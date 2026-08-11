---
name: "Pull Request - Reconstrucción / Traducción Z80"
about: Plantilla para proponer cambios en la traducción del binario, etiquetado de memoria o estructura de datos.
---

## 📝 Resumen del Cambio (Summary)
<!-- Describe brevemente los cambios introducidos en este Pull Request y su objetivo principal. -->

- [ ] **Etiquetado / Naming:** Identificación y renombrado de etiquetas (funciones, variables o constantes).
- [ ] **Delimitación de Datos:** Reestructuración o corrección de bloques de datos (`.db`, `.dw`, tablas, gráficos, audio).
- [ ] **Desensamblado de Código:** Conversión de bytes crudos a instrucciones Z80 ejecutables.
- [ ] **Formato / Refactor:** Mejoras en la estructura del código, comentarios o legibilidad sin alterar el ensamblado.
- [ ] **Fix / Corrección:** Corrección de un fallo previo en la traducción o en la delimitación de memoria.

---

## 📍 Rangos de Memoria / Archivos Modificados (Scope)

- **Rango de direcciones de memoria (PC / Org):** `$XXXX` - `$YYYY`
- **Archivos principales modificados:**
  - `[ej. src/engine/player.asm]`
  - `[ej. data/sprites.inc]`
- **Issue(s) relacionada(s):** Closes #<!-- Número de Issue si aplica, ej. #12 -->

---

## 🔬 Descripción Detallada de los Cambios (Detailed Changes)

### 1. Funciones y Variables Identificadas / Renombradas:
- `lbl_8200` ➡️ `UPDATE_SPRITE_ANIMATION`: Subrutina encargada de actualizar el frame actual del sprite principal.
- `data_9100` ➡️ `PLAYER_POS_X`: Variable de 1 byte con la coordenada X del jugador en la pantalla.

### 2. Estructuras / Bloques de Datos Delimitados:
- Se delimitó la tabla de saltos en `$8500` - `$8510` (previamente desensamblada por error como instrucciones `NOP` / `LD`).
- Se formateó la tabla de atributos de color/VRAM en bloques `.db`.

---

## 🧪 Verificación de Fidelidad 1:1 (Byte-Matching)

Es fundamental verificar si los cambios mantienen la integridad de la compilación frente al ejecutable original.

- [ ] **BYTE-MATCH EXACTO:** El ejecutable/ROM generado tras este PR es **100% idéntico** (bit a bit) al binario original.
- [ ] **NON-MATCHING (Con divergencias):** El binario difiere. *(Justificar en la sección de notas el motivo de la divergencia).*

**Comando de verificación utilizado:**
```bash
# Ejemplo: md5sum / cmp entre el ejecutable generado y la ROM/disco original
md5sum build/game_rebuilt.bin original/game_original.bin
```
**Resultado del HASH / Checksum:**
- Original: `XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`
- Reconstruido: `XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`

---

## 📋 Checklist del Autor

- [ ] El código ensambla correctamente con la toolchain del proyecto (`sjasmplus`, `pasmo`, etc.) sin errores ni warnings.
- [ ] Se han documentado adecuadamente las nuevas etiquetas y los bloques de datos.
- [ ] No se han dejado etiquetas temporales o ambiguas (ej. `temp_1`, `fix_here`).
- [ ] Se ha verificado que no hay solapamiento de direcciones o saltos a posiciones fuera de rango.