# Manual del subsistema gráfico — Mad Mix Game (MSX1, VDP TMS9918 en SCREEN 2)

*[Read this in English](manual_subsistema_grafico.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Fuente: `madmix1.asm` (motor de actores, API de VDP, buffer de
> losetas, scroll) y `madmix_scr.asm` (portada, color de pantalla,
> marco de caramelo). Para la crónica de cómo se descubrió cada pieza,
> ver `FINDINGS.md`; este documento asume que ya está todo identificado
> y explica el resultado final de forma ordenada.

## 1. Qué es esto y qué NO es

Este manual explica cómo el juego pone gráficos en pantalla: el modo
de vídeo que usa, cómo dibuja el laberinto y su scroll, y — el punto
más importante, porque sorprende a quien conoce el hardware del MSX —
cómo dibuja al comecocos, los fantasmas y el resto de personajes.

**Punto central del manual**: el juego usa `SCREEN 2` (modo bitmap del
TMS9918, el mismo VDP del MSX1) pero **no usa en ningún momento los
sprites hardware del chip** — no se ha encontrado ni una sola
escritura a la tabla de atributos de sprites ni al generador de
patrones de sprites en todo el código transcrito (`FILVRM`/`LDIRVM`
solo tocan la tabla de patrones y la tabla de color del modo bitmap).
En su lugar, el motor de actores (§4) compone cada personaje a mano —
máscara + patrón, con desplazamiento sub-pixel bit a bit — directamente
sobre la tabla de patrones, exactamente el mismo enfoque de "blitting"
con máscaras AND/OR que usaría un juego de ZX Spectrum (que ni
siquiera tiene sprites hardware). Es la explicación técnica real detrás
de la sensación, jugando, de que el motor "se comporta como un
Spectrum" — no es una impresión vaga, es literalmente el mismo
algoritmo de composición.

**Tampoco** es un motor de tiles con hardware de scroll: el MSX1 no
tiene ningún asistente de scroll en el VDP (a diferencia de consolas
contemporáneas con "fine scroll" en hardware), así que el scroll de 4px
de la cámara (§6) también es software puro — desplazamiento de nibbles
sobre un buffer en RAM del Z80, volcado a VRAM completo cada frame.

## 2. El hardware: TMS9918 en `SCREEN 2` (Graphics I)

Tres tablas relevantes en VRAM (16 KB direccionables, acceso vía dos
puertos de E/S: `$98`=datos, `$99`=control/dirección):

| Zona VRAM | Tamaño | Contenido |
|---|---|---|
| `$0000`-`$17FF` | 6144 bytes | **Tabla de patrones**: el bitmap real, 8 bytes (filas) por celda de carácter, 256 patrones × 3 "tercios" de pantalla (cada tercio con su propia copia de los 256 patrones — peculiaridad de `SCREEN 2`, cada bloque de 8 filas de carácter tiene su generador de patrones independiente) |
| `$1800`-`$1AFF` | 768 bytes | **Tabla de nombres**: qué patrón dibujar en cada una de las 32×24 celdas de la pantalla |
| `$2000`-`$37FF` | 6144 bytes | **Tabla de color**: 1 byte por CADA FILA de cada patrón (no por celda completa) — nibble alto = tinta, nibble bajo = fondo; confirmado exacto: `TABLA_COLOR_MARCO_CARAMELO` son 768 celdas × 8 bytes = 6144 |

**El truco de la "tabla de nombres identidad"**: en vez de usar la
tabla de nombres para indexar patrones de forma indirecta (como haría
un tileset tradicional), el juego escribe `nombre = índice de patrón`
literal (0, 1, 2... 255, repetido en los 3 tercios) — ver
`DIBUJAR_PORTADA` (§7) y el motor principal. Esto convierte
efectivamente `SCREEN 2` en un **bitmap direccionable por patrón**: el
juego dibuja directamente escribiendo bytes en la tabla de patrones
(indexada por número de patrón = posición en pantalla), sin tener que
mantener sincronizada una tabla de nombres aparte. Es la misma
filosofía que un framebuffer plano, adaptada a la estructura de
`SCREEN 2`.

## 3. La API de VDP propia (no la BIOS del MSX)

El juego reimplementa a mano las 3 rutinas clásicas de la BIOS de MSX
(`FILVRM`/`LDIRVM`/`SETWRT`), en vez de llamarlas vía `CALL` a ROM —
razón probable: evitar la sobrecarga de una llamada a BIOS en rutinas
que se ejecutan muchas veces por frame. Confirmadas byte a byte,
`madmix1.asm`, `$8931`-`$8960` (sin ningún hueco entre ellas):

- **`SETVRAM`** (equiv. `SETWRT`): fija el puntero de escritura del
  VDP a la dirección en `HL` — byte bajo al puerto `$99`, byte alto
  (enmascarado a 14 bits) `OR $40` (comando "fijar puntero de
  escritura") también al puerto `$99`, con un retardo de 2 `EX (SP),HL`
  que exige el VDP tras el comando.
- **`FILVRM`**: rellena `BC` bytes de VRAM desde `HL` con el byte fijo
  `A` — bucle anidado de `OUT ($98),A` (256×256 iteraciones máximo).
- **`LDIRVM`**: copia `BC` bytes de RAM (`HL`) a VRAM (`DE`), byte a
  byte con `OUT ($98),A`.

Todo el resto del subsistema gráfico se apoya en estas 3. La portada
(§7) y el arranque de pantalla usan además escritura de registro del
VDP directa: `OUT ($99),valor` seguido de `OUT ($99),número_registro OR $80`.

## 4. El motor de actores SIN sprites hardware: `MOTOR_ACTORES`

Este es el corazón del subsistema — llamado para dibujar CADA
personaje (comecocos, fantasmas, mariquita, repugnantoso, pistas de
tanque/avión, iconos de HUD...) cada vez que hace falta redibujarlo.
Hasta 10 actores activos simultáneos por frame (`$8437`, contador),
indexando una tabla de 64 sprites-fuente (`PTR_TABLA_SPRITES`).

**El algoritmo, en 2 pasadas separadas** (primera pasada dentro de
`MOTOR_ACTORES` mismo; segunda, `COMPONER_ACTORES_EN_BUFFER`, ver más
abajo):

1. **Filtrado y recorte**: descarta el actor si ya hay 10 activos, si
   el índice de sprite no es válido, o si su columna cae fuera de la
   ventana visible (`< 4` o `≥ 116`). Calcula el recorte vertical
   contra el borde de cámara (`TABLA_MASCARA_RECORTE_BORDE`, indexada
   por columna) y reserva un registro de 12 bytes en un array de
   actores (`$92E3`).
2. **Volteo**: si el sprite requiere volteo horizontal (2 flags
   independientes en los bits 6-7: orden de bits dentro de cada byte,
   y orden de los bytes de cada fila), lo aplica ANTES de dibujar,
   sobre una copia temporal del patrón — `INVERTIR_BITS_PATRON_ACTOR`
   (espejo bit a bit clásico, `RLC`/`RRA` × 8 por byte) e
   `INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (intercambia bytes desde los dos
   extremos hacia el centro). Es el mismo mecanismo que usan los
   fantasmas/mariquita/repugnantoso para reutilizar un único sprite
   "derecha" como "izquierda" (ver `manual_motor_colision_ia.md` §6).
3. **Desplazamiento sub-pixel + mezcla con máscara**: el motor MSX no
   tiene desplazamiento de sprite por hardware más fino que 1 píxel de
   carácter — aquí se implementa desplazamiento de **0 a 7 bits**
   (sub-carácter) rotando el patrón bit a bit entre registros (`RRA`/
   `RR`/`RL` encadenados, alternando bancos con `EXX` para procesar 2
   filas a la vez) y componiéndolo con el fondo mediante **máscara
   AND** (conserva el fondo donde el sprite es transparente) seguida
   de **OR** (aplica el patrón del sprite) — el algoritmo de "mask +
   bitmap" clásico de blitting sin hardware, con dos variantes casi
   idénticas según la dirección del desplazamiento
   (`DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`).
4. **Las máscaras de recorte no salen de una tabla estática propia**:
   `CALCULAR_DIRECCION_MASCARA_ACTOR` calcula su dirección como
   `$DC00 + (posición_en_pantalla / 8)` — y `$DC00` **no es una tabla
   dedicada**, es un subtramo de `TABLA_RLE_MARCO_CARAMELO` (la tabla
   de compresión RLE del marco de caramelo del HUD) **reutilizado con
   un segundo propósito** al mismo tiempo: economía de memoria típica
   de un MSX1 de 64KB. Confirmado real (coincide con volcados de RAM
   en vivo), no un artefacto de análisis.
5. **Dos pasadas por diseño**: `MOTOR_ACTORES` no escribe el resultado
   final directo — copia las 3 máscaras/patrón de cada fila a un
   **cursor en RAM baja** (`$0500` en adelante, `CAPTURAR_MASCARAS_ACTOR`),
   y es una segunda función, `COMPONER_ACTORES_EN_BUFFER`, la que
   recorre ese cursor y aplica el `AND`/`OR` final sobre el buffer de
   pantalla — con **código automodificable**: los 6 operandos de
   máscara de sus 6 iteraciones (`ida` y `vuelta`, en pares idénticos
   1=6/2=5/3=4) se reescriben en caliente con los 3 bytes de recorte de
   cada actor antes de procesarlo. Nota de investigación: no se ha
   encontrado el `CALL`/`JP` real que invoca `COMPONER_ACTORES_EN_BUFFER`
   en el código ya transcrito — su mecánica está confirmada, su
   disparador no.

## 5. El sistema de losetas del laberinto

A diferencia de los actores (que se recalculan y redibujan activamente
cada frame que hace falta), el laberinto es un **buffer de trabajo en
RAM del Z80** (`BUFFER_LOSETAS_TRABAJO`, `$DE04`, NO en VRAM) que se
va actualizando y se vuelca a VRAM completo una vez por frame:

- **`MAPEAR_LOSETA_A_GRAFICO`**: dada una posición de cámara/loseta,
  calcula la dirección real del patrón gráfico correspondiente
  (`GRAFICOS_LOSETAS` + índice derivado del tipo de loseta vía
  `TABLA_TIPOS_LOSETA`) y lo copia (2 palabras = 4 bytes por celda de
  carácter, repetido) al buffer de trabajo. Es la rutina que consume
  `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` para redibujar una franja
  completa de fondo tras mover la cámara.
- **`ACTUALIZAR_VRAM_FRAME`** (llamada una vez por frame desde
  `GESTIONAR_FRAME`, la ISR de VBLANK — ver `FLUJO_PROGRAMA.md`
  §5.10): al final de su trabajo (icono de HUD, zonas de destello),
  vuelca `BUFFER_LOSETAS_TRABAJO` completo a la tabla de patrones de
  VRAM (`ZONA_PATRON_VRAM_LABERINTO`, `$0220`) — 18 filas × 8 columnas
  de carácter, byte a byte vía `OUT ($98),B` directo (más rápido que
  llamar a `LDIRVM`). **Confirma un punto arquitectónico clave**: el
  scroll (§6) NUNCA escribe en VRAM directamente — solo prepara el
  buffer en RAM; es esta función la única que copia ese buffer a la
  VRAM real.
- **Redibujado incremental vs. total**: `REDIBUJAR_LOSETA_BUFFER_VRAM`
  actualiza una sola loseta (16×16px) en el buffer, bien por llamada
  directa o encolada (`APILAR_PETICION_REDIBUJADO`/
  `VACIAR_COLA_REDIBUJADO`, vaciada cada frame por `GESTIONAR_FRAME`).
  `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` hace un redibujado TOTAL
  (36 pasadas de `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) — usado al
  arrancar/cambiar de nivel, no cada frame.

## 6. El scroll por software (4px, sin hardware de scroll)

Resumen — ver `FLUJO_PROGRAMA.md` §4 y `manual_motor_colision_ia.md`
para el despachador completo de dirección. El mecanismo gráfico en sí:

`SCROLL_ARRIBA`/`SCROLL_ABAJO` desplazan las 144 filas de
`BUFFER_LOSETAS_TRABAJO` 4 píxeles verticales encadenando **24 `RLD`/`RRD`
por fila** (la instrucción Z80 de rotación de nibble a través de
`(HL)` y el nibble bajo de `A`) — un truco clásico de 8 bits para
desplazar contenido medio-byte sin desplazamiento de bit a bit
explícito. `SCROLL_IZQUIERDA`/`SCROLL_DERECHA` (`APLICAR_DESPLAZAMIENTO_LATERAL`)
hacen el equivalente horizontal. Las 4 rutinas terminan en
`SCROLL_LOSETA_BUFFER_VRAM`, que decide entre 2 "fases" de copia
(`COPIAR_LOSETA_FASE_A`/`_B`) según la alineación de byte resultante.
El resultado queda en `BUFFER_LOSETAS_TRABAJO` — el volcado real a
VRAM lo hace `ACTUALIZAR_VRAM_FRAME` (§5), no el scroll en sí.

## 7. El color: portada comprimida, marco de caramelo, y zonas de destello

**La portada** (`DIBUJAR_PORTADA`, `madmix_scr.asm`, punto de entrada
real tras la reubicación): apaga pantalla, escribe la tabla de
nombres identidad, vuelca el bitmap SIN comprimir (`PORTADA_PATRON`,
6144 bytes, la tabla de patrones completa) y luego **descomprime** el
color desde un formato empaquetado: 768 grupos, cada uno con un byte
de control (0 = color 0/0 directo; si no, dos índices de 4 bits
empaquetados en el byte) que indexa una paleta de 16 valores
(`PALETA_COLORES_PORTADA`) para componer el byte de color final
(nibble alto/bajo), replicado 8 veces (una columna de carácter
completa). Sistema de compresión propio, no un formato estándar.

**El resto de la pantalla** (marco de caramelo del HUD, color de fondo
del laberinto durante el juego): `APLICAR_COLOR_PANTALLA` (pese a su
nombre, confirmado que aplica el color de TODA la pantalla, no solo el
marco) traduce 768 bytes de `TABLA_COLOR_MARCO_CARAMELO` con
`OBTENER_COLOR_VDP` (compone nibble alto/bajo desde `TABLA_COLORES_VDP`,
la misma tabla de 16 colores VDP que usa `CONSULTAR_COLOR_VDP` en
`madmix1.asm`) y rellena la tabla de color de VRAM completa vía
`FILVRM`. La FORMA del marco (qué patrón dibujar, no su color) la da
`TABLA_RLE_MARCO_CARAMELO` (compresión RLE clásica: pares
`[valor, repetición]`, 870 bytes) — la misma tabla que, reutilizada
por partida doble (§4), sirve de máscara de recorte de actores.

**Zonas de destello del HUD**: `ZONA_COLOR_VRAM_DESTELLO_A`/`_B`
(`$2A80`/`$2B80`, 16 bytes cada una) — coloreadas por `ACTUALIZAR_VRAM_FRAME`
cada vez que cambia `COLOR_ACTUAL`, para el parpadeo de icono/color del
HUD durante los modos especiales (ver `manual_motor_colision_ia.md` §8).

## 8. Direcciones y constantes VRAM relevantes

| Constante | Dirección | Qué es |
|---|---|---|
| — (tabla de patrones) | `$0000`-`$17FF` | bitmap de `SCREEN 2` completo |
| — (tabla de nombres) | `$1800`-`$1AFF` | identidad (nombre=patrón), nunca se toca tras la inicialización |
| `ZONA_PATRON_VRAM_LABERINTO` | `$0220` | destino del volcado de `BUFFER_LOSETAS_TRABAJO` (patrón visible del laberinto) |
| — (tabla de color) | `$2000`-`$37FF` | color de `SCREEN 2` completo, 1 byte por fila de patrón |
| `ZONA_COLOR_VRAM_DESTELLO_A`/`_B` | `$2A80`/`$2B80` | color del icono/destello del HUD (16 bytes cada una) |

## 9. Confianza y pendientes

La mecánica de composición de actores (máscaras, desplazamiento
sub-pixel, doble pasada) está verificada al 100% contra el
desensamblado real y contra volcados de VRAM/RAM en vivo. Puntos
genuinamente abiertos:

- El llamador real de `COMPONER_ACTORES_EN_BUFFER` no está identificado
  en el código ya transcrito (§4).
- El propósito exacto de la variable en `$8435` (constante fija a 3 en
  varios sitios) y de los bits 6-7 usados como selector de mitad
  vertical en `MOTOR_ACTORES` (`$843E`, 144 vs 176) — mecánica
  confirmada, semántica exacta sin cerrar del todo.
- El tramo `$4000`-adyacente de `ACTUALIZAR_VRAM_FRAME` (un `LDIR`
  de RAM a RAM sin efecto observable, `BC=$052B`) — descartada la
  hipótesis de "relleno de temporización" (los ciclos no cuadran),
  propósito real sin confirmar.

## 10. Para seguir profundizando

- `FINDINGS.md` — todas las secciones relacionadas con VDP/VRAM/motor
  de actores, en orden cronológico, con el razonamiento completo de
  cada descubrimiento (búsquese "Zona 0xDC00" para el hallazgo de la
  reutilización de `TABLA_RLE_MARCO_CARAMELO` como máscaras).
- `FLUJO_PROGRAMA.md` §5.1/§5.4 — resumen más corto, en el contexto
  del flujo completo del juego.
- `manual_motor_colision_ia.md` — quién decide QUÉ dibujar y CUÁNDO
  (este manual documenta solo el CÓMO se pone en VRAM).
- `graficos.html`/`niveles.html` (recursos) — catálogo visual de tiles
  y sprites ya identificados, útil como referencia mientras se lee
  este manual.
