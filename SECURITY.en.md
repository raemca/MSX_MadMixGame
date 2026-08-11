# Security Policy

## Scope of this project

`MSX_MadMixGame` is a reverse-engineering, documentation and
preservation project — not a production service. There is no server,
no user accounts, no database, and no personal data is processed. The
repository's content falls into three categories:

- **Z80 assembly source code** (`src/*.asm`), meant to be compiled
  with `sjasmplus` and run on an MSX emulator (or a real MSX) — never
  on the machine that compiles it.
- **Python tools** (`tools/*.py`) that read/generate local binary
  files (`.bin`, `.dsk`, `.cas`, `.wav`) from other local files
  within the repository itself.
- **Self-contained HTML pages** (`recursos/*.html`) that open
  directly in the browser, with no backend and no network calls — all
  the data they display is embedded in the file itself.

Given this scope, most classic web vulnerability categories don't
apply (SQL injection, XSS with remote data, session management, etc.).
What does make sense to report:

- A `tools/` script that, when processing a deliberately crafted
  input file (a corrupted or malicious `.dsk`/`.cas`/`.bin`), writes
  outside the expected directory, overwrites arbitrary files, or has
  any other unsafe behavior beyond failing with a controlled error.
- Any HTML file in `recursos/` that, contrary to its current design
  (self-contained, no network), ends up loading or executing content
  from an untrusted external source.
- Any credential, token, or sensitive data that ends up in the
  repository's history by mistake.

## What is NOT a vulnerability in this project

Because of the project's own goal (a byte-for-byte reconstruction of
the original 1987/88 binary, see `METODOLOGIA.md`), the assembly code
**deliberately** reproduces the original game's behavior, including
its historical bugs — with the sole documented, explicit exception of
the level-13 ball counter (see `FINDINGS.md`). "Odd" behavior in the
reconstructed game that matches the original **is not a security
issue**, it's historical fidelity. If you're unsure whether something
falls into this category, report it anyway and it will be clarified.

## Supported version

There are no published releases with differentiated support: only the
`main` branch is maintained, always at its latest state.

| Branch | Supported |
| --- | --- |
| `main` | :white_check_mark: |
| any fork/older branch | :x: |

## How to report an issue

- **For most cases** (the most likely scenario: a bug in a `tools/`
  script): open a normal
  [Issue](https://github.com/raemca/MSX_MadMixGame/issues), just like
  any other bug — no need to treat it as anything special, there are
  no users at risk here.
- **If you'd really rather report it privately** (for example, if you
  found a leaked credential in the history), write to
  <raemca@hotmail.com> with the details.

This is a personal project maintained by a single person in their
spare time: there's no SLA and no bug bounty program, but every
report is reviewed and appreciated — especially from someone who took
the time to look at the code carefully.
