# Level format manual — Mad Mix Game (MSX1)

*[Leer esto en español](manual_niveles.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Source: `madmix_scr.asm` (`CARGAR_NIVEL`, `TABLA_NIVELES`, the 13
> bodies + 3 level headers) and `madmix1.asm` (`VERIFICAR_FIN_NIVEL`).
> For the chronicle of how each piece was discovered, see `FINDINGS.md`;
> this document assumes everything is already identified and explains
> the final result in an orderly way.

## 1. What this is and what it is NOT

This manual explains how the game's 15 levels are built —
the tile grid format, how they're loaded into memory, and
how a level is detected as complete — and how to edit them with
`mmlvl_tool.py`.

**It is not** a level system with rich metadata nor an in-game visual
editor: each level is, literally, a grid of bytes
(one byte = one tile) plus a fixed 20-byte register with a handful
of parameters (starting position, how many enemies, ball
target...). There are no layers, no entities with their own position
outside the item tables already documented in `manual_motor_colision_ia.md`
— enemies always "appear" at the same reference point in the
level, never at their own per-level coordinates.

**The most surprising fact**: the real game has **15 levels**, not
14 — level 15 (previously called the "hidden level" in this same
project's earlier analysis) is reachable in normal play, by completing
level 14. It is just one more level body, with no special trick to
reach it — see §4.

## 2. General architecture

```
$2BF3 ─── REGISTRO_NIVEL (20 bytes)     -- working copy of the current level's register (§3)
$5885 ─┬─ CARGAR_NIVEL / INICIALIZAR_ITEMS_NIVEL -- loader (§5), called from INICIO/VERIFICAR_FIN_NIVEL
       └─ INICIALIZAR_PARCIAL_ITEMS_NIVEL -- 2nd entry point, only clears the tank/plane track
$59A9 ─── TABLA_NIVELES (320 bytes = 16 registers x 20 bytes)  -- level catalog (§4)
$5B8C..  ─── CUERPO_L01..CUERPO_L15 + CABECERA_4AFC/_4B5C/_50BC -- the real data (§4.2)
$8FD4  ─── VERIFICAR_FIN_NIVEL (madmix1.asm) -- detects target reached, advances level (§6)
$6045 ─── GESTIONAR_CICLO_NIVELES -- menu "DEMO" mode: plays 4 sample levels (§7)
```

## 3. The level register (20 bytes)

Each level is described by a 20-byte register. On load, it is
copied whole into a fixed working area (`REGISTRO_NIVEL`, `$2BF3`) —
the "factory" values found in that zone in the compiled `.BIN` are
just a snapshot of the last level processed at compile time, with no
meaning of their own (the real game always overwrites them when the
first level loads).

| Offset | Field | Content |
|---|---|---|
| 0-1 | `REGISTRO_NIVEL_CUERPO_PTR` | pointer to the level's BODY (the tile grid, variable rows) |
| 2-3 | `REGISTRO_NIVEL_CABECERA_PTR` | pointer to the fixed HEADER (3 rows, shared across several levels) |
| 4-5 | `REGISTRO_NIVEL_PIE_PTR` | duplicate of the previous field — the header is ALSO copied below the body, as a "footer" |
| 6 | `REGISTRO_NIVEL_FILAS` | number of rows in the body (varies per level, 15-23) |
| 7 | `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` | HUD notice flag ("NEXT... EXTRA") |
| 8 | `REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` | number of active ghosts this level (max. 8, see `manual_motor_colision_ia.md` §6.1) |
| 9 | `REGISTRO_NIVEL_CONTADOR_MARICOCOS` | number of active ladybugs (max. 2, §6.2) |
| 10 | `REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS` | number of active "repugnantosos" (max. 8, §6.3) |
| 11 | `REGISTRO_NIVEL_DURACION_PARPADEO` | duration in frames of the special ball/track blink |
| 12 | `REGISTRO_NIVEL_LOSETA_COMODIN` | real tile that replaces the `$3C` wildcard in the body (§5) |
| 13-14 | `REGISTRO_NIVEL_FILA_COLUMNA` | row/column of an initial reference point (items' "spawn" position) |
| 15-16 | `REGISTRO_NIVEL_POSICION_COMECOCOS` | Pac-Man/camera starting position — stays live for the whole game at `$2C02` |
| 17 | `REGISTRO_NIVEL_ICONO_HUD` | HUD character/icon code for this level |
| 18-19 | `REGISTRO_NIVEL_OBJETIVO_BOLAS` | target number of "balls to eat" to complete the level (§6) |

## 4. `TABLA_NIVELES` — the catalog of 15 levels

**320 bytes = 16 registers of 20 bytes** (`$59A9`-`$5AE9`). The first
one (index 0) is a **dead register**, an exact duplicate of level 1 —
never reached in normal play (`NIVEL_ACTUAL` starts at 1, never
at 0). Indices 1-15 are the 15 real levels; 15 is the earlier
analysis' "hidden level", confirmed reachable by normally
completing level 14 (`VERIFICAR_FIN_NIVEL`, §6, makes no
special distinction when reaching it).

Rewritten as a native data table directly in the assembler
(`DW CUERPO_L01, CABECERA_50BC, CABECERA_50BC` etc.) instead of an
`INCBIN` binary table — the body/header pointers are
real labels, the assembler itself resolves the correct
address instead of having to keep loose hex manually
synchronized.

### 4.1 The data files: 13 bodies + 3 shared headers

`data/niveles/*.bin` — one file per unique block of data:

- **13 bodies** (`body_l01.bin` to `body_l15.bin`, skipping the
  level-0 duplicate): each level's variable grid, 15-23
  rows × 32 columns.
- **3 shared headers** (`header_50bc.bin`, `header_4afc.bin`,
  `header_4b5c.bin`, 96 bytes each = 3 rows × 32), reused
  by several levels at once — a memory-saving trick: they are the
  maze's top/bottom borders, and several levels share
  exactly the same border:
  - `CABECERA_50BC`: levels 0, 1, 2, 3, 6, 9, 10, 11, 14 (9 uses)
  - `CABECERA_4AFC`: levels 4, 5, 7, 12, 13 (5 uses)
  - `CABECERA_4B5C`: level 8 (1 use)

Each byte of the grid is a **tile index** (bits 0-6, see
`data/tiles/*.til`, catalog 00-90) with **bit 7** of unconfirmed
meaning at runtime (`CARGAR_NIVEL` always clears it when
copying to the active buffer) but which IS present in the original
binaries — that's why `mmlvl_tool.py`'s text format preserves it byte
for byte instead of discarding it.

### 4.2 The `$3C` wildcard and alternation by "laps"

When copying the body, `CARGAR_NIVEL` replaces every tile with value
`$3C` (60, the "wildcard") with the real value set in
`REGISTRO_NIVEL_LOSETA_COMODIN` (offset 12) — this way the same body
pattern can look different depending on the level without duplicating
data. The substitution **is not unconditional**: if it's the first
full lap of the 15-level cycle (`CONTADOR_VUELTAS_NIVELES=0`), the
wildcards are copied as-is, WITHOUT substitution; on later laps, they
are substituted in an alternating pattern (one yes, one no, based on
the parity of the count of wildcards found compared against the lap
number) — visual variety in long games that go around the level
cycle more than once.

## 5. Loading a level: `CARGAR_NIVEL` step by step

Called from `INICIO`/`VERIFICAR_FIN_NIVEL` (`madmix1.asm`) whenever
a new level is needed:

1. Locates the `NIVEL_ACTUAL` register in `TABLA_NIVELES` (20 bytes
   × level number) and copies it whole into `REGISTRO_NIVEL` (§3).
2. Copies the header (96 bytes) to the active level buffer
   (`$FC50` — see bug note below), **above** the body.
3. Copies the body (`REGISTRO_NIVEL_FILAS` × 32 bytes), clearing the
   bit 7 ("eaten") of each tile and applying the wildcard
   substitution (§4.2).
4. Copies the SAME header again, **below** the body (as a "footer") —
   the maze ends up symmetrical top/bottom with the same border.
5. Resets `CONTADOR_BOLAS_COMIDAS` to 0, computes the VRAM address of
   the initial reference point (`POSICION_PARPADEO_BOLA`), clears
   all special-mode flags, restores the default HUD color,
   sets the camera position to `$1018`, and calls
   `INICIALIZAR_ITEMS_NIVEL` (§5.1).

**Known bug, fixed in v2.0**: the active level buffer is
`$FC50` in the reconstructed code — the original 1987 v1.0 used
`$FC60` in the 5 places where this constant is recorded as a magic
number (2 in `madmix1.asm`, 3 in `madmix_scr.asm`), a real bug that
broke level 13's ball counter. v2.0 (the 2013 CAS/ROM re-release)
fixed it by moving the buffer 16 bytes earlier; it is the
**only** deliberate deviation from the byte-for-byte reproduction of
the original v1.0 in this entire project — everything else remains
v1.0 exactly as it is, bugs included. See `FINDINGS.md` for the full
detail.

### 5.1 `INICIALIZAR_ITEMS_NIVEL` — enemy and item respawn

Places the 3 active item tables (`TABLA_ITEMS_PELMAZOIDE`,
`TABLA_ITEMS_MARICOCO`, `TABLA_ITEMS_REGPUNANTOSO` — see
`manual_motor_colision_ia.md` §6) at the reference point
(`REGISTRO_NIVEL_FILA_COLUMNA`), clearing their mode/phase fields —
they all "respawn" at the same exit spot. It also clears the
warning/flash queue (`TABLA_RANURAS_AVISO`) and resets
movement direction/timers (except with the "tool" mode
active, which starts with a special value of 14). Second entry
point, `INICIALIZAR_PARCIAL_ITEMS_NIVEL`, only clears the
tank/plane track table — used when leaving those special modes
without repeating the rest of the reset.

**That reference point is always the ghost house**:
verified by cross-checking each level's `REGISTRO_NIVEL_FILA_COLUMNA`
value against its own body — the tile catalog has a
dedicated "puerta_fantasmas_inicio_izquierdo/derecho" structure
(`$50`/`$51`, with the power-line tile `$38` in the center, not
walkable by these items) that visually marks the house on the
map. Checked on level 1 (column 12 exact, computed and real) and
on level 2 (column 16 exact), with a consistent row offset
of 1 (items appear right below the door, never on the
blocked center tile). Same pattern as the original Pac-Man —
all ghosts are born from the same spot —, extended here to all 3
item types, not just the ghosts.

## 6. How level end is detected: `VERIFICAR_FIN_NIVEL`

Checked **every frame** inside the main loop
(`madmix1.asm`, see `FLUJO_PROGRAMA.md` §4): compares
`CONTADOR_BOLAS_COMIDAS` against `REGISTRO_NIVEL_OBJETIVO_BOLAS`. If
it doesn't match, the level is still in progress. If it matches:

1. Increments `NIVEL_ACTUAL`. If it reaches 16 (that is, level 15
   was just completed), resets it to 1 and increments
   `CONTADOR_VUELTAS_NIVELES` (§4.2) — the 15-level cycle starts
   over. If not (this includes the case of completing 14 and moving
   to 15), it simply continues with the next register.
2. Triggers the HUD icon/color flash, copies the extra-life flag from
   the new register, and jumps to `PANTALLA_PRESENTACION_NIVEL`
   (reloads the HUD for the new level, which in turn leads into
   `CARGAR_NIVEL`).

**What counts as a "ball"**: not just normal balls — forced-direction
arrows ALSO increment `CONTADOR_BOLAS_COMIDAS` when stepped on (see
`manual_motor_colision_ia.md` §4), so a level's real target mixes
both tile types.

## 7. The menu's "DEMO" mode: `GESTIONAR_CICLO_NIVELES`

Different from actually playing: the main menu offers a
"DEMO" option that plays, with no player input, **4 sample
levels** from its own table (`TABLA_CICLO_NIVELES`, `$60D0`, 4
entries `[level, script_pointer]`) — not the full 15 levels.
For each one: it sets `NIVEL_ACTUAL`, loads the level (the same
`CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL` as in real play), and
plays a **demo script** — a sequence of pairs
`[duration in frames, simulated direction]` ending with direction
`$FF`, which replaces the real keyboard/joystick reading in
`MOTOR_MOVIMIENTO_COLISION` while the cycler is active (see
`manual_motor_colision_ia.md` §3, step 1).

The scripts live in `data/demos/*.dem` (binary, byte-pair
format, with no dedicated editing tool in this project —
they are recording data, not something meant to be hand-edited). Of
the 10 scripts that exist in the original binary, only 4 are
referenced from `TABLA_CICLO_NIVELES` (levels 1, 2, 4 and 5); the
other 6 (`_sinref`) have no pointer reaching them — orphan
data, preserved as-is for byte-for-byte fidelity with the
original.

## 8. Tool: `tools/mmlvl_tool.py`

```
py tools/mmlvl_tool.py disasm file.bin file.txt   # binary -> editable text grid
py tools/mmlvl_tool.py asm file.txt file.bin      # text -> binary (to recompile the game)
py tools/mmlvl_tool.py roundtrip file.bin            # verifies that disasm+asm produces the same binary
py tools/mmlvl_tool.py roundtrip-all folder/           # same, for every .bin in a folder
py tools/mmlvl_tool.py check-bolitas file.txt LEVEL  # counts balls in the .txt and compares against
                                                          # that level's real target in TABLA_NIVELES
```

The text format: each cell is the raw byte in **2-digit
hex** (not a mnemonic like in the sound files — there is no
command language here, only tile indices), organized as
a `rows × 32 columns` grid with a header notice repeating
the fixed-size warning. `check-bolitas` is the most useful check
when editing a level: it reads the real target directly from
`TABLA_NIVELES` in `madmix_scr_body.asm` (with no separate
manifest file that could get out of sync) and counts the "floor with
ball" tiles (`$2D`/`$2E`/`$2F`, with bit 7 masked out) in the `.txt` —
if they don't match, the level is unfinishable (it would compile with
no error, but the level could never be completed by playing it).

> ⚠️ **Real editing limit** (same pattern as sound, see
> `manual_driver_sonido.md` §9): each `.bin` compiles with `INCBIN` at
> a FIXED address. You can change the VALUE of any tile with no
> problem. **Do NOT add or remove rows or columns**: the size is
> FIXED — if it changes, everything after it in `madmix_scr.asm`/
> `madmix1.asm` shifts address. The game would compile with
> no error at all but would load the wrong levels or data at
> runtime.

## 9. Confidence and open items

The level register structure, the 16-entry table, and the
loading/end-detection mechanism are 100% verified against the real
disassembly. Open items:

- The exact meaning of bit 7 of each body tile (always cleared on
  load, present in the original data — a candidate for a "level
  editing flag" from the original team, unconfirmed).
- Bit 5, polled in `VERIFICAR_ENTRADA` right after completing
  a level (a candidate for a pause/confirm key, not fully
  identified).
- The exact detail of the wildcard-substitution alternation across
  laps (§4.2) — mechanics confirmed, but not visually verified by
  actually playing several full laps in a row.

## 10. To dig further

- `FINDINGS.md` — every level-related section, the 20-byte
  register field by field, and the level-13 bug, in chronological
  order.
- `manual_motor_colision_ia.md` — what the enemies/items do once
  the level is already loaded (this manual only documents how the
  level is built and loaded, not the game logic inside it).
- `niveles.html`/`editor_niveles.html` (recursos) — visualization of
  the 15 already-reconstructed levels.
