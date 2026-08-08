#!/usr/bin/env python3
"""
gen_cas_file.py -- genera build/madmix_reconstruido.cas, un .cas real
y reproducible byte a byte (formato "estandar" .cas de emuladores MSX)
a partir de TODOS los ingredientes ya reconstruidos: load_cas/TOPO.bas,
load_cas/MADMIX.bas, y los binarios ya compilados por main.asm en
build/cas/ (LOGOTOPO.CM, TEST.BIN, LOAD.BIN, madmix_cas_scr.bin,
MADMIX1.BIN). LOGOTOPO.CM ya sale de nuestra propia fuente
(load_cas/logotopo_cm_body.asm, verificada 0 diferencias contra el
.bin original) -- ya NO se copia verbatim del .bin de referencia.

Formato .cas (verificado byte a byte contra el .cas real de 1988,
FISICO/Mad Mix Game (1988).../...cas, ver FINDINGS.md):

  SYNC = 1F A6 DE BA CC 13 7D 74  (marca de sincronismo, 8 bytes)

  Ficheros CON NOMBRE (BASIC "TOPO"/"MADMIX", binarios "LOGOTOPO"/
  "LOAD"/"TEST"): bloque de NOMBRE (SYNC + 10 bytes de tipo-ID + 6
  caracteres ASCII de nombre, con espacios de relleno) seguido
  INMEDIATAMENTE de un bloque de DATOS (SYNC + ...):
    - BASIC ASCII (tipo-ID 0xEA x10): datos = texto tal cual + relleno
      $1A hasta completar 256 bytes (sin cabecera de direccion).
    - Binario (tipo-ID 0xD0 x10): datos = cabecera de 6 bytes
      (start/end/exec, cada uno DW little-endian) + el payload real.

  Los 2 bloques finales (contenido de MADMIX.SCR reubicado y de
  MADMIX1.BIN) NO llevan bloque de nombre ni cabecera de 6 bytes --
  son datos crudos leidos directamente por LOAD.BIN via CALL $DDCC
  con IX/DE como parametros, sin busqueda por nombre. SI llevan un
  marcador de 1 byte ($FF) justo tras el SYNC, antes del payload real
  -- detectado por diff: sin contarlo, el payload aparecia desplazado
  1 byte respecto al original.

  Cada bloque de datos real va seguido de unos pocos bytes de "cola"
  antes del siguiente SYNC (o del final del fichero) -- casi siempre
  relleno solido a $00, salvo el bloque SCR (termina en "EB 00 00 00
  00 00 00", sin explicar) y el bloque ENGINE (sin cola, termina justo
  en el byte final del fichero). Estas colas no se han podido derivar
  del contenido (ni checksum simple ni relleno constante identificado)
  -- se preservan tal cual, copiadas directamente del .cas de 1988,
  para lograr fidelidad byte a byte real.

Uso: py tools/gen_cas_file.py

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""
import os

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "src")
BUILD = os.path.join(SRC, "build")
CAS_DIR = os.path.join(BUILD, "cas")
LOAD_CAS = os.path.join(SRC, "load_cas")

OUT = os.path.join(BUILD, "madmix_reconstruido.cas")

SYNC = bytes([0x1F, 0xA6, 0xDE, 0xBA, 0xCC, 0x13, 0x7D, 0x74])
TYPE_ASCII = bytes([0xEA]) * 10
TYPE_BIN = bytes([0xD0]) * 10

# Bytes de "cola" tras cada bloque de datos, copiados tal cual del
# .cas de 1988 -- no derivables del contenido (ver docstring).
GAP_LOGOTOPO = bytes([0x00, 0x00, 0x00, 0x00])
GAP_LOAD = bytes([0x00] * 7)
GAP_TEST = bytes([0x00] * 5)
GAP_SCR = bytes([0xEB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
GAP_ENGINE = bytes([])

# Marcador de 1 byte que llevan los bloques de datos CRUDOS (sin
# nombre ni cabecera de 6 bytes), justo tras el SYNC, antes del
# payload real -- mismo valor ($FF) en ambos bloques crudos de este
# .cas, significado exacto no identificado (¿marca de "bloque sin
# cabecera"? ver FINDINGS.md).
RAW_MARKER = bytes([0xFF])


def dw(value):
    return bytes([value & 0xFF, (value >> 8) & 0xFF])


def name_block(type_id, name6):
    assert len(name6) == 6
    return SYNC + type_id + name6.encode("ascii")


def ascii_data_block(text_bytes, total_len=256):
    assert len(text_bytes) <= total_len
    padded = text_bytes + bytes([0x1A]) * (total_len - len(text_bytes))
    return SYNC + padded


def bin_data_block(start, end, exec_addr, payload, gap):
    header = dw(start) + dw(end) + dw(exec_addr)
    return SYNC + header + payload + gap


def raw_data_block(payload, gap):
    return SYNC + RAW_MARKER + payload + gap


def main():
    with open(os.path.join(LOAD_CAS, "TOPO.bas"), "rb") as f:
        topo_bas = f.read()
    with open(os.path.join(LOAD_CAS, "MADMIX.bas"), "rb") as f:
        madmix_bas = f.read()
    with open(os.path.join(CAS_DIR, "LOGOTOPO.CM"), "rb") as f:
        # build/cas/LOGOTOPO.CM (generado por main.asm desde
        # logotopo_cm_body.asm): los 4254 bytes reales del cuerpo
        # ($9470-$A50D, "end" inclusivo -- misma convencion que
        # LOAD.BIN/TEST.BIN, sin ningun byte suelto que restaurar).
        logotopo = f.read()
    with open(os.path.join(CAS_DIR, "LOAD.BIN"), "rb") as f:
        load_bin = f.read()
    with open(os.path.join(CAS_DIR, "TEST.BIN"), "rb") as f:
        test_bin = f.read()
    with open(os.path.join(CAS_DIR, "madmix_cas_scr.bin"), "rb") as f:
        scr = f.read()
    with open(os.path.join(CAS_DIR, "MADMIX1.BIN"), "rb") as f:
        engine = f.read()

    out = bytearray()
    out += name_block(TYPE_ASCII, "TOPO  ")
    out += ascii_data_block(topo_bas)
    out += name_block(TYPE_BIN, "LOGOTO")
    out += bin_data_block(0x9470, 0xA50D, 0x9470, logotopo, GAP_LOGOTOPO)
    out += name_block(TYPE_ASCII, "MADMIX")
    out += ascii_data_block(madmix_bas)
    out += name_block(TYPE_BIN, "LOAD  ")
    out += bin_data_block(0xDDA0, 0xDECA, 0xDDA0, load_bin, GAP_LOAD)
    out += name_block(TYPE_BIN, "TEST  ")
    out += bin_data_block(0xC350, 0xC44C, 0xC350, test_bin, GAP_TEST)
    out += raw_data_block(scr, GAP_SCR)
    out += raw_data_block(engine, GAP_ENGINE)

    with open(OUT, "wb") as f:
        f.write(out)

    print(f"escrito {OUT} ({len(out)} bytes)")


if __name__ == "__main__":
    main()
