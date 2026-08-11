---
name: "Reporte de Error de Desensamblado / Etiquetado Z80"
about: Plantilla para reportar errores en la delimitación de datos/código, naming de funciones/variables, o divergencias en la reconstrucción del binario original.
title: "[$XXXX] <Resumen del problema de desensamblado o etiqueta>"
labels: disassembly, data-structure, byte-match, z80
assignees: ''
---

## 📌 Resumen del Problema (Overview)
<!-- Describe el error encontrado en la traducción del binario al código fuente (ej. datos interpretados como código, rutina mal identificada, variable con tipo/tamaño incorrecto, o desalineación al reensamblar). -->

**Interpretación actual en el fuente:**
<!-- Cómo está nombrada o estructurada actualmente esta sección en el proyecto. -->

**Interpretación corregida / propuesta:**
<!-- Cómo debería estructurarse, nombrarse o delimitarse según el análisis del binario original. -->

---

## 📍 Ubicación en Memoria y Archivos (Location)

- **Dirección de Memoria (PC / Org):** `$XXXX` (ej. `$8000` / `#8000`)
- **Offset en el Binario Original:** `0xXXXX`
- **Archivo afectado en el repo:** `[ej. src/engine/player.asm, data/sprites.inc]`
- **Plataforma / Arquitectura target:** [ej. ZX Spectrum 48K/128K, Amstrad CPC, MSX, Game Boy, ColecoVision]
- **Ensamblador / Toolchain de reconstrucción:** [ej. sjasmplus, Pasmo, z80asm, SkoolKit]

---

## 🏷️ Tipo de Error en la Traducción (Issue Category)
<!-- Marca con una [x] la opción correspondiente -->
- [ ] **Data vs. Code (Delimitación de datos/código):** Se ha desensamblado un bloque de datos como instrucciones Z80 (o código executable identificado como bytes `.db`/`.dw`).
- [ ] **Dimensionamiento de Datos / Tablas:** Una tabla, gráfico o buffer tiene una longitud o estructura de bytes incorrecta (ej. `.db` en lugar de `.dw`, o tamaño de sprite equivocado).
- [ ] **Etiquetado / Naming Erróneo:** Nombre de función, rutina o variable que no se corresponde con su comportamiento real en el juego.
- [ ] **Punteros y Tablas de Salto (Jump Tables):** Punteros de memoria no detectados, tablas de saltos desalineadas o referencias indirectas (`JP (HL)`, `LD A, (IX+d)`) mal asociadas a etiquetas.
- [ ] **Divergencia Byte-Match (Non-matching reassembly):** Al ensamblar el código fuente actual, el ejecutable generado no coincide al 100% (bit a bit) con el binario original.
- [ ] **Documentación / Comentarios:** Interpretación errónea de la lógica interna en las notas/comentarios de la función.

---

## 🔬 Comparativa de Código / Desensamblado (Code Comparison)

### Estado Actual en el Repositorio:
```z80
; Dirección actual: $8000
; [Describir lo que hay actualmente en el archivo del repo]
lbl_8000:
    LD A, $05
    OUT ($FE), A
    RET
