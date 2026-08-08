#!/usr/bin/env python3
"""
build_all.py -- compila TODO el motor, la pantalla de carga y los
cargadores de disco y cinta desde el codigo fuente (src/main.asm),
en una sola invocacion de sjasmplus.

Requiere sjasmplus en el PATH (ver README.md, seccion "Requisitos").

Genera (todo dentro de src/build/):
  MADMIX1.BIN                          -- motor, compartido disco/cinta
  disk/MADMIX0.BIN, disk/MADMIX.SCR, disk/MADMIX1.BIN
  cas/TEST.BIN, cas/LOAD.BIN, cas/LOGOTOPO.CM, cas/madmix_cas_scr.bin, cas/MADMIX1.BIN
  main.lst                             -- listado completo (usado por tools/gen_inventory.py)

Este script NO genera el .dsk ni el .cas finales -- eso lo hace
tools/gen_disk_and_cas.py, un paso aparte (empaqueta los binarios de
disco/cinta en los 2 entregables finales). Tampoco regenera el
inventario de recursos/flujo_programa.html -- eso lo hace
tools/gen_inventory.py, aparte, cuando se quiera reflejar cambios de
etiquetas en el visor HTML.

Uso: py tools/build_all.py

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "src")


def main():
    # sjasmplus no crea subcarpetas por si solo -- SAVEBIN falla con
    # "opening file for write" si build/disk/ o build/cas/ no existen.
    os.makedirs(os.path.join(SRC, "build", "disk"), exist_ok=True)
    os.makedirs(os.path.join(SRC, "build", "cas"), exist_ok=True)

    # sjasmplus resuelve las rutas de SAVEBIN/INCBIN relativas al
    # directorio de trabajo, no a la ubicacion de main.asm -- por eso
    # se invoca con cwd=src/ (main.asm usa rutas como "build/...").
    try:
        result = subprocess.run(["sjasmplus", "main.asm", "--lst=build/main.lst"], cwd=SRC)
    except FileNotFoundError:
        print("ERROR: no se encuentra 'sjasmplus' en el PATH (ver README.md, seccion Requisitos)")
        sys.exit(1)

    if result.returncode != 0:
        print(f"ERROR: sjasmplus devolvio codigo {result.returncode}")
        sys.exit(result.returncode)

    print("Compilacion completa -- ver src/build/ (MADMIX1.BIN, disk/, cas/)")
    print("Siguiente paso: py tools/gen_disk_and_cas.py")
    print("(opcional, si cambiaron etiquetas: py tools/gen_inventory.py)")


if __name__ == "__main__":
    main()
