#!/usr/bin/env python3
"""
mmsnd_tool.py -- descompilador/compilador del bytecode de sonido de
Mad Mix Game (Topo Soft, 1987), driver PSG credito a "COMILONAS".

Formato bytecode (ver src/FINDINGS.md, seccion "RESUELTO: los 15
comandos del bytecode del driver de sonido"):
  - byte < 0x80 -> valor de NOTA (se suma a una transposicion por canal
    y se busca en la tabla de 96 palabras de RM_TABLE_C8DE, $C8DE en
    madmix1.asm, que da el periodo de tono real del PSG). La duracion
    en tics NO va en este byte -- la fijan los comandos SET_DURATION/
    SET_DURATION_MULTI por separado.
  - byte >= 0x80 -> COMANDO (0x80-0x8E, 15 comandos), cada uno con 0,
    1 o un numero variable de bytes de parametro (ver OPS abajo).

Los 13 subpatrones compartidos (data/sound/*.spt, ver FINDINGS.md) usan
el MISMO bytecode -- estos comandos funcionan sin cambios sobre ellos,
la unica diferencia es la extension del fichero (.spt en vez de .snd)
para no mezclarlos con los 16 scripts reales de evento/musica.

Uso:
  py mmsnd_tool.py disasm fichero.snd [fichero.txt]
  py mmsnd_tool.py asm fichero.txt [fichero.snd]
  py mmsnd_tool.py roundtrip fichero.snd     (verifica disasm+asm=identico)
  py mmsnd_tool.py roundtrip-all carpeta/     (roundtrip de todos los .snd/.spt de la carpeta)

Autor de esta herramienta: Rafael Eduardo Martín Candial
"""

import sys
import os

# (nombre, num_parametros) -- num_parametros: entero fijo, o None para
# el comando 6 (variable: 1 byte de cuenta + esa cantidad de bytes)
OPS = {
    0x80: ("SET_VOLUME", 1),
    0x81: ("SET_MIXER", 1),
    0x82: ("LOOP", 0),
    0x83: ("SET_DURATION", 1),
    0x84: ("HOLD", 0),
    0x85: ("SET_TEMPO", 1),
    0x86: ("SET_DURATION_MULTI", None),
    0x87: ("SET_INSTRUMENT", 1),
    0x88: ("SET_ENVELOPE", 1),
    0x89: ("SET_ENVELOPE_SHAPE", 1),
    0x8A: ("SET_FLAGS", 1),
    0x8B: ("RESET_SHARED_ENVELOPE", 0),
    0x8C: ("CALL_SUBPATTERN", 1),
    0x8D: ("RETURN_SUBPATTERN", 0),
    0x8E: ("SET_CHANNEL_STATE", 1),
}
NAME_TO_OP = {name: op for op, (name, _) in OPS.items()}


class DecodeError(Exception):
    pass


def disassemble(data: bytes) -> list[str]:
    lines = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b < 0x80:
            lines.append(f"NOTE 0x{b:02X}")
            i += 1
            continue
        if b not in OPS:
            raise DecodeError(f"offset {i}: byte 0x{b:02X} no es un comando valido (0x80-0x8E)")
        name, nparams = OPS[b]
        i += 1
        if nparams == 0:
            lines.append(name)
        elif nparams == 1:
            if i >= n:
                raise DecodeError(f"offset {i-1}: {name} espera 1 byte de parametro, fichero truncado")
            lines.append(f"{name} 0x{data[i]:02X}")
            i += 1
        else:
            # comando 6: 1 byte de cuenta + esa cantidad de bytes
            if i >= n:
                raise DecodeError(f"offset {i-1}: {name} espera byte de cuenta, fichero truncado")
            count = data[i]
            i += 1
            if i + count > n:
                raise DecodeError(f"offset {i-1}: {name} cuenta={count} se sale del fichero")
            params = data[i:i+count]
            i += count
            hexbytes = " ".join(f"0x{x:02X}" for x in params)
            lines.append(f"{name} 0x{count:02X} {hexbytes}".rstrip())
    return lines


def assemble(lines: list[str]) -> bytes:
    out = bytearray()
    for raw in lines:
        line = raw.split(";", 1)[0].strip()  # permite comentarios con ;
        if not line:
            continue
        parts = line.split()
        mnem = parts[0]
        args = parts[1:]
        if mnem == "NOTE":
            if len(args) != 1:
                raise DecodeError(f"linea invalida (NOTE espera 1 valor): {raw!r}")
            val = int(args[0], 0)
            if not (0 <= val < 0x80):
                raise DecodeError(f"NOTE fuera de rango (0-0x7F): {raw!r}")
            out.append(val)
            continue
        if mnem not in NAME_TO_OP:
            raise DecodeError(f"mnemonico desconocido: {mnem!r} (linea: {raw!r})")
        op = NAME_TO_OP[mnem]
        name, nparams = OPS[op]
        out.append(op)
        if nparams == 0:
            if args:
                raise DecodeError(f"{name} no lleva parametros (linea: {raw!r})")
        elif nparams == 1:
            if len(args) != 1:
                raise DecodeError(f"{name} espera 1 parametro (linea: {raw!r})")
            out.append(int(args[0], 0) & 0xFF)
        else:
            if len(args) < 1:
                raise DecodeError(f"{name} espera byte de cuenta + N bytes (linea: {raw!r})")
            count = int(args[0], 0)
            rest = args[1:]
            if len(rest) != count:
                raise DecodeError(
                    f"{name}: cuenta={count} pero hay {len(rest)} bytes de datos (linea: {raw!r})"
                )
            out.append(count & 0xFF)
            for a in rest:
                out.append(int(a, 0) & 0xFF)
    return bytes(out)


def warning_banner(inpath: str) -> str:
    # .spt (subpatrones compartidos) los indexa TABLA_SUBPATRONES_PSG en
    # madmix1.asm; .snd (scripts de evento/musica reales) los indexa
    # LEVELCYCLE_RESOURCE_TABLE en madmix_scr.asm -- consumidor distinto
    # segun el tipo de fichero, mismo riesgo de desplazamiento de direccion.
    if inpath.endswith(".spt"):
        consumer = "TABLA_SUBPATRONES_PSG (madmix1.asm)"
    else:
        consumer = "LEVELCYCLE_RESOURCE_TABLE (madmix_scr.asm)"
    return (
        "; !!! AVISO -- LEE ESTO ANTES DE EDITAR !!!\n"
        "; Ingenieria inversa, herramientas y documentacion de este proyecto: Rafael Eduardo Martin Candial\n"
        "; Este fichero se compila con INCBIN a una direccion FIJA, calcada del\n"
        "; binario original de 1987. Puedes cambiar valores de una instruccion ya\n"
        "; existente (otra nota, duracion, instrumento...) sin ningun problema.\n"
        "; NO añadas ni quites lineas, y NO cambies la cuenta de un\n"
        "; SET_DURATION_MULTI: si el numero de bytes total cambia al reensamblar,\n"
        "; TODO lo que va detras en madmix1.asm se desplaza de direccion, y\n"
        f"; {consumer} sigue apuntando a la\n"
        "; direccion VIEJA -- el juego compilaria sin error pero saltaria a sitios\n"
        "; incorrectos en tiempo de ejecucion. Ver FINDINGS.md / README.md.\n"
    )


def cmd_disasm(args):
    inpath = args[0]
    with open(inpath, "rb") as f:
        data = f.read()
    lines = disassemble(data)
    text = (
        warning_banner(inpath)
        + f"; {os.path.basename(inpath)} ({len(data)} bytes)\n"
        + "\n".join(lines) + "\n"
    )
    if len(args) > 1:
        with open(args[1], "w", newline="\n", encoding="utf-8") as f:
            f.write(text)
        print(f"escrito {args[1]} ({len(lines)} instrucciones)")
    else:
        sys.stdout.write(text)


def cmd_asm(args):
    inpath = args[0]
    with open(inpath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    data = assemble(lines)
    if len(args) > 1:
        with open(args[1], "wb") as f:
            f.write(data)
        print(f"escrito {args[1]} ({len(data)} bytes)")
    else:
        sys.stdout.buffer.write(data)


def cmd_roundtrip(path):
    with open(path, "rb") as f:
        original = f.read()
    lines = disassemble(original)
    rebuilt = assemble(lines)
    if rebuilt == original:
        print(f"OK   {os.path.basename(path)}: {len(original)} bytes, {len(lines)} instrucciones, identico")
        return True
    else:
        print(f"FAIL {os.path.basename(path)}: {len(original)} bytes originales, {len(rebuilt)} bytes tras roundtrip")
        n = min(len(original), len(rebuilt))
        for i in range(n):
            if original[i] != rebuilt[i]:
                print(f"  primera diferencia en offset {i}: original=0x{original[i]:02X} rebuilt=0x{rebuilt[i]:02X}")
                break
        return False


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    rest = sys.argv[2:]
    try:
        if cmd == "disasm":
            cmd_disasm(rest)
        elif cmd == "asm":
            cmd_asm(rest)
        elif cmd == "roundtrip":
            ok = cmd_roundtrip(rest[0])
            sys.exit(0 if ok else 1)
        elif cmd == "roundtrip-all":
            folder = rest[0]
            allok = True
            for fn in sorted(os.listdir(folder)):
                if fn.endswith(".snd") or fn.endswith(".spt"):
                    ok = cmd_roundtrip(os.path.join(folder, fn))
                    allok = allok and ok
            sys.exit(0 if allok else 1)
        else:
            print(__doc__)
            sys.exit(1)
    except DecodeError as e:
        print(f"ERROR: {e}")
        sys.exit(2)


if __name__ == "__main__":
    main()
