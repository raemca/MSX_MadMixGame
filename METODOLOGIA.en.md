# Project methodology — how Mad Mix Game (reverse engineering) was made

*Process documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com), with Claude (Anthropic) as technical assistant*

## 0. What this document is and is NOT

This project already has three documents explaining the technical
**result** from different angles:

- `src/FINDINGS.md` — the chronological findings diary, with
  all the reasoning, the dead ends and the corrections,
  in the order they happened.
- `src/FLUJO_PROGRAMA.md` — the same knowledge reorganized by
  execution flow, to read the game engine in one go.
- `manuales/` — reference manuals per subsystem, meant as
  training material, with the research process left out.

None of the three explains **the process itself**: how the work was
done, with what discipline, in what order the problem was tackled,
what tools were built and why, and what mistakes were
made and corrected along the way. That's the goal of this
document — a different zoom level, that of the *method* rather than
the *result*.

*(See also `REFLEXION_COLABORACION_IA.md` for the separate analysis
of how the collaboration between a person and an AI assistant
actually worked throughout this project — this document focuses
on the technical process itself.)*

## 1. Starting point

The stated goal from the start (see the header of
`FINDINGS.md`) is to reconstruct *Mad Mix Game* (Topo Soft, 1987/88,
MSX1) as **real, assemblable source code**, verified byte for byte
against the original binaries — not a clone, not a free
reimplementation, but the reconstruction of the actual lost source
code, including its bugs, its odd design decisions and its real
programming style of the era.

The starting material was minimal: the files from a 1987/88
floppy disk (`AUTOEXEC.BAS`, `MADMIX.BAS`, `MADMIX0.BIN`, `MADMIX1.BIN`,
`MADMIX.SCR`) and, later, a 1988 cassette tape with a different
layout of the same binaries. No original source code, no
symbol maps, no documentation from Topo Soft — only the compiled
binaries and the playable game itself in an emulator.

The work started as a series of loose chat sessions on
claude.ai (static analysis with `z80dasm` and manual byte-by-byte
inspection, with no emulator or debugger), and at some point moved to
Claude Code, with `FINDINGS.md` working from then on as an
explicit "context bridge" between sessions — the file's own first
line literally says so. The public Git repository is
much more recent than the work itself: it was initialized on August
8, 2026 with a dump of the progress already reached up to that
point; `FINDINGS.md` itself contains references to dates from
mid-July, so the real work had already been going on for weeks
before there was version control.

## 2. The guiding principle: byte-for-byte verification as a trust contract

If there's a single idea that explains how this whole
project was built, it's this: **no claim about the code is taken as
settled until it's verified against the real bytes of the original
binary**. Not "I think this is how it is", but "I compile this
isolated block and compare it, byte for byte, against the real
`.BIN`/`.dsk`/`.cas`".

This discipline shows up again and again in `FINDINGS.md`, almost
like a refrain: *"0 differences byte for byte"*, *"verified by
compiling the isolated block with `ORG $C4A0`"*, *"confirmed against
a real VRAM dump"*. It's not a minor technical detail — it's the
mechanism that has let a project with hundreds of rounds of changes,
renamings and reorganizations **never silently drift**
away from the original without anyone noticing. Every hypothesis
(what does this routine do? what format does this data have?) was
treated as provisional until there was an objective check that
confirmed or ruled it out.

Concrete examples of this discipline applied in practice:

- The **full memory map** (`0x8400`-`0xDDA0` of
  `MADMIX1.BIN`, and the equivalent for `MADMIX.SCR`) was declared
  "complete" only when recompiling reproduced the original binary
  with 0 differences in every stretch, stretch by stretch.
- The **64 character sprites** were first located by a
  structural clue (a table of 64 pointers with a fixed 144-byte
  stride falling inside an undeciphered gap), but they were **not
  considered resolved until the user, the game's original
  player, identified them at a glance** on a raw render with no
  prior format hypothesis at all — combining structural
  evidence (from the AI) with lived knowledge (from the user).
- The reconstructed **`.dsk`/`.cas`** are not considered finished
  because "they compile with no errors" — they're considered
  finished because they're generated from scratch (without starting
  from a copy of the original to patch) and the byte-for-byte
  comparison against the real originals gives a **closed and
  explained** list of differences (the deliberately fixed
  level-13 bug, and a handful of already-documented unrelated bytes)
  — never an open list of "weird unexplained stuff".
- In this very session, while correcting the real sprite format
  (see §10), the verification was empirical before it was
  theoretical: three regrouping hypotheses for the same bytes were
  tested by rendering them, and only the one that left no
  visual artifact unexplained was adopted — "looks reasonable" was
  not accepted, "looks clean across all 64 entries" was required.

## 3. Phases of the work, in order

### Phase 0 — Startup: the disk's three binaries

Manual disassembly of `MADMIX0.BIN` (58 bytes, the "relocator" —
it turned out to have **two independent entry points**, not one, an
early finding that forced a revision of the first hypothesis) and
locating the full boot sequence from the tokenized
`.BAS` itself (confirming byte for byte, in the raw BASIC dump,
the exact address `&HFA2A` that starts the real engine).

### Phase 1 — Basic architecture: memory, interrupts, VDP

Initial memory map of `MADMIX1.BIN`, identifying the
VBLANK interrupt vector hot-patched in, and a custom
reimplementation (not the BIOS) of the 3 classic VRAM access
routines (`FILVRM`/`LDIRVM`/`SETVRAM`) — confirmed to be contiguous
in memory and with small real differences from what had
initially been assumed (nested loops instead of a 16-bit
subtraction, long jumps instead of short ones, an `EX (SP),HL`
delay the VDP itself requires).

### Phase 2 — The tile system and the collision engine

Locating the tile-type table (with an offset
and size error fixed by reading the `.BIN` byte by byte) and, above
all, an important shift in understanding: the "type"
table **does not distinguish wall from floor** as had been assumed
— that distinction lives in another mechanism (the raw graphic
index's range), and "type" instead encodes special behaviors layered
on top. This phase also documented the L-shaped trapdoor mechanic
(3 states, 12 tiles) based on the user's explanation of how
that mechanic actually plays out.

### Phase 3 — The "big gap": sprites, text font, never-before-seen text

The `0x8F74`-`0xB940` zone (~10,700 bytes) was the hardest stretch to
resolve, and it was done **in successive layers**, each unlocking the
next: first it was confirmed that `INIT` never does a `RET` and
falls into the main loop (449 bytes); then previously never-seen
in-game text appeared (`"FASE 00"`, `"READY?"`, `"ESTAS
FRITO"`) alongside a table of 64 fixed-stride pointers; that table
turned out to be the key to locating **the 64 character sprites**
(9216 bytes, identified at a glance by the user); and the remaining
600 bytes turned out to be the game's character font,
confirmed by the real glyph-address formula. Only then did the whole
`0x8400`-`0xD500` stretch reach 0 differences.

### Phase 4 — The "candy frame" and the real screen color

A finding with a U-turn built in: a 768-byte block was
investigated and **dismissed** in one session as "background
texture/shading" — and in a later session it turned out to be
exactly what had been dismissed: the real color (red/white/gray) of
the HUD candy frame, applied to the VRAM color table. Verified
by comparing the real transformation against a live VRAM dump.
Separately, the frame's *shape* itself (not its color) was located
as an RLE table whose repetitions added up to exactly the size
of the full screen pattern table — confirmed by
rendering it and comparing pixel for pixel against a real
screen reconstruction.

### Phase 5 — The sound driver: a custom bytecode language

Recognizing that the `0xC4A0`-`0xD000` block, believed to be a
"generic resource manager", is actually the **AY-3-8910 PSG sound/
music driver** — a bytecode interpreter of Topo Soft's own making,
with 15 commands deciphered one by one. On that basis two tools were
built (`tools/mmsnd_tool.py`, a disassembler/assembler
verified with a byte-for-byte *roundtrip*; `tools/mmsnd_render.py`, a
WAV renderer) that were fine-tuned over **successive rounds of
real listening** by the user — each round found a real bug
in the renderer (inverted mixer polarity,
broken loop-end detection, a wrong instrument-field mapping),
never "sounds off, we'll leave it".

### Phase 6 — Special-item subsystem and the AI of the 3 entity types

Deciphering the subsystem that manages the power ball, hippo,
tool and the tank/plane tracks, and the "AI" (with no
real pathfinding) of ghosts, ladybug and "repugnantoso" — each one
with its own effect on reaching its spot (chasing, regenerating
eaten balls, planting new ones).

### Phase 7 — The levels, and the case of the "hidden level" that wasn't

Locating the 15 playable levels (bodies + shared
headers) and a 15th level that at first looked like
**real content with no register pointing to it at all** — a
later session found that it did have a real register in the
level table (mislabeled as "20 bytes unidentified") and that it's
reached by playing entirely normally after completing level 14. This
specific case is explained in more detail in §10 and in
`REFLEXION_COLABORACION_IA.md`, because it repeated — with
different nuances — twice in the project's history.

### Phase 8 — Unification: from loose files to a truly compilable project

Once the content was identified, a whole phase was dedicated to
the **architecture of the reconstruction project itself**: unifying
`madmix1.asm`/`madmix_scr.asm` into a single assembly pass
(`main.asm`, sharing a symbol space so cross calls
used real labels instead of hex), also reconstructing
the disk and tape loaders (`load_disk/`/`load_cas/`), and
building the scripts that compile and package **the whole project
in one go** (`tools/build_all.py`, `tools/gen_disk_and_cas.py`) — with
the `.dsk` built from scratch (real FAT12, not a patched copy).

### Phase 9 — Sustained refactoring: hundreds of small rounds

Most of `FINDINGS.md`'s volume (roughly 370
milestones and rounds logged, the vast majority in a single
central stretch of the diary) are not big discoveries but ongoing
background work: replacing loose hex addresses with
real labels once their name was already known, translating
English/cryptic labels into descriptive Spanish, converting hex to
decimal wherever it reads better, adding line-by-line comments,
extracting embedded data (tiles, sprites, sound, levels) into
individual editable files, and keeping the HTML viewers in sync
every time something changed. No change of this kind was
accepted without recompiling and checking that the binary
was still identical.

### Phase 10 — Reference documentation and publication

With the code already complete and stable, the manuals in
`manuales/` were written (one per subsystem, with the research
process left out) and `FLUJO_PROGRAMA.md` was rewritten from scratch
(it had been frozen at a very early stage). The public Git
repository was created, with a legal notice clearly separating
what belongs to the original game (Topo Soft) and what belongs
to the reverse-engineering work itself.

## 4. Tools built

All of them live in `tools/`, all can be invoked on their own, and
all have some form of *roundtrip* verification (decoding and
re-encoding reproduces the exact original binary):

| Tool | What it does |
|---|---|
| `build_all.py` | Compiles the whole project in one go (`sjasmplus main.asm`) |
| `gen_disk_and_cas.py` | Generates the 2 final deliverables (`.dsk`/`.cas`) from scratch |
| `gen_dsk_file.py` | Builds the complete `.dsk` (boot sector, FAT12, directory, data) without starting from a copy |
| `gen_cas_bin.py`/`gen_cas_file.py` | Build the real `.cas` (sync, headers, blocks) |
| `mmsnd_tool.py` | Sound bytecode disassembler/assembler, with *roundtrip* |
| `mmsnd_render.py` | Renders the sound bytecode to WAV, to listen to it without the game |
| `mmlvl_tool.py` | Level grid disassembler/assembler, with a ball-target check |
| `msxbasic_tool.py` | MSX BASIC detokenizer/tokenizer |
| `gen_inventory.py` | Generates the searchable inventory of every label in the project |
| `gen_flow_diagram.py` | Generates the graph of real calls between functions |

## 5. Mistakes made and how they were corrected

Being honest about this is part of the method, not an exception to
it. Documented cases of conclusions that turned out to be wrong,
and how they were caught:

- **The "hidden level"**: first documented as real content but
  with no connection to the rest of the game; corrected on finding
  its real register in the level table. Corrected again in this
  same session (August 2026), because the documentation kept
  using the "hidden" label in several places as if it were the
  current state instead of an already-superseded phase — see
  `REFLEXION_COLABORACION_IA.md` §4.
- **The format of the 64 character sprites**: first documented
  as a single 24×48-pixel image per entry, a reading that
  produced recognizable sprites but with horizontal background
  stripes. Corrected in this session by empirically checking that they
  are actually 24×24 with two planes interleaved row by row
  (mask + pattern) — see §10.
- **The game's music credit**: an edit made directly on
  GitHub "fixed" the real musician's name (extracted literally
  from the ROM, `"COMILONAS"`) to `"GOMILONAS"`, believing it was
  a typo. When merging that branch, cross-checking against the
  source code itself (`DB "COMILONAS"` in `madmix_scr_body.asm`)
  caught the contradiction, and the verified data was kept, not
  the "correction".
- **The `TILE_TYPES` table**: the initial hypothesis that it
  encoded wall/floor was explicitly ruled out on finding that all 45
  wall tiles share a type with plain floor — the document
  itself flags it as "an important shift in understanding",
  with no attempt to gloss over it.

## 6. Current status

- The disk's 3 binaries (`MADMIX0.BIN`, `MADMIX1.BIN`,
  `MADMIX.SCR`) and the tape's (`LOAD.BIN`, `TEST.BIN`,
  `LOGOTOPO.CM`) are complete and compile to 0 differences byte
  for byte against the originals, except for the already-documented
  and explained deviations (the fixed level-13 bug, a handful
  of unrelated bytes).
- The reconstructed `.dsk` and `.cas` load and run in openMSX,
  confirmed in both versions.
- There remain genuinely open points, flagged as such in each
  manual and in `FINDINGS.md` — this project does not claim to have
  100% of every byte's purpose explained, only 100% of the
  bytes reproduced exactly, with whatever isn't fully understood
  explicitly marked as pending rather than glossed over.
