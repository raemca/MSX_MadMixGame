---
name: "Reporte de error en la reconstrucción (Mad Mix Game / MSX1)"
about: Plantilla para reportar errores en el desensamblado, etiquetado, datos o herramientas de este proyecto.
title: "[$XXXX] <Resumen del problema>"
labels: bug, desensamblado
assignees: ''
---

## 📌 Resumen del Problema

<!-- Describe el error encontrado: datos interpretados como código, rutina mal
identificada, variable con tamaño incorrecto, divergencia byte a byte,
herramienta de tools/ que falla, documentación desactualizada, etc. -->

**Estado actual en el proyecto:**
<!-- Cómo está nombrado/estructurado/documentado actualmente. -->

**Corrección propuesta:**
<!-- Cómo debería ser, según tu análisis del binario original o de la ejecución en vivo. -->

---

## 📍 Ubicación

- **Dirección de memoria real (si aplica):** `$XXXX` (ej. `$8400`, dentro de `MADMIX1.BIN`)
- **Fichero(s) afectado(s):** `[ej. src/madmix1_body.asm, tools/mmlvl_tool.py, manuales/manual_niveles.md]`
- **Versión / binario:** disco (`MADMIX1.BIN`/`MADMIX.SCR`/`MADMIX0.BIN`) o cinta (`LOAD.BIN`/`TEST.BIN`/`LOGOTOPO.CM`) — indica cuál, ya que se reconstruyen por separado.

---

## 🏷️ Tipo de Problema

<!-- Marca con [x] la opción correspondiente -->
- [ ] **Dato interpretado como código (o viceversa):** un bloque de datos se desensambló como instrucciones Z80, o al revés.
- [ ] **Dimensionamiento de datos:** una tabla, tile, sprite o buffer tiene tamaño o formato incorrecto (ver `manuales/` para los formatos ya documentados).
- [ ] **Etiquetado erróneo:** un nombre no se corresponde con el comportamiento real de la rutina/variable.
- [ ] **Divergencia byte a byte:** al recompilar (`py tools/build_all.py` + `py tools/gen_disk_and_cas.py`), el resultado no coincide con el original y no es la desviación ya documentada del nivel 13.
- [ ] **Herramienta rota:** algún script de `tools/` falla o produce un resultado incorrecto (roundtrip, verificación, etc.).
- [ ] **Documentación desactualizada o inconsistente:** algo en `src/FINDINGS.md`, `src/FLUJO_PROGRAMA.md`, `manuales/` o los `.en.md` ya no coincide con el código real.

---

## 🔬 Comparativa (si aplica)

### Estado actual en el repositorio

```z80
; Dirección real: $XXXX
; [pega aquí el fragmento actual de src/madmix1_body.asm o src/madmix_scr_body.asm]
```

### Propuesta / evidencia

```z80
; [pega aquí tu propuesta, o describe cómo lo verificaste: volcado real, ejecución en vivo con openMSX, etc.]
```

---

## ✅ Cómo lo verificaste (si lo hiciste)

- [ ] Recompilé (`py tools/build_all.py`) y comparé contra el binario original.
- [ ] Lo verifiqué en vivo con openMSX (breakpoints/watchpoints, ver `src/FINDINGS.md` para ejemplos de este método).
- [ ] Es una observación sin verificar todavía (indícalo igualmente, es útil como pista).
