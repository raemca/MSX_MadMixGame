#!/usr/bin/env python3
"""
mmsnd_render.py -- renderiza a WAV un script de sonido de Mad Mix
Game, emulando el PSG AY-3-8910 + el interprete del bytecode propio
del driver (ver src/FINDINGS.md).

ADVERTENCIA DE PRECISION: la mecanica del interprete (que hace cada
comando, que tablas consulta) esta verificada leyendo el codigo real.
Lo que NO esta verificado en vivo es: la frecuencia de tick real
(se asume 50 Hz, PAL), y el detalle fino de las dos fases de
envolvente de volumen y las tres fases de envolvente/deslizamiento de
tono (la mecanica de recarga esta trazada, pero no escuchada contra
el juego real). El resultado es una RECONSTRUCCION RAZONADA, no una
emulacion certificada -- sirve para juzgar de oido si la lectura del
bytecode tiene sentido musical, no como referencia perfecta.

Los 16 scripts reales viven en src/data/sound/snd/ (SCRIPT_ADDR); los
13 subpatrones compartidos, en src/data/sound/spt/ (SUBPATTERN_ADDR)
-- mismo bytecode, misma funcion render/render-all, solo cambia el
manifiesto de direcciones usado internamente (detectado por nombre de
fichero).

Uso (rutas relativas a la raiz del repositorio):
  py tools/mmsnd_render.py render fichero.snd salida.wav [opciones]
  py tools/mmsnd_render.py render src/data/sound/spt/00_subpatron00_cb9c.spt salida.wav [opciones]
  py tools/mmsnd_render.py render-all src/data/sound/snd/ carpeta_salida/ [opciones]
  py tools/mmsnd_render.py render-all src/data/sound/spt/ carpeta_salida/ [opciones]
  py tools/mmsnd_render.py render-chord fichero.snd salida.wav 0,7,14 [opciones]
      -- mezcla varias "voces" que arrancan en offsets distintos DENTRO
      del mismo fichero, cada una parando en su propio limite (ver
      FINDINGS.md: asi carga IML_900F el soniquete de inicio de nivel
      en los 3 canales del PSG a la vez, offsets 0/+7/+14 dentro de
      10_evt10_inicio_nivel_cef0.snd)

Opciones:
  --rate HZ        frecuencia de muestreo del WAV (defecto 44100)
  --tickhz HZ       frecuencia de tick del driver (defecto 50, PAL)
  --max-ticks N     limite de seguridad de ticks a renderizar (defecto 300)
  --clock HZ        reloj del PSG (defecto 1789772, estandar MSX)

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""

import sys
import os
import struct
import wave

sys.path.insert(0, os.path.dirname(__file__))
from mmsnd_tool import OPS  # noqa: E402

ENGINE_BASE = 0xC8DE
ENGINE_FILE = os.path.join(os.path.dirname(__file__), "..", "src", "data", "sound", "_engine_tables.bin")

# Manifest: nombre de fichero real -> direccion base (ver FINDINGS.md,
# "RESUELTO: $6128 es el indice de efecto de sonido")
SCRIPT_ADDR = {
    "00_script_cdcb.snd": 0xCDCB,
    "01_script_cdff.snd": 0xCDFF,
    "02_boot_ch2_ce0c.snd": 0xCE0C,
    "03_evt09_trampilla_transicion_ce5a.snd": 0xCE5A,
    "04_evt04_disparo_avion_ce72.snd": 0xCE72,
    "05_evt07_pista_ce7e.snd": 0xCE7E,
    "06_evt01_bola_clavada_ce8b.snd": 0xCE8B,
    "07_evt11_bola_poder_ce9c.snd": 0xCE9C,
    "08_evt06_planta_clavada_ceac.snd": 0xCEAC,
    "09_evt00_bolita_cee2.snd": 0xCEE2,
    "10_evt10_inicio_nivel_cef0.snd": 0xCEF0,
    "11_evt08_arma_modo_cf07.snd": 0xCF07,
    "12_evt13_fin_modo_cf27.snd": 0xCF27,
    "13_evt05_mariquita_repone_cf44.snd": 0xCF44,
    "14_evt02_flecha_cf62.snd": 0xCF62,
    "15_evt03_modo_especial_cf70.snd": 0xCF70,
}

# Manifest de los 13 subpatrones compartidos (data/sound/spt/, ver
# FINDINGS.md "los 13 subpatrones, extraidos a .spt"). A diferencia de
# los scripts de SCRIPT_ADDR, estos YA viven dentro de _engine_tables.bin
# (caen en 0xCB9C-0xCDCB, parte del bloque base) -- no se pegan aparte
# en load_memory(), solo hace falta su direccion de inicio para poder
# renderizarlos SUELTOS (fuera de una llamada real via CALL_SUBPATTERN).
SUBPATTERN_ADDR = {
    "00_subpatron00_cb9c.spt": 0xCB9C,
    "01_subpatron01_cbd3.spt": 0xCBD3,
    "02_subpatron02_cc1c.spt": 0xCC1C,
    "03_subpatron03_cc45.spt": 0xCC45,
    "04_subpatron04_cc96.spt": 0xCC96,
    "05_subpatron05_ccd0.spt": 0xCCD0,
    "06_subpatron06_ccef.spt": 0xCCEF,
    "07_subpatron07_cd16.spt": 0xCD16,
    "08_subpatron08_cd3f.spt": 0xCD3F,
    "09_subpatron09_cd76.spt": 0xCD76,
    "10_subpatron10_cd91.spt": 0xCD91,
    "11_subpatron11_cdab.spt": 0xCDAB,
    "12_subpatron12_cbb0.spt": 0xCBB0,
}


SCRIPT_END = {}  # rellenado por load_memory(): nombre -> direccion de fin (exclusiva)


def load_memory():
    """Construye un espacio de direcciones unico: _engine_tables.bin
    (0xC8DE en adelante) + los 16 scripts reales pegados en orden de
    direccion -- asi CALL_SUBPATTERN y las tablas de instrumento
    resuelven con aritmetica de offset simple, sin casos especiales."""
    with open(ENGINE_FILE, "rb") as f:
        engine = f.read()
    scripts_dir = os.path.join(os.path.dirname(__file__), "..", "src", "data", "sound", "snd")
    parts = [(addr, name) for name, addr in SCRIPT_ADDR.items()]
    parts.sort()
    buf = bytearray(engine)
    expected = ENGINE_BASE + len(engine)
    for addr, name in parts:
        if addr != expected:
            raise RuntimeError(f"hueco/solape inesperado antes de {name} (direccion {addr:04X}, esperaba {expected:04X})")
        with open(os.path.join(scripts_dir, name), "rb") as f:
            data = f.read()
        buf += data
        expected += len(data)
        SCRIPT_END[name] = expected
    return bytes(buf), ENGINE_BASE


class Memory:
    def __init__(self, buf, base):
        self.buf = buf
        self.base = base
        self.end = base + len(buf)

    def __getitem__(self, addr):
        if not (self.base <= addr < self.end):
            raise IndexError(f"lectura fuera de rango: ${addr:04X}")
        return self.buf[addr - self.base]

    def word(self, addr):
        return self[addr] | (self[addr + 1] << 8)


# --- Tablas fijas dentro de _engine_tables.bin, offsets conocidos ---
PITCH_TABLE_ADDR = 0xC8DE       # 96 palabras, nota+transposicion -> periodo de tono
CMD_JUMP_TABLE_ADDR = 0xC99E    # no hace falta para el renderizador (ya tenemos OPS)
TRANSPOSE_TABLE_ADDR = 0xCA67   # 3 bytes, uno por canal (verificado: 00 00 00 en el original)
INSTRUMENT_TABLE_ADDR = 0xCA6A  # 16 entradas x 15 bytes
ENV_SHAPE_TABLE_ADDR = 0xCB5A   # 4 entradas x 6 bytes
SUBPATTERN_TABLE_ADDR = 0xCB72  # 21 punteros x 2 bytes (entradas 13-20 repiten la 0)


class Channel:
    """Estado de una ranura de canal (46 bytes en el original, aqui
    como objeto Python con los mismos campos por nombre)."""

    def __init__(self, start_addr):
        self.orig_ptr = start_addr    # +$00/+$01
        self.read_ptr = start_addr    # +$02/+$03
        self.ticks_left = 0           # +$04/+$05
        self.duration = 0             # +$06/+$07
        self.mixer_mask = 0           # +$08 (bit0=tono activo, bit3=ruido activo)
        self.volume = 0               # +$09
        self.tone_period = 0          # +$0A/+$0B
        # Envolvente de volumen (2 fases secuenciales, ver FINDINGS.md
        # "renderizador de audio" -- RM_C579/RM_C586/RM_C699):
        #   fase completa = espera vol_delay ticks, aplica vol_delta al
        #   acumulador, repite vol_repeat veces; luego pasa a la fase 2.
        self.vol_delay_left = [0, 0]      # +$0C/+$0D (cuenta atras hasta el proximo paso)
        self.vol_repeat_left = [0, 0]     # +$0E/+$0F (pasos que quedan, decrece 1/paso)
        self.vol_delay_reload = [0, 0]    # instrumento b[10]/b[11]
        self.vol_repeat_reload = [0, 0]   # instrumento b[0]/b[1]
        self.vol_delta = [0, 0]           # instrumento b[5]/b[6]
        # Envolvente/deslizamiento de tono (3 fases, mismo patron,
        # RM_C5BA/RM_C5C7/RM_C6B1 -- delta CON SIGNO, a diferencia del
        # de volumen):
        self.pitch_delay_left = [0, 0, 0]     # +$10/+$11/+$12
        self.pitch_repeat_left = [0, 0, 0]    # +$13/+$14/+$15
        self.pitch_delay_reload = [0, 0, 0]   # instrumento b[12]/b[13]/b[14]
        self.pitch_repeat_reload = [0, 0, 0]  # instrumento b[2]/b[3]/b[4]
        self.pitch_delta = [0, 0, 0]          # instrumento b[7]/b[8]/b[9] (con signo)
        self.vol_accum = 0             # +$2A
        self.pitch_accum = 0            # +$2B/+$2C (16 bits, con signo)
        self.flags = 0                   # +$2D
        self.return_addr = None            # $CA61+canal*2 (CALL/RETURN_SUBPATTERN)
        self.instrument_raw = bytes(15)  # copia de instrumento activo ($CA6A+n*15)
        self.channel_index = 0
        self.in_subpattern = False
        self.script_end = None  # limite de "fin natural" (no existe en el original --
                                 # alli lo interrumpe LOAD_RESOURCE_SLOT_EMPTY desde fuera)
        self.loop_hit = False  # se pone a True dentro de run_commands al ejecutar LOOP
                                # -- marca "ya se completo una vuelta entera", para que el
                                # renderizador aislado pueda parar ahi en vez de repetir
                                # (comparar read_ptr==orig_ptr tras cada tic no sirve: tras
                                # un LOOP se siguen leyendo comandos sin pausa hasta la
                                # siguiente nota/HOLD, asi que el puntero ya no coincide
                                # exacto con el inicio en el instante en que se muestrea)


class Interpreter:
    def __init__(self, mem: Memory, tick_hz=50):
        self.mem = mem
        self.tick_hz = tick_hz
        self.tempo_mult = 0  # ($C9BD): multiplicador de duracion, fijado por SET_TEMPO
        # SET_CHANNEL_STATE escribe en $CA67+canal (la tabla de
        # transposicion) en tiempo real -- Memory es de solo lectura
        # (viene de un fichero), asi que el valor "en vivo" vive aparte
        # y se consulta antes que la tabla original.
        self.transpose_override = {}

    def read_byte(self, addr):
        return self.mem[addr]

    def note_to_period(self, note, channel_idx):
        if channel_idx in self.transpose_override:
            transpose = self.transpose_override[channel_idx]
        else:
            transpose = self.mem[TRANSPOSE_TABLE_ADDR + channel_idx]
        idx = (note + transpose) & 0xFF
        return self.mem.word(PITCH_TABLE_ADDR + idx * 2)

    def load_instrument(self, ch: Channel, idx):
        """Copia los 15 bytes del instrumento (ver FINDINGS.md,
        mapeo retrazado byte a byte contra RM_C699/RM_C6B1):
          b[0]/b[1]   = repeticiones fase1/fase2 de volumen
          b[2..4]     = repeticiones fase1/2/3 de tono
          b[5]/b[6]   = delta fase1/fase2 de volumen
          b[7..9]     = delta (con signo) fase1/2/3 de tono
          b[10]/b[11] = retardo entre pasos, fase1/fase2 de volumen
          b[12..14]   = retardo entre pasos, fase1/2/3 de tono
        """
        base = INSTRUMENT_TABLE_ADDR + idx * 15
        b = bytes(self.mem[base + i] for i in range(15))
        ch.instrument_raw = b
        ch.vol_repeat_reload = [b[0], b[1]]
        ch.pitch_repeat_reload = [b[2], b[3], b[4]]
        ch.vol_delta = [b[5], b[6]]

        def signed(x):
            return x - 256 if x >= 128 else x

        ch.pitch_delta = [signed(b[7]), signed(b[8]), signed(b[9])]
        ch.vol_delay_reload = [b[10], b[11]]
        ch.pitch_delay_reload = [b[12], b[13], b[14]]
        ch.flags &= ~0b11

    def relatch_envelopes(self, ch: Channel):
        """RM_C53A/RM_C699/RM_C6B1: al empezar una nota nueva, recarga
        los contadores en vivo desde los valores del instrumento y
        pone a cero los acumuladores."""
        ch.vol_delay_left = list(ch.vol_delay_reload)
        ch.vol_repeat_left = list(ch.vol_repeat_reload)
        ch.pitch_delay_left = list(ch.pitch_delay_reload)
        ch.pitch_repeat_left = list(ch.pitch_repeat_reload)
        ch.vol_accum = 0
        ch.pitch_accum = 0

    def step_envelope(self, delay_left, repeat_left, delay_reload, delta, accum, signed16=False):
        """Un tic de una envolvente secuencial de N fases (ver
        FINDINGS.md): procesa fases en orden, se detiene en la
        primera que este "activa" (contando el retardo o aplicando un
        paso); una fase se salta solo si ya esta agotada del todo."""
        for i in range(len(delay_left)):
            if delay_left[i] > 0:
                delay_left[i] -= 1
                return accum
            if repeat_left[i] > 0:
                repeat_left[i] -= 1
                accum += delta[i]
                if signed16:
                    accum = ((accum + 0x8000) & 0xFFFF) - 0x8000
                else:
                    accum &= 0xFF
                delay_left[i] = delay_reload[i]
                return accum
            # fase agotada (retardo y repeticiones a 0) -> prueba la siguiente
        return accum

    def apply_envelopes(self, ch: Channel):
        ch.vol_accum = self.step_envelope(
            ch.vol_delay_left, ch.vol_repeat_left, ch.vol_delay_reload, ch.vol_delta, ch.vol_accum)
        ch.pitch_accum = self.step_envelope(
            ch.pitch_delay_left, ch.pitch_repeat_left, ch.pitch_delay_reload, ch.pitch_delta,
            ch.pitch_accum, signed16=True)

    def run_commands(self, ch: Channel):
        """Procesa comandos (bytes >=0x80) hasta encontrar una NOTA
        (<0x80), que arranca la nota y termina el lote. Devuelve
        False si el puntero se sale del espacio de direcciones
        valido (fin natural del script)."""
        while True:
            if (not ch.in_subpattern) and ch.script_end is not None and ch.read_ptr >= ch.script_end:
                # fin natural (heuristica del renderizador aislado: en el
                # juego real esto lo corta LOAD_RESOURCE_SLOT_EMPTY desde
                # fuera, no hay marcador de "fin" explicito en el bytecode)
                return False
            try:
                b = self.read_byte(ch.read_ptr)
            except IndexError:
                return False
            if b < 0x80:
                # NOTA: resuelve el periodo de tono base y avanza
                note = b
                ch.read_ptr += 1
                ch.tone_period = self.note_to_period(note, ch.channel_index)
                # cierre de nota (RM_C53A/RM_C699/RM_C6B1/RM_C552): relatch
                # de envolventes y recarga del contador de tics
                self.relatch_envelopes(ch)
                ch.ticks_left = ch.duration
                return True
            name, nparams = OPS[b]
            addr = ch.read_ptr
            ch.read_ptr += 1
            if name == "SET_VOLUME":
                ch.volume = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
            elif name == "SET_MIXER":
                ch.mixer_mask = self.read_byte(ch.read_ptr) & 0x09
                ch.read_ptr += 1
            elif name == "LOOP":
                ch.read_ptr = ch.orig_ptr
                ch.loop_hit = True
            elif name == "SET_DURATION":
                v = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                ch.duration = (v * self.tempo_mult) & 0xFFFF
            elif name == "HOLD":
                ch.ticks_left = ch.duration
                return True
            elif name == "SET_TEMPO":
                v = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                divisor = (v * 0x10) & 0xFFFF
                # RM_C8A2: BC(=$0BB8=3000) / DE(=divisor) -> cociente en BC,
                # se guarda el byte bajo del COCIENTE (no el resto)
                self.tempo_mult = (0x0BB8 // divisor) & 0xFF if divisor else 0xFFFF
            elif name == "SET_DURATION_MULTI":
                count = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                total = 0
                for _ in range(count):
                    vb = self.read_byte(ch.read_ptr)
                    ch.read_ptr += 1
                    total = (total + vb * self.tempo_mult) & 0xFFFF
                ch.duration = total
            elif name == "SET_INSTRUMENT":
                idx = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                self.load_instrument(ch, idx & 0x1F)
            elif name == "SET_ENVELOPE":
                ch.read_ptr += 1  # parametro consumido, tabla fija global no modelada aqui
            elif name == "SET_ENVELOPE_SHAPE":
                ch.read_ptr += 1
            elif name == "SET_FLAGS":
                v = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                ch.flags |= v
            elif name == "RESET_SHARED_ENVELOPE":
                pass
            elif name == "CALL_SUBPATTERN":
                idx = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                ch.return_addr = ch.read_ptr
                ch.in_subpattern = True
                target = self.mem.word(SUBPATTERN_TABLE_ADDR + idx * 2)
                ch.read_ptr = target
            elif name == "RETURN_SUBPATTERN":
                if ch.return_addr is None:
                    return False
                ch.read_ptr = ch.return_addr
                ch.in_subpattern = False
            elif name == "SET_CHANNEL_STATE":
                v = self.read_byte(ch.read_ptr)
                ch.read_ptr += 1
                self.transpose_override[ch.channel_index] = v
            else:
                raise RuntimeError(f"comando no manejado: {name}")

    def tick(self, ch: Channel):
        if ch.ticks_left > 0:
            ch.ticks_left -= 1
            self.apply_envelopes(ch)
            return True
        ok = self.run_commands(ch)
        if ok:
            # RM_C552 cae directo en RM_C564 en el original (sin salto
            # de por medio): el primer tic de la nota nueva YA decrementa
            # el contador y aplica un paso de envolvente, no espera al
            # tic siguiente.
            if ch.ticks_left > 0:
                ch.ticks_left -= 1
            self.apply_envelopes(ch)
        return ok


def note_freq(period, clock):
    if period == 0:
        return 0.0
    return clock / (16.0 * period)


# Curva -3dB/paso (estandar para el generador de volumen del AY-3-8910/
# compatibles): nivel 0 es silencio real, niveles 1-15 son audibles
# (nunca redondean a 0). La tabla anterior (entera, /16) redondeaba a 0
# los niveles 1-6, silenciando notas que en el hardware real si suenan
# (encontrado al investigar 07_evt11_bola_poder_ce9c.wav, que usa
# volumen efectivo 6 y sonaba mudo).
VOLUME_TABLE = [0.0] + [2 ** ((i - 15) / 2.0) for i in range(1, 16)]
VOLUME_TABLE = [int(round(v * 255)) for v in VOLUME_TABLE]


class Voice:
    """Un canal + su propio estado de osciladores (cada voz de un
    acorde necesita su fase de tono y su LFSR de ruido propios)."""

    def __init__(self, start_addr, script_end, channel_index=0):
        self.ch = Channel(start_addr)
        self.ch.channel_index = channel_index
        self.ch.script_end = script_end
        self.phase_acc = 0.0
        self.noise_lfsr = 1
        self.noise_counter = 0.0
        self.noise_bit = 0
        self.alive = True


def synth_tick(interp: Interpreter, voice: Voice, n, rate, clock, noise_period=16):
    """Avanza un tic para una voz y devuelve n muestras firmadas
    (-64..64, deja margen para mezclar varias voces sin recortar).
    Si la voz ya termino (fin natural del script), devuelve silencio."""
    if voice.alive:
        voice.alive = interp.tick(voice.ch)
    if not voice.alive:
        return [0] * n
    ch = voice.ch
    period = (ch.tone_period + ch.pitch_accum) & 0xFFFF
    freq = note_freq(period, clock)
    eff_volume = (ch.volume + ch.vol_accum) & 0x0F
    tone_on = bool(ch.mixer_mask & 0x01)
    noise_on = bool(ch.mixer_mask & 0x08)
    vol = VOLUME_TABLE[eff_volume] // 4  # /4: deja margen para sumar hasta 3 voces sin recortar
    out = []
    for _ in range(n):
        tone_high = False
        if tone_on and freq > 0:
            voice.phase_acc += freq / rate
            voice.phase_acc %= 1.0
            tone_high = voice.phase_acc < 0.5
        noise_high = True
        if noise_on:
            voice.noise_counter += 1
            if voice.noise_counter >= noise_period:
                voice.noise_counter = 0.0
                bit0 = voice.noise_lfsr & 1
                bit3 = (voice.noise_lfsr >> 3) & 1
                feedback = bit0 ^ bit3
                voice.noise_lfsr = (voice.noise_lfsr >> 1) | (feedback << 16)
                voice.noise_bit = voice.noise_lfsr & 1
            noise_high = bool(voice.noise_bit)
        if not tone_on and not noise_on:
            # Silencio real: ni tono ni ruido activos (RM_C82E con
            # ambos bits a 0). Antes esto seguia restando (vol//2)
            # usando el volumen base aunque no sonara nada, dejando un
            # offset DC negativo constante en vez de silencio -- se oia
            # como un "ruidito"/zumbido en vez de silencio verdadero
            # (encontrado en 02_boot_ch2_ce0c.wav, que tiene ~11s de
            # silencio real al principio segun el bytecode).
            out.append(0)
        else:
            out_high = (tone_high or not tone_on) and (noise_high or not noise_on)
            level = vol if out_high else 0
            out.append(level - (vol // 2))
    return out


def _write_wav(out_path, samples, rate):
    with wave.open(out_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(rate)
        frames = bytes((max(-128, min(127, s)) + 128) & 0xFF for s in samples)
        w.writeframes(frames)


def render(script_path, out_path, rate=44100, tick_hz=50, max_ticks=300, clock=1789772):
    buf, base = load_memory()
    mem = Memory(buf, base)
    name = os.path.basename(script_path)
    if name in SCRIPT_ADDR:
        start = SCRIPT_ADDR[name]
        end = SCRIPT_END[name]
    elif name in SUBPATTERN_ADDR:
        # los subpatrones ya viven dentro de _engine_tables.bin (no se
        # pegan aparte en load_memory()) -- "end" solo hace falta como
        # limite de seguridad, el final real lo marca su propio
        # RETURN_SUBPATTERN (ver run_commands: return_addr=None -> stop)
        start = SUBPATTERN_ADDR[name]
        end = start + os.path.getsize(script_path)
    else:
        raise RuntimeError(f"{name} no esta en SCRIPT_ADDR ni en SUBPATTERN_ADDR (direccion desconocida)")

    interp = Interpreter(mem, tick_hz)
    voice = Voice(start, end)
    samples = []
    samples_per_tick = rate / tick_hz
    n = int(round(samples_per_tick))

    ticks = 0
    while ticks < max_ticks and voice.alive:
        before = voice.alive
        chunk = synth_tick(interp, voice, n, rate, clock)
        if before and not voice.alive:
            break
        samples.extend(s * 4 for s in chunk)  # deshace el /4 de margen: aqui solo hay 1 voz
        ticks += 1
        if voice.ch.loop_hit:
            # LOOP ya se ejecuto una vez: una vuelta entera capturada,
            # parar aqui en vez de repetir (ver Channel.loop_hit -- mas
            # fiable que comparar read_ptr==start tic a tic, que se
            # puede saltar si tras el LOOP se leen varios comandos sin
            # pausa antes de la siguiente nota/HOLD)
            break

    _write_wav(out_path, samples, rate)
    return len(samples) / rate


def render_chord(script_path, offsets, out_path, rate=44100, tick_hz=50, max_ticks=300, clock=1789772):
    """Renderiza varias 'voces' que arrancan en offsets distintos
    DENTRO del mismo fichero (ver FINDINGS.md -- IML_900F instala el
    soniquete de inicio de nivel en los 3 canales a la vez, cada uno
    7 bytes mas adentro que el anterior) y las mezcla en un solo WAV,
    cada una parando en su propio limite (el siguiente offset, o el
    final del fichero para la ultima)."""
    buf, base = load_memory()
    mem = Memory(buf, base)
    name = os.path.basename(script_path)
    if name not in SCRIPT_ADDR:
        raise RuntimeError(f"{name} no esta en el manifiesto SCRIPT_ADDR (direccion desconocida)")
    start = SCRIPT_ADDR[name]
    file_end = SCRIPT_END[name]
    offs = sorted(offsets)

    interp = Interpreter(mem, tick_hz)
    voices = []
    for i, off in enumerate(offs):
        end = start + offs[i + 1] if i + 1 < len(offs) else file_end
        voices.append(Voice(start + off, end, channel_index=i))

    samples_per_tick = rate / tick_hz
    n = int(round(samples_per_tick))
    mixed = []
    ticks = 0
    while ticks < max_ticks and any(v.alive for v in voices):
        chunk = [0] * n
        for v in voices:
            vs = synth_tick(interp, v, n, rate, clock)
            for i in range(n):
                chunk[i] += vs[i]
        mixed.extend(chunk)
        ticks += 1

    _write_wav(out_path, mixed, rate)
    return len(mixed) / rate


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    opts = {"rate": 44100, "tick_hz": 50, "max_ticks": 300, "clock": 1789772}
    args = sys.argv[2:]
    positional = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--rate":
            opts["rate"] = int(args[i + 1]); i += 2
        elif a == "--tickhz":
            opts["tick_hz"] = int(args[i + 1]); i += 2
        elif a == "--max-ticks":
            opts["max_ticks"] = int(args[i + 1]); i += 2
        elif a == "--clock":
            opts["clock"] = int(args[i + 1]); i += 2
        else:
            positional.append(a); i += 1

    if cmd == "render":
        inpath, outpath = positional[0], positional[1]
        secs = render(inpath, outpath, **opts)
        print(f"escrito {outpath} ({secs:.2f} s)")
    elif cmd == "render-chord":
        inpath, outpath, offsets_str = positional[0], positional[1], positional[2]
        offsets = [int(x, 0) for x in offsets_str.split(",")]
        secs = render_chord(inpath, offsets, outpath, **opts)
        print(f"escrito {outpath} ({secs:.2f} s, {len(offsets)} voces)")
    elif cmd == "render-all":
        indir, outdir = positional[0], positional[1]
        os.makedirs(outdir, exist_ok=True)
        for fn in sorted(os.listdir(indir)):
            if (fn.endswith(".snd") and fn in SCRIPT_ADDR) or (fn.endswith(".spt") and fn in SUBPATTERN_ADDR):
                outp = os.path.join(outdir, os.path.splitext(fn)[0] + ".wav")
                try:
                    secs = render(os.path.join(indir, fn), outp, **opts)
                    print(f"OK   {fn} -> {outp} ({secs:.2f} s)")
                except Exception as e:
                    print(f"FAIL {fn}: {e}")
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
