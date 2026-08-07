#!/usr/bin/env python3
"""
gen_dsk_file.py -- genera src/build/madmix_reconstruido.dsk DESDE CERO:
construye la estructura FAT12 completa (sector de arranque, 2 tablas
FAT, directorio raiz, area de datos) en vez de partir de una copia del
.dsk original y parchearla.

Formato: MSX-DOS 720KB estandar -- verificado leyendo byte a byte la
estructura real del .dsk original (ver FINDINGS.md): 512 bytes/sector,
2 sectores/cluster (1024 bytes/cluster), 1 sector reservado, 2 copias
de FAT de 3 sectores cada una, 112 entradas de directorio raiz, 1440
sectores totales, descriptor de medio $F9. Asignacion de clusters
SECUENCIAL, sin fragmentacion (confirmado decodificando las cadenas
FAT reales) -- se reproduce con el mismo algoritmo simple.

Los 6 ficheros del disco, en el mismo orden/cluster que el original:
  MADMIX        -- copia verbatim SIN ANALIZAR (load_disk/MADMIX_dup.bin,
                   ver load_disk/MADMIX_dup.txt)
  MADMIX.BAS    -- tokenizado desde load_disk/MADMIX.bas (msxbasic_tool)
  MADMIX0.BIN   -- build/disk/MADMIX0.BIN (ya incluye su cabecera BLOAD)
  MADMIX1.BIN   -- build/disk/MADMIX1.BIN + cabecera BLOAD calculada
                   aqui mismo (build/disk/MADMIX1.BIN es solo el cuerpo,
                   sin cabecera, misma convencion que build/cas/MADMIX1.BIN)
  MADMIX.SCR    -- build/disk/MADMIX.SCR (ya incluye su cabecera BLOAD)
  AUTOEXEC.BAS  -- tokenizado desde load_disk/AUTOEXEC.bas (msxbasic_tool)

El sector de arranque (load_disk/boot_sector.bin, ver
load_disk/boot_sector.txt) y las fechas/horas de cada entrada de
directorio (metadatos de fichero sin relacion con el contenido, no
derivables de nada) se preservan como constantes literales copiadas
del original -- unica dependencia real del .dsk original en todo este
script, y solo como referencia documentada, no como base a parchear.

El relleno de cola de cada cluster (la parte de cada fichero que no
llena su ultimo cluster completo) se rellena con CEROS, no con el
contenido real del disco original -- el disco original es un soporte
REUTILIZADO y ese relleno contiene restos de un uso previo sin
relacion con el juego (ver FINDINGS.md); no vale la pena preservar
"basura" ajena solo por fidelidad byte a byte. MSX-DOS nunca lee esa
zona (solo usa el tamaño declarado en el directorio), asi que esto no
tiene ningun efecto funcional -- unicamente hace que la comparacion
byte a byte contra el .dsk original ya no de "solo 9 diferencias" en
esas zonas de relleno (ver FINDINGS.md para el recuento exacto).

Uso: py tools/gen_dsk_file.py

Autor de esta herramienta: Rafael Eduardo Martín Candial
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "src")
BUILD = os.path.join(SRC, "build")
DISK_DIR = os.path.join(BUILD, "disk")
LOAD_DISK = os.path.join(SRC, "load_disk")

OUT = os.path.join(BUILD, "madmix_reconstruido.dsk")

BYTES_PER_SECTOR = 512
SECTORS_PER_CLUSTER = 2
RESERVED_SECTORS = 1
NUM_FATS = 2
ROOT_ENTRIES = 112
TOTAL_SECTORS = 1440
SECTORS_PER_FAT = 3

CLUSTER_SIZE = BYTES_PER_SECTOR * SECTORS_PER_CLUSTER  # 1024
FAT_START = RESERVED_SECTORS * BYTES_PER_SECTOR
FAT_SIZE = SECTORS_PER_FAT * BYTES_PER_SECTOR
ROOT_DIR_START = FAT_START + NUM_FATS * FAT_SIZE
ROOT_DIR_SIZE = ROOT_ENTRIES * 32
DATA_START = ROOT_DIR_START + ROOT_DIR_SIZE


def dos_name(name):
    base, _, ext = name.partition(".")
    return base.upper().ljust(8)[:8].encode("ascii") + ext.upper().ljust(3)[:3].encode("ascii")


def dir_entry(name, size, cluster, time_, date_, attr=0x00):
    entry = bytearray(32)
    entry[0:11] = dos_name(name)
    entry[11] = attr
    entry[22:24] = struct.pack("<H", time_)
    entry[24:26] = struct.pack("<H", date_)
    entry[26:28] = struct.pack("<H", cluster)
    entry[28:32] = struct.pack("<I", size)
    return bytes(entry)


def build_fat(cluster_counts):
    """cluster_counts: lista de (cluster_inicial, num_clusters), en
    orden. Devuelve los bytes de UNA tabla FAT12 (se duplica luego)."""
    total_clusters = 2 + sum(n for _, n in cluster_counts)
    entries = [0] * total_clusters
    entries[0] = 0xFF9  # $F9 (descriptor de medio) + relleno reservado
    entries[1] = 0xFFF  # reservado

    for start, count in cluster_counts:
        for i in range(count):
            c = start + i
            entries[c] = (start + i + 1) if i < count - 1 else 0xFFF

    fat_bytes = bytearray(FAT_SIZE)
    for i in range(0, len(entries), 2):
        e0 = entries[i]
        e1 = entries[i + 1] if i + 1 < len(entries) else 0
        off = (i * 3) // 2
        fat_bytes[off] = e0 & 0xFF
        fat_bytes[off + 1] = ((e0 >> 8) & 0x0F) | ((e1 & 0x0F) << 4)
        fat_bytes[off + 2] = (e1 >> 4) & 0xFF
    return bytes(fat_bytes)


def tokenize(bas_path):
    sys.path.insert(0, HERE)
    import msxbasic_tool
    with open(bas_path, "r", encoding="utf-8") as f:
        text = f.read()
    return msxbasic_tool.tok(text)


def main():
    for path in [
        os.path.join(LOAD_DISK, "boot_sector.bin"),
        os.path.join(LOAD_DISK, "MADMIX_dup.bin"),
        os.path.join(DISK_DIR, "MADMIX0.BIN"),
        os.path.join(DISK_DIR, "MADMIX.SCR"),
        os.path.join(DISK_DIR, "MADMIX1.BIN"),
    ]:
        if not os.path.exists(path):
            print(f"ERROR: falta {path} -- ejecuta antes 'py tools/build_all.py'")
            sys.exit(1)

    with open(os.path.join(LOAD_DISK, "boot_sector.bin"), "rb") as f:
        boot_sector = f.read()
    with open(os.path.join(LOAD_DISK, "MADMIX_dup.bin"), "rb") as f:
        madmix_dup = f.read()
    with open(os.path.join(DISK_DIR, "MADMIX0.BIN"), "rb") as f:
        madmix0 = f.read()
    with open(os.path.join(DISK_DIR, "MADMIX.SCR"), "rb") as f:
        madmix_scr = f.read()
    with open(os.path.join(DISK_DIR, "MADMIX1.BIN"), "rb") as f:
        madmix1_body = f.read()

    madmix1_start = 0x8400
    madmix1_header = bytes([0xFE]) + struct.pack(
        "<HHH", madmix1_start, madmix1_start + len(madmix1_body) - 1, madmix1_start
    )
    madmix1 = madmix1_header + madmix1_body

    madmix_bas = tokenize(os.path.join(LOAD_DISK, "MADMIX.bas"))
    autoexec_bas = tokenize(os.path.join(LOAD_DISK, "AUTOEXEC.bas"))

    # nombre, contenido, hora, fecha -- hora/fecha reales del disco
    # original (metadatos sin relacion con el contenido, ver docstring)
    files = [
        ("MADMIX", madmix_dup, 0xBCF1, 0x290C),
        ("MADMIX.BAS", madmix_bas, 0xBCF1, 0x290C),
        ("MADMIX0.BIN", madmix0, 0xBCF1, 0x290C),
        ("MADMIX1.BIN", madmix1, 0xBCF1, 0x290C),
        ("MADMIX.SCR", madmix_scr, 0xBCF1, 0x290C),
        ("AUTOEXEC.BAS", autoexec_bas, 0xBD73, 0x290C),
    ]

    cluster_counts = []
    cluster = 2
    for _name, content, _t, _d in files:
        n = (len(content) + CLUSTER_SIZE - 1) // CLUSTER_SIZE
        cluster_counts.append((cluster, n))
        cluster += n

    fat = build_fat(cluster_counts)

    root_dir = bytearray(ROOT_DIR_SIZE)
    for idx, ((name, content, t, d), (cl, _n)) in enumerate(zip(files, cluster_counts)):
        root_dir[idx * 32:idx * 32 + 32] = dir_entry(name, len(content), cl, t, d)

    data_area = bytearray()
    for (_name, content, _t, _d), (_cl, n) in zip(files, cluster_counts):
        pad_len = n * CLUSTER_SIZE - len(content)
        data_area += content + bytes(pad_len)

    disk = bytearray(TOTAL_SECTORS * BYTES_PER_SECTOR)
    disk[0:len(boot_sector)] = boot_sector
    disk[FAT_START:FAT_START + FAT_SIZE] = fat
    disk[FAT_START + FAT_SIZE:FAT_START + 2 * FAT_SIZE] = fat
    disk[ROOT_DIR_START:ROOT_DIR_START + ROOT_DIR_SIZE] = root_dir
    disk[DATA_START:DATA_START + len(data_area)] = data_area

    with open(OUT, "wb") as f:
        f.write(disk)

    print(f"escrito {OUT} ({len(disk)} bytes)")


if __name__ == "__main__":
    main()
