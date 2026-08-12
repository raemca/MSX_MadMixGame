# Mad Mix Game (Topo Soft, 1987/88) — reverse-engineering findings

*[Leer esto en español](FINDINGS.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (<raemca@hotmail.com>)*

Context to resume the work. Origin: static analysis of
`MADMIX1.BIN` extracted from the original `.dsk` with `mtools`,
using `z80dasm` + manual byte-by-byte inspection (no emulator or
debugger yet). Everything here comes from a chat session with
Claude on claude.ai; this file is the context bridge into Claude
Code.

## Disk structure

| File | Size | Function |
| --- | --- | --- |
| AUTOEXEC.BAS | 19 B | `RUN"madmix",R` |
| MADMIX.BAS | 183 B | BASIC loader, does the BLOADs |
| MADMIX0.BIN | 58 B | machine-code loader, see below |
| MADMIX1.BIN | 22952 B | the game engine, 0x8400-0xDDA0 |
| MADMIX.SCR | 21768 B | loading screen |

No need to touch the first three — they work as-is. The work is
reconstructing MADMIX1.BIN as assemblable source.

## MADMIX0.BIN — the loader (58 bytes, fully and unambiguously disassembled)

```asm
di
in a,(0a8h)        ; read primary slot
ld b,a
ld (0fffdh),a      ; save current config
srl a / srl a / srl a / srl a
or b
ld (0fffeh),a
out (0a8h),a       ; switch slots (RAM in page 0)
ld hl,08800h
ld de,01000h
ld bc,05500h
ldir               ; copy 0x5500 bytes from 0x8800 to 0x1000
call 01000h        ; run the relocated block
ld a,(0fffdh)
out (0a8h),a       ; restore slots
ei
ret
```

**Important for the reconstruction**: any `.asm` that replaces
MADMIX1.BIN has to occupy exactly the same space in every stretch,
because these addresses (0x8800, 0x1000, 0x5500, 0x8400) are hard-
wired into this loader. If our code isn't byte-for-byte the same
size as the original in every routine, everything shifts and this
loader stops working. To reproduce the relocation in SjASMPlus: use
`PHASE 0x1000` / `DEPHASE` on the stretch that occupies
0x8800-0xDD00 of the original.

**CORRECTION/EXPANSION (verified directly with Z80Dasm, with the
correct header offset): the listing above only covers HALF of the
file.** The real 58 bytes have **two independent entry points**,
not one:

```asm
; 0xFA00 (RELOCATOR) -- run via "BLOAD MADMIX0.BIN,R"
DI
IN A,($A8)
LD B,A
LD ($FFFD),A        ; save current slot config
SRL A / SRL A / SRL A / SRL A
OR B
LD ($FFFE),A         ; ALSO save a twisted version, for the
                       ; second entry point below
OUT ($A8),A
LD HL,$8800 / LD DE,$1000 / LD BC,$5500
LDIR
CALL $1000            ; PORTADA_INIT (madmix_scr.asm)
LD A,($FFFD)
OUT ($A8),A            ; restore slots
EI
RET                     ; <- returns to the BASIC that called it

; 0xFA2A (JUMP_TO_ENGINE) -- SECOND entry point, independent
DI
LD A,($FFFE)
OUT ($A8),A              ; restore the OTHER saved slot config
JP $8400                  ; jumps straight to JT_INIT (MADMIX1.BIN)
```

This settles a piece that had been loose for a while:
`MADMIX1.BIN` is loaded with a `BLOAD` WITHOUT `",R"` (confirmed
from the start of the project), so something has to start it by
hand AFTER loading it. `0xFA2A` is the perfect candidate —
probably invoked by an explicit `CALL`/`USR` in the orchestrating
BASIC, right after the line that loads `MADMIX1.BIN`.

**DONE**: `MADMIX0.BIN` now has its own source,
`src/madmix0.asm` — the disk's 3 files (`MADMIX0.BIN`,
`MADMIX1.BIN`, `MADMIX.SCR`) each now have their own independent
`.asm`. Verified 0 differences across the full 58 bytes.

## RESOLVED: full boot sequence from the .BAS (confirms who calls `0xFA2A`)

Byte-by-byte dump of `AUTOEXEC.BAS` and `MADMIX.BAS` (tokenized,
standard MSX-BASIC format: `[next-line ptr 2B][line num
2B][tokens...][00]`, ending in `00 00`). The relevant lines of
`MADMIX.BAS` (the earlier ones are just `REM` with the title and
credits, including a "CRACKED BY PAU D'ACI" — this disk copy is
patched by a crack group, it's not 100% the original from Topo
Soft, though there's no sign it affects the loading mechanics):

```basic
70 BLOAD"MADMIX.SCR":BLOAD"MADMIX0.BIN",R
80 BLOAD"MADMIX1.BIN":DEFUSR=&HFA2A:X=USR(0)
```

(the address `&HFA2A` is confirmed BYTE FOR BYTE: it appears in the
raw dump as `0C 2A FA`, i.e. "2-byte hex constant = 0xFA2A" —
matches `JUMP_TO_ENGINE` in `madmix0.asm` exactly. The exact
`DEFUSR=`/`USR(0)` syntax is inferred from the surrounding tokens
with slightly less certainty than the address itself, but the
overall structure doesn't allow for any other reasonable reading).

Full boot sequence:

1. `AUTOEXEC.BAS` → `RUN"madmix",R` → hands control to `MADMIX.BAS`.
2. `MADMIX.BAS` line 70: `BLOAD"MADMIX.SCR"` (loads without
   running, lands at 0x8800). Then `BLOAD"MADMIX0.BIN",R` loads
   `MADMIX0.BIN` and, because of the `,R`, EXECUTES it immediately
   from its `exec` address (`0xFA00` = `RELOCATOR`): this does the
   `LDIR` that relocates `MADMIX.SCR` to 0x1000, draws the title
   screen, and does `RET` — **returning control to BASIC itself**,
   which continues on the next line.
3. `MADMIX.BAS` line 80: `BLOAD"MADMIX1.BIN"` — without `,R`
   (confirms what was already known) — it only copies the block
   into memory (0x8400-0xDDA0), doesn't run anything yet. **This
   `BLOAD` is the one that "loads the 1".**
4. `DEFUSR=&HFA2A : X=USR(0)` — **this is what "calls the routine
   that runs the 1"**: BASIC itself, using MSX-BASIC's standard
   mechanism for invoking machine code. Jumps to `0xFA2A`
   (`JUMP_TO_ENGINE`, still resident in memory since
   `MADMIX0.BIN` was loaded in step 2 — nobody overwrites it),
   which restores the slot config saved in `$FFFE` and does
   `JP $8400` — the final, definitive jump into the game engine.
   From here on there's no return to BASIC.

This closes the "who starts `MADMIX1.BIN`" thread: it's the
orchestrating BASIC itself, in two steps (`BLOAD` without `,R` +
an explicit `DEFUSR`/`USR`), not `MADMIX0.BIN` on its own.

## IMPORTANT: the .BIN has a 7-byte MSX header at the start

`MADMIX1.BIN` (22952 bytes on disk) starts with the standard MSX
`BLOAD` header: `FE 00 84 A0 DD 00 84` = ID `$FE` + start `$8400` +
end `$DDA0` (inclusive) + exec `$8400`. The real CODE therefore
starts at **file offset 7**, not 0. If raw bytes are read from the
`.BIN` to verify something,
`address = 0x8400 + (file_offset - 7)`. Bit us once (misaligned a
table read by 7 bytes) — don't forget it.

## Memory map of MADMIX1.BIN (0x8400-0xDDA0)

- `0x8400`: header + jump table (12 `JP` entries), **verified byte
  for byte** against the original `.BIN` — matches `src/madmix1.asm`
  exactly.
- `0x8400-0x8800`: permanently resident code
- `0x8800-0xDD00`: block that the loader relocates and runs at
  `0x1000-0x6500` — includes the real game logic (`0x60DC` called
  every interrupt)
- `0x8EC4-0x8F23`: tile-type table (**96 bytes**, complete —
  CORRECTED, see below; previously thought to be 0x8EC7/93 bytes)
- `0x8F24`: real entry point (`INIT`), **disassembled and
  transcribed into `src/madmix1.asm` up to offset `$8F71`** (see
  its own section below)
- `0x9300-0x9700`: small 8x8 font/icons (score, dots), NOT the
  characters
- `0x9D40-0xA3E0`: strong candidate for character sprites
  (53 blocks of 16x16, varied shapes) — located but **not
  identified which is which** (Pac-Man, ghosts, hippo, tank, plane,
  ladybug, steamroller, trapdoors)
- `~0x9600-0xB700`: striped candy frame (repeated 00/FF pattern),
  large, not yet included in the project
- `0xB940-0xC4A0`: maze tile graphics, 32 bytes each (16x16, 16
  rows x 2 bytes) — YES included (`data/tile_gfx.bin`)
- `0xC4A0-0xC900`: "resource slot" manager (real code, disassembled
  and understood, see below)
- `0xC900-0xCF8B`: resource headers (`0xCDCB`, `0xCDFF`, `0xCE0C`)
  in a bytecode-like format (common prefix `85 64`, opcodes ≥0x80)
  — the interpreter that consumes them NOT located
- `0xD000-0xD500`: candidate for maze/level data (long repeated
  runs = corridors, values ≤0xBF) — included
  (`data/maze_data.bin`) but NOT confirmed whether it's all 15
  levels or a subset/compressed format
- `0xD500-0xDDA0`: unexplored

## VBLANK interrupt

- Vector `0x0038` hot-patched with `JP 0x882A`
- ISR at `0x882A`: reads VDP status (`IN A,(099h)`), if it's a
  frame interrupt saves registers and calls:
  - `0x8860`: housekeeping — semaphore at `0x8430`
  - `0x60DC`: game logic, **every interrupt without exception**
    (there's NO 25/50Hz frame-skip, that hypothesis was checked
    and ruled out)
- `0x89A0` (`WAIT_VBLANK`): sets flag=1, EI, polls until the ISR
  clears it on the next interrupt — functionally equivalent to a
  `HALT`

## VDP API -- addresses VERIFIED byte for byte against the .BIN

`0x8931` (FILVRM), `0x8942` (LDIRVM) and `0x8954` (SETVRAM) were
correct (unlike the initial false alarm: searching for who calls
them with a direct `CALL` gave 0 results across the whole file, but
that only means nobody invokes them that way in the parts of the
code scanned so far — they're probably called from still-
unexplored areas, or via indirect jumps). Decoding the real bytes
confirmed the 3 routines are CONTIGUOUS, with no gap between them
(0x8931-0x8960 complete), and the real content differs slightly
from what was in `madmix1.asm` (which was approximate/invented, not
transcribed):

- **FILVRM** uses a NESTED B/C loop (a compensating `INC B`, then
  an inner `OUT/DEC C/JR NZ`, outer `DEC B/JR NZ`) — the classic
  MSX BIOS pattern for counting 16 bits with 8-bit instructions,
  not the 16-bit BC subtraction that was there before.
- **LDIRVM** is practically identical to what was there, except it
  uses `JP NZ` (3 bytes) instead of `JR NZ` (2 bytes) for the loop
  jump.
- **SETVRAM** has 2 extra instructions at the end, `EX (SP),HL` x2
  — a deliberate delay "no-op" (19 T-states each) that the VDP
  requires after setting the VRAM address and before the next port
  access.

All 3 corrections are now in `src/madmix1.asm` and compile with the
exact expected addresses (verified with `--sym`).

### Gap 0x8961-0x899F FULLY transcribed (filled the DS before WAIT_VBLANK)

Pulling on the thread of the side finding (the table routine right
after SETVRAM), the whole stretch up to `WAIT_VBLANK` (0x89A0) was
decoded byte for byte — it fits exactly, with nothing left over.
Already transcribed in `src/madmix1.asm`. Four new things:

- **`0x8961` `LOOKUP_8978`**: `LD HL,$8978 / AND $78 / RRCA x3 /
  ADD A,L / LD L,A / LD A,H / ADC A,0 / LD H,A / LD A,(HL) / OR
  $10 / RET`. Extracts a 4-bit index from bits 3-6 of A, looks it
  up in a 16-byte table at `0x8978` and returns the result with
  bit 4 forced to 1.
- **`0x8978` `DIRBITS_TABLE`** (16 bytes): `01,04,06,0D,0C,05,0A,
  0E,01,04,06,08,02,07,0B,0F`. Interesting HYPOTHESIS: the 16
  values are ALL combinations of bits `1,2,4,8` (up/down/left/
  right, matches the bits of arrows 51-54) — exactly `0,3,9` are
  missing and `1,4,6` repeat. Could be a movement-decision table
  (ghost AI? resolving which direction to take at a junction with
  several open walls?). Real usage not confirmed yet.
- **`0x8988` `ADDR_FROM_DC00`**: `PUSH BC / (SRL B / RR C) x3 / LD
  HL,$DC00 / ADD HL,BC / POP BC / RET`. Divides BC by 8 (16 bits)
  and adds it to base `0xDC00` — falls INSIDE the "0xD500-0xDDA0
  unexplored" zone. HYPOTHESIS: converts a pixel coordinate into an
  8-by-8 table/attribute index, similar in spirit to
  `MAP_COORD_TO_ADDR` (0x8CB6) but with a different base table.
  What `0xDC00` corresponds to isn't confirmed.
- **`0x899B` `RESET_8437`** — **IDENTIFIES JT_SLOT3** (previously
  "unidentified" in the jump table): `XOR A / LD ($8437),A /
  RET`. Zeroes out the resident variable `0x8437`, the same one
  read/compared in the still-untranscribed code that starts at
  `0x8447` (see further below, jump-table/resident-zone section).
  Connects two loose threads from earlier sessions: we now know
  `0x8437` is a variable that can be reset via the public API
  (jump table), though we still don't know exactly what it's used
  for.

## VDP API (encapsulated, the base for everything else)

- `0x8954` SETVRAM(HL): prepares port 0x99/0x98 to read/write at
  that VRAM address — used by all the others
- `0x8942` LDIRVM(HL=source,DE=dest,BC=bytes): copies RAM→VRAM
- `0x8931` FILVRM(HL=dest,BC=count,A=value): fills VRAM
- `0x8CA3`/`0x8E15`: same as LDIRVM but with `CPL` (mask/negative)
- `0x8DFE` approx: text routine, indexes the font table at `0x935B`

## Software scroll (camera centered on Pac-Man)

- `0x2C02`: Pac-Man's position = camera position
- `0x8CB6`: coordinates → address (AND 07Ch, aligns to grid)
- `0xFC60`: in-RAM level matrix, 1 byte/cell, bit7 = flag (eaten?),
  bits 0-6 = raw tile index (0-127)
- `0x8CDA`: raw index AND 07Fh → table `0x8EC7` → tile "type"
  (0x00-0x13, 20 types)
- **Graphic calculation** (resolved): `HL = 0xB940 + 32 ×
  raw_matrix_byte` — the graphic is indexed by the RAW byte
  directly, NOT by the `0x8EC7` "type". Two independent paths from
  the same byte: one for collision (type), another for rendering
  (graphic). Lets several visually distinct tiles share the same
  logical type.
- `0x8D5F`/`0x8CFF`/`0x8D10`: producer/consumer queue of "strips to
  redraw" (until a tile boundary is crossed)
- `0x8D1B`: redraws a 2×16-tile strip — contiguous source
  (`0xB940`+offset), destination with a 32-byte/row stride (screen
  width) into shadow buffer `0xDE04`
- **Not confirmed**: the exact point where `0xDE04` gets flushed to
  real VRAM (presumably via LDIRVM, not located)

## Tile-type table (0x8EC4, 96 bytes, complete) — CORRECTED

Address and size corrected by reading the original `.BIN` byte for
byte (see header note above). Previously thought to be `0x8EC7`/93
bytes; the 3 extra bytes at the start were actually the tail of the
previous routine (`CB E3` = `SET 4,E`, `7B` = `LD A,E`, `18
AA` = `JR $-86`), not part of the table. Indices 0-47 → type 0x00
(floor/corridor, the most common, 48 entries not 45). From 48
onward there are increasing types 0x01-0x13 (wall variants,
corners, etc.). 20 distinct types in total (0x00-0x13). The table
ends EXACTLY where `INIT` starts (`0x8EC4 + 0x60 = 0x8F24`) — good
cross-confirmation. The exact content is already in `madmix1.asm`
as `TILE_TYPES`.

### Anomaly confirmed by the developer (playing/visually identifying)

Graphic tiles #51 (up), #52 (down) and #53 (left) are arrows that
force Pac-Man to advance in that direction (mechanic confirmed by
playing the original), and all three have type `2` in the table —
consistent. But tile #54 (RIGHT arrow, same visual and mechanical
family) has type `3`, not `2`. Confirmed directly against the real
`TILE_TYPES` values (indices 51,52,53,54 → 2,2,2,3). With all 4
directions now identified, the anomaly is sharper: it isn't a
"weird" type from ambiguity about which direction each index is —
it's specifically the RIGHT direction that breaks the pattern set
by the other three. Possible explanations, none confirmed yet:

- The type encodes something more than "this is an arrow" (e.g. a
  distinct sub-mechanic just for the right arrow).
- It's a real inconsistency/bug in the original game.
- The graphic index and the type index aren't as strictly 1:1 as
  assumed — pending review with more cases as the developer keeps
  visually identifying the rest of the tiles (see
  `src/recursos/graficos.html`).

Second anomaly of the same kind: graphic tiles #84, #85, #86 and #87
are the 4 pieces of a decorative mosaic showing Pac-Man's face (per
the developer, it's NOT floor — it's a decorative wall that shows up
in some stages). Real types: `0,10,10,0` — two of the four
pieces share a type with normal floor (`0`) and the other two share
type `10` with another wall tile already seen (graphic index 61).
In other words: a single visual mosaic (4 contiguous pieces, one
object) has 2 different logical types, and neither of those 2 types
is exclusive to the mosaic. Reinforces the suspicion that "type"
isn't a purely visual/aesthetic classification but something more
tied to collision/behavior (e.g. "can you walk over it or not",
rather than "what it looks like"), and that the graphic↔type
mapping has more nuance than assumed. Unresolved — pending more
cases.

### IMPORTANT FINDING: "type" does not distinguish wall from floor

Tiles 0-44 (45 graphics: 16 iron + 16 concrete + 13 brick, see the
full legend below) are ALL walls — and all 45 have type `0`, the
exact same type as plain floor and floor-with-ball (45-47).
Confirms what the developer flagged from the start ("most of type 0
are floor OR walls"): the `TILE_TYPES` table **is not** the source
of the walkable/wall distinction. That distinction has to be
resolved by ANOTHER mechanism, not yet located — probably by
comparing the raw graphic index against known ranges (e.g. "if it's
between 0 and 44, it's a wall") rather than looking at the
`TILE_TYPES` byte. This is an important shift in understanding:
`TILE_TYPES` seems to encode "special behaviors" instead (pinned
ball, arrows, vehicle tracks, etc.) layered on top of a wall/floor
base that's determined some other way. Still need to locate that
logic.

### L-shaped trapdoors (a 3-state mechanic, 12 tiles)

Mechanic confirmed by the developer: a trapdoor is an L-shaped wall
that Pac-Man can climb/push; doing so, the vertical arm of the L
falls flat and the horizontal one rises, flipping the trapdoor over
— so Pac-Man can escape a ghost by leaving it on the other side of
the now-flipped wall. The game animates the transition (with sound)
in both directions. There are 3 distinct graphic states, 4 tiles
each (top-left, top-right, bottom-left, bottom-right corner):

- **Trapdoor A** ("right-handed" L, crossed right to left): 74
  (top-left), 75 (top-right), 67 (bottom-left), 68 (bottom-right).
- **Trapdoor B** ("left-handed" L, crossed left to right): 71
  (top-left), 72 (top-right), 73 (bottom-left), 69 (bottom-right).
- **Transition** (momentary, replaces the 4 tiles of the active
  trapdoor while it's falling/flipping over, before the reversed
  trapdoor is shown): 76 (top-left), 77 (top-right), 78
  (bottom-left), 79 (bottom-right).

In-game sequence: trapdoor A ↔ transition ↔ trapdoor B (in both
directions). Real types for these 12 tiles: `0,0,15,15` (A),
`17,0,15,16` (B), `18,0,0,0` (transition) — type `15` ("vertical/
horizontal wall crossing" in the wall legend) shows up again on
trapdoor pieces with no apparent relation to a wall crossing,
reinforcing the suspicion that types get reused by shared behavior
(here probably "bottom corner of a structure, blocks the same way
a crossing does") rather than by visual similarity or belonging to
the same object.

### Legend for the 3 wall styles (iron/concrete/brick)

Confirmed by the developer: the 3 styles are NOT mixed within a
single level (each level uses one of the three). Piece by piece
(same order across all 3 styles, concrete and iron complete, brick
only up to position 12):

| # within the set | Iron | Concrete | Brick | Meaning |
| --- | --- | --- | --- | --- |
| 0 | 0 | 16 | 32 | standalone piece, not connectable |
| 1 | 1 | 17 | 33 | top end of a vertical wall |
| 2 | 2 | 18 | 34 | vertical wall |
| 3 | 3 | 19 | 35 | bottom end of a vertical wall |
| 4 | 4 | 20 | 36 | left end of a horizontal wall |
| 5 | 5 | 21 | 37 | horizontal wall |
| 6 | 6 | 22 | 38 | right end of a horizontal wall |
| 7 | 7 | 23 | 39 | bottom-left corner |
| 8 | 8 | 24 | 40 | bottom-right corner |
| 9 | 9 | 25 | 41 | top-left corner |
| 10 | 10 | 26 | 42 | top-right corner |
| 11 | 11 | 27 | 43 | horizontal wall + central vertical branch downward |
| 12 | 12 | 28 | 44 | horizontal wall + central vertical branch upward |
| 13 | 13 | 29 | — | vertical wall + central horizontal branch rightward |
| 14 | 14 | 30 | — | vertical wall + central horizontal branch leftward |
| 15 | 15 | 31 | — | crossing between a vertical wall and a horizontal wall |

### Visual identifications confirmed by the developer (ongoing)

Logged here as the developer identifies tiles by looking at
`src/recursos/graficos.html` (which also gets updated with each
one). Index = graphic number (same order as in
`tile_gfx.bin`/`madmix1.asm`/the HTML page).

### `0x9D40-0xA3E0` RULED OUT as a sprite candidate -- 3 formats tried, none gives a coherent shape

Tried, using `src/recursos/graficos.html` (mode selector in the
sprite gallery):

1. Raw 16x16 raster (16 rows x 2 bytes, `tile_gfx.bin`'s real
   format) — no recognizable shape.
2. Native VDP TMS9918 16x16 sprite quadrant (4 blocks of 8x8, order
   top-left/bottom-left/top-right/bottom-right) — no recognizable
   shape.
3. 4x independent 8x8 blocks, NOT composed into a 16x16 (in case
   they were small individual sprites) — no recognizable shape
   either.

Conclusion: the problem isn't the decoding format — most likely
**`0x9D40-0xA3E0` was never actually verified byte for byte**. It
was a "strong candidate" from the original analysis session (before
this repo existed), and we already know that session had several
real errors confirmed later (the `TILE_TYPES` address off by 3
bytes, the wrong `SP` for `INIT`, a misread "CALL 0x1000") — so an
unverified candidate from that same session is suspect by default.
Still need to locate the REAL position of the character sprites via
one of these two paths (neither tried yet):

1. **Static**: locate in the disassembly where VDP register #6
   (sprite pattern table, via port `0x99`) is written, and from
   there trace the `LDIRVM`-style call that copies the real data —
   its HL (source) would be the real address in ROM.
2. **Live**: with openMSX + debugger, breakpoint on that VRAM write
   and read which ROM address is being copied.

**MILESTONE: all 91 `tile_gfx.bin` tiles are visually identified**
(the only real thing left open: the exact function of tile #59,
similar to #60 but unconfirmed). Still unidentified: the 53
character sprites (`0x9D40-0xA3E0`) and the candy frame (format
still unconfirmed, not even extracted).

| Index | Real type | Identification |
| --- | --- | --- |
| 51 | 2 | UP arrow — forces Pac-Man to advance in that direction |
| 52 | 2 | DOWN arrow — forces Pac-Man to advance in that direction |
| 53 | 2 | LEFT arrow — forces Pac-Man to advance in that direction |
| 54 | 3 | RIGHT arrow — same mechanic as 51-53, but a different type (3 instead of 2, see anomaly above). Directions confirmed by the developer: up=51, down=52, left=53, right=54 |
| 45,46,47 | 0,0,0 | floor with a ball (normal edible), on the 3 different floor types |
| 48,49,50 | 1,1,1 | floor with a PINNED ball (an enemy pins balls; you need a tool to unpin them and then eat them), on the same 3 floor types |
| 63,64,65 | 12,13,14 | ORIGINAL floor with no ball (the same 3 floor types as 45-47/48-50, now with nothing on top) |
| 0-15 | 0 (all 16) | **IRON wall** — full set of 16 connectable pieces (see full legend below) |
| 16-31 | 0 (all 16) | **CONCRETE wall** (rounded) — same 16 pieces as iron, same order, different art |
| 32-44 | 0 (all 13) | **BRICK wall** — only 13 pieces, analogous to iron/concrete 0-12 (missing the T-junctions and the crossing, indices analogous to 13,14,15) |
| 60 | 9 | **power-ball item** — walking over it lets Pac-Man eat ghosts temporarily |
| 61 | 10 | **hippo item** — turns you into a hippo: you can step on/kill ghosts, but you CANNOT eat balls while it lasts, and ghosts killed this way give no points |
| 62 | 11 | **tool item** — needed to unpin the pinned balls (see 48-50) |
| 59 | 8 | visually similar to 60 (floor item) but function not recalled — pending |
| 66 | 15 | solid BLACK tile — standard flat filler/floor, presumably used OUTSIDE the playable area |
| 70 | 0 | loose brick wall piece — the developer doesn't recall levels using it; might cover one of the missing T-junctions/crossing in the brick set (the analogues to iron/concrete 13,14,15) |
| 88,89,90 | 0,0,0 | decorative stars, small to large — filler/decoration next to the black tile (66), outside the playable area |
| 74,75,67,68 | 0,0,15,15 | **trapdoor A**, "right-handed" L — crossed right to left. Pieces: 74=top-left, 75=top-right, 67=bottom-left, 68=bottom-right |
| 71,72,73,69 | 17,0,15,16 | **trapdoor B**, "left-handed" L — crossed left to right. Pieces: 71=top-left, 72=top-right, 73=bottom-left, 69=bottom-right |
| 76,77,78,79 | 18,0,0,0 | **transition** between trapdoor A and B (and vice versa) — 4 tiles that momentarily replace the trapdoor's 4 tiles while Pac-Man pushes/flips the wall, before the reversed trapdoor appears. Pieces: 76=top-left, 77=top-right, 78=bottom-left, 79=bottom-right |
| 80 | 0 | LEFT start of the ghost-house door, joins the wall (complements 56/57) |
| 81 | 19 | RIGHT start of the ghost-house door, joins the wall (complements 56/57) — shares type `19` with tile 82 (left cap of the plane track), despite being somewhat different visually and functionally |
| 56,57 | 5,6 | electric line acting as the ghost house's door — visually they look like the same tile but have different types (5 and 6), consistent with the "one type per tile" pattern in this range. Developer's HYPOTHESIS (unconfirmed): one of the two lets Pac-Man through and the other doesn't — recalls a level with a ball INSIDE the ghost house itself, which would fit with a "passable" variant existing |
| 55 | 4 | TANK track (vertical) — analogous to 58 (end to end), but turns you into a tank; besides firing in the direction of travel, you can alternate firing left/right while moving along it |
| 58 | 7 | plane take-off/landing track (straight stretch) — you enter at one end and exit the other; turns Pac-Man into a plane and lets you shoot. Several are drawn contiguously in the level |
| 82 | 19 | LEFT cap of the plane track |
| 83 | 0 | RIGHT cap of the plane track |
| 84,85,86,87 | 0,10,10,0 | 4 pieces of a decorative mosaic showing Pac-Man's face — it's a wall/decoration in some stages, NOT floor (even though two pieces share type 0 with the floor) |

Pattern note: types 4-14 (graphic indices 55-65) each seem to be
EXCLUSIVE to a single tile (a 1-to-1 ladder: graphic 55→type4,
56→type5 ... 65→type14), unlike type 0 (shared by ~48 tiles) or
types like 10/15/19 (shared by 2-3). Not yet confirmed whether
those "unique" types are related to each other in any way (they
could, e.g., be special tiles each with their own dedicated logic
in the engine, rather than belonging to a shared category).

First real semantic clue about what a "type" means: type `1` groups
the 3 "pinned ball" variants (45-47→48-50, same floor, ball in a
different state) — seems to confirm the type IS tied to behavior/
interaction (here: "can it be eaten directly, or is the tool needed
first?"), not just corridor/wall collision. But this inverts what
you'd expect for floor WITHOUT a ball (63,64,65): there, instead of
sharing a common "walkable floor" type, each of the 3 terrain
variants has its OWN unique type (12,13,14) — in other words, when
the floor has a ball (any terrain) the type gets unified into 0 or
1 depending on the ball's state, but when it does NOT have a ball
the type DOES distinguish the terrain. Confirms that "type" mixes
at least two different axes (ball state + terrain variant) in a
non-trivial way — not fully resolved, pending more identifications.

## INIT (0x8F24) — disassembled and transcribed up to 0x8F71

Bytes verified directly against the original `.BIN`:

```asm
LD SP, $0FFF          ; NOT $FFF0 as previously assumed
CALL $881B             ; unidentified (see below)
DI
CALL $1000             ; LITERAL, see mystery resolved below
CALL $CF8B             ; empties slots 0,1,2
XOR A  \ LD DE,$CDCB \ CALL $C4A0   ; slot 0
LD A,1 \ LD DE,$CDFF \ CALL $C4A0   ; slot 1
LD A,2 \ LD DE,$CE0C \ CALL $C4A0   ; slot 2
.loop:  CALL $5D0A \ JR Z,.loop     ; polling (virtual, unidentified)
CALL $CF8B
CALL $6429             ; virtual, unidentified
EI
CALL $CF8B
CALL $5B56             ; virtual, unidentified -- SEE NOTE
CALL $CF8B
LD A,3    \ LD ($2C27),A
LD HL,0   \ LD ($2C29),HL
LD A,1    \ LD ($2C07),A
XOR A     \ LD ($2C2C),A
CALL $CF8B
; still untranscribed from here on ($8F74)
```

Confirms what the earlier notes said (SP, installs something, CALL
0x1000, 3 calls to 0xC4A0 with those exact 3 pointers) and adds new
detail. Transcribed in `src/madmix1.asm` as `INIT`.

### Mystery resolved: what "CALL 0x1000" really does

`CALL $1000` in INIT is a literal instruction (bytes `CD 00
10`), not an approximation. `$1000` is EXACTLY the address where
`MADMIX0.BIN` (58 bytes) gets BLOADed. This explains the whole
boot mechanism:

1. BASIC calls `START` (`0x8400`), which does `JP $8F24` = `INIT`
   (still running from the STATIC copy, not yet relocated).
2. `INIT` does its setup and `CALL $1000` → this invokes
   `MADMIX0.BIN`, the loader, which lives there.
3. `MADMIX0.BIN` does DI, switches slots, `LDIR`s 0x8800→0x1000
   (0x5500 bytes) — this OVERWRITES its own remaining body (only
   58 bytes, well under 0x5500) — and then does `CALL 0x1000`
   AGAIN, this time running the block that's now ALREADY relocated
   (what used to live at static `0x8800`).
4. That second call never returns in normal gameplay (interrupt-
   driven game loop) — so it doesn't matter that `MADMIX0.BIN`'s
   tail (restore slots, EI, RET) has been overwritten: it never
   runs again. It's a "loader that self-destructs after jumping to
   its payload", a classic 8-bit trick.

### Mystery UNRESOLVED: mixing static/virtual addresses

Inside `INIT` (which runs from its relocated copy, per the point
above), `CALL $881B` uses the STATIC address as-is (not the virtual
`$101B`), while the following calls (`$5D0A`, `$6429`, `$5B56`) ARE
low/virtual addresses (within `0x1000-0x6500`). It's not clear why
this mix happens — maybe `$881B` is a routine where it doesn't
matter which copy runs, or maybe the original's static/virtual
convention isn't as clean as "the whole relocated block always uses
virtual addresses". Pending clarification via live tracing
(emulator + debugger), don't assume an answer.

### Intriguing finding NOT investigated: `$5B56` falls inside `maze_data.bin`

`$5B56` is a virtual address; its static equivalent is
`0x8800 + ($5B56-$1000) = 0xD356`, which falls INSIDE the range we'd
been assuming was `maze_data.bin` (`0xD000-0xD500`, see
`data/maze_data.bin`). If `INIT` does a `CALL` to an address that
"should" be maze data, then either (a) the real range of
`maze_data` is different from `0xD000-0xD500`, or (b) that zone
mixes code and data, or (c) it's a coincidence and `$5B56` falls in
another zone due to a calculation error in this document. Pending
verification before accepting the current `maze_data.bin` extraction
as final.

**CORRECTED/CLOSED** (later session): the "equivalent static
address" calculation in this paragraph (`0x8800 + ($5B56-$1000)`)
started from the hypothesis that `madmix1.asm` was also relocated
with `PHASE`, a hypothesis that was fully ruled out shortly after
(see the note at the top of `madmix1.asm`: the engine runs from
STATIC addresses, `PHASE` genuinely applies only to
`madmix_scr.asm`). With that corrected, `CALL $5B56` in `INIT` is
simply a direct call into code ALREADY relocated to low RAM by
`MADMIX0.BIN` -- it falls inside `madmix_scr.asm` (near `TI_5B62`,
in the main menu screen), with no relation to `maze_data.bin`. The
real reason `maze_data.bin` exists was resolved through a completely
different path -- see the "RESOLVED THE PURPOSE OF `maze_data.bin`"
section below.

## Resource manager (real code, understood) -- UPDATED, see full milestone below

Initial notes for this section (earlier session, partial
disassembly). **Expanded** in the "MILESTONE: `0xC4A0-0xD000`
fully transcribed" section below -- that's where the definitive
analysis is (identified as the PSG's sound driver, not just a
generic "resource manager"). The address `0xCF8B` for
`LOAD_RESOURCE_SLOT_EMPTY` was correct from the start -- an early
attempt in this session "corrected" it by mistake to `0xCF8E`
(a byte-extraction error on our end, not the binary's), and it was
corrected back to `0xCF8B` after verifying with `--sym` and a
byte-diff that `INIT`'s real `CALL`s point there.

- `0xC9C9`: table of 4 slots, 46 bytes each
- `0xC4A0`: finds a free slot among the 4 and occupies it with
  pointer DE (auto-allocate)
- `0xC4CC`: directly forces slot number A = pointer DE (no
  searching)
- `0xC88D`: generic 16-bit multiplication, HL = A × DE
- `0xCF8B` (confirmed): empties slots 0,1,2 (calls `0xC4CC` with
  DE=0 three times) — called several times during boot
- `0x8F24` (real init): SP, installs the ISR, `CALL 0x1000`
  (relocated block — persists for the whole game, not just at
  boot), then 3 calls to `0xC4A0` with indices 0,1,2 and pointers
  to `0xCDCB`/`0xCDFF`/`0xCE0C` (confirmed: these are 3 real sound/
  music scripts, inside the driver's own data block -- see the
  milestone below)

## Hypotheses ruled out or corrected during the session

- ~~Game logic at 25Hz, graphics at 50Hz~~ → FALSE, everything runs
  at the same interrupt frequency (see above)
- ~~0xB940 is the map matrix~~ → FALSE, it's the tile graphics
  table; the real matrix is `0xFC60`
- ~~0xC300 is a table of ghost trajectories~~ → probably FALSE,
  rendering it as a bitmap it looks more like tile graphics, not
  movement data

## MAP_COORD_TO_ADDR (0x8CB6) fully deciphered -- confirms a 32-column matrix, and that `maze_data.bin` is A SINGLE level, not all 15

Full disassembly of `0x8CB6` (via Z80Dasm.exe):

```asm
PUSH AF
PUSH BC
LD HL,($2C02)      ; camera/Pac-Man position (confirmed in another section)
LD D,H
LD E,L
LD A,H
ADD A,B
AND $7C
RRCA
RRCA
LD B,A
LD A,L
ADD A,C
AND $7C
RLCA
RR B
RRA
RR B
RRA
RR B
RRA
LD C,A
LD HL,$FC60
ADD HL,BC
POP BC
POP AF
RET
```

The `AND $7C` + rotations pattern (`RRCA` x2 for the row, `RLCA`+
`RR B`/`RRA` x3 for the column) is the classic Z80/MSX idiom for
computing `address = base + row×32 + column`. The **32 comes
straight from the code's constants**, it isn't a guess.

**This confirms with hard facts, not just a visual count, the
developer's observation**: they counted 25 visible tiles wide in
level 1 + 7 more tiles in the "turn around" corridor = exactly 32,
matching the real constant in the code.

**Important consequence for storage**: `data/maze_data.bin` is
1280 bytes. `1280 ÷ 32 = 40` exact rows -- a very clean number,
consistent with it being **a single complete level** of 32×40 tiles
(taller than one screen, which fits with the camera scrolling
vertically to follow Pac-Man). But that means **`maze_data.bin`
CANNOT contain all 15 levels** -- it's only enough for one. **The
other 14 levels have to be somewhere else in the ROM we haven't
located yet.** Candidates to keep searching: the rest of
`0xD500-0xDDA0` (a zone still not fully mapped, see the finding
about the table at `0xDC00` right below, which we already know is
NOT level data) or beyond `0xDDA0` if the original memory map
underestimated the file's real size.

## Zone 0xDC00 (inside "0xD500-0xDDA0 unexplored"): confirmed static table, still not deciphered

Following the thread from cursor `$8438` (see the address
correction above): `0xDC00` was checked across the 5 live RAM dumps
(`ram.bin` through `ram5.bin`, different moments/game states) --
**0 differences across all of them**. It's a fully static zone, not
modified during play. That byte sequence was searched for in
`MADMIX1.BIN` and it matches EXACTLY at the same `0xDC00` address
in the file -- confirming it's simply part of the static image of
the `.BIN` as BLOADed, with no prior copy or transformation.

Full content extracted (`0xDC00`-`0xDD7F`, 384 bytes): a table of
16-bit values in pairs (low byte, high byte), with the high byte
almost always in the `01`-`07` range and the low one varying --
doesn't look like a typical sprite bitmap (too structured). From
`0xDD80` onward there's real, recognizable Z80 code: slot switching
(`OUT ($A8),A` with `A=$55`) + `JP $8400` (game restart), and a
small routine reading PSG ports (`$A0`-`$A2`, typically joystick/
keyboard on MSX) -- possibly a reset/special-check routine, trigger
not investigated. From `0xDD92` onward it's `$FF` filler bytes up
to the file's documented end (`0xDDA0`).

**Attempt to render the table as an image (AND/OR masks)**: since
`JTS2_PROCESS_ACTORS` consumes this zone via 6 successive `POP DE`
(each `DE` = a 16-bit AND/OR pair blended with the background via
`AND E`/`OR D`), all 192 pairs were rendered as if each were an
8-pixel row (using the OR byte). **No recognizable shape came out**
-- just a band with scattered dots, consistent with almost all the
values having only the 3 low bits set.

**Conclusion / pending**: the "render the whole table at once"
approach was probably wrong -- `JTS2_PROCESS_ACTORS` only reads 6
pairs (12 bytes) per call, starting at a specific offset computed
by `ADDR_FROM_DC00` based on the actor's position at that moment,
not the whole table. To see anything meaningful you'd need to
compute the EXACT offset for a real captured actor (with a known
position) and render only those 12 bytes. It's also not confirmed
that `JTS2_PROCESS_ACTORS` is the one that draws characters as such
-- it could be a different subsystem (the HUD "spark" icon, the
collectible balls, etc.), since it uses simple OR blending without
the bit-by-bit sub-pixel shifting that `JTS2_RENDER_A`/
`JTS2_RENDER_B` do use (the ones we know DO draw actors with fine
movement). Parked here -- a good starting point if this zone is
revisited.

## Ghost movement mechanic: fixed 4-pixel step, synchronized

Confirmed by analyzing a sequence of 5 screenshots
(`src/dump_openmsx/secuencia/paso 1.png` through `paso 5.png`, the
ghost house with 2-3 ghosts visible) that the developer took by
pressing F5 repeatedly in openMSX until movement was detected, and
capturing at that instant.

**Method**: ghost silhouettes were detected by "runs of solid
color" (not brightness -- the ghost's color and the wall's are
almost the same hue, but the wall alternates in a pixel-by-pixel
grid pattern while the ghost is a solid fill, so looking for runs
of ≥4 consecutive pixels of the same color separates them cleanly
from the background). The X center of each silhouette was measured
on a fixed row (y=48) that crosses the body.

**Important scale correction**: the screenshots were taken with
openMSX at **2x zoom, with scanlines and 50% blur enabled** -- the
pixel measurements from the PNG need to be divided by 2 to get
native MSX pixels, and some noise from the blur is expected.

**Result** (positions in native pixels, after dividing by 2): on
each movement event (steps 2→3 with 2 ghosts, steps 4→5 with 3
ghosts), ALL active ghosts move by **the same amount, ~4 native
pixels (half an 8x8 tile)**, but each in its own direction (some
+4, others −4) -- consistent with each ghost bouncing between its
own patrol limits, but the movement "tick" itself being
synchronized for all actors at once.

**Confirmed by the developer**: the movement fires irregularly in
real time (sometimes on the 3rd F5 press, sometimes the 4th,
sometimes the 5th -- i.e. a variable counter/timer before deciding
"time to move"), but WHEN it fires, it moves all actors at once, by
the same fixed distance. This fits with `$8437` (actor counter)
being walked in a single pass by the `JT_SLOT2`/`ACTOR_ENGINE`
engine -- see the section below. Still not identified in the
disassembly which variable counter/timer decides WHEN the next
movement is due (a possible lead for when `ACTOR_ENGINE` analysis
is picked back up: look for a variable that increments/compares
each frame against a non-fixed, or random, value before triggering
the 4px shift).

## MILESTONE: JT_SLOT2 transcribed into madmix1.asm, EXACT BYTE FOR BYTE (0 differences across 960 bytes)

The whole actor engine (0x8440-0x87FF, see the analysis below) is
now in `src/madmix1.asm` as `ACTOR_ENGINE` and its subroutines
(`JTS2_RENDER_A`/`B`, `JTS2_COPY_CURSOR`, `JTS2_RESUME`,
`JTS2_XOR_TRANSFORM`, `JTS2_SWAP_SORT`, `JTS2_PROCESS_ACTORS`).
Verified by comparing the compiled `.BIN` against the original byte
for byte across the whole range: **0 differences across 960
bytes**. Two data tables remain unextracted (`$87FB`, of which only
5 real bytes are known -- and those ARE transcribed -- and `$91C3`,
which falls outside this block and is still not located) and the
semantic purpose of several pieces is still unconfirmed (see the
comments in `madmix1.asm` and the analysis below), but the
STRUCTURE and the byte-for-byte CONTENT are settled. While
transcribing, several errors from my first pass were caught and
fixed (loop labels off by 1-2 instructions, two self-modifying
writes with the destination swapped) -- all found precisely THANKS
TO the byte-for-byte comparison, not visual inspection.

## JT_SLOT2 (0x8440-0x8800): the "actor" engine -- the full resident zone disassembled

Using `Z80Dasm.exe` (already included in `FISICO\MADMIXGAME_DISC\`)
with the right parameters (`-begin 7 -offset 8400`, to skip the
7-byte header and number things with real addresses) a reliable
disassembly of the WHOLE resident gap 0x8440-0x8800 was generated
(960 bytes, `JT_SLOT2`'s target). Worth remembering for the future:
`Z80Dasm.exe -begin 7 -offset 8400 MADMIX1.BIN > output.txt` gives
real addresses directly, no need to do the arithmetic by hand.

It's an **actor/moving-object** system (characters, almost
certainly), not just a loose routine. Pieces identified:

- **`0x8437`** confirmed as the **active-actor counter**: there's a
  loop at `0x86BB` that decrements `0x8437` and advances an IX
  pointer by -12 bytes each time (12-byte actor records, probably),
  until it reaches 0 -- and it's the SAME variable that
  `JT_SLOT3`/`RESET_8437` zeroes out. It fits: the public API can
  "empty" the active-actor list.
- An actor record accessed via `IX+0` through `IX+9` (10+ fields:
  on-screen position, data pointer, frame counter...).
- **`ADDR_FROM_DC00` (0x8988) IS ACTUALLY USED** (`CALL $8988` at
  `0x84AD`) -- confirms the earlier hypothesis: it converts a
  coordinate into an address inside the `0xD500-0xDDA0` zone.
- Two data tables: `0x92E3` (10-byte records, same layout as the
  actor struct -- probably "initial definition per actor/character
  type") and `0x91C3` (smaller records).
- **Software rendering with sub-pixel shifting**: two nearly
  identical code blocks (`0x85C1` and `0x8624`, selected via a
  computed `JP (IY)` based on the actor's position) do chained bit
  rotations (`RL`/`RR` with `EXX`) to shift a 24-bit mask pixel by
  pixel within 32-byte-stride rows, with `AND`/`OR` to blend it
  with the background -- exactly the same style as `REDRAW_STRIP`
  (0x8D1B) but applied to an object moving with FINE movement (not
  full-tile jumps).
- **Self-modifying code**: at `0x8779` there's a routine that
  WRITES values directly into the operands of later instructions
  (`LD ($87B6),A`, `LD ($87D4),A`, etc.) -- a classic 1987 8-bit
  performance technique.

### Big implication for the character-sprite mystery

If the actors/characters are rendered with this software system
(bit rotation over a buffer, the same style as the maze tiles),
**they may not use VDP hardware sprites at all** -- which would
explain why searching for "who writes VDP register 6" found
nothing, and why NO hardware sprite format (16x16 raster, 16x16
quadrant, independent 8x8) gave a meaningful image for
`0x9D40-0xA3E0`: that candidate may never have been hardware
sprites at all, and the characters' real graphics might be
somewhere else, in the SAME raster format as `tile_gfx.bin` (which
we already know decodes correctly).

### Traced IX+5/+6 (graphics pointer) -- leads to a STATIC dead end

- **`0x92E3`, 12-byte stride**: confirmed to BE the active-actor
  array itself (not a separate "definition table"). `IX = $92E3 +
  (value_of_$8437_before_incrementing) × 12` -- in other words,
  `$8437` works as the "next free slot index" when creating an
  actor, IN ADDITION to being a counter when walking them later.
- **`IX+5`/`IX+6`** (the source pointer that feeds the copy loop at
  `0x8687`, the one that pulls 3 bytes from each 32-byte block) is
  filled from a "cursor" variable at **`0x8438`** -- and that SAME
  `0x8687` routine is the one that UPDATES `0x8438` when it
  finishes (`LD ($8438),DE` at `0x86B0`). It's a cursor that
  advances sequentially each time a new actor is created, reading a
  bit further into the same data stream.
- The INITIAL value of that cursor (before the first actor is
  created, when `$8437`==0) is literally **`$0500`** (`LD DE,$0500`
  at `0x851A`) -- a low-RAM address, outside both the static image
  (0x8400-0xDDA0) and the relocated block (0x1000-0x6500). The
  WHOLE file (22945 bytes) was searched for any other instruction
  that writes something TO `$0500` (i.e. what copies the real
  graphics there before they're read) -- **none turns up**. A dead
  end for static analysis: either something puts that data there by
  another means (the BASIC loader, the BIOS, a separate BLOAD...),
  or live memory needs to be inspected with an emulator to find out
  what's really at `$0500` at that point in the game.

**Recommendation**: this specific thread (finding the real pointer
to the character graphics) has hit the limit of what static
analysis can give for now. The two paths still open are (a)
decipher the bytecode interpreter for the resource headers
(`0xCDCB`/`0xCDFF`/`0xCE0C`, confirmed to indeed be tokenized
bytecode with prefix `85 64` and opcodes ≥`0x80` -- a custom
language, not a direct pointer, so its interpreter needs to be
located first, which still hasn't happened) or (b) live tracing
with an emulator+debugger, which will very likely solve this much
faster than continuing to pull bytes by hand.

### IMPORTANT CORRECTION: the copy direction was backwards

Everything above about "IX+5/6 is the SOURCE graphics pointer" was
misread. Looking at `JTS2_COPY_CURSOR` (0x8687) carefully:

```asm
LD L,(IX+$05) / LD H,(IX+$06)   ; HL = cursor ($8438/IX+5/6)
LD E,(IX+$02) / LD D,(IX+$03)   ; DE = buffer (ADDR_FROM_DC00)
EX DE,HL                         ; NOW: HL=buffer, DE=cursor
...
LDI                              ; copies (HL)->(DE)
```

`LDI` ALWAYS copies from `(HL)` to `(DE)`. After the `EX DE,HL`, HL
is the buffer (computed from the actor's position, inside `0xDC00`)
and DE is the cursor. In other words: the copy goes from the
**position-dependent buffer TO the cursor at `$0500+`**, not the
other way around. The cursor isn't "where the graphic comes from"
-- it's an **output/log buffer** that gets filled by reading from
the `0xDC00` zone (inside "0xD500-0xDDA0 unexplored"). This fully
explains why searching the ROM for those bytes never found anything
(see below): it isn't a static resource copied once, it's a zone
recomputed at runtime from wherever each actor is.

An attempt was made to confirm this by searching for the real
bytes at `$0500` (from several live RAM dumps) inside `MADMIX1.BIN`,
inside `MADMIX.SCR` (21768 bytes) and even across the whole `.dsk`
(737280 bytes) -- **zero matches across all three**, not even with
8-byte fragments. Confirms the conclusion: this zone isn't a copy
of a static resource, it's generated at runtime. Pending:
investigate what's really at `0xDC00` (the real source zone) and
its relation to the actor's position -- it might connect with the
128-byte-per-entry table mentioned right below.

### Loose, unconnected finding: "$0500" as a QUANTITY (not an address) in the unexplored zone

Searching for `$0500`, it shows up 3 times as `LD BC,$0500`
(quantity, 1280 decimal) at `0xD97B`, `0xD9FB` and `0xDA7B` --
exactly every 128 bytes, inside the "0xD500-0xDDA0 unexplored"
zone. 1280 is also the exact size of `maze_data.bin`
(0xD000-0xD500). Probably a coincidence unrelated to the sprite
search, but it suggests a table with 128-byte entries in that zone
(a pointer + length per level?) -- noted to revisit if
`0xD500-0xDDA0` is investigated in the future.

### CORRECTION + CLOSED: the 128-byte table is NOT levels -- it's the `0xDC00` mask table, and there's no room in the .BIN for the 14 remaining levels

Picking the earlier thread back up: the raw bytes around
`0xD97B`/`0xD9FB`/`0xDA7B` were dumped and they are NOT real code --
they're highly repetitive data shaped like `01 xx` (16-bit
word-like pairs), and the `LD BC,$0500` is a coincidental byte match
inside that blob, not a real instruction (linear disassembly with
Z80Dasm also fails to produce an instruction at that address when
disassembling from `0x8400` -- confirming it falls inside a data
zone, not code).

The full table was walked using its 128-byte stride pattern: it
starts at **`0xD8FB`** and ends at **`0xDCFB`+128=`0xDD7B`**, i.e.
**9 entries × 128 bytes = 1152 bytes**, not 3. Comparing the
entries against each other, several are almost byte-for-byte
identical (e.g. `0xD9FB` and `0xDA7B` share their first ~32 bytes
exactly), which fits a **bitmask/pattern table** (for actor
sub-pixel rendering, same spirit as the `RL`/`RR` chains in
`JTS2_RENDER_A`/`JTS2_RENDER_B`) much better than level parameters.

**This is the SAME zone we already knew as the "static `0xDC00`
table"** (see the next finding) -- it simply extends further back
to `0xD8FB`, it doesn't start at `0xDC00` as had been bounded
before. The boundary is corrected here.

**Conclusion about the 14 remaining levels**: with this finding,
the whole `.BIN` (`0x8400`-`0xDDA0`, 22952 bytes) is now practically
fully mapped or accounted for:

- `0x8400-0x8800`: jump table + `ACTOR_ENGINE` (confirmed byte for byte)
- `0x8800-0xB940`: main code (partially transcribed)
- `0xB940-0xC4A0`: `tile_gfx.bin` (2912 bytes, confirmed)
- `0xC4A0-0xD000`: resource manager (2912 bytes, untranscribed but identified as code, not level data)
- `0xD000-0xD500`: `maze_data.bin`, ONE level (1280 bytes, confirmed)
- `0xD500-0xD8FB`: still unmapped (~1019 bytes)
- `0xD8FB-0xDD7B`: actor mask/render table (1152 bytes, this finding)
- `0xDD7B-0xDDA0`: tail/filler (~37 bytes)

**There isn't remotely enough room for 14 more levels of 1280 bytes
each (17920 bytes) in any gap in this file.** The full disk listing
was also checked
(`FISICO/MADMIXGAME_DISC/.../Mad MIX Game (1987)(Topo Soft)(Sp)/`):
only `AUTOEXEC.BAS`, `MADMIX` (184 bytes, tokenized BASIC, a loader
"cracked by Pau d'Aci" that loads the same 3 usual files),
`MADMIX.BAS`, `MADMIX.SCR` (21768 bytes, loading/title screen),
`MADMIX0.BIN` (58 bytes) and `MADMIX1.BIN` (22952 bytes) exist --
**there are no separate per-level files** (nothing like
`LEVEL1.DAT`, `MADMIX2.BIN`, etc.).

**This casts doubt on the starting premise of "15 levels each with
its own 32×40 map"**: either (a) the levels are procedurally
generated/derived from a single base map (rotation, mirroring,
palette/visual-theme swap reusing the same matrix), or (b) "15
levels" in the player's memory doesn't mean 15 geometrically
distinct mazes, but 15 repetitions/laps of increasing difficulty
over few base maps (or the same map). **Pending a check with the
developer**, who originally played the game and can clarify whether
the maze visibly changes for real between levels.

**Developer's answer: the maze DOES change geometrically between
levels** (it isn't the same layout recycled with different
difficulty). This means the search has to continue -- the 15 maps
exist in some format, somewhere.

### LOCATED: the resource bytecode interpreter (a piece that had been pending for several sessions)

Disassembling `0xC4A0` in the real `.BIN` (not the internal, still
incomplete, position in `madmix1.asm`), the real body of the
already-known "resource slot manager" shows up (`0xC4A0-0xC900`,
see the zone table), and inside it, starting at `~0xC4EB`, a **real
bytecode interpreter**:

```asm
LD C,(IX+2) / LD B,(IX+3)      ; BC = pointer to the bytecode program
...
LD A,(BC)                      ; reads a byte from the program
CP $80
JP C,$C527                     ; < 0x80: "literal" byte (separate branch)
SUB $80
LD HL,$C99E
CALL $C8BC                     ; HL = $C99E + A*2 (2-byte pointer table)
JP (HL)                        ; jumps to the opcode's routine
```

This is EXACTLY the interpreter that was being searched for since
the earlier section ("decipher the bytecode interpreter... which
still hasn't been found") -- it was inside the same
`0xC4A0-0xC900` already listed as "resource manager, real code" in
the zone table, it just hadn't been entered until now.

**Dispatch table `0xC99E`**: 15 valid pointers (`0xC6E5`, `0xC703`,
`0xC765`, `0xC6EE`, `0xC761`, `0xC733`, `0xC774`, `0xC7AB`, `0xC74D`,
`0xC7F4`, `0xC797`, `0xC70E`, `0xC84B`, `0xC867`, `0xC878`), all
within `0xC6xx-0xC8xx` (right before the interpreter itself),
followed by zero filler up to 32 entries. In other words: **15 real
opcodes** (`0x80`-`0x8E`), each with its own "draw command" routine
-- almost certainly a vector-graphics/compact-command interpreter
(things like "draw line", "fill", "copy block"...) for the already-
known resource headers `0xCDCB`/`0xCDFF`/`0xCE0C`.

**On whether this explains the 15 levels**: for now it CANNOT be
confirmed. All we know for certain about the real calls to `0xC4A0`
is that there are only **3** in the whole ROM (the ones in `INIT`,
with pointers to `0xCDCB`/`0xCDFF`/`0xCE0C`, slots 0/1/2 -- see the
section above) -- there's no fourth call, let alone 15, anywhere
detected so far. That suggests these 3 resource loads are for
something fixed (palette, candy frame, title...) and NOT for levels,
unless the engine loads levels through a completely different path
(maybe calling the opcode routines directly without going through
`0xC4A0`'s slot register, or the 15 maps use a completely separate
format still not located).

**Honest conclusion for this finding**: it's a real and valuable
piece of the puzzle (it closes an open question from earlier
sessions: "the interpreter hasn't been located"), but **it doesn't
by itself solve where the other 14 levels are**. The large,
genuinely unexplored stretch is still `0x8800-0xB940` (main code,
the sample taken at `0x8F71-0x8FF0` is real, dense game logic, not a
data table, but it hasn't been walked in full) and the body itself
of the 15 opcode routines (`0xC6E5`-`0xC8xx`) together with the
`0xCDCB`-`0xCF8B` headers, which still haven't been read line by
line. Reasonable next step: read what each of the 3 known headers
does (how many bytes of program does each have? which opcodes does
it use?) to find out whether this language would, in principle, be
capable of encoding a 32x40 maze in a reasonable space.

### The bytecode has subroutine CALL/RET -- and a real pointer table at 0xCB72 (but it's NOT the level table)

Suggestion from the developer: since there are 15 levels, search the
data zone for a **pointer table** (probably RLE format given they're
tile maps). A script was written that scans the WHOLE `.BIN` looking
for stretches of 15+ consecutive 16-bit words whose value always
falls within the valid `0x8400-0xDDA0` range (the typical footprint
of a pointer table). 3 serious candidate zones came up:

- `0x8A0E`: **ruled out** -- it's the `LDI` instruction (`ED A0`)
  repeated many times in a row (an unrolled copy loop), not a table;
  the byte `ED A0` falls in the valid range by pure coincidence.
- `0xCE10`: **ruled out** -- these are the bytecode program's own
  bytes for header `0xCE0C` (the language's real operands/opcodes),
  not a pointer table.
- **`0xCB72`: IS a real pointer table.** 12 increasing addresses
  (`0xCB9C, 0xCBD3, 0xCC1C, 0xCC45, 0xCC96, 0xCCD0, 0xCCEF, 0xCD16,
  0xCD3F, 0xCD76, 0xCD91, 0xCDAB`), with variable-sized "chunks"
  between consecutive entries (26 to 81 bytes) -- fits with
  variable-length, RLE-like blocks. A 13th entry follows (`0xCBB0`)
  and then 8 entries identical to the first one repeated (`0xCB9C`),
  probably unused/default slots.

**What code uses this table was traced** (the only reference to
bytes `72 CB` in the whole `.BIN`: `0xC85D`), and it turns out to
be the handler for **opcode `0x8C`** in the already-known dispatch
table `0xC99E`. Disassembled (`0xC84B-0xC875`):

```asm
; opcode 0x8C: "CALL subprogram(index)"
LD A,($C9BC)      ; active-slot index (the same $C9BC the
                   ; developer saw varying in step with the music)
INC BC
ADD A,A
LD L,A \ LD H,0
LD A,(BC)          ; A = operand byte = subprogram index
INC BC
LD DE,$CA61
ADD HL,DE
LD (HL),C \ INC HL \ LD (HL),B   ; saves the current BC (return addr) at $CA61+slot*2
LD HL,$CB72
CALL $C8BC         ; HL = $CB72 + index*2  (generic table lookup)
LD B,H \ LD C,L
JP $C518           ; resumes the interpreter loop with BC = new pointer

; opcode 0x8D (next in the table): "subprogram RET"
LD A,($C9BC)
ADD A,A
LD L,A \ LD H,0
LD DE,$CA61
ADD HL,DE
LD C,(HL) \ INC HL \ LD B,(HL)   ; restores the saved BC
JP $C518
```

In other words: the bytecode language has a **real subroutine
call** (with a 2-byte-per-active-slot "return stack" at `0xCA61+`),
and `0xCB72` is the table of reusable subprograms (shared drawing
pieces -- wall chunks, corners, etc.) that any bytecode program can
invoke by index. **This confirms the graphics engine is much more
sophisticated than it looked**, but it is NOT -- on its own -- the
table for the 15 levels: it's generic interpreter infrastructure,
usable by any resource (including the candy frame or the title).

**Just in case, ALL real calls to `0xC4A0` and to `0xCF8B` in the
whole `.BIN` were also checked** (searching for bytes `CD A0 C4`
and `CD 8B CF`, which would find the call regardless of how it goes
through register DE even if loaded dynamically):

- `CALL $C4A0`: exactly 3, all inside `INIT` (the already-known
  ones, slots 0/1/2).
- `CALL $CF8B`: 8, all clustered between `0x8F2E` and `0x9100`
  (`INIT`/boot zone), none scattered through the rest of the code.

**Conclusion**: the `0xC4A0` "resource slot" mechanism is NOT used
to load levels -- it's used exactly 3 times, always at boot, for
resources unrelated to the maze. Loading the 15 levels has to go
through a completely different code path, almost certainly inside
the large `0x8800-0xB940` stretch still not systematically walked
(the two samples taken there are normal, coherent game logic, not
tables, but they're only a couple of ~100-byte windows within
~10KB). That's the most promising place to keep looking.

### CORRECTION: the "unexplored" stretch is much smaller than estimated, and is already practically exhausted -- the 15 levels still haven't turned up

The developer, looking at live memory, flagged large blocks that
were "structured but not identical" between `~0x9530` and
`~0xB8A7`. Checked against the static `.BIN`:

- Matches findings ALREADY documented in earlier sessions (zone
  table, above): 8x8 font/icons (`0x9300-0x9700`), the 53 16x16
  blocks ruled out as sprites (`0x9D40-0xA3E0`), and above all the
  **striped candy frame** (`~0x9600-0xB700`, repeated `00/FF`
  pattern) -- exactly the `FF FF FF 00 00 00` pattern seen in the
  raw dumps. In other words: it's **decorative graphics already
  catalogued, just never extracted into the project**, not new
  level data.
- Disassembling what's IMMEDIATELY BEFORE that zone
  (`0x9100-0x9134`) confirms it's real, coherent code (a scroll
  loop synced to VBLANK) that ends in a clean `RET` at `0x9134`.
  From `0x9135` onward the disassembly degenerates into garbage
  (`JR NZ`/`SBC`/`XOR` patterns with regular operand increments) --
  a clear sign the disassembler has desynced entering a data zone.
  **This shrinks the genuinely unexplored code stretch from
  `0x8800-0xB940` (~10KB) down to just `0x8800-0x9134` (~2.3KB)**,
  and that stretch had already mostly been sampled in earlier
  sessions (ISR, housekeeping, FILVRM/LDIRVM/SETVRAM, LOOKUP_8978,
  ADDR_FROM_DC00, RESET_8437, WAIT_VBLANK, MAP_COORD_TO_ADDR,
  TILE_TYPE_LOOKUP, REDRAW_STRIP, TILE_TYPES, INIT).

Within that small stretch there were exactly 3 real unknowns left:
the targets of `JT_SLOT6` (`0x8E3C`), `JT_SLOT8` (`0x89AD`) and
`JT_SLOT9` (`0x8C34`) -- the only part of the engine's public API
(the jump table at `0x8400`) that still hadn't been identified. All
3 were disassembled:

- **`JT_SLOT8` (`0x89AD`)**: reads the camera/Pac-Man position
  (`$2C02`), checks with `AND $03` which sub-tile "quadrant" it
  falls in, and dispatches (via `RRA`+`JP C`) to different scroll
  routines depending on which tile edge was crossed. It's the
  **scroll trigger** (part of the already-known camera tracking),
  not level loading.
- **`JT_SLOT9` (`0x8C34`)**: clears a large VRAM block (a 36-row
  loop writing to `$DE04`+offset, plus 2 96-byte fills via
  `FILVRM`/`0x8931`), and if `$2C27` (probably a digit counter) is
  nonzero, **draws text/score with a font from `0x92C3`** (the same
  "font/icons" zone mentioned above), letter by letter, inverted
  via the VDP port. It's the **score/HUD refresh**, not level
  loading.
- **`JT_SLOT6` (`0x8E3C`)**: reads a pair of flags (`$8EC4`/`$8EC6`,
  inside the `TILE_TYPES` table itself) and runs a 5-check loop over
  a table at `0x8E88`, building a bitmask in `E`. Looks like
  collision/entry logic (same style as `DIRBITS_TABLE`), not level
  loading.

**Honest conclusion**: reasonable static searching within the code
that's genuinely available and unexplored has been exhausted. None
of the jump table's last 3 unknowns is a level loader, the resource
mechanism (`0xC4A0`) isn't used for levels, and there's no raw space
left for 15×1280 bytes anywhere in the `.BIN`. **Recommendation**:
the fastest path from here is LIVE, not static -- set a WRITE
breakpoint on the already-confirmed buffer `$FC60` (where
`MAP_COORD_TO_ADDR` places the current tile matrix) and see which
code address does that write the first time a level starts (or when
changing levels). That address would, in all likelihood, be the
real level loader, whatever its source format turns out to be.

## RESOLVED: THE 15 LEVELS ARE NOT IN `MADMIX1.BIN` -- THEY'RE IN `MADMIX.SCR`

**This is the most important finding across several sessions.** The
recommendation above was followed: the developer set a write
watchpoint in `openMSX` over the whole `$FC60-$FE5F` buffer:

```tcl
debug set_watchpoint write_mem {0xfc60 0xfe5f}
```

and started level 1. The first break landed at `PC=0x9115`
(discarded: it was the already-known ball-blink animation). The
SECOND break, right as the level started, landed at **`PC=0x5943`,
`SP=0x0FFD`** -- **an address in low memory (0x4000-0x7FFF),
COMPLETELY OUTSIDE the range of `MADMIX1.BIN`** (`0x8400-0xDDA0`).

### The real loader: `0x5904` (low memory, resolved with a live RAM dump)

The whole RAM was dumped at the moment of the break
(`save_debuggable memory ram_level1_load.bin 0 65536`,
`src/dump_openmsx/ram_level1_load.bin`) and disassembled with
`Z80Dasm.exe -begin 5904 -offset 5904 ram_level1_load.bin`
(hexadecimal addresses as the argument, no MSX header because
`save_debuggable` dumps raw RAM). Full result, coherent and never
desyncing:

```asm
; 0x5904 -- LEVEL LOADER
LD A,($2C07)        ; A = current level number (state variable)
LD HL,$59A9         ; HL = level table (see below)
LD BC,$0014         ; 20 bytes per record
AND A
JR Z,$5914
  ADD HL,BC          ; HL += 20 x A times  (HL = table + level*20)
  DEC A
  JR NZ,$5910
LD DE,$2BF3          ; copies the 20-byte record to working RAM
LDIR
LD DE,$FC60          ; DE = THE ALREADY-KNOWN LEVEL BUFFER
LD HL,($2BF5)        ; HL = record field2 (pointer to a fixed HEADER)
LD BC,$0060          ; 96 bytes (3 rows of 32)
LDIR                 ; copies the fixed header to $FC60
LD A,($2BF9)         ; A = record field6 (VARIABLE row count)
LD L,A \ LD H,0
ADD HL,HL (x5)       ; HL = A*32  -- the 32-column stride, confirmed again
LD C,L \ LD B,H       ; BC = variable_rows * 32
LD HL,($2BF3)         ; HL = record field0 (pointer to the level BODY)
...
; main loop (0x593F-0x5947):
RES 7,(HL)            ; clears the "eaten" bit on each source cell
LDI                    ; copies byte by byte, BC times, into $FC60+96 onward
JR NZ until BC=0
```

**This is exactly the level-reconstruction engine**: it copies a
fixed 3-row header + a variable-length body (`field6 * 32` bytes)
right after it, both into the `$FC60` buffer already known from
`MAP_COORD_TO_ADDR`.

### The source: `MADMIX.SCR` is NOT a screen image -- it's a BLOAD of code+data relocated with `MADMIX0.BIN`'s trick

`MADMIX.SCR`'s real header (first 7 bytes, `FE 00 88 00 DD 00 88`):
type `FE` (normal machine-code BLOAD, NOT type `FF`/screen),
**start=0x8800, end=0xDD00, exec=0x8800** -- practically the same
address range where `MADMIX1.BIN` later gets loaded. This fits
EXACTLY with the old finding (from earlier sessions, when
`PHASE`/`DEPHASE` was investigated and then ruled out for the main
engine) that `MADMIX0.BIN` does an `LDIR` from `0x8800` to `0x1000`,
`BC=$5500`: that `LDIR` wasn't relocating the main engine (which
does run at static addresses, as already shown) -- **it was
relocating the content `MADMIX.SCR` had just loaded**, moments
before `MADMIX1.BIN` overwrote that same zone with the real engine.
Real boot sequence:

1. `BLOAD"MADMIX.SCR"` -- loads ~21KB of code+data at `0x8800-0xDD00` (a staging position, not final)
2. `BLOAD"MADMIX0.BIN",R` -- runs the relocator: `LDIR` copies that ~21KB from `0x8800` to `0x1000` (low memory, permanent)
3. `BLOAD"MADMIX1.BIN"` -- overwrites `0x8400-0xDDA0` with the game engine (what we've spent months reconstructing)
4. The engine (`INIT`, `0x8F71` onward) calls into the now-relocated low memory (`CALL $5904`, `CALL $5CD1`, etc. -- calls already seen in `INIT`'s disassembly but left uninvestigated, assumed to be "external")

**Verified byte for byte**: the bytes in `MADMIX.SCR` at the
position corresponding to `0x5904` (applying the inverse offset,
+0x7800, and `MADMIX.SCR`'s file offset) match EXACTLY the bytes
seen in live RAM at `0x5904`. Confirmed with a script, 0
differences across 31 bytes compared.

### The 15-level table: `0x59A9` (relocated) / `0xD1A9` (in `MADMIX.SCR`), 20 bytes per record

Fully extracted from `MADMIX.SCR` (15 records of 20 bytes,
`0x59A9 + level*20`):

| level | field0 (body pointer) | field2 (header pointer) | field6 (variable rows) | total rows (3+field6) |
| --- | --- | --- | --- | --- |
| 0 | 0x335C | 0x50BC | 22 | 25 |
| 1 | 0x335C | 0x50BC | 22 | 25 |
| 2 | 0x361C | 0x50BC | 15 | 18 |
| 3 | 0x37FC | 0x50BC | 16 | 19 |
| 4 | 0x407C | 0x4AFC | 15 | 18 |
| 5 | 0x3C3C | 0x4AFC | 16 | 19 |
| 6 | 0x3E3C | 0x50BC | 18 | 21 |
| 7 | 0x443C | 0x4AFC | 19 | 22 |
| 8 | 0x425C | 0x4B5C | 15 | 18 |
| 9 | 0x39FC | 0x50BC | 18 | 21 |
| 10 | 0x469C | 0x50BC | 17 | 20 |
| 11 | 0x4BBC | 0x50BC | 21 | 24 |
| 12 | 0x4E5C | 0x4AFC | 19 | 22 |
| 13 | 0xCFA4 | 0x4AFC | 21 | 24 |
| 14 | 0xD244 | 0x50BC | 23 | 26 |

**Note, CONFIRMED by the developer**: level 0 and level 1 have an
IDENTICAL 20-byte record, byte for byte, but **the real game does
NOT have 15 levels, it has 14** -- the developer confirms the first
level doesn't repeat while playing. In other words: `$2C07` is
1-indexed (level 1 = table index 1) and index 0 is a dead/unused
record (filler, never reached by the real game). **The 14 real
playable levels are table indices 1-14; index 0 doesn't count.**

**Data format visually confirmed**: the first ~48 bytes of several
`field0` pointers and of the shared `field2` (`0x50BC`, shared by 8
levels) were dumped. Result:

- `0x50BC` (shared header): **`0x42` repeated 48+ times in a row**
  -- a whole row of a single tile (probably the "empty" area outside
  the maze the developer described: "3 more rows on top"). With bit7
  cleared by `RES 7,(HL)`, pure tile `0x42`.
- Level 0 (`0x335C`): `09 05×11 0B 05×11 0A 42×7 02 2D BF 2D BF 2D
  BF 2D BF 2D BF 2D 02 2D BF 2D...` -- instantly recognizable: long
  runs of a wall tile (`0x05`), corners (`0x09`/`0x0B`/`0x0A`), an
  empty stretch (`0x42`), and the alternating `0x2D`/`0xBF` pattern
  (with bit7, `0xBF&0x7F=0x3F`) -- **exactly the 2 most frequent
  values in `maze_data.bin`** (`0x2D` 282 times, `0x3F` 277 times,
  see the `LD BC,$0500`/histogram finding above). It's the corridor-
  with-alternating-balls pattern.
- Levels 2 and 4: equally recognizable patterns (long runs of a
  tile, pairs of "caps" `0x4A`/`0x4B` and `0x47`/`0x48` repeating at
  a regular period -- wall decoration).

**Final conclusion on the "memory saving" the developer had asked
about**: there's NO RLE compression. It's the raw tile-index
matrix, identical in spirit to `maze_data.bin`, **but each level is
stored with ITS OWN height** (18 to 26 rows, not a fixed 40) -- the
saving comes from not padding every level to a common maximum, not
from compressing the data itself. With heights of 18-26 rows × 32
columns, each level takes between ~600 and ~850 bytes -- all 15 fit
easily in `MADMIX.SCR`'s 21768 bytes (which also includes the
loader code, the table, and probably more shared resources like the
headers/"caps" reused across levels).

**Pending, now minor**: decide whether `maze_data.bin`/its copy in
`MADMIX1.BIN` (`0xD000-0xD500`, fixed 40 rows) is an old development
copy, an independent "demo/attract" level, or something else.

**DONE**: `MADMIX.SCR` now has its own source, `src/madmix_scr.asm`,
with `PHASE $1000`/`DEPHASE` (correctly applied here, unlike in
`madmix1.asm`). It transcribes everything confirmed in this
session: the title-screen drawing (`0x1000-0x10E4`, identity-name
table + bitmap copy + color decompression), `COORD_TO_ADDR`
(`0x545F`), the full level loader (`0x5904-0x59A9`) and the 14-level
table (`0x59A9-0x5AD5`). **Verified 0 differences byte for byte**
against the original `MADMIX.SCR` across the 7646 confirmed bytes
(header + title-screen code + bitmap + compressed color +
`COORD_TO_ADDR` + loader + level table). The rest are honest `DS`
gaps (zones still not disassembled, mainly the raw data for the 14
levels scattered between `0x335C` and `0x545F`).

## DONE: `0x335C-0x511C` fully transcribed -- the bodies/headers of the 14 levels, with 0 differences

What was already known conceptually (the content feeding
`niveles.html`) got formalized in `madmix_scr.asm`: the `field0`
(body) and `field2` (header) pointers of each `LEVEL_TABLE` record
point into this zone. The 12 unique bodies + 3 unique headers were
extracted directly from the original `MADMIX.SCR` (address formula:
`file_offset = relocated_address - 0x1000 + 7`, verified first
against the already-known first 10 bytes of `LEVEL_TABLE` before
trusting it) and placed as `INCBIN` blocks labeled by real address
(`BODY_L01` .. `BODY_L12`, `HEADER_4AFC`, `HEADER_4B5C`,
`HEADER_50BC`) in `src/data/niveles/`.

**Finding when sorting the blocks by address**: they turned out to
be **perfectly contiguous with each other** (each one ends exactly
where the next starts, no padding), with **a single exception**: a
real **576-byte gap at `0x48BC-0x4AFC`** that doesn't match any
`LEVEL_TABLE` pointer. Its content looks just like any level body
(tiles `0x42/0x05/0x2D/0xBF/0x36/0x33`...) and measures exactly 18
rows × 32 columns = 576 bytes -- the same size as levels 6 and 9.
It was extracted the same way (`BODY_HIDDEN_48BC`) and documented as
a **strong candidate for an extra unused/development level**,
parallel to `maze_data.bin` in `MADMIX1.BIN`: it exists, it's
shaped like a real level, but no table record references it, so the
game never loads it.

**VISUALLY CONFIRMED (`src/recursos/nivel_oculto.html`, rendered
with the same tile decoder as `niveles.html`)**: **it's a real
15th level, hidden/unused**. The developer (who played the
original) confirms it: **the interior walls draw the silhouette of
a Pac-Man, bordered by one-way tiles** -- a design too deliberate to
be noise or a data misread. The developer adds an important piece
of context: **the game "is supposed to" have 15 levels but they
never located all 15 while playing, nor in any reference online** --
this finding fits exactly with that open count. Candidates for its
nature: an Easter egg, a development test level, or content cut
before release. It's still not linked from `LEVEL_TABLE`, so as
shipped on the disk it's never reached by playing -- pending
deciding whether it's worth patching a table record (e.g. the dead
0) to point at this block and check whether it's genuinely playable
in an emulator.

## COMPARED against v2.0 (CAS+ROM, the "can't get past level 13/14" bug already fixed per the developer): the hidden level is STILL unused -- it isn't the cause of the known bug

The developer provided `FISICO\MADMIXGAME_CAS\madmix.cas` and
`madmix.rom`, a 2.0 version with the Spectrum "can't get past level
13/14" bug already fixed, to check whether the hidden level
(Pac-Man-shaped) is the explanation for that bug (was the real 15th
level, broken/unreachable, what was blocking progress?).

**Method**: the CAS uses a different loading scheme from the disk
(blocks named after their final destination address: `LOADER`,
`LOGOTO`, `COLORS`, `PATS`, `1000`, `28EC`, `8400` -- its own tape
loader that places each block directly at its final address,
without `MADMIX0.BIN`'s relocation trick). The blocks were located
by their tape headers (sync marker `1F A6 DE BA CC 13 7D 74`), the
address↔file-offset correspondence was calibrated by searching for
KNOWN content (not assuming addresses), and it was verified against
`LEVEL_TABLE`'s record 0 before trusting anything.

**Result, with 0 differences verified byte for byte**: the 12
bodies + 3 headers + the full `LEVEL_TABLE` (15 records) + **the
hidden level at `0x48BC` itself** are, in v2.0, at **the exact same
addresses and with the exact same content** as in the disk's v1.0.
`LEVEL_TABLE` still has exactly the same 15 records, none pointing
at `0x48BC`. In other words: **v2.0 did NOT touch this zone at
all** -- it didn't relocate the hidden level, didn't link it, and
didn't delete it. It's just as orphaned as in v1.0.

**Conclusion**: the hidden/Pac-Man level **is not the cause** of
the "can't get past 13/14" bug -- if it were, fixing the bug would
have required touching `LEVEL_TABLE` or this memory zone, and not a
single bit was touched. The real bug must be elsewhere (most likely
candidate: the level-advance/end-of-game logic in `MADMIX1.BIN`,
not located yet -- pending if this lead is picked up by comparing
the CAS/ROM's `8400` block against `madmix1.asm`). The hidden level
still looks like what was already thought: content cut/deliberately
disconnected, unrelated to the level-progression bug.

**Useful side effect of this comparison**: while aligning addresses
in the `8400` block (the equivalent of `MADMIX1.BIN`), the real
7-byte bug in `madmix1.asm`'s header was detected and fixed (see
its own section above).

## LOCATED (partially): the real fix for the "level 13 doesn't count balls correctly" bug -- without touching `madmix1.asm`, diagnosis only

Context provided by the developer: the real v1.0 bug (inherited from
the Spectrum original, per external sources they checked) is that
**level 13's eaten-ball counter doesn't work right** -- even if you
eat them all, the level is never marked complete. v2.0 (CAS+ROM)
fixes it: you can finish 13 and move on to 14, but from there it
loops back to level 1 (there's no accessible hidden 15th) and the
hidden/Pac-Man level is still unused (confirmed in the section
above).

**Method**: a full byte-for-byte diff of the engine's 22945 bytes
(`0x8400-0xDDA0`) between the original `MADMIX1.BIN` (disk) and the
CAS's `8400` block, **also verified against the ROM** (an
independent build) to rule out it being a tape artifact -- the three
findings below are byte-for-byte IDENTICAL in both CAS and ROM.

**The only real changes across the whole engine** (aside from a
~340-byte zone at `0x93DD-0x9532` which is already DATA in the
original, not code -- the disassembler degenerates the same way in
both versions, so those diffs belong to a table, not logic; its
content hasn't been investigated yet):

1. **`0x8CD4`**, inside `MAP_COORD_TO_ADDR` (0x8CB6, already
   transcribed in `madmix1.asm`): `LD HL,$FC60` → `LD HL,$FC50`.
   `$FC60` is the active-level-matrix buffer, already confirmed and
   used in `LEVEL_LOADER`/`MAP_COORD_TO_ADDR`.
2. **`0x8BE5`**: the same change (`LD HL,$FC60`→`$FC50`) in a TWIN
   routine still not transcribed (it lives in the `DS` gap right
   before `MAP_COORD_TO_ADDR` in `madmix1.asm`, "Gap up to
   MAP_COORD_TO_ADDR" section). Same surrounding byte structure
   (`21 60 FC` → `21 50 FC`, preceded by `18 1F CB` repeated x3 in
   both places) -- they're two nearly identical copies of the same
   routine, a pattern already seen before in the item-activation
   subsystem.
3. **`0x8F26`**, inside `INIT` (0x8F24): `LD SP,$0FFF` →
   `LD SP,$F2FF`. Completely changes the memory zone where the
   stack lives. Possibly unrelated to the ball-counter bug -- could
   be a necessary adjustment for how the tape/ROM loader manages low
   memory (the CAS's loading scheme is different from the disk's,
   see the section above), not necessarily part of the counter fix.
4. **A new ~180-byte block at `0xC9BC-0xCA73`**: in v1.0 it's pure
   zero filler (unused); in v2.0 it has real code, fitted exactly
   into that gap without shifting anything else in the file
   (everything before and after stays byte-for-byte identical).
   Full bytes:

   ```text
   02 01 00 00 CD 5E 00 00 1E 3D 00 01 0E CB CD D0
   CD 4D 00 C0 00×34 FF CD A5 CB 06 00 18 00 01 0F
   CD 5E 00×10 07 00×4 FE 00×4 01 00×9 F2 00×3 0C CE
   13 CE 4E 00 C0 00×29 0A 00 03 00 01 00×3 1E 01 00
   00 09 CE 00×3 F7 00 07 00×4 FE 00×4 01 00
   ```

   Not cleanly disassembled yet (the real entry point isn't
   obvious; linear disassembly attempts from `0xC9BC` degenerate
   into scattered NOPs, a sign the routine's real start is further
   along or the block mixes code with data). **It contains no
   literal reference to `$2C08` (ball counter) or `$2C07` (current
   level)** as the byte pair `08 2C`/`07 2C`, so if it's related to
   the counter it's indirect (via a register, not a literal
   address).

**Conclusion (partial, without touching `madmix1.asm`)**: the
strongest candidate for the real fix is the `$FC60`→`$FC50` change
in the two copies of the coordinate→address formula, possibly
combined with the new code block at `0xC9BC` (which fits perfectly
in terms of timing: someone had to ADD logic for it to work, not
just tweak a constant). The `SP` change in `INIT` is suspected to be
a side effect of the CAS/ROM's different loading scheme, not the
fix itself -- pending confirmation. **Logical next step if this is
picked back up**: transcribe `0x8BE5`'s twin routine (to understand
what `MAP_COORD_TO_ADDR` does "in duplicate") and disassemble the
new `0xC9BC-0xCA73` block more carefully (trying different entry
points).

**CLOSED (later session, without fixing anything -- the goal is to
finish disassembling v1.0 exactly as it is, not to fix the bug)**:
the two pending pieces from this finding were, in fact, already
transcribed -- they just needed to be recognized and cross-
referenced:

- **`0x8BE5`'s twin routine** is `TILE_ADDR_CALC` (`0x8BC9` in
  `madmix1.asm`), transcribed in the session that resolved the 7
  `JT_SLOT5-9` gaps (same `AND $7C` + rotations idiom, same
  `LD HL,$FC60` base). `0x8BE5` falls right on that constant's low
  byte -- exactly the byte v2.0 changes from `$60` to `$50`. In this
  v1.0 it stays as `$60` (the original, deliberately unfixed bug),
  verified 0 differences.
- **The `0xC9BC-0xCA73` block** falls inside `RM_TABLE_C8DE` (the
  sound driver's data table), right after the 15-command jump table
  (`0xC99E-0xC9BB`) -- it's the zone already described as "in-RAM
  state of the channels, zeroed in the original". Checked byte for
  byte against the real `.BIN`: of the 183 bytes, 181 are `$00` and
  only 2 differ (`$07` at `0xCA6A`, `$FE` at `0xCA6F`) -- already
  transcribed as-is within the table, with no pending `DS` gap. It's
  precisely where v2.0 puts new code for the fix; in this v1.0 it's
  simply idle channel state, not yet used.

Both cross-notes were added as comments in `madmix1.asm` next to
`TILE_ADDR_CALC` and `RM_TABLE_C8DE`, recompiled and re-verified 0
differences byte for byte. Not a single bit of the real content was
touched -- the goal of this reconstruction is to reproduce the
original v1.0 exactly as it is, bug included, not to fix it.

**Verified**: the 16 blocks compile with `sjasmplus --sym`, each one
landing exactly at its real address, and the full byte-for-byte diff
against `MADMIX.SCR` gives **0 differences across the 7616 bytes**
of `0x335C-0x511C`. The only remaining diffs in the whole file fall
in the already-known, still-untranscribed gaps: the 3-byte one at
`0x28ED-0x28F0`, the item-position table + undisassembled code at
`0x511C-0x5904` (includes the item-activation subsystem already
documented above), and the unexplored tail `0x5AD5-0x6500`.

## The level record's remaining 13 bytes (offsets 7-19): deciphered with real code, not numeric pattern-matching

The 20-byte-per-level record (`0x59A9`+level×20) was picked back
up. Instead of guessing from each field's numeric value, **which
code reads each address** was traced ($2BF3-$2C06, where the full
record gets copied via `LDIR`) immediately after the copy, within
the same load function (`0x5904-0x59A8`) and in the stretch of
`INIT` that runs right after. Result, field by field:

- **Offsets 4-5** (a byte-for-byte duplicate of offsets 2-3, the
  header pointer): **NOT a wasted duplicate** -- it's used a SECOND
  time (`0x5965: LD HL,($2BF7) / LD BC,$0060 / LDIR`) to copy the
  fixed header (3 rows) again, this time RIGHT AFTER the level body
  that was just copied. **Confirms the developer's old observation**:
  3 extra rows on top AND 3 extra rows on the bottom, symmetric,
  both filled with the same header.
- **Offset 7** (`$2BFA`): copied into variable `$2C2B` (a single-
  use "pending flag" that `INIT` reads and clears right after). If
  its value crosses a certain threshold together with `$2C27`
  (already-known counter, set to 3 by `INIT`), it triggers a
  conditional draw of HUD text/icon via a text routine at `0x5CD1`
  (the same one that draws font glyphs). Real values: mostly 0/1,
  level 9 has a 2 -- looks like a small enum (a warning/special-icon
  type), not a simple boolean.
- **Offset 12** (`$2BFF`): **the clearest finding of all** -- it's
  the tile index that replaces the `0x3C` wildcard marker whenever
  it shows up in the level body's raw data (seen directly in the
  loader's main loop, `0x594B-0x5960`: `CP $3C` / on a match, it's
  replaced with `LD A,($2BFF)` before writing). The real values
  (`0x3F`,`0x40`,`0x41`) are all from the already-catalogued
  "floor with ball" family -- in other words, **the base map is
  shared between levels as a template, and each level only chooses
  which "ball" tile variant fills the wildcard gaps**. This also
  explains why several levels share the same body/header pointer
  (field0/field2): they're the SAME template with different
  filling.
- **Offsets 13-14** (`$2C00`, read as a 16-bit word): passed (with
  the high byte decremented by 1) to a helper function at `0x545F`
  which is **the exact same formula as `MAP_COORD_TO_ADDR`**
  (`AND $7C` + rotations = row×32+column, base `$FC60`). In other
  words, **row and column of an initial reference point** within
  the level matrix -- the result is stored in `$2C0A`, the same
  variable later used by the ball-blink animation (`0x9111`). Most
  likely candidate: the position of the level's first ball/animated
  piece, or a reference point for the initial scroll.
- **Offsets 15-16** (`$2C02`): copied AS-IS (with no formula
  applied) straight into `$2C02` -- which, as we already knew, is
  **the camera/Pac-Man position variable** that `MAP_COORD_TO_ADDR`
  uses continuously during play. In other words: **the real starting
  position of Pac-Man/camera when the level starts.**
- **Offset 17** (`$2C04`): copied straight into `$9147`, a position
  in the font/HUD table (next to `$9148`, which always gets the
  fixed value `0x78`). The real values are only 4 distinct ones
  (`0x30,0x38,0x60,0x70`) repeated across levels -- looks like a
  character/icon code for a "level type" HUD indicator or similar,
  not a value unique per level.

**UPDATED (2026-07-25)** -- offsets 8, 9, 10 and 11 are now
deciphered with real code; only 18 and 19 still have no reference
found. See the "Deciphered offsets 8/11/18/19" section below for
the full detail (this note is deliberately left outdated, as a
historical record of how the analysis evolved).

**CONFIRMED, IMPORTANT CORRECTION (14 levels, not 15)**: the
developer confirms the real game has 14 levels, not 15 -- level 0
(a record byte-for-byte identical to level 1) is a dead table
record the game never reaches (`$2C07` is 1-indexed; the playable
levels are indices 1-14). Corrected in `src/recursos/niveles.html`
(index 0 is now labeled "Record 0 (not playable)").

### The title screen IS in `MADMIX.SCR` -- packed together with the level loader

Question from the developer: is the title/loading-screen image also
in `MADMIX.SCR`? The relocated low-memory stretch `0x1000-0x335C`
(~9KB, unexplored until now, right before where the level loader
starts at `0x5904`/table `0x59A9`) was investigated, and it DOES
contain a real image-to-VRAM loading routine, fully disassembled
from `0x1000`:

```asm
; 0x1000-0x101D: writes an IDENTITY name table to VRAM $1800
; (the "name = pattern index" trick already known from
; FINDINGS.md, not the image itself -- it's the usual infrastructure)
LD HL,$1800 / OUT ($99),A x2 (sets VRAM pointer $1800, write mode)
LD BC,$0000
loop: LD A,C / OUT ($98),A / INC BC / LD A,B / CP $03 / JR NZ  ; 768 bytes = 0,1,2..255 x3

; 0x101F-0x103D: COPIES THE REAL IMAGE into the VRAM pattern table $0000
LD HL,$10ED        ; SOURCE pointer -- the bitmap itself, in this same MADMIX.SCR zone
LD DE,$0000        ; VRAM destination = $0000 (pattern table, SCREEN 2)
LD BC,$1800        ; 6144 bytes -- EXACTLY the size of the full pattern table
EX DE,HL / sets VRAM pointer (same OUT $99 x2 pattern + EX (SP),HL x2 delay)
EX DE,HL
loop: LD A,(HL) / OUT ($98),A / INC HL / DEC BC / ... JR NZ   ; copies the 6144 bytes

; 0x103F-0x104A: sets VDP register 7 (border/background color) to 1
LD A,$01 / LD B,A / LD C,$07 / OUT($99) / OR $80 / OUT($99)

; 0x104C onward: reconstructs the COLOR table (768 bytes, $2000)
; from $28F0, packed as NIBBLEs (4 bits/color) -- unpacked with a
; 16-entry table at $10AC (each color nibble -> full foreground/
; background attribute byte)
LD BC,$0300 / LD DE,$2000 / LD HL,$28F0
... (nibble-unpacking loop via the table at $10AC) ...
```

**Conclusion**: `MADMIX.SCR` isn't "just" the level loader -- it
does two jobs in the same file: (1) draws the full title/loading
screen (patterns + color, with the palette compressed to nibbles)
right at boot, and (2) stays resident in low memory after
`MADMIX0.BIN`'s relocation to serve as the level loader for the rest
of the game. That's why the name "SCR" isn't entirely misleading --
just incomplete: it's screen AND game data at once, packed together.

**DONE**: rendered in `src/recursos/portada.html`. Algorithm
verified exactly against the disassembly (index1 = `(ctrl>>3)&0x0F`,
index2 = `(idx1&0x08)|(ctrl&0x07)`, color =
`(table16[idx2]<<4)|table16[idx1]`, control byte `0x00` = color 0/0
without going through the table). With the identity name table and
the standard 16-color MSX1 palette, the result is the game's real
title screen on the first try: the green Pac-Man in the center, two
white ghosts on the sides, and the checkered floor -- confirming
that both the decompression algorithm's disassembly and the
pointers (`0x10AC`/`0x10ED`/`0x28F0`) were accurate.

## RAM composition before flushing to VRAM: confirmed for the background, refined for the actors

Question from the developer: given the game doesn't use sprites or
other VDP hardware features (already confirmed in earlier
sessions), is there a "work mirror" in normal RAM where the image
gets computed before being flushed to VRAM? This was investigated
thoroughly, reviewing both `madmix1.asm` (the already byte-exact
transcription of `ACTOR_ENGINE`) and `MADMIX.SCR`'s relocated block
(`0x1000-0x6500`), which until now had remained mostly unexplored.

### Confirmed: `JTS2_RENDER_A`/`JTS2_RENDER_B` don't touch VDP ports -- they read/write normal RAM

Reviewing the already-transcribed `madmix1.asm` code line by line:
the two actor sub-pixel render routines do `LD A,(HL)` / `AND`/`OR`
/ `LD (HL),A` -- **normal memory operations, NOT `OUT ($98)`/
`OUT ($99)` (the VDP ports)**. Since the TMS9918's VRAM **is not
mapped into the Z80's address space** (it's only accessed via those
two ports), this proves actor rendering, just like background
rendering, **writes into a normal RAM buffer, not directly into
VRAM** -- corrects what was said in earlier sessions ("the software
writes directly into VRAM's pattern table"), which was too literal
a conclusion drawn from live VRAM dumps.

### The actor cursor starts at `0x0500`, NOT at `0xDE04` -- they're two different buffers

Tracing `RESET_8437`/`$8437` and the code that calls
`JTS2_COPY_CURSOR` (right before it, in `madmix1.asm`):

```asm
LD HL, $8437
LD A, (HL)
AND A
JR NZ, JTS2_851F     ; if $8437 != 0, resumes the cursor saved at $8438
LD DE, $0500          ; if it's the FIRST time, the cursor starts at $0500
JR JTS2_8523
JTS2_851F:
LD DE, ($8438)
```

This **confirms with hard facts** (no longer just a loose hypothesis
from earlier sessions) that **`0x0500` is the work buffer dedicated
to actor rendering** -- a buffer DIFFERENT from the `0xDE04` that
`REDRAW_STRIP` uses for the background. `JTS2_COPY_CURSOR` copies
there, from the bitmask table (`0xD8FB-0xDD7B`, based on the
actor's position), the fragments that `JTS2_RENDER_A`/`B` then
combine (`AND`/`OR`) with the content already present to achieve
the sub-pixel shift.

**Important for the memory map**: `0x0500` falls inside what
`mapa_memoria.html` had marked as `0x0000-0x1000: not analyzed
(system/BIOS)` -- that zone DOES contain real game data, it needs
correcting.

### `0xDE04`: confirmed to be a large buffer (at least 144×32 = 4608 bytes), with its own init routine

Searching for all references to the literal `0xDE04` in both files
turned up a reset routine in `MADMIX.SCR`'s relocated zone (low
address `0x5B8C`):

```asm
LD DE, $DE04
LD B, $90            ; 144 rows
loop:
  PUSH BC / PUSH DE
  LD H,D / LD L,E
  INC DE
  LD (HL), $FF        ; seeds 1 byte...
  LD BC, $0017         ; ...and LDIR replicates it 23 more times (24 bytes total)
  LDIR
  POP HL
  LD BC, $0020         ; advances to the next row (32-byte stride)
  ADD HL, BC
  EX DE, HL
  POP BC
  DJNZ loop
```

Fills 24 of the 32 bytes of each of 144 rows with `$FF` (leaving 8
bytes of each row untouched -- probably the candy-frame/HUD side
strip, which isn't part of the playable area). **144 rows is a lot
more than one screen** (24 character rows = 192 pixel rows if the
unit were per-line, or 144 pixel rows = 18 character rows if the
unit is "per pixel line" -- suspiciously matching the height of the
SMALLEST level found, 18 rows). Confirms `0xDE04` is a noticeably
larger buffer than had been assumed before (not a simple work
strip), consistent with a "canvas" that comfortably fits the visible
content plus a scroll margin.

### Side finding: an RLE table at `0xD6B6` (inside `MADMIX1.BIN`'s "unexplored" zone) fills the VRAM pattern table

Filtering the calls to `FILVRM` in the relocated zone (`0x6432`
onward) turned up an RLE fill mechanism that reads `(value, count)`
pairs from a table at `0xD6B6` -- a **STATIC address inside
`MADMIX1.BIN`**, right in the `0xD500-0xD8FB` stretch the memory map
had as "unexplored" -- and calls `FILVRM` to paint the VRAM pattern
table in blocks (destination starts at VRAM `$0000`, advances by
each pair's count). Before that there's a `FILVRM` that sets the
whole color table (`VRAM $2000`, `0x17F8`≈6136 bytes) to color `1`.
This resolves part of the `0xD500-0xD8FB` gap: it isn't a work RAM
buffer, it's an **RLE data table consumed by MADMIX.SCR's relocated
code**, probably the initial drawing of a level (base fill before
the specific tiles).

### Side finding: HUD/score glyph-drawing routine (`0x5CAF`, low address)

The only `LDIRVM` call found across the whole relocated zone
(`0x5CBF`) turned out to be drawing ONE character (8 font bytes from
a table at `0x925B`, inside MADMIX1.BIN, plus matching color fill)
-- the score/HUD refresh, not a general screen dump.

### Honest conclusion -- what's still missing

**Confirmed**: there are at least TWO work buffers in normal RAM
with the same layout as VRAM (32-byte stride): `0x0500` (actors,
starts here the first time, persistent cursor at `$8438`) and
`0xDE04` (background/tiles, at least 4608 bytes, with its own
init-to-`$FF` routine). Both fit the developer's hypothesis: it's
all composed in software in RAM and then transferred to VRAM.

### RESOLVED: the flush from `0xDE04` to VRAM happens in the ISR (once per frame), with its own loop, without going through `LDIRVM`

An execution breakpoint was tried live (openMSX) at `LDIRVM`'s
entry point (`0x8942`), conditioned on `HL` falling inside
`0xDE04-0xF004` or `0x0500-0x0700` -- **it never fired**, even after
a good while of playing. This was itself a useful data point: it
confirmed the flush doesn't go through the shared `LDIRVM`
subroutine.

Static analysis was picked back up: `REDRAW_STRIP` (`0x8D1B`) was
fully disassembled for the first time (before it was just a `TODO`
stub in `madmix1.asm`) and confirmed to be a pure RAM-to-RAM `LDI`
copy (`TILE_GFX`/`0xB940+` → `0xDE04+`), with no `OUT` at all --
consistent with the `LDIRVM` watchpoint never firing on that side.

Searching for ALL references to the literal `0xDE04` in
`MADMIX1.BIN` (correcting the offset: the instruction address is 1
byte before where the address bytes appear), 5 more sites turned up,
all inside the `0x8860-0x8931` zone (the one we already had as "ISR
housekeeping + gap" in the memory map) -- **that is, inside the
VBLANK interrupt routine itself**. One of them, at `0x88E8`, is the
real flush:

```asm
; 0x88E5 onward (inside the ISR/housekeeping, 0x8860-0x8931)
LD DE, $0220        ; DE = destination address in VRAM (pattern table)
LD HL, $DE04         ; HL = SOURCE: the background buffer
LD B, $12             ; 18 (outer loop)
PUSH BC / PUSH HL / PUSH DE
EX DE, HL
CALL SETVRAM          ; sets the VRAM address (0x0220) by hand, NOT via LDIRVM
EX DE, HL
LD D, $20              ; 32 -- the same row stride already known
LD A, L
LD C, $98               ; VDP data port
LD E, $18                ; 24 (inner loop)
inner_loop:
  LD L, A
  LD B, (HL)             ; reads a byte from buffer 0xDE04
  OUT (C), B              ; REAL WRITE TO VRAM
  ADD A, D                 ; A += 32 (advances a row WITHIN the same high byte)
  DEC E
  JP NZ, inner_loop      ; 24 iterations
; (the outer loop, B=18, repeats all of it with H+1/D-1 -- see above at 0x88A5 onward)
```

**This confirms, with real code in its exact place, the whole
architecture the developer had proposed**: the background is
composed in RAM buffer `0xDE04` (by `REDRAW_STRIP` whenever a strip
needs redrawing) and gets flushed to VRAM **once per frame, inside
the ISR**, with a hand-written `OUT ($98)` loop (neither `LDIRVM`
nor `FILVRM`, which is why searches targeting those 2 routines
never found it). The flush isn't "the whole screen at once" but in
small blocks (at this specific point, 18×24=432 bytes) -- consistent
with only updating the strip that changed that frame, not the whole
canvas.

### RESOLVED: `0x0500` doesn't need its own flush -- it's a simple work "scratchpad", and the final result goes back into `0xDE04`

The `0x8860-0x8931` stretch was fully disassembled looking for an
equivalent flush for the actor buffer (`0x0500`) -- **no reference
to `0x0500` appears anywhere in that zone**. This, combined with the
two live breaks already captured with the developer, closes the
loop:

- **First live break** (`PC=0x869C`, inside `JTS2_COPY_CURSOR`):
  `LDI` with `HL=0xE511` (source, inside `0xDE04-0xF004`) and
  `DE=0x0501` (destination, inside `0x0500+`).
- **Second live break** (`PC=0x85A4`, inside `JTS2_85A2`, the BLEND
  step of `JTS2_RENDER_A`/`B`): `HL=0xE5F2`, again inside
  `0xDE04-0xF004`.

In other words: `JTS2_COPY_CURSOR` **copies a snapshot of the
current background from `0xDE04` into `0x0500`** (a simple
scratchpad/work area, with no persistent content of its own),
`JTS2_RENDER_A`/`B` do the bit-shifting arithmetic there, but the
**final result is written back into `0xDE04`** (confirmed by the
second break: the blend itself happens reading AND writing within
the background buffer, not in `0x0500`). `0x0500` never appears on
screen by itself, so it doesn't need (and doesn't have) its own
VRAM-flush routine -- the same `0xDE04` flush (`0x88E8`, VBLANK ISR)
already includes, as a side effect, any actor composited on top of
it.

**Final conclusion for this whole thread**: there's a single visible
canvas in RAM (`0xDE04`), where BOTH the background (`REDRAW_STRIP`)
AND the actors (`JTS2_RENDER_A`/`B`, using `0x0500` only as an
intermediate scratchpad) get composited, and a single family of
routines in the VBLANK ISR (`0x8860-0x8931`) that flushes it to VRAM
in blocks, once per frame. Architecture confirmed start to finish,
with cross-checked static AND live evidence.

## NEW SUBSYSTEM found while filling gaps in `madmix_scr.asm`: activating special items (power ball, hippo, tool, track...)

Picking back up the task of filling `madmix_scr.asm`'s `DS` gaps
(`0x2BF0-0x335C`, the 14 levels' scattered data, `0x5478-0x5904`),
the `0x5478-0x5904` stretch turned out to be quite a bit more than
"loose unidentified code": it's a **complete subsystem, never before
documented, for activating the game's special items** (power
ball, hippo, tool, tank/plane track -- the `items` already
catalogued in `graficos.html` as tiles `59-62`/`58`/`82-83`).

### General structure (disassembled, not yet transcribed into `madmix_scr.asm`)

Inside `0x5478-0x5904` there are **two nearly identical instances**
of the same handler (one code copy per item type handled there),
each shaped like this:

```asm
; handler (one instance per item type), ~170-280 bytes:
LD IX, ITEM_TABLE        ; $549B in the 1st instance, $5588 in the 2nd
PUSH BC                   ; B = number of entries to check (comes from outside)
loop:
  LD C,(IX+0) / LD B,(IX+1)         ; candidate position (row,col packed)
  LD HL,($2C02)                      ; Pac-Man/camera's current position
  ; does it match (within a 2-bit margin, AND $03) the current position?
  ...
  CALL $5559                          ; LOCAL helper identical to COORD_TO_ADDR
                                        ; (row*32+col -> $FC60+offset) -- yet
                                        ; another copy of the same formula,
                                        ; doesn't reuse the one at $545F
  ; checks bit 7 ("eaten" tile) and tile-type range (SUB $3F, CP $03)
  ...
  PUSH IX
  CALL $8440                            ; calls the actor engine DIRECTLY
                                          ; (ACTOR_ENGINE) to activate the item
  POP IX
  LD (IX+2), $01                          ; marks the entry as "active"
  CALL $57D8                                ; TODO: unidentified (associated effect)
  ; if the distance is within the window (CP $0C row, CP $09 column):
  DEC (2C08)                                  ; decrements the already-known
                                                ; counter (reset to 0 in
                                                ; the level loader, see
                                                ; the "13 bytes" section)
  LD (HL), A          ; at $5557, writes something to the destination tile
  CALL $8CEE                                    ; TODO: new address, unidentified
                                                  ; (inside the main engine,
                                                  ; near MAP_COORD_TO_ADDR/
                                                  ; TILE_TYPE_LOOKUP)
  LD A,(5 or 6)
  LD ($6128), A                                   ; TODO: unidentified variable
                                                    ; (score/HUD?)
  LD BC,$0007 / ADD IX,BC                           ; next entry (7
                                                      ; bytes/record)
  POP BC / DEC B / JP NZ,loop                        ; repeats for the B
                                                        ; entries
  RET
```

### The referenced tables

**4 addresses used as `LD IX,nnnn`** were located in this stretch:
`$549B`, `$5588` (each referenced twice, once per "pass"), `$5773`
and `$511C`. Real content checked:

- **`$511C`**: a clean table of **7-byte records**, confirmed with
  real data (`20 10 00 01 00 00 01`, `10 10 00 01 00 00 02`,
  `10 10 00 01 00 00 03`, `10 10 00 01 00 00 01`...) -- the last
  byte changes (`01,02,03,01...`, a candidate for "item type"), the
  first bytes look like position (row/column packed, same style as
  the rest of the engine). **This falls INSIDE what we had
  catalogued as "scattered data for the 14 levels"
  (`0x335C-0x545F`)** -- meaning that zone doesn't only contain tile
  matrices, it also contains per-level special-item position tables.
  Reclassifying still pending.
- **`$5773`**: NOT a static data table -- it's a **RAM work zone**
  (starts at zero in the `.BIN`, confirmed) which is also followed
  by real code that references it with `IX=$5773` (self-reference).
  Matches a loose finding from earlier sessions in
  `madmix1.asm`/`MADMIX1.BIN`: there's a loop at `0x58D9`
  (`LD B,$04 / LD HL,$5773 / LD (HL),$00 / INC HL / INC HL /
  DJNZ`) that clears this SAME address from the other file --
  confirms `$5773` is a variable shared between both binaries, not
  something exclusive to `MADMIX.SCR`.
- **`$549B`/`$5588`**: the two "active position" tables used by each
  handler instance (7-byte/entry format, same as `$511C`).

### DONE: `0x5478-0x5904` fully transcribed into `madmix_scr.asm`, 0 differences byte for byte

Disassembled with Z80Dasm without ever desyncing across the whole
range (code and data coherently connected via real CALL/JP) and
fully transcribed. Final structure, more detailed than the first
pass:

- `ITEM_RNG` (`$5478`, 15 bytes) -- the already-documented
  pseudo-random generator.
- `ITEM_ANIM_TABLE_1`/`ITEM_ANIM_TABLE_2` (`$5487`/`$5574`, 20 bytes
  each) -- animation-frame tables (index `type*4 + phase 0-3`), a
  tile value with bit 7 = extra flag.
- `ITEM_TABLE_1` (`$549B`, **2** entries of 7 bytes -- the exact
  number wasn't obvious until the init loop was transcribed) and
  `ITEM_TABLE_2` (`$5588`, **8** entries). Real compiled content
  (not zeros): `$20,$10,$01/$02,$01,$00,$00,$01` repeated -- seed
  position `(0x20,0x10)` + a "type" field (1 or 2) + fixed rest.
  These are work buffers, reinitialized every level by `TABLE_INIT`.
- `ITEM_HANDLER_1`/`ITEM_HANDLER_2` (`$54A9`/`$55C0`): the count of
  entries to process (`B`) is read from **`($2BFC)`/`($2BFD`)** --
  offsets **9 and 10** of the level record copied to working RAM.
  **First concrete data point about those still-undeciphered
  offsets**: a strong candidate for "number of type-1 items /
  type-2 items in this level". Pending confirmation when that task
  is tackled.
- `COORD_TO_ADDR_LOCAL` (`$5559`): a third copy of the same
  coordinate→address formula as `COORD_TO_ADDR` (`$545F`) and
  `MAP_COORD_TO_ADDR` (`$8CB6` in `madmix1.asm`) -- that's now 3
  independent copies of the same formula in the game.
- `GHOST_HINT_HANDLER` (`$566A`): handles a 3-entry table at
  `$2C2E` (RAM, outside this file) comparing Pac-Man's position
  against asymmetric margins; triggers `CLEAR_5773_AND_SET` with
  `C=$4D`.
- `CLEAR_5773_AND_SET` (`$56CA`): a shared helper, clears `$5773`'s
  4 entries and optionally stores a new position.
- `ITEM_EXTRA_TABLE` (`$56F5`, 122 bytes up to `$5772`): more
  animation/effect data not yet deciphered field by field
  (recognized structure: blocks of a repeated tile + a 6-7-byte
  tail + `$FF` terminator), transcribed as verified raw data.
- `$5773-$5781`: the already-known RAM work zone (compiles to
  zero).
- `ITEM_TIMER_TICK` (`$5782`): walks `$5773`'s 4 entries.
- `ITEM_EFFECT` (`$57D8`): filters by position and by item type
  (`($2C2D)`), triggers sound/animation via `$8D70` or delegates to
  `GHOST_HINT_HANDLER` for type 3 ("track").
- `TABLE_INIT` (`$5885`): initializes the 3 active tables (`$511C`
  8 entries, `ITEM_TABLE_1` 2 entries, `ITEM_TABLE_2` 8 entries)
  with the seed position (`$2C00`), clears `$5773` and
  `GHOST_HINT_HANDLER`'s 3-entry table (`$2C2E`). Called from
  `LEVEL_LOADER` (`CALL $5885`).

**Errors found and fixed while transcribing** (same category that
had already bitten us before in the main loop): two "redundant"
explicit `JR`s were missing (jumping to the very next instruction,
offset 0) that the real code does have -- one of them shifted
EVERYTHING that came after by +2 bytes, caught immediately by
`--sym`. It also turned out the loop labels (`IH1_LOOP`/`IH2_LOOP`)
must include each iteration's `PUSH BC`, not just the body -- the
real `JP NZ` goes back to `PUSH BC`, not the next instruction. And a
`CALL C,$8440` that was actually `CALL NC,$8440`. **Verified: 0
differences across the full 1164 bytes**, and the whole file
(`0x28ED-0x28F0`, `0x511C-0x545F`, `0x5AD5-0x6500`) now only differs
in the gaps still not transcribed (plus the single stray byte
already documented at `0x6500`, outside the relocated zone).

**Pending**: 3 subroutines called from here still unidentified:
`$5278` (used by both handlers, seems to determine whether the item
is "collectible" -- returns with carry set if not), `$53A2` (used
by `ITEM_TIMER_TICK`) and `$8CEE` (inside `madmix1.asm`, near
`MAP_COORD_TO_ADDR`); and the exact purpose of variable `$6128`.

### DONE: `0x511C-0x545F` fully transcribed, 0 differences -- this is where `$5278` and `$53A2` lived

Tackling what was thought to be "the item position table", Z80Dasm
disassembled the WHOLE range (835 bytes) without desyncing even
once, from `$51FE` to the `RET` at `$545E` (right before
`COORD_TO_ADDR` at `$545F`). It turned out to be much more than a
table:

- `ITEM_TABLE_POS_511C` (`$511C`, 8 entries x 7 bytes): the
  already-documented type table, real compiled content confirmed to
  match the earlier sessions' live sample (seed position
  `0x10`/`0x20,0x10` + final field = item type 0-3).
- An auxiliary 170-byte table (`$5154-$51FD`): the first 32 bytes
  indexed as 16 16-bit words via `((IX+2) AND $0F)*2` (almost every
  entry is a repeated byte); the rest (138 bytes) looks like a
  direction-bit table, not decoded field by field -- transcribed as
  verified data.
- **`R51FE_MAIN` (`$51FE`)**: the routine called from the main loop
  (already documented as `CALL $51FE` in the collision engine) --
  computes a position relative to the camera (`+8,+16`, stored in
  `$2C1F`) and, if `($2BFB)` (**CORRECTED: it's offset 8 of the
  level record, not "offset 11" as an earlier note in this same
  session said -- an arithmetic error, `$2BFB - $2BF3 = 8`; see the
  "Deciphered offsets 8/11/18/19" section below for the full,
  corrected breakdown**) is nonzero, walks that many entries of
  `ITEM_TABLE_POS_511C`, activating each one via `ACTOR_ENGINE` +
  `ITEM_EFFECT`, same as the other two handlers.
- **`HELPER_5278` (`$5278`)**: the helper that was missing from
  `ITEM_HANDLER_1`/`ITEM_HANDLER_2` -- checks whether the candidate
  position is "behind" the camera given the current movement
  direction and computes an approximate direction (`D`), then tries
  the 4 directions (via `HELPER_5414`, which does use
  `COORD_TO_ADDR`/`TILE_TYPE_LOOKUP` to check for a free tile) and
  decides whether the item is reachable.
- **`HELPER_53A2` (`$53A2`)**: turned out to be a **second entry
  point inside `HELPER_5278`** (reached both by falling through
  normally and by a direct `CALL` from `ITEM_TIMER_TICK`) --
  computes distance/direction normalized to the camera with repeated
  `RES 7` masks (clearing the "eaten tile" bit on each subtraction).
- `HELPER_5414` (`$5414`): the 4-direction mini-helper, already
  described.

**One error found**: the label `ITEM_ANIM_TABLE_1` (`$5487`) was
used by mistake in an `LD HL,` that actually references the
170-byte auxiliary table right here (`$517E`, an offset within it)
-- a coincidence that both tables looked interchangeable given the
context, caught immediately by the byte-for-byte diff (2 exact
bytes, the `LD HL` operand's). **Verified: 0 differences across the
full 835 bytes.**

## DONE: `0x5AD5-0x6500` fully transcribed -- `madmix_scr.asm` NO LONGER HAS ANY PENDING `DS` GAP

The last unexplored stretch (2603 bytes, the "tail" of the relocated
block reaching the hard 0x5500-byte limit that `MADMIX0.BIN` copies)
turned out to be, by far, the biggest finding in the whole
`madmix_scr.asm` reconstruction: **it's the game's MAIN MENU
screen, with keyboard/joystick/key-redefinition/demo submenus, plus
the ORIGINAL CREDITS.**

### The game's real credits (plain text, unambiguous)

Text table at `0x5FC2` (format `[length][attribute][text]`, same as
the rest of this zone's text tables):

```text
POGRAMADO BY:
RAPHAEL GOMEZZZ..
GRAPHICOS BY :
ROBERTO P.ACEBES
MUSIC-A BY:
COMILONAS
TOPOSHOW -1988-
```

**CORRECTED** (2026-07-25, after dumping the real bytes byte for
byte instead of trusting an earlier "idealized" reading): the real
text does NOT say "PROGRAMADO"/"GRAFICOS"/"MUSICA" as such, but
literally "POGRAMADO" (missing the first R), "GRAPHICOS" (with PH)
and "MUSIC-A" (with a hyphen) -- transcribed as-is, without
"correcting" the spelling, because these are the real bytes of the
1987 game. The name "RAPHAEL GOMEZ" also has two extra Zs at the end
("GOMEZZZ"), possibly a deliberate fade-out effect or an error never
fixed. There's one more entry in the table, `"MAD$MIX GAME"` (with a
literal `$` instead of a space), but **it's not confirmed that it
actually gets shown on screen** -- `TAIL_CREDITS_DRAW`'s 8 calls to
`TAIL_DECODE` end on the "TOPOSHOW -1988-" line, without reaching
that last entry.

### The main menu (text at `0x5BF9`)

```text
1 TECLADO
2 JOYSTICK
3 REDEFINE TECLAS
4 DEMO
0 JUGAR
```

Four routines (`TI_5C3A`/`TI_5C53`/`TI_5C60`/`TI_5C70`, one per
option reachable with the cursor) self-modify this text's attribute
bytes at runtime (`$5BFA`/`$5C07`, alternating `$F1`/`$91`) to
highlight the current option -- real self-modifying code, not a
guess.

### The key-redefinition menu (option 3, text at `0x5E03`)

```text
PAUSA / FUEGO / ARRIBA / ABAJO / IZQUIERDA / DERECHA
ESPACIO, S.SHIFT, C.SHIFT, ENTER, SHIFT, CTRL, GRAPH, CAPS,
F1-F5, ESCAPE, TAB, STOP, BS, SELECT, HOME, INS, DEL, symbols...
```

The first 6 entries are the redefinable game actions; the rest are
the names of the keys assignable to each one.

### The "demo" (option 4): `TAIL_LEVELCYCLE_MAIN` (`$6045`)

Writes `$2C07` (current level) directly with a value from a 4-entry
table `LEVELCYCLE_TABLE` (`$60D0`, levels 1/2/4/5, pointers inside
`MADMIX1.BIN`) and calls `LEVEL_LOADER`/`TABLE_INIT`/`JT_SLOT9`/
`JT_SLOT6` to draw it -- confirms "demo" is literally showing several
levels in a loop without playing.

### Other findings

- Three more copies of already-known routines: a third
  coordinate→address formula (inside `TAIL_JOY_READ`... no, see
  `HELPER_5414`/`COORD_TO_ADDR`), standard MSX BIOS matrix keyboard
  reading, and a resource "decompression"/drawing engine
  (`TAIL_DECODE`, `$5CD1`) that calls the already-known resource
  manager (`$C4A0`/`$C4EB`, the same one `main.asm`/`madmix1.asm`
  still has pending as "resource manager").
- **Second relocation routine** (`TAIL_RELOCATOR2`, `$64AB`), a
  twin of `MADMIX0.BIN`'s: switches slots with fixed values
  (`$55`/`$50`), copies `0x54AB` bytes from `$8400` to `$1000` and
  runs it -- a strong candidate for "return to menu/hot-restart"
  from inside a game in progress.
- An 811-byte block after `TAIL_LEVELCYCLE_HELPER`
  (`LEVELCYCLE_RESOURCE_TABLE`, `$60FE`): the first 42 bytes are a
  real 14-entry `[id,pointer]` table (indexed by variable `$6128`,
  pointing at `$CDxx`/`$CExx`/`$CFxx` addresses -- inside the
  "resource manager"/bytecode programs `madmix1.asm` still has
  pending to trace). The remaining 768 bytes (from `$6129`) are the
  **candy frame**, RESOLVED in two steps:
  1. First attempt (direct character indices against the `$925B`
     font): gave a frame-like shape but with the lives/score row
     visibly shifted -- a sign the reading wasn't correct.
  2. **The real routine that consumes the block was found**:
     `TAIL_CREDITS_MAIN` (`$6454`), which was ALREADY transcribed
     without its full role having clicked -- it reads each byte,
     runs it through `TAIL_TILE_LOOKUP` (`$6484`, a nibble-swap
     using `MADMIX1.BIN`'s real `LOOKUP_8978` table, 16 bytes at
     `$8978`, the same one already known), and uses the result as a
     **solid fill value** for 8 consecutive bytes via `FILVRM` --
     these aren't free-shape glyphs, they're texture blocks (like
     the candy's stripes). Applying the real transformation
     (768 = 32×24, the full MSX screen grid) the result has a lot
     of structure: one value dominates with 432 repetitions
     (background/center gap) and clear border/stripe clusters show
     up. See `src/recursos/recurso_grafico.html` (includes both
     attempts, with the correct one flagged and the rest kept as a
     record).

  **Conclusion (with the developer, who played the original)**: the
  rendered result is monochrome vertical stripes -- thicker right
  where the candies would fall, which suggests the mechanism/
  transformation IS correctly understood -- but not a "pretty"
  image. Chasing the color table as a next step was ruled out: in
  SCREEN 2 color only tints these same stripes, it doesn't shape
  them. Most likely conclusion (at the time): **this block is a
  background texture/fill (shading behind the window), NOT the candy
  drawing itself** -- the detailed candy graphic (with a recognizable
  shape, 16×16-tile style like the maze's) was still, at the time,
  the pending gap in `madmix1.asm`. Investigation closed here at
  that point.

  **IMPORTANT CORRECTION (later session, with the candy frame
  already located as `RLE_TABLE_D6B6`)**: this conclusion was wrong
  on the exact point it dismissed -- **this 768-byte block IS the
  application of the candy frame's real color**, not a separate
  background texture. Confirmed by applying `TAIL_TILE_LOOKUP`'s
  real transformation to the real 768 bytes of
  `LEVELCYCLE_RESOURCE_TABLE` (extracted from the original
  `MADMIX.SCR`) and comparing the result against a real VRAM dump:
  it **matches EXACTLY, byte for byte**, the VRAM color table
  (`$2000`) for the whole screen -- row 0 (the frame's top border)
  gives `$E1,$E1,$E1,$F1,$F1,$E1` (gray/black, white/black -- the
  rounded corners) followed by `$6E` repeated (dark red/gray -- the
  straight stripe stretch) and the symmetric mirror at the end,
  computed with no manual adjustment at all. `TAIL_CREDITS_MAIN`
  (`$6454`) is the real routine: it reads the 768 bytes from
  `$6129`, translates them with `TAIL_TILE_LOOKUP` (combines two
  `DIRBITS_TABLE` lookups, high and low nibble), and fills the whole
  VRAM color table (`$2000`, 768 cells × 8 bytes) via `FILVRM` --
  exactly the same "RLE for the shape, separate color table for the
  tint" pattern already known from other SCREEN 2 graphics. **This
  fully resolves where the candy frame's real color (red/white/gray)
  gets applied** -- the shape comes from `RLE_TABLE_D6B6`
  (`madmix1.asm`) and the color from this 768-byte block
  (`madmix_scr.asm`, via `TAIL_CREDITS_MAIN`/`TAIL_TILE_LOOKUP`).
  The earlier conclusion's mistake was evaluating the image by
  rendering it as if the bytes were a pattern (black and white)
  instead of recognizing them as color attribute bytes (high nibble
  = ink, low nibble = paper).

### Method and errors found

Fully disassembled with Z80Dasm without ever desyncing at any real
code point (only the text/table zones, as expected). A very
laborious transcription due to the number of **dual entry points
within the same routine** (code reuse: a `CALL`/`JR` jumps into the
middle of another routine to reuse its tail with a different
parameter, a pattern already seen in `MADMIX0.BIN` but much more
frequent here) -- most of this session's errors were mislabeled
addresses from assuming a jump's "obvious" target instead of
verifying the real address byte for byte, all caught by `--sym`/diff
and fixed one by one. **Verified: 0 differences across the full 2603
bytes.**

**`madmix_scr.asm` is now 100% complete byte for byte**, except for
2 bytes already documented in earlier sessions and unrelated to this
task (the 3-byte gap at `0x28ED-0x28F0` and the stray byte at
`0x6500`, outside the zone relocated by `MADMIX0.BIN`).

## SECOND BIG FINDING in `madmix_scr.asm`'s gaps: `0x2BF0-0x335C` is the MAIN GAME LOOP (movement, collision, items, trapdoors)

Continuing the gap review, `0x2BF0-0x335C` (~1900 bytes, only 4%
zeros -- clearly dense, not filler) turned out to be disassemblable
as real, coherent code from `0x2CA0` to the end of the stretch
(`0x335C`). It's, in all likelihood, **the central per-frame game-
update routine** -- the code that ties together literally almost
everything we've spent months reconstructing:

- It calls `MAP_COORD_TO_ADDR` (`0x8CB6`), `TILE_TYPE_LOOKUP`
  (`0x8CDA`), `REDRAW_STRIP` (`0x8D1B`), `JT_SLOT6` (`0x8E3C`,
  collision), `JT_SLOT7` (`0x8D70`), `JT_SLOT8` (`0x89AD`, scroll
  trigger) and `ACTOR_ENGINE` (`0x8440`) -- practically the whole
  index of the main engine's jump table, all from a single place.
- There's a clear **direction-based dispatch**: it reads/computes an
  input value (0-15, `AND $0F`), uses it as an index into a pointer
  table at `$2E3C` (16 entries of 2 bytes) and jumps with `JP (IX)`
  -- a jump table for "what to do based on movement direction",
  possibly combined with what tile type is ahead (the conditional
  jumps check `TILE_TYPE_LOOKUP` before deciding).
- It calls, conditioned on flags, the TWO special-item handlers just
  found and documented above (`CALL Z,$51FE` / `CALL Z,$54A9` /
  `CALL Z,$55C0`) and
  `ACTOR_ENGINE` right after (`CALL Z,$8440`) -- confirms this
  central loop is the one that DECIDES when to activate an item and
  when to activate an actor, not the other way around.
- The final stretch (`~0x32D6-0x335C`, right before the hard limit
  with the level-data zone) is a **trapdoor animation** routine: it
  explicitly writes tile indices `0x43,0x44,0x45,0x47,0x48,0x49,
  0x4A,0x4B` (which are EXACTLY the trapdoors 76-79/71-74 already
  catalogued in `graficos.html` as "A<->B transition, falls/flips
  over") into the 4 positions of a 2×2 quadrant, calling
  `REDRAW_STRIP` once per tile -- the real "the trapdoor flips over"
  mechanism we only knew by name until now.
- Along the way, quite a few `$2Cxx` variables that used to be loose
  are now better pinned down: `$2C0E` works as a counter that gets
  decremented and compared against `$3C` (the same wildcard tile
  from the level record, offset 12 -- reused here as a limit),
  `$2C0D`/`$2C2D` as status flags, `$2C04`/`$2C24` as HUD digit
  selectors (already seen in the level loader and in `INIT`).

**Not transcribed yet** -- it's a large, dense block (~1900 bytes)
that deserves its own careful transcription session rather than
being rushed. There are also subroutines called from here still
unidentified: `$2E64`, `$5782` (already seen from the other item
subsystem) and the exact purpose of the 16-pointer table at `$2E3C`.

**Important implication**: between this main loop and the
special-item subsystem documented right above, the TWO code gaps in
`madmix_scr.asm` (`0x2BF0-0x335C` and `0x5478-0x5904`) are now MUCH
better understood than they seemed at the start of the session --
neither is a generic mystery anymore, they're central, nameable
pieces of the game engine.

### DONE: `0x2BF0-0x335C` fully transcribed into `madmix_scr.asm`, 0 differences byte for byte

Full transcription: `MAINLOOP_TABLES` (0x2BF0-0x2CA0, via INCBIN),
`MAIN_LOOP` (0x2CA0-0x2E3C), `ML_DISPATCH_TABLE` (0x2E3C-0x2E64),
`CHECK_TILE_DELTA` (0x2E64-0x2E9F), `DRAW_TILE_HELPER`
(0x2E9F-0x2EB7), and the 20 handlers + `TRAPDOOR_FLIP_TABLE`
(0x2EB7-0x335C), with `HANDLER_XXXX` labels by real address.
**Verified: 0 differences across the full 1724 bytes** against the
original `MADMIX.SCR`.

Two of my own errors found and fixed while transcribing (noted
because they're the kind of mistake that can repeat):

1. **The dispatch table has 20 entries, not 16** -- a "4-bit
   nibble" (0-15) was assumed without checking against the next
   routine's real address (`CHECK_TILE_DELTA`, which should land at
   `0x2E64`); when it didn't line up (it landed at `0x2E5C`, exactly
   16 entries × 2 bytes too early) the error was caught. The 4
   missing entries (17-19, plus one repeated) turn out to be exactly
   the 3 code blocks that looked "unconnected" (drawing the trapdoor
   variants) -- resolves that open question along the way.
2. **A misplaced loop label**: `JR Z,$2D9C` in the original goes
   back to repeat the WHOLE table-index CALCULATION (starting at
   `LD HL,$2C14`), not just re-reading `(HL)` -- the label had been
   placed 17 bytes too late, on the wrong instruction. Caught by the
   single byte that didn't line up in the first verification pass.

Method: verify by RANGES with `--sym` (each label must land at its
exact real address) before trusting the full byte-diff -- that way
structural errors (extra/missing bytes) are located almost
immediately, instead of having to trace a generic diff.

## LIVE MEMORY DUMP (openMSX) -- calls the PHASE/DEPHASE premise into question

The developer captured live memory with the game running in openMSX
(the debugger's Tcl console):

```tcl
save_debuggable memory ram.bin 0 65536
save_debuggable VRAM vram.bin 0 16384
```

Files at `src/dump_openmsx/ram.bin` (64KB, the Z80's address space
as seen by the CPU at the moment of capture) and
`src/dump_openmsx/vram.bin` (16KB, the VDP's VRAM, a separate space
not directly accessible by the Z80). Commands used saved in
`src/capturar_openmsx.md`.

### Alignment check: the dump is reliable

Before drawing conclusions, the dump was checked against what was
already confirmed against the static `.BIN`:

- `0x8931` (FILVRM) and `0x8440` (JT_SLOT2) match the original
  `.BIN` byte for byte -- page 2 (0x8000-0xBFFF) of the dump IS the
  static image of `MADMIX1.BIN`, as expected.

### IMPORTANT FINDING: the engine runs from STATIC addresses, not from the relocated copy

3 routines already confirmed by their STATIC address (within the
range `madmix1.asm` had been treating as the "relocated block",
0x8800-0xDD00) were checked against those same STATIC addresses in
the live dump:

- `0x8988` (`ADDR_FROM_DC00`): matches byte for byte.
- `0x899B` (`RESET_8437`): matches byte for byte.
- `0x8961` (`LOOKUP_8978`): matches byte for byte.

In other words: this code is REALLY RUNNING from its original static
position, exactly as it is in the file -- no relocation is needed
for it to work.

By contrast, address `0x1000` (where `madmix1.asm` had been assuming
the relocated copy lives and runs, including `LOOKUP_8978`'s virtual
address -- checked at `0x1161`, which in the dump comes out ALL
ZEROS, not matching) contains code that's COMPLETELY DIFFERENT from
expected: VDP/screen initialization (`LD HL,$1800` -- the standard
default SCREEN2 name-table address, plus a loop filling VRAM port by
port). It doesn't resemble our `LOOKUP_8978` or the rest of the
reconstructed block at all.

**Working hypothesis (replaces the one from the original analysis
session)**: `MADMIX0.BIN`'s relocation (0x8800→0x1000,
`CALL 0x1000`) is probably a **one-shot boot operation** (maybe
initial VDP/screen setup, run once because at THAT point in booting
some code needs to run from low memory for some reason -- e.g. while
the disk ROM occupies other pages), NOT the permanent installation
of the whole game engine as the "persists for the whole game, not
just at boot" note said. The real engine (ISR, actors, scroll, etc.)
lives and runs permanently at its STATIC addresses (0x8400 onward),
with no relocation.

**FIXED in `madmix1.asm`**: `PHASE $1000`/`DEPHASE` was removed
entirely. The whole file now uses real STATIC addresses start to
finish (a single `ORG $8400`, no relocation at all). The hard fact
that `MADMIX0.BIN` copies 0x5500 bytes from 0x8800 to 0x1000 is
still noted (it comes straight from the loader itself), but it's NO
LONGER interpreted as "virtual addressing is needed for the engine
to work" -- it's interpreted as a one-shot boot operation (probably
VDP/screen init, given what's seen at `0x1000` in the dump) that
doesn't affect how the rest of the code is organized. Recompiled and
verified: ALL confirmed addresses (`ISR` 0x882A, `FILVRM` 0x8931,
`LDIRVM` 0x8942, `SETVRAM` 0x8954, `LOOKUP_8978` 0x8961,
`ADDR_FROM_DC00` 0x8988, `RESET_8437` 0x899B, `WAIT_VBLANK` 0x89A0,
`MAP_COORD_TO_ADDR` 0x8CB6, `TILE_TYPE_LOOKUP` 0x8CDA,
`REDRAW_STRIP` 0x8D1B, `TILE_TYPES` 0x8EC4, `INIT` 0x8F24) still
land exactly right, same file size (22938 bytes), 0 errors.

**Good side effect**: while re-verifying addresses with this change,
it turned out `MAP_COORD_TO_ADDR` was landing at `0x8CB8`, not
`0x8CB6` -- because of a made-up `PLAYER_POS` variable (never
confirmed against the binary) placed right before it, shifting
everything that came after by 2 bytes. `PLAYER_POS` was removed from
there; if that variable really exists in the original, it needs to
be located by disassembly before being placed again.

### Other data from the dump, no clear conclusion yet

- **`$8437`** (actor counter) live = `06` (6 active actors at the
  moment of capture) -- consistent with the "actor counter"
  hypothesis.
- **`$8438`** (graphics cursor, earlier hypothesis) live = `$06B0`
  (16 bits, not `$0500` -- normal, it will have advanced after
  creating several actors).
- **The actor array at `0x92E3`** (12-byte stride) has real data
  that differs per actor, e.g. actor 0 = `FB A4 10 E1 0C 00 05 11
  2F 84 00 00` -- confirms the 12-byte structure is real, though
  it's striking that it contains the sequence `11 2F 84` (which are
  literally the opcode bytes for `LD DE,$842F`, a real instruction
  that appears in the code at `0x870B`) -- not yet explained whether
  it's a coincidence or the actor record genuinely includes a
  fragment of code.
- `$0500` (RAM) was rendered as if it were tile graphics (16x16
  raster format) hoping to find the character sprites there -- **no
  recognizable shape came out** (see `scratch_img/ram_0500.png`, no
  longer included in the repo). Since we now know `$8438` changes
  dynamically, trying the address `$8438` points to LIVE (`$06B0`
  in this capture) would be the logical next step if this thread is
  picked back up, instead of the initial `$0500` (which is only the
  boot-time value before any actor is created).
- Pending: analyze `vram.bin` (16KB) -- nothing in the real VRAM has
  been looked at yet, which is where hardware sprite patterns would
  live if they exist.

## VRAM ANALYSIS (vram.bin) -- CONFIRMS the characters are rendered in software

Reconstructing the full screen (pattern table `0x0000`, name table
`0x1800`, color table `0x2000`, standard SCREEN2 format) from
`vram.bin`, and comparing against `src/dump_openmsx/ejemplo.png` (a
reference capture from the internet the developer provided to check
the correct composition):

- **The hardware sprite table is empty/unused**: the attribute table
  (`0x1B00`) has all 32 sprites parked at the same Y=209/X=0 with
  sequential filler pattern numbers, and the sprite pattern table
  (`0x3800`) is filled with a constant byte (`0x01`) -- there's no
  real graphics there. Reinforces what was already suspected: the
  characters do NOT use hardware sprites.
- **The name table (`0x1800`) is pure identity**: the 768 bytes are
  exactly `00,01,02...FF` repeated 3 times (one per SCREEN2 "third"
  of the screen). This confirms the game NEVER reuses a pattern by
  index -- instead, every screen cell has its OWN dedicated 8x8 byte
  in the pattern table, and the engine draws by writing directly
  there (matches exactly the `JT_SLOT2` "actor engine" hypothesis:
  software rendering with bit shifting, not sprites).
- **The initial reconstruction (24 full rows) came out with a
  broken composition** (the developer noticed it: the lives/score
  HUD showed up shifted, with 2 tile rows and the bottom candy
  frame "left over" after it). The hypothesis of vertical scroll via
  row rotation was tried (without real success, see below).
- **Real cause found**: analyzing the dominant color of each of the
  24 screen rows, rows **21, 22 and 23 are entirely 0x00** (black/
  unused), and rows **16-20 contain leftover content** (looks like a
  maze and an "extra" candy that don't belong to the current
  composition). The real, full composition is in rows **0-15** (128
  of the 192 pixels tall): candy on top, maze, candy on the bottom,
  and the HUD strip (lives/score) right below, exactly as in
  `ejemplo.png`. Cropping to those 16 rows, the reconstruction
  matches the reference perfectly.

### CORRECTED: there was no need to crop rows -- it was a localized "torn frame"

The first "fix" attempt (cropping to rows 0-15) was wrong: it changes
the image's proportions and isn't the right thing to do anyway. The
developer provided `src/dump_openmsx/ejemplo.png` (a reference
capture from the internet, confirmed to be the EXACT SAME screen --
the start of phase 1, only the ghost's position and the lives count
differ). Comparing structurally (non-black pixel count per 8px
strip, to avoid depending on whether my approximate color palette
is exact) the reference against the VRAM's 24 rows:

- VRAM rows 0-11 and 16-19 match the reference EXACTLY, at the same
  position -- that part of the dump is perfectly consistent.
- VRAM rows 12-13 (bottom candy) have the EXACT profile of what
  should be at rows 20-21 in the reference -- the content is real
  but it's in the wrong position within VRAM at the moment of
  capture.
- Rows 14-15 (HUD, low count = small icons) don't fit cleanly
  anywhere; rows 21-23 (where the real HUD should be) are zero.

**Explanation confirmed by the developer**: at the moment of
capture Pac-Man was NOT moving and the scroll was stopped -- ONLY
the ghost was in motion. Since characters are drawn in software
(`JT_SLOT2`'s engine, see above, writing directly into the pattern
table), it's most likely the capture caught the engine HALFWAY
through redrawing the ghost, right in the row band where it was at
that instant -- hence why only that specific strip (12-15, and
therefore also its counterpart at 20-23) comes out inconsistent,
while the rest of the screen (static, nothing animating) matches the
reference perfectly. It isn't an addressing bug or a reconstruction
flaw -- it's a real captured frame, partially mid-write.

**RESOLVED with a second capture**: the developer repeated the
capture (`ram2.bin`/`vram2.bin`, same files and sizes as the first)
and this time the reconstruction comes out clean and matches
`ejemplo.png`: full frame on all 4 sides, Pac-Man with the correct
face, HUD with 3 lives + score right below the frame. `ram2.bin` was
re-checked against `ADDR_FROM_DC00` (0x8988) and `RESET_8437`
(0x899B) -- they still match exactly. Final image at
`src/dump_openmsx/screen_reconstructed.png` (uncropped, full
256x192).

### CORRECTION: the problem was still there -- it wasn't rotation nor a "torn frame"

The above was too optimistic a conclusion (the developer caught it,
looking at the image more carefully than I had: at large size you
can clearly see a SECOND maze stretch + repeated candy frame after
the HUD, which shouldn't be there). The capture was repeated a third
time (`ram3.bin`/`vram3.bin`) with a breakpoint deliberately set on
the confirmed ISR (`0x882A`, via `debug breakpoint set 0x882A` in
openMSX's console) to guarantee the capture always lands at the
exact same instant in the draw cycle, instead of a manually-timed
pause with random timing. **The result is pixel-for-pixel IDENTICAL
to the second capture** -- which rules out fairly confidently that
it's a "frame mid-write" (with exact sync to the same point in the
cycle, a timing issue would have changed or disappeared).

The real VDP registers were checked at that instant: `R2=6` (name
table → `0x1800`), `R3=255` (color table → `0x2000`), `R4=3`
(pattern table → `0x0000`), `R5=54` (sprite attrs → `0x1B00`),
`R6=7` (sprite patterns → `0x3800`), `R10=0`. These are EXACTLY the
standard default SCREEN 2 addresses already being used -- rules out
the error being a misplaced table.

**"Masked bit" hypothesis tried and RULED OUT**: the pattern of
affected rows (12-15 and 20-23, i.e. the "upper" half of each 8-row
third, where the name byte has bit 7 set) suggested the VDP hardware
might be forcing that bit to 0 when computing the address within
each third (a "masking" mechanism documented for Graphics II, see
threads on smspower.org/meka). Forcing that bit to 0 in the
calculation was tried -- the result was WORSE (duplicates also
showed up in rows 0-7, which had been fine before), so this specific
hypothesis is ruled out.

**Current status: unresolved.** The VDP registers are standard, the
breakpoint-based sync rules out timing, and the bit-masking
hypothesis doesn't fit. The defect is consistent and reproducible
across 3 separate captures, so it's real and not noise -- but the
cause hasn't been found yet. Continuing to try to fix it by
trial-and-error formulas isn't recommended; if this is picked back
up, the most productive path would be (a) review a real emulator's
source code (openMSX, blueMSX) to see its exact addressing formula
in Graphics 2 mode, instead of scattered documentation, or (b)
accept that pixel-perfect visual reconstruction of the screen is
secondary -- the important part is already confirmed solidly and
independently of this unresolved detail (no hardware sprites,
identity name table, software character rendering).

## Actor graphics extracted DIRECTLY from VRAM (ground truth)

Since we already know how to correctly decode the pattern table (at
least in the screen's "good" rows, see the VRAM-dump section), two
real confirmed graphics were cropped directly from
`src/dump_openmsx/screen_reconstructed.png`:

- **`src/dump_openmsx/actor_comecocos_maze.png`**: Pac-Man's face
  exactly as it really looks in the maze. Important note: it's NOT
  aligned to the 8x8 grid -- it occupies a position with a sub-pixel
  offset, consistent with the fine-movement software rendering
  already seen in `JT_SLOT2`. This confirms a clean 16x16 crop isn't
  always possible directly from the framebuffer; it may require
  capturing at a tile-aligned instant, or accepting the offset.
- **`src/dump_openmsx/border_candy_corner_TL.png`** (renamed, it
  used to be mistakenly called `actor_ghost_corner_TL.png`): the
  developer (who knows the game) confirms this is NOT a ghost. It's
  the white, rounded cap where the HORIZONTAL candy-wrapper end (top)
  and the VERTICAL one (side) meet at the corner -- both ends are
  white and rounded by design, and when they overlap at the corner
  they look (to my eye, mistakenly) like a ghost's silhouette. All 4
  corners have the same motif, which is purely decorative for the
  candy frame, unrelated to the game's ghosts. Still pending: finding
  a real image of a ghost.

  **CLOSED/OBSOLETE** (later session): the goal of this item was to
  get visual "ground truth" to identify the character sprites by
  comparison. That was already achieved through a much more direct
  and reliable path -- the developer (the original player) visually
  identified all 64 sprites in `src/recursos/ptrtable_sprites.html`,
  including the ghost ones (`SPR27_FANTASMA_DER_1` through
  `SPR36_FANTASMA_VULN_ABAJO_2`, `SPR62_FANTASMA_MUERTO`), verified
  with 0 differences byte for byte. There's no longer a need to
  chase a VRAM capture with a real ghost in it -- this task's purpose
  has been fulfilled another way.

## Game characters (per the developer, who played the original)

Pac-Man, ghosts, hippo, tank, plane/ship, ladybug (replenished
balls), steamroller (crushed them), trapdoors (blocked the ghosts,
could be flipped by pushing from one
side to invert the block and pass over). Candidate sprites located
at `0x9D40-0xA3E0` but WITHOUT each one assigned to its character —
pending live tracing or more visual analysis.

## Status of the madmix1.asm project

Compiles with SjASMPlus, ~22.9KB of output (the original is 22952
file bytes = 22945 of code). The relocation trick (`PHASE $1000`/
`DEPHASE`) is ALREADY implemented: the `0x8800-0xDD00` block is
assembled inside `PHASE $1000`, and every CONFIRMED routine/data
(ISR, VDP API, WAIT_VBLANK, MAP_COORD_TO_ADDR, TILE_TYPE_LOOKUP,
REDRAW_STRIP, TILE_TYPES, INIT, TILE_GFX, MAZE_DATA) lands at its
verified real address, with `DS` gaps (zero filler, marked and
commented) in between for what isn't reconstructed yet. The jump
table (0x8400-0x842E) was verified byte for byte against the
original `.BIN` and deliberately uses literal static addresses (not
symbols), because of how it interacts with `PHASE`. `INIT` (0x8F24)
is transcribed byte for byte up to offset `0x8F71` (see its own
section).

**NOTE (outdated above, corrected here)**: `madmix1.asm` no
longer uses `PHASE`/`DEPHASE` (ruled out after the live RAM dump,
see its own section below) -- it runs with a static `ORG` start to
finish.

## FIXED: a real 7-byte bug in `madmix1.asm`'s header (carried since the start, never caught)

While comparing addresses with v2.0's CAS/ROM (see below), it turned
out `madmix1.asm` had the SAME problem already found and fixed in
`madmix0.asm` and `madmix_scr.asm`: `ORG $8400` was placing the MSX
header (`DB $FE` + 3 `DW`, 7 bytes) so it occupied REAL address
space, when those 7 bytes are file metadata that the real `BLOAD`
consumes and never ends up in memory. This shifted `START`/`JT_INIT`
by +7 relative to their real address (`--sym` showed
`START: 0x8407` instead of the real `0x8400`), AND also made the
first `DS` gap after the jump table (documented as "`$842E-$8430`,
2 bytes") compute its size wrong: the real gap, verified against the
original `.BIN`, is **`$8427-$8430`, 9 bytes** (all zeros in both
cases, so the content of those bytes didn't change anything
playable, but the compiled file ended up **7 bytes short at the
end** -- 22938 instead of the real 22945 -- and the last bytes came
out `00 00...00` instead of the real `...FF FF FF FF CD`).

**Why it wasn't caught earlier**: the jump table uses literal (not
symbolic) addresses in its `JP`s, so the compiled BYTES for that
zone stayed correct despite the internal addressing error. And by an
arithmetic coincidence (`DS destination-$`), the `$8430-$` gap
(together with `FRAME_FLAG` and the second `DS $8440-$`) "absorbed"
the +7 shift right at that point, so ALL later labels
(`FRAME_FLAG`, `ACTOR_ENGINE`, `TILE_TYPES`, `INIT`...) already
landed at their correct real address -- which is why later
sections' checks (960 bytes of `JT_SLOT2`, etc.) always came back
"0 differences" and the bug went unnoticed for several sessions.

**Fix**: change `ORG $8400` to `ORG $83F9` (7 bytes earlier), so the
header occupies `$83F9-$83FF` and `START` lands exactly at `$8400`.
Verified: `START: EQU 0x8400`, `JT_INIT: EQU 0x8403` (previously
`0x8407`/`0x840A`), correct compiled size (22945 bytes, same as the
original with no header), **0 differences across `0x8400-0x8440`**
(previously had the mis-sized gap), and the already-verified
sections (`JT_SLOT2`/`ACTOR_ENGINE` 960 bytes, `TILE_TYPES` 96
bytes) stay at 0 differences after the change -- the fix didn't
break anything that already worked.

What's ALREADY done: header, jump table (100% verified), ISR with
basic housekeeping, full VDP API (SETVRAM/LDIRVM/FILVRM), scroll
routine skeletons, complete and corrected tile-type table, `INIT`
partially transcribed byte for byte, complete tile graphics
(`data/tile_gfx.bin`), candidate maze data (`data/maze_data.bin`),
memory relocation with `PHASE`/`DEPHASE`.

What's MISSING (in order of size impact):

1. Candy frame (~8KB of graphics data, `0x9600-0xB700`)
2. Character zone (~1.7KB, `0x9D40-0xA3E0`)
3. Resource-header interpreter + the rest of `0xC900-0xD000`
4. The rest of `0xD500-0xDDA0`, mostly unexplored (but see the
   `$5B56` finding falling inside `maze_data.bin` -- review before
   assuming `0xD000-0xD500` is data only)
5. Filling in real logic for every routine marked `; TODO`
   (including continuing `INIT` from `0x8F74`, and the unidentified
   jump-table functions: slots 2,3,5,6,7,8,9)
6. Resolving the static/virtual mixing mystery in `INIT`
   (`CALL $881B` vs `CALL $5D0A`/`$6429`/`$5B56`) with live tracing
   (emulator + debugger) -- static analysis has no more to give at
   this specific point.

## MILESTONE: `0xC4A0-0xD000` fully transcribed -- it's the PSG's SOUND/MUSIC DRIVER, not a generic "resource manager"

One of `madmix1.asm`'s pending `DS` gaps was filled in (the most
tractable of the four, since it has known entry points from `INIT`).
Fully disassembled with `Z80Dasm.exe -begin 0 -offset 0xC4A0` over
an exact slice of the original `.BIN` (`fileOffset = addr - 0x8400 +
7`), transcribed instruction by instruction (generated with a
PowerShell script that parses the disassembler's output and only
labels addresses that are real `JR`/`JP`/`CALL`/`DJNZ` targets
within the block itself, to avoid inventing extra names), and
**verified 0 differences byte for byte** by compiling the block in
isolation with its own `ORG $C4A0` and comparing against the real
2912 bytes extracted directly from the `.BIN` (avoids the issue that
the rest of `madmix1.asm` still doesn't have real addresses from
`TILE_GFX` onward, see the note below).

**Real identification**: it isn't a generic "resource manager" -- it's
the **PSG sound/music driver** (AY-3-8910, I/O ports `$A0`=register
/ `$A1`=data). Matches the real credit "MUSIC-A BY: COMILONAS"
already found in the credits screen (`madmix_scr.asm`,
`TAIL_CREDITS_TEXT` section; real text with a hyphen, not "MUSICA",
see the credits section above).

- `LOAD_RESOURCE_SLOT_ALLOC` (`0xC4A0`, confirmed, it was already
  called that in the `asm`): finds a free slot among 4 channel
  "slots" of 46 bytes (`$2E`) in a table at `0xC9C9`, initializes it
  to zero and saves the DE pointer (the sound script) twice.
- `RM_C4CC`: an equivalent internal helper but with an EXPLICIT
  index in A (doesn't search for a slot) -- forces slot A to
  pointer DE.
- `RM_C4F9` (main player loop, walks 3 slots): for each active slot,
  if it's not "waiting" (tick counter), it reads a command byte
  from the script pointer. Bytes `>= 0x80` are commands from a
  15-entry jump table (`RM_TABLE_C99E`, at `0xC99E-0x9BB`): change
  note/instrument, tie volume to a "companion" channel, enable/
  disable a sound effect, end/repeat the script, set a noise mask,
  etc. -- without breaking down each of the 15 commands note by
  note (out of scope for this binary-preservation project, doesn't
  change the binary's result). Bytes `< 0x80` are note durations,
  indexed into a 96-word delay table (`RM_TABLE_C8DE`, at
  `0xC8DE-0x99D`).
- `RM_C8C9`: each "tick" flushes the PSG's 11 registers to ports
  `$A0`/`$A1` (loop `D=$0B`) -- the real exit point to the sound
  chip.
- The 3 script pointers `INIT` installs with
  `LOAD_RESOURCE_SLOT_ALLOC` (`$CDCB`/`$CDFF`/`$CE0C`, indices
  0/1/2) fall INSIDE this driver's own data block -- confirms
  they're 3 real sound resources (music + 2 effects, or similar),
  not pointers to external data still to be located.
- `LOAD_RESOURCE_SLOT_EMPTY` is at `0xCF8B` -- the address already
  suspected before disassembling this block, now **confirmed**
  (`--sym` + byte-diff against `INIT`'s 4 real `CALL $CF8B`s; a
  byte search across the whole `.BIN` also found 8 occurrences
  total, see above). An early attempt in this session mistakenly
  shifted it to `0xCF8E` (an extraction error on our end: the 3
  bytes `LD DE,$0000` right before the `XOR A` were misclassified as
  data instead of code) -- caught and fixed after seeing 14
  unexpected differences in `INIT`'s `CALL`s during final
  verification. Calls `RM_C4CC` 3 times with `A=0,1,2`, always
  setting `DE=$0000` right before each call (all 3 are symmetric).
- The rest of the ~1700 data bytes (duration table, jump table,
  channel state zeroed in the original `.BIN`, instrument/note
  tables from `0xCA53` onward, the 3 sound scripts and a final table
  at `0xCFA4-0xCFFF` that looks like a percussion envelope) are
  transcribed as raw bytes (`DB`), verified byte for byte, without
  trying to decode each note -- same as was done with `TILE_TYPES`
  at the time.

**Important note on absolute addresses**: the earlier large gap
(`0x8F74-0xB940`, candy frame + character sprites, ~11KB) is STILL
not reconstructed and is **not** filled with `DS` (deliberately, see
the comment in the `.asm` itself) because no address in between is
confirmed yet. This means `TILE_GFX` and EVERYTHING that comes after
it in today's assembled file (including this newly-transcribed
sound driver) land at a physical address LOWER than their real one
until that gap is filled -- it's the same limitation already
documented in "Status of the madmix1.asm project". That's why this
block's verification was done in ISOLATION (compiling just these
2912 bytes with their own `ORG $C4A0`) instead of comparing the
whole `.BIN` -- the content is 100% byte-exact, only its position
within today's assembled `madmix1.asm` isn't yet.

## MILESTONE: the 7 small unidentified code gaps (`JT_SLOT5/6/7/8/9`, 0x8431-0x8EC4) fully transcribed

The 7 remaining SMALLEST `DS` gaps in `madmix1.asm` were filled in
(the large graphics gap, 0x8F74-0xB940, is still pending). Same
method as the sound driver: disassembled per block with
`Z80Dasm.exe`, transcribed with an automatic conversion script
(labels only on addresses that are real `JR`/`JP`/`CALL`/`DJNZ`
targets), and verified byte for byte by compiling each block in
isolation with its real `ORG` (same address-shift issue as the
sound driver, see the corresponding note). **0 differences across
the ~1,531 real bytes** (the 15-byte gap at `0x8431-0x8440` didn't
count as code: it's a RAM variable zone, confirmed zero in the
original `.BIN`).

- **`0x8431-0x8440` (15 bytes)**: confirmed all zeros -- a RAM
  variable zone ($8437/$843A/$843E/$843F, already used in
  `ACTOR_ENGINE`), not file padding.
- **`0x8800-0x8931` (305 bytes)**: contained three things.
  - `INSTALL_ISR` (`JT_SLOT5`, `$881B`, identified): installs the
    interrupt vector. The made-up stub that used to exist elsewhere
    in the file (with an initial `DI`) was wrong --
    the real one does NOT start with `DI` -- and it's been removed.
  - `ISR` (`0x882A`): had **3 real bugs** in the previous version,
    found by byte diffing: (1) a symmetric `PUSH AF`/`POP AF` saving
    the shadow `AF` right before/after the `PUSH`/`POP HL,DE,BC,IX,
    IY` was missing; (2) a whole block reading VDP status
    (`IN A,($99)` + `LD A,($10E4)` + 2x `OUT`) right before
    restoring `AF` and exiting was missing; (3) the final
    instruction is `RET`, NOT `RETI` as had been thought. Along the
    way it was also **confirmed** that `CALL $60DC` is a real static
    address (not an old note assuming relocation, as had been
    doubted): the ISR really does call there every VBLANK.
  - `ISR_HOUSEKEEPING` (`0x8860`): the previous stub was basically a
    `RET NZ` with a TODO; the real body always calls a "hook"
    (`$8889`, see below) and, if `FRAME_FLAG` confirms a frame has
    passed, also calls `$86BB` (`JTS2_RESUME`, already transcribed),
    `$899B` (`RESET_8437`) and a new routine `$8CFF` (inside the
    next gap). Also includes `$8889` (a 1-byte `RET`, confirmed --
    looks like a disabled dev hook that ignores A's value) and
    `$8891`, a large VDP refresh routine (uses `LOOKUP_8978`/
    `FILVRM`/`SETVRAM` over several VRAM zones) not fully
    identified.
- **`0x89AD-0x8CB6` (777 bytes)**: `JT_SLOT8` (`SCROLL_DISPATCH`,
  `$89AD`) and `JT_SLOT9` (`$8C34`) are the **camera's software
  scroll**: `SCROLL_DISPATCH` picks between `SCROLL_UP` (nibble
  with `RLD`), `SCROLL_DOWN` (nibble with `RRD`) and `SCROLL_LR`
  (vertical/horizontal with `LDI`) based on the camera position's
  low bits (`$2C02`); all three use `TILE_ADDR_CALC` (`$8BC9`, a
  variant of `MAP_COORD_TO_ADDR` that also writes an attribute bit
  into a table at `$8EC7`). `JT_SLOT9` redraws 4 vertical strips
  and, if `($2C27)` (probable LIVES counter) is nonzero, draws B
  icons via a NEGATED variant of `LDIRVM` reading sprites from
  `$92C3` (very close to `$92E3`, the already-confirmed actor
  table).
- **`0x8CDA-0x8EC4` (490 bytes)**: the previous `TILE_TYPE_LOOKUP`
  and `REDRAW_STRIP` stubs didn't match the real code
  (`TILE_TYPE_LOOKUP` uses base `$8EC7`, not `$8EC4`, with an extra
  `AND $1F`; `REDRAW_STRIP` doesn't use a "SCREEN_SHADOW" as its
  destination, it uses `$DE04` computed from `$2C02`). Also found:
  - A **deferred-redraw queue** (`QUEUE_PUSH`/`QUEUE_INIT_CHECK`/
    `QUEUE_POP_DISPATCH`): `QUEUE_PUSH` (its caller not yet located)
    pushes `(C,B,A)` requests onto a RAM circular buffer
    (`$8D61-$8D6F`, `$FF`=empty); `QUEUE_INIT_CHECK` is the real
    routine behind `ISR_HOUSEKEEPING`'s mysterious `CALL $8CFF`, and
    it drains the queue calling `REDRAW_STRIP` for each entry.
  - `JT_SLOT7` (`SCORE_DRAW`, `$8D70`): draws the score marker.
    Computes the digits by repeated subtraction against a table of
    divisors (1000/100/10) and draws them via `TEXT_BLIT` (which
    interprets each byte as a character index into a font table at
    `$935B`). **Curious finding**: if the accumulated score reaches
    `$2710` (10000), instead of continuing to count it shows the
    text **"BESTIA"** ("BEAST") -- a text "prize" instead of a
    number --, and if `($60CA)` is active (probable demo-mode flag,
    consistent with `madmix_scr.asm`'s `TAIL_*` routines) it shows
    **" DEMO "**. Both texts and the digit buffer are index lists
    terminated with `$FF`, stored right next to the divisor table
    (`0x8DE3-0x8DFD`) -- this zone desyncs linear disassembly (the
    `$30` filler bytes for digits happen to decode as `JR`
    instructions that land on real labels further down), it needs
    to be checked carefully byte by byte instead of trusting the
    disassembler's straight-line output.
  - `JT_SLOT6` (`INPUT_READ`, `$8E3C`): keyboard reading (standard
    MSX matrix, `OUT $AA`/`IN $A9`, 5 rows against a mask table at
    `$8E88`) and joystick (PSG port, `OUT $A0`/`IN $A2`), decoding
    the direction bits with the same `LOOKUP_8978`/`DIRBITS_TABLE`
    pattern. Stores the result in a "free" byte reused inside the
    `TILE_TYPES` table itself (`$8EC4`/`$8EC6`/`$8EC7`) -- confirmed
    those bytes are `$00` in the real table, consistent with being
    reused as flags. The port/mask table at `$8E88-$8E93` (12 bytes)
    had the same disassembler-desync issue as the BESTIA/DEMO zone
    -- resolved by re-disassembling from the next known real
    instruction (`$8E94`) instead of trusting the straight-line
    reading.

With this, the only gaps left in `madmix1.asm` are: the large
graphics one (candy frame + sprites, `0x8F74-0xB940`, ~10,700
bytes), the final tail `0xD500-0xDDA1` (~2,209 bytes) and `INIT`'s
untranscribed continuation from `0x8F74` onward (already known and
documented before, not part of this task).

## Deciphered level-record offsets 8/11/18/19 (offsets 9/10 already known) -- and an arithmetic bug fixed

Final review of the level record's 20 bytes (base `$2BF3` in working
RAM, confirmed by `LD DE,$2BF3 / LDIR` in the level loader). Purely
real-code analysis (grepping each already-used `$2BFx`/`$2C0x`
address, no guessing from numeric patterns, same discipline as the
rest of this section) over the code that's ALREADY 100% transcribed
in `madmix_scr.asm`.

**Bug found and fixed**: a note from an earlier session labeled
`$2BFB` as "offset 11" when documenting `R51FE_MAIN`. That's an
arithmetic error -- `$2BFB - $2BF3 = 8`, not 11. The real offset 8
is `$2BFB`, and the real offset 11 is `$2BFE` (which, moreover, DOES
have its own real, distinct meaning, see below -- it wasn't free).

- **Offset 8** (`$2BFB`): confirmed by `R51FE_MAIN` -- count of
  `ITEM_TABLE_POS_511C` entries to activate (the "third type" of
  item, alongside offsets 9 and 10). Real values per level: 2-5.
- **Offset 9** (`$2BFC`): already known, `ITEM_HANDLER_1` -- number
  of type-1 items. Real values: 0-2 (fits `ITEM_TABLE_1`'s 2
  entries).
- **Offset 10** (`$2BFD`): already known, `ITEM_HANDLER_2` -- number
  of type-2 items. Real values: 0-3 (fits `ITEM_TABLE_2`'s 8
  entries).
- **Offset 11** (`$2BFE`, NEW): copied into `$2C0E` from two main-
  loop handlers, `HANDLER_311B`/`HANDLER_315D` (triggered on
  stepping on a tile with a specific relative-position pattern --
  "touching the special ball/track"). `$2C0E` is a **countdown
  counter**: the main loop decrements it every frame (`DEC (HL)` on
  `$2C0E`) and compares it against `$3C` (60 decimal, a reused
  literal -- coincidentally the same value as offset 12's tile
  wildcard, but that's a constant coincidence, not a real relation)
  and against `$32` (50) in `R51FE_MAIN`; in both cases, once the
  counter drops below the threshold, bit 0 (odd/even) gets tested --
  **the classic pattern of a blink once the countdown runs out**.
  HANDLER_311B also awards 2 points (`LD HL,$0002 / CALL $8D70` =
  `madmix1.asm`'s `SCORE_DRAW`) and triggers a sound effect
  (`$6128`). Strong candidate: **duration (in frames) of the
  special ball/track's blink for each level before it changes
  state** -- consistent with `GHOST_HINT_HANDLER`/`ITEM_EFFECT` type
  3 ("track") already documented. Real values: almost all `0xFA`
  (250, ~5s at 50Hz), with 4 distinct levels: level 7=`0xC8`(200),
  level 10=`0x32`(50, already below the 60 threshold used in the
  main loop!), level 11=`0xFF`(255, max), level 13=`0x50`(80).
- **Offsets 18-19** (`$2C05`/`$2C06`): **RESOLVED (later session)**
  -- see the dedicated section below, "Deciphered offsets 18-19:
  the level-end counter". At the time of writing this, no reference
  had been found because the real consumer lives in `madmix1.asm`
  (`IML_90B7`, inside the main loop), which wasn't transcribed yet
  -- not inside the large graphics gap as suspected here.

## MILESTONE: the "big gap" starts with INIT's real continuation (0x8F74-0x9134), and turns out to be the MAIN GAME LOOP

Starting to tackle the large graphics gap (`0x8F74-0xB940`, ~10,700
bytes, candy frame + sprites), the first step was disassembling from
the start to check whether it really was pure graphics from the
first byte. **It wasn't**: the first 449 bytes (`0x8F74-0x9134`,
ending in a stray filler `NOP` at `0x9135`) are real code -- the
continuation of `INIT` that had been marked "untranscribed from here
on" for the whole session. Cleanly disassembled with `Z80Dasm.exe`,
fully transcribed and **verified 0 real differences** (the 16 bytes
that do differ in the check are the same symbol-shift issue already
documented for the rest of the unfilled gap -- confirmed by checking
that `TILE_GFX` shifted exactly 449 bytes closer to its real address
after this change).

**Important finding**: `INIT` never does a `RET`. It enters a loop
(`INIT_MAIN_LOOP`, `0x8FD4`) that turns out to be **the game's main
loop** -- not just initialization. Two backward jumps from this new
block point to addresses INSIDE the already-transcribed and verified
`INIT` (`JP $8F54` and `JP $8F71`), confirming the "dual entry
point" pattern already seen many times in this project -- the labels
`INIT_RESUME_8F54`/`INIT_MAINLOOP_ENTRY_8F71` were added to the
existing `INIT` without touching a single already-verified byte.

Every call in this stretch is into routines ALREADY CONFIRMED in
other files, which backs up this reading:

- `TAIL_DECODE` (`$5CD1`), `TABLE_INIT` (`$5885`),
  `JT_SLOT9_TARGET` (`$8C34`), `TAIL_CREDITS_MAIN` (`$6454`, reused
  here for the in-game HUD, not just for credits), `WAIT_VBLANK`
  (`$89A0`), `INPUT_READ` (`$8E3C`),
  `LOAD_RESOURCE_SLOT_EMPTY`/`RM_C4CC` (sound manager),
  `TAIL_VDP_FILL` (`$5B8C`), `TAIL_TILE_LOOKUP` (`$6484`) -- all
  from `madmix_scr.asm`/`madmix1.asm`, already 100% transcribed.
- `INIT_HELPER_9116`: a character-by-character text reveal effect
  ("typewriter" style), waiting for a `WAIT_VBLANK` between each
  one.
- The rest of the loop polls the keyboard/joystick and manages a
  level/lives counter (`$2C27`) -- the typical "wait for a key to
  continue" cycle from these games.

It ends right where the linear-disassembly desync point was already
documented (`0x9135`-`0x9300`, "unexplored" in `mapa_memoria.html`)
-- confirms that boundary, already identified in an earlier session,
was correct.

**Continuation (same gap, 0x9136-0x92E3, 429 more bytes, FULLY
TRANSCRIBED, 0 real differences)**: right after the code, the
"unexplored" zone turned out to be real DATA, not graphics --
located by following every address the previous code block reads/
writes:

- **Never-before-documented in-game messages**: `FASE_TEXT`
  (`"FASE 00"`, with a level-number template substituted at runtime
  via `LEVEL_NUM_TABLE`), `EXTRALIFE_TEXT`/`EXTRA_TEXT`
  (`"EN LA PROXIMA... EXTRA"` / `"EXTRA"`), `READY_TEXT`
  (`"READY?"`, the classic level-start notice) and `GAMEOVER_TEXT`
  (`"ESTAS FRITO"`, the lose-a-life message).
- **`PTR_TABLE_91C3` (256 bytes, 64 entries of 4 bytes)**: each
  entry is `[16-bit address][flag byte][constant $18]`. The 64
  addresses have an EXACT fixed stride of 144 bytes (`0x90`), from
  `$953B` to `$B8AB` -- and **they all fall inside the graphics gap
  still not deciphered** (`0x92E3-0xB940`). It's the most promising
  lead so far for splitting that gap into its real divisions,
  instead of guessing at a fixed tile size (which is exactly why the
  3 earlier attempts to locate the sprites failed). The flag byte
  varies between `0x00`/`0x04`/`0x06` with no identified pattern;
  the trailing `$18` is constant across all 64 entries, its purpose
  unidentified.
- **`PATTERN_TAIL_92C3` (32 bytes, right before the actor table at
  `0x92E3`)**: 4 groups of 8 bytes that look like a real 8x8 tile
  pattern (MSX SCREEN 2 format) -- not yet confirmed whether it's
  the first resource pointed to by `PTR_TABLE_91C3` or simply
  filler.
- The small 19-byte table at the start (`0x9136-0x9148`) is used in
  a search loop (`IML_900F`) comparing against `($9147) AND $78` --
  possibly a HUD column-position table, exact detail unconfirmed.

**A transcription bug found and fixed along the way**: while
inserting this block, the header comment and the first data line
ended up stuck together with no line break between them -- the
whole first row of 16 bytes (`$08,$48,$10,...`) got absorbed into
the comment and never actually compiled (16 bytes short, caught
immediately because `TILE_GFX` didn't match the expected shift).
Fixed by regenerating the whole block by script from the `.BIN`'s
real bytes, verified at zero differences before inserting it again.

## BIG MILESTONE: the 64 CHARACTER SPRITES identified and transcribed (0x953B-0xB93B, 9216 bytes, 0 differences)

Using `PTR_TABLE_91C3` as a guide (64 pointers with a fixed 144-byte
stride, see the earlier milestone), `src/recursos/ptrtable_sprites.html`
was built to render the 64 entries as a raw bitmap, with no
commitment to any format hypothesis beforehand. **The developer
(the game's original player) identified all 64 entries at a
glance.** Fully transcribed, 0 differences byte for byte (verified
by compiling the block in isolation with `ORG $953B`).

### Full catalog (table index → sprite)

```text
 0 Pac-Man vulnerable right, mouth closed
 1 Pac-Man vulnerable right, mouth open 90º
 2 Pac-Man vulnerable right, mouth open 95º
 3 Pac-Man vulnerable down, mouth closed
 4 Pac-Man vulnerable down, mouth half open
 5 Pac-Man vulnerable down, mouth more open
 6 Pac-Man vulnerable up (back turned) -- only view
 7 Pac-Man invincible right, mouth closed
 8 Pac-Man invincible right, mouth open 90º
 9 Pac-Man invincible right, mouth open 95º
10 Pac-Man invincible down, mouth closed
11 Pac-Man invincible down, mouth more open
12 Pac-Man turned into a plane, facing up
13 Pac-Man "at work" (laying balls) facing right
14 Pac-Man "at work" (laying balls) facing down
15 Pac-Man "at work" (laying balls) facing up (back turned)
16 Pac-Man as hippo (steps on ghosts) right, step 1
17 Pac-Man as hippo right, step 2
18 Pac-Man as hippo right, step 3
19 Pac-Man as hippo down, step 1
20 Pac-Man as hippo down, step 2
21 Pac-Man as hippo up, step 1
22 Pac-Man as hippo up, step 2
23 Pac-Man as tank, facing right
24 Pac-Man as hippo down, step 3
25 Pac-Man as hippo up, step 3
26 Sprite with 4 circles in the center -- UNIDENTIFIED
27 Ghost right, step 1
28 Ghost right, step 2
29 Ghost down, step 1
30 Ghost down, step 2
31 Ghost up (back turned), step 1
32 Ghost up (back turned), step 2
33 Vulnerable ghost right, step 1
34 Vulnerable ghost right, step 2
35 Vulnerable ghost down, step 1
36 Vulnerable ghost down, step 2
37 Ladybug down
38 Ladybug up
39 Ladybug right
40 Pac-Man death (small ball), sequence 0
41 Pac-Man death (large ball), sequence 1
42 Pac-Man death (decomposing), sequence 2
43 Pac-Man death (decomposing), sequence 3
44 Pac-Man death (decomposing), sequence 4 -- last frame
45 "Repugnantoso" right, step 1
46 "Repugnantoso" right, step 2
47 "Repugnantoso" right, step 3
48 "Repugnantoso" down, step 1
49 "Repugnantoso" down, step 2
50 "Repugnantoso" down, step 3
51 "Repugnantoso" up, step 1
52 "Repugnantoso" up, step 2
53 "Repugnantoso" up, step 3
54 "Repugnantoso" disheveled (facing down?) -- NOT fully identified
55 400 POINTS (appears where a ghost was eaten)
56 600 POINTS (appears where a ghost was eaten)
57 Pac-Man invincible down, mouth half open
58 Pac-Man death down, sad, shrink 1 -- the sequence's real START
59 Pac-Man death right, sad, shrink 2
60 Pac-Man death up (back turned), shrink 3
61 Pac-Man death left, sad, shrink 4 -- continues at 40
62 Dead ghost
63 Null sprite (blank/black, all zeros)
```

**Real death-animation sequence** (confirmed by the developer, it's
NOT the index order): `58 → 59 → 60 → 61 → 40 → 41 → 42 → 43 → 44`.

### A gameplay finding with a direct code implication

The character sprites **only exist for the right, down and up (back
turned) views** -- none has its own sprite facing left, almost
certainly to save memory. When the game draws an actor facing left,
it very likely uses the right-facing sprite **flipped horizontally
at runtime**. This fits something already transcribed without being
fully understood: `ACTOR_ENGINE` has two nearly-twin drawing
routines, `JTS2_RENDER_A` (shift to the right) and `JTS2_RENDER_B`
(shift to the left), selected based on the actor's position. Strong
candidate: one of the two does the real horizontal flip (in addition
to, or instead of, the already-documented sub-pixel shift) --
pending confirmation by reviewing that code with this new lead.

### What's left of this gap

- `0x92E3-0x953B` (600 bytes): still unidentified, right before the
  sprite table.
- `0xB93B-0xB940` (5 bytes): unidentified tail right before
  `TILE_GFX`.
- The exact mechanism of how each 144-byte block gets CONSUMED
  (pixel format, how it's decided which of the 8 bytes in each group
  of 3 corresponds to which row) still hasn't been deciphered at the
  code level -- they were identified visually, the reading algorithm
  wasn't decoded. `JTS2_XOR_TRANSFORM` (inside `ACTOR_ENGINE`) reads
  3 bytes from the address the table points to and applies a bit
  rotation, but careful review of the real code shows it only
  touches the first 3 bytes of each 144-byte entry (repeatedly, 48
  times, with self-modification) -- it doesn't walk the full 144
  bytes. The rest of the entry (the real visual pattern) is consumed
  somewhere else still not located (candidate: `JTS2_RENDER_A`/
  `JTS2_RENDER_B`).

## RESOLVED the large gap's remaining 605 bytes -- it's the CHARACTER FONT, and with this ALL of `0x8400-0xD500` is at 0 differences

The two gaps left after finding the sprites --
`0x92E3-0x953B` (600 bytes) and `0xB93B-0xB940` (5 bytes) -- turned
out to be the **character font** used by `TAIL_DECODE`/`TEXT_BLIT`
to draw every text already transcribed (credits, menu, score,
"FASE"/"READY?"/"ESTAS FRITO"). Located with `TEXT_BLIT`'s real
formula (already transcribed and verified): glyph address =
`$925B + code*8`.

- Codes `$11-$1F` (control, unused by any real text) and `$20`
  (space): confirmed to be real zero in the `.BIN` -- a blank glyph,
  not made-up filler.
- Starting at `$21` (`FONT_TABLE_9363`, at `0x9363`) 59 real glyphs
  of 8 bytes each begin (symbols, digits, uppercase letters) -- ends
  EXACTLY where the sprite table starts (`0x953B`), with not a
  single byte overlapping.
- The rest (`0xB93B-0xB940`, 5 bytes) is an unidentified tail, real
  content `$00,$FF,$FF,$FF,$FF`.

  **REVIEWED again (later session), no result -- probably just
  filler**: just like was done successfully for the `0xD500` block
  (which did turn out to have a real hidden consumer), any reference
  to this address was searched for across all the code already
  transcribed in `madmix1.asm` and `madmix_scr.asm` (both 100%) --
  neither as a literal `LD HL,$B93x` nor as a low/high raw-byte
  pointer. **None was found.** `ACTOR_ENGINE` indexes sprites by
  number (0-63) over fixed 144-byte blocks, with no need for any
  "end of table" marker, and `0xB940` isn't a round boundary
  suggesting deliberate alignment padding. Unlike the `0xD500` gap,
  there's no extra lead to chase here -- most likely it's unused
  filler, with no hidden function.

**FULLY TRANSCRIBED, 0 differences byte for byte.** With this,
`TILE_GFX` now lands EXACTLY at its real address (`0xB940`) for the
first time in the whole session -- there's no more symbol shift from
`0x8400` all the way to here. Full verification by stretch:

```text
0x8400-0x92E3: 0 differences (3811 bytes)
0x92E3-0xB940: 0 differences (9821 bytes) -- the whole "big gap"
0xB940-0xC4A0: 0 differences (2912 bytes) -- TILE_GFX
0xC4A0-0xD000: 0 differences (2912 bytes) -- sound driver
0xD000-0xD500: 0 differences (1280 bytes) -- MAZE_DATA
```

**All of `madmix1.asm` from `0x8400` to `0xD500` is at 0 differences
byte for byte.** The only real gap left in the whole file is
`0xD500-0xDDA1` (2209 bytes, the final tail) -- and the "candy
frame" itself (the candy's graphic, distinct from the character
sprites) still hasn't been located within what's already
transcribed.

## RESOLVED the final tail `0xD500-0xDDA1` -- `madmix1.asm` is now complete at 0 differences byte for byte

The last `DS` gap in the whole file was transcribed. Real structure
discovered:

- **`0xD500-0xD6B6`** (438 bytes, `TABLA_SIN_IDENTIFICAR_D500`): still
  undeciphered. Same visual style as the RLE table right below it
  (pairs with repeated `$FF,$FF` markers, patterns `01,10,01,00`/
  `01,11,01,01`), but no place in the already-transcribed code was
  found loading a literal address within this range. Transcribed
  byte for byte, undeciphered.

  **RULED OUT as the hidden level's header** (checked because
  `MADMIX.SCR`'s body/header block has no room for a 4th header of
  its own, see the hidden-level finding -- this was the only
  unidentified zone left in `MADMIX1.BIN` as a candidate). Rendering
  it as if it were a 32-column tile grid produces a jumble with no
  recognizable structure at all -- no rooms/corridors, nor the solid
  "empty" row the 3 real headers do have. Also, 24 of the 438 bytes
  fall outside the valid tile-index range (0-90) and almost all are
  `$FF,$FF` pairs -- the same signature as the adjacent RLE table,
  not raw tile data. Conclusion: it's the same kind of data as
  `RLE_TABLE_D6B6` (masks/RLE), not a lost level header.

  **FULLY RESOLVED (later session)**: they're neither graphics masks
  nor RLE -- they're **10 auto-play scripts for DEMO mode**. The
  definitive lead: `LEVELCYCLE_TABLE` (`$60D0`, `madmix_scr.asm`,
  already transcribed) had a note saying "the `$D5xx`/`$D6xx`
  pointers fall inside `MADMIX1.BIN`" that was never connected to
  this gap -- its 4 pointers (`$D524`, `$D564`, `$D5D4`, `$D644`)
  ALL fall within this range. `TAIL_LEVELCYCLE_MAIN` (`$6045`) uses
  each pointer as `IX` and walks pairs `[(IX+0)=duration in frames,
  (IX+1)=simulated direction]`, waiting for the indicated frame
  count and simulating that direction (with `AND $1F`) as if it were
  a real key press, until it hits direction `$FF` (end of script,
  moves to the next level in the `1→2→4→5→1...` cycle).

  Walking the block straight through from `0xD500` (without using
  any pointer, just jumping from pair to pair until each `$FF`), the
  438 bytes split **EXACTLY into 10 consecutive scripts, with not a
  single byte left over** (100+94+18+66+4+24+18+88+6+20 = 438). Only
  4 of those 10 scripts are referenced by `LEVELCYCLE_TABLE`
  (`DEMO_SCRIPT_NIVEL1/2/4/5` in `madmix1.asm`) -- and curiously
  level 1's pointer (`$D524`) doesn't point to the real start of its
  script, which begins at `$D500` (the first 18 pairs, up to
  `$D524`, are simply skipped). The other **6 scripts**
  (`DEMO_SCRIPT_SINREF_1` through `_6`) are real, well-formed
  content (cleanly ending in `$FF` like the others) but **with no
  pointer referencing them at all** -- the same disconnected-content
  pattern as the hidden level and the `LEVEL_TABLE` gap (logical
  candidate: scripts recorded for more levels, of which only 4 ever
  got connected to the final cycler).

  **TRANSCRIBED with the 10 labels** (`DEMO_SCRIPT_NIVEL1/2/4/5` +
  `DEMO_SCRIPT_SINREF_1..6`), recompiled and verified: each label
  lands exactly at its real address (`--sym`), 0 differences byte for
  byte kept. Also fixed an outdated comment in `madmix_scr.asm` that
  said "6-entry table" for `LEVELCYCLE_TABLE` when the real loop
  (`CP $04`) confirms there are 4.
- **`0xD6B6-0xDD82`** (1740 bytes, `RLE_TABLE_D6B6`): a real RLE
  table, with **two confirmed consumers** that reuse the same bytes
  in two different ways (typical MSX1 memory economy):
  1. `TAIL_LEVELCYCLE_HELPER2` (`madmix_scr.asm`, `$6429`) walks it
     sequentially as 870 `(value, repeat count)` pairs: `BC=$0366`
     iterations × 2 bytes = exactly 1740 bytes, ending right at
     `$DD82` (verified by exact arithmetic: `$D6B6 + 2*$0366 =
     $DD82`, matches where the real code below starts). Each pair is
     passed to `CALL $8931` (`LDIRVM`/`FILVRM`) to fill the VRAM
     pattern table when a level starts.
  2. `ADDR_FROM_DC00` (`$8988`) + `JTS2_PROCESS_ACTORS` access a
     sub-stretch of this same table (`$DC00` onward) randomly
     (offset based on the actor's on-screen position), as 16-bit
     AND/OR masks to composite sprites against the background --
     this **resolves** the "Zone 0xDC00" that was left as "not
     deciphered yet" in an earlier finding on this same table: it
     isn't a separate table, it's a sub-stretch of `RLE_TABLE_D6B6`
     reused for a second purpose.
- **`0xDD82-0xDD8A`** (8 bytes, `SLOT_RESTART_DD82`): real code
  (`DI` / `LD A,$55` / `OUT ($A8),A` / `JP START`), with no known
  caller in the code already transcribed -- possibly an external
  entry point (from `MADMIX0.BIN` or some other mechanism), trigger
  unconfirmed.
- **`0xDD8A-0xDD93`** (9 bytes, `PSG_WRITE_READ_DD8A`): real code,
  **with a confirmed caller** -- it's the real target of
  `CALL $DD8A` in `IR_JOYREAD`, already present in the file before
  this session (now turned into a symbolic reference). Writes A to
  the PSG register already selected by the caller, selects register
  14 (I/O Port A, joystick 1 on MSX) and returns its value.
- **`0xDD93-0xDD96`** (3 bytes): an orphan code tail with no known
  caller, `POP HL` / `EI` / `RET`.
- **`0xDD96-0xDDA0`** (10 bytes): solid `$FF` filler.
- **`0xDDA0`** (1 byte, `$CD`): outside the game's real data -- the
  first byte of what would be the next instruction if the file
  continued, but the `.BIN` ends here (disk-sector padding, not part
  of the program).

**FULLY TRANSCRIBED, 0 differences byte for byte** (verified by
compiling the whole file and comparing against the complete original
`.BIN`, accounting for the MSX header's 7-byte shift).
**`madmix1.asm` is now 100% complete, with no `DS` gap remaining,
from `0x8400` to `0xDDA1`.**

## RESOLVED THE CANDY FRAME -- it was in `RLE_TABLE_D6B6`, visually confirmed

The question that had been open for many sessions ("where's the
candy frame's graphic?") got resolved by analyzing the RLE table
`0xD6B6-0xDD82`, just transcribed in the final tail, in more detail.

**The key lead**: adding up the 870 repeat counts across all
`(value, repeat)` pairs in the table, the total comes to **exactly
6144 bytes (`$1800`)** -- the FULL size of the VRAM pattern table in
SCREEN2. This fits what was already known about the routine that
consumes it (`TAIL_LEVELCYCLE_HELPER2`, `$6429` in `madmix_scr.asm`):
it flushes the table SEQUENTIALLY starting at VRAM `$0000`, so this
RLE table isn't a simple partial fill -- **it reconstructs the whole
screen pattern table, in one go, before anything else gets drawn on
top**.

**Definitive verification**: the RLE was expanded (870 pairs → 6144
bytes) and rendered as a bitmap using SCREEN2's identity name table
(already confirmed in an earlier session's real VRAM dump: name byte
= cell index, no indirection). The result is the candy frame, **complete
and perfectly recognizable**: diagonal red-and-white stripes at the
top and bottom, the white rounded caps at all 4 corners (the same
motif already identified before in `border_candy_corner_TL.png`,
which at the time was cropped from a live VRAM dump without yet
knowing where those bytes came from in the `.BIN`), and even the
small "shine"/star motif near the bottom-left corner -- **pixel for
pixel identical** to `src/dump_openmsx/screen_reconstructed.png`
(the real screen reconstruction from an earlier session). Render
saved at `src/dump_openmsx/candy_frame_reconstructed.png`.

The render's center comes out black (empty) because that's exactly
the area the maze tiles (`TILE_GFX`, via `REDRAW_STRIP`) overwrite
afterward, frame by frame -- the frame survives intact at the
top/bottom borders because the maze never draws there. This also
explains why the old "candy frame at `~0x9600-0xB700`" hypothesis
(from much earlier sessions, before the character sprites were
identified) was wrong: that zone turned out to be the character font
and the 64 sprites, not the frame -- the real frame lived in the
file's tail, disguised as a "generic VRAM-fill RLE table".

**Conclusion**: the `.BIN` doesn't contain a "candy graphic" as such
in tile-table format (like `TILE_GFX`'s) -- the frame's whole design
(stripes + corners + shine) is encoded directly as a single RLE
strip over the entire screen pattern table, generated by design
rather than drawn tile by tile. Minor, non-blocking pending item:
the frame's color (red/white) isn't in this table -- the routine
sets the whole color table to a constant value (`$01`) before this
flush, so the stripes' real color gets applied somewhere else not
yet located (candidate if this is picked back up: look for writes to
VRAM `$2000`+ after this routine).

## RESOLVED THE PURPOSE OF `maze_data.bin` -- it's the real (shared) source for levels 13 and 14's bodies

A question left open for many sessions: why does a complete, valid
32×40-tile maze (`maze_data.bin`, `0xD000-0xD500`) live resident in
`MADMIX1.BIN`, if the 14 real levels live in `MADMIX.SCR`? It was
already known, from earlier sessions, that `LEVEL_TABLE` somehow
referenced this zone for levels 13 and 14, but without verifying the
exact mechanism or whether the result was a real maze or noise.

**The mechanism, confirmed**: `LEVEL_LOADER` (`$5904`, in
`madmix_scr.asm`) reads the body pointer (`field0`, offset 0 of the
20-byte record) from `LEVEL_TABLE` and uses it **as-is, with no
address conversion at all**, as the source for an `LDI` that copies
`field6*32` bytes into the active-level buffer. For levels 0-12 that
pointer falls within `0x1000-0x6500` (`MADMIX.SCR`'s relocated copy
in low RAM). But for levels 13 and 14, the table's real pointers are
**`0xCFA4`** and **`0xD244`** -- addresses inside the static range
where `MADMIX1.BIN` lives (`0x8400-0xDDA0`), not inside the relocated
zone! Since both files coexist in RAM at runtime (`MADMIX1.BIN`
loaded on top of `MADMIX.SCR`'s relocated copy, see the boot sequence
documented above), the level loader ends up reading these two
levels' bodies **directly from `MADMIX1.BIN`'s resident memory**,
not from dedicated data in `MADMIX.SCR`.

- **Level 13** (`field6=21`, a 672-byte body from `0xCFA4`): the
  first 92 bytes come from `RM_TABLE_CFA4` (the sound driver's
  envelope/percussion table, which ends right at `0xD000`), and the
  remaining 580 bytes are the start of `maze_data.bin`.
- **Level 14** (`field6=23`, a 736-byte body from `0xD244`): 700
  bytes are from `maze_data.bin` (from its midpoint to its end at
  `0xD500`) plus 36 bytes that spill into the adjacent
  `TABLA_SIN_IDENTIFICAR_D500` table (the 438-byte undeciphered gap
  transcribed in the final tail).

**Proof this is deliberate design, not coincidence**: level 13's
body ends EXACTLY at `0xCFA4+672 = 0xD244` -- which is literally
level 14's body pointer. The two records were built to be read in
one go, back to back, with no gap
or overlap, in the same stretch of memory. This can't happen by
chance.

**Definitive visual verification**: `src/recursos/niveles.html`
already had (from an earlier session) levels 13 and 14's real bodies
extracted with these exact same pointers. Rendering those entries
with the same tile decoder as the rest of the levels, **both come
out as complete, symmetric, perfectly playable mazes** -- corridors,
walls, with no trace of noise or visual discontinuity,
indistinguishable in style from the rest of the real levels. It also
matches the statistical finding already noted before: the 2 most
frequent values in `maze_data.bin` (`0x2D`/`0x3F`, the corridor-
with-balls pattern) are EXACTLY the same ones that dominate the
normal levels -- confirms `maze_data.bin` was deliberately designed
to produce a real-looking maze when read as level data, not that it
is a casual byproduct of another table.

**Conclusion**: `maze_data.bin` isn't a discarded development level
nor a lost copy -- it's a real piece of design, deliberately placed
in `MADMIX1.BIN` to serve as a **shared, reused data source** for
levels 13 and 14, saving the need to duplicate ~1.4 KB of level data
inside `MADMIX.SCR`. It's a memory-saving trick typical of an MSX1
engine with very tight resources: instead of reserving dedicated
space for two more levels' bodies, the level table simply points at
bytes that are ALREADY resident in memory for another reason (the
sound driver's tail + this block), accepting that they're also
readable as valid tiles. This also partly explains why
`TABLA_SIN_IDENTIFICAR_D500` (at least its first 36 bytes) has the
same visual style as a level-data/mask table: it's literally the end
of level 14's body.

### Why they resorted to this trick: `MADMIX.SCR` is full to the last byte of the relocation budget

The developer's hypothesis, with very good numerical backing:
**`MADMIX.SCR` couldn't grow any further** within `MADMIX0.BIN`'s
relocation mechanism, and that's why there was no room to store two
more levels' bodies there.

`MADMIX0.BIN` (the relocator, 58 bytes) does an `LDIR` with
`BC=$5500` -- a **fixed value, written literally in the code**, not
an assumption on our part. It copies exactly 0x5500 (21,760) bytes
from `0x8800` to `0x1000`.

And the real size of the `MADMIX.SCR` zone that `LDIR` relocates
matches that limit EXACTLY: `0x8800 + 0x5500 = 0xDD00`, which is
precisely where the relocated zone ends. The only byte left over in
the whole file (the "stray byte" of unknown content at `0xDD00`, see
above) falls OUTSIDE that zone -- the `LDIR` doesn't even copy it.

In other words: the budget for "everything that gets relocated to
low memory" (title screen, music driver/loader, menu, credits, and
the bodies/headers of the 12 real levels + the hidden one) is
**full to the very last possible byte**, with not a single byte of
margin. This fits very well with the idea that the developers ran
out of room for the ~1.4 KB extra that levels 13 and 14's bodies
would have needed, and instead of touching the relocator's fixed
constant (possibly itself limited by how much free RAM there really
was in that low MSX zone before hitting something reserved by the
system), they went for the cheapest shortcut: pointing those two
levels at bytes that were already resident in `MADMIX1.BIN` for
another reason, which has its own separate space budget.

## CONFIRMED IN EMULATOR: the hidden level (Pac-Man-shaped) is a real, playable maze

It was finally tried live, patching a COPY of the original `.dsk`
(without touching the real disk or the reconstructed source code):
level 1's record was located directly in the `.dsk`'s raw bytes
(offset `52676`, checked first against `LEVEL_TABLE`'s already-known
300 bytes) and its body pointer (`field0`) was overwritten from
`0x335C` (real level 1) to `0x48BC` (the hidden level), reusing
record 6's other metadata (which also has `field6=18` rows, same as
the hidden one). A 20-byte in-place patch, same file size, without
touching the disk structure (`build/nivel_oculto_test.dsk`).

**Result, confirmed by the developer playing it in openMSX**: the
level loads and **you can walk around normally** -- definitively
confirms `BODY_HIDDEN_48BC` is a real, fully playable maze, not
noise or broken data. Two glitches showed up, both explained by
record 6's "borrowed" metadata (not by the maze itself):

- Pac-Man appears at a position that makes no sense for this
  geometry, right where the ghosts also appear -- fits with record
  6's starting position (offsets 15-16) and reference point (offsets
  13-14) being valid coordinates for ITS OWN maze, not the hidden
  one.
- The ghost house door comes out duplicated/misplaced in the center
  of the screen -- the reused header (`0x50BC`) is a generic shared
  header, not designed for this specific level's Pac-Man silhouette.

**Conclusion**: if this level had had its own real record in
`LEVEL_TABLE` (something that never happened -- none of the 15
entries reference it), it would have needed its own custom header
and its own starting coordinates, consistent with its Pac-Man
silhouette. Without that, it's consistent with the hypothesis that
it's content that was cut/never finished being connected before the
game shipped, not a loading bug. With this, the parked task "test
the hidden level in an emulator" is closed -- visual and playable
confirmation obtained, no need to keep chasing fine-tuned positions
(that wasn't the goal).

### CORRECTION about the ghost-house door: it does NOT live in the header, and the hidden level already has its own, correctly placed

Developer's hypothesis after the test: maybe the reused header
determines the ghost house's position, and that's why it came out
misplaced? Checked by searching for the door's pattern (3 tiles:
`left-start`/`electric-line`/`right-start`, indices `0x50,0x38,0x51`
-- see `graficos.html`'s catalog) in the 3 known headers and in the
body of the 12 real levels + the hidden one.

**Result, clear-cut**: none of the 3 headers contains those tiles --
the door **always lives in the body**, as just another maze tile, on
a different row depending on each level's design (level 1: row 9;
level 6: row 2; level 10: row 8; etc.). And the hidden level
**already has its own door, complete and correctly placed**, in its
own body (`body_hidden_48bc.bin`, row 8, columns 23-25) -- built by
whoever designed the level, just like any of the 12 finished levels.

This rules out the header being the cause of the misplaced ghost
house during the emulator test. The real cause has to be in the
position fields borrowed from record 6 (offsets 13-16: Pac-Man's
starting position and reference point) -- those are numeric
coordinates from the `LEVEL_TABLE` record, not something the engine
computes by searching the map for the door tile, so inheriting level
6's values is enough to explain them showing up somewhere nonsensical
for this geometry. The maze itself, ghost house included, is
complete and well designed.

### OBSOLETE -- see the later round "the hidden level DOES have a real record, it was the mislabeled record 15"

The proposal below (manually building a new record) turned out to be
unnecessary: the record already existed in the original binary, it
was just misclassified as "20 bytes unidentified". The original
reasoning is kept intact below for its historical/methodological
value.

### PENDING RESOLUTION (documented, NOT implemented): 15 gaps in the table for 15 distinct mazes -- the hidden level would fit as "level 15"

Numerical reasoning, without touching any code or data yet:
`LEVEL_TABLE` has exactly **15 records** (indices 0-14). And
counting how many REALLY DISTINCT mazes exist across the whole game
-- the 12 unique bodies of levels 1-12, the 2 distinct mazes that
"borrow" bytes from `MADMIX1.BIN` for levels 13 and 14, and the
hidden level at `0x48BC` -- comes to **exactly 15**. The number of
slots in the table matches the number of distinct mazes that exist.
Right now, however, one of those slots (index 0) is wasted
duplicating level 1's record exactly, and the hidden level has no
slot referencing it -- in other words, one slot is spare and one is
missing.

**Possible solution, not implemented**: the hidden level would fit
naturally as a **"level 15"** at the end of the progression (not as
a replacement for slot 0). To pull this off, based on what's already
confirmed in this session, it would take:

1. **Reorganizing the table**: remove record 0 (a useless duplicate
   of level 1) and shift every record back one position, so level 1
   takes index 0, level 2 index 1, ..., level 14 index 13 -- freeing
   up index 14 (the last one) for a new record for the hidden level.
2. **Building the hidden level's record**: point `field0` at
   `0x48BC` (its real body, already confirmed playable) and `field6`
   at `18` rows; pick one of the existing shared headers (all 3
   available work structurally, since the ghost door already lives
   in the body itself, not the header -- see the finding above); and
   compute its own metadata (Pac-Man's starting position, item
   counters, etc.) instead of borrowing them from another level, as
   was done in the quick emulator test.
3. **Adjusting `INIT`'s code**: change `$2C07`'s startup from
   `LD A,1` to `LD A,0` (so numbering starts at 0 instead of 1, now
   that index 0 becomes a real level instead of a dead record).
4. **Adjusting the level-advance loop**: the `CP $10` (16) comparison
   / reset to `$01` in `IML_90B7` (`madmix1.asm`) would need to
   compare against `15` (`$0F`) instead and reset to `$00`, so the
   full cycle is `0-14` (15 levels) instead of today's `1-14`.

**Honesty note**: these are 4 coordinated code/data changes, not a
simple table edit -- and it still doesn't fully resolve the detail
of whether the ghosts' spawn position depends only on the record's
fields (already identified) or on some additional mechanism not yet
traced live (see the emulator-test section above). It stands as a
reasoned proposal, pending implementation and testing if this line
of work is picked back up -- **not a single byte of `madmix1.asm`,
`madmix_scr.asm`, or any project data was touched to write this
section.**

## CORRECTION: the "active level buffer" (0xFC60) reaches further than documented, and the rest of high RAM (0xF000-0xFFFF) was identified

Reviewing the "not analyzed" stretches left near the end of the 64KB,
using the 6 real RAM dumps already available
(`src/dump_openmsx/ram*.bin`):

- **`0xF004-0xFA00`** and **`0xFA32-0xFC60`**: confirmed to be memory
  belonging to the MSX-BASIC/DOS interpreter itself -- the first
  contains the standard device-name table (`"PRN LST NUL AUX
  CON"`), the second the keyword table (`"color auto goto list
  run..."`). Practically 0 differences across the 6 dumps (static).
  Neither is part of any of the 3 reconstructed binaries -- it's the
  gap where `MADMIX0.BIN` (`0xFA00-0xFA32`) gets deliberately loaded,
  precisely because those tables aren't needed for the rest of the
  boot sequence (see the separate finding on why this doesn't break
  BASIC).
- **CORRECTION about `0xFC60`**: the previously documented limit
  (`0xFC60-0xFE60`, 512 bytes) was too short. Comparing `0xFC60` live
  directly against `header_50bc.bin` + `body_l01.bin` concatenated:
  **0 differences** (with bit 7 masked, for already-eaten balls)
  across the first 800 bytes -- confirms the real active-level buffer
  reaches up to **`0xFF80`**, not `0xFE60`. With level 1 loaded (25
  rows: 3 header + 22 body) it uses exactly those 800 bytes; with the
tallest level (14, 26 rows) it would use up to 832 bytes (`0xFFA0`).
- **`0xFF80-0xFFE0`** (96 bytes): solid `$42` filler in the analyzed
  dump -- the part of the same buffer that level 1 doesn't need
  (reserved for taller levels).
- **`0xFFE0-0xFFFF`** (32 bytes, the absolute end of the 64KB):
  static across the 6 dumps, with a recognizable Z80 stack-tail
  pattern (`FB FD E1 DD E1 D1 C9...` = `EI`/`POP IY`/`POP IX`/
  `POP DE`/`RET`, a typical epilogue). Most likely candidate: leftover
  stack from the BASIC phase (before `INIT` sets `SP=$0FFF`, a
  completely different memory zone), frozen there because nothing
  touches that address again during play. Not part of any of the 3
  binaries.

With this, `0xF000-0xFFFF` is now fully identified: part is the real
level buffer (now with its correct limit) and the rest is BASIC/DOS
system memory or leftover stack, neither belonging to the game
itself. Fixed in `src/recursos/mapa_memoria.html` (continuity
re-verified: 0 gaps, 58 segments).

## IDENTIFIED: 0xDDA0-0xDE04 (right after MADMIX1.BIN's real end) is a SYSTEM interrupt handler, not the game's

Continuing the sweep of "not analyzed" zones, the `0xDDA0-0xDE03`
stretch (right between `MADMIX1.BIN`'s final orphan byte at `0xDDA0`
and where the background buffer starts at `0xDE04`) was disassembled
with `Z80Dasm` using the real RAM dumps -- **100% static across the
6 dumps**, same as today's other system findings.

From `0xDDA9` onward (the 9 bytes before it look like desync noise, a
pattern already seen many times in this project) the disassembly is
clean and very recognizable -- a **classic interrupt handler**:

```asm
PUSH IX / PUSH IY / PUSH HL / PUSH DE / PUSH BC / PUSH AF
EXX / EX AF,AF' / PUSH AF / PUSH HL
LD HL,($DDD2) / LD A,L / OR H / POP HL
LD IX,$0038                  ; the Z80's interrupt vector
LD IY,($FCC0)
JR NZ,$DDE8
...
CALL $001C                   ; reserved BIOS/DOS zone
...
POP AF / POP BC / POP DE / POP HL / POP IY / POP IX
EI
RET
```

Saves absolutely every register (the mandatory pattern for any
routine that can fire mid-interrupt), checks a flag, and calls fixed,
very-low-level addresses (`$0038` is the Z80's own housekeeping
interrupt vector, `$001C` and `$F380` fall inside the reserved MSX
BIOS/DOS routine/variable zone). `LD IY,($FCC0)` might look related
to our level buffer (`0xFC60`+, just corrected above) by sheer
address proximity, but there's no sign of a real relationship -- it
fits much better as a fixed system variable that happens to land
nearby.

**Conclusion**: with very high confidence, this is **MSX-DOS/Disk-
BASIC resident code** (a generic interrupt hook, in the style of
"CTRL-STOP check" or equivalent housekeeping), not part of any of
the game's 3 binaries -- consistent with this session's same pattern
(frozen system content left over in memory after boot, never touched
again during play). The exact BIOS routine hasn't been identified
with absolute precision (a reference disassembly of the MSX ROM/DOS
would be needed to name it with total certainty), but the structure
leaves no reasonable doubt about its system nature. Fixed in
`mapa_memoria.html`.

## IDENTIFIED: 0x0000-0x04FF -- MSX low-level hook table, and live confirmation of the game's real interrupt vector

Finishing the sweep of "not analyzed" zones at the low end of memory,
using the same 6 RAM dumps (0 differences between them across the
whole stretch):

- **`0x0000-0x0037`**: the classic MSX low-level hook table (RST
  vectors + BIOS gaps) -- mostly zero, with 5 `JP`s to `$DDxx`/`$DExx`
  addresses (`$DDEE`, `$DE0F`, `$DE4F`, `$DE96`, `$DE3D`). Those
  addresses ALL fall inside the MSX-DOS/Disk-BASIC system zone
  identified earlier in this same session (`0xDDA0-0xF004`) -- hooks
  inherited from boot, not the game's (and probably already "dead":
  their targets have been overwritten by the game's own background
  buffer, so if they were ever invoked they'd jump into data, not
  real code -- but nothing invokes them during play).
- **`0x0038`** (the Z80's real interrupt vector, `RST 38h`):
  **`JP $882A`**. This is the only piece across the whole stretch
  that IS the game -- confirms live, from a different angle,
  something already transcribed and documented: `ISR` (`0x882A`, in
  `madmix1.asm`) is the real interrupt routine, and `INSTALL_ISR` is
  what writes this `JP` here on the fly at boot (`LD HL,$882A` was
  already in the transcribed code).
- **`0x003B-0x0054`** (26 bytes): a complete, coherent routine -- it
  changes the slot configuration using `$FFFF` as a working variable
  (`OUT ($A8),A` / `LD A,($FFFF)` / ... / `RET`). Any `CALL` to this
  address was searched for across all the code already transcribed
  in `madmix1.asm` and `madmix_scr.asm` (both 100%) -- **there is
  none**. It's system/BIOS code, not the game's.
- **`0x0055-0x00FF`**: all zero.
- **`0x0100-0x04FF`** (1024 bytes): solid `$FF` filler, 100% static
  across the 6 dumps. Could be mistaken for the actor buffer, but
  that one's already confirmed (earlier session) to start right
  after, at `$0500` -- this stretch is simply reserved, unused
  memory.

With this, `0x0000-0x04FF` is now fully identified: almost all of it
is system (inherited from BASIC/DOS boot, same as this session's
other findings), with the one real exception being the interrupt
vector at `$0038`, which is one more live confirmation of `ISR`/
`INSTALL_ISR`, already transcribed and verified before. Fixed in
`mapa_memoria.html` (continuity re-verified: 0 gaps, 62 segments).

## Deciphered offsets 18-19: the level-completion counter (and the real mechanism behind the level-13 bug)

Mechanism confirmed by real code, not numeric pattern-matching --
`IML_90B7`, inside the main loop in `madmix1.asm` (the part that was
still missing when the earlier note was written, which is why no
reference showed up):

```asm
LD HL,($2C08)     ; counter of "things eaten" in this level
LD DE,($2C05)     ; record offsets 18-19, copied here by the generic LDIR
AND A
SBC HL,DE
JR NZ,IML_90E4    ; if they don't match, the level is still not done
LD HL,$2C07
INC (HL)          ; if they match, advance to the next level
```

**Offsets 18-19 are the total number of "things to eat" to mark the
level complete** -- compared against `$2C08`, a 16-bit counter that
starts at zero every level (`LEVEL_LOADER`, `madmix_scr.asm`) and
gets incremented in 4 places in the collision engine
(`0x2CA0-0x335C`, already transcribed): the normal "floor with ball"
tile handler, and 3 more handlers that check different bits of a `B`
byte (candidate: extra "special ball" positions, using the wildcard's
substitute tile, offset 12, as the graphic) -- all 4 share the same
"redraw with `DRAW_TILE_HELPER` + add points + `INC ($2C08)`"
pattern.

**Numeric verification**: the 15 `LEVEL_TABLE` records were
extracted and, across the 12 real level bodies
(`src/data/niveles/body_l*.bin`), the "floor with ball" family tiles
(`0x2D`/`0x2E`/`0x2F`, bit 7 masked) were counted directly. For 4 of
the 12 real levels, the direct tile count matches offsets 18-19's
value **EXACTLY** -- and as a bonus, it also matches exactly for
level 13 (whose "borrowed" body is read from `MADMIX1.BIN`, see the
`maze_data.bin`-purpose finding):

| Level | offset 18-19 (target) | balls counted in the body |
| --- | --- | --- |
| 1 | 114 | 114 ✓ |
| 8 | 90 | 90 ✓ |
| 10 | 116 | 116 ✓ |
| 12 | 176 | 176 ✓ |
| 13 | 105 | 105 ✓ (borrowed body from `0xCFA4`) |

Five exact matches of this kind aren't a coincidence -- they
confirm beyond doubt that offsets 18-19 are the level's target ball
count (the classic "eat all the balls to clear the stage"
mechanism, like Pac-Man).

**Honesty note -- pending full precision (at the time)**: for the
other 8 levels the direct tile count did NOT match the target exactly
(differences of 11 to 116). The most likely cause was the body's
"wildcard" tiles (`0x3C`), which `LEVEL_LOADER` substitutes
conditionally (based on an external variable `$2C2C`, which is 0 on
the game's first full lap and only increases once the level counter
wraps from 16 back to 1) and the 3 additional "special ball by B
bits" handlers just identified, whose positions came from a
different table (candidate: `ITEM_TABLE_POS_511C` or similar,
already transcribed) that hadn't been cross-checked against this
count yet. The **mechanism itself was fully confirmed and left no
reasonable doubt** (real code, with 4 exact matches) -- what was
still open was only the fine detail of why the simple count didn't
add up for the rest of the levels.

**FULLY RESOLVED (level-tool session)**: the developer, reviewing
the visual level editor, pointed out that "arrow tiles have a ball,
so they should count toward the balls". Verified in the real code:
the 4 arrow handlers (`HANDLER_2F18`/`HANDLER_2F50`/`HANDLER_2F88`/
`HANDLER_2FC0`, tile types 3-6) increment `($2C08)` exactly like the
normal ball-tile handler (same `CALL $8D70` pattern with 2 points +
`INC HL / LD ($2C08),HL`). In other words: arrow tiles (`0x33`-
`0x36`) DO give a "ball" when stepped on, in addition to forcing the
direction. Adding them to the count (`tools/mmlvl_tool.py`,
`recursos/editor_niveles.html`): **all 12 levels match their
`LEVEL_TABLE` target EXACTLY, with no exception** -- no wildcard
tiles or extra "special ball" table were needed to explain the
mismatch, it simply was that 4 tile types were missing from the
count. Mystery fully closed.

**Connection to the already-known level-13 bug -- tested and RULED
OUT**: the thought was that, since level 13's body is read from
`MADMIX1.BIN` (the sound envelope table + `maze_data.bin`, see the
`maze_data.bin`-purpose finding), the real ball count in that
"borrowed" body might not match the target stored in its record,
directly explaining the historical bug ("even if you eat all the
balls, level 13 is never marked complete"). **This was immediately
checked by counting the real balls in level 13's body (672 bytes
from `0xCFA4`) against its target (`105`): they match EXACTLY
(105 = 105)** -- a **fifth confirmation** of the offsets-18-19
mechanism, but this RULES OUT the hypothesis that the level-13 bug
is a simple ball-count mismatch. The real cause of the historical
bug, with what we know, remains the more plausible of the two: the
`$FC60`→`$FC50` change in the coordinate→address formula (see the
"LOCATED... the real fix for the level 13 bug" section above).

## MILESTONE: first "production" test -- a disk generated 100% from source, works perfectly in openMSX

Definitive proof the reconstruction is real, not just "matching on
paper": the 3 `.asm` files (`madmix0.asm`,
`madmix1.asm`, `madmix_scr.asm`) were compiled and their resulting
binaries written **directly into a copy of the original `.dsk`**, at
the exact spot where each file lives (located by searching for each
original file's first 32 bytes in the raw `.dsk`, also confirming
all 3 are stored contiguously, with no fragmentation -- `MADMIX0.BIN`
at offset `9216`, `MADMIX1.BIN` at `10240`, `MADMIX.SCR` at `33792`).

**Verification before testing it**: the resulting full disk
(737,280 bytes) differs from the original in exactly **4 bytes** --
the same 3 at `0x28ED-0x28F0` and the stray byte at `0x6500` already
documented for a while (inside `MADMIX.SCR`), nothing else. Neither
the disk structure, nor `AUTOEXEC.BAS`/`MADMIX.BAS`, nor any other
file gets touched.

## RESOLVED: the tape (`.cas`) version's full structure -- confirms `MADMIX.SCR` and `MADMIX1.BIN` live there too, and relocation is done DIFFERENTLY from the disk

Purely read-only investigation of
`FISICO\Mad Mix Game (1988)(Topo Soft)(es)[RUN'CAS-']\...cas`
(50242 bytes), triggered by a question from the developer: do
equivalents of `MADMIX0.BIN`/`MADMIX.SCR` exist on the tape?

**Full structure** (located by searching for the CAS format's 12
`1F A6 DE BA CC 13 7D 74` sync markers and decoding each header
block):

| # | Name | Type | Offset in `.cas` | Size |
| --- | -------- | ------ | ------------------- | -------- |
| 1 | `TOPO` | ASCII BASIC | 32 | 256 B |
| 2 | `LOGOTOPO.CM` | binary | 320 | 4264 B |
| 3 | `MADMIX` | ASCII BASIC | 4616 | 256 B |
| 4 | `LOAD.BIN` | binary, loads at `$DDA0` | 4904 | 312 B (6+306) |
| 5 | `TEST.BIN` | binary, loads at `$C350` | 5248 | 264 B (6+258) |
| 6 | *(unnamed, no header)* | raw data | 5521 | 21761 B |
| 7 | *(unnamed, no header)* | raw data | 27297 | 22945 B |

Blocks 6 and 7 were compared byte for byte against the already-
reconstructed files: **block 6 = `MADMIX.SCR`'s real content** (21761
bytes compared, only 1 difference, in the last byte) and **block 7 =
`MADMIX1.BIN`'s real content** (22945 bytes compared, only 1
difference, also in the last byte). In other words, the game engine
is the exact same binary in both editions.

**Real boot sequence** (reading the plaintext BASIC listings):

```basic
' TOPO (first file, tape auto-boots into this)
10 COLOR 1,1,1:SCREEN 2
20 BLOAD"CAS:LOGOTOPO.CM",R      ' loads+runs the Topo Soft logo
30 RUN"CAS:                      ' empty name = "run whatever comes next"

' MADMIX (second BASIC program, loaded by the RUN above)
10 COLOR 1,1,1:SCREEN 2
20 BLOAD"CAS:LOAD.BIN"           ' no ",R": load only, don't run
30 BLOAD"CAS:TEST.BIN"           ' same
40 DEF USR=56736!                ' 56736 = 0xDDA0 = LOAD.BIN's entry point
50 A=USR(0)                      ' invokes it
```

**Full disassembly of `LOAD.BIN` (`$DDA0`) and `TEST.BIN`
(`$C350`)** with `Z80Dasm.exe` (extracted directly from the `.cas`,
no offset ambiguity). What matters:

- `TEST.BIN` is a RAM/slot detection engine (a classic MSX sweep:
  tries writing `$20`/`$FA` at `$4000` and `$8000` through `ENASLT`
  (`$0024`, self-modified as the `CALL` target at `$C3B3`), and saves
  two slot configurations at `$E290-E293` -- the same "save/restore
  slot" pattern `RELOCATOR` uses with `$FFFD/$FFFE` in `madmix0.asm`,
  but here to figure out which physical slot the RAM lives in
  (necessary on a cold tape boot, without the already-established
  context disk/DOS provides).
- `LOAD.BIN` is the real orchestrator, and here's the answer to the
  developer's question:

  ```asm
  CALL $C350              ; TEST.BIN: detects RAM slots
  CALL $DE93 / $DE98 / $DE9D   ; applies the 3 page configurations
  LD IX,$1000              ; <-- direct final DESTINATION address
  LD DE,$5500               ; <-- same size as RELOCATOR's LDIR
  LD A,$FF : SCF
  CALL $DDCC                 ; reads from tape IX=destination, DE=bytes
  CALL $1000                  ; runs the block just loaded (title screen)
  LD IX,$8400                ; MADMIX1.BIN's native address
  LD DE,$59A0                  ; 22944 bytes
  LD A,$FF : SCF
  CALL $DDCC                    ; reads from tape IX=$8400, DE=bytes
  JP $8400                       ; jumps to JT_INIT -- same as JUMP_TO_ENGINE
  ```

  `$DDCC` is the generic tape-reading routine (bit by bit, uses fixed
  BASIC ROM hooks like `$00E1`/`$C961`/`$CDD9`/`$EDD9`/`$69ED` pushed
  onto the stack, and blinks the border by writing to port `$99` --
  the typical border-flicker of commercial tape loaders). It takes
  the destination address in `IX` and the byte count in `DE`, nothing
  more.

**Answer to the question ("is the same `.scr` relocation done on
tape?"): NO, it's not the same mechanism, but it lands in the same
place.** On disk, `BLOAD"MADMIX.SCR"` lands at `$8800` (its
factory load address) and a second step is needed
(`MADMIX0.BIN`/`RELOCATOR`) that `LDIR`s those `0x5500` bytes from
`$8800` to `$1000` before the title screen can run. On tape, since
the raw block reader (`$DDCC`) accepts the destination address as a
free parameter (`IX`), `LOAD.BIN` itself tells it to **write
directly into `$1000`** -- completely skipping the intermediate
landing at `$8800` and the later `LDIR`. Even the byte count matches
`RELOCATOR`'s exactly (`DE=$5500` on tape == `BC=$5500` from the
`LDIR` in `madmix0.asm`), and `CALL $1000` runs in both cases right
after. Even the "1-byte difference at the end" that showed up
comparing blocks 6 and 7 is explained: the tape only reads exactly
`$5500`/`$59A0` bytes (whatever `LD DE,...` asks for); the extra byte
present in the `.cas` file falls outside what the routine actually
uses, so it doesn't matter that it doesn't match with total
precision.

**Bonus, closes a loose end from an earlier session**: the live RAM
dump (booted from DISK) that identified `0xDDA0-0xDE04` as "system
code, generic interrupt handler, unable to name the exact ROM
routine" -- **is this exact same code**, byte for byte. Three of the
five `JP` hooks found back then in the low memory table (`$DE96`,
`$DE3D`, and by extension the range) land exactly at the start of
real instructions in this disassembly (`jr $dea2` at `$DE96`,
`out ($99),a` at `$DE3D`, `xor a` at `$DE4F`). In other words: even
the disk boot leaves this tape-loading engine resident in high RAM
(part of the Disk-BASIC ROM/runtime, or a vestige inherited from a
codebase shared between versions), even though it's never invoked
during play.

**Hypothesis for why -- fits something already documented without
being connected until now**: `MADMIX.BAS` (the disk loader) carries
a "CRACKED BY PAU D'ACI" credit line (see the "full boot sequence
from the .BAS" section above) -- it was already known this disk copy
is an adaptation by a crack group, not necessarily Topo Soft's
official distribution. The pattern fits exactly what's typical of a
tape→disk conversion done by a third party: instead of replicating
the tape's free-address block-loading logic (`$DDCC`, `IX`/`DE` as
parameters), the disk converter took the easy path -- a normal
`BLOAD` (which lands wherever the file header says, `$8800` for
`MADMIX.SCR`) followed by a dedicated relocator (`MADMIX0.BIN`) that
does the exact same `0x5500`-byte `LDIR` to `$1000` that the tape
achieves in a single step. It's a plausible explanation, well
supported by the available evidence, though there's no way to
confirm it 100% without more context (each edition's release date,
whether Topo Soft ever had its own "factory" disk edition, etc.).

**Final conclusion, this one fully verified**: regardless of which
one is the "original" and which the adaptation, the game content's
RAM layout at runtime is **identical** in both editions --
`MADMIX.SCR` ends up relocated at `$1000-$6500` and `MADMIX1.BIN`
resides at `$8400-$DDA0` whether you get there the long way (disk:
`BLOAD`+`LDIR`) or the short way (tape: direct read to the final
address). All the source-reconstruction work (`madmix1.asm`/
`madmix_scr.asm`) is valid for both editions with no changes.

**The developer loaded it in openMSX and confirmed: it works
perfectly** -- a disk generated from scratch out of our source code,
indistinguishable in practice from the original. File:
`build/madmix_reconstruido.dsk`.

## Refactor: tiles, sprites and images no longer live pinned inside the `.asm` -- each in its own file

For maintainability: graphics that used to be literal `DB` bytes
inside `madmix1.asm`/`madmix_scr.asm` were extracted into individual
files under `src/data/`, loaded with `INCBIN` one after another in
the exact same order (so the layout in memory stays byte-for-byte
identical). Extension convention: `.til` for tiles, `.spr` for
sprites, `.fnt` for fonts, `.img` for the rest of the graphics
(title screen, candy frame).

- **`data/tiles/`** (91 files, 32 bytes each): the maze tiles,
  previously in a single `tile_gfx.bin`. Named with the index and a
  short description (e.g. `45_suelo_con_bola_1.til`), using the
  already-confirmed catalog from `graficos.html`.
- **`data/sprites/`** (64 files, 144 bytes each): the character
  sprites, previously as 64 inline `DB` blocks in `madmix1.asm`.
  Named with the index and the already-established name (e.g.
  `27_fantasma_der_1.spr`).
- **`data/fonts/`**: `fuente_caracteres.fnt` (472 bytes,
  `FONT_TABLE_9363`, 59 glyphs). Unlike tiles/sprites, it goes in
  **a single file for the whole font**, not one per character --
  `TEXT_BLIT` computes each glyph's address by formula
  (`base + code×8`), which requires a contiguous block, and it's
  also how bitmap fonts are really edited (the whole character set
  at once, not one by one).
- **`data/img/`**: the rest of the graphics that aren't a tile,
  sprite or font -- `marco_caramelo_forma.img` (1740 bytes,
  `RLE_TABLE_D6B6`), `marco_caramelo_color.img` (768 bytes, the
  color block from `LEVELCYCLE_RESOURCE_TABLE` in `madmix_scr.asm`
  -- the 43-byte table of `[id,pointer]` pointers preceding this
  block was left as-is, inline, because it's a functional table for
  the resource manager, not an image), and the title screen's 3
  files (`portada_paleta.img`, `portada_patron.img`,
  `portada_color.img`, renamed from `portada_table16.bin`/
  `portada_pattern.bin`/`portada_color_packed.bin` -- they were
  already externalized, just moved to the new folder and extension
  for consistency).
- **`data/demos/`** (10 files, `.dem` extension, 438 bytes total):
  DEMO mode's 10 auto-play scripts (see "IDENTIFIED...
  0xD500-0xD6B6 are 10 scripts..." above), previously as inline `DB`
  blocks under the labels `DEMO_SCRIPT_NIVEL1/2/4/5` and
  `DEMO_SCRIPT_SINREF_1..6`. Numeric data (duration/direction pairs),
  not text, so they were kept as pure binary, not ASCII. Named in
  order, flagging whether they're connected to a real level:
  `01_nivel1.dem` (100B), `02_nivel2.dem` (94B), `03_sinref.dem`
  (18B), `04_nivel4.dem` (66B), `05_sinref.dem` (4B), `06_sinref.dem`
  (24B), `07_sinref.dem` (18B), `08_nivel5.dem` (88B),
  `09_sinref.dem` (6B), `10_sinref.dem` (20B).

The old, now-superseded blobs (`tile_gfx.bin` and the original 3
`portada_*.bin`) were deleted. **Verified after each step**: a full
recompile of the 3 files, 0 differences kept in `MADMIX0.BIN`/
`MADMIX1.BIN`, and the same already-known 4 bytes in `MADMIX.SCR` --
the refactor didn't change a single bit of the real content, only
where it lives in the file tree.

## RESOLVED (extraction): the 3 sound scripts now live in `data/sound/*.snd`

Same as was done with tiles/sprites/fonts, `RM_TABLE_C8DE` was split
into individual files: the driver's tables (duration, command jump,
instrument/note -- 1261 bytes) stay as inline `DB` in `madmix1.asm`
(they aren't independent "content"), and the 3 real scripts move to
`data/sound/00_script_cdcb.snd` (52 bytes), `01_script_cdff.snd` (13
bytes) and `02_script_ce0c.snd` (383 bytes), loaded with `INCBIN`
under the labels `SOUND_SCRIPT_0_CDCB`/`SOUND_SCRIPT_1_CDFF`/
`SOUND_SCRIPT_2_CE0C`. References in `INIT` (which installs them) and
in `IML_900F` (the level-start jingle, `SOUND_SCRIPT_2_CE0C
+$E4/+$EB/+$F2`) were updated to use the labels instead of loose
addresses. **Verified**: `madmix1.asm` recompiled, 0 differences
kept.

**Extension decision**: `.snd` was used for all 3 equally, NOT
`.mus` for the longest one -- it's still not confirmed live **which
of the 3 scripts is which** (indices 0/1/2 via
`LOAD_RESOURCE_SLOT_ALLOC`, pointers `0xCDCB`/`0xCDFF`/`0xCE0C`), and
the `$CEF0`/`$CEF7`/`$CEFE` finding (the level-start jingle reads
FROM INSIDE script 2, it isn't its own script) suggests the longest
script could be a pool of reusable fragments instead of a single
continuous piece of music -- assuming "longest = music" without proof
would be exactly the kind of unverified claim this project avoids.

**Size-based lead (not confirmed live)**:

- Script 0 (`0xCDCB`, 52 bytes)
- Script 1 (`0xCDFF`, 13 bytes) -- the shortest, a clear candidate for a simple effect
- Script 2 (`0xCE0C`, 383 bytes) -- by far the longest, a clear candidate for the main music

**Expected sound catalog, per the developer (the original player)**
-- for when this thread is picked back up and needs cross-checking
against what each already-transcribed tile-handler/engine event
actually triggers:

1. Main music
2. Level-start jingle
3. Level-end jingle
4. Ball-eating sound (normal small ball)
5. Ghost-kill sound
6. Ball-stepping sound (hippo mode)
7. Ball-laying sound ("at work"/ball-laying mode)
8. Ball-replenish jingle (when the ladybug replaces it)
9. Shot (plane mode)
10. Sound for passing through a one-way tile
11. Trapdoor-enable sound

That's quite a few more than 3 distinct "events" for only 3 sound
scripts -- most likely several events share the same short script
(reused with different parameters/notes via the 15-command
"bytecode"), or some of these sounds come from a different mechanism
unrelated to `RM_TABLE_C8DE` altogether. None of this has been
investigated yet -- it stays parked until it's possible to trace live
what triggers each of the 3 indices.

**New lead found while documenting `IML_900F` (madmix1.asm, main
loop, level-start/"READY?" boot sequence)**: right where `READY_TEXT`
("READY?") gets drawn, the code calls `RM_C4CC` (the direct
`LOAD_RESOURCE_SLOT_ALLOC` entry that installs a channel without
searching for a free slot) 3 times with pointers `$CEF0`/`$CEF7`/
`$CEFE` -- **these 3 pointers fall INSIDE script 2 (`$CE0C`, 383
bytes)**, exactly 7 bytes apart from each other (offset +0xE4
relative to `$CE0C`), and the first bytes in that zone show a pattern
repeating every 7 bytes (`85,64,8E,X,8C,0B,8B`). This is a very
strong candidate for the catalog's **"level-start jingle"** above
(the PSG's 3 channels start at once, each at a different phase of
the same short sequence, right when "READY?" appears).

This also **refines the size-based lead above**: if the 383-byte
"script 2" contains short, reusable sub-sequences like this (instead
of being a single continuous piece of music), it can't simply be
assumed to be "the main music" just for being the longest of the 3
-- it could actually be a shared table of short fragments (jingles/
effects) from which different events take their own starting point.
Not fully confirmed, but it's the most concrete lead so far on that
block's internal structure.

## PENDING: decipher `ITEM_EXTRA_TABLE` ($56F5, madmix_scr.asm) field by field

`ITEM_EXTRA_TABLE` (94 bytes, `madmix_scr.asm` around line 2187) is
consumed by `ITEM_TIMER_TICK` ($5782), indexed via `IX-1` to decide
which tile to draw based on `$2C0F`, in the blink animation for the
4 "active item slots". Structure recognized visually but NOT
deciphered field by field -- left documented as raw data until it's
investigated further.

4 blocks are distinguishable, each ending in `$FF`, each with: a long
strip of the same repeated tile index (e.g. `$36`×22, `$3E`×24 --
the item's blinking "body"), a short tail of 4-7 distinct indices
(`$28,$28,$29,$29,$2A,$2B[,$2C]` -- candidates for candy-frame
corner/edge tiles), and a final stretch of another repeated index
(`$38`×10, `$37`×10). Interleaved in there is a 5+24-byte stretch
(`$0F,$8D,$0E,$0D,$0F` and then `$03,$00,$06,$80`×6) that doesn't fit
that tile-index pattern -- probably timing/color parameters,
unconfirmed.

**Pending**: it's unknown whether the 4 blocks map 1:1 to
`ITEM_TABLE_POS_511C`'s 4 item types, nor what the 29 interleaved
bytes exactly represent. Requires tracing `ITEM_TIMER_TICK` live to
confirm the real mapping before the format can be documented field by
field (and, if warranted, decide whether it makes sense to extract it
into its own file, similar to what was done with tiles/sprites/
demos).

## RESOLVED: `PATTERN_TAIL_92C3` (madmix1.asm) is the HUD's extra-life icon, not a tile or filler

It had been left marked "unconfirmed HYPOTHESIS" as to whether it was
the first tile pointed to by `PTR_TABLE_91C3` or simple filler before
the actor table. Thoroughly investigated: **it's the "extra life"
icon** (a miniature Pac-Man) drawn in the HUD once per remaining
life.

**Proof, from real code, not a format hypothesis**:
`JT_SLOT9_TARGET` (`madmix1.asm:1739-1754`) reads `($2C27)` (lives
counter) and, for each life, calls `JS9_ROWFLIP` twice, reading
16+16 bytes from `HL=$92C3` -- exactly `PATTERN_TAIL_92C3`'s full 32
bytes -- drawing them to VRAM with a "negated" variant (`CPL` before
each `OUT`), in columns shifted by `$18` (24 px) per extra life.

Assembling those 32 bytes in the real order the routine writes them
(2 8x8 tiles per write band, 2 bands -- NOT in the 2-bytes/row
interleaved order our `.til` format uses) produces a circle with a
notch at the top, the classic "life" icon:

```text
.....###.##.....
...#####.#..#...
..###..##..###..
.###.##.#######.
.###.#..#######.
#####..#########
###############.
##############.#
############..##
#######.....####
.##############.
.##############.
..############..
...##########...
.....######.....
................
```

Consistent with sitting in memory right next to
`EXTRALIFE_TEXT`/`EXTRA_TEXT` ("EN LA PROXIMA... EXTRA").

**Ruled-out lead**: the coincidence that `PATTERN_TAIL_92C3`'s
address range ($92C3-$92E3) also fits `TEXT_BLIT`'s real formula
(`$925B + code×8`) for codes $0D-$10 (a subset of
`FONT_CHARSET_5F2C`'s "24 special codes") is pure address-arithmetic
coincidence -- there's no caller in the transcribed code that invokes
`TEXT_BLIT` with those codes. The real, confirmed identity is the
life icon, not a font glyph.

**Verified**: recompiled all of `madmix1.asm` after fixing the
comment, 0 differences kept against `MADMIX1.BIN`.

**Extracted to a file**: `data/img/icono_vida.img` (32 bytes),
loaded with `INCBIN` under the `PATTERN_TAIL_92C3` label, following
the same convention as the rest of `data/img/` (candy frame, title
screen). Re-verified after extraction: 0 differences.

## Cleanup: most "TODO: unidentified" on jumps/CALLs were outdated comments, not real gaps

The developer asked whether the many "TODO: unidentified" notes next
to `CALL $XXXX`/`JP $XXXX` really reflected unresolved gaps. All were
reviewed one by one (checking against the compiler's real `--sym`,
not from memory) -- **most were outdated comments**: the target
already had a label and transcribed code elsewhere in the same file
(or in the other `.asm`), but the comment at the call site was never
updated when that identification happened.

**Confirmed as ALREADY IDENTIFIED (comment fixed)**:

| Address | Real identity | Call sites fixed |
| --- | --- | --- |
| `$881B` | `INSTALL_ISR` | `madmix1.asm` (JT_SLOT5, INIT) |
| `$8E3C` | `INPUT_READ` | `madmix1.asm` (JT_SLOT6) |
| `$8D70` | `SCORE_DRAW` | `madmix1.asm` (JT_SLOT7) |
| `$89AD` | `SCROLL_DISPATCH` | `madmix1.asm` (JT_SLOT8) |
| `$8C34` | `JT_SLOT9_TARGET` | `madmix1.asm` (JT_SLOT9) |
| `$8CEE` | `QUEUE_PUSH` (`madmix1.asm`) | `madmix_scr.asm` (2 instances, item handlers) |
| `$5782` | `ITEM_TIMER_TICK` | `madmix_scr.asm` |
| `$5278` | `HELPER_5278` | `madmix_scr.asm` (2 instances) |
| `$53A2` | `HELPER_53A2` | `madmix_scr.asm` (`ITEM_TIMER_TICK`) |
| `$511C` | `ITEM_TABLE_POS_511C` | `madmix_scr.asm` (`TABLE_INIT`) |
| `$5885` | `TABLE_INIT` | `madmix_scr.asm` (`LEVEL_LOADER`) -- the most flagrant case: the routine is defined 160 lines above, in the SAME file, and the comment still said "untranscribed" |
| `$5D0A` | `TAIL_JOY_READ` (`madmix_scr.asm`) | `madmix1.asm` (`INIT`) |
| `$6429` | `TAIL_LEVELCYCLE_HELPER2` (`madmix_scr.asm`) | `madmix1.asm` (`INIT`) |

**Two genuinely nameless cases, but NOT "unknown code"** -- they're
secondary entry points inside routines ALREADY fully transcribed,
verified with the real `--sym`:

- `$58F8` falls inside `TABLE_INIT` (`$5885`-`$5904`), exactly
  between labels `TI_2C10` and `TI_CLR2C2E` -- a second entry point
  that skips resetting the 3 item tables and goes straight to
  clearing `($2C10)/($2C1A)/($2C1B)/($2C0C)` and the `$2C2E` block.
  Same pattern as `HELPER_5278`/`HELPER_53A2` (two entries, one
  shared tail), only this second entry point hasn't been given its
  own name yet.
- `$5B56` falls inside the intro/demo-cycle trigger routine
  (`madmix_scr.asm`, the `TI_CONT` block over `$5B50`), also fully
  transcribed -- with no named entry point of its own.

**Verified**: both files recompiled after fixing all the comments
(text-only change, zero bytes), differences kept at 0 (`MADMIX1.BIN`)
and at the same already-known 4 bytes (`MADMIX.SCR`).

**Correction to an earlier note**: it had been noted here that
`$54A9`/`$55C0` (in `madmix_scr.asm`) were left unreviewed for
lacking a comment -- **error, they were already identified** from
before as `ITEM_HANDLER_1`/`ITEM_HANDLER_2` (with their own label and
transcribed code, line ~1833/1980), just not using the name at the 3
call sites (`$54A9`/`$55C0` at lines ~459/461, ~900/902, ~1098/1100).
They didn't need investigating, only cross-checking -- fixed right
here.

## RESOLVED: the two genuine cases, `$58F8` and `$5B56` -- not new code, exact addresses inside already-transcribed routines

Thoroughly investigated with the compiler's real listing (`--lst`,
the authority over any manual byte calculation):

**`$58F8`** = the `LD B,$03` instruction halfway through
`TABLE_INIT` (`$5885`, see above), right after the `TI_2C10` block
(which clears `($2C10)/($2C1A)/($2C1B)/($2C0C)`) and right at the
start of `TI_CLR2C2E` (which clears the 3 entries/6 bytes of the
`$2C2E` table). In other words: `CALL $58F8` runs **only** the
`$2C2E` block's cleanup and `RET` -- nothing else.

Its only caller in this form was also identified: `HANDLER_31B7`
(`madmix_scr.asm`), the 15th/16th entry of `ML_DISPATCH_TABLE` (the
per-tile-type dispatch table, 20 entries). Cross-checked against
`TILE_TYPES` (`madmix1.asm`) and the `data/tiles/` catalog: type 15 =
`suelo_sin_bola_1/2/3` (tiles 63/64/65) + `muro_ladrillo_suelto`
(tile 70); type 16 = `loseta_solida_negra` (tile 66). That handler's
`CP $08` branch resets a temporary special mode (restores
`($2C24)` from `($2C18)`, clears `($2C2D)`/`($2C0D)`) and sets
`$6128=$03` before calling `$58F8`.

**New lead for the pending sound task**: the `$2C2E` table is the
"active trapdoor/track positions" one (confirmed by
`TRAPDOOR_FLIP_TABLE`, which iterates it and sets `$6128=$04`, and
`GHOST_HINT_HANDLER` -- tank/plane track -- which reads it and sets
`$6128=$07`). Also see the special-item handlers (`$6128=$05`/
`$6128=$06`). **`$6128` gets a small, distinct value (3,4,5,6,7...)
from each of the game's special mechanics** -- a very strong
candidate for being the **sound-effect index to trigger**, exactly
what's needed for the pending task of splitting `RM_TABLE_C8DE` into
`.mus`/`.snd` and cross-checking it against the developer's 11-sound
catalog. Not yet confirmed (would require live-tracing what reads
`$6128` and when), but it's the most concrete lead so far for that
task.

**`$5B56`** = the `CALL $CF8B` instruction (`LOAD_RESOURCE_SLOT_EMPTY`,
already well known) halfway through `TI_CONT`, `TAIL_INTRO`'s shared
tail (the demo-mode/attract loop). `madmix1.asm` calls it directly
from `INIT_RESUME_8F54` (part of the game's real boot sequence) to
reuse that tail while skipping `TAIL_KEYWAIT_UP` and
`TAIL_LEVELCYCLE_HELPER2` (which don't apply when starting a real
game, only to the demo cycle). From there it runs, in order:
`LOAD_RESOURCE_SLOT_EMPTY`, `PATCH_OFF_10D8` (see below, RESOLVED),
`TAIL_VDP_CLEAR`, `TAIL_LEVELCYCLE_HELPER_ALT`, a `$01F4` (500)
countdown and `TAIL_KEYMENU_MAIN` -- **in other words, this
`CALL $5B56` is what shows the main menu when starting a real game**,
reusing the same code that also shows it after the demo mode times
out.

**Update -- they now have their own labels**: `$58F8` is now
`TI_2C2E_ENTRY` (the 2 `CALL`s in `madmix_scr.asm` already use the
symbolic name) and `$5B56` is now `TI_5B56` (declared in
`madmix_scr.asm`; the `CALL $5B56` in `madmix1.asm` stays numeric
since it's cross-file, but the comment now references the real
name). Verified 0 differences after the change.

## RESOLVED: INIT's "second `CALL $1000`" is literally `PORTADA_INIT` again

Also closing the "exact relationship between the block relocated at
`$1000` and `INIT`'s second `CALL $1000`" gap (`FLUJO_PROGRAMA.md`
§7): `madmix_scr.asm` has the label `PORTADA_INIT` right at the start
of the `PHASE $1000` zone (line 63), and its body starts with
`DI / CALL VDP_WAIT_READY / LD HL,$1800 / ...` -- **exactly** the
`"LD HL,$1800 + VRAM fill loop"` pattern already confirmed via a live
RAM dump in an earlier session for what's really at `$1000` at the
moment `INIT` (`madmix1.asm`) runs its own `CALL $1000`. In other
words: it isn't different code nor a naming coincidence -- `INIT`
literally invokes the SAME `PORTADA_INIT` routine that `RELOCATOR`
(`madmix0.asm`) and `LOAD.BIN` (tape, see the `.cas` finding) had
already run once right after the initial relocation/load.

In other words, the title screen gets drawn twice total during a real
game's boot: once by the loader (disk: `RELOCATOR`; tape: `LOAD.BIN`),
immediately after relocating/loading the block into `$1000`, and a
second time by the game engine itself (`INIT`, now with control fully
in `MADMIX1.BIN`'s hands) as part of its own boot sequence. The exact
reason for the redundancy (defensive hygiene after the BASIC/VDP
context changes between one call and the other, or just safely
repeating the effect) isn't confirmed and would need live tracing,
but the WHAT (same routine, same bytes, two invocations) no longer
admits doubt -- resolved by pure static analysis, cross-checking the
disassembly against the already-transcribed source code itself.

## RESOLVED: the self-modifiable byte `$10E4` -- didn't need openMSX, the answer was in the already-transcribed ISR

This was the one gap "parked for openMSX" that actually did NOT need
live tracing -- the two opcode hypotheses tried before (`$A2`="AND
D", `$E2`="JP PO,nn") started from the wrong question: they assumed
`$10E4` was **code** that needed disassembling. Reviewing the real
ISR (`ISR`, `$882A`, already 100% transcribed in `madmix1.asm`) for
the `INIT_MAIN_LOOP` diagram, it shows up right before exiting:

```asm
IN     A,($99)
LD     A,($10E4)     ; <- HERE
OUT    ($99),A
LD     A,$81
OUT    ($99),A
```

It's the standard VDP register-write pair (`OUT data` /
`OUT $80|regnum`, here `regnum=1`). In other words: **`$10E4` is
DATA, not an instruction** -- the ISR reads it and writes it back
into VDP register 1 **every VBLANK**. `PATCH_OFF_10D8`/
`PATCH_ON_10DE` don't apply the screen on/off directly: they only
leave the value (`$A2`/`$E2`) prepared, which the ISR itself really
applies, frame by frame, until the opposite gets patched in. The 8
bytes that follow in memory (`$10E5-$10EC`) are never executed nor
read as part of this mechanism -- they're simply whatever fills that
gap in the relocated block (an undisassembled tail, irrelevant here).

Fixed in `madmix_scr.asm` (comment on `PATCH_OFF_10D8`/
`PATCH_ON_10DE`) and in `madmix1.asm` (comment on the ISR's own
`LD A,($10E4)`). Verified 0 new differences.

## RESOLVED: `TI_BREAK` is a hidden INFINITE LIVES cheat (self-patch at `$909A`)

Investigating `TI_BREAK`'s secret combo (`CP $EB`/`CP C,$07`, the ESC
key on row 7 of the matrix during `TAIL_INTRO`'s demo cycle) to make
sense of `LD ($909A),A`: checking what's really at address `$909A`
in `madmix1.asm`'s real listing (`sjasmplus --lst`), it shows up
**in the middle of an instruction, not as a standalone variable** --
it's the literal operand byte of `SUB $01` inside `IML_9078` (the
"life lost" routine):

```asm
IML_9078:
    ...
    LD     HL,$2C27      ; $2C27 = remaining lives
    LD     A,(HL)
    SUB    $01             ; <- $909A is this instruction's "01" byte
    LD     (HL),A
    JP     NC,INIT_MAIN_LOOP   ; lives left -> continue
    CALL   $5B8C                ; no carry... GAME OVER
```

`TI_BREAK` does `XOR A / LD ($909A),A`, i.e. it writes a `$00` there
-- turning `SUB $01` into **`SUB $00`** at runtime. The result: the
lives subtraction becomes a no-op (the life count never drops, and
since `SUB $00` never sets carry, the GAME OVER branch can never fire
either). The border flicker (color `$06`, a 4-`HALT` wait, color
`$01`) is simply the visual confirmation the code has been accepted
-- after that, execution falls into `TI_CONT` and the game continues
completely normally into the main menu, with no other visible effect
besides the patch now applied.

**Confirmed by pure static analysis** (cross-reading the real listing
of both files), with no need for live tracing. Closes the last
pending gap in `FLUJO_PROGRAMA.md` §7 that didn't depend on openMSX.
Fixed in `madmix_scr.asm` (`TAIL_INTRO`/`TI_BREAK`'s comment, which
previously said, wrongly, "resets sound/screen") and in `madmix1.asm`
(comment on `IML_9078`'s own `SUB $01`). Verified 0 new differences
in both files.

**Verified**: both files recompiled after fixing the comments with
this precise identity, differences kept at 0 (`MADMIX1.BIN`) and at
the same already-known 4 bytes (`MADMIX.SCR`).

## RESOLVED: `$10D8`/`$10DE` (madmix_scr.asm) -- turn the screen off/on before and after redrawing

No longer unidentified low addresses. They're `PATCH_OFF_10D8`/
`PATCH_ON_10DE` (`madmix_scr.asm`, right after `VDP_WAIT_READY`/
`VDP_ENABLE_DISPLAY`): two nearly identical 6-byte mini-routines
that **self-modify** the byte at `$10E4` (part of a later
instruction, still undisassembled):

```text
PATCH_OFF_10D8: LD A,$A2 / LD ($10E4),A / RET
PATCH_ON_10DE:  LD A,$E2 / LD ($10E4),A / RET
```

`$A2` and `$E2` are exactly the same values `VDP_WAIT_READY`/
`VDP_ENABLE_DISPLAY` write into the VDP's **register 1** (TMS9918):
both enable 16K mode + interrupts, differing only in bit 6
(`BLANK`) -- `$A2` = screen off, `$E2` = screen on. In other words,
`PATCH_OFF_10D8`/`PATCH_ON_10DE` prepare, for a later deferred write,
whether that write is going to turn the screen off or on.

**Usage pattern, confirmed at all 3 call sites**: turn screen off →
redraw (credits, main menu, HUD) → turn screen on. Avoids seeing the
redraw process (flicker):

- `TAIL_INTRO`: turns off → `TAIL_CREDITS_DRAW` → turns on.
- `TI_CONT`/`TI_5B65`: turns off → clears the VDP + level cycle +
  draws the main menu → turns on → reads a key.
- `TAIL_CREDITS_MAIN` / `TAIL_LEVELCYCLE_HELPER_ALT`: turn on when
  done drawing / turn off when starting to redraw.

**Update -- resolved without needing openMSX**: `$10E4` isn't an
instruction, it's the DATA the `ISR` (`$882A`, `madmix1.asm`) reads
every VBLANK and rewrites into VDP register 1. See the "RESOLVED: the
self-modifiable byte `$10E4`" section above for the full breakdown.

**Verified**: both files recompiled, differences kept at 0
(`MADMIX1.BIN`) and at the same already-known 4 bytes
(`MADMIX.SCR`).

## Documented the sound driver's internal helpers (RM_C4CC-RM_C8C9)

Closing out the inventory's list of 89 candidates for "real function"
(`recursos/flujo_programa.html`): the last gaps were all internal
helpers of `LOAD_RESOURCE_SLOT_ALLOC`/`RM_C4F9` (the PSG player).
Identified and commented in `madmix1.asm`:

- **`RM_C88D`**: unsigned 8×16 multiplication (`HL = A*DE`, classic
  shift-and-add) -- a generic utility used to compute offsets
  (slot×size, etc.).
- **`RM_C8A2`**: unsigned 16/16 division (shift-and-subtract, 16
  iterations).
- **`RM_C8BC`**: a 16-bit word table lookup (`HL = table[A]`, 2-byte
  entries) -- the same routine serves both the note-duration table
  (`RM_TABLE_C8DE`, 96 words) and the command dispatch
  (`RM_TABLE_C99E`, 15 jumps): `LD HL,table / CALL RM_C8BC / JP (HL)`
  is a classic indexed jump.
- **`RM_C8C9`**: flushes the 11 register-shadow bytes
  (`$C9BE`-`$C9C8`) to the AY-3-8910 PSG's 11 real registers -- the
  player's final step every tick.
- **`RM_C82E`** (new finding): enables/disables the current channel's
  bit in `$C9C5` based on a boolean parameter. **`$C9C5` is at offset
  +7 relative to `$C9BE`** (the base `RM_C8C9` flushes to the ports)
  -- offset 7 is exactly the AY-3-8910's **register 7 (the mixer:
  enables tone/noise per channel)**. In other words, `RM_C82E` is the
  routine that turns a channel on/off in the PSG's mixer.
- **`RM_C699`/`RM_C6B1`/`RM_C6C9`**: relatch "target" parameters into
  "current" ones for the channel slot (or a fixed shared table at
  `$CA53` in `RM_C6C9`'s case) when starting a new note -- the exact
  meaning of each field is still undecoded (out of scope, same as the
  rest of the driver's "bytecode").

**Verified**: `madmix1.asm` recompiled, 0 differences kept.

## Documented `ML_DISPATCH_TABLE`'s 20 handlers -- full type↔tile↔mode catalog, and one important correction

Cross-checking `TILE_TYPES` (`madmix1.asm`) against `data/tiles/*.til`'s
visual catalog gave the exact type→tile→handler mapping (the dispatch
index IS the type value, with no offset, confirmed in the real code
that builds the table: `A=type; ADD A,A; HL=ML_DISPATCH_TABLE;
ADD A,L...`):

| Type | Tile(s) | Handler | Effect |
| --- | --- | --- | --- |
| 0 | normal wall/floor (0-44) + loose decorative variants | `HANDLER_2EB7` | no effect (default) |
| 1 | suelo_con_bola_1/2/3 | `HANDLER_2EC7` | normal ball: +1 point, +1 level-end counter |
| 2 | suelo_con_bola_clavada_1/2/3 | `HANDLER_2EFC` | "frees" the pinned ball (no points) |
| 3-6 | up/down/left/right arrow | `HANDLER_2F18`/`2F50`/`2F88`/`2FC0` | forces direction, +2 points, +1 counter |
| 7 | pista_tanque_vertical | `HANDLER_2FF8` | special mode `$2C2D=8` ("tank mode") |
| 8, 9 | linea_electrica_puerta_fantasmas_a/b | `HANDLER_2EB7` | no logic of its own (shares the default) |
| 10 | pista_avion_recto/remate_izq/remate_der | `HANDLER_3067` | special mode `$2C2D=9` ("plane mode") |
| 11 | item_suelo_sin_confirmar | `HANDLER_30F3` | exits special mode |
| 12 | item_bola_de_poder | `HANDLER_311B` | special mode `$2C2D=1`, +2 points, +1 counter |
| 13 | item_hipopotamo | `HANDLER_315D` | special mode `$2C2D=2` |
| 14 | item_herramienta | `HANDLER_318E` | special mode `$2C2D=3` |
| 15, 16 | suelo_sin_bola_*/muro_ladrillo_suelto/loseta_solida_negra | `HANDLER_31B7` | exits special mode (already documented above) |
| 17-19 | trapdoor-transition variants | `ML_3252`/`ML_3299`/`ML_32E2` | trapdoor-opening animation |

**"Special mode" catalog (`$2C2D`) confirmed**: 1=power ball,
2=hippo, 3=tool, 8=tank, 9=plane -- matches exactly the sprites and
sound catalog already known ("hippo mode", "at-work/ball-laying
mode", "plane mode").

**Important CORRECTION**: `HANDLER_3067` had been labeled in an
earlier session as `"type 9": candidate for "power ball eaten"`.
That's **wrong on both counts**: by its position in the dispatch
table it's the handler for **type 10** (not 9), and type 10 is the
**plane track** tiles (`pista_avion_recto`/`remate_izq`/`remate_der`),
not the power ball -- the real power ball is **type 12**, handled by
`HANDLER_311B`. `HANDLER_3067`'s 12-call loop isn't "make the ghosts
vulnerable": it sets `$2C2D=9` (plane mode) and walks 12 positions
calling `SCROLL_DISPATCH`/`R51FE_MAIN`/`ITEM_HANDLER_1`/
`ITEM_HANDLER_2`/`ITEM_TIMER_TICK` (and conditionally `ACTOR_ENGINE`)
-- probably re-synchronizing the item subsystem along the track when
entering plane mode, not decoded note by note in detail.

**Extra lead for the sound task**: this pass turns up more `$6128`
values (the "event marker", a candidate for the sound index): `0`
(normal ball), `3` (many special modes on activation), `9` (trapdoor
transition), `0B`=11 (power ball, at the end, overwriting the initial
`3`). That's quite a few distinct values for only 3 sound scripts --
reinforces the already-noted suspicion that several events share a
script with different entry points (see the `$CEF0`/`$CEF7`/`$CEFE`
finding above).

**Verified**: `madmix_scr.asm` recompiled, 0 new differences (the
same already-known 4 bytes).

## Tools used in the analysis session

- `mtools` (`mdir`/`mcopy`) to extract files from the `.dsk`
- `z80dasm` for linear disassembly (desyncs when crossing data zones
  -- every stretch needs visual verification)
- Python + Pillow to render byte blocks as bitmaps (16x16 with 2
  bytes/row, or 8x8 with 1 byte/row) and tell graphics apart from
  code/data by eye

## Function-documentation pass in `madmix_scr.asm` (parallel to the one already done in `madmix1.asm`)

At an explicit request to continue in `madmix_scr.asm` the same
function identification/documentation work already done in
`madmix1.asm`:

- **Sweep of the ~39 labels classified as "function"** (target of
  some `CALL`, see `FLUJO_PROGRAMA.md` §0's methodology): most
  already had their own header from an earlier pass. Only 5 lacked
  one (`HELPER_53A2`, `TAIL_VDP_CLEAR`, `TAIL_KEYWAIT_UP`,
  `TAIL_LEVELCYCLE_HELPER_ALT` turned out to already be covered by a
  neighboring label's comment -- a comment of its own was added
  anyway so each one is self-explanatory without having to look
  sideways) plus `ITEM_RNG` (already had a sufficient inline note).
- **Line-by-line documentation of the engine's preamble
  collision/movement** (`MAIN_LOOP`, `$2CA0`-`$2E9B`, before the
  `ML_DISPATCH_TABLE` dispatcher): the frame's valid-direction
  decision (real input vs. demo script), the "you can only turn if
  the position is tile-aligned" logic (mask `E` based on alignment on
  each axis), `CHECK_TILE_DELTA` with its per-column type cache, and
  the `IX` dispatch point.
- **New finding**: while a "special mode" is active (`($2C0F)!=0` --
  power ball, hippo, etc.), the normal per-tile-type dispatch gets
  **suspended** (type 0, "no effect", is forced) and instead the
  preamble itself manages the mode's countdown: decrements
  `($2C0E)`, blinks the HUD icon in the final instants (`($9147)` for
  mode 2/hippo, a fixed value pick for mode 1/power ball), and once
  it runs out empties the resource manager and clears
  `($2C0D)`/`($2C2D)`.
- Also documented the trapdoor loop (`ML_2DFA`-`ML_2E36`, 3 entries
  of the `$2C2E` table, two position sub-formats distinguished by
  bit 0/bit 7) and `CHECK_TILE_DELTA`/`DRAW_TILE_HELPER` line by
  line.
- **Also fixed an error in `mapa_memoria.html` along the way**: the
  `0x2CA0-0x335C` entry still said "16-entry dispatcher" and
  "type-9 handler = power ball" (both already corrected at the time
  to 20 entries / type 12, but never propagated to this file).
  Fixed.
- **Remaining scope** (not covered in this pass, to continue): the
  line-by-line detail of the dispatcher's 20 `HANDLER_*` (they
  already have header documentation with the type→tile→effect
  mapping from an earlier session, but not every internal jump
  commented one by one), and the `HELPER_5278`/`HELPER_5414`/
  `ITEM_HANDLER_1`/`ITEM_HANDLER_2` chain in the special-item
  subsystem.

Verified 0 new differences after each block of changes (recompiling
and comparing against the original `MADMIX.SCR`).

## Documented `ML_DISPATCH_TABLE`'s 20 `HANDLER_*` line by line -- confirms the "special-mode gate" pattern and fixes a comment carrying an incomplete reading

Continuing the same pass, with the tile-type dispatcher's 20 handlers
(they already had a header with the type→tile→effect mapping from an
earlier session, but not their internal jumps commented one by one).
Doing so revealed a very clear, well-confirmed pattern (every handler
checks the `A` variable right on entry, which in **every** case comes
from `LD A,($2C2D) ... JP (IX)` in `MAIN_LOOP`'s dispatcher -- i.e.
**`A` is always the current special mode at the moment any
`HANDLER_*` is entered**, not a parameter of the tile itself):

- **Normal ball (`HANDLER_2EC7`) and the 4 arrows
  (`HANDLER_2F18`-`2FC0`)**: only act if the current mode is `< 2`
  (none, or power ball) -- with hippo/tool/tank/plane active, balls
  can NOT be eaten nor do arrows force a direction.
- **Pinned ball (`HANDLER_2EFC`)**: unlike the previous ones, it only
  acts if the mode is EXACTLY 3 (tool) -- outside that mode, stepping
  on a pinned ball does nothing. **This is a new finding, it wasn't
  in the earlier comment**: the "tool" mode literally exists to free
  pinned balls (turns them into normal balls, subtracting 3 from the
  tile index: 48→45, 49→46, 50→47), matching the name.
- **Mode activation by pickup (`HANDLER_311B` power ball,
  `HANDLER_315D` hippo, `HANDLER_318E` tool)**: only act if the
  current mode is 0 -- modes are mutually exclusive, two can't be
  active at once.
- **Mode activation by track (`HANDLER_2FF8` tank type 7,
  `HANDLER_3067` plane type 10)**: if no mode is active, they turn it
  on (with a "debounce" flag in one of B's bits so it doesn't
  re-trigger every frame while still on the track); if the active
  mode is ALREADY theirs (8 or 9 respectively), instead of
  re-activating they just run the item/scroll refresh loop (12 steps
  along the track).
- **Mode exit by pickup (`HANDLER_30F3`, type 11)**: unlike the
  activation ones, only acts if a mode is ALREADY active -- restores
  color/flags and ends the current mode.
- **Mode exit by track (`HANDLER_31B7`, types 15/16)**: ends tank
  mode (`CP $08` branch) or plane mode (`CP $09` branch, with its own
  12-step loop running in reverse from the activation one).
- **Trapdoor transitions (`ML_3252`/`ML_3299`/`ML_32E2`, types
  17-19)**: don't check the special mode at all, only the movement
  phase -- they draw specific frames of the opening/closing
  animation.

Also documented along the way: `CHECK_TILE_DELTA`'s tile-type cache
gets manually updated in `HANDLER_2EC7` (to `$0F` = `suelo_sin_bola`,
the type matching the tile just "eaten") instead of being
invalidated.

Verified 0 new differences after each block of changes.

## Documented `R51FE_MAIN`/`HELPER_5278` (special-item subsystem) -- confirms it's the movement AI for one entity type, with "approach the target or go random" as the real algorithm

Continuing the same line-by-line documentation pass, this time over
`R51FE_MAIN` ($51FE, called from the main loop) and its helper
`HELPER_5278` ($5278). They already had a header from earlier
sessions, but not the internal detail.

**Confirmed algorithm** (`ITEM_TABLE_POS_511C` entities, 8 entries of
7 bytes: X, Y, own flag, current direction/animation, sub-X, sub-Y,
rotation phase):

1. Computes an "aim point" = camera + (16,24) mod 128, stored in
   `$2C1F`.
2. For each active entity: `HELPER_5278` decides whether it's in
   range (based on alignment with the aim point, with possible
   inversion if `($2C0D)` is active) and computes the desired
   **approach direction** toward that point (up/down if the column
   matches, left/right if the row matches).
3. Tests all 4 possible directions with `HELPER_5414` (already
   documented, "is there a free tile one step this way?") and builds
   a bitmask of the ones that ARE walkable.
4. If the desired direction is walkable, it's used (always if a
   special mode is active, otherwise with a 50% chance via
   `ITEM_RNG`); if it isn't (or the remaining 50% hits), it picks
   among ALL walkable ones using a 170-byte table (`$517E`) plus a
   random tie-breaking bit.
5. Applies the resulting movement to the entity's fractional position
   (sub-X/sub-Y), with step speed halved if the entity's own flag or
   the "inverted" special mode are active.

In other words: **it's a classic chase/patrol AI algorithm** ("try to
head toward the target, if you can't or by pure chance, move along
any free path"), applied to one of the game's entity families
(candidate: the 8-entry table fits the ghosts, though it hasn't been
cross-checked with full certainty against the ghost sprites --
`ACTOR_ENGINE` is what actually draws them using the direction/
animation computed here).

**Two details are left not fully resolved**, flagged as such in the
code itself rather than made up: the exact meaning of `(IX+2)`
(tested as an "active/frozen" binary flag but its full semantics
unconfirmed) and whether the direction code stored in `(IX+3)` after
going through table `$517E` uses the same 1/2/4/8 bitmask convention
as the rest of the subsystem or its own sequential one (the two code
paths that write it couldn't be fully reconciled with certainty).

Verified 0 new differences after each block of changes.

## Closed the special-item subsystem: `HELPER_5414`, `ITEM_HANDLER_1/2`, `GHOST_HINT_HANDLER`, `CLEAR_5773_AND_SET`, `ITEM_TIMER_TICK`, `ITEM_EFFECT`

Continuing the same line-by-line documentation pass. Two of my own
mistakes found and fixed along the way (see "Errors found" at the
end), and several new findings:

- **`HELPER_5414` confirms the subsystem's real direction
  convention**: `$01`/`$02`/`$04`/`$08` = right/left/down/up
  (verified directly from its `C+=4`/`DEC C`/`B+=4`/`DEC B`
  operations on the position). **This forced a fix to a comment I
  had myself written wrong in `HELPER_5278`** (I had mistakenly
  reused the dispatcher arrows' bit-index convention, which is a
  DIFFERENT, unrelated convention). It also confirms tile types 0
  (normal wall/floor), 7 (tank track), 8 (ghost-house door electric
  line) and 10 (plane track) are non-walkable for these items -- any
  other type is.
- **Big finding: `ITEM_HANDLER_1` and `ITEM_HANDLER_2` are a
  complementary pair managing "pinned" balls' lifecycle**:
  - `ITEM_HANDLER_1` looks for already-eaten ball gaps
    (`suelo_sin_bola`, indices 63-65) and **regenerates** them back
    into a normal ball (`suelo_con_bola`, 45-47) -- decrementing the
    level-end counter (`$2C08`) because there's now a pending ball
    again.
  - `ITEM_HANDLER_2` looks for uneaten normal balls (45-47) and
    **turns them into pinned balls** (48-50) -- without touching
    `$2C08` (planting a pinned ball doesn't change how many are left
    to eat, it just "freezes" it until freed with tool mode,
    `HANDLER_2EFC`).
  - Both use the same "planted item" mechanism via `HELPER_5278`
    (positioning) + `ACTOR_ENGINE` (drawing) + `(IX+2)` (stops
    recomputing direction once placed).
- **`GHOST_HINT_HANDLER`**: watches how close Pac-Man is to the
  active track/trapdoor positions (`$2C2E`, same format as
  `MAIN_LOOP`'s trapdoor loop) with an asymmetric margin wider than
  the tile itself -- a "hint" before actually stepping on it, which
  arms `CLEAR_5773_AND_SET` and marks event `$6128=7`.
- **`ITEM_EFFECT`**: dispatches based on the current special mode
  (`$2C2D`); mode 3 (tool) literally reuses the same code path as
  "no special mode" (`IE_57FD`), differing only in the chosen sound/
  timer parameters.

**My own errors found and fixed along the way** (both caught by the
discipline of recompiling+comparing after each block, not before
touching the binary):

1. A comment in `HELPER_5278` that assigned the wrong physical
   direction to the wrong value (`$01`/`$02`/`$04`/`$08`) -- fixed
   after verifying the real convention in `HELPER_5414`.
2. **Adding a comment in `HELPER_5414` accidentally deleted a real
   instruction (`AND A`)** in `H5414_545A` -- caught on the next
   recompile (expected 0 differences, came back with differences) and
   fixed immediately by adding the instruction back.

Verified 0 new differences after each block of changes (the same
already-known 4 bytes at all times).

## RESOLVED: `$6128` is the sound-effect index -- the 383-byte block split into 14 individual files, one per event

Picking back up the sound task pending for several sessions. Searching
for who calls the PSG player's "tick" entry point
(`$C4EB`, right before `RM_C4F9` in `madmix1.asm`, with no label of
its own until now), the missing piece turned up:

**`TAIL_LEVELCYCLE_HELPER`** (`$60DC`, `madmix_scr.asm`) -- confirmed
by the `ISR`'s own comment (`CALL $60DC`, run **every VBLANK**) --
does exactly this:

```asm
LD HL, $6128
LD A, (HL)
CP $FF
JR Z, TLH_END              ; $FF = "nothing pending"
LD (HL), $FF                 ; marks it as consumed
LD HL, LEVELCYCLE_RESOURCE_TABLE
... (indexes by A*3) ...
LD A, (HL) / LD E,(HL+1) / LD D,(HL+2)   ; [channel, ptr_lo, ptr_hi]
CALL $C4A0                     ; LOAD_RESOURCE_SLOT_ALLOC: installs the script
TLH_END:
CALL $C4EB                       ; PSG player tick (ALWAYS, every VBLANK)
```

In other words: **`$6128` is exactly the "sound-effect index to
trigger"** that had been suspected for a while -- any part of the
game that wants to play a sound writes its index into `$6128`, and
on the next VBLANK this routine picks it up, looks it up in
`LEVELCYCLE_RESOURCE_TABLE` (`$60FE`, 14 entries of 3 bytes) and
installs the corresponding script on a PSG channel.

**The full table** (`LEVELCYCLE_RESOURCE_TABLE`, `madmix_scr.asm`):

| `$6128` index | channel | pointer | triggered from | bytes | developer's catalog candidate |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | `$CEE2` | `HANDLER_2EC7` (eat normal ball) | 14 | #4 "ball-eating sound" |
| 1 | 0 | `$CE8B` | `HANDLER_2EFC` (free pinned ball, tool mode) | 17 | #7 "ball-laying sound" |
| 2 | 0 | `$CF62` | 4× `HANDLER_2Fxx` (arrows) | 14 | #10 "one-way tile" |
| 3 | 1 | `$CF70` | activate/exit special mode (tank/plane/tool/hippo) | 27 | generic "mode change" |
| 4 | 0 | `$CE72` | `TRAPDOOR_FLIP_TABLE` | 12 | #9 "Shot (plane mode)" -- **corrected**, see below |
| 5 | 1 | `$CF44` | `ITEM_HANDLER_1` (replenishes eaten ball) | 30 | #8 "replenish ball (ladybug)" |
| 6 | 1 | `$CEAC` | `ITEM_HANDLER_2` (plants pinned ball) | 54 | no direct match in the catalog |
| 7 | 1 | `$CE7E` | `GHOST_HINT_HANDLER` (track warning) + `ITEM_EFFECT` tails | 13 | candidate #9/#5 (ambiguous, two uses) |
| 8 | 0 | `$CF07` | `ITEM_EFFECT` (arms special-mode timer) | 32 | generic "activate mode" |
| 9 | 0 | `$CE5A` | `ML_3252`/`ML_3299` (trapdoor transition) | 24 | related to #11 |
| 10 (`$0A`) | 2 | `$CEF0` | **`IML_900F`** (direct call, not via `$6128`) | 23 | #2 "level-start jingle" |
| 11 (`$0B`) | 2 | `$CE9C` | `HANDLER_311B` (power ball, final event) | 16 | related to #1/#9 |
| 12 (`$0C`) | 0 | `$CDCB` | no write site found (reuses the music script) | -- | #1 "main music" |
| 13 (`$0D`) | 2 | `$CF27` | `ITEM_EFFECT` (final event after a special mode ends) | 29 | generic "mode end" |

**Key finding**: what had been treated for sessions as "a single
383-byte music script at `$CE0C`" turns out to be: the first 78
bytes (`$CE0C`-`$CE5A`) ARE indeed channel 2 of the boot music
(installed alongside `$CDCB`/`$CDFF` by `INIT`), but the rest are
**13 short, independent fragments**, each the sound effect for a
specific game event -- confirmed by cross-checking the real table
against every code site that writes `($6128)` (an exhaustive search
for `LD ($6128),A` in both files). The "pool of reusable fragments"
candidate already flagged in an earlier session (on finding
`$CEF0`/`$CEF7`/`$CEFE` fell inside "script 2") is thus fully
confirmed.

**Cross-check against the developer's 11-sound catalog**: several
match with high confidence -- `$6128=0` (eat ball) with "#4 ball-
eating sound"; `$6128=5` (`ITEM_HANDLER_1`) with "#8 replenish ball
(ladybug)" -- also confirmed by cross-checking the item's animation
frame (`$27`=39 decimal=sprite `39_mariquita_der`); `$6128=10`/
`IML_900F` with "#2 level-start jingle" (it literally fires when
"READY?" appears). Others (`6`, `7`, `8`, `13`) have no clear, direct
match in the list of 11 -- left marked as "generic"/weak candidate
instead of forcing a label, honoring the no-overclaiming principle.

**Later correction (real-listening session): `$6128=4` is NOT
"enable trapdoor", it's "Shot (plane mode)" (#9)**. The first
hypothesis rested only on `TRAPDOOR_FLIP_TABLE`'s name and on it
writing to the trapdoor table. Listening to
`04_evt04_trampilla_ce72.wav` (rendered by `mmsnd_render.py`), the
developer -- the game's original player -- identified by ear that
it's "the shooting sound", not a trapdoor. Verified in the code:
`TRAPDOOR_FLIP_TABLE` gets called both from the tank/trapdoor path
and from `HANDLER_3067` (plane mode's handler) -- meaning it's a
generic "flip a position marker in `$2C2E`" routine reused by both
mechanisms, not exclusive to trapdoors. Files renamed to
`04_evt04_disparo_avion_ce72.snd`/`.txt`; updated the label/INCBIN in
`madmix1.asm` and `mmsnd_render.py`'s `SCRIPT_ADDR` manifest.
Recompiled and verified: 0 new diffs against `MADMIX1.BIN`.

**Work done** (per the developer's explicit request: "just split
into .snd files, don't decipher the bytecode" -- no attempt was made
to decode the 15-command language or the instrument tables, see
below):

- The 14 segments were extracted into individual files under
  `data/sound/02_boot_ch2_ce0c.snd` through
  `15_evt03_modo_especial_cf70.snd`, named by address + event index +
  catalog candidate wherever the match is solid (the old monolithic
  `02_script_ce0c.snd` was removed).
- `madmix1.asm`: the single `SOUND_SCRIPT_2_CE0C` label was replaced
  with 14 labels (`SOUND_BOOT_CH2_CE0C` + `SOUND_EVT00_CEE2` ...
  `SOUND_EVT13_CF27`), each with its own `INCBIN`. `IML_900F`'s 3
  calls (which used `SOUND_SCRIPT_2_CE0C+$E4/+$EB/+$F2`) were updated
  to use `SOUND_EVT10_CEF0`/`+7`/`+14` directly, and the boot install
  in `INIT` to use `SOUND_BOOT_CH2_CE0C`.
- Verified: recompiled, **0 differences** against the original
  `MADMIX1.BIN` (a purely organizational source change, no compiled
  byte differs).

**Out of scope for this pass, explicitly left pending**: the
bytecode language itself (15 commands via the jump table at `$C99E`,
plus a second table of ~20 pointers to "instrument/envelope
programs" using the same language, at roughly `$CA76`-`$CDAB`)
hasn't been decoded -- each `.snd` file is still raw bytes, not yet
editable as text. There's no period tool that understands this
format (it's Topo Soft's own driver, "MUSIC-A BY: COMILONAS", not a
known public format) -- if this thread is picked back up, the
realistic path is decoding the full bytecode and building a custom
compiler/decompiler to a plain-text format.

## RESOLVED: the sound driver bytecode's 15 commands, deciphered one by one

At an explicit request from the developer ("let's do it"), the part
left out of scope was picked back up. Manual, instruction-by-
instruction disassembly of the 15 routines in the `$C99E` jump table
-- each target address was verified by computing the exact byte
offset from the nearest known routine/label (assuming nothing),
confirming each block ends exactly where the next one should start
according to the pointer table itself. All 15 fit with no gap or
overlap.

### The playback loop, per tick

`RM_PLAYER_TICK_C4EB` (called every VBLANK) walks the 3 channel
slots. For each one, the first thing it checks is **`(IX+$04)/(IX+$05)`
-- the current note's remaining tick count**:

- If it's **nonzero**: the note is still playing -- it just
  decrements the counter (`RM_C564`) and applies the volume/pitch
  envelopes (see below), without touching the script.
- If it's **zero**: the previous note ended -- it re-enables the
  channel in the mixer (`RM_C82E` with `A=0`), retrieves the current
  read pointer (`(IX+$02)/(IX+$03)`) and enters `RM_518`: a **loop
  that processes command bytes (`>=$80`) one after another, all in
  the SAME tick**, until it finds a byte `<$80`, which breaks it out
  of the loop.

In other words: commands are "instantaneous" (all run at once at the
start of a note).

**IMPORTANT CORRECTION (found while building the audio renderer, see
below) -- the byte `<$80` is NOT a duration, it's the NOTE**:
`RM_C527` adds it to a per-channel transposition value (`$CA67`+
channel, via `RM_C882`) and uses that sum as an index into the
96-word table `$C8DE` -- and that table, seen with this new context,
contains exactly the progression of values you'd expect from a
**PSG tone period** (decreasing and flattening out as the "note"
rises, the classic chromatic-scale pattern). The result is stored in
`(IX+$0A/$0B)` -- in other words, `$C8DE` is a **note→tone-period
table**, not a duration one. The real duration in ticks lives
elsewhere (`(IX+$06/$07)`, set by commands 3/6) and gets reloaded
into `(IX+$04/$05)` every time a new note is processed (`RM_C552`).
This also forces a correction to command 0's name (see the table)
and to what `(IX+$09)`/`(IX+$2A)` hold.

### Channel record structure (offsets within the 46-byte slot)

| Offset | Content |
| --- | --- |
| `+$00/+$01` | ORIGINAL script pointer (for the loop command) |
| `+$02/+$03` | current READ script pointer |
| `+$04/+$05` | remaining tick count for the current note |
| `+$06/+$07` | duration in ticks (set by commands 3/6, copied into `+$04/+$05` when a new note is processed) |
| `+$08` | mixer mask (tone/noise) for `RM_C82E` |
| `+$09` | base volume (command 0) |
| `+$0A/+$0B` | BASE tone period, already resolved (note + channel transposition, via table `$C8DE`) |
| `+$2A` | VOLUME ENVELOPE accumulator (added to the base volume when writing the PSG's volume register) |
| `+$2B/+$2C` | PITCH ENVELOPE/SLIDE accumulator (16-bit, added to the base period when writing the tone register) |
| `+$2D` | assorted flags (bits tested by `RM_C5A7`/`RM_C612` to decide whether to "relatch" a companion channel) |

### The 15 commands (command byte = `$80` + number)

| # | Byte | Address | Params | Mechanical effect | Proposed name |
| --- | --- | --- | --- | --- | --- |
| 0 | `$80` | `$C6E5` | 1 byte | Stores it as-is in `(IX+$09)` (base volume) | **SET_VOLUME** (previously wrongly called SET_NOTE) |
| 1 | `$81` | `$C703` | 1 byte | `AND $09`, stores in `(IX+$08)` (mixer mask) | **SET_MIXER** |
| 2 | `$82` | `$C765` | 0 | Reloads `BC`/`(IX+$02-03)` from `(IX+$00-01)` (goes back to the start of the script) | **LOOP** |
| 3 | `$83` | `$C6EE` | 1 byte | Multiplies it by `($C9BD)` (via `RM_C88D`) and stores in `(IX+$06-07)` (duration in ticks) | **SET_DURATION** |
| 4 | `$84` | `$C761` | 0 | Jumps directly to `RM_C552` (note closing) without going through duration | **HOLD/TIE** (repeats the previous duration) |
| 5 | `$85` | `$C733` | 1 byte | Multiplies it by `$0010`, divides `$0BB8` by that value (via `RM_C8A2`) and stores the QUOTIENT in `($C9BD)` (verified: `RM_C8A2` returns the quotient in BC, remainder in HL; the handler does `LD A,C` after the division) | **SET_TEMPO/SPEED** (recomputes the multiplier command 3 uses) |
| 6 | `$86` | `$C774` | N bytes (until a counter in A runs out) | Repeatedly adds `($C9BD)` to an accumulator and stores in `(IX+$06-07)` (duration in ticks) | **SET_DURATION_MULTI** (cumulative variant of 3) |
| 7 | `$87` | `$C7AB` | 1 byte | `RES 0/1,(IX+$2D)`, copies 15 bytes from a table (`$CA6A`+index) into `(IX+$16..)`, and zeroes `(IX+$0C/$0D/$10/$11/$12/$2A/$2B/$2C)` | **SET_INSTRUMENT** (loads an instrument's volume/pitch envelope parameters and resets the accumulators) |
| 8 | `$88` | `$C74D` | 1 byte | `AND $1F`, stores in `($CA5E)`, calls `RM_C6C9` (relatches the fixed envelope table) | **SET_ENVELOPE** |
| 9 | `$89` | `$C7F4` | 1 byte | Copies 6 bytes from a table (`$CB5A`+index) into the fixed table `$CA53+4`, resets `($CA5F)` and syncs `($CA60)` with the current channel | **SET_ENVELOPE_SHAPE** (a variant that also sets a percussion-shape table) |
| 10 | `$8A` | `$C797` | 1 byte | `OR`s it with `(IX+$2D)` and with `($CA5D)` (global flags) | **SET_FLAGS** |
| 11 | `$8B` | `$C70E` | 0 | If `($C9BC)` (current channel) matches `($CA60)` (the channel that "owns" the fixed table), clears it entirely (10 bytes) | **RESET_SHARED_ENVELOPE** (only acts if you're the owning channel) |
| 12 | `$8C` | `$C84B` | 1 byte | Saves `BC` into a per-channel table (`$CA61`+channel), looks it up in a 2-byte/entry table (`$CB72`) and the result goes into `BC` | **CALL_SUBPATTERN** (saves the return address, jumps to an indexed pattern) |
| 13 | `$8D` | `$C867` | 0 | Restores `BC` from the `$CA61`+channel table (no parameter) | **RETURN_SUBPATTERN** (counterpart of 12: returns from the pattern) |
| 14 | `$8E` | `$C878` | 1 byte | Writes the byte as-is into `(HL)`, with `HL` pointing at the channel's state entry (`$CA67`+channel, via `RM_C882`) | **SET_CHANNEL_STATE** |

**Confidence**: the mechanics (which bytes it reads, which fields it
touches, which table it indexes) are 100% verified -- it comes
directly from reading the
real instructions, not from guessing. The **names** are reasoned
interpretation based on that mechanics and context, not live
verification -- commands 6, 9, 10 and 12/13 (patterns/subroutines)
in particular are the most speculative part. The note↔duration mix-
up from the first pass (command 0 and the byte `<$80`) was caught
and fixed while trying to build the audio renderer: as soon as an
attempt was made to CONSUME these values to actually synthesize
sound, the inconsistency (a "duration" value feeding directly into
the PSG's tone register) became obvious.

**Still undecoded**: the instrument tables themselves (~20 pointers
at roughly `$CA76` to programs written in this same language,
interpreted as "instrument" instead of "channel"), and the precise
meaning of each 96/170/etc.-byte table these commands index
(duration, envelope, percussion shape). There's still no compatible
period tool -- any editor would have to be a new tool built from this
grammar.

## Built `tools/mmsnd_tool.py` -- the sound bytecode disassembler/assembler, with roundtrip verification across the 16 real files

At an explicit request from the developer ("build the format and the
compiler/decompiler"), with the 15 commands already deciphered: wrote
a Python script (`src/tools/mmsnd_tool.py`, no external dependencies)
with:

- `disasm file.snd [file.txt]`: dumps the binary to plain text, one
  mnemonic per line (`SET_NOTE 0x0E`, `DUR 0x18`,
  `SET_DURATION_MULTI 0x03 0x11 0x22 0x33` for the variable-length
  command, etc.), with `;` for comments.
- `asm file.txt [file.snd]`: the reverse conversion.
- `roundtrip`/`roundtrip-all`: verifies that `disasm`+`asm` reproduces
  the original binary byte for byte -- **the proof itself that the
  bytecode deciphering is correct**: if a command had the wrong
  parameter count, the file wouldn't add up correctly at the end
  (would be caught as truncation or extra bytes) or an invalid
  command byte would get decoded mid-file.

**Verified: the 16 real `.snd` files (the 3 music ones + the 13
effects) roundtrip exactly, with no exception** -- each one cleanly
decomposes into valid instructions down to the last byte, with no
truncation or unknown command. Since each file's boundaries were
obtained completely independently (by cross-checking
`LEVELCYCLE_RESOURCE_TABLE`, not by analyzing the bytecode itself),
this result is further strong confirmation that the 15 commands'
mechanics are well understood. The variable-length command (6,
`SET_DURATION_MULTI`) doesn't appear in any real file, so it was
verified separately with a synthetic case
(`SET_DURATION_MULTI 0x03 0x11 0x22 0x33`) -- also an exact
roundtrip.

A twin `.txt` (same name, `.txt` extension) was generated for each of
the 16 `.snd` files in `data/sound/` -- that's now the file that gets
hand-edited; the workflow to modify a sound is: edit the `.txt`, run
`py tools/mmsnd_tool.py asm file.txt file.snd` to regenerate the
binary, and recompile the game normally (the `.asm` still `INCBIN`s
the `.snd`, not the `.txt`).

**⚠️ WARNING -- a real limit on what can be edited** (caught by the
developer, not something I'd thought to check): each `.snd` compiles
to a FIXED address, matching the original binary exactly. Changing
an **existing** instruction's **value** (a different note/duration/
instrument) is safe. **Adding or removing instructions, or changing
a `SET_DURATION_MULTI`'s count, is NOT** -- if the file's total byte
count changes, everything after it in `madmix1.asm` shifts address,
and `LEVELCYCLE_RESOURCE_TABLE` (`madmix_scr.asm`) is left pointing
at the OLD address: the game would compile with no error at all but
jump to the wrong places at runtime (silent corruption, not a
compile failure). `mmsnd_tool.py` itself prints this same warning at
the top of every `.txt` it generates, and it's also in `README.md`.
A possible mitigation, not implemented (an explicit decision to
document instead of touching code): rewrite
`LEVELCYCLE_RESOURCE_TABLE` with symbolic references (`DW
SOUND_EVT00_CEE2`) instead of raw bytes, so that specific table would
self-update -- it wouldn't fix the rest of the fixed numeric
addresses further down in the file.

## Built `tools/mmsnd_render.py` -- a WAV renderer, and two important corrections found while building it

At an explicit request from the developer ("can you make another
tool that plays those sounds?"). Building a real renderer (not just
splitting/recombining bytes) forces you to CONSUME each value's
meaning, not just know how many bytes it takes -- and that brought
two real errors from the earlier pass to light, plus a piece that
was missing entirely.

### Correction 1: the byte `<0x80` is the NOTE, not the duration

While trying to feed the synthesizer "duration", I found that value
was being used to index the PSG's TONE register directly -- it made
no sense as a duration. Retracing `RM_C527`: the byte is added to a
per-channel transposition value (`$CA67`, 3 bytes, one per channel --
verified in the original binary: all 3 are `$00`, no transposition)
and the result indexes the 96-word table `$C8DE`, whose values (seen
now in this light) are exactly a progression of decreasing PSG tone
periods -- a chromatic scale. The real duration lives in a different
field (`+$06/+$07` of the channel record, set by commands 3/6). This
forced renaming command 0 (previously `SET_NOTE`, now `SET_VOLUME`
-- it really does set the base volume) and the tool's `DUR` mnemonic
to `NOTE`. Fixed in `mmsnd_tool.py`, `FINDINGS.md` and the 16
regenerated `.txt` files (verified exact roundtrip again after the
rename, which doesn't affect the bytes).

### Correction 2: `RM_C82E`'s polarity was backwards

Documented in an earlier session as "A=0 enables, A!=0 disables".
Carefully retracing the bit algebra (`CPL`, `OR`, `AND` over the PSG
register 7 shadow) to be able to decide whether a channel sounds or
not: it's BACKWARDS -- **a bit set to 1 in A ENABLES** that generator
(bit0=tone, bit3=noise), a bit at 0 leaves it silenced. Makes sense
with the rest of the code: `RM_C4F9` does `XOR A` (everything to 0,
briefly silences, avoids clicks) before processing a new note's
commands, and `RM_C53A` calls again with the real value set by
`SET_MIXER` to leave the final audible state. Fixed the comment in
`madmix1.asm` (verified 0 differences, it's just a comment).

### The missing piece: shared "subpatterns"

Commands 12/13 (`CALL_SUBPATTERN`/`RETURN_SUBPATTERN`) weren't just a
curiosity -- **the real music on the 3 boot channels uses them
constantly** (17-20 times per music script, no call to
`RETURN_SUBPATTERN` in the 16 files -- they live at the end of each
subpattern, outside the already-extracted files). Located with the
`$CB72` pointer table (**21 entries, not 20** -- corrected after
labeling the zone byte by byte in `madmix1.asm`, see below; entries
13-20 repeat the same pointer, the first subpattern's): 13 unique
subpatterns at `$CB9C`-`$CDAB` (right before `$CDCB`, the first
script). Extracted together with the rest of the auxiliary tables
(transposition `$CA67`, instruments `$CA6A` -- 16 of 15 bytes each --,
envelope shapes `$CB5A` -- 4 of 6 bytes --) into a single file
`data/sound/_engine_tables.bin` (1261 bytes, the full `$C8DE`-`$CDCB`
-- the same zone that still lives as inline `DB` in `madmix1.asm`,
here only so the renderer has real data). **The 13 subpatterns also
pass `mmsnd_tool.py`'s exact roundtrip** (including checking that
they end in `RETURN_SUBPATTERN`) -- further confirmation the
bytecode model is correct.

### The renderer (`tools/mmsnd_render.py`)

Emulates: a square-wave tone generator + a noise generator
(simplified LFSR, not verified against the AY-3-8910's real
polynomial) + a mixer (with the polarity already corrected) + a
16-step logarithmic volume table (AY-3-8910 standard values).
Interprets the bytecode tick by tick just like
`RM_PLAYER_TICK_C4EB`, including `SET_TEMPO`/`SET_DURATION` (with
`RM_C8A2`'s division correctly oriented: quotient, not remainder --
another detail that came out wrong the first time and got fixed
after seeing the first test produce a 128-second note instead of a
fraction of a second).

`py mmsnd_render.py render file.snd output.wav` / `render-all
folder/ output_folder/`. All 16 sounds are already rendered in
`build/sound_preview/*.wav` to listen to.

**Honest limit of this pass, unresolved**: the volume envelopes (2
phases) and pitch/slide envelopes (3 phases) are modeled in a
simplified way -- the reload mechanics are traced (which fields get
copied from where), but the fine detail of how they combine with the
accumulator hasn't been verified by listening against the real game.
The noise generator also isn't a certified emulation of the chip's
real LFSR. In other words: the result is a **reasoned
reconstruction, not a certified emulation** -- good enough to judge
by ear whether the bytecode reading makes musical sense (rhythm,
which note, when it's silent), not as a perfect timbre reference.
Without a listening session from the developer against the real game
(or against the `.cas`/`.dsk` in openMSX) this can't be tuned any
further.

### The developer's listening session -- first round of corrections

First result, with the 16 `.wav` files already in
`build/sound_preview/`: `14_evt02_flecha_cf62.wav` and
`15_evt03_modo_especial_cf70.wav` "perfect" on the first try (both are
the simple case: pure tone, no `CALL_SUBPATTERN`, no
`SET_ENVELOPE_SHAPE`); `13_evt05_mariquita_repone_cf44.wav` "almost
perfect, recognizable but too fast, like it's missing the ending
part"; `10_evt10_inicio_nivel_cef0.wav` unrecognizable ("is it slow?
is something wrong with it?").

Investigating the ladybug case turned up a **real bug in the
instrument field mapping** (the 15 bytes per instrument, table
`$CA6A`): I had mixed up which byte is the "delay between steps" and
which is "how many repetitions" for each phase of the volume
envelope. Retracing bit by bit against `RM_C699`/`RM_C6B1` (the
"relatch" routine that copies these instrument values into the live
counters when each note starts), the real mapping of the 15 bytes
is:

```text
b[0]/b[1]   = phase1/phase2 repeat count, volume
b[2..4]     = phase1/2/3 repeat count, pitch
b[5]/b[6]   = phase1/phase2 delta, volume
b[7..9]     = phase1/2/3 delta (SIGNED), pitch
b[10]/b[11] = delay between steps, phase1/phase2, volume
b[12..14]   = delay between steps, phase1/2/3, pitch
```

Each phase is processed in order (1, then 2, [then 3 for pitch]),
stopping at the first one still "active" -- it only moves to the
next phase once the current one exhausts BOTH its delay and its
repeat count. Fixed in `mmsnd_render.py` (`load_instrument`/
`relatch_envelopes`/`apply_envelopes`, signed 16-bit for the pitch
accumulator, unsigned for the volume one).

A 1-tick-per-note timing mismatch was also fixed: in the original,
`RM_C552` (relatch when a note starts) falls straight into `RM_C564`
(decrement counter + apply one envelope step) **with no jump in
between** -- the first tick of every note already counts and applies
a step, it doesn't wait for the next tick. The renderer wasn't doing
that; fixed.

**The `10_evt10_inicio_nivel_cef0` case** has a different
explanation, not a renderer bug: `IML_900F` (madmix1.asm) installs
this same data block on all 3 channels SIMULTANEOUSLY, each starting
7 bytes further in (offsets 0/+7/+14) -- it's a 3-voice chord, not a
single-voice melody. Rendering only channel 0 in isolation (what
`render` does today) necessarily sounds incomplete/unrecognizable by
design, not from a modeling error. Pending: add a multichannel render
mode that mixes the 3 voices for this specific case (and for the
boot music, which could also sound better with the 3 `00`/`01`/`02`
channels mixed instead of each one separately).

Verified after the fix: all 16 `.wav` files regenerate with no
errors (`render-all`), generally slightly shorter durations (the
timing fix removes 1 tick per note).

### Second round: `render-chord` for the level-start jingle

The developer confirmed "very good direction, everything much
better" and that `10_evt10_inicio_nivel_cef0.wav` is now recognizable
as the start-of-level music, but "some notes seem slow and long".
This fits exactly with the previous round's diagnosis: treating this
file as ONE linear channel, the renderer plays voice 1 (offset 0,
`CALL_SUBPATTERN 0x0B`) and, instead of stopping where it should,
keeps reading into voice 2's chunk (offset +7, which **repeats the
same 0x0B subpattern**) and then voice 3's (offset +14) -- everything
concatenated into a single voice, instead of the 3 sounding AT ONCE
like `IML_900F` really does.

Added `render_chord()`/`render-chord` to `mmsnd_render.py`: creates N
"voices" (each with its own `Channel` + its own tone/noise
oscillator) starting at different offsets WITHIN the same file, each
with its own "natural end" limit (the next offset, or the end of the
file for the last one), advances them in parallel tick by tick and
mixes their output (with amplitude headroom between voices to avoid
clipping). `render()` (single voice) was rewritten as a special case
of the same machinery (`Voice`/`synth_tick`), with no behavior
change -- verified with no regression across the 16 existing `.wav`
files (same durations as before the refactor).

`py tools/mmsnd_render.py render-chord data/sound/10_evt10_inicio_nivel_cef0.snd output.wav 0,7,14`
-- result: 1.70 s (before, as a single voice, between 4.80 s and the
8 s safety cap, dragging along the subpattern's spurious repeat).
Generated at `build/sound_preview/10_evt10_inicio_nivel_ACORDE.wav`,
pending the developer listening to it.

**Note for the future**: the boot music (`00`/`01`/`02`) is 3
SEPARATE files (not offsets within one), so they don't fit
`render_chord` as-is -- if that music should be heard with the 3
channels mixed, a variant taking 3 file paths instead of 3 offsets
would be needed (not implemented yet, same principle).

### Third round: `04_evt04` renamed to "shot (plane mode)", and the ladybug's "last note", investigated tick by tick

The developer identified `04_evt04_trampilla_ce72.wav` by ear as "the
shooting sound" (#9), not a trapdoor -- confirmed in the code that
`TRAPDOOR_FLIP_TABLE` (the routine that writes `$6128=4`) gets called
both from the tank/trapdoor path and from `HANDLER_3067` (plane
mode), confirming it's a generic routine reused by both, not
exclusive to trapdoors. Renamed to
`04_evt04_disparo_avion_ce72.snd`/`.txt` (label/INCBIN in
`madmix1.asm` and `mmsnd_render.py`'s `SCRIPT_ADDR` manifest
updated); recompiled and verified: 0 new diffs.

Afterward, the developer insisted `13_evt05_mariquita_repone_cf44.wav`
"is missing the last note, or it's so fast it can't even be heard"
(after the first round's envelope fix). `Interpreter`/`Channel` were
instrumented with a tick-by-tick dump (full state: `read_ptr`,
`ticks_left`, `vol_accum`, effective volume) to see exactly what
happens, instead of guessing. Result, verified sample by sample
against the real WAV:

- The file (30 bytes, verified exact against the original binary, 0
  diffs) uses **instrument `$0C`** for notes
  `0x30 0x30 0x28 0x34 0x30 0x2C` with base volume `0x09`
  (`SET_VOLUME`).
- Instrument `$0C`: `01 0E 00 00 00 07 FF 00 00 00 00 01 00 00 00` --
  volume repeat counts `[1,14]`, volume delta `[7,-1]`, volume
  reload delay `[0,1]` (no pitch at all: everything zero).
- Starting ANY note with this instrument: volume phase 1 has delay 0,
  so it applies on the very first tick (`vol_accum` goes from 0 to 7
  on the same tick the note starts). With base volume 9, `9+7=16`,
  and the PSG's volume register is 4 bits (`AND $0F` at `$C61D`,
  verified byte for byte against the original) -- **16 wraps back to
  0: silence**. The first 2 ticks (40 ms) of EVERY note using this
  instrument are silent by design; from the 3rd tick on, phase 2 does
  `vol_accum -= 1` per step, leaving the note sounding loud (effective
  volume 15, then 14...).
- For the last note (`NOTE 0x2C`, `SET_DURATION 0x05` = 5 ticks):
  ticks 1-2 silent, ticks 3-5 audible and loud (same pattern as the
  earlier notes of duration 4 and 7) -- the generated WAV does contain
  those 3 final loud ticks (confirmed by inspecting the `.wav`'s
  samples, max amplitude ~251/255, same as the earlier notes). There's
  no premature cutoff or dropped tick in the renderer.
- In other words: **the mechanics match the real code exactly**
  (retraced instruction by instruction); it's neither a bytecode
  transcription error (the bytes are exact) nor a new renderer bug.
  What makes the last note sound "almost inaudible" is that, with
  `SET_DURATION 0x05`, only 3 of those 5 ticks (60 ms) are really
  audible after the 40 ms "silent attack" this specific instrument
  always imposes -- the shortest note in the whole file, ending
  abruptly (no decay) right as the script runs out.

**Unresolved / needs the developer's ear to decide the next step**:
there's no evidence of an error in the model or the data -- if this
still sounds "wrong" compared to the real game, the remaining
hypotheses are (a) it also sounds this way in the original game (a
very brief closing "click", maybe intentional) and the renderer is
already faithful, or (b) on real hardware, this channel, on reaching
the script's end, keeps reading into contiguous memory (the next
fragment, `14_evt02_flecha_cf62.snd`, starts right at `$CF62`)
instead of cleanly stopping like our "natural end" heuristic
(`Channel.script_end`) does -- meaning the real note could have an
audible tail our isolation cuts off. (a) and (b) can't be told apart
without comparing against the game actually running (openMSX), so
it's left parked with the rest of the checks that need an ear/
emulator.

### Fourth round: two real bugs found and fixed in mmsnd_render.py, and two cases that aren't bugs

The developer reported in quick succession: 05_evt07_pista_ce7e.wav
"doesn't play", 07_evt11_bola_poder_ce9c.wav "doesn't either",
02_boot_ch2_ce0c.wav "I don't hear anything here, at most a little
noise at the end", and separately confirmed that
00_script_cdcb.wav/01_script_cdff.wav are "the start of the title
song"/"the intro drums" (a correct identification, not a bug).

**Real bug #1 -- too-coarse volume table (VOLUME_TABLE)**: the table
in use (0,0,0,0,0,0,0,1,1,2,3,4,6,8,11,16, scaled to 0-255) rounded
volume levels 1 through 6 down to 0, silencing notes that DO sound on
real hardware (if quiet). This was exactly
07_evt11_bola_poder_ce9c.snd's case: it uses SET_VOLUME 0x06, with no
envelope moving it -- a constant effective volume of 6, which with the
old table gave amplitude 0 (total silence) in an infinite loop
(LOOP) that also happened to hit the 300-tick safety cap without ever
sounding. Fixed by replacing the table with the AY-3-8910's standard
volume-generator curve (3dB per step, level = 2 raised to
((n-15)/2)): level 0 is still real silence, but 1-15 never round down
to 0 anymore. Verified: the regenerated wav no longer has any silent
samples.

**Real bug #2 -- constant negative DC offset during real silence
(synth_tick)**: when neither tone nor noise is active (mixer mask at
0, real channel silence), the code was still subtracting half the
volume (correct centering for a square wave, but ONLY when something
is sounding) using the channel's BASE volume even though nothing was
playing -- leaving a constant negative DC level instead of true
silence (128 in the 8-bit wav). With a high base volume and a long
silent stretch (see below, 02_boot_ch2_ce0c.wav has about 11.5s of
real silence at the start) this was heard as background noise/hum
instead of silence, exactly what the developer described ("a little
noise"). Fixed: real silence now writes a zero sample without
touching the volume. Verified sample by sample: the first 11.52s of
02_boot_ch2_ce0c.wav are now exact silence, not the old offset.

**02_boot_ch2_ce0c.snd (boot music channel 2) -- not a bug, it's a
real ~11.5s silent prelude, verified tick by tick**: the script
starts with SET_VOLUME 0x0E, SET_DURATION 0xC0 (192 ticks) and three
HOLDs in a row, with no NOTE or SET_MIXER before them. Retraced
against the real code (RM_C4F9/RM_C552/RM_C564, $C761 for HOLD): HOLD
jumps straight to RM_C552 (reloads the tick counter from the current
duration) WITHOUT going through RM_C53A (envelope relatch) or note
resolution -- it's a pure "tie", it resets nothing. With the mixer
still at 0 (SET_MIXER has never been called) and no pitch resolved,
those 3 HOLDs are 3 times 192 = 576 ticks (11.52s) of real silence
before the first CALL_SUBPATTERN 0x02 runs its own SET_MIXER 0x01 and
the percussion notes kick in. Confirmed with a tick-by-tick dump
(instrumented Interpreter.tick) that the mixer stays at 0 up to
exactly tick 576. `render()`'s default safety limit (--max-ticks 300
= 6s) cuts the ENTIRE render short inside that silence -- that's why
"nothing plays": it isn't an interpreter bug, it's that 6s isn't
enough to even reach the first drum hit. Re-rendered with
--max-ticks 1200 (24s): confirms real silence up to 11.52s and
audible percussion afterward. With --max-ticks 3000 (60s) a full LOOP
cycle still doesn't complete -- this channel's full pattern is long;
pending (not urgent) figuring out how long a complete cycle is if a
full lap needs rendering.

**05_evt07_pista_ce7e.snd is STILL silent -- a different, unresolved
cause**: this script (13 bytes) contains no NOTE at all -- SET_TEMPO,
SET_DURATION, SET_MIXER 0x08 (noise only), SET_VOLUME,
SET_ENVELOPE_SHAPE, SET_ENVELOPE, RESET_SHARED_ENVELOPE, end. The
15-command table (commands 8/9/11) indicates that SET_ENVELOPE/
SET_ENVELOPE_SHAPE/RESET_SHARED_ENVELOPE read and write a shared
table at $CA53 (10 bytes, "owned" by one channel at a time via $CA60)
that's a COMPLETELY DIFFERENT mechanism from the per-channel volume/
pitch envelope already modeled -- very likely the PSG's real HARDWARE
envelope generator (period/shape registers), used here to modulate a
pure-noise channel with no note needed at all. mmsnd_render.py treats
these 3 commands as no-ops (only consuming their parameter byte)
because that shared table and whoever walks it tick by tick (RM_C6C9
and where it's called from in the main loop) haven't been traced yet.
Without modeling that piece, this effect will keep sounding mute.
Pending: trace RM_C6C9 and the rest of the "shared envelope"
mechanism -- parked with the rest of the sound topics needing more
investigation.

All the wavs in build/sound_preview were regenerated after both
fixes (render-all).

### Fifth round: 02_boot_ch2_ce0c_full.wav "isn't complete" -- a third real bug, broken LOOP detection

The developer, after the two earlier fixes, confirmed
02_boot_ch2_ce0c_full.wav (rendered before those fixes, with
--max-ticks 2000 = 40s) "now plays the game's music" but asked
whether it had all been captured.

Investigating how long a full lap takes: a longer tick-by-tick dump
was instrumented, confirming the script (78 bytes, 26 calls to
CALL_SUBPATTERN before the final LOOP) DOES advance normally through
all 26 subpatterns in sequence (it doesn't get stuck in any inner
loop) -- it's simply a long piece: about 11.52s of initial silence
(see the previous round) plus ~57.6s of real percussion, roughly 69
seconds per full lap. The 40s render was being cut mid-lap, hence
"isn't complete" -- not a bytecode interpretation error.

But while trying to measure this, a **third real bug** was found: the
mechanism `render()` uses to stop only once a lap completes
(comparing read_ptr against the start address, tick by tick) **never
fires** for scripts like this one, because after executing LOOP the
interpreter keeps reading commands with no pause (SET_TEMPO,
SET_VOLUME, SET_DURATION, HOLD...) until the next note/HOLD -- by the
time the pointer is sampled at the end of the tick, it no longer
matches the start address exactly. Before this fix, render() for
02_boot_ch2_ce0c.snd and 07_evt11_bola_poder_ce9c.snd (the only two
real .snd files with a LOOP) only ever stopped by hitting the
--max-ticks safety cap, never cleanly at the exact lap point.

Fixed by adding a `Channel.loop_hit` flag, set to True right inside
the LOOP command's own handling (at the exact moment it runs, without
relying on comparing pointers afterward); render() stops as soon as
it sees it. Verified: 07_evt11_bola_poder_ce9c.wav went from 6.00s (a
noise loop bluntly cut off by the safety cap) to 0.26s (one clean
lap); 01_script_cdff.wav went from 6.00s to 2.42s. Regenerated
02_boot_ch2_ce0c_full.wav with --max-ticks 8000: stops on its own
(before the cap) at 69.14s -- confirms a real full lap of about 69
seconds (11.52s of silence + ~57.6s of percussion).

### Sixth round: labeling the data tables in madmix1.asm (0xC8DE-0xCDCB)

The developer asked whether `RM_TABLE_C8DE` was "the driver itself"
in assembly. Clarified: no, it's pure DATA -- the driver's code
(`RM_C4A0` through `RM_C8C9`) is already fully disassembled right
above it; this zone is the tables that code reads. It used to be a
single `DB` dump with no subdivision beyond a header comment. At the
developer's request (explicitly choosing "just label it in the
.asm", without extracting it to a separate file), labels+comments per
table were added, without touching a single byte: `CMD_JUMP_TABLE_C99E`
(30B), `CHANNEL_STATE_ZERO_C9BC` (171B), `SHARED_ENVELOPE_TABLE_CA53`
(10B), `MISC_FLAGS_CA5D` (4B), `SUBPATTERN_RETURN_TABLE_CA61` (6B),
`TRANSPOSE_TABLE_CA67` (3B), `INSTRUMENT_TABLE_CA6A` (240B),
`ENV_SHAPE_TABLE_CB5A` (24B), `SUBPATTERN_TABLE_CB72` (42B),
`SUBPATTERN_BYTECODE_CB9C` (up to `$CDCB`). The exact boundaries were
computed programmatically by counting bytes from `RM_TABLE_C8DE`
(an auxiliary script, not by hand) to avoid risking a shift; several
`DB` lines had to be split into two or three because a table boundary
fell mid-line -- same bytes, just reorganized. Verified: recompiled,
0 differences, exact same size (22945 bytes).

Along the way, counting bytes precisely revealed `SUBPATTERN_TABLE_CB72`
has 21 pointers, not 20 as previously documented (entries 13-20 repeat
subpattern 0's pointer) -- fixed in this document and in
`mmsnd_render.py`.

### Seventh round: new `manuales/` section -- reference documentation for training

At the developer's request, `src/manuales/` was created as a third
leg of the documentation, alongside `FINDINGS.md` (the chronological
findings diary) and `FLUJO_PROGRAMA.md` (organized by execution
flow): here, HOW each already-resolved subsystem WORKS gets
documented, in an orderly technical-manual format, meant as training
material for a new programmer and as preservation in its own right --
with the investigation process left out.

First manual: `manuales/manual_driver_sonido.md`, self-contained
coverage of everything already resolved about the PSG sound driver:
the AY-3-8910 hardware and why the driver uses precomputed tables,
the code/data architecture, the tick loop (`RM_PLAYER_TICK_C4EB`/
`RM_C4F9`), the 46-byte channel slot field by field, the 15 bytecode
commands with their full table, the 15-byte instrument and the 2/3-
phase envelope mechanics, the subpatterns, the `$6128`/
`LEVELCYCLE_RESOURCE_TABLE` mechanism with the full table of the 14
indices, the unresolved shared hardware envelope
(`SHARED_ENVELOPE_TABLE_CA53`, manual §8) as an explicit starting
point for whoever picks that thread back up, and the two tools'
(`mmsnd_tool.py`/`mmsnd_render.py`) real workflow. Linked from
`README.md`. More manuals will be added as it's decided which other
parts of the system to document this way.

### Eighth round: cleanup of mainloop_engine.bin and reorganization of maze_data.bin

The developer asked about the rest of the loose `.bin` files in
`data/` (`maze_data.bin`, `mainloop_tables.bin`, `niveles_tabla.bin`),
and along the way one undocumented in the README turned up:
`mainloop_engine.bin` (1724 bytes). Investigated: it has no `INCBIN`
in any `.asm` (confirmed with an exhaustive grep over all of `src/`)
-- it corresponds to `MADMIX.SCR`'s `0x2CA0-0x335C` range, which was
already transcribed entirely as real Z80 code with labels (not as a
data blob), so an `INCBIN` was never needed for it. It was an orphan
working/verification copy from the session that transcribed that
stretch (same role as `_engine_tables.bin` for sound). Confirmed by
the developer it's no longer needed -- **deleted**.

About `maze_data.bin`: the developer asked whether it deserved to
live in `data/niveles/` like the rest of the level bodies, since
levels 13 and 14 use it. Investigating the exact detail
(`FINDINGS.md`, "RESOLVED THE PURPOSE OF maze_data.bin") confirmed it
is NOT identical content shared by both levels -- they're two
CONTIGUOUS, NON-OVERLAPPING halves, each exclusive to one level: the
first 580 bytes are the tail of level 13's body (the head, 92 bytes,
lives in `RM_TABLE_CFA4`, the sound driver's envelope table); the
last 700 bytes are the head of level 14's body (the tail, 36 bytes,
lives in the undeciphered table after `$D500`). Given this, the file
was split in two (`data/niveles/body_l13_maze.bin`, 580 bytes, and
`body_l14_maze.bin`, 700 bytes), following the same "one file = one
level" convention as the rest of `data/niveles/` -- instead of moving
the 1280-byte blob as-is under a name suggesting "shared content"
(which would have been inaccurate). Updated `madmix1.asm`'s `INCBIN`
(now two `INCBIN`s with labels `BODY_L13_MAZE_D000`/
`BODY_L14_MAZE_D244`, with a comment explaining the exact split and
making clear that -- unlike the rest of `data/niveles/` -- these two
compile inside `MADMIX1.BIN`, not `MADMIX.SCR`). Verified:
recompiled, 0 differences, exact same size (22945 bytes).
`maze_data.bin` deleted after the split. `README.md` updated.

### Ninth round: LEVEL_LOADER WRITES to the source when loading (RES 7,(HL) before LDI), and RM_TABLE_CFA4 downgraded from "sound table" to "no confirmed consumer"

The developer asked, about the memory-sharing trick between
`maze_data.bin`/`RM_TABLE_CFA4` and level 13 (see "RESOLVED THE
PURPOSE OF maze_data.bin" above): is level 13's information the
file's content plus 92 unrelated, untouched sound bytes, or does
level 13 overwrite those 92 sound bytes (and shouldn't that break
things)?

Verified by reading `LEVEL_LOADER` (`madmix_scr.asm`) line by line:
it's NOT a simple non-destructive read. The body-copy loop (both
`.plain_copy` and `.with_wildcard`) does:

```asm
RES 7, (HL)     ; clears the "eaten" bit -- AT THE SOURCE, (HL), not the destination
LDI              ; copies (HL)->(DE) ALREADY modified, advances both pointers
```

`HL` is the level table's ORIGINAL body pointer (for level 13,
`$CFA4`, confirmed by extracting the real record from
`niveles_tabla.bin`: `body_pointer=$CFA4`, `rows=21`, `21×32=672`
bytes). In other words: the loader DOES write to the source, clearing
bit 7 of each byte before copying it into the game buffer (`$FC60`)
-- it isn't a harmless read.

Checked in the compiled binary: of `RM_TABLE_CFA4`'s 92 real bytes,
**10 have bit 7 set** (they're `$BF`, offsets 30/32/34/48/50/52/63/
67/79/83 relative to `$CFA4`) and turn into `$3F` the first time
level 13 loads in a game.

**Why doesn't this break anything?** An exhaustive `grep` search was
done for every reference to `$CFA4`/`RM_TABLE_CFA4` in `madmix1.asm`
and `madmix_scr.asm` -- **no routine ever reads it**, not in the
sound driver (already fully disassembled, `$C4A0`-`$C8C9`, no gaps)
nor anywhere else. Important consequence for the documentation: the
name "envelope/percussion table" `RM_TABLE_CFA4` had carried since an
old session **was and still is a never-confirmed guess** (the
original note already said "not identified note by note"). With the
driver now complete and no reader found, the correct conclusion is
NOT "it was used once and isn't needed anymore" -- it's **"there's no
proof it was ever used, not even once"**. Two equally plausible
hypotheses, with no way to tell them apart from the final binary:

1. Leftover from an earlier driver version (an instrument/pattern
   abandoned before the game was finished, never deleted -- deleting
   bytes late shifts everything after it, the same risk we already
   know firsthand from this project).
2. It was never sound data at all: the pattern resemblance that
   motivated the name back then could be coincidence, and it may
   actually be level filler deliberately placed next to level 13/14's
   data.

Fixed the comment on `RM_TABLE_CFA4` and on `BODY_L13_MAZE_D000`
in `madmix1.asm` to reflect this precisely (without asserting "sound
table" as a confirmed fact). Verified: recompiled, 0 differences,
comment-only.

### Tenth round: LEVEL_TABLE rewritten as a native data table (goodbye niveles_tabla.bin)

The developer asked whether `niveles_tabla.bin` (the 15 level
records, 300 bytes) shouldn't be in a readable/editable format, now
that the meaning of almost every field is known (offsets 0-19).
Unlike the sound bytecode (which needed its own compiler/decompiler
because it's a made-up language), this case needs no new tool at
all: each record's body/header pointers (offsets 0-1, 2-3, 4-5)
already have real labels defined in `madmix_scr.asm` itself
(`BODY_L01`, `BODY_L2`... `BODY_L12`, `HEADER_4AFC`, `HEADER_4B5C`,
`HEADER_50BC`), so it's enough to replace the `INCBIN` with a native
`DW`/`DB` table that references them directly -- SjASMPlus itself
computes the correct address when assembling.

The full table (15 records) was generated with a script that starts
from `niveles_tabla.bin`'s real bytes, maps each known pointer value
to its label, and leaves the already-deciphered fields (offsets 6,
8, 9, 10, 11, 12, 17, 18-19) as named values instead of loose hex;
the unidentified fields (7, 15, 16) are left in hex with an honest
"unidentified" comment -- without inventing a meaning. The one
exception to using labels: levels 13 and 14 point at `$CFA4`/`$D244`,
addresses inside `MADMIX1.BIN` -- a different binary, compiled
separately, with no link between the two -- so those two specific
pointers stay as literal hex, with a comment explaining which label
they correspond to in `madmix1.asm` (`RM_TABLE_CFA4`/
`BODY_L14_MAZE_D244`).

Verified: `madmix_scr.asm` recompiled, compared byte for byte against
the original -- exactly the same 4 already-known diffs as always
(positions ~6388-6390 and the last byte), none new. (Process note:
the first check showed ~17,756 diffs due to a bug in the comparison
script itself -- it applied the 7-byte BLOAD-header discount that's
only needed for `MADMIX1.BIN`, not for `MADMIX.SCR`, whose compiled
binary DOES include that header by default. Fixed the script, not the
code.) `niveles_tabla.bin` deleted after the conversion. `README.md`
updated.

### Eleventh round: HTML viewers updated (flujo_programa.html regenerated, mapa_memoria.html fixed)

The developer asked not to forget updating the HTML viewers after
this session's changes. The 3 candidates referencing what was touched
(`maze_data.bin`, `niveles_tabla.bin`, `mainloop_engine.bin`, the new
sound labels, `LEVEL_TABLE`) were reviewed:

- **`recursos/flujo_programa.html`**: the `INVENTORY` (591 labels,
  "auto-generated from the .sym files") was out of date on two
  fronts -- missing the ~12 new sound labels plus
  `BODY_L13_MAZE_D000`/`BODY_L14_MAZE_D244`, `MAZE_DATA` no longer
  exists, and above all **every `madmix_scr.asm` line number after
  `LEVEL_TABLE`** had shifted when the native table was inserted (a
  drift that, in fact, had already been carried since before this
  session: neither `TI_2C2E_ENTRY`/`TI_5B56` nor the earlier
  `TAIL_KEYMENU_MAIN`→`TAIL_MAINMENU_DRAW` rename from previous
  sessions were reflected). The whole inventory was regenerated from
  scratch with a script (compiles the 3 `.asm` files with `--sym`,
  locates each symbol's definition line, and classifies it as
  function/internal/data/no-ref by cross-checking `CALL`/`JP`/`JR` --
  both by symbolic name and by literal hex address, since calls
  BETWEEN the 3 binaries, compiled separately with no linker, use the
  numeric address, not the symbol). Result: 623 labels (up from 591),
  compared entry by entry against the old inventory -- only 5 genuine
  category differences (calculation improvements, e.g. detecting
  `CALL Z, $XXXX` with a space after the comma, which the earlier
  heuristic skipped), the rest are either legitimately new labels or
  `MAZE_DATA`'s removal. Also updated the per-category counters in
  the HTML itself (94 function/279 internal/163 data/87 no-ref) and
  in `FLUJO_PROGRAMA.md` §0/README.md (same 591→623 change).
- **`recursos/mapa_memoria.html`**: fixed the two entries mentioning
  `maze_data.bin` by name (now nonexistent, split into
  `body_l13_maze.bin`/`body_l14_maze.bin`) and the one describing
  `RM_TABLE_CFA4` as "probable envelope/percussion table" without
  this session's correction (no confirmed consumer); added a mention
  that `LEVEL_TABLE` is no longer a `.bin` but a native table.
- **`recursos/niveles.html`**: reviewed, no references to the files
  touched (its "591" is unrelated tile data, not the label counter).

Verified: both binaries recompiled, 0 differences in `MADMIX1.BIN`
and the same 4 already-known diffs as always in `MADMIX.SCR` (the
changes are documentation/HTML only, no compiled byte differs).
`INVENTORY`'s JSON verified parseable (623 entries).

### Twelfth round: level editor -- readable text, tools/mmlvl_tool.py and a visual editor (recursos/editor_niveles.html)

The developer asked about `header_XXXX.bin`'s format (level headers):
they're tile grids (32 columns x 3 rows), the same format as level
bodies -- indices 0-90 from `data/tiles/*.til`'s real catalog, with
no fields of their own meaning, drawn by `LEVEL_LOADER` as a
decorative margin above and below the playable body. From there, they
proposed the same treatment sound already got: a readable text
format + a conversion tool + (here it does make sense, since these
are visual tiles) a visual editor using the already-identified
catalog to
paint levels without hand-typed hex, respecting the current fixed
dimensions and warning if the ball count stops matching
`LEVEL_TABLE`.

**New finding during implementation**: bit 7 of each byte IS genuinely
used in the real level bodies (77-160 bytes with bit7 set per file,
checked with a script) -- even though `LEVEL_LOADER` unconditionally
clears it on load (`RES 7,(HL)`, see the previous round), it's present
in the original binary and the text format has to preserve it byte
for byte. The 3 shared headers, by contrast, always have bit7 at 0.

**Second finding**: `body_l13_maze.bin`/`body_l14_maze.bin` (580/700
bytes, the "borrowed" fragments from the previous round) are NOT
multiples of 32 -- they aren't complete grids, they're chunks that
start/end mid-row of the level they belong to (they share memory with
`RM_TABLE_CFA4` and the undeciphered table after `$D500`).
`tools/mmlvl_tool.py` handles them with a second text format ("flat
mode", `; bytes=N` instead of `; rows=N cols=N`) -- a byte list with
no grid shape, with its own fixed-size warning. They're left out of
the visual editor (painting them as an isolated grid makes no sense).

**`tools/mmlvl_tool.py`** (same spirit as `mmsnd_tool.py`):
`disasm`/`asm` (bin↔text, auto-detects grid or flat mode based on
whether the size is a multiple of 32, validates declared rows/
columns/bytes before writing), `roundtrip`/`roundtrip-all` (verified:
the 17 `.bin` files in `data/niveles/` -- including the 2 flat
fragments -- reproduce their exact original binary), and
`check-bolitas file.txt LEVEL` (counts "floor with ball" tiles,
0x2D/0x2E/0x2F with bit7 masked, and compares them against the real
target read directly from `LEVEL_TABLE` in `madmix_scr.asm` --
parsing the 9-line block per record, with no separate manifest that
could desync). Verified against the 5 levels already known to match
exactly from the offsets-18-19 round (1=114, 8=90, 10=116, 12=176):
the 4 checkable with this command match exactly. Level 6 (not one of
the 5 exact ones) gives the already-documented mismatch (128 counted
vs 151 target) -- expected behavior, not a tool bug.

**`recursos/editor_niveles.html`** (a new viewer, self-contained, no
server or fetch, same pattern as the rest of `recursos/`): a palette
of the 91 tiles (reuses -- by copying, the same way `niveles.html`
already does with `graficos.html` -- the `TILE_GFX` array and the
`hexToGrid`/`drawTile` decoder), the active level's grid paintable
with click/drag, a checkbox to paint with bit7 set, a live ball
counter (green/red depending on whether it matches `LEVEL_TABLE`'s
target, embedded as a snapshot when the HTML is generated -- if
`LEVEL_TABLE` changes it needs regenerating, same manual maintenance
as `TILE_GFX`/`LEVELS` in the other viewers), an "Open .txt" button
(`<input type=file>`, no CORS issues) and "Download .txt" (Blob) in
the same format `mmlvl_tool.py` produces/consumes -- the real
workflow is editing visually, downloading, manually moving the file
into `data/niveles/` and running `mmlvl_tool.py asm` before
recompiling, same as is already done with the `.snd` files. It
doesn't include `body_l13_maze`/`body_l14_maze` (fragments not
row-aligned) nor validate items/enemies (separate coordinate tables,
`ITEM_TABLE_1`/`ITEM_TABLE_2` in `madmix_scr.asm`, not encoded in the
tile grid -- confirmed with the developer as out of scope for this
pass).

Verified: both binaries recompiled after generating the 16 grid
`.txt` files (0 differences in `MADMIX1.BIN`, the same 4 as always in
`MADMIX.SCR` -- generating text touches no compiled `.bin` or `.asm`).
The HTML editor was thoroughly code-reviewed (there's no way to take
a screenshot in this environment) and opened in the developer's
browser for them to visually confirm painting/downloading -- pending
their confirmation.

**Later tweak after confirming the editor works**: the developer
asked to lock editing of the 3 shared headers (`header_*.bin`) in
`editor_niveles.html` -- being purely decorative and shared across
several levels, painting them there makes no sense. Added: painting/
opening/downloading get disabled when the active file is a header
(detected by name, `header_*`), with a visible on-screen notice. It
was also reported that the ball counter doesn't match for every level
(example: level 3, 109 counted vs 120 target) -- verified with
`mmlvl_tool.py check-bolitas`: it's the same mismatch already
documented in the offsets-18-19 round (`0x3C` wildcards substituted
at load time + "special ball" positions that aren't tile bytes), not
a new bug. The editor's counter now distinguishes the levels where an
exact match WAS confirmed (1, 8, 10, 12 -- there, a mismatch would be
a real sign of a problem) from those that never matched even
unedited (the rest, where the mismatch is expected and flagged as
such instead of as a red alarm).

### Thirteenth round: mystery closed -- arrows also count as a ball

The developer, while testing the level editor, pointed out that arrow
tiles (the "forces you to advance in that direction" kind) have a
ball drawn on them and should count toward the total. Verified in
`madmix_scr.asm`: the 4 arrow handlers (`HANDLER_2F18`/
`HANDLER_2F50`/`HANDLER_2F88`/`HANDLER_2FC0`) do exactly the same
`CALL $8D70` (2 points) + `INC ($2C08)` as the normal-ball handler --
confirming that yes, stepping on an arrow also counts as "ball
eaten". This **fully resolves** the mystery open since
the offsets-18-19 session ("for the other 8 levels the direct tile
count does NOT match exactly"): adding the 4 arrows (`0x33`-`0x36`)
to the count alongside the 3 normal-ball tiles (`0x2D`-`0x2F`), **all
12 levels match their `LEVEL_TABLE` target EXACTLY, with no
exception at all** -- there was no need to invoke wildcard tiles or an
extra "special ball" table, 4 tile types were simply missing from
the counted set. Fixed `BALL_TILES` in `tools/mmlvl_tool.py` and
`recursos/editor_niveles.html` (which now also flags any mismatch as
a real signal -- there are no longer levels with an "expected
mismatch"). See also the resolution note added directly in the
"Deciphered offsets 18-19" section above.

### Fourteenth round: levels 13/14 added to the editor (with read-only context) + hidden level renamed to "15" (label only)

The developer asked to add levels 13 and 14 to the visual editor, and
to rename the hidden level to "level 15" (clarifying its real link
into `LEVEL_TABLE` is still unresolved, an explicitly parked task).

**Level 14, thoroughly investigated**: it was confirmed that the
36-byte tail `body_l14_maze.bin` was missing (to complete its real
736 bytes, 23×32) are exactly the first 36 bytes of
`data/demos/01_nivel1.dem` (`DEMO_SCRIPT_NIVEL1`, `$D500` onward) --
and that those 36 bytes are **never read as a real demo script**:
`LEVELCYCLE_TABLE` (`madmix_scr.asm`) points at demo level 1 at
`$D524`, not `$D500` (`$D524-$D500=$24=36`, exactly 18
`[duration,direction]` pairs the demo system simply skips over).
Confirmed no other `CALL`/`LD` in the transcribed code reads those 36
bytes directly -- they're left orphaned as a demo script, just as
"unconfirmed consumer" as `RM_TABLE_CFA4` was for level 13. There's
no real conflict in treating them as level 14's context.

**Numeric verification combining each level's full body** (borrowed
head/tail + its own part), also counting the arrows (see the previous
round): **level 14 = 267 balls counted, real target 267 -- EXACT**.
**Level 13 = 106 counted, real target 105 -- one too many**, isolated
within the 92 borrowed bytes from `RM_TABLE_CFA4` (whose identity was
already known to be uncertain) -- not a flaw in the counting criteria
(already confirmed exact across the 12 real levels + level 14), but a
numeric coincidence in a table probably never meant to be part of a
level.

**Editor (`recursos/editor_niveles.html`)**: levels 13 and 14 are now
shown as a COMPLETE grid (21×32 and 23×32 respectively) to give real
visual context, but with the borrowed part (the first 92 bytes in
13, the last 36 in 14) shaded and locked -- it can't be painted
there, and export/import only affects `body_l13_maze.bin`/
`body_l14_maze.bin`'s own range, in the same "flat" format
(`; bytes=N`) `mmlvl_tool.py` already understands for these two files
(no new format invented). The ball counter counts over the full grid
(including the borrowed part, because that's how the real game reads
it), so level 13 will permanently show "106 / 105" unless the owned
part is edited to compensate -- documented on screen so it doesn't
read as an editor bug.

The hidden level (`body_hidden_48bc.bin`) is now labeled in the
dropdown as "level 15" with an explicit note that it's reference
numbering only, with no real change in `LEVEL_TABLE` or any `.asm` --
the real hookup remains pending and deliberately not implemented (see
`README.md`, an already-documented pending item).

### Fifteenth round: RM_TABLE_CFA4 and level 14's tail consolidated as their own files -- and a CORRECTION about `niveles.html`

The developer asked why lock level 13's head (`RM_TABLE_CFA4`) and
level 14's tail if, in practice, they already function as real parts
of those levels' bodies and nothing else uses them -- editing there
would "just be hitting the same thing that's already being hit now".
Correct reasoning: there's no confirmed consumer besides the
corresponding level in either case (already verified for
`RM_TABLE_CFA4` in the previous round; for level 14's tail it was
also confirmed `LEVELCYCLE_TABLE` deliberately skips those 36 bytes,
`$D524` instead of `$D500`). The lock's only reason was mechanical
(they weren't editable files of their own), not safety.

**Consolidated**: `RM_TABLE_CFA4` (92 bytes, previously inline `DB`
in `madmix1.asm`) was extracted into its own
`data/niveles/body_l13_head_cfa4.bin`, with `INCBIN`.
`data/demos/01_nivel1.dem` (100 bytes) was split into
`data/niveles/body_l14_tail_demo1.bin` (36 bytes, level 14's real
tail) + a `01_nivel1.dem` trimmed down to the 64 bytes that really
are a demo script (new label `DEMO_SCRIPT_NIVEL1_REAL_D524` at
`$D524`). Verified: recompiled, **0 differences** in both binaries.
Both new files already have their `.txt` (`mmlvl_tool.py disasm`),
verified with `roundtrip-all` (19 files total now in
`data/niveles/`).

**IMPORTANT CORRECTION about a finding from the previous round**:
while verifying this, an error of my own turned up, not the
project's. To compare bytes I used `build/MADMIX1.BIN` (my freshly
compiled binary) applying the `address - 0x8400 + 7` formula -- that
formula is correct ONLY for the disk's **original** `.BIN` (which
carries a 7-byte BLOAD header); `build/MADMIX1.BIN` (`sjasmplus`'s
output) does NOT carry that header (confirmed: exactly 22945 bytes,
starts directly with the real code, versus the original's 22952 =
22945+7). Applying the extra `+7` against a file that no longer
needed it shifted all my readings by 7 bytes -- which led me to
conclude, **wrongly**, that `recursos/niveles.html` had a "starts
reading 7 bytes early" bug for levels 13 and 14. **The check was
redone reading from the original `.BIN`** (with the `+7` formula
applied where it belongs): `niveles.html` **matches exactly** (with
bit 7 masked, which is exactly what its renderer does) the real
reconstruction of both levels. There was no bug in `niveles.html` --
that claim is retracted.

This also invalidated the "106 vs 105" ball count reported for level
13 in the previous round (computed with the same shifted data).
**Recounted with the now-fixed, consolidated files: level 13 =
105/105 exact, level 14 = 267/267 exact** -- all 14 checkable real
levels (1-12, 13, 14) match without exception, with no isolated
anomaly in `RM_TABLE_CFA4` as had been mistakenly noted.

**`recursos/editor_niveles.html` updated**: levels 13/14 no longer
have any "shaded/locked" zone -- each one is a complete grid made of
2 files of its own, BOTH editable, with a simple colored line marking
where one ends and the other starts (informational only, not
restrictive). "Download .txt" generates one file per part (same
"flat" format `mmlvl_tool.py` already uses); "Open .txt" auto-detects
which part a loaded file belongs to by its declared byte count.

### Sixteenth round: `RM_TABLE_CFA4` was NEVER sound data -- renamed to `BODY_L13_HEAD_CFA4`

The developer questioned the whole premise behind `RM_TABLE_CFA4`:
not just that it had no confirmed consumer (already established in
the ninth round), but that the very idea it was "a sound table
recycled/borrowed by level 13" might, from the start, have been a
mistaken deduction on our part -- the name "RM_TABLE" comes from a
very old session that labeled it a possible envelope/percussion table
just for sitting next to the real sound tables, with no real
verification. The argument: it's too much of a coincidence that its
92 bytes are EXACTLY what's missing to complete level 13's 672-byte
body (92 here + `BODY_L13_MAZE_D000`, 580 bytes) AND that the content
decodes into tiles that make sense.

**Verified by decoding the 92 bytes row by row** (32 columns,
`data/tiles/*.til`'s catalog): the result is NEITHER noise NOR filler
-- it's a perfectly coherent, left-right symmetric maze room: a
complete `muro_cemento` border (corners, horizontal/vertical walls),
a `loseta_solida_negra` interior with decorative
`estrella_pequena/mediana/grande` in the same pattern the rest of the
real levels use, and two `suelo_con_bola`/`suelo_sin_bola` blocks with
their `item_bola_poder` on each side -- exactly the composition of a
real level room, not a coincidence of sound bytes that "by chance"
look like tiles.

**Conclusion**: the developer was right. There was never sound there,
not even in an earlier driver version -- it's been level 13's body's
head from the start, and the "overlap/borrowing with sound" documented
in earlier rounds was a mistaken reading on our part of address
proximity, not something the game actually does.

**Changes**: the `RM_TABLE_CFA4` label in `madmix1.asm` was renamed
to `BODY_L13_HEAD_CFA4` (and its 2 cross-references, in
`BODY_L13_MAZE_D000`'s comment and in `madmix_scr.asm` next to
`LEVEL_TABLE`'s `$CFA4` pointer). The accompanying comment was
rewritten to stop presenting "recycled sound" and "always a level" as
two equally valid hypotheses -- it now documents the conclusion with
the evidence (exact size + content that decodes with meaning) and
keeps only the honest clarification that the existence of an earlier
driver version can never be fully ruled out from the final binary
alone, though it no longer carries any real weight against the
content evidence. `recursos/mapa_memoria.html` and `README.md`
updated the same way (category changed from "resources" to "level" in
the memory map).

Recompiled after the rename: **0 differences** in `MADMIX1.BIN`
(`+7` formula against the original `.BIN`) and the same **4
preexisting diffs as always** in `MADMIX.SCR` (offsets ~6388-6390 and
the last byte) -- no regression. `recursos/flujo_programa.html`
regenerated (`gen_inventory.py` against the freshly compiled `.sym`
files): inventory goes from 623 to **624** labels (`RM_TABLE_CFA4`
removed, `BODY_L13_HEAD_CFA4` added, and
`DEMO_SCRIPT_NIVEL1_REAL_D524` -- a label from the previous round
that hadn't been added to the inventory yet -- also added); per-
category counts updated to 94 function / 279 internal / 164 data /
87 no-ref in the HTML and in `FLUJO_PROGRAMA.md` §0.

### Seventeenth round: level 14's tail was never a demo script either -- unified into `body_l14.bin`

Same reasoning as the previous round with `RM_TABLE_CFA4`, applied
this time to the last 36 bytes of level 14's body ($D500-$D524,
previously `DEMO_SCRIPT_NIVEL1`). The developer pointed out: if
`LEVELCYCLE_TABLE` has always pointed at $D524 and never at $D500,
and the demo works fine starting there, then those 36 bytes were
never, in practice, a demo script -- the idea that they were a
"shifted real script" was a deduction on our part from an old
session, made while still piecing the puzzle together without yet
seeing the full picture.

**Verified in `LEVELCYCLE_TABLE`** (`madmix_scr.asm`, `$60D0`):
`DB $01,$24,$D5,...` -- level 1's pointer has ALWAYS literally been
`$D524`, there's no version or variant pointing at
`$D500`. So there is no "real script that starts at $D500 and is read
from partway through" -- that reading (present in earlier sessions'
comments) had the causality backwards: it isn't that the script
starts at $D500 and the pointer skips 36 bytes for some reason; the
script ALWAYS started at $D524, and $D500-$D524 never belonged to the
script at all.

**Consolidated**: `data/niveles/body_l14_maze.bin` (700 bytes, head) +
`body_l14_tail_demo1.bin` (36 bytes, tail) are combined into a single
new file, `data/niveles/body_l14.bin` (736 bytes = 23×32, a complete
grid), with its twin `.txt` in grid format (no longer flat).
The two old files and their `.txt`s are removed. In `madmix1.asm`:
`BODY_L14_MAZE_D244` + `DEMO_SCRIPT_NIVEL1` (at `$D500`) are replaced
by a single `BODY_L14_D244` label with one `INCBIN`; the label
`DEMO_SCRIPT_NIVEL1_REAL_D524` is renamed to `DEMO_SCRIPT_NIVEL1` (the
"REAL" suffix is no longer needed, since there's no other
`DEMO_SCRIPT_NIVEL1` to confuse it with anymore) and stays at its real
address, `$D524`. Also fixed the large comment block documenting
"0xD500-0xD6B6 (438 bytes): 10 demo scripts" -- it now correctly
describes "0xD524-0xD6B6 (402 bytes)", without the (now inaccurate)
phrase that level 1's pointer "falls partway through the real
script". `LEVELCYCLE_TABLE`'s comment in `madmix_scr.asm` was fixed
the same way.

Recompiled after the restructuring: **0 differences** in
`MADMIX1.BIN` and the same **4 preexisting diffs** in `MADMIX.SCR` --
no regression. `recursos/flujo_programa.html` regenerated: the
inventory drops from 624 to **623** labels (a net consolidation of 1
fewer label: `BODY_L14_MAZE_D244` and `DEMO_SCRIPT_NIVEL1_REAL_D524`
are removed, `BODY_L14_D244` is added, and `DEMO_SCRIPT_NIVEL1` now
refers to `$D524` instead of `$D500`); per-category counts back to
94/279/163/87.

`recursos/editor_niveles.html` updated: the "combined level14" entry
(2 segments, with a separator line) becomes a normal single-file entry
(`body_l14.bin`), just like any other level -- there's no longer any
"parts" zone or line for level 14, the same thing that also happened
to level 13 with `BODY_L13_HEAD_CFA4`, except level 13 DOES still
remain 2 real files on disk (`body_l13_head_cfa4.bin` +
`body_l13_maze.bin`, its own comment section) because there's no
reason to merge them beyond convenience -- they're kept separate for
now. `README.md` and `recursos/mapa_memoria.html` updated to reflect
the new structure (range 0xD244-0xD524 = level 14's complete body;
range 0xD524-0xD6B6 = 10 demo scripts, 402 bytes).

### Eighteenth round: level 13's two files also get unified into one

Symmetric close to the previous two rounds: if `BODY_L13_HEAD_CFA4`
(sixteenth round) was never sound data and `DEMO_SCRIPT_NIVEL1`
(seventeenth round) was never a demo script -- both were always, in
practice, simply parts of their level's body -- there's no real
reason left to keep those parts in separate files. Unlike level 14's
correction (which fixed an objectively wrong address reading), there's
no new fact to correct here: it's a convenience simplification now
that the premise justifying the separation ("one of the two halves
is context for another table") has been fully ruled out.

**Consolidated**: `data/niveles/body_l13_head_cfa4.bin` (92 bytes) +
`body_l13_maze.bin` (580 bytes) are combined into a single new file,
`data/niveles/body_l13.bin` (672 bytes = 21×32, a complete grid),
with its twin `.txt` in grid format (no longer flat). The two old
files and their `.txt`s are removed. In `madmix1.asm`:
`BODY_L13_HEAD_CFA4` + `BODY_L13_MAZE_D000` are replaced by a single
`BODY_L13_CFA4` label with one `INCBIN`, and their accompanying
comments are merged into one documenting both corrections (ruling out
the sound hypothesis + the unification). `madmix_scr.asm` (the
comment next to `LEVEL_TABLE`'s `$CFA4` pointer) updated the same
way.

Recompiled: **0 differences** in `MADMIX1.BIN` and the same **4
preexisting diffs** in `MADMIX.SCR` -- no regression.
`recursos/flujo_programa.html` regenerated: the inventory drops from
623 to **622** labels (`BODY_L13_HEAD_CFA4` and `BODY_L13_MAZE_D000`
removed, `BODY_L13_CFA4` added); per-category counts 94/279/162/87.
`recursos/editor_niveles.html` updated: the "combined level13" entry
(2 segments, with a separator line) becomes a normal single-file
entry (`body_l13.bin`), just like the rest of the levels -- there's
no level left in the editor with more than one segment (the multi-
segment mechanism is kept in the code in case a future file needs it,
but no current level uses it). `README.md` and
`recursos/mapa_memoria.html` updated: the `0xCFA4-0xD244` range is
now described as a single block, "level 13's COMPLETE body".

With this, all 15 `LEVEL_TABLE` records point to a level body
contained in a single real `data/niveles/` file (or, for the 12
normal levels + the hidden one, within `MADMIX.SCR`'s contiguous
block) -- there's no level left documented as "split into several
parts for historical reasons".

### Nineteenth round: `INSTRUMENT_TABLE_CA6A`, `ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_TABLE_CB72` and `SUBPATTERN_BYTECODE_CB9C` reformatted so the `DB` rows match their comments' geometry

The developer pointed out that `INSTRUMENT_TABLE_CA6A` said "16
instruments x 15 bytes" but was dumped in `madmix1.asm` as a 16-
bytes-per-line hex dump, with no relation to each instrument's real
boundaries (15 bytes) -- and that `ENV_SHAPE_TABLE_CB5A`,
`SUBPATTERN_TABLE_CB72` and `SUBPATTERN_BYTECODE_CB9C` had the same
problem.

**`INSTRUMENT_TABLE_CA6A`** (already fixed in the previous round for
a similar request): confirmed with code, not just arithmetic
(240/16=15) -- `SET_INSTRUMENT` computes `HL=index*15` with `RM_C88D`
(8x16 multiplication) and copies exactly `D=$0F=15` bytes from
`$CA6A+HL`. Reformatted into 16 rows of 15 bytes, one per instrument.

**`ENV_SHAPE_TABLE_CB5A`** (24 bytes, comment "4 entries x 6 bytes"):
reformatted into 4 rows of 6 bytes, one per envelope shape.

**`SUBPATTERN_TABLE_CB72`** (42 bytes, "21 16-bit pointers"):
previously in rows of 6/8/7 pointers (correct bytes, but with no
relation to the 21 declared entries). Reformatted into `DW` with
**one entry per line** -- and, following the convention already used
in `ML_DISPATCH_TABLE` (`madmix_scr.asm`), with **real labels**
instead of literal hex, so the assembler itself resolves the
addresses.

**`SUBPATTERN_BYTECODE_CB9C`** (559 bytes, "13 shared subpatterns"):
this case ran deeper -- each subpattern's bytecode is VARIABLE-sized
(they aren't fixed-size records), so "matching the geometry" meant
splitting the dump exactly at the 13 real boundaries, not just
changing the row width. Computing the 13 boundaries from
`SUBPATTERN_TABLE_CB72`'s unique addresses (12 in table order + entry
12, `$CBB0`, which falls in memory BEFORE entry 1 -- confirmed with a
script: 13 unique addresses sorted by memory address do add up to
exactly 559 bytes with no gaps or overlaps), 12 new labels were
generated (`SUBPATTERN_CBB0`, `SUBPATTERN_CBD3`, ...
`SUBPATTERN_CDAB`; entry 0, at `$CB9C`, directly uses
`SUBPATTERN_BYTECODE_CB9C`, with no duplicate label of its own).
**Strong verification of the bytecode model itself**: all 13
fragments delimited this way end, without exception, in `$8D`
(command 13, RETURN_SUBPATTERN) -- independent confirmation that the
pointer addresses and the bytecode's semantics fit together
perfectly. `SUBPATTERN_TABLE_CB72` was rewritten with `DW` pointing
at these 12 new labels + `SUBPATTERN_BYTECODE_CB9C` for entry 0 and
the 8 repeats (entries 13-20).

All four tables were generated with a Python script that extracted
the raw bytes from the current rows, verified the length sums against
the sizes declared in the comments, and regenerated the `DB`/`DW`
aligned to the real boundaries -- no data byte changed, only the
source lines' format and the introduction of new labels where there
were none.

Recompiled: **0 differences** in `MADMIX1.BIN` at each intermediate
step (one per table) and at the end. `recursos/flujo_programa.html`
regenerated: 622 → **634** labels (12 new `SUBPATTERN_*`); per-
category counts 94/279/174/87. Along the way, a side effect in
`gen_inventory.py`/the inventory itself was fixed:
`SUBPATTERN_BYTECODE_CB9C` had ended up misclassified as "no-ref" at
an intermediate step (from having another label stacked at the same
address right below it, breaking the "next line is DB/DW" heuristic)
-- resolved by not duplicating entry 0's label. `FLUJO_PROGRAMA.md`
and `README.md` updated with the new count.

### Twentieth round: the 13 shared subpatterns, extracted into `data/sound/*.spt` (same tool as the `.snd` files)

The developer asked whether the 13 subpatterns (see the previous
round) use the same bytecode as the event `.snd` files and whether
they'd be compatible with `mmsnd_tool.py`/`mmsnd_render.py` -- and
whether it made sense to extract them too, into their own files with
a different extension.

**Verified before touching anything** (extracting the 13 byte ranges
and running them through `mmsnd_tool.py`'s `disassemble()`/
`assemble()` with no code changes at all): all 13 roundtrip exactly,
same 15-command language, readable decoding (`SET_INSTRUMENT`,
`SET_VOLUME`, ..., `RETURN_SUBPATTERN`). In `mmsnd_render.py` the
interpreter ALREADY fully supports `CALL_SUBPATTERN`/
`RETURN_SUBPATTERN` (that's how it reproduces the boot music today,
which calls subpatterns constantly), and a stray `RETURN_SUBPATTERN`
with no prior call (`ch.return_addr is None`) already resolves as
"end of script" with no error -- but `render()`'s `SCRIPT_ADDR`
manifest doesn't include the subpatterns yet, so playing them
STANDALONE from the CLI doesn't work without extending that manifest
(not implemented this round, documented as pending).

**Extracted**: the 13 subpatterns into `data/sound/*.spt` (extension
chosen by the developer to avoid mixing them with the 16 real
event/music `.snd` files), named by their entry index in
`SUBPATTERN_TABLE_CB72` (00-12) plus their address --
`00_subpatron00_cb9c.spt` .. `12_subpatron12_cbb0.spt` (entry 12
falls at `$CBB0`, in memory BEFORE entry 1, see the previous round).
Each with its twin `.txt` generated with `mmsnd_tool.py disasm`.
`mmsnd_tool.py roundtrip-all` extended to also walk `.spt` in
addition to `.snd` (one line of code); the 29 files in
`data/sound/` (16 `.snd` + 13 `.spt`) pass roundtrip exactly.

The `.txt` header warning (`WARNING_BANNER`, now `warning_banner(path)`)
was made extension-aware: for `.snd` it still points at
`LEVELCYCLE_RESOURCE_TABLE` (`madmix_scr.asm`)
as the consumer with a fixed address; for `.spt` it correctly points
at `SUBPATTERN_TABLE_CB72` (`madmix1.asm`) -- they're different
pointer tables, and the previous generic warning would have pointed
at the wrong table for a `.spt`.

In `madmix1.asm`: the 13 `DB` blocks (already reformatted in the
previous round with the correct boundaries) were replaced with
`INCBIN` pointing at the new `.spt` files, without touching the 13
already-existing labels (`SUBPATTERN_BYTECODE_CB9C`/
`SUBPATTERN_CBB0`/etc. -- same addresses). Recompiled: **0
differences** in `MADMIX1.BIN`. `recursos/flujo_programa.html`
regenerated: same total label count (634, none added/removed -- only
which source line they come from changes). `_engine_tables.bin`
(the renderer's working copy) did NOT need regenerating: it still
contains the same bytes across `$C8DE-$CDCB` (including the 13
subpatterns), since the change was only about where those bytes come
from in the `.asm`, not their content.

`README.md` updated: a new entry in `data/sound/`'s tree for the
`.spt` files, the fixed-size warning extended to cover them
(mentioning their real consumer, `SUBPATTERN_TABLE_CB72`), and
`_engine_tables.bin`'s description fixed (it no longer says the
subpatterns "are still inline DB" -- they're now `INCBIN` from
`.spt`, though the renderer's copy is still valid unchanged since the
final bytes are identical).

### Twenty-first round: `data/sound/` organized into `snd/` and `spt/`, and reference WAVs for the 13 subpatterns

With the `.snd` files (16 real scripts) and the `.spt` files (13
subpatterns, previous round) living loose together in the same
directory, the developer asked to organize them into their own
subfolders by type: `data/sound/snd/` and `data/sound/spt/`.
`_engine_tables.bin` (the renderer's working copy, doesn't belong to
either group -- it mixes pitch/instruments/envelope with the
subpatterns themselves) stays at `data/sound/`'s root.

**Moved**: the 16 `.snd`+`.txt` files to `data/sound/snd/`, the 13
`.spt`+`.txt` files to `data/sound/spt/`. **`madmix1.asm`** updated:
the 26 `INCBIN "data/sound/..."` paths become
`INCBIN "data/sound/snd/..."` / `"data/sound/spt/..."` as
appropriate. Recompiled: **0 differences** in `MADMIX1.BIN`.

**`tools/mmsnd_render.py`** updated for the new layout: `load_memory()`
now looks for the 16 real scripts in `data/sound/snd/` (previously
directly in `data/sound/`). A new manifest, `SUBPATTERN_ADDR`, was
added (`.spt` filename -> real address, the same 13 values already
used in `madmix1.asm`) -- unlike the real scripts, subpatterns do NOT
get pasted in separately in `load_memory()` (they already live inside
`_engine_tables.bin`, which covers the full `$C8DE`-`$CDCB`), so
`render()` only needed to be taught their start address. `render()`
now checks `SCRIPT_ADDR` first, and if not found, `SUBPATTERN_ADDR`
(using the `.spt` file's own on-disk size as the end limit -- either
way the real end is always marked by each one's `RETURN_SUBPATTERN`,
already verified that a `RETURN_SUBPATTERN` with no prior call ends
playback with no error). `render-all` extended the same way to
recognize `.spt` in addition to `.snd`.

**Generated the 13 reference WAVs** in `build/sound_preview/` (same
place as the 16 `.snd`, with `py tools/mmsnd_render.py render-all
data/sound/spt/ build/sound_preview/`): durations between 0.02 s and
0.64 s, all rendered with no error. Also confirmed the 16 `.snd`
files still render exactly the same after the folder change
(`render-all data/sound/snd/ build/sound_preview/`, same durations
as before the reorganization) and that `mmsnd_tool.py roundtrip-all`
still passes cleanly pointing at each subfolder separately.

Along the way, an inaccuracy in the `.txt` header warning generated
by `mmsnd_tool.py` (`WARNING_BANNER`, turned into
`warning_banner(path)`) was fixed: it used to always cite
`LEVELCYCLE_RESOURCE_TABLE` as the consumer with a fixed address,
which is correct for `.snd` but NOT for `.spt` (whose real consumer
is `SUBPATTERN_TABLE_CB72`, in `madmix1.asm`, not `madmix_scr.asm`)
-- the warning now names the correct table based on the file's
extension.

`README.md` (the `data/sound/` tree with the two subfolders) and
`manuales/manual_driver_sonido.md` (paths updated, a new paragraph in
§6.8 about the subpatterns' files/WAVs) updated.

### Twenty-second round: `CMD_JUMP_TABLE_C99E` reformatted into 15 rows, one per command, with its name/effect in the comment

Same kind of adjustment as the previous rounds on the sound driver's
other tables: `CMD_JUMP_TABLE_C99E` (30 bytes, 15 16-bit pointers,
one per `$80`-`$8E` bytecode command) was dumped across two lines of
16/14 bytes with no relation to its 15 real entries. Reformatted into
15 `DW` lines, one per command, each with the command number, the
opcode, the name and a summary of its mechanical effect -- taken
directly from the already-verified table in `FINDINGS.md` ("The 15
commands"), with cross-references to the real labels each command
reads/modifies (`INSTRUMENT_TABLE_CA6A`, `SHARED_ENVELOPE_TABLE_CA53`,
`ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_RETURN_TABLE_CA61`,
`SUBPATTERN_TABLE_CB72`, `TRANSPOSE_TABLE_CA67`). No new labels were
created for the 15 target addresses (`$C6E5` etc. -- they're
intermediate points inside routines already labeled further up in
the file, `RM_C6xx`/`RM_C7xx`, there's no entry point of their own to
label without cutting into that already-dissected block); the table
still uses literal hex addresses, same as before, just reorganized by
row.

Recompiled: **0 differences** in `MADMIX1.BIN`.
`recursos/flujo_programa.html` regenerated: same total label count
(634, none added/removed -- a pure source-format change).

### Twenty-third round: `RM_TABLE_C8DE` (the 96-note tone-period table) reformatted into one row per note

Same kind of adjustment as the previous three rounds, now on the last
sound-driver table that remained a hex dump with no relation to its
own geometry: `RM_TABLE_C8DE` (192 bytes = 96 words, note+
transposition → PSG tone period) was in 12 rows of 16 bytes.
Reformatted into 96 `DW` lines, one per note (0-95), each with the
value decoded in hex and decimal.

**Extra verification along the way**: the 96 values are strictly
monotonically decreasing (the period drops as the note index rises)
-- confirmed programmatically across all 96, not just by eye. This is
exactly the expected pattern for a rising chromatic scale (PSG period
inversely proportional to frequency), and reinforces the reading
already established in an earlier session that this table is
note→period, not duration (see FINDINGS.md, "IMPORTANT CORRECTION...
the byte <0x80 is NOT a duration, it's the NOTE"). No musical note
names (C, C#, D...) have been assigned to each row -- that would need
additional data (tuning/octave reference) not verified in this
project; the comment sticks to the numeric index (0-95) and the
period, the only thing confirmed by code.

Recompiled: **0 differences** in `MADMIX1.BIN`. No labels added or
removed (634, same as before) -- a pure source-format change. With
this, the 4 sound-driver tables that had hex dumps unrelated to their
documented geometry (`INSTRUMENT_TABLE_CA6A`, `ENV_SHAPE_TABLE_CB5A`,
`SUBPATTERN_TABLE_CB72`, `CMD_JUMP_TABLE_C99E`, and now
`RM_TABLE_C8DE`) are all aligned.

### Twenty-fourth round: applied the real fix for the level 13/14 bug -- the only deliberate deviation from v1.0 in the whole project

After precisely locating v2.0's 5 real fix sites (see the previous
round: 2 already known in `madmix1.asm` -- `TILE_ADDR_CALC`/`0x8BE5`,
`MAP_COORD_TO_ADDR`/`0x8CD4` -- and 3 new ones in `madmix_scr.asm` --
`COORD_TO_ADDR`/`0x5474`, `COORD_TO_ADDR_LOCAL`/`0x556F`,
`LEVEL_LOADER`/`0x591A`) and ruling out that the new code at `$C9BC`
or the `SP` change had any real execution mechanism connected to them
(see the previous round: no call, old or new, points at
`$C9BC-$CA73` anywhere in the whole resident game), the developer
asked to apply the real fix to our source: **`$FC60` -> `$FC50` at
all 5 sites**.

This is the **first and only deliberate deviation** from reproducing
the original v1.0 byte for byte anywhere in the project -- until now
the discipline had always been "reproduce v1.0 exactly as it is, bugs
included, don't fix it" (see earlier rounds on the hidden level, the
`$FC60` bug, etc.). It was applied explicitly at the developer's
request, with the mechanism already confirmed (not a guess): the
active-level buffer (`$FC60`) is too small for level 14's larger
body, and that's why level 13's ball counter never completed
correctly -- moving the buffer 16 bytes earlier (`$FC50`) at the 5
sites where it's recorded as a magic number fixes it, exactly the way
the v2.0 re-release did (a 2013 homebrew CAS/ROM, "fixed by Manuel
Pazos in 2013" per its own credits).

**Documented in the code itself**: each of the 5 sites now carries a
"BUG FIXED" comment explaining the original value (`$FC60`), the
reason, and a cross-reference to the other sites; a note was also
added at the top of both files (`madmix1.asm`/`madmix_scr.asm`)
flagging this as the whole reconstruction's only deliberate
deviation.

**Verified**: both files recompiled, byte-for-byte diff against the
original v1.0 binaries:

- `MADMIX1.BIN`: **exactly 2 differences**, at `$8BE5` and `$8CD4`
  (`$60`->`$50`), none other -- confirms the change had no side effect
  anywhere else in the engine.
- `MADMIX.SCR`: **exactly 7 differences** -- the 4 already-known,
  unrelated ones (`$28ED-$28EF` and the stray byte at `$6500`) plus
  the 3 new expected ones (`$5474`, `$556F`, `$591A`, also
  `$60`->`$50`), nothing more.

`README.md` updated: the "0 differences except 4 unrelated bytes"
claim now explicitly documents these 5 additional bytes as
deliberately fixed, making clear it's the project's only exception
to the faithful-reproduction rule.

**Pending if this is picked back up**: generate a new
`build/madmix_reconstruido.dsk` with this fixed version (the one
already in `build/` predates this fix) if the developer wants to try
it in openMSX.

### Twenty-fifth round: `madmix1.asm` + `madmix_scr.asm` unified into `main.asm` -- cross-file calls now use real labels, and a new file for the tape version

`madmix1.asm` and `madmix_scr.asm` used to compile separately, with
no linker -- any call/pointer from one file to the other couldn't use
a real label, it stayed as literal hex with the real name in a
comment (~45 sites in `madmix_scr.asm` pointing at `madmix1.asm`, ~15
in the opposite direction, plus `LEVEL_TABLE`'s pointers at
levels 13/14). The developer asked to unify both to resolve this, and
to have the same build also generate a file for the tape version --
verified in the previous round that the real `.cas` concatenates its
blocks with NO padding (each block carries its own destination
address in the header).

**Key finding that simplified the implementation**: `madmix_scr.asm`
already used `PHASE $1000` over a physical `ORG $8800` -- the LOGICAL
addresses (which `CALL`/`JP`/pointers resolve against) were already
`$1000+`, identical to how the tape would load that same content
directly. The real body's assembled bytes are EXACTLY the same for
disk and tape -- no need to assemble anything twice, just dump
(`SAVEBIN`) the same already-assembled content with different
framing.

**Architecture implemented**:

- `madmix1_body.asm` / `madmix_scr_body.asm` (new, content moved from
  the old files): only labels+code+data, with no
  `DEVICE`/`ORG`/BLOAD header/`PHASE`/`DEPHASE`/`SAVEBIN`. The one
  name collision found between the two (verified programmatically by
  comparing the full set of top-level labels): `END_OF_FILE` --
  renamed `END_OF_FILE_M1` / `END_OF_FILE_SCR`.
- `main.asm` (new, the real entry point): `INCLUDE`s both bodies in a
  single pass -- they share one symbol space. Generates
  `build/MADMIX1.BIN` and `build/MADMIX.SCR` (same `ORG`/`PHASE`/BLOAD
  header as before, now over the included content) plus
  `build/madmix_cas_scr.bin` (`MADMIX.SCR`'s same logical body, no
  header, for tape).
- `madmix0.asm`: untouched, still compiled separately (disk-exclusive,
  no cross-references with the other two).

**A real technical detail found while implementing** (non-trivial,
worth noting): inside a `PHASE` block, `$` is the simulated LOGICAL
address, but `SAVEBIN` pulls bytes from the real PHYSICAL position
where SjASMPlus wrote them in its internal memory map -- a first
attempt at `SAVEBIN ..., $1000, ...` (the logical address) returned
21760 zeros, because nothing was ever really written at physical
address `$1000` (`MADMIX.SCR`'s body's physical bytes live at `$8807`
onward, right after the BLOAD header at `$8800`). Fixed by adding a
`SCR_BODY_START_PHYS` label right BEFORE `PHASE $1000` (outside the
block, at the real physical address) and using that label as the
tape `SAVEBIN`'s base. It was also verified, with a minimal test
before touching any cross-reference, that SjASMPlus DOES allow two
`ORG` sections within the same pass to occupy overlapping physical
address ranges (`madmix1_body.asm` at physical `$8400-$DDA0` and
`madmix_scr_body.asm` at physical `$8800-$DD00` coexist with no error
-- makes sense: on the real machine they don't coexist at the same
time either, `MADMIX.SCR` occupies that zone transiently before being
relocated and overwritten by the engine).

**Replacing hex with labels**: generated and applied automatically by
cross-checking every `CALL`/`JP`/`JR` with a hex address outside its
own body's range against the unified `.sym` (`build/main.sym`) -- 68
substitutions in `madmix_scr_body.asm`, 17 in `madmix1_body.asm`,
plus `LEVEL_TABLE`'s 2 pointers (levels 13/14, now
`DW BODY_L13_CFA4, ...`/`DW BODY_L14_D244, ...` directly). Exactly 3
addresses are left unconverted, deliberately: `$2C36` (x2, already
documented as "a call into RAM, not static code, unidentified") and
`$0040` (system vector, `JP $0040`) -- neither is a real code label,
they can't and shouldn't be converted.

**Verified at each step** (mechanics first, substitution after,
LEVEL_TABLE last): recompiled and byte-diffed against the original
`.dsk` after each batch -- **always exactly 2 differences in
`MADMIX1.BIN`** (`$8BE5`/`$8CD4`, the already-applied `$FC60`->`$FC50`
fix) **and 7 in `MADMIX.SCR`** (the 4 already-known unrelated ones +
the 3 from the same fix) -- not one difference more, not one less, at
any point in the process. `build/madmix_cas_scr.bin` verified byte
for byte identical to `MADMIX.SCR` minus its 7-byte header (0
differences, 21760 bytes).

**New**: `tools/gen_cas_bin.py` concatenates `madmix_cas_scr.bin` +
`MADMIX1.BIN` (no padding) into `build/madmix_cas.bin` (44705 bytes)
plus a text manifest (`build/madmix_cas.bin.txt`) with the 2 real
destinations/lengths. Pending, out of scope for this round: packing
those 2 stretches into real tape blocks (sync markers, checksum) and
reconstructing `LOAD.BIN`/`TEST.BIN` (the tape loader, today only
analyzed by reading) as its own source.

**Files deleted** (content moved, no longer top-level compilable):
`madmix1.asm`, `madmix_scr.asm`. `README.md` updated (introduction,
file tree, "Compile" section, ~20 loose descriptive references to the
old names).

**Pending follow-up, not resolved this round**: `tools/gen_inventory.py`
assumes 3 separate `.sym` files (one per file) to classify each label
by "source file" in `flujo_programa.html`'s inventory. With `main.asm`
unifying two of the three into a single `.sym` (`build/main.sym`),
that script would need to decide each label's "file" by ADDRESS RANGE
instead of by source `.sym` -- `recursos/flujo_programa.html` has NOT
been regenerated this round, it still reflects the pre-unification
classification (the labels' names/addresses are still correct, only
the inventory's automatic generation would be out of date if
`gen_inventory.py` needed running again as it stands today).

### Twenty-sixth round: full disk and tape loaders reconstructed in `load_disk/`/`load_cas/`, integrated into `main.asm`

The developer created `src/load_disk/` and `src/load_cas/` (empty),
asking to reconstruct everything specific to each version -- the disk
loader (`madmix0.asm`, `.bas`) and the tape loader (`LOAD.BIN`/
`TEST.BIN`, `.bas`, the Topo Soft logo) -- so a single `main.asm`
build generates absolutely everything. `LOGOTOPO.CM` (the logo,
4253/4254 bytes, never analyzed) was deliberately left out
("organize everything except the logo", the developer's explicit
decision).

**First step, technical validation before writing anything real**:
`TEST.BIN` (tape) lives at `$C350`, an address `madmix1_body.asm`
already uses (sound driver, static, no `PHASE`) -- unlike the
already-validated SCR/M1 overlap (two different *representations*,
physical vs. phased), here it would be two UNRELATED contents at the
SAME physical address. A minimal test (an `ORG` overlapped with a
second inner `ORG`, each with its own `SAVEBIN`): confirmed
`SAVEBIN` captures a snapshot of the physical buffer at the moment of
its own call, in SOURCE ORDER, not "whoever writes last wins"
globally -- if one block's `SAVEBIN` runs BEFORE a later block
overwrites that same address, the first one keeps its content intact.
Practical consequence: in `main.asm`, `MADMIX1.BIN`'s block must come
BEFORE `TEST.BIN`'s -- that way the engine's `SAVEBIN` has already
captured the real sound driver at `$C350` before `TEST.BIN` reuses
that same physical address (exactly like on the real machine:
`TEST.BIN` occupies it transiently when booting from tape, then the
engine overwrites it once loaded).

**`madmix0.asm` -> `load_disk/madmix0_body.asm`**: moved following the
same `_body.asm` pattern as the engine/screen (content with no
`DEVICE`/`ORG`/header/`SAVEBIN`), with its two internal `CALL`/`JP`
now using shared labels (`PORTADA_INIT`, `START`) instead of
`$1000`/`$8400`. **A real error made and fixed during this round**:
`MADMIX0.BIN`'s BLOAD header (`DW start,end,exec`) can NOT use the
`RELOCATOR` label as its base -- BLOAD discards the 7 header bytes
before placing the data in RAM, so the REAL load address declared in
the file is `$FA00` (the header's own position), not `$FA07` (where
`RELOCATOR` physically lands in OUR assembly, which does physically
include the header before the body). Using the label first produced
a 51-byte file (missing the whole header) and then, after fixing the
`SAVEBIN`, 3 wrong header bytes (computed with a +7 offset relative
to the correct ones). Fix: a header with literal constants
(`DW $FA00, $FA32, $FA00`, same as the original `madmix0.asm`),
`SAVEBIN` with a `MADMIX0_HEADER_START` label placed INSIDE the `ORG`
(not before -- another one-line error, fixed on the spot: a label
placed before an `ORG` takes the address from before the `ORG`, not
the new one). Verified 0 differences across the full 58 bytes after
fixing both mistakes.

**`LOAD.BIN`/`TEST.BIN` (tape) reconstructed as their own source for
the first time**: until now they were only analyzed in prose
(narrative disassembly in an earlier round). This time the REAL bytes
were extracted from the 1988 `.cas` (locating the "LOAD"/"TEST"-named
blocks by their sync markers, reading each one's 6-byte start/end/
exec header: `LOAD.BIN` $DDA0-$DECA/299B, `TEST.BIN`
$C350-$C44C/253B) and disassembled with `Z80Dasm.exe` byte for byte,
unambiguously. `load_cas/load_bin_body.asm` and
`load_cas/test_bin_body.asm` are that disassembly turned into real
source, with labels for every verifiable internal jump/call.

**Non-trivial finding in `TEST.BIN`**: its last stretch
(`ENASLT_HELPER`, 122 bytes, $C3D2-$C44C) is a TEMPLATE that never
runs at its original position -- `TEST.BIN` copies it with `LDIR` to
a transient work zone at `$AFC8` (outside the game's range) and only
runs it from there. Its 5 absolute `CALL`/`JP` jumps are already
written by the original author for the FINAL post-relocation address
($AFxx/$Bxxx) -- they have to be left as literal hex (using a label
here, even though it "logically" corresponds to a point in this same
block, would produce wrong bytes: our assembler would resolve the
label to its address WITHIN `$C350`, not the real `$AFC8`-relative
address the code expects at runtime). Its 2 `JR`/`DJNZ` jumps
(relative, work the same whether relocated or not) WERE converted to
real labels. Detail documented with comments in the `.asm` itself.

**Transcription errors found and fixed before accepting the
reconstruction** (the usual "reconstruct first, verify after" mode):
in `load_bin_body.asm`, the real order of the 6 "apply page config"
variants (`PAGE_CONFIG_1/2/3` + their 3 unused twins) each has its
own explicit `JR` (there's no fall-through cascade, a first draft
wrongly assumed there was); the `LD B,$0C` instruction was missing
from `TAPE_READ`'s "hooks" loop. Both `test_bin_body.asm` and
`load_bin_body.asm` were missing the real file's last stray byte
(`$E1`/`$00` respectively, after the last real instruction). All
caught by a byte-for-byte diff against the bytes extracted from the
`.cas`, none reached FINDINGS.md unfixed.

**Verified**: `TEST.BIN` (253B) and `LOAD.BIN` (299B) generated by
`main.asm` are byte for byte identical to those extracted from the
1988 `.cas` -- 0 differences in both.

**`AUTOEXEC.BAS`/`MADMIX.BAS` (disk, tokenized) reconstructed as an
editable listing**: a new tool, `tools/msxbasic_tool.py`
(`detok`/`tok`/`roundtrip`). Unlike the other tools
in the project, it does NOT use a full standard MSX-BASIC token table
(risky to reconstruct from memory without a reliable reference) -- it
uses a PARTIAL table with only the tokens EMPIRICALLY verified
against the text already decoded in an earlier round (`BLOAD`, `RUN`,
`DEF`, `USR`, `=`, the 2-byte hex constant with the `$0C` prefix, the
compact integers `$11`-`$1B`=0-10). Any byte outside that set is
represented as a `{$XX}` escape in the listing -- guarantees an exact
roundtrip even for unidentified tokens (several of `MADMIX.BAS`'s
lines 40/50/60, apparently `SCREEN`/`COLOR`/similar, are left with
placeholders instead of guessing values). Roundtrip verified 0
differences in both files (19B and 183B).

A side curiosity: the disk folder ALSO has a file called "MADMIX"
(no extension, 184 bytes) almost identical to `MADMIX.BAS` (183
bytes) but with a different integer value on line 40 (170 vs. 1) --
it isn't part of the real boot sequence (`AUTOEXEC.BAS` calls
`RUN"madmix",R`, which in MSX-DOS BASIC looks for `.BAS` by default),
so it hasn't been reconstructed; left as an observation, not
investigated further.

**`TOPO.bas`/`MADMIX.bas` (tape, already plain ASCII)**: extracted
directly from the 1988 `.cas` (ASCII data blocks with no address
header, unlike the binaries -- confirms the block "type", flagged in
the 10 type-ID bytes before the name (`$EA` vs. `$D0`), is what
determines whether the block carries a start/end/exec header or not)
and copied as-is into `load_cas/`, with no tokenization tool needed.

**`LOGOTOPO.CM`**: copied as-is (unanalyzed, 4254 bytes) into
`load_cas/LOGOTOPO.CM.bin`, with `load_cas/LOGOTOPO.CM.txt` explaining
why (the developer's explicit decision, "organize everything except
the logo") and leaving a visible TODO. `main.asm` does NOT generate
this file yet.

**`main.asm` expanded** with 2 new blocks (`MADMIX0.BIN` deliberately
after `MADMIX1.BIN`, see above; `TEST.BIN`/`LOAD.BIN` after
`MADMIX0.BIN`) -- becomes the ONLY compilation point for disk and
tape (also replaces the separate `sjasmplus madmix0.asm` invocation,
which no longer exists). Re-verified after all the changes:
`build/madmix_reconstruido.dsk` still gives exactly the same 9
already-known differences (offsets
12268/12507/40180-40182/51323/51574/52513/55559), none new.

**Pending follow-up, not resolved this round**: disassembling
`LOGOTOPO.CM` (out of scope, the developer's explicit decision);
semantically identifying `MADMIX.BAS`'s unresolved tokens (lines
40/50/60, probably `SCREEN`/`COLOR`/similar); packing `load_cas/`
into a full real `.cas` with sync markers and checksums
(`gen_cas_bin.py`, from the previous round, only concatenates
engine+screen, doesn't include BASICs/LOAD.BIN/TEST.BIN/logo);
adapting `tools/gen_inventory.py` to address-range classification
(pending since the previous round).

### Twenty-seventh round: build outputs organized into `build/cas/`/`build/disk/`

The developer created `src/build/cas/` and `src/build/disk/`, asking
that the build place each generated binary in the folder matching its
version (tape or disk). `main.asm` (the `SAVEBIN`s), `tools/gen_cas_bin.py`
and the `.dsk`-patching script updated accordingly:

- `build/disk/` -- `MADMIX1.BIN`, `MADMIX.SCR`, `MADMIX0.BIN`,
  `AUTOEXEC.BAS`, `MADMIX.BAS`, `madmix_reconstruido.dsk`: everything
  needed to generate the disk, self-contained.
- `build/cas/` -- `MADMIX1.BIN`, `madmix_cas_scr.bin`, `TEST.BIN`,
  `LOAD.BIN`, `madmix_cas.bin`/`.bin.txt`: everything needed to
  generate the tape, self-contained.

`MADMIX1.BIN` (the game engine, the exact same binary in both
editions, verified in an earlier round) lives DUPLICATED in both
folders -- this round's first design left it shared plainly in
`build/`, but the developer pointed out that then `build/disk/`
wasn't self-contained (you'd have to look outside it to generate the
disk). Fixed: `main.asm` calls the same `SAVEBIN` twice
(`build/disk/MADMIX1.BIN` and `build/cas/MADMIX1.BIN`) -- verified
both copies are byte for byte identical. `gen_cas_bin.py` and the
`.dsk`-patching script updated to each read their own local copy, not
the other one's folder.

Verified after the change: a clean rebuild from scratch produces the
same sizes as always at the new paths, and
`build/disk/madmix_reconstruido.dsk` still gives exactly the same 9
known differences, none new.

**On-the-fly correction, same round**: the developer asked whether
the loose files at `build/`'s ROOT (`m0.sym`, `m1.sym`, `mscr.sym`,
`madmix0.sym`, `madmix1.sym`, `madmix_scr.sym`, `madmix_scr.lst`, and
an old copy of `MADMIX1.BIN`) served any purpose. Checked by deleting
them and rebuilding from scratch (`sjasmplus main.asm`, no flags):
NONE gets regenerated -- they're orphan leftovers from earlier
sessions' loose invocations (from when `madmix0.asm`/`madmix1.asm`/
`madmix_scr.asm` compiled separately), not part of today's
reproducible build process. Deleted.

The developer also clarified `build/cas/`/`build/disk/`'s real
intent: they're for each version's "ingredient" binaries (self-
contained, see above), but the packaged FINAL DELIVERABLE
(`madmix_reconstruido.dsk`, `madmix_cas.bin`) should live at
`build/`'s ROOT, not inside those subfolders. Fixed: `tools/gen_cas_bin.py`
and the `.dsk`-patching script (`build_disk.py`, in the session's
scratchpad, never persisted to the repository) now write their final
output to `build/madmix_cas.bin`/`.bin.txt` and
`build/madmix_reconstruido.dsk` respectively, reading their
ingredients from `build/cas/`/`build/disk/`. Re-verified: same sizes,
same 9 `.dsk` differences, none new.

**Final correction and real progress, same round**: the developer
clarified that `build/madmix_cas.bin` (the intermediate ingredient,
without tape-block formatting) SHOULD stay in `build/cas/` -- what
should go at `build/`'s ROOT was the REAL `.cas`, with genuine tape
blocks (sync/name/header), which until now didn't exist. New
`tools/gen_cas_file.py`: packages `load_cas/TOPO.bas`,
`load_cas/LOGOTOPO.CM.bin` (unanalyzed, verbatim copy),
`load_cas/MADMIX.bas` and `build/cas/LOAD.BIN`/`TEST.BIN`/
`madmix_cas_scr.bin`/`MADMIX1.BIN` into
`build/madmix_reconstruido.cas`, reproducing the 1988 `.cas`'s real
format (sync marker `1F A6 DE BA CC 13 7D 74`; a NAME block for named
files -- type-ID `$EA`x10 for ASCII BASIC, `$D0`x10 for binary, + 6
name characters -- followed by a DATA block: BASIC = text + `$1A`
padding up to 256 bytes; binary = a 6-byte start/end/exec header +
payload; the 2 final unnamed blocks carry raw data).

**A real finding during implementation**: the 2 "raw" (unnamed)
blocks also carry a 1-byte marker (`$FF`) right after SYNC, BEFORE
the real payload -- not documented in any earlier round. Caught by a
1-byte shift across the ENTIRE rest of the reconstructed `.cas` when
first compared (35193 cascading differences, the classic symptom of
"exactly 1 byte missing/extra somewhere earlier"). Fixed by adding
the marker before the payload in both raw blocks.

**Verified, final result**: `build/madmix_reconstruido.cas` (50242
bytes, the EXACT size) compared byte for byte against the original
1988 `.cas`: **only 9 differences, all 3 categories ALREADY known** --
3 bytes at the same relative position as the already-documented
`$28ED-$28EF` (unrelated, preexisting); 5 bytes matching the
deliberate `$FC60`->`$FC50` fix (2 in the ENGINE block + 3 in the SCR
block, the same split as in the `.dsk` comparison); and 1 byte at the
file's last position (the already-known "1-byte difference at
MADMIX1.BIN's last byte", outside the range `LOAD.BIN` actually reads
with `LD DE,$59A0`). **Zero unexpected differences** -- very strong
validation that the WHOLE tape-reconstruction chain (TOPO.bas,
MADMIX.bas, LOAD.BIN, TEST.BIN, unanalyzed LOGOTOPO.CM,
madmix_cas_scr.bin, MADMIX1.BIN, and now the tape-block packaging
itself) is correct start to finish.

**Pending follow-up**: the exact meaning of the raw blocks' `$FF`
marker and of the unexplained irregular tails (`EB 00 00 00 00 00 00`
after the SCR block) hasn't been identified -- preserved as literal
constants copied from the original `.cas`, without deriving them from
the content.

### Twenty-eighth round: unifying the two `tools/` folders into one, at the repo root

The developer noticed there were two `tools/` folders -- one at the
repository root (`madmixgame/tools/`, with only `msxbasic_tool.py`,
created there by oversight in the tokenized-BASIC round) and another
inside `src/` (`src/tools/`, with the rest of the tools:
`gen_cas_bin.py`, `gen_cas_file.py`, `mmlvl_tool.py`,
`mmsnd_render.py`, `mmsnd_tool.py`). Asked to unify them into one, at
the root.

The 5 scripts were moved from `src/tools/` to `tools/` (root);
`src/tools/` removed (it only had a leftover `__pycache__`). Since all
these scripts compute paths relative to their own location
(`os.path.dirname(__file__)`), moving up a folder level breaks those
paths unless adjusted -- fixed by adding an extra `src/` segment to
each one:

- `gen_cas_bin.py`/`gen_cas_file.py`: `build/` -> `src/build/`.
- `mmsnd_render.py`: `data/sound/...` -> `src/data/sound/...` (2
  sites: `ENGINE_FILE` and `scripts_dir`), plus the docstring's usage
  examples updated to paths relative to the repo root.
- `mmlvl_tool.py`: along the way, a real preexisting bug unrelated to
  the move was found and fixed -- `cmd_check_bolitas` was still
  reading `madmix_scr.asm` (a file deleted several rounds ago,
  renamed to `madmix_scr_body.asm` in `main.asm`'s unification) -- the
  `check-bolitas` command had been silently broken for several rounds
  (it had never been invoked again since that unification). Fixed to
  `src/madmix_scr_body.asm`.
- `msxbasic_tool.py`: no changes needed (it takes every path as a
  command-line argument, doesn't compute any relative to itself).

Verified by running all 6 scripts from the new location (`py
tools/name.py ...` from the repo root): `gen_cas_bin.py`,
`gen_cas_file.py` (regenerates the reconstructed `.cas`, same 9
differences as always), `mmlvl_tool.py check-bolitas` (level 1: 114
balls, target 114, OK -- confirms the path fix), `mmsnd_tool.py
roundtrip` and `mmsnd_render.py render` (both on a real script, no
errors). `README.md` updated: a new section in "Structure" showing
`tools/` as a sibling of `src/` at the repository root (previously it
incorrectly appeared as a subfolder of `src/`), and every example
path for commands (`mcopy`, `msxbasic_tool.py`) adjusted to paths
relative to the repo root (with the `src/build/...` prefix where it
applies).

### Twenty-ninth round: `dump_openmsx/`, `manuales/` and `recursos/` also move to the repository root

Same pattern as the previous round with `tools/`: the developer asked
to move these 3 folders from `src/` to the repository root
(`madmixgame/dump_openmsx`, `madmixgame/manuales`,
`madmixgame/recursos`), becoming siblings of `src/` and `tools/`.

Verified before moving that none of the 3 have real relative
references that could break (`href=`, `src=`, `fetch(`, Markdown
links `](../...)`) -- `recursos/`'s `.html` files are self-contained
(no external dependencies, confirmed by grep) and `manuales/` has no
round-trip relative links. Moved with no issues.

Fixed the path mentions that did need adjusting (removing the `src/`
prefix, which no longer applies):

- `src/madmix1_body.asm` (4 comments referencing
  `recursos/ptrtable_sprites.html` and `dump_openmsx/*.png` as
  supporting material for the reader).
- `recursos/mapa_memoria.html`, `recursos/graficos.html`, and their
  copies in `recursos/descartado/` (informational text inside the JS
  data, not real links, but fixed anyway for accuracy).
- `README.md`: a new section in "Structure" showing the 4 folders
  (`tools/`, `recursos/`, `manuales/`, `dump_openmsx/`) as siblings of
  `src/` at the root, removed the duplicate entries left nested inside
  `src/`'s subtree.
- Along the way, in `manuales/README.md` a loose mention of
  `madmix1.asm` (the old name, gone since `main.asm`'s unification
  several rounds ago) was fixed to `madmix1_body.asm`.

**Deliberately NOT touched**: the ~25 mentions of `src/recursos`/
`src/dump_openmsx` inside `FINDINGS.md` (this very file) are left as-
is -- it's a chronological diary, it describes the structure as it
was AT THE TIME of each finding, it isn't rewritten retroactively.
Verified after the move: `sjasmplus main.asm` still compiles with no
errors (0 errors, the same 2 warnings as always).

**Extra cleanup, same day**: the developer asked to also clean up
`build/` (the loose folder at the repository root, different from
`src/build/`) -- it contained binaries and `.sym`/`.lst` files from
very old sessions (`24-26/07`, from when `madmix0.asm`/`madmix1.asm`/
`madmix_scr.asm` compiled separately and the build hadn't yet settled
into `src/build/`). Verified nothing referenced it (neither
`main.asm`, nor any `tools/` script, nor `README.md`) before deleting
it entirely -- 10 files, none irreplaceable (everything regenerable
from today's source code).

### Thirtieth round: `tools/build_all.py` + `tools/gen_disk_and_cas.py` -- finally a real (persisted) script to build and package EVERYTHING

Found while the developer asked "does the project have a script that
builds everything?": the answer was NO -- the step that patches the
original `.dsk` with the recompiled binaries had spent the WHOLE
session (and several earlier ones) living only as a throwaway script
in the conversation's scratchpad, never saved to the repository. Any
regenerated `.dsk` depended on whoever requested it remembering to
rebuild that script from scratch.

Fixed with 2 new scripts in `tools/`, designed to be able to
regenerate the WHOLE project with no dependency on session memory:

- **`build_all.py`**: invokes `sjasmplus main.asm` with the correct
  working directory (`src/`, since `main.asm` uses `SAVEBIN` paths
  relative to the cwd, not its own location) and first creates
  `src/build/disk/`/`src/build/cas/` if they don't exist (`sjasmplus`
  doesn't create subfolders on its own -- a real error found on the
  first test: `error: opening file for write: build/disk/MADMIX1.BIN`
  when testing from a fully deleted `src/build/`).
- **`gen_disk_and_cas.py`**: takes the binaries already compiled in
  `src/build/disk/`/`src/build/cas/` and generates the 2 FINAL
  DELIVERABLES -- `src/build/madmix_reconstruido.dsk` (the patching
  logic that used to only live in the scratchpad, now really
  persisted) and `src/build/madmix_reconstruido.cas` (delegating to
  the already-existing `gen_cas_bin.py` + `gen_cas_file.py`). Checks
  that the ingredients exist before starting and warns with a clear
  message if `build_all.py` needs running first.

**Verified end to end**: `src/build/` deleted entirely, `py
tools/build_all.py` + `py tools/gen_disk_and_cas.py` from scratch
reproduce exactly the same `.dsk` (9 differences, the same as always)
and the same `.cas` (9 differences, the same as always) as every
earlier manual check this session -- the first time the whole flow is
tested with no manual step and no script outside the repository.

### Thirty-first round: the `.dsk` is built FROM SCRATCH -- no longer starting from a copy of the original to patch

The developer, reviewing `gen_disk_and_cas.py`, asked whether
starting from a copy of the original `.dsk` was really needed to
generate the final `.dsk`, and asked for it to be generated from
scratch instead. The `.dsk`'s real FAT12 structure was investigated
(reading the boot sector + BPB + FATs + root directory byte by byte)
to confirm it's fully reproducible: standard 720KB MSX-DOS format
(512B/sector, 2 sectors/cluster = 1024B/cluster, 1 reserved sector, 2
FAT copies of 3 sectors each, 112 root directory entries, 1440 total
sectors, media descriptor `$F9`), with the disk's 6 files assigned
SEQUENTIALLY with no fragmentation (decoding the real FAT12 chains:
MADMIX=cluster 2, MADMIX.BAS=3, MADMIX0.BIN=4, MADMIX1.BIN=5-27,
MADMIX.SCR=28-49, AUTOEXEC.BAS=50 -- exactly what's expected by file
size, no gaps).

**New `tools/gen_dsk_file.py`**: builds the whole `.dsk` (boot sector +
2 FAT12 tables + root directory + data area) from the already-
compiled binaries, with no need for the original `.dsk` as a base.
Only 3 pieces of information CANNOT be derived from anything (they
aren't "game code/data", they're metadata/boilerplate belonging to
the disk format itself or to third parties) and are preserved as
verbatim resources in `load_disk/`, extracted ONCE from the original
`.dsk`:

- **`boot_sector.bin`** (512 bytes): the standard MSX-DOS boot sector,
  generic boilerplate from the formatting tool (an OEM identifier
  "DSKTOOL " embedded in the sector itself), nothing Mad Mix Game
  specific.
- **`MADMIX_dup.bin`** (184 bytes): a SIXTH file the original disk
  has, "MADMIX" with no extension -- almost identical to `MADMIX.BAS`
  but 1 byte longer with a different value on line 40 (170 vs 1). It
  is NOT part of the real boot sequence (`AUTOEXEC.BAS` does
  `RUN"madmix",R`, which in MSX-DOS BASIC looks for `.BAS` by
  default). Possibly a dev/test version left behind by mistake. Not
  analyzed in detail (same treatment as `LOGOTOPO.CM`).
- **`dsk_slack.bin`** (5012 bytes): the cluster-tail padding for the 6
  files (none fills its last cluster exactly). **A real, non-trivial
  finding**: this padding is NOT zero -- the original floppy was
  REUSED MEDIA, with readable leftovers from an earlier, unrelated
  use (file path fragments like
  `...GIF\CRAZE_GAM_JAP_MSX2.GIF` and
  `...GIF\BOMULUS_GAM_ENG_MSX1.GIF`, looking like an MSX ROM
  cataloging/dumping session by whoever originally imaged this disk).
  MSX-DOS never reads past the size declared in the directory, so this
  doesn't affect the game at all -- but without preserving it as-is,
  the generated `.dsk` would be functionally identical but NOT byte
  for byte identical in those zones. Found by diffing: a first
  attempt with zero padding produced 1671 differences (all inside
  these tail zones, never in any file's real content) instead of the
  9 expected -- diagnosed and fixed by capturing the real padding.

`MADMIX1.BIN`'s 7-byte BLOAD header (which its `SAVEBIN` doesn't
include, the same asymmetry as always) is computed in the script
itself from the compiled body's real size (`$FE` + start/end/exec),
with no need to copy it from anywhere -- `MADMIX0.BIN`/`MADMIX.SCR`
already include theirs in their `SAVEBIN`, no need to touch them.

`gen_disk_and_cas.py` simplified: now it only orchestrates
`gen_dsk_file.py` + `gen_cas_bin.py` + `gen_cas_file.py`, with no
patching logic of its own.

**Re-verified after the change**: `.dsk` generated 100% from scratch,
compared byte for byte against the original: exactly the same 9
already-known differences as always (the `$FC60`->`$FC50` fix and the
2 preexisting unrelated bytes), none new -- confirms the understanding
of the FAT12 format and the 3 non-derivable pieces is complete and
correct.

**Immediate simplification, same day**: the developer decided it
wasn't worth preserving the cluster-tail padding (`dsk_slack.bin`,
5012 bytes of "junk" from a reused floppy, with no relation to the
game) just for byte-for-byte fidelity. `load_disk/dsk_slack.bin`/`.txt`
removed; `gen_dsk_file.py` now fills those zones with ZEROS instead
(simpler, with no dependency on the original `.dsk` for them).
Expected, accepted consequence: the byte-for-byte comparison against
the original no longer gives "only 9 differences" -- it gives 1671
(the usual 9 + the full cluster-tail padding of each of the 6 files,
none of it in a zone MSX-DOS ever reads). Documented in `README.md`
so it doesn't read as a regression next time the `.dsk` is compared.

### Extra round: `mainloop_tables.bin` split -- the 3 bytes of real code no longer live mixed in with the data tables

The developer, reviewing `MAINLOOP_TABLES`
(`INCBIN "data/mainloop_tables.bin"`, 176 bytes, `0x2BF0-0x2CA0`),
asked whether the first 3 bytes were real assembly code. Checked by
dumping the real hex: **yes** -- `E1 FB C9` = `POP HL` / `EI` / `RET`,
exactly the same orphan-code pattern (no known caller) already
present at `0xDD93` in `madmix1_body.asm`.

The developer raised a valid methodological doubt before accepting
this: what if those 3 bytes are actually the TAIL of a longer code
sequence starting INSIDE the previous INCBIN
(`data/img/portada_color.img`), and what we thought was "image data"
in its last bytes is actually the start of these same instructions?
Verified by disassembling a combined block (the last 64 bytes of
`portada_color.img` + the first 30 bytes of `mainloop_tables.bin`)
with `Z80Dasm.exe`: `portada_color.img`'s tail disassembles as
totally incoherent noise (`LD B,(HL)` / `LD B,L` / `LD B,H` repeated
with no logical pattern -- typical of compressed image/color bytes,
not real code), while the 3 bytes at `0x2BF0` DO form a coherent,
meaningful sequence (restores the stack, re-enables interrupts,
returns). Confirms the boundary between both files is correct -- the
code fragment starts exactly at `0x2BF0`, not before.

**Fixed**: the 3 code bytes are now written as real instructions in
`madmix_scr_body.asm` (`POP HL` / `EI` / `RET`, with a comment
explaining the finding), the same way it was already done at `0xDD93`.
`data/mainloop_tables.bin` trimmed to 173 bytes (no longer including
those 3 bytes, now expressed as code). The `MAINLOOP_TABLES` label now
points exactly to where the real state variables + tables start
(`0x2BF3`), more precise than before (previously it mistakenly
included the 3 code bytes under a label meant for
"tables").

Verified: recompiled, 0 new differences -- `MADMIX.SCR` still gives
exactly the same 7 already-known differences as always. `.dsk`/`.cas`
regenerated, no change in the expected count.

**Additional confirmation, same day**: the developer noticed these 3
instructions (here and at `0xDD93` in `madmix1_body.asm`) are DEAD --
never called. Verified with an exhaustive `grep` search for
`2BF0`/`DD93` across all of `src/*.asm`: **zero** `JP`/`JR`/`CALL`
references to either address anywhere in the reconstructed source.
Confirmed: it isn't "no caller identified yet", it's genuinely dead
code (probably a leftover from an earlier version of the original
source, whose real entry point was removed or moved at some point
without cleaning up these final 3 bytes -- common in hand-assembled
80s code, since the assembler doesn't strip unreachable code).
Comments at both sites updated to reflect the confirmation instead of
the earlier, more tentative wording.

### Extra round: `mainloop_tables.bin` removed -- all its content becomes native, labeled data in `madmix_scr_body.asm`

The developer, picking `MAINLOOP_TABLES` back up, pointed out that
"this data looks like variables" and that keeping it as an opaque
`.bin` file made no sense -- asked to break it down with comments
explaining what each part is. Since the previous round had already
identified the first 3 bytes as real dead code (`POP HL`/`EI`/`RET`),
they were right: the rest isn't a homogeneous "table", it's fields
each with their own meaning, most of them ALREADY deciphered with real
code in earlier rounds this session (see "The level record's
remaining 13 bytes" and "Deciphered offsets 8/11/18/19 of the level
record").

**Fully rewritten, 173 bytes, in 3 parts**:

1. **`LEVEL_REC_WORK`** (`$2BF3-$2C06`, 20 bytes): the level record's
   20-byte working copy from `LEVEL_TABLE` (confirmed by
   `LD DE,$2BF3 / LDIR` in the level loader) -- each of the 20 fields
   with its own label and comment (`LEVEL_REC_BODY_PTR`,
   `LEVEL_REC_HEADER_PTR`, `LEVEL_REC_ROWS`,
   `LEVEL_REC_ITEM1/2/3_COUNT`, `LEVEL_REC_BLINK_DURATION`,
   `LEVEL_REC_WILDCARD_TILE`, `LEVEL_REC_REF_ROWCOL`,
   `LEVEL_REC_START_POS`, `LEVEL_REC_HUD_ICON`,
   `LEVEL_REC_BALL_TARGET`), using the field-by-field deciphering
   already documented. The VALUES baked into the ROM are just a
   snapshot of the last level processed at compile time (no meaning
   of their own -- a real game always overwrites them when each level
   loads).
2. **In-game state variables** (`$2C07-$2C37`, 49 bytes): individually
   labeled wherever there was already evidence from real code
   (`CURRENT_LEVEL`, `BALLS_EATEN_COUNT`, `BALL_BLINK_POS/TIMER`,
   `SPECIAL_MODE_FLAG/COUNTDOWN/ACTIVE/COLOR_PAIR`, `MOVE_DIRECTION`,
   `SAVED_COLOR`/`CURRENT_COLOR`, `REFERENCE_POINT`, `LIVES_REMAINING`,
   `PENDING_HUD_FLAG`, `FIRST_LOOP_FLAG`, `SPECIAL_MODE`,
   `HINT_POS_TABLE`) -- the gaps with genuinely no access found in the
   code are left as `DS n,$00` with an "unidentified" comment (they
   really are zero, not invented filler). **New finding along the
   way**: `SAVED_COLOR`/`CURRENT_COLOR` ($2C18/$2C24, both `$78` by
   default) and `SPECIAL_MODE_COLOR_PAIR` ($2C16, `$1018`) were
   identified by cross-checking the binary's real values against the
   already-transcribed write sites (`LD BC,$1018` / `LD BC,$1C18` in
   the tank/plane mode handlers) -- previously documented only as
   "ungrouped color variables".
3. **`JR MAIN_LOOP`** (`$2C36-$2C37`, 2 bytes): **a new finding, not
   documented before**. These 2 bytes were already known to be
   "called directly as a CALL into RAM" from 2 sites, with no further
   detail ("$2C36, a call into RAM, not static code, unidentified").
   Verified their default content (`$18,$68`) is NOT noise -- it
   decodes exactly as `JR $2CA0`, the relative jump lands pixel-for-
   pixel on `MAIN_LOOP`. Probably a self-patchable "trampoline"
   (a runtime patching mechanism still unidentified, but the factory
   value is a trivial jump back to the main loop). Written as a real
   instruction (`JR MAIN_LOOP`), not as loose bytes -- the assembler
   resolves it automatically to the same 2 bytes.
4. **Engine tables** (`$2C38-$2CA0`, 104 bytes): no content changes,
   only new real labels (`TILE_DISPATCH_TABLE`, `TILE_DISPATCH_PTRS`
   with `DW SUBTABLE_A/B/C/D` instead of loose hex, and the 4
   sub-tables with their own label).

`data/mainloop_tables.bin` **removed** -- no longer needed, all its
content lives as native data in `madmix_scr_body.asm`.

**Verified**: recompiled, 0 new differences -- `MADMIX.SCR` still
gives exactly the same 7 already-known differences as always
(confirms the 173 hand-rewritten bytes, including the reconstructed
`JR MAIN_LOOP` instruction, are byte for byte identical to the `.bin`
they replace). `.dsk`/`.cas` regenerated with no change in the
expected count.

### Extra round: `mainloop_tables.bin`'s new labels really get substituted throughout the code (231 sites)

The developer correctly pointed out that the labels created in the
previous round (`CURRENT_LEVEL`, `BALLS_EATEN_COUNT`, etc.) weren't
used anywhere -- they only existed at their own definition. If they
were really real variables, the rest of the code had to call them by
name, not keep using loose hex.

**An important correction found while doing this**: searching only
`madmix_scr_body.asm` (as I did in the previous round, guided by
`FINDINGS.md`) was INSUFFICIENT -- many of these variables are read/
written ONLY from `madmix1_body.asm` (they share an address space
because `madmix_scr_body.asm` gets relocated into low memory).
Cross-checking BOTH files with grep turned up real references to
addresses I had mistakenly marked "unidentified" in the previous
round:

- `$2C11-15` (5 bytes I thought were a gap): actually
  `DIR_BEHAVIOR_SELECTOR`, `TILE_TYPE_CACHE`, `TILE_COL_CACHE`,
  `DIR_TABLE_INDEX`, `RAW_DIRECTION` -- all used in `MAIN_LOOP`'s
  direction-dispatch loop.
- `$2C16-17`: was NOT a "color pair" (my initial guess seeing two
  writes, `LD BC,$1018`/`$1C18`) -- it's `CAMERA_POS`, the current
  camera position (confirmed by `LD BC,($2C16) ; current camera
  position` in `MAIN_LOOP`); tank/plane modes simply SET it to a
  specific value while they last.
- `$2C19`: `GAME_STATE_FLAG`, used only from `madmix1_body.asm`.
- `$2C1A/$2C1B`: not just "cleared together with others" as I
  thought -- they're active variables in their own right:
  `FORCED_DIRECTION` (direction forced by arrows) and
  `FORCED_DIR_TIMER` (countdown).
- `$2C1C/$2C1D`: `DIR_INPUT_LATCH`/`INPUT_EDGE_FLAG`, real button-
  press edge-detection logic in `MAIN_LOOP`.
- `$2C1E`: `TRAPDOOR_PHASE`, trapdoor animation variant.
- `$2C22-23` (which I thought was part of a 3-byte gap): `RNG_SEED`,
  the `ITEM_RNG` ($5478) pseudo-random generator's seed.
- `$2C25-26`: `SCROLL_LR_PARAM`, used in `SCROLL_DISPATCH`/`SCROLL_LR`
  (`madmix1_body.asm`) -- its precise meaning is flagged as
  "unconfirmed" already in the existing code, but it's a real
  variable, not a gap.
- `$2C29-2A`: `SCORE_ACCUM`, the game's accumulated score (if it
  reaches 10000/`$2710` it triggers `BESTIA_TEXT`).

The gaps that WERE confirmed genuine (zero references in EITHER file,
verified with cross-file grep): `$2C21`, `$2C28`, `$2C34-35` -- 4
bytes total, far fewer than the ~30 assumed in the first pass.

2 aliases were also added at addresses already labeled for another
reason: `PACMAN_POS` (the same byte as `LEVEL_REC_START_POS`, offset
15-16 of the level record -- Pac-Man/camera's live position gets
referenced DOZENS of times throughout a game, far more than as a
record field) and `RAM_HOOK_2C36` (a label that was missing in front
of the previous round's `JR MAIN_LOOP` instruction, needed to
substitute the 2 `CALL $2C36` sites).

**Substitution applied**: a one-off script (not persisted, session
scratchpad) that splits each line into code+comment (at the first `;`
outside quotes) and substitutes address for label ONLY in the code
part -- comments mentioning the hex address are left intact as a
cross-reference. 231 substitutions total: 174 in
`madmix_scr_body.asm`, 57 in `madmix1_body.asm`.

**Verified**: recompiled, exactly the same already-known differences
as always in both binaries -- **7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`**, none new -- confirms the 231 substitutions are 100%
byte-for-byte equivalent (expected, since substituting a hex address
for a label that resolves to that same address can't change any
generated byte). `.dsk`/`.cas` regenerated, same counts as always
(1671 and 9 respectively).

### Extra round: `recursos/mapa_memoria.html` and `recursos/flujo_programa.html` brought up to date -- `tools/gen_inventory.py` rebuilt and persisted

The developer asked whether the HTML viewers had been kept up to date
throughout this session's progress -- the honest answer was NO. Both
were reviewed:

- **`mapa_memoria.html`**: the `0x2BF0-0x2CA0` entry literally
  described the state BEFORE this session's finding ("the first 9
  bytes are a code tail + completely unidentified filler"). Fixed and
  split into 4 real entries: dead code (`0x2BF0-3`), `LEVEL_REC_WORK`
  (`0x2BF3-2C07`), in-game state variables (`0x2C07-2C36`),
  `RAM_HOOK_2C36` (`0x2C36-8`), and the engine tables
  (`0x2C38-2CA0`).

- **`flujo_programa.html`**: the "634 labels" inventory turned out to
  be a static JS array, generated ONCE by a script (`gen_inventory.py`)
  that was never saved to the repository (the same pattern as the
  `.dsk` patching before this session) -- it had been out of date
  since before `main.asm`'s unification: old file names
  (`madmix_scr`/`madmix1` instead of `madmix_scr_body.asm`/
  `madmix1_body.asm`), line numbers from several rounds ago, and ZERO
  labels from `load_disk/`/`load_cas/` or from `mainloop_tables.bin`'s
  breakdown.

**Rebuilt `tools/gen_inventory.py`, persisted this time**: reads
`src/build/main.lst` (sjasmplus's full listing, generated with
`--lst=`) instead of `--sym` -- the `.sym` only gives name+address,
insufficient now that `main.asm` compiles EVERYTHING in one pass:
several addresses are deliberately REUSED across different source
files (`$C350` is both `madmix1_body.asm`'s sound driver AND
`load_cas/test_bin_body.asm`'s `TEST_BIN_ENTRY`, an overlap already
validated in an earlier round) -- only the listing, with its "# file
opened/closed" markers, unambiguously tells which SOURCE file each
label comes from (by position in the source, not by final address).

**2 real bugs found and fixed while building it** (verified with
targeted tests before trusting the result):

1. The line-parsing regex didn't correctly consume the hex dump
   of generated bytes (variable length, up to 4 hex pairs per listing
   line) before the source text -- on `DB`/`DS` lines that did dump
   bytes, the captured "text" ended up contaminated with those leading
   hex bytes, breaking the "followed by a DB/DW/DS/INCBIN" detection
   (first attempt: the count dropped from 174 to only 20 labels).
   Fixed by changing the regex to explicitly consume 0-4 optional hex
   pairs before the text.
2. A label with a comment on the SAME line (`LEVEL_TABLE:    ;
   300 bytes...`, a very common pattern in this project) was taken as
   if the comment were "the next real instruction", instead of
   continuing the search -- caused dozens of real data labels to
   wrongly fall into "no-ref" (second attempt: the count rose to 99,
   still below expected). Fixed to also skip line remnants starting
   with `;`.

**Final result**: 729 labels (up from 634 -- reflects the new ones
from `load_disk/`/`load_cas/` and `mainloop_tables.bin`'s breakdown),
classified as 93 function / 218 internal / 224 data / 194 no-ref.
Verified against known specific cases (`LEVEL_TABLE`->data,
`RELOCATOR`/`LOAD_BIN_ENTRY`->no-ref same as in the old inventory,
`MAIN_LOOP`->internal, `TEST_BIN_ENTRY`->function, correct file
`test_bin_body.asm` not confused with `madmix1_body.asm` despite
sharing address $C350).

`tools/build_all.py` updated to also generate `src/build/main.lst`
(`--lst=` flag) on every full build, so `gen_inventory.py` always has
fresh data with no separate manual step. `README.md` updated (label
count, a new entry in `tools/`, an explanation of why the listing is
needed instead of the .sym).

**Immediate correction, same day**: the developer found a real gap
in the hex-to-label substitution round -- `$2C38` and `$2C48` (the
addresses of `TILE_DISPATCH_TABLE`/`TILE_DISPATCH_PTRS`) were still
used as literal hex at 4 real code sites (`madmix_scr_body.asm`,
lines ~468/549/1875/1904: `LD HL,$2C38`/`$2C48`), because the
previous round's substitution script only covered the state-variable
range (`$2BF3-$2C37`), not the engine tables' addresses, which had
already been labeled since `mainloop_tables.bin`'s conversion round.
Substituted the 4 sites with `TILE_DISPATCH_TABLE`/`TILE_DISPATCH_PTRS`;
verified by also cross-checking `madmix1_body.asm` (no reference to
those 2 addresses there). Recompiled: the same already-known 7
differences in `MADMIX.SCR`, none new. `.dsk`/`.cas`/HTML inventory
regenerated.

**Another correction, same day**: the developer found `PATCH_OFF_10D8`/
`PATCH_ON_10DE` written as `DB` with literal hex (with a comment
stating the equivalent instruction) instead of real instructions --
the same kind of debt as the dead code at `$2BF0`/`$DD93` from earlier
rounds, but here it IS reachable code (real calls from `TI_CONT`/
`TAIL_LEVELCYCLE_HELPER_ALT`/`TAIL_CREDITS_MAIN`). Rewritten as real
instructions (`LD A,$A2`/`LD ($10E4),A`/`RET` and `LD A,$E2`/
`LD ($10E4),A`/`RET`) and renamed to descriptive names:
`QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` (reflecting what they do -- they
preload the byte the ISR will apply to VDP register 1 on the next
VBLANK, they don't change the screen on the spot). The 9 data bytes
that followed ($10E4 onward) stay as they are, they're genuinely
data, not part of these 2 routines. Updated the 6 sites that called
them (`madmix_scr_body.asm`) and the cross-reference comment in
`madmix1_body.asm`. Verified: recompiled, the same already-known
differences as always in both binaries (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`), none new. `.dsk`/`.cas`/HTML inventory regenerated
(729 labels, same count).

**Third correction, same day**: the developer asked whether the 9
data bytes right after `QUEUE_SCREEN_ON` (`$10E4-$10EC`) were
variables. Reviewed: the FIRST byte (`$10E4`) was already confirmed
from an earlier round (the VDP register 1 value the ISR rereads and
rewrites every VBLANK, see "RESOLVED: the self-modifiable byte
`$10E4`") but still had no label of its own, only mentioned in
comments. Added `VDP_REG1_PENDING` and substituted the 3 real
references (`QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` in
`madmix_scr_body.asm`, the ISR's read in `madmix1_body.asm`). The
following 8 bytes (`$10E5-$10EC`) were re-checked (grep in both
files) -- still no real reference found, they stay as `DB` with the
exact original values and an "unidentified" comment (already
investigated and parked for live tracing in an earlier round, not
resolved by static analysis). Verified: recompiled, the same
differences as always in both binaries, none new. `.dsk`/`.cas`/HTML
inventory regenerated (730 labels, +1 for `VDP_REG1_PENDING`).

### Extra round: `MAIN_LOOP`'s 65 `ML_XXXX` renamed to descriptive names

The developer pointed out the `ML_` + hex-address convention (e.g.
`ML_2CAD`) carries no self-explanatory information, and asked to
clean it up starting with `MAIN_LOOP` (the project's other similar
conventions -- `JTS2_`, `RM_`, `GH_`, `TI_`, `KMD_`, `H5278_`, etc. --
are left for a future round, a scope explicitly agreed with the
developer).

The whole collision/movement engine (`MAIN_LOOP`, `0x2CA0-0x335C`,
~1200 lines) was read to understand each of the 65 `ML_XXXX` labels'
real role before renaming -- no guessing, using the comments already
there (this stretch was already very well documented from earlier
rounds). All renamed to names reflecting their real function, grouped
by block:

- Preamble (direction/input decision, alignment, dispatch):
  `ML_READ_REAL_INPUT`, `ML_STORE_DIRECTION`, `ML_LATCH_CLEAR`,
  `ML_LATCH_STORE`, `ML_ALIGN_START`, `ML_ALIGN_CHECK_Y`,
  `ML_ALIGN_APPLY`, `ML_DIR_FINALIZE`, `ML_TILE_TYPE_INDEX`,
  `ML_DISPATCH_LOOKUP`.
- Active special-mode management (power ball/hippo):
  `ML_SPECIAL_MODE_TICK`, `ML_POWER_BLINK_COLOR`, `ML_POWER_MODE_END`,
  `ML_HIPPO_MODE_TICK`, `ML_HIPPO_BLINK_ICON`, `ML_HIPPO_MODE_END`.
- Direction sub-table + scroll/items: `ML_DIR_SUBTABLE_LOOKUP`,
  `ML_DIR_SUBTABLE_LOOP`, `ML_DIR_BEHAVIOR_STORE`, `ML_SCROLL_PREP`,
  `ML_SCROLL_DISPATCH_CALL`, `ML_SCROLL_AND_ITEMS`.
- Active-trapdoor loop: `ML_TRAPDOOR_LOOP`,
  `ML_TRAPDOOR_FORMAT_B`, `ML_TRAPDOOR_FORMAT_B_POS`,
  `ML_TRAPDOOR_ROW_FIXED`, `ML_TRAPDOOR_DRAW`, `ML_TRAPDOOR_NEXT`.
- `CHECK_TILE_DELTA`/`DRAW_TILE_HELPER` internals:
  `ML_DELTA_CHECK_LEFT/DOWN/UP`, `ML_DELTA_RESOLVE`,
  `ML_DELTA_MASK_RESULT`, `ML_DRAWTILE_COL_CHECK`, `ML_DRAWTILE_REDRAW`.
- Tails of the 16 tile-type handlers (each returns to the main
  dispatch): `HANDLER_2EB7_CONT`, `HANDLER_2EC7_EXIT`,
  `HANDLER_2EFC_EXIT`, `HANDLER_2F18/2F50/2F88/2FC0_EXIT`,
  `HANDLER_2FF8_MODE_CHECK/ACTIVATE/TAIL`, `HANDLER_3067_ACTIVATE/LOOP`,
  `HANDLER_30F3_EXIT`, `HANDLER_311B_EXIT`, `HANDLER_315D_EXIT`,
  `HANDLER_318E_EXIT`, `HANDLER_31B7_PLANE_CHECK/LOOP`.
- Shared "exit special mode" tail (used by several handlers):
  `SPECIAL_MODE_EXIT_TAIL`, `SPECIAL_MODE_EXIT_REENTER`.
- Internal `TRAPDOOR_FLIP_TABLE`: `TRAPDOOR_FLIP_SCAN/SET/STORE`.
- Forced-direction countdown: `FORCED_DIR_TIMER_TICK`,
  `FORCED_DIR_CLEAR`, `FORCED_DIR_TICK_DONE`.
- Trapdoor opening/closing animation (types 17-19):
  `TRAPDOOR_ANIM_OPEN_A/B`, `TRAPDOOR_ANIM_CLOSE_A/B`,
  `TRAPDOOR_ANIM_EXIT`.

Applied with a global substitution script (whole word, in BOTH
files -- a cross-reference mention in a `madmix1_body.asm` comment
also updated) -- unlike the hex-to-label round, comments ARE touched
here (they're references by NAME, not hex addresses, so they'd be out
of date/misleading if not updated too).

**Along the way, 4 loose hex calls found and fixed** in the same
stretch (`CALL Z,$51FE`/`$54A9`/`$55C0`/`CALL $5782`, 3 sites each):
they already had a real label (`R51FE_MAIN`, `ITEM_HANDLER_1`,
`ITEM_HANDLER_2`, `ITEM_TIMER_TICK`) but hadn't been substituted at
these 12 call sites.

Also updated 2 header comments describing the old convention
("ML_XXXX labels = real address (hex)...") and the warning about "not
confusing the table index with the handler's address" (still valid,
but now referring to the new NAMES, not to them being hex).

**Verified**: recompiled, the same already-known differences as
always in both binaries (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`), none
new -- 215 name substitutions + 12 hex-to-label ones, zero byte
changes. `.dsk`/`.cas`/HTML inventory regenerated (730 labels,
function count rises from 93 to 97 for the 4 newly-labeled calls).

**Pending, scope agreed with the developer**: the project's other
`PREFIX_hex` conventions (`JTS2_`, `RM_`, `GH_`, `TI_`, `KMD_`,
`H5278_`, `H53A2_`, `H5414_`, `IH1_`/`IH2_`, etc., several hundred
labels) are left for a future round -- deliberately started with just
`MAIN_LOOP` to validate the naming criteria before scaling up.

### Extra round: the 14 `HANDLER_XXXX` (tile-type handlers) renamed to `HNDLR_` + a descriptive Spanish name

After the `ML_XXXX` rename in `MAIN_LOOP`, the developer asked to
continue with the tile-type handlers (`HANDLER_2EB7`, `HANDLER_2EC7`,
etc. -- `ML_DISPATCH_TABLE`'s 14 entries), this time with names in
**Spanish** (unlike the `ML_` round, where English was chosen
following the project's dominant convention) -- an explicit
divergence requested by the developer for this specific group, with 3
examples given literally: `HANDLER_2EC7` -> `HNDLR_BOLITA_NORMAL`,
`HANDLER_2EFC` -> `HNDLR_BOLITA_CLAVADA`, `HANDLER_2F18` ->
`HNDLR_FLECHA_ARRIBA`.

Full map applied (14 base handlers, per the tile type each one
handles in `ML_DISPATCH_TABLE`, documented in `madmix_scr_body.asm`'s
comment block ~line 793-806):

| Old label  | New label            | Tile type(s) |
| ----------------- | ---------------------------- | ------------------- |
| HANDLER_2EB7    | HNDLR_SUELO_NORMAL          | 0, 8, 9 (normal wall/floor + ghost-house door electric line, no logic of its own) |
| HANDLER_2EC7    | HNDLR_BOLITA_NORMAL         | 1 (normal ball) |
| HANDLER_2EFC    | HNDLR_BOLITA_CLAVADA        | 2 (pinned/fixed ball) |
| HANDLER_2F18    | HNDLR_FLECHA_ARRIBA         | 3 |
| HANDLER_2F50    | HNDLR_FLECHA_ABAJO          | 4 |
| HANDLER_2F88    | HNDLR_FLECHA_IZQUIERDA      | 5 |
| HANDLER_2FC0    | HNDLR_FLECHA_DERECHA        | 6 |
| HANDLER_2FF8    | HNDLR_PISTA_TANQUE          | 7 (vertical tank track) |
| HANDLER_3067    | HNDLR_PISTA_AVION           | 10 (plane track) |
| HANDLER_30F3    | HNDLR_ITEM_SUELO            | 11 (not-fully-confirmed floor item) |
| HANDLER_311B    | HNDLR_BOLA_PODER            | 12 (real power ball) |
| HANDLER_315D    | HNDLR_HIPOPOTAMO            | 13 (hippo item) |
| HANDLER_318E    | HNDLR_HERRAMIENTA           | 14 (tool item) |
| HANDLER_31B7    | HNDLR_SUELO_SIN_BOLA        | 15, 16 (floor without ball/loose wall + solid black tile) |

And its 18 associated sub-labels (tails returning to the main
dispatch, created in the previous `ML_` round), renamed accordingly
(same suffix, new prefix): `HNDLR_SUELO_NORMAL_CONT`,
`HNDLR_BOLITA_NORMAL_EXIT`, `HNDLR_BOLITA_CLAVADA_EXIT`,
`HNDLR_FLECHA_ARRIBA_EXIT`, `HNDLR_FLECHA_ABAJO_EXIT`,
`HNDLR_FLECHA_IZQUIERDA_EXIT`, `HNDLR_FLECHA_DERECHA_EXIT`,
`HNDLR_PISTA_TANQUE_MODE_CHECK`, `HNDLR_PISTA_TANQUE_ACTIVATE`,
`HNDLR_PISTA_TANQUE_TAIL`, `HNDLR_PISTA_AVION_ACTIVATE`,
`HNDLR_PISTA_AVION_LOOP`, `HNDLR_ITEM_SUELO_EXIT`,
`HNDLR_BOLA_PODER_EXIT`, `HNDLR_HIPOPOTAMO_EXIT`,
`HNDLR_HERRAMIENTA_EXIT`, `HNDLR_SUELO_SIN_BOLA_PLANE_CHECK`,
`HNDLR_SUELO_SIN_BOLA_PLANE_LOOP`.

Applied with a global substitution script (whole word, keys sorted by
descending length so a sub-label like `HANDLER_31B7_PLANE_CHECK`
never gets "shadowed" by its `HANDLER_31B7` prefix in the regex
alternation -- though in practice `\b` already prevented that, since
`_` is a word character). BOTH files are touched, and comments too
(name references, same criteria as the `ML_` round): 124 substitutions
in `madmix_scr_body.asm`, 5 in `madmix1_body.asm` (`SOUND_EVT*`
comments citing the handler tied to each sound effect), 129 total.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs against the original binaries at the exact usual
baseline -- 7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN` (comparing the body
after the 7-byte BLOAD header) -- zero new differences. `.dsk`/`.cas`
regenerated (`py tools/gen_disk_and_cas.py`). HTML inventory
regenerated (`py tools/gen_inventory.py`): same total of 730 labels
(function=97, internal=218, data=225, no-ref=190) -- the rename
doesn't change classification, only names.

**Pending, same agreed scope as the `ML_` round**: the project's
other `PREFIX_hex` conventions (`JTS2_`, `RM_`, `GH_`, `TI_`, `KMD_`,
`H5278_`, `H53A2_`, `H5414_`, `IH1_`/`IH2_`, etc.) remain out of scope
until the developer asks to continue.

### Extra round: `TRAPDOOR_ANIM_OPEN_A/OPEN_B/CLOSE_A/CLOSE_B` renamed to `HNDLR_TRAMPILLA_*` (tile types 17-19), with a laterality correction

The developer raised the hypothesis that these 3 entries were
"trapdoor open-left / open-right / closed" and asked to verify whether
the left/right pairing was correct. Cross-checking against the tile
catalog (`TILE_TYPES` in `madmix1_body.asm` ~line 3060-3072, the
source of truth for tile names) confirmed the general idea was right
but the pairing was REVERSED relative to the initial hypothesis:

- Tile 68 = `trampilla_a_abajo_derecha` -> tile type 17 -> dispatched
  by the entry that was `TRAPDOOR_ANIM_OPEN_A`
- Tile 73 = `trampilla_b_abajo_izquierda` -> tile type 18 ->
  dispatched by the entry that was `TRAPDOOR_ANIM_OPEN_B`
- Tiles 78/79 = `trampilla_transicion_abajo_izquierda/derecha` -> tile
  type 19 -> dispatched by the entry that was `TRAPDOOR_ANIM_CLOSE_A`

In other words, `OPEN_A` = opening to the RIGHT (not left) and
`OPEN_B` = opening to the LEFT (not right).

A non-obvious nuance was also found: `CLOSE_A`/`CLOSE_B`'s A/B letter
does NOT correspond to the same side as `OPEN_A`/`OPEN_B`'s A/B --
it's reversed. `HNDLR_TRAMPILLA_CERRADA` (previously `CLOSE_A`) is the
ONLY `ML_DISPATCH_TABLE` entry for type 19 (closing, both sides share
this same "transition" tile), and internally decides which drawing
variant to use by reading `TRAPDOOR_PHASE` (the phase the previous
opening left set: $01 if `HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA` opened
it, $02 if `HNDLR_TRAMPILLA_ABIERTA_DERECHA` opened it). If the phase
is 2 (opened from the right) it jumps to the `_B` variant to draw that
closing; if it's 1 (opened from the left) it stays in
`HNDLR_TRAMPILLA_CERRADA`'s own body. Documented with an explicit
comment in the code so this detail isn't lost in the future.

Map applied:

| Old label           | New label                       |
|---------------------------|---------------------------------------|
| TRAPDOOR_ANIM_OPEN_A       | HNDLR_TRAMPILLA_ABIERTA_DERECHA       |
| TRAPDOOR_ANIM_OPEN_B       | HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA     |
| TRAPDOOR_ANIM_CLOSE_A      | HNDLR_TRAMPILLA_CERRADA               |
| TRAPDOOR_ANIM_CLOSE_B      | HNDLR_TRAMPILLA_CERRADA_B (an internal variant, not its own dispatch-table entry) |

`TRAPDOOR_ANIM_EXIT` (the return tail shared by all 3, similar to
`SPECIAL_MODE_EXIT_TAIL`/`FORCED_DIR_TIMER_TICK`) is left unrenamed --
following the same criteria as earlier rounds of not touching shared
tails that already had their own descriptive name.

21 substitutions (19 in `madmix_scr_body.asm`, 2 in
`madmix1_body.asm`, whole word, also touching comments). Also updated
the header comment block (~line 701 and ~1442) to reflect the new
names and the laterality/`_B`-variant explanation.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`). `.dsk`/`.cas` and HTML inventory regenerated: same
total of 730 labels (function=97, internal=218, data=225, no-ref=190).

### Extra round: the 8 bytes at `$10E5-$10EC` labeled `VDP_SCR2_REGS_TABLE` (a strong hypothesis, no confirmed reader)

In-depth analysis of the 8 unidentified bytes following
`VDP_REG1_PENDING` (`$02, $E2, $06, $80, $00, $36, $07, $11`). 2
competing hypotheses were considered:

1. **Dead code**: decodes into 4 valid Z80 instructions (`LD (BC),A`
   / `JP PO,$8006` / `NOP` / `LD (HL),$07`) + 1 incomplete byte
   (`$11`, the start of `LD DE,nnnn` whose operand already falls
   inside `portada_patron.img`). Ruled out: the jump target, `$8006`,
   falls BEFORE where `MADMIX1.BIN` starts (`ORG $83F9`) -- an empty
   zone with no known real code, making no sense as a `JP` target.
2. **VDP R0-R7 register table for SCREEN 2**: `R1=$E2` (screen on,
   matches the value `QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` use),
   `R2=$06` (name table at `$1800`, `$1800/$400=6`), `R3=$80` (color
   table at `$2000`, bit7=high block), `R4=$00` (pattern table at
   `$0000`) -- all 4 match EXACTLY the VRAM layout `PORTADA_INIT` sets
   by hand a bit further up (same file, a few lines earlier). Too much
   of a coincidence to be chance.

It was also ruled out that accessing `VDP_REG1_PENDING` (the previous
byte, `$10E4`) could touch these 8 bytes indirectly: its 3 real
references (`madmix1_body.asm`'s ISR + 2 sites in
`QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON`) all use direct absolute
addressing (`LD A,(VDP_REG1_PENDING)`/`LD (VDP_REG1_PENDING),A`,
3-byte opcodes with final data `$E4,$10`), none uses a pointer (`HL`)
that could overflow into higher addresses.

**Developer's decision**: the VDP register-table hypothesis is "the
most reasonable, too much matching data". Labeled `VDP_SCR2_REGS_TABLE`
with a per-register comment (R0-R7) and an explicit note that it still
has no confirmed reader -- no loop was found in any source file
(`madmix_scr_body.asm`, `madmix1_body.asm`, `load_disk/`, `load_cas/`)
reading it; the most plausible explanation is that the screen already
arrives configured this way via MSX-BASIC's `SCREEN 2` (run by
`AUTOEXEC.BAS`/`MADMIX.BAS` before the `BLOAD`), and this table would
be a copy unused by the game itself (a leftover from an earlier
version that applied it with a generic loop, later replaced by the
manual `OUT`s seen in `PORTADA_INIT`/`VDP_WAIT_READY`/
`VDP_ENABLE_DISPLAY`).

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`). `.dsk`/`.cas` and HTML inventory regenerated: 731
labels (up from 730), the `data` category rises from 225 to 226 for
the new label.

### Extra round: the hidden level DOES have a real record in `LEVEL_TABLE` -- it was record 15, mislabeled as "20 bytes unidentified"

The developer asked to analyze `$5AD5-$5AE8` (20 bytes documented
until now as "unidentified data, before the first code stretch" of the
menu/credits zone). The key lead: `LEVEL_TABLE` ends EXACTLY at
`$5AD5` (300 bytes = 15 records of 20 bytes each) -- these 20 bytes
are the EXACT same size as a level record.

**Decoded with the same field format as the 15 documented records**:

```text
DW $48BC, $50BC, $50BC   ; body, header(top), header(bottom)
DB 18, $01               ; field6=variable rows (total=21), field7 unidentified
DB 3, 1, 1                ; type 3/1/2 items
DB $96                    ; blink duration (150 frames)
DB $3F                     ; wildcard tile
DB $60, $30                ; initial reference row/column
DB $48, $10                ; offsets 15-16, unidentified (same as the rest)
DB $70                     ; HUD icon
DW 165                     ; ball target
```

`$48BC` is EXACTLY `BODY_HIDDEN_48BC` (the 15th maze, already
confirmed playable in an earlier session by patching a copy of the
`.dsk`). `$50BC` is EXACTLY `HEADER_50BC` (the same shared header
used by levels 0/1). Every other field falls within ranges identical
to the rest of the levels' (wildcard tile `$3F`, HUD icon `$70` --
same values as levels 0/1). **It isn't noise: it's a complete, valid,
well-formed level record.**

**And it's REACHABLE in normal play**, not just "format-compatible".
Verified by cross-checking 2 routines:

- `LEVEL_LOADER` (`madmix_scr_body.asm`, `$5A76` approx.) computes the
  record's address as `LEVEL_TABLE + CURRENT_LEVEL*20` (a loop adding
  20, `CURRENT_LEVEL` times) -- **with no cap of its own**, the
  comment that said "current level number (1-14, 0 is dead)" didn't
  reflect the code's actual range.
- `IML_90B7` (`madmix1_body.asm`), on completing a level: `INC (HL)`
  on `CURRENT_LEVEL`, then `CP $10` (16) -- if it's NOT 16, it
  continues WITHOUT resetting. In other words: on completing level
  14, `CURRENT_LEVEL` becomes 15, the check (`15 != 16`) does NOT
  reset it, and the next level load uses `CURRENT_LEVEL=15`, reading
  exactly this record. It only resets to 1 on the NEXT lap, if level
  15 is ALSO completed.

**Conclusion**: the real game has **15 playable levels**, not 14 --
the last one (the Pac-Man-shaped maze, already rendered in
`recursos/nivel_oculto.html`) is really played by completing the 14
"normal" levels in a single game without breaking the cycle. This
document's own old section ("PENDING RESOLUTION: 15 gaps... the
hidden level has no gap referencing it") proposed manually building a
new record to achieve this -- that proposal is now **obsolete**: the
record already existed in the original binary all along, it was just
misclassified.

**Changes**: in `madmix_scr_body.asm`, the 20-byte block is rewritten
with `DW BODY_HIDDEN_48BC, HEADER_50BC, HEADER_50BC` + the remaining
fields broken down the same way as the rest of the levels (no longer
an anonymous `DB`, the assembler resolves the pointers);
`LEVEL_TABLE`'s header comment updated (300->320 bytes, 15->16
records, "14 levels"->"15 levels"); `LEVEL_LOADER`'s comment fixed
(real range 1-15); `IML_90B7`'s comment expanded explaining why it
doesn't reset at 15. `README.md` updated (file tree,
`niveles.html`'s description) to reflect 15 real levels instead of
"14 + 1 unused hidden one".

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- only labels/comments over already-existing bytes,
zero content changes. `.dsk`/`.cas`/HTML inventory regenerated: same
total of 731 labels (this record doesn't create a new label, it
follows the same anonymous pattern as the rest of `LEVEL_TABLE`'s
records, which also have no individual per-level label).

**Pending, minor**: it would be interesting in the future to render/
count real balls in the hidden maze (`data/niveles/`, if it ever gets
extracted as its own file like the other levels) against the
just-decoded `165` target, for an extra cross-check -- non-blocking,
the finding is already confirmed by the body/header pointers'
exact match.

### Extra round: `body_hidden_48bc.bin` renamed to `body_l15.bin`, the levels HTML updated, and the header+body+footer structure confirmed

After confirming level 15 (previously "hidden") has a real record in
`LEVEL_TABLE`, the file and label are renamed so they stop sounding
like a "separate finding" and become just another level, like
`BODY_L01`..`BODY_L14`:

- `data/niveles/body_hidden_48bc.bin` -> `data/niveles/body_l15.bin`
  (same 576 bytes, no content changes). Twin `.txt` regenerated with
  `mmlvl_tool.py disasm` (18 rows x 32 columns).
- Label `BODY_HIDDEN_48BC` -> `BODY_L15` in `madmix_scr_body.asm`
  (definition + 3 references: the levels header comment,
  `LEVEL_TABLE`'s header comment, and record 15 itself) and in
  `madmix1_body.asm` (`IML_90B7`'s cross-reference comment).
- **Exact cross-check**: `mmlvl_tool.py check-bolitas body_l15.txt
  15` counts **165 real balls** in the body, matching EXACTLY the 165
  target decoded in `LEVEL_TABLE`'s record -- fully confirms the
  finding, beyond the already-verified pointer match. `mmlvl_tool.py`'s
  hard cap was also updated (previously `>= 15` records when reading
  `LEVEL_TABLE`, now `>= 16`) and its docstring (level range 0-15).

**A question raised by the developer, verified in the code**: each
level is NOT composed of just header+body -- `LEVEL_LOADER`
(`madmix_scr_body.asm`) does 3 copies in this order: TOP header
(offset 2, 96 bytes) -> body (offset 0, variable rows) -> BOTTOM
header (offset 4, another 96 bytes, a genuine FOOTER identical in
format to the header). Also confirmed that, across all 16
`LEVEL_TABLE` records (including the new level-15 one), the top and
bottom headers are ALWAYS the same pointer -- they never differ.

**`recursos/niveles.html` updated**: level 15 becomes just a normal
`LEVELS` entry (composed of `header_50bc.bin` + `body_l15.bin`, same
"top header + body, no footer" criteria the other 15 entries use),
shown AT THE END as "Level 15" with a notice explaining the
resolution -- the separate `HIDDEN_LEVEL` object, the
`buildHiddenLevelCard()` function, the `i===10` insertion hook
(which placed it at its real memory position, between level 10 and
11) and the now-unused `.hidden-level`/`.badge-hidden` CSS classes
are removed. The HTML's 2 intro notes are rewritten to reflect the
correct conclusion (16 records, not 15; the repeated "footer"; level
15 real and playable, not hidden).

**`recursos/editor_niveles.html`**: level 15's descriptive text was
fixed (filename, real ball target, reachable in normal play). The
embedded data block (`LEVEL_FILES`, JSON with each `.bin`'s hex,
generated in a past session with no known generator script) still
uses the old name/metadata (`ballTarget: null`, `hiddenUnwired: true`)
-- **pending**, not hand-touched due to the risk of corrupting the
hex; left noted in the HTML itself.

**Verified**: recompiled with no errors, the same differences as
always in both binaries (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).
`.dsk`/`.cas`/HTML inventory regenerated: same total of 731 labels.

### Extra round: `ITEM_TABLE_POS_511C` reanalyzed -- the 7-byte structure confirmed, one misidentified field fixed, and 2 auxiliary tables labeled for the first time

The developer asked to reanalyze `ITEM_TABLE_POS_511C` and the next
block (170 bytes at `$5154-$51FD`) to reorganize them with real
comments. Cross-checking `HELPER_5278`/`HELPER_53A2`/`TABLE_INIT`
against `ITEM_TABLE_1`/`ITEM_TABLE_2` (same 7-byte structure,
confirmed) established each of the 8 entries' real format:

```text
offset 0: X position (whole tile)
offset 1: Y position (whole tile)
offset 2: mode/behavior (0=actively chasing -- the only real value
          for type-3 items; 1/2="planted", exclusive to
          ITEM_TABLE_1/2, never this table)
offset 3: current movement-direction code (1/2/4/8)
offset 4: sub-position X (fractional part)
offset 5: sub-position Y (fractional part)
offset 6: animation phase (0-3, rotating)
```

**Important correction**: offset 6 used to be documented in an old
round as "variable final field (item type, 0-3)" -- rereading
`R51FE_MAIN` confirms it's actually the ANIMATION PHASE
(`LD A,(IX+6); INC A; AND $03; LD (IX+6),A`, incremented every time
the entry is processed) -- the different compiled values across the 8
entries (1,2,3,1,2,1,0,1) are just so they don't all animate in sync,
not a "type" of anything.

**The 170-byte block ($5154-$51FD) turned out to have 3 parts, not
2**:

1. `ITEM_MODE_SPRITE_PTRS` ($5154, 32 bytes = 16 words, new label):
   indexed by `(offset2 AND $0F)*2` from `R51FE_MAIN`. In practice
   ONLY entry 0 is ever checked (offset2 never changes from 0 for
   type-3 items) -- and that entry 0 is self-referential (`$5156`,
   falls inside the table itself). Entries 1-15 (never reached at
   runtime) are candidates for inheritance from an earlier engine
   version.
2. **An unexplained 10-byte gap** ($5174-$517D:
   `A2,A2,23,23,24,24,1F,1F,20,20`) -- discovered by precisely
   recalculating where the next real table starts (`$517E`, not
   `$5174` as the old "32 bytes" comment suggested). Has the same
   "shape" (repeated byte pairs) as `ITEM_MODE_SPRITE_PTRS` but falls
   outside its indexable range and before the next table -- no real
   reference found.
3. `ITEM_DIR_CHOICE_TABLE` ($517E, 128 bytes, new label): indexed by
   `HELPER_5278` as
   `(free directions)<<3 | (alignment gate)<<1 | (random bit)`
   -> the chosen final direction. Content verified consistent with
   the algorithm, not decoded row by row (128 possible combinations).

The 2 loose hex references (`LD HL,$5154` in `R51FE_MAIN`,
`LD HL,$517E` in `HELPER_5278`) were substituted with the new labels.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- only labels/comments over already-existing bytes,
zero content changes. `.dsk`/`.cas`/HTML inventory regenerated: 733
labels (up from 731, +2 for `ITEM_MODE_SPRITE_PTRS`/
`ITEM_DIR_CHOICE_TABLE`), the `data` category rises from 226 to 228.

### Extra round: `ITEM_DIR_CHOICE_TABLE` fully decoded -- it's data, and its "gate" turned out to be the previous direction, not a simple alignment flag

The developer asked whether `ITEM_DIR_CHOICE_TABLE` was code or data.
Confirmed it's pure DATA (only ever read with `LD A,(HL)`, no
`JP`/`JR`/`CALL` anywhere in the project points there).

Reorganizing its 128 bytes into 16 blocks of 8 (one per "free
directions" combination, the bitmask already known to form the
index's high half), it turned out the previous round's comment
("alignment gate", a simple 0/1 bit) was INCOMPLETE: following the
real code (`H5278_531E`), the E value contributing bits 1-2 of the
index comes from `TILE_DISPATCH_TABLE[(IX+3)]` (the movement
direction ALREADY in progress, offset 3 of the 7-byte item record) --
not a binary flag. `TILE_DISPATCH_TABLE` at indices 0/1/2/4/8 holds
`$00/$01/$02/$03/$04`; after `SUB $01` (clamped to 0 on carry) and
`ADD A,A` (doubled), the result is `0/0/2/4/6` depending on whether
the previous direction was none-or-right/left/down/up respectively --
in other words, it DOES occupy bit 2 of the final index in certain
cases (contrary to what was thought: there's no "half of the table
never read", all 128 bytes ARE reachable).

**Real structure, confirmed byte for byte**: each of the 16 8-byte
blocks splits into 4 pairs (a random bit breaks the tie within the
pair): pair0 = if there was no previous direction or it was going
right, pair1 = if it was going left, pair2 = if it was going down,
pair3 = if it was going up. The real content confirms it's a "keep
the movement direction if it's still free, otherwise pick another
free one" table (continuity bias): when only ONE direction is free in
the block, all 8 bytes are identical to that direction regardless of
what the previous one was; when there are several, each pair tends to
return the same direction that was in use if it's in the free set.

The full table was rewritten as 16 `DB` of 8 bytes (previously rows
of 16 bytes not aligned to this structure), each commented with its
free-directions bitmask and the 4 pairs' detail. Fixed 2 code
comments that still talked about an "alignment gate"
(in `H5278_531E`/`H5278_532D` and in the `LD HL,ITEM_DIR_CHOICE_TABLE`)
to reflect that it's the categorized previous direction.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- the restructuring preserves exactly the same 128
bytes in the same order, zero content changes. `.dsk`/`.cas`/HTML
inventory regenerated: same total of 733 labels (no new labels added,
only existing `DB` rows reorganized).

### Extra round: `ITEM_MODE_SPRITE_PTRS` fully resolved -- the "self-referential pointer" was the real mechanism, and confirms the horizontal flip (bit7) without live tracing

The developer asked to reanalyze `ITEM_MODE_SPRITE_PTRS` to organize
and comment it. The previous round had already noticed entry 0
pointed inside the table itself but left it as "candidate, detail
unconfirmed". Tracing the real use of the word read (register DE) in
`R51FE_MAIN` confirms it's NOT a choice among "16 mode pointers": it's
A SINGLE pointer (self-referential, deliberately) to which
`direction(1-4)*4 + phase(0-3)` gets ADDED to read the final sprite --
in other words, the whole table is: a pointer to itself (2 bytes) +
the real sprite data for the 4 directions (2 frames each).

**Fix to an existing comment (not introduced this session)**:
`HELPER_5278` labeled `C = step speed based on alignment` after the
`TILE_DISPATCH_TABLE` lookup -- FALSE in this context: that same
table, indexed by the final chosen direction ($01/$02/$04/$08),
converts it into a COMPACT 1-4 CODE (right/left/down/up) that's
returned to the caller and used to index sprite tables
(`ITEM_MODE_SPRITE_PTRS`, `ITEM_ANIM_TABLE_1`, `ITEM_ANIM_TABLE_2`) --
confirmed by cross-checking all 3 consumers, all 3 match exactly the
same `direction(1-4)*4+phase(0-3)` pattern.

**An important side finding**: the "left" group across the 3 tables
(`ITEM_MODE_SPRITE_PTRS`, `ITEM_ANIM_TABLE_1`, `ITEM_ANIM_TABLE_2`) is
ALWAYS the "right" group with bit7 set -- confirms, by pure static
analysis with no live tracing needed, the "there are no left-facing
sprites, the right one gets flipped horizontally" mechanism already
documented as a parked hypothesis for the character sprites. Here
it's proven independently and conclusively.

**Restructuring applied**: the 3 tables (`ITEM_MODE_SPRITE_PTRS`,
`ITEM_ANIM_TABLE_1`, `ITEM_ANIM_TABLE_2`) are rewritten with one `DB`
row of 4 bytes per direction (the "never read" offset + right + left
+ down + up), with an explicit comment on which is which and why the
first group is never read (the direction is never 0).
`ITEM_MODE_SPRITE_PTRS` also documents its own 10-byte tail (offset
22-31, out of range) together with the already-known 10-byte gap from
the previous round ($5174-$517D) as a single, unexplained 20-byte
stretch. Also fixed 2 inline comments (`R51FE_MAIN` and
`HELPER_5278`) that were left out of date with the old reading.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- the restructuring preserves exactly the same bytes,
zero content changes. `.dsk`/`.cas`/HTML inventory regenerated: same
total of 733 labels (no new labels added, only existing `DB` rows and
comments reorganized).

### Extra round: the gap's final 10 bytes ($5174-$517D) analyzed as code vs. data -- an orphan sprite candidate, not code

The developer asked whether `DB $A2,$A2,$23,$23,$24,$24,$1F,$1F,$20,$20`
(the unexplained gap between `ITEM_MODE_SPRITE_PTRS` and
`ITEM_DIR_CHOICE_TABLE`) was code or data.

**Disassembly tried**: decodes COMPLETELY across the exact 10 bytes
(no half instruction) as `AND D`/`AND D`/`INC HL`/`INC HL`/`INC H`/
`INC H`/`RRA`/`RRA`/`JR NZ,+32` -- but the sequence has no functional
sense at all (identical instructions repeated with no recognizable
purpose, very different from the real dead code already confirmed in
this project, `POP HL`/`EI`/`RET`, which IS a meaningful sequence).

**As data**, on the other hand, it fits perfectly: it's 5 PAIRS of
identical bytes (`$A2,$A2`/`$23,$23`/`$24,$24`/`$1F,$1F`/`$20,$20`) --
exactly the same "2 repeated frames" convention used by
`ITEM_MODE_SPRITE_PTRS`/`ITEM_ANIM_TABLE_1`/`ITEM_ANIM_TABLE_2`. Also,
`$1F`/`$20` match EXACTLY the "up" sprites already documented in
`ITEM_MODE_SPRITE_PTRS`, and `$A2` is `$22` with bit7 set (the same
horizontal-flip pattern confirmed in the previous round). No real
reference found in the code (neither direct nor indirect).

**Conclusion**: a strong candidate for orphan sprite data (maybe a
5th entry or a discarded variant), not code. The comment (section
header + the `DB` line itself) was updated to reflect this, instead
of a plain "unexplained gap".

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- comment-only change, zero content changes.
`.dsk`/`.cas`/HTML inventory regenerated: same total of 733 labels.

### Extra round: the 3 "moving item" types identified as real characters -- ghost, ladybug and "repugnantoso"

Cross-checking the exact sprite indices each of the 3 moving-item
tables uses (`ITEM_TABLE_POS_511C`/`ITEM_TABLE_1`/`ITEM_TABLE_2`,
already analyzed in earlier rounds) against the character sprite
catalog already identified by the developer in an earlier session
(`madmix1_body.asm`, `SPR27`.. `SPR53`), confirmed the 3 "types"' real
identity:

- **Type 3** (`ITEM_TABLE_POS_511C`, 8 entries) = **GHOST**. Sprites
  `$1B/$1C`=`SPR27/28_FANTASMA_DER`, `$1D/$1E`=
  `SPR29/30_FANTASMA_ABAJO`, `$1F/$20`=`SPR31/32_FANTASMA_ARRIBA`
  (left = right flipped). Confirms `R51FE_MAIN`/`HELPER_5278` (with
  its "keep direction if possible" table, `ITEM_DIR_CHOICE_TABLE`) is
  the ghosts' movement AI. Architectural maximum: 8 simultaneous
  ghosts (the table's fixed size); how many are really active in a
  given level is decided by `LEVEL_REC_ITEM3_COUNT` (offset 8 of the
  level record, 0-8).
- **Type 1** (`ITEM_TABLE_1`, 2 entries) = **LADYBUG**. Sprites
  `$27`=`SPR39_MARIQUITA_DER`, `$25`=`SPR37_MARIQUITA_ABAJO`,
  `$26`=`SPR38_MARIQUITA_ARRIBA`. Matches exactly the "ladybug
  replenished balls" already documented by the developer, and the
  already-confirmed handler effect (regenerates already-eaten balls).
- **Type 2** (`ITEM_TABLE_2`, 8 entries) = **"REPUGNANTOSO"** (the
  "steamroller" mentioned by the developer). Sprites
  `$2D-$2F`=`SPR45-47_REPUGNANTE_DER`, `$30-$32`=
  `SPR48-50_REPUGNANTE_ABAJO`, `$33-$35`=`SPR51-53_REPUGNANTE_ARRIBA`.
  Matches the already-confirmed effect (the OPPOSITE of the ladybug:
  turns normal balls into pinned balls instead of regenerating them).

**Renamed the ladybug and repugnante labels** (the developer
explicitly asked for these 2, leaving ghost for a possible future
round):

| Before | After |
|-------|---------|
| `ITEM_TABLE_1` | `ITEM_TABLE_MARIQUITA` |
| `ITEM_HANDLER_1` | `HNDLR_MARIQUITA` |
| `ITEM_ANIM_TABLE_1` | `ITEM_ANIM_TABLE_MARIQUITA` |
| `LEVEL_REC_ITEM1_COUNT` | `LEVEL_REC_MARIQUITA_COUNT` |
| `IH1_LOOP`/`IH1_54DB`/`IH1_54DC`/`IH1_NEXT` | `MARIQUITA_LOOP`/`MARIQUITA_SKIP`/`MARIQUITA_STORE`/`MARIQUITA_NEXT` |
| `ITEM_TABLE_2` | `ITEM_TABLE_REPUGNANTE` |
| `ITEM_HANDLER_2` | `HNDLR_REPUGNANTE` |
| `ITEM_ANIM_TABLE_2` | `ITEM_ANIM_TABLE_REPUGNANTE` |
| `LEVEL_REC_ITEM2_COUNT` | `LEVEL_REC_REPUGNANTE_COUNT` |
| `IH2_LOOP`/`IH2_55F4`/`IH2_55F5`/`IH2_NEXT` | `REPUGNANTE_LOOP`/`REPUGNANTE_SKIP`/`REPUGNANTE_STORE`/`REPUGNANTE_NEXT` |

77 substitutions (75 in `madmix_scr_body.asm`, 2 in
`madmix1_body.asm`, whole word, also touching comments). Also updated
`HNDLR_MARIQUITA`/`HNDLR_REPUGNANTE`'s header comment blocks and
`LEVEL_REC_ITEM3_COUNT`'s field to cite the confirmed character
identity instead of just "type N".

`ITEM_TABLE_POS_511C` (ghost) is left unrenamed for now -- identity
confirmed via the comment, pending a possible future round if
requested.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`). `.dsk`/`.cas`/HTML inventory regenerated: same total
of 733 labels (a pure rename, no labels added or removed).

### Extra round: `ITEM_TABLE_POS_511C` and its handler renamed to GHOST, closing the ladybug/repugnante/ghost trio

Completing the previous round (ladybug/repugnante), the developer
asked to also rename the type-3 table/handler, already confirmed as
GHOST by the `SPR27-32_FANTASMA_*` sprites.

| Before | After |
|-------|---------|
| `ITEM_TABLE_POS_511C` | `ITEM_TABLE_FANTASMA` |
| `R51FE_MAIN` | `HNDLR_FANTASMA` (same `HNDLR_` pattern as ladybug/repugnante) |
| `R51FE_LOOP` | `FANTASMA_LOOP` |
| `R51FE_NEXT` | `FANTASMA_NEXT` |
| `R51FE_END` | `FANTASMA_END` |
| `R51FE_5242` | `FANTASMA_SPECIAL_ADJUST` |
| `R51FE_5248` | `FANTASMA_DRAW` |
| `LEVEL_REC_ITEM3_COUNT` | `LEVEL_REC_FANTASMA_COUNT` |
| `ITEM_MODE_SPRITE_PTRS` | `ITEM_ANIM_TABLE_FANTASMA` (unifies the name with `ITEM_ANIM_TABLE_MARIQUITA`/`ITEM_ANIM_TABLE_REPUGNANTE`, even though it's the only self-referential one of the 3) |

`HELPER_5278`/`HELPER_53A2`/`HELPER_5414`/`ITEM_DIR_CHOICE_TABLE` are
deliberately left unrenamed: they're movement infrastructure SHARED
by all 3 creatures (ladybug, repugnante and ghost all call it the
same way), not exclusive to the ghost.

48 substitutions in `madmix_scr_body.asm` (0 in `madmix1_body.asm`, no
cross-references). Also found and fixed 3 loose textual artifacts
from the previous round (abbreviations like "HNDLR_MARIQUITA/2" that
were leftovers from the old "ITEM_HANDLER_1/2" notation before the
rename, now expanded to the 2/3
full names). Added an "IDENTITY CONFIRMED" note in
`ITEM_ANIM_TABLE_FANTASMA`'s header citing the exact `SPR27-32`.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`). `.dsk`/`.cas`/HTML inventory regenerated: same total
of 733 labels (a pure rename).

With this, the engine's 3 "moving item" types now have a real
character name instead of "type 1/2/3": `ITEM_TABLE_FANTASMA`/
`HNDLR_FANTASMA`, `ITEM_TABLE_MARIQUITA`/`HNDLR_MARIQUITA`,
`ITEM_TABLE_REPUGNANTE`/`HNDLR_REPUGNANTE`.

### Extra round: `recursos/flujo_programa.html` brought up to date -- tables 3 and 4 (per-tile-type handler / state variables) had gone several rename rounds without being updated

The developer pointed out that the flow HTML's "data" section still
only referenced hex addresses with no label name. Reviewing the file
found 2 hand-written tables (not generated by `gen_inventory.py`,
which only fills section 5's `INVENTORY` array) completely out of
date:

- **Table 3 (tile-type dispatcher)**: used the old names
  `HANDLER_2EB7`/`HANDLER_2EC7`/.../`ML_3252`/`ML_3299`/`ML_32E2`
  (from before the 2 `HNDLR_*` rename rounds). Rewritten row by row
  with all 20 types (previously bulk-grouped as "0-7 not detailed"),
  current names, and fixed descriptions (e.g. type 10 no longer says
  "candidate for power ball eaten" but "plane track, CORRECTED" --
  that correction had been in `FINDINGS.md` for a while but never
  reached this HTML).
- **Table 4 (shared state variables)**: 11 rows that only showed the
  hex address, with no label. All completed with the real name
  (`PACMAN_POS`, `CURRENT_LEVEL`, `BALLS_EATEN_COUNT`,
  `SPECIAL_MODE_FLAG/COUNTDOWN/ACTIVE`, `MOVE_DIRECTION`,
  `DIR_BEHAVIOR_SELECTOR`, `LIVES_REMAINING`, `SCORE_ACCUM`,
  `SPECIAL_MODE`, `HINT_POS_TABLE`). The 2 real exceptions with no
  label (`$6128`, `$FC50`) are left as hex but with an explicit "no
  label of its own" note instead of pretending they have one --
  honesty about what really isn't symbolized in the source code.
  Also updated `$FC60`->`$FC50` (the already-documented bug fix) and
  added that the buffer is header+body+FOOTER (a recent round's
  finding, also not reflected here until now).
- Also fixed a flow-diagram box (section 1) that said
  `ITEM_HANDLER_1/2` with the description "special items (power ball,
  hippo...)" -- both out of date/wrong, now says
  `HNDLR_MARIQUITA/HNDLR_REPUGNANTE` with the real description
  confirmed in the character-identification round.

No source-code or compiled-byte changes in this round -- pure
documentation (HTML). The rest of the file was reviewed for more
out-of-date references: `TRAPDOOR_ANIM_EXIT` (inside the `INVENTORY`
array) is the only remaining "TRAPDOOR_ANIM" mention, and it's
correct (that label was deliberately left unrenamed in its round, for
being a common tail that already had a descriptive name).
`GHOST_HINT_HANDLER`/`TRAPDOOR_FLIP_TABLE` (mentioned in the diagram)
also verified, still their current real names.

### Extra round: `LD IX, $511C` in `TABLE_INIT` substituted with the real label (it had been left as hex despite already having a name)

The developer noticed `TABLE_INIT` still used `$511C` as literal hex
even though its own comment already said "ITEM_TABLE_FANTASMA (already
has its own label...)" -- it had slipped past earlier rename rounds
because, unlike `ITEM_TABLE_MARIQUITA`/`ITEM_TABLE_REPUGNANTE` (which
in that same function WERE ALREADY referenced by name from the
start), this was the only one of the 3 still in pure hex. Substituted
with `ITEM_TABLE_FANTASMA`.

Along the way, renamed `TABLE_INIT`'s 3 loops (also hex-based, same
underlying issue): `TI_511C_LOOP`/`TI_549B_LOOP`/`TI_5588_LOOP` ->
`TI_FANTASMA_LOOP`/`TI_MARIQUITA_LOOP`/`TI_REPUGNANTE_LOOP`.

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`). `.dsk`/`.cas`/HTML inventory regenerated: same total
of 733 labels.

### Extra round: `ITEM_EXTRA_TABLE` restructured -- the "entry offset" mechanism resolved and a byte-reuse trick detected

The developer asked to dig deeper into `ITEM_EXTRA_TABLE` ($56F5, 126
bytes, checked by `ITEM_TIMER_TICK`) to structure and comment it.
Cross-checking the 7 real values the 4 callers (`GHOST_HINT_HANDLER`,
`IE_581B`, `IE_584A`, `IE_5870`) pass to `CLEAR_5773_AND_SET` via
register `C`, confirmed the full mechanism:

**C's value is NOT a generic counter -- its low 7 bits (AND $7F) are
the ENTRY OFFSET directly into the table.** This lets each event enter
at a different point of the same sequence: from the start (long
animation) or jumping straight to the shared closing tail (for a
short "flash"). C's bit7 distinguishes the context
(`GHOST_HINT_HANDLER` vs `ITEM_EFFECT`) as `CLEAR_5773_AND_SET`
already documented.

**Real structure, 3 sequences ending in `$FF`**:

- Sequence A (offset 1-39): `flecha_derecha`(tile 54) x22 + shared
  closing + `linea_electrica_puerta_fantasmas_a`(56) x10 + `$FF`.
- Sequence B (offset 40-84): 5 undeciphered bytes (`$0F,$8D,$0E,
  $0D,$0F`) + an undeciphered repeating pattern (`$03,$00,$06,$80` x6)
  + a 4-icon cycle (`pista_avion`(58)/`item_suelo`(59)/`bola_poder`
  (60)/`hipopotamo`(61)) + shared closing + `$FF`.
- Sequence C (offset 85-125): `item_herramienta`(62) x24 + shared
  closing + `pista_tanque_vertical`(55) x10 + `$FF`.
- Closing shared by all 3: `$28,$28,$29,$29,$2A,$2B[,$2C]` -- brick-
  wall corners/joints (tiles 40-44 in the catalog).

**A "memory-saving trick" finding**: the `$FF` that closes sequence A
(offset 39) is DELIBERATELY REUSED as a valid entry point into
sequence B (real entry `$A7`, used by `IE_581B` when the item is the
hippo) -- it works because `ITEM_TIMER_TICK` only checks "is it $FF"
on the byte AFTER the one it draws, never the current one.

**A strong hypothesis about the semantics** (not visually confirmed):
the tiles drawn are REAL ones from the map catalog (not invented
decorative sprites), drawn with `ACTOR_ENGINE` at a temporary "notice"
position -- possibly a "celebration flash" showing power-up icons
when activating a special mode (sequence B) or when scoring points/
flagging a trapdoor track (sequences A/C and the short tails).

**Changes applied**: 7 new labels (`ITEM_EXTRA_SEQ_A`,
`ITEM_EXTRA_SEQ_A_TAIL`, `ITEM_EXTRA_SEQ_B_ENTRY`,
`ITEM_EXTRA_SEQ_B_MAIN`, `ITEM_EXTRA_SEQ_B_TAIL`, `ITEM_EXTRA_SEQ_C`,
`ITEM_EXTRA_SEQ_C_TAIL`) marking each real entry point inside the
`DB` block, with a comment explaining the full mechanism in the
section header. The 7 sites where `C`'s value gets loaded
(`GHOST_HINT_HANDLER`, `IE_581B` x2, `IE_584A` x2, `IE_5870` x3) were
annotated with a comment showing which label each hex value
corresponds to -- they were NOT substituted with the label directly
because the real byte combines offset+context flag, it isn't the
label's absolute address (substituting would have produced a wrong
byte).

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- the restructuring preserves exactly the same 126
bytes, zero content changes. `.dsk`/`.cas`/HTML inventory regenerated:
740 labels (up from 733, +7 for the new ones), the `data` category
rises from 228 to 235.

**Pending**: the 29-byte undeciphered stretch inside sequence B
(`$0F,$8D,$0E,$0D,$0F` + `$03,$00,$06,$80` x6) is still unexplained;
and the "celebration flash" hypothesis hasn't been confirmed by
visually rendering it.

### Extra round: fixed an old, reversed comment in `CLEAR_5773_AND_SET` (C's bit7 wasn't what it said)

While explaining what `ITEM_EXTRA_TABLE` is for, `CLEAR_5773_AND_SET`
was reread to pin down where each "flash" gets drawn, and the old
comment ("C with bit7 set = the GHOST_HINT_HANDLER case") turned out
to be REVERSED: of the 7 real values verified in the previous round,
`GHOST_HINT_HANDLER` uses `$4D` (bit7 CLEAR) while `IE_581B` uses
`$AD`/`$A7` (bit7 SET) -- exactly the opposite of what the comment
said. Fixed: bit7 set = `IE_581B`'s 2 calls (activating a special
mode, exits without saving position); bit7 clear =
`GHOST_HINT_HANDLER`/`IE_584A`/`IE_5870` (they DO save the item's
current position in the entry).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- comment-only
change.

### Extra round: `ITEM_EXTRA_TABLE` renamed to `ITEM_TABLE_EFECTOS_DESTELLO`

The developer asked to rename `ITEM_EXTRA_TABLE` so its name reflects
its real function (a temporary flash visual effect, not level data),
following the `ITEM_TABLE_*` pattern already used for ghost/ladybug/
repugnante:

| Before | After |
|-------|---------|
| `ITEM_EXTRA_TABLE` | `ITEM_TABLE_EFECTOS_DESTELLO` |
| `ITEM_EXTRA_SEQ_A` | `EFECTOS_DESTELLO_SEQ_A` |
| `ITEM_EXTRA_SEQ_A_TAIL` | `EFECTOS_DESTELLO_SEQ_A_TAIL` |
| `ITEM_EXTRA_SEQ_B_ENTRY` | `EFECTOS_DESTELLO_SEQ_B_ENTRY` |
| `ITEM_EXTRA_SEQ_B_MAIN` | `EFECTOS_DESTELLO_SEQ_B_MAIN` |
| `ITEM_EXTRA_SEQ_B_TAIL` | `EFECTOS_DESTELLO_SEQ_B_TAIL` |
| `ITEM_EXTRA_SEQ_C` | `EFECTOS_DESTELLO_SEQ_C` |
| `ITEM_EXTRA_SEQ_C_TAIL` | `EFECTOS_DESTELLO_SEQ_C_TAIL` |

22 substitutions in `madmix_scr_body.asm` (no cross-references in
`madmix1_body.asm`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels (a pure rename).

### Extra round: `ITEM_TABLE_EFECTOS_DESTELLO`'s 7 sub-labels go from "documentation only" to being REALLY referenced in the code

The developer pointed out the 7 sub-labels (`EFECTOS_DESTELLO_SEQ_A`,
`_A_TAIL`, `_B_ENTRY`, `_B_MAIN`, `_B_TAIL`, `_C`, `_C_TAIL`) had no
real references -- they were just markers placed to document where
each stretch starts inside the `DB`, but the code still used literal
hex values (`$4D`, `$AD`, `$A7`, `$6D`, `$17`, `$55`, `$01`) with a
plain comment noting which label they "would correspond to".

**The 7 literals were substituted with label-difference expressions**,
which the assembler itself resolves to the exact same constant at
compile time:

- `LD C, $4D` -> `LD C, EFECTOS_DESTELLO_SEQ_B_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $6D` -> `LD C, EFECTOS_DESTELLO_SEQ_C_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $17` (x2) -> `LD C, EFECTOS_DESTELLO_SEQ_A_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $55` -> `LD C, EFECTOS_DESTELLO_SEQ_C - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $01` -> `LD C, EFECTOS_DESTELLO_SEQ_A - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $AD` -> `LD C, (EFECTOS_DESTELLO_SEQ_B_MAIN - ITEM_TABLE_EFECTOS_DESTELLO) | $80`
- `LD C, $A7` -> `LD C, (EFECTOS_DESTELLO_SEQ_B_ENTRY - ITEM_TABLE_EFECTOS_DESTELLO) | $80`

Bit7 (which distinguishes the "IE_581B, no position saved" context
from the rest, see the previous round on `CLEAR_5773_AND_SET`) is
added with `| $80` where it applies. Verified in the `.lst` that the 7
expressions generate BYTE FOR BYTE the same values as the literals
they replace (`0E 4D`, `0E AD`, `0E A7`, `0E 6D`, `0E 17`x2, `0E 55`,
`0E 01`).

With this, if a byte is ever inserted into or removed from
`ITEM_TABLE_EFECTOS_DESTELLO` in the future, these 7 entry points
would recompute themselves on the next build -- they're no longer
independent magic numbers that need to be kept in sync by hand.

**Note on the inventory**: `gen_inventory.py` classifies "function"/
"internal" only by literal use in `CALL`/`JP`/`JR` -- a reference
inside an arithmetic expression (`LABEL - LABEL`) isn't caught by
that heuristic, so these 7 labels still count as "data" in the tally
(same as before, 740 labels unchanged) -- the real improvement is that
the CODE genuinely uses them now, not a change in the inventory's
category.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- zero compiled
content changes. `.dsk`/`.cas`/HTML inventory regenerated.

### Extra round: `DRAW_TILE_HELPER` renamed to `DIBUJAR_CAMBIO_LOSETA`

The developer thought the Spanish name better describes the real
function (writes a new tile onto the map and redraws it in VRAM,
used by almost every tile-type handler). Renamed together with its 2
internal sub-labels:

| Before | After |
|-------|---------|
| `DRAW_TILE_HELPER` | `DIBUJAR_CAMBIO_LOSETA` |
| `ML_DRAWTILE_COL_CHECK` | `DIBUJAR_CAMBIO_LOSETA_CHECK_COL` |
| `ML_DRAWTILE_REDRAW` | `DIBUJAR_CAMBIO_LOSETA_REDRAW` |

16 substitutions in `madmix_scr_body.asm` (no cross-references in
`madmix1_body.asm`). Reviewed `recursos/flujo_programa.html` and
`recursos/mapa_memoria.html` (memory: "update resource HTMLs") --
neither mentions this name, nothing to sync.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels (a pure rename).

### Extra round: `SCORE_DRAW` renamed to `DIBUJAR_MARCADOR_PUNTOS`

| Before | After |
|-------|---------|
| `SCORE_DRAW` | `DIBUJAR_MARCADOR_PUNTOS` |
| `SCORE_DRAW_COMMON` | `DIBUJAR_MARCADOR_PUNTOS_COMMON` |
| `SCORE_DRAW_DIGITS` | `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` |

24 substitutions (11 in `madmix_scr_body.asm`, 13 in
`madmix1_body.asm`, where the real definition lives, JT_SLOT7/$8D70).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels.
`recursos/flujo_programa.html` (flow-diagram box + the JT_INIT
dispatch table row) and `recursos/mapa_memoria.html` (segment
0x8D1B-0x8E3C) updated with the new name.

### Extra round: `HELPER_5278` renamed to `MOVER_ITEM_MOVIL`

The developer asked for a descriptive name for `HELPER_5278` (decides
direction + applies movement for the 3 moving characters: ghost/
ladybug/repugnante). Renamed to `MOVER_ITEM_MOVIL`. `HELPER_53A2`
(its second entry point, only visibility/VRAM position) is left
unrenamed for now -- that part of the proposal wasn't confirmed.

17 identifier substitutions + **2 sites where the code still used the
literal hex `CALL $5278`** (instead of the symbol) also fixed to
`CALL MOVER_ITEM_MOVIL` -- the same kind of oversight as `$511C` in
`TABLE_INIT` (previous round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels.
`recursos/mapa_memoria.html` (segment 0x51FE-0x5478) updated.

### Extra round: substituting 8 words with the developer's own terminology in the code labels

The developer asked to substitute 8 words with their own terminology
in the code labels (scope explicitly chosen via a question: only
`HNDLR_*`/`ITEM_TABLE_*`/`LEVEL_REC_*` and their sub-labels, WITHOUT
touching `.til`/`.spr` filenames or `madmix1_body.asm`'s `SPR*` sprite
catalog):

| Old word | New word |
|------------------|----------------|
| HIPOPOTAMO | HIPODOSO |
| TANQUE | COCOTANQUE |
| AVION | COCONAVE |
| FANTASMA | PELMAZOIDE |
| MARIQUITA | MARICOCO |
| REPUGNANTE | REGPUNANTOSO |
| HERRAMIENTA | EXCAVATOFONO |
| FLECHA | AUTOCOCO |

Applied to the 43 affected labels (with their sub-labels: `_EXIT`,
`_LOOP`, `_MODE_CHECK`, `_ACTIVATE`, `_TAIL`, `_SKIP`, `_STORE`,
`_NEXT`, `_DRAW`, `_SPECIAL_ADJUST`, `_END`, `TI_*_LOOP`, etc.), 206
substitutions total (203 in `madmix_scr_body.asm`, 3 in
`madmix1_body.asm` -- comments citing the labels by name). Lowercase
prose mentions of the same words (tile names: "flecha_arriba",
"pista_tanque_vertical", "modo avion"...) and the sprite catalog's
`SPR*_FANTASMA_*`/`SPR*_MARIQUITA_*`/`SPR*_REPUGNANTE_*` labels are
deliberately left UNTOUCHED (outside the chosen scope).

**Verified**: recompiled with no errors (the same 2 warnings as
always), diffs at the exact usual baseline (7 in `MADMIX.SCR`, 2 in
`MADMIX1.BIN`) -- a pure rename, zero content changes. `.dsk`/`.cas`/
HTML inventory regenerated: same total of 740 labels.
`recursos/flujo_programa.html` (dispatch table + diagram box) and
`recursos/mapa_memoria.html` (4 segments in the 0x511C-0x5904 zone)
updated with the new names, noting "previously X" where it adds
context.

**Note for the future**: if it's later decided to extend this
terminology to filenames (`data/tiles/*.til`, `data/sprites/*.spr`)
and the rest of the resource HTML, the developer already declined
that larger scope this time -- it would be a separate round.

### Extra round: `JT_SLOT2: JP $8440` substituted with `JP ACTOR_ENGINE` (an out-of-date comment)

The developer asked where `$8440` jumps to (line 10 of
`madmix1_body.asm`, `JT_SLOT2`'s entry in the jump table). The comment
said "no confirmed name yet", but `ACTOR_ENGINE` (line 95 of the same
file) has been a real, confirmed label for several sessions already
-- the comment simply had never been updated since before the name
was confirmed. Fixed: `JP $8440` -> `JP ACTOR_ENGINE`, comment
updated.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- just substituting
hex with an already-existing label, zero content changes.

### Extra round: the whole jump table (JT_INIT..JT_TILE_TYPE) substituted with real labels instead of hex

When the developer asked where `$8F24` (`JT_INIT`) jumps to, it turned
out the WHOLE 12-entry jump table (the engine's "public API", `$8400`)
had the same systemic pattern: every entry did `JP $XXXX` with a
comment naming the already-confirmed label, instead of using the
label directly. Fixed the remaining 10 entries (`JT_INIT`/`JT_SLOT2`
were already fixed in the previous round):

| Entry | Before | After |
|---------|-------|---------|
| JT_SLOT3 | `JP $899B` | `JP RESET_8437` |
| JT_WAIT_VBLANK | `JP $89A0` | `JP WAIT_VBLANK` |
| JT_SLOT5 | `JP $881B` | `JP INSTALL_ISR` |
| JT_SLOT6 | `JP $8E3C` | `JP INPUT_READ` |
| JT_SLOT7 | `JP $8D70` | `JP DIBUJAR_MARCADOR_PUNTOS` |
| JT_SLOT8 | `JP $89AD` | `JP SCROLL_DISPATCH` |
| JT_SLOT9 | `JP $8C34` | `JP JT_SLOT9_TARGET` |
| JT_REDRAW_STRIP | `JP $8D1B` | `JP REDRAW_STRIP` |
| JT_MAP_ADDR | `JP $8CB6` | `JP MAP_COORD_TO_ADDR` |
| JT_TILE_TYPE | `JP $8CDA` | `JP TILE_TYPE_LOOKUP` |

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- substituting hex
with already-existing labels, zero content changes. `.dsk`/`.cas`/
HTML inventory regenerated: 740 labels (no change in the total), but
several labels that were only reachable via this table (and so were
counted as "no-ref" since the hex `JP $XXXX` wasn't detected) now get
correctly classified as "internal" now that the `JP` names them by
symbol -- the internal category rises from 218 to 221, no-ref drops
from 190 to 187.

### Extra round: `ACTOR_ENGINE` renamed to `MOTOR_ACTORES`

32 substitutions (26 in `madmix_scr_body.asm`, 6 in
`madmix1_body.asm`, where the real definition lives at `$8440`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels.
`recursos/flujo_programa.html`, `recursos/mapa_memoria.html` and
`recursos/ptrtable_sprites.html` updated (the only remaining mentions
are in `recursos/descartado/`, obsolete, irrelevant files).

### Extra round: 2 more hex CALLs fixed in ISR_HOUSEKEEPING (CALL $86BB/$899B -> JTS2_RESUME/RESET_8437)

While explaining RESET_8437, 2 CALLs inside ISR_HOUSEKEEPING were
found still in literal hex despite already having a confirmed real
label (same pattern as the jump table, earlier rounds): `CALL $86BB`
-> `CALL JTS2_RESUME`, `CALL $899B` -> `CALL RESET_8437`.
`CALL $8CFF` is left as is -- it's still genuinely unidentified
(confirmed in the function's own header comment).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- just substituting
hex with already-existing labels, zero content changes.

### Extra round: `RESET_8437` renamed to `RESET_CONTADOR_ACTORES`

6 substitutions in `madmix1_body.asm` (definition, comments and the
real `CALL`/`JP`, already fixed from hex to label in the previous
round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 740 labels (function rises from 97 to 99,
internal drops from 221 to 220, no-ref drops from 187 to 186 --
cumulative effect of `gen_inventory.py` not having been rerun since
the `CALL $86BB/$899B` -> `JTS2_RESUME`/`RESET_8437` fix in the
previous round; both are now correctly detected as "function" via a
`CALL` with a real name). `recursos/flujo_programa.html` and
`recursos/mapa_memoria.html` updated (3 mentions).

### Extra round: `INSTALL_ISR` renamed to `ACTIVAR_INTERRUPCION_MODO_1`

Along the way, another `CALL $881B` (in `INIT`) that was still in hex
despite having a confirmed label was fixed -- the same systemic
pattern as earlier rounds (jump table, `RESET_CONTADOR_ACTORES`).

5 substitutions in `madmix1_body.asm`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 740 labels (function rises from 99 to 100,
internal drops from 220 to 219, from fixing the hex `CALL`).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### Extra round: `INPUT_READ` renamed to `LEER_ENTRADA`

13 substitutions (4 in `madmix_scr_body.asm`, 9 in
`madmix1_body.asm`). Along the way, fixed 2 more `CALL $8E3C` still
in hex in `madmix1_body.asm` (the same systemic pattern from earlier
rounds).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels (it was already
classified as "function" before, from other named calls).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### Extra round: `SCROLL_DISPATCH` renamed to `GESTIONAR_SCROLL`

10 substitutions (6 in `madmix_scr_body.asm`, 4 in
`madmix1_body.asm`). `ML_SCROLL_DISPATCH_CALL` (a distinct sub-label
from `MAIN_LOOP`, from an earlier rename round) is deliberately left
untouched -- it's its own identifier, not the same label.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: same total of 740 labels.
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### Extra round: 9 more hex CALLs fixed (FILVRM/SETVRAM/DIBUJAR_MARCADOR_PUNTOS) while reviewing JT_SLOT9_TARGET

While explaining `JT_SLOT9_TARGET`, 9 more sites with the same
systemic pattern were found (literal hex with an already-confirmed
label, unsubstituted): `CALL $8931` (x3) -> `CALL FILVRM`,
`CALL $8954` (x2) -> `CALL SETVRAM`, `CALL $8D70` (x2, inside
`JT_SLOT9_TARGET` itself) -> `CALL DIBUJAR_MARCADOR_PUNTOS`. Along
the way, fixed 2 comments citing "$8D70" in prose that had gone out
of date/redundant after earlier rounds (one said "still not
transcribed", already false for a while).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- just substituting
hex with already-existing labels + comment fixes, zero content
changes. `.dsk`/`.cas`/HTML inventory regenerated: same total of 740
labels.

### The full scroll chain: GESTIONAR_SCROLL -> SCROLL_UP/DOWN/LR -> SCROLL_TAIL -> ACTUALIZAR_VRAM_FRAME (previously GH_8891)

Investigating the scroll mechanics in detail established the full
chain of responsibilities, clearing up an initial confusion about
"who writes to VRAM":

1. `GESTIONAR_SCROLL` (previously `SCROLL_DISPATCH`) reads
   `PACMAN_POS` and decides, based on X/Y's low bits, whether to
   shift 4px up, down, or sideways, jumping (not calling) into one of
   three routines.
2. `SCROLL_UP`/`SCROLL_DOWN` (`RLD`/`RRD` nibble) and `SCROLL_LR`
   (`LDI`) shift the RAM work buffer's content at `$DE04` (144 rows x
   32 bytes) 4 pixels in the chosen direction.
3. All three converge into `SCROLL_TAIL`: if a full tile boundary was
   also crossed (`XOR D / AND $01` test), it walks 9 steps (`B=$09`,
   matching the confirmed visible height) calling `TILE_ADDR_CALC` to
   fetch the new tile from the level's resident RAM, and writes it
   into the SAME `$DE04` buffer (not VRAM) via two bit-copy variants
   (`SCOPY_A`/`SCOPY_B`).
4. The real VRAM write is done by a **separate, unconditional
   routine, once per frame**: `ACTUALIZAR_VRAM_FRAME` (renamed from
   `GH_8891`, called from `ISR_HOUSEKEEPING`). Its final stretch
   (from `$88ED` onward) sets VRAM address $0220 with `SETVRAM` and
   flushes `$DE04`'s content byte by byte with `OUT ($98),B` -- 18
   rows of data (matches 9 tile rows x 2, since each 16px tile takes
   2 rows of an 8px pattern). The rest of `ACTUALIZAR_VRAM_FRAME`
   (unrelated to scrolling) also manages color/blink for other VRAM
   zones ($2220, $2A80, $2B80) based on `GAME_STATE_FLAG`.

**Key conclusion**: neither `GESTIONAR_SCROLL` nor `SCROLL_TAIL`
touches real VRAM directly -- they only prepare the intermediate
`$DE04` buffer in RAM. It's `ACTUALIZAR_VRAM_FRAME`, run
unconditionally every frame from the interrupt, that copies that
buffer to real VRAM.

**A bug from this session, found and fixed in the process itself**:
while substituting hex with a label in `STAIL_DISPATCH`
(`LD IX,$8B5C` / `LD IX,$8B85`, jumps into `SCOPY_A`/`SCOPY_B`), it
was wrongly assumed those two addresses pointed at the already-
existing `SCOPY_A:`/`SCOPY_B:` labels themselves. Checking against
`main.sym` after recompiling revealed they did **not match** (there
was a 7- and 4-byte preamble respectively, C/B/A register setup,
BEFORE each label) -- causing 2 bytes of extra difference in
`MADMIX1.BIN` (4 instead of the expected 2). Fixed by adding
`SCOPY_A_ENTRY:`/`SCOPY_B_ENTRY:` right at the real entry point
(before the preamble) and pointing `LD IX,` at those new labels.
Along the way, `STAIL_RESUME:` was also added (the return point after
`JP (IX)`, jumped to via `LD IY,$8B4D` -- this one DID match the real
address exactly, no bug).

**Verified**: recompiled, diffs at the exact usual baseline (7 in
`MADMIX.SCR`, 2 in `MADMIX1.BIN`, the deliberate `$FC60->$FC50`
bytes). `.dsk`/`.cas`/HTML inventory regenerated: 743 total labels
(function=100 internal=219 data=235 no-ref=189).
`recursos/flujo_programa.html` (the JT_INIT table, JT_SLOT8/9 rows)
and `recursos/mapa_memoria.html` (the ISR_HOUSEKEEPING, GESTIONAR_SCROLL
and `$DE04` buffer segments) updated with the full chain.

### SCROLL_TAIL -> SCROLL_LOSETA_BUFFER_VRAM

Renamed `SCROLL_TAIL` (the shared tail of `SCROLL_UP`/`SCROLL_DOWN`/
`SCROLL_LR` that redraws the exposed tile in the `$DE04` buffer) to
`SCROLL_LOSETA_BUFFER_VRAM`, a more descriptive name matching the
rest of the already-documented chain (`GESTIONAR_SCROLL` ->
`SCROLL_UP`/`DOWN`/`LR` -> `SCROLL_LOSETA_BUFFER_VRAM` ->
`ACTUALIZAR_VRAM_FRAME`).

Along the way, reviewing the cross-references, 2 outdated historical
comments were fixed:

- The JT_SLOT8/JT_SLOT9 header block said
  `TILE_ADDR_CALC`/`SCROLL_TAIL`/`SCOPY_A`/`SCOPY_B` "translated tile
  coordinates into a VRAM address" and flushed "the new strip to the
  pattern table" -- **false** per the previous round's finding (they
  write to the `$DE04` RAM buffer, not VRAM;
  `ACTUALIZAR_VRAM_FRAME` is what flushes to real VRAM). Fixed with an
  explicit note.
- `SCROLL_ADDR_CALC`'s comment said it was called by "the scroll
  dispatcher (SCROLL_TAIL/STAIL_DISPATCH) after moving" -- **false**,
  the previous round had already found its only real call is from
  `JT_SLOT9_TARGET` (a FULL camera redraw, 36 passes), not incremental
  scrolling. Fixed here along the way (it had been left pending since
  the previous round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total, just a
rename). `recursos/flujo_programa.html` and
`recursos/mapa_memoria.html` updated (every `SCROLL_TAIL` mention
substituted).

### Reinterpreting the $DE04 buffer: it's a PIXEL canvas, not "the active level's buffer"

The developer noticed a real inconsistency: the buffer at $DE04 (144
rows x 32 bytes = 4608 bytes) is BIGGER than the whole active-level
buffer at $FC50 (header+body+footer, real max ~928 bytes = 29 rows x
32, the level with the most variable rows: 23+3+3=29). If $DE04 were
"the whole level projected to VRAM" it wouldn't make sense for it to
be bigger than the source level itself.

Investigating the `TAIL_VDP_FILL` routine ($5B8C, the one that
initializes $DE04 with $FF across 24 of every 32 bytes/row) turned up
two things:

1. **The name and comment were misleading**: despite being called
   "TAIL_VDP_FILL" and its comment saying "fills VRAM", the code does
   NOT touch VRAM at all -- it's pure `LD (HL),$FF` + `LDIR` over
   normal RAM. Comment fixed.
2. **It's called ONLY from `TAIL_VDP_CLEAR`, in the menu/demo-screen
   flow** (`TI_5B62`/`TAIL_INTRO`), not from real level loading. In
   other words: **$DE04 isn't exclusive to the active level** -- it's
   a generic work canvas reused both for the menu (with its own candy
   frame) and for real gameplay.

**The piece that resolves the size**: `ACTUALIZAR_VRAM_FRAME` (0x8891)
flushes this buffer to VRAM address `$0220`, which falls inside the
**pattern table** ($0000-$17FF), writing byte by byte with
`OUT ($98)` -- the SAME technique `PORTADA_INIT` uses for the title
screen (an uncompressed bitmap + an "identity" name table: pattern
name = pattern index = screen position). Under that hypothesis (the
identity name table gets set once in `PORTADA_INIT` and never touched
again), "drawing" reduces to writing bitmap bytes at consecutive
pattern-table addresses.

Reading it that way, $DE04's dimensions match EXACTLY the visible
grid already confirmed in an earlier session (12x9 tiles):

- **144 rows = 9 tile rows x 16px/tile** (matches the already-
  confirmed visible height).
- **32 bytes/row = 256px = the full screen width** (16 tiles of
  16px). Of those 32 bytes, `TAIL_VDP_FILL` fills 24 (192px = 12
  tiles, the already-confirmed playable area) and leaves 8 untouched
  (64px = 4 tiles, covered by the decorative candy frame).

**Conclusion**: $DE04 and the level buffer ($FC50) operate at
different levels of abstraction, which is why they aren't comparable
in size. $FC50 stores tile types (1 byte each, which is why it's
small). $DE04 stores the already-rendered PIXEL BITMAP, ready to be
flushed as-is to VRAM's pattern table -- hence why it's much bigger,
and why it's also shared with the menu/demo screens (it isn't "the
level's buffer", it's the visible window's pixel-resolution render
canvas).

**Verified**: comment-only change (no bytes altered), recompiled,
diffs at the exact usual baseline (7/2). `recursos/mapa_memoria.html`
(the 0xDE04 entry) rewritten with this reinterpretation.

### Real usage of the JT_INIT jump table: only slot 0 has external callers

Checking with grep across ALL the transcribed source code (`.asm`)
for calls to the jump table's fixed addresses (`$8400`-`$8424`, 12
entries) and to their labels by name, confirmed an important
distinction between slot 0 and the rest:

- **`JT_INIT`/`START` (`$8400`/`$8403`) DOES have real callers**: the
  disk loader (`load_disk/madmix0_body.asm`, `JP START`) and the tape
  loader (`load_cas/load_bin_body.asm`, `LD IX,START` / `JP START`)
  jump here right after loading `MADMIX1.BIN` into RAM -- it's the
  real entry point used to start the engine from outside. There's
  also an internal restart point (`SLOT_RESTART_DD82`) that comes
  back here.
- **The other 11 slots (`JT_SLOT2` through `JT_TILE_TYPE`,
  `$8406`-`$8424`) have NO caller at all** anywhere in the
  transcribed source code -- neither by hex nor by name. Every site
  that needs `MOTOR_ACTORES`, `LEER_ENTRADA`,
  `DIBUJAR_MARCADOR_PUNTOS`, `GESTIONAR_SCROLL`, `JT_SLOT9_TARGET`,
  etc. calls the real label DIRECTLY, never through the table.

This also explains why, before substituting hex for labels in the
previous round ("the whole jump table... substituted with real
labels"), several of these functions were classified as "no
reference" by `gen_inventory.py`: the table's own `JP $XXXX` was the
ONLY textual reference to them anywhere in the code, but that doesn't
mean the table is used as a real dispatch mechanism -- it's the other
way around, the table depends on someone reading the code to know
where its entries point, not the reverse.

**HYPOTHESIS (not 100% verifiable without analyzing `LOGOTOPO.CM`,
out of scope, nor the BASIC scripts in detail)**: the table was
probably designed as the engine's "public API" -- maybe used during
original development to be able to move the real functions around
without breaking external callers, or meant for external code to
invoke at fixed, stable addresses. In the final version only slot 0
(boot) fulfills that real role; the rest ended up as code convention/
organization, not an active dispatch mechanism.

No byte verification applies (no code was touched, documentation
only).

### INIT -> INICIO

Renamed the `INIT` label (the engine's real boot entry, `JT_INIT`'s
target, $8F24) to `INICIO`, at the developer's request. A whole-word
substitution (`\bINIT\b`) so it doesn't affect `PORTADA_INIT` nor
`JT_INIT` (which reference it as a prefix/suffix with an underscore,
not as a standalone word) nor the compound labels
`INIT_MAIN_LOOP`/`INIT_RESUME_8F54`/`INIT_MAINLOOP_ENTRY_8F71`/
`INIT_HELPER_9116`/`INIT_LOOP_8FD1`/`INIT_8FB7`/`INIT_8FCE`/
`INIT_8FEA`, which stay the same (they aren't the renamed label,
they're their own distinct labels that already used "INIT" as part
of their own name).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total, just a
rename). `recursos/flujo_programa.html` and
`recursos/mapa_memoria.html` updated (every prose mention of the
`INIT` function substituted with `INICIO`).

### JT_SLOT9_TARGET -> REDIBUJAR_PANTALLA_COMPLETA

Renamed `JT_SLOT9_TARGET` (a FULL camera redraw + life icons, 36
passes of `SCROLL_ADDR_CALC`, distinct from `GESTIONAR_SCROLL`'s
incremental scroll) to `REDIBUJAR_PANTALLA_COMPLETA`, after
confirming in conversation it's only invoked at specific points
(starting a game, changing level, losing a life, cycling through
sample levels in the menu/demo) and NEVER inside the game's
continuous frame-by-frame loop (see the previous round on
`INIT_MAIN_LOOP`/`IML_9078`/`IML_90B7`).

Along the way, fixed the 2 sites in `madmix1_body.asm` still using
`CALL $8C34` (hex) instead of the label, even though the comment
already named it -- the same systemic pattern as always.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated (every mention substituted, and the memory-segment entry
expanded with clarification of when it's invoked).

### Full normalization of the jump table: all 12 entries with descriptive names

The developer noticed a real inconsistency: after several rename
rounds, some jump-table entries ($8400) had a descriptive name
(`JT_WAIT_VBLANK`, `JT_MAP_ADDR`, `JT_TILE_TYPE`, inherited from
earlier sessions; `JT_REDIBUJAR_LOSETA_VRAM`, a side effect of a
mechanical text rename this same session) while the rest kept the
generic `JT_SLOTn` name (`JT_INIT`, `JT_SLOT2`, `JT_SLOT3`,
`JT_SLOT5`, `JT_SLOT6`, `JT_SLOT7`, `JT_SLOT8`, `JT_SLOT9`) even
though their targets already had a confirmed real name for a while.
There was no real criterion behind it -- earlier renames simply never
touched the table entry's own label because its old text didn't match
the target function's name.

Normalized all 12 entries to follow the same pattern (entry name =
"JT_" + the real target's name):

| Before | After | Target |
|-------|---------|---------|
| `JT_INIT` | `JT_INICIO` | `INICIO` |
| `JT_SLOT2` | `JT_MOTOR_ACTORES` | `MOTOR_ACTORES` |
| `JT_SLOT3` | `JT_RESET_CONTADOR_ACTORES` | `RESET_CONTADOR_ACTORES` |
| `JT_SLOT5` | `JT_ACTIVAR_INTERRUPCION` | `ACTIVAR_INTERRUPCION_MODO_1` |
| `JT_SLOT6` | `JT_LEER_ENTRADA` | `LEER_ENTRADA` |
| `JT_SLOT7` | `JT_DIBUJAR_MARCADOR_PUNTOS` | `DIBUJAR_MARCADOR_PUNTOS` |
| `JT_SLOT8` | `JT_GESTIONAR_SCROLL` | `GESTIONAR_SCROLL` |
| `JT_SLOT9` | `JT_REDIBUJAR_PANTALLA_COMPLETA` | `REDIBUJAR_PANTALLA_COMPLETA` |

(`JT_WAIT_VBLANK`, `JT_REDIBUJAR_LOSETA_VRAM`, `JT_MAP_ADDR`,
`JT_TILE_TYPE` were already correct, no changes.) Also applied in the
comments of `load_disk/madmix0_body.asm` and
`load_cas/load_bin_body.asm` that mentioned `JT_INIT` in prose.

Along the way, at the developer's request, the whole block of 12
`JP` entries was column-realigned for readability (the mix of long
and short names after successive renames had left the spacing
irregular).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- only label
renaming and whitespace reformatting, zero content changes.
`.dsk`/`.cas`/HTML inventory regenerated: 743 labels (no change in
total). `recursos/flujo_programa.html` (section 2, the full dispatch
table) and `recursos/mapa_memoria.html` (every segment entry citing
`JT_SLOTn`) updated.

### REDIBUJAR_PANTALLA_COMPLETA -> REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM ; REDIBUJAR_LOSETA_VRAM -> REDIBUJAR_LOSETA_BUFFER_VRAM

Two more renames to make explicit in the name itself that these
functions write to the intermediate RAM BUFFER ($DE04), not directly
to real VRAM (a key distinction established in earlier rounds about
ACTUALIZAR_VRAM_FRAME):

- `REDIBUJAR_PANTALLA_COMPLETA` -> `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`
  (confirmed in this conversation that it writes to `$DE04`
  indirectly, through the 36 calls to `SCROLL_ADDR_CALC`).
- `REDIBUJAR_LOSETA_VRAM` -> `REDIBUJAR_LOSETA_BUFFER_VRAM`.

The corresponding jump-table entries were renamed the same way to
keep the "JT_" + target-name pattern:
`JT_REDIBUJAR_PANTALLA_COMPLETA` -> `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`,
`JT_REDIBUJAR_LOSETA_VRAM` -> `JT_REDIBUJAR_LOSETA_BUFFER_VRAM`. The
jump-table block ($8400) was column-realigned again after this
change in name length.

With this, the 3 functions that write to the `$DE04` canvas end up
named uniformly and explicitly about NOT touching real VRAM:
`SCROLL_LOSETA_BUFFER_VRAM`, `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`
and `REDIBUJAR_LOSETA_BUFFER_VRAM`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### MAP_COORD_TO_ADDR -> MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA

Renamed `MAP_COORD_TO_ADDR` (converts a relative row/column
coordinate, relative to `PACMAN_POS`, into an absolute address
inside the active level's tile-type buffer, `$FC50` -- the formula
"base + row*32 + column", twin of `TILE_ADDR_CALC` which does the
same but for the `$DE04` pixel canvas) to
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, at the developer's request. The
jump-table entry `JT_MAP_ADDR` (slot 10) was renamed the same way,
to `JT_MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, following this table's
already-normalized pattern.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated (every mention substituted).

### TILE_TYPE_LOOKUP -> CONSULTAR_TIPO_LOSETA

Renamed `TILE_TYPE_LOOKUP` (takes an address inside the level's
tile buffer, strips bit 7 "food", and uses the rest as an index into
a second translation table at `$8EC7`, +3 relative to
`TILE_TYPES`/`$8EC4`, applying `AND $1F` to get the final tile type
-- an indirect table lookup, not a direct read) to
`CONSULTAR_TIPO_LOSETA`. The jump-table entry `JT_TILE_TYPE` (slot
11) was renamed the same way, to `JT_CONSULTAR_TIPO_LOSETA`.

With this, the full "position -> tile type" chain ends up named
start to finish: `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (relative
coordinate -> address) + `CONSULTAR_TIPO_LOSETA` (address -> type)
-> feeds `ML_DISPATCH_TABLE` (type -> handler).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### Detail of each frame's loop in flujo_programa.html: ALWAYS vs. CONDITIONAL vs. EVENT

The developer noticed the "every frame / every move" section of the
diagram (recursos/flujo_programa.html) grouped several functions as
if they all ran the same way every frame, when in reality some are
unconditional, others depend on a condition, and others are events
triggered from further inside the dispatch. The real body of
`MAIN_LOOP` (madmix_scr.asm:409, invoked every frame from `IML_9078`/
madmix1.asm via the `RAM_HOOK_2C36` "trampoline") was investigated to
separate exactly what always happens from what doesn't:

- **ALWAYS** (unconditional, inside `MAIN_LOOP`): `LEER_ENTRADA` (or
  demo-script address), `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` +
  `CHECK_TILE_DELTA` (with column caching -- only calls
  `CONSULTAR_TIPO_LOSETA` if the column changed relative to the
  previous frame), dispatch to `ML_DISPATCH_TABLE` (forced to "no
  effect" if a special mode is active), `GESTIONAR_SCROLL`,
  `ITEM_TIMER_TICK`, and a loop over the 3 active trapdoor entries
  (`HINT_POS_TABLE`/$2C2E) that redraws each via `MOTOR_ACTORES`.
- **CONDITIONAL** (only if `($8EC6)`=0, "keyboard not blocked"):
  `HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO` and the
  `MOTOR_ACTORES` redraw for the pac-man character itself.
- **EVENT** (triggered from INSIDE an `HNDLR_*` handler depending on
  the tile type stepped on, not a fixed frame step):
  `DIBUJAR_MARCADOR_PUNTOS` (only when the score changes),
  `TRAPDOOR_FLIP_TABLE`/`GHOST_HINT_HANDLER` (arm/move a trapdoor),
  `LOAD_RESOURCE_SLOT_*` (sound).
- **Does NOT belong to this loop at all**:
  `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` -- confirmed in earlier
  rounds that it only fires on transitions (boot, level change, life
  lost, demo cycling), never every frame. Relocated in the diagram
  next to `INIT_MAIN_LOOP`.

The section of the diagram in `recursos/flujo_programa.html` was
rewritten with 3 new rows (ALWAYS/CONDITIONAL/EVENT, with a color tag
per category via the new CSS classes `.tag-always`/`.tag-cond`/
`.tag-event`) instead of a single ambiguous "every frame / every
move" row. A `.flow-note` class was also added for a longer
explanatory note about `IML_9078`/`IML_90B7`. Along the way, the
`.box`/`.box b` CSS was fixed so the long names from the last few
rename rounds (`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`,
`REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`...) wrap inside the box
instead of overflowing it (`overflow-wrap`/`word-break`).

No byte verification applies (a purely documentation/HTML change,
no `.asm` touched).

### Outdated comment fixed: PTR_TABLE_91C3 was already resolved

The comment right before `PTR_TABLE_91C3` (madmix1_body.asm) still
read as if it were an unresolved mystery ("strong candidate to be
the key", "probably..."), even though a few lines below, the
"CHARACTER SPRITES" block (0x953B-0xB93B) already confirms it's
exactly that: the 64-pointer table to the character sprites,
identified one by one by the developer via
recursos/ptrtable_sprites.html. A classic internal contradiction of
the kind that's been fixed all session. Fixed in both places: the
header comment in `madmix1_body.asm` and the equivalent entry in
`recursos/mapa_memoria.html` (segment 0x9136-0x92E3).

**Verified**: recompiled, diffs at the exact usual baseline (7/2)
-- comment-only change, zero content changes.

### PTR_TABLE_91C3 -> PTR_TABLA_SPRITES, reconstructed with DW labels instead of hex

Renamed `PTR_TABLE_91C3` to `PTR_TABLA_SPRITES` and rewrote its 64
entries (256 bytes) using `DW SPRxx_...` (the real label of each
character sprite, already existing in the sprite catalog) instead of
raw address bytes -- generated and verified with a script (parses
the raw addresses + the list of SPR labels with their address in a
comment, and matches by exact address) to avoid manual-transcription
errors across the 64 entries.

Along the way, found and fixed the ONE real site that read this
table by hex: `LD BC, $91C3` inside `MOTOR_ACTORES` (line ~176),
with an already-outdated comment ("real table is FAR away... not
extracted yet") dating from before the table and sprites were
identified -- the same systemic hex-not-substituted pattern from all
session, now fixed to `LD BC, PTR_TABLA_SPRITES`.

The alternative of adding a new `PTR_`-prefixed label for each of
the 64 pointers was discarded: not needed, because (a) each sprite
block already has its own descriptive label (`SPR00_PM_VULN_DER_CERRADA`,
etc.) and (b) there's only ONE site in the whole code that reads the
table, by computed index (not by a literal address repeated in
several places) -- there would be no caller that would use those
hypothetical individual `PTR_*` labels.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- the
reconstruction with `DW`/labels reproduces exactly the same 256
bytes as the raw-hex version. `.dsk`/`.cas`/HTML inventory
regenerated: 743 labels (no change in total -- `gen_inventory.py`'s
classifier doesn't detect references via `DW`, only literal
`CALL`/`JP`/`JR`, so the 64 SPR labels keep their previous
classification despite now having a real reference).
`recursos/mapa_memoria.html` and `recursos/ptrtable_sprites.html`
updated (the latter also had an outdated title, "not decoded yet",
contradicted by its own "RESOLVED" note one paragraph later --
fixed too).

### PORTADA_INIT -> DIBUJAR_PORTADA

Renamed `PORTADA_INIT` (routine at $1000, madmix_scr.asm: turns off
the screen, writes the identity name table, dumps the title-screen
bitmap to the pattern table, rebuilds the color, turns the screen
back on) to `DIBUJAR_PORTADA`. Referenced from several files besides
madmix_scr.asm/madmix1.asm: `load_disk/madmix0_body.asm` (the disk
RELOCATOR calls it after the relocation LDIR) and
`load_cas/load_bin_body.asm` (tape's LOAD.BIN points there with
`LD IX,`/`CALL`). All synchronized.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### LOAD_RESOURCE_SLOT_EMPTY -> VACIAR_CANALES_SONIDO

Renamed `LOAD_RESOURCE_SLOT_EMPTY` ($CF8B: calls the sound driver's
internal helper `RM_C4CC` 3 times with `DE=$0000` and `A=0/1/2`,
emptying the 3 PSG-player channel slots -- "stop all sound in
progress" before loading a level/menu/credits) to
`VACIAR_CANALES_SONIDO`.

Along the way, 3 more sites with the same systemic hex-not-
substituted pattern were found and fixed: `CALL $CF8B` in
`INIT_MAIN_LOOP` and 2 more in the final stretch of `IML_90E4`/
`IML_POLL_90F2` (one of them unreachable code, already documented as
such, but fixed anyway for consistency).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### LOAD_RESOURCE_SLOT_ALLOC -> INSTALAR_RECURSO_SONIDO

Renamed `LOAD_RESOURCE_SLOT_ALLOC` ($C4A0: finds a free slot among 4
46-byte channel slots at $C9C9 and installs a music/SFX script
pointer there) to `INSTALAR_RECURSO_SONIDO`, counterpart of
`VACIAR_CANALES_SONIDO`.

Along the way, 3 more sites with the systemic hex-not-substituted
pattern were fixed: `CALL $C4CC` (x3, direct installation of the 3
music channels when starting a level) -> `CALL RM_C4CC` (the
already-identified internal helper, with an explicit slot index in A
instead of a free-slot search).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### SOUND_SCRIPT_0_CDCB / SOUND_SCRIPT_1_CDFF / SOUND_BOOT_CH2_CE0C -> SOUND_SCRIPT_MELODIA_CANAL_0/1/2

Renamed the 3 main music scripts (installed by INICIO at boot, one
per PSG driver channel) with consistent names:
- `SOUND_SCRIPT_0_CDCB` -> `SOUND_SCRIPT_MELODIA_CANAL_0`
- `SOUND_SCRIPT_1_CDFF` -> `SOUND_SCRIPT_MELODIA_CANAL_1`
- `SOUND_BOOT_CH2_CE0C` -> `SOUND_SCRIPT_MELODIA_CANAL_2`

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files (flujo_programa.html/mapa_memoria.html), no
sync required.

### TAIL_JOY_READ -> LEER_TECLADO

Renamed `TAIL_JOY_READ` ($5D0A) to `LEER_TECLADO`. Despite its
previous name, this function does NOT read the joystick -- it reads
the KEYBOARD via matrix scan (ports $AA/$A9, standard MSX BIOS
method), scanning the 9 rows until it finds a pressed key (Z=0,
A=column, C=row) or confirming there is none (Z=1 after the 9 rows).
Used by `TAIL_KEYWAIT_RELEASE`/`TAIL_KEYWAIT_UP` (key waits in
menus) and `TAIL_LEVELCYCLE_MAIN` (polling in the demo mode's sample-
level cycler).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files, no sync required.

### TAIL_LEVELCYCLE_HELPER2 -> DIBUJAR_MARCO_CARAMELO_VRAM

Renamed `TAIL_LEVELCYCLE_HELPER2` ($6429) to
`DIBUJAR_MARCO_CARAMELO_VRAM`. Function: clears the VRAM color table
($2000, FILVRM with $01) and decompresses `RLE_TABLE_D6B6` (870
bytes, [value,count] pairs), dumping the result with direct FILVRM
to the VRAM pattern table (destination starts at $0000) -- draws the
SHAPE of the candy frame. It's the "sister" of `TAIL_CREDITS_MAIN`,
which applies the COLOR of that same frame (reading
`LEVELCYCLE_RESOURCE_TABLE`/$6129).

Along the way, a clearly outdated/misplaced comment right above the
function was fixed: it described "slot-switching copy... data in
blocks of $6129 (id+8 bytes)... second entry point at $647C" -- that
is actually the description of `TAIL_CREDITS_MAIN` ($6129) and of
`TAIL_LEVELCYCLE_HELPER_ALT` ($647C, a DIFFERENT function, not a
second entry point of this one). The correct comment already existed
right AFTER the function (left untouched, still valid); the one
BEFORE it was removed/replaced with one that describes what the
function actually does.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### Comment fixed: INIT_RESUME_8F54 is not reached via TAIL_CREDITS_MAIN

The header comment of `INIT_RESUME_8F54` said "real re-entry...
after the 'CALL $6454' wait loop" (TAIL_CREDITS_MAIN), but the only
real jump (`JP INIT_RESUME_8F54`, in the Game Over sequence) doesn't
go through `$6454` at all -- it comes from the ~150-frame wait loop
(`IML_LOOP_90B1`) after showing the "YOU'RE TOAST" message. This
label is reached by 2 real paths:
1. Falling through here with no jump, the first time the machine
   boots (right after drawing the title screen, installing the 3
   music channels and waiting for a key).
2. Via the `JP INIT_RESUME_8F54` from the Game Over sequence.

Comment fixed to reflect this.

**Verified**: recompiled, diffs at the exact usual baseline (7/2)
-- comment-only change, zero content changes.

### INIT_RESUME_8F54 -> REINICIAR_PARTIDA

Renamed `INIT_RESUME_8F54` to `REINICIAR_PARTIDA`. Reached by 2
paths (see the previous round on the fixed comment): falling through
with no jump from the machine's real boot, or via `JP` from the Game
Over sequence (after the "YOU'RE TOAST" message and ~150 frames of
waiting). Its body empties the sound, shows the main menu
(`TI_5B56`) and resets lives=3/score=0/level=1 -- the "clean return
to a new game".

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### LIVES_REMAINING -> VIDAS_RESTANTES

Renamed the `LIVES_REMAINING` variable ($2C27, player's remaining
lives) to `VIDAS_RESTANTES`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### SCORE_ACCUM -> PUNTUACION ; CURRENT_LEVEL -> NIVEL_ACTUAL

Renamed two game-state variables:
- `SCORE_ACCUM` ($2C29, word) -> `PUNTUACION` (accumulated score).
- `CURRENT_LEVEL` ($2C07) -> `NIVEL_ACTUAL` (current level, 1-15).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### FIRST_LOOP_FLAG -> CONTADOR_VUELTAS_NIVELES (and finding: it affects level design on later loops)

Renamed `FIRST_LOOP_FLAG` to `CONTADOR_VUELTAS_NIVELES`, after
confirming it isn't a simple boolean but a COUNTER of complete loops
through the 15-level cycle: it's incremented in `IML_90D8`
(madmix1.asm) every time `NIVEL_ACTUAL` wraps from 16 to 1 (having
also completed the hidden/15th level), and reset to 0 in
`REINICIAR_PARTIDA`.

**Undocumented design finding until now**: in `LEVEL_LOADER`
(madmix_scr.asm, lines ~3122-3157) this counter decides how a
level's body gets copied to the active RAM:
- Value 0 (first loop): copies the level as-is (.plain_copy).
- Value !=0 (second loop or more): activates `.with_wildcard` --
  replaces, alternating one-in-two, every "wildcard" tile ($3C) in
  the map with `LEVEL_REC_WILDCARD_TILE` (a specific tile from that
  level's record). In other words: level design changes slightly
  starting from the second complete loop -- a discrete "loop+"
  variation mechanism never documented before in the project.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### Hex fixed: JP $8F71 -> JP INIT_MAINLOOP_ENTRY_8F71

While explaining `INIT_MAINLOOP_ENTRY_8F71`, the same usual systemic
pattern was found: `JP $8F71` in `IML_90D8` (line ~2609) used hex
instead of the already-confirmed label, even though the comment
itself already named it. Fixed.

While explaining it: `INIT_MAINLOOP_ENTRY_8F71` is the point that
"reloads the current level's HUD without resetting lives/score" --
counterpart of `REINICIAR_PARTIDA` (which does reset everything).
Reached by falling through with no jump after `REINICIAR_PARTIDA`
(new game) or via this `JP` from `IML_90D8` every time a level is
completed and it advances to the next one.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- only hex
substituted with an already-existing label, zero content changes.

### INIT_MAINLOOP_ENTRY_8F71 -> PANTALLA_PRESENTACION_NIVEL

Renamed `INIT_MAINLOOP_ENTRY_8F71` to `PANTALLA_PRESENTACION_NIVEL`.
It's the point that "reloads the current level's HUD without
resetting lives/score" -- counterpart of `REINICIAR_PARTIDA` (which
does reset everything). Reached by falling through with no jump
after `REINICIAR_PARTIDA` (new game) or via `JP` from `IML_90D8`
every time a level is completed. Its body draws the "STAGE XX" text,
the extra-life notice and "READY?" before loading the level with
`LEVEL_LOADER` -- hence the name, it's the presentation/transition
screen between levels.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### GAME_STATE_FLAG -> FLAG_NIVEL_RECIEN_CARGADO

Renamed `GAME_STATE_FLAG` to `FLAG_NIVEL_RECIEN_CARGADO`, after
confirming its exact role: a "consume once" flag. It's set to 1 at 2
points in `PANTALLA_PRESENTACION_NIVEL` (right before calling
`LEVEL_LOADER`, and again after drawing "READY?"), and consumed by
`ACTUALIZAR_VRAM_FRAME` (called once per frame from the interrupt):
it reads it, immediately sets it to 0, and depending on its value
chooses between a deeper VRAM refresh (FILVRM over $2220) or the
normal incremental path.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### Hex fixed: 5x CALL $89A0 -> CALL WAIT_VBLANK

The developer asked whether `$89A0` (inside
`PANTALLA_PRESENTACION_NIVEL`) had a label -- yes, it's `WAIT_VBLANK`
(already confirmed, `JT_WAIT_VBLANK`'s target). 5 sites in
`madmix1_body.asm` were found still using `CALL $89A0` instead of the
label, even though the comment already named it in each one. All
fixed.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- only hex
substituted with an already-existing label, zero content changes.
`.dsk`/`.cas`/HTML inventory regenerated: 743 labels (no change in
total).

### LEVEL_LOADER -> CARGAR_NIVEL

Renamed `LEVEL_LOADER` to `CARGAR_NIVEL`: loads the current level's
record from `LEVEL_TABLE`, copies header+body+footer to the active
buffer ($FC50), resets the ball counter/camera position/color/
special mode/HUD icon, and calls `TABLE_INIT`.

Along the way, 3 more sites with the systemic hex-not-substituted
pattern were fixed: `CALL $5885` (x2, one of them inside
`CARGAR_NIVEL` itself) -> `CALL TABLE_INIT`, and `CALL $5904` ->
`CALL CARGAR_NIVEL` (in `TAIL_LEVELCYCLE_MAIN`, the demo mode's
sample-level cycler).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html`, `recursos/mapa_memoria.html`,
`recursos/niveles.html` and `recursos/editor_niveles.html` updated.

### Hex fixed: LD HL,$9153 -> LD HL,LEVEL_NUM_TABLE

The developer asked whether `$9153` (inside
`PANTALLA_PRESENTACION_NIVEL`, right after `CARGAR_NIVEL`) had a
label -- yes, it's `LEVEL_NUM_TABLE` (the string
" 0 1 2...9101112131415" with the level numbers as 2-digit text).
The code indexes this table by `NIVEL_ACTUAL*2` to get the number to
show on the HUD ("STAGE XX"). Same usual systemic pattern (hex
instead of an already-existing label), fixed.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- only hex
substituted with an already-existing label, zero content changes.
`.dsk`/`.cas`/HTML inventory regenerated: 743 labels (no change in
total).

### LEVEL_NUM_TABLE -> TABLA_NUMEROS_NIVEL

Renamed `LEVEL_NUM_TABLE` (string " 0 1 2...9101112131415" with the
level numbers as 2-digit text, indexed by NIVEL_ACTUAL*2) to
`TABLA_NUMEROS_NIVEL`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files.

### Hex fixed: $9151/$9149 -> FASE_TEXT+8/FASE_TEXT (label arithmetic)

`$9151` had no label of its own, but falls inside `FASE_TEXT`
($9149: `DB $08,$B0," FASE 00"`) -- it's exactly the first digit of
the "00" placeholder (offset +8), where the code writes the real
level number read from `TABLA_NUMEROS_NIVEL` before drawing the
text. Substituted `LD DE,$9151` with `LD DE,FASE_TEXT+8` (label
arithmetic, same pattern already used in earlier rounds for other
tables) and, along the way, `LD DE,$9149` (the same base address)
with `LD DE,FASE_TEXT`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- the assembler
computes the exact same bytes, zero content changes. `.dsk`/`.cas`/
HTML inventory regenerated: 743 labels (no change in total).

### FASE_TEXT -> TEXTO_FASE

Renamed `FASE_TEXT` (the "FASE 00" template with a replaceable level
number, offset +8) to `TEXTO_FASE`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### New label: TABLA_POSICIONES_HUD ($9136) + hex breakdown

The anonymous 19-byte table at `$9136` (right before `TEXTO_FASE`)
had no label of its own; the raw hex `$9136`/`$9147`/`$9148` was used
at several sites in `madmix1_body.asm` and `madmix_scr_body.asm`.
Analyzing the content revealed a real, non-random structure:

```
$08,$48, $10,$50, $18,$58, $20,$60, $28,$68, $30,$70, $38,$78, $40, $00,$00,$00,$00
```

They're `(v, v+$40)` pairs with `v` climbing by 8 (`$08..$38`), plus
a lone `$40` -- exactly every multiple of 8 between `$08` and `$78`,
the range that survives the `AND $78` mask used by the
`IML_900F` search loop. The last 4 bytes (offsets 15-18) are
padding/values overwritten at runtime ($9147=offset 17,
$9148=offset 18: HUD icon/color). Probable hint of two HUD-column
rows $40 positions apart from each other (fine detail of what each
row is for not confirmed).

Applied: label `TABLA_POSICIONES_HUD` at `$9136`, broken down into
several `DB` lines showing the pattern (instead of a single hex
line), and substituted the `LD HL,$9136` / `($9147)` / `($9148)`
uses with `TABLA_POSICIONES_HUD` / `TABLA_POSICIONES_HUD+17` /
`TABLA_POSICIONES_HUD+18` in both `_body.asm` files.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (one more: the new table label).
`recursos/mapa_memoria.html` updated with the new label and the
pattern detail.

### LEVEL_REC_WORK -> REGISTRO_NIVEL

Renamed `LEVEL_REC_WORK` (one of the 3 labels stacked at `$2BF3`
together with `MAINLOOP_TABLES` and `LEVEL_REC_BODY_PTR`, with no
distance between them) to `REGISTRO_NIVEL`. It's the start of the
20-byte RAM working copy of the level record that `CARGAR_NIVEL`
copies from `LEVEL_TABLE` (ROM) via `LDIR` when loading each level.
No code references (only used as a definition label).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### The 15 fields of REGISTRO_NIVEL renamed to Spanish

Renamed the 15 fields of the level record (offsets 0-19,
`$2BF3-$2C06`), all with the `LEVEL_REC_` prefix or loose English
names, to Spanish names with the common prefix `REGISTRO_NIVEL_`:

- `LEVEL_REC_BODY_PTR` -> `REGISTRO_NIVEL_CUERPO_PTR` (offset 0-1)
- `LEVEL_REC_HEADER_PTR` -> `REGISTRO_NIVEL_CABECERA_PTR` (offset 2-3)
- `LEVEL_REC_HEADER_PTR2` -> `REGISTRO_NIVEL_PIE_PTR` (offset 4-5;
  duplicate of the previous one, reused to also copy the header
  below the body -- hence "PIE"/footer)
- `LEVEL_REC_ROWS` -> `REGISTRO_NIVEL_FILAS` (offset 6)
- `FLAG_VIDA_EXTRA_NIVEL` -> `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` (offset 7)
- `LEVEL_REC_PELMAZOIDE_COUNT` -> `REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (offset 8)
- `LEVEL_REC_MARICOCO_COUNT` -> `REGISTRO_NIVEL_CONTADOR_MARICOCOS` (offset 9)
- `LEVEL_REC_REGPUNANTOSO_COUNT` -> `REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS` (offset 10)
- `LEVEL_REC_BLINK_DURATION` -> `REGISTRO_NIVEL_DURACION_PARPADEO` (offset 11)
- `LEVEL_REC_WILDCARD_TILE` -> `REGISTRO_NIVEL_LOSETA_COMODIN` (offset 12)
- `LEVEL_REC_REF_ROWCOL` -> `REGISTRO_NIVEL_FILA_COLUMNA` (offset 13-14)
- `LEVEL_REC_START_POS` -> `REGISTRO_NIVEL_POSICION_INICIAL` (offset 15-16,
  field alias -- see next)
- `PACMAN_POS` -> `REGISTRO_NIVEL_POSICION_COMECOCOS` (same offset
  15-16 as the previous one: it's the pac-man/camera's live position
  throughout the game, $2C02, used by dozens of sites)
- `LEVEL_REC_HUD_ICON` -> `REGISTRO_NIVEL_ICONO_HUD` (offset 17)
- `LEVEL_REC_BALL_TARGET` -> `REGISTRO_NIVEL_OBJETIVO_BOLAS` (offset 18-19)

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total, 1:1 renames).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated (manual blocks with the old names).

### CURRENT_COLOR -> COLOR_ACTUAL

Renamed `CURRENT_COLOR` to `COLOR_ACTUAL` (game-state variable
alongside `SAVED_COLOR`, used for the HUD/text attribute color).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### TABLA_POSICIONES_HUD: why it's in (column, column+$40) pairs

The developer asked whether the table might instead be
(position,color) pairs per entry. Investigating the real consumer
(`IML_900F`, further down in the same `INICIO` block) confirmed the
exact mechanism: after the search, the HUD/`READY?` color is derived
from `(TABLA_POSICIONES_HUD+17) AND $48 XOR $5F` via
`TAIL_TILE_LOOKUP` -- **no** color byte is read from the table
itself. But the `$48` mask keeps bit 3 and bit 6, and bit 6 is
EXACTLY the bit that distinguishes each `(v, v+$40)` pair in the
table. In other words: they aren't independent (position,color)
pairs -- it's the same bit of the same target variable that decides
both the search order/row in the table AND contributes color. The
table's comment in `madmix1_body.asm` and the corresponding detail
in `recursos/mapa_memoria.html` updated to reflect this (also
substituting the residual raw hex `$9147` with
`TABLA_POSICIONES_HUD+17`).

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).
`recursos/mapa_memoria.html` updated.

### TAIL_TILE_LOOKUP -> OBTENER_COLOR_VDP

Renamed `TAIL_TILE_LOOKUP` ($6484) to `OBTENER_COLOR_VDP`. The
`TAIL_` prefix was left over from the provisional naming of the
session that disassembled the last unexplored stretch of
`madmix_scr.asm` (`0x5AD5-0x6500`, the relocated block's "tail" --
see the round "`0x5AD5-0x6500` fully transcribed"), unrelated to what
the function actually does. Its exact behavior was confirmed: given
an input byte, it extracts two 4-bit codes (one from bits 3-6,
another from bits 0-2 combined with reused bit 6), looks each up in
`DIRBITS_TABLE` ($8978) and combines the results into a VDP color
byte (high nibble = ink, low nibble = paper, the SCREEN2 color-table
format). Confirmed use in `APLICAR_COLOR_PANTALLA` (real color of
the candy frame/screen) and in `IML_900F` (HUD/`READY?` color). Its
header comment was also updated to reflect this explicitly.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/graficos.html` updated.

### CLEAR_TEXT_1/2 -> TEXTO_VACIO_1/2, READY_TEXT -> TEXTO_READY

Renamed the 3 text entries `IML_900F` draws alongside the level-start
message: `CLEAR_TEXT_1`/`CLEAR_TEXT_2` (the two blank lines that
"clear" before/after) to `TEXTO_VACIO_1`/`TEXTO_VACIO_2`, and
`READY_TEXT` ("READY?") to `TEXTO_READY`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### New label: MOSTRAR_READY_Y_ARRANCAR_NIVEL ($902A)

The developer raised a legitimate architectural question: does
`IML_900F`'s functionality end at the `XOR A` (loop exit), with
everything that follows from `LD ($8EC6),A` being a distinct block
with a different purpose? Grepping confirmed that no `JP`/`JR`/`CALL`
anywhere in the whole source code points to that address ($902A) --
it's reached exclusively by falling through naturally out of the
loop. Even so, they are two clearly distinct functionalities chained
together: `IML_900F` is the search/wait loop (visible sweep effect on
the HUD icon); from `$902A` onward is the "presentation" of the level
start (re-enables the keyboard, computes the HUD/READY? color, draws
the 3 lines of text, sets FLAG_NIVEL_RECIEN_CARGADO and starts the
3 channels of the level jingle) -- no longer dependent on the search
result except for color.

Applied: new label `MOSTRAR_READY_Y_ARRANCAR_NIVEL` at `$902A`
(purely documentational, without changing the actual execution
flow), with a comment explaining the split and why it's only reached
by natural fall-through.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (one more: the new label).
`recursos/mapa_memoria.html` updated.

### IML_900F -> BUSCAR_COLUMNA_HUD

After splitting off `MOSTRAR_READY_Y_ARRANCAR_NIVEL` (previous
round), `IML_900F` itself is left with only the search/wait loop
over `TABLA_POSICIONES_HUD`. Renamed to `BUSCAR_COLUMNA_HUD`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### Hex fixed: $9145 -> TABLA_POSICIONES_HUD+15

`$9145` (the 2-byte pointer `BUSCAR_COLUMNA_HUD` leaves pointing to
the matching entry, reused afterward by `INIT_HELPER_9116`'s
"typewriter" effect) had no label of its own, but falls inside
`TABLA_POSICIONES_HUD` (offset 15: exactly the first free byte after
the 15 real search values, offsets 0-14). The 3 references in
`madmix1_body.asm` were substituted with `TABLA_POSICIONES_HUD+15`
(label arithmetic).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### MAIN_LOOP -> MOTOR_MOVIMIENTO_COLISION, RAM_HOOK_2C36 -> ENLACE_MOTOR_MOVIMIENTO_COLISION

The developer proposed renaming `RAM_HOOK_2C36` to a name describing
the engine it points to, but was told that would poorly describe the
hook itself (which is a trampoline, not the engine itself) -- it
would fit `MAIN_LOOP` better, the routine that actually does that
work (its own header comment already called it "COLLISION/MOVEMENT
ENGINE"). The developer agreed to rename both things consistently:
`MAIN_LOOP` -> `MOTOR_MOVIMIENTO_COLISION` and `RAM_HOOK_2C36` ->
`ENLACE_MOTOR_MOVIMIENTO_COLISION`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### RM_C4CC -> INSTALAR_RECURSO_SONIDO_EN_A

Renamed `RM_C4CC` to `INSTALAR_RECURSO_SONIDO_EN_A`: same body as
`INSTALAR_RECURSO_SONIDO` but with the slot index EXPLICIT in `A`
(instead of searching for a free slot). No HTML changes (no
references outside code).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### IML_WAIT_90EC -> PAUSAR_PARTIDA

Renamed `IML_WAIT_90EC` to `PAUSAR_PARTIDA`. Confirmed its dual use:
(1) a mandatory 50-frame wait + key poll when starting each level
(from `MOSTRAR_READY_Y_ARRANCAR_NIVEL`), and (2) a real pause
triggered by the player during play via input bit 5 (unidentified),
checked in `IML_90E4`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### IML_9078 -> BUCLE_PRINCIPAL_JUEGO

Renamed `IML_9078` to `BUCLE_PRINCIPAL_JUEGO`: it's, literally, the
game's main loop (unlike `PREPARAR_INICIO_NIVEL`, which is only the
transition sequence) -- each pass advances the engine
(`ENLACE_MOTOR_MOVIMIENTO_COLISION`), checks the "life lost" timer
(`MODO_ESPECIAL_ACTIVE`), falls into `IML_90B7` (checks level end)
and into `IML_90E4` (polls the pause key), and repeats.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### IML_90B7 -> VERIFICAR_FIN_NIVEL

Renamed `IML_90B7` to `VERIFICAR_FIN_NIVEL`: the stretch of
`BUCLE_PRINCIPAL_JUEGO` that compares `BALLS_EATEN_COUNT` against
`REGISTRO_NIVEL_OBJETIVO_BOLAS` and, if they match, advances
`NIVEL_ACTUAL` and jumps to `PANTALLA_PRESENTACION_NIVEL`; if not, it
continues to the pause poll (`IML_90E4`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### FIXED: INIT_HELPER_9116 is NOT a "typewriter" that reveals text

The historical comment for `INIT_HELPER_9116` claimed it revealed
the HUD (STAGE/READY/etc) "position by position", like a typewriter.
Reviewing what was already confirmed about `REGISTRO_NIVEL_ICONO_HUD`
and `COLOR_ACTUAL` (the "New label: MOSTRAR_READY_Y_ARRANCAR_NIVEL"
round and the `ACTUALIZAR_VRAM_FRAME` analysis), that description is
incorrect: the bytes it copies are the raw values of
`TABLA_POSICIONES_HUD` ($08/$48/.../$78/$40), NOT text codes.
`REGISTRO_NIVEL_ICONO_HUD` doesn't draw text -- it feeds
`ACTUALIZAR_VRAM_FRAME`, which fills (FILVRM, solid fill) 18 VRAM
blocks at `$2220` if the value changed; `COLOR_ACTUAL` is reread
right there EVERY frame unconditionally to fill 2 other VRAM color
zones (`$2A80`/`$2B80`). The real effect is a fast icon+color
transition flicker/flash, not a letter-by-letter reveal of "READY?"
(that text is drawn separately, only once, in
`MOSTRAR_READY_Y_ARRANCAR_NIVEL`). Header comment fixed in
`madmix1_body.asm`, with a pending note to confirm the real
appearance of this flash live (emulator).

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).
`recursos/mapa_memoria.html` updated.

### FIXED: comment on the TAIL_VDP_FILL call in the GAME OVER sequence

The comment on the call to `TAIL_VDP_FILL` from the GAME OVER
sequence (`madmix1_body.asm`) said "fills the VRAM border" -- wrong
on both counts, per what was already confirmed in `TAIL_VDP_FILL`'s
own header comment: it fills the PLAYABLE AREA (not the border/
frame) of the `$DE04` RAM buffer (not VRAM directly). Fixed to
reflect this.

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### VERIFIED LIVE: TAIL_VDP_FILL on GAME OVER makes the play area BLACK, no flicker

The developer tested the Game Over sequence in the emulator (losing
all lives): the play area turns **black** and "YOU'RE TOAST" appears,
**with no visible flash or flicker at all**. This resolves the open
question of what ink color `TAIL_VDP_FILL`'s `$FF` fill uses
(confirms it's black at that moment) and confirms the effect is a
one-time static fill, not a flash/blink -- consistent with
`TAIL_VDP_FILL` only being called once (not inside an alternating
loop). The call's comment in `madmix1_body.asm` updated with this
verification.

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### TAIL_VDP_FILL -> RELLENAR_SOLIDO_BUFFER_VRAM

Renamed `TAIL_VDP_FILL` to `RELLENAR_SOLIDO_BUFFER_VRAM`. Closed the
`$DE04` fill finding: it's always a SOLID one-time fill (no
parameters or alternating loop), only of the playable area (24 of 32
bytes/row, not the candy frame). Confirmed live by the developer in
the Game Over sequence: the play area turns black (ink color = black
at that moment) with no flicker at all.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### RELLENAR_SOLIDO_BUFFER_VRAM -> RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM, GAMEOVER_TEXT -> TEXTO_GAME_OVER

Two more renames in the Game Over sequence:
`RELLENAR_SOLIDO_BUFFER_VRAM` (this same round's previous name) was
refined to `RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM` to make it
explicit that it only fills the playable area (not the frame); and
`GAMEOVER_TEXT` ("YOU'RE TOAST") to `TEXTO_GAME_OVER`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### IML_LOOP_90B1 -> ESPERA_150_FRAMES

Renamed `IML_LOOP_90B1` to `ESPERA_150_FRAMES`: the `HALT`/`DJNZ`
loop (B=$96=150) that keeps the Game Over message visible before
restarting the game.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### BALLS_EATEN_COUNT -> CONTADOR_BOLAS_COMIDAS

Renamed `BALLS_EATEN_COUNT` to `CONTADOR_BOLAS_COMIDAS`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### BALL_BLINK_POS -> POSICION_PARPADEO_BOLA, MODO_ESPECIAL_COUNTDOWN -> MODO_ESPECIAL_CUENTA_ATRAS, MODO_ESPECIAL_ACTIVE -> MODO_ESPECIAL_ACTIVO

Three game-state variable renames (direct translation to Spanish, no
change in meaning).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### IML_90FD -> SALTAR_A_BUCLE_PRINCIPAL_JUEGO

Renamed `IML_90FD` to `SALTAR_A_BUCLE_PRINCIPAL_JUEGO`: the common
reunion point (from the pause poll when not triggered, or after
resuming from `PAUSAR_PARTIDA`) that does `JP BUCLE_PRINCIPAL_JUEGO`.
Along the way, identified that the next 2 instructions (`CALL
VACIAR_CANALES_SONIDO` / `JP $0040`) are unreachable code (the
unconditional `JP` above never falls through to them) -- `$0040`
also falls in the middle of the MSX BIOS's jump table, not a valid
entry address by itself.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### IML_90E4 -> VERIFICAR_ENTRADA

Renamed `IML_90E4` to `VERIFICAR_ENTRADA`: polls the keyboard/
joystick (bit 5, exact physical button/key still unidentified, a
pause/confirm candidate) when the level hasn't been completed yet,
and if it's active it enters `PAUSAR_PARTIDA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### IML_WAITLOOP_90EF -> BUCLE_PAUSA

Renamed `IML_WAITLOOP_90EF` to `BUCLE_PAUSA`: the `HALT`/`DJNZ` loop
of the fixed 50-frame wait inside `PAUSAR_PARTIDA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### IML_90D8 -> SIGUIENTE_NIVEL

Renamed `IML_90D8` to `SIGUIENTE_NIVEL`: the common reunion point
after completing any level (reached by a direct jump in the normal
case, or by falling through after the reset-to-level-1 block when
the whole cycle loop, including the hidden level 15, is completed)
-- calls INIT_HELPER_9116, copies the extra-life flag, and jumps to
PANTALLA_PRESENTACION_NIVEL.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### FIXED: wrong comment about the blink rhythm of INIT_HELPER_9106

A comment manually added by the developer at the call to
`INIT_HELPER_9106` (inside `VERIFICAR_FIN_NIVEL`) claimed "blinks
every 4 frames" -- doesn't match the real code (uses bit 6 of the
counter, which changes every 64 increments) nor the live
verification already done by the developer (that tile doesn't
visibly blink). Fixed to point to the real mechanism of the pac-
man's visible blink (`ML_POWER_BLINK_COLOR`, already documented in
an earlier round).

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### INIT_HELPER_9106 -> ACTUALIZAR_LOSETA_BOLA_ESPECIAL, INIT_HELPER_9116 -> DESTELLO_ICONO_COLOR_HUD

The developer asked whether the two functions `INIT_HELPER_9106`/
`INIT_HELPER_9116` (same inherited generic name, differing only in
address) did the same thing. Comparing the real code: NO -- one
writes a single byte to a fixed maze tile (the special ball, no loop
of its own, relies on the caller already running once per frame) and
the other walks several bytes of TABLA_POSICIONES_HUD in its own
loop with its own VBLANK wait, writing to HUD icon/color variables.
Renamed to make this clear: `INIT_HELPER_9106` ->
`ACTUALIZAR_LOSETA_BOLA_ESPECIAL`, `INIT_HELPER_9116` ->
`DESTELLO_ICONO_COLOR_HUD`. Along the way, fixed an index comment
(madmix1_body.asm ~2397) that still described
`DESTELLO_ICONO_COLOR_HUD` as a "typewriter-style text reveal" --
already fixed in the function's header comment in an earlier round,
but not at this second site.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_READ_REAL_INPUT -> SALTAR_A_LEER_ENTRADA

Renamed `ML_READ_REAL_INPUT` to `SALTAR_A_LEER_ENTRADA`: the branch
of `MOTOR_MOVIMIENTO_COLISION` (normal mode, not demo) that calls
`LEER_ENTRADA` to get the player's real direction.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### RAW_DIRECTION -> DIRECCION_SIN_PROCESAR

Renamed `RAW_DIRECTION` to `DIRECCION_SIN_PROCESAR`: the "raw"
direction for each frame, saved by `ML_STORE_DIRECTION` before any
alignment validation (parallel to `DIRECCION_DE_MOVIMIENTO`, which
is the already-filtered/validated version).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### DIR_INPUT_LATCH -> FLAG_DIRECCION_NUEVA

Renamed `DIR_INPUT_LATCH` to `FLAG_DIRECCION_NUEVA`: a boolean flag
(0/1, not a direction) that's only set on the first frame in which a
direction is detected after there being none -- distinguishes a
"freshly arrived press" from a "direction held for several frames".

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_LATCH_CLEAR -> LIMPIAR_FLAG_DIRECCION

Renamed `ML_LATCH_CLEAR` to `LIMPIAR_FLAG_DIRECCION`: the branch that
disarms `FLAG_DIRECCION_NUEVA` (sets it to 0) when no direction is
pressed this frame.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_LATCH_STORE -> COPIAR_FLAG_DIRECCION

Renamed `ML_LATCH_STORE` to `COPIAR_FLAG_DIRECCION`: the confluence
point of the 3 branches of the latch mechanism (held/new/no input)
that copies the result into `INPUT_EDGE_FLAG`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_STORE_DIRECTION -> PROCESAR_DIRECCION

Renamed `ML_STORE_DIRECTION` to `PROCESAR_DIRECCION`: receives this
frame's direction (from the real keyboard or a demo script), saves
it in `DIRECCION_SIN_PROCESAR`/`B`, and updates the "new press" latch
mechanism (`FLAG_DIRECCION_NUEVA`/`INPUT_EDGE_FLAG`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### CAMERA_POS -> POSICION_ACTUAL_CAMARA

Renamed `CAMERA_POS` to `POSICION_ACTUAL_CAMARA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_ALIGN_START -> CALCULAR_MASCARA_ALINEAMIENTO

Renamed `ML_ALIGN_START` to `CALCULAR_MASCARA_ALINEAMIENTO`: starts
computing the mask of valid turns based on alignment with the tile
(X/Y axis), from the alignment value `C` (real or forced by
`DIRECCION_FORZADA`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_ALIGN_CHECK_Y -> COMPROBAR_ALINEAMIENTO_Y

Renamed `ML_ALIGN_CHECK_Y` to `COMPROBAR_ALINEAMIENTO_Y`: second half
of the alignment-mask computation (Y axis, after the X check in
`CALCULAR_MASCARA_ALINEAMIENTO`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_ALIGN_APPLY -> APLICAR_MASCARA_ALINEAMIENTO

Renamed `ML_ALIGN_APPLY` to `APLICAR_MASCARA_ALINEAMIENTO`: applies
the mask (E) to the candidate direction (C) -- if it's still valid
it's accepted, otherwise it falls back to the previous frame's
direction (B).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_DIR_FINALIZE -> FIJAR_DIRECCION_FINAL

Renamed `ML_DIR_FINALIZE` to `FIJAR_DIRECCION_FINAL`: saves the
final `DIRECCION_DE_MOVIMIENTO` and starts the tile-type query
(`CHECK_TILE_DELTA`), with a retry using the previous frame's
direction (B) if the first query returns a normal type (0).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### CHECK_TILE_DELTA -> CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION

Renamed `CHECK_TILE_DELTA` to
`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`: shifts the camera
position one tile according to the received direction bit, and
queries that tile's type (with column/type caching).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_TILE_TYPE_INDEX -> CALCULAR_INDICE_TIPO_LOSETA

Renamed `ML_TILE_TYPE_INDEX` to `CALCULAR_INDICE_TIPO_LOSETA`:
converts the tile type into `ML_DISPATCH_TABLE`'s word index, and
applies the override that forces index 0 while a special mode
(`MODO_ESPECIAL_ACTIVO`) lasts.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_DISPATCH_LOOKUP -> OBTENER_MANEJADOR_LOSETA

Renamed `ML_DISPATCH_LOOKUP` to `OBTENER_MANEJADOR_LOSETA`: indexes
`ML_DISPATCH_TABLE` with the already-computed offset and leaves the
handler's real pointer in `IX`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_DISPATCH_TABLE -> TABLA_MANEJADORES_LOSETA

Renamed `ML_DISPATCH_TABLE` to `TABLA_MANEJADORES_LOSETA`: the 20
dispatch pointers by tile type (0-19).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### RESOLVED: TILE_DISPATCH_TABLE -> TABLA_CLASE_ALINEAMIENTO

The developer asked for a full analysis of `TILE_DISPATCH_TABLE`'s
usage (marked as "exact use beyond being stored in C unconfirmed").
Tracing forward from `OBTENER_MANEJADOR_LOSETA` found that C (this
table's value, 0-4) gets combined in `ML_DIR_SUBTABLE_LOOP` with the
rotating index `DIR_TABLE_INDEX` (offset = C*4 + index) to select an
entry from the 20-byte subtables (`SUBTABLE_A/B/C/D`) -- exactly the
mechanism of `SELECTOR_SPRITE_COMECOCOS` already resolved in an
earlier round. A SECOND use was also found, in the ghost/item AI
(lines ~2036-2074): there the same table converts a direction in
bitmask format ($01/$02/$04/$08) into the same 1-4 compact code, to
index ghost/maricoco/repugnantoso sprite tables -- a more generic
purpose ("compact a direction bitmask into an index") that the
chosen name doesn't fully cover, but the developer confirmed keeping
`TABLA_CLASE_ALINEAMIENTO` (more precise for the main/original use)
instead of a more neutral name.

Renamed `TILE_DISPATCH_TABLE` -> `TABLA_CLASE_ALINEAMIENTO`, header
comments and both usage sites updated to reflect the resolved
mechanism.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_DELTA_CHECK_LEFT -> COMPROBAR_LOSETA_IZQUIERDA

Renamed `ML_DELTA_CHECK_LEFT` to `COMPROBAR_LOSETA_IZQUIERDA`: one of
the 4 links in `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`'s chain
that checks bit by bit which direction (right/left/down/up) is
active in the received bitmask.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_DELTA_RESOLVE -> IDENTIFICAR_PROXIMA_LOSETA

Renamed `ML_DELTA_RESOLVE` to `IDENTIFICAR_PROXIMA_LOSETA`: reunion
point of the direction-check chain, where the already-shifted
position is converted into a real VRAM address and the tile type is
identified (with caching).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### ML_DELTA_CHECK_DOWN -> COMPROBAR_LOSETA_ABAJO, ML_DELTA_CHECK_UP -> COMPROBAR_LOSETA_ARRIBA

Complete the 4-link chain of
`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` (right inline,
`COMPROBAR_LOSETA_IZQUIERDA`, `COMPROBAR_LOSETA_ABAJO`,
`COMPROBAR_LOSETA_ARRIBA`), all consistently named now.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### PENDING: +4/-1 asymmetry in CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION

The developer asked whether the comments on the
`COMPROBAR_LOSETA_IZQUIERDA/ABAJO/ARRIBA` chain were correct. The
part about which bit corresponds to which direction is right (bit0=
right, bit1=left, bit2=down, bit3=up, confirmed by the order of the
4 `RRA` rotations), but a real, unexplained asymmetry was found:
right/down add `$04` (a full tile step, which always survives the
`AND $7C` in `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` at
`madmix1_body.asm:1811-1827`), while left/up only subtract 1
(`DEC C`/`DEC B`) -- a change that might NOT cross any tile boundary,
depending on the pac-man's current sub-position. Not confirmed
whether this is deliberate original behavior or an unexplored edge
case. Noted as a `PENDIENTE`/PENDING comment in the code (right
before `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`), pending live
verification in the emulator.

**Verified**: recompiled with no errors (comment-only change), diffs
at the exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### TILE_COL_CACHE -> CACHE_COLUMNA_LOSETA, TILE_TYPE_CACHE -> CACHE_TIPO_LOSETA

Renamed the pair of caches in `IDENTIFICAR_PROXIMA_LOSETA` that avoid
repeating `CONSULTAR_TIPO_LOSETA` when the queried column is the same
as last time.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### ML_DELTA_MASK_RESULT -> ENMASCARAR_TIPO_LOSETA

Renamed `ML_DELTA_MASK_RESULT` to `ENMASCARAR_TIPO_LOSETA`: final
reunion point of `IDENTIFICAR_PROXIMA_LOSETA` (cache or real query)
that applies `AND $1F` to keep the 5 low bits (0-19) before returning
control.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### INPUT_EDGE_FLAG -> COPIA_FLAG_DIRECCION_NUEVA

Renamed `INPUT_EDGE_FLAG` to `COPIA_FLAG_DIRECCION_NUEVA`: a
queryable copy of `FLAG_DIRECCION_NUEVA` that the rest of the engine
uses to detect the press edge (e.g. `TRAPDOOR_FLIP_TABLE` is only
called once per new press, not on every held frame).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### FIXED: "trapdoors" -> "tank/plane hint" (HINT_POS_TABLE/TRAPDOOR_FLIP_TABLE and family)

The developer questioned why "trapdoors" kept being mentioned while
explaining `TRAPDOOR_FLIP_TABLE` -- correctly: it's a terminology
error inherited from an old, unconfirmed hypothesis. The code itself
already had the answer resolved in `GHOST_HINT_HANDLER`'s header
comment ("'Hint' handler (tank/plane...") and in
`SOUND_EVT04_CE72`'s comment ("CONFIRMED by the developer... Shot
(plane mode)"), which had never been cross-checked against the rest
of the ambiguous "trapdoor/hint" comments scattered through the
file.

**Important**: there are TWO distinct systems that mistakenly shared
vocabulary:
1. **REAL trapdoors** (tile types 17-19):
   `HNDLR_TRAMPILLA_ABIERTA_DERECHA/IZQUIERDA/CERRADA(_B)`,
   `TRAPDOOR_PHASE`, `TRAPDOOR_ANIM_EXIT`, `SOUND_EVT09_CE5A`, the
   `data/tiles/*trampilla*.til` files -- these ARE trapdoors, no
   changes.
2. **Tank/plane hint** (table `$2C2E`, triggered by
   `HNDLR_PISTA_COCOTANQUE`/`HNDLR_PISTA_COCONAVE`, queried by
   `GHOST_HINT_HANDLER`) -- this was NEVER about trapdoors, renamed:
   - `HINT_POS_TABLE` -> `TABLA_PISTA_TANQUE_AVION`
   - `TRAPDOOR_FLIP_TABLE` -> `REGISTRAR_PISTA_TANQUE_AVION`
   - `TRAPDOOR_FLIP_SCAN` -> `BUSCAR_HUECO_PISTA`
   - `TRAPDOOR_FLIP_SET` -> `FIJAR_PISTA`
   - `TRAPDOOR_FLIP_STORE` -> `GUARDAR_PISTA`
   - `ML_TRAPDOOR_LOOP` -> `ML_PISTA_LOOP`
   - `ML_TRAPDOOR_NEXT` -> `ML_PISTA_NEXT`
   - `ML_TRAPDOOR_FORMAT_B`/`_POS` -> `ML_PISTA_FORMATO_B`/`_POS`
   - `ML_TRAPDOOR_ROW_FIXED` -> `ML_PISTA_FILA_FIJA`
   - `ML_TRAPDOOR_DRAW` -> `ML_PISTA_DIBUJAR`

   Also fixed ~15 loose comments that said "trapdoor(s)" in the
   context of this second system (the table's definition, the draw
   loop in MOTOR_MOVIMIENTO_COLISION, GHOST_HINT_HANDLER,
   HNDLR_PISTA_COCOTANQUE, TI_2C2E_ENTRY, SOUND_EVT04_CE72).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total, 1:1 renames).
`recursos/mapa_memoria.html` and `recursos/flujo_programa.html`
updated.

### ITEM_TIMER_TICK -> ACTUALIZAR_DESTELLO_ITEMS

Renamed `ITEM_TIMER_TICK` to `ACTUALIZAR_DESTELLO_ITEMS`: animates up
to 4 simultaneous entries of the special-item "sparkle" sequence
(`ITEM_TABLE_EFECTOS_DESTELLO`), called once per frame
unconditionally.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/flujo_programa.html` updated.

### SAVED_COLOR -> COLOR_GUARDADO

Renamed `SAVED_COLOR` to `COLOR_GUARDADO`: backup copy of
`COLOR_ACTUAL`, saved/restored on entry/exit transitions of the
special modes.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### TI_2C2E_ENTRY -> INICIALIZAR_PARCIAL_ITEMS_NIVEL

Renamed `TI_2C2E_ENTRY` to `INICIALIZAR_PARCIAL_ITEMS_NIVEL`: second
entry point into `INICIALIZAR_ITEMS_NIVEL` that only clears
`TABLA_PISTA_TANQUE_AVION`, used when exiting the tank/plane modes.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 744 labels (no change in total).

### TI_CLR2C2E -> .LOOP_LIMPIEZA (local label)

Renamed `TI_CLR2C2E` to `.LOOP_LIMPIEZA` (SjASMPlus local label,
scope `INICIALIZAR_PARCIAL_ITEMS_NIVEL`): the loop that clears the
"active" flag of `TABLA_PISTA_TANQUE_AVION`'s 3 entries.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (one fewer since it's now local,
same pattern already seen with `.CONTINUAR_RESPAWN`).

### TI_CLR5773 -> .LOOP_LIMPIEZA_DESTELLO (local label)

Renamed `TI_CLR5773` to `.LOOP_LIMPIEZA_DESTELLO` (local label): the
loop inside `INICIALIZAR_ITEMS_NIVEL` that clears the 4 entries of
table `$5773` of active sparkle effects (the same one
`ACTUALIZAR_DESTELLO_ITEMS` queries).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (one fewer since it's now local,
same pattern already seen with `.CONTINUAR_RESPAWN`/`.LOOP_LIMPIEZA`).

### TI_2C10 -> CONTINUAR_RESET_EXCAVATOFONO, analysis of the $0E value

Renamed `TI_2C10` to `CONTINUAR_RESET_EXCAVATOFONO`: a reunion point
inside `INICIALIZAR_ITEMS_NIVEL` where, if `MODO_ESPECIAL` is 3
(EXCAVATOFONO/digger phone), `$0E` gets written to 4 variables
(`DIRECCION_DE_MOVIMIENTO`/`DIRECCION_FORZADA`/
`TEMPORIZADOR_DIRECCION_FORZADA`/`TEMPORIZADOR_PARPADEO_BOLA`)
instead of `0`. Analyzed at the developer's request:
`DIRECCION_FORZADA=$0E` has real justification -- it's a value
(`0b1110`) that survives an `AND` against all 3 possible alignment
masks (`$0F`/`$03`/`$0C`), guaranteeing the forced direction is
always accepted after a respawn in EXCAVATOFONO mode, regardless of
sub-tile alignment. `TEMPORIZADOR_DIRECCION_FORZADA=$0E` (14 frames)
is plausible as the real duration of that forcing.
The other 2 writes (`DIRECCION_DE_MOVIMIENTO`,
`TEMPORIZADOR_PARPADEO_BOLA`) have no clear justification of their
own -- probably register A (already loaded with $0E) being reused
to save code, with no specific meaning for those two variables.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total).

### LEVEL_TABLE -> TABLA_NIVELES

Renamed `LEVEL_TABLE` to `TABLA_NIVELES`: the 16 20-byte records for
all the game's levels (index 0 = dead record, index 15 = hidden
level 15).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total).
`recursos/mapa_memoria.html`, `recursos/editor_niveles.html` and
`recursos/niveles.html` updated.

### `BODY_L*` -> `CUERPO_L*`, `HEADER_*` -> `CABECERA_*` (TABLA_NIVELES labels)

At the developer's request, substituted "BODY" with "CUERPO" and
"HEADER" with "CABECERA" in every label making up `TABLA_NIVELES`'s
content: `BODY_L01/L2/L3/L4/L5/L6/L7/L8/L9/L10/L11/L12/L15` ->
`CUERPO_L*` (in `madmix_scr_body.asm`), `BODY_L13_CFA4`/
`BODY_L14_D244` -> `CUERPO_L13_CFA4`/`CUERPO_L14_D244` (defined in
`madmix1_body.asm`, referenced from `madmix_scr_body.asm`), and
`HEADER_4AFC`/`HEADER_4B5C`/`HEADER_50BC` -> `CABECERA_4AFC`/
`CABECERA_4B5C`/`CABECERA_50BC`. `MADMIX0_HEADER_START` (in
`main.asm`) was left untouched, being a distinct label unrelated to
the level record. Along the way, 2 historical mentions in comments
(old names `BODY_L13_HEAD_CFA4`/`BODY_L13_MAZE_D000`/
`BODY_L14_MAZE_D244`) were updated for terminology consistency.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total, 1:1 renames).
`recursos/mapa_memoria.html` updated.

### Format: hex -> decimal in "count" fields (REGISTRO_NIVEL_FILAS)

Following a question from the developer about whether
`REGISTRO_NIVEL`/`TABLA_NIVELES`'s fields should be in hex, a
criterion was agreed on: decimal for fields that are pure counts/
durations (rows, item counters, blink duration, ball target), hex
for the ones that are addresses/indices in bit tables (packed
positions, HUD icon). Applied the first case:
`REGISTRO_NIVEL_FILAS` ("factory" value in the RAM declaration, with
no real meaning of its own since `CARGAR_NIVEL` always overwrites
it) `DB $12` -> `DB 18`. Pure format change, same byte.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### Format: hex -> decimal in the rest of REGISTRO_NIVEL's "count" fields

Applied the agreed criterion (decimal for counts/durations, hex for
addresses/indices) to the rest of `REGISTRO_NIVEL`'s RAM declaration
fields: `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` (`$01`->`1`),
`REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (`$02`->`2`),
`REGISTRO_NIVEL_CONTADOR_MARICOCOS`/`REPUGNANTOSOS` (`$01`->`1`
each), `REGISTRO_NIVEL_DURACION_PARPADEO` (`$C8`->`200`),
`REGISTRO_NIVEL_OBJETIVO_BOLAS` (`$0000`->`0`). Left in hex, after
reviewing each one: `REGISTRO_NIVEL_FILA_COLUMNA`/
`POSICION_COMECOCOS` (packed coordinates used in address
arithmetic), `REGISTRO_NIVEL_ICONO_HUD` (index into
`TABLA_POSICIONES_HUD`), and `REGISTRO_NIVEL_LOSETA_COMODIN` -- this
last one checked more carefully: the real code does `OR $80` on it
(it doesn't come pre-marked in the data), but its value
`$C0`=192 doesn't match the known catalog of ~91 decimal tiles, so
it isn't clear converting it to decimal would add real clarity -- it
stays in hex.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### Format: hex -> decimal in game-state variables ($2C07-$2C2D)

Reviewed the variable declarations between `NIVEL_ACTUAL` ($2C07) and
`MODO_ESPECIAL` ($2C2D), applying the same criterion (decimal for
counts/flags/enums/small indices with their own numeric meaning; hex
for direction bitmasks, packed coordinates, VDP colors, seeds, or
unconfirmed values). Converted to decimal: `NIVEL_ACTUAL`,
`CONTADOR_BOLAS_COMIDAS`, `TEMPORIZADOR_PARPADEO_BOLA`,
`MODO_ESPECIAL_FLAG`, `MODO_ESPECIAL_CUENTA_ATRAS`,
`MODO_ESPECIAL_ACTIVO`, `CACHE_TIPO_LOSETA`, `DIR_TABLE_INDEX`,
`FLAG_NIVEL_RECIEN_CARGADO`, `TEMPORIZADOR_DIRECCION_FORZADA`,
`FLAG_DIRECCION_NUEVA`, `COPIA_FLAG_DIRECCION_NUEVA`,
`TRAPDOOR_PHASE`, `VIDAS_RESTANTES` (`$03`->`3`), `PUNTUACION`,
`FLAG_VIDA_EXTRA`, `CONTADOR_VUELTAS_NIVELES`, `MODO_ESPECIAL` (the
rest were `$00`->`0`, same value, pure format change). Left in hex
after reviewing each one: `POSICION_PARPADEO_BOLA`/
`CACHE_COLUMNA_LOSETA`/`REFERENCE_POINT` (addresses/coordinates),
`SELECTOR_SPRITE_COMECOCOS` (tied to the hex sentinel `$FE`),
`DIRECCION_DE_MOVIMIENTO`/`DIRECCION_SIN_PROCESAR`/
`DIRECCION_FORZADA` (direction bitmask), `POSICION_ACTUAL_CAMARA`
(packed coordinate), `COLOR_GUARDADO`/`COLOR_ACTUAL` (packed VDP
color nibbles), `RNG_SEED` (arbitrary seed), `SCROLL_LR_PARAM`
(meaning unconfirmed, observed values look like a bitmask).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### Format: hex -> decimal in TABLA_CLASE_ALINEAMIENTO

Converted `TABLA_CLASE_ALINEAMIENTO`'s 16 bytes to decimal
(`$00-$04` -> `0-4`): they're the 5 already-resolved alignment
classes, not a bitmask or an address. Small readability gain (they're
single-digit values) but consistent with the "index/class ->
decimal" criterion. `TABLA_PISTA_TANQUE_AVION` was left untouched
(it's reserved `DS 6,$00` padding, with no "factory" data of its own
meaning).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).

### VRAM comments added + hex fixed in the 7 TAIL_DECODE calls of PANTALLA_PRESENTACION_NIVEL/IML_9078

At the developer's request, an explicit comment was added on every
`LD HL,$XXXX` that precedes a `CALL TAIL_DECODE` in
`madmix1_body.asm`, clarifying that this value is a position inside
the VRAM pattern table (SCREEN2, $0000-$17FF) -- NOT a Z80 RAM
address, and therefore should NEVER be converted into label
arithmetic (unlike the `DE` in the same call, which ARE real Z80 RAM
addresses to the text records).

Along the way, found and fixed the `DE`/addresses that WERE
hex-not-substituted (the same usual systemic pattern):
- `DE,$918B` -> `DE,EXTRA_TEXT`
- `DE,$9173` -> `DE,EXTRALIFE_TEXT`
- `DE,$9192` -> `DE,CLEAR_TEXT_1`
- `DE,$919E` -> `DE,READY_TEXT`
- `DE,$91AA` -> `DE,CLEAR_TEXT_2`
- `DE,$91B6` -> `DE,GAMEOVER_TEXT`
- `($9193),A`/`($919F),A`/`($91AB),A` -> `(CLEAR_TEXT_1+1),A`/
  `(READY_TEXT+1),A`/`(CLEAR_TEXT_2+1),A` (label arithmetic, offset
  +1 = attribute/color byte of each text record)

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- only comments and
hex substituted with already-existing labels, zero content changes.
`.dsk`/`.cas`/HTML inventory regenerated: 743 labels (no change in
total).

### TAIL_DECODE -> DIBUJAR_TEXTO_VRAM

Renamed `TAIL_DECODE` (generic "print a colored text string to VRAM"
engine: DE=record [length][attribute/color][C character bytes],
HL=VRAM position in the pattern table; every byte >=$20 draws a real
character via TAIL_VDP_PATTERN_WRITE, every byte <$20 is interpreted
as a count of blank columns to skip) to `DIBUJAR_TEXTO_VRAM`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated (2 mentions).

### EXTRA_TEXT -> TEXTO_EXTRA ; EXTRALIFE_TEXT -> TEXTO_VIDA_EXTRA

Renamed two more HUD texts, following the pattern already used with
TEXTO_FASE:
- `EXTRA_TEXT` ("EXTRA") -> `TEXTO_EXTRA`
- `EXTRALIFE_TEXT` ("NEXT... EXTRA") -> `TEXTO_VIDA_EXTRA`

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### PENDING_HUD_FLAG -> FLAG_VIDA_EXTRA

Renamed `PENDING_HUD_FLAG` to `FLAG_VIDA_EXTRA`, after confirming its
exact role: an "extra life pending to be granted" flag, with the
same "consume once" pattern as `FLAG_NIVEL_RECIEN_CARGADO`. It's set
in `IML_90D8` (on completing a level, copying `LEVEL_REC_HUD_FLAG` --
offset 7 of the level record -- before `CARGAR_NIVEL` overwrites it
with the next level's data) and consumed in
`PANTALLA_PRESENTACION_NIVEL`: it's added to `VIDAS_RESTANTES` (with
a cap, doesn't apply if it would reach 5 or more) and, if applied,
draws `TEXTO_EXTRA` ("EXTRA") on screen.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### INIT_8FB7 -> SIN_VIDA_EXTRA

Renamed `INIT_8FB7` to `SIN_VIDA_EXTRA`. It isn't a real function --
it's the reunion point inside `PANTALLA_PRESENTACION_NIVEL` that the
2 conditional jumps of the `FLAG_VIDA_EXTRA` block fall to when the
extra life is NOT granted (flag at 0, or the computation would go
over 5 lives). From there a second, different check starts: if
`LEVEL_REC_HUD_FLAG` (of the just-loaded level) is 1 and there are
fewer than 4 lives, it draws `TEXTO_VIDA_EXTRA` ("NEXT... EXTRA") as
a notice that the next level will grant an extra life.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files.

### Comment added: 5-life cap in the extra-life check

Added an explicit comment on the `CP $05` in
`PANTALLA_PRESENTACION_NIVEL` (inside the `FLAG_VIDA_EXTRA` block):
"maximum number of lives is 5 -- no more extra lives are granted
above that". Clarifies the purpose of the check already explained in
conversation: if `VIDAS_RESTANTES + FLAG_VIDA_EXTRA` would reach 5,
the extra life is silently discarded.

**Verified**: recompiled, diffs at the exact usual baseline (7/2) --
comment-only, zero content changes.

### LEVEL_REC_HUD_FLAG -> FLAG_VIDA_EXTRA_NIVEL

Renamed offset-7 field of the level record (20 bytes, `LEVEL_TABLE`/
`LEVEL_REC_WORK`) from `LEVEL_REC_HUD_FLAG` to
`FLAG_VIDA_EXTRA_NIVEL`, distinguishing it from `FLAG_VIDA_EXTRA`
(the RAM relay variable that copies this value when the level
completes). Marks, per level, whether completing it grants an extra
life; it's read twice during the level transition: once for the
just-completed level (relay to FLAG_VIDA_EXTRA) and once for the
just-loaded level (the "NEXT... EXTRA" notice).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files.

### INIT_8FCE -> PAUSA_TEXTO_FASE ; INIT_LOOP_8FD1 -> PAUSA_TEXTO_FASE_LOOP

Renamed two more labels inside the level transition sequence:
- `INIT_8FCE` -> `PAUSA_TEXTO_FASE`: reunion point (not a real
  function) where the conditional jumps of the extra-life notice
  block ("NEXT... EXTRA") fall to; re-enables interrupts and starts
  a fixed 80-frame wait while showing the stage/extra-life HUD.
- `INIT_LOOP_8FD1` -> `PAUSA_TEXTO_FASE_LOOP`: the body of that
  80-frame HALT/DJNZ loop.

Also investigated, following a question from the developer, that the
real "READY? stays frozen until a key is pressed" happens LATER in
the sequence (after this fixed pause), in the `IML_POLL_90F2` loop
(indefinite loop, polls LEER_TECLADO until it detects any key/
direction) preceded by another fixed 50-frame wait in
`IML_WAIT_90EC` -- both with proposed names
(`ESPERA_INICIO_NIVEL`/`ESPERAR_TECLA_INICIO`) but NOT YET renamed,
pending a future round if the developer confirms them.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files.

### INIT_MAIN_LOOP -> PREPARAR_INICIO_NIVEL

Renamed `INIT_MAIN_LOOP` to `PREPARAR_INICIO_NIVEL`, after this
conversation's detailed analysis of its body: it's NOT the game's
main loop (that's `IML_9078`/`IML_90B7`) -- it's a single one-shot
sequence "level just loaded -> reposition HUD by camera -> draw
READY? -> start music -> enter the key-wait" run only on transitions
(boot, level change, life lost), never every frame.

Along the way, fixed the header comment (lines ~2375-2391) that
dated from an earlier hypothesis and explicitly said "turns out to
be the GAME'S MAIN LOOP -- INICIO never does a RET, it enters this
loop and never leaves again" -- contradicted by the already-
documented finding that the real loop is IML_9078/IML_90B7 and
PREPARAR_INICIO_NIVEL is re-entered at specific points, not
continuously.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### TABLE_INIT -> INICIALIZAR_ITEMS_NIVEL (comment expanded)

Renamed `TABLE_INIT` to `INICIALIZAR_ITEMS_NIVEL`, after a discussion
of the "item" (per-level persistent state: position/phase of ghosts,
ladybug, repugnantoso) vs. "actor" (per-frame transient entry in the
MOTOR_ACTORES table, managed by RESET_CONTADOR_ACTORES) distinction
-- the initially proposed name ("INICIALIZAR_TABLA_ACTORES") was
discarded for describing the wrong function, since this routine
doesn't touch the actor table at all.

Its header comment was also expanded to detail exactly what it
initializes: the 3 item tables (ITEM_TABLE_PELMAZOIDE/MARICOCO/
REGPUNANTOSO, repositioned to the level's reference point), the
$5773 flash zone, the forced-direction flags (with the special
SPECIAL_MODE=3 case), and (via its second entry point TI_2C2E_ENTRY)
the HINT_POS_TABLE trapdoor/hint table.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### Comment fixed: TAIL_LEVELCYCLE_HELPER_ALT ($02C0 is SHORTER than $0300, not longer)

`TAIL_LEVELCYCLE_HELPER_ALT`'s comment said `BC=$02C0` was a "longer
pass" than `TAIL_CREDITS_MAIN`'s (`BC=$0300`) -- simple arithmetic
disproves it: `$02C0`=704 decimal, `$0300`=768 decimal, 704 < 768.
That is, the sample-level cycler processes FEWER color cells than
the HUD/credits refresh, not more. Fixed.

**Verified**: recompiled, diffs at the exact usual baseline (7/2) --
comment-only change, zero content changes.

### TAIL_CREDITS_MAIN -> APLICAR_COLOR_PANTALLA

Renamed `TAIL_CREDITS_MAIN` to `APLICAR_COLOR_PANTALLA`. A name tied
to the "candy frame" (e.g. `APLICAR_COLOR_MARCO_CARAMELO`) was
discarded because the table it processes
(`LEVELCYCLE_RESOURCE_TABLE`, 768 bytes) covers the WHOLE COLOR GRID
of the screen (32x24 cells, the entire VRAM color table $2000), not
just the border -- and it's reused both for the level HUD and for
the demo screen, not just for credits despite the original name.

Along the way, another entry in `recursos/mapa_memoria.html`
(segment 0x8F24-0x9136) that still described `PREPARAR_INICIO_NIVEL`
as "the GAME'S MAIN LOOP" was fixed -- outdated since that label's
rename round, where the `.asm` version was already fixed but not
this memory-map entry.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### SPECIAL_MODE -> MODO_ESPECIAL (whole family)

Renamed `SPECIAL_MODE` ($2C2D, enum 0=none/1=power ball/2=hippo/
3=tool/8=tank/9=plane) to `MODO_ESPECIAL`. By substring substitution,
this also carried over -- intentionally, to keep consistency -- to
the rest of the family:
- `SPECIAL_MODE_FLAG` -> `MODO_ESPECIAL_FLAG`
- `SPECIAL_MODE_COUNTDOWN` -> `MODO_ESPECIAL_COUNTDOWN`
- `SPECIAL_MODE_ACTIVE` -> `MODO_ESPECIAL_ACTIVE`
- `ML_SPECIAL_MODE_TICK` -> `ML_MODO_ESPECIAL_TICK`

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### DIR_BEHAVIOR_SELECTOR -> SELECTOR_DIRECCION_SCROLL_FINO

Renamed `DIR_BEHAVIOR_SELECTOR` ($2C11) to
`SELECTOR_DIRECCION_SCROLL_FINO`, after closing out its exact
function in this conversation: it's the value, read from a subtable
indexed by movement direction + exact position (0-15) within the
current tile (via TILE_DISPATCH_TABLE/TILE_DISPATCH_PTRS/
SUBTABLE_A-D), passed as a parameter to GESTIONAR_SCROLL to decide,
every frame, whether to trigger the FINE 4px scroll (SCROLL_UP/
SCROLL_DOWN/SCROLL_LR) and on which axis -- it does NOT directly
decide the new-tile redraw (that's a separate, later check, based on
PACMAN_POS, inside SCROLL_LOSETA_BUFFER_VRAM).

Investigation context (long, with several self-corrections along the
way): also clarified along the way, following the developer's
questions, the real life-loss mechanism -- ITEM_EFFECT ($57D8)
detects a pac-man/enemy collision via a fixed VRAM window (the
camera is always centered on the pac-man), and it was CONFIRMED that
special mode 3 (EXCAVATOFONO/tool) does NOT protect against dying
(it redirects via "JP Z,IE_57FD" to the same handling as mode
0/normal, only with a different timer duration) -- only modes 1
(power ball) and 2 (hippo) prevent death by contact.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### SELECTOR_DIRECCION_SCROLL_FINO -> SELECTOR_SPRITE_COMECOCOS (important correction)

After a very detailed register-by-register trace (with the help of a
dedicated exploration agent), the earlier hypothesis about this
variable ($2C11) was corrected. It's NOT primarily a fine-scroll
parameter -- that was a misreading in an earlier round (the real
parameter GESTIONAR_SCROLL receives comes from a different H
register, the raw direction bitmask, not this variable).

The confirmed real use: its 7 low bits travel (via ML_SCROLL_PREP,
register B, preserved on the stack during calls to
GESTIONAR_SCROLL/item handlers) all the way to the MOTOR_ACTORES call
that draws the pac-man, where they're used as an INDEX into
PTR_TABLA_SPRITES (register B, madmix1_body.asm:171-181). In other
words: it's the pac-man's ANIMATION FRAME SELECTOR (which mouth
phase + orientation to draw) -- bit7 is horizontal flipping (reuses
the right-side sprite for the left, the same mechanism as the
ghosts). The real values of the direction subtables ($00,$01,$02 for
one direction, $03,$04,$05 for another, etc.) are literally sprite
indices for the pac-man's 3 mouth phases, cycled by DIR_TABLE_INDEX
according to the exact position within the tile -- this is what
produces the visible "mouth opening and closing" effect while
walking.

This also explains, closing out a several-rounds-long investigation
thread: why PANTALLA_PRESENTACION_NIVEL preloads this variable to 14
(index of SPR14_PM_OBRA_ABAJO, "digging" sprite) or 0 (SPR00, normal
pac-man) depending on whether MODO_ESPECIAL was 3 when a life was
lost -- it's pure visual continuity: making the pac-man appear drawn
with the correct sprite (digger vs normal) from the very first frame
after respawn, without briefly flickering the wrong sprite.

Renamed accordingly to `SELECTOR_SPRITE_COMECOCOS`. Also expanded
`ML_DIR_SUBTABLE_LOOP`'s header comment (madmix_scr_body.asm,
previously said "strong candidate... fine detail unconfirmed") with
the now-closed full finding.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### INIT_8FEA -> SPRITE_COMECOCOS_INICIAL

Renamed `INIT_8FEA` to `SPRITE_COMECOCOS_INICIAL` -- it's the reunion
point of the if/else that decides whether `SELECTOR_SPRITE_COMECOCOS`
starts with the digger sprite's index (14, if the life was lost in
EXCAVATOFONO mode) or the normal one (0), and that value gets saved
right there. Comment updated to reflect the now-closed finding (real
sprite index, not a generic "special mode flag").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 743 labels (no change in total). No mentions
in the active HTML files.

### SPRITE_COMECOCOS_INICIAL -> .CONTINUAR_RESPAWN (local label)

Renamed `SPRITE_COMECOCOS_INICIAL` to `.CONTINUAR_RESPAWN`, this time
as a LOCAL label (sjasmplus dot syntax, scoped inside
`PREPARAR_INICIO_NIVEL`) instead of global -- its only real use was
inside that same function. Along the way, the comments the developer
had manually added on these lines were kept/expanded (clarifying
"special pac-man (EXCAVATOFONO) for special mode 3", "normal pac-man
(SPR00) for all other modes").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (one fewer than the previous round
-- the local label is counted differently by `gen_inventory.py`, not
a real content loss). No mentions in the active HTML files.

### MOVE_DIRECTION -> DIRECCION_DE_MOVIMIENTO ; FORCED_DIRECTION -> DIRECCION_FORZADA

Renamed two game-state variables:
- `MOVE_DIRECTION` ($2C10) -> `DIRECCION_DE_MOVIMIENTO`: the pac-
  man's final, validated direction for the current frame (result of
  MAIN_LOOP's alignment check; also serves as a fallback for the
  next frame if the new candidate direction isn't valid).
- `FORCED_DIRECTION` ($2C12 approx.) -> `DIRECCION_FORZADA`: a
  "sticky direction" override triggered by the arrow handlers
  (forces a specific alignment mask instead of the real one).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total).
`recursos/flujo_programa.html` and `recursos/mapa_memoria.html`
updated.

### FORCED_DIR_TIMER -> TEMPORIZADOR_DIRECCION_FORZADA

Renamed `FORCED_DIR_TIMER` to `TEMPORIZADOR_DIRECCION_FORZADA`
(also, along the way, `FORCED_DIR_TIMER_TICK` ->
`TEMPORIZADOR_DIRECCION_FORZADA_TICK`, the common cleanup tail of
HNDLR_SUELO_SIN_BOLA).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total).
`recursos/mapa_memoria.html` updated.

### BALL_BLINK_TIMER -> TEMPORIZADOR_PARPADEO_BOLA

Renamed `BALL_BLINK_TIMER` to `TEMPORIZADOR_PARPADEO_BOLA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 742 labels (no change in total). No mentions
in the active HTML files.

### Format: hex -> decimal in the rest of the code (usage of the already-converted variables)

At the developer's request, after converting the RAM declarations of
the previous section ($2C07-$2C2D) and `TABLA_CLASE_ALINEAMIENTO` to
decimal, the REST of `madmix_scr_body.asm`/`madmix1_body.asm` was
reviewed for assignments (`LD A,$XX`/`LD (HL),$XX`) or comparisons
(`CP $XX`) on those same variables that were still in hex, so the
style is consistent between the declaration and each use. Changes
applied:

- `TABLA_NIVELES`'s 16 records (offset 11, "blink duration"):
  `$FA`->`250` (11 records), `$C8`->`200` (2), `$32`->`50`,
  `$FF`->`255`, `$50`->`80`, `$96`->`150`. Also a comment citing the
  value in hex ("compares CP $10 (16)") fixed to decimal.
- `NIVEL_ACTUAL`: `CP $10`->`CP 16` and `LD (HL),$01`->`LD (HL),1` in
  `VERIFICAR_FIN_NIVEL`/`SIGUIENTE_NIVEL` (madmix1_body.asm).
- `CONTADOR_BOLAS_COMIDAS`: `LD HL,$0000`->`LD HL,0` in
  `CARGAR_NIVEL`'s reset.
- `MODO_ESPECIAL`/`MODO_ESPECIAL_FLAG`: every mode activation
  (tank=8, plane=9, power ball=1, hippo=2, excavatofono=3) and their
  comparisons (`HNDLR_PISTA_COCOTANQUE`, `HNDLR_PISTA_COCONAVE`,
  `HNDLR_ITEM_SUELO`, `HNDLR_HIPODOSO`, `HNDLR_EXCAVATOFONO`,
  `HNDLR_SUELO_SIN_BOLA`, `HNDLR_SUELO_NORMAL`, `HNDLR_BOLITA_NORMAL`,
  `ML_MODO_ESPECIAL_TICK`, `ML_HIPPO_MODE_TICK`) converted from hex
  to decimal. In `CONTINUAR_RESET_EXCAVATOFONO` only the `CP $03`->
  `CP 3` on `MODO_ESPECIAL` was converted; the `LD A,$0E` that sets
  `DIRECCION_FORZADA`/`TEMPORIZADOR_DIRECCION_FORZADA`/etc. was
  deliberately left in hex (same criterion below).
- `MODO_ESPECIAL_CUENTA_ATRAS`: `CP $3C`->`CP 60` (both occurrences,
  the countdown threshold in `ML_MODO_ESPECIAL_TICK`).
- The death-counter setup after `MODO_ESPECIAL_ACTIVO` (`IE_581B`):
  `CP $03`->`CP 3`, `LD A,$28`->`LD A,40`, `LD A,$2D`->`LD A,45`
  (40/45-frame durations already confirmed in an earlier round).
- `CACHE_TIPO_LOSETA`: `LD A,$0F`->`LD A,15` (along with the comment)
  in `HNDLR_BOLITA_NORMAL`, when marking the tile as "eaten".
- `FLAG_NIVEL_RECIEN_CARGADO`/`FLAG_DIRECCION_NUEVA`/
  `COPIA_FLAG_DIRECCION_NUEVA`/`FLAG_VIDA_EXTRA`: every assignment
  of 0/1 to these boolean flags converted (`ACTUALIZAR_VRAM_FRAME`,
  `PREPARAR_INICIO_NIVEL`, `MOTOR_MOVIMIENTO_COLISION`,
  `PANTALLA_PRESENTACION_NIVEL`).
- `TRAPDOOR_PHASE`/`TEMPORIZADOR_DIRECCION_FORZADA`: converted
  `HNDLR_TRAMPILLA_CERRADA`'s comparison (`CP $02`->`CP 2`, on the
  value already read from `TRAPDOOR_PHASE`) and its
  `TEMPORIZADOR_DIRECCION_FORZADA` assignment (`LD A,$03`->
  `LD A,3`). Also took the opportunity to convert to decimal the
  generic "correct movement phase" checks (`AND $03`/`CP $02`->
  `CP 2`) that appear repeated across the 3 trapdoor handlers, for
  consistency with the rest. The `LD A,$02`/`LD A,$01` that set both
  `DIRECCION_FORZADA` (hex, direction bitmask) AND `TRAPDOOR_PHASE`
  (decimal) at once from the same register were left in hex -- same
  criterion as `CONTINUAR_RESET_EXCAVATOFONO`: when a single value
  feeds a "hex" variable and a "decimal" one at once, the primary/
  shared variable's format wins.
- `VIDAS_RESTANTES`: `CP $05`->`CP 5` (the 5-life cap) and `CP $04`->
  `CP 4` (upcoming-extra-life notice) in
  `PANTALLA_PRESENTACION_NIVEL`; also `LD (HL),$00`->`LD (HL),0` for
  `FLAG_VIDA_EXTRA` in the same block. Deliberately left in hex:
  `SUB $01` in `VIDAS_RESTANTES`'s decrement
  (`REINICIAR_PARTIDA`/death) -- it's the exact operand byte that
  TI_BREAK's infinite-lives trick patches to `SUB $00`, already
  documented as such in its own comment, so it stays in hex to not
  break the correspondence with that note.
- `PUNTUACION`: `LD DE,$2710`->`LD DE,10000`, the point threshold
  that triggers the "BEAST" text in `DIBUJAR_MARCADOR_PUNTOS`.

Reviewed with no changes needed (already in decimal or had no
associated hex literals): `DIR_TABLE_INDEX` (only `AND $03`, a
modulo mask, left in hex), `MODO_ESPECIAL_ACTIVO` (the only site
with a literal was already converted in an earlier round; the rest
are `XOR A`/`AND A`/`DEC (HL)`, with no operand),
`CONTADOR_VUELTAS_NIVELES` (already in decimal in
`REINICIAR_PARTIDA`, the rest are reads with no comparison).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply --
pure format change, no new symbol). No changes needed in
`recursos/mapa_memoria.html`/`recursos/flujo_programa.html` (they
don't cite these hex values in their text).

### Study (not applied): proposed Spanish names for the `JTS2_` family in `MOTOR_ACTORES`

At the developer's request, analysis of the ~28 internal labels of
`MOTOR_ACTORES` (0x8440-0x87FF, `madmix1_body.asm:95-775`) that still
carry the `JTS2_` disassembly-placeholder prefix (generic, just like
`IML_`/`TI_`/`TAIL_` once were). **This section is analysis only --
nothing has been renamed in the code yet**, pending the developer's
confirmation of which proposals to apply.

**Context (already resolved in earlier rounds, summary)**:
`MOTOR_ACTORES` is the routine that registers an actor (pac-man,
ghost, item...) in the 12-byte active-actor table at `$92E3`
(counter at `$8437`), computes its draw position and paints it
immediately into a buffer with sub-pixel offset (bitwise AND/OR mix
via the fast SP-based memory read/write trick). The full array is
walked a second time, already inside the ISR
(`ISR_HOUSEKEEPING`), via `JTS2_RESUME`.

**New piece of context, found while cross-referencing this routine
with the already-existing "Zone 0xDC00" finding** (comment in
`RLE_TABLE_D6B6`, `madmix1_body.asm:4440-4446`): the address computed
by `ADDR_FROM_DC00` (used by `MOTOR_ACTORES` for IX+2/3) falls inside
the SAME table that holds the decorative frame ("candy frame"), in
its `$DC00`-onward sub-range -- and that same comment already
documented that this sub-zone is read as AND/OR sprite-vs-background
compositing MASK PAIRS. This fits exactly with the AND/OR pattern of
`JTS2_85A2`/`JTS2_PROCESS_ACTORS` further below: the table at
`$DC00+` isn't a generic "output" buffer but, more likely, a table of
CLIPPING/COMPOSITING MASKS by screen position, and what
`JTS2_COPY_CURSOR` does is CAPTURE (prefetch) the masks that apply to
each actor for this frame into the low-RAM cursor (`$0500+`), so the
rest of the pipeline (`JTS2_85A2`/render and, later,
`JTS2_PROCESS_ACTORS`) can consume them without recomputing the
address every time.

**Side finding**: `JTS2_PROCESS_ACTORS` (the "second pass", with
self-modifying code) **has no confirmed `CALL`/`JP` anywhere in the
transcribed code so far** -- it doesn't match
`ISR_HOUSEKEEPING`'s unidentified `CALL $8CFF` (different addresses).
It might be called from a still-untranscribed gap, from a computed
jump, or it might be dead code / leftover from an earlier version of
the engine. Its proposed name is therefore marked medium confidence,
and it's recommended NOT to rename it until its real caller is
found.

#### Named subroutines and data (dropping the `JTS2_` prefix)

| Current label | Address | Proposal | Confidence | Reason |
| --- | --- | --- | --- | --- |
| `JTS2_85A2` | 0x85A2 | `MEZCLAR_Y_AVANZAR_FILA_ACTOR` | High | Tail SHARED by `JTS2_RENDER_A`/`JTS2_RENDER_B`: mixes 3 bytes with AND/OR against `(HL)`, advances `HL` 32 bytes (one row) and repeats via `EX AF,AF'`/`DEC A` until the row counter runs out. |
| `JTS2_RENDER_A` | 0x85C1 | `DIBUJAR_FILA_DESPLAZADA_DERECHA` | High | Variant with `RRA`/`RR L,H` (shifts the pattern right) before merging with `JTS2_85A2`. |
| `JTS2_RENDER_B` | 0x8624 | `DIBUJAR_FILA_DESPLAZADA_IZQUIERDA` | High | Twin of the previous one with `RLA`/`RL H,L` (shifts left). |
| `JTS2_COPY_CURSOR` | 0x8687 | `CAPTURAR_MASCARAS_ACTOR` | Medium-high | Extracts from area `$DC00+` (AND/OR masks by position, see above) into the low-RAM cursor, for the just-registered actor. |
| `JTS2_SAVED_IX` | 0x86B9 | `IX_ACTOR_GUARDADO` | High | Data word: a copy of `IX` (pointer to the actor's record) that `JTS2_RESUME` picks back up. |
| `JTS2_RESUME` | 0x86BB | `CONTINUAR_CAPTURA_MASCARAS_ACTORES` | High | Repeats the same capture as `CAPTURAR_MASCARAS_ACTOR`, walking the array backward (step -12), called from `ISR_HOUSEKEEPING` every vblank. |
| `JTS2_XOR_TRANSFORM` | 0x86FA | `INVERTIR_BITS_PATRON_ACTOR` | Medium-high | `RLC C`/`RRA` x8 per byte = the classic trick for reversing the order of a byte's 8 bits. Only triggered if bit7 of value `D` (camera-mask comparison) differs -- the same convention already confirmed in `SELECTOR_SPRITE_COMECOCOS` (bit7 = horizontal flip), so it's a strong candidate for being "the bitwise half" of a sprite's horizontal flip. Exact purpose (real flip vs. another transform) unconfirmed by a live test. |
| `JTS2_SWAP_SORT` | 0x873A | `INVERTIR_ORDEN_BYTES_PATRON_ACTOR` | Medium-high | Swaps bytes between two pointers converging toward the center -- the natural complement of `INVERTIR_BITS_PATRON_ACTOR`: also reversing the BYTE ORDER of the row (not just each byte's bits) completes a horizontal flip of a graphic wider than 8px. Triggered by bit6 of the same value `D`. Same confidence level as the previous one (mechanism clear, final purpose to confirm). |
| `JTS2_PROCESS_ACTORS` | 0x8779 | `COMPONER_ACTORES_EN_BUFFER` | Medium (see the unconfirmed-caller warning above) | Second pass over the full array, with no sub-pixel offset (simple OR mix), with self-modifying code; ends by setting `$8437` to 0 -- looks like the "final composite" after `MOTOR_ACTORES`'s incremental sub-pixel blit. |
| `JTS2_TABLE_87FB` | 0x87FB | `TABLA_MASCARA_RECORTE_BORDE` | Low-medium | Only 5 real bytes, indexed by coarse horizontal position (`AND $F8`, divided by 8 without multiplying). Hypothesis: a clipping mask for actors near the screen edge; unconfirmed what it's actually compared against. |
| `JTS2_SELFMOD_1` | 0x8707 (operand) | `OPERANDO_MASCARA_A_IDA` | Medium | See next row -- full symmetric pattern. |
| `JTS2_SELFMOD_2` | -- | `OPERANDO_MASCARA_B_IDA` | Medium | " |
| `JTS2_SELFMOD_3` | -- | `OPERANDO_MASCARA_C_IDA` | Medium | " |
| `JTS2_SELFMOD_4` | -- | `OPERANDO_MASCARA_C_VUELTA` | Medium | " |
| `JTS2_SELFMOD_5` | -- | `OPERANDO_MASCARA_B_VUELTA` | Medium | " |
| `JTS2_SELFMOD_6` | -- | `OPERANDO_MASCARA_A_VUELTA` | Medium | `COMPONER_ACTORES_EN_BUFFER`'s 6 self-modified operands are filled in matching pairs from `IX+7/8/9` (1=6, 2=5, 3=4) -- a 6-step "there and back" pattern, consistent with `JTS2_87E6`'s row adjustment (advances and sometimes wraps, like walking two halves of a block). |
| `JTS2_8774` | 0x8774 | `SALIR_MOTOR_ACTORES` | High | SHARED epilogue (`POP BC/DE/HL/AF`+`RET`) of the whole family: used as an early exit from `MOTOR_ACTORES`'s guard, and as the natural end of `INVERTIR_BITS_PATRON_ACTOR`/`INVERTIR_ORDEN_BYTES_PATRON_ACTOR`/`MEZCLAR_Y_AVANZAR_FILA_ACTOR`. |

#### Internal merge/branch points -- proposed as LOCAL labels (pattern already used in the project, e.g. `.LOOP_LIMPIEZA`)

These are never called from outside their "parent" routine, so they
fit the local-label pattern (`.name`, scoped to the preceding global
label) already used elsewhere in the project.

**Inside `MOTOR_ACTORES`** (entry guard + actor setup, before
entering the draw loop):

| Current label | Local proposal | Reason |
| --- | --- | --- |
| `JTS2_8455` | `.DESCARTAR_ACTOR` | Shared exit of the 3 range guards (counter>=10, B>=$40, E outside $04-$73). |
| `JTS2_8457` | `.COMPROBAR_LIMITE_VERTICAL` | Completes the `E` guard (upper limit `$74`) before falling into `.DESCARTAR_ACTOR`. |
| `JTS2_846D` | `.CONTINUAR_TRAS_SELECCION_MITAD` | Merge after choosing `$90`/`$B0` (screen/camera half) at `$843E`. |
| `JTS2_84A9` | `.CONTINUAR_TRAS_CLIP_VERTICAL` | Merge after comparing `D` against `$843E`. |
| `JTS2_84EE` | `.CALCULAR_RECORTE_CAMARA` | Alternate branch of the camera-relative vertical clipping computation. |
| `JTS2_8502` | `.CONTINUAR_TRAS_RECORTE` | The actor survives clipping -- continues computing IX+0/1. |
| `JTS2_84FD` | `.DESCARTAR_ACTOR_FUERA_DE_CAMARA` | Specific bail-out from the clipping computation (jumps to `SALIR_MOTOR_ACTORES`). |
| `JTS2_8510` | `.CONTINUAR_TRAS_LIMITAR_FILAS` | Merge after forcing the row counter (`IX+4`) to a minimum of 1. |
| `JTS2_851F` | `.CONTINUAR_CURSOR_ACTOR` | Branch: not the frame's first actor -> reuse the already-in-progress cursor (`$8438`). |
| `JTS2_8523` | `.GUARDAR_CURSOR_ACTOR` | Merge: saves the cursor pointer at `IX+5/6` and calls `CAPTURAR_MASCARAS_ACTOR`. |
| `JTS2_8545` | `.CONTINUAR_TRAS_INVERSION_BITS` | Merge after the optional call to `INVERTIR_BITS_PATRON_ACTOR`. |
| `JTS2_854F` | `.CONTINUAR_TRAS_INVERSION_BYTES` | Merge after the optional call to `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`. |
| `JTS2_856D` | `.CONTINUAR_TRAS_ELEGIR_DIRECCION` | Merge after choosing `IY`=right/left render. |
| `JTS2_8584` | `.BUCLE_DIBUJAR_ACTOR` | Main loop: fast SP-based read of a source row pair + `JP (IY)` to the render variant. |

**Inside `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`** (same
internal structure in both, identical names by symmetry):

| Current label (right) | Current label (left) | Local proposal | Reason |
| --- | --- | --- | --- |
| `JTS2_85C5` | `JTS2_8628` | `.DESPLAZAR_SUBPIXEL_FILA1` | First bit-by-bit sub-pixel shift loop (`DJNZ`). |
| `JTS2_85D8` | `JTS2_863B` | `.ESCRIBIR_FILA1` | AND/OR mix of the first of the two 3-byte rows + SP-based reload of the next source row. |
| `JTS2_860E` | `JTS2_8671` | `.DESPLAZAR_SUBPIXEL_FILA2` | Second shift loop, for the next row. |
| `JTS2_8621` | `JTS2_8684` | `.CONTINUAR_FILA2` | Final merge -> `JP MEZCLAR_Y_AVANZAR_FILA_ACTOR` (reuses the shared tail for the second row). |

**Inside `CAPTURAR_MASCARAS_ACTOR`**: `JTS2_869A` -> `.BUCLE_CAPTURA`
(6-byte-per-iteration copy loop, `DEC A`/`JP NZ`).

**Inside `CONTINUAR_CAPTURA_MASCARAS_ACTORES`**: `JTS2_86BF` ->
`.SIGUIENTE_ACTOR` (outer loop header: decrements `$8437`, `RET Z` on
reaching 0); `JTS2_86D9` -> `.BUCLE_CAPTURA` (inner loop, same
structure as in `CAPTURAR_MASCARAS_ACTOR` with the extra `EX DE,HL`
for walking the array backward).

**Inside `INVERTIR_BITS_PATRON_ACTOR`**: `JTS2_8707` ->
`.BUCLE_BLOQUES` (outer loop, 48 fixed iterations); `JTS2_870E` ->
`.BUCLE_INVERTIR_BYTE` (inner loop, the bit reversal itself, `DJNZ`
over the height in `$8435`).

**Inside `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`**: `JTS2_874E` ->
`.COMPROBAR_CONVERGENCIA` (loop header: computes the final pointer
and checks whether it already matches the initial one); `JTS2_8760`
-> `.INTERCAMBIAR_BLOQUE` (branch: the pointers still differ, swap a
block); `JTS2_8762` -> `.BUCLE_INTERCAMBIO` (inner byte-by-byte swap
loop).

**Inside `COMPONER_ACTORES_EN_BUFFER`**: `JTS2_8786` ->
`.SIGUIENTE_ACTOR` (outer loop header: installs the 6 self-modified
operands and preps `SP`/`HL`/`B`); `JTS2_87B2` -> `.BUCLE_COMPONER`
(6-step inner loop, `POP DE`/`AND E`/`OR D`/`LD (HL),A` with the
self-modified operands); `JTS2_87E6` -> `.AJUSTAR_SALTO_FILA` (merge:
checks `H AND $06` and adjusts `L`/`H` to jump to the next row block
when needed).

**Pending before applying**: confirm with the developer which
criterion to use for the 6 tables above (apply all at once vs. in
blocks), and decide whether `COMPONER_ACTORES_EN_BUFFER`/
`TABLA_MASCARA_RECORTE_BORDE` get renamed now (with their medium/low
confidence marked in the name itself, as already done before with
other project hypotheses) or left until more evidence turns up (the
first one's real caller, the second one's confirmed real use).

**Verification note**: pure-analysis section, no changes to any
`.asm` -- no recompile or diff applies.

### Study applied: renamed the entire `JTS2_` family in `MOTOR_ACTORES`

The developer confirmed ("OK, PROCEED WITH THE SUBSTITUTION") to
apply the previous study's proposal in full. Renamed the 45
`JTS2_xxxx` labels of `madmix1_body.asm:95-787` (0x8440-0x8787):

- **17 global subroutines/data** (dropping the `JTS2_` prefix):
  `TABLA_MASCARA_RECORTE_BORDE`, `CAPTURAR_MASCARAS_ACTOR`,
  `INVERTIR_BITS_PATRON_ACTOR`, `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`,
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`,
  `MEZCLAR_Y_AVANZAR_FILA_ACTOR`, `IX_ACTOR_GUARDADO`,
  `CONTINUAR_CAPTURA_MASCARAS_ACTORES`, `SALIR_MOTOR_ACTORES`,
  `COMPONER_ACTORES_EN_BUFFER`, and the 6 self-modified operands (see
  below, ended up local instead of global).
- **28 internal merge/branch points**, converted to LOCAL labels
  (`.name`) per the study's table, each scoped to its real parent
  routine: `MOTOR_ACTORES` (14),
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA` (4 each, same local
  names by symmetry), `CAPTURAR_MASCARAS_ACTOR` (1),
  `CONTINUAR_CAPTURA_MASCARAS_ACTORES` (2),
  `INVERTIR_BITS_PATRON_ACTOR` (2), `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`
  (3), `COMPONER_ACTORES_EN_BUFFER` (2, not counting the operands).

**Adjustment during application (2 cases where a pure local scope
didn't work)**:

- The 6 `JTS2_SELFMOD_1..6` were proposed as GLOBAL names in the
  study, but applying them broke `.BUCLE_COMPONER`'s scope (each is a
  real LABEL in the middle of the loop, and sjasmplus always ties
  local labels to the last NON-local label -- being global, each
  `OPERANDO_MASCARA_*` reset the scope). They were converted to local
  too (`.OPERANDO_MASCARA_A_IDA` etc.), now correctly nested under
  `COMPONER_ACTORES_EN_BUFFER`.
- `.BUCLE_DIBUJAR_ACTOR` (inside `MOTOR_ACTORES`) is also referenced
  from inside `MEZCLAR_Y_AVANZAR_FILA_ACTOR` (shared loop that
  re-enters the draw loop via the SP-trick) -- same scope problem.
  Instead of making it global, sjasmplus's
  `PARENT_LABEL.local` syntax was used (`JP NZ,
  MOTOR_ACTORES.BUCLE_DIBUJAR_ACTOR`), which preserves the real local
  scope without sacrificing the name.

**Comments updated**: `MOTOR_ACTORES`'s narrative header comment
(lines 36-94) was expanded with the new cross-reference
(`CAPTURAR_MASCARAS_ACTOR` reads from the SAME AND/OR mask table as
the candy frame, `$DC00+`, not from its own background buffer) and
with the horizontal-flip hypothesis for `INVERTIR_BITS_PATRON_ACTOR`/
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (explicitly marked as an
unconfirmed-live hypothesis). `COMPONER_ACTORES_EN_BUFFER`'s comment
makes it explicit that its real caller is still unidentified.

Also synced `src/README.md` and `src/FLUJO_PROGRAMA.md` (loose
mentions of `JTS2_RENDER_A/B`, `JTS2_RESUME`, `JTS2_PROCESS_ACTORS`,
and along the way 2 already-obsolete names from an earlier round,
`RESET_8437` -> `RESET_CONTADOR_ACTORES`) and
`recursos/mapa_memoria.html` (4 mentions in the segment block for
0x0500 and 0xD6B6). `recursos/flujo_programa.html` needed no manual
edit -- its only mentions lived in the auto-generated `INVENTORY`
block, resolved with `gen_inventory.py`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: **703 labels** (down from 742 to 703, -39 --
consistent with the already-documented mechanism that every new
LOCAL label subtracts 1 from `gen_inventory.py`'s total: exactly 39
new local labels were created, 28 merge/branch points + 6
self-modified operands + the 5 sites that were already local before
don't count -- zero real content loss). `recursos/flujo_programa.html`
regenerated; `recursos/mapa_memoria.html` updated by hand.

### Study (not applied): proposed Spanish names for the `H5278_` labels of `MOVER_ITEM_MOVIL`

At the developer's request, analysis of `MOVER_ITEM_MOVIL` ($5278,
`madmix_scr_body.asm:1935-2132`) and its 14 internal `H5278_xxxx`
labels. **Analysis only -- nothing has been renamed in the code
yet**, pending the developer's confirmation.

**What `MOVER_ITEM_MOVIL` does** (the global name is already good, no
change proposed): moves a "mobile" item (ghost via
`HNDLR_PELMAZOIDE`, or ladybug/repugnantoso via `HNDLR_MARICOCO`/
`HNDLR_REGPUNANTOSO`) one step toward the pac-man. Structured in 4
phases:

1. **Compute the approach direction** (D=$01/$02/$04/$08) comparing
   the item's position against `REFERENCE_POINT` (camera+8,+16, or
   its NEGATED version if `MODO_ESPECIAL_FLAG` is active -- "inverted
   camera"). This whole phase is skipped (D stays 0) if the item is
   "frozen" (`IX+2`!=0) or if `MODO_ESPECIAL_ACTIVO` (countdown) is
   in progress.
2. **Only if aligned to a tile** (`IX+0/1` sub-position=0): recomputes
   the final direction. Tests the 4 free directions with
   `HELPER_5414`; if the desired direction (phase 1) is one of the
   free ones, uses it (always if `MODO_ESPECIAL_FLAG` is active, or
   50% of the time via an `ITEM_RNG` roll otherwise); if it can't or
   a reroll is due, picks among ALL the free ones via
   `TABLA_CLASE_ALINEAMIENTO` and `ITEM_DIR_CHOICE_TABLE` (a bias
   toward "keep the previous direction if possible").
3. **Applies the movement**: saves the final direction in `IX+3`,
   converts it into the 1-4 compact code (via
   `TABLA_CLASE_ALINEAMIENTO`), computes the step (`$0100` normal,
   `$0080` half-step if `IX+2` is active OR if `MODO_ESPECIAL_FLAG` is
   active) and adds/subtracts it to the X or Y sub-position according
   to the code.
4. **Falls through with no jump into `HELPER_53A2`** (its "second
   entry point", with its own global name -- outside this study's
   `H5278_` scope): computes the item's VRAM position relative to the
   camera and whether it's visible. `HELPER_53A2` is also called
   directly with `CALL $53A2` from `ACTUALIZAR_DESTELLO_ITEMS`, which
   skips phases 1-3.

**Side finding 1 (possibly inverted comment, not fixed)**: the
comment next to `BIT 7, A` in phase 2 (before `H5278_5340`, item
active/`IX+2`!=0) says "only chosen at random if the fractional
position has the high bit set, otherwise keeps the current
direction". The real logic of the following `JR NZ, H5278_5340` says
the OPPOSITE: `BIT 7,A` leaves `Z=0` (NZ) when bit7 IS set, and in
that case the jump **avoids** the random choice (jumps straight to
applying `A=(IX+3)`, the direction already in progress); only when
bit7 is 0 does the code fall into `H5278_531E` (random choice). In
other words: bit7 set -> KEEPS direction; bit7 clear -> CHOOSES at
random -- exactly the opposite of what the current comment says. Not
fixed (out of scope for "rename only"), but deserves a separate fix
pass.

**Side finding 2**: the real call to `HELPER_53A2` from
`ACTUALIZAR_DESTELLO_ITEMS` (line ~2885) is still in hex, `CALL
$53A2`, even though the label already exists -- the same systemic
"hex not substituted" pattern found many times in the project. Also
not fixed in this analysis-only pass.

#### Proposal: the 14 labels as LOCALS (`.name`), scope `MOVER_ITEM_MOVIL`

Same as in the `MOTOR_ACTORES` study, none of these 14 are called
from outside the routine, so they fit as local labels.

| Current label | Local proposal | Reason |
| --- | --- | --- |
| `H5278_5293` | `.COMPROBAR_ESTADO_ITEM` | Entry when `MODO_ESPECIAL_FLAG`=0 (normal mode): checks whether the item is frozen (`IX+2`) or a special-mode countdown is in progress, before deciding whether to compute a direction. |
| `H5278_529F` | `.CALCULAR_DIRECCION_ACERCAMIENTO` | Point where the BC (item position) vs. HL (reference point) comparison starts, to get the direction toward the target. |
| `H5278_52B3` | `.COMPROBAR_FILA` | Branch: the column didn't match, tests whether the row matches (vertical vs. horizontal axis). |
| `H5278_52C5` | `.COMPROBAR_ALINEAMIENTO_LOSETA` | Merge point of ALL phase-1 branches (with or without a computed direction); the first instruction here checks whether the item is tile-aligned. |
| `H5278_5303` | `.ELEGIR_ENTRE_LIBRES` | Can't move toward the target (or a random reroll is due): sets up the index to choose among ALL free directions. |
| `H5278_531E` | `.ELEGIR_DIRECCION_ALEATORIA` | Picks a new direction at random among the free ones, via `TABLA_CLASE_ALINEAMIENTO` + `ITEM_DIR_CHOICE_TABLE`. |
| `H5278_532D` | `.CONTINUAR_INDICE_DIRECCION_PREVIA` | Merge after classifying the previous direction (`SUB $01` clamped to 0) into `ITEM_DIR_CHOICE_TABLE`'s index. |
| `H5278_5340` | `.FIJAR_DIRECCION_Y_PASO` | Merge SHARED by almost all the previous branches: saves the final chosen direction at `IX+3` and computes the step size (normal/half). |
| `H5278_5360` | `.CONTINUAR_TRAS_ELEGIR_PASO` | Merge after deciding a normal (`$0100`) or half (`$0080`) step based on `IX+2`. |
| `H5278_5369` | `.CONTINUAR_TRAS_MODO_INVERTIDO` | Merge after checking whether `MODO_ESPECIAL_FLAG` also forces a half step. |
| `H5278_5373` | `.COMPROBAR_CODIGO_IZQUIERDA` | After applying (or not) code 1 (right, X+=step), checks code 2 (left). |
| `H5278_537D` | `.COMPROBAR_CODIGO_ABAJO` | Saves the final X sub-position/position, switches HL to the Y sub-position, checks code 3 (down). |
| `H5278_5392` | `.COMPROBAR_CODIGO_ARRIBA` | After applying (or not) code 3, checks code 4 (up). |
| `H5278_539C` | `.GUARDAR_POSICION_Y` | Saves the final Y sub-position/position; falls through with no jump into `HELPER_53A2`. |

**Verification note**: pure-analysis section, no changes to any
`.asm` -- no recompile or diff applies.

### Study applied: renamed the 14 `H5278_` labels of `MOVER_ITEM_MOVIL`

The developer confirmed ("ok, update") applying the previous study's
proposal. Renamed the 14 `H5278_xxxx` labels of
`madmix_scr_body.asm:1935-2130` to locals (`.name`, scope
`MOVER_ITEM_MOVIL`) exactly per the study's table. Also includes the
cross-reference in `ITEM_DIR_CHOICE_TABLE`'s comment
(`H5278_531E-H5278_533A`, where `H5278_533A` was never a real label,
just a closing address in prose) -> `MOVER_ITEM_MOVIL.ELEGIR_DIRECCION_ALEATORIA`
(sjasmplus syntax for referencing a local label from outside its
routine, in a comment).

Along the way, also applied the study's 2 side findings (small, low
risk, already fully diagnosed):

- `CALL $53A2` (in `ITT_57A8`, inside `ACTUALIZAR_DESTELLO_ITEMS`) ->
  `CALL HELPER_53A2`, the same systemic hex-not-substituted-with-the-
  already-existing-label pattern.
- Fixed the inverted comment next to `.ELEGIR_ENTRE_LIBRES`/
  `.ELEGIR_DIRECCION_ALEATORIA`'s `BIT 7,A`: it said "only chosen at
  random if the high bit is set, otherwise keeps the current
  direction"; the real logic of the following `JR NZ` is the
  opposite -- bit7 set KEEPS the current direction (jumps to
  `.FIJAR_DIRECCION_Y_PASO` with `A=(IX+3)`), bit7 clear is what
  makes it fall into the random choice. Comment change, zero byte
  change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: **689 labels** (down from 703 to 689, -14,
exactly the 14 new local labels -- same already-documented counting
mechanism, zero real loss). Expected side effect in the inventory
breakdown: `funcion`/function goes from 100 to 101 and `sinref`/no-ref
drops by 1 -- `HELPER_53A2` goes from looking "unreferenced" to
having a real, detectable call, thanks to the `CALL $53A2` -> `CALL
HELPER_53A2` fix. No changes needed in `recursos/mapa_memoria.html`
(its only mention of this area already used the global names
`MOVER_ITEM_MOVIL`/`HELPER_53A2`/`HELPER_5414`, without citing any of
the renamed sub-labels) nor in `src/README.md`/`src/FLUJO_PROGRAMA.md`
(same case).

### Bug fixed in `tools/gen_inventory.py`: `DJNZ` didn't count as a reference

The developer reported that `recursos/flujo_programa.html` marked as
"unreferenced" labels that DID have real calls in the code (detected
example: `HNDLR_PISTA_COCONAVE_LOOP`, referenced only by `DJNZ
HNDLR_PISTA_COCONAVE_LOOP` at line 1227 of `madmix_scr_body.asm`,
never by `JP`/`JR`/`CALL`).

Root cause: `gen_inventory.py`'s `JUMP_RE` only looked for
`\b(?:JP|JR)\b LABEL` -- **`DJNZ` wasn't in the list**, despite being
a conditional jump instruction (relative, decrements B) just as
valid as `JR` for marking a label as "internal". Since `DJNZ` is the
standard idiom for ending almost every loop in the project, this
affected a large number of genuinely used labels. Fixed by adding
`DJNZ` to `JUMP_RE`'s alternation.

Took the opportunity to document 2 known limitations in the script
itself (docstring) that were NOT fixed in this pass (a text-based
heuristic, not real control-flow analysis):

- It doesn't detect references via data table (`DW LABEL` used as a
  jump table, e.g. `TABLA_MANEJADORES_LOSETA`) nor via register
  (`LD IY,LABEL` + `JP (IY)`, the pattern used by
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA` in `MOTOR_ACTORES`)
  -- these labels can still show up as "unreferenced" despite having
  real use.
- LOCAL labels (with a dot, `.name`) aren't registered in the
  inventory at all -- `LABEL_RE` doesn't recognize the leading dot,
  so they're left out completely (they don't appear either as
  "unreferenced" or in any other way). This was already known
  indirectly (it explains the drop in "total labels" every round
  that creates new local labels), but wasn't documented as an
  explicit script limitation until now.

**Verified**: Python-tool-only change, no `.asm` touched -- diffs of
`MADMIX.SCR`/`MADMIX1.BIN` not re-checked (doesn't apply, nothing
recompiled). `recursos/flujo_programa.html` regenerated: same total
(689 labels), but `interna`/internal goes from 180 to 212 (+32) and
`sinref`/unreferenced drops from 172 to 140 (-32) -- 32 labels that
had real use only via `DJNZ` are now correctly reclassified.

### Second bug fixed in `gen_inventory.py`: indirect uses (`DW` jump table, `LD IY/IX/HL,LABEL`+register jump) also didn't count

The developer kept seeing functions with a real call marked
"unreferenced" (flagged example: `DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`,
only referenced with `LD IY, DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`
followed by `JP (IY)` further down in `MOTOR_ACTORES` -- exactly the
limitation already noted in the script's docstring after the earlier
`DJNZ` fix, but not fixed yet).

Broader root cause: `CALL_RE`/`JUMP_RE` only detect references that
are LITERALLY the operand of `CALL`/`JP`/`JR`/`DJNZ`. Any other way
of "using" a label (storing it in a register to jump to it later via
`JP (IY)`/`(IX)`/`(HL)`, or as a `DW LABEL` entry in a jump table
like `TABLA_MANEJADORES_LOSETA`) wasn't detected at all.

Fixed with a more general approach: new `collect_mentions` function
that gathers EVERY identifier appearing as an operand on any line of
code (outside comments, excluding each label definition's own
`NAME:`). New classification rule, last resort before `sinref`: if
the name appears mentioned anywhere else in the code -> `interna`
(indirect use detected, even if not a literal `JP`/`CALL`).

**Verified**: Python-tool-only change, no `.asm` touched --
`MADMIX.SCR`'s diff re-confirmed unchanged (7, nothing recompiled).
`recursos/flujo_programa.html` regenerated: same total (689),
`interna` goes from 212 to 315 (+103), `sinref` drops from 140 to 37
(-103). The 37 labels left as `sinref` were reviewed by hand: they
match already-documented "no known caller" cases (the 11 unused
`JT_*` slots, `SLOT_RESTART_DD82`, `COMPONER_ACTORES_EN_BUFFER` --
see the `MOTOR_ACTORES` study above), ISR/reset entry points reached
by hardware vector (not by text), end-of-file markers
(`END_OF_FILE_SCR`) and a few genuine candidates to review in a
future session (`TB_ROW`, `MAINLOOP_TABLES`,
`TAIL_BITDISPATCH_END`, `ENASLT_HELPER_*`/`TAPE_MOTOR_HELPER_*`/
`PAGE_CONFIG_E291_*` in the tape loaders). The limitation note in the
script's docstring was updated (text heuristic: a name that happens
to coincidentally match unrelated code would get marked "internal"
without really being so -- no real case of this has been seen yet).

### SCROLL_ADDR_CALC -> DIBUJAR_FILA_LOSETAS_BUFFER_VRAM

Renamed `SCROLL_ADDR_CALC` to `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`:
after explaining it, it doesn't compute any "scroll" -- it redraws
ONE COMPLETE ROW (12 tiles) of the maze into the `$DE04` work buffer,
calling `TILE_ADDR_CALC` (its already-identified "twin") twice per
row to locate each tile's real graphic. Called 36 times (once per
visible row) from `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` for the
TOTAL camera redraw (boot, level change, life lost, demo cycle) --
unlike `SCROLL_LOSETA_BUFFER_VRAM`, which is the INCREMENTAL redraw
of a single tile when crossing it.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 689 labels (no change in total, a 1:1
rename). `recursos/flujo_programa.html` (the
`JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` table) and
`recursos/mapa_memoria.html` (2 mentions, segments 0x8C34 and 0xDE04)
updated.

### TILE_ADDR_CALC -> MAPEAR_LOSETA_A_GRAFICO

Renamed `TILE_ADDR_CALC` to `MAPEAR_LOSETA_A_GRAFICO`, in parallel
with its already-identified twin `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
(same verb, same "X_A_Y" structure). Given a tile position (packed
row/column), looks up its type in the loaded level's buffer
(`$FC50`) and returns in `HL` the real address of its graphic in
`TILE_GFX` ($B940), also saving it in `($8433)`. Called from
`DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` (twice per row) and from
`SCROLL_LOSETA_BUFFER_VRAM`/`GESTIONAR_SCROLL` (incremental redraw of
a single tile).

**Pending, not yet renamed or resolved**: the routine's final
stretch (lines ~1683-1709, internal label `TAC_TAIL`) queries a
second table at `$8EC7` (same area as `TILE_TYPES`+3, used by
`CONSULTAR_TIPO_LOSETA`) and, if the tile type's original bit7
("food") was set, does an `XOR (HL)` that flips a bit of that entry
-- a candidate for "toggle graphic variant/color of an already-eaten
tile", unconfirmed live and not yet cross-checked with anything else.
No comment of its own in the code -- pending a future session.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 689 labels (no change in total, a 1:1
rename). `recursos/mapa_memoria.html` updated (1 mention, segment
0x89AD-0x8C34, `GESTIONAR_SCROLL`).

### SAC_LOOP -> .BUCLE_LOSETAS_FILA (local label)

Renamed `SAC_LOOP` to `.BUCLE_LOSETAS_FILA`, as a LOCAL label (scope
`DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`, its only use). It's the 12-pass
loop that copies each tile's graphic in the row into the buffer,
calling `MAPEAR_LOSETA_A_GRAFICO` twice (at the start and halfway
through the loop, to advance to the next tile).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 688 labels (down 1, same usual mechanism for
new local labels -- zero real loss). No mentions in the active
HTML/`.md` files.

### Comments + decimal in DIBUJAR_FILA_LOSETAS_BUFFER_VRAM's 3 header `LD`s

At the developer's request, reviewed the 3 values `LD B,$20`/
`LD C,$FF`/`LD A,$0C` in `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`'s header
(right before `.BUCLE_LOSETAS_FILA`) against the already-agreed hex/
decimal criterion. Only `LD A,$0C` -> `LD A,12` fits as decimal (it's
the loop's pure counter, 12 tiles per row). `LD B,$20` (32-byte step
between VRAM pattern-table strips) and `LD C,$FF` (BC's low byte,
only relevant for `LDI`'s automatic decrement, with no confirmed use
of its own in the loop) are left in hex -- same "packed address/
step" and "unconfirmed value" criterion already applied in earlier
rounds. A comment explaining its role was added to each of the 3
lines.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### SCROLL_LR_PARAM: confirmed the return value (DE) has no consumer

Following a question from the developer about `SCROLL_LR_PARAM`
($2C25, `madmix_scr_body.asm:345`), investigated the 3 sites that
call `GESTIONAR_SCROLL` (the only real entry point to the routines
that write this variable) to see whether any of them actually use
the returned `DE`.

All 3 (`madmix_scr_body.asm:665`, `:1209`, `:1439`) follow the SAME
pattern: `PUSH DE` right before `CALL GESTIONAR_SCROLL` and `POP DE`
a bit later (after the `CALL`s to `HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/
`HNDLR_REGPUNANTOSO`/`ACTUALIZAR_DESTELLO_ITEMS`), restoring the `DE`
they had BEFORE the call -- systematically discarding the `DE`
`GESTIONAR_SCROLL` returns.

The piece that closes the case: `GESTIONAR_SCROLL` calls
`SCROLL_UP`/`SCROLL_DOWN`/`SCROLL_LR` not with `CALL` but with `JP`
(tail-call) -- so `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`/
`SCROLL_LOSETA_BUFFER_VRAM`'s final `RET` (which loads
`DE,(SCROLL_LR_PARAM)` right before returning) returns DIRECTLY to
those 3 sites, with no intermediate consumer inside
`GESTIONAR_SCROLL`.

**Conclusion**: in the code already transcribed and byte-verified,
the value `SCROLL_LR_PARAM` leaves in `DE` on return **is used by
nobody** -- confirmed at the 3 only real callers of
`GESTIONAR_SCROLL`. The reason each scroll direction writes a
different value into the variable (`SCROLL_LR`: `$0400`/`$FC00`
depending on the branch; `SCROLL_DOWN`: `$0004`; `SCROLL_UP`:
`$00FC`) if nobody reads it afterward remains unresolved -- a
candidate for "dead output" (possibly leftover from an older calling
convention, or meant for a consumer that was never wired up / no
longer exists in this version), but the variable hasn't been renamed
nor has anything in the code changed: the value's ORIGINAL purpose
remains unconfirmed, only that it lacks a real consumer today.

**Verification note**: pure-analysis section, no changes to any
`.asm` -- no recompile or diff applies.

### IR_JOYREAD's internal labels renamed to Spanish

At the developer's request, after explaining `IR_JOYREAD` (joystick
reading via the PSG port inside `LEER_ENTRADA`, which reorders the
bits so the result uses the same format as the keyboard reading),
renamed its 5 internal labels `IRJ_B1..B5` (local, only used inside
the routine) according to the direction/button each one leaves
behind when moving to the next test -- the developer confirmed that
the "button" (bit4, previously `IRJ_B5`) is fire:

- `IRJ_B1` -> `.COMPROBAR_ABAJO`
- `IRJ_B2` -> `.COMPROBAR_IZQUIERDA`
- `IRJ_B3` -> `.COMPROBAR_DERECHA`
- `IRJ_B4` -> `.COMPROBAR_DISPARO`
- `IRJ_B5` -> `.CONTINUAR_TRAS_DISPARO`

Along the way, a `; bitN = direction` comment was added to each of
the 5 `RRA` that test the corresponding bit (up/down/left/right/
fire).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 683 labels (down from 688 to 683, -5, exactly
the 5 new local labels -- zero real loss). No mentions in the active
HTML/`.md` files (README.md mentions `IR_JOYREAD` by its global name,
unchanged; the sub-labels were never cited outside the `.asm`
itself).

### IR_JOYREAD -> LEER_JOYSTICK

Renamed `IR_JOYREAD` to `LEER_JOYSTICK`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 683 labels (no change in total, a 1:1
rename). `recursos/mapa_memoria.html` (segment 0xDD8A-0xDD93,
`PSG_WRITE_READ_DD8A`) and `src/README.md` updated.

### PSG_WRITE_READ_DD8A -> CONFIGURAR_Y_LEER_JOYSTICK_PSG

Renamed `PSG_WRITE_READ_DD8A` to `CONFIGURAR_Y_LEER_JOYSTICK_PSG`:
writes to the already-selected PSG register (finishes putting the
mixer in input mode, a value prepared by `LEER_JOYSTICK`), selects
register 14 (I/O port A) and reads joystick 1's state. Also added a
comment on the line of the only real call (`LEER_JOYSTICK`)
explaining the routine's two halves.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 683 labels (no change in total, a 1:1
rename). `recursos/mapa_memoria.html` (segment 0xDD8A-0xDD93) and
`src/README.md` updated.

### IR_JOYLOOP -> COMPROBAR_PAUSA (finding: the 6th redefinable action identified)

Renamed `IR_JOYLOOP` to `COMPROBAR_PAUSA`. Despite the "LOOP" name it
carried, it isn't a loop -- it's a SINGLE extra port test (the 6th
pair in `IR_PORT_TABLE`), shared by `LEER_ENTRADA`'s two paths:
reached by falling through with no jump from the end of `IR_KBTEST`
(keyboard scan, 5 tests) or by jumping directly from `LEER_JOYSTICK`
(after reading the joystick). It also acts as a shared epilogue:
merges (`OR`) the resulting bit with the accumulator at `$8EC4` and
returns.

**Finding, from a hint by the developer**: the game menu's 6
redefinable actions are "PAUSE/FIRE/UP/DOWN/LEFT/RIGHT" -- exactly
6, the same number as `IR_PORT_TABLE`'s 6 pairs (5 for `IR_KBTEST` +
1 for this extra test). Since the 4 directions + fire were already
confirmed in the 5 normal tests (`IR_KBTEST` and `LEER_JOYSTICK`'s 5
`RRA`), the 6th shared test can ONLY be PAUSE -- consistent with it
always being read from the keyboard, even in joystick mode (pause
usually isn't mapped to a stick button). Comments updated in
`LEER_ENTRADA`'s header, on the label itself, and in
`IR_PORT_TABLE`'s data block reflecting the finding.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 683 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### $8EC6 -> FLAG_ENTRADA_BLOQUEADA (new label)

At the developer's request, gave `$8EC6` its own label (a "free"
byte inside `TILE_TYPES`, offset 2, always `$00` in the ROM):
`FLAG_ENTRADA_BLOQUEADA`. It's the flag that makes `LEER_ENTRADA`
return without reading anything (bit0 set -> immediate `RET NZ`)
during the HUD column-search animation when loading a level
(`PREPARAR_INICIO_NIVEL` activates it before `BUSCAR_COLUMNA_HUD`,
`MOSTRAR_READY_Y_ARRANCAR_NIVEL` deactivates it when finished).

Since it had no identity of its own -- it's a byte in the middle of
`TILE_TYPES`'s first row of 16 `DB $00` -- that row was split into
two `DB`s (2 bytes + label + 14 bytes) so it could be labeled
without touching any output byte. Substituted the 3 real uses
(`LD HL,$8EC6`/`LD ($8EC6),A` x2) and updated the 2 header comments
that mentioned it.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 684 labels (+1, a real new label -- "data"
category). `recursos/flujo_programa.html` (2 mentions) and
`src/FLUJO_PROGRAMA.md` (3 mentions) updated.

### $8EC4 -> ACUMULADOR_ENTRADA (new label) + a third bug in gen_inventory.py

At the developer's request, same operation as with `$8EC6`: gave
`$8EC4` -- which exactly coincides with the start of `TILE_TYPES` --
its own label: `ACUMULADOR_ENTRADA`. It's the byte `LEER_ENTRADA`
clears (if `A=0`) or leaves intact (if `A!=0`) before reading, and
where the 3 exit paths (`IR_KBTEST`/`COMPROBAR_PAUSA`/
`LEER_JOYSTICK`) merge the result with `OR` before returning -- the
"accumulator" other code sites later check with `AND $3F`/`AND $06`.
Since it coincided with `TILE_TYPES`'s address, no `DB` needed
splitting -- it was added as a second label stacked right on top
(`TILE_TYPES:` / `ACUMULADOR_ENTRADA:`, same byte). Substituted the 3
real uses and updated the 2 header comments that mentioned `$8EC4`
in `LEER_ENTRADA`'s context (left untouched the 2 mentioned in the
distinct context of `CONSULTAR_TIPO_LOSETA`/`TILE_TYPES` as the tile-
type table).

**Side effect found and fixed**: stacking `ACUMULADOR_ENTRADA:`
right below `TILE_TYPES:` made `gen_inventory.py` reclassify
`TILE_TYPES` from "data" to "unreferenced" -- the "what follows the
label" finder didn't know how to skip over ANOTHER stacked label
(with or without its own comment) to reach the real `DB`. Same kind
of bug as the 2 already fixed earlier in this tool (`DJNZ` not
detected, indirect uses not detected). Fixed the search loop so
lines that are only another label (with or without a comment) are
transparent and the search continues until the real statement.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 685 labels (+1, a real new label -- "data"
category). The `gen_inventory.py` fix also corrected 3 pre-existing
similar cases elsewhere in the project (not just `TILE_TYPES`):
`dato`/data goes from 237 to 241 (+4 total), `sinref` drops from 38
to 34 (-4). No mentions to sync in the active HTML/`.md` files (the 2
mentions of `$8EC4` in `mapa_memoria.html` are from a different
context, `CONSULTAR_TIPO_LOSETA`, unrelated to this rename).

### IR_49 -> .CONTINUAR_TRAS_LIMPIAR_ACUMULADOR (local label)

Renamed `IR_49` to `.CONTINUAR_TRAS_LIMPIAR_ACUMULADOR`, local to
`LEER_ENTRADA` (its only use). It's the merge point of the `A`
parameter's 2 branches: if `A=0` it clears `ACUMULADOR_ENTRADA`
before falling here; if `A!=0` it jumps here directly without
clearing. From here the code is identical for both cases (dispatches
to `IR_KBLOOP`/`LEER_JOYSTICK` based on `$8427`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 684 labels (down 1, same usual mechanism for
new local labels -- zero real loss). No mentions in the active
HTML/`.md` files.

### LEER_TECLADO -> COMPROBAR_PULSACION

Renamed `LEER_TECLADO` ($5D0A) to `COMPROBAR_PULSACION`: it doesn't
read or decode any specific key, it does a single sweep of the
matrix's 9 rows and returns with the Z flag set to indicate whether
it found any key pressed (`Z`=none, `NZ`=yes) -- a one-shot query,
not a wait (the wait loop is done by its callers,
`TAIL_KEYWAIT_RELEASE`/`TAIL_KEYWAIT_UP`, calling it repeatedly).
This frees up the name `LEER_TECLADO` for `IR_KBLOOP` (renamed in the
next round), avoiding the collision that would happen if `IR_KBLOOP`
were also called `LEER_TECLADO`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 684 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### IR_KBLOOP -> LEER_TECLADO_DIRECCIONES

Renamed `IR_KBLOOP` to `LEER_TECLADO_DIRECCIONES`, now that
`LEER_TECLADO` was freed up (previous round). It's `LEER_ENTRADA`'s
"keyboard" half, the counterpart of `LEER_JOYSTICK`: scans
`IR_PORT_TABLE`'s first 5 row/mask pairs (up/down/left/right/fire)
via `IR_PORTTEST`, building the same bit format as `LEER_JOYSTICK` in
`E`, and falls through with no jump into `COMPROBAR_PAUSA` for the
6th shared test.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 684 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### $8427 -> MODO_ENTRADA (new label) + concrete values confirming the inverted polarity

At the developer's request, gave `$8427` (inside the `$8427-$8430`
padding gap, always `$00` in the ROM) its own label: `MODO_ENTRADA`.
It's the keyboard/joystick selector `LEER_ENTRADA` reads to dispatch
to `LEER_TECLADO_DIRECCIONES` (0) or `LEER_JOYSTICK` (!=0). No
splitting was needed -- the label was placed right before the
`DS $8430-$,$00` that already reserved the whole gap.

Along the way, while locating the 3 real sites that write it
(`madmix_scr_body.asm`, main menu), concrete NUMBERS could finally be
put to the inverted-polarity suspicion `LEER_ENTRADA`'s header
comment had carried for several rounds: `TI_5C60` (menu option "1
KEYBOARD") writes `MODO_ENTRADA=1`, `TI_5C70` ("2 JOYSTICK") writes
`MODO_ENTRADA=0` -- EXACTLY the opposite of how `LEER_ENTRADA`'s
dispatcher interprets it (1 -> joystick, 0 -> keyboard). Comment
expanded with this confirmation; still unresolved whether this is a
real bug in the original or whether there's another, not-yet-located
site that touches the variable again between the menu selection and
gameplay.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 685 labels (+1, a real new label --
classified "internal" by the inventory, not "data": being a padding
`DS` instead of a `DB` with its own value, `gen_inventory.py`'s
heuristic counts it by its references instead of by adjacent data --
a reasonable classification, not a bug). `src/FLUJO_PROGRAMA.md` (the
menu-options table) updated.

### LEER_TECLADO_DIRECCIONES -> LEER_TECLADO

Renamed `LEER_TECLADO_DIRECCIONES` to `LEER_TECLADO`, now that that
name was freed up again after renaming the routine that previously
held it to `COMPROBAR_PULSACION` (previous round). No behavior
changes, just the final name still missing in this chain of renames
for `LEER_ENTRADA` and its family.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 685 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### IR_PORT_TABLE's 6 pairs broken out with a comment per stretch

At the developer's request, `IR_PORT_TABLE`'s single 12-byte `DB`
line is broken out into 6 lines of 2 bytes each (one row/mask pair
each), with a comment indicating which action it corresponds to: up,
down, left, right, fire and pause (the last one, used by
`COMPROBAR_PAUSA`). Pure format change, same bytes.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### IR_PORT_TABLE -> TABLA_TECLAS_MSX

Renamed `IR_PORT_TABLE` to `TABLA_TECLAS_MSX`: the 6 row/mask pairs
of the standard MSX keyboard matrix used by `LEER_TECLADO`/
`COMPROBAR_PAUSA` for the 6 configurable control actions.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 685 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### IR_KBTEST/IR_65/IR_68 renamed + finding: ESCANEAR_FILAS_TECLADO is a routine shared across files

While renaming the 3 labels confirmed with the developer, it was
detected that `IR_KBTEST` **wasn't purely local** to `LEER_TECLADO`
as initially thought: `madmix_scr_body.asm:3696` (inside what was
named `TAIL_FONT_ROUTINE`) calls it directly with `CALL`, with its
own table (`TAIL_UNK_5C93`, 6 pairs, all row `$F0`) and `B=6` instead
of `B=5`. Renaming it to a local label would have broken compilation
(and in fact did on a first attempt, fixed before continuing) -- it
was made global instead: `IR_KBTEST` -> `ESCANEAR_FILAS_TECLADO`.
`IR_65`/`IR_68` (the 2 internal branches of its loop, with no
external caller) ARE purely local:
`IR_65` -> `.TECLA_NO_PULSADA`, `IR_68` -> `.CONTINUAR_BUCLE_TECLAS`.

**Side finding**: `TAIL_FONT_ROUTINE` has nothing to do with fonts/
patterns (a historical name from a discarded hypothesis) -- by
calling `ESCANEAR_FILAS_TECLADO` with its own 6-key table (all on row
`$F0`) and returning the bitmask in `E`, checked bit by bit by its
caller (`TI_5B62`/`TI_5B65`, the main menu loop) right after, it's
actually the **main menu's key reader** (the equivalent of
`LEER_TECLADO`/`LEER_JOYSTICK` but for menu navigation). Header
comment fixed, marked as a rename candidate (e.g.
`LEER_TECLAS_MENU_PRINCIPAL`) for a future round -- not renamed yet,
out of scope for this specific request.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- after fixing a
first attempt that introduced an extra `JR` not present in the
original (the "fall through with no jump" mistakenly turned into an
explicit jump while moving the comment; caught and fixed before
finalizing the round). `.dsk`/`.cas`/HTML inventory regenerated: 683
labels (down from 685 to 683, -2, the 2 new local labels -- zero real
loss). No mentions to sync in the active HTML/`.md` files
(`FLUJO_PROGRAMA.md` already correctly described `TAIL_FONT_ROUTINE`
as "reads a key", without mentioning fonts).

### IR_PORTTEST -> COMPROBAR_TECLA_MSX

Renamed `IR_PORTTEST` to `COMPROBAR_TECLA_MSX`: the lowest-level
helper of the whole keyboard-reading family -- selects the matrix
row (`IX+0`, port `$AA`), reads the columns (port `$A9`) and isolates
a specific key's bit with `AND (IX+1)`. Called by
`ESCANEAR_FILAS_TECLADO` (once per table pair) and by
`COMPROBAR_PAUSA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 683 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### IR_79 -> .FINALIZAR_LECTURA (local label)

Renamed `IR_79` to `.FINALIZAR_LECTURA`, local to `COMPROBAR_PAUSA`
(its only use). It's the merge point after checking the PAUSE key
(pressed or not): merges `E` with `ACUMULADOR_ENTRADA` (`OR (HL)`)
and returns -- the same pattern as `.CONTINUAR_BUCLE_TECLAS` in
`ESCANEAR_FILAS_TECLADO`, but for this single check.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 682 labels (down 1, same usual mechanism for
new local labels -- zero real loss). No mentions in the active
HTML/`.md` files.

### Split FLAG_ENTRADA_BLOQUEADA's own byte from the rest of TILE_TYPES's row

At the developer's request, the 14-byte `DB` that started at
`FLAG_ENTRADA_BLOQUEADA` is split into its own byte (`DB $00`) plus
the remaining 13 padding bytes on their own line -- the same
treatment already applied to `ACUMULADOR_ENTRADA`. Pure format
change, same bytes.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### TILE_TYPES moved from $8EC4 to $8EC7 (the table's real address)

Following the finding of who uses the byte adjacent to
`FLAG_ENTRADA_BLOQUEADA` ($8EC7), the developer asked to move the
`TILE_TYPES` label to that address. Confirmed correct: the ONLY real
consumer of the tile-type table, `CONSULTAR_TIPO_LOSETA`, uses
`HL=$8EC7+A / AND $1F` as the base -- the 3 preceding bytes
($8EC4-$8EC6) aren't part of the table, they're the zone reused by
`LEER_ENTRADA` (`ACUMULADOR_ENTRADA`/`FLAG_ENTRADA_BLOQUEADA`).

`TILE_TYPES` is moved to `$8EC7` (without removing any byte -- the
full reserved 96-byte block is still emitted the same, ending EXACTLY
at `INICIO`/`$8F24` as already verified). Along the way, substituted
the 2 real uses still in hex (`LD HL,$8EC7` in
`MAPEAR_LOSETA_A_GRAFICO` and in `CONSULTAR_TIPO_LOSETA`) with the
label, and updated every comment that described `TILE_TYPES` as
starting at `$8EC4` (the data block's header, `GESTIONAR_SCROLL`'s
header, the `CONSULTAR_TIPO_LOSETA`/`LEER_ENTRADA` block's header,
`LEER_ENTRADA`'s own header).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 682 labels (no change in total, the label
already existed, only its address changes).
`recursos/mapa_memoria.html` (2 mentions, segments 0x8E3C-0x8EC4 and
0x8EC4-0x8F24) and `src/FLUJO_PROGRAMA.md` (1 mention) updated.

### TILE_TYPES -> TABLA_TIPOS_LOSETA

Renamed `TILE_TYPES` to `TABLA_TIPOS_LOSETA`: the tile-type/collision
table (indexed by the same number as the graphic), queried by
`CONSULTAR_TIPO_LOSETA` and written by `MAPEAR_LOSETA_A_GRAFICO`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 682 labels (no change in total, a 1:1
rename). `recursos/mapa_memoria.html` (2 mentions) and
`src/FLUJO_PROGRAMA.md` (1 mention) updated.

### Format: hex -> decimal in TABLA_TIPOS_LOSETA

After confirming `TABLA_TIPOS_LOSETA`'s bytes match, byte for byte,
the type<->tile catalog already confirmed in earlier rounds (offsets
45-92 cross-checked against `data/tiles/*.til` and
`HNDLR_TRAMPILLA_*`/`HNDLR_PISTA_COCONAVE`/etc., a perfect match with
no discrepancy), its 93 bytes were converted from hex to decimal:
same criterion already applied to `TABLA_CLASE_ALINEAMIENTO` -- it's
a pure index/enum (0-19) used directly as dispatch in
`TABLA_MANEJADORES_LOSETA`, not a bitmask or an address. Pure format
change, same bytes (`$01`->`1` ... `$13`->`19`, and the `$00`s that
were already the same in both formats).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Split ACUMULADOR_ENTRADA's padding byte

Following a question from the developer, confirmed that the second
byte of `ACUMULADOR_ENTRADA`'s `DB $00,$00` ($8EC5) has no real
reference anywhere in the code (searched across the whole project,
zero results) -- it's pure padding of the reserved block, unlike the
first byte ($8EC4) which IS `LEER_ENTRADA`'s real accumulator. Split
into its own line with an explicit comment, the same treatment as
`FLAG_ENTRADA_BLOQUEADA`. Pure format change, same bytes.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Format: hex -> decimal in FLAG_ENTRADA_BLOQUEADA (ACUMULADOR_ENTRADA left in hex)

Following a question from the developer about whether
`ACUMULADOR_ENTRADA`/`FLAG_ENTRADA_BLOQUEADA` should be in decimal:
`FLAG_ENTRADA_BLOQUEADA` yes (`$00`->`0`) -- it's a pure boolean
(`BIT 0,(HL)`), the same case already applied to
`FLAG_NIVEL_RECIEN_CARGADO`/`FLAG_DIRECCION_NUEVA`.
`ACUMULADOR_ENTRADA` is left in hex -- it isn't a boolean or an enum,
it's a BITMASK accumulator (up/down/left/right/fire/pause, set with
`SET`/`RL`), the same family as `DIRECCION_DE_MOVIMIENTO`/
`DIRECCION_SIN_PROCESAR`/`DIRECCION_FORZADA`, already left in hex for
the same reason. Pure format change, same byte (`$00`=`0`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).
### RM_C4BC/RM_C4C6/RM_C4C9 renamed to local labels (free-slot search in INSTALAR_RECURSO_SONIDO)

Analyzed the detail of `INSTALAR_RECURSO_SONIDO` (sound driver):
before searching, it checks whether the SPECIFIC slot the caller
asked for (index in `A`) is already free; if so, it's used directly
with no search. If not, it walks the 3 46-byte slots from `$C9C9`
looking for a free one (a 2-byte pointer to `$0000`); if it finds
one, it uses it; if all 3 are occupied, it falls back to the
originally requested slot (fallback, overwriting it). Renamed, all
local (only used inside the routine):

- `RM_C4BC` -> `.BUSCAR_RANURA_LIBRE` (the search loop)
- `RM_C4C6` -> `.USAR_RANURA_SOLICITADA` (the one requested by the
  caller, free from the start or a fallback if none other was)
- `RM_C4C9` -> `.USAR_RANURA_ENCONTRADA` (the one the search loop
  found)

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 679 labels (down from 682 to 679, -3, exactly
the 3 new local labels -- zero real loss). No mentions in the active
HTML/`.md` files.

### RM_C4D8 -> LIMPIAR_E_INSTALAR_RANURA

Renamed `RM_C4D8` to `LIMPIAR_E_INSTALAR_RANURA`: a tail shared
between `INSTALAR_RECURSO_SONIDO` (jumps here with `JR` after
choosing a slot) and `INSTALAR_RECURSO_SONIDO_EN_A` (falls through
with no jump, no slot search). Zeroes the chosen slot's 46 bytes and
writes the sound-resource pointer twice in a row at the start. Left
global (can't be local, used by 2 different global routines).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 679 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### RM_C4DC -> .BUCLE_LIMPIAR_RANURA (local label)

Renamed `RM_C4DC` to `.BUCLE_LIMPIAR_RANURA`, local to
`LIMPIAR_E_INSTALAR_RANURA` (its only use). It's the loop that zeroes
the slot's 46 bytes, byte by byte with `DJNZ`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 678 labels (down 1, same usual mechanism for
new local labels -- zero real loss). No mentions in the active
HTML/`.md` files.

### RM_PLAYER_TICK_C4EB -> TICK_REPRODUCTOR_PSG

Renamed `RM_PLAYER_TICK_C4EB` to `TICK_REPRODUCTOR_PSG`: the PSG
sound player's real "tick" entry point, called from
`TAIL_LEVELCYCLE_HELPER` on every VBLANK.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 678 labels (no change in total, a 1:1
rename). `recursos/flujo_programa.html` (1 mention) and
`src/FLUJO_PROGRAMA.md` (1 mention) updated.

### RM_C4F9 -> PROCESAR_CANAL_PSG

Renamed `RM_C4F9` to `PROCESAR_CANAL_PSG`:
`TICK_REPRODUCTOR_PSG`'s 3-channel loop header. For each slot, checks
whether it's "waiting" (jumps to `RM_C564` if so); if not, reads the
next script byte (a command via `CMD_JUMP_TABLE_C99E` if `>=$80`, a
note duration via `RM_TABLE_C8DE` if not). Left global (same style
already used by the rest of this sound driver's `RM_Cxxxx` labels,
not yet converted to local).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 678 labels (no change in total, a 1:1
rename). No mentions in the active HTML files; `src/FLUJO_PROGRAMA.md`
(1 mention) updated.

### RM_C564..RM_C6B1 renamed: the sound driver's volume/pitch envelope engine

At the developer's request ("pull the thread" / "rename it now"),
analyzed and renamed the stretch of `TICK_REPRODUCTOR_PSG` that
applies envelopes per tick. Cross-checking it with the block already
in `FINDINGS.md` ("RESOLVED: the 15 sound driver bytecode
commands"), confirmed it's exactly the mechanism already described
there (channel-record offset table, command 7 `SET_INSTRUMENT` that
loads the envelope parameters) -- used that already-established
terminology ("envelope") instead of "modulation"/"tremolo/vibrato"
which had been floated in conversation.

Renamed (all `.local` labels scoped to `APLICAR_ENVOLVENTES_CANAL`):

- `RM_C564` -> `APLICAR_ENVOLVENTES_CANAL` (global, jumped to from
  `PROCESAR_CANAL_PSG`): decrements the note's tick counter and
  applies one step of each envelope.
- `RM_C579` -> `.BUCLE_ENVOLVENTE_VOLUMEN`, `RM_C586` ->
  `.RECARGAR_PASO_ENVOLVENTE_VOLUMEN`, `RM_C5A2` ->
  `.CONTINUAR_ENVOLVENTE_VOLUMEN`, `RM_C5A7` ->
  `.FIN_ENVOLVENTE_VOLUMEN` (volume envelope, accumulator `+$2A`).
- `RM_C5B2` -> `.INICIAR_ENVOLVENTE_TONO`, `RM_C5BA` ->
  `.BUCLE_ENVOLVENTE_TONO`, `RM_C5C7` ->
  `.RECARGAR_PASO_ENVOLVENTE_TONO`, `RM_C5F1` ->
  `.SUMAR_PASO_ENVOLVENTE_TONO`, `RM_C604` ->
  `.CONTINUAR_TRAS_PASO_ENVOLVENTE_TONO`, `RM_C60D` ->
  `.CONTINUAR_ENVOLVENTE_TONO`, `RM_C612` -> `.FIN_ENVOLVENTE_TONO`
  (pitch/slide envelope, accumulator `+$2B/+$2C`, signed).
- `RM_C61D` -> `COMBINAR_Y_ESCRIBIR_CANAL` (global, also jumped to
  directly from `PROCESAR_CANAL_PSG` when the script is empty): adds
  accumulators + base values and writes the PSG's volume/pitch
  registers, advances to the next slot.
- `RM_C699` -> `REINICIAR_ENVOLVENTE_VOLUMEN`, `RM_C6B1` ->
  `REINICIAR_ENVOLVENTE_TONO` (global, called both when setting up a
  new note and when an envelope runs out completely): reload
  countdown/steps from the instrument values.

Also added a header comment on `APLICAR_ENVOLVENTES_CANAL`
summarizing the mechanism and pointing to the offset table already
documented in `FINDINGS.md`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 667 labels (down from 678 to 667, -11, exactly
the 11 new local labels -- zero real loss). No mentions in the active
HTML/`.md` files (the ones in `FINDINGS.md` are historical, left
untouched).

### RM_C518/RM_C527 renamed + 2 hex-not-substituted fixed (the PSG bytecode command dispatcher)

Renamed the command-dispatch loop already described in `FINDINGS.md`
("RESOLVED: the 15 commands..."): `RM_C518` -> `DESPACHAR_COMANDO_PSG`
(global, the ~13 command routines return here after running -- reads
the next script byte; if `>=$80` dispatches via
`CMD_JUMP_TABLE_C99E`, otherwise falls into note resolution);
`RM_C527` -> `.RESOLVER_NOTA` (local, only use: adds the note to the
channel's transposition and looks it up in `RM_TABLE_C8DE` to get the
base pitch period).

Along the way, fixed the 2 `LD HL,$Cxxx` still in hex even though
`CMD_JUMP_TABLE_C99E`/`RM_TABLE_C8DE` already had their own labels --
the same usual systemic pattern.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (down 1, the only new local label
-- zero real loss). No mentions in the active HTML/`.md` files.

### RM_C82E -> ACTUALIZAR_MEZCLADOR_CANAL

Renamed `RM_C82E` to `ACTUALIZAR_MEZCLADOR_CANAL`: enables/disables
the current channel's tone and noise in the PSG mixer register's
shadow (`$C9C5`), already documented in detail in an earlier round
("audio renderer", polarity fixed).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### CMD_JUMP_TABLE_C99E -> TABLA_COMANDOS_PSG

Renamed `CMD_JUMP_TABLE_C99E` to `TABLA_COMANDOS_PSG`: the jump table
for the sound driver bytecode's 15 commands, already fully decoded
in an earlier round.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### RM_C8BC -> LEER_PALABRA_INDEXADA

Renamed `RM_C8BC` to `LEER_PALABRA_INDEXADA`: a generic 16-bit
word-table lookup helper (`HL`=table, `A`=index ->
`HL`=value at `table+A*2`), used both for note duration/pitch
(`RM_TABLE_C8DE`) and for command dispatch (`TABLA_COMANDOS_PSG`).
Along the way, fixed an outdated mention of the old name
`RM_TABLE_C99E` in its own header comment (already renamed to
`TABLA_COMANDOS_PSG` in an earlier round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### RM_C882 -> OBTENER_PUNTERO_TRANSPOSICION

Renamed `RM_C882` to `OBTENER_PUNTERO_TRANSPOSICION`: computes
`HL = TRANSPOSE_TABLE_CA67 + current channel`. Used by
`DESPACHAR_COMANDO_PSG.RESOLVER_NOTA` to add the transposition to the
note before looking up the pitch period, and by command 14
(`SET_CHANNEL_STATE`, already documented in `FINDINGS.md`) to set it.
Header comment updated with both confirmed uses (the second one is
no longer "unconfirmed", it had been resolved in an earlier round
about the 15 commands).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### RM_TABLE_C8DE -> TABLA_NOTAS_PSG

Renamed `RM_TABLE_C8DE` to `TABLA_NOTAS_PSG` (a single round -- the
developer adjusted the name from `TABLA_NOTAS` to `TABLA_NOTAS_PSG`
right after, before verifying, so both steps are applied together):
the 96-word table mapping note+transposition -> the PSG's real pitch
period, already fully decoded in an earlier round ("RESOLVED: the 15
commands...").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 666 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### Renamed the remaining 26 RM_ labels of the sound driver + finding: a third shared envelope (noise)

At the developer's request ("analyze all the RM_ functions and their
flow" / "apply it all"), analyzed and renamed the rest of the sound
driver in one go.

**Main finding**: the stretch `madmix1_body.asm:3617-3660` (previously
without its own label, only reachable by falling through with no
jump after `TICK_REPRODUCTOR_PSG`'s 3-channel loop) is a **third
envelope**, with the exact same structure (countdown/steps/increment/
period) as the already-renamed volume/pitch ones, but over the
SHARED table `$CA53` instead of per-channel -- combines
`($CA5E)+($CA5F)` and writes the result to `$C9C4`, the shadow of the
**PSG's register 6 (NOISE period)**. Makes sense that it's shared:
the AY-3-8910 only has one noise generator for all 3 channels. Given
a new global label, `APLICAR_ENVOLVENTE_RUIDO`, with a header comment
explaining the finding.

**Renamed** (global, when called from more than one site or from
outside their immediate block):
`RM_C53A`->`ARMAR_NOTA`, `RM_C552`->`CERRAR_NOTA` (destination of a
direct `JP` from the HOLD/TIE command), `RM_C6C9`->
`REINICIAR_ENVOLVENTE_RUIDO` (relatch of `$CA53`, counterpart of
`REINICIAR_ENVOLVENTE_VOLUMEN`/`_TONO`), `RM_C88D`->
`MULTIPLICAR_8X16`, `RM_C8A2`->`DIVIDIR_16X16`, `RM_C8C9`->
`VOLCAR_REGISTROS_PSG` (dumps the register shadow to hardware, the
final step of each tick).

**Renamed to local** (internal loops/branches with no external use,
20 total): `.BUCLE_ENVOLVENTE_RUIDO`/`.RECARGAR_PASO_ENVOLVENTE_RUIDO`/
`.CONTINUAR_ENVOLVENTE_RUIDO`/`.FIN_ENVOLVENTE_RUIDO`/`.ESCRIBIR_RUIDO_PSG`
(in `APLICAR_ENVOLVENTE_RUIDO`); `.BUCLE_REINICIO_VOLUMEN`/
`.BUCLE_REINICIO_TONO`/`.BUCLE_REINICIO_RUIDO` (in their respective
`REINICIAR_ENVOLVENTE_*`); `.BUCLE_LIMPIAR_RANURA_COMPLETA` (a command
candidate for `RESET_SHARED_ENVELOPE`), `.BUCLE_ACUMULAR_DURACION`
(the `SET_DURATION_MULTI` command), `.BUCLE_COPIAR_INSTRUMENTO` (the
`SET_INSTRUMENT` command), `.BUCLE_COPIAR_FORMA_ENVOLVENTE` (the
`SET_ENVELOPE_SHAPE` command) -- these 4 are internal loops of
command bodies that still have NO label of their own (see note
below); `.BUCLE_DESPLAZAR_MASCARA`/`.APLICAR_MASCARA_MEZCLADOR` (in
`ACTUALIZAR_MEZCLADOR_CANAL`); `.BUCLE_MULTIPLICAR`/
`.CONTINUAR_MULTIPLICAR` (in `MULTIPLICAR_8X16`);
`.BUCLE_DIVIDIR`/`.CONTINUAR_DIVIDIR` (in `DIVIDIR_16X16`);
`.SIN_ACARREO` (in `LEER_PALABRA_INDEXADA`, a branch that was missing
from an earlier round); `.BUCLE_VOLCAR_REGISTROS` (in
`VOLCAR_REGISTROS_PSG`).

**Pending, out of scope for this round**: the bodies of the 15
bytecode commands (`SET_VOLUME`, `SET_MIXER`, etc., already named in
`FINDINGS.md`'s "The 15 commands" table) still have no label of their
own -- only referenced by raw address from `TABLA_COMANDOS_PSG`.
Giving them one would require inserting 15 new labels and rewriting
that table from `DW $Cxxx` to `DW LABEL`, a bigger change left for a
future round if full completion is wanted.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 647 labels (down from 666 to 647, -19 -- 1 new
global label (`APLICAR_ENVOLVENTE_RUIDO`) minus 20 new local labels,
matches exactly). No mentions in the active HTML/`.md` files (only in
`FINDINGS.md`, historical).

### CHANNEL_STATE_ZERO_C9BC -> AREA_TRABAJO_PSG

Renamed `CHANNEL_STATE_ZERO_C9BC` to `AREA_TRABAJO_PSG`: not just
"channel state" -- it's the whole sound driver's 171-byte RAM
working area (channel index, the PSG's 11-register shadow, the 3
channel slots, and the shared tables up to `TRANSPOSE_TABLE_CA67`),
all `$00` in the original v1.0 (in the v2.0 CAS/ROM this is where the
level-13-bug patch is inserted, already documented).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 647 labels (no change in total, a 1:1
rename). No mentions in the active HTML/`.md` files.

### INSTRUMENT_TABLE_CA6A -> TABLA_INSTRUMENTOS_PSG

Renamed `INSTRUMENT_TABLE_CA6A` to `TABLA_INSTRUMENTOS_PSG`: 16
instruments x 15 bytes, copied into the channel slot by the
`SET_INSTRUMENT` command. Along the way, `src/README.md` updated (it
also mentioned the old name `RM_TABLE_C8DE` from an earlier round,
fixed to `TABLA_NOTAS_PSG` at the same time).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 647 labels (no change in total, a 1:1
rename). `src/README.md` (1 mention, 2 names fixed) updated.

### ENV_SHAPE_TABLE_CB5A -> TABLA_ENVOLVENTES_PSG

Renamed `ENV_SHAPE_TABLE_CB5A` to `TABLA_ENVOLVENTES_PSG`: 4
percussion envelope shapes x 6 bytes, copied by the
`SET_ENVELOPE_SHAPE` command to `SHARED_ENVELOPE_TABLE_CA53+4`. Along
the way, `src/README.md` updated (same mention as in the previous
round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`/HTML
inventory regenerated: 647 labels (no change in total, a 1:1
rename). `src/README.md` (1 mention) updated.

### 7 hex-not-substituted fixed: $C9BC -> AREA_TRABAJO_PSG

At the developer's request, located and fixed the 7 real sites still
using `$C9BC` in hex (current channel index) despite coinciding with
`AREA_TRABAJO_PSG`'s exact start: `PROCESAR_CANAL_PSG`, the
`RESET_SHARED_ENVELOPE` command, `ACTUALIZAR_MEZCLADOR_CANAL` (x2),
the `CALL_SUBPATTERN`/`RETURN_SUBPATTERN` commands and
`OBTENER_PUNTERO_TRANSPOSICION`. Same usual systemic pattern.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Fixed AREA_TRABAJO_PSG's commented size: 171 -> 151 bytes

At the developer's request ("check whether the block's size is
correct"), counted the real declared (`DB`) bytes of
`AREA_TRABAJO_PSG`: 2 + 9x16 + 5 = **151 bytes**, not 171 as the
comment said in 2 places (the data block's index header and the
label itself). The block itself WAS fine -- it ends exactly where
`SHARED_ENVELOPE_TABLE_CA53` starts ($CA53-$C9BC=151, checks out) --
it was only the comment's number that was wrong. Fixed in both
places. Comment change, zero byte change.

**Verified**: recompiled, diffs at the exact usual baseline (7/2) --
comment-only, zero content changes.

### 4 hex-not-substituted fixed: $CA53 -> SHARED_ENVELOPE_TABLE_CA53

At the developer's request, the same usual systemic pattern but this
time on the shared (noise) envelope table. Located and fixed the 4
real sites still using `$CA53` in hex despite coinciding with
`SHARED_ENVELOPE_TABLE_CA53`'s exact start: `APLICAR_ENVOLVENTE_RUIDO`
(`LD IY,...`), `REINICIAR_ENVOLVENTE_RUIDO` (`LD IY,...`), the
`RESET_SHARED_ENVELOPE` command (`LD HL,...`) and the
`SET_ENVELOPE_SHAPE` command (`LD IY,...` before
`.BUCLE_COPIAR_FORMA_ENVOLVENTE`). The 2 comments that already
mentioned `$CA53` in prose were left as-is (correct).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### SHARED_ENVELOPE_TABLE_CA53 -> TABLA_ENVOLVENTE_RUIDO_PSG

At the developer's request, renamed following the already-established
`TABLA_X_PSG` pattern (`TABLA_NOTAS_PSG`, `TABLA_INSTRUMENTOS_PSG`,
`TABLA_ENVOLVENTES_PSG`), using "RUIDO"/noise because the functions
that handle it are already called `APLICAR_ENVOLVENTE_RUIDO`/
`REINICIAR_ENVOLVENTE_RUIDO` -- makes clear it's the noise envelope
shared across channels (live state), unlike `TABLA_ENVOLVENTES_PSG`
(template shapes). 8 occurrences renamed in `madmix1_body.asm` (4 in
code, 4 in comments).

**Verified**: recompiled with no errors (recompiling `main.lst`
before regenerating the inventory -- otherwise `gen_inventory.py`
reads stale data from an outdated `.lst`), diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 647 labels (no change in total, a 1:1 rename).

### SUBPATTERN_TABLE_CB72 -> TABLA_SUBPATRONES_PSG

At the developer's request, renamed following the same `TABLA_X_PSG`
pattern -- it's the 21-word (`DW`) pointer table `CALL_SUBPATTERN`
indexes to jump to one of the 13 shared subpatterns. Renamed in
`madmix1_body.asm` (14 mentions, all in comments) and in
`src/README.md` (2 mentions). Also fixed the same name in the
warning banner `tools/mmsnd_tool.py` writes at the top of every
subpattern `.txt` (`warning_banner()`), and regenerated the 13 `.txt`
files in `src/data/sound/spt/` with `py tools/mmsnd_tool.py disasm`
so the notice stays up to date (binary content/instructions
unchanged, only the name in the comment).
`manuales/manual_driver_sonido.md` was left untouched -- it's a
frozen document with several other already-outdated names, not part
of the live docs synced every round.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 647 labels (no change in total, a 1:1 rename).

### 1 hex-not-substituted fixed: $CA6A -> TABLA_INSTRUMENTOS_PSG

At the developer's request, the same usual systemic pattern. Located
and fixed the only real site still using `$CA6A` in hex (inside the
`SET_INSTRUMENT` command, `LD DE,$CA6A` as the base before
`ADD HL,DE` to compute `base + index*15`) despite coinciding with
`TABLA_INSTRUMENTOS_PSG`'s exact start.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### 2 hex-not-substituted fixed: $CB5A -> TABLA_ENVOLVENTES_PSG, $CB72 -> TABLA_SUBPATRONES_PSG

At the developer's request, checked the same systemic pattern for the
2 recently renamed tables. Located and fixed 1 real site per table:
`$CB5A` in the `SET_ENVELOPE_SHAPE` command (`LD DE,$CB5A` as the
base before `ADD HL,DE` for `base + index*6`), and `$CB72` in the
`CALL_SUBPATTERN` command (`LD HL,$CB72` before
`LEER_PALABRA_INDEXADA`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### ISR -> ENTRADA_INTERRUPCION_VBLANK

At the developer's request. The `ISR` label isn't a function called
by code (nobody does `CALL ISR`/`JP ISR`) -- it's the entry point the
CPU jumps to by hardware via the mode-1 interrupt vector
(`$0038/$0039`, installed by `ACTIVAR_INTERRUPCION_MODO_1`). The new
name reflects that: "ENTRADA"/entry instead of a word suggesting an
explicit call. Renamed in `madmix1_body.asm` (6 mentions),
`madmix_scr_body.asm` (4 mentions), `FLUJO_PROGRAMA.md` (several
mentions) and `recursos/mapa_memoria.html` (4 mentions).
`src/README.md` line 568 was NOT touched: it's an already-frozen
session-history paragraph (it even uses `INSTALL_ISR`, an even older
name, left unsynced) -- same criterion as with other history records.
`ISR_HOUSEKEEPING` (a real, distinct function, IS called by code) was
NOT touched -- verified that no replacement affected it.

**Pending note**: `INSTALL_ISR` still appears as-is (not synced to
the real name `ACTIVAR_INTERRUPCION_MODO_1`) in `FLUJO_PROGRAMA.md`
(lines ~137/169) and in `README.md`'s history paragraph -- out of
scope for this round, a candidate for future cleanup.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 647 labels (no change in total, a 1:1 rename).

### GH_885D_EARLYEXIT -> .NO_ES_IRQ_VBLANK (local)

At the developer's request. It's `ENTRADA_INTERRUPCION_VBLANK`'s
early exit when `IN A,($99)` + `AND A`/`JP P,...` detects the sign
bit isn't set (it wasn't a real VBLANK IRQ) -- discards the spurious
interrupt without running `ISR_HOUSEKEEPING`/`TAIL_LEVELCYCLE_HELPER`.
Verified it's only referenced from inside
`ENTRADA_INTERRUPCION_VBLANK` (the only call, in the same routine) --
converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 646 labels (down 1, the known global->local quirk).

### ISR_HOUSEKEEPING -> GESTIONAR_FRAME

At the developer's request. Called from
`ENTRADA_INTERRUPCION_VBLANK` on every VBLANK: decides whether a full
frame's heavy work is due yet using `FRAME_FLAG` as a semaphore -- if
so, refreshes VRAM (`ACTUALIZAR_VRAM_FRAME`), advances actors
(`CONTINUAR_CAPTURA_MASCARAS_ACTORES`/`RESET_CONTADOR_ACTORES`) and
empties the deferred-redraw queue (previously `$8CFF`, already
identified in another round). The Spanish name reflects what it does
("manage the frame") instead of the English acronym "housekeeping"
inherited from earlier analysis. Renamed in `madmix1_body.asm` (6
mentions), `src/README.md` (1 mention), `src/FLUJO_PROGRAMA.md` (3
mentions) and `recursos/mapa_memoria.html` (1 mention).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 646 labels (no change in total, a 1:1 rename).

### GH_8889_HOOK -> FUNCION_INHABIL

At the developer's request. Confirmed byte for byte that the body is
just `RET` (1 byte) -- it does nothing, even though the 4 calls (3
from `GESTIONAR_FRAME`, 1 from `ACTUALIZAR_VRAM_FRAME`) preload `A`
with different values ($0F/$01/$01/$06) that are completely ignored.
Left global (called from 2 different routines, not just one).
Unconfirmed hypothesis: a disabled development hook (debug/sound)
whose real body was overwritten with a `RET` before the final
version, leaving the calls as a vestige. Renamed only in
`madmix1_body.asm` (6 mentions) -- no mentions in
`README.md`/`FLUJO_PROGRAMA.md`/`mapa_memoria.html`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 646 labels (no change in total, a 1:1 rename).

### GH_8882_SKIP -> .SIN_TRABAJO_DE_FRAME (local)

At the developer's request. It's the convergence point inside
`GESTIONAR_FRAME` that `JR NZ` jumps to when `FRAME_FLAG` didn't
confirm a new frame -- skips the whole heavy block
(`ACTUALIZAR_VRAM_FRAME`, actor advance, queue emptying) and falls
straight here for the final call to `FUNCION_INHABIL` and `RET`.
Verified it's only referenced from inside `GESTIONAR_FRAME` (the
only call, in the same routine) -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 645 labels (down 1, the known global->local quirk).

### 2 hex-not-substituted fixed: $8430 -> FRAME_FLAG

At the developer's request, the same usual systemic pattern. Located
and fixed the 2 real sites still using `$8430` in hex inside
`GESTIONAR_FRAME` (`LD A,($8430)` / `LD ($8430),A`) despite
coinciding with `FRAME_FLAG`'s exact start. Line 27
(`DS $8430-$, $00`, the padding right BEFORE `FRAME_FLAG`) was
deliberately left in hex -- it can't reference the very label it
defines at that same point.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Commented FUNCION_INHABIL's 4 no-effect parameters

At the developer's request, added a comment on each of the 4
`LD A,$0F/$01/$01/$06` lines preceding a call to `FUNCION_INHABIL` (3
in `GESTIONAR_FRAME`, 1 in `ACTUALIZAR_VRAM_FRAME`), making it
explicit that the loaded value has no effect because
`FUNCION_INHABIL`'s body is just `RET`. Comment-only change, zero
byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### 1 hex-not-substituted fixed: $8CFF -> QUEUE_INIT_CHECK

At the developer's request, the same usual systemic pattern. The
real routine behind the old "mysterious" call `CALL $8CFF` inside
`GESTIONAR_FRAME` was already identified further down in the file as
`QUEUE_INIT_CHECK` (empties the deferred-redraw queue every frame),
but the `CALL` was still in hex, as was `GESTIONAR_FRAME`'s header
comment mentioning it as "not yet identified" (already outdated,
fixed along the way). Also synced `src/FLUJO_PROGRAMA.md` (1
mention, §5.9). `src/README.md` line 573 left untouched -- it's the
same already-frozen session-history paragraph identified in the
`ISR` round.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### QUEUE_INIT_CHECK -> VACIAR_COLA_REDIBUJADO

At the developer's request. The previous name ("startup check") fell
short: the routine doesn't just check, it walks and fully empties the
circular queue of tiles pending redraw (filled by `QUEUE_PUSH`),
calling `REDIBUJAR_LOSETA_BUFFER_VRAM` for each entry until the `$FF`
sentinel. Renamed in `madmix1_body.asm` (5 mentions),
`src/FLUJO_PROGRAMA.md` (2 mentions) and `recursos/mapa_memoria.html`
(1 mention). Also added a comment at the call site (inside
`GESTIONAR_FRAME`) explaining the functionality.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 645 labels (no change in total, a 1:1 rename; the
function/unreferenced subtotals each shifted by 1 from heuristic
reclassification, not from labels being lost/created).

### GH_888A_VDPOUT -> FIJAR_COLOR_BORDE_VDP

At the developer's request. Sets the VDP's (TMS9918) register 7 --
border/background color -- to A's value: `OUT ($99),A` (data)
followed by `LD A,$87` / `OUT ($99),A` (register number with the
write-mode bit set). Defined in `madmix1_body.asm` but called
exclusively from `madmix_scr_body.asm` (2 sites) -- confirmed it
stays global. Named by function (what it does) instead of a generic
mechanism name ("VDPOUT").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 645 labels (no change in total, a 1:1 rename).

### New label: $8888 -> ULTIMO_ICONO_HUD_CACHEADO

At the developer's request. `$8888` had no label -- it fell right on
the padding byte (previously transcribed as `NOP`, same value `$00`)
right after `.SIN_TRABAJO_DE_FRAME`'s `RET` inside `GESTIONAR_FRAME`.
Turns out to be a real 1-byte variable shared between the 2 files: it
caches the last level icon drawn on the HUD -- `ACTUALIZAR_VRAM_FRAME`
(madmix1_body.asm) compares it every frame against
`REGISTRO_NIVEL_ICONO_HUD` to decide whether a redraw is needed
(unless `FLAG_NIVEL_RECIEN_CARGADO` forces the redraw), and
`APLICAR_COLOR_PANTALLA` (madmix_scr_body.asm) resets it to 0 when
applying the screen color palette (level load). Converted the `NOP`
into `DB $00` with the label -- the exact same byte, better
represents its real nature as data, not dead instruction. Substituted
the 2 real use sites (`madmix1_body.asm` and `madmix_scr_body.asm`)
that used `$8888` in raw hex.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- identical byte
confirmed between `NOP` and `DB $00`. `.dsk`/`.cas` regenerated. HTML
inventory regenerated: 646 labels (up 1, new label, `dato`/data
category).

### GH_88A4 -> .REDIBUJAR_ICONO_HUD (local)

At the developer's request. It's the branch of `ACTUALIZAR_VRAM_FRAME`
that updates `ULTIMO_ICONO_HUD_CACHEADO` and repaints the icon's VRAM
zone (an 18-fill loop via `FILVRM` from `$2220`) -- reached here if
`FLAG_NIVEL_RECIEN_CARGADO` forces the redraw, or by natural fall-
through when the comparison against the cache indicates the icon
changed. Verified it's only referenced from inside
`ACTUALIZAR_VRAM_FRAME` -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 645 labels (down 1, the known global->local quirk).

### RESOLVED: LOOKUP_8978/DIRBITS_TABLE were VDP color, not addresses -- renamed

At the developer's request ("this needs to be analyzed to know what
it really is"). `LOOKUP_8978`'s earlier header-comment hypothesis
("movement decision table, ghost AI?") was wrong. The proof was
already in the code, just unconnected: `OBTENER_COLOR_VDP`
(madmix_scr_body.asm, `$6484`) has a comment explicitly stating it
composes 2 lookups into the same table to translate a byte into a
full SCREEN2 VDP color (high nibble = ink, low nibble = paper). Also
confirmed the addresses in the names were swapped: the ROUTINE is at
`$8961` (not `$8978` as "LOOKUP_8978" suggested) and the TABLE is at
`$8978` (so the "8978" in the name actually belonged to the table).
Renamed: `LOOKUP_8978` -> `CONSULTAR_COLOR_VDP` (simple version, low
nibble/background only, used in `ACTUALIZAR_VRAM_FRAME` to paint the
HUD icon and the `COLOR_ACTUAL` zone), `DIRBITS_TABLE` ->
`TABLA_COLORES_VDP` (16 VDP colors 0-15, not address bits). Fixed the
outdated header comment. Along the way, substituted the 2 real sites
using `CALL $8961` in hex (`madmix1_body.asm`) and the 2 using
`LD HL,$8978` (`madmix_scr_body.asm`, inside `OBTENER_COLOR_VDP`) --
same usual systemic pattern. Synced `src/FLUJO_PROGRAMA.md`,
`recursos/mapa_memoria.html` and `recursos/graficos.html` (the
latter, though not one of the usual 2 synced HTML files, referenced
the exact name in prose and in a JS comment). `src/README.md` line
545 left untouched -- another already-frozen session-history
paragraph (it also mentions `TAIL_TILE_LOOKUP`, an even older name
for `OBTENER_COLOR_VDP`, left unsynced).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 645 labels (no change in total, a 1:1 rename; subtotals
shifted from heuristic reclassification).

### GH_88BC -> .SIN_CAMBIO_ICONO_HUD (local), GH_88AD -> .BUCLE_RELLENO_ICONO_HUD (local)

At the developer's request. `GH_88BC` is the twin branch of
`.REDIBUJAR_ICONO_HUD` inside `ACTUALIZAR_VRAM_FRAME`: taken when the
HUD icon did NOT change, does a 1323-byte `LDIR` from `$4000` onto
itself (same source and destination -- doesn't change memory, just
burns cycles, an apparent timing filler to match this branch's
duration to the real-redraw one) and a dead call to
`FUNCION_INHABIL`, before converging into the common code.

While renaming `GH_88BC` to local, a compile error appeared ("Label
not found") from the same scoping trap already documented earlier
this session: `GH_88AD` (a global label) fell in between, breaking
the local-scope chain. Fixed by also converting `GH_88AD` to local
(`.BUCLE_RELLENO_ICONO_HUD`, the 18-fill VRAM loop via `FILVRM`) --
verified it was only referenced from inside the same routine.

**Verified**: recompiled with no errors after the scoping fix, diffs
at the exact usual baseline (7/2). `.dsk`/`.cas` regenerated. HTML
inventory regenerated: 643 labels (down 2, two global->local
conversions).

### $00C0 -> 192 (decimal)

At the developer's request. It's the BC (length) parameter of the
`FILVRM` call inside `.BUCLE_RELLENO_ICONO_HUD` -- a byte count, not
an address or a mask, fits the already-established policy of decimal
for counts.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Commented the 10 calls to FILVRM

At the developer's request, added a comment at each of the 10 sites
that do `CALL FILVRM` (5 in `madmix1_body.asm`, 5 in
`madmix_scr_body.asm`) noting that it's the equivalent of the
same-named MSX BIOS routine. Comment-only change, zero byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### GH_88CB -> .APLICAR_COLOR_Y_SCROLL_VRAM (local)

At the developer's request. It's the convergence point inside
`ACTUALIZAR_VRAM_FRAME` where the HUD icon's 2 branches
(`.REDIBUJAR_ICONO_HUD`/`.SIN_CAMBIO_ICONO_HUD`) fall to -- work that
happens EVERY frame unconditionally: refreshes 2 VRAM color zones
(`$2A80`/`$2B80`) from `COLOR_ACTUAL` via `CONSULTAR_COLOR_VDP`, and
flushes the `$DE04` work buffer to VRAM `$0220` (the same buffer the
`SCROLL_*` routines shift) -- it's the part that actually applies the
maze scroll to the screen every frame. Verified it's only referenced
from inside `ACTUALIZAR_VRAM_FRAME` -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 642 labels (down 1, the known global->local quirk).

### Comments clarifying $2220 (real VRAM) vs $4000 (Z80 memory, not VRAM)

At the developer's request. `$2220` (in `.REDIBUJAR_ICONO_HUD`) is a
real VRAM address -- passed as `HL` to `FILVRM`, which only writes
VRAM via port `$98`. `$4000` (in `.SIN_CAMBIO_ICONO_HUD`) is NOT VRAM
-- used directly with `LDIR` (normal Z80 memory access, not going
through `FILVRM`/`SETVRAM`), a Z80 memory-space address used only as
filler for the already-documented timing `LDIR`. Added a comment on
each line clarifying the difference. Comment-only change, zero byte
change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### UNRESOLVED MYSTERY: $052B (1323) in .SIN_CAMBIO_ICONO_HUD -- the timing hypothesis DISCARDED

The developer distrusted the value `$052B` (1323, the fill `LDIR`'s
counter over `$4000`). An approximate cycle count to compare
`ACTUALIZAR_VRAM_FRAME`'s two branches: `.REDIBUJAR_ICONO_HUD` (18x
`FILVRM` of 192 bytes, just the inner `OUT/DEC/JR NZ` loop ~28
cycles/byte) ≈ 97000 cycles; `.SIN_CAMBIO_ICONO_HUD` (`LDIR` with
BC=1323, ~21 cycles/byte) ≈ 27800 cycles. Not even close (~3.5x
difference), so the "filler to match the other branch's timing"
hypothesis (written in an earlier round this same session) is
DISCARDED. Explicitly marked in the code as an unresolved mystery --
no alternative explanation has been found. Comment-only change, zero
byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### 4 new VRAM/RAM constants: ZONA_COLOR_VRAM_DESTELLO_A/B, ZONA_PATRON_VRAM_LABERINTO, BUFFER_LOSETAS_TRABAJO

At the developer's request, labeled the addresses of the
`.APLICAR_COLOR_Y_SCROLL_VRAM` block: `$2A80`/`$2B80` (VRAM, 16-byte
color zones for the HUD icon/color sparkle) -> `ZONA_COLOR_VRAM_DESTELLO_A`/
`ZONA_COLOR_VRAM_DESTELLO_B`; `$0220` (VRAM, destination of the
tile-buffer flush) -> `ZONA_PATRON_VRAM_LABERINTO`; `$DE04` (Z80
memory, NOT VRAM -- the tile work buffer) -> `BUFFER_LOSETAS_TRABAJO`.
Since the project had never used `EQU` before (no precedent in any
file), the 4 were defined as constants right BEFORE
`ACTUALIZAR_VRAM_FRAME` (not inside it), to avoid repeating earlier
rounds' scoping trap. Substituted every real site using these values
in raw hex: `$2A80`/`$2B80` (2 sites), `$0220` (1 site), `$DE04` (7
sites: 6 in `madmix1_body.asm`, 1 in `madmix_scr_body.asm`) -- the
same usual systemic pattern, here with new labels instead of
already-existing ones. Also converted to decimal `FILVRM`'s 2 counts
($0010->16) and the scroll loop's row count ($12->18) within the same
block. Synced `ACTUALIZAR_VRAM_FRAME`'s header comments and several
prose entries in `recursos/mapa_memoria.html`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 646 labels (up 4, the 4 new constants).

### GH_88ED -> .BUCLE_FILA_CARACTERES_VRAM (local), GH_88FC -> .BUCLE_COLUMNA_CARACTERES_VRAM (local)

At the developer's request. These are the 2 nested loops that flush
`BUFFER_LOSETAS_TRABAJO` to VRAM at the end of `ACTUALIZAR_VRAM_FRAME`:
they transpose the linear pixel canvas (144 rows x 32 bytes) into the
per-character format SCREEN2's pattern table expects (8 consecutive
bytes = a character's 8 lines). The outer one (`DJNZ`, B=18) walks 18
character rows (8-pixel-line bands); the inner one (`JP NZ`, E=24)
walks each band's 24 columns, reading 8 bytes per column (a 32-byte
jump = one buffer row) and flushing them consecutively to VRAM.
Verified both are only referenced from each other inside
`ACTUALIZAR_VRAM_FRAME` -- converted to local.

**Verified**: recompiled with no errors (no scoping problem this
time), diffs at the exact usual baseline (7/2). `.dsk`/`.cas`
regenerated. HTML inventory regenerated: 644 labels (down 2, two
global->local conversions).

### Commented FILVRM, LDIRVM and SETVRAM's headers

At the developer's request, added a one-line comment on each of the 3
VDP API routines explaining its functionality: `FILVRM` (fills BC
bytes of VRAM from HL with the fixed byte A), `LDIRVM` (copies BC
bytes from RAM HL to VRAM DE, byte by byte) and `SETVRAM` (positions
the VDP's write pointer at HL's VRAM address -- equivalent to the
BIOS's `SETWRT`, confirmed by the port-`$99` write pattern which
matches exactly). Comment-only change, zero byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### Analyzed the 5 unexplained bytes between CONSULTAR_COLOR_VDP and TABLA_COLORES_VDP

At the developer's request, searched for who accesses the 5
`DB $00` bytes falling between `CONSULTAR_COLOR_VDP` (ends at
`$8972`, 18 bytes from `$8961`) and `TABLA_COLORES_VDP` (`$8978`) --
addresses `$8973`-`$8977`. No `JP`/`CALL` nor label arithmetic
referencing them was found in either file. Observed fact: `$8978` is
an exact multiple of 8 -- HYPOTHESIS (real consumer unconfirmed):
padding to align the table to an 8-byte boundary, unlike the
FILVRM/LDIRVM/SETVRAM block above, which sit exactly contiguous with
no gap. Comment on the line updated with this analysis. Comment-only
change, zero byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### ADDR_FROM_DC00 -> CALCULAR_DIRECCION_MASCARA_ACTOR

At the developer's request. Asking about `$DC00` led to locating a
later finding already present in FINDINGS.md that fully resolves the
old "Zone 0xDC00 undeciphered": it's NOT a separate table, it's a
SUB-RANGE of `RLE_TABLE_D6B6` (the candy frame's RLE table) reused
for a second purpose -- memory economy typical of MSX1. This routine
(+ `COMPONER_ACTORES_EN_BUFFER`) accesses that sub-range randomly as
16-bit AND/OR masks to composite sprites against the background.
Renamed to reflect the real purpose (previously it only described the
mechanism, "from DC00"). Header comment rewritten with the full
finding. Renamed in `madmix1_body.asm` (6 mentions), `src/README.md`
(1 mention) and `recursos/mapa_memoria.html` (2 mentions).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 644 labels (no change in total, a 1:1 rename).

### RLE_TABLE_D6B6 -> TABLA_RLE_MARCO_CARAMELO

At the developer's request. Renamed the RLE table that reconstructs
the full VRAM candy frame (870 value/repeat pairs, 1740 bytes,
`$D6B6-$DD82`) -- keeps "RLE" (the real compression format) and adds
the already-visually-confirmed identity (the candy frame), matching
the already-existing data-file name (`marco_caramelo_forma.img`).
Renamed in `madmix1_body.asm` (definition + 3 mentions),
`madmix_scr_body.asm` (2 mentions), `src/README.md` (2 mentions),
`recursos/mapa_memoria.html` (3 mentions, also fixing along the way a
stray `LOOKUP_8978` mention that had slipped through an earlier
round) and `recursos/graficos.html` (2 mentions).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 644 labels (no change in total, a 1:1 rename).

### SD_89BA -> .COMPROBAR_EJE_Y (local)

At the developer's request. It's the convergence point inside
`GESTIONAR_SCROLL` between the direct path (L's 2 low bits, X
sub-pixel, already tile-aligned) and the fall-through path (C is
masked to its 2 low bits before arriving here) -- from here the check
moves to the Y axis (H's 2 low bits) the same way. Verified it's only
referenced from inside `GESTIONAR_SCROLL` -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 643 labels (down 1, the known global->local quirk).

### SD_89C2 -> .DECIDIR_DIRECCION_SCROLL (local)

At the developer's request. It's `.COMPROBAR_EJE_Y`'s twin but for
the already-resolved Y axis: the direct path (H's 2 low bits, Y
sub-pixel, already tile-aligned) and the fall-through path (`AND
$0C` on C, bits 2-3) converge here. From here the final 4-step
`RRA`/`JP C,...` cascade starts, deciding SCROLL_UP/DOWN/LR (or
none). Verified it's only referenced from inside `GESTIONAR_SCROLL`
-- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 642 labels (down 1, the known global->local quirk).

### SCROLL_UP -> SCROLL_ARRIBA, SCROLL_DOWN -> SCROLL_ABAJO

At the developer's request, translated the 2 vertical-scroll routines
to Spanish (the lateral one, `SCROLL_LR`, was left as-is -- no change
was requested for it). Renamed in `madmix1_body.asm` (definitions +
mentions in comments/calls) and in `recursos/mapa_memoria.html` (2
entries, including a prose shorthand "SCROLL_UP/DOWN/LR" rewritten to
the full form for clarity).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 642 labels (no change in total, a 1:1 rename).

### SCROLL_LR turned out to be 2 distinct routines: SCROLL_DERECHA (already labeled) and SCROLL_IZQUIERDA (new, previously unnamed)

At the developer's request ("analyze it in depth"). `GESTIONAR_SCROLL`'s
4-bit cascade (`RRA`/`JP C,...`) wasn't choosing among 3 routines but
among 4: `SCROLL_ARRIBA`, `SCROLL_ABAJO`, the old `SCROLL_LR`
(labeled, reached by `JP C`), and a FOURTH block **with no label**,
reached only by fall-through when the final `RET NC` doesn't return
(carry set on the 4th rotation). Both blocks share the
`SLR_800A_TAIL` tail (a 140-iteration loop of 24 `LDI` each, opposite
directions via `BC=$FFE0`/`-32` vs `BC=$0020`/`+32`) and differ in
one flag (`A=$FF`/`-1` vs `A=$01`/`+1`) that, at the loop's end, gets
ADDED directly to `REGISTRO_NIVEL_POSICION_COMECOCOS` (`ADD A,H`/`LD
H,A`). Medium-high confidence HYPOTHESIS (assuming the standard
convention of X increasing to the right, unconfirmed live): adding +1
moves the camera right, subtracting 1 moves it left. Renamed:
`SCROLL_LR` (already labeled, +1 flag) -> `SCROLL_DERECHA`; the
unnamed block (-1 flag) -> new label `SCROLL_IZQUIERDA`. Header
comments updated with the hypothesis and its confidence level. Synced
`madmix_scr_body.asm` (1 mention) and `recursos/mapa_memoria.html` (2
entries).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 643 labels (up 1, the new SCROLL_IZQUIERDA label).

### SCROLL_LR_PARAM -> PARAMETRO_DESPLAZAMIENTO_SCROLL

At the developer's request. The previous name suggested exclusive use
by the lateral routines, but it's actually written by all 4
directions (`SCROLL_IZQUIERDA=$0400`, `SCROLL_DERECHA=$FC00`,
`SCROLL_ABAJO=$0004`, `SCROLL_ARRIBA=$00FC`) as a packed 4px (dx,dy)
delta (H=horizontal axis, L=vertical axis, the other always 0), later
read by 2 consumers (`DE=(PARAMETRO_DESPLAZAMIENTO_SCROLL)`) at the
end of their respective redraw loops. A fact reinforcing the previous
round's LEFT/RIGHT hypothesis: this parameter's signs (+4 LEFT / -4
RIGHT) are opposite to the direct adjustment of
`REGISTRO_NIVEL_POSICION_COMECOCOS` (-1/+1) -- the physically expected
relationship between "which way the camera moves" and "which way the
redrawn content shifts". Renamed in `madmix1_body.asm` (6 mentions),
`madmix_scr_body.asm` (definition + 1 mention) and
`recursos/mapa_memoria.html` (1 mention).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 643 labels (no change in total, a 1:1 rename).

### SLR_800A_TAIL -> APLICAR_DESPLAZAMIENTO_LATERAL

At the developer's request. It's the tail shared between
`SCROLL_IZQUIERDA` and `SCROLL_DERECHA`: copies 24 of every 32 bytes
per row (140 rows, via `BC` as a -32/+32 step between passes) of the
`BUFFER_LOSETAS_TRABAJO` canvas, and on finishing adds the +1/-1 flag
to `REGISTRO_NIVEL_POSICION_COMECOCOS`. Left global (referenced from
2 different global routines, not nested inside just one). Only in
`madmix1_body.asm` (4 mentions) -- no mentions in other live files.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 643 labels (no change in total, a 1:1 rename).

### SLR_LOOP -> .BUCLE_FILA_DESPLAZAMIENTO (local)

At the developer's request. It's the body of the 140-iteration loop
inside `APLICAR_DESPLAZAMIENTO_LATERAL`: for each row, copies 24
bytes (24 consecutive `LDI`) and advances `HL`/`DE` by the row step.
Verified it's only referenced from inside the same routine --
converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 642 labels (down 1, the known global->local quirk).

### SDOWN_OUTER -> .BUCLE_FILA_SCROLL_ABAJO (local), SDOWN_INNER -> .BUCLE_NIBBLE_SCROLL_ABAJO (local)

At the developer's request. These are `SCROLL_ABAJO`'s 2 nested
loops: the outer one walks the canvas's 144 rows; the inner one does
24 `RRD` per row (with `INC L` between each) -- the classic Z80 trick
of chaining `RRD` across consecutive bytes using `A` as a "carry
nibble" to propagate a 1-nibble shift (the fine 4px scroll already
documented in `GESTIONAR_SCROLL`'s header comment). Renaming the
outer one triggered the same usual scoping trap (`SDOWN_INNER` global
in between) -- fixed by also converting the inner one to local.
Verified both are only referenced from each other inside
`SCROLL_ABAJO`.

**Verified**: recompiled with no errors (after the scoping fix),
diffs at the exact usual baseline (7/2). `.dsk`/`.cas` regenerated.
HTML inventory regenerated: 640 labels (down 2, two global->local
conversions).

### SUP_OUTER -> .BUCLE_FILA_SCROLL_ARRIBA (local), SUP_INNER -> .BUCLE_NIBBLE_SCROLL_ARRIBA (local)

At the developer's request. Twins of `SCROLL_ABAJO`'s but for
`SCROLL_ARRIBA`: use `RLD`/`DEC L` (instead of `RRD`/`INC L`) --
walk the row in the opposite direction and rotate nibbles the other
way, consistent with being the opposite direction. Same naming
pattern and same usual scoping trap (`SUP_INNER` global in between
while renaming the outer one) -- fixed by also converting the inner
one to local. Verified both are only referenced from each other
inside `SCROLL_ARRIBA`.

**Verified**: recompiled with no errors (after the scoping fix),
diffs at the exact usual baseline (7/2). `.dsk`/`.cas` regenerated.
HTML inventory regenerated: 638 labels (down 2, two global->local
conversions).

### Commented SCROLL_ARRIBA/SCROLL_ABAJO's 4 loop labels

At the developer's request, added a one-line comment on each of the 4
loop labels explaining its functionality
(`.BUCLE_FILA_SCROLL_ABAJO`/`.BUCLE_NIBBLE_SCROLL_ABAJO`/
`.BUCLE_FILA_SCROLL_ARRIBA`/`.BUCLE_NIBBLE_SCROLL_ARRIBA`).
**Self-corrected an own mistake during editing**: the first attempt
to comment `.BUCLE_NIBBLE_SCROLL_ARRIBA` accidentally deleted the
`RLD` instruction that followed the label (the Edit's `old_string`
didn't include that line in the replacement). Caught and fixed before
recompiling, re-verified with diffs at the exact usual baseline (7/2)
to confirm no byte ended up shifted.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### Commented the SCROLL_ARRIBA/SCROLL_ABAJO labels

At the developer's request, added a one-line comment on each of the 2
labels summarizing its full functionality (shifts the canvas 4px in
its direction, 144 rows x 24 RRD/RLD chained per row, updates
`PARAMETRO_DESPLAZAMIENTO_SCROLL`/`REGISTRO_NIVEL_POSICION_COMECOCOS`).
Comment-only change, zero byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### $0020 -> 32 (decimal) in SCROLL_ABAJO/SCROLL_ARRIBA, plus comment

At the developer's request. It's the row step for the
`BUFFER_LOSETAS_TRABAJO` canvas (`LD DE,...` before the `.BUCLE_FILA_*`
loops) -- a count/step, not an address or mask, fits the already-
established policy of decimal for counts. Applied consistently in
both routines (`SCROLL_ABAJO` and `SCROLL_ARRIBA` use the same value
for the same purpose). Also added a comment at each site noting what
the value is.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated (no label changes,
`gen_inventory.py` doesn't apply).

### Analyzed and commented SCROLL_ARRIBA's setup block; $DE1B turned out to be BUFFER_LOSETAS_TRABAJO+23

At the developer's request. Analyzed `SCROLL_ARRIBA`'s 8 setup lines
(packed delta, `EXX`+C/D as phase constants consumed in
`SCROLL_LOSETA_BUFFER_VRAM` via `ADD A,C`/`XOR D` to choose
`SCOPY_A`/`SCOPY_B`, signed direction flag `+1`). Finding: `$DE1B`
wasn't a loose address -- it's exactly
`BUFFER_LOSETAS_TRABAJO+23` (the end of the 24-byte playable row;
`SCROLL_ARRIBA` walks each row backward with `DEC L`, opposite to
`SCROLL_ABAJO`). Fixed to the label+offset form -- the same usual
"hex not substituted" systemic pattern, here with label arithmetic
instead of direct substitution. Confirmed along the way: in
`SCROLL_LOSETA_BUFFER_VRAM` the direction flag is added to
`REGISTRO_NIVEL_POSICION_COMECOCOS.L` (not `.H` as in the lateral
scroll) -- consistent with `L`=vertical axis, `H`=horizontal axis in
that variable. `$00FC`/`$2F`/`$0F`/`$01` were left in hex (signed
deltas and mask/phase constants, not pure counts) with a comment
explaining each one.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`BUFFER_LOSETAS_TRABAJO+23` compiles byte-identical to `$DE1B`.
`.dsk`/`.cas` regenerated (no label changes, `gen_inventory.py`
doesn't apply).

### $90 -> 144 and $02 -> 2 (decimal) in SCROLL_ARRIBA/SCROLL_ABAJO's loops, plus comments

At the developer's request. `LD C,$90` (the outer loop's counter, 144
rows) and `LD B,$02` (the inner loop's counter, 2 passes x 12
RRD-or-RLD/INC-or-DEC L pairs = 24 per row) are pure counts --
converted to decimal per the already-established policy. Applied in
both routines (`SCROLL_ABAJO` and `SCROLL_ARRIBA`) for consistency.
Also added a comment on both blocks' `PUSH HL` and `XOR A`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Commented SCROLL_ABAJO's setup block (SCROLL_ARRIBA's twin)

At the developer's request. Same analysis as `SCROLL_ARRIBA`'s block:
no value is a pure count (signed packed delta `$0004`, phase
constants `$00`/`$F0`, signed direction flag `$FF`) -- left in hex,
with a comment on each one. `LD HL,BUFFER_LOSETAS_TRABAJO` already
used the label (it's the start of the playable row, opposite sense
from `SCROLL_ARRIBA`'s `+23`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Analyzed and commented SCROLL_DERECHA's setup block + APLICAR_DESPLAZAMIENTO_LATERAL's counter

At the developer's request. Finding: `$EF84` wasn't a loose address
-- it's exactly `BUFFER_LOSETAS_TRABAJO+4480` (row 140 of the canvas,
4480/32=140). Fixed to the label+offset form, the same usual systemic
pattern. Converted to decimal `$0020`->32 (row step, pure count) and
`$8C`->140 (the outer loop counter of
`APLICAR_DESPLAZAMIENTO_LATERAL`, shared by `SCROLL_IZQUIERDA` and
`SCROLL_DERECHA`). The rest (`$FC00` signed packed delta, `$23` a not-
fully-confirmed adjustment constant, `$01` signed direction flag) stay
in hex, with a comment on each one, consistent with the rest of the
scroll blocks.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`BUFFER_LOSETAS_TRABAJO+4480` compiles byte-identical to `$EF84`.
`.dsk`/`.cas` regenerated (no label changes, `gen_inventory.py`
doesn't apply).

### Commented all of GESTIONAR_SCROLL + SCROLL_IZQUIERDA's setup block

At the developer's request. Commented every line of
`GESTIONAR_SCROLL` (reading the camera position, saving the input
parameter, the 2 low-bit L/H checks, the final RRA/JP C cascade, and
the RET NC). In `SCROLL_IZQUIERDA`'s block, the same treatment as its
twin `SCROLL_DERECHA`: `$FFE0` -> `-32` (the same row step as
`SCROLL_DERECHA` but in the opposite direction, compiles identically
in two's complement) and `$EFE4` -> `BUFFER_LOSETAS_TRABAJO+4576` (row
143, the canvas's last one, 4576/32=143) -- fixed to label+offset,
the same usual systemic pattern. The rest (`$0400` delta, `$00`
adjustment constant, `$FF` direction flag) stay in hex with a
comment, same as in the twin blocks.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`LD BC,-32` and `BUFFER_LOSETAS_TRABAJO+4576` compile byte-identical
to `$FFE0`/`$EFE4`. `.dsk`/`.cas` regenerated (no label changes,
`gen_inventory.py` doesn't apply).

### SCOPY_A_ENTRY -> COPIAR_LOSETA_FASE_A, SCOPY_B_ENTRY -> COPIAR_LOSETA_FASE_B

At the developer's request. These are the 2 alternate entry points
`STAIL_LOOP` (inside `SCROLL_LOSETA_BUFFER_VRAM`) jumps to via
`JP (IX)`, chosen by a 1-bit parity test
(`(new L + shadow C) XOR shadow D) AND 1`, using the phase constants
already commented earlier). Confirmed: this mechanism is specific to
VERTICAL scroll (`SCROLL_ARRIBA`/`SCROLL_ABAJO`) -- the lateral one
(`SCROLL_IZQUIERDA`/`SCROLL_DERECHA`) ends in a different routine
(`DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) that never passes through here,
fixing an inaccuracy `recursos/mapa_memoria.html` had ("all 4 converge
in SCROLL_LOSETA_BUFFER_VRAM"). Difference between the 2 phases: A
does an extra `EX DE,HL` that B doesn't -- not-fully-confirmed
HYPOTHESIS: compensates an odd/even byte alignment when crossing a
tile boundary (16px = 4 steps of 4px scroll, but the 1-bit test only
distinguishes 2 possibilities, not 4). Kept GLOBAL (not local) to
avoid repeating the already-seen scoping trap -- the
`STAIL_DISPATCH`/`STAIL_LOOP`/`STAIL_RESUME` labels fall in between
the definition and weren't touched. Synced `recursos/mapa_memoria.html`
(1 mention, also fixing the paragraph's inaccuracy along the way).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 638 labels (no change in total, a 1:1 rename).

### STAIL_DISPATCH -> .PREPARAR_BUCLE_LOSETAS (local)

At the developer's request. It's the convergence point inside
`SCROLL_LOSETA_BUFFER_VRAM` between the 2 phase-selection branches
(direct `JR Z` for phase A, fall-through for phase B): sets up `IY`
(return), retrieves the pointer (`POP DE`) and sets the outer loop's
counter (`C`/`B=9`) before entering `STAIL_LOOP`. Verified it's only
referenced from inside `SCROLL_LOSETA_BUFFER_VRAM`, with no global
label in between -- converted to local with no scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 637 labels (down 1, the known global->local quirk).

### Commented .PREPARAR_BUCLE_LOSETAS, $09 -> 9 (decimal)

At the developer's request. Added a comment on every line of the
block (the phases' return point, D transfer between register banks,
retrieving the row pointer, the loop's counter). The only pure count
(`$09`, `STAIL_LOOP`'s outer-loop iterations -- 9 tiles) was
converted to decimal; the rest are register/address transfers with no
applicable conversion.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### Commented SCROLL_LOSETA_BUFFER_VRAM's header

At the developer's request. Added a comment on every line of the
initial block: register-bank switch, reading/updating the camera
position with the direction flag, and the 1-bit phase test
(`ADD A,C`/`XOR D`/`AND $01`) that decides `COPIAR_LOSETA_FASE_A`
vs `COPIAR_LOSETA_FASE_B`. No value was convertible to decimal
(`AND $01` is a bitmask). `RES 0,H` was left marked as unconfirmed
purpose.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### STAIL_LOOP -> .BUCLE_LOSETAS (local), STAIL_RESUME -> .CONTINUAR_BUCLE_LOSETAS (local)

At the developer's request. `.BUCLE_LOSETAS` is the start of the
9-tile loop inside `SCROLL_LOSETA_BUFFER_VRAM`: for each one, computes
its graphic address (`MAPEAR_LOSETA_A_GRAFICO`) and dispatches to the
chosen phase (`JP (IX)`). `.CONTINUAR_BUCLE_LOSETAS` is where that
phase returns to when finished (`JP (IY)`): undoes the DE/HL swap,
advances the index in the alternate bank (+4) and repeats (`DJNZ`)
until the counter runs out; on exit, reloads
`PARAMETRO_DESPLAZAMIENTO_SCROLL` into `DE` and `RET`s. The same usual
scoping trap while renaming `STAIL_RESUME` (with `STAIL_LOOP` global
in between) -- fixed by also converting `STAIL_LOOP` to local.
Verified both are only referenced from each other inside
`SCROLL_LOSETA_BUFFER_VRAM`.

**Verified**: recompiled with no errors (after the scoping fix),
diffs at the exact usual baseline (7/2). `.dsk`/`.cas` regenerated.
HTML inventory regenerated: 635 labels (down 2, two global->local
conversions).

### SCOPY_A -> .BUCLE_COPIAR_LOSETA_FASE_A (local), SCOPY_B -> .BUCLE_COPIAR_LOSETA_FASE_B (local)

At the developer's request. These are the inner loops (4 passes each)
inside `COPIAR_LOSETA_FASE_A`/`COPIAR_LOSETA_FASE_B`: the real body
that copies the new tile's bytes. `.BUCLE_COPIAR_LOSETA_FASE_A` does
4x4=16 `LDI` (direct copy, row step `B=32` between each, 16 bytes = a
16x16px tile). `.BUCLE_COPIAR_LOSETA_FASE_B` does the same number of
passes but with `LD A,(DE)` + 4x `RRCA` + `AND C` + `OR (HL)` +
`LD (HL),A` -- a nibble-level mix with the already-existing content,
instead of a direct copy, consistent with the hypothesis that phase B
compensates for a byte misalignment phase A doesn't have. Verified
both are only referenced inside their respective routine -- converted
to local with no scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 633 labels (down 2, two global->local conversions).

### Commented and converted to decimal the whole .BUCLE_LOSETAS/COPIAR_LOSETA_FASE_A/B block

At the developer's request. Converted the pure counts to decimal:
`$04` (index-advance step, and both phases' pass counter) -> `4`;
`$20` (step between source rows) -> `32`; `$00` in `ADC A,$00` (carry
propagation, x2) -> `0`. `$FF` (mask used with `AND C`) was left in
hex. Added a comment on every line with a relevant value or purpose;
since `COPIAR_LOSETA_FASE_B` repeats an identical 13-instruction group
4 times, only the first occurrence of each repeated pattern was
commented instead of all 4 separately.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated (no label changes,
`gen_inventory.py` doesn't apply).

### TAC_TAIL -> .RESTAURAR_Y_SALIR (local)

At the developer's request. It's `MAPEAR_LOSETA_A_GRAFICO`'s common
epilogue: pops the 4 registers saved at the start (`HL`/`BC`/`DE`/`AF`)
and returns. Reached both by a direct jump (B's bit 7 clear) and by
fall-through (bit 7 set, after writing to `TABLA_TIPOS_LOSETA`).
Side finding: an `AND $00` right before it completely nullifies the
`(HL)` read, likely a vestige of a more complex check simplified at
some point -- documented in the code. Verified it's only referenced
from inside `MAPEAR_LOSETA_A_GRAFICO` -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 632 labels (down 1, the known global->local quirk).

### Commented and converted to decimal all of MAPEAR_LOSETA_A_GRAFICO; $B940 -> TILE_GFX

At the developer's request. Finding: `$B940` (the base added to the
computed graphic address) already had a real label (`TILE_GFX`) not
yet substituted -- the same usual systemic pattern. Converted to
decimal the values that weren't masks: `LD L,$00`->`0` (seed of the
index computation, not an address), `LD A,$02`->`2` (a state/mode
value written to `$8435`), `ADC A,$00`->`0` (carry propagation),
`LD B,$10`->`16`. A curious finding about the last one: `B` is never
read again between that assignment and `.RESTAURAR_Y_SALIR`'s final
`POP BC` -- it appears to have no observable effect (similar in
spirit to `FUNCION_INHABIL`'s no-effect parameters, documented in the
code). Added a comment on every line. The masks (`$7C` x2, `$7F`,
`$03`, `$3F`, `$80`, the `$00` in the already-documented degenerate
`AND`) stayed in hex.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`TILE_GFX` compiles byte-identical to `$B940`. `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### JS9_LOOP1 -> .BUCLE_REDIBUJADO_CAMARA (local)

At the developer's request. It's
`REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`'s main loop: 36 passes
(`B=$24`), one per camera strip, for the TOTAL (not incremental)
redraw -- calls `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` per pass and
advances the destination (128 bytes) and alternate-bank (`INC H`)
pointers. Verified it's only referenced inside the same routine (plus
2 mentions in comments, also synced) -- converted to local with no
scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 631 labels (down 1, the known global->local quirk).

### JS9_LOOP2 -> .BUCLE_ICONOS_VIDA (local)

At the developer's request. Draws the life icon once for each
remaining life (`B=VIDAS_RESTANTES`): 2 16-byte bands per icon
(`CALL JS9_ROWFLIP` x2) and advances 24px (`$18`) between icons.
Verified it's only referenced inside the same routine (plus 2
mentions in comments, synced) -- converted to local with no scoping
problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 630 labels (down 1, the known global->local quirk).

### JS9_ROWFLIP -> LDIRVM_INVERTIDO

At the developer's request. Flushes BC bytes from HL to VRAM
(destination DE, via SETVRAM) inverting each byte (CPL) before
writing it -- an inverted variant of LDIRVM, the same "inverted mode"
`TEXT_BLIT` uses elsewhere (exact reason unconfirmed: reusing
graphic data with 2 appearances, or a deliberate visual effect).
Left global (follows the same pattern as FILVRM/LDIRVM/SETVRAM, the
"VDP API"). Also renamed `JS9_ROWFLIP_LOOP` -> `LDIRVM_INVERTIDO_LOOP`
(caught by the same replacement, no scoping problem since it's its
only reference). Synced comments that said "negated mode" ->
"inverted mode" for terminology consistency.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 630 labels (no change in total, a 1:1 rename).

### Commented and converted to decimal the rest of REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM, MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA and CONSULTAR_TIPO_LOSETA

At the developer's request. Finding: `$8DE9` already had a real label
(`SCORE_DIGIT_BUFFER`) not yet substituted -- the same usual systemic
pattern; also `$8DEA` -> `SCORE_DIGIT_BUFFER+1`. Confirmed that
`LD D,$16`/`LD E,$48` (in `.BUCLE_ICONOS_VIDA`) form the same VRAM
address `$1648` used right before for the `FILVRM` fill -- the fill
prepares the zone where the icons are later drawn. Converted the pure
counts to decimal: `$24`->`36` (camera strips), `$0080`->`128`
(destination step), `$0060`->`96` (x2, FILVRM fill), `$0010`->`16`
(x2, icon bands), `$18`->`24` (horizontal step between icons),
`$0005`->`5` (digit copy), the `$00` in `ADC A,$00` (x2, in
`CONSULTAR_TIPO_LOSETA`) ->`0`. `LD HL,$0000`
(`DIBUJAR_MARCADOR_PUNTOS`'s parameter) ->`0`. Left in hex: the
addresses (`$1648`, `$92C3`, `$FC50`) and the masks (`AND $7C` x2,
`AND $7F`, `AND $1F`, `LD A,$FF`/`LD (HL),$30` as byte values, not
counts). Added a comment on every relevant line across the 3
routines.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`SCORE_DIGIT_BUFFER`/`SCORE_DIGIT_BUFFER+1` compile byte-identical to
`$8DE9`/`$8DEA`. `.dsk`/`.cas` regenerated (no label changes,
`gen_inventory.py` doesn't apply).

### QUEUE_PUSH -> APILAR_PETICION_REDIBUJADO

At the developer's request. Pushes an entry (C,B,A) into the deferred-
redraw circular queue ($8D61-$8D6F, sentinel $FF) via the write
pointer $8D5F. Left global -- confirmed it's called from 2 real sites
in `madmix_scr_body.asm` (HNDLR_MARICOCO/HNDLR_REGPUNANTOSO, when
regenerating an already-eaten pellet). Renamed to use the same
Spanish terminology as its counterpart `VACIAR_COLA_REDIBUJADO`.
Synced in `madmix1_body.asm` (definition + 2 mentions in comments)
and `madmix_scr_body.asm` (2 calls + 2 mentions in comments).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 630 labels (no change in total, a 1:1 rename).

### QIC_LOOP -> .BUCLE_VACIAR_COLA (local), QUEUE_POP_DISPATCH -> .DESPACHAR_ENTRADA_COLA (local)

At the developer's request. `.BUCLE_VACIAR_COLA` walks the deferred-
redraw circular queue from `$8D61` to the `$FF` sentinel, resetting
the write pointer on reaching the end. `.DESPACHAR_ENTRADA_COLA` is
where it falls if there's a real entry: interprets the next 3 bytes
as `(C,B,A)` and calls `REDIBUJAR_LOSETA_BUFFER_VRAM`. The same usual
scoping trap while renaming the outer loop (`QUEUE_POP_DISPATCH`
global in between) -- fixed by also converting this one to local.
Synced `src/FLUJO_PROGRAMA.md` and `recursos/mapa_memoria.html` (the
latter also used to fix a stray `QUEUE_PUSH` mention that had slipped
through the previous round).

**Verified**: recompiled with no errors (after the scoping fix),
diffs at the exact usual baseline (7/2). `.dsk`/`.cas` regenerated.
HTML inventory regenerated: 628 labels (down 2, two global->local
conversions).

### RS_LOOP -> .BUCLE_FILA_LOSETA (local)

At the developer's request. It's `REDIBUJAR_LOSETA_BUFFER_VRAM`'s
main loop ("RS" was left over from the old name `REDRAW_STRIP`,
already renamed): 16 rows, copying 2 bytes per row (`LDI` x2 from
`TILE_GFX`) and advancing the destination 30 bytes (which, added to
the 2 already copied, gives 32, the canvas's row width). Verified
it's only referenced inside the same routine -- converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 627 labels (down 1, the known global->local quirk).

### Commented and converted to decimal APILAR_PETICION_REDIBUJADO/VACIAR_COLA_REDIBUJADO/REDIBUJAR_LOSETA_BUFFER_VRAM; $B940 -> TILE_GFX

At the developer's request. Finding: `$B940` (tile graphic base)
again not substituted with the real label `TILE_GFX` -- the same
systemic pattern already seen several times this session. Converted
the pure counts to decimal: `LD L,$00`->`0` (computation seed, not
an address), `LD B,$10`->`16` (tile rows), `LD BC,$001E`->`30`
(destination step). Left in hex: the queue's addresses/pointers
(`$8D5F`, `$8D61`), the `$FF` sentinel and the masks (`AND $03`,
`AND $02`, `AND $7F`). Added a comment on every relevant line across
the 3 routines.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) -- confirms
`TILE_GFX` compiles byte-identical to `$B940`. `.dsk`/`.cas`
regenerated (no label changes, `gen_inventory.py` doesn't apply).

### SCORE_DIGIT_BUFFER -> BUFFER_DIGITOS_PUNTUACION

At the developer's request. A 7-byte buffer (`"000000",$FF`) where
`DIBUJAR_MARCADOR_PUNTOS_DIGITOS` writes the score converted to ASCII
digits, which `TEXT_BLIT` later draws at `$16B0`. Translated to
Spanish (an English name, inconsistent with the rest of the project).
Renamed in `madmix1_body.asm` (8 mentions). `src/README.md` line 614
left untouched -- an already-frozen session-history paragraph
(struck-through checklist).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 627 labels (no change in total, a 1:1 rename).

### TEXT_BLIT -> DIBUJAR_TEXTO_INVERTIDO_VRAM

At the developer's request. Draws a text string ($FF-terminated list-
of-codes format) by flushing each glyph to VRAM inverted (CPL), the
same mechanism as LDIRVM_INVERTIDO -- hence the name. The name
`DIBUJAR_TEXTO_VRAM` was avoided as it collides with an ALREADY-
existing, distinct routine in `madmix_scr_body.asm` (renamed from
`TAIL_DECODE` in an earlier session). Renamed in `madmix1_body.asm`
(9 mentions, including the sub-label `TEXT_BLIT_LOOP` ->
`DIBUJAR_TEXTO_INVERTIDO_VRAM_LOOP` caught by the same replacement),
`src/README.md` (1 mention) and `recursos/mapa_memoria.html` (1
mention).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 627 labels (no change in total, a 1:1 rename).

### Commented DIBUJAR_MARCADOR_PUNTOS

At the developer's request. No value was convertible to decimal (the
`10000` was already in decimal; `$16B0`/`$60CA` are addresses). Added
a comment on every line explaining the logic: demo-mode flag, adding
the delta to the score, comparison against the "BEAST" bonus
threshold, and conversion to ASCII digits. Comment-only change, zero
byte change.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only). `.dsk`/`.cas` regenerated.

### SCORE_DIVISORS -> DIVISORES_PUNTUACION

At the developer's request. A table of 3 16-bit divisors (1000, 100,
10) used by `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` to extract the score's
first 3 digits by repeated subtraction (the last digit comes straight
from the remainder). Translated to Spanish, the same pattern as
`BUFFER_DIGITOS_PUNTUACION`. Renamed only in `madmix1_body.asm` (2
mentions) -- no mentions in other live files.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 627 labels (no change in total, a 1:1 rename).

### SDD_LOOP -> .BUCLE_DIVISORES (local), SDD_INNER -> .BUCLE_RESTA_DIGITO (local)

At the developer's request. `.BUCLE_DIVISORES` walks
`DIVISORES_PUNTUACION`'s divisors (1000, 100, 10), calling
`.BUCLE_RESTA_DIGITO` to extract each digit by repeated subtraction
(exits the loop after processing divisor 10, leaving the last digit
straight from the remainder). `.BUCLE_RESTA_DIGITO` is the classic
digit-by-repeated-subtraction extraction algorithm: counts how many
times the divisor can be subtracted without going negative. Verified
both are only referenced inside `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` --
converted to local with no scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 625 labels (down 2, two global->local conversions).

### SDD_EMIT_DIGIT -> .EMITIR_DIGITO (local)

At the developer's request. Converts a digit (A, 0-9) to an ASCII
character (+$30) and writes it to the next free position in
`BUFFER_DIGITOS_PUNTUACION`, advancing the pointer saved in the
alternate register bank. Called from 2 sites inside
`DIBUJAR_MARCADOR_PUNTOS_DIGITOS`. Verified it's only referenced
inside that routine -- converted to local with no scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 624 labels (down 1, the known global->local quirk).

### Commented and converted to decimal DIBUJAR_MARCADOR_PUNTOS_DIGITOS/.EMITIR_DIGITO

At the developer's request. Converted to decimal the values that
weren't addresses or masks: `LD DE,$0000`->`0` (initial offset, not
an address) and `CP $0A`->`CP 10` (comparison against the last
divisor, 10). `ADD A,$30` was left in hex (the ASCII-conversion
constant, "+$30" already documented as such in the header comment).
Added a comment on every line explaining the digit-by-repeated-
subtraction extraction algorithm and the register-bank handling
(EXX) for the destination pointer.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, comment-only/decimal). `.dsk`/`.cas` regenerated.

### TB_OUTER -> .BUCLE_FILAS_CARACTER (local), TB_ROW -> .DIBUJAR_FILA_CARACTER (local), TB_NEXTCOL -> .FIN_FILA (local)

At the developer's request. Inside `DIBUJAR_TEXTO_INVERTIDO_VRAM`:
`.BUCLE_FILAS_CARACTER` is the outer loop (8 passes, one per row of
the 8x8 character). `.DIBUJAR_FILA_CARACTER` is the code that reads
the font byte, inverts it (CPL) and writes it twice to VRAM at
consecutive positions -- finding: it's never jumped to with JP/JR,
it's inline code that isn't really a loop of its own despite having a
label. `.FIN_FILA` is the convergence point before the DJNZ, after
deciding whether it needs to "wrap" to the next VRAM strip (a split
into thirds of the SCREEN2 pattern table, exact mechanism not fully
confirmed). Verified all 3 are only referenced from each other inside
the same routine -- converted to local with no scoping problem.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated. HTML inventory
regenerated: 621 labels (down 3, three global->local conversions).

### Commented and converted to decimal all of DIBUJAR_TEXTO_INVERTIDO_VRAM

At the developer's request. Converted the pure counts to decimal: `LD
H,$00`->`0` (16-bit code extension), `LD B,$08`->`8` (row counter),
`SUB $08`->`8` and `ADD A,$08`->`8` (column steps, x2). Left in hex:
`CP $FF` (sentinel), `AND $06` (mask) and `LD BC,$935B` (address --
no exact label, falls 8 bytes before `FONT_TABLE_9363`, documented in
the comment). Added a comment on every line explaining the glyph
address computation, the per-row inverted flush, and the VRAM-strip
"wrap" logic.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated (no label changes,
`gen_inventory.py` doesn't apply).

### Final sweep of English labels in madmix1_body.asm

At the developer's request, audited EVERY label (global and local) in
`madmix1_body.asm` looking for names still in English. Applied in a
single batch (~40 renames) after the developer's explicit approval
("apply it all"), following the conventions already set this session
and, where one existed, the descriptive name already used in the
corresponding data files (`src/data/sound/*.spt`/`*.snd`):

- Graphics/HUD: `TILE_GFX` -> `GRAFICOS_LOSETAS`; `PATTERN_TAIL_92C3`
  -> `ICONO_VIDA_EXTRA`; `FONT_TABLE_9363` -> `TABLA_FUENTE_CARACTERES`.
- PSG sound driver (tables): `MISC_FLAGS_CA5D` ->
  `FLAGS_ENVOLVENTE_COMPARTIDA_PSG`; `SUBPATTERN_RETURN_TABLE_CA61` ->
  `TABLA_RETORNO_SUBPATRONES_PSG`; `TRANSPOSE_TABLE_CA67` ->
  `TABLA_TRANSPOSICION_PSG`.
- The 13 PSG bytecode subpatterns (`SUBPATTERN_xxxx` by address)
  renamed to `SUBPATRON_NN_HHHH` (zero-padded entry number + hex
  suffix), matching exactly the name already used by the `.spt` files
  in `src/data/sound/spt/`.
- The 3 script pointers `INICIO` installs
  (`SOUND_SCRIPT_MELODIA_CANAL_0/1/2` -> `GUION_MELODIA_CANAL_0/1/2`)
  and the 15 sound-event scripts (`SOUND_EVTxx_...` ->
  `GUION_EVTxx_...`, keeping the descriptor already in each name:
  trapdoor, plane shot, hint, ball dunked, etc.).
- The 10 demo-mode scripts: `DEMO_SCRIPT_NIVEL1/2/4/5` ->
  `GUION_DEMO_NIVEL1/2/4/5`; `DEMO_SCRIPT_SINREF_1..6` ->
  `GUION_DEMO_SINREF_1..6`.
- `SLOT_RESTART_DD82` -> `REINICIO_SLOT_DD82`; `BESTIA_TEXT` ->
  `TEXTO_BESTIA`; `DEMO_TEXT` -> `TEXTO_DEMO`.

Along the way, synced several sites that had fallen out of sync from
EARLIER rename rounds (found during the sweep of
`recursos/mapa_memoria.html`): a stray `QUEUE_PUSH` mention (already
renamed to `APILAR_PETICION_REDIBUJADO` in a previous round) in
`REDIBUJAR_LOSETA_BUFFER_VRAM`'s description.

**Verified**: recompiled with no errors (9676 lines), diffs at the
exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`).
`recursos/flujo_programa.html` regenerated (recompiling `main.lst`
first, before `gen_inventory.py`, to avoid reading stale data): 621
labels (funcion/function=102 interna/internal=244 dato/data=242
sinref/unreferenced=33). `.dsk`/`.cas` regenerated with no issues.
Also synced `src/FLUJO_PROGRAMA.md` (`SOUND_SCRIPT_2_CE0C` ->
`GUION_MELODIA_CANAL_2`, confirmed by address `$CE0C`;
`BESTIA_TEXT`/`DEMO_TEXT` -> `TEXTO_BESTIA`/`TEXTO_DEMO`),
`recursos/mapa_memoria.html` (several entries in the `SEGMENTS`
array) and `recursos/graficos.html` (the JS variable `TILE_GFX` ->
`GRAFICOS_LOSETAS`, including its `.forEach`, for consistency with
the new label even though it's client code, not prose). Mentions of
old names inside `src/README.md`'s frozen historical narrative (past-
tense paragraphs about earlier sessions' findings: `DEMO_SCRIPT_NIVEL1`,
`SLOT_RESTART_DD82`, `TILE_GFX`) were deliberately left untouched,
following the criterion already established this session of not
retroactively rewriting past discovery accounts.

### MOTOR_ACTORES / DIBUJAR_FILA_DESPLAZADA_DERECHA/IZQUIERDA: data reviewed

At the developer's request, reviewed every numeric literal across the
whole body of `MOTOR_ACTORES` (0x8440) and its two sub-pixel drawing
routines `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`, converting to
decimal the ones that are pure limits/counts/steps and adding a
comment to each literal and to the most relevant logical blocks:

- The 4 entry guards, already summarized in the routine's header as
  "$0A/$40/$04/$74": `CP $0A` -> `CP 10` (max simultaneous active
  actors, matches `$8437`, see `RESET_CONTADOR_ACTORES`); `CP $40` ->
  `CP 64` (number of entries in `PTR_TABLA_SPRITES`, valid sprite-
  index limit); `CP $04` -> `CP 4` and `CP $74` -> `CP 116` (min/max
  visible-column limits). Also updated the routine's header (line
  ~46) to cite them in decimal and keep it consistent with the code,
  since it's live documentation for this same routine (not a frozen
  historical account).
- `LD (HL), $90`/`LD (HL), $B0` -> `144`/`176`: two camera vertical-
  clipping limits chosen based on A's bit 5: their exact meaning
  hasn't been pinned down (documented as an open hypothesis, like
  other "half" values already seen in the routine).
- `ADD A, $10` -> `ADD A, 16`: a fixed row offset before calling
  `CALCULAR_DIRECCION_MASCARA_ACTOR` (exact purpose unconfirmed,
  possible candidate for a reserved strip at the top of the screen).
- `LD A, $03` -> `LD A, 3`: a fixed constant saved to `$8435` with no
  identified use in the rest of the transcribed code (unconfirmed).
- The 3 `LD BC, $0020` (one in `MEZCLAR_Y_AVANZAR_FILA_ACTOR`, one in
  each drawing routine) -> `LD BC, 32`: VRAM/buffer row step, the
  same pattern already used across the rest of the tile engine.
- Everything else was left in hex per the already-established
  convention: addresses (`$843E`, `$92E3`, `$8433`, `$0500`, etc.),
  bitmasks (`AND $F8`/`$07`/`$C0`/`$80`/`$40`) and the `(IX+$NN)`
  offsets of the 12-byte actor record's fields (structure offsets,
  already uniform style throughout the file).
- Added field comments to every read/write of `(IX+$NN)` (position,
  mask address, row counter, cursor, edge-clipping mask) summarizing
  the mapping already described in the routine's header, and block
  comments in the two sub-pixel drawing routines (bit-by-bit shift
  loop, AND/OR mix against the background, row advance, repeat for
  the pair's second row).

**Verified**: recompiled with no errors (9676 lines), diffs at the
exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). A purely
notation/comment change, no new or renamed labels -- no need to
regenerate the inventory or `.dsk`/`.cas`.

### CAPTURAR_MASCARAS_ACTOR and family (0x8687-0x87FF): data reviewed

Continuation of the same data/comment sweep over the rest of the
`MOTOR_ACTORES` block: `CAPTURAR_MASCARAS_ACTOR`,
`CONTINUAR_CAPTURA_MASCARAS_ACTORES`, `INVERTIR_BITS_PATRON_ACTOR`,
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` and `COMPONER_ACTORES_EN_BUFFER`.

- `LD BC, $00FF` (appears twice, once in each capture routine):
  deliberately left in hex, it isn't a simple counter -- C=$FF is a
  "safety" value so the 3 implicit `DEC`s of the following `LDI`s
  don't borrow into B (B must stay at 0 for the later `ADD HL,BC` of
  +29 to work). Added a comment explaining it.
- `LD C, $1D` (4 occurrences) -> `LD C, 29`: together with the 3
  bytes already copied by the `LDI`s, adds up to exactly 32, the row
  step already documented in `MOTOR_ACTORES`'s header ("3 bytes of
  every 32-byte block").
- `LD DE, $FFF4` in `CONTINUAR_CAPTURA_MASCARAS_ACTORES`: left in hex
  (a signed delta, already covered by the convention), but added a
  comment clarifying it equals -12 (steps back one full actor
  record).
- `LD B, $30` in `INVERTIR_BITS_PATRON_ACTOR` -> `LD B, 48`: the
  outer loop's block cap (upper limit, the real byte-per-block count
  comes from `($8435)`).
- In `COMPONER_ACTORES_EN_BUFFER`: `ADD A, $20` -> `ADD A, 32` (the
  same row step as the rest of the engine) and `SUB $08` -> `SUB 8`
  (compensates the 3 rows already added via H, returning to the
  block's base). `LD DE, $000A` -> `LD DE, 10`: FINDING -- this
  routine advances the IX pointer by ONLY 10 bytes per actor, not 12
  like `MOTOR_ACTORES`/`CONTINUAR_CAPTURA_MASCARAS_ACTORES` do over
  the same array. Discrepancy documented as-is, unresolved; fits with
  this routine still having no confirmed caller in the transcribed
  code (see the function's header and FINDINGS.md), which could
  explain why such a mismatch never showed up in the real game.
- Added field comments (what each `(IX+$NN)` does, which register
  holds each "there and back" mask block) and flow comments
  (`INVERTIR_ORDEN_BYTES_PATRON_ACTOR`'s convergence loop, operand
  self-modification in `COMPONER_ACTORES_EN_BUFFER`) without touching
  addresses, bitmasks or structure offsets, left in hex by the same
  usual convention.

**Verified**: recompiled with no errors (9678 lines), diffs at the
exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). A purely
notation/comment change, no new or renamed labels -- no need to
regenerate the inventory or `.dsk`/`.cas`.

### VRAM API (FILVRM/LDIRVM/SETVRAM) and neighbors: data reviewed

Last batch of the same sweep: `FILVRM`, `LDIRVM`, `SETVRAM`
(equivalents of the MSX BIOS's same-named routines),
`CONSULTAR_COLOR_VDP`, `CALCULAR_DIRECCION_MASCARA_ACTOR`,
`RESET_CONTADOR_ACTORES` and `WAIT_VBLANK`.

Unlike the earlier batches, here there were practically no decimal-
candidate literals: these are low-level VDP routines, and all their
values are ports ($98/$99), bitmasks (`AND $3F`/`OR $40` of the
SETWRT command, `AND $78`/`OR $10` of `CONSULTAR_COLOR_VDP`) or the
base address `$DC00` itself -- the three cases this session's
convention always keeps in hex. `TABLA_COLORES_VDP` also wasn't
touched: they're VDP color codes (0-15), naturally hexadecimal by how
they're extracted (nibbles). So this was limited to adding per-
instruction comments: what each `OUT`/`CALL SETVRAM` does in the 3
VRAM routines, the meaning of `AND $3F`/`OR $40` (the VDP's "set write
pointer" command's two bits), the bit isolation/rotation in
`CONSULTAR_COLOR_VDP`, and in `WAIT_VBLANK` a note cross-referencing
`GESTIONAR_FRAME` (confirmed by reading its code, line ~903): it's
that routine, not the ISR itself, that sets `FRAME_FLAG` back to 0
when processing the frame.

**Verified**: recompiled with no errors (9678 lines), diffs at the
exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`). A purely
comment change, no literal converted, no new or renamed labels -- no
need to regenerate the inventory or `.dsk`/`.cas`.

### CAPTURAR_MASCARAS_ACTOR and family, part 2: the full PSG driver (INSTALAR_RECURSO_SONIDO .. VOLCAR_REGISTROS_PSG)

At the developer's request ("do the same with the rest of the data
from line 3392 to the end of the file"), reviewed the entire rest of
`madmix1_body.asm`: all the PSG sound driver CODE
(`INSTALAR_RECURSO_SONIDO`, `INSTALAR_RECURSO_SONIDO_EN_A`,
`LIMPIAR_E_INSTALAR_RANURA`, `TICK_REPRODUCTOR_PSG`/`PROCESAR_CANAL_PSG`/
`DESPACHAR_COMANDO_PSG` with the 15 command bodies with no label of
their own, `APLICAR_ENVOLVENTES_CANAL`, `APLICAR_ENVOLVENTE_RUIDO`,
`REINICIAR_ENVOLVENTE_VOLUMEN/TONO/RUIDO`, `ACTUALIZAR_MEZCLADOR_CANAL`,
`OBTENER_PUNTERO_TRANSPOSICION`, `MULTIPLICAR_8X16`, `DIVIDIR_16X16`,
`LEER_PALABRA_INDEXADA`, `VOLCAR_REGISTROS_PSG`) and the final stretch
(`REINICIO_SLOT_DD82`, `CONFIGURAR_Y_LEER_JOYSTICK_PSG`). The pure
data tables (0xC8DE-0xDDA0: notes, commands, instruments, envelopes,
subpatterns, sound/demo scripts, levels 13/14, candy frame) were
already well documented from earlier rounds (`TABLA_NOTAS_PSG` already
had the decimal equivalent per note) and needed no changes -- they're
signed/packed bytes (instrument format) or data via `INCBIN`,
consistent with the convention of leaving them in hex.

- Pure loop counters converted to decimal: `LD D,2`/`LD D,3` (the
  envelope's volume/pitch phases, exactly matching the already-
  documented instrument format: 2 volume repeats, 3 pitch repeats),
  `LD B,3` (3 channels), `LD D,3`->`LD D,3` in
  `INSTALAR_RECURSO_SONIDO` (3 slots), `LD B,8`/`LD B,16` in
  `MULTIPLICAR_8X16`/`DIVIDIR_16X16`, `LD D,11` in
  `VOLCAR_REGISTROS_PSG` (the PSG's 11 registers), `LD A,14` in
  `CONFIGURAR_Y_LEER_JOYSTICK_PSG` (the PSG register that reads the
  joystick).
- Pure sizes/steps converted: `46` (channel-slot size, 4 sites), `10`
  (`TABLA_ENVOLVENTE_RUIDO_PSG`'s bytes), `15` (instrument size), `6`
  (envelope-shape size), `16` and `3000` (`SET_TEMPO`'s multiplier/
  divisor, the reason for `3000` specifically unverified).
- Left in hex (masks/sentinels, the usual convention): `AND $09`/
  `$1F`/`$0F` (masks), `CP $80`/`SUB $80` (the bytecode's format
  marker, command vs. note), `$09` in `ACTUALIZAR_MEZCLADOR_CANAL`
  (NOT a counter despite looking like one -- it's a bit0+bit3 bit
  pattern shifted with `SLA`, carefully verified before ruling out
  the conversion), and `LD BC,$00FF`/`LD DE,$FFF4` in the
  `CAPTURAR_MASCARAS_ACTOR` family (already documented in the
  previous round).
- FINDING of "hex not substituted with an already-existing label"
  (the same systemic pattern from earlier rounds): 5 uses of
  `($CA5D)` -> `(FLAGS_ENVOLVENTE_COMPARTIDA_PSG)`, 2 uses of `$CA61`
  -> `TABLA_RETORNO_SUBPATRONES_PSG`, 1 use of `$CA67` ->
  `TABLA_TRANSPOSICION_PSG`. Also, 2 offsets inside already-labeled
  zones converted to `LABEL+N` arithmetic (the same pattern as
  `BUFFER_LOSETAS_TRABAJO+23` from an earlier round): `$CA60` ->
  `FLAGS_ENVOLVENTE_COMPARTIDA_PSG+3`, `$CA5F` -> `+2` (via the same
  base), `$CA5E` -> `+1`, and `$CA54` -> `TABLA_ENVOLVENTE_RUIDO_PSG+1`.
- Identified with confidence (by exact match between the fields they
  touch and the description already in the `TABLA_COMANDOS_PSG`
  table) the 15 command bodies with no label of their own in the PSG
  bytecode, and added a one-line comment to each with its command
  name/number (`SET_VOLUME`, `SET_MIXER`, `LOOP`, `SET_DURATION`,
  `HOLD`, `SET_TEMPO`, `SET_DURATION_MULTI`, `SET_INSTRUMENT`,
  `SET_ENVELOPE`, `SET_ENVELOPE_SHAPE`, `SET_FLAGS`,
  `RESET_SHARED_ENVELOPE`, `CALL_SUBPATTERN`, `RETURN_SUBPATTERN`,
  `SET_CHANNEL_STATE`) -- none had a label in the original because
  `DESPACHAR_COMANDO_PSG` jumps to them via `JP (HL)` indexing
  `TABLA_COMANDOS_PSG`, not by name.

**Verified**: recompiled with no errors (9686 lines), diffs at the
exact usual baseline (7 in `MADMIX.SCR`, 2 in `MADMIX1.BIN`) --
confirms the 8 hex-to-label/`LABEL+N`-arithmetic substitutions
resolve to the exact same addresses as the original hex. A purely
notation/comment/existing-label change, no new or renamed labels --
no need to regenerate the inventory or `.dsk`/`.cas`.

### VDP_WAIT_READY -> APAGAR_PANTALLA_VDP

Renamed `VDP_WAIT_READY` (`madmix_scr_body.asm`, $10BC) to
`APAGAR_PANTALLA_VDP`: the previous name was misleading -- despite
saying "WAIT", the routine does NOT wait for anything, it only reads
the VDP's status register (`IN A,($99)`, a useful side effect: clears
the pending VBLANK interrupt flag) and writes `$A2` to VDP register 1,
which with bit6=0 turns the screen off (BLANK), leaving IE active and
large sprites. The one that DOES really wait is its neighbor
`VDP_ENABLE_DISPLAY` (a `JP P` loop waiting for VBLANK before turning
the screen back on with `$E2`) -- the old name described the wrong
routine.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` had no mentions. The mentions in
`FINDINGS.md` (historical narrative from earlier sessions about
`PORTADA_INIT`/the `$10D8`/`$10DE` patches) were deliberately left
untouched, same criterion as always.

### identity_loop -> .BUCLE_TABLA_IDENTIDAD (local)

Renamed the local loop `.identity_loop` (inside `DIBUJAR_PORTADA`,
`madmix_scr_body.asm`) to `.BUCLE_TABLA_IDENTIDAD`: writes the title
screen's identity name table (768 bytes in VRAM $1800, name=pattern
index), the same trick already identified in the main engine for
treating the pattern table as a direct array.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md` or `recursos/*.html`.

### PORTADA_PATTERN -> PORTADA_PATRON

Renamed `PORTADA_PATTERN` to `PORTADA_PATRON` (`madmix_scr_body.asm`,
$10ED): the title screen's uncompressed bitmap, 6144 bytes (`INCBIN
"data/img/portada_patron.img"`) which `DIBUJAR_PORTADA` flushes
directly to the VRAM pattern table ($0000). A simple translation
("PATTERN" -> "PATRON") to match exactly the already-existing data
file's name.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md`.

### PORTADA_COLOR_PACKED -> PORTADA_COLOR

Renamed `PORTADA_COLOR_PACKED` to `PORTADA_COLOR`
(`madmix_scr_body.asm`, $28F0): the title screen's compressed color
block, 768 bytes (`INCBIN "data/img/portada_color.img"`) which
`BUCLE_DESCOMPRIMIR_COLOR_PORTADA` decompresses byte by byte (each
byte encodes 2 4-bit indices into `PALETA_COLORES_PORTADA`, combined
in the high/low nibble) to rebuild the real SCREEN2 color table in
VRAM $2000. "Packed" is already explained by the block's comment, no
need for it in the name; it matches the already-existing data file.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md`.

### COLOR_LOOP -> BUCLE_DESCOMPRIMIR_COLOR_PORTADA

Renamed `COLOR_LOOP` to `BUCLE_DESCOMPRIMIR_COLOR_PORTADA`: the main
loop that walks `PORTADA_COLOR`'s 768 groups, decompressing each byte
into a real SCREEN2 color (via `PALETA_COLORES_PORTADA`) and
repeating it 8 times (an 8-line column) when writing it to the VRAM
color table $2000. Global (no dot, referenced by a `JR NZ,` from
itself), unlike the local loop `.BUCLE_RELLENAR_COLOR` it contains.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry (`PORTADA_COLOR_PACKED -> PORTADA_COLOR`).

### COLOR_ZERO_CASE -> ESCRIBIR_COLUMNA_COLOR

Renamed `COLOR_ZERO_CASE` to `ESCRIBIR_COLUMNA_COLOR`: the previous
name only described one of its TWO entry paths (a direct jump when
the control byte is 0, color 0/0 with nothing to decompress). It's
also reached by natural fall-through after decompressing the normal
case -- it's the SHARED routine that writes the already-resolved
color byte (in A) 8 times to VRAM (an 8-line column, already
described in the following line's comment).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md`.

### PORTADA_TABLE16 -> PALETA_COLORES_PORTADA

Renamed `PORTADA_TABLE16` to `PALETA_COLORES_PORTADA` (a name
proposed by the developer, different from the literal translation
`PORTADA_PALETA`): a 16-byte palette table (`INCBIN
"data/img/portada_paleta.img"`) with the real SCREEN2 color values
(0-15), indexed by `BUCLE_DESCOMPRIMIR_COLOR_PORTADA` to translate
each compressed byte's two 4-bit indices into the final color's low/
high nibble.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the 2 mentions just added in this same file's
earlier entries.

### color_fill -> .BUCLE_RELLENAR_COLOR (local)

Renamed the local loop `.color_fill` (inside `ESCRIBIR_COLUMNA_COLOR`)
to `.BUCLE_RELLENAR_COLOR`: writes the same color byte 8 times in a
row to VRAM, filling an 8-line column of a character.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry.

### DIBUJAR_PORTADA in full: data reviewed

At the developer's request, reviewed every numeric literal across the
whole body of `DIBUJAR_PORTADA` (drawing the title screen: identity
name table, pattern bitmap, color decompression), converting pure
counts/sizes to decimal and adding comments:

- `CP $03` -> `CP 3`: the identity name table is written across 3
  256-byte pages (768 total).
- `LD BC, $1800` -> `LD BC, 6144`: the full size of SCREEN2's pattern
  table (`PORTADA_PATRON`'s bitmap).
- `LD A, $01` -> `LD A, 1` and `LD C, $07` -> `LD C, 7`: border/
  background color (palette index) and the VDP register number (R7),
  already cited in decimal in the existing comment ("register 7...
  = 1").
- `LD BC, $0300` -> `LD BC, 768`: number of color groups to
  decompress, matches the already-existing block comment ("768
  groups of 8 lines").
- `LD BC, $0008` -> `LD BC, 8`: lines per character column (reused
  afterward to advance the destination VRAM pointer by 8).
- Left the rest in hex per the usual convention: VRAM addresses
  (`$1800`, `$0000`, `$2000`) and VDP masks/commands (`AND $3F`/
  `OR $40`/`OR $80`/`AND $07`/`AND $78`/`AND $08`).
- Added comments to each step: setting the VRAM address (SETWRT),
  extracting the compressed byte's 2 4-bit indices, saving/restoring
  the 2 distinct counters that share register BC in
  `ESCRIBIR_COLUMNA_COLOR`'s stretch (the 8-fill count and the
  remaining-groups counter).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). A purely notation/comment change, no new or renamed
labels -- no need to regenerate the inventory or `.dsk`/`.cas`.

### TRAPDOOR_PHASE -> LADO_APERTURA_TRAMPILLA

Renamed `TRAPDOOR_PHASE` to `LADO_APERTURA_TRAMPILLA` (a name
proposed by the developer, more precise than the first proposal
`FASE_TRAMPILLA`): a 1-byte state variable ($2C1E) storing WHICH SIDE
the current trapdoor opened from (1=left, set by
`HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA`; 2=right, set by
`HNDLR_TRAMPILLA_ABIERTA_DERECHA`), so `HNDLR_TRAMPILLA_CERRADA` knows
which closing-animation variant to draw. Also updated the declaration
comment to reflect the real meaning (side, not a generic "phase").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (game-state-variables
index). Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### REFERENCE_POINT -> PUNTO_REFERENCIA_CAMARA

Renamed `REFERENCE_POINT` to `PUNTO_REFERENCIA_CAMARA` (`$2C1F-20`):
a 16-bit position computed as camera + fixed offset (mod 128),
recalculated every frame by `HNDLR_PELMAZOIDE`, used by
`MOTOR_MOVIMIENTO_ITEM` to decide whether a mobile item ("pelmazoide")
is "behind the camera"/off-screen. Already described in existing
comments as "aim point"/"reference point"; the name makes clear it's
camera-relative, not a fixed map point.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (game-state-variables
index). Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### RNG_SEED -> SEMILLA_ALEATORIA

Renamed `RNG_SEED` to `SEMILLA_ALEATORIA` (`$2C22-23`): the 16-bit
seed of the `GENERAR_ALEATORIO` ($5478) pseudorandom generator, which
reads it, mixes it with the Z80's `R` refresh register via `XOR` and
writes it back every time a random number is requested. "RNG" (Random
Number Generator initials) translated; matches the already-existing
comment ("pseudorandom generator seed").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (game-state-variables
index). Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### TILE_DISPATCH_PTRS/SUBTABLE_A-D -> PUNTEROS_SUBTABLA_DIRECCION/SUBTABLA_DIRECCION_A-D

Renamed `TILE_DISPATCH_PTRS` to `PUNTEROS_SUBTABLA_DIRECCION` and its
4 sub-tables `SUBTABLE_A/B/C/D` to `SUBTABLA_DIRECCION_A/B/C/D`
(`$2C48-$2C9F`): the previous name was misleading -- it has nothing to
do with tile types, it's a 4-pointer table indexed by the movement
DIRECTION (E, already decided by the collision engine) that selects
the sub-table (20 bytes = 5 rows x 4 columns) used by
`ML_DIR_SUBTABLE_LOOP` to choose the pac-man's animation frame (mouth
phase + orientation). It hasn't been possible to confirm which
specific direction (up/down/left/right) each letter A/B/C/D
corresponds to, so the letters are kept instead of inventing an
unverified mapping.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the "collision/tile
engine tables" block). Mentions in `FINDINGS.md` (historical
narrative from earlier sessions) deliberately left untouched, same
criterion as always.

### ML_MODO_ESPECIAL_TICK -> TICK_MODO_ESPECIAL

Renamed `ML_MODO_ESPECIAL_TICK` to `TICK_MODO_ESPECIAL` (dropped the
`ML_` prefix, the rest already untranslated from a broader label
family): the per-frame update routine for the timed special modes
(power ball=1, hippo=2) -- decrements the duration counter, handles
the HUD icon's blink in the final instants, and when time runs out
clears the mode flags. It's also the common convergence point ~20
tile-type handler routines jump to after finishing their work.
"TICK" is kept (not translated): it's already an accepted technical
loanword in this project (see `TICK_REPRODUCTOR_PSG`), meaning
"advance a state by one discrete time step" -- here it happens to be
1:1 with a frame, but the name describes the action, not the cadence.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_HIPPO_MODE_TICK -> TICK_MODO_HIPOPOTAMO

Renamed `ML_HIPPO_MODE_TICK` to `TICK_MODO_HIPOPOTAMO`: twin of
`TICK_MODO_ESPECIAL` for special mode 2 (hippo) -- same pattern
(decrements the timer, blinks the HUD icon in the final instants),
but the blink is implemented by XOR-toggling the icon's bit 6 instead
of choosing between two fixed values.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_POWER_MODE_END -> FIN_MODO_BOLA_PODER

Renamed `ML_POWER_MODE_END` to `FIN_MODO_BOLA_PODER`: reached when
the power-ball mode's timer reaches 0 -- empties the sound slots
(`VACIAR_CANALES_SONIDO`) and turns off the special-mode flags,
returning the game to its normal state.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_POWER_BLINK_COLOR -> PARPADEO_COLOR_BOLA_PODER

Renamed `ML_POWER_BLINK_COLOR` to `PARPADEO_COLOR_BOLA_PODER`: the
point where the HUD icon's blinking color is set in the power-ball
mode's final instants (alternates between fixed `$30` and
`COLOR_GUARDADO`, based on the counter's low bit).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_DIR_SUBTABLE_LOOKUP/ML_HIPPO_MODE_END/ML_HIPPO_BLINK_ICON -> OBTENER_SUBTABLA_DIRECCION/FIN_MODO_HIPOPOTAMO/PARPADEO_ICONO_HIPOPOTAMO

Continuation of the cleanup of the `ML_`-prefix family (probably
"Main Loop") in the collision/movement engine:

- `ML_DIR_SUBTABLE_LOOKUP` -> `OBTENER_SUBTABLA_DIRECCION`: computes
  and loads into DE the pointer to the chosen direction sub-table
  (indexing `PUNTEROS_SUBTABLA_DIRECCION` with the final direction
  *2), paralleling the PSG driver's `OBTENER_PUNTERO_TRANSPOSICION`.
- `ML_HIPPO_MODE_END` -> `FIN_MODO_HIPOPOTAMO`: twin of
  `FIN_MODO_BOLA_PODER` for special mode 2 (restores `COLOR_GUARDADO`
  and turns off the mode flags).
- `ML_HIPPO_BLINK_ICON` -> `PARPADEO_ICONO_HIPOPOTAMO`: twin of
  `PARPADEO_COLOR_BOLA_PODER`, but XOR-toggles the HUD icon's bit
  instead of choosing between two fixed colors.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_DIR_SUBTABLE_LOOP/DIR_TABLE_INDEX/ML_DIR_BEHAVIOR_STORE -> BUCLE_SUBTABLA_DIRECCION/INDICE_SUBTABLA_DIRECCION/GUARDAR_SELECTOR_SPRITE_COMECOCOS

Continuation of the `ML_`-family/English-name cleanup in the
collision/movement engine, around the loop that resolves the pac-
man's animation frame:

- `ML_DIR_SUBTABLE_LOOP` -> `BUCLE_SUBTABLA_DIRECCION`: walks the 4
  entries of the chosen direction sub-table looking for one that
  isn't the $FF sentinel.
- `DIR_TABLE_INDEX` -> `INDICE_SUBTABLA_DIRECCION` (`$2C14`): the
  rotating index (0-3) that loop advances every call.
- `ML_DIR_BEHAVIOR_STORE` -> `GUARDAR_SELECTOR_SPRITE_COMECOCOS`: the
  point where the already-resolved value (real, or inherited via the
  $FE sentinel) is saved into `SELECTOR_SPRITE_COMECOCOS`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the game-state-variables
index and the "collision/tile engine tables" block). Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_SCROLL_PREP/ML_SCROLL_DISPATCH_CALL/ML_SCROLL_AND_ITEMS -> PREPARAR_SCROLL/PREPARAR_LLAMADA_SCROLL/DISPARAR_SCROLL_Y_ITEMS

Continuation of the `ML_`-family cleanup in the collision/movement
engine, the stretch that triggers the scroll and the special-item
handlers after resolving the animation frame:

- `ML_SCROLL_PREP` -> `PREPARAR_SCROLL`: splits the previous value
  (bit7 apart from the rest) and preps the parameters for the next
  batch of calls.
- `ML_SCROLL_DISPATCH_CALL` -> `PREPARAR_LLAMADA_SCROLL`: finishes
  prepping the parameters and decides H's variant based on whether a
  special mode is active.
- `ML_SCROLL_AND_ITEMS` -> `DISPARAR_SCROLL_Y_ITEMS`: triggers
  `GESTIONAR_SCROLL` and, if the keyboard isn't blocked, the special-
  item handlers (`HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/
  `HNDLR_REGPUNANTOSO`) + `ACTUALIZAR_DESTELLO_ITEMS`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ML_PISTA_LOOP/NEXT/FORMATO_B/FORMATO_B_POS/FILA_FIJA/DIBUJAR -> BUCLE_PISTA_TANQUE_AVION/SIGUIENTE_PISTA/PISTA_FORMATO_B/PISTA_FORMATO_B_POS/PISTA_FILA_FIJA/DIBUJAR_PISTA

Last batch of the `ML_`-family cleanup: the tank/plane hint loop
(walks `TABLA_PISTA_TANQUE_AVION`'s 3 entries, computes the VRAM
address based on the sub-format encoded in each entry and calls
`MOTOR_ACTORES` to draw the effect, or frees the entry if the
computation goes out of range):

- `ML_PISTA_LOOP` -> `BUCLE_PISTA_TANQUE_AVION`
- `ML_PISTA_NEXT` -> `SIGUIENTE_PISTA`
- `ML_PISTA_FORMATO_B` -> `PISTA_FORMATO_B` (only the prefix is
  dropped, "FORMATO_B" was already in Spanish)
- `ML_PISTA_FORMATO_B_POS` -> `PISTA_FORMATO_B_POS` (same)
- `ML_PISTA_FILA_FIJA` -> `PISTA_FILA_FIJA` (same)
- `ML_PISTA_DIBUJAR` -> `DIBUJAR_PISTA`

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions, with the
previous `ML_TRAPDOOR_*` names) deliberately left untouched, same
criterion as always.

### FORCED_DIR_CLEAR/FORCED_DIR_TICK_DONE -> LIMPIAR_DIRECCION_FORZADA/FIN_TICK_DIRECCION_FORZADA

Renamed `FORCED_DIR_CLEAR` to `LIMPIAR_DIRECCION_FORZADA` (really
clears `DIRECCION_FORZADA` once the timer has reached 0) and
`FORCED_DIR_TICK_DONE` to `FIN_TICK_DIRECCION_FORZADA` (the common
exit point of `TEMPORIZADOR_DIRECCION_FORZADA_TICK`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### TRAPDOOR_ANIM_EXIT -> FIN_ANIMACION_TRAMPILLA

Renamed `TRAPDOOR_ANIM_EXIT` to `FIN_ANIMACION_TRAMPILLA`: the common
exit point of `HNDLR_TRAMPILLA_ABIERTA_DERECHA`/
`HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA` after drawing (or not) the
opening-animation frame.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ITEM_TABLE_PELMAZOIDE -> TABLA_ITEMS_PELMAZOIDE

Renamed `ITEM_TABLE_PELMAZOIDE` to `TABLA_ITEMS_PELMAZOIDE`
(`$511C`): the 8-entry active table (7 bytes each) for type-3 items
(ghosts -- already identified via `SPR27-32_FANTASMA_*`).
"ITEM_TABLE" in English + "PELMAZOIDE" already in Spanish (a term
already consistent in `HNDLR_PELMAZOIDE`, etc.); the same pattern as
`TABLA_PISTA_TANQUE_AVION`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x511C-0x5154`
block). Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### ITEM_ANIM_TABLE_PELMAZOIDE/ITEM_DIR_CHOICE_TABLE -> TABLA_ANIMACION_PELMAZOIDE/TABLA_ELECCION_DIRECCION

Renamed the two data tables in block `$5154-$51FE`:

- `ITEM_ANIM_TABLE_PELMAZOIDE` -> `TABLA_ANIMACION_PELMAZOIDE` (32
  bytes): the ghosts' sprite-selection-by-direction+phase table,
  indexed by `HNDLR_PELMAZOIDE` as `direction(1-4)*4+phase(0-3)`; a
  sister of `TABLA_ITEMS_PELMAZOIDE` (the state one) but this one is
  the animation/graphics table.
- `ITEM_DIR_CHOICE_TABLE` -> `TABLA_ELECCION_DIRECCION` (128 bytes,
  `$517E`): pure data indexed by `MOTOR_MOVIMIENTO_ITEM` as
  `(free directions)<<3 | (previous direction)<<1 | (random bit)`,
  returns the final chosen direction (a "keep the direction if
  possible" bias); generic to `MOTOR_MOVIMIENTO_ITEM`, not specific
  to the pelmazoides.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x5154-0x51FE`
block). Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### PELMAZOIDE_LOOP/PELMAZOIDE_DRAW/PELMAZOIDE_SPECIAL_ADJUST -> BUCLE_PELMAZOIDE/DIBUJAR_PELMAZOIDE/AJUSTAR_SPRITE_MODO_ESPECIAL

Renamed 3 labels of `HNDLR_PELMAZOIDE` (`MOVER_ITEM_MOVIL`, already
fully in Spanish at the time, later separately renamed to
`MOTOR_MOVIMIENTO_ITEM` in a later round, see below):

- `PELMAZOIDE_LOOP` -> `BUCLE_PELMAZOIDE`: walks
  `TABLA_ITEMS_PELMAZOIDE`'s active entries calling
  `MOTOR_MOVIMIENTO_ITEM`. Watch out when applying: there's a
  DISTINCT label `TI_PELMAZOIDE_LOOP` (line ~3058) that contains
  "PELMAZOIDE_LOOP" as a substring -- NOT touched, targeted edits
  instead of `replace_all` to avoid corrupting it.
- `PELMAZOIDE_DRAW` -> `DIBUJAR_PELMAZOIDE`: draws the already-
  resolved sprite (direction+phase).
- `PELMAZOIDE_SPECIAL_ADJUST` -> `AJUSTAR_SPRITE_MODO_ESPECIAL`: with
  power-ball mode active, shifts +20 bytes to use the second half of
  each `TABLA_ANIMACION_PELMAZOIDE` group (the ghost's variant sprite
  during special mode).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`.

### MOVER_ITEM_MOVIL -> MOTOR_MOVIMIENTO_ITEM

Renamed `MOVER_ITEM_MOVIL` to `MOTOR_MOVIMIENTO_ITEM`: the previous
name was already fully in Spanish but sounded redundant ("move mobile
item"). A generic movement engine shared by the 3 mobile-item types
(pelmazoide/ghost, ladybug, "repugnantoso"): validates the position,
computes the approach direction toward the camera, tests free
directions via `CONSULTAR_LOSETA_LIBRE_DIRECCION` and picks the final
direction via `TABLA_ELECCION_DIRECCION`. Name chosen to fit the same
family as `MOTOR_MOVIMIENTO_COLISION`/`MOTOR_ACTORES`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x51FE-0x5478`
block). Also synced the mentions just added in this same file's 2
previous entries. Mentions in `FINDINGS.md` of genuine historical
narrative (earlier rounds about `HELPER_5278`/the sub-label study)
deliberately left untouched.

### ITEM_EFFECT -> ACTIVAR_EFECTO_ITEM

Renamed `ITEM_EFFECT` to `ACTIVAR_EFECTO_ITEM` (`$57D8`): an item's
activation effect, called after `MOTOR_ACTORES` from the 3 mobile-item
handlers. Filters by a fixed VRAM position window (near the pac-man)
and by the item type read from `($2C2D)`, and triggers sounds/
animations/special modes via `ARMAR_AVISO_DESTELLO`/`$8D70`, or
delegates to `AVISAR_PROXIMIDAD_PISTA` when the type is 3 (hint).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### PELMAZOIDE_NEXT/PELMAZOIDE_END -> SIGUIENTE_PELMAZOIDE/FIN_PELMAZOIDE

Renamed `PELMAZOIDE_NEXT` to `SIGUIENTE_PELMAZOIDE` (advances to the
next `TABLA_ITEMS_PELMAZOIDE` entry, reached both when the position
wasn't valid and after drawing and checking the effect) and
`PELMAZOIDE_END` to `FIN_PELMAZOIDE` (`HNDLR_PELMAZOIDE`'s final
`RET`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md` or `recursos/mapa_memoria.html`.

### HELPER_5414 -> CONSULTAR_LOSETA_LIBRE_DIRECCION

Renamed `HELPER_5414` to `CONSULTAR_LOSETA_LIBRE_DIRECCION`
(`$5414`): checks, for each of the 4 direction bits (`A=$01/$02/$04/
$08` = right/left/down/up), whether the item's position has a free
tile one step in that direction (via `CONSULTAR_TIPO_LOSETA`). Called
4 times in a row from `MOTOR_MOVIMIENTO_ITEM`, accumulating a bitmask
of free directions. Same style as `CONSULTAR_TIPO_LOSETA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x51FE-0x5478`
block). Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### HELPER_53A2/H53A2_53BA -> CALCULAR_POSICION_VRAM_ITEM/.CONTINUAR_AJUSTE_COLUMNA (local)

Renamed `HELPER_53A2` to `CALCULAR_POSICION_VRAM_ITEM` (`$53A2`):
`MOTOR_MOVIMIENTO_ITEM`'s second entry point, called directly from
`ACTUALIZAR_DESTELLO_ITEMS` (bypassing the "behind camera" checks).
Computes the VRAM address (D/E) of the item's position relative to
the current camera and checks it against the visible screen limits;
returns with carry if it falls out of range, or DE=VRAM address if
visible.

Also converted to LOCAL (only used inside the same function)
`H53A2_53BA` -> `.CONTINUAR_AJUSTE_COLUMNA`: a column-adjustment
convergence point -- computes `(E-8) mod 64` (wrapped with `RES 7`),
the item's column adjusted to the 64-wide visible window (a candidate
for a half/quadrant of the tile buffer, the same "half" partition
type already seen in `MOTOR_ACTORES`, not fully confirmed).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 620
labels (down 1 from the global->local conversion, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues.
`recursos/mapa_memoria.html` synced (the `0x51FE-0x5478` block).
Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### H53A2_53C7/H53A2_5411 -> .CONTINUAR_AJUSTE_FILA/.SALIR_FUERA_DE_RANGO (local)

Converted `CALCULAR_POSICION_VRAM_ITEM`'s 2 remaining labels to local
(only used inside the same function):

- `H53A2_53C7` -> `.CONTINUAR_AJUSTE_FILA`: twin of
  `.CONTINUAR_AJUSTE_COLUMNA` but for the row (`(D-8) mod 64`).
- `H53A2_5411` -> `.SALIR_FUERA_DE_RANGO`: the common exit point of
  the 4 limit checks (row against `$2C`, column against `$38`) --
  sets carry and returns, exactly as the function's header describes
  ("returns with carry if the position falls out of range").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 618
labels (down 2 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `FINDINGS.md` or `recursos/mapa_memoria.html`.

### CALCULAR_POSICION_VRAM_ITEM in full: data reviewed

At the developer's request, reviewed every numeric literal across the
whole body of `CALCULAR_POSICION_VRAM_ITEM`, converting to decimal
the ones that are pure limits/offsets and adding a comment to every
relevant line:

- `SUB $08` (4 occurrences) -> `SUB 8`: the same camera-relative
  reference offset `PUNTO_REFERENCIA_CAMARA` uses (`+8`), here
  subtracted instead of added.
- `CP $40`/`LD C, $40`/`LD B, $40` -> `64`: half the column/row range
  and the corresponding wrap adjustment (reused afterward as an
  addend to compensate for the wrap).
- `CP $2C` -> `CP 44` and `CP $38` -> `CP 56`: visible row/column
  upper limits.
- `ADD A, $0E` -> `ADD A, 14`: base offset for building the final
  VRAM address (a candidate, the exact reason for this value not
  fully confirmed).
- Left in hex `ADD A, $F8` (signed delta, -8, the same usual
  convention) and `ADC A, $00` (trivial carry propagation).
- Added comments explaining the full flow: clearing the scroll-flag
  bit7 before treating the camera position as a pure coordinate, the
  reason for each wrap adjustment, and the final VRAM address
  computation (column*2+14, row*4-8) with carry propagation from 2
  bits of (IX+4)/(IX+5).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). A purely notation/comment change, no new or renamed
labels -- no need to regenerate the inventory or `.dsk`/`.cas`.

### H5414_5427/H5414_542F/H5414_543A/H5414_5440 -> .COMPROBAR_IZQUIERDA/.COMPROBAR_ABAJO/.COMPROBAR_ARRIBA/.CONSULTAR_LOSETA_DESPLAZADA (local)

Converted `CONSULTAR_LOSETA_LIBRE_DIRECCION`'s bit-decoding chain to
local (an `RRA` cascade that tests each of A's 4 bits, 1/2/4/8, and
applies the corresponding coordinate shift):

- `H5414_5427` -> `.COMPROBAR_IZQUIERDA` (bit1, after ruling out
  right)
- `H5414_542F` -> `.COMPROBAR_ABAJO` (bit2, after ruling out left)
- `H5414_543A` -> `.COMPROBAR_ARRIBA` (bit3, after ruling out down)
- `H5414_5440` -> `.CONSULTAR_LOSETA_DESPLAZADA` (the common
  convergence point of all 4 branches, right before `CALL
  MAPEAR_COORDENADA_A_DIRECCION`/`CONSULTAR_TIPO_LOSETA`)

The other 3 labels in the same family (`H5414_5456`/`H5414_545A`/
`H5414_545C`) were renamed in a later round, see below.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 614
labels (down 4 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `FINDINGS.md` or `recursos/mapa_memoria.html`.

### H5414_5456/H5414_545A/H5414_545C -> .LOSETA_BLOQUEADA/.LOSETA_LIBRE/.FIN_CONSULTA_LOSETA (local)

Converted `CONSULTAR_LOSETA_LIBRE_DIRECCION`'s 3 remaining labels to
local, closing out the tile-type classification:

- `H5414_5456` -> `.LOSETA_BLOQUEADA`: convergence of types 0
  (wall/floor), 7 (tank hint), 8 (power line) and 10 (plane hint) --
  sets A=0 and SCF (carry=blocked).
- `H5414_545A` -> `.LOSETA_LIBRE`: any other type -- A=D (the tested
  direction) and clears carry.
- `H5414_545C` -> `.FIN_CONSULTA_LOSETA`: the common final exit
  (POP DE/POP BC/RET) of both paths.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 611
labels (down 3 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. Also
synced the mention just added in this same file's previous entry. No
mentions in `recursos/mapa_memoria.html`.

### CONSULTAR_LOSETA_LIBRE_DIRECCION in full: data reviewed

At the developer's request, reviewed every numeric literal across the
whole body of `CONSULTAR_LOSETA_LIBRE_DIRECCION`:

- `CP $08`/`CP $07`/`CP $0A` -> `CP 8`/`CP 7`/`CP 10`: tile types,
  already cited in decimal in the header comment ("Types 0... 7...
  8... and 10") -- now the code matches the prose.
- Left in hex the 4 `LD A, $01/$02/$04/$08` (right/left/down/up
  direction codes, the bitmask convention already established
  throughout the session, not pure counts).
- Added a comment to each `LD A, $0X` explaining it saves the
  direction code for the result in D.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). A purely notation/comment change, no new or renamed
labels -- no need to regenerate the inventory or `.dsk`/`.cas`.

### COORD_TO_ADDR -> MAPEAR_COORDENADA_A_DIRECCION

Renamed `COORD_TO_ADDR` to `MAPEAR_COORDENADA_A_DIRECCION` (`$545F`):
converts a coordinate (BC) into the level buffer's address, the exact
same formula as `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (`row*32+column`),
applied here to BC instead of the camera position -- includes the
same v2.0 fix (`$FC60` -> `$FC50`) for the level-13 ball-counter bug.
Name chosen to fit the same family. Watch out when applying: there's
an independent copy `MAPEAR_COORDENADA_A_DIRECCION_LOCAL` (previously
`COORD_TO_ADDR_LOCAL`, renamed separately in a later round) that at
the time contained "COORD_TO_ADDR" as a substring -- NOT touched,
targeted edits instead of `replace_all`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (611
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### ITEM_RNG -> GENERAR_ALEATORIO

Renamed `ITEM_RNG` to `GENERAR_ALEATORIO` (`$5478`): a generic
pseudorandom generator (not item-specific despite the previous name)
-- reads `SEMILLA_ALEATORIA`, mixes it with the Z80's `R` refresh
register via `XOR`, and saves it back. Matches the already-established
`SEMILLA_ALEATORIA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (611
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Also synced the
mention just added in this same file's previous entry. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### ITEM_TABLE_MARICOCO/ITEM_ANIM_TABLE_MARICOCO -> TABLA_ITEMS_MARICOCO/TABLA_ANIMACION_MARICOCO

Renamed following the same pattern already applied to pelmazoide:
`ITEM_TABLE_MARICOCO` -> `TABLA_ITEMS_MARICOCO` (`$549B`, type-1
active table, 2 entries x 7 bytes) and `ITEM_ANIM_TABLE_MARICOCO` ->
`TABLA_ANIMACION_MARICOCO` (`$5487`, 20 bytes, the sprite-by-
direction+phase table, the same confirmed mechanism as
`TABLA_ANIMACION_PELMAZOIDE`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (611
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x5478-0x5904`
block). No mentions in `FINDINGS.md`.

### HNDLR_MARICOCO/HNDLR_REGPUNANTOSO in full + MAPEAR_COORDENADA_A_DIRECCION_LOCAL: renamed as a batch

At the developer's request, completed the parallelism between the 3
mobile-item subunits (pelmazoide already done in earlier rounds, now
ladybug and repugnantoso):

- `MARICOCO_LOOP` -> `BUCLE_MARICOCO`; `MARICOCO_NEXT` ->
  `SIGUIENTE_MARICOCO`; `MARICOCO_SKIP` -> `SIN_REGENERAR_MARICOCO`
  (converges when it's not time to regenerate the pellet).
- `REGPUNANTOSO_LOOP` -> `BUCLE_REGPUNANTOSO`; `REGPUNANTOSO_NEXT` ->
  `SIGUIENTE_REGPUNANTOSO`; `REGPUNANTOSO_SKIP` ->
  `SIN_PLANTAR_REGPUNANTOSO` (converges when it's not time to plant
  the dunked ball).
- `ITEM_TABLE_REGPUNANTOSO` -> `TABLA_ITEMS_REGPUNANTOSO`;
  `ITEM_ANIM_TABLE_REGPUNANTOSO` -> `TABLA_ANIMACION_REGPUNANTOSO`
  (the same pattern already applied to pelmazoide/ladybug).
- `COORD_TO_ADDR_LOCAL` -> `MAPEAR_COORDENADA_A_DIRECCION_LOCAL`
  (`$5559`): a third independent copy of the same formula as
  `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`/`MAPEAR_COORDENADA_A_DIRECCION`,
  with the same v2.0 fix (`$FC60` -> `$FC50`).

Watch out when applying: there are DISTINCT labels `TI_MARICOCO_LOOP`/
`TI_REGPUNANTOSO_LOOP` containing "MARICOCO_LOOP"/"REGPUNANTOSO_LOOP"
as a substring -- NOT touched, targeted edits instead of
`replace_all` for those two.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (611
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `recursos/mapa_memoria.html` synced (the `0x5478-0x5904`
block). Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### GHOST_HINT_HANDLER/CLEAR_5773_AND_SET and family: renamed as a batch

Renamed the whole "hint notice" subsystem:

- `GHOST_HINT_HANDLER` (`$566A`) -> `AVISAR_PROXIMIDAD_PISTA`: checks
  the 3 tank/plane hint entries against the pac-man's position with
  an asymmetric "notice" margin (wider than the tile itself, to
  detect proximity before stepping on it) and sets up the notice via
  `CLEAR_5773_AND_SET`.
- `CLEAR_5773_AND_SET` (`$56CA`) -> `ARMAR_AVISO_DESTELLO`: clears/
  finds a free slot among `$5773`'s 4 entries and saves the notice
  marker.

Converted the whole internal chain to local (exclusive use inside
each function):

- `GHH_LOOP` -> `.BUCLE_PISTA`; `GHH_SKIP` -> `.SIGUIENTE_PISTA`;
  `GHH_5768A` -> `.FORMATO_B` (the same format B already seen in
  `PISTA_FORMATO_B`); `GHH_5694` -> `.FORMATO_B_POS` (parallel to
  `PISTA_FORMATO_B_POS`); `GHH_5699` -> `.FILA_FIJA` (parallel to
  `PISTA_FILA_FIJA`); `GHH_569C` -> `.COMPROBAR_MARGEN_PISTA` (starts
  the asymmetric-margin check).
- `CS_LOOP` -> `.BUCLE_RANURA_AVISO`; `CS_NEXT` ->
  `.SIGUIENTE_RANURA_AVISO`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 603
labels (down 8 from the 8 global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues.
`recursos/mapa_memoria.html` synced (game-state-variables index).
Also synced the mention just added in this same file's previous
entry. Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### ITT_LOOP/ITT_57A8/ITT_57AD/ITT_NEXT -> local in ACTUALIZAR_DESTELLO_ITEMS

Converted `ACTUALIZAR_DESTELLO_ITEMS`'s internal chain to local ("ITT"
= Item Timer Tick, only used inside the same function):

- `ITT_LOOP` -> `.BUCLE_DESTELLO`: walks `$5773`'s 4 active entries.
- `ITT_57A8` -> `.CALCULAR_POSICION_DESTELLO`: computes the VRAM
  position via `CALCULAR_POSICION_VRAM_ITEM` when there's no fixed
  position forced by the special mode.
- `ITT_57AD` -> `.DIBUJAR_FRAME_DESTELLO`: with the position already
  resolved (fixed or computed), indexes `ITEM_TABLE_EFECTOS_DESTELLO`
  by the phase to get the frame/tile and draws with `MOTOR_ACTORES`
  if the position was valid.
- `ITT_NEXT` -> `.SIGUIENTE_DESTELLO`: advances to the next entry.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 599
labels (down 4 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `recursos/mapa_memoria.html`. Mentions in `FINDINGS.md`
(historical narrative from earlier sessions) deliberately left
untouched, same criterion as always.

### IE_57FD/IE_581B/IE_WAIT/IE_5833/IE_584A/IE_5856/IE_5870/IE_587C/IE_5881 -> local in ACTIVAR_EFECTO_ITEM

Converted `ACTIVAR_EFECTO_ITEM`'s whole internal chain to local ("IE"
= Item Effect, decides what to do based on the active special mode
when an item's position matches the pac-man's):

- `IE_57FD` -> `.ACTIVAR_NUEVO_MODO_ESPECIAL`: activates a new
  special mode (no active mode, or re-entry from mode 3/tool).
- `IE_581B` -> `.INICIAR_MODO_ESPECIAL`: sets up the timer, triggers
  event `$6128=8` and moves into waiting.
- `IE_WAIT` -> `.ESPERAR_EVENTO`: actively waits for `$6128` to be
  consumed.
- `IE_5833` -> `.MODO_BOLA_PODER_ACTIVO`; `IE_584A` ->
  `.SUMAR_PUNTOS_MODO1` (adds points + notice + event 7).
- `IE_5856` -> `.MODO_HIPOPOTAMO_ACTIVO`; `IE_5870` ->
  `.SUMAR_PUNTOS_MODO2` (the same closing as mode1, duplicated for
  mode2).
- `IE_587C` -> `.MODO_HERRAMIENTA_ACTIVO`: reuses
  `.ACTIVAR_NUEVO_MODO_ESPECIAL`'s handling.
- `IE_5881` -> `.DELEGAR_AVISO_PISTA`: a fallback exit, delegates to
  `AVISAR_PROXIMIDAD_PISTA`.

Along the way, fixed prose mentions of these labels inside
`ARMAR_AVISO_DESTELLO`'s and `ITEM_TABLE_EFECTOS_DESTELLO`'s header
comments (outside `ACTIVAR_EFECTO_ITEM`'s scope) to use scoped
notation (`ACTIVAR_EFECTO_ITEM.NAME`) instead of the bare local
label, avoiding ambiguity about which function they belong to.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 590
labels (down 9 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `recursos/mapa_memoria.html`. Mentions in `FINDINGS.md`
(historical narrative from earlier sessions) deliberately left
untouched, same criterion as always.

### TI_PELMAZOIDE_LOOP/TI_MARICOCO_LOOP/TI_REGPUNANTOSO_LOOP -> local in INICIALIZAR_ITEMS_NIVEL

Converted the 3 remaining `TI_`-prefix labels to local ("Tabla de
Items"/item table, not to be confused with `ACTUALIZAR_DESTELLO_ITEMS`'s
`ITT_` family, already renamed separately): the 3 loops in
`INICIALIZAR_ITEMS_NIVEL` that reset each item table (pelmazoide/
ladybug/repugnantoso) to the level's initial reference position,
clearing their mode/phase fields. Exclusive use inside this function.

- `TI_PELMAZOIDE_LOOP` -> `.BUCLE_RESET_PELMAZOIDE`
- `TI_MARICOCO_LOOP` -> `.BUCLE_RESET_MARICOCO`
- `TI_REGPUNANTOSO_LOOP` -> `.BUCLE_RESET_REGPUNANTOSO`

These 3 labels were deliberately left untouched in the previous round
(`MARICOCO_LOOP`/`REGPUNANTOSO_LOOP`'s rename) for sharing a substring
with them -- this round closes them out.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 587
labels (down 3 from the global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `recursos/mapa_memoria.html`. Mentions in `FINDINGS.md`
from earlier rounds (which described these labels as "distinct, not
touched" at the time) deliberately left untouched, same criterion as
always.

### ACTUALIZAR_DESTELLO_ITEMS/ACTIVAR_EFECTO_ITEM/INICIALIZAR_ITEMS_NIVEL/CARGAR_NIVEL: data reviewed

At the developer's request, reviewed every numeric literal across
this whole block (`ACTUALIZAR_DESTELLO_ITEMS`, `ACTIVAR_EFECTO_ITEM`,
`INICIALIZAR_ITEMS_NIVEL`/`INICIALIZAR_PARCIAL_ITEMS_NIVEL`,
`CARGAR_NIVEL`), converting to decimal the pure limits/counts/indices
and adding comments:

- `ACTUALIZAR_DESTELLO_ITEMS`: `LD B, $04` -> `4` (`$5773`'s active
  entries). `LD D, $38`/`LD E, $40` -> `56`/`64`: a fixed VRAM
  position that turns out to be exactly the center of the window
  `ACTIVAR_EFECTO_ITEM` checks -- a new detail, noted in the comment.
- `ACTIVAR_EFECTO_ITEM`: the position window's 4 limits ->
  `50`/`62`/`60`/`68` (matches the range now cited in decimal in the
  header). The state/mode comparisons (`H==1`, special mode
  `1`/`2`/`3`, etc.) and the `$6128` event markers (`8`, `7`, `13`)
  also converted -- along the way, fixed the header, which cited
  parameters in hex (`$28`/`$AD`/`$2D`/`$A7`) already out of sync
  with the code (which already used decimal `40`/`45` from an
  earlier round).
- `INICIALIZAR_ITEMS_NIVEL`: entry counts (`7` bytes/entry, `8`/`2`/`8`
  entries per table, `4` entries of `$5773`, `3` hint entries) and
  the tool mode's special value `14` (previously `$0E`, also fixed
  the mention in the function's header).
- `CARGAR_NIVEL`: `LD BC, $0014` -> `20` and both `LD BC, $0060` ->
  `96` (already had the decimal comment, now the code matches).
  `CP $3C` -> `CP 60` (wildcard tile). Left in hex the rest per the
  usual convention: packed addresses/values (`$FC50`, `$1018`),
  bitmasks (`AND $01`/`$80`/`$7F`) and the color/attribute byte `$78`.

**Verified**: recompiled with no errors (9687 lines), diffs at the
exact usual baseline (7/2). A purely notation/comment change, no new
or renamed labels -- no need to regenerate the inventory or
`.dsk`/`.cas`.

### TAIL_INTRO -> GESTIONAR_INTRODUCCION

Renamed `TAIL_INTRO` to `GESTIONAR_INTRODUCCION` (`$5AE9`): manages
the entire intro screen -- turns off the screen, draws the credits
(`DIBUJAR_CREDITOS`, previously `TAIL_CREDITS_DRAW`), turns the
screen back on, and enters a loop of up to 70 iterations (copies a
VRAM/RAM block onto itself) waiting for a key/joystick press (ESC
triggers the hidden infinite-lives trick). When done it draws the
title screen, installs the 3 sound resources and waits again; it's
also the menu dispatcher's return point. "TAIL_" is the prefix of a
broader family (`TAIL_CREDITS_TEXT`/etc.) still untouched.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (587
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### QUEUE_SCREEN_OFF/QUEUE_SCREEN_ON/TAIL_CREDITS_DRAW -> PROGRAMAR_APAGADO_PANTALLA/PROGRAMAR_ENCENDIDO_PANTALLA/DIBUJAR_CREDITOS

Renamed `QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` to
`PROGRAMAR_APAGADO_PANTALLA`/`PROGRAMAR_ENCENDIDO_PANTALLA`: they
don't turn the screen off/on directly -- they only schedule the VDP
register 1 value (`VDP_REG1_PENDING`) that
`ENTRADA_INTERRUPCION_VBLANK` will reread and actually apply on the
next VBLANK. Distinct from `APAGAR_PANTALLA_VDP` (already renamed
earlier, that one DOES write directly). `TAIL_CREDITS_DRAW` (`$5F77`)
-> `DIBUJAR_CREDITOS`: draws the credits screen (clears and writes
the 3 text blocks via `DIBUJAR_TEXTO_VRAM`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (587
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### TI_LOOP -> .BUCLE_ESPERA_INTRO (local)

Converted `TI_LOOP` (inside `GESTIONAR_INTRODUCCION`) to local,
`.BUCLE_ESPERA_INTRO`: on every iteration does an `LDIR` copying
block `$4000` ONTO ITSELF (source=destination=$4000, 16384 bytes) --
no real effect on the data, almost certainly used only as a timing
delay between each key/joystick poll (`COMPROBAR_PULSACION`), up to
70 times or until a press is detected
(`.COMPROBAR_TRUCO_VIDAS_INFINITAS`, previously `TI_BREAK`, renamed
in a later round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 586
labels (down 1 from the global->local conversion, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. No
mentions in `FINDINGS.md`.

### TI_BREAK/TI_WAIT -> .COMPROBAR_TRUCO_VIDAS_INFINITAS/.BUCLE_ESPERA_TIMEOUT (local)

Converted `TI_BREAK` (inside `GESTIONAR_INTRODUCCION`) to local,
`.COMPROBAR_TRUCO_VIDAS_INFINITAS`: checks whether the key that broke
`.BUCLE_ESPERA_INTRO` was ESC (matrix row 7) and, if so, activates
the hidden infinite-lives trick -- live-patches
`BUCLE_PRINCIPAL_JUEGO`'s `SUB $01` instruction (madmix1_body.asm) to
`SUB $00` (losing a life stops subtracting and stops triggering Game
Over), visually confirming with a border-color flash. Whether or not
it's ESC, it falls into `.CONTINUAR_INTRO` (previously `TI_CONT`,
renamed in a later round).

While applying it, the classic local-label-scope trap fired:
`TI_WAIT` (a timeout wait loop, `BC=$2710`) is a GLOBAL label that
fell in between the new local's reference (line 3472) and its
definition (line 3506) -- a "Label not found" error on recompile.
Verified `TI_WAIT` had no other external references and also
converted it to local: `TI_WAIT` -> `.BUCLE_ESPERA_TIMEOUT`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 584
labels (down 2 from the 2 global->local conversions, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. Also
synced the mention just added in this same file's previous entry.
Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### TI_CONT -> .CONTINUAR_INTRO (local)

Converted `TI_CONT` (inside `GESTIONAR_INTRODUCCION`) to local,
`.CONTINUAR_INTRO`: the convergence point after the infinite-lives-
trick check (triggered or not) -- waits for the key to be released
(`ESPERAR_TECLA_SOLTADA`, previously `TAIL_KEYWAIT_UP`), draws the
candy frame (`DIBUJAR_MARCO_CARAMELO_VRAM`), and falls into
`MOSTRAR_MENU_PRINCIPAL` (previously `TI_5B56`, renamed in a later
round) -- that one IS still global, called externally from
`REINICIAR_PARTIDA` in `madmix1_body.asm`). Along the way, fixed a
prose mention out of scope (`PROGRAMAR_APAGADO_PANTALLA`/
`PROGRAMAR_ENCENDIDO_PANTALLA`'s header, much further up in the file)
to scoped notation (`GESTIONAR_INTRODUCCION.CONTINUAR_INTRO`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 583
labels (down 1 from the global->local conversion, the already-
expected pattern). `.dsk`/`.cas` regenerated with no issues. Also
synced the mention just added in this same file's previous entry.
Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### TAIL_KEYWAIT_UP/TAIL_KEYWAIT_RELEASE -> ESPERAR_TECLA_SOLTADA/ESPERAR_TECLA_PULSADA

Renamed, fixing a MISLEADING name detected while analyzing them:
`TAIL_KEYWAIT_UP` (`$5D04`) -> `ESPERAR_TECLA_SOLTADA` (waits while
`COMPROBAR_PULSACION` returns NZ -- key pressed -- until there's none
anymore, the original name DID describe this one correctly), but
`TAIL_KEYWAIT_RELEASE` (`$5CFE`) -> `ESPERAR_TECLA_PULSADA`: despite
its previous name ("RELEASE"), it actually waits while
`COMPROBAR_PULSACION` returns Z (nothing pressed) until a press is
detected -- that is, it waits for a key to be PRESSED, not released.
This is clear from the typical joint usage (`CALL
ESPERAR_TECLA_SOLTADA` followed by `JP ESPERAR_TECLA_PULSADA`): first
it waits for the current key to be released, then it waits for the
next press -- the second one's old name described the wrong function.
Also updated both header comments to reflect the real behavior
separately (previously a single ambiguous line, "Waits to release a
key / to press a key").

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (583
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### TAIL_VDP_CLEAR/TAIL_LEVELCYCLE_HELPER_ALT/TI_5B62/TAIL_MAINMENU_DRAW/TAIL_FONT_ROUTINE/TI_5BA7/TVF_LOOP: renamed as a batch

Renamed 7 labels of the menu/intro flow:

- `TAIL_VDP_CLEAR` (`$5CA0`) -> `LIMPIAR_VRAM_AREA_JUEGO`: clears
  VRAM's main area (patterns $2000-$37FF) after filling the work
  buffer.
- `TAIL_LEVELCYCLE_HELPER_ALT` (`$647C`) -> `APLICAR_COLOR_CICLO_NIVELES`:
  a variant of `APLICAR_COLOR_PANTALLA` for the sample-level cycler
  (BC=704 instead of 768, same loop).
- `TI_5B62` -> `REINICIAR_TIMEOUT_MENU`: resets the menu's timeout to
  its default value (500 frames) and falls into drawing the menu.
- `TAIL_MAINMENU_DRAW` (`$5BCC`) -> `DIBUJAR_MENU_PRINCIPAL`: draws
  the main menu's 5 lines of text.
- `TAIL_FONT_ROUTINE` (`$5C80`) -> `LEER_TECLAS_MENU_PRINCIPAL`:
  despite the previous name, it's the reader for the menu's 6
  navigation keys (a name already proposed in a comment in an earlier
  round).
- `TI_5BA7` -> `DESPACHAR_ACCION_MENU`: dispatches by A's bit to the
  4 menu variants (pause/fire, etc.).
- `TVF_LOOP` (inside `RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`,
  exclusive use there) -> `.BUCLE_RELLENAR_FILA` (local): walks the
  buffer's 144 rows, filling each one.

`TI_5B62`/`TI_5BA7` could NOT be converted to
`GESTIONAR_INTRODUCCION` locals despite being conceptually part of
its flow, because a distinct global label
(`RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`) falls in between, breaking
the scope.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 582
labels (down 1 from `TVF_LOOP`'s global->local conversion, the
already-expected pattern). `.dsk`/`.cas` regenerated with no issues.
`recursos/mapa_memoria.html` synced (the RAM bitmap canvas block).
Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### TI_5B56 -> MOSTRAR_MENU_PRINCIPAL

Renamed `TI_5B56` to `MOSTRAR_MENU_PRINCIPAL` (`$5B56`):
`.CONTINUAR_INTRO`'s real second entry point, called externally from
`REINICIAR_PARTIDA` in `madmix1_body.asm` -- skips the key wait and
the candy-frame drawing (not applicable on a real game start), and
goes straight to preparing and showing the main menu. Being a cross-
file reference, also updated the real call and its comment in
`madmix1_body.asm` (`REINICIAR_PARTIDA`, ~line 2452), which also cited
in a chain several old names already renamed in earlier rounds
(`TAIL_INTRO`, `TAIL_KEYWAIT_UP`, `QUEUE_SCREEN_OFF`, `TAIL_VDP_CLEAR`,
`TAIL_LEVELCYCLE_HELPER_ALT`, `TAIL_MAINMENU_DRAW`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (582
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `src/FLUJO_PROGRAMA.md` synced (2 mentions, one inside an
ASCII-box diagram -- padding recomputed to keep the 65-character box
width). Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### TI_5B65 -> ACTUALIZAR_MENU_PRINCIPAL

Renamed `TI_5B65` to `ACTUALIZAR_MENU_PRINCIPAL` (a name chosen by
the developer, consistent with the pattern already used in
`ACTUALIZAR_VRAM_FRAME`/`ACTUALIZAR_DESTELLO_ITEMS` for periodic-
refresh routines, instead of `ACTIVAR_X` which would suggest a one-
shot trigger): the point where both the menu's start (timeout just
reset by `REINICIAR_TIMEOUT_MENU`) and every subsequent cycle pass
converge -- saves the timeout to `$6043`, draws the menu, turns the
screen on, reads the navigation keys and dispatches the corresponding
action; re-runs every frame while the menu is active.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (582
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `src/FLUJO_PROGRAMA.md` synced (2 direct mentions); that
section also has MANY other out-of-sync names from earlier rounds
(`PATCH_OFF_10D8`, `TAIL_MAINMENU_DRAW`, `TAIL_FONT_ROUTINE`,
`TI_5BA7`, `TAIL_INTRO`, etc.) out of scope for this round -- a
separate pending cleanup. No mentions in `recursos/mapa_memoria.html`.
Mentions in `FINDINGS.md` (historical narrative from earlier
sessions) deliberately left untouched, same criterion as always.

### GESTIONAR_INTRODUCCION/RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM: data reviewed

At the developer's request, reviewed every numeric literal across the
whole block of `GESTIONAR_INTRODUCCION` and
`RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`:

- `LD B, $46` -> `LD B, 70` (wait-loop iterations, already documented
  in decimal in an earlier rename round).
- `LD BC, $2710` -> `LD BC, 10000` (timeout frames before returning to
  the intro).
- `CP $07` -> `CP 7` (keyboard matrix row 7).
- `LD B, $90` -> `LD B, 144` (buffer rows, already cited in decimal
  in the header comment), `LD BC, $0017` -> `23` (playable-area bytes
  per row) and `LD BC, $0020` -> `32` (row step, same pattern as the
  rest of the engine).
- FINDING of "hex not substituted with an already-existing label"
  (the same systemic pattern from earlier rounds, this time crossing
  files): `CALL $1000` -> `CALL DIBUJAR_PORTADA` (this file's own
  label, already used that way in `madmix1_body.asm`/`load_disk`/
  `load_cas` but never fixed here) and `LD DE, $CDCB`/`$CDFF`/`$CE0C`
  -> `GUION_MELODIA_CANAL_0`/`_1`/`_2` (labels from `madmix1_body.asm`,
  the same namespace when compiling everything in a single pass via
  `main.asm`). Also converted to decimal the indices `LD A,
  $01`/`$02` -> `1`/`2` in the calls to `INSTALAR_RECURSO_SONIDO`,
  matching what `INICIO` (`madmix1_body.asm`) already had.
- One more `CALL $1000` remains unfixed in this same file (line
  ~4410, a different function, out of scope for this round's block).
- Left the rest in hex per the usual convention: addresses (`$4000`,
  `$909A`), the fill sentinel (`$FF`), and the key/VDP-color codes
  (`$EB`, `$06`, `$01` in `FIJAR_COLOR_BORDE_VDP` -- matrix/palette
  codes, not counts).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2) -- confirms the 4 hex-to-label substitutions resolve
to the exact same addresses as the original hex. A purely notation/
comment/existing-label change, no new or renamed labels -- no need to
regenerate the inventory or `.dsk`/`.cas`.

### TI_5C3A/TI_5C53/TI_5C60/TI_5C70 -> SELECCIONAR_OPCION_*

Renamed the main menu's 4 selection routines (each self-modifies
`TEXTO_MENU_PRINCIPAL`'s (previously `MAINMENU_TEXT`) attribute bytes
to highlight the current option):

- `TI_5C3A` (option 3, redefine keys) -> `SELECCIONAR_OPCION_REDEFINIR_TECLAS`
- `TI_5C53` (option 4, demo) -> `SELECCIONAR_OPCION_DEMO`
- `TI_5C60` (option 1, keyboard) -> `SELECCIONAR_OPCION_TECLADO`
- `TI_5C70` (option 2, joystick) -> `SELECCIONAR_OPCION_JOYSTICK`

All 4 have to stay global: between `DESPACHAR_ACCION_MENU` and them
there are 2 intermediate global labels (`GESTIONAR_TIMEOUT_MENU`,
previously `TAIL_BITDISPATCH_END`, `DIBUJAR_MENU_PRINCIPAL`) that
would break the scope if converted to local.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `src/FLUJO_PROGRAMA.md` synced (the 4-menu-options
table). No mentions in `recursos/mapa_memoria.html`. Mentions in
`FINDINGS.md` (historical narrative from earlier sessions)
deliberately left untouched, same criterion as always.

### TAIL_BITDISPATCH_END -> GESTIONAR_TIMEOUT_MENU

Renamed `TAIL_BITDISPATCH_END` to `GESTIONAR_TIMEOUT_MENU`: the point
that's fallen into (nobody jumps here explicitly) when none of the
menu's 4 options matched the key read in `DESPACHAR_ACCION_MENU`.
Manages the menu's timer: if `A!=0` (some other, unrecognized key) it
resets the timeout and shows the menu again; if `A==0` (no key)
decrements the counter and, on reaching 0, returns to
`GESTIONAR_INTRODUCCION` (attract mode) instead of waiting forever.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (582
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. Also synced the mention just added in this same file's
previous entry. Mentions in `FINDINGS.md` (historical narrative from
earlier sessions) deliberately left untouched, same criterion as
always.

### MAINMENU_TEXT -> TEXTO_MENU_PRINCIPAL

Renamed `MAINMENU_TEXT` to `TEXTO_MENU_PRINCIPAL`: the main menu's 5
text records ("1 KEYBOARD", "2 JOYSTICK", "3 REDEFINE KEYS", "4
DEMO", "0 PLAY"), drawn by `DIBUJAR_MENU_PRINCIPAL`. The same
already-established `TEXTO_X` pattern (`TEXTO_FASE`, `TEXTO_READY`,
`TEXTO_GAME_OVER`, `TEXTO_DEMO`, `TEXTO_BESTIA`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (582
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. `src/FLUJO_PROGRAMA.md` synced (1 mention). Also synced the
mention just added in this same file's previous entry. No mentions in
`recursos/mapa_memoria.html`.

### pattern_loop -> .BUCLE_VOLCAR_PATRON_PORTADA (local)

Renamed the local loop `.pattern_loop` (inside `DIBUJAR_PORTADA`) to
`.BUCLE_VOLCAR_PATRON_PORTADA`: flushes `PORTADA_PATRON`'s 6144 bytes
byte by byte to the VRAM pattern table ($0000).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (621
labels, no change in total). `.dsk`/`.cas` regenerated with no
issues. No mentions in `FINDINGS.md`.

### TAIL_KEYMENU_DRAW/TAIL_LEVELCYCLE_MAIN/TAIL_UNK_5C93/TAIL_VDP_PATTERN_WRITE renamed

Renamed the last 4 `TAIL_`-family labels in this menu/demo area:

- `TAIL_KEYMENU_DRAW` (`$5D1F`) -> `DIBUJAR_MENU_REDEFINIR_TECLAS`:
  draws the entire key-redefinition submenu.
- `TAIL_LEVELCYCLE_MAIN` (`$6045`) -> `GESTIONAR_CICLO_NIVELES`: the
  sample-level cycler engine (demo mode, option 4).
- `TAIL_UNK_5C93` -> `TABLA_TECLAS_MENU_PRINCIPAL`: a 12-byte table (6
  row/mask pairs, all row `$F0`) used by `LEER_TECLAS_MENU_PRINCIPAL`
  to read the main menu's 6 selection keys.
- `TAIL_VDP_PATTERN_WRITE` (`$5CAF`) -> `ESCRIBIR_PATRON_VRAM`: writes
  an 8-row pattern to VRAM via a double `FILVRM`/`LDIRVM`.

At the developer's request, also reorganized `TABLA_TECLAS_MENU_PRINCIPAL`
into 6 `DB` lines (one pair per line, the same format as
`TABLA_TECLAS_MSX`) with a comment per pair noting which final bit of
the result it corresponds to and which menu option it triggers
(deduced by tracing `ESCANEAR_FILAS_TECLADO` -- each `RL E` shifts the
already-read bits, so the LAST pair in the table ends up in the
result's bit 0 and the FIRST in the highest bit -- and
`DESPACHAR_ACCION_MENU`, which checks bits 5/1/3/4). FINDING: pairs 4
and 5 of the table are IDENTICAL (`$F0,$08` both) -- they read the
same key twice; the bit pair 4 produces (result bit 2) isn't checked
anywhere, a dead/wasted bit in the original design.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated (582
labels, no change in total, all 4 are 1:1 renames). `.dsk`/`.cas`
regenerated with no issues. The only mention in
`recursos/mapa_memoria.html` (`TAIL_LEVELCYCLE_MAIN` in the
`0xD524-0xD6B6` block) synced. `src/FLUJO_PROGRAMA.md` not touched:
all 4 labels only appear inside section 5.8's large paragraph, already
flagged as out of sync and out of scope in an earlier round (it still
contains many other outdated names, e.g. `TI_5BA7`, `TAIL_INTRO`,
`TAIL_FONT_ROUTINE`) -- a separate pending cleanup, same criterion as
always.

### TD_LOOP/TD_SKIP/TD_INCDE -> local to DIBUJAR_TEXTO_VRAM

Confirmed by grep that the 3 labels are purely internal to
`DIBUJAR_TEXTO_VRAM` (no other file references them), converted to
local:

- `TD_LOOP` -> `.BUCLE_CARACTER`: the main loop that walks the `C`
  "characters" of the text record; if the byte read is `>=$20` (a real
  pattern code) calls `ESCRIBIR_PATRON_VRAM` and advances `HL` 8
  columns.
- `TD_SKIP` -> `.SALTAR_COLUMNAS`: FINDING -- bytes `<$20` are NOT
  printable characters, they're a COUNT of 8px blank columns to skip
  (the byte itself is used as the loop's count, adding 8 to `L` each
  pass). It's this game's text format's gap/spacing mechanism.
- `TD_INCDE` -> `.CONTINUAR_CARACTER`: a tail shared by both paths
  (advances `DE`, decrements `C`, repeats `.BUCLE_CARACTER` or exits
  with `EI`/`RET`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 579
labels (582 -> 579, -3 for the 3 global->local conversions).
`.dsk`/`.cas` regenerated with no issues. No mentions in
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.

### LIMPIAR_VRAM_AREA_JUEGO/ESCRIBIR_PATRON_VRAM/DIBUJAR_TEXTO_VRAM: data reviewed

At the developer's request, reviewed every numeric literal across the
whole block (`LIMPIAR_VRAM_AREA_JUEGO`, `ESCRIBIR_PATRON_VRAM`,
`DIBUJAR_TEXTO_VRAM`):

- `LD BC, $1800` -> `LD BC, 6144` (the full size of the VRAM pattern
  table, `$2000-$37FF`, already cited in decimal in the previous
  routine's header comment).
- `LD BC, $0008` (x2, in `ESCRIBIR_PATRON_VRAM`) and `LD A, $08` (x2,
  in `DIBUJAR_TEXTO_VRAM`) -> `8` (the same "8 columns/8 rows" stride
  already documented in the header comments).
- `LD H, $00` / `ADC A, $00` -> `0`.
- `LD HL, $2000`/`LD DE, $925B`/`CP $20` left in hex (VRAM/RAM
  addresses and the character-code threshold). `LD A, $01` in
  `LIMPIAR_VRAM_AREA_JUEGO` also left in hex: it isn't a counter, it's
  the actual bit pattern (bit 0 set) `FILVRM` flushes into every byte
  of the pattern table.
- FINDING (architecture, not just format): `DIBUJAR_TEXTO_VRAM`'s
  header "2nd byte" (saved in `AF'` with the first `EX AF,AF'`) wasn't
  used anywhere VISIBLE in the main loop -- it's retrieved inside
  `ESCRIBIR_PATRON_VRAM` (its own `EX AF,AF'`+`PUSH AF`) right before
  the second `FILVRM`/`SET 5,H` half. That is: the text record doesn't
  just carry the character count and the code table, it also carries
  the color/attribute value to fill into the "color" half of each
  8-row pattern -- now documented in both routines' header comments.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (`gen_inventory.py` doesn't apply).
`.dsk`/`.cas` regenerated with no issues.

### TJR_LOOP -> .BUCLE_FILA (local to COMPROBAR_PULSACION)

Renamed `TJR_LOOP` (`$5D0C`) to `.BUCLE_FILA`, local to
`COMPROBAR_PULSACION` (`$5D0A`, no external references confirmed by
grep): walks the keyboard matrix's 9 rows (0-8), selecting each one
via port `$AA` (preserving the high nibble with `AND $F0` and adding
the row number) and reading columns via `$A9`; exits with `NZ` if it
finds any key pressed in the current row, or with `Z` if it exhausts
all 9 rows without finding one.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 578
labels (579 -> 578, -1 for global->local). `.dsk`/`.cas` regenerated
with no issues. No mentions in `FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.

### TAIL_FONT_CLEAR/TAIL_FONT_SELECT/TAIL_KEYMENU_HILITE + DIBUJAR_MENU_REDEFINIR_TECLAS's locals renamed

Renamed the rest of the key-redefinition submenu block:

- `TAIL_FONT_CLEAR` (`$5EDA`) -> `REINICIAR_TECLAS_USADAS`: despite
  the name it has nothing to do with fonts -- clears (`RES 7`) the 72
  positions of a "used" table (reuses the shared tile-type table
  `$8E88` as scratch) before starting to detect new presses.
- `TAIL_FONT_SELECT` (`$5EEB`) -> `ESPERAR_TECLA_NUEVA`: walks the
  keyboard matrix's 9 rows looking for the first NEW key (bit 7 clear
  in its "used" table entry), marks it and writes that key's real
  row/mask pair into the redefinition buffer, also saving a linear
  index (0-71) at `$5F76`.
- `TAIL_KEYMENU_HILITE` (`$5DF1`) -> `DIBUJAR_NOMBRE_TECLA_ASIGNADA`:
  looks up entry number `B` in the key-name table (`$5E56`) and jumps
  to `DIBUJAR_TEXTO_VRAM` to draw it. Its internal local loop
  `KH_LOOP` -> `.BUCLE_BUSCAR_NOMBRE`.
- `KMD_5D46`/`KMD_5D67`/`KMD_5D88`/`KMD_5DA9`/`KMD_5DCA` (reunion
  points between `DIBUJAR_MENU_REDEFINIR_TECLAS`'s 6 near-identical
  blocks, one per redefinable action) -> local
  `.CONTINUAR_TECLA_2`.`.CONTINUAR_TECLA_3`.`.CONTINUAR_TECLA_4`.
  `.CONTINUAR_TECLA_5`.`.CONTINUAR_TECLA_6`.
- `KMD_5DEB` -> `.FIN_DIBUJAR_MENU`: besides closing out the 6th
  block, it's the function's real tail (waits to release and then
  press a key before exiting).

All the local ones confirmed to have no external references by grep
before converting.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 571
labels (578 -> 571, -7 for the 7 global->local conversions: 6
`KMD_*` + `KH_LOOP`; the other 3 are 1:1 global renames). `.dsk`/`.cas`
regenerated with no issues. No mentions in `FINDINGS.md`.
`src/FLUJO_PROGRAMA.md` NOT touched: `TAIL_KEYMENU_HILITE`/
`TAIL_FONT_SELECT` only appear inside that same section 5.8 large
paragraph, already flagged as out of sync and out of scope in earlier
rounds.

### KEYMENU_TEXT_5E03 -> TEXTO_MENU_REDEFINIR_TECLAS

Renamed `KEYMENU_TEXT_5E03` (`$5E03`-`$5ED9`, 215 bytes) to
`TEXTO_MENU_REDEFINIR_TECLAS`: the key-redefinition submenu's full
text table -- the 6 action names (PAUSE, FIRE, UP, DOWN, LEFT, RIGHT)
followed by ~28 assignable key names, each record in
`[length][attribute][ASCII text]` format. The same already-established
`TEXTO_X` pattern (`TEXTO_MENU_PRINCIPAL`, `TEXTO_FASE`...).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (571, a 1:1 rename). `.dsk`/`.cas`
regenerated with no issues. Mentions in `src/README.md` (struck-
through checklist, historical narrative) and `src/FLUJO_PROGRAMA.md`
(the same already-out-of-sync section 5.8 paragraph) left untouched,
same criterion as always.

### TFC_LOOP -> .BUCLE_LIMPIAR_MARCAS (local to REINICIAR_TECLAS_USADAS)

Renamed `TFC_LOOP` to `.BUCLE_LIMPIAR_MARCAS`, local to
`REINICIAR_TECLAS_USADAS` (no external references confirmed by grep):
walks table `$5F2C`'s 72 positions clearing bit 7 (the "used" mark)
of each one.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 570
labels (571 -> 570, -1 for global->local). `.dsk`/`.cas` regenerated
with no issues. No mentions in `FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.

### REINICIAR_TECLAS_USADAS: data reviewed + finding "does $8E88 have no label?"

At the developer's request, reviewed `REINICIAR_TECLAS_USADAS`'s
literals: `LD B, $48` -> `LD B, 72` (number of entries to clear).
Along the way, the developer asked whether `$8E88` (used as the
scratch buffer's base address) had a label of its own -- CONFIRMED:
it's exactly `TABLA_TECLAS_MSX` (`madmix1_body.asm:2333`, the same
namespace when compiling via `main.asm`), the same "hex not
substituted with an already-existing label" systemic pattern from
earlier rounds. Fixed `LD HL, $8E88` -> `LD HL, TABLA_TECLAS_MSX`.

Additional FINDING: the routine's header comment ("clears the shared
tile-type table $8E88") was an old, WRONG hypothesis -- there's no
tile-type table at that address (the real ones live at `$2E3C`/
`$FC50`, unrelated). The comment was fixed to reflect that it
actually reuses `TABLA_TECLAS_MSX` as a scratch buffer.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same address byte, only the source changes). No label
changes. `.dsk`/`.cas` regenerated with no issues.

### TFS_ROW0/TFS_ROW/TFS_BIT/TFS_NEXTBIT/TFS_SHIFT/TFS_FOUND -> local to ESPERAR_TECLA_NUEVA + FINDING: TABLA_TECLAS_MSX is the redefinition's real destination

Renamed `ESPERAR_TECLA_NUEVA`'s 6 internal labels, all local (no
external references confirmed by grep):

- `TFS_ROW0` -> `.REINICIAR_ESCANEO`: the full-scan reset point
  (`DE=$F000`, starting row + linear index to 0).
- `TFS_ROW` -> `.BUCLE_FILA`: the row loop (selects the row on `$AA`,
  reads columns from `$A9`).
- `TFS_BIT` -> `.BUCLE_BIT`: the row's bit loop; if it's 0 (key
  pressed) jumps to handle it.
- `TFS_NEXTBIT` -> `.TECLA_DETECTADA`: rebuilds the real bitmask and
  writes the row/mask pair.
- `TFS_SHIFT` -> `.BUCLE_CONSTRUIR_MASCARA`: a loop that rebuilds the
  single-bit mask from the position where the bit loop broke.
- `TFS_FOUND` -> `.TECLA_NUEVA`: the key wasn't already used -- marks
  it, saves its value to `$5F76` and updates the write pointer.

An architecture FINDING (not just naming): the write pointer
(`$5F74`) `.TECLA_DETECTADA` uses to flush each detected row/mask pair
points to `TABLA_TECLAS_MSX` (`madmix1_body.asm`, see this same
file's previous round) -- and it's NOT a scratch buffer as thought in
the previous round: it's the REAL DESTINATION of the redefinition.
There are exactly 6 redefinable actions = 6 row/mask pairs = 12 bytes
= `TABLA_TECLAS_MSX`'s exact size, so the redefinition submenu
live-overwrites, byte by byte, the real table `LEER_TECLADO` uses to
read up/down/left/right/fire/pause. Comments fixed in
`REINICIAR_TECLAS_USADAS`/`ESPERAR_TECLA_NUEVA` to reflect this. Also,
the 72-"mark" table at `$5F2C` cleared by `REINICIAR_TECLAS_USADAS`
turned out to be `FONT_CHARSET_5F2C` (renamed to `TABLA_CODIGOS_TECLA`
in the next round, see below): its 72 real data bytes (digits/
symbols/A-Z + 24 special codes) serve as a "valid character map", and
the "key used" mechanism reuses bit 7 (always 0 in those values) as
an overlaid flag.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 564
labels (570 -> 564, -6 for the 6 global->local conversions).
`.dsk`/`.cas` regenerated with no issues. No mentions in
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.

### FONT_CHARSET_5F2C -> TABLA_CODIGOS_TECLA + reorganized into 9 rows with comments

Renamed `FONT_CHARSET_5F2C` to `TABLA_CODIGOS_TECLA`: FIXED, it isn't
a font/bitmap -- it's the map from 72 keyboard-scan positions (row x8+
bit, the same order as `ESPERAR_TECLA_NUEVA`) to that key's identity.
Deciphered row by row by cross-checking the data with the scan order:

- Rows `$F0`-`$F5` (48 bytes): that key's real printable ASCII glyph
  (digits, symbols, A-Z), passable as-is to `ESCRIBIR_PATRON_VRAM`.
- Rows `$F6`-`$F8` (24 bytes): a special code `1`-`24`, an index into
  `TEXTO_MENU_REDEFINIR_TECLAS` for non-printable keys (hence
  `DIBUJAR_MENU_REDEFINIR_TECLAS`'s `CP $24`: decides between drawing
  the full name or the loose glyph).
- 3 final padding bytes, never reached (the real scan only covers 72
  positions).

At the developer's request, reorganized from a flat hex block into 9
lines (one per keyboard row), with a per-row comment; the 6 rows of
printable glyphs as string literals (`DB "01234567"`, etc, except for
the loose backslash/braces/semicolon of row `$F1` and the `:`/space
of row `$F2`, split into character/hex literals to avoid breaking the
string) and the 3 rows of special codes in decimal (they're indices,
not masks). Verified SjASMPlus accepts `\`/`{`/`}`/`;` inside a string
literal with no escaping needed. Also substituted the 2 unlabeled
uses of `$5F2C` (in `REINICIAR_TECLAS_USADAS`/`ESPERAR_TECLA_NUEVA`)
with `TABLA_CODIGOS_TECLA`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes, only format/label changes). No label
changes (564, a 1:1 rename). `.dsk`/`.cas` regenerated with no
issues. The mention in `src/FLUJO_PROGRAMA.md` NOT touched (the same
already-out-of-sync section 5.8 paragraph). An old mention in
`FINDINGS.md` (line ~4353, historical narrative from a much earlier
session) left untouched; the mention from the previous entry (this
same session) fixed above going forward.

### FINDING: the "3 padding bytes" after TABLA_CODIGOS_TECLA were PUNTERO_ESCRITURA_TECLA/CODIGO_TECLA_ACTUAL

At the developer's request, reviewed the loose hex addresses
(`$5F74`/`$5F76`) in the `REINICIAR_TECLAS_USADAS`/
`ESPERAR_TECLA_NUEVA`/`DIBUJAR_MENU_REDEFINIR_TECLAS` block. They
didn't match any previous label, but they DID fit by offset: the 3
bytes left as "padding, never reached" at the end of
`TABLA_CODIGOS_TECLA` (`$5F74`-`$5F76`, right after its 72 real
entries `$5F2C`-`$5F73`) are NOT inert padding -- they're exactly the
size of the two real variables this same code block uses. Confirmed
by exact arithmetic: `DIBUJAR_CREDITOS` starts at `$5F77` = `$5F74`+3.

Split those 3 bytes into two labels of their own (same initial value
0, same bytes):
- `PUNTERO_ESCRITURA_TECLA` (word, `$5F74`-`$5F75`): the write
  pointer into `TABLA_TECLAS_MSX` during redefinition.
- `CODIGO_TECLA_ACTUAL` (byte, `$5F76`): the currently assigned key's
  code, also read by `DIBUJAR_MENU_REDEFINIR_TECLAS`.

Substituted every use of `$5F74`/`$5F76` (code and comments) with the
new labels.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes -- the address arithmetic was exact).
`recursos/flujo_programa.html` regenerated: 566 labels (564 -> 566,
+2 for the 2 new labels). `.dsk`/`.cas` regenerated with no issues.
No mentions in `src/FLUJO_PROGRAMA.md`.

### Own labels for each TEXTO_MENU_REDEFINIR_TECLAS record referenced by address

At the developer's request, reviewed the hex addresses inside
`TEXTO_MENU_REDEFINIR_TECLAS`'s range (`$5E03`-`$5ED9`). Found 7, the
6 used in `DIBUJAR_MENU_REDEFINIR_TECLAS` (as `DE` for
`DIBUJAR_TEXTO_VRAM`, each pointing to a redefinable action's record)
plus 1 in `DIBUJAR_NOMBRE_TECLA_ASIGNADA` (the start of the key-name
sub-section indexed by `B`). Instead of expressing them as
`TABLE+offset`, a label of its own was created for each referenced
record (the same criterion as `GUION_MELODIA_CANAL_0/1/2` in
`madmix1_body.asm`: distinct data pieces inside the same block, each
with its own label):

- `$5E0A` (FIRE) -> `TEXTO_TECLA_FUEGO`
- `$5E11` (UP) -> `TEXTO_TECLA_ARRIBA`
- `$5E19` (DOWN) -> `TEXTO_TECLA_ABAJO`
- `$5E20` (LEFT) -> `TEXTO_TECLA_IZQUIERDA`
- `$5E2B` (RIGHT) -> `TEXTO_TECLA_DERECHA`
- `$5E03` (PAUSE) -> already had a label: it's
  `TEXTO_MENU_REDEFINIR_TECLAS`'s own start, only the hex was
  substituted with it.
- `$5E56` (start of the assignable-key-name sub-table, indexed by
  `TABLA_CODIGOS_TECLA`'s special code 1-24) ->
  `TABLA_NOMBRES_TECLA_ASIGNABLE` (matches exactly the degenerate
  entry `DB $01,$01,$01`, right after `ENTER`).

Precedent deliberately NOT applied to `TEXTO_MENU_PRINCIPAL`/
`DIBUJAR_MENU_PRINCIPAL` (the same 5-hex-`DE`-pointer pattern): left
as a possible separate round, not requested this time.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes -- exact offsets). `recursos/flujo_programa.html`
regenerated: 572 labels (566 -> 572, +6 new labels). `.dsk`/`.cas`
regenerated with no issues. No mentions in `src/FLUJO_PROGRAMA.md`.

### Labeled EVERY entry of TEXTO_MENU_REDEFINIR_TECLAS, including the ones with no current references

At the developer's request, labeled the table's 24 remaining entries
that still had no label of their own (some with no reference anywhere
in the currently transcribed code):

- `TEXTO_TECLA_ESPACIO_1`/`TEXTO_TECLA_SSHIFT`/`TEXTO_TECLA_CSHIFT`/
  `TEXTO_TECLA_ENTER_1`: the 4 entries between `DERECHA` and
  `TABLA_NOMBRES_TECLA_ASIGNABLE` -- no current references.
- The 24 entries indexed by `TABLA_CODIGOS_TECLA`'s special code 1-24
  (`DIBUJAR_NOMBRE_TECLA_ASIGNADA`'s real destination):
  `TEXTO_TECLA_SHIFT`(1), `_CTRL`(2), `_GRAPH`(3), `_CAPS`(4),
  `_CODE`(5, FINDING: empty text -- a single space -- in the position
  corresponding to CODE in the standard SHIFT/CTRL/GRAPH/CAPS/CODE
  row), `_F1`..`_F5`(6-10), `_ESCAPE`(11), `_TAB`(12), `_STOP`(13),
  `_BS`(14), `_SELECT`(15), `_ENTER_2`(16, a duplicate of `_ENTER_1`),
  `_ESPACIO_2`(17, a duplicate of `_ESPACIO_1`), `_HOME`(18), `_INS`(19),
  `_DEL`(20), `_EXCLAMACION`(21), `_COMILLAS`(22), `_ALMOHADILLA`(23),
  `_DOLAR`(24).

Each entry with a comment noting its special code (or "no current
references" for the 4 before the indexed section). Data format
unchanged (same strings/bytes, only labels added).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes). `recursos/flujo_programa.html`
regenerated: 600 labels (572 -> 600, +28 new labels). `.dsk`/`.cas`
regenerated with no issues. No mentions in
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.

### Added TEXTO_TECLA_PAUSA (same address as TEXTO_MENU_REDEFINIR_TECLAS)

The developer pointed out that a label of its own was missing for the
PAUSE entry, even though it coincides with the table's global label's
address. Added `TEXTO_TECLA_PAUSA:` right below
`TEXTO_MENU_REDEFINIR_TECLAS:` (same byte, two labels at the same
address, the same pattern as the rest of the named entries).
Substituted `DIBUJAR_MENU_REDEFINIR_TECLAS`'s `LD DE,
TEXTO_MENU_REDEFINIR_TECLAS` with `LD DE, TEXTO_TECLA_PAUSA`,
consistent with the other 5 actions.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes). `recursos/flujo_programa.html`
regenerated: 601 labels (600 -> 601, +1). `.dsk`/`.cas` regenerated
with no issues.

### Same treatment for TEXTO_MENU_PRINCIPAL/DIBUJAR_MENU_PRINCIPAL

At the developer's request, applied `TEXTO_MENU_REDEFINIR_TECLAS`'s
same criterion to the twin table `TEXTO_MENU_PRINCIPAL` (deliberately
left pending in an earlier round): a label of its own for each of the
5 records, including the first one (coincides with the table's global
label's address, the same pattern as `TEXTO_TECLA_PAUSA`):

- `$5BF9` (KEYBOARD) -> `TEXTO_OPCION_TECLADO` (same address as
  `TEXTO_MENU_PRINCIPAL`)
- `$5C06` (JOYSTICK) -> `TEXTO_OPCION_JOYSTICK`
- `$5C14` (REDEFINE KEYS) -> `TEXTO_OPCION_REDEFINIR_TECLAS`
- `$5C27` (DEMO) -> `TEXTO_OPCION_DEMO`
- `$5C2F` (PLAY) -> `TEXTO_OPCION_JUGAR`

Substituted `DIBUJAR_MENU_PRINCIPAL`'s 5 `LD DE,`. Along the way,
also substituted the attribute bytes self-modified by the 4
`SELECCIONAR_OPCION_*` routines (`$5BFA`/`$5C07`, offset +1 of the
first two entries) with `TEXTO_OPCION_TECLADO+1`/
`TEXTO_OPCION_JOYSTICK+1` (label+offset arithmetic, the same pattern
already used with `TABLA_TECLAS_MSX+10`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes -- exact offsets). `recursos/flujo_programa.html`
regenerated: 606 labels (601 -> 606, +5). `.dsk`/`.cas` regenerated
with no issues. No mentions in `src/FLUJO_PROGRAMA.md`/
`recursos/mapa_memoria.html`.

### TAIL_CREDITS_TEXT -> TEXTO_CREDITOS_PROGRAMADO_POR + a label per entry + FINDING: "MAD$MIX GAME" IS drawn (it's the first of the 8 calls, not the missing one)

At the developer's request, reviewed `DIBUJAR_CREDITOS`'s hex
addresses. All 8 fell inside the credits table, but only the first
one (`TAIL_CREDITS_TEXT`) had a label of its own. Created the other 7
and renamed the table (fixing along the way the out-of-sync `TAIL_`
prefix):

- `TAIL_CREDITS_TEXT` -> `TEXTO_CREDITOS_PROGRAMADO_POR` ("PROGRAMMED
  BY:")
- `$5FD4` -> `TEXTO_CREDITOS_NOMBRE_PROGRAMADOR` ("RAPHAEL GOMEZZZ..")
- `$5FE8` -> `TEXTO_CREDITOS_GRAFICOS_POR` ("GRAPHICOS BY :")
- `$5FFA` -> `TEXTO_CREDITOS_NOMBRE_GRAFICOS` ("ROBERTO P.ACEBES")
- `$600C` -> `TEXTO_CREDITOS_MUSICA_POR` ("MUSIC-A BY:")
- `$6019` -> `TEXTO_CREDITOS_NOMBRE_MUSICA` ("COMILONAS")
- `$6024` -> `TEXTO_CREDITOS_TOPOSHOW` ("TOPOSHOW -1988-")
- `$6035` -> `TEXTO_CREDITOS_TITULO` ("MAD$MIX GAME")

FINDING (fixes a wrong historical note): the `"MAD$MIX GAME"` entry
(`TEXTO_CREDITOS_TITULO`) had a comment saying it was "never reached
by any of `DIBUJAR_CREDITOS`'s 8 calls". That's wrong -- it IS
reached: it's the FIRST of the 8 calls (`HL=$0248`, right at the top
of the screen), despite being placed LAST in the data layout (the
routine uses hardcoded literal addresses, not a sequential loop, just
as the table's header comment already warned). Along the way, also
fixed `DIBUJAR_CREDITOS`'s header comment ("7 fixed patterns" -> it's
8).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes). `recursos/flujo_programa.html`
regenerated: 613 labels (606 -> 613, +7). `.dsk`/`.cas` regenerated
with no issues. The mention at `madmix_scr_body.asm:3445` (a comment
in another function) also updated. Mentions in `FINDINGS.md`
(historical narrative from earlier sessions, including a note "TAIL_
CREDITS_TEXT/etc. still untouched" from an earlier round this same
session, correct at the time) and `src/README.md` (struck-through
checklist) left untouched. No mentions in `src/FLUJO_PROGRAMA.md`.

### GESTIONAR_CICLO_NIVELES/DESPACHAR_EFECTO_SONIDO/APLICAR_COLOR_PANTALLA/REUBICADOR_REINICIO_JUEGO: 11 labels renamed

Renamed the rest of the sample-level cycler region, the sound
dispatcher and the second relocator:

- `TLC_LOOP`/`TLC_INNER`/`TLC_5CAD`/`TLC_END` (local to
  `GESTIONAR_CICLO_NIVELES`, no external refs) -> `.BUCLE_NIVEL_DEMO`/
  `.REPRODUCIR_GUION_DEMO`/`.COMPROBAR_FIN_GUION`/`.FIN_CICLO_NIVELES`.
- `LEVELCYCLE_TABLE` -> `TABLA_CICLO_NIVELES`: the 4-entry
  `[level,pointer]` table the previous loop consumes.
- `TAIL_LEVELCYCLE_HELPER` -> `DESPACHAR_EFECTO_SONIDO`: FINDING,
  despite the name it's NOT part of the level cycler -- it's the
  sound-effect dispatcher called on EVERY VBLANK (if there's a
  pending event at `$6128` it installs its script; it always ticks
  the PSG player). The real cross-reference (`CALL`) from
  `madmix1_body.asm` updated.
- `LEVELCYCLE_RESOURCE_TABLE` -> `TABLA_RECURSOS_SONIDO_EVENTO`: the
  `[channel,pointer]` table the previous dispatcher indexes.
- `TLH2_LOOP` (local to `DIBUJAR_MARCO_CARAMELO_VRAM`) ->
  `.BUCLE_DESCOMPRIMIR_MARCO`.
- `TCM_ENTRY2` -> `APLICAR_COLOR_DESDE_TABLA`: `APLICAR_COLOR_PANTALLA`'s
  second entry point, stays global because
  `APLICAR_COLOR_CICLO_NIVELES` jumps here directly from outside.
- `TCM_LOOP` (local, under `APLICAR_COLOR_DESDE_TABLA`'s scope) ->
  `.BUCLE_APLICAR_COLOR`.
- `TAIL_RELOCATOR2` -> `REUBICADOR_REINICIO_JUEGO`: a second
  relocation routine, twin of `MADMIX0.BIN`'s, still with no confirmed
  caller.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 607
labels (613 -> 607, -6 for the 6 global->local conversions).
`.dsk`/`.cas` regenerated with no issues. `src/FLUJO_PROGRAMA.md`
synced (2 direct mentions in active sections, §2 and §5.9); the
remaining mentions (`TAIL_LEVELCYCLE_HELPER2`/`TAIL_RELOCATOR2`/
`LEVELCYCLE_TABLE`/`LEVELCYCLE_RESOURCE_TABLE` in the already-out-of-
sync section 5.8 large paragraph) left untouched, same criterion as
always. `recursos/mapa_memoria.html` synced (the `0x5AE9-0x6500` and
`0xD244-0xD524`/`0xD524-0xD6B6` blocks, 4 mentions); the "previously
TAIL_LEVELCYCLE_HELPER2" mention (a different historical name,
already resolved in an earlier round) left untouched.

### TABLA_CICLO_NIVELES reorganized: level in decimal + pointers with a real label

At the developer's request, reviewed whether `TABLA_CICLO_NIVELES`
should be in hex or decimal: each 3-byte record mixed a level index
(decimal, like the rest of the simple indices) with a 2-byte pointer
that, FINDING, matched exactly `GUION_DEMO_NIVEL1`/`_NIVEL2`/
`_NIVEL4`/`_NIVEL5` (`madmix1_body.asm`, the same shared namespace via
`main.asm`) -- the same "hex not substituted with an already-existing
label" systemic pattern. Reorganized into 8 lines (`DB` level + `DW`
pointer per entry, 4 pairs), with the level in decimal (1,2,4,5) and
the pointer as the real label instead of 2 hex bytes. Along the way,
fixed the header comment: it cited the old names
`DEMO_SCRIPT_NIVEL1/2/4/5` (never actually used in the file, the real
table was always called `GUION_DEMO_NIVEL1/2/4/5`).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes -- exact pointers). No label changes
(`gen_inventory.py` doesn't apply). `.dsk`/`.cas` regenerated with no
issues.

### TLH_END -> .TICK_SIEMPRE (local to DESPACHAR_EFECTO_SONIDO)

Renamed `TLH_END` to `.TICK_SIEMPRE`, local to
`DESPACHAR_EFECTO_SONIDO` (no external references confirmed by grep):
the convergence point where both paths meet (a pending event
installed, or `$FF`/nothing pending) before the final `CALL
TICK_REPRODUCTOR_PSG`, which always runs.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 606
labels (607 -> 606, -1 for global->local). `.dsk`/`.cas` regenerated
with no issues.

### Last loose English labels in the file: VDP_ENABLE_DISPLAY/VDP_REG1_PENDING/VDP_SCR2_REGS_TABLE/MAINLOOP_TABLES/LOADER_END/END_OF_FILE_SCR

At the developer's request, checked whether any English labels
remained in `madmix_scr_body.asm` (besides the already-handled
`TAIL_`/`HNDLR_` family). Found a loose group and renamed it:

- `VDP_ENABLE_DISPLAY` -> `ENCENDER_PANTALLA_VDP` (sister of
  `APAGAR_PANTALLA_VDP`, already in Spanish).
- `VDP_REG1_PENDING` -> `VDP_REGISTRO1_PENDIENTE`. The real cross-
  reference (`LD A,(...)`) from `madmix1_body.asm:879` updated.
- `VDP_SCR2_REGS_TABLE` -> `TABLA_REGISTROS_SCREEN2_VDP`.
- `MAINLOOP_TABLES` -- FINDING: **removed**, not renamed. It matched
  `REGISTRO_NIVEL`'s (next line) exact same address and had no real
  reference in the code (only historical narrative in `FINDINGS.md`)
  -- purely redundant, unlike earlier cases like `TEXTO_TECLA_PAUSA`
  where the coinciding label DID represent a distinct entity.
- `LOADER_END` -> `FIN_CARGADOR_NIVEL`: also coincides in address
  (with `TABLA_NIVELES`, `$59A9`), but it DOES have its own purpose --
  it's the anchor of the `DS $59A9-$, $00` that checks/fills in case
  `CARGAR_NIVEL` doesn't end exactly there.
- `END_OF_FILE_SCR` -> `FIN_FICHERO_SCR`: a block-end marker, with no
  real reference from `main.asm` (`SAVEBIN` uses the distinct label
  `END_OF_FILE_SCR_DISK`, not touched).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 605
labels (606 -> 605, -1 for `MAINLOOP_TABLES`'s removal; the other 5
are 1:1 renames). `.dsk`/`.cas` regenerated with no issues. No
mentions in `src/FLUJO_PROGRAMA.md`/`recursos/mapa_memoria.html`.

### Maintenance round: recursos/flujo_programa.html had gone the WHOLE session unsynced (sections 1-4, manual prose)

The developer flagged that `recursos/flujo_programa.html`'s section 1
("Large flow diagram") had outdated information. Reviewing it
confirmed a process failure: throughout this whole session,
`src/FLUJO_PROGRAMA.md` and `recursos/mapa_memoria.html` were synced
after every rename, but `recursos/flujo_programa.html` was NOT --
it was wrongly assumed that file was entirely generated by
`tools/gen_inventory.py`. In reality only section 5 (the inventory)
and the 4 per-type count lines are regenerated; sections 1-4 (the
large flow diagram, the `JT_INICIO` dispatch table, the tile-type
dispatcher, state variables) are manual prose, just like
`FLUJO_PROGRAMA.md`.

Checked and fixed, cross-referencing every cited name against the
current source code (not against `src/build/main.sym`, which has been
stale since 07/29 and still has old names -- `main.lst`, fresh, was
used as backup for addresses with no explicit label):

- `TI_CONT`/`$5B56` -> `.CONTINUAR_INTRO` (local to
  `GESTIONAR_INTRODUCCION`) / `MOSTRAR_MENU_PRINCIPAL`
- `TAIL_KEYMENU_MAIN` -> `DIBUJAR_MENU_PRINCIPAL`
- `TI_5B65` -> `ACTUALIZAR_MENU_PRINCIPAL`
- `TAIL_KEYMENU_DRAW` -> `DIBUJAR_MENU_REDEFINIR_TECLAS`
- `TAIL_LEVELCYCLE_MAIN` -> `GESTIONAR_CICLO_NIVELES`
- `CHECK_TILE_DELTA` -> `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`
- `ML_DISPATCH_TABLE` -> `TABLA_MANEJADORES_LOSETA` (2 mentions,
  including section 3's header)
- `GHOST_HINT_HANDLER` -> `AVISAR_PROXIMIDAD_PISTA`
- `TAIL_INTRO` -> `GESTIONAR_INTRODUCCION`
- `SLOT_RESTART_DD82` -> `REINICIO_SLOT_DD82`
- `TI_2C2E_ENTRY` -> `INICIALIZAR_PARCIAL_ITEMS_NIVEL`
- `ML_2D37` -> `TICK_MODO_ESPECIAL`
- 2 loose mentions of "634 labels" in prose (never touched by
  `gen_inventory.py`, which only updates the `<h2>` and the 4
  `<li><b>N type</b>` lines via regex) -> 605.

Confirmed with NO changes (already had current names): `RELOCATOR`,
`JUMP_TO_ENGINE`, `JT_INICIO`/`INICIO`/`START`,
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, `FLAG_ENTRADA_BLOQUEADA`,
`JT_MOTOR_ACTORES`/`MOTOR_ACTORES`,
`JT_RESET_CONTADOR_ACTORES`/`RESET_CONTADOR_ACTORES`,
`PTR_TABLA_SPRITES`, and the already-correct "previously X" mentions
of `BALLS_EATEN_COUNT`/`MODO_ESPECIAL_COUNTDOWN`/`MODO_ESPECIAL_ACTIVE`/
`HINT_POS_TABLE`.

Saved a reinforced memory (`feedback_actualizar_htmls_recursos`) to
avoid repeating this failure: treat `recursos/flujo_programa.html`
exactly like `FLUJO_PROGRAMA.md`/`mapa_memoria.html` in every round's
closing checklist, never assume "the script already regenerates it".

**Verified**: purely documentation (HTML) changes, don't affect
assembly -- no recompile or binary diff applies. Checked with grep
that no mentions of the old names remain.

### MARICOCO_STORE/REGPUNANTOSO_STORE -> local .GUARDAR_ESTADO_REGENERACION/.GUARDAR_ESTADO_PLANTADO

Renamed `MARICOCO_STORE`/`REGPUNANTOSO_STORE` (local reunion points
inside `BUCLE_MARICOCO`/`BUCLE_REGPUNANTOSO`: the "condition met" and
"not met" paths converge here, saving a value + the VRAM address to
scratch before `MOTOR_MOVIMIENTO_ITEM`) to
`.GUARDAR_ESTADO_REGENERACION`/`.GUARDAR_ESTADO_PLANTADO`.

The expected local-scoping trap fired and was fixed: when converting
to local, the intermediate global label `SIN_REGENERAR_MARICOCO`/
`SIN_PLANTAR_REGPUNANTOSO` (between `BUCLE_*` and the `JR` referencing
the new local) broke compilation ("Label not found:
BUCLE_MARICOCO.GUARDAR_ESTADO_REGENERACION"). Confirmed by grep that
both were purely internal, also converted to local:
`.SIN_REGENERAR_MARICOCO`/`.SIN_PLANTAR_REGPUNANTOSO`.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 601
labels (605 -> 601, -4 for the 4 global->local conversions).
`.dsk`/`.cas` regenerated with no issues. No mentions in
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md` (the ones in `FINDINGS.md` are
historical narrative).

### TABLA_ITEMS_MARICOCO/TABLA_ITEMS_REGPUNANTOSO: data converted to decimal

At the developer's request, reviewed `TABLA_ITEMS_MARICOCO`'s format
(confirmed: the same 7-byte-per-entry format as
`TABLA_ITEMS_PELMAZOIDE`, `[X,Y,mode/planted,dir,subX,subY,phase]`,
already documented in that table's comment). None of the 7 fields is
a real bitmask (all are small coordinates/flags/indices), so
`TABLA_ITEMS_MARICOCO`'s 2 entries and `TABLA_ITEMS_REGPUNANTOSO`'s 8
were converted to decimal (`$20,$10,$01/$02,$01,$00,$00,$01` ->
`32,16,1/2,1,0,0,1`), adding the same per-field comment breakdown
`TABLA_ITEMS_PELMAZOIDE` already had. `TABLA_ITEMS_PELMAZOIDE` itself
was NOT touched (not requested this round, still in hex) -- remains
a possible minor inconsistency to resolve in a future round if
uniforming the 3 tables is wanted.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes -- only format changed). No label changes.
`.dsk`/`.cas` regenerated with no issues.

### New resource: recursos/flujo_detallado.html -- a real call graph (Mermaid.js), generated by tools/gen_flow_diagram.py

At the developer's request, created a new HTML viewer with the
program's real call graph (not hand-drawn like `flujo_programa.html`'s
section 1, but generated from `src/build/main.lst`, the same approach
as `gen_inventory.py`). Scope decisions agreed with the developer
before building it:

- Nodes: only the 102 labels classified as **"funcion"/function**
  (the destination of at least one `CALL`) -- the same set as the
  existing inventory's "funcion" category. Does NOT include the ~180
  "interna"/internal ones (destination only of `JP`/`JR`, no `CALL`)
  -- in particular, the tile-type handlers (`HNDLR_SUELO_NORMAL`,
  etc., reached only via `JP (IX)` from `TABLA_MANEJADORES_LOSETA`)
  do NOT appear as nodes. Explicitly documented in the HTML itself as
  a scope limitation, not an accidental omission.
- Rendering: Mermaid.js (CDN) in a `flowchart TD` with a `subgraph`
  per category (color), zoom +/-/reset and checkboxes to show/hide
  categories.
- Categories/colors: reused `flujo_programa.html`'s same `--c-*`
  ones (boot/motor/items/hud/menu/sonido), plus a new `graficos`/
  graphics category (VRAM management) explicitly requested by the
  developer, previously split with no real criterion between motor/
  menu. Categorization done by hand (an explicit dict in the script,
  not a name heuristic) since it's only 102 nodes -- the script warns
  via stdout of any new "funcion" with no explicit category in future
  rounds.

A real FINDING/bug during construction, fixed before finalizing the
task: the first version attributed every `CALL` to the LAST "funcion"
label seen in the file, without accounting for the fact that between
two consecutive "funcion" labels there can be HUNDREDS of lines
belonging to real but non-function routines (reached only by `JR`/
`JP`, e.g. `LEER_TECLADO`/`LEER_JOYSTICK` between
`COMPROBAR_TECLA_MSX` and `ACTUALIZAR_LOSETA_BOLA_ESPECIAL`, 444
lines apart) -- this produced FALSE edges (e.g.
`COMPROBAR_TECLA_MSX` -- a 6-line routine with not a single real call
-- appearing as if it called `DIBUJAR_PORTADA`/`MOSTRAR_MENU_PRINCIPAL`/
etc.). Fixed by computing each line's real lexical owner using ALL
global labels (of any type) as boundaries, and discarding (not
reattributing) `CALL`s whose real owner isn't "funcion" -- dropped
the edge count from 181 (buggy) to 85 (correct), with 178 discarded
calls explicitly documented in the HTML's note instead of silently
hidden.

**Verified**: a purely documentation file (HTML+Python script),
doesn't affect assembly -- no recompile or binary diff applies.
Nodes generated: 102 (boot=11, menu=9, motor=17, items=13, hud=10,
graficos=28, sonido=14, others=0 -- all categorized). Edges: 85.
Added entries in `src/README.md` (the `tools/` tree and the "HTML
Viewers" section).

### Systematic inventory of unlabeled hex addresses in madmix_scr_body.asm -- first batch: substitutions with an already-existing label

At the developer's request, wrote an audit script (cross-checks every
`LD HL/DE/IX/IY,$XXXX` / `CALL/JP $XXXX` / `($XXXX)` in
`madmix_scr_body.asm` against `madmix_scr_body.asm`+`madmix1_body.asm`'s
real labels) to detect hex not substituted with an already-existing
label, explicitly excluding: `LD BC,$XXXX` (almost always an `LDIR`
counter, not an address), values immediately before/after
`FILVRM`/`LDIRVM`/`SETVRAM`/`OUT ($99)` (VRAM position/pattern
arguments, not RAM addresses, the same usual criterion) and manual
case-by-case verification of the rest (several script "RANGE" hits
turned out to be false positives: point arithmetic values, packed
movement deltas, packed camera positions -- discarded with no change
applied).

Applied the first batch (addresses that ALREADY had a real label):

- `$1000` (`LD DE,$1000` and `CALL $1000`, inside
  `REUBICADOR_REINICIO_JUEGO`) -> `DIBUJAR_PORTADA`. It's the "second
  unfixed `CALL $1000`" that had been flagged as pending since a much
  earlier round this same session.
- `$8400` (same routine) -> `START`.
- `$D6B6` (in `DIBUJAR_MARCO_CARAMELO_VRAM`) -> `TABLA_RLE_MARCO_CARAMELO`.
- `$8EC6` (3 uses + 2 mentions in comments) -> `FLAG_ENTRADA_BLOQUEADA`
  (already existed in `madmix1_body.asm`, the same namespace).

A separate FINDING, documented but no change applied: `$925B`
(`ESCRIBIR_PATRON_VRAM`, font/text patterns) falls EXACTLY on
`PTR_TABLA_SPRITES+152` (`madmix1_body.asm`, entry 38 of 64 in the
character-sprite pointer table) -- semantically distinct data that
numerically overlaps; deserves separate investigation before deciding
whether it's real memory reuse or a coincidence.

Still pending (next round, NEW labels to create):
`$5556`/`$5557` (`.GUARDAR_ESTADO_REGENERACION`'s scratch),
`$5667`/`$5668` (REGPUNANTOSO's twin), `$5773` (`TABLA_RANURAS_AVISO`,
4 bytes), `$5BBC` (a "trap" return address in
`GESTIONAR_TIMEOUT_MENU`), `$5C9F` (`LEER_TECLAS_MENU_PRINCIPAL`'s
accumulator), `$6128` (a pending event/sound marker, 27 uses), `$6129`
(the candy frame's color data start), `$60CA`/`$60CB`/`$60CD` (the
sample-level cycler's real state, the historical comment "tail that
compiles to zero" was wrong).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (`gen_inventory.py` doesn't apply).
`.dsk`/`.cas` regenerated with no issues.

### Second batch of the hex-address inventory: 11 new labels created

Continuation of the previous round -- created new labels for the
addresses that had none (all real variables/scratch, verified case by
case by reading the code before touching anything):

- `$5556`/`$5557` (instance 1's scratch, after `SIGUIENTE_MARICOCO`)
  -> `ESTADO_REGENERACION_MARICOCO` (byte) /
  `VRAM_REGENERACION_MARICOCO` (word).
- `$5667`/`$5668` (twin, instance 2) -> `ESTADO_PLANTADO_REGPUNANTOSO` /
  `VRAM_PLANTADO_REGPUNANTOSO`.
- `$5773` (the first 8 of the 15 bytes in the "RAM work area shared
  with MADMIX1.BIN") -> `TABLA_RANURAS_AVISO` (4 entries x 2 bytes).
  The remaining 7 bytes ($577B-$5781) are left unlabeled, documented
  as "no confirmed consumer in this file".
- `$5BBC`: FINDING -- it isn't a data address, it's a "trap" return
  address: `ACTUALIZAR_MENU_PRINCIPAL` manually pushes it onto the
  stack before dispatching the menu option, so that each
  `SELECCIONAR_OPCION_*`'s bare `RET` (called via `JP`, not `CALL`)
  lands exactly on `GESTIONAR_TIMEOUT_MENU`'s `POP AF`, skipping its
  `POP HL`. Added as local label
  `GESTIONAR_TIMEOUT_MENU.CONTINUAR_TRAS_OPCION`, referenced with
  `PARENT.local` notation (the same pattern already used in this
  project's comments, here applied for the first time inside real
  code).
- `$5C9F`: FINDING -- coincides exactly with the `NOP` opcode (`$00`)
  that serves as the "natural fall-through" after
  `TABLA_TECLAS_MENU_PRINCIPAL` (documented in its own header comment)
  -- the same "byte reused with a double role" pattern as other
  findings this session. Labeled the `NOP` itself as
  `ACUMULADOR_TECLAS_MENU` (no byte added).
- `$6128` (27 uses) -> `EVENTO_SONIDO_PENDIENTE`. FINDING: it isn't an
  independent "loose" byte -- it's literally byte 43 of
  `TABLA_RECURSOS_SONIDO_EVENTO`'s `DB` row (which only needs 42 = 14
  entries x 3 bytes), split into its own label with no bytes added.
- `$6129` -> `TABLA_COLOR_MARCO_CARAMELO` (the start of `INCBIN
  "data/img/marco_caramelo_color.img"`, 768 bytes).
- `$60CA`/`$60CB`/`$60CD`: FINDING -- the historical comment said "a
  tail after .FIN_CICLO_NIVELES, compiles to zero" / "alignment
  variable/padding before the table", but they're REAL, actively used
  variables (even from `MOTOR_MOVIMIENTO_COLISION` and
  `ACTIVAR_EFECTO_ITEM`, outside `GESTIONAR_CICLO_NIVELES`) ->
  `INDICE_CICLO_NIVELES` (byte, 0-3 index of the current sample
  level) / `PUNTERO_GUION_DEMO` (word, cursor into the active script)
  / `CONTADOR_FRAME_GUION_DEMO` (byte). The final 2 bytes
  ($60CE-$60CF) are left unlabeled, no confirmed consumer.

All substitutions verified with grep before applying (no substring
collisions) and with no byte added/removed --
`MADMIX.SCR`/`MADMIX1.BIN`'s length identical byte for byte to the
usual one, alongside the 7/2 baseline.

Synced `src/FLUJO_PROGRAMA.md` (3 mentions in active sections, §5.9
and §4's variables table) and `recursos/mapa_memoria.html` (1
mention). Left untouched the mentions inside paragraphs already
flagged as out of sync in earlier rounds (§5.6/§5.8, with other old
names not updated).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2, same bytes, exact same length). `recursos/flujo_programa.html`
regenerated: 612 labels (601 -> 612, +11 new). `.dsk`/`.cas`
regenerated with no issues.

### LOAD_BIN_ENTRY -> ORQUESTADOR_CARGA_CINTA

Renamed `LOAD_BIN_ENTRY` (`src/load_cas/load_bin_body.asm`, `$DDA0`)
to `ORQUESTADOR_CARGA_CINTA`: `LOAD.BIN`'s real entry point (invoked
from BASIC via `DEF USR=56736!:A=USR(0)`), tape's equivalent of
`RELOCATOR`+`JUMP_TO_ENGINE` together -- detects RAM slots
(`DETECTAR_SLOTS_RAM`), sets up pages, reads from tape directly to
`$1000` (title screen) and runs it, reads the whole engine directly to
`$8400` (`START`) and jumps there, with no intermediate landing or
`LDIR` (unlike the disk version). The real reference in `src/main.asm`
(`SAVEBIN "build/cas/LOAD.BIN", ...`) updated.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (a 1:1 rename). `.dsk`/`.cas`
regenerated with no issues.

### PAGE_CONFIG_1/2/3 -> APLICAR_SLOT_PAGINA_0/1/2

Renamed `PAGE_CONFIG_1`/`_2`/`_3` (`src/load_cas/load_bin_body.asm`)
to `APLICAR_SLOT_PAGINA_0`/`_1`/`_2`: each one applies the slot
configuration `DETECTAR_SLOTS_RAM` saved at `$E293` to one of the
MSX map's first 3 16KB "pages" (the classic 4-page x slot/sub-slot
system via port `$A8`+`EXPTBL`/`$FFFF`), jumping to its own `D`/`E`
"setup" and from there to the common switcher `APLICAR_CAMBIO_SLOT`
(a name assigned in a later round this same session). They're 3 of
the 6 "apply page/slot configuration" variants already documented in
the header comment (the other 3, with `$E291`, aren't called from
this file -- not touched).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (a 1:1 rename). `.dsk`/`.cas`
regenerated with no issues.

### TAPE_READ -> LEER_CINTA

Renamed `TAPE_READ` (`src/load_cas/load_bin_body.asm`, `$DDCC`) to
`LEER_CINTA`: a generic bit-by-bit tape-reading routine (receives the
destination in `IX` and byte count in `DE`), used by
`ORQUESTADOR_CARGA_CINTA` both for reading the title-screen block and
the whole engine. Uses fixed BASIC ROM hooks and flashes the border
(VDP port `$99`). A surgical rename (not `replace_all`): `TAPE_READ`
is a substring of `TAPE_READ_HOOK_LOOP`/`_BIT`/`_BIT_STORE`/
`_BIT_CALL`/`_ABORT`/`_UNHOOK_LOOP` (a family of related locals, not
touched yet, candidates for a separate round).

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (a 1:1 rename). `.dsk`/`.cas`
regenerated with no issues.

### TAPE_READ_HOOK_LOOP -> .BUCLE_GUARDAR_GANCHOS (local to LEER_CINTA)

Renamed `TAPE_READ_HOOK_LOOP` to `.BUCLE_GUARDAR_GANCHOS`, local to
`LEER_CINTA` (no external references): backs up 12 entries (24 bytes)
of a fixed BASIC/ROM vector table (`$FCA6` downward) by pushing them
onto the stack, before installing `LEER_CINTA`'s own hooks. Its
counterpart `TAPE_READ_UNHOOK_LOOP` (renamed in a later round this
same session to `.BUCLE_RESTAURAR_GANCHOS`) does the opposite at the
end: restores them from the stack.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). `recursos/flujo_programa.html` regenerated: 611
labels (612 -> 611, -1 for global->local). `.dsk`/`.cas` regenerated
with no issues.

### TEST_BIN_ENTRY -> DETECTAR_SLOTS_RAM

Renamed `TEST_BIN_ENTRY` (`src/load_cas/test_bin_body.asm`, `$C350`)
to `DETECTAR_SLOTS_RAM`: `TEST.BIN`'s RAM/slot detection engine,
invoked by `ORQUESTADOR_CARGA_CINTA` as the first step before
touching the tape -- walks the primary/secondary slot combinations on
pages `$4000`/`$8000` (the classic `ENASLT`-based detection pattern)
and saves 2 resulting slot configurations to `$E290-$E293`. The real
reference in `src/main.asm` (`SAVEBIN "build/cas/TEST.BIN", ...`)
updated, along with the real `CALL` from `ORQUESTADOR_CARGA_CINTA`.
The "live" mention from this same session's previous entry fixed
going forward; historical mentions from earlier sessions in
`FINDINGS.md` left untouched.

**Verified**: recompiled with no errors, diffs at the exact usual
baseline (7/2). No label changes (a 1:1 rename). `.dsk`/`.cas`
regenerated with no issues.

### Full review of `load_cas/load_bin_body.asm`: last 14 English/cryptic labels renamed

Reviewed EVERY function label still in English or with a cryptic name
in this file (`LOAD.BIN`, the tape-load orchestrator). Three groups,
all confirmed and applied:

**Group A -- family of locals inside `LEER_CINTA`** (the bit-by-bit
tape-read loop, already had `TAPE_READ`->`LEER_CINTA` done in the
previous round):
- `TAPE_READ_BIT_STORE` -> `.ALMACENAR_BYTE`: saves the byte already
  assembled bit by bit into the destination (`(BC)`).
- `TAPE_READ_BIT_CALL` -> `.LLAMAR_GANCHO_BIT`: invokes the ROM hook
  that reads the next tape bit.
- `TAPE_READ_BIT` -> `.BUCLE_LEER_BIT`: the main loop, one pass per
  bit read.
- `TAPE_READ_ABORT` -> `.FINALIZAR_LECTURA`: the real convergence
  point of success AND failure (the previous name "ABORT" was
  misleading -- it isn't only the error exit, it's where both paths
  meet: restores ROM hooks and returns the result flag in every
  case).
- `TAPE_READ_UNHOOK_LOOP` -> `.BUCLE_RESTAURAR_GANCHOS`: already
  renamed in the previous round (see entry above), included here only
  for a full-set review.

**Group B -- code not invoked from this file** (a vestige or hook for
an unused case in this build, the same VDP port `$99` as
`LEER_CINTA`):
- `TAPE_MOTOR_HELPER_A` -> `AYUDANTE_MOTOR_CINTA_A`
- `TAPE_MOTOR_HELPER_B` -> `AYUDANTE_MOTOR_CINTA_B`

**Group C -- the "apply page/slot configuration" family** (6 variants
+ the common switcher, already documented in the header comment since
the `PAGE_CONFIG_1/2/3` round): the 3 twins with `$E291` (NOT invoked
from this file, the dead counterpart of the 3
`ORQUESTADOR_CARGA_CINTA` DOES call) and the 3 D/E "setups" + the
final switcher:
- `PAGE_CONFIG_E291_A` -> `APLICAR_SLOT_ORIGINAL_PAGINA_0`
- `PAGE_CONFIG_E291_B` -> `APLICAR_SLOT_ORIGINAL_PAGINA_1`
- `PAGE_CONFIG_E291_C` -> `APLICAR_SLOT_ORIGINAL_PAGINA_2`
- `PAGE_CONFIG_SETUP_A` -> `CONFIGURAR_MASCARA_PAGINA_0`
- `PAGE_CONFIG_SETUP_B` -> `CONFIGURAR_MASCARA_PAGINA_1`
- `PAGE_CONFIG_SETUP_C` -> `CONFIGURAR_MASCARA_PAGINA_2`
- `PAGE_SWITCH_COMMON` -> `APLICAR_CAMBIO_SLOT`

With this, `load_cas/load_bin_body.asm` has no pending English or
cryptic labels left (every function/local in the file now has a
descriptive Spanish name). "Live" mentions of `PAGE_SWITCH_COMMON`
and `TAPE_READ_UNHOOK_LOOP` in this same session's entries (above)
fixed going forward; historical mentions from earlier sessions left
untouched.

**Verified**: recompiled with no errors (0 errors, 2 pre-existing
unrelated warnings). Diffs at the exact usual baseline: **7 in
`MADMIX.SCR`, 2 in `MADMIX1.BIN`** (offsets `$8BE5`/`$8CD4`, the
already-documented historical fix). No label changes outside this
file (1:1 renames, no bytes inserted or removed). `.dsk`/`.cas`
regenerated with no issues. `recursos/flujo_programa.html`
regenerated: 606 labels (a clean inventory, no mentions of the old
names). `tools/gen_flow_diagram.py`'s `CATEGORY` dict had 5 outdated
names (`TEST_BIN_ENTRY`, `TAPE_READ`, `PAGE_CONFIG_1/2/3`) from rounds
before this rename session -- fixed and
`recursos/flujo_detallado.html` regenerated (same 102 nodes/85 edges,
no structural change). `recursos/mapa_memoria.html` and
`recursos/flujo_secuencial.html` had no mentions of any of the 14 old
names already (nothing to sync in those two).

### Review of `load_cas/load_bin_body.asm`'s variables/literals: decimal where it fits + new labels for $E290-$E293

Full review of every numeric literal in the file (an explicit request
from the developer: "review all the variables, convert to decimal the
ones that fit and check whether all of them have labels"). Two
results:

**Decimal where it fits** (pure counters, no mask/sign/address
semantics): `LD DE, $5500` -> `LD DE, 21760` (byte size of the
destination block for `DIBUJAR_PORTADA`, same as disk's `RELOCATOR`
LDIR); `LD DE, $59A0` -> `LD DE, 22944` (byte size of the destination
block for `START`); both `LD B, $0C` -> `LD B, 12` (the 12-ROM-hook
table `.BUCLE_GUARDAR_GANCHOS`/`.BUCLE_RESTAURAR_GANCHOS` push/
restore); `CP $01` -> `CP 1` (the final result comparison, not a
mask). The rest of the file's literals were deliberately left in hex:
addresses (`$FCA6`, `$FCA4`, `$FC8E`, `$FC9A`, `$FC9E`, ROM hooks
`$00E1`/`$C961`/`$CDD9`/`$EDD9`/`$69ED`, `$FFFF`), ports (`$A8`,
`$99`, `$AB`), bitmasks (`$0F`, and the D/E pairs of the
`CONFIGURAR_MASCARA_PAGINA_x` family: `$03`/`$FC`, `$0C`/`$F3`,
`$30`/`$CF` -- note this `$0C` is a mask, NOT the loop counter above,
same value but different semantics), VDP command bytes (`$87`), signed
deltas used in overlap arithmetic (`$0372`, `$FFE8` = -24), the `$FF`
sentinel (`LEER_CINTA`'s parameter) and constants of unknown purpose
in dead, uninvoked code (`AYUDANTE_MOTOR_CINTA_B`: `$13`, `$09`,
`$01`) or feeding directly into the `$FC9A` ROM hook (`$E4`, `$F3`).

**New labels -- `$E290`-`$E293`**: 4 bytes of free RAM (outside any
project binary) used as a SHARED working variable between
`test_bin_body.asm` (writes them, in `SLOT_SAVE_A`/`SLOT_SAVE_B`) and
`load_bin_body.asm` (reads them, the
`APLICAR_SLOT_ORIGINAL_PAGINA_x`/`APLICAR_SLOT_PAGINA_x` families) --
until now 4 loose hex literals repeated 6 times across both files,
with no label. The same pattern as `BUFFER_LOSETAS_TRABAJO: EQU
$DE04` in `madmix1_body.asm` (working RAM with a real name even though
it isn't backed by any `DB` in the project). Created as `EQU` in
`test_bin_body.asm` (before `SLOT_SAVE_A`, available to
`load_bin_body.asm` via `main.asm`'s shared symbol space):
- `SLOT_PRIMARIO_A` = `$E290`, `EXPTBL_COMPLEMENTO_A` = `$E291`
  (config "A", saved by `SLOT_SAVE_A`, the one the dead
  `APLICAR_SLOT_ORIGINAL_PAGINA_x` family uses).
- `SLOT_PRIMARIO_B` = `$E292`, `EXPTBL_COMPLEMENTO_B` = `$E293`
  (config "B", saved by `SLOT_SAVE_B`, the one
  `ORQUESTADOR_CARGA_CINTA` DOES use via `APLICAR_SLOT_PAGINA_x`).

Both files' headers updated to reference the new names instead of a
literal hex.

**Verified**: recompiled with no errors (0 errors, 2 pre-existing
unrelated warnings). Diffs at the exact usual baseline: 7 in
`MADMIX.SCR`, 2 in `MADMIX1.BIN`. `.dsk`/`.cas` regenerated with no
issues. `recursos/flujo_programa.html` regenerated: 610 labels (606 ->
610, +4 for the new `EQU`s). `recursos/mapa_memoria.html` unchanged --
the `$E290-$E293` range is free RAM outside every binary that document
maps (the same criterion as `$FCA6`/`$AFC8`, also not mapped there).

### Full review of `load_cas/test_bin_body.asm`: 13 function/jump labels renamed

Reviewed every function and jump label still in English or poorly
descriptive in this file (`TEST.BIN`, the RAM/slot detection engine).
Three groups:

**Group A -- saving slot configuration** (used by `DETECTAR_SLOTS_RAM`
before and after detection, to be able to restore the original slot
at the end):
- `SLOT_SAVE_A` -> `GUARDAR_CONFIG_SLOT_A`
- `SLOT_SAVE_B` -> `GUARDAR_CONFIG_SLOT_B`
- `SLOT_SAVE_COMMON` -> `GUARDAR_SLOT_COMUN` (a tail shared by the
  previous two; CANNOT be local -- `GUARDAR_CONFIG_SLOT_B`, which must
  stay global since it's invoked from `DETECTAR_SLOTS_RAM`, falls
  between A's `JR` and this label -- the same local-scoping trap
  already documented in earlier rounds).

**Group B -- `DETECTAR_RAM_PAGINA`** (receives the page in `HL`; tests
the 16 slot/subslot combinations via `ENASLT`, writing/reading a
`$20`/`$FA` pattern to distinguish real RAM from ROM/nothing):
- `RAM_TEST` -> `DETECTAR_RAM_PAGINA`
- `RAM_TEST_OUTER` -> `.BUCLE_SLOT_SECUNDARIO` (local, a 4-subslot
  loop)
- `RAM_TEST_TRY` -> `.BUCLE_SLOT_PRIMARIO` (local, a 4-primary-slot
  loop, tries each combination)
- `RAM_TEST_NEXT` -> `.SIGUIENTE_COMBINACION` (local, a failed
  combination, continues)
- `RAM_TEST_FOUND` -> `.RAM_ENCONTRADA` (local, RAM detected)

**Group C -- extended relocatable `ENASLT` template** (copied to
`$AFC8` at runtime; handles the subslot case, which the ROM's standard
`ENASLT` doesn't resolve directly):
- `ENASLT_HELPER` -> `ENASLT_EXTENDIDO`: the entry point -- if the
  page doesn't use a subslot, it merges directly into port `$A8`; if
  it does, it jumps to handle the subslot.
- `ENASLT_HELPER_C` -> `ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT`: the
  subslot case -- updates the subslot cache table (`$FCC5`+offset)
  and retries.
- `ENASLT_HELPER_B` -> `ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO`:
  computes the AND/OR mask pair to insert 2 bits at the correct page
  position of the primary slot register.
- `ENASLT_HELPER_D` -> `ENASLT_EXTENDIDO_MASCARA_SUBSLOT`: the same
  but for the subslot register (`EXPTBL`/port `$A8`).
- `ENASLT_HELPER_B_MID`/`ENASLT_HELPER_B_LOOP` (the primary mask's
  internal loops, no external reference) -> local
  `.BUCLE_DESPLAZAR_MASCARA`/`.BUCLE_REPLICAR_MASCARA`.
- `ENASLT_HELPER_D_MID` (the subslot mask's internal loop) -> local
  `.BUCLE_DESPLAZAR_MASCARA` (the same local name as above, but scoped
  to `ENASLT_EXTENDIDO_MASCARA_SUBSLOT` -- no collision, locals
  resolve by scope).

Note on confidence: Group C is the one that could least be 100%
verified -- the general purpose is understood (building 2-bit-per-
page masks for slots/subslots) but not every arithmetic micro-detail
of B/C/D. Cross-referencing hex comments (`= X after relocating to
$AFC8`) updated to the new names, including `PARENT.local` syntax for
the two `.BUCLE_DESPLAZAR_MASCARA` cases.

**Verified**: recompiled with no errors (0 errors, 2 pre-existing
unrelated warnings). Diffs at the exact usual baseline: 7 in
`MADMIX.SCR`, 2 in `MADMIX1.BIN`. `.dsk`/`.cas` regenerated with no
issues. `recursos/flujo_programa.html` regenerated: 603 labels (610
-> 603, -7 for the 7 global->local conversions: 4 in Group B + 3 in
Group C). `tools/gen_flow_diagram.py` had `SLOT_SAVE_A`/`SLOT_SAVE_B`/
`RAM_TEST` in the `CATEGORY` dict -- fixed and
`recursos/flujo_detallado.html` regenerated (same 102 nodes/85 edges,
no structural change). `recursos/mapa_memoria.html` and
`src/FLUJO_PROGRAMA.md` had no mentions of any of the 13 old names
(nothing to sync).

### Review of `load_cas/test_bin_body.asm`'s data/literals: decimal where it fits

Reviewed every numeric literal in the file (an explicit request from
the developer). Also checked that no leftover hex literal remains
that should be substituted with an already-existing label -- the 4
`EQU`s (`SLOT_PRIMARIO_A`/`EXPTBL_COMPLEMENTO_A`/`SLOT_PRIMARIO_B`/
`EXPTBL_COMPLEMENTO_B`) and the previous round's function labels were
already used everywhere they should be.

**Decimal where it fits** (pure counters): `LD BC, $007A` ->
`LD BC, 122` (`ENASLT_EXTENDIDO`'s byte size for the relocation
`LDIR`, matches the "122 bytes" already documented in the header);
`LD C, $04`/`LD B, $04` -> `LD C, 4`/`LD B, 4` (the 4 secondary/
primary slot combinations `DETECTAR_RAM_PAGINA` walks); `LD B, $00`
-> `LD B, 0` (16-bit extension of the table index in
`ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT`).

The rest was deliberately left in hex: addresses (`$8000`, `$4000`,
`$0000` as MSX pages; `$0024` ENASLT; `$C3B3` self-modified operand;
`$AFC8`; `$FCC5`; `$FFFF` EXPTBL), ports (`$A8`), `ENASLT`'s packed
format/mask bytes (`$80`, `$83`, `$03`, `$C0`, `$3F`, the `$04` step
in `ADD A,$04` that advances a bit field, not an independent
counter), RAM-detection pattern constants (`$20`/`$FA`, "complementary
write" per the header), mask-construction-by-modular-sum constants
(`$AB`, `$55`), and the standard interrupt vector `RST $38`.

**A separate finding, not applied**: `$C3B3` (the lines where
`DETECTAR_SLOTS_RAM` self-modifies the `CALL $0024` operand inside
`.BUCLE_SLOT_PRIMARIO`) is that instruction's real operand, INSIDE
`TEST.BIN`'s own binary -- the same "self-modified byte with no label
of its own" pattern as others already resolved this session (e.g.
`$5C9F`/`ACUMULADOR_TECLAS_MENU` in `madmix_scr_body.asm`). Labeling
it would require splitting the `CALL $0024` instruction into
`DB $CD` + `DW $0024` with a label in between (same bytes, 0
differences) -- more invasive than a simple substitution, left
pending the developer's explicit confirmation instead of applying it
directly.

**Verified**: recompiled with no errors (0 errors, 2 pre-existing
unrelated warnings). Diffs at the exact usual baseline: 7 in
`MADMIX.SCR`, 2 in `MADMIX1.BIN`. `.dsk`/`.cas` regenerated with no
issues. `recursos/flujo_programa.html` regenerated: 603 labels (no
change, only literals touched, not symbols).

### New label for the self-modified operand at $C3B3 (confirmed by the developer)

Applied the finding left pending in the previous entry:
`DETECTAR_SLOTS_RAM` self-modifies twice (before and after relocating
`ENASLT_EXTENDIDO`) the operand of the `CALL $0024` instruction living
inside `.BUCLE_SLOT_PRIMARIO` (`DETECTAR_RAM_PAGINA`) -- until now
referenced as a loose hex literal `$C3B3` in both writes, with no
label of its own despite being inside the project's binary.

Split the `CALL $0024` instruction into `DB $CD` (fixed opcode) +
`DW $0024` with a local label `.OPERANDO_ENASLT_AUTOMODIFICADO` right
on the operand -- the exact same 3 bytes (`CD 24 00`), confirmed in
the listing (`C3B2 CD` / `C3B3 24 00`). Both writes in
`DETECTAR_SLOTS_RAM` now use `LD
(DETECTAR_RAM_PAGINA.OPERANDO_ENASLT_AUTOMODIFICADO), HL` (`PARENT.local`
syntax, already used earlier this session).

Note on the inventory: local labels (`.` prefix) are NEVER counted by
`gen_inventory.py` (its label-detection regex requires the first
character to be a letter or `_`, a dot doesn't match) -- this
retroactively confirms why earlier rounds' global->local conversions
always LOWERED the total instead of keeping it steady (the new local
label simply never gets counted, it isn't added then subtracted).
`.OPERANDO_ENASLT_AUTOMODIFICADO` doesn't appear in the inventory for
the same reason -- expected behavior, not a generator bug.

**Verified**: recompiled with no errors. Diffs at the exact usual
baseline (7/2). `.dsk`/`.cas` regenerated with no issues.
`recursos/flujo_programa.html` regenerated: 603 labels (no change,
the new label is local and isn't counted, see note above).

### Comments added to every data item/variable in `load_cas/test_bin_body.asm`

An explicit request from the developer: review every literal/address
in the file and add a comment where one was missing. Comment-only
changes (0 code bytes touched), among others:
- `LD A, ($8000)`/`LD ($8000), A`: saving/restoring the original byte
  the RAM test overwrites.
- `LD HL, $4000`/`$8000`/`$0000` (the 3 `CALL DETECTAR_RAM_PAGINA`):
  identified as page 1/2/0.
- `IN A, ($A8)` in `GUARDAR_SLOT_COMUN`: reads the active primary
  slot.
- `LD A, $80`/`AND $83`/`ADD A, $04` in `DETECTAR_RAM_PAGINA`: the
  packed format of `ENASLT`'s config byte (primary slot in bits 0-1,
  a fixed high bit) and how the inner loop advances that field.
- `$20`/`$FA`: explicitly identified as "test pattern #1"/"#2" at each
  use, with the success/failure logic explained.
- A new header on `ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO`/
  `_SUBSLOT`: describes the general technique (isolate the page
  number, shift a base mask, replicate the value via a `$55` modular
  sum), with an explicit note that the bit-by-bit detail isn't 100%
  verified (the same hedge already used in the rename round). Every
  `AND`/`OR`/`IN`/`OUT` of those two functions commented with its role
  in that technique.
- The 2 `RST $38` padding bytes after the real `RET` (never executed,
  same as the `DB $E1` that already had a comment) marked as such.

**Verified**: recompiled with no errors. Diffs at the exact usual
baseline (7/2, comment-only, 0 code bytes). `.dsk`/`.cas` regenerated
with no issues.

### Comments added to every data item/variable in `load_cas/load_bin_body.asm`

Same treatment as the previous entry, now for `LOAD.BIN` (an explicit
request from the developer: "do the same in this file"). Comment-only
changes (0 code bytes touched). Highlights:
- Both `LD A, $FF` (`LEER_CINTA`'s parameter) and the `LD A, $E4`/
  `$F3` (mode for the `$FC9A` hook, via `$FC9E`): commented with an
  explicit hedge that their exact semantics aren't 100% verified
  (they're parameters of an external ROM hook, not the project's own
  logic).
- `$0372`/`$FFE8`: identified as a delta pair from a protected-zone
  overlap check (`$FFE8` = -24), same hedge.
- The loose `$87`s (appear 4 times, including in the dead code
  `AYUDANTE_MOTOR_CINTA_A/B`): confidently identified as "VDP --
  selects register 7 (color)" (the second `OUT` of the standard
  VDP-register-write pattern).
- **High-confidence finding**: `CONFIGURAR_MASCARA_PAGINA_0/1/2`'s 3
  D/E pairs (`$03`/`$FC`, `$0C`/`$F3`, `$30`/`$CF`) are exactly the
  mask/complement pairs for the slot register's bits 1-0/3-2/5-4 (2
  bits per page) -- D isolates that page's bits, E is its exact
  complement (used to clear those same bits before inserting the new
  value in `APLICAR_CAMBIO_SLOT`). No hedge, a mathematically exact
  pattern (`$FC` = NOT `$03`, etc.).
- The rest of the dead code in `AYUDANTE_MOTOR_CINTA_B` (`$13`, `$09`,
  port `$AB`) commented with an explicit uncertainty hedge (a routine
  never invoked, no way to verify against real execution).

**Verified**: recompiled with no errors. Diffs at the exact usual
baseline (7/2, comment-only, 0 code bytes). `.dsk`/`.cas` regenerated
with no issues.

### New `recursos/mapa_memoria_logotopo.html`, ready for LOGOTOPO.CM's future disassembly

An explicit request from the developer: create a memory map like
`mapa_memoria.html` but dedicated to `LOGOTOPO.CM` (Topo Soft's tape
logo, explicitly out of scope for `load_cas/`'s reorganization, see
`src/load_cas/LOGOTOPO.CM.txt`), ready to be filled in when that RE
sub-project is resumed.

The same visual template/CSS/table structure as the main map, but
with one deliberate difference: the bar's scale is NOT the full memory
map (0x0000-0xFFFF) but its OWN scale bounded to `LOGOTOPO.CM`'s real
range (`RANGE_START`/`RANGE_END` = 0x9470/0xA50D, 4253 bytes) --
`pct()` recomputed accordingly, and the address ruler uses a 0x100
step instead of 0x1000 (too small a range for 0x1000 jumps to produce
more than 1-2 marks). `FILES` has a single entry (no relocation:
`exec` == `start` == 0x9470 in the tape block's real header).

`SEGMENTS` starts with only 2 entries: the 3 bytes already confirmed
without disassembling anything (`JP $95D1`, the first real opcode,
already documented in `LOGOTOPO.CM.txt`) and the whole rest marked
"not yet explored" -- meant to be subdivided segment by segment
exactly as historically done with `mapa_memoria.html`.

`src/README.md` updated (a new entry in "HTML Viewers"); along the
way, removed an already-outdated label counter ("729") in
`flujo_programa.html`'s entry (that document already shows its own
live count in its generated header, duplicating it in `README.md`
only creates another source that goes out of sync).

**Verified**: a new page, doesn't affect the build or the binaries --
no recompile/byte-diff applies. HTML/JS structure visually checked
against `mapa_memoria.html` (same template, only the range/scale and
`SEGMENTS`/`FILES`'s content differ).

## RESUMED: LOGOTOPO.CM disassembly -- first code block transcribed and verified (0x9470-0x9693, 549 bytes, 0 differences)

An explicit request from the developer: "Disassemble LOGOTOPO.CM.bin
and let's start working on it" -- resumes the sub-project deliberately
left postponed (see the previous entry and
`src/load_cas/LOGOTOPO.CM.txt`).

**Initial disassembly**: `Z80Dasm.exe -offset 9470
src/load_cas/LOGOTOPO.CM.bin` (our copy already excludes the 7-byte
BLOAD header -- it starts directly at `C3 D1 95`, no `-begin` needed).
The full output (3645 lines) saved to
`src/load_cas/LOGOTOPO_dasm_raw.txt` as a reference for the next
rounds.

**Key finding, the same pattern as the rest of the project**:
Z80Dasm's LINEAR disassembly doesn't distinguish code from data --
looking for long `nop` stretches (`$00` blocks, typical of image/
color areas with a black background) located dozens of sync breaks
starting at `0x9694` (jumps to nonsensical addresses like `$6c0c`,
loose meaningless instructions like `ex af,af'` in the middle of what
should be a table). Manual inspection confirmed the `0x9470-0x9693`
stretch is real, coherent code (ends in `JP $0059`, a clean tail-call)
and that right after, at `0x9694`, content starts decoding as garbage
-- a natural boundary for the first transcription.

**Transcribed and verified the first block** (`0x9470-0x9693`, 549
bytes): converted from Z80Dasm syntax to SjASMPlus with a one-off
Python script (normalizes mnemonics to uppercase, detects every
`JR`/`DJNZ`/`JP`/`CALL` destination within the range and assigns a
placeholder label `L_XXXX` = the real address in hex -- the same
criterion as this project's old names like `HANDLER_311B`/`R51FE_MAIN`
before they were understood). New file
`src/load_cas/logotopo_cm_body.asm`, with a header explaining the
"IN PROGRESS" state. The rest of the tape block (`0x9694-0xA50C`,
3705 bytes) stays as an `INCBIN` of
`src/data/logotopo/datos_sin_analizar_9691.bin` (this project's usual
historical pattern: transcribe in pieces, keep the rest as `INCBIN`
until the next round) + 1 loose final byte ($00, outside the .cas
header's real start/end range, the same pattern as other files in
this tape file).

**High-level structure already identified** (13 routines, provisional
names by address):
- `L_9470`: the real entry (`JP L_95D1`, jumps past the subroutine
  definitions to the real start point).
- `L_94A6`/`L_967E`: write N consecutive bytes to VRAM with A's value,
  via a ROM hook at `$004D` -- the usage pattern (A=byte, HL=VRAM
  address before the `CALL`) matches `WRTVRM`'s standard convention,
  likely but NOT 100% confirmed against a reference table of BIOS
  hooks.
- `L_9473`: draws a rectangle/frame with `HALT`-based timing (3 frames
  between iterations) -- a candidate for a "progressive drawing"
  effect.
- `L_94B1`: a "glyph"/large-character routine -- reads an index, looks
  it up in a pointer table (`$96F8`), copies (width,position) pairs
  from a shape table at `$9728` into a work buffer, and composites
  against VRAM byte by byte. Uses SELF-MODIFYING CODE
  (`LD ($94F1),A`/`LD ($94DD),A` overwrite the operands of `LD B,n`/
  `LD C,n` instructions further up in the same routine) -- the same
  pattern already seen in `test_bin_body.asm` (`ENASLT_EXTENDIDO`) and
  in `madmix_scr_body.asm` this session.
- `L_950B`/`L_9532`/`L_954D`/`L_956B`/`L_958E`/`L_95AE`: 6 logo-entry
  "effects", each preps parameters (`$94BD`/`$94B2`/`$94E9`/`$94F3`,
  also self-modified) and calls `L_94B1`/`L_94A6` in a loop, consuming
  data tables at `$96B2`/`$96CC`/`$96E9` (not yet analyzed, inside the
  `INCBIN`).
- `L_95D1`: the real MAIN SEQUENCE (which `L_9470` jumps to). Clears
  the whole VRAM color table (`L_9602`) and chains the 6 effects + 2
  VRAM fills (`L_9688`) + drawing the grid/frame (`L_962B`) in a fixed
  order -- the best high-level clue available so far for "how the
  logo gets built on screen".
- `L_9602`: fills 0x1800 (6144) bytes of VRAM `$2000` with `$F0`, byte
  by byte via `$004D` -- 6144 EXACTLY matches SCREEN2's color-table
  size (32x8x24). High-confidence hypothesis: clears/preps the color
  table before drawing.
- `L_9614`: writes a pattern (`$81`) to VRAM `$2F78` in blocks of 2
  rows x 64 bytes -- a candidate for "draw a solid frame/border".
  `L_9688`: HL=$0000/DE=$C000/BC=$1800, jumps to a ROM hook at `$0059`
  -- a candidate for `FILVRM`/`LDIRVM`/`LDIRMV` per the standard BIOS
  hook table, exact identity UNCONFIRMED (the 3 loaded registers alone
  aren't enough to distinguish which one without checking against a
  real reference).
- `L_962B`: two "boxes" of lines (`$71` x5 rows, `$31` x6 rows, via
  `L_967E`) starting at `$2658`, with a shift repeated 16 times until
  E reaches `$98` -- a candidate for a decorative grid/frame, still
  pending full deciphering.

**Integration into `main.asm`**: a new block `ORG $9470` /
`INCLUDE "load_cas/logotopo_cm_body.asm"` / `SAVEBIN
"build/cas/LOGOTOPO.CM", ...`, deliberately placed AFTER the
`MADMIX1.BIN` block -- `$9470-$A50D` coincides with `MADMIX1.BIN`'s
STATIC range (character/sprite source, `$92E3-$B93B`), the same
pattern already verified with `TEST.BIN`/`$C350` (sound driver):
`SAVEBIN` takes a snapshot of the buffer at its own point in source
order, so there's no real conflict.

**Verified**: recompiled with no errors. `build/cas/LOGOTOPO.CM`
generated (4253 bytes) with **0 differences** byte for byte against
`src/load_cas/LOGOTOPO.CM.bin` (the 4253 real bytes, not counting the
loose byte). The usual baseline intact across the 3 existing
binaries: `MADMIX.SCR` 7 differences, `MADMIX1.BIN` (disk AND tape) 2
differences each -- confirms reusing `MADMIX1.BIN`'s address range had
no side effect. `.dsk`/`.cas` rebuilt/regenerated with no issues
(still do NOT include `LOGOTOPO.CM` in the package --
`gen_cas_file.py` still untouched, pending until the disassembly is
further along). `recursos/mapa_memoria_logotopo.html` updated: the
single "unexplored" segment was split into the `0x9470-0x9693` block
(now code/verified) and the still-unanalyzed rest.

**Pending for the next round**: disassemble the rest
(`0x9694-0xA50C`, 3705 bytes) -- foreseeably a mix of data tables
(shapes/pointers already referenced from the block above) and more
code; understand the 13 already-transcribed routines in detail
(`L_XXXX` names are only placeholders); confirm the exact identity of
the ROM hooks at `$0059` (and reinforce `$004D`'s) against an MSX BIOS
hook reference table.

### LOGOTOPO.CM: renamed ENTRADA_LOGOTOPO/DIBUJAR_LOGO_TOPOSOFT, decoded the index/shape tables, and a new renderer

**Renamed** (confirmed by the developer): `LOGOTOPO_ENTRY` ->
`ENTRADA_LOGOTOPO` (the initial `JP`, `$9470`) and `L_95D1` ->
`DIBUJAR_LOGO_TOPOSOFT` (the real sequence that draws the logo).
Recompiled, 0 differences in `LOGOTOPO.CM` (4253 bytes) and the usual
baseline intact (7/2).

**Finding: more self-modifying code than thought when transcribing**.
Reviewing `L_94B1` in detail to answer what each of
`DIBUJAR_LOGO_TOPOSOFT`'s `CALL`s does, confirmed that `$94B2`, `$94BD`
and `$94E9` are ALSO self-modified operands (low bytes of 3 placeholder
`LD HL,$0000` instructions inside `L_94B1`, not just `$94F1`/`$94DD`
which were already commented) -- they're indices the caller injects
before every `CALL L_94B1`. And `$94F3` isn't a data address: it's
literally the OPCODE of the `OR (HL)` instruction at `$94F3` (inside
`L_94F2`) -- `DIBUJAR_LOGO_TOPOSOFT` sets it to `$00` (NOP, via
`XOR A`) at the start, and `L_956B` explicitly restores it to `$B6`
(`OR (HL)`) later, a self-modified "combine with VRAM YES/NO" switch.

**Confirmed mechanism**: `$94BD` (the "shape" index) is doubled and
looked up as a word in the pointer table `$9694` (15 valid entries,
indices 0-14 -- confirmed by real address overlap: entry 15 already
falls inside `L_950B`'s table at `$96B2`); the value is added to
`$9728` to get the shape data's real address. Every shape has a
2-byte header: 1st byte (self-modifies `L_94F0`'s `LD B,n` operand) =
bytes written per segment; 2nd byte (self-modifies `L_94DC`'s
`LD C,n` operand) = number of segments. `$94B2` (the "width/position"
index) feeds table `$96F8`, which turned out to be just an
incremental sequence (`$00C0,$00C1,$00C2...`) used as a row delta --
it doesn't contribute visual content, only positioning.

**Index tables decoded** (bytes extracted directly from the `.bin`, a
one-off script, no changes to the source code):
- `$96B2` (used by `L_950B`, animated with `HALT`): `1,1,2,2,3,3,4,4,
  5,5,6,6,5,5,4,4,3,3,2,2,1,1,0,0,FF` -- a symmetric "grow and shrink"
  (pulse) pattern, 24 entries + end.
- `$96CC` (used by `L_958E`, no `HALT`, 2 bytes/entry): an increasing
  row `$30->$70` with shape `6,5,4,4,3,2,2,1,2,2,3,4,5,6` -- a
  candidate for a curve/variable-thickness stroke.
- `$96E9` (used by `L_95AE`, animated with `HALT`, FIXED position):
  `11,12,13,12,11,12,13,14,FF` -- the same pulse pattern in a
  different index range (shapes 7-10, much larger than 0-6).

**New renderer**: `recursos/logotopo_formas.html` -- extracts (a
one-off script) the 15 shapes from table `$9694` and renders them as
8x8 monochrome tiles (1 bit/pixel, MSB=left, the VDP pattern table's
native format), with an adjustable "columns"-per-card control to
experiment with the real layout (the raw data alone isn't enough to
know whether they go in 1 long row or a grid -- the B/C header gives
the most literal layout, used as the default). Verified the extracted
bytes are real image data (not garbage): classic shading patterns
like `$AA`/`$55` (a bit-level checkerboard) and `$FF`/`$C0` (solid
fills) appear throughout shapes 7-10 (the 4 largest, 280-792 bytes).

**Pending**: visual identification of each shape (which letter/icon it
represents) -- a task for the developer with the renderer already
built, a starting point for naming `L_950B`/`L_9532`/etc. with more
confidence.

**Process note**: while injecting the shapes' JSON into the HTML via
PowerShell (`Get-Content -Raw` + `WriteAllText`), the file got
corrupted (mojibake: `—`/`ó`/`í` etc. wrongly encoded) -- PowerShell
interpreted the UTF-8 with the wrong codepage in the roundtrip. Fixed
by rewriting the whole file at once with the native write tool
(without going through PowerShell for non-ASCII text). Saved to
memory for future sessions.

### VISUALLY CONFIRMED the logo's full animation -- 9 routines renamed

The developer identified the real animation using
`recursos/logotopo_formas.html` (and shared a reference video, second
half of https://www.youtube.com/watch?v=gm3muULn91E, not consulted
directly -- verbal confirmation was enough): the logo animates the
letters T-O-P-O sliding/revealing to form "Topo", below it the word
"Soft" rotating in place, and finishes with a blinking star to the
right of the T. Exact mapping confirmed: idx7=T, idx8=1st O, idx9=P,
idx10=2nd O -- EXACTLY matching what had already been deduced from
the code (each routine sets `$94BD` to a constant shape index before
drawing).

**Renamed** (9 labels, all verified -- recompiled with no errors,
`LOGOTOPO.CM` 0 differences, the usual baseline intact 7/2):
- `L_94B1` -> `DIBUJAR_FORMA_ANIMADA` (the generic shape-drawing
  engine, now understood in detail: index in `$94BD`, the 15-shape
  pointer table `$9694`, a 2-byte header of bytes-per-segment/number-
  of-segments).
- `L_9532` -> `DIBUJAR_T_TOPO` (fixed shape=7, slides via `$94E9`).
- `L_954D` -> `DIBUJAR_P_TOPO_ANIMADA` (fixed shape=9, slides with
  `HALT` between steps).
- `L_956B` -> `DIBUJAR_O1_TOPO` (fixed shape=8, 7 steps with a
  different position-table offset).
- `L_958E` -> `DIBUJAR_O2_TOPO_ANIMADA` (fixed shape=10, 14 steps with
  an increasing row `$30->$70` -- a "stroke"-style reveal).
- `L_950B` -> `DIBUJAR_SOFT_ROTANDO` (shapes 0-6 via table `$96B2`, a
  0->6->0 pulse pattern, called 3 times from the main sequence).
- `L_95AE` -> `DIBUJAR_ESTRELLA_ANIMADA` (shapes 11-14 via table
  `$96E9`, the same pulse pattern).
- `L_9602` -> `LIMPIAR_TABLA_COLOR_VRAM`.
- `L_9688` -> `LIMPIAR_TABLA_PATRONES_VRAM`.

Header comments of `DIBUJAR_FORMA_ANIMADA` and `DIBUJAR_LOGO_TOPOSOFT`
rewritten to reflect the now-confirmed understanding (previously they
described loose hypotheses, "unidentified effects").
`recursos/logotopo_formas.html` updated: every card now shows the
shape's real name (e.g. "idx7 -- Topo's T") instead of just the
numeric index. `recursos/mapa_memoria_logotopo.html` updated with the
visual confirmation and the new names.

**Still unidentified**: 3-4 decorative routines that DON'T use the
shape engine (draw directly with fixed patterns `$71`/`$31`/`$81`):
`L_962B` (two "boxes" of lines), `L_9614` (block pattern fill),
`L_9473`/`L_94A6`/`ENTRADA_LOGOTOPO`-area (rectangle with `HALT`) --
asked the developer whether they recall any frame/line/rectangle in
the animation, no confirmed answer yet.

**Verified**: recompiled with no errors. `LOGOTOPO.CM` 0 differences.
The usual baseline intact (7/2). `.dsk`/`.cas` regenerated with no
issues.

### Completed the logo's visual identification: 4 more routines renamed -- the full animation understood

The developer supplied the rest of the visual sequence: after "TOPO"
is drawn, the text gets colored with an animation that expands from
the center outward; then "Soft" rotates; when finished, a point of
light travels along "Soft"'s top line and ends up next to the star,
over the T's corner. The ORDER exactly matches the real order of
calls in `DIBUJAR_LOGO_TOPOSOFT` (verified before renaming, not
after): after TOPO's 4 letters come 2 unidentified routines, then
`DIBUJAR_SOFT_ROTANDO` x3, then a third unidentified routine, then
`DIBUJAR_ESTRELLA_ANIMADA` -- a 1:1 mapping with "colors TOPO (2
routines) -> Soft rotates -> point of light (1 routine) -> star".

**Renamed** (4 labels, confirmed by the developer):
- `L_962B` -> `ANIMAR_COLOR_TOPO`: the color animation expanding from
  the center (two "boxes" of color lines starting at `$2658`,
  repeating 16 times with a 4-frame `HALT` pause between each step --
  the pause confirms it's an animation, not an instant draw).
- `L_9614` -> `RELLENAR_COLOR_TOPO`: the color's finishing touch/
  consolidation right after (called immediately after
  `ANIMAR_COLOR_TOPO`).
- `L_9473` -> `ANIMAR_PUNTO_LUZ_SOFT`: the point of light traveling
  along "Soft" (walks a VRAM address range `$2F78->$2FB8` with `HALT`
  as the timer between positions -- called right after
  `DIBUJAR_SOFT_ROTANDO`'s 3 rotations and right before
  `DIBUJAR_ESTRELLA_ANIMADA`, the exact expected position).
- `L_94A6` -> `ESCRIBIR_8_BYTES_VRAM` (the generic "write 8 bytes to
  VRAM(HL) with A's value" helper, used by several already-identified
  routines -- renamed for clarity, not for being its own visual
  part).

With this, **every top-level routine** in the already-transcribed
block (`$9470-$9693`) has a real name describing its role in the
animation -- only internal loop labels (`L_XXXX`) remain unrenamed,
which don't need it (internal convergence points, not independent
functions). Header comments of the 3 main routines and of
`DIBUJAR_LOGO_TOPOSOFT`/the file header rewritten to reflect the full
understanding.

`recursos/mapa_memoria_logotopo.html` updated (top note + segment
detail) reflecting the now-confirmed full animation.

**Verified**: recompiled with no errors. `LOGOTOPO.CM` 0 differences.
The usual baseline intact (7/2). `.dsk`/`.cas` regenerated with no
issues.

### `gen_cas_file.py` now packages OUR assembled LOGOTOPO.CM, not a verbatim copy

An explicit request from the developer: now that `logotopo_cm_body.asm`
is verified (0 differences against the reference `.bin`), the `.cas`
package must use OUR compiled binary, not the verbatim copy of
`load_cas/LOGOTOPO.CM.bin` used until now.

Changed `tools/gen_cas_file.py`: `logotopo`'s read switched from
`load_cas/LOGOTOPO.CM.bin` (verbatim copy) to `build/cas/LOGOTOPO.CM`
(generated by `main.asm` from `logotopo_cm_body.asm`). Important
detail: `build/cas/LOGOTOPO.CM` is the body's real 4253 bytes
(`SAVEBIN` ends at `END_OF_FILE_LOGOTOPO`, BEFORE the final loose
byte) -- the real 1988 block DOES include that loose byte ($00) as
part of the payload (already documented in the round that created the
file), so it's restored by adding `+ bytes([0x00])` in Python after
reading the file, with a comment explaining why. The file's docstring
and `src/README.md` updated (no longer say "verbatim copy" for
`LOGOTOPO.CM`).

**Verified**: `py tools/build_all.py` + `py tools/gen_disk_and_cas.py`
from scratch. `build/madmix_reconstruido.cas` (50242 bytes, the exact
size) compared byte for byte against the original 1988 `.cas`
(`FISICO/Mad Mix Game (1988).../...cas`): **exactly the same 9 usual
differences** (offsets 11902-11904 = `$28ED-$28EF` pre-existing,
unrelated; 23045/23296/24235/29318/29557 = the deliberate
`$FC60->$FC50` fix; 50241 = the file's last byte, already known) --
**no new difference**, confirming substituting `LOGOTOPO.CM`'s source
with our own didn't affect the packaging. `.dsk` untouched (doesn't
depend on `LOGOTOPO.CM`, doesn't apply).

### Segmented the rest of LOGOTOPO.CM (a single INCBIN -> tables and 15 shapes with real labels), and FIXED an error from this same session: there was no "loose byte", it was 4254 real bytes

An explicit request from the developer: section
`datos_sin_analizar_9691.bin` (the opaque 3705-byte INCBIN) into the
already-identified images (the 15 shapes, already visually confirmed)
and the rest of the pending blocks.

**Fixed an error introduced in an earlier round this same session**:
while computing each shape's exact boundaries using the real pointer
table (instead of assuming sequential packing), it turned out
`FORMA_ESTRELLA_4` should end exactly at `$A50D` -- the same address
that had been documented as "loose byte, unknown content, outside the
real range". The `.cas` block's `start=$9470 end=$A50D` header uses an
INCLUSIVE "end" (the same convention already used, and verified, for
`LOAD.BIN`/`TEST.BIN` -- `$DECA-$DDA0=298` +1 = 299 bytes, the
documented real size), not exclusive as assumed the first time the
file was split. The real body is **4254 bytes** (`$9470-$A50D` both
inclusive), with no byte out of range: the last byte is simply
`FORMA_ESTRELLA_4`'s real last bitmap byte. Fixed in
`logotopo_cm_body.asm` (the file header, `END_OF_FILE_LOGOTOPO` now
after the last shape) and in `gen_cas_file.py` (the `+bytes([0x00])`
that restored the missing byte is no longer needed).

**Real structure discovered** (verified with an extraction script
using the REAL pointer table, not assuming contiguity):

- `TABLA_PUNTEROS_FORMAS` (`$9694-$96B1`, 30 bytes): 15 words, now
  written as a label difference (`FORMA_X-TABLA_FORMAS`) instead of a
  hex literal, so they stay correct if any shape's size changes.
- `TABLA_ANIMACION_SOFT` (`$96B2-$96CA`, 25 bytes) + 1 loose,
  unexplained byte (`$96CB`) + `TABLA_TRAZO_O2_TOPO` (`$96CC-$96E8`,
  29 bytes) + `TABLA_ANIMACION_ESTRELLA` (`$96E9-$96F1`, 9 bytes): the
  3 index tables already decoded in an earlier round, now with a
  label and real data (previously only documented in prose).
- `VARIABLES_TRABAJO_FORMA` (`$96F2-$96F7`, 6 zero bytes): includes
  the 2 working pointers (`$96F4`/`$96F6`) `DIBUJAR_FORMA_ANIMADA`
  uses as scratch RAM.
- `TABLA_DELTA_POSICION` (`$96F8-$9727`, 48 bytes): **a second error
  fixed** in the same round -- the first attempts to write it as
  `DW $00C0..$00D7` produced 48 differences on recompile (the real
  high byte is the one that increments, `$C000..$D700`, not the low
  one -- `LD E,(IX+0)` reads the LOW byte first, `LD D,(IX+0)` the
  HIGH one after, so the real memory is "00 C0 00 C1..." =
  DE=$C000,$C100... not $00C0,$00C1...). Fixed and verified 0
  differences.
- `TABLA_FORMAS` (`$9728-$A50D`, the rest): the 15 real shapes, each
  extracted to its own binary file under `src/data/logotopo/formas/`
  (the same pattern as `.til`/`.spr` elsewhere in the project), with
  a 2-byte header (`DB width, rows`) written directly in the `.asm`.
  **New finding**: the PHYSICAL order in the file isn't sequential
  0..14 -- there's a 40-byte block of ORPHAN graphic data (the same
  `$AA`/`$55` shading pattern as the real shapes, but with NO entry in
  `TABLA_PUNTEROS_FORMAS` referencing it) between `FORMA_O1_TOPO` and
  `FORMA_P_TOPO` -- the same kind of finding as the 6 already-
  documented unused demo scripts in `madmix1_body.asm` (see
  `mapa_memoria.html`). Preserved as-is in
  `src/data/logotopo/formas/huerfano_9eea.bin`, no known use.

Removed `src/data/logotopo/datos_sin_analizar_9691.bin` (superseded
by the real segmentation, no longer referenced anywhere).
`recursos/mapa_memoria_logotopo.html` rewritten with the full
breakdown (8 segments instead of one generic "unexplored"), fixed the
same exclusive/inclusive "end" error in `RANGE_END`/`FILES`.
`src/README.md` updated (size 4254, status "COMPLETE", a new entry
for `logotopo_formas.html` in "HTML Viewers").

**Verified**: recompiled with no errors. `build/cas/LOGOTOPO.CM` now
4254 bytes (previously 4253), **0 differences** against the complete
`LOGOTOPO.CM.bin` (the 4254 real bytes, no longer 4253+1). The usual
baseline intact (`MADMIX.SCR` 7, `MADMIX1.BIN` 2). `.dsk`/`.cas`
regenerated: `madmix_reconstruido.cas` compared again against the
original 1988 `.cas`, **the same 9 usual differences, none new** --
confirms the size fix didn't affect the final packaging.

### Renamed every remaining L_ label in LOGOTOPO.CM (25 local + 1 global) -- the file has no pending placeholder left

An explicit request from the developer: review the 26 remaining
placeholder `L_XXXX` labels in `logotopo_cm_body.asm`, explain what
each one does and propose a name.

**2 labels removed** (`L_94DC`, `L_94F0`, inside
`DIBUJAR_FORMA_ANIMADA`): with no real `JR`/`JP`/`DJNZ` reference --
they had been added unnecessarily while transcribing, contributing no
real convergence point. Simply removed.

**24 labels converted to local** (internal loop points, no references
outside their routine): `.BUCLE_AVANZAR_PUNTO`/
`.BUCLE_ESPERA_3_FRAMES` (`ANIMAR_PUNTO_LUZ_SOFT`); `.BUCLE_8_BYTES`
(`ESCRIBIR_8_BYTES_VRAM`); `.BUCLE_SEGMENTO`/`.BUCLE_BYTE`
(`DIBUJAR_FORMA_ANIMADA`); `.BUCLE_POSICION` (`DIBUJAR_T_TOPO` and,
separately, `DIBUJAR_P_TOPO_ANIMADA` -- the same local name, different
scopes); `.BUCLE_SEGMENTO`/`.ULTIMO_SEGMENTO` (`DIBUJAR_O1_TOPO`, the
second one is the final stretch with `JP` instead of `CALL`, a tail-
call); `.BUCLE_TRAZO`/`.ULTIMO_TRAZO` (`DIBUJAR_O2_TOPO_ANIMADA`, the
same pattern); `.BUCLE_FOTOGRAMA`/`.BUCLE_ESPERA_4_FRAMES`
(`DIBUJAR_ESTRELLA_ANIMADA`); `.BUCLE_RELLENO`
(`LIMPIAR_TABLA_COLOR_VRAM`); `.BUCLE_FILA`/`.BUCLE_BYTE`
(`RELLENAR_COLOR_TOPO`); `.BUCLE_EXPANSION`/`.BUCLE_CAJA_1A`/
`.BUCLE_CAJA_1B`/`.BUCLE_CAJA_2A`/`.BUCLE_CAJA_2B`/
`.BUCLE_ESPERA_4_FRAMES` (`ANIMAR_COLOR_TOPO`, the animation draws the
same 2 line "boxes" twice, at 2 different start points -- hence the
1/2 suffix); `.BUCLE_8_BYTES` (`ESCRIBIR_8_BYTES_VRAM_C`, see below).

**1 label renamed as GLOBAL** (`L_967E` -> `ESCRIBIR_8_BYTES_VRAM_C`):
unlike the rest, it IS called from another routine (`ANIMAR_COLOR_TOPO`,
4 times) -- it couldn't be converted to local. It's a twin of
`ESCRIBIR_8_BYTES_VRAM` (the same "write 8 bytes to VRAM(HL) with A's
value via WRTVRM" pattern), but uses `C` as the counter instead of
`B` -- hence the `_C` suffix.

**A local-scoping trap, hit twice this same round** (already
documented in earlier project rounds, still easy to hit): converting
a label to local breaks compilation if a GLOBAL/non-local label falls
between its definition and its reference. It happened with `L_949F`
(between `.BUCLE_AVANZAR_PUNTO`'s definition and its return `JR`) and
again with a re-conversion from an earlier round this session -- fixed
by also converting those intermediate labels to local, the same fix
pattern already used in `madmix_scr_body.asm` (SIN_REGENERAR_MARICOCO)
and `test_bin_body.asm` (ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO) this
same session.

File header updated: no `L_XXXX` placeholder label remains anywhere
in `logotopo_cm_body.asm`.

**Verified**: recompiled with no errors. `LOGOTOPO.CM` 0 differences
(4254 bytes). The usual baseline intact (`MADMIX.SCR` 7, `MADMIX1.BIN`
2). `.dsk`/`.cas` regenerated with no issues.
`recursos/flujo_programa.html` regenerated: 643 labels (670 -> 643,
-27: -26 global->local conversions +1 new global, -2 removed).

### Review of `logotopo_cm_body.asm`'s data/variables: 6 hex substituted with table labels + decimal where it fits

An explicit request from the developer: review all data/variables,
convert to decimal what fits, check whether any hex can be substituted
with an already-existing label, and comment each one.

**6 hex addresses substituted with the real label** (all pointed
exactly to one of the tables already labeled in the previous
segmentation round, no byte change):
- `LD DE, $96F8` -> `LD DE, TABLA_DELTA_POSICION` (in
  `DIBUJAR_FORMA_ANIMADA`)
- `LD DE, $9694` -> `LD DE, TABLA_PUNTEROS_FORMAS` (same)
- `LD HL, $9728` -> `LD HL, TABLA_FORMAS` (same)
- `LD HL, $96B2` -> `LD HL, TABLA_ANIMACION_SOFT` (in
  `DIBUJAR_SOFT_ROTANDO`)
- `LD HL, $96CC` -> `LD HL, TABLA_TRAZO_O2_TOPO` (in
  `DIBUJAR_O2_TOPO_ANIMADA`)
- `LD HL, $96E9` -> `LD HL, TABLA_ANIMACION_ESTRELLA` (in
  `DIBUJAR_ESTRELLA_ANIMADA`)

**Decimal where it fits**: every shape index (`$94BD`), position-table
index (`$94B2`) and position/row (`$94E9`) self-modified by the 6
"effect" routines -- confirmed as pure index/position values, not
addresses or masks (e.g. `LD A,$07`->`LD A,7` = `FORMA_T_TOPO`'s
index). Every pure loop counter (`LD B,$XX`/`LD C,$XX` used with
`DJNZ`/`DEC`, never as a mask). The full color/pattern table sizes
(`LD BC,$1800`->`6144`, x2). Position steps (`ADD A,$08`->`8`,
`ADD A,$10`->`16`, `SUB $08`->`8`) and final-position comparisons
(`CP $18`->`24`, `CP $50`->`80`, `CP $98`->`152`). For consistency
with that same criterion, also `TABLA_TRAZO_O2_TOPO` (position/row
bytes, previously `$30..$70`, now `48..112`).

**Deliberately left in hex**: VRAM addresses (`$2F78`, `$2658`,
`$2000`, `$0000`), VDP color/pattern bytes (`$81`, `$F1`, `$F0`,
`$71`, `$31`), the real "OR (HL)" opcode (`$B6`, it's an opcode, not
data), table sentinels (`$FF`), the `$FFE8`-style signed delta
(`$FFF8` = -8), and `DIBUJAR_FORMA_ANIMADA`'s self-modified
placeholders (`LD HL,$0000` x3 -- their real value is never used,
always overwritten before being read).

**A separate finding, not applied**: `$2F78` is used IDENTICALLY as a
start address in two different routines (`ANIMAR_PUNTO_LUZ_SOFT` and
`RELLENAR_COLOR_TOPO`) with no label of its own -- a candidate for a
new `EQU` (as done with `$E290-$E293` in `test_bin_body.asm`), but the
semantic relationship between both uses is still unclear (see the
already-existing comment in `RELLENAR_COLOR_TOPO`). Same for `$2658`
(`ANIMAR_COLOR_TOPO`) and `$2000` (`LIMPIAR_TABLA_COLOR_VRAM`). Left
pending the developer's explicit confirmation before labeling, instead
of applying it directly.

**Verified**: recompiled with no errors. `LOGOTOPO.CM` 0 differences
(4254 bytes, comment-only/label substitutions, 0 code bytes changed).
The usual baseline intact (`MADMIX.SCR` 7). `.dsk`/`.cas` regenerated
with no issues.

### Confirmed by the developer: created the 3 pending VRAM labels from the previous entry

`$2000`/`$2658`/`$2F78` -- the 3 VRAM addresses (all inside SCREEN2's
color table, `$2000-$37FF`) that repeated identically across several
routines with no label of their own -- confirmed by the developer.
Created as `EQU` at the top of the file, next to `ENTRADA_LOGOTOPO`:
- `VRAM_TABLA_COLOR` = `$2000` (the table's full base, used by
  `LIMPIAR_TABLA_COLOR_VRAM`).
- `VRAM_COLOR_ZONA_TOPO` = `$2658` (used by `ANIMAR_COLOR_TOPO`).
- `VRAM_COLOR_ZONA_SOFT` = `$2F78` (used IDENTICALLY by
  `ANIMAR_PUNTO_LUZ_SOFT` and `RELLENAR_COLOR_TOPO` -- the name
  "ZONA_SOFT" is a convenience label, the exact semantic relationship
  between both uses is still not fully confirmed, a note left in
  `RELLENAR_COLOR_TOPO`'s comment).

**Verified**: recompiled with no errors. `LOGOTOPO.CM` 0 differences
(label substitutions only, 0 code bytes changed). The usual baseline
intact (`MADMIX.SCR` 7). `.dsk`/`.cas` regenerated with no issues.
`recursos/flujo_programa.html` regenerated: 646 labels (643 -> 646, +3
new `EQU`s).

## Full rewrite of `FLUJO_PROGRAMA.md` (it had been frozen since very early in the project)

A "wrap-up work/documentation" review requested by the developer:
comparing `FLUJO_PROGRAMA.md` against the current code confirmed that
almost the whole document (sections 1 through 6, ~550 lines) used
names from BEFORE the (at least) 250+ rename rounds recorded in this
same file -- with no "previously X now Y" note, meaning it was truly
out of date, not deliberate history (a single partial exception:
§5.10, which already used mostly current names). Confirmed with the
developer: a full rewrite now, not just marking it as historical nor a
partial update.

Re-read the current source code (`madmix0_body.asm`, `madmix1_body.asm`,
`madmix_scr_body.asm`) section by section to rebuild the document from
scratch, verifying every cited label against the real code (grep of
the ~85 global labels + several locals mentioned: ALL exist in the
current code, 0 invented).

**An architecture fix, not just names**: the old version said
`INIT_MAIN_LOOP` (`$8FD4`) was "the main loop". That's wrong -- that
address is `PREPARAR_INICIO_NIVEL`, a SINGLE-STEP sequence that only
runs on transitions (boot, level change, life lost), never every
frame. The real loop that repeats every frame is
`BUCLE_PRINCIPAL_JUEGO`/`VERIFICAR_FIN_NIVEL` (previously `IML_9078`/
`IML_90B7`), a bit further down in the same block. Fixed in the new
§4, with a diagram and an explicit clarification that the movement/
collision/scroll engine runs in parallel from the VBLANK interrupt
(`ENTRADA_INTERRUPCION_VBLANK`/`GESTIONAR_FRAME`), not inside
`BUCLE_PRINCIPAL_JUEGO`'s body.

Also updated the main menu's options table (§5.8) with
`DESPACHAR_ACCION_MENU`'s full detail (bits 1/3/4/5 -> the 4 options,
bit 0 = "PLAY" exits the loop) and documented the hidden infinite-
lives trick (`.COMPROBAR_TRUCO_VIDAS_INFINITAS` inside
`GESTIONAR_INTRODUCCION`, triggered with ESC in the intro, live-patches
`SUB $01` -> `SUB $00` in `BUCLE_PRINCIPAL_JUEGO`) that the old version
didn't mention.

Added a final explicit §7 section listing the genuinely pending
points/unconfirmed-live hypotheses (`INICIO`'s second `CALL $1000`,
`VERIFICAR_ENTRADA`'s pause bit, `MOTOR_ACTORES`'s sprite horizontal
flip, the sound driver's instrument tables), so as not to imply
everything is closed.

`recursos/flujo_programa.html` (which HAD been kept synced session by
session, unlike `FLUJO_PROGRAMA.md`) had only 2 loose out-of-sync
points, fixed: the "SCROLL_UP/DOWN/LR" abbreviation (current real
names: `SCROLL_ARRIBA`/`SCROLL_ABAJO`/`APLICAR_DESPLAZAMIENTO_LATERAL`)
in §2's table, and the manual "605 labels" count in the intro note and
the classification legend (out of date for several new-label-creation
rounds; fixed to 646, recomputed with `gen_inventory.py`).

**Verified**: recompiled with no errors after `gen_inventory.py` (646
labels, no code changes). A final grep over `FLUJO_PROGRAMA.md` for
~85 known old names (every rename family recorded in this file
relevant to the document): 0 matches.

### Full rewrite of `manuales/manual_driver_sonido.md` -- it was out of date, and its §8 ("unresolved") had been resolved for a while without the manual reflecting it

At the developer's request ("I think the sound driver manual is out of
date, review it"). Compared against the current code
(`madmix1_body.asm:3390-4426`, the driver's whole region): the manual
used practically every name from BEFORE the rename round documented
further above ("Renamed the remaining 26 RM_ labels of the sound
driver..."), with no "before/now" note -- truly out of date, just like
what happened to `FLUJO_PROGRAMA.md`. Rewritten completely, same
criterion: only what's genuinely out of date, preserving the rest of
the prose.

**A substantive finding, not just names**: the manual's §8 ("What
remains unresolved: the shared hardware envelope") described a mystery
that was **already resolved** in the code since the driver's rename
round (see above) -- nobody had simply come back to this manual to
reflect it. The shared envelope is specifically the **NOISE** envelope
(the PSG's register 6, noise period), not a generic hardware envelope
generator above volume/pitch as the old version suggested. Full
mechanism: `APLICAR_ENVOLVENTE_RUIDO` (the same phase structure as the
volume/pitch envelopes, a single phase, over the fixed table
`TABLA_ENVOLVENTE_RUIDO_PSG` instead of per channel) is reached by
falling through with no jump after `TICK_REPRODUCTOR_PSG`'s 3-channel
loop, writes the result to `$C9C4` (register 6's shadow) and ends in
`VOLCAR_REGISTROS_PSG`. `REINICIAR_ENVOLVENTE_RUIDO` is its relatch.
Along the way, fixed command 11's description
(`RESET_SHARED_ENVELOPE`): the manual said "clears the shared
envelope, only if the channel is the owner" -- it actually ALWAYS
clears the full 46 bytes of the executing channel's slot, and it
ALSO clears the 10-byte shared table if that channel is the owner.
Section 8 rewritten from "unresolved" to "resolved", with the full
mechanics.

Rest of the changes: architecture (§3), the tick loop (§4) and the
command table (§6) updated with the real names
(`INSTALAR_RECURSO_SONIDO`, `TICK_REPRODUCTOR_PSG`,
`PROCESAR_CANAL_PSG`, `DESPACHAR_COMANDO_PSG`, `ARMAR_NOTA`,
`CERRAR_NOTA`, `APLICAR_ENVOLVENTES_CANAL`, `ACTUALIZAR_MEZCLADOR_CANAL`,
`MULTIPLICAR_8X16`/`DIVIDIR_16X16`/`LEER_PALABRA_INDEXADA`,
`VOLCAR_REGISTROS_PSG`, `TABLA_NOTAS_PSG`, `TABLA_COMANDOS_PSG`,
`AREA_TRABAJO_PSG`, `TABLA_RETORNO_SUBPATRONES_PSG`,
`TABLA_TRANSPOSICION_PSG`, `TABLA_INSTRUMENTOS_PSG`,
`TABLA_ENVOLVENTES_PSG`, `TABLA_SUBPATRONES_PSG`, the 13 individual
`SUBPATRON_NN_XXXX`, `GUION_MELODIA_CANAL_0/1/2`, the 13
`GUION_EVTxx_..._CExx`, `VACIAR_CANALES_SONIDO`). §7 updated with
`DESPACHAR_EFECTO_SONIDO`/`EVENTO_SONIDO_PENDIENTE`/
`TABLA_RECURSOS_SONIDO_EVENTO`, the index table expanded with each
script's real label, and fixed the level-start-chord trigger (it's
`MOSTRAR_READY_Y_ARRANCAR_NIVEL`, not `IML_900F` as the old version
said -- verified by reading the real code, `madmix1_body.asm:2625-2654`).

**Verified**: a final grep over the manual for every known old driver
name (`LOAD_RESOURCE_SLOT_*`, `RM_*`, `*_TABLE_C*`,
`TAIL_LEVELCYCLE_HELPER`, `LEVELCYCLE_RESOURCE_TABLE`, `IML_900F`, a
loose `$6128`): 0 matches outside the 2 deliberate mentions framed as
"before/now". Not a code change (documentation only), no recompile
applies.

### New manual: `manuales/manual_motor_colision_ia.md` (movement/collision engine + AI of the 3 item types)

At the developer's request, after I myself suggested it as the second
candidate on finishing the sound manual review. A new document (not a
correction of an existing one), the same style/structure as
`manual_driver_sonido.md`. Re-read the real source code of
`madmix_scr_body.asm` section by section (the collision engine
`$2CA0-$335C`, the 20-type dispatch table `$2E3C`, the generic item-
movement engine `$5278`, and the 3 item handlers
`HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO` plus
`ACTIVAR_EFECTO_ITEM`/`AVISAR_PROXIMIDAD_PISTA`/`ARMAR_AVISO_DESTELLO`/
`ACTUALIZAR_DESTELLO_ITEMS`) to rebuild the explanation from scratch,
instead of just summarizing what was already written in
`FLUJO_PROGRAMA.md`.

New content, not just reorganizing what was already known: clarifies
that `HNDLR_MARICOCO` (ladybug) and `HNDLR_REGPUNANTOSO`
(repugnantoso) are a PAIR with opposite effects over the same tile-
index range (63-65 "no ball" -> regenerates to 45-47 "with ball" vs.
45-47 -> plants to 48-50 "with dunked ball"), share a movement engine
(`MOTOR_MOVIMIENTO_ITEM`) and a coordinate helper
(`MAPEAR_COORDENADA_A_DIRECCION_LOCAL`, one of the 5 already-
documented level-13-bug sites), and differ in when they set their
"planted" flag ((IX+2), at the end vs. on entry) and in whether they
touch `CONTADOR_BOLAS_COMIDAS`. Also explicitly notes that this engine
is NOT real pathfinding (no BFS/A*, only looks at the 4 adjacent
tiles) and that the 8 ghosts in `TABLA_ITEMS_PELMAZOIDE` all run the
same code with no per-ghost personality distinction (unlike the
original Pac-Man).

**Verified**: a final grep over the manual for the 56 cited labels
(handlers, tables, state variables) against `madmix_scr_body.asm`: all
56 exist as-is in the current code, 0 invented. Not a code change
(new documentation only), no recompile applies.

### New manual: `manuales/manual_subsistema_grafico.md` (VDP in SCREEN 2, an actor engine with no hardware sprites, tiles and software scroll)

At the developer's request, the third manual in the series, following
my own initial suggestion (the first time "what other manuals could we
make" came up this session, before writing the collision/AI one).
Re-read the real source code of `madmix1_body.asm` (the full actor
engine `MOTOR_ACTORES`/`COMPONER_ACTORES_EN_BUFFER`/pattern inversion,
the VDP API `FILVRM`/`LDIRVM`/`SETVRAM`, the tile system
`MAPEAR_LOSETA_A_GRAFICO`/`ACTUALIZAR_VRAM_FRAME`) and
`madmix_scr_body.asm` (`DIBUJAR_PORTADA` with its color decompression,
`APLICAR_COLOR_PANTALLA`/`OBTENER_COLOR_VDP`).

**Explicit verification of the manual's central point** (the "inherits
the Spectrum's approach" hypothesis that motivated the idea): grepped
`SPRT`/mentions of an attribute table or VDP registers 5/6 (hardware
sprites) across all of `src/*.asm` -- 0 matches. Confirms the actor
engine never touches the VDP's hardware sprite plane: it composites
every character with AND/OR masks + bit-by-bit sub-pixel shifting
directly onto SCREEN 2's pattern table, the same blitting algorithm a
Spectrum game would use (which has no hardware sprites). Also
documented an already-known finding never explained before in one
place: `CALCULAR_DIRECCION_MASCARA_ACTOR` reuses a sub-range of
`TABLA_RLE_MARCO_CARAMELO` (the HUD candy frame's RLE table) as actor
clipping masks -- double purpose for the same table, memory economy
typical of a 64KB MSX1 (see FINDINGS.md, "Zone 0xDC00", a much older
entry).

**Verified**: a final grep over the manual for the ~42 cited labels
against `madmix1_body.asm`/`madmix_scr_body.asm`: all exist as-is in
the current code, 0 invented. Not a code change (new documentation
only), no recompile applies.

### New manual: `manuales/manual_niveles.md` (the 15 levels' format, the 20-byte record, level load and end)

At the developer's request, the fourth manual in the series -- the
"most practical" candidate I myself proposed. Re-read the real source
code of `madmix_scr_body.asm` (`CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL`/
`INICIALIZAR_PARCIAL_ITEMS_NIVEL`, the full 20-byte level record field
by field, `TABLA_NIVELES`'s header with the dead record 0 and the 3
shared-header files, `GESTIONAR_CICLO_NIVELES`) and of
`madmix1_body.asm` (`VERIFICAR_FIN_NIVEL`).

Along the way, fixed 3 old names left loose in
`tools/mmlvl_tool.py`'s docstring (never updated in the rename round
that gave them a real name): `LEVEL_LOADER` -> `CARGAR_NIVEL`,
`LEVEL_TABLE` -> `TABLA_NIVELES`, `MAP_COORD_TO_ADDR` ->
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`/`MAPEAR_COORDENADA_A_DIRECCION`.
Verified the script is still valid Python after the change
(`py -m py_compile`).

New content, not just reorganizing: documents for the first time in
one place the wildcard `$3C` substitution's alternation based on
`CONTADOR_VUELTAS_NIVELES` (never substituted on the first loop
through the 15-level cycle; on later loops, it alternates) and
explicitly notes that the "hidden level" (15) is reachable in a normal
game with no trick at all, upon completing 14 -- `VERIFICAR_FIN_NIVEL`
gives it no special treatment.

**Verified**: a final grep over the manual for the 35 cited labels
(level record, loader, tables) against `madmix_scr_body.asm`/
`madmix1_body.asm`: all exist as-is in the current code, 0 invented.
Minimal code change (3 names in a docstring, verified with
py_compile), no sjasmplus recompile applies.

### Confirmed by real data: the level record's reference point is always the ghost house

Following a direct question from the developer ("in every level do
the enemies always come out from the ghost house?"), verified by
cross-referencing `REGISTRO_NIVEL_FILA_COLUMNA` (offset 13-14 of the
record, the point where `INICIALIZAR_ITEMS_NIVEL` places the 3 item
tables) against each level's real body. The tile catalog has a
dedicated 3-tile structure
`puerta_fantasmas_inicio_izquierdo`/`linea_electrica_puerta_fantasmas_a`/
`puerta_fantasmas_inicio_derecho` (`$50`/`$38`/`$51`) that visually
marks the house on the map -- the central tile (`$38`, type 8 in
`TABLA_MANEJADORES_LOSETA`) is one of the few NOT walkable by these
items (see `manual_motor_colision_ia.md` §5).

**Level 1** (`body_l01.bin`): the door appears in the body at column
12 (body row 9, columns 11-13, center 12).
`REGISTRO_NIVEL_FILA_COLUMNA` = `$30,$34` = raw column 48/4=12
(EXACT), raw row 52/4=13 -- a +1 row offset relative to the real door
(full-buffer row 12), consistent with items appearing right below the
door (the central tile is blocked).

**Level 2** (`body_l2.bin`): the door appears at column 16 (body row
11, columns 15-17, center 16). `REGISTRO_NIVEL_FILA_COLUMNA` =
`$40,$3C` = raw column 64/4=16 (EXACT), the same +1 row offset.

The exact same pattern in both levels despite having completely
different dimensions and reference values -- confirms with data
evidence, not just via the code's mechanism, that the original design
deliberately places each level's reference point at its own ghost
house. Documented in `manual_niveles.md` §5.1 (not exhaustively
verified across all 15 levels, but the pattern is systemic and there's
no reason to expect an exception).

**Also**: fixed `LEVEL_LOADER` (`CARGAR_NIVEL`'s old name) in
`tools/mmlvl_tool.py`'s `WARNING_BANNER`/`FLAT_BANNER` template and,
so the fix is real and not just for future regenerations, in the 18
`.txt` files in `data/niveles/` that already had the notice recorded
with the old name.

**Verified**: `py -m py_compile` on `mmlvl_tool.py` with no errors; a
`roundtrip-all` of the 18 level files after the change: 18/18
identical (a comment-only change, 0 data bytes affected).

## FIXED: the real format of the 64 character sprites is 24×24 with 2 interleaved planes (mask+pattern), NOT a single 24×48 image

The milestone that resolved `PTR_TABLA_SPRITES` (further above, "BIG
MILESTONE: the 64 CHARACTER SPRITES identified and transcribed") left
documented that each 144-byte entry was regrouped into 48 rows 24px
wide, a format the developer identified at a glance on
`ptrtable_sprites.html` at the time. That reading produced recognizable
sprites but **with white/black horizontal background stripes and an
elongated look** -- it was the developer themself who, looking at the
already-published catalog (`recursos/ptrtable_sprites.html` and the
poster's actor mosaic), noticed that visual defect and asked whether
two patterns' data were actually being mixed, since in the ZX
Spectrum version of the game the sprites are 24×24 with two patterns.

**Empirical check** (before touching any file): for several real
`.spr` files (`27_fantasma_der_1.spr`, `00_pm_vuln_der_cerrada.spr`),
three regrouping hypotheses for the 144 bytes were rendered
separately:

1. 48 rows of 3 bytes in a row (the old reading) -- background stripes
   in every row, an elongated look. Confirms the defect the developer
   reported.
2. Two 24-row blocks (bytes 0-71 and 72-143 as two stacked 24×24
   images) -- **still striped** in both halves. Rules out this
   hypothesis.
3. Interleaved even/odd rows (real row 0 = bytes 0-2, row 1 = bytes
   3-5, row 2 = bytes 6-8, ...) -- **no stripes, two clean, recognizable
   24×24 images**: the ghost comes out perfect on both planes, same
   for the pac-man (a circle with an eye and a mouth).

That is: each of the sprite's 24 real rows takes up **6 consecutive
bytes** (3 from one plane + 3 from the other), not 3 loose bytes
repeated 48 times as assumed. It matches exactly the blitting
algorithm already documented in `manual_subsistema_grafico.md` §4
before this finding: "an AND mask (keeps the background where the
sprite is transparent) followed by OR (applies the sprite's pattern)"
-- a classic mask+bitmap needs two planes of the same size, one per
operation. It also matches something already known but never fully
explained: `JTS2_XOR_TRANSFORM` reads 3 bytes, 48 times in a row, with
self-modification -- that's 24 [mask, pattern] pairs, not 48 rows of a
single image.

Of the two planes, the one producing each character's "normal" look
(a light body with dark details, e.g. the pac-man as a white circle
with a dark eye/mouth) is labeled here as **pattern/ink** (offset +3
of each 6-byte group); the other, mostly solid-looking with the same
gaps in negative, is labeled as **mask** (offset +0). The mask=first 3
bytes / pattern=next 3 bytes assignment is the interpretation most
consistent with the already-documented AND-then-OR algorithm, but the
exact Z80 code that consumes this table (which exact `MOTOR_ACTORES`
routine reads each plane) still hasn't been located line by line --
same as it already stood unresolved in the original milestone.

**Updated**: `recursos/ptrtable_sprites.html` (the decoder and the 3
views, View 3 now shows pattern and mask side by side),
`recursos/mmg_poster_dossier.html` (the "Real actor catalog" mosaic),
`src/README.md` (the pixel-format table and file tree), the header
comment in `src/madmix1_body.asm` before `SPR00_PM_VULN_DER_CERRADA`.
Doesn't affect a single data byte or compiled binary -- it's a fix to
how the already-100%-transcribed `.spr` is INTERPRETED/displayed, not
to the bytes themselves.

## LIVE-CONFIRMED (openMSX): the camera's H/L axis and the 4 scroll routines were NOT swapped -- an outside developer's hypothesis doesn't hold up

An outside developer reviewing the project raised a reasonable doubt
about `GESTIONAR_SCROLL`/`SCROLL_ARRIBA`/`SCROLL_ABAJO`/
`SCROLL_IZQUIERDA`/`SCROLL_DERECHA` (`madmix1_body.asm`, see also
`manual_subsistema_grafico.md` §6): that the comment `HL = camera
position (H=horizontal axis, L=vertical axis)` was swapped, and that
`SCROLL_IZQUIERDA` was actually `SCROLL_ARRIBA` (and vice versa).
Before touching anything, this was verified **live**, not just by
reading the code.

**First pass (static analysis, LATER DISCARDED)**: looking only at
the code, `SCROLL_ARRIBA`/`SCROLL_ABAJO` chain 24 `RLD`/`RRD` within
each of the buffer's 144 rows (a classic Z80 *horizontal* sub-pixel
shift technique), while `SCROLL_IZQUIERDA`/`SCROLL_DERECHA` copy whole
rows with `LDI` to the neighboring row (`APLICAR_DESPLAZAMIENTO_LATERAL`,
a ±32 step = one row, a classic *vertical* shift technique). That
reasoning led to an earlier conclusion that yes, the names were
swapped -- matching the outside developer's suspicion. **That
conclusion was wrong**: probably from a mistaken assumption about
`BUFFER_LOSETAS_TRABAJO`'s real row/column orientation in memory. This
stands as a methodology warning: plausible mechanical reasoning about
code, without running it, can fail just like any other hypothesis --
which is why it moved to live verification before fixing anything.

**Live verification (the one that counts)**: using openMSX's external
control protocol (`-script`, `debug breakpoint create -address ...
-command {...}`, `debug read "memory" ...`), breakpoints were
installed at the entry of the 4 scroll routines and right after each
one saves the updated camera position (`0x8A56` for
`SCROLL_IZQUIERDA`/`SCROLL_DERECHA`'s tail, `0x8B2D` for
`SCROLL_ARRIBA`/`SCROLL_ABAJO`'s), recording in each case the real
bytes of `REGISTRO_NIVEL_POSICION_COMECOCOS` (`$2C02`=L, `$2C03`=H).
With the reconstructed `.dsk` loaded on the `Mitsubishi_ML-G3_ES`
machine (it has a real floppy drive, unlike the `C-BIOS_MSX1_*` ones,
which don't), the developer played moving in all 4 directions (default
keys: Q=up, A=down, O=left, P=right) for ~2 minutes. Result,
consistent with no exception across hundreds of captured events:

```
SCROLL_ARRIBA    -> L goes up    (H constant)
SCROLL_ABAJO     -> L goes down  (H constant)
SCROLL_DERECHA   -> H goes up    (L constant)
SCROLL_IZQUIERDA -> H goes down  (L constant)
```

That is: **each routine moves exactly the axis its name says**, and
the comment `H=horizontal axis, L=vertical axis` was correct. There
was no swap at all. Fixed the 3 comments that still marked this as
`HYPOTHESIS ... unconfirmed live` (`madmix1_body.asm`,
`GESTIONAR_SCROLL`'s header and the `SCROLL_IZQUIERDA`/`SCROLL_DERECHA`
labels) to `LIVE-CONFIRMED`. Doesn't affect a single data byte or
compiled binary -- only the comment.

**Technical note on the verification infrastructure itself**:
openMSX's control protocol requires `-diska` with a machine that has a
real floppy drive (`Mitsubishi_ML-G3_ES` worked; the `C-BIOS_MSX1_*`
ones have no FDC and fail silently); `-control pipe` left the machine
unbooted waiting for an external client that never arrived (better to
launch without that flag so it boots on its own, with a visible
window); openMSX's timer command is `after realtime <seconds>`, not
milliseconds (a real `after realtime 45000` is 12 hours, not 45
seconds -- a real mistake made and fixed during this same
verification); and manually forcing `PC` with `reg PC` to skip the
menu is risky (it left the CPU in `HALT` with interrupts disabled) --
more reliable to let the developer themself navigate the real menu
while the breakpoints, already armed since boot, capture the data
without interfering with the game's flow.
