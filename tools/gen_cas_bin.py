#!/usr/bin/env python3
"""
gen_cas_bin.py -- genera build/cas/madmix_cas.bin, la concatenacion
SIN formato de bloques de cinta (sin sync/nombre/checksum) de
madmix_scr+MADMIX1 -- un INGREDIENTE mas para el .cas real, no el
.cas en si (eso lo hace gen_cas_file.py, que empaqueta esto y el
resto de piezas en un .cas real, en la RAIZ de build/).

Concatena SIN relleno (verificado que asi lo hace el .cas real, tanto
el original de 1988 como la reedicion v2.0 de 2013: cada bloque de
cinta lleva su propia direccion de destino en la cabecera, asi que no
hace falta ningun hueco de memoria entre ellos en el propio fichero):

  build/cas/madmix_cas_scr.bin  (21760 bytes) -> destino real $1000
  build/cas/MADMIX1.BIN         (22945 bytes) -> destino real $8400
                                 (copia local -- identica a
                                 build/disk/MADMIX1.BIN, ver
                                 FINDINGS.md)

en ese orden (coincide con el orden real de carga: la cinta original
carga primero el bloque de $1000 y lo ejecuta -- dibuja la portada --
antes de cargar el bloque de $8400 y saltar ahi).

Escribe tambien un manifiesto de texto corto documentando los 2
destinos/longitudes, para un futuro empaquetador de bloques de cinta
(marcas de sincronismo, checksum) -- fuera de alcance de este script.

Uso: py tools/gen_cas_bin.py

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""
import os

HERE = os.path.dirname(__file__)
BUILD = os.path.join(HERE, "..", "src", "build")
CAS_DIR = os.path.join(BUILD, "cas")

SCR_PART = os.path.join(CAS_DIR, "madmix_cas_scr.bin")
ENGINE_PART = os.path.join(CAS_DIR, "MADMIX1.BIN")
OUT = os.path.join(CAS_DIR, "madmix_cas.bin")
MANIFEST = os.path.join(CAS_DIR, "madmix_cas.bin.txt")

SCR_DEST = 0x1000
ENGINE_DEST = 0x8400


def main():
    with open(SCR_PART, "rb") as f:
        scr = f.read()
    with open(ENGINE_PART, "rb") as f:
        engine = f.read()

    combined = scr + engine
    with open(OUT, "wb") as f:
        f.write(combined)

    manifest = (
        "; madmix_cas.bin -- fichero unificado para la version de cinta (.cas)\n"
        "; Generado por tools/gen_cas_bin.py a partir de main.asm. Concatenado\n"
        "; SIN relleno (verificado contra el .cas real, ver FINDINGS.md).\n"
        "; Ingenieria inversa, herramientas y documentacion de este proyecto:\n"
        "; Rafael Eduardo Martin Candial (raemca@hotmail.com)\n"
        ";\n"
        f"; tramo 1: offset 0x{0:04X}-0x{len(scr):04X} ({len(scr)} bytes) -> cargar en ${SCR_DEST:04X}\n"
        f"; tramo 2: offset 0x{len(scr):04X}-0x{len(combined):04X} ({len(engine)} bytes) -> cargar en ${ENGINE_DEST:04X}\n"
        ";\n"
        "; Pendiente (fuera de alcance de este script): empaquetar estos 2\n"
        "; tramos en bloques de cinta reales (marcas de sincronismo, cabecera\n"
        "; de destino de 6 bytes, checksum) y el propio cargador (LOAD.BIN/\n"
        "; TEST.BIN equivalentes, ver FINDINGS.md 'estructura completa de la\n"
        "; version de cinta') -- este script solo genera el contenido, no el\n"
        "; formato de cinta completo.\n"
    )
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(manifest)

    print(f"escrito {OUT} ({len(combined)} bytes = {len(scr)} + {len(engine)})")
    print(f"escrito {MANIFEST}")


if __name__ == "__main__":
    main()
