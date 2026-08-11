# Manuals

*[Leer esto en español](README.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

This folder is different from `FINDINGS.md` (a chronological diary of
findings) and from `FLUJO_PROGRAMA.md` (an inventory organized by
execution flow). Those document **how each thing was discovered**, in
the order it was investigated, with all the uncertainty and dead ends
along the way.

Here, instead, each already-understood subsystem is documented as
**how it works**, in an orderly, pedagogical way — as if it were the
technical manual an era-appropriate programmer would have left for a
new colleague. Two concrete goals:

1. **Training**: so that a programmer joining the project (or any
   similar reverse-engineering effort) can learn how each piece
   really works without having to reconstruct the whole research
   process.
2. **Preservation**: to leave a clear, readable record of how this
   piece of 8-bit software archaeology is built, beyond the
   reconstructed source code itself.

Each manual assumes the reader knows Z80 assembly and programming in
general, but **does not** assume anything specific about this
project or about MSX sound hardware — that gets explained from
scratch the first time it's needed.

## Index

- [`manual_driver_sonido.md`](manual_driver_sonido.md) — the
  AY-3-8910 PSG sound/music driver (`madmix1_body.asm`, region
  `$C4A0`-`$CF8D`): architecture, the 15-command bytecode language,
  the data tables, the effect-triggering mechanism
  (`EVENTO_SONIDO_PENDIENTE`), and the tools to edit and
  listen to the sounds.
- [`manual_motor_colision_ia.md`](manual_motor_colision_ia.md) — the
  movement/collision engine (`madmix_scr_body.asm`), the 20-tile-type
  dispatch table, and the AI of the 3 moving item types
  (ghosts, ladybug, "repugnantoso"): how they decide direction, what
  each one does on reaching its spot, and the special modes
  (power ball/hippo/tool) triggered by stepping on them.
- [`manual_subsistema_grafico.md`](manual_subsistema_grafico.md) — the
  VDP in `SCREEN 2`, the custom VRAM API (not the BIOS), and why the
  actor engine never uses the MSX's hardware sprites: it composes
  every character by hand with AND/OR masks and sub-pixel shifting,
  the same approach a ZX Spectrum game would use. Also the maze tile
  system, the software scroll (4px, `RLD`/`RRD`), and how screen
  color is managed.
- [`manual_niveles.md`](manual_niveles.md) — the format of the 15
  levels: the 20-byte register, the 16-entry table (register 0 is a
  dead duplicate), the 13 bodies + 3 shared headers, the `$3C`
  wildcard, how end-of-level is detected, the menu's demo mode, and
  the `mmlvl_tool.py` tool to edit them.

*(More manuals will be added here as it's decided what other parts of
the system to document this way.)*
