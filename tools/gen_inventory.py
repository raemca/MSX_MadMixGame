#!/usr/bin/env python3
"""
gen_inventory.py -- genera el inventario de etiquetas para
recursos/flujo_programa.html (el array INVENTORY embebido en su
<script>), a partir del listado completo de sjasmplus
(src/build/main.lst).

Por que el listado y no el .sym: --sym solo da nombre+direccion: con
main.asm compilando TODO en una sola pasada (motor, pantalla,
cargador de disco, cargador de cinta), varias direcciones se
REUTILIZAN por ficheros fuente distintos (p.ej. $C350 es a la vez el
driver de sonido de madmix1_body.asm Y TEST.BIN de
load_cas/test_bin_body.asm -- se solapan a proposito, ver
FINDINGS.md). Solo el listado (con sus marcadores "# file opened/
closed") permite saber de que fichero FUENTE viene cada etiqueta sin
ambiguedad, cruzando por POSICION EN EL FUENTE, no por direccion
final.

Clasificacion de cada etiqueta (heuristica, no infalible -- igual
criterio que la version anterior de este inventario):
  funcion  -- destino de al menos un CALL en cualquier fichero
  dato     -- ninguna llamada CALL Y le sigue un DB/DW/DS/INCBIN
  interna  -- destino de JP/JR/DJNZ, O mencionada como operando en
             cualquier otra linea de codigo (DW ETIQUETA en tabla de
             saltos, LD IY/IX/HL,ETIQUETA + JP (IY/IX/HL), etc.)
  sinref   -- el nombre no aparece en ningun otro sitio del codigo

NOTA: sigue siendo heuristica de texto, no de flujo real -- un
identificador que coincida por casualidad con el nombre de una
etiqueta dentro de codigo no relacionado la marcaria "interna" sin
serlo de verdad (no se ha visto ningun caso real todavia). Las
etiquetas LOCALES (con punto, `.nombre`) no se registran en el
inventario en absoluto -- `LABEL_RE` no reconoce el punto inicial,
asi que quedan fuera por completo (ambito interno a su etiqueta padre).

Uso:
  sjasmplus src/main.asm --lst=src/build/main.lst   (generar el listado primero)
  py tools/gen_inventory.py                          (lee el .lst, escribe el HTML)

Autor de esta herramienta: Rafael Eduardo Martín Candial (raemca@hotmail.com)
"""
import os
import re
import json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "src")
LST_PATH = os.path.join(SRC, "build", "main.lst")
HTML_PATH = os.path.join(ROOT, "recursos", "flujo_programa.html")

LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
LST_LINE_RE = re.compile(r"^\s*(\d+)\+?\s+([0-9A-F]{4})?(?:(?:\s[0-9A-F]{2}){0,4})\s*(.*)$")
CALL_RE = re.compile(r"\bCALL\b(?:\s+[A-Z]+,)?\s+([A-Za-z_][A-Za-z0-9_]*)\b")
JUMP_RE = re.compile(r"\b(?:JP|JR|DJNZ)\b(?:\s+[A-Z]+,)?\s+([A-Za-z_][A-Za-z0-9_]*)\b")
DATA_MNEMONIC_RE = re.compile(r"^\s*(DB|DW|DS|INCBIN)\b")
LABEL_DEF_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
IDENT_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")


def parse_listing(path):
    """Devuelve (labels, source_lines) donde labels[name] = (addr, file, line)
    y source_lines es la lista de (file, line, addr, text) en orden."""
    labels = {}
    source_lines = []
    file_stack = []

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        raw_lines = f.readlines()

    for raw in raw_lines:
        raw = raw.rstrip("\n")
        if raw.startswith("# file opened:"):
            file_stack.append(raw.split(":", 1)[1].strip())
            continue
        if raw.startswith("# file closed:"):
            if file_stack:
                file_stack.pop()
            continue

        m = LST_LINE_RE.match(raw)
        if not m:
            continue
        lineno, addr, text = m.group(1), m.group(2), m.group(3)
        cur_file = file_stack[-1] if file_stack else "?"
        source_lines.append((cur_file, int(lineno), addr, text))

        lm = LABEL_RE.match(text.strip())
        if lm and addr:
            name = lm.group(1)
            if name not in labels:
                labels[name] = (addr, cur_file, int(lineno))

    return labels, source_lines


def collect_mentions(source_lines):
    """Cualquier identificador que aparezca como OPERANDO en cualquier
    linea de codigo (fuera de comentarios), excluyendo el propio
    'NOMBRE:' de cada definicion de etiqueta -- para detectar usos
    indirectos que CALL_RE/JUMP_RE no cubren: tablas de saltos
    (DW ETIQUETA) y saltos via registro (LD IY,ETIQUETA + JP (IY))."""
    mentions = set()
    for _file, _line, _addr, text in source_lines:
        code = text.split(";", 1)[0]
        m = LABEL_DEF_RE.match(code)
        if m:
            code = m.group(2)
        mentions.update(IDENT_RE.findall(code))
    return mentions


def classify(labels, source_lines):
    called = set()
    jumped = set()
    for _file, _line, _addr, text in source_lines:
        for m in CALL_RE.finditer(text):
            called.add(m.group(1))
        for m in JUMP_RE.finditer(text):
            jumped.add(m.group(1))
    mentioned = collect_mentions(source_lines)

    # que sigue a cada etiqueta (siguiente linea con contenido real)
    next_stmt = {}
    for i, (_file, _line, _addr, text) in enumerate(source_lines):
        stripped = text.strip()
        lm = LABEL_RE.match(stripped)
        if not lm:
            continue
        name = lm.group(1)
        rest_of_line = stripped[len(lm.group(0)):].strip()
        if rest_of_line and not rest_of_line.startswith(";"):
            next_stmt[name] = rest_of_line
            continue
        for j in range(i + 1, len(source_lines)):
            nxt = source_lines[j][3].strip()
            if nxt == "" or nxt.startswith(";"):
                continue
            # otra etiqueta apilada justo debajo (con o sin comentario
            # propio) es transparente: seguir buscando la sentencia real
            nxt_lm = LABEL_RE.match(nxt)
            if nxt_lm:
                nxt_rest = nxt[len(nxt_lm.group(0)):].strip()
                if not nxt_rest or nxt_rest.startswith(";"):
                    continue
                next_stmt[name] = nxt_rest
                break
            next_stmt[name] = nxt
            break

    result = {}
    for name in labels:
        if name in called:
            tipo = "funcion"
        elif DATA_MNEMONIC_RE.match(next_stmt.get(name, "")):
            tipo = "dato"
        elif name in jumped:
            tipo = "interna"
        elif name in mentioned:
            tipo = "interna"          # uso indirecto: DW en tabla de saltos, LD IY/IX/HL,ETIQUETA + JP (IY/IX/HL), etc.
        else:
            tipo = "sinref"
        result[name] = tipo
    return result


def build_inventory(labels, types):
    rows = []
    for name, (addr, file_, line) in labels.items():
        rows.append([name, addr, file_, line, types[name]])
    # ordenar por fichero (orden de aparicion no garantizado por dict,
    # asi que por direccion dentro de cada fichero)
    file_order = []
    for _n, _a, file_, _l, _t in rows:
        if file_ not in file_order:
            file_order.append(file_)
    file_rank = {f: i for i, f in enumerate(file_order)}
    rows.sort(key=lambda r: (file_rank[r[2]], int(r[1], 16)))
    return rows


def main():
    if not os.path.exists(LST_PATH):
        print(f"ERROR: falta {LST_PATH} -- ejecuta antes:")
        print("  sjasmplus src/main.asm --lst=src/build/main.lst")
        raise SystemExit(1)

    labels, source_lines = parse_listing(LST_PATH)
    types = classify(labels, source_lines)
    rows = build_inventory(labels, types)

    counts = {"funcion": 0, "interna": 0, "dato": 0, "sinref": 0}
    for row in rows:
        counts[row[4]] += 1

    with open(HTML_PATH, "r", encoding="utf-8") as f:
        html = f.read()

    inv_pattern = re.compile(r"const INVENTORY = \[.*?\];", re.DOTALL)
    if not inv_pattern.search(html):
        print("ERROR: no se encontro 'const INVENTORY = [...]' en el HTML, no se toco nada")
        raise SystemExit(1)
    inv_js = "const INVENTORY = " + json.dumps(rows, ensure_ascii=False, separators=(",", ":")) + ";"
    html_new = inv_pattern.sub(lambda m: inv_js, html, count=1)

    total = len(rows)
    html_new = re.sub(
        r"Inventario completo \(\d+ etiquetas, clasificadas y buscables\)",
        f"Inventario completo ({total} etiquetas, clasificadas y buscables)",
        html_new,
    )
    for tipo, label_txt in [("funcion", "función"), ("interna", "interna"), ("dato", "dato"), ("sinref", "sin ref.")]:
        html_new = re.sub(
            rf'(value="{tipo}"[^>]*>\s*<span class="tipo-tag tipo-{tipo}">{label_txt}</span>\s*\()\d+(\))',
            rf"\g<1>{counts[tipo]}\g<2>",
            html_new,
        )
    # lista de vinetas en prosa ("<li><b>94 función</b> ...")
    for tipo, label_txt in [("funcion", "función"), ("interna", "interna"), ("dato", "dato"), ("sinref", "sin ref\\.")]:
        html_new = re.sub(
            rf"(<li><b>)\d+( {label_txt}</b>)",
            rf"\g<1>{counts[tipo]}\g<2>",
            html_new,
        )

    with open(HTML_PATH, "w", encoding="utf-8") as f:
        f.write(html_new)

    print(f"escrito {HTML_PATH}")
    print(f"total etiquetas: {total}  (funcion={counts['funcion']} interna={counts['interna']} dato={counts['dato']} sinref={counts['sinref']})")


if __name__ == "__main__":
    main()
