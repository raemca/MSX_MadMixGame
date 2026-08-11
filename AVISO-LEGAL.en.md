# Legal notice and attribution

*[Leer esto en español](AVISO-LEGAL.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

## Who owns what

**The game is not mine.** *Mad Mix Game* was published by **Topo Soft**
(catalogued in 1987; the game's own credits screen signs it as
"TOPOSHOW -1988-"). The program credits its authorship, exactly as it
appears on that screen, to **"RAPHAEL GOMEZZZ"** (programming),
**"ROBERTO P.ACEBES"** (graphics) and **"COMILONAS"** (music) —
pseudonyms or period spellings exactly as they appear in the binary.
The intellectual property of the original game — code, graphics,
sound and design — remains with Topo Soft, with the people behind
those credits, or with whoever has inherited those rights today.

**What is mine** are the tools in this repository, the comments in the
reconstructed source code, the analysis and the documentation
(`FINDINGS.md`, `FLUJO_PROGRAMA.md`, `README.md` and the accompanying
HTML resources). That is published under the license stated in
`LICENSE`.

## What this repository contains

This project **did not have access to the original source code** of
*Mad Mix Game* — it hasn't survived, or at least it never reached this
work. What's in `src/` is a **reverse-engineered reconstruction**:
a line-by-line disassembly of the original disk and tape binaries,
rewritten as readable assembler source (`SjASMPlus`), with descriptive
labels and comments explaining what each routine does and why. It
comes with the tools (`tools/`) that let you recompile that source and
regenerate, byte for byte, the same `.dsk`/`.cas` files that boot on a
real MSX or in an emulator — the verification that the analysis is
correct is, precisely, that it reproduces the original exactly. This
work recovers the closest possible approximation to the game's lost
source code, and the documentation that was never published alongside
it.

This repository **does not include** the original disk or tape images
(`.dsk`/`.cas`/`.rom`) as dumped from the physical media, nor the
third-party tools used during the analysis (for example, the
disassembler). What is distributed is the reconstructed source, the
already-identified and documented game data (level maps, tiles, sound)
needed for that source to compile into an identical binary, and the
original tools to generate it — not a copy of the original product.

The images in `dump_openmsx/` and `recursos/` are not promotional
screenshots: they are memory/VRAM dumps and reconstructions generated
from the analysis itself, used as evidence that the data format is
correctly understood.

## If you are one of the authors, Topo Soft, or their successor in rights

If you worked on *Mad Mix Game*, you are one of the people credited on
its credits screen ("RAPHAEL GOMEZZZ", "ROBERTO P.ACEBES", "COMILONAS"),
or you represent Topo Soft or whoever has inherited its rights, and you
would prefer this material not be published, **say so and it will be
taken down without argument**. Any legal request, from whoever it may
concern, will be honored. The intent of this work is the opposite of
causing harm: it is to leave a record of how a game that is part of the
history of Spanish software was built, for educational purposes and to
preserve that legacy before it is lost for good.

## About the credits

The names on the credits screen have been transcribed exactly as they
appear in the game's binary, including their original typos (see the
comments in `src/madmix_scr_body.asm`), not from external sources. No
claim is made about the real civil identity behind those pseudonyms:
if anyone can confirm it, a correction with better information is
welcome.
