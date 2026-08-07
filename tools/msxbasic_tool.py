#!/usr/bin/env python3
"""
msxbasic_tool.py -- detokeniza/tokeniza BASIC tokenizado de MSX (cabecera $FF).

Tabla de tokens PARCIAL, no una tabla estandar completa de MSX-BASIC: solo
incluye los tokens verificados EMPIRICAMENTE contra el contenido ya conocido
(FINDINGS.md, "secuencia de arranque completa desde el .BAS") de
AUTOEXEC.BAS y MADMIX.BAS -- BLOAD, RUN, DEF, USR, "=", la constante hex de
2 bytes (prefijo $0C) y los literales enteros compactos $11-$1B (0-10).

Cualquier byte fuera de ese conjunto confirmado (o fuera del rango ASCII
imprimible $20-$7E) se representa como escape "{$XX}" en el listado
editable -- garantiza un roundtrip exacto incluso para tokens cuyo
significado no se ha identificado (p.ej. algunos tokens de las lineas de
cabecera/REM de MADMIX.BAS, ver FINDINGS.md).

Uso:
    py msxbasic_tool.py detok <entrada.bas> <salida.txt>
    py msxbasic_tool.py tok <entrada.txt> <salida.bas>
    py msxbasic_tool.py roundtrip <original.bas>   -- detok+tok y compara bytes

Autor de esta herramienta: Rafael Eduardo Martín Candial
"""
import sys

BASE_ADDR = 0x8001  # direccion del primer byte de la primera linea (tras la
                     # cabecera $FF en $8000) -- fija para estos ficheros.

TOKENS = {
    0x8F: "REM",
    0x97: "DEF",
    0xB5: "RUN",
    0xCF: "BLOAD",
    0xDD: "USR",
    0xEF: "=",
}
TOKENS_REV = {v: k for k, v in TOKENS.items()}
# Ordenar por longitud descendente para hacer coincidencia de la mas larga
# primero (evita que "DEF" se coma parte de otra palabra, etc.)
KEYWORDS_BY_LEN = sorted(TOKENS_REV.keys(), key=len, reverse=True)

HEX_CONST_PREFIX = 0x0C
INT_LITERAL_BASE = 0x11   # $11..$1B representan los enteros 0..10


def detok_line_content(content: bytes) -> str:
    out = []
    i = 0
    n = len(content)
    while i < n:
        b = content[i]
        if b == HEX_CONST_PREFIX and i + 2 < n:
            val = content[i + 1] | (content[i + 2] << 8)
            out.append("&H%04X" % val)
            i += 3
        elif INT_LITERAL_BASE <= b <= INT_LITERAL_BASE + 10:
            out.append(str(b - INT_LITERAL_BASE))
            i += 1
        elif b in TOKENS:
            out.append(TOKENS[b])
            i += 1
        elif 0x20 <= b <= 0x7E:
            out.append(chr(b))
            i += 1
        else:
            out.append("{$%02X}" % b)
            i += 1
    return "".join(out)


def detok(data: bytes) -> str:
    assert data[0] == 0xFF, "no es un fichero BASIC tokenizado (falta cabecera $FF)"
    pos = 1
    lines = []
    while True:
        ptr = data[pos] | (data[pos + 1] << 8)
        if ptr == 0:
            break
        linenum = data[pos + 2] | (data[pos + 3] << 8)
        start = pos + 4
        end = data.index(0x00, start)
        content = data[start:end]
        lines.append((linenum, detok_line_content(content)))
        pos = end + 1
    return "\n".join(f"{num} {text}" for num, text in lines) + "\n"


def tok_line_content(text: str) -> bytes:
    out = bytearray()
    i = 0
    n = len(text)
    in_quotes = False
    while i < n:
        c = text[i]
        if not in_quotes and c == "{" and text[i:i + 2] == "{$":
            j = text.index("}", i)
            out.append(int(text[i + 2:j], 16))
            i = j + 1
            continue
        if not in_quotes and c == "&" and text[i:i + 2] == "&H":
            j = i + 2
            while j < n and text[j] in "0123456789ABCDEFabcdef":
                j += 1
            val = int(text[i + 2:j], 16)
            out.append(HEX_CONST_PREFIX)
            out.append(val & 0xFF)
            out.append((val >> 8) & 0xFF)
            i = j
            continue
        if c == '"':
            in_quotes = not in_quotes
            out.append(0x22)
            i += 1
            continue
        if not in_quotes:
            matched = False
            for kw in KEYWORDS_BY_LEN:
                if text.startswith(kw, i):
                    out.append(TOKENS_REV[kw])
                    i += len(kw)
                    matched = True
                    break
            if matched:
                continue
            if c.isdigit():
                out.append(INT_LITERAL_BASE + int(c))
                i += 1
                continue
        out.append(ord(c))
        i += 1
    return bytes(out)


def tok(text: str) -> bytes:
    out = bytearray([0xFF])
    lines = [l for l in text.split("\n") if l.strip() != ""]
    records = []
    for line in lines:
        num_str, _, rest = line.partition(" ")
        linenum = int(num_str)
        content = tok_line_content(rest)
        records.append((linenum, content))

    addr = BASE_ADDR
    encoded = []
    for linenum, content in records:
        reclen = 2 + 2 + len(content) + 1  # ptr(2) + linenum(2) + content + terminador
        addr += reclen
        encoded.append((addr, linenum, content))

    for next_ptr, linenum, content in encoded:
        out.append(next_ptr & 0xFF)
        out.append((next_ptr >> 8) & 0xFF)
        out.append(linenum & 0xFF)
        out.append((linenum >> 8) & 0xFF)
        out.extend(content)
        out.append(0x00)
    out.append(0x00)
    out.append(0x00)
    return bytes(out)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "detok":
        with open(sys.argv[2], "rb") as f:
            data = f.read()
        text = detok(data)
        with open(sys.argv[3], "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"detok: {sys.argv[2]} ({len(data)} bytes) -> {sys.argv[3]}")
    elif cmd == "tok":
        with open(sys.argv[2], "r", encoding="utf-8") as f:
            text = f.read()
        data = tok(text)
        with open(sys.argv[3], "wb") as f:
            f.write(data)
        print(f"tok: {sys.argv[2]} -> {sys.argv[3]} ({len(data)} bytes)")
    elif cmd == "roundtrip":
        with open(sys.argv[2], "rb") as f:
            orig = f.read()
        text = detok(orig)
        back = tok(text)
        if back == orig:
            print(f"OK: roundtrip identico byte a byte ({len(orig)} bytes)")
        else:
            print(f"DIFERENCIA: orig={len(orig)} bytes, roundtrip={len(back)} bytes")
            n = min(len(orig), len(back))
            diffs = 0
            for i in range(n):
                if orig[i] != back[i]:
                    diffs += 1
                    if diffs <= 20:
                        print(f"  offset {i}: orig={orig[i]:02X} roundtrip={back[i]:02X}")
            print(f"  total diffs: {diffs}")
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
