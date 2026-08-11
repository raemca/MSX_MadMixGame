# Contributing Guide

*[Leer esto en español](CONTRIBUTING.md)*

Thanks for your interest in contributing to this **reverse-engineering,
disassembly and Z80 assembly reconstruction** project for *Mad Mix Game*
(Topo Soft, 1987/88, MSX1)!

The goal of this repository is to translate the game's original binaries
(disk and tape) into real Z80 source code, identifying and documenting
functions, variables and data blocks, always keeping a **1:1 reconstruction
(byte-matching)** against the original executables. Before anything else,
take a look at `METODOLOGIA.en.md` (the project's full process) and
`src/FINDINGS.md` (the findings diary, Spanish-only so far) to understand
how the work has been done up to now.

---

## 📌 Core Project Principles

1. **1:1 fidelity (byte-matching):** any change to the assembly instructions
   or data tables must keep generating a binary that is identical, byte for
   byte, to the original — except for the project's single deliberate
   deviation (the level-13 ball-counter fix, documented in `src/FINDINGS.md`
   and `manuales/manual_niveles.en.md`).
2. **Clarity over interpretation:** no new code is added, and original
   routines are never "optimized". The goal is to translate and interpret
   exactly what the binary does, original bugs included.
3. **Step by step:** it's better to label/document one small, verified block
   than to submit a large change without checking it against the real
   binary.
4. **Descriptive names in Spanish:** the convention already established
   throughout the project (hundreds of renaming rounds documented in
   `src/FINDINGS.md`) is to use descriptive names **in Spanish**, not
   English or cryptic abbreviations — for example `MOTOR_ACTORES`,
   `CONSULTAR_TIPO_LOSETA`, `REGISTRO_NIVEL_POSICION_COMECOCOS`, not
   `ACTOR_ENGINE` or `lbl_8200`. Purely internal labels within a routine
   (jump marks, not functions with their own identity) use a leading dot
   (`.BUCLE_LOSETAS`, a local label).

---

## 🛠️ Working Environment and Tools

- **Assembler:** [SjASMPlus](https://github.com/z00m128/sjasmplus) on your
  PATH — the only assembler this project uses (not `pasmo`, not `z80asm`).
- **Python 3** (`py` on Windows) — for the `tools/` utilities (full build,
  `.dsk`/`.cas` generation, sound, levels, tokenized BASIC). No external
  dependencies, standard library only.
- **openMSX** (optional but recommended) to test the result — and, for live
  debugging, it supports an external control protocol via script (see
  `doc/manual/openmsx-control.html` in your openMSX install;
  `src/FINDINGS.md` has a real usage example for verifying hypotheses live,
  not just by reading the code).
- **A legally obtained copy of the original game** (disk and/or tape) if you
  want to verify the byte-for-byte comparison yourself — this repository
  **does not include** the original images (`.dsk`/`.cas`/`.rom`), see
  `AVISO-LEGAL.en.md`. Without one you can still contribute (renaming,
  comments, documentation), but you won't be able to check the byte-match
  yourself.

---

## 🚀 Contribution Workflow

### 1. Set Up the Repository

1. **Fork** this repository on GitHub.
2. Clone it locally:

   ```bash
   git clone https://github.com/YOUR_USERNAME/MSX_MadMixGame.git
   cd MSX_MadMixGame
   ```

3. Create a descriptive branch:

   ```bash
   git checkout -b label-collision-engine
   # or: git checkout -b fix-scroll-comment
   ```

### 2. Build and Verify

```bash
# Builds the ENTIRE project in one go (engine, screen, disk and tape loaders)
py tools/build_all.py

# Generates the 2 final deliverables (.dsk and .cas) from scratch
py tools/gen_disk_and_cas.py
```

This leaves the binaries in `src/build/` —
`src/build/madmix_reconstruido.dsk` and `src/build/madmix_reconstruido.cas`
are the final deliverables. If you have a copy of the original, compare:

```bash
# Windows / PowerShell
fc /b src\build\madmix_reconstruido.dsk path\to\original.dsk

# or with Python, byte for byte, to count exact differences
py -c "a=open('src/build/madmix_reconstruido.dsk','rb').read(); b=open('path/to/original.dsk','rb').read(); print(sum(1 for x,y in zip(a,b) if x!=y), 'differences')"
```

If your change is only renaming/comments, the result must be **exactly the
same** as before your change (0 new differences). If you introduce a real,
justified divergence, document it the same way the level-13 bug was
documented.

### 3. Document the Finding

If you identify or fix something (a label, a data block, a behavior), add an
entry to `src/FINDINGS.md` following the style already used — a `##`/`###`
heading describing what was believed before, what was discovered, and how it
was verified. It's the project's chronological diary; history isn't
rewritten, it's added on top of.

---

## 📬 Submitting Pull Requests

1. Commit your changes with descriptive messages:

   ```bash
   git commit -m "Rename MOTOR_MOVIMIENTO_ITEM and document the finding in FINDINGS.md"
   ```

2. Push your branch:

   ```bash
   git push origin label-collision-engine
   ```

3. Open a **Pull Request** against this repository's `main` branch.
4. Fill in the PR template (memory ranges changed, byte-for-byte
   verification, affected files).

---

## 🐛 Reporting Bugs and Inconsistencies

If you find a misinterpreted section, data disassembled as code, or a label
that no longer describes what its routine does, but you're not going to fix
it yourself:

1. Check there isn't already an open Issue about it.
2. Open a new Issue using the disassembly/labeling bug report template
   (available in English and Spanish).
3. Include the real memory address and the technical justification — if you
   can verify it live with openMSX or by comparing against the original
   binary, even better.

---

Thanks for helping preserve and reverse-engineer this piece of Spanish
software history!
