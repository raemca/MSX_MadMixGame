# Graphics subsystem manual — Mad Mix Game (MSX1, TMS9918 VDP in SCREEN 2)

*[Leer esto en español](manual_subsistema_grafico.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Source: `madmix1.asm` (actor engine, VDP API, tile buffer,
> scroll) and `madmix_scr.asm` (cover art, screen color,
> candy frame). For the chronicle of how each piece was discovered,
> see `FINDINGS.md`; this document assumes everything is already
> identified and explains the final result in an orderly way.

## 1. What this is and what it is NOT

This manual explains how the game puts graphics on screen: the video
mode it uses, how it draws the maze and its scroll, and — the most
important point, because it surprises anyone who knows MSX hardware —
how it draws Pac-Man, the ghosts and the rest of the characters.

**Central point of the manual**: the game uses `SCREEN 2` (the
TMS9918's bitmap mode, the same VDP as the MSX1) but **never uses
the chip's hardware sprites at any point** — not a single write to
the sprite attribute table or to the sprite pattern generator has
been found anywhere in the transcribed code (`FILVRM`/`LDIRVM`
only touch the bitmap mode's pattern table and color table).
Instead, the actor engine (§4) composes every character by hand —
mask + pattern, with bit-level sub-pixel shifting — directly
onto the pattern table, exactly the same AND/OR-mask "blitting"
approach a ZX Spectrum game would use (which doesn't even have
hardware sprites). This is the real technical explanation behind
the feeling, while playing, that the engine "behaves like a
Spectrum" — it's not a vague impression, it's literally the same
compositing algorithm.

**Nor** is it a tile engine with hardware scroll support: the MSX1
has no scroll assist at all in the VDP (unlike contemporary consoles
with hardware "fine scroll"), so the camera's 4px scroll (§6) is also
pure software — nibble shifting over a Z80 RAM buffer, dumped to VRAM
in full every frame.

## 2. The hardware: TMS9918 in `SCREEN 2` (Graphics I)

Three relevant tables in VRAM (16 KB addressable, accessed via two
I/O ports: `$98`=data, `$99`=control/address):

| VRAM zone | Size | Content |
|---|---|---|
| `$0000`-`$17FF` | 6144 bytes | **Pattern table**: the real bitmap, 8 bytes (rows) per character cell, 256 patterns × 3 screen "thirds" (each third has its own copy of the 256 patterns — a `SCREEN 2` quirk, each 8-character-row block has its own independent pattern generator) |
| `$1800`-`$1AFF` | 768 bytes | **Name table**: which pattern to draw in each of the screen's 32×24 cells |
| `$2000`-`$37FF` | 6144 bytes | **Color table**: 1 byte per EACH ROW of each pattern (not per whole cell) — high nibble = ink, low nibble = background; confirmed exact: `TABLA_COLOR_MARCO_CARAMELO` is 768 cells × 8 bytes = 6144 |

**The "identity name table" trick**: instead of using the
name table to index patterns indirectly (as a traditional tileset
would), the game writes `name = pattern index`
literally (0, 1, 2... 255, repeated across the 3 thirds) — see
`DIBUJAR_PORTADA` (§7) and the main engine. This effectively turns
`SCREEN 2` into a **pattern-addressable bitmap**: the
game draws directly by writing bytes to the pattern table
(indexed by pattern number = screen position), without having to
keep a separate name table in sync. It's the same
philosophy as a plain framebuffer, adapted to `SCREEN 2`'s
structure.

## 3. The custom VDP API (not the MSX BIOS)

The game reimplements by hand the 3 classic MSX BIOS routines
(`FILVRM`/`LDIRVM`/`SETWRT`), instead of calling them via `CALL` into
ROM — likely reason: avoiding the overhead of a BIOS call in routines
that run many times per frame. Confirmed byte for byte,
`madmix1.asm`, `$8931`-`$8960` (with no gap between them):

- **`SETVRAM`** (equiv. `SETWRT`): sets the VDP's write
  pointer to the address in `HL` — low byte to port `$99`, high byte
  (masked to 14 bits) `OR $40` (the "set write
  pointer" command) also to port `$99`, with a 2 `EX (SP),HL`
  delay that the VDP requires after the command.
- **`FILVRM`**: fills `BC` bytes of VRAM starting at `HL` with the
  fixed byte `A` — nested loop of `OUT ($98),A` (up to 256×256
  iterations).
- **`LDIRVM`**: copies `BC` bytes from RAM (`HL`) to VRAM (`DE`), byte
  by byte with `OUT ($98),A`.

The rest of the graphics subsystem relies on these 3. The cover art
(§7) and screen boot also directly write VDP
registers: `OUT ($99),value` followed by `OUT ($99),register_number OR $80`.

## 4. The actor engine WITHOUT hardware sprites: `MOTOR_ACTORES`

This is the heart of the subsystem — called to draw EVERY
character (Pac-Man, ghosts, ladybug, "repugnantoso", tank/plane
tracks, HUD icons...) every time it needs redrawing.
Up to 10 simultaneous active actors per frame (`$8437`, counter),
indexing a table of 64 source sprites (`PTR_TABLA_SPRITES`).

**The algorithm, in 2 separate passes** (first pass inside
`MOTOR_ACTORES` itself; second, `COMPONER_ACTORES_EN_BUFFER`, see
below):

1. **Filtering and clipping**: discards the actor if there are
   already 10 active, if the sprite index isn't valid, or if its
   column falls outside the visible window (`< 4` or `≥ 116`). Computes
   vertical clipping against the camera edge
   (`TABLA_MASCARA_RECORTE_BORDE`, indexed by column) and reserves a
   12-byte register in an actor array (`$92E3`).
2. **Flipping**: if the sprite needs horizontal flipping (2
   independent flags in bits 6-7: bit order within each byte,
   and byte order within each row), it applies it BEFORE drawing,
   on a temporary copy of the pattern — `INVERTIR_BITS_PATRON_ACTOR`
   (classic bit-by-bit mirroring, `RLC`/`RRA` × 8 per byte) and
   `INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (swaps bytes from both
   ends toward the center). This is the same mechanism ghosts/
   ladybug/"repugnantoso" use to reuse a single "right-facing"
   sprite as "left-facing" (see `manual_motor_colision_ia.md` §6).
3. **Sub-pixel shifting + mask blending**: the MSX engine has
   no sprite shifting finer than 1 character pixel in
   hardware — here **0 to 7 bit** (sub-character) shifting is
   implemented by rotating the pattern bit by bit between registers
   (chained `RRA`/`RR`/`RL`, alternating banks with `EXX` to process 2
   rows at a time) and blending it with the background via an
   **AND mask** (preserves the background where the sprite is
   transparent) followed by an **OR** (applies the sprite's pattern) —
   the classic hardware-less "mask + bitmap" blitting algorithm, with
   two nearly identical variants depending on shift
   direction (`DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`).
4. **The clipping masks don't come from their own static table**:
   `CALCULAR_DIRECCION_MASCARA_ACTOR` computes its address as
   `$DC00 + (screen_position / 8)` — and `$DC00` **is not a
   dedicated table**, it's a sub-range of
   `TABLA_RLE_MARCO_CARAMELO` (the HUD candy frame's RLE
   compression table) **reused for a second purpose**
   at the same time: memory economy typical
   of a 64KB MSX1. Confirmed real (matches live RAM
   dumps), not an analysis artifact.
5. **Two passes by design**: `MOTOR_ACTORES` does not write the
   final result directly — it copies each row's 3 masks/pattern to a
   **cursor in low RAM** (`$0500` onward, `CAPTURAR_MASCARAS_ACTOR`),
   and it's a second function, `COMPONER_ACTORES_EN_BUFFER`, that
   walks that cursor and applies the final `AND`/`OR` onto the
   screen buffer — with **self-modifying code**: the 6 mask
   operands of its 6 iterations ("forward" and "back", in identical
   pairs 1=6/2=5/3=4) are rewritten on the fly with the 3 clipping
   bytes of each actor before processing it. Research note: the
   real `CALL`/`JP` that invokes `COMPONER_ACTORES_EN_BUFFER`
   has not been found in the code transcribed so far — its
   mechanics are confirmed, its trigger is not.

## 5. The maze tile system

Unlike actors (which are actively recomputed and redrawn every
frame that needs it), the maze is a **Z80 RAM working
buffer** (`BUFFER_LOSETAS_TRABAJO`, `$DE04`, NOT in VRAM) that gets
updated and dumped to VRAM in full once per frame:

- **`MAPEAR_LOSETA_A_GRAFICO`**: given a camera/tile
  position, computes the real address of the corresponding
  graphic pattern (`GRAFICOS_LOSETAS` + an index derived from the tile
  type via `TABLA_TIPOS_LOSETA`) and copies it (2 words = 4 bytes per
  character cell, repeated) into the working buffer. It's the routine
  `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` consumes to redraw a
  full strip of background after the camera moves.
- **`ACTUALIZAR_VRAM_FRAME`** (called once per frame from
  `GESTIONAR_FRAME`, the VBLANK ISR — see `FLUJO_PROGRAMA.md`
  §5.10): at the end of its work (HUD icon, flash zones),
  dumps the entire `BUFFER_LOSETAS_TRABAJO` to the VRAM
  pattern table (`ZONA_PATRON_VRAM_LABERINTO`, `$0220`) — 18 rows × 8
  character columns, byte by byte via direct `OUT ($98),B` (faster
  than calling `LDIRVM`). **Confirms a key architectural point**: the
  scroll (§6) NEVER writes to VRAM directly — it only prepares the
  RAM buffer; this function is the only one that copies that buffer
  to real VRAM.
- **Incremental vs. full redraw**: `REDIBUJAR_LOSETA_BUFFER_VRAM`
  updates a single tile (16×16px) in the buffer, either via a
  direct or queued call (`APILAR_PETICION_REDIBUJADO`/
  `VACIAR_COLA_REDIBUJADO`, drained every frame by `GESTIONAR_FRAME`).
  `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` does a TOTAL redraw
  (36 passes of `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) — used when
  starting/changing level, not every frame.

## 6. Software scroll (4px, no scroll hardware)

Summary — see `FLUJO_PROGRAMA.md` §4 and `manual_motor_colision_ia.md`
for the full direction dispatcher. The graphics mechanism itself:

`SCROLL_ARRIBA`/`SCROLL_ABAJO` shift the 144 rows of
`BUFFER_LOSETAS_TRABAJO` 4 vertical pixels by chaining **24 `RLD`/`RRD`
per row** (the Z80 nibble-rotation instruction through
`(HL)` and A's low nibble) — a classic 8-bit trick to
shift half-byte content without explicit bit-by-bit
shifting. `SCROLL_IZQUIERDA`/`SCROLL_DERECHA` (`APLICAR_DESPLAZAMIENTO_LATERAL`)
do the horizontal equivalent. All 4 routines end in
`SCROLL_LOSETA_BUFFER_VRAM`, which chooses between 2 copy "phases"
(`COPIAR_LOSETA_FASE_A`/`_B`) depending on the resulting byte
alignment. The result stays in `BUFFER_LOSETAS_TRABAJO` — the real
dump to VRAM is done by `ACTUALIZAR_VRAM_FRAME` (§5), not by the
scroll itself.

## 7. Color: compressed cover art, candy frame, and flash zones

**The cover art** (`DIBUJAR_PORTADA`, `madmix_scr.asm`, the real
entry point after relocation): turns off the screen, writes the
identity name table, dumps the UNCOMPRESSED bitmap (`PORTADA_PATRON`,
6144 bytes, the whole pattern table) and then **decompresses** the
color from a packed format: 768 groups, each with a control
byte (0 = direct color 0/0; otherwise, two 4-bit indices
packed into the byte) that indexes a 16-value palette
(`PALETA_COLORES_PORTADA`) to build the final color byte
(high/low nibble), replicated 8 times (one full character
column). A custom compression scheme, not a standard format.

**The rest of the screen** (HUD candy frame, maze background color
during play): `APLICAR_COLOR_PANTALLA` (despite its
name, confirmed to apply the color of the WHOLE screen, not just the
frame) translates 768 bytes of `TABLA_COLOR_MARCO_CARAMELO` with
`OBTENER_COLOR_VDP` (builds the high/low nibble from `TABLA_COLORES_VDP`,
the same 16-color VDP table `CONSULTAR_COLOR_VDP` uses in
`madmix1.asm`) and fills the entire VRAM color table via
`FILVRM`. The frame's SHAPE (which pattern to draw, not its color) comes
from `TABLA_RLE_MARCO_CARAMELO` (classic RLE compression: pairs
`[value, repeat]`, 870 bytes) — the same table that, reused
twice over (§4), also serves as the actor clipping mask.

**HUD flash zones**: `ZONA_COLOR_VRAM_DESTELLO_A`/`_B`
(`$2A80`/`$2B80`, 16 bytes each) — colored by `ACTUALIZAR_VRAM_FRAME`
every time `COLOR_ACTUAL` changes, for the HUD icon/color blink
during special modes (see `manual_motor_colision_ia.md` §8).

## 8. Relevant VRAM addresses and constants

| Constant | Address | What it is |
|---|---|---|
| — (pattern table) | `$0000`-`$17FF` | full `SCREEN 2` bitmap |
| — (name table) | `$1800`-`$1AFF` | identity (name=pattern), never touched after initialization |
| `ZONA_PATRON_VRAM_LABERINTO` | `$0220` | destination of the `BUFFER_LOSETAS_TRABAJO` dump (maze's visible pattern) |
| — (color table) | `$2000`-`$37FF` | full `SCREEN 2` color, 1 byte per pattern row |
| `ZONA_COLOR_VRAM_DESTELLO_A`/`_B` | `$2A80`/`$2B80` | HUD icon/flash color (16 bytes each) |

## 9. Confidence and open items

The actor compositing mechanics (masks, sub-pixel
shifting, double pass) are 100% verified against the real
disassembly and against live VRAM/RAM dumps. Genuinely
open points:

- The real caller of `COMPONER_ACTORES_EN_BUFFER` has not been
  identified in the code transcribed so far (§4).
- The exact purpose of the variable at `$8435` (fixed at 3 in
  several places) and of bits 6-7 used as a vertical-half
  selector in `MOTOR_ACTORES` (`$843E`, 144 vs 176) — mechanics
  confirmed, exact semantics not fully closed.
- The `$4000`-adjacent stretch of `ACTUALIZAR_VRAM_FRAME` (an
  `LDIR` from RAM to RAM with no observable effect, `BC=$052B`) — the
  "timing padding" hypothesis has been ruled out (the cycle counts
  don't match), real purpose unconfirmed.

## 10. To dig further

- `FINDINGS.md` — every section related to VDP/VRAM/the actor
  engine, in chronological order, with the full reasoning behind
  each discovery (search for "Zona 0xDC00" for the finding about
  reusing `TABLA_RLE_MARCO_CARAMELO` as masks).
- `FLUJO_PROGRAMA.md` §5.1/§5.4 — a shorter summary, in the context
  of the game's full flow.
- `manual_motor_colision_ia.md` — who decides WHAT to draw and WHEN
  (this manual only documents the HOW of getting it into VRAM).
- `graficos.html`/`niveles.html` (recursos) — a visual catalog of
  already-identified tiles and sprites, useful as a reference while
  reading this manual.
