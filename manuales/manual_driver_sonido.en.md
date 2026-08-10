# Sound driver manual — Mad Mix Game (MSX1, AY-3-8910 PSG)

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Source: `madmix1.asm`, region `$C4A0`-`$CF8D` (2912 bytes: code +
> data). Real credit found in the game's credits screen:
> **"MUSIC-A BY: COMILONAS"**. For the chronicle of how each piece
> was discovered, see `FINDINGS.md`; this document assumes everything
> is already resolved and explains the final result in an orderly way.

## 1. What this is and what it is NOT

This driver **is not** an MSX standard or something provided by the
machine's BASIC or BIOS — it is a custom-built bytecode interpreter,
Topo Soft's own, made for this game. MSX-BASIC has its own `PLAY`
instruction to play music, with its own text format ("MML"); this
driver has absolutely nothing to do with that, nor with any known
tracker format of the era. It is a 100% original implementation,
designed and optimized for this specific game's needs.

Nor is it "a generic resource manager", which was the first working
hypothesis in earlier sessions of this project (which is why some
labels were once called `LOAD_RESOURCE_SLOT_ALLOC`/
`LOAD_RESOURCE_SLOT_EMPTY`, today `INSTALAR_RECURSO_SONIDO`/
`VACIAR_CANALES_SONIDO`) — it is, specifically, the sound and music
player.

## 2. The hardware behind it: the AY-3-8910 PSG

Before getting into the driver, it's necessary to understand what the
real sound chip can -- and cannot -- do, because the driver's entire
design is a response to those limitations.

The AY-3-8910 (the "PSG", *Programmable Sound Generator*) has **3
independent tone channels**, each with:

- A **tone period** (12 bits): an integer that controls the
  frequency of a square wave. The relationship is
  `frequency = chip_clock / (16 × period)` — the smaller the period,
  the higher the note. The chip does not understand "notes", "C",
  "A440" or anything like that: only periods, plain integers.
- A **volume** (4 bits, 0-15).
- A **noise generator** shared between the 3 channels (useful for
  percussion/effects, not for tone) — with its own **noise
  period** (register 6), also shared.
- A **hardware envelope generator** (period + shape), which can
  replace a channel's fixed volume with an automatic ramp — a real
  chip mechanism. This driver **does not use it**
  directly: instead it implements its own software envelopes
  (§6.7 and §8), including a noise one that also writes
  register 6's period in software, tick by tick.

All of this is controlled by writing to chip registers through two
I/O ports (`$A0`=register number, `$A1`=value) — see
`VOLCAR_REGISTROS_PSG` (§4), the final dump of each tick.

**The real problem this driver solves**: the Z80 has no hardware
multiplication or division. Computing "what period corresponds to a
C4" in real time, 50 times a second, would be very expensive. The
solution used throughout the whole 8-bit era (and the one used here)
is to **precompute** that note→period mapping once and store it in a
table — at runtime the Z80 only needs an indexed jump, no expensive
arithmetic. That idea appears again and again in this driver:
precomputed tables instead of live computation.

## 3. General architecture

```
$C4A0 ─┬─ INSTALAR_RECURSO_SONIDO / INSTALAR_RECURSO_SONIDO_EN_A -- install a script on a channel
       ├─ TICK_REPRODUCTOR_PSG / PROCESAR_CANAL_PSG          -- the player's "tick" (once per VBLANK)
       ├─ DESPACHAR_COMANDO_PSG / ARMAR_NOTA / CERRAR_NOTA   -- the bytecode interpreter (a note or command)
       ├─ APLICAR_ENVOLVENTES_CANAL                          -- applies one volume/tone envelope step PER CHANNEL
       ├─ APLICAR_ENVOLVENTE_RUIDO / REINICIAR_ENVOLVENTE_RUIDO -- NOISE envelope, SHARED between the 3 channels (§8, resolved)
       ├─ ACTUALIZAR_MEZCLADOR_CANAL                         -- enable/disable tone and noise per channel
       ├─ MULTIPLICAR_8X16 / DIVIDIR_16X16 / LEER_PALABRA_INDEXADA -- utilities: arithmetic and table lookup
       └─ VOLCAR_REGISTROS_PSG                                -- dumps the register shadow to the real chip
$C8DE ─┬─ TABLA_NOTAS_PSG                          -- period table (note -> PSG period)
       ├─ TABLA_COMANDOS_PSG                       -- jump table for the 15 bytecode commands
       ├─ AREA_TRABAJO_PSG                         -- 151 bytes of idle-state area (in the v2.0 CAS/ROM the level-13 bug patch goes here, see FINDINGS.md)
       ├─ TABLA_ENVOLVENTE_RUIDO_PSG               -- shared noise envelope: LIVE STATE (§8)
       ├─ TABLA_RETORNO_SUBPATRONES_PSG            -- CALL_SUBPATTERN return address per channel
       ├─ TABLA_TRANSPOSICION_PSG                  -- live per-channel transposition
       ├─ TABLA_INSTRUMENTOS_PSG                   -- 16 instruments x 15 bytes
       ├─ TABLA_ENVOLVENTES_PSG                    -- 4 TEMPLATE envelope shapes x 6 bytes
       ├─ TABLA_SUBPATRONES_PSG                    -- pointers to the 13 shared subpatterns
       └─ SUBPATRON_00_CB9C .. SUBPATRON_12_CBB0   -- the bytecode of those 13 subpatterns, each with its own label, data/sound/spt/*.spt
$CDCB ─── GUION_MELODIA_CANAL_0/1/2 + 13 event scripts (GUION_EVTxx_..._CExx) -- the 16 real resource "scripts" (music + effects, data/sound/snd/*.snd)
$CF8B ─── VACIAR_CANALES_SONIDO               -- clears the 3 channels (used on screen/level change)
```

Everything from `$C8DE` onward is **data**, not code — the driver's
real code is complete between `$C4A0` and `$C8C9`. See
`madmix1.asm` (search for each label above) for the full
disassembly, already commented line by line.

## 4. The playback loop (the "tick")

Every **VBLANK** (end-of-frame video interrupt, 50 times a second on
PAL), `DESPACHAR_EFECTO_SONIDO` (`$60DC`,
`madmix_scr.asm`) does two things:

1. Checks `(EVENTO_SONIDO_PENDIENTE)`: if it's not `$FF`, there is a
   pending sound effect to trigger (see §7).
2. ALWAYS calls `TICK_REPRODUCTOR_PSG` (`$C4EB`) — the player's real
   "tick".

`TICK_REPRODUCTOR_PSG` sets up pointers (channel table at `$C9C9`,
PSG register shadow at `$C9BE`) and enters `PROCESAR_CANAL_PSG`,
a loop that walks the **3 channels** (46 bytes each, see §5) and
for each one:

1. **Is there time left in the current note?** (`(IX+$04)`/`(IX+$05)` ≠ 0):
   if so, it jumps straight to `APLICAR_ENVOLVENTES_CANAL` — decrements
   the counter and applies one step of the channel's volume/tone
   envelopes — it does not touch the bytecode.
2. **Did the note end?**: it briefly mutes the channel
   (`ACTUALIZAR_MEZCLADOR_CANAL` with `A=0`, avoids clicks), and enters
   `DESPACHAR_COMANDO_PSG`: reads bytes from the script one at a time. Each
   byte is either a **note** (`< $80`, resolves the period and ends
   the batch) or a **command** (`≥ $80`, executes it and keeps
   reading the next byte immediately, without consuming a tick).

After walking through the 3 channels, execution falls through
(no jump, straight through) into `APLICAR_ENVOLVENTE_RUIDO` — the
third envelope, shared between the 3 channels, see §8 — which in
turn ends in `VOLCAR_REGISTROS_PSG`, which dumps the shadow of the
PSG's 11 registers to the real chip.

**Important detail for anyone wanting to reimplement this in an
emulator/renderer**: when a new note is resolved
(`DESPACHAR_COMANDO_PSG`→`ARMAR_NOTA`→`CERRAR_NOTA`→falls straight
into `APLICAR_ENVOLVENTES_CANAL`, with no jump in between), the FIRST
tick of that note **already** decrements the counter and applies one
envelope step — it does not wait for the next tick. This is an easy
detail to miss (it was discovered as a real bug while building the
renderer, see `FINDINGS.md`).

## 5. The channel slot (46 bytes)

There are 3 slots, one per PSG channel, at `$C9C9` (`$C9C9`, `$C9C9+46`,
`$C9C9+92`). Fields (offset relative to `IX`, the pointer to the slot):

| Offset | Field | Notes |
|---|---|---|
| `+$00/$01` | ORIGINAL script pointer | used by `LOOP` to jump back to the start |
| `+$02/$03` | current READ pointer | advances byte by byte through the script |
| `+$04/$05` | ticks left in the current note | when it reaches 0, the next batch of commands is read |
| `+$06/$07` | duration in ticks | set by `SET_DURATION`/`SET_DURATION_MULTI`; copied to `+$04/$05` on every new note |
| `+$08` | mixer mask | bit0=tone active, bit3=noise active (see `SET_MIXER`, §6) |
| `+$09` | base volume | set by `SET_VOLUME` |
| `+$0A/$0B` | already-resolved BASE tone period | note + transposition, via `TABLA_NOTAS_PSG` |
| `+$0C/$0D` | VOLUME envelope: delay countdown, phase 1/2 | |
| `+$0E/$0F` | VOLUME envelope: repeats left, phase 1/2 | |
| `+$10/$11/$12` | TONE envelope: delay countdown, phase 1/2/3 | |
| `+$13/$14/$15` | TONE envelope: repeats left, phase 1/2/3 | |
| `+$1B/$1C` | VOLUME envelope: delta per step, phase 1/2 | unsigned |
| `+$1D/$1E/$1F` | TONE envelope: delta per step, phase 1/2/3 | **signed** |
| `+$20/$21` | VOLUME envelope: delay reload value, phase 1/2 | |
| `+$22/$23/$24` | TONE envelope: delay reload value, phase 1/2/3 | |
| `+$2A` | LIVE accumulator of the volume envelope | added to the base volume when writing the PSG register |
| `+$2B/$2C` | LIVE accumulator of the tone envelope (16-bit, signed) | added to the base period |
| `+$2D` | miscellaneous flags | tested to decide whether to "relatch" a companion channel |

All these fields come from copying the **active instrument** (§6.7)
when `SET_INSTRUMENT` runs, except `+$00` to `+$09` (set directly by
the bytecode) and `+$2A`-`+$2D` (live accumulators, recomputed tick
by tick).

## 6. The bytecode language (15 commands + note)

Each sound "script" (see §9, `data/sound/snd/*.snd`) or shared
subpattern (`data/sound/spt/*.spt`, same language) is a sequence
of bytes read command by command:

- **Byte `< $80`** → it's a **NOTE**: the value (0-95) is added to
  the channel's transposition (`TABLA_TRANSPOSICION_PSG`) and the
  result indexes `TABLA_NOTAS_PSG` to get the real tone period.
- **Byte `≥ $80`** → it's a **COMMAND** (`$80` + command number,
  `TABLA_COMANDOS_PSG` does the indexed jump).

### Full command table

| # | Byte | Params | Name | Effect |
|---|---|---|---|---|
| 0 | `$80` | 1 byte | **SET_VOLUME** | sets the base volume (`+$09`) |
| 1 | `$81` | 1 byte | **SET_MIXER** | `AND $09`, sets the mixer mask (`+$08`); **a bit set to 1 ENABLES** that generator (bit0=tone, bit3=noise) |
| 2 | `$82` | 0 | **LOOP** | resets the read pointer to the start of the script (`+$00/$01` → `+$02/$03`) |
| 3 | `$83` | 1 byte | **SET_DURATION** | the value × the current tempo multiplier (`($C9BD)`) → duration in ticks (`+$06/$07`) |
| 4 | `$84` | 0 | **HOLD** ("tie") | repeats the current duration without resolving a new note or re-triggering envelopes — jumps straight to `CERRAR_NOTA` (updates the read pointer and reloads the tick counter, skipping tone resolution and envelope relatch) |
| 5 | `$85` | 1 byte | **SET_TEMPO** | `value × 16`, then `$0BB8 ÷ that` (`DIVIDIR_16X16`, quotient) → new tempo multiplier (`($C9BD)`), used by `SET_DURATION`/`SET_DURATION_MULTI` |
| 6 | `$86` | 1 count byte + N bytes | **SET_DURATION_MULTI** | adds N values × the tempo multiplier → duration in ticks (cumulative variant of `SET_DURATION`, variable length) |
| 7 | `$87` | 1 byte | **SET_INSTRUMENT** | copies the 15 bytes of the given instrument (`TABLA_INSTRUMENTOS_PSG`, see §6.7) into the channel's envelope fields, and zeroes the live accumulators |
| 8 | `$88` | 1 byte | **SET_ENVELOPE** | `AND $1F` (0-31) → base of the shared noise envelope (`$CA5E`) and relatch via `REINICIAR_ENVOLVENTE_RUIDO` (§8) |
| 9 | `$89` | 1 byte | **SET_ENVELOPE_SHAPE** | copies one of the 4 shapes from `TABLA_ENVOLVENTES_PSG` into `TABLA_ENVOLVENTE_RUIDO_PSG+4`, resets the accumulator (`$CA5F`) and marks the current channel as "owner" (`$CA60`) |
| 10 | `$8A` | 1 byte | **SET_FLAGS** | `OR`s with the channel's flags (`+$2D`) and with a set of global flags (`$CA5D`) |
| 11 | `$8B` | 0 | **RESET_SHARED_ENVELOPE** | **always clears the full 46 bytes of the current channel's slot**; ONLY if the channel is also the "owner" (`$CA60`) of the shared noise envelope does it also clear its 10 bytes (`TABLA_ENVOLVENTE_RUIDO_PSG`) |
| 12 | `$8C` | 1 byte | **CALL_SUBPATTERN** | saves the return address (`TABLA_RETORNO_SUBPATRONES_PSG`) and jumps to one of the shared subpatterns (`TABLA_SUBPATRONES_PSG`, see §6.8) |
| 13 | `$8D` | 0 | **RETURN_SUBPATTERN** | retrieves the address saved by `CALL_SUBPATTERN` and returns there |
| 14 | `$8E` | 1 byte | **SET_CHANNEL_STATE** | writes the value as-is into the current channel's `TABLA_TRANSPOSICION_PSG` — live transposition |

**Confidence**: the mechanics (which bytes it reads, which fields it
touches, which table it indexes) are 100% verified against the real
disassembly, including the shared noise envelope (§8, see below). The
**names** are a reasoned interpretation based on that mechanics.

### 6.7 The instrument (16 entries × 15 bytes, `TABLA_INSTRUMENTOS_PSG`)

```
b[0]/b[1]   = phase 1/phase 2 repeats of the VOLUME envelope
b[2..4]     = phase 1/2/3 repeats of the TONE envelope
b[5]/b[6]   = phase 1/phase 2 delta of VOLUME (unsigned)
b[7..9]     = phase 1/2/3 delta of TONE (SIGNED)
b[10]/b[11] = delay between steps, phase 1/phase 2 of VOLUME
b[12..14]   = delay between steps, phase 1/2/3 of TONE
```

**How an envelope is processed (volume: 2 phases; tone: 3 phases),
each tick**: the phases are walked THROUGH IN ORDER, stopping at the
first one that is still "active":

1. If the phase still has delay left (`> 0`): the delay is
   decremented and that's it, nothing else happens this tick.
2. If it has no delay left but DOES have repeats left (`> 0`): the
   repeats are decremented, the delta is added to the live
   accumulator, and the delay is reloaded from the reload value
   (`b[10..]`).
3. If the phase has neither delay nor repeats left: it is exhausted,
   the next phase is tried (same tick).

In other words: a phase = "wait `delay` ticks, then apply `delta` to
the accumulator, repeat `repeats` times — then move to the next
phase". The volume accumulator (`+$2A`) is added to the base volume
when writing the PSG's real register, with `AND $0F` (the chip's
volume register is 4 bits — if the sum goes above 15, it **wraps
around to 0**, real silence; this is a verified behavior of the
original driver itself, not something the renderer invented). The
tone accumulator (`+$2B/$2C`, 16-bit signed) is added to the base
period.

This SAME phase mechanism (delay/repeats/delta/reload) is reused
as-is, a third time, for the shared noise envelope — see §8.

### 6.8 Subpatterns (commands 12/13)

`CALL_SUBPATTERN`/`RETURN_SUBPATTERN` implement a **subroutine call
within the bytecode itself**. `CALL_SUBPATTERN`'s parameter indexes
`TABLA_SUBPATRONES_PSG` (42 bytes, 21 16-bit
pointers — entries 13 through 20 repeat entry 0's pointer),
which points to one of the **13 unique shared subpatterns**
(`$CB9C`-`$CDCB`, right before the first real resource script
begins) — each with its own global label
(`SUBPATRON_00_CB9C` to `SUBPATRON_12_CBB0`, numbered by its entry
index in `TABLA_SUBPATRONES_PSG`, not by memory order). The
return address is saved in `TABLA_RETORNO_SUBPATRONES_PSG` (2
bytes per channel) and retrieved with `RETURN_SUBPATTERN`.

Each of the 13 has its own file in `data/sound/spt/`
(`.spt` extension, same bytecode and same tool as the event `.snd`
files) and its own reference `.wav` in `build/sound_preview/`
(`mmsnd_render.py`, which already supported `CALL_SUBPATTERN`/
`RETURN_SUBPATTERN` to play the boot music, also
knows how to play them ON THEIR OWN, thanks to a `RETURN_SUBPATTERN`
with no prior call already being interpreted as end of playback).

This mechanism is used A LOT in the real music (17-20 calls per
script across the 3 boot channels) — it's the way to avoid repeating
identical musical fragments over and over inside each script.

## 7. How effects are triggered: `EVENTO_SONIDO_PENDIENTE` and `TABLA_RECURSOS_SONIDO_EVENTO`

The rest of the game (outside the driver) never installs a sound
script directly — it writes an **effect index** into the global
variable `EVENTO_SONIDO_PENDIENTE` (`$6128`). `DESPACHAR_EFECTO_SONIDO`
(`$60DC`, `madmix_scr.asm`), called every VBLANK, does the following:

1. Reads `(EVENTO_SONIDO_PENDIENTE)`. If it's `$FF`, nothing is
   pending, it does nothing else (apart from the player's normal
   tick, §4).
2. If it's not `$FF`, it uses it as an index (× 3) into
   `TABLA_RECURSOS_SONIDO_EVENTO` (`$60FE`, 14 entries of 3 bytes:
   `[channel, pointer_low, pointer_high]`), installs the
   corresponding script on that channel via `INSTALAR_RECURSO_SONIDO`
   (`$C4A0`), and marks the event as consumed
   (`EVENTO_SONIDO_PENDIENTE = $FF`).
3. ALWAYS calls `TICK_REPRODUCTOR_PSG` (the normal tick).

The 14 known indices, and which game event they correspond to
(catalog candidate in parentheses where there is a solid one — see
`FINDINGS.md` for the detail and confidence level of each one):

| index | channel | script | triggered by | candidate |
|---|---|---|---|---|
| 0 | 0 | `GUION_EVT00_BOLITA_CEE2` (`$CEE2`) | eating a normal ball (`HNDLR_BOLITA_NORMAL`) | "ball-eating sound" |
| 1 | 0 | `GUION_EVT01_BOLA_CLAVADA_CE8B` (`$CE8B`) | freeing a stuck ball, tool mode (`HNDLR_BOLITA_CLAVADA`) | "ball-releasing sound" |
| 2 | 0 | `GUION_EVT02_FLECHA_CF62` (`$CF62`) | passing over an arrow tile (`HNDLR_AUTOCOCO_*`) | "one-way tile" |
| 3 | 1 | `GUION_EVT03_MODO_ESPECIAL_CF70` (`$CF70`) | entering/leaving special mode | generic "mode change" |
| 4 | 0 | `GUION_EVT04_DISPARO_AVION_CE72` (`$CE72`) | `REGISTRAR_PISTA_TANQUE_AVION` (tank/plane track) | "Shot (plane mode)" — CONFIRMED by the user (original player) |
| 5 | 1 | `GUION_EVT05_MARIQUITA_REPONE_CF44` (`$CF44`) | refilling an eaten ball (`HNDLR_MARICOCO`) | "refill ball" |
| 6 | 1 | `GUION_EVT06_PLANTA_CLAVADA_CEAC` (`$CEAC`) | planting a stuck ball (`HNDLR_REGPUNANTOSO`) | no direct match |
| 7 | 1 | `GUION_EVT07_PISTA_CE7E` (`$CE7E`) | track proximity warning (`AVISAR_PROXIMIDAD_PISTA`) + effect tails | ambiguous, two uses |
| 8 | 0 | `GUION_EVT08_ARMA_MODO_CF07` (`$CF07`) | arms the special-mode timer (`ACTIVAR_EFECTO_ITEM`) | generic "activate mode" |
| 9 | 0 | `GUION_EVT09_TRAMPILLA_TRANSICION_CE5A` (`$CE5A`) | trapdoor transition (`HNDLR_TRAMPILLA_ABIERTA_*`) | related to trapdoors |
| 10 | 2 | `GUION_EVT10_INICIO_NIVEL_CEF0` (`$CEF0`) | **called directly** from `MOSTRAR_READY_Y_ARRANCAR_NIVEL`, not via `EVENTO_SONIDO_PENDIENTE` | "level-start jingle" |
| 11 | 2 | `GUION_EVT11_BOLA_PODER_CE9C` (`$CE9C`) | power ball (final event) | related |
| 12 | 0 | `GUION_MELODIA_CANAL_0` (`$CDCB`) | no write site found (reuses the music script) | "main music" |
| 13 | 2 | `GUION_EVT13_FIN_MODO_CF27` (`$CF27`) | final event after special mode | generic "mode end" |

**Special case — the level-start jingle (index 10)**:
`MOSTRAR_READY_Y_ARRANCAR_NIVEL` installs the SAME 23-byte block
on **all 3 channels at once**, each one starting 7 bytes further in
than the previous one (offsets 0/+7/+14) — it's a 3-voice chord, not
a linear melody. Any attempt to play it back as a single channel will
sound incomplete by design.

## 8. The shared envelope, resolved: it is the NOISE envelope (PSG register 6)

This mechanism went untraced for a good part of the project — today
it is fully identified.

`SET_ENVELOPE` (command 8), `SET_ENVELOPE_SHAPE` (command 9) and
`RESET_SHARED_ENVELOPE` (command 11, with a nuance — see above) read
and write a table **shared between the 3 channels**,
`TABLA_ENVOLVENTE_RUIDO_PSG` (`$CA53`, 10 bytes), with a separately
tracked "owner" (`$CA60`). After the loop over the 3 channels,
`TICK_REPRODUCTOR_PSG` falls through (no jump, straight through) into
`APLICAR_ENVOLVENTE_RUIDO`: a **third envelope**, with the SAME
phase structure as the volume/tone ones (§6.7) — delay countdown,
repeats, delta, reload — but with only ONE phase (not 2 or
3), operating on `TABLA_ENVOLVENTE_RUIDO_PSG` instead of on a
channel slot. The result (`($CA5E)` base + `($CA5F)` accumulator)
is written to `$C9C4` — the shadow of **PSG register 6 (noise
period)** — and from there `VOLCAR_REGISTROS_PSG` dumps it to the
real chip. `REINICIAR_ENVOLVENTE_RUIDO` is its relatch (the same
function as `REINICIAR_ENVOLVENTE_VOLUMEN`/`_TONO` but over the
fixed table instead of per channel), called from `SET_ENVELOPE` and,
if it fully runs out, from `APLICAR_ENVOLVENTE_RUIDO` itself.

It makes sense for it to be shared and not per channel: the
AY-3-8910 only has **one** noise generator (and a single noise
period, register 6) for all 3 channels — unlike tone and volume,
which are independent per channel on the real chip.

**The "owner" (`$CA60`)**: any channel that executes
`SET_ENVELOPE_SHAPE` becomes the owner of the shared envelope. This
matters for `RESET_SHARED_ENVELOPE` (command 11): it ALWAYS clears
the full 46 bytes of the slot of the channel that executes it, but
it only also clears the 10-byte shared table if that
channel turns out to be the current owner — this prevents any
channel from stomping over a noise effect that "belongs" to another
one.

**Practical consequence, already resolved**: the script
`05_evt07_pista_ce7e.snd` contains no notes at all — it only uses
`SET_MIXER` (pure noise), `SET_ENVELOPE`/`SET_ENVELOPE_SHAPE`/
`RESET_SHARED_ENVELOPE` and `SET_DURATION`. With the mechanism now
modeled, `mmsnd_render.py` (§10) can play this effect instead of
leaving it silent, as long as it incorporates this third envelope
into its emulation loop (see the script itself for the current state
of that implementation).

## 9. The 16 real resource "scripts"

They live in `data/sound/snd/*.snd` (the binary compiled with `INCBIN`,
byte for byte identical to the original) with a twin `.txt` (this
manual's text format, one mnemonic per line, see §10):

| File | Label | Address | Use |
|---|---|---|---|
| `00_script_cdcb` | `GUION_MELODIA_CANAL_0` | `$CDCB` | music, channel 0 |
| `01_script_cdff` | `GUION_MELODIA_CANAL_1` | `$CDFF` | music, channel 1 |
| `02_boot_ch2_ce0c` | `GUION_MELODIA_CANAL_2` | `$CE0C` | music, channel 2 (percussion) |
| `03` to `15` | `GUION_EVTxx_..._CExx` | `$CE5A`-`$CF70` | 13 individual sound effects, one per `EVENTO_SONIDO_PENDIENTE` index (§7) |

> ⚠️ **Real editing limit**: each `.snd` compiles with `INCBIN` at a
> FIXED address. Changing the VALUE of an already-existing
> instruction is 100% safe. **Adding/removing instructions, or
> changing the count of a `SET_DURATION_MULTI`, is NOT**: it would
> change the total size, and everything after it in `madmix1.asm`
> would shift address — `TABLA_RECURSOS_SONIDO_EVENTO` would still be
> pointing at the OLD address. The game would compile with no errors
> at all but would jump to the wrong places at runtime.

## 10. Tools

### `tools/mmsnd_tool.py` — bytecode disassembler/assembler

```
py tools/mmsnd_tool.py disasm file.snd file.txt   # binary -> editable text
py tools/mmsnd_tool.py asm file.txt file.snd      # text -> binary (to recompile the game)
py tools/mmsnd_tool.py roundtrip file.snd            # verifies that disasm+asm produces the same binary
py tools/mmsnd_tool.py roundtrip-all folder/           # same, for every .snd in a folder
```

The text format: one mnemonic per line (`SET_VOLUME 0x09`,
`NOTE 0x3C`, etc., exactly the names from the §6 table),
comments with `;`. Every generated file carries a notice repeating
the §9 fixed-size warning.

**Real workflow to edit a sound**: edit the `.txt` →
`py tools/mmsnd_tool.py asm file.txt file.snd` → recompile the
game (`sjasmplus madmix1.asm`) → verify it still gives the same
byte count as before.

### `tools/mmsnd_render.py` — WAV renderer

Emulates the PSG (square wave + simplified LFSR noise + 16-step
logarithmic volume table) and the full bytecode interpreter,
so you can LISTEN to a `.snd` without needing openMSX or the full
game:

```
py tools/mmsnd_render.py render file.snd output.wav [--max-ticks N]
py tools/mmsnd_render.py render-all folder/ output_folder/
py tools/mmsnd_render.py render-chord file.snd output.wav 0,7,14   # mixes several voices (see §7, level-start chord)
```

**Fidelity warning**: the mechanics (what each command does, which
table it looks up) are verified against the real code, including the
noise envelope from §8. What remains a **reasoned
reconstruction, not certified emulation** is the fine timbre detail
of the chip's real noise generator. It's good enough to judge by ear
whether the bytecode reading makes musical sense — rhythm, which
note, when it goes silent —, not as a perfect sound reference. Tool
and limitations tuned iteratively by listening against the real game
(see `FINDINGS.md` for the full history of corrections found this
way: instrument field mapping, `SET_MIXER` polarity, DC offset during
silence, detecting the end of a `LOOP`, among others).

## 11. To dig further

- `FINDINGS.md` — every sound-related section, in chronological
  order, with the full reasoning behind each
  discovery (useful when this summarized version isn't enough;
  search for "envolvente de ruido" for the §8 finding).
- `data/sound/_engine_tables.bin` — working copy of the entire
  `$C8DE`-`$CDCB` zone so `mmsnd_render.py` has real data without
  depending on compiling the game first.
- The only real gap left: the exact timbre detail of the
  AY-3-8910's noise generator as emulated in `mmsnd_render.py` (§10)
  — the driver's own mechanics (what it writes, when, from what
  source) no longer have any known open points.
