# Mad Mix Game — flujo del programa e inventario de funciones

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial*

Este documento es el complemento de `FINDINGS.md` (que es un **diario
de descubrimientos**, cronológico) organizado por **flujo de
ejecución**: qué llama a qué, en qué orden ocurre todo, y qué hace
cada subsistema. El objetivo final es que el código fuente
(`madmix0_body.asm`/`madmix1_body.asm`/`madmix_scr_body.asm`) llegue a
leerse como si lo hubiera escrito un programador de la época que
documentara bien su trabajo: nombres propios en vez de direcciones
sueltas, y una explicación clara de qué hace cada rutina y por qué.

**Es un documento vivo.** No pretende cubrir las ~650 etiquetas del
proyecto de golpe — se va ampliando sesión a sesión, exactamente como
se ha hecho con `FINDINGS.md`. Lo que sigue es el panorama grande:
arranque, bucle principal y los subsistemas ya bien entendidos. Cada
sección dice explícitamente qué está confirmado y qué es hipótesis o
queda pendiente.

**Reescritura completa** (esta ronda): el documento se había quedado
congelado en una etapa muy temprana del proyecto, con nombres
ingleses/crípticos que llevaban mucho tiempo superados por cientos de
rondas de renombrado ya aplicadas al código fuente real (ver
`FINDINGS.md`). Todo lo que sigue está verificado directamente contra
el código actual, no reconstruido de memoria.

Compañero visual: `recursos/flujo_programa.html` (diagrama del flujo
+ inventario completo y buscable de todas las etiquetas).

## 0. Una etiqueta no es una función — cómo se prioriza el trabajo

Las etiquetas de los ficheros fuente son un batiburrillo: la mayoría
NO son funciones en el sentido de programación estructurada (un
punto de entrada, un `RET`, una responsabilidad clara) — muchas son
simples marcas internas de salto (cabeceras de bucle, casos de una
rama, puntos de salida compartidos) que viven dentro del cuerpo de
otra rutina — la mayoría de estas ya se han convertido a etiquetas
**locales** (`.NOMBRE`, con punto) durante las rondas de renombrado —
y otro grupo grande son etiquetas de **datos** (tiles, sprites,
texto, tablas), no código.

`recursos/flujo_programa.html` §5 mantiene la clasificación
automática (función/interna/dato/sin referencia) filtrable, útil para
triaje al empezar a trabajar en una zona nueva del código.

---

## 1. Panorama en 3 actos

El juego real son **3 ficheros BLOAD** encadenados, cada uno con su
cabecera MSX estándar (`$FE` + start/end/exec), todos generados desde
`src/main.asm` (única pasada de ensamblado, comparten un solo espacio
de símbolos):

1. **`MADMIX.SCR`** (`madmix_scr_body.asm`, carga en `$8800`, se
   auto-ejecuta): dibuja la portada, y contiene además —reubicado
   más tarde a memoria baja, ver abajo— el motor de colisión/movimiento
   (el "bucle principal" de cada frame), el subsistema de activación
   de ítems, el cargador + tabla de los 15 niveles jugables, y el
   menú principal + créditos.
2. **`MADMIX0.BIN`** (`load_disk/madmix0_body.asm`, carga y se
   auto-ejecuta en `$FA00`, 58 bytes): el "relocador". Tiene **dos
   puntos de entrada**:
   - `RELOCATOR` (`$FA00`, el que se auto-ejecuta al cargar):
     guarda la configuración de slot activa (dos copias, una normal
     y otra "retorcida" para el otro punto de entrada), copia `$5500`
     bytes de `$8800` (donde acaba de aterrizar `MADMIX.SCR`) a
     `$1000`, y **ejecuta ese bloque reubicado una única vez**
     (`CALL DIBUJAR_PORTADA`). No dibuja el motor de juego de forma
     permanente — es una operación de arranque puntual.
   - `JUMP_TO_ENGINE` (`$FA2A`, un segundo punto de entrada,
     independiente): restaura la otra configuración de slot guardada
     y salta directo a `$8400` (`JT_INICIO`, el motor real). Invocado
     por un `CALL`/`USR` explícito desde el BASIC orquestador,
     después de cargar también `MADMIX1.BIN`.
3. **`MADMIX1.BIN`** (`madmix1_body.asm`, carga en `$8400`, sin
   auto-ejecución — `JUMP_TO_ENGINE` lo arranca a mano, ver punto
   anterior): el motor de juego real. Contiene la tabla de saltos
   pública (`JT_INICIO` y compañía, ver §3), `INICIO` y el bucle
   principal por frame, el motor de actores, el driver de sonido, las
   91 losetas, los 64 sprites, la fuente de texto y los datos crudos
   de 12 niveles + 1 oculto + 10 guiones de demo.

**Detalle importante confirmado**: el bloque reubicado a `$1000`
(desde `MADMIX.SCR`) contiene TODO el código de portada + motor de
colisión + niveles + demo + menú + créditos, pero se ejecuta desde
ahí **solo la primera vez** (dibujar portada, tanto desde `RELOCATOR`
como otra vez desde `INICIO`, ver §2). El resto de ese código se
referencia después por sus direcciones **estáticas dentro de
`MADMIX.SCR` tal cual** (`$5xxx`-`$6xxx`), no en `$1xxx`-`$2xxx` —
el bloque reubicado en `$1000` y el código estático de `MADMIX.SCR`
son la MISMA representación lógica en direcciones físicas distintas
(mismo patrón `PHASE`/`DEPHASE` que reproduce `main.asm`).

---

## 2. Secuencia de arranque, paso a paso

```
BASIC orquestador (AUTOEXEC.BAS/MADMIX.BAS, fuera de alcance)
  │
  ├─ BLOAD "MADMIX.SCR",R  ──────────────────────────────────────┐
  │                                                                │
  │  MADMIX.SCR carga en $8800 y se AUTOEJECUTA ahi mismo         │
  │  (arranque de portada: paleta, patron, color -- DIBUJAR_PORTADA) │
  │                                                                │
  ├─ BLOAD "MADMIX0.BIN",R  (carga en $FA00, SE AUTOEJECUTA)      │
  │     RELOCATOR ($FA00):                                        │
  │       - guarda config. de slot en $FFFD (y una "retorcida"    │
  │         en $FFFE, para el otro punto de entrada)               │
  │       - conmuta a RAM en pagina 0                              │
  │       - LDIR $8800 -> $1000, 0x5500 bytes                      │
  │       - CALL DIBUJAR_PORTADA (ejecuta UNA VEZ el bloque        │
  │         reubicado: dibuja la portada)                          │
  │       - restaura slots, EI, RET                                │
  │                                                                │
  ├─ BLOAD "MADMIX1.BIN"  (carga en $8400, SIN ",R" -- no se       │
  │     auto-ejecuta, JUMP_TO_ENGINE lo arranca a mano)            │
  │                                                                │
  └─ CALL/USR -> JUMP_TO_ENGINE ($FA2A, MADMIX0.BIN):              │
        restaura la OTRA config de slot (desde $FFFE)              │
        JP START  (JT_INICIO, motor real de MADMIX1.BIN)           │
                                                                     │
INICIO ($8F24, madmix1_body.asm) -- NUNCA hace RET:                │
  - LD SP,$0FFF                                                     │
  - CALL ACTIVAR_INTERRUPCION_MODO_1                                │
  - DI / CALL DIBUJAR_PORTADA (dibuja la portada OTRA VEZ -- se     │
    dibuja dos veces al arrancar una partida real: una por el       │
    cargador, otra aqui por el propio motor)                        │
  - vacia+instala las 3 ranuras de sonido (INSTALAR_RECURSO_SONIDO, │
    scripts GUION_MELODIA_CANAL_0/1/2)                              │
  - espera pulsacion (sondea COMPROBAR_PULSACION en bucle)          │
  - EI                                                               │
  - REINICIAR_PARTIDA: vacia recursos (VACIAR_CANALES_SONIDO),      │
    CALL MOSTRAR_MENU_PRINCIPAL (entra en el bucle del MENU         │
    PRINCIPAL, espera a que se elija "0 JUGAR" -- ver §5.8),        │
    vidas=3, puntuacion=0, nivel=1, vueltas=0                       │
  - PANTALLA_PRESENTACION_NIVEL (reentrada normal de cada vuelta):  │
    dibuja HUD, CALL CARGAR_NIVEL, PREPARAR_INICIO_NIVEL (secuencia │
    de un solo paso: HUD, "READY?", arranca musica del nivel)       │
  - cae en BUCLE_PRINCIPAL_JUEGO -- EL BUCLE REAL DE CADA FRAME    ┘
```

**Confirmado** (transcrito y verificado 0 diferencias): toda la
secuencia de arriba. Sigue sin trazar en vivo con precisión el
propósito exacto de un segundo `CALL $1000` que hace `INICIO` (una
instrucción literal confirmada en los bytes, pero cuyo efecto visual
distinto del primer dibujado de portada no se ha aislado del todo).

---

## 3. La tabla de despacho `JT_INICIO` — la "API pública" del motor

En `$8400` (inicio de `MADMIX1.BIN`), 12 entradas `JP`, todas
identificadas y con destino transcrito:

| Slot | Etiqueta | Destino | Qué hace |
|---|---|---|---|
| 0 | `JT_INICIO` | `INICIO` (`$8F24`) | Arranque real del motor (§2), nunca retorna |
| 1 | `JT_MOTOR_ACTORES` | `MOTOR_ACTORES` (`$8440`) | Motor de actores/render sub-pixel (§5.1) |
| 2 | `JT_RESET_CONTADOR_ACTORES` | `RESET_CONTADOR_ACTORES` (`$899B`) | `XOR A / LD ($8437),A / RET` — resetea una variable de actor |
| 3 | `JT_WAIT_VBLANK` | `WAIT_VBLANK` (`$89A0`) | Espera de sincronismo vertical |
| 4 | `JT_ACTIVAR_INTERRUPCION` | `ACTIVAR_INTERRUPCION_MODO_1` (`$881B`) | Instala el vector de interrupción real |
| 5 | `JT_LEER_ENTRADA` | `LEER_ENTRADA` (`$8E3C`) | Lectura de teclado/joystick (§5.5) |
| 6 | `JT_DIBUJAR_MARCADOR_PUNTOS` | `DIBUJAR_MARCADOR_PUNTOS` (`$8D70`) | Dibuja el marcador de puntos (§5.6) |
| 7 | `JT_GESTIONAR_SCROLL` | `GESTIONAR_SCROLL` (`$89AD`) | Scroll por software de la cámara (§5.4) |
| 8 | `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` | `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` (`$8C34`) | Redibuja franjas de cámara + iconos de vida (§5.4) |
| 9 | `JT_REDIBUJAR_LOSETA_BUFFER_VRAM` | `REDIBUJAR_LOSETA_BUFFER_VRAM` (`$8D1B`) | Copia una loseta 16×16 del fondo al buffer |
| 10 | `JT_MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` | `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (`$8CB6`) | Coordenada cámara → dirección en la matriz de nivel |
| 11 | `JT_CONSULTAR_TIPO_LOSETA` | `CONSULTAR_TIPO_LOSETA` (`$8CDA`) | Dirección de loseta → tipo (colisión) |

Casi nadie en el resto del código llama a estos slots por número —
casi todos los sitios llaman directo a la dirección real (`CALL
MOTOR_ACTORES`, `CALL MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, etc.), así
que esta tabla funciona más como "índice/API documentada" que como
mecanismo de despacho activo.

---

## 4. El bucle principal (`BUCLE_PRINCIPAL_JUEGO`, `$8FD4`+)

**Corrección de arquitectura importante frente a versiones antiguas
de este documento**: la rutina en `$8FD4` NO es directamente "el
bucle principal" — tiene la etiqueta `PREPARAR_INICIO_NIVEL`, y es
una secuencia de **un solo paso** ("nivel recién cargado → posicionar
HUD → dibujar READY? → arrancar música → esperar al jugador") que se
ejecuta solo en las transiciones (arranque, cambio de nivel, pérdida
de vida). El bucle real que se repite **cada frame** es
`BUCLE_PRINCIPAL_JUEGO`, algo más adelante en el mismo bloque.

Tras `INICIO`, el juego vive el resto de su vida en este flujo —
confirmado que no hay más "vuelta atrás": las dos reentradas
conocidas (`JP PREPARAR_INICIO_NIVEL` / `JP PANTALLA_PRESENTACION_NIVEL`)
reentran en el propio `INICIO` ya transcrito, no saltan a otro sitio.

**Aclaración de arquitectura**: el movimiento del comecocos/fantasmas,
el redibujado de cámara y el motor de colisión (`TABLA_MANEJADORES_LOSETA`,
§5.2) NO están en el cuerpo de `BUCLE_PRINCIPAL_JUEGO` que se lista
abajo — se disparan desde `ENTRADA_INTERRUPCION_VBLANK` (`$882A`) en
cada VBLANK, vía `GESTIONAR_FRAME` (ver §5.10). Es decir, dos "hilos"
cooperando por interrupción: `ENTRADA_INTERRUPCION_VBLANK`
mueve/dibuja el juego frame a frame en segundo plano, mientras
`BUCLE_PRINCIPAL_JUEGO` en primer plano espera (`HALT`, vía
`WAIT_VBLANK`) y comprueba condiciones globales (temporizador de
modo especial, fin de nivel, pausa) al ritmo de esos mismos frames.

### Diagrama paso a paso

```
REINICIAR_PARTIDA (arranque real / tras GAME OVER)   PANTALLA_PRESENTACION_NIVEL (cada vuelta normal)
        │                                                       │
        ▼                                                       │
  vacía recursos, MOSTRAR_MENU_PRINCIPAL, vidas=3,              │
  puntuación=0, nivel=1, vueltas=0                              │
        │                                                       │
        └───────────────────────────────┬──────────────────────┘
                                         ▼
                              vacía recursos (VACIAR_CANALES_SONIDO)
                                         │
                    dibuja 3 líneas de HUD (DIBUJAR_TEXTO_VRAM: TEXTO_FASE,
                    y si aplica TEXTO_VIDA_EXTRA) según nivel (NIVEL_ACTUAL)
                    y flags del registro de nivel (REGISTRO_NIVEL_VIDA_EXTRA_FLAG)
                                         │
                                         ▼
                            espera 80 frames (PAUSA_TEXTO_FASE_LOOP)
┌───────────────────────────────────────┴────────────────────────────────────┐
│ PREPARAR_INICIO_NIVEL ($8FD4) -- secuencia de UN SOLO PASO, no el bucle     │
│  1. vacía recursos, INICIALIZAR_ITEMS_NIVEL (reinicia 3 tablas de items +   │
│     flags de modo)                                                          │
│  2. REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM (redibuja cámara + iconos vida) │
│  3. APLICAR_COLOR_PANTALLA (mismo motor de dibujado del HUD que créditos)   │
│  4. fija el sprite inicial del comecocos (normal, o "excavatofono" si       │
│     MODO_ESPECIAL=3)                                                        │
│  5. limpia flags de dirección/temporizadores                                │
│  6. REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM otra vez (tras limpiar flags)   │
│  7. bloquea teclado (FLAG_ENTRADA_BLOQUEADA=1)                              │
│  8. BUSCAR_COLUMNA_HUD: busca en TABLA_POSICIONES_HUD (19 bytes) la entrada │
│     que coincide con la columna de cámara -- 1 VBLANK de espera por         │
│     entrada probada (efecto de barrido visible), fija posición del HUD     │
│  9. desbloquea teclado (FLAG_ENTRADA_BLOQUEADA=0)                           │
│ 10. MOSTRAR_READY_Y_ARRANCAR_NIVEL: calcula color de atributo (vía          │
│     OBTENER_COLOR_VDP) según columna de cámara, dibuja TEXTO_VACIO_1 /      │
│     TEXTO_READY / TEXTO_VACIO_2 (efecto "borra y pinta")                    │
│ 11. instala el soniquete de inicio de nivel (3 canales,                     │
│     GUION_EVT10_INICIO_NIVEL_CEF0 + offsets 0/7/14)                        │
└───────────────────────────────────────┬────────────────────────────────────┘
                                         ▼
                    PAUSAR_PARTIDA: espera 50 frames + sondea hasta cualquier
                    input (primera vuelta: entra aquí directo, sin comprobar
                    pausa antes)
┌───────────────────────────────────────┴────────────────────────────────────┐
│ BUCLE_PRINCIPAL_JUEGO -- TIC REAL POR FRAME (se repite mientras se juega)   │
│  · CALL ENLACE_MOTOR_MOVIMIENTO_COLISION (trampolín automodificable, ver   │
│    §5.2) + WAIT_VBLANK                                                     │
│  · si MODO_ESPECIAL_ACTIVO [temporizador respawn/invulnerabilidad] > 0:    │
│    decrementa; si llega a 0 JUSTO AHORA → "vida perdida": DESTELLO_ICONO_  │
│    COLOR_HUD, realinea cámara a múltiplo de 4 losetas, resta 1 vida        │
│    (VIDAS_RESTANTES) [objetivo del truco de vidas infinitas, ver           │
│    `.COMPROBAR_TRUCO_VIDAS_INFINITAS` en `GESTIONAR_INTRODUCCION`, §5.8] → │
│      · quedan vidas → JP PREPARAR_INICIO_NIVEL (reinicia HUD del nivel)    │
│      · sin vidas → GAME OVER: rellena de negro el área jugable,            │
│        TEXTO_GAME_OVER, espera ~150 frames, JP REINICIAR_PARTIDA           │
│  ▼                                                                          │
│ VERIFICAR_FIN_NIVEL -- fin de nivel                                        │
│  · ACTUALIZAR_LOSETA_BOLA_ESPECIAL (parpadeo de la bola especial, cada     │
│    vuelta -- verificado en vivo que NO es visible, mecanismo distinto)     │
│  · compara CONTADOR_BOLAS_COMIDAS contra REGISTRO_NIVEL_OBJETIVO_BOLAS →   │
│      · coincide → nivel completado: INC NIVEL_ACTUAL; si llega a 16,       │
│        vuelve a nivel 1 e incrementa CONTADOR_VUELTAS_NIVELES;             │
│        DESTELLO_ICONO_COLOR_HUD (revelado del nuevo HUD) →                 │
│        JP PANTALLA_PRESENTACION_NIVEL                                      │
│      · no coincide → sigue                                                 │
│  ▼                                                                          │
│ VERIFICAR_ENTRADA -- sondeo de "pausa" (bit 5 de LEER_ENTRADA, tecla       │
│ exacta sin confirmar)                                                      │
│      · bit activo → PAUSAR_PARTIDA: espera fija de 50 frames + sondeo     │
│        hasta cualquier input (mismo patrón que la entrada inicial),        │
│        vacía sonido                                                        │
│      · bit inactivo → sigue directo                                        │
│  ▼                                                                          │
│  JP BUCLE_PRINCIPAL_JUEGO -- siguiente frame                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

Notas:
- El movimiento real del comecocos, el scroll y el motor de colisión
  (`TABLA_MANEJADORES_LOSETA`) ocurren en paralelo, disparados por
  `ENTRADA_INTERRUPCION_VBLANK` en cada VBLANK — no están representados
  arriba porque no forman parte del cuerpo de `BUCLE_PRINCIPAL_JUEGO`
  en sí (ver §5.10 para la cadena de la interrupción).
- El "bit 5 sin identificar" de `VERIFICAR_ENTRADA` es el único hueco
  real que queda dentro de este diagrama — candidato fuerte a tecla de
  pausa, sin confirmar (necesitaría trazado en vivo o simplemente
  probar la tecla en el juego real).

---

## 5. Subsistemas

### 5.1 Motor de actores — `MOTOR_ACTORES` (`$8440`-`$8800`, 960 B)

Dibuja/mueve el comecocos y los fantasmas con render sub-pixel
(offset fino dentro de la loseta, no solo loseta a loseta). Usa un
buffer de RAM en `$0500`-`$1000` para el trabajo intermedio antes de
volcar a VRAM. Llamado desde prácticamente todos los subsistemas de
juego (item handlers, manejadores de loseta, `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`)
para redibujar un actor tras cambiar su estado.

**Confirmado**: solo hay sprites hacia derecha/abajo/arriba en los
datos — nunca hacia la izquierda. `INVERTIR_BITS_PATRON_ACTOR`/
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (hipótesis, sin confirmar en vivo)
hacen el volteo horizontal en tiempo de ejecución, mismo convenio
bit7 ya confirmado en `SELECTOR_SPRITE_COMECOCOS`.

### 5.2 Despachador de tipo de loseta — `TABLA_MANEJADORES_LOSETA` (`$2E3C`, `madmix_scr_body.asm`)

20 punteros, indexados por el **tipo** de la loseta hacia la que se
mueve el comecocos (`CONSULTAR_TIPO_LOSETA`, valores 0-19). Es el
corazón del "motor de colisión/movimiento"
(`MOTOR_MOVIMIENTO_COLISION`) que decide qué pasa cuando el jugador
entra en cada loseta.

**Preámbulo documentado línea a línea** (`MOTOR_MOVIMIENTO_COLISION`,
antes del despacho): decide la dirección válida del frame (input real
o guión de demo si `GESTIONAR_CICLO_NIVELES` está activo), solo
permite girar en posiciones alineadas a loseta, y consulta
`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` (con caché por columna)
para saber el tipo de la loseta de destino. Mientras un modo especial
está activo (`MODO_ESPECIAL_ACTIVO!=0`), el despacho por tipo queda
suspendido (se fuerza tipo 0) y el propio preámbulo gestiona la
cuenta atrás del modo (parpadeo de icono HUD, fin de modo).

**Patrón confirmado**: `A` al entrar a cualquier manejador es siempre
el modo especial actual (`MODO_ESPECIAL`), no un parámetro de la
loseta. Ver `FINDINGS.md` para el desglose completo por manejador.

| Tipo | Loseta(s) | Efecto |
|---|---|---|
| 0 | pared/suelo normal (0-44) + variantes decorativas sueltas | sin efecto (default) |
| 1 | `suelo_con_bola_1/2/3` | bolita normal: +1 punto, +1 contador fin de nivel |
| 2 | `suelo_con_bola_clavada_1/2/3` | "libera" la bola fija (sin puntos) |
| 3-6 | flechas arriba/abajo/izq/der | fuerza dirección, +2 puntos, +1 contador |
| 7 | `pista_tanque_vertical` | modo especial "tanque" |
| 8, 9 | `linea_electrica_puerta_fantasmas_a/b` | sin lógica propia (comparten el default) |
| 10 | `pista_avion_recto`/`remate_izq`/`remate_der` | modo especial "avión" |
| 11 | `item_suelo_sin_confirmar` | sale de modo especial |
| 12 | `item_bola_de_poder` (la real) | modo especial "bola de poder", +2 puntos, +1 contador |
| 13 | `item_hipopotamo` | modo especial "hipopótamo" |
| 14 | `item_herramienta` | modo especial "herramienta" |
| 15, 16 | `suelo_sin_bola_*`/`muro_ladrillo_suelto`/`loseta_solida_negra` | sale de modo especial |
| 17-19 | variantes `trampilla_transicion` | animación de apertura de trampilla |

Relacionado: una tabla en RAM de trabajo (`$2C2E`, fuera de este
fichero) guarda hasta 3 posiciones activas de pista/trampilla,
consultada tanto por el motor de colisión como por
`AVISAR_PROXIMIDAD_PISTA` (§5.3).

### 5.3 Subsistema de items especiales

Piezas y su papel real (ver `FINDINGS.md` para el desglose línea a
línea completo):

- **`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO`** (`$2377`/`$2563` aprox.,
  tablas propias `TABLA_ITEMS_MARICOCO`/`TABLA_ITEMS_REGPUNANTOSO`)
  son un par complementario que gestiona el ciclo de vida de las
  bolas "clavadas": `HNDLR_MARICOCO` **regenera** huecos de bolita ya
  comida (`suelo_sin_bola`, 63-65) de vuelta a bolita normal (45-47),
  decrementando el contador de fin de nivel porque vuelve a haber una
  pendiente; `HNDLR_REGPUNANTOSO` **planta** bolas clavadas nuevas
  convirtiendo bolitas normales sin comer (45-47) en clavadas
  (48-50), sin tocar ese contador. Ambos posicionan sus items vía
  `MOTOR_MOVIMIENTO_ITEM`/`CONSULTAR_LOSETA_LIBRE_DIRECCION` (IA de
  "acercarse al objetivo o azar") y dibujan con `MOTOR_ACTORES`; una
  vez colocados marcan su entrada de tabla para dejar de recalcular
  dirección ("plantado").
- **`HNDLR_PELMAZOIDE`** (`$51FE`, tabla `TABLA_ITEMS_PELMAZOIDE`, 8
  entradas × 7 bytes): la IA de movimiento de los fantasmas — intenta
  acercarse a un punto de mira (cámara+offset), y si no puede o por
  azar (`GENERAR_ALEATORIO`), se mueve por cualquier dirección
  transitable vía `CONSULTAR_LOSETA_LIBRE_DIRECCION` (los tipos de
  loseta 0/7/8/10 son intransitables para estas entidades).
- **`AVISAR_PROXIMIDAD_PISTA`** (`$566A`): vigila proximidad del
  comecocos a las pistas de tanque/avión activas (tabla en `$2C2E`)
  con margen amplio, arma un aviso vía `ARMAR_AVISO_DESTELLO`.
- **`ACTUALIZAR_DESTELLO_ITEMS`** (`$5782`): temporizador de los 4
  "slots activos" de item, usa una tabla de efectos de destello para
  decidir la loseta de animación.
- **`ACTIVAR_EFECTO_ITEM`**: despacha el efecto de colisión según el
  modo especial actual; el modo "herramienta" reutiliza el mismo
  camino que "sin modo especial".

### 5.4 Cámara: scroll y HUD de vidas

- `GESTIONAR_SCROLL` (`$89AD`, `JT_GESTIONAR_SCROLL`): decide scroll
  arriba/abajo/lateral según bits de la posición de cámara
  (`REGISTRO_NIVEL_POSICION_COMECOCOS`).
- `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` (`$8C34`,
  `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`): redibuja la cámara
  completa (36 pasadas de `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) y, si
  quedan vidas, dibuja el icono de vida una vez por vida restante; de
  paso limpia y redibuja el marcador de puntos.
- `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (`$8CB6`): fórmula compartida
  coordenada→dirección en la matriz de nivel (stride de 32 columnas).

### 5.5 Entrada — `LEER_ENTRADA` (`$8E3C`, `JT_LEER_ENTRADA`)

Lee teclado (matriz MSX estándar) y joystick (puerto del PSG),
decodifica direcciones con el mismo patrón de extracción de bits que
`CONSULTAR_COLOR_VDP`/`TABLA_COLORES_VDP` (reutilizado aquí para
dirección, no color), y guarda el resultado en
`ACUMULADOR_ENTRADA`/`FLAG_ENTRADA_BLOQUEADA` (bytes "libres"
reutilizados justo antes de `TABLA_TIPOS_LOSETA`).

### 5.6 HUD — `DIBUJAR_MARCADOR_PUNTOS` (`$8D70`, `JT_DIBUJAR_MARCADOR_PUNTOS`)

Dibuja el marcador de puntos. Si el modo demo está activo
(`INDICE_CICLO_NIVELES`) muestra `TEXTO_DEMO` (" DEMO ") en vez del
número; si no, suma a la puntuación acumulada (`PUNTUACION`); si
llega a 10000 muestra `TEXTO_BESTIA` ("BESTIA") en vez de seguir
contando; si no, convierte el número a dígitos ASCII
(`DIBUJAR_MARCADOR_PUNTOS_DIGITOS`) y lo dibuja con
`DIBUJAR_TEXTO_INVERTIDO_VRAM`.

### 5.7 Carga de nivel — `CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL` (`$5904`, `$5885`)

`CARGAR_NIVEL` lee el registro de 20 bytes de `TABLA_NIVELES` según
`NIVEL_ACTUAL`, copia cabecera + cuerpo (sustituyendo el tile comodín
si aplica) al buffer `$FC50`, y fija la posición inicial del
comecocos. `INICIALIZAR_ITEMS_NIVEL` (`$5885`) reinicializa las 3
tablas de items móviles + varios flags de modo especial. Tiene un
**segundo punto de entrada**, `INICIALIZAR_PARCIAL_ITEMS_NIVEL`
(mitad de la rutina), que solo limpia la tabla de pistas activas
(`$2C2E`) — usado por separado al salir de los modos tanque/avión sin
repetir el resto del reseteo.

### 5.8 Menú principal, intro/demo y redefinición de teclas

- `GESTIONAR_INTRODUCCION` (`$5AE9`, antes attract mode): espera
  tecla; si no hay pulsación en el plazo, cicla niveles de muestra
  (`GESTIONAR_CICLO_NIVELES`) reproduciendo los guiones de
  `data/demos/*.dem`. **RESUELTO**: si la tecla es ESC (fila 7),
  activa un truco oculto de vidas infinitas
  (`.COMPROBAR_TRUCO_VIDAS_INFINITAS`, local) que parchea en caliente
  el `SUB $01` de `BUCLE_PRINCIPAL_JUEGO` a `SUB $00`.
- `.CONTINUAR_INTRO`/`MOSTRAR_MENU_PRINCIPAL`/`ACTUALIZAR_MENU_PRINCIPAL`
  (`$5B50`-`$5B71` aprox.): cola común de "continuar" tras la intro —
  apaga la pantalla (`PROGRAMAR_APAGADO_PANTALLA`), vacía recursos,
  limpia VRAM (`LIMPIAR_VRAM_AREA_JUEGO`), avanza el ciclo de nivel
  (`APLICAR_COLOR_CICLO_NIVELES`), y entra en **el bucle del menú
  principal**: dibuja `DIBUJAR_MENU_PRINCIPAL`, vuelve a encender la
  pantalla (`PROGRAMAR_ENCENDIDO_PANTALLA`), lee una tecla
  (`LEER_TECLAS_MENU_PRINCIPAL`) y comprueba el bit 0 del resultado:
  - **bit 0 activo** → sale del bucle del menú, limpia posición/color
    de cámara, `WAIT_VBLANK`, `RET` — es la señal de **"JUGAR"**, y
    devuelve el control a quien llamó al menú (`INICIO` en el
    arranque real, o el punto de retorno tras la intro), que continúa
    hacia `BUCLE_PRINCIPAL_JUEGO`.
  - **bit 0 inactivo** → `DESPACHAR_ACCION_MENU` reparte por bit
    (1/3/4/5) hacia las 4 opciones numeradas (ver tabla abajo); si no
    coincide con ninguna y el valor es distinto de cero, reinicia el
    temporizador del menú (`GESTIONAR_TIMEOUT_MENU`); si es
    exactamente cero (sin tecla), cuenta atrás hacia
    `GESTIONAR_INTRODUCCION` (modo attract) en vez de quedarse
    esperando para siempre.
  - Cada una de las 4 opciones (excepto "JUGAR", que sale del bucle)
    **retorna al propio bucle del menú**, redibujando el menú con la
    opción resaltada.

| Opción | Bit | Rutina | Qué hace | ¿Vuelve al menú? |
|---|---|---|---|---|
| 1 TECLADO | 3 | `SELECCIONAR_OPCION_TECLADO` | fija método de entrada, resalta opción 1 | Sí |
| 2 JOYSTICK | 4 | `SELECCIONAR_OPCION_JOYSTICK` | fija método de entrada, resalta opción 2 | Sí |
| 3 REDEFINE TECLAS | 1 | `SELECCIONAR_OPCION_REDEFINIR_TECLAS` | `CALL DIBUJAR_MENU_REDEFINIR_TECLAS` (submenú real de teclas), limpia VRAM, redibuja | Sí |
| 4 DEMO | 5 | `SELECCIONAR_OPCION_DEMO` | `CALL GESTIONAR_CICLO_NIVELES` (cicla niveles de muestra reproduciendo `data/demos/*.dem`), limpia recursos/VRAM, redibuja | Sí — es un módulo de demo que se ejecuta y vuelve, NO deja el menú de forma permanente |
| 0 JUGAR | 0 | (sale del bucle) | limpia posición/color de cámara + `WAIT_VBLANK` | No — continúa hacia `BUCLE_PRINCIPAL_JUEGO`, la partida real |

`DIBUJAR_MENU_REDEFINIR_TECLAS`: el submenú real de redefinición de
teclas (`TEXTO_MENU_REDEFINIR_TECLAS`, texto de las 6 acciones +
nombres de tecla), usando `ESPERAR_TECLA_NUEVA` para detectar la
tecla pulsada vía `TABLA_CODIGOS_TECLA`.
- `APLICAR_COLOR_PANTALLA`/`DIBUJAR_CREDITOS`: pantalla de créditos
  real ("POGRAMADO BY: RAPHAEL GOMEZZZ..", etc.) — también dispara la
  aplicación del color real del marco de caramelo
  (`TABLA_RECURSOS_SONIDO_EVENTO`... la tabla de color en sí, ver
  `FINDINGS.md`).
- `REUBICADOR_REINICIO_JUEGO`: segunda rutina de reubicación gemela a
  `RELOCATOR` de `MADMIX0.BIN` — candidata a "volver al menú en
  caliente", sin confirmar en vivo.

### 5.9 Driver de sonido (`$C4A0`-`$CF8B`, en `madmix1_body.asm`)

`INSTALAR_RECURSO_SONIDO` (`$C4A0`) busca hueco libre entre las
ranuras de canal (46 bytes cada una, en `$C9C9`); el reproductor
principal (`TICK_REPRODUCTOR_PSG`/`PROCESAR_CANAL_PSG`) lee
comandos/duraciones de un script y vuelca los 11 registros del PSG
AY-3-8910 cada tic. `VACIAR_CANALES_SONIDO` (`$CF8B`) vacía las 3
ranuras.

**`EVENTO_SONIDO_PENDIENTE`** (`$6128`) es el índice de efecto de
sonido a disparar (ver `FINDINGS.md` para el desglose completo).
`DESPACHAR_EFECTO_SONIDO` (`$60DC`, `madmix_scr_body.asm`), llamada
en cada VBLANK desde la ISR, consume `(EVENTO_SONIDO_PENDIENTE)` y lo
busca en `TABLA_RECURSOS_SONIDO_EVENTO` (`$60FE`, 14 entradas
`[canal, puntero]`) para instalar el script correspondiente en el
reproductor PSG.

Los 15 comandos del bytecode están descifrados uno a uno (ver
`FINDINGS.md`). Cada `.snd` tiene un `.txt` gemelo en texto plano
editable, generado y verificado con `tools/mmsnd_tool.py` (roundtrip
byte a byte exacto). Pendiente: las tablas de instrumento en sí (~20
punteros a programas escritos en este mismo lenguaje) no se han
decodificado todavía.

### 5.10 Interrupción — `ENTRADA_INTERRUPCION_VBLANK` (`$882A`) + `GESTIONAR_FRAME` (`$8860`)

`ENTRADA_INTERRUPCION_VBLANK` guarda registros, hace housekeeping
(`GESTIONAR_FRAME`: llama a `CONTINUAR_CAPTURA_MASCARAS_ACTORES`,
`RESET_CONTADOR_ACTORES`, refresco de VRAM vía `ACTUALIZAR_VRAM_FRAME`,
vacía la cola de redibujado diferido vía
`VACIAR_COLA_REDIBUJADO`/`.DESPACHAR_ENTRADA_COLA` →
`REDIBUJAR_LOSETA_BUFFER_VRAM`) y restaura. Instalada por
`ACTIVAR_INTERRUPCION_MODO_1` al arrancar (`$0038` → `JP $882A`,
confirmado en vivo).

---

## 6. Variables de estado compartido más importantes

Referencia rápida (RAM de trabajo, casi todas dentro del "registro de
nivel activo" copiado a `REGISTRO_NIVEL`/`$2C0X`-`$2C2D` o cerca):

| Variable | Qué es |
|---|---|
| `REGISTRO_NIVEL_POSICION_COMECOCOS` (`$2C02`) | Posición de cámara/comecocos |
| `REGISTRO_NIVEL_OBJETIVO_BOLAS` (`$2C05`/`$2C06`) | Objetivo de bolitas a comer (offsets 18-19 del registro de nivel) |
| `NIVEL_ACTUAL` (`$2C07`) | Nivel actual (1-14; el 0 reutiliza el registro del 1) |
| `CONTADOR_BOLAS_COMIDAS` (`$2C08`) | Contador en vivo de bolitas/items restantes |
| Flags de modo especial (`$2C0D`-`$2C11`) | Hipopótamo/obra/avión..., reinicializados por `INICIALIZAR_ITEMS_NIVEL` |
| `$2C18`/`$2C24` | Par guardado/restaurado al entrar y salir de un modo especial |
| `VIDAS_RESTANTES` (`$2C27`) | Vidas restantes |
| `PUNTUACION` (`$2C29`) | Puntuación acumulada |
| `MODO_ESPECIAL` (`$2C2D`) | Selector de modo especial activo (0=normal) |
| `CONTADOR_VUELTAS_NIVELES` | Vueltas completas al ciclo de 15 niveles |
| `EVENTO_SONIDO_PENDIENTE` (`$6128`) | Índice de efecto de sonido a disparar (§5.9) |

---

## 7. Pendiente / hipótesis sin confirmar en vivo

- El propósito exacto del segundo `CALL $1000` dentro de `INICIO`
  (§2) — distinto del dibujado de portada del cargador.
- El bit 5 de `LEER_ENTRADA` (candidato a tecla de pausa, §4) — sin
  confirmar qué tecla física es.
- El mecanismo exacto de volteo horizontal de sprites en
  `MOTOR_ACTORES` (§5.1) — candidatas identificadas, sin trazar en
  vivo.
- Las tablas de instrumento del driver de sonido (§5.9) — sin
  decodificar nota a nota.
- Ver `FINDINGS.md` para el catálogo completo de hallazgos, hipótesis
  y correcciones — este documento resume solo el flujo de alto nivel.
