# Guía de Contribución (CONTRIBUTING)

¡Gracias por tu interés en contribuir a este proyecto de **ingeniería inversa, desensamblado y reconstrucción en ensamblador Z80**! 

El objetivo principal de este repositorio es traducir el binario original del juego a código fuente en ensamblador Z80, identificando y documentando funciones, variables y bloques de datos, manteniendo siempre una **reconstrucción 1:1 (Byte-Matching)** con respecto al ejecutable original.

---

## 📌 Principios Fundamentales del Proyecto

1. **Fidelidad 1:1 (Byte-Matching):** Cualquier modificación en las instrucciones ensamblador o en las tablas de datos debe generar un binario idéntico al dump/ROM original.
2. **Claridad sobre Interpretación:** No añadimos código nuevo ni "optimizamos" rutinas originales. El objetivo es traducir e interpretar lo que el binario hace exactamente.
3. **Paso a Paso:** Es preferible etiquetar pequeños bloques de datos o funciones individuales que enviar cambios masivos sin verificar.

---

## 🛠️ Entorno de Trabajo y Herramientas

Para contribuir y verificar tus cambios localmente necesitarás:

* **Ensamblador / Toolchain:** `sjasmplus` (o la herramienta indicada en el archivo `Makefile` / `build.sh`).
* **Verificación de Hash:** Utilidades como `md5sum`, `shasum` o `cmp` para comprobar la integridad del binario resultante.
* **Emulador / Depurador (opcional pero recomendado):** Emuladores con monitor Z80/RAM como Fuse, RetroVirtualMachine, OpenMSX, MAME o Ghidra/IDA Pro.

---

## 🚀 Flujo de Trabajo para Contribuir

### 1. Preparar el Repositorio
1. Haz un **Fork** de este repositorio en GitHub.
2. Clona tu fork localmente:
   ```bash
   git clone https://github.com/TU_USUARIO/nombre-del-repo.git
   cd nombre-del-repo
   ```
3. Crea una rama descriptiva para tus cambios:
   ```bash
   git checkout -b feature/identificar-rutina-jugador
   # o bien: git checkout -b fix/tabla-datos-sprites
   ```

### 2. Normas de Estilo y Nomenclatura (Z80 / Assembly)

* **Etiquetas de Funciones / Subrutinas:** Usar `SNAKE_CASE` en mayúsculas descriptivas.
  * *Ejemplo:* `UPDATE_PLAYER_POSITION:`, `CHECK_SPRITE_COLLISION:`
* **Variables y Posiciones de Memoria en RAM:** Usar prefijos claros según el alcance/tipo si aplica.
  * *Ejemplo:* `PLAYER_X_POS`, `GAME_SCORE_BCD`, `CURRENT_STAGE`
* **Datos y Tablas (`.db` / `.dw`):**
  * Mantener los datos alineados y documentar la estructura (ancho x alto de sprites, formato de atributos de color VRAM, etc.).
  * Si un bloque aún no se ha interpretado completamente, delimitarlo de forma precisa como bytes raw con su dirección original (`data_8000:`).
* **Direcciones Hexadecimales:** Utilizar la notación `$XXXX` (o `#XXXX` según el ensamblador del proyecto).

### 3. Compilación y Verificación del Binario

Antes de realizar el commit, **debes asegurarte de que el proyecto ensambla correctamente** y de verificar el checksum:

```bash
# 1. Ensamblar el código fuente
make build   # o el script de compilación del proyecto

# 2. Comparar el binario generado con la ROM/disco original
md5sum build/game_rebuilt.bin original/game_original.bin
```

> ⚠️ **Atención:** Si tu contribución es solo de renombrado de etiquetas o refactorización de comentarios, el MD5 debe coincidir exactamente. Si hay una divergencia justificada (ej. corrección de un bug del original), indícalo claramente en la Pull Request.

---

## 📬 Envío de Pull Requests (PR)

1. Haz commit de tus cambios con mensajes descriptivos:
   ```bash
   git commit -m "Renombra subrutina $8200 a UPDATE_PLAYER_SPRITE y delimita tabla de animación"
   ```
2. Sube tus cambios a tu fork:
   ```bash
   git push origin feature/identificar-rutina-jugador
   ```
3. Abre una **Pull Request** en GitHub contra la rama `main` del repositorio principal.
4. Completa todos los puntos de la **plantilla de Pull Request** (rangos de memoria modificados, verificación de hash, etc.).

---

## 🐛 Reporte de Errores e Inconsistencias

Si encuentras una sección de código mal interpretada, datos leídos como código o una etiqueta confusa, pero no vas a enviar el código tú mismo:
1. Revisa que no exista ya un reporte abierto en la pestaña de **Issues**.
2. Abre una **nueva Issue** utilizando la plantilla de *Reporte de Error de Desensamblado / Etiquetado Z80*.
3. Incluye la dirección de memoria (`PC`) y la justificación técnica correspondiente.

---

¡Muchas gracias por colaborar en la preservación e ingeniería inversa del software retro de 8 bits!
