# Manual del formato de niveles — Mad Mix Game (MSX1)

*[Read this in English](manual_niveles.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Fuente: `madmix_scr.asm` (`CARGAR_NIVEL`, `TABLA_NIVELES`, los 13
> cuerpos + 3 cabeceras de nivel) y `madmix1.asm` (`VERIFICAR_FIN_NIVEL`).
> Para la crónica de cómo se descubrió cada pieza, ver `FINDINGS.md`;
> este documento asume que ya está todo identificado y explica el
> resultado final de forma ordenada.

## 1. Qué es esto y qué NO es

Este manual explica cómo están construidos los 15 niveles del juego —
el formato de la rejilla de losetas, cómo se cargan en memoria, y
cómo se detecta que un nivel está completo — y cómo editarlos con
`mmlvl_tool.py`.

**No es** un sistema de niveles con metadatos ricos ni un editor visual
en el propio juego: cada nivel es, literalmente, una rejilla de bytes
(un byte = una loseta) más un registro fijo de 20 bytes con un puñado
de parámetros (posición inicial, cuántos enemigos, objetivo de
bolitas...). No hay capas, no hay entidades con posición propia fuera
de las tablas de item ya documentadas en `manual_motor_colision_ia.md`
— los enemigos "aparecen" siempre en el mismo punto de referencia del
nivel, nunca en coordenadas propias por nivel.

**El dato más sorprendente**: el juego real tiene **15 niveles**, no
14 — el nivel 15 (antes llamado "nivel oculto" en análisis previos de
este mismo proyecto) es alcanzable en partida normal, completando el
14. Es un cuerpo de nivel más, sin ningún truco especial para llegar a
él — ver §4.

## 2. Arquitectura general

```
$2BF3 ─── REGISTRO_NIVEL (20 bytes)     -- copia de trabajo del registro del nivel actual (§3)
$5885 ─┬─ CARGAR_NIVEL / INICIALIZAR_ITEMS_NIVEL -- cargador (§5), llamado desde INICIO/VERIFICAR_FIN_NIVEL
       └─ INICIALIZAR_PARCIAL_ITEMS_NIVEL -- 2º punto de entrada, solo limpia pista tanque/avion
$59A9 ─── TABLA_NIVELES (320 bytes = 16 registros x 20 bytes)  -- catalogo de niveles (§4)
$5B8C..  ─── CUERPO_L01..CUERPO_L15 + CABECERA_4AFC/_4B5C/_50BC -- los datos reales (§4.2)
$8FD4  ─── VERIFICAR_FIN_NIVEL (madmix1.asm) -- detecta objetivo cumplido, avanza de nivel (§6)
$6045 ─── GESTIONAR_CICLO_NIVELES -- modo "DEMO" del menu: reproduce 4 niveles de muestra (§7)
```

## 3. El registro de nivel (20 bytes)

Cada nivel se describe con un registro de 20 bytes. Al cargar, se
copia entero a una zona de trabajo fija (`REGISTRO_NIVEL`, `$2BF3`) —
los valores que hay "de fábrica" en esa zona en el `.BIN` compilado son
solo la instantánea del último nivel procesado en tiempo de
compilación, sin significado propio (la partida real siempre los
sobreescribe al cargar el primer nivel).

| Offset | Campo | Contenido |
|---|---|---|
| 0-1 | `REGISTRO_NIVEL_CUERPO_PTR` | puntero al CUERPO del nivel (la rejilla de losetas, filas variables) |
| 2-3 | `REGISTRO_NIVEL_CABECERA_PTR` | puntero a la CABECERA fija (3 filas, compartida entre varios niveles) |
| 4-5 | `REGISTRO_NIVEL_PIE_PTR` | duplicado del anterior — la cabecera se copia TAMBIÉN debajo del cuerpo, de "pie" |
| 6 | `REGISTRO_NIVEL_FILAS` | número de filas del cuerpo (varía por nivel, 15-23) |
| 7 | `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` | flag de aviso de HUD ("EN LA PRÓXIMA... EXTRA") |
| 8 | `REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` | nº de fantasmas activos este nivel (máx. 8, ver `manual_motor_colision_ia.md` §6.1) |
| 9 | `REGISTRO_NIVEL_CONTADOR_MARICOCOS` | nº de mariquitas activas (máx. 2, §6.2) |
| 10 | `REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS` | nº de "repugnantosos" activos (máx. 8, §6.3) |
| 11 | `REGISTRO_NIVEL_DURACION_PARPADEO` | duración en fotogramas del parpadeo de la bola/pista especial |
| 12 | `REGISTRO_NIVEL_LOSETA_COMODIN` | loseta real que sustituye al comodín `$3C` del cuerpo (§5) |
| 13-14 | `REGISTRO_NIVEL_FILA_COLUMNA` | fila/columna de un punto de referencia inicial (posición de "aparición" de los items) |
| 15-16 | `REGISTRO_NIVEL_POSICION_COMECOCOS` | posición inicial del comecocos/cámara — queda viva toda la partida en `$2C02` |
| 17 | `REGISTRO_NIVEL_ICONO_HUD` | código de carácter/icono del HUD para este nivel |
| 18-19 | `REGISTRO_NIVEL_OBJETIVO_BOLAS` | objetivo de "bolitas a comer" para completar el nivel (§6) |

## 4. `TABLA_NIVELES` — el catálogo de 15 niveles

**320 bytes = 16 registros de 20 bytes** (`$59A9`-`$5AE9`). El primero
(índice 0) es un **registro muerto**, duplicado exacto del nivel 1 —
nunca se alcanza en juego normal (`NIVEL_ACTUAL` arranca en 1, nunca
en 0). Los índices 1-15 son los 15 niveles reales; el 15 es el "nivel
oculto" de análisis previos, confirmado alcanzable completando
normalmente el 14 (`VERIFICAR_FIN_NIVEL`, §6, no hace ninguna
distinción especial al llegar ahí).

Reescrita como tabla de datos nativa en el propio ensamblador
(`DW CUERPO_L01, CABECERA_50BC, CABECERA_50BC` etc.) en vez de un
`INCBIN` de tabla binaria — los punteros de cuerpo/cabecera son
etiquetas reales, el propio ensamblador resuelve la dirección
correcta en vez de tener que mantener hex sueltos sincronizados a
mano.

### 4.1 Los ficheros de datos: 13 cuerpos + 3 cabeceras compartidas

`data/niveles/*.bin` — un fichero por bloque único de datos:

- **13 cuerpos** (`body_l01.bin` a `body_l15.bin`, saltando el
  duplicado del nivel 0): la rejilla variable de cada nivel, 15-23
  filas × 32 columnas.
- **3 cabeceras compartidas** (`header_50bc.bin`, `header_4afc.bin`,
  `header_4b5c.bin`, 96 bytes cada una = 3 filas × 32), reutilizadas
  por varios niveles a la vez — economía de memoria: son los bordes
  superior/inferior del laberinto, y varios niveles comparten
  exactamente el mismo borde:
  - `CABECERA_50BC`: niveles 0, 1, 2, 3, 6, 9, 10, 11, 14 (9 usos)
  - `CABECERA_4AFC`: niveles 4, 5, 7, 12, 13 (5 usos)
  - `CABECERA_4B5C`: nivel 8 (1 uso)

Cada byte de la rejilla es un **índice de loseta** (bits 0-6, ver
`data/tiles/*.til`, catálogo 00-90) con el **bit 7** de significado no
confirmado en tiempo de ejecución (`CARGAR_NIVEL` lo borra siempre al
copiar al buffer activo) pero SÍ presente en los binarios originales
— por eso el formato de texto de `mmlvl_tool.py` lo conserva byte a
byte en vez de descartarlo.

### 4.2 El comodín `$3C` y la alternancia por "vueltas"

Al copiar el cuerpo, `CARGAR_NIVEL` sustituye cada loseta con valor
`$3C` (60, el "comodín") por el valor real fijado en
`REGISTRO_NIVEL_LOSETA_COMODIN` (offset 12) — así un mismo patrón de
cuerpo puede lucir distinto según el nivel sin duplicar datos. La
sustitución **no es incondicional**: si es la primera vuelta completa
al ciclo de 15 niveles (`CONTADOR_VUELTAS_NIVELES=0`), los comodines
se copian tal cual, SIN sustituir; en vueltas posteriores, se
sustituyen en un patrón alternante (uno sí, uno no, según la paridad
del recuento de comodines encontrados comparada con el número de
vuelta) — variedad visual en partidas largas que dan más de una vuelta
completa al ciclo de niveles.

## 5. Cargando un nivel: `CARGAR_NIVEL` paso a paso

Llamado desde `INICIO`/`VERIFICAR_FIN_NIVEL` (`madmix1.asm`) cada vez
que hace falta un nivel nuevo:

1. Localiza el registro de `NIVEL_ACTUAL` en `TABLA_NIVELES` (20 bytes
   × número de nivel) y lo copia entero a `REGISTRO_NIVEL` (§3).
2. Copia la cabecera (96 bytes) al buffer de nivel activo
   (`$FC50` — ver nota de bug más abajo), **arriba** del cuerpo.
3. Copia el cuerpo (`REGISTRO_NIVEL_FILAS` × 32 bytes), limpiando el
   bit 7 ("comido") de cada loseta y aplicando la sustitución de
   comodín (§4.2).
4. Copia la MISMA cabecera otra vez, **debajo** del cuerpo (de "pie") —
   el laberinto queda simétrico arriba/abajo con el mismo borde.
5. Resetea `CONTADOR_BOLAS_COMIDAS` a 0, calcula la dirección VRAM del
   punto de referencia inicial (`POSICION_PARPADEO_BOLA`), limpia
   todos los flags de modo especial, restaura el color de HUD por
   defecto, fija la posición de cámara a `$1018`, y llama a
   `INICIALIZAR_ITEMS_NIVEL` (§5.1).

**Bug conocido, corregido en la v2.0**: el buffer de nivel activo es
`$FC50` en el código reconstruido — la v1.0 original de 1987 usaba
`$FC60` en los 5 sitios donde esta constante aparece grabada como
número mágico (2 en `madmix1.asm`, 3 en `madmix_scr.asm`), un bug real
que rompía el contador de bolitas del nivel 13. La v2.0 (reedición
CAS/ROM de 2013) lo corrigió desplazando el buffer 16 bytes antes; es
la **única** desviación deliberada de la reproducción byte a byte de
la v1.0 original en todo este proyecto — todo lo demás sigue siendo la
v1.0 tal cual, bugs incluidos. Ver `FINDINGS.md` para el detalle
completo.

### 5.1 `INICIALIZAR_ITEMS_NIVEL` — reaparición de enemigos e items

Coloca las 3 tablas de item activo (`TABLA_ITEMS_PELMAZOIDE`,
`TABLA_ITEMS_MARICOCO`, `TABLA_ITEMS_REGPUNANTOSO` — ver
`manual_motor_colision_ia.md` §6) en el punto de referencia
(`REGISTRO_NIVEL_FILA_COLUMNA`), limpiando sus campos de modo/fase —
"vuelven a aparecer" todos en el mismo sitio de salida. También limpia
la cola de avisos/destellos (`TABLA_RANURAS_AVISO`) y resetea
dirección/temporizadores de movimiento (salvo con el modo "herramienta"
activo, que arranca con un valor especial de 14). Segundo punto de
entrada, `INICIALIZAR_PARCIAL_ITEMS_NIVEL`, solo limpia la tabla de
pista tanque/avión — usado al salir de esos modos especiales sin
repetir el resto del reseteo.

**Ese punto de referencia es siempre la casa de los fantasmas**:
verificado cruzando el valor de `REGISTRO_NIVEL_FILA_COLUMNA` de cada
nivel contra su propio cuerpo — el catálogo de losetas tiene una
estructura dedicada "puerta_fantasmas_inicio_izquierdo/derecho"
(`$50`/`$51`, con la loseta de línea eléctrica `$38` en el centro, no
transitable por estos items) que marca visualmente la casa en el
mapa. Comprobado en el nivel 1 (columna 12 exacta, calculada y real) y
en el nivel 2 (columna 16 exacta), con un desfase de fila consistente
de 1 (los items aparecen justo debajo de la puerta, nunca sobre la
loseta bloqueada del centro). Mismo patrón que el Pac-Man original —
todos los fantasmas nacen del mismo sitio —, extendido aquí a los 3
tipos de item, no solo los fantasmas.

## 6. Cómo se detecta el fin de nivel: `VERIFICAR_FIN_NIVEL`

Comprobado **cada frame** dentro del bucle principal
(`madmix1.asm`, ver `FLUJO_PROGRAMA.md` §4): compara
`CONTADOR_BOLAS_COMIDAS` contra `REGISTRO_NIVEL_OBJETIVO_BOLAS`. Si no
coincide, el nivel sigue en curso. Si coincide:

1. Incrementa `NIVEL_ACTUAL`. Si llega a 16 (es decir, se acaba de
   completar el nivel 15), lo resetea a 1 e incrementa
   `CONTADOR_VUELTAS_NIVELES` (§4.2) — el ciclo de 15 niveles vuelve a
   empezar. Si no (incluye el caso de completar el 14 y pasar al 15),
   simplemente continúa con el siguiente registro.
2. Dispara el destello de icono/color del HUD, copia el flag de vida
   extra del nuevo registro, y salta a `PANTALLA_PRESENTACION_NIVEL`
   (recarga el HUD para el nuevo nivel, que a su vez desemboca en
   `CARGAR_NIVEL`).

**Qué cuenta como "bolita"**: no solo las bolitas normales — las
flechas de dirección forzada TAMBIÉN incrementan
`CONTADOR_BOLAS_COMIDAS` al pisarlas (ver
`manual_motor_colision_ia.md` §4), así que el objetivo real de un
nivel mezcla ambos tipos de loseta.

## 7. El modo "DEMO" del menú: `GESTIONAR_CICLO_NIVELES`

Distinto de jugar de verdad: el menú principal ofrece una opción
"DEMO" que reproduce, sin intervención del jugador, **4 niveles de
muestra** de una tabla propia (`TABLA_CICLO_NIVELES`, `$60D0`, 4
entradas `[nivel, puntero_a_guion]`) — no los 15 niveles completos.
Para cada uno: fija `NIVEL_ACTUAL`, carga el nivel (mismo
`CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL` que en juego real), y
reproduce un **guion de demo** — una secuencia de pares
`[duración en fotogramas, dirección simulada]` terminada con dirección
`$FF`, que sustituye a la lectura real de teclado/joystick en
`MOTOR_MOVIMIENTO_COLISION` mientras el ciclador está activo (ver
`manual_motor_colision_ia.md` §3, paso 1).

Los guiones viven en `data/demos/*.dem` (binario, formato de pares
byte a byte, sin herramienta de edición dedicada en este proyecto —
son datos de grabación, no algo pensado para editarse a mano). De los
10 guiones que existen en el binario original, solo 4 están
referenciados desde `TABLA_CICLO_NIVELES` (niveles 1, 2, 4 y 5); los
otros 6 (`_sinref`) no tienen ningún puntero que los alcance — datos
huérfanos, conservados tal cual por fidelidad byte a byte con el
original.

## 8. Herramienta: `tools/mmlvl_tool.py`

```
py tools/mmlvl_tool.py disasm fichero.bin fichero.txt   # binario -> rejilla de texto editable
py tools/mmlvl_tool.py asm fichero.txt fichero.bin      # texto -> binario (para recompilar el juego)
py tools/mmlvl_tool.py roundtrip fichero.bin            # verifica que disasm+asm da el mismo binario
py tools/mmlvl_tool.py roundtrip-all carpeta/           # lo mismo para todos los .bin de una carpeta
py tools/mmlvl_tool.py check-bolitas fichero.txt NIVEL  # cuenta bolitas del .txt y compara contra
                                                          # el objetivo real de ese nivel en TABLA_NIVELES
```

El formato de texto: cada celda es el byte crudo en **hex de 2
dígitos** (no un mnemónico como en los ficheros de sonido — aquí no
hay un lenguaje de comandos, solo índices de loseta), organizado como
una rejilla de `filas × 32 columnas` con un aviso de cabecera repitiendo
la advertencia de tamaño fijo. `check-bolitas` es la comprobación más
útil al editar un nivel: lee el objetivo real directamente de
`TABLA_NIVELES` en `madmix_scr_body.asm` (sin fichero de manifiesto
aparte que se pueda desincronizar) y cuenta las losetas "suelo con
bola" (`$2D`/`$2E`/`$2F`, con el bit 7 enmascarado) del `.txt` — si no
coinciden, el nivel es infinal (compilaría sin error, pero el nivel
nunca terminaría de jugarse).

> ⚠️ **Límite real de edición** (mismo patrón que sonido, ver
> `manual_driver_sonido.md` §9): cada `.bin` se compila con `INCBIN` a
> una dirección FIJA. Puedes cambiar el VALOR de cualquier loseta sin
> problema. **NO añadas ni quites filas ni columnas**: el tamaño es
> FIJO — si cambia, todo lo que va detrás en `madmix_scr.asm`/
> `madmix1.asm` se desplaza de dirección. El juego compilaría sin
> ningún error pero cargaría niveles o datos incorrectos en tiempo de
> ejecución.

## 9. Confianza y pendientes

La estructura del registro de nivel, la tabla de 16 entradas, y el
mecanismo de carga/detección de fin están verificados al 100% contra
el desensamblado real. Puntos abiertos:

- El significado exacto del bit 7 de cada loseta del cuerpo (se borra
  siempre al cargar, presente en los datos originales — candidato a
  "flag de edición" del equipo original, sin confirmar).
- El bit 5 sondeado en `VERIFICAR_ENTRADA` justo después de completar
  un nivel (candidato a tecla de pausa/confirmación, sin identificar
  del todo).
- El detalle exacto de la alternancia de sustitución del comodín entre
  vueltas (§4.2) — mecánica confirmada, pero no verificada visualmente
  jugando varias vueltas completas seguidas.

## 10. Para seguir profundizando

- `FINDINGS.md` — todas las secciones relacionadas con niveles, el
  registro de 20 bytes campo a campo, y el bug del nivel 13, en orden
  cronológico.
- `manual_motor_colision_ia.md` — qué hacen los enemigos/items una
  vez que el nivel ya está cargado (este manual documenta solo cómo se
  construye y carga el nivel, no la lógica de juego dentro de él).
- `niveles.html`/`editor_niveles.html` (recursos) — visualización de
  los 15 niveles ya reconstruidos.
