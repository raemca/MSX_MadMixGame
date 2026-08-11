# MadMixGame — Reverse Engineering Project

*[Leer esto en español](README.md)*

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*
 
Summary
-------
MadMixGame is a reverse engineering project whose goal is to study, document and reconstruct the behavior and resources of a classic game for the MSX platform. The project brings together technical analysis, data extraction (graphics, audio, levels), code reconstruction and experiments to allow the game to be run, modified and studied on modern environments.

Goals
---------
- Analyze the original binary/distribution to understand its architecture and resources.
- Recover and document graphics, sound and levels.
- Reimplement parts of the game or build tools that allow editing and experimenting with its data.
- Provide clear documentation so other researchers and enthusiasts can continue the work.

Scope
-------
This repository focuses on the technical work: disassembly, resource extraction, conversion tools and technical documentation. It does not include or redistribute commercial binaries of the original game, nor copyrighted material without proper authorization. Contributions must follow legal and ethical practices.

Repository structure
--------------------------
- src/: Documentation and source code related to the analysis and tools (see [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md)).
- assets/ (if present): extracted resources (graphics, audio, maps), usually in converted format.
- tools/: utilities and scripts used for extraction, conversion and analysis.
- docs/: reverse-engineering notes, diagrams and references.

Getting started
------------
1. Read the main documentation in [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md) for specific details about the analysis performed.
2. Check the tools/ folder for available scripts and utilities.
3. Run (where applicable) extraction scripts in a controlled environment. Use virtual machines or isolated environments when handling binaries.

Dependencies and environment
----------------------
The tools used may include assemblers/disassemblers, image/sound conversion utilities and development environments (Python, Node.js, Make, etc.). Check the files inside src/ and tools/ for specific instructions on installing dependencies and recommended versions.

Contributing
---------
- Before submitting changes, open an issue to describe the proposed work or improvement.
- Create branches with clear descriptions and submit pull requests with tests and documentation of the changes.
- Keep a changelog and document any new dependencies or build steps.

Legal and ethical aspects
-------------------------
Reverse engineering may be subject to legal restrictions depending on jurisdiction and the origin of the analyzed material. This project promotes:
- Not redistributing proprietary software or copyrighted assets without permission.
- Sharing only results, tools and documentation that do not infringe third-party rights.
- Clearly documenting the origin of the data and any use of protected material.

Resources and references
----------------------
- Internal documentation: [src/README.md](C:/Users/User/Documents/Programacion/MSX/proyectos/madmixgame/src/README.md)
- Typical tools: Z80 disassemblers, hex editors, tile conversion utilities, retro audio trackers.

Contact
--------
For questions or collaboration proposals, open an issue in this repository or reach out to the maintainers listed in the internal documentation.

Final notes
-------------
This README is an introductory summary. See the documents in src/ for detailed technical information and reproducible steps.
