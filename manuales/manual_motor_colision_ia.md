# Manual del motor de movimiento/colisión e IA de items — Mad Mix Game (MSX1)

*[Read this in English](manual_motor_colision_ia.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Fuente: `madmix_scr.asm`, región `$2CA0`-`$5904` aprox. (motor de
> colisión, tabla de despacho de loseta, subsistema de items
> especiales). Para la crónica de cómo se descubrió cada pieza, ver
> `FINDINGS.md`; este documento asume que ya está todo identificado y
> explica el resultado final de forma ordenada.

## 1. Qué es esto y qué NO es

Este es el subsistema que decide, **cada frame**, hacia dónde se mueve
el comecocos y qué pasa cuando pisa algo — y, por separado pero
íntimamente ligado, la "IA" de los 3 tipos de entidad que se mueven
por el mapa sin ser el jugador: los fantasmas (`HNDLR_PELMAZOIDE`), la
mariquita (`HNDLR_MARICOCO`) y el "repugnantoso" (`HNDLR_REGPUNANTOSO`).

**No es** un pathfinding real (no hay BFS/A\* ni conocimiento del mapa
completo): cada entidad decide su dirección mirando solo las 4
losetas inmediatamente adyacentes a su posición actual, con una tabla
de sesgo hacia "seguir igual" y un bit aleatorio para desempatar. Es
el mismo tipo de solución barata en CPU que el motor de colisión del
propio jugador (§3) — ambos comparten literalmente la misma tabla de
elección aleatoria por rango de direcciones libres. **Tampoco** hay
distinción de comportamiento "perseguir/huir" por fantasma como en el
Pac-Man original (Blinky/Pinky/Inky/Clyde): las 8 entradas de
`TABLA_ITEMS_PELMAZOIDE` ejecutan el mismo código, con el mismo sesgo
de "acercarse a un punto de referencia fijo ligado a la cámara" — ver
§6 para el matiz importante de qué es realmente ese punto.

## 2. Arquitectura general

```
$2C36 ─── ENLACE_MOTOR_MOVIMIENTO_COLISION      -- trampolin (JR), llamado desde madmix1.asm cada frame
$2CA0 ─┬─ MOTOR_MOVIMIENTO_COLISION              -- decide direccion, alineamiento, modo especial (§3)
       ├─ TABLA_MANEJADORES_LOSETA ($2E3C)      -- 20 punteros, uno por tipo de loseta (§4)
       ├─ CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION ($2E64) -- tipo de loseta 1 paso por delante (con cache)
       ├─ HNDLR_SUELO_NORMAL / HNDLR_BOLITA_NORMAL / HNDLR_BOLITA_CLAVADA / HNDLR_AUTOCOCO_* / ... -- 20 manejadores (§4)
       └─ bucle de pista tanque/avion (dentro de MOTOR_MOVIMIENTO_COLISION, al final)
$5278 ─┬─ MOTOR_MOVIMIENTO_ITEM                  -- motor de movimiento GENERICO de item (§5), usado por los 3 tipos
       ├─ CALCULAR_POSICION_VRAM_ITEM ($53A2)   -- 2º punto de entrada: solo posicion visible, sin mover
       └─ CONSULTAR_LOSETA_LIBRE_DIRECCION ($5414) -- ¿hay loseta transitable 1 paso en esta direccion?
$51FE ─── HNDLR_PELMAZOIDE                       -- IA de fantasmas, hasta 8 activos (§6.1)
$5478 ─── GENERAR_ALEATORIO                      -- generador pseudoaleatorio compartido (LFSR simplificado)
$5487 ─── HNDLR_MARICOCO                         -- IA de mariquita, hasta 2 activas, REGENERA bolitas comidas (§6.2)
$5574 ─── HNDLR_REGPUNANTOSO                     -- IA de "repugnantoso", hasta 8 activos, PLANTA bolas clavadas (§6.3)
$566A ─── AVISAR_PROXIMIDAD_PISTA                -- aviso de pista tanque/avion cercana (§7)
$56CA ─── ARMAR_AVISO_DESTELLO / ACTUALIZAR_DESTELLO_ITEMS -- cola de "flashes" de animacion (§7)
$57D8 ─── ACTIVAR_EFECTO_ITEM                    -- dispara modos especiales / puntos al pisar un item (§8)
```

Todo esto vive en `madmix_scr.asm` (la "pantalla de carga", que en
realidad contiene mucho más que gráficos — ver `README.md`), a
diferencia del motor de actores/render (`madmix1.asm`, ver
`FLUJO_PROGRAMA.md` §5.1) y del driver de sonido (`manual_driver_sonido.md`).

## 3. El motor de colisión: `MOTOR_MOVIMIENTO_COLISION`

Se llama **una vez por frame** desde el bucle principal
(`BUSCAR_COLUMNA_HUD`/`BUCLE_PRINCIPAL_JUEGO`, `madmix1.asm`) a través
del trampolín `ENLACE_MOTOR_MOVIMIENTO_COLISION` (`$2C36`, 2 bytes,
`JR MOTOR_MOVIMIENTO_COLISION`). Hace, en orden:

1. **Lee dirección**: si el ciclador de niveles de muestra está activo
   (`(INDICE_CICLO_NIVELES)≠0`, modo demo) usa la dirección
   precalculada del guion; si no, llama a `LEER_ENTRADA` (teclado/
   joystick real).
2. **Filtra por alineamiento**: una dirección solo es válida si el
   comecocos está alineado a loseta en el eje perpendicular a ella (no
   se puede girar a mitad de pasillo). Si la dirección pedida no es
   válida, se mantiene la del frame anterior.
3. **Consulta la loseta un paso por delante** en la dirección elegida
   (`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`, con caché de columna
   para no repetir el cálculo si no cambió). Si el tipo es "sin efecto"
   (0), reintenta con la dirección del frame anterior por si esa sí
   pisa algo especial.
4. **Modo especial activo** (`MODO_ESPECIAL_ACTIVO≠0`): mientras dura
   un modo especial (bola de poder/hipopótamo/herramienta/tanque-avión),
   el despacho normal por tipo de loseta queda **suspendido por
   completo** — se fuerza tipo 0 (sin efecto). El propio tic del modo
   especial (parpadeo de icono HUD, cuenta atrás, fin de modo) se
   gestiona aparte, en el mismo bloque (`TICK_MODO_ESPECIAL`).
5. **Despacha** al manejador de la tabla de 20 entradas (§4) según el
   tipo de loseta resultante.
6. **Selector de sprite del comecocos**: con la dirección final ya
   decidida, indexa una de 4 subtablas de 20 bytes (`SUBTABLA_DIRECCION_A`
   a `_D`, una por dirección) con un índice rotativo — el valor
   obtenido es el **frame de animación real** (boca abierta/cerrada +
   orientación, con el bit 7 como volteo horizontal) que se pasa a
   `MOTOR_ACTORES` para redibujar. Esto NO es un parámetro de scroll,
   pese a lo que sugería una hipótesis de trabajo anterior — ver
   `FINDINGS.md` para el rastreo completo registro a registro.
7. **Dispara scroll + items + redibujado**: llama a `GESTIONAR_SCROLL`,
   y si el teclado no está bloqueado (`FLAG_ENTRADA_BLOQUEADA=0`),
   ejecuta en orden fijo `HNDLR_PELMAZOIDE` → `HNDLR_MARICOCO` →
   `HNDLR_REGPUNANTOSO` → `ACTUALIZAR_DESTELLO_ITEMS` (siempre) →
   `MOTOR_ACTORES` (redibuja al comecocos).
8. **Bucle de pista tanque/avión**: recorre las 3 entradas de
   `TABLA_PISTA_TANQUE_AVION` y dibuja cada una activa con `MOTOR_ACTORES`
   directamente (esto NO pasa por el sistema de tipos de loseta).

**Pendiente sin cerrar**: hay una asimetría entre pares de dirección
opuestos en `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` — derecha/abajo
avanzan un paso de loseta completo (+4), pero izquierda/arriba solo
restan 1 unidad (puede que ni siquiera cruce un límite de loseta según
la sub-posición actual). No confirmado si es deliberado o un caso sin
explorar del todo — ver `FINDINGS.md`.

## 4. La tabla de despacho por tipo de loseta (`TABLA_MANEJADORES_LOSETA`, 20 entradas, `$2E3C`)

El índice de despacho es directamente el valor de tipo que devuelve
`CONSULTAR_TIPO_LOSETA` (sin desplazamiento). Mapeo tipo → loseta real
→ manejador (cruzado contra `TABLA_TIPOS_LOSETA` de `madmix1.asm` y el
catálogo de `data/tiles/*.til`):

| Tipo | Loseta(s) | Manejador | Efecto |
|---|---|---|---|
| 0 | pared/suelo normal + decorativas sin manejo propio; también tipos 8/9 | `HNDLR_SUELO_NORMAL` | sin efecto de juego (caso general) |
| 1 | suelo_con_bola (bolita normal) | `HNDLR_BOLITA_NORMAL` | come la bolita: +1 punto, cuenta para fin de nivel |
| 2 | suelo_con_bola_clavada (bola fija) | `HNDLR_BOLITA_CLAVADA` | solo con modo "herramienta" (3): la libera (convierte en bolita normal) |
| 3-6 | flecha arriba/abajo/izquierda/derecha | `HNDLR_AUTOCOCO_*` | fuerza esa dirección (si no está ya bloqueada), +2 puntos, cuenta para fin de nivel |
| 7 | pista_tanque_vertical | `HNDLR_PISTA_COCOTANQUE` | (no detallado en este manual, ver `graficos.html`) |
| 8, 9 | línea eléctrica puerta de fantasmas | `HNDLR_SUELO_NORMAL` | genérico; tipo 9 tiene una salida especial (fin de modo "avión") |
| 10 | pista_avion (recto/remates) | `HNDLR_PISTA_COCONAVE` | comparte cola de salida con el tipo 9 |
| 11 | item_suelo_sin_confirmar | `HNDLR_ITEM_SUELO` | (no detallado en este manual) |
| 12 | item_bola_de_poder | `HNDLR_BOLA_PODER` | activa modo especial 1 (bola de poder) |
| 13 | item_hipopótamo | `HNDLR_HIPODOSO` | activa modo especial 2 (hipopótamo) |
| 14 | item_herramienta | `HNDLR_EXCAVATOFONO` | activa modo especial 3 (herramienta) |
| 15, 16 | suelo_sin_bola / muro_ladrillo_suelto / loseta_solida_negra | `HNDLR_SUELO_SIN_BOLA` | sin efecto (bolita ya comida / decorativo) |
| 17, 18, 19 | variantes de trampilla_transicion | `HNDLR_TRAMPILLA_ABIERTA_DERECHA`/`_IZQUIERDA`/`HNDLR_TRAMPILLA_CERRADA` | mecánica de trampilla en L (3 estados) |

**Dos manejadores documentados en detalle, como ejemplo del patrón
general** (todos siguen la misma forma: filtrar por modo especial
actual y por "fase de movimiento" para no contar la misma loseta dos
veces, luego actuar):

- `HNDLR_BOLITA_NORMAL`: solo actúa si NO hay modo especial "fuerte"
  en curso (modo < 2) y la fase de movimiento es la correcta. Marca
  `EVENTO_SONIDO_PENDIENTE=0`, sustituye la loseta por su versión
  "comida" (bit 7), suma 1 punto y incrementa `CONTADOR_BOLAS_COMIDAS`
  (consultado por `VERIFICAR_FIN_NIVEL`, `madmix1.asm`).
- `HNDLR_AUTOCOCO_*` (flechas): igual filtro, más una comprobación de
  que esa dirección no esté ya bloqueada (bitmask en B). Si está
  libre: marca evento, sustituye la loseta, fija `DIRECCION_FORZADA`
  y también cuenta como bolita (+2 puntos, +1 al contador de fin de
  nivel) — las flechas cuentan para completar el nivel además de
  forzar el giro.

## 5. El motor de movimiento genérico de item: `MOTOR_MOVIMIENTO_ITEM`

Los 3 tipos de entidad (§6) comparten **la misma rutina** de decisión
de movimiento — solo cambian la tabla de posiciones activas, la tabla
de sprites de animación, y qué hacen al llegar a su sitio. Recibe en
`IX` el puntero a la entrada activa (formato común de 7 bytes:
`[X, Y, modo/plantado, dirección, subX, subY, fase]`).

**Punto de entrada 1** (`$5278`, uso normal): calcula si el item debe
moverse hacia un **punto de referencia** (`PUNTO_REFERENCIA_CAMARA`,
ver §6.1 para qué es exactamente) y en qué dirección:

1. Si el item está "inactivo/congelado" (`(IX+2)≠0`, ver §6.2/§6.3
   para cuándo se pone ese flag) o hay un modo especial en curso, NO
   calcula dirección de acercamiento nueva — sigue con la que ya tenía.
2. Si no, compara su posición contra el punto de referencia (alineado
   a múltiplos de 4): mismo eje de columna → dirección vertical; mismo
   eje de fila → horizontal; ninguno de los dos → sin dirección clara.
3. **Solo si está alineado a loseta** (posición sub-loseta = 0) se
   permite cambiar de dirección: consulta las 4 direcciones con
   `CONSULTAR_LOSETA_LIBRE_DIRECCION` y arma un bitmask de "libres".
   Si la dirección deseada (paso 2) es una de las libres, la usa —
   pero solo el 100% de las veces si hay un modo especial activo; si
   no, un 50% de las veces (tirada con `GENERAR_ALEATORIO`), para que
   el movimiento no sea perfectamente determinista.
4. Si la dirección deseada NO está libre (o tocó el 50% "no"), elige
   entre TODAS las direcciones libres usando `TABLA_ELECCION_DIRECCION`
   (16 grupos × 8 valores, indexada por bitmask de libres + dirección
   previa + 1 bit aleatorio de desempate) — la misma tabla de sesgo
   "prefiere seguir igual" que describe la cabecera de esa tabla en
   el código (§1).
5. Aplica el movimiento (paso normal `$0100` o medio paso `$0080` si
   `(IX+2)` está activo o hay modo especial "invertido") sumando/
   restando al eje X o Y según el código de dirección final.

**Punto de entrada 2**, `CALCULAR_POSICION_VRAM_ITEM` (`$53A2`, llamado
directo desde `ACTUALIZAR_DESTELLO_ITEMS`): NO mueve nada, solo calcula
si la posición actual del item cae dentro de la ventana visible de
pantalla y, si es así, la dirección VRAM (D/E) donde dibujarlo.

`CONSULTAR_LOSETA_LIBRE_DIRECCION` (`$5414`) considera **transitables**
todos los tipos de loseta salvo 0 (pared/suelo normal), 7 (pista
tanque), 8 (línea eléctrica) y 10 (pista avión) — es decir, estos
items solo se mueven por losetas "con decoración especial" (bolitas,
flechas, trampillas...), nunca por pasillo llano puro. Coherente con
ser entidades del subsistema de items, no comecocos/fantasma en el
sentido del motor principal.

## 6. Los 3 tipos de item activo

Los 3 comparten formato de tabla (7 bytes/entrada) y usan
`MOTOR_MOVIMIENTO_ITEM` para moverse, pero cada uno tiene su propio
manejador, tabla de sprites, y — sobre todo — su propio **efecto al
llegar a su sitio**.

### 6.1 `HNDLR_PELMAZOIDE` — fantasmas (`TABLA_ITEMS_PELMAZOIDE`, hasta 8 activos, `$51FE`)

El único de los 3 que **persigue de verdad**: calcula un "punto de
mira" (`PUNTO_REFERENCIA_CAMARA`) como `posición_de_cámara + (16, 24)`
(offsets `+8`/`+16` sobre columna/fila, módulo 128) — es decir, un
punto fijo relativo a la ventana visible, no la posición exacta del
comecocos. Con un modo especial "invertido" activo (bola de poder), el
punto de referencia se usa **negado**: los fantasmas huyen en vez de
perseguir. El número de fantasmas activos este nivel sale de
`REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (offset del registro de nivel).

Animación: `TABLA_ANIMACION_PELMAZOIDE`, 2 sprites por dirección
(alternados por un índice de fase 0-3), con una variante alternativa
(+20 bytes) cuando el modo especial de "vulnerable" está activo y el
tiempo restante indica que toca parpadear. Tras dibujar, llama a
`ACTIVAR_EFECTO_ITEM` para comprobar colisión con el comecocos en esa
misma posición (§8).

### 6.2 `HNDLR_MARICOCO` — la mariquita (`TABLA_ITEMS_MARICOCO`, hasta 2 activas, `$5487`)

Sprites confirmados por el técnico (jugador original del juego):
`SPR39_MARIQUITA_DER`/`SPR37_..._ABAJO`/`SPR38_..._ARRIBA`. Su efecto:
**regenera bolitas ya comidas**. Cada frame, si su posición y la de la
cámara están alineadas a loseta, comprueba la loseta bajo ella: si es
una de `suelo_sin_bola_1/2/3` (bolita ya comida, índices 63-65), se
marca como candidata a regenerar. Al moverse allí (vía
`MOTOR_MOVIMIENTO_ITEM`) y confirmarse dentro de la ventana visible,
**reescribe la loseta como `suelo_con_bola`** (45-47), decrementa
`CONTADOR_BOLAS_COMIDAS` (vuelve a haber una bolita pendiente) y encola
el redibujado con `EVENTO_SONIDO_PENDIENTE=5`. Tras la primera vez que
se dibuja, fija `(IX+2)=1` — a partir de ahí queda **"plantada"**: deja
de recalcular dirección/perseguir nada, simplemente se queda quieta.

### 6.3 `HNDLR_REGPUNANTOSO` — el "repugnantoso" (`TABLA_ITEMS_REGPUNANTOSO`, hasta 8 activos, `$5574`)

Sprites confirmados: `SPR45-53_REPUGNANTE_DER/ABAJO/ARRIBA` (nombre de
catálogo: "apisonadora"). Estructura idéntica a la mariquita, pero con
el efecto **contrario**: busca bolitas normales SIN comer (índices
45-47) y las convierte en **bolas clavadas/fijas** (48-50) — es el
manejador que "planta" bolas clavadas nuevas en el mapa (liberarlas de
vuelta es tarea del modo especial "herramienta", `HNDLR_BOLITA_CLAVADA`,
§4). A diferencia de la mariquita, fija `(IX+2)=2` **nada más entrar**
al bucle (no al final) y NO toca `CONTADOR_BOLAS_COMIDAS` al plantar —
plantar una bola clavada no cambia cuántas bolitas quedan por comer,
solo las "congela" hasta que se liberen. Usa `EVENTO_SONIDO_PENDIENTE=6`.

Ambos (`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO`) usan el mismo helper
`MAPEAR_COORDENADA_A_DIRECCION_LOCAL` (copia independiente de la
fórmula de `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`) — es uno de los 5
sitios donde vivía el bug real del contador de bolitas del nivel 13 de
la v1.0 original (`$FC60` → `$FC50`, corregido en la v2.0 CAS/ROM, ver
`FINDINGS.md`).

## 7. Pista tanque/avión y la cola de "flashes": aviso, destello, puntos

`TABLA_PISTA_TANQUE_AVION` (`$2C2E`, 3 entradas × 2 bytes, RAM de
trabajo) guarda las posiciones activas de pista — la rellena
`REGISTRAR_PISTA_TANQUE_AVION` (fuera de alcance de este manual). Dos
consumidores distintos:

- **Dibujado real**: el bucle al final de `MOTOR_MOVIMIENTO_COLISION`
  (§3, paso 8) decodifica cada entrada y llama a `MOTOR_ACTORES`
  directamente.
- **Aviso de proximidad**: `AVISAR_PROXIMIDAD_PISTA` (`$566A`) decodifica
  las mismas entradas pero solo para comprobar si el comecocos está
  dentro de un margen **asimétrico** alrededor de la pista (columna
  [-4,+12), fila [-8,+20) — una zona de detección más amplia que la
  propia loseta, para avisar ANTES de pisarla). Si coincide, llama a
  `ARMAR_AVISO_DESTELLO` y marca `EVENTO_SONIDO_PENDIENTE=7`.

`ARMAR_AVISO_DESTELLO` (`$56CA`) es un pool de 4 ranuras
(`TABLA_RANURAS_AVISO`) que arma una animación de "flash" — cada
llamador pasa un byte que es el **offset de entrada** dentro de
`ITEM_TABLE_EFECTOS_DESTELLO` (3 secuencias de losetas con centinela
`$FF`, no un contador genérico), lo que permite que cada evento entre
en un punto distinto de la misma secuencia (animación larga completa,
o solo el "cierre" corto). `ACTUALIZAR_DESTELLO_ITEMS` (llamada siempre,
cada frame, desde `MOTOR_MOVIMIENTO_COLISION`) recorre las 4 ranuras y
dibuja el frame correspondiente con `MOTOR_ACTORES`.

**Identidad de las 3 secuencias** (cruzadas contra `data/tiles/*.til`):
A = flecha derecha + cierre + línea eléctrica; B = (tramo sin
descifrar) + ciclo de los 4 iconos de item/power-up (pista
avión/item suelo/bola de poder/hipopótamo) + cierre; C = item
herramienta + cierre + pista tanque. Hipótesis fuerte sin confirmar
visualmente: es un "flash" de celebración que dibuja iconos reales del
catálogo con el motor de sprites, no una animación decorativa
inventada — la secuencia B en concreto cicla justo por los 4 iconos de
power-up al activarse un modo especial.

**Sin descifrar**: 5 bytes en la unión de las secuencias A/B (offset
40-44, `$0F,$8D,$0E,$0D,$0F`, no encajan con el patrón de "loseta
repetida" del resto) y un patrón repetido de 24 bytes al principio de
la secuencia B (`$03,$00,$06,$80` ×6) — ver `FINDINGS.md`.

## 8. `ACTIVAR_EFECTO_ITEM` — qué pasa al pisar un item especial

Llamada desde los 3 manejadores de §6 tras dibujar cada item (y
también, con el mismo nombre semántico, desde el manejador de tipo de
loseta de bola de poder/hipopótamo/herramienta — no confundir: aquí se
documenta la versión de items móviles). Primer filtro: si ya hay un
modo especial activo, no repite el efecto (evita re-disparo mientras
dura). Segundo filtro: una ventana fija de posición VRAM (fila
[50,62), columna [60,68) — "cerca del centro de pantalla") fuera de la
cual delega directamente en `AVISAR_PROXIMIDAD_PISTA` como fallback.

Dentro de la ventana, según si ya hay un modo especial en curso:

- **Sin modo especial** (o modo 3/herramienta): si el item no está ya
  consumido y no hay demo/ciclo en curso, activa el modo especial
  correspondiente — duración 40 frames si viene del contexto "modo 3",
  45 frames si el item es el hipopótamo — arma el aviso de destello,
  dispara `EVENTO_SONIDO_PENDIENTE=8` y **espera activamente** (bucle
  de sondeo) a que el gestor de sonido lo consuma antes de marcar el
  evento final (13).
- **Modo bola de poder (1) o hipopótamo (2) ya activo**: si el item no
  está ya consumido, suma puntos (`DIBUJAR_MARCADOR_PUNTOS`, con la
  tabla de puntos exacta dependiendo de si es la primera o siguiente
  colisión) y marca `EVENTO_SONIDO_PENDIENTE=7`.

## 9. Variables de estado relevantes (RAM de trabajo, `$2Cxx`)

Ya con nombre real (ver `FLUJO_PROGRAMA.md` §6 para la tabla completa
de variables compartidas del motor principal); las más citadas en este
manual:

| Variable | Qué es |
|---|---|
| `DIRECCION_DE_MOVIMIENTO` | dirección final decidida este frame (bitmask) |
| `DIRECCION_SIN_PROCESAR` | dirección cruda leída de `LEER_ENTRADA`, antes de filtrar |
| `FLAG_DIRECCION_NUEVA` | flanco de pulsación (input nuevo tras soltar) |
| `DIRECCION_FORZADA` | override "sticky" activado por flechas/`CONSULTAR_LOSETA_LIBRE_DIRECCION` |
| `MODO_ESPECIAL_ACTIVO` | temporizador de modo especial en curso (0 = ninguno) |
| `MODO_ESPECIAL` | ID del modo especial actual (1=bola de poder, 2=hipopótamo, 3=herramienta, 8/9=tanque/avión) |
| `MODO_ESPECIAL_CUENTA_ATRAS` | cuenta atrás de duración del modo especial |
| `MODO_ESPECIAL_FLAG` | flag de "cámara invertida" (fantasmas huyen en vez de perseguir) |
| `PUNTO_REFERENCIA_CAMARA` | punto de mira de los fantasmas, cámara+(16,24) |
| `SELECTOR_SPRITE_COMECOCOS` | frame de animación del comecocos (no es scroll, ver §3) |
| `CACHE_COLUMNA_LOSETA`/`CACHE_TIPO_LOSETA` | caché de la última consulta de tipo de loseta |
| `CONTADOR_BOLAS_COMIDAS` | bolitas comidas este nivel (consultado por `VERIFICAR_FIN_NIVEL`) |
| `EVENTO_SONIDO_PENDIENTE` | índice de efecto de sonido a disparar (ver `manual_driver_sonido.md` §7) |

## 10. Para seguir profundizando

- `FINDINGS.md` — todas las secciones relacionadas con el motor de
  colisión y los 3 tipos de item, en orden cronológico, con el
  razonamiento completo de cada descubrimiento.
- `FLUJO_PROGRAMA.md` §5.2/§5.3 — resumen más corto, en el contexto
  del flujo completo del juego (motor de actores, HUD, menú...).
- Puntos genuinamente abiertos, por si alguien quiere continuar:
  - La asimetría derecha/abajo (+4) vs izquierda/arriba (-1) en
    `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` (§3).
  - Los 5 bytes sin descifrar en la unión de secuencias A/B de
    `ITEM_TABLE_EFECTOS_DESTELLO`, y el patrón repetido de 24 bytes al
    inicio de la secuencia B (§7).
  - Los manejadores de tipo de loseta no detallados en este manual
    (`HNDLR_PISTA_COCOTANQUE`, `HNDLR_PISTA_COCONAVE`, `HNDLR_ITEM_SUELO`,
    `HNDLR_BOLA_PODER`, `HNDLR_HIPODOSO`, `HNDLR_EXCAVATOFONO`, los 3
    manejadores de trampilla) — mecánica ya trazada en `FINDINGS.md`,
    pendiente de consolidar aquí si hace falta.
