#!/usr/bin/env python3
"""
mmlvl_tool.py -- descompilador/compilador de las rejillas de losetas
de nivel (data/niveles/*.bin: 13 cuerpos + 3 cabeceras; el nivel 15,
antes "oculto", es un cuerpo mas -- body_l15.bin -- ver FINDINGS.md).
Cada byte es un indice de loseta (bits 0-6, ver
data/tiles/*.til, 00-90) con un bit 7 sin significado confirmado en
tiempo de ejecucion (CARGAR_NIVEL lo borra al cargar, ver
FINDINGS.md), pero presente de verdad en los binarios originales, asi
que el formato de texto lo preserva byte a byte.

Uso:
  py mmlvl_tool.py disasm fichero.bin fichero.txt
  py mmlvl_tool.py asm fichero.txt fichero.bin
  py mmlvl_tool.py roundtrip fichero.bin
  py mmlvl_tool.py roundtrip-all carpeta/
  py mmlvl_tool.py check-bolitas fichero.txt NIVEL
      -- cuenta losetas "suelo con bola" (0x2D/0x2E/0x2F, bit7
      enmascarado) en fichero.txt y lo compara contra el objetivo real
      del nivel NIVEL (0-15; el 0 es el registro muerto, el 15 es el
      nivel oculto/BODY_L15 -- ver FINDINGS.md), leido directamente de
      TABLA_NIVELES en madmix_scr_body.asm (sin fichero de manifiesto
      aparte que se pueda desincronizar).

COLUMNS = 32 siempre (stride fijo de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA/
MAPEAR_COORDENADA_A_DIRECCION, ver FINDINGS.md) -- las filas varian por
nivel (15-23) y se autodetectan del tamano del fichero.

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""

import sys
import os
import re

COLUMNS = 32
# 0x2D/0x2E/0x2F: suelo con bola normal. 0x33-0x36: las 4 flechas
# (arriba/abajo/izquierda/derecha) TAMBIEN cuentan -- confirmado en
# madmix_scr.asm: HANDLER_2F18/2F50/2F88/2FC0 incrementan ($2C08) igual
# que el manejador de bolita normal (ver FINDINGS.md).
BALL_TILES = {0x2D, 0x2E, 0x2F, 0x33, 0x34, 0x35, 0x36}

WARNING_BANNER = """; !!! AVISO -- LEE ESTO ANTES DE EDITAR !!!
; Ingenieria inversa, herramientas y documentacion de este proyecto: Rafael Eduardo Martin Candial (raemca@hotmail.com)
; Rejilla de losetas de {name} -- {rows} filas x {cols} columnas.
; Cada celda es el byte crudo en hex (2 digitos): bits 0-6 = indice de
; loseta (ver data/tiles/*.til, 00-90), bit 7 = flag sin confirmar en
; tiempo de ejecucion (CARGAR_NIVEL lo borra al cargar el nivel, ver
; FINDINGS.md) pero presente de verdad en el binario original.
; NO añadas ni quites filas ni columnas: el tamaño es FIJO. Si cambia,
; todo lo que va detras en madmix_scr.asm/madmix1.asm se desplaza de
; direccion -- el juego compilaria sin error pero cargaria niveles o
; datos incorrectos en tiempo de ejecucion. Ver FINDINGS.md/README.md.
; filas={rows} columnas={cols}
"""


FLAT_BANNER = """; !!! AVISO -- LEE ESTO ANTES DE EDITAR !!!
; Ingenieria inversa, herramientas y documentacion de este proyecto: Rafael Eduardo Martin Candial (raemca@hotmail.com)
; Fragmento de {name} -- {n} bytes SIN alinear a fila de 32 columnas
; (empieza/termina a mitad de una fila real del nivel al que
; pertenece -- es un trozo prestado de memoria compartida, ver
; FINDINGS.md "RESUELTO EL PROPOSITO DE maze_data.bin"). Por eso NO
; se representa como rejilla de filas, solo como lista plana de
; bytes en el mismo orden. Puedes cambiar el VALOR de cualquier byte;
; NO añadas ni quites ninguno: el tamaño es FIJO, cambiar la cuenta
; desplazaria direcciones en madmix1.asm/madmix_scr.asm.
; bytes={n}
"""

FLAT_WRAP = 16  # bytes por linea, solo por legibilidad -- no tiene significado de fila real


def disassemble(data: bytes, name: str) -> str:
    if len(data) % COLUMNS == 0:
        rows = len(data) // COLUMNS
        out = [WARNING_BANNER.format(name=name, rows=rows, cols=COLUMNS)]
        for r in range(rows):
            row = data[r * COLUMNS:(r + 1) * COLUMNS]
            out.append(" ".join(f"{b:02X}" for b in row))
        return "\n".join(out) + "\n"

    # modo "plano": el fragmento no es multiplo de 32 (fragmentos que
    # empiezan/terminan a mitad de fila; ningun fichero actual de
    # data/niveles/ usa este modo, pero se mantiene para fragmentos futuros)
    out = [FLAT_BANNER.format(name=name, n=len(data))]
    for i in range(0, len(data), FLAT_WRAP):
        chunk = data[i:i + FLAT_WRAP]
        out.append(" ".join(f"{b:02X}" for b in chunk))
    return "\n".join(out) + "\n"


def assemble(text: str) -> bytes:
    lines = text.split("\n")
    declared_rows = declared_cols = declared_bytes = None
    grid_lines = []
    for ln in lines:
        stripped = ln.strip()
        if not stripped:
            continue
        m = re.match(r";\s*filas=(\d+)\s+columnas=(\d+)", stripped)
        if m:
            declared_rows = int(m.group(1))
            declared_cols = int(m.group(2))
            continue
        m2 = re.match(r";\s*bytes=(\d+)", stripped)
        if m2:
            declared_bytes = int(m2.group(1))
            continue
        if stripped.startswith(";"):
            continue
        grid_lines.append(stripped)

    if declared_bytes is not None:
        out = bytearray()
        for ln in grid_lines:
            for tok in ln.split():
                out.append(int(tok, 16) & 0xFF)
        if len(out) != declared_bytes:
            raise ValueError(
                f"se declaran {declared_bytes} bytes pero hay {len(out)} tokens -- "
                "NO se puede cambiar la cuenta de bytes (desplazaria direcciones), ver cabecera del fichero"
            )
        return bytes(out)

    if declared_rows is None or declared_cols is None:
        raise ValueError("no se encontro la cabecera '; filas=N columnas=N' ni '; bytes=N'")
    if declared_cols != COLUMNS:
        raise ValueError(
            f"columnas declaradas ({declared_cols}) != {COLUMNS} (fijo para este proyecto)"
        )
    if len(grid_lines) != declared_rows:
        raise ValueError(
            f"se declaran {declared_rows} filas pero hay {len(grid_lines)} lineas de rejilla -- "
            "NO se puede cambiar el numero de filas (desplazaria direcciones), ver cabecera del fichero"
        )

    out = bytearray()
    for i, ln in enumerate(grid_lines):
        tokens = ln.split()
        if len(tokens) != declared_cols:
            raise ValueError(
                f"fila {i}: {len(tokens)} celdas, se esperaban {declared_cols} -- "
                "NO se puede cambiar el numero de columnas (desplazaria direcciones)"
            )
        for tok in tokens:
            out.append(int(tok, 16) & 0xFF)
    return bytes(out)


def cmd_disasm(args):
    bin_path, txt_path = args
    with open(bin_path, "rb") as f:
        data = f.read()
    text = disassemble(data, os.path.basename(bin_path))
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(text)
    if len(data) % COLUMNS == 0:
        print(f"escrito {txt_path} ({len(data)} bytes, {len(data)//COLUMNS} filas)")
    else:
        print(f"escrito {txt_path} ({len(data)} bytes, fragmento sin alinear a fila)")


def cmd_asm(args):
    txt_path, bin_path = args
    with open(txt_path, encoding="utf-8") as f:
        text = f.read()
    data = assemble(text)
    with open(bin_path, "wb") as f:
        f.write(data)
    print(f"escrito {bin_path} ({len(data)} bytes)")


def _roundtrip_one(bin_path):
    with open(bin_path, "rb") as f:
        original = f.read()
    text = disassemble(original, os.path.basename(bin_path))
    rebuilt = assemble(text)
    return original == rebuilt, len(original), len(rebuilt)


def cmd_roundtrip(args):
    (bin_path,) = args
    ok, n1, n2 = _roundtrip_one(bin_path)
    status = "OK" if ok else f"FALLO ({n1} bytes -> {n2} bytes)"
    print(f"{bin_path}: {status}")
    if not ok:
        sys.exit(1)


def cmd_roundtrip_all(args):
    (folder,) = args
    all_ok = True
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".bin"):
            continue
        path = os.path.join(folder, name)
        ok, n1, n2 = _roundtrip_one(path)
        print(f"{'OK  ' if ok else 'FAIL'} {name} ({n1} bytes)")
        all_ok = all_ok and ok
    sys.exit(0 if all_ok else 1)


def read_level_ball_target(madmix_scr_path: str, nivel: int) -> int:
    """Lee el objetivo real de bolitas (offsets 18-19) del registro
    'nivel' directamente de LEVEL_TABLE en madmix_scr_body.asm -- cada
    registro son exactamente 9 lineas de datos (DW/DB), la ultima es
    el DW del objetivo de bolitas. Sin manifiesto aparte que se pueda
    desincronizar de la fuente real."""
    with open(madmix_scr_path, encoding="utf-8") as f:
        src = f.read()
    idx = src.index("LEVEL_TABLE:")
    tail = src[idx + len("LEVEL_TABLE:"):]
    stmt_re = re.compile(r"^\s*(DW|DB)\s+([^;]+)", re.MULTILINE)
    records = []
    current = []
    for m in stmt_re.finditer(tail):
        current.append((m.group(1), m.group(2).strip()))
        if len(current) == 9:
            records.append(current)
            current = []
        if len(records) >= 16:
            break
    if nivel < 0 or nivel >= len(records):
        raise ValueError(f"nivel {nivel} fuera de rango (0-{len(records)-1})")
    kind, val = records[nivel][8]
    if kind != "DW":
        raise ValueError("formato de LEVEL_TABLE inesperado (se esperaba DW en offset 18-19)")
    return int(val.split(",")[0].strip())


def cmd_check_bolitas(args):
    txt_path, nivel_str = args
    nivel = int(nivel_str)
    with open(txt_path, encoding="utf-8") as f:
        text = f.read()
    data = assemble(text)
    count = sum(1 for b in data if (b & 0x7F) in BALL_TILES)
    scr_path = os.path.join(os.path.dirname(__file__), "..", "src", "madmix_scr_body.asm")
    target = read_level_ball_target(scr_path, nivel)
    match = "OK" if count == target else "DESAJUSTE"
    print(f"{txt_path}: {count} bolitas contadas, objetivo real (LEVEL_TABLE nivel {nivel}) = {target} -- {match}")
    if count != target:
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    dispatch = {
        "disasm": cmd_disasm,
        "asm": cmd_asm,
        "roundtrip": cmd_roundtrip,
        "roundtrip-all": cmd_roundtrip_all,
        "check-bolitas": cmd_check_bolitas,
    }
    fn = dispatch.get(cmd)
    if fn is None:
        print(__doc__)
        sys.exit(1)
    fn(args)


if __name__ == "__main__":
    main()
