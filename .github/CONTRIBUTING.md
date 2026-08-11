# Guía de Contribución (CONTRIBUTING)

*[Read this in English](CONTRIBUTING.en.md)*

¡Gracias por tu interés en contribuir a este proyecto de **ingeniería inversa,
desensamblado y reconstrucción en ensamblador Z80** de *Mad Mix Game* (Topo
Soft, 1987/88, MSX1)!

El objetivo del repositorio es traducir los binarios originales del juego
(disco y cinta) a código fuente Z80 real, identificando y documentando
funciones, variables y bloques de datos, manteniendo siempre una
**reconstrucción 1:1 (byte-matching)** frente a los ejecutables originales.
Antes de nada, échale un vistazo a `METODOLOGIA.md` (el proceso completo del
proyecto) y a `src/FINDINGS.md` (el diario de hallazgos) para entender cómo se
ha trabajado hasta ahora.

---

## 📌 Principios Fundamentales del Proyecto

1. **Fidelidad 1:1 (byte-matching):** cualquier cambio en las instrucciones
   ensamblador o en las tablas de datos debe seguir generando un binario
   idéntico, byte a byte, al original — salvo la única desviación deliberada
   del proyecto (el fix del contador de bolitas del nivel 13, documentado en
   `src/FINDINGS.md` y `manuales/manual_niveles.md`).
2. **Claridad sobre interpretación:** no se añade código nuevo ni se
   "optimizan" rutinas originales. El objetivo es traducir e interpretar
   exactamente lo que el binario hace, bugs originales incluidos.
3. **Paso a paso:** mejor etiquetar/documentar un bloque pequeño y verificado
   que enviar un cambio grande sin comprobar contra el binario real.
4. **Nombres descriptivos en español:** la convención ya establecida en todo
   el proyecto (cientos de rondas de renombrado documentadas en
   `src/FINDINGS.md`) es usar nombres descriptivos **en español**, no inglés
   ni abreviaturas crípticas — por ejemplo `MOTOR_ACTORES`,
   `CONSULTAR_TIPO_LOSETA`, `REGISTRO_NIVEL_POSICION_COMECOCOS`, no
   `ACTOR_ENGINE` ni `lbl_8200`. Las etiquetas puramente internas de una
   rutina (marcas de salto, no funciones con entidad propia) usan un punto
   inicial (`.BUCLE_LOSETAS`, etiqueta local).

---

## 🛠️ Entorno de Trabajo y Herramientas

- **Ensamblador:** [SjASMPlus](https://github.com/z00m128/sjasmplus) en el
  PATH — es el único ensamblador que usa este proyecto (no `pasmo`, no
  `z80asm`).
- **Python 3** (`py` en Windows) — para las herramientas de `tools/`
  (compilación completa, generación de `.dsk`/`.cas`, sonido, niveles, BASIC
  tokenizado). Sin dependencias externas, solo librería estándar.
- **openMSX** (opcional pero recomendado) para probar el resultado — y, para
  depuración en vivo, admite un protocolo de control externo por script (ver
  `doc/manual/openmsx-control.html` de tu instalación de openMSX;
  `src/FINDINGS.md` tiene un ejemplo real de uso para verificar hipótesis en
  vivo, no solo leyendo el código).
- **Una copia legalmente obtenida del juego original** (disco y/o cinta) si
  quieres verificar tú mismo la comparación byte a byte — este repositorio
  **no incluye** las imágenes originales (`.dsk`/`.cas`/`.rom`), ver
  `AVISO-LEGAL.md`. Sin ellas puedes seguir contribuyendo (renombrados,
  comentarios, documentación), pero no podrás comprobar el byte-match tú
  mismo.

---

## 🚀 Flujo de Trabajo para Contribuir

### 1. Preparar el Repositorio

1. Haz un **fork** de este repositorio en GitHub.
2. Clónalo localmente:

   ```bash
   git clone https://github.com/TU_USUARIO/MSX_MadMixGame.git
   cd MSX_MadMixGame
   ```

3. Crea una rama descriptiva:

   ```bash
   git checkout -b etiquetar-motor-colision
   # o bien: git checkout -b fix-comentario-scroll
   ```

### 2. Compilar y Verificar

```bash
# Compila TODO el proyecto de un tirón (motor, pantalla, cargadores de disco y cinta)
py tools/build_all.py

# Genera los 2 entregables finales (.dsk y .cas) desde cero
py tools/gen_disk_and_cas.py
```

Esto deja los binarios en `src/build/` —
`src/build/madmix_reconstruido.dsk` y `src/build/madmix_reconstruido.cas` son
los entregables finales. Si tienes una copia del original, compara:

```bash
# Windows / PowerShell
fc /b src\build\madmix_reconstruido.dsk ruta\al\original.dsk

# o con Python, byte a byte, para contar diferencias exactas
py -c "a=open('src/build/madmix_reconstruido.dsk','rb').read(); b=open('ruta/al/original.dsk','rb').read(); print(sum(1 for x,y in zip(a,b) if x!=y), 'diferencias')"
```

Si tu cambio es solo renombrado/comentarios, el resultado debe ser
**exactamente el mismo** que antes de tu cambio (0 diferencias nuevas). Si
introduces una divergencia real y justificada, documéntala igual que se hizo
con el bug del nivel 13.

### 3. Documentar el hallazgo

Si identificas o corriges algo (una etiqueta, un bloque de datos, un
comportamiento), añade una entrada en `src/FINDINGS.md` siguiendo el estilo ya
usado — un encabezado `##`/`###` describiendo qué se creía antes, qué se
descubrió y cómo se verificó. Es el diario cronológico del proyecto; no se
reescribe el historial, se añade encima.

---

## 📬 Envío de Pull Requests

1. Haz commit de tus cambios con mensajes descriptivos:

   ```bash
   git commit -m "Renombra MOTOR_MOVIMIENTO_ITEM y documenta su hallazgo en FINDINGS.md"
   ```

2. Sube tu rama:

   ```bash
   git push origin etiquetar-motor-colision
   ```
3. Abre una **Pull Request** contra la rama `main` de este repositorio.
4. Completa la plantilla de PR (rangos de memoria modificados, verificación
   byte a byte, ficheros afectados).

---

## 🐛 Reporte de Errores e Inconsistencias

Si encuentras una sección mal interpretada, datos leídos como código, o una
etiqueta que ya no describe lo que hace su rutina, pero no vas a corregirlo
tú mismo:

1. Comprueba que no exista ya un Issue abierto sobre lo mismo.
2. Abre un nuevo Issue con la plantilla de reporte de desensamblado/etiquetado
   (disponible en español e inglés).
3. Incluye la dirección de memoria real y la justificación técnica —si puedes
   verificarlo en vivo con openMSX o comparando contra el binario original,
   mejor.

---

¡Gracias por colaborar en la preservación e ingeniería inversa de este trozo
de la historia del software español!
