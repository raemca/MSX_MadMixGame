# Mad Mix Game — reconstruction project (MSX1)

*[Leer esto en español](README.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

Reverse-engineered reconstruction of **all 3 binaries** from the
original disk.

**`main.asm`** is the real entry point for building the engine and
the loading screen: it unifies `madmix1_body.asm` + `madmix_scr_body.asm`
in a single assembly pass (they share a single symbol space), so all
cross calls/pointers between them use real labels instead of literal
hex addresses — they used to be compiled separately, with no linker,
and any reference from one file to the other stayed as hex with the
real name in a comment. See `FINDINGS.md` for the full detail of this
unification.

- **`madmix1_body.asm`** → part of `build/MADMIX1.BIN` (the game
  engine). STATIC addresses from start to end (`ORG $8400`, no
  relocation). Reproducing the relocation trick from `MADMIX0.BIN`
  with `PHASE $1000`/`DEPHASE` was tried, but a live memory dump
  (openMSX) showed that the game engine runs from static addresses,
  not from a relocated copy.
- **`madmix_scr_body.asm`** → part of `build/disk/MADMIX.SCR`. Despite
  the original name/extension, **it is not a screen image**: it is
  code+data that on disk `MADMIX0.BIN` relocates from `0x8800` to
  `0x1000` (`main.asm` applies `PHASE`/`DEPHASE` over this body when
  generating `MADMIX.SCR`, the opposite of what happens with
  `madmix1_body.asm`). It contains the cover art drawing, the
  collision/movement engine (the "main loop"), the special-item
  activation subsystem, the loader + table of the 15 playable levels
  (the 15th, previously believed to be "hidden and unused", has its
  own register and is reachable in normal play -- see below), and the
  main menu + credits screen. **100% complete**, except for 2
  unrelated bytes already documented.
- **`load_disk/madmix0_body.asm`** → `MADMIX0.BIN` (58 bytes, the
  "relocator"). Exclusive to the disk version (it does the `LDIR`
  relocation that tape doesn't need, since tape loads straight to
  destination), but **already integrated into `main.asm`** (shares
  the symbol space, uses `PORTADA_INIT`/`START` instead of
  `$1000`/`$8400`). It has TWO entry points: one that does the `LDIR`
  relocation of `MADMIX.SCR` (0x8800→0x1000) and calls the cover art
  drawing, and another (`0xFA2A`) that jumps straight to the
  `MADMIX1.BIN` engine — invoked by a separate `CALL`/`USR` from the
  orchestrating BASIC, since `MADMIX1.BIN` is loaded without `",R"`.
  **100% complete.**
- **`load_cas/load_bin_body.asm`/`test_bin_body.asm`** → `LOAD.BIN`
  (299 bytes) and `TEST.BIN` (253 bytes), the loader for the
  **tape** version: `TEST.BIN` detects RAM slots, `LOAD.BIN` applies
  that configuration and reads from tape directly into `$1000`/`$8400`
  (without the relocation step that disk does) — see `FINDINGS.md`
  for the detail of why disk and tape reach the same place by
  different paths. Reconstructed by byte-for-byte disassembly of the
  1988 `.cas` with `Z80Dasm.exe`, **100% complete**, 0 differences.
- **`load_disk/AUTOEXEC.bas`/`MADMIX.bas`** and
  **`load_cas/TOPO.bas`/`MADMIX.bas`** → the BASIC loaders for each
  version. The disk ones are tokenized (reconstructed with
  `tools/msxbasic_tool.py`, see below); the tape ones are already
  plain ASCII in the original `.cas`, copied as-is.
- **`load_cas/logotopo_cm_body.asm`** → `LOGOTOPO.CM` (4254 bytes), the
  animated Topo Soft logo of the tape version. **COMPLETE**:
  code block (`0x9470-0x9693`, 549 bytes) and data
  (`0x9694-0xA50D`: `TABLA_PUNTEROS_FORMAS`, 3 animation tables,
  `TABLA_DELTA_POSICION`, and `TABLA_FORMAS` with the 15 shapes + 1
  orphan block with no reference) transcribed, verified byte for
  byte (0 differences) and **visually confirmed by the developer**
  (T-O-P-O letters sliding in, color expanding out from the center,
  "Soft" rotating, a light dot running across it, a blinking star) —
  see `recursos/logotopo_formas.html`,
  `load_cas/LOGOTOPO.CM.txt` and `FINDINGS.md`.

`main.asm` also generates `build/cas/madmix_cas_scr.bin` (the logical
body of `MADMIX.SCR`, without the BLOAD header) which, together with
`build/MADMIX1.BIN`, forms the content of the **tape version**
(`.cas`) — see the "Building" section below for details.

See `FINDINGS.md` for the full technical detail of every
finding. **All three files are 100% complete** and compile to
**0 differences** byte for byte against the originals, except for:
4 already-documented bytes unrelated to the engine (3 at
`0x28ED-0x28F0` and 1 at `0x6500`, both inside `madmix_scr_body.asm`,
unrelated content), and **5 bytes of a deliberate deviation**: the
real level-13 ball-counter bug (`$FC60`→`$FC50`,
2 places in `madmix1_body.asm` + 3 in `madmix_scr_body.asm`) is fixed
on purpose, the same way the v2.0 re-release (2013 homebrew CAS/ROM)
fixed it — it is the **only** intentional correction in the whole
project; everything else still reproduces v1.0 exactly as it is,
bugs included. See `FINDINGS.md` for the full comparison analysis
against v2.0.

See `FLUJO_PROGRAMA.md` for the analysis organized by **execution
flow** (boot, dispatch table, main loop, each subsystem) instead of
by chronological discovery order — it complements `FINDINGS.md`. Its
visual companion is `recursos/flujo_programa.html` (flow diagram +
searchable inventory of the 729 labels across all source files,
regenerated with `tools/gen_inventory.py` from the sjasmplus
listing). It's a work in progress: the end goal is for every routine
to have its own name and a clear explanation, as if the code had been
documented by an expert programmer of the time.

See `manuales/` for reference technical manuals, intended as
training material for a new programmer (and as preservation in their
own right) — unlike `FINDINGS.md` (which documents HOW each thing was
discovered) and `FLUJO_PROGRAMA.md` (organized by execution flow),
here each already-understood subsystem is documented as HOW IT WORKS,
in an orderly way with the research process left out. It starts with
`manuales/manual_driver_sonido.md` (the PSG sound driver); more will
be added as it's decided what other parts to document this way.

**Tested in production**: both `src/build/madmix_reconstruido.dsk`
and `src/build/madmix_reconstruido.cas` (both generated FROM SCRATCH
by `tools/gen_disk_and_cas.py`, without starting from a copy of any
original) **load and run perfectly in openMSX** — both versions,
disk and tape, confirmed.

## Requirements

- [SjASMPlus](https://github.com/z00m128/sjasmplus) on the PATH —
  compiles `src/main.asm` (engine, screen, disk/tape loaders).
- Python 3 (`py` on Windows) — needed to generate the final
  deliverables (`tools/gen_disk_and_cas.py` and everything it
  orchestrates: `gen_dsk_file.py`, `gen_cas_bin.py`, `gen_cas_file.py`),
  and for the rest of the `tools/` utilities (sound, levels,
  tokenized BASIC). No external dependencies (everything uses the
  standard library) — **`mtools` is not needed**: the `.dsk` builds
  its FAT12 structure from scratch in Python (see
  `tools/gen_dsk_file.py`), nothing is injected with third-party
  tools.
- [openMSX](https://openmsx.org/) to test it (optional, only to run
  the result).

## Structure

`tools/`, `manuales/`, `recursos/` and `dump_openmsx/` live at the
ROOT of the repository (siblings of `src/`, not inside it) — a
single copy of each for the whole project:

```
madmixgame/
├── tools/                          ← all invokable as `py tools/name.py ...` from the root
│   ├── build_all.py                ← BUILDS EVERYTHING (sjasmplus src/main.asm, with the right cwd and build/disk/ and build/cas/ folders) -- first step of the "one command" flow to regenerate the project
│   ├── gen_disk_and_cas.py         ← second step: generates the 2 FINAL DELIVERABLES, src/build/madmix_reconstruido.dsk and src/build/madmix_reconstruido.cas, from what build_all.py compiled (delegates to gen_dsk_file.py + gen_cas_bin.py + gen_cas_file.py)
│   ├── gen_dsk_file.py             ← builds the .dsk FROM SCRATCH (boot sector, 2 FAT12 tables, root directory, data area -- without starting from a copy of the original or patching it), see FINDINGS.md for the full format -- invoked by gen_disk_and_cas.py
│   ├── mmsnd_tool.py               ← disassembler/assembler for the sound bytecode (disasm/asm/roundtrip/roundtrip-all, works the same on `.snd` and `.spt` -- same bytecode, see FINDINGS.md)
│   ├── mmsnd_render.py             ← renders a .snd to WAV (emulates the PSG + the bytecode interpreter) -- a reasoned reconstruction, not certified emulation, see notice in FINDINGS.md
│   ├── mmlvl_tool.py               ← disassembler/assembler for the level tile grids (disasm/asm/roundtrip/roundtrip-all/check-bolitas, see FINDINGS.md)
│   ├── gen_cas_bin.py              ← concatenates madmix_cas_scr.bin + MADMIX1.BIN into src/build/cas/madmix_cas.bin (intermediate ingredient, no real .cas blocks yet) -- invoked by gen_disk_and_cas.py
│   ├── gen_cas_file.py             ← packages ALL the ingredients from load_cas/ and build/cas/ into src/build/madmix_reconstruido.cas, a REAL .cas (sync/name/header) -- verified byte for byte against the 1988 .cas, only 9 already-known differences, see FINDINGS.md -- invoked by gen_disk_and_cas.py
│   ├── msxbasic_tool.py            ← detok/tok/roundtrip for tokenized MSX BASIC (disk's AUTOEXEC.BAS/MADMIX.BAS). PARTIAL token table -- only the empirically verified ones (BLOAD/RUN/DEF/USR/=/hex constant/compact integers); any other byte is represented as a {$XX} escape, see FINDINGS.md
│   ├── gen_inventory.py            ← regenerates the resource inventory in recursos/flujo_programa.html (729 labels, classified as function/internal/data/unreferenced) from src/build/main.lst -- run after any label change in the source code, see FINDINGS.md
│   └── gen_flow_diagram.py         ← regenerates recursos/flujo_detallado.html (Mermaid.js graph of real calls between "function" labels, colored by subsystem) from src/build/main.lst -- run after any label/call change, see FINDINGS.md
├── recursos/                       ← self-contained HTML viewers (see "HTML viewers" section below)
├── manuales/                       ← reference technical manuals (training + preservation), see manuales/README.md
│   └── manual_driver_sonido.md     ← how the PSG sound driver works (architecture, bytecode, tables, $6128, tools)
├── dump_openmsx/                   ← real RAM/VRAM dumps and PNG renders used to verify findings (candy frame, sprites, levels 13/14, etc.)
└── src/
    ├── main.asm                        ← real entry point: SINGLE compilation point for disk and tape (generates MADMIX1.BIN, MADMIX.SCR, madmix_cas_scr.bin, MADMIX0.BIN, TEST.BIN, LOAD.BIN, LOGOTOPO.CM)
    ├── madmix1_body.asm                ← engine body (part of MADMIX1.BIN) -- no longer separately compilable
    ├── madmix_scr_body.asm             ← body of the cover screen + main loop + levels (part of MADMIX.SCR) -- no longer separately compilable
    ├── load_disk/                      ← sources exclusive to the DISK version
    │   ├── madmix0_body.asm            ← body of MADMIX0.BIN (relocator, 58 bytes) -- no longer separately compilable
    │   ├── AUTOEXEC.bas                ← editable listing (detokenized with tools/msxbasic_tool.py) of AUTOEXEC.BAS
    │   ├── MADMIX.bas                  ← editable (detokenized) listing of MADMIX.BAS -- the real loader, does the BLOADs
    │   ├── boot_sector.bin/.txt        ← standard MSX-DOS boot sector (720KB), NOT game-specific -- boilerplate from the formatting tool, preserved verbatim for tools/gen_dsk_file.py
    │   └── MADMIX_dup.bin/.txt         ← 6th file on the original disk ("MADMIX" with no extension, almost identical to MADMIX.BAS, NOT part of the real boot process) -- verbatim copy, UNANALYZED, see .txt
    ├── load_cas/                       ← sources exclusive to the TAPE version (.cas)
    │   ├── load_bin_body.asm           ← body of LOAD.BIN (load orchestrator, 299 bytes) -- no longer separately compilable
    │   ├── test_bin_body.asm           ← body of TEST.BIN (RAM/slot detection, 253 bytes) -- no longer separately compilable
    │   ├── TOPO.bas                    ← listing as-is (already plain ASCII in the .cas) -- auto-runs the tape, loads the logo
    │   ├── MADMIX.bas                  ← listing as-is -- loads LOAD.BIN/TEST.BIN and invokes them
    │   ├── LOGOTOPO.CM.bin             ← the Topo Soft logo, binary reference copy (see LOGOTOPO.CM.txt)
    │   ├── logotopo_cm_body.asm        ← body of LOGOTOPO.CM (4254 bytes) -- COMPLETE, see FINDINGS.md
    │   └── LOGOTOPO.CM.txt             ← note explaining the status/history of LOGOTOPO.CM
    ├── data/
    │   ├── tiles/                      ← the maze's 91 tiles, 1 .til file per tile (32 bytes, 16x16 format)
    │   ├── sprites/                    ← the 64 character sprites, 1 .spr file per sprite (144 bytes, 24x24 format with 2 interleaved planes: mask+pattern, 6 bytes/row x 24 rows)
    │   ├── fonts/                      ← text fonts (.fnt extension), a single file per complete font (each glyph's position is computed by formula, requiring a contiguous block):
    │   │   └── fuente_caracteres.fnt   ← text font (59 glyphs of 8 bytes, codes $21-$5B)
    │   ├── img/                        ← the rest of the graphics that are neither tile, sprite nor font (.img extension):
    │   │   ├── portada_paleta.img      ← table of 16 values to decompress the cover art color
    │   │   ├── portada_patron.img      ← cover art bitmap (6144 bytes, uncompressed)
    │   │   ├── portada_color.img       ← cover art color, nibble-compressed (768 bytes)
    │   │   ├── marco_caramelo_forma.img ← shape of the candy frame (RLE table, 1740 bytes)
    │   │   ├── marco_caramelo_color.img ← real color of the candy frame (768 bytes)
    │   │   └── icono_vida.img          ← HUD extra-life icon (16x16, 32 bytes, tile-major byte order, not interleaved like .til)
    │   ├── demos/                      ← the 10 auto-play scripts for DEMO mode, 1 .dem file per script (pairs [duration in frames, simulated direction]; only 4 of the 10 are connected to a real level, see FINDINGS.md)
    │   ├── sound/                      ← PSG sound driver scripts, Topo Soft's own bytecode, already DECODED (see FINDINGS.md, "the 15 commands of the sound driver bytecode"). Organized into two subfolders by file type (see FINDINGS.md, "organization of data/sound/ into snd/ and spt/"). Each `.snd`/`.spt` (binary, compiled with INCBIN) has a twin `.txt` (own text format, one mnemonic per line — see `tools/mmsnd_tool.py`) which is the one edited by hand:
    │   │   ├── snd/                     ← the 16 real music/event scripts
    │   │   │   ├── 00_script_cdcb.snd/.txt      ← music, channel 0 (52 bytes)
    │   │   │   ├── 01_script_cdff.snd/.txt      ← music, channel 1 (13 bytes)
    │   │   │   ├── 02_boot_ch2_ce0c.snd/.txt    ← music, channel 2 (78 bytes)
    │   │   │   └── 03_evt09_....snd/.txt to 15_evt03_....snd/.txt  ← 13 individual sound effects, one per `$6128` event (previously treated as a single 383-byte block next to channel 2 — split apart this session, each with its event index and sound-catalog candidate in the name/comment)
    │   │   ├── spt/                     ← the 13 shared subpatterns ($CB9C-$CDCB, called via `CALL_SUBPATTERN` from the music scripts), `.spt` extension (same bytecode as `.snd`, `mmsnd_tool.py` treats them with no change at all — only kept apart so they don't get mixed up with the 16 real scripts) — previously inline `DB` in `madmix1_body.asm`, consolidated into their own file this session, see FINDINGS.md. Named by entry index in `TABLA_SUBPATRONES_PSG` (00-12), not by memory order (entry 12, `$CBB0`, falls in memory between entries 0 and 1): `00_subpatron00_cb9c.spt/.txt` .. `12_subpatron12_cbb0.spt/.txt`
    │   │   └── _engine_tables.bin      ← working copy of the complete `$C8DE-$CDCB` block (tone, instruments, envelope shapes AND the 13 subpatterns) so `mmsnd_render.py` has a single simulated memory block where it can resolve `CALL_SUBPATTERN` — it's still just a snapshot of the compiled bytes, not an editable source; the tone/instrument/envelope table still lives as inline `DB` in `madmix1_body.asm`, the subpatterns come from their own `.spt` files (INCBIN) in `spt/`, but the final bytes are identical in both cases, so this copy did not need to be regenerated
    │   └── niveles/                    ← raw bodies/headers for each level (13 bodies + 3 shared headers, includes level 15 -- previously believed "hidden/unused", confirmed real and playable in normal play, see manual_niveles.md and FINDINGS.md). Tile grids already DECODED (index 0-90 = real catalog in `data/tiles/*.til`, bit 7 = flag not confirmed at runtime). Each `.bin` (the one compiled with INCBIN) has a twin `.txt` (own text format, one hex byte per cell, one row per line — see `tools/mmlvl_tool.py`) which is the one edited by hand, same as the `.snd`/`.txt` sound pair:
    │       ├── body_l13.bin/.txt       ← COMPLETE body of level 13 (672 bytes = 21×32, full grid). UNLIKE the rest of this directory, this file and `body_l14.bin` compile inside MADMIX1.BIN (INCBIN in madmix1_body.asm), not in MADMIX.SCR — RESOLVED: it's the old `maze_data.bin`, split and later reunified, see FINDINGS.md "RESOLVED THE PURPOSE OF maze_data.bin". Previously split into `body_l13_head_cfa4.bin` (92B; previously `RM_TABLE_CFA4`/`BODY_L13_HEAD_CFA4`) + `body_l13_maze.bin` (580B) — unified: the first 92 bytes were NEVER sound data (old label discarded), they decode to a coherent maze room, same style as the rest of the real levels
    │       └── body_l14.bin/.txt       ← COMPLETE body of level 14 (736 bytes = 23×32, full grid). Previously split into `body_l14_maze.bin` (700B) + `body_l14_tail_demo1.bin`/`DEMO_SCRIPT_NIVEL1` (36B, previously believed to be the start of a demo script) — unified after confirming that LEVELCYCLE_TABLE ALWAYS pointed to `$D524`, never to `$D500`, so those 36 bytes were never a demo script: they were always the tail of level 14's body, same kind of error as `body_l13.bin`, see FINDINGS.md

> ⚠️ **WARNING — same limit as sound**: each `.bin` in `data/niveles/`
> compiles with `INCBIN` at a FIXED address. You can change the
> VALUE of any cell (which tile goes there) with no problem at all.
> **Changing the number of rows or columns of the grid, or the
> number of bytes of a flat fragment, is NOT safe**: it would shift
> the address of everything that comes after it in
> `madmix_scr_body.asm`/`madmix1_body.asm`.
> `tools/mmlvl_tool.py asm` rejects with an error any `.txt` that
> does not declare the same dimensions as the original.

**`LEVEL_TABLE`** (the 15 level registers, previously `niveles_tabla.bin`)
is NO LONGER a separate `.bin`: it was rewritten as a native data
table directly in `madmix_scr_body.asm` (`DW`/`DB`), with the
body/header pointers as real labels (`BODY_L01`, `HEADER_50BC`,
etc.) instead of loose hex — the assembler itself resolves the
correct address, and changing which body/header a level uses is as
simple as changing a label. Exception: levels 13 and 14 point to
addresses inside `MADMIX1.BIN` (a different binary, not linked with
this one), so those two specific pointers remain literal hex, with a
comment explaining which label they correspond to there.
See `FINDINGS.md` for the field-by-field detail of the 20-byte
register.
    ├── build/                      ← compiled binaries land here: build/madmix_reconstruido.dsk and build/madmix_reconstruido.cas are the FINAL DELIVERABLES (at the root); build/disk/ and build/cas/ hold each version's "ingredient" binaries, self-contained (and build/sound_preview/*.wav, the 16 sounds already rendered)
    ├── FINDINGS.md                 ← findings diary (chronological)
    ├── FLUJO_PROGRAMA.md           ← analysis by execution flow (boot, dispatch, subsystems) -- complements FINDINGS.md
    └── README.md
```

**Note on `data/tiles/`, `data/sprites/`, `data/fonts/`, `data/img/`, `data/demos/` and `data/sound/`**: each object (tile, sprite, image, demo script or sound script) lives in its own file — this way they can be edited/regenerated from outside the `.asm` without touching code. The `.asm` loads them with `INCBIN`, one after another in the exact order they appear in the original binary, so the memory layout stays byte-for-byte identical. Exception: **fonts** (`data/fonts/`) go in a single file per complete font, not one file per character — the code computes each glyph's address by formula (`base + code×8`), which requires them to be contiguous as a single table, and it's also how bitmap fonts are really edited (the whole character set at once). **Sound scripts** (`data/sound/`) use the `.snd` extension for the binary (the one the `.asm` compiles with `INCBIN`, byte-for-byte identical to the original) and `.txt` for its editable plain-text twin — the bytecode of the 15 commands is already decoded (see `FINDINGS.md`), so the `.txt` is the real way to edit them: modify the `.txt` and regenerate the `.snd` with `py tools/mmsnd_tool.py asm file.txt file.snd` before recompiling the game. The **13 shared subpatterns** (called via `CALL_SUBPATTERN` from the music scripts) use the SAME bytecode and the SAME tool, but with the `.spt` extension so they don't get mixed up with the 16 real event/music scripts. The driver's tone/instrument/envelope tables (`TABLA_NOTAS_PSG`, `TABLA_INSTRUMENTOS_PSG`, `TABLA_ENVOLVENTES_PSG`) stay as inline `DB` — they are the interpreter's fixed "machinery" (constant-size registers, not bytecode), not variable content belonging to any one specific script/subpattern.

> ⚠️ **WARNING — the real limit of what can be edited in the sound `.txt` files**: each `.snd`/`.spt` compiles with `INCBIN` at a FIXED address, taken straight from the original binary. Changing the VALUE of an existing instruction (a different note, duration, instrument...) is 100% safe. **Adding or removing instructions, or changing the count of a `SET_DURATION_MULTI`, is NOT safe**: if the total byte count changes, everything after it in `madmix1_body.asm` shifts address, and `LEVELCYCLE_RESOURCE_TABLE` (in `madmix_scr_body.asm`, which triggers each sound via `$6128`) is left pointing at the OLD address — the game would compile with no errors at all but would jump to the wrong places at runtime. For `.spt` files the risk is the same but with bigger impact: `TABLA_SUBPATRONES_PSG` (`madmix1_body.asm`) points to each one by real address via a label, so changing the size of ONE subpattern shifts ALL the ones that come after it in memory and breaks the pointers of anything already compiled before that change. This same warning is repeated at the top of every `.txt` the tool generates.

### Pixel sizes for each format (to view/edit with YY-CHR, Tilemap Studio, GIMP, etc.)

All of them are monochrome, 1 bit per pixel, MSB first — the
simplest "raw" format supported by any tile/CHR editor. All of them
go in linear row-by-row order with no interleaving, **except
`data/sprites/`**, which interleaves 2 planes (AND mask +
OR pattern/ink, see `recursos/ptrtable_sprites.html` and
`manual_subsistema_grafico.md` §4) row by row: 3 mask bytes + 3
pattern bytes for each of the 24 real rows:

| Folder | Extension | Pixel size | Bytes/row | Bytes per file |
|---|---|---|---|---|
| `data/tiles/` | `.til` | 16×16 | 2 | 32 |
| `data/sprites/` | `.spr` | 24×24, 2 interleaved planes (mask+pattern) | 6 (3+3) | 144 |
| `data/fonts/` | `.fnt` | 8×8 per glyph (59 glyphs in a row) | 1 | 472 (59×8) |
| `data/img/marco_caramelo_forma.img` | `.img` | — (RLE table, not a plain bitmap) | — | 1740 |
| `data/img/marco_caramelo_color.img` | `.img` | — (VRAM color attributes, not a bitmap) | — | 768 |
| `data/img/portada_patron.img` | `.img` | 256×192 (full screen) | 32 | 6144 |
| `data/img/portada_color.img` | `.img` | — (nibble-compressed color, not a plain bitmap) | — | 768 |
| `data/img/portada_paleta.img` | `.img` | — (table of 16 values) | — | 16 |
| `data/img/icono_vida.img` | `.img` | 16×16 (2×2 patterns of 8×8, tile-major order, NOT interleaved like `.til`) | 1 (per 8×8 pattern) | 32 |

Note: not all `.img` files are plain bitmaps directly editable as an
image — the ones marked "not bitmap" are compressed or are
attribute/color tables, they need to go through their real
transformation (see `FINDINGS.md`) before they make visual sense.

## HTML viewers (`recursos/`)

Self-contained pages (no external dependencies) that open directly
in the browser:

- **`graficos.html`** — the 91 identified maze tiles, with a 4×4
  composition area to test fits.
- **`niveles.html`** — the 15 real levels reconstructed with the
  tiles, from the table discovered in `MADMIX.SCR`. The 15th
  (`0x48BC-0x4AFC`) was first documented as "hidden/unused" --
  **RESOLVED**: it DOES have its own register in `LEVEL_TABLE` (register
  15, previously mislabeled as "20 bytes unidentified" right after
  register 14) and it IS reachable in normal play
  (`LEVEL_LOADER` has no cap of its own; the level counter passes
  through 15 before resetting to 1 when the cycle completes, see
  `FINDINGS.md`) — visually confirmed as a real maze shaped like
  Pac-Man, and **actually tested by playing it in openMSX**
  (patching a copy of the `.dsk` so level 1 points to it): it walks
  normally, confirming it is real, playable content, not noise (see
  `FINDINGS.md` for the patch details and the expected quirks from
  reusing another level's metadata in that test, done before its
  real register was found).
- **`portada.html`** — the cover screen reconstructed from the raw
  data in `MADMIX.SCR`.
- **`mapa_memoria.html`** — a complete map of RAM (0x0000-0xFFFF)
  with the origin of each zone and which file it comes from (with
  braces over the bar marking the final/permanent position of each
  of the 3 binaries), a living document that grows as more is
  discovered.
- **`mapa_memoria_logotopo.html`** — same visual template as
  `mapa_memoria.html` but with its own scale limited to the
  `LOGOTOPO.CM` range (0x9470-0xA50D, 4254 bytes, the Topo Soft logo
  of the tape version). **COMPLETE**: the whole file transcribed,
  verified byte for byte and visually confirmed — see
  `src/load_cas/logotopo_cm_body.asm` and `FINDINGS.md`.
- **`logotopo_formas.html`** — renderer for the 15 animated "shapes"
  of `LOGOTOPO.CM` (monochrome 8x8 tiles, adjustable columns per
  card), each with its real name confirmed by the developer (T/O/P/O
  letters from "Topo", 7 frames of "Soft" rotating, 4 frames of the
  star).
- **`ptrtable_sprites.html`** — the 64 graphic entries of
  `PTR_TABLE_91C3` (`madmix1_body.asm`, inside the large gap
  `0x92E3-0xB940` still undeciphered at the time), rendered as a raw
  bitmap in 3 different views, with no interpretation yet at that
  point — the starting point for deciphering the rest of the
  graphics gap.
- **`flujo_programa.html`** — visual companion to `FLUJO_PROGRAMA.md`:
  the large flow diagram (boot → dispatch table → main loop →
  subsystems) plus the full, searchable inventory of labels across
  all source files (engine, screen, disk and tape loaders) —
  regenerated with `tools/gen_inventory.py`, which resolves the real
  file/line from the sjasmplus listing (necessary because some
  addresses are deliberately reused across files, e.g.
  `TEST.BIN`/sound driver at `$C350`, see FINDINGS.md). Living
  document.
- **`flujo_detallado.html`** — real call graph (Mermaid.js),
  generated by `tools/gen_flow_diagram.py` from
  `src/build/main.lst`: one node per "function" label (target of at
  least one `CALL`), colored by subsystem (boot, menu, engine,
  items, HUD, graphics/VRAM, sound), with edges = real `CALL`s
  between them (dotted + condition code if the `CALL` is
  conditional). Deliberate scope: it does NOT include the tile-type
  handlers nor the rest of the "internal" labels (only reached by
  `JP`/`JR`, never `CALL`) — see the note in the HTML itself for the
  exact detail of what is left out and why. Living document,
  regenerate after renames with `py tools/gen_flow_diagram.py`.
- **`flujo_secuencial.html`** — step-by-step (non-graph) variant of
  the same execution flow as `flujo_detallado.html`, colored by
  subsystem (boot, engine, items, HUD, menu, sound, graphics,
  decision); useful for following the linear sequence without a
  node-graph's visual complexity.
- **`editor_niveles.html`** — visual editor for the tile grids in
  `data/niveles/` (13 bodies + 3 headers, the 15 real levels):
  palette of the 91 real tiles (reuses the decoder from
  `graficos.html`), paint with click/drag, live ball counter against
  the real target in `LEVEL_TABLE`, and buttons to open/download the
  same `.txt` format used by `tools/mmlvl_tool.py`
  (self-contained, no server — saving is a file download, not a
  direct disk write). Headers are read-only (shared across several
  levels). Levels 13 (`body_l13.bin`, 21×32) and 14 (`body_l14.bin`,
  23×32) are each a single file, like any other level — both used to
  be split across two files until it was confirmed that those splits
  came from wrong deductions in old sessions (level 13 shared
  nothing with sound; the last 36 bytes of level 14 were not a
  reassigned demo script); unified and consolidated (see
  `FINDINGS.md`). Level 15 (`body_l15.bin`) is just as normal:
  it has its own register in `LEVEL_TABLE` (register 15) and is
  reached by playing normally after completing level 14 — the
  "hidden level" label from this same project's earlier analysis has
  been dropped, see `manual_niveles.md` §4 and `FINDINGS.md`. It does
  not validate item/enemy positions (coordinate tables aside, out of
  scope for this first pass).
- **`mmg_poster_dossier.html`** — single-page visual poster/dossier
  summarizing the project (poster format), meant to show the work at
  a glance without navigating the rest of the viewers.

## Building

```
py tools/build_all.py
py tools/gen_disk_and_cas.py
```

The first script compiles ALL the source code (equivalent to
`sjasmplus src/main.asm`, invoked with the right working directory
and creating `src/build/disk/`/`src/build/cas/` if needed). The
second one takes those already-compiled binaries and generates the 2
final deliverables: `src/build/madmix_reconstruido.dsk` and
`src/build/madmix_reconstruido.cas`. Both verify their own inputs and
raise a clear error if something is missing (e.g. if the first step
is skipped).

**The `.dsk` is built FROM SCRATCH** (`tools/gen_dsk_file.py`): the boot
sector, the 2 FAT12 tables, the root directory and the data area are
all assembled by the script itself -- it does not start from a copy
of the original `.dsk` to patch on top of it (as it used to do
before). The only 2 pieces that are not derived from anything (the
standard MSX-DOS boot sector and a 6th file on the disk unrelated to
the real boot process) are preserved as verbatim resources in
`load_disk/` -- see `gen_dsk_file.py` itself and `FINDINGS.md` for
the full detail of the real FAT12 format.

Each cluster's tail padding (the part of a file that doesn't fill
its last cluster completely) is filled with ZEROS, not with the
original disk's real content: the original floppy is a REUSED
medium, and that padding contains readable leftovers from a previous
unrelated use (see `FINDINGS.md`) — it's not worth preserving someone
else's "garbage" just for byte-for-byte fidelity, since MSX-DOS never
reads that zone (it only uses the size declared in the directory).
That's why the byte-for-byte comparison against the original `.dsk`
no longer gives just 9 differences, but those 9 plus the size of each
file's tail padding — all inside zones with no functional effect at
all.

These two scripts are the equivalent of "building the whole project
in one go" — the rest of this section details what each piece does
internally, in case something needs to be run on its own (e.g. just
`sjasmplus src/main.asm` without regenerating `.dsk`/`.cas`, or just
`tools/gen_cas_file.py` after changing only something in
`load_cas/`).

```
sjasmplus src/main.asm
```

The single compilation point for the raw binaries, for disk and
tape at once (what `tools/build_all.py` does internally). Generates:

- `build/disk/MADMIX1.BIN` and `build/cas/MADMIX1.BIN` — the game
  engine, two IDENTICAL copies (the same `SAVEBIN` called twice): it
  is exactly the same binary in both editions (verified, see
  `FINDINGS.md`), but each folder is kept SELF-CONTAINED — everything
  needed to generate its `.dsk`/`.cas` lives inside it.
- `build/disk/MADMIX.SCR`, `build/disk/MADMIX0.BIN` — specific to
  the **disk** version (`MADMIX.SCR` with a physical BLOAD header at
  `$8800`; `MADMIX0.BIN` the "relocator",
  `load_disk/madmix0_body.asm`).
- `build/cas/madmix_cas_scr.bin` (the logical body of `MADMIX.SCR`,
  without the BLOAD header), `build/cas/TEST.BIN`,
  `build/cas/LOAD.BIN` — specific to the **tape** version
  (`load_cas/test_bin_body.asm`/`load_bin_body.asm`).

**`madmix1_body.asm`/`madmix_scr_body.asm`/`load_disk/madmix0_body.asm`/
`load_cas/*_body.asm` are NO LONGER separately compilable**: they all
share a single symbol space inside `main.asm` (so cross calls use
real labels instead of hex), so each one needs the others' labels to
resolve — compiling any of them alone would fail with undefined
symbols. `main.asm` is the one real entry point.

Non-trivial technical detail (see `FINDINGS.md` for the full
analysis): `TEST.BIN` lives at `$C350`, the same physical address
used by the sound driver in `madmix1_body.asm` (transient RAM reuse,
just like on the real machine) — that's why the `MADMIX1.BIN` block
goes BEFORE the `TEST.BIN` one in `main.asm`: `SAVEBIN` captures a
snapshot of the buffer at the moment it is itself called, so block
order matters.

### Tape version (`.cas`)

```
py tools/gen_cas_bin.py
```

Generates `build/madmix_cas.bin` (at the ROOT of `build/`, the final
deliverable — `build/cas/` only holds the "ingredient" binaries):
`build/cas/madmix_cas_scr.bin` (real destination `$1000`) followed,
with NO padding, by `build/cas/MADMIX1.BIN` (real destination
`$8400`) — verified that this is exactly how the real `.cas`
concatenates its blocks (both the 1988 original and the 2013 v2.0
re-release): each tape block carries its own destination address in
its header, so no memory gap is needed between them in the file
itself. `build/madmix_cas.bin.txt` is also written, a short manifest
with the 2 offsets/destinations/lengths.

```
py tools/gen_cas_file.py
```

Generates `build/madmix_reconstruido.cas` — a REAL, complete `.cas`
(real sync, name and header blocks, standard MSX emulator format),
packaging `load_cas/TOPO.bas`, `load_cas/MADMIX.bas`, and
`build/cas/LOGOTOPO.CM`/`LOAD.BIN`/`TEST.BIN`/`madmix_cas_scr.bin`/
`MADMIX1.BIN` — all 5 tape binaries now come from our own source
compiled by `main.asm` (`LOGOTOPO.CM` is no longer copied verbatim
from the reference `.bin`, see `load_cas/logotopo_cm_body.asm`).
**Verified byte for byte against the original 1988 `.cas`: only 9
differences, the 3 already known** (the deliberate `$FC60→$FC50`
fix, the preexisting unrelated difference at `$28ED-$28EF`, and the
stray final byte of `MADMIX1.BIN` — exactly the same categories as
in the `.dsk` comparison, see `FINDINGS.md`).

### Disk BASIC (tokenized)

```
py tools/msxbasic_tool.py tok src/load_disk/AUTOEXEC.bas src/build/disk/AUTOEXEC.BAS
py tools/msxbasic_tool.py tok src/load_disk/MADMIX.bas src/build/disk/MADMIX.BAS
py tools/msxbasic_tool.py roundtrip src/build/disk/AUTOEXEC.BAS
```

`load_disk/AUTOEXEC.bas`/`MADMIX.bas` are the already-detokenized
listings (editable as plain text); `tok` re-tokenizes them to
produce the real `.BAS`/`.BIN` the disk expects. PARTIAL token table
(see `tools/msxbasic_tool.py`) — only covers what's been empirically
verified; any unidentified byte is preserved exactly via a `{$XX}`
escape in the listing.

## Testing it (reusing the original .dsk)

`py tools/gen_disk_and_cas.py` (see "Building" above) already
generates `src/build/madmix_reconstruido.dsk` ready to open in
openMSX — what follows below is the manual, step-by-step equivalent,
in case you need to inject into ANOTHER copy of the disk (not the
one that script uses). Requires
[mtools](http://www.gnu.org/software/mtools/) — unlike the main
flow, which doesn't need it at all.

No need to touch `AUTOEXEC.BAS` or `MADMIX.BAS` — they keep working
as-is. We replace the reconstructed binaries inside a COPY of the
original disk:

```
copy Mad_MIX_Game.dsk copia.dsk
mcopy -o src/build/disk/MADMIX1.BIN -i copia.dsk ::MADMIX1.BIN
mcopy -o src/build/disk/MADMIX.SCR -i copia.dsk ::MADMIX.SCR
mcopy -o src/build/disk/MADMIX0.BIN -i copia.dsk ::MADMIX0.BIN
```

And then boot `copia.dsk` in openMSX like the original disk.

## Pending before they are complete binaries

1. ~~Reproduce the memory relocation (`PHASE`/`DEPHASE`)~~ —
   tried and implemented in `madmix1_body.asm`, but then DISCARDED there:
   a live memory dump showed that the `MADMIX1.BIN` engine runs
   from static addresses. **It IS used, correctly, in
   `madmix_scr_body.asm`** — that's the real case where it applies
   (also confirmed live).
2. ~~Fill the `DS` gaps in `madmix1_body.asm` with real content~~ —
   **FULLY DONE: `madmix1_body.asm` no longer has any pending `DS`
   gap, 0 differences byte for byte from start to end
   (`0x8400-0xDDA1`).** The last tail, `0xD500-0xDDA1` (2209 bytes),
   turned out to be: **10 auto-play scripts for DEMO
   mode** (`0xD500-0xD6B6`, 438 bytes, pairs `[duration in
   frames, simulated address]` ending in `$FF`) —
   consumed by `TAIL_LEVELCYCLE_MAIN` via `LEVELCYCLE_TABLE`, which
   only references 4 of the 10 (levels 1/2/4/5); the other 6 are
   real, unconnected scripts (unlike level 15, which at one point
   also looked "unconnected" but turned out to have a real register
   in `LEVEL_TABLE` — see below; these 6 scripts still have no known
   pointer that uses them);
   **THE CANDY FRAME ITSELF!** (`TABLA_RLE_MARCO_CARAMELO`,
   `0xD6B6-0xDD82`, 1740 bytes) — an RLE table whose 870
   repetitions add up to exactly 6144 bytes (the full VRAM pattern
   table), confirmed by rendering it: red-and-white stripes,
   rounded corners and highlight, pixel for pixel matching the
   real screen reconstruction (see the candy frame section below
   for details). Along the way, a sub-range of this same table
   (from `$DC00`) turned out to have a SECOND use — read
   ad hoc as 16-bit AND/OR masks to compose
   sprites (`CALCULAR_DIRECCION_MASCARA_ACTOR`/`COMPONER_ACTORES_EN_BUFFER`) — this resolves
   the "0xDC00 zone" that had been left as "undeciphered" in an
   earlier session's finding; and two real code fragments at the end
   (`SLOT_RESTART_DD82`, with no known caller, and
   `CONFIGURAR_Y_LEER_JOYSTICK_PSG`, the confirmed target of an
   already-existing `CALL` in `LEER_JOYSTICK`), plus `$FF` padding
   and one final orphan byte
   (`$CD` at `0xDDA0`, outside the actually loaded range). See
   `FINDINGS.md` for the full detail. The old "big gap"
   (~10,700 bytes, already resolved before this final tail) ended
   up fully resolved and documented in layers: (a) 449 bytes of the
   real continuation of `INIT` (`INIT` never does a `RET`, it falls
   into the MAIN GAME LOOP); (b) 429 bytes of never-before-seen
   in-game text (`"FASE 00"`, `"READY?"`, `"ESTAS FRITO"`, extra-life
   notice) and the 64-pointer table `PTR_TABLE_91C3`; (c) 600
   bytes of **character font** (`FONT_TABLE_9363`,
   `0x92E3-0x953B`) confirmed via the real
   `DIBUJAR_TEXTO_INVERTIDO_VRAM` formula (`glyph = $925B + code*8`) — codes `$11-$20` are
   real zeros (control/blank space), and from `$21` to `$5B` the
   59 real glyphs; (d) **THE CHARACTER SPRITES ARE ALREADY
   IDENTIFIED AND TRANSCRIBED!** (`0x953B-0xB93B`, 9216 bytes, 64
   sprites, 0 differences byte for byte) — the developer (the original
   player) identified them at a glance by looking at
   `recursos/ptrtable_sprites.html`: Pac-Man
   (vulnerable/invincible with mouth phases, plane, "obra"/
   ball-releasing, hippo, tank), ghost (normal/vulnerable/dead),
   ladybug, "repugnantoso", the complete death sequence of
   Pac-Man and the points marker for eating a ghost (400/600).
   Key gameplay fact: **there are no left-facing sprites**,
   only right/down/up — the right-facing one is horizontally
   flipped at runtime (see `FINDINGS.md` for the full catalog and
   the code routines,
   `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`
   — the exact mechanism of bit 7 is parked, it requires live
   tracing); (e) 5 bytes of unidentified tail
   (`0xB93B-0xB940`: `$00,$FF,$FF,$FF,$FF`) right before
   `TILE_GFX`, which now lands at its real address `0xB940` for
   the first time. **THE "CANDY FRAME" IS ALREADY LOCATED AND
   VISUALLY CONFIRMED!** It was in the RLE table in the final tail
   (`TABLA_RLE_MARCO_CARAMELO`, `0xD6B6-0xDD82`, inside this same
   gap — see item 2 below): the 870 repetitions of its
   `(value,repeat)` pairs add up to exactly 6144 bytes (`$1800`, the
   full SCREEN2 VRAM pattern table). Expanding the RLE and
   rendering it with the identity name table (confirmed against a
   real VRAM dump) produces the complete, recognizable frame:
   diagonal red-and-white stripes, rounded corners on all 4 corners
   and the highlight motif — pixel for pixel matching
   `dump_openmsx/screen_reconstructed.png` (render at
   `dump_openmsx/candy_frame_reconstructed.png`, see
   `FINDINGS.md`). It is not a 16×16 tile like the ones in
   `TILE_GFX` — it is the entire screen pattern table generated all
   at once by design, and it only survives around the edges because
   the maze drawn on top occupies the center. **AND THE REAL COLOR
   OF THE FRAME IS ALSO LOCATED!** The routine that consumes the
   768-byte block at `$60FE` (`TAIL_CREDITS_MAIN` +
   `TAIL_TILE_LOOKUP`, in `madmix_scr_body.asm`, nibble-swap against
   `DIRBITS_TABLE` in `madmix1_body.asm`, solid fill via `FILVRM`) —
   which an earlier session had investigated and dismissed as
   "background texture/shading, not the frame" — turned out to be
   exactly that: **the real color (dark red/gray/white) of the candy
   frame**, applied to the VRAM color table. Verified by applying the
   real transformation to the 768 bytes and comparing against a real
   VRAM dump: matches exactly, byte for byte (see `FINDINGS.md`). The
   earlier conclusion was wrong because it rendered the bytes as a
   pattern (black/white) instead of as color attributes.
   ~~Resource manager (`0xC4A0-0xD000`)~~ —
   **done**, 0 differences byte for byte across the 2912 bytes
   (verified by compiling the isolated block with `ORG $C4A0`, see
   `FINDINGS.md`): it turned out to be the **PSG (AY-3-8910) sound/
   music driver**, not a generic resource manager — it matches the
   real credit "MUSIC-A BY: COMILONAS" (see below, note about the
   real spelling). It was confirmed that
   `LOAD_RESOURCE_SLOT_EMPTY` is at `0xCF8B`, as already
   suspected. ~~The 7 small unidentified code gaps
   (`JT_SLOT5/6/7/8/9`, 0x8431-0x8EC4)~~ — **done**, 0 differences
   byte for byte across the ~1,531 real bytes (the gap at 0x8431
   didn't count, it was an already-zeroed RAM variable zone).
   Findings: `INSTALL_ISR` (JT_SLOT5, $881B) is real, without the
   initial `DI` that an earlier made-up stub had (removed); the
   `ISR` had 3 real bugs (a missing symmetric `PUSH AF`/`POP AF`,
   a missing VDP status-read block, and it ended in `RETI`
   instead of `RET`); `GESTIONAR_FRAME` did much more than the
   stub said (it calls `CONTINUAR_CAPTURA_MASCARAS_ACTORES`,
   `RESET_CONTADOR_ACTORES` and a new routine at `$8CFF`);
   `JT_SLOT8`/`JT_SLOT9` ($89AD/$8C34) are the
   **software camera scroll** (up/down/sideways) plus the
   life-counter drawing; `TILE_TYPE_LOOKUP` and
   `REDRAW_STRIP` had stubs that did not match the real code;
   a **deferred-redraw queue** (`QUEUE_*`) was found,
   and `JT_SLOT7` ($8D70) turned out to be the **score marker
   drawing**, with two curious alternate texts: "BESTIA" (if the
   score reaches 10000) and " DEMO " (in demo mode);
   `JT_SLOT6` ($8E3C) is the **keyboard/joystick reading**.
3. ~~Transcribe the collision/movement engine (`0x2CA0-0x335C`)~~
   — done, 0 differences byte for byte. ~~Transcribe the bodies and
   headers of the 14 levels (`0x335C-0x511C`)~~ — done, 0
   differences byte for byte across the 7616 bytes (see
   `src/data/niveles/`); along the way a **15th level** was
   discovered at `0x48BC-0x4AFC` (`BODY_HIDDEN_48BC`), at the time with
   no known register in `LEVEL_TABLE` — **visually
   confirmed** (see `recursos/niveles.html`, which already includes
   this level 15): the walls draw
   the silhouette of a Pac-Man bordered with one-way tiles. It fits
   with the game "supposedly" having 15 levels, though all 15 were
   never located by playing or in external sources.
   **Later update**: it does have a real register in
   `LEVEL_TABLE` (register 15, previously mislabeled) and is reached
   by playing normally after completing level 14 — it is not a
   "hidden/unused" level, it is just one more normal level; see
   `manual_niveles.md` §4 and `FINDINGS.md`. ~~Transcribe the special-item
   activation subsystem (`0x5478-0x5904`)~~ — done, 0 differences byte for byte
   across the 1164 bytes. ~~Transcribe `0x511C-0x545F`~~ — done, 0
   differences byte for byte across the 835 bytes; it turned out to be much more
   than a position table: it held `HELPER_5278`/`HELPER_53A2`
   (the two missing helpers from the item subsystem) and
   `R51FE_MAIN`, a third activation routine called from the
   main loop. ~~Transcribe the `0x5AD5-0x6500` tail~~ — done,
   0 differences byte for byte across the 2603 bytes; it turned out to be **the
   game's main menu screen** (keyboard/joystick/
   key redefinition/demo) with real self-modifying code, plus
   **the original credits** — real text, byte for byte, WITHOUT
   "correcting" the spelling (see `FINDINGS.md`): "POGRAMADO BY:
   RAPHAEL GOMEZZZ..", "GRAPHICOS BY : ROBERTO P.ACEBES",
   "MUSIC-A BY: COMILONAS", "TOPOSHOW -1988-". **`madmix_scr_body.asm`
   no longer has any pending `DS` gap** (except for 2 already
   documented bytes unrelated to this task: `0x28ED-0x28F0` and the
   stray byte at `0x6500`). ~~Plain-hex text tables~~ — **done**:
   `MAINMENU_TEXT`, `KEYMENU_TEXT_5E03` and
   `TAIL_CREDITS_TEXT` (and `BESTIA_TEXT`/`DEMO_TEXT`/
   `SCORE_DIGIT_BUFFER` in `madmix1_body.asm`) were rewritten from
   loose hex bytes into literal strings (`DB "TEXT"`) wherever the
   original most likely wrote them that way — more faithful to the
   project's human-readability goal, 0 differences byte for byte
   re-verified after the change.
4. ~~Decipher the 6 level-metadata bytes that remain
   unidentified (offsets 8, 9, 10, 11, 18, 19 of the 20-byte
   register)~~ — **done for 4 of the 6** (see `FINDINGS.md`, along
   the way an arithmetic error from an earlier note was fixed, one
   that called "offset 11" what is actually offset 8).
   Offsets 8/9/10: number of item type 3/1/2 for this level
   (confirmed, all three item-subsystem handlers read them as a
   loop counter). Offset 11: duration in frames of the
   special ball/track blink before changing state (confirmed by
   real code in the main loop — a countdown compared against a
   threshold, with a blink-style parity test). ~~Offsets 18 and 19~~ — **RESOLVED**: it is
   the target number of "balls to eat" to mark the level as
   completed — `IML_90B7` (main loop, `madmix1_body.asm`) compares
   these two bytes (`$2C05`, 16 bits) against `$2C08` (the real
   counter, incremented by 4 collision-engine handlers each time a
   ball/special ball is eaten) and only then advances the level.
   Verified by directly counting the "floor with ball" tiles
   (`0x2D`/`0x2E`/`0x2F`) in each level's real body: it matched
   **exactly** in only 5 of the 13 levels checked at first (1,
   8, 10, 12 and 13 — the latter with its body "borrowed" from
   `MADMIX1.BIN`, see item 5). **FULLY RESOLVED afterward**: the
   arrow tiles (`0x33`-`0x36`) also count as a ball when stepped on
   (`HANDLER_2F18`/`2F50`/`2F88`/`2FC0` increment the same
   counter) — adding them in, **all 12 real levels match exactly,
   with no exception** (see `FINDINGS.md`, "mystery closed -- arrows
   also count as a ball").
5. ~~Determine the real purpose of `maze_data.bin`~~ — **RESOLVED** (and
   corrected later, see below).
   `LEVEL_LOADER` uses the body pointer from `LEVEL_TABLE`
   directly, with no address conversion. For levels 0-12
   that pointer falls inside the relocated copy of `MADMIX.SCR`
   (`0x1000-0x6500`), but for levels **13** and **14** the
   real pointers (`0xCFA4` and `0xD244`) fall inside the
   STATIC range of `MADMIX1.BIN` — since both files coexist in RAM
   at runtime, the loader ends up reading these two levels' bodies
   directly from resident memory: level 13 reads
   92 bytes from `BODY_L13_HEAD_CFA4` + 580 bytes from
   `body_l13_maze.bin`; level 14 reads its full 736 bytes from
   `body_l14.bin`. **Proof that this is deliberate design**: level
   13's body ends EXACTLY (`0xCFA4+672=0xD244`) where level 14's
   pointer begins — it can't be a coincidence. Rendering the real
   bodies with the tile decoder (they were already in
   `recursos/niveles.html` from an earlier session, see also
   `dump_openmsx/level13_from_madmix1_memory.png` and
   `level14_from_maze_data.png`) produces **complete, symmetrical,
   playable mazes**, with no trace of noise. The old
   `maze_data.bin` (later split into `body_l13_maze.bin` +
   `body_l14.bin`) is a real design piece, placed on purpose in
   `MADMIX1.BIN` as a shared/reused data source to save space
   instead of duplicating ~1.4 KB of level data inside
   `MADMIX.SCR`.

   **Correction about `0xCFA4` (previously `RM_TABLE_CFA4`)**: it was
   labeled in an old session as "possible sound envelope/percussion
   table" just because of its proximity to the real sound tables —
   never confirmed, and with the sound driver now fully
   disassembled it was confirmed that no sound routine reads it.
   Decoding its 92 bytes as tiles, the content is a coherent,
   symmetrical maze room (walls, floor with ball, power-ball item,
   stars), just like any other real level — it was never sound
   data, it was always the head of level 13's body; renamed to
   `BODY_L13_HEAD_CFA4`.

   **Correction about the last 36 bytes of level 14 (previously
   `DEMO_SCRIPT_NIVEL1`, `0xD500-0xD524`)**: from the same kind of
   error, an old session deduced they were the real start of the
   "level 1" demo script — only reassigned by `LEVELCYCLE_TABLE` to
   `0xD524` for some reason. False: `LEVELCYCLE_TABLE` has ALWAYS
   pointed to `0xD524`, never to `0xD500` (verified in the table
   itself, `madmix_scr_body.asm`), so those 36 bytes were never
   executed as a demo script — they were always the tail of level
   14's body. Unified with the head (previously `body_l14_maze.bin`,
   700 bytes) into a single editable file, `body_l14.bin` (736 bytes
   = 23×32), like any other level. The real demo label
   `DEMO_SCRIPT_NIVEL1` now lives where it always was in
   practice: `0xD524`. See `FINDINGS.md` for the full detail of
   both corrections.
