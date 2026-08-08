#!/usr/bin/env python3
"""
gen_disk_and_cas.py -- genera los 2 entregables finales,
src/build/madmix_reconstruido.dsk y src/build/madmix_reconstruido.cas,
a partir de los binarios YA compilados en src/build/disk/ y
src/build/cas/ (ver tools/build_all.py, que debe ejecutarse antes).

.dsk: delega en tools/gen_dsk_file.py, que construye la estructura
FAT12 completa DESDE CERO (boot sector, FAT, directorio, area de
datos) -- no parte de una copia del .dsk original ni la parchea, ver
ese fichero para el detalle completo del formato.

.cas: delega en tools/gen_cas_bin.py (ingrediente intermedio) y
tools/gen_cas_file.py (empaquetado real en bloques de cinta) -- ver
esos ficheros para el detalle del formato.

Uso: py tools/gen_disk_and_cas.py

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    sys.path.insert(0, HERE)
    import gen_dsk_file
    import gen_cas_bin
    import gen_cas_file
    gen_dsk_file.main()
    gen_cas_bin.main()
    gen_cas_file.main()


if __name__ == "__main__":
    main()
