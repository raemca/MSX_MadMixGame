---
name: "Pull Request - Reconstrucción Mad Mix Game (MSX1 / Z80)"
about: Plantilla para proponer cambios en la reconstrucción del binario, etiquetado de memoria, herramientas o documentación.
---

## 📝 Resumen del Cambio

<!-- Describe brevemente los cambios y su objetivo principal. -->

- [ ] **Etiquetado / naming:** identificación y renombrado de etiquetas (funciones, variables, constantes) — en español descriptivo, siguiendo la convención ya establecida.
- [ ] **Delimitación de datos:** reestructuración o corrección de bloques de datos (tiles, sprites, niveles, sonido, texto).
- [ ] **Desensamblado de código:** conversión de bytes crudos (`DS`, huecos sin identificar) a instrucciones Z80 reales.
- [ ] **Herramientas (`tools/`):** cambios en los scripts Python de compilación/generación/verificación.
- [ ] **Documentación:** cambios en `src/FINDINGS.md`, `src/FLUJO_PROGRAMA.md`, `manuales/`, `METODOLOGIA.md` o los visores HTML de `recursos/`.
- [ ] **Fix / corrección:** corrección de un fallo previo en la reconstrucción o en el etiquetado.

---

## 📍 Alcance (rangos de memoria / ficheros modificados)

- **Rango de direcciones reales (si aplica):** `$XXXX` - `$YYYY`
- **Ficheros principales modificados:**
  - `[ej. src/madmix1_body.asm]`
  - `[ej. tools/mmlvl_tool.py]`
- **Issue(s) relacionada(s):** Closes #<!-- número de Issue si aplica -->

---

## 🔬 Descripción Detallada

### 1. Etiquetas identificadas / renombradas

<!-- Ejemplo real del estilo del proyecto (español descriptivo, no inglés ni abreviaturas crípticas): -->
- `RM_C4CC` ➡️ `INSTALAR_RECURSO_SONIDO_EN_A`: variante de entrada con el índice ya cargado en A.
- `$8437` ➡️ `CONTADOR_ACTORES_ACTIVOS`: variable de 1 byte, número de actores dibujados este frame.

### 2. Bloques de datos / hallazgos

<!-- Ejemplo: -->
- Se identificó el bloque `$5AD5`-`$5B50` como la pantalla de menú principal (antes hueco `DS` sin explorar).
- Se corrigió el tamaño documentado de `AREA_TRABAJO_PSG` (171 → 151 bytes).

---

## 🧪 Verificación de Fidelidad (Byte-Matching)

Este proyecto reconstruye el binario original **byte a byte**, con una única
desviación deliberada ya documentada (el fix del contador de bolitas del
nivel 13, ver `src/FINDINGS.md`). Cualquier otro cambio debe reproducir
exactamente el original.

- [ ] Recompila sin errores: `py tools/build_all.py`
- [ ] Regenera los entregables: `py tools/gen_disk_and_cas.py`
- [ ] **BYTE-MATCH:** comparado contra el binario original (si tienes una
      copia), **0 diferencias nuevas** respecto al estado anterior de la rama.
- [ ] **No aplica / sin copia del original:** el cambio es solo
      documentación/comentarios/herramientas, sin tocar bytes compilados.

**Comando(s) de verificación utilizados:**

```bash
py tools/build_all.py
py tools/gen_disk_and_cas.py
# comparación byte a byte, si tienes el original:
py -c "a=open('src/build/madmix_reconstruido.dsk','rb').read(); b=open('ruta/al/original.dsk','rb').read(); print(sum(1 for x,y in zip(a,b) if x!=y), 'diferencias')"
```

**Resultado:** <!-- ej. "0 diferencias, igual que antes del cambio" -->

---

## 📋 Checklist del Autor

- [ ] El código compila con `sjasmplus` (vía `py tools/build_all.py`) sin errores ni warnings nuevos.
- [ ] Las etiquetas nuevas siguen la convención del proyecto (español descriptivo; `.NOMBRE` con punto para marcas internas de salto, no funciones con entidad propia).
- [ ] No quedan etiquetas temporales o ambiguas.
- [ ] Si el cambio es un hallazgo real (no solo limpieza), se ha añadido la entrada correspondiente en `src/FINDINGS.md`.
- [ ] Si el cambio afecta a un documento con traducción al inglés (`README.md`, los manuales, `FLUJO_PROGRAMA.md`, `METODOLOGIA.md`...), se ha actualizado también su `.en.md`.
