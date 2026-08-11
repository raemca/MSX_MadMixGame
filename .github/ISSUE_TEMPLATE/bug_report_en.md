---
name: "Bug report (English) - Mad Mix Game / MSX1 reconstruction"
about: Template to report errors in the disassembly, labeling, data, or tools of this project.
title: "[$XXXX] <Problem summary>"
labels: bug, disassembly
assignees: ''
---

## 📌 Problem Summary

<!-- Describe the error found: data disassembled as code, a misidentified
routine, a variable with the wrong size, a byte-for-byte divergence, a
tools/ script that fails, outdated documentation, etc. -->

**Current state in the project:**
<!-- How it is currently named/structured/documented. -->

**Proposed correction:**
<!-- How it should be, based on your analysis of the original binary or live execution. -->

---

## 📍 Location

- **Real memory address (if applicable):** `$XXXX` (e.g. `$8400`, inside `MADMIX1.BIN`)
- **Affected file(s):** `[e.g. src/madmix1_body.asm, tools/mmlvl_tool.py, manuales/manual_niveles.en.md]`
- **Version / binary:** disk (`MADMIX1.BIN`/`MADMIX.SCR`/`MADMIX0.BIN`) or tape (`LOAD.BIN`/`TEST.BIN`/`LOGOTOPO.CM`) — please specify, since they're reconstructed separately.

---

## 🏷️ Type of Issue

<!-- Mark the relevant option with [x] -->
- [ ] **Data disassembled as code (or vice versa):** a data block was disassembled as Z80 instructions, or the other way around.
- [ ] **Data sizing:** a table, tile, sprite or buffer has the wrong size or format (see `manuales/` for the already-documented formats).
- [ ] **Wrong label:** a name doesn't match the routine's/variable's real behavior.
- [ ] **Byte-for-byte divergence:** after rebuilding (`py tools/build_all.py` + `py tools/gen_disk_and_cas.py`), the result doesn't match the original and it's not the already-documented level-13 deviation.
- [ ] **Broken tool:** a `tools/` script fails or produces an incorrect result (roundtrip, verification, etc.).
- [ ] **Outdated or inconsistent documentation:** something in `src/FINDINGS.md`, `src/FLUJO_PROGRAMA.md`, `manuales/`, or the `.en.md` files no longer matches the real code.

---

## 🔬 Comparison (if applicable)

### Current state in the repository

```z80
; Real address: $XXXX
; [paste the current fragment from src/madmix1_body.asm or src/madmix_scr_body.asm here]
```

### Proposal / evidence

```z80
; [paste your proposal here, or describe how you verified it: a real dump, live execution with openMSX, etc.]
```

---

## ✅ How You Verified It (if you did)

- [ ] I rebuilt it (`py tools/build_all.py`) and compared it against the original binary.
- [ ] I verified it live with openMSX (breakpoints/watchpoints, see `src/FINDINGS.md` for examples of this method).
- [ ] This is an unverified observation (please note it anyway, it's still a useful lead).
