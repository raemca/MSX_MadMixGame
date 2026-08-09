# Mad Mix Game (Topo Soft, 1987/88) — hallazgos de ingeniería inversa

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

Contexto para retomar el trabajo. Origen: análisis estático de
`MADMIX1.BIN` extraído del `.dsk` original con `mtools`, usando
`z80dasm` + inspección manual byte a byte (sin emulador ni
debugger todavía). Todo lo de aquí viene de una sesión de chat
con Claude en claude.ai; este fichero es el puente de contexto
hacia Claude Code.

## Estructura del disco

| Fichero | Tamaño | Función |
| --- | --- | --- |
| AUTOEXEC.BAS | 19 B | `RUN"madmix",R` |
| MADMIX.BAS | 183 B | cargador BASIC, hace los BLOAD |
| MADMIX0.BIN | 58 B | loader en código máquina, ver abajo |
| MADMIX1.BIN | 22952 B | el motor del juego, 0x8400-0xDDA0 |
| MADMIX.SCR | 21768 B | pantalla de carga |

No hace falta tocar los tres primeros — funcionan tal cual. El
trabajo es reconstruir MADMIX1.BIN como fuente ensamblable.

## MADMIX0.BIN — el loader (58 bytes, desensamblado completo y sin ambigüedad)

```asm
di
in a,(0a8h)        ; lee slot primario
ld b,a
ld (0fffdh),a      ; guarda config actual
srl a / srl a / srl a / srl a
or b
ld (0fffeh),a
out (0a8h),a       ; conmuta slots (RAM en página 0)
ld hl,08800h
ld de,01000h
ld bc,05500h
ldir               ; copia 0x5500 bytes de 0x8800 a 0x1000
call 01000h        ; ejecuta el bloque reubicado
ld a,(0fffdh)
out (0a8h),a       ; restaura slots
ei
ret
```

**Importante para la reconstrucción**: cualquier `.asm` que
reemplace a MADMIX1.BIN tiene que ocupar exactamente el mismo
espacio en cada tramo, porque estas direcciones (0x8800, 0x1000,
0x5500, 0x8400) están grabadas a fuego en este loader. Si nuestro
código no tiene el mismo tamaño byte a byte que el original en
cada rutina, todo se desplaza y este loader deja de funcionar.
Para reproducir el reubicado en SjASMPlus: usar `PHASE 0x1000` /
`DEPHASE` en el tramo que ocupa 0x8800-0xDD00 del original.

**CORRECCIÓN/AMPLIACIÓN (verificado con Z80Dasm directamente, con
el offset de cabecera correcto): el listado de arriba solo cubre
LA MITAD del fichero.** Los 58 bytes reales tienen **dos puntos de
entrada independientes**, no uno:

```asm
; 0xFA00 (RELOCATOR) -- el que se ejecuta via "BLOAD MADMIX0.BIN,R"
DI
IN A,($A8)
LD B,A
LD ($FFFD),A        ; guarda config de slot actual
SRL A / SRL A / SRL A / SRL A
OR B
LD ($FFFE),A         ; guarda TAMBIEN una version retorcida, para el
                       ; segundo punto de entrada de mas abajo
OUT ($A8),A
LD HL,$8800 / LD DE,$1000 / LD BC,$5500
LDIR
CALL $1000            ; PORTADA_INIT (madmix_scr.asm)
LD A,($FFFD)
OUT ($A8),A            ; restaura slots
EI
RET                     ; <- vuelve al BASIC que lo llamo

; 0xFA2A (JUMP_TO_ENGINE) -- SEGUNDO punto de entrada, independiente
DI
LD A,($FFFE)
OUT ($A8),A              ; restaura la OTRA config de slot guardada
JP $8400                  ; salta directo a JT_INIT (MADMIX1.BIN)
```

Esto encaja una pieza que llevaba tiempo suelta: `MADMIX1.BIN` se
carga con un `BLOAD` SIN `",R"` (confirmado desde el principio del
proyecto), así que algo tiene que arrancarlo a mano DESPUÉS de
cargarlo. `0xFA2A` es el candidato perfecto -- probablemente
invocado por un `CALL`/`USR` explícito en el BASIC orquestador,
después de la línea que carga `MADMIX1.BIN`.

**HECHO**: `MADMIX0.BIN` tiene ahora su propio fuente,
`src/madmix0.asm` -- los 3 ficheros del disco (`MADMIX0.BIN`,
`MADMIX1.BIN`, `MADMIX.SCR`) tienen ya cada uno su `.asm`
independiente. Verificado 0 diferencias en los 58 bytes completos.

## RESUELTO: secuencia de arranque completa desde el .BAS (confirma quién llama a `0xFA2A`)

Volcado byte a byte de `AUTOEXEC.BAS` y `MADMIX.BAS` (tokenizados,
formato estándar MSX-BASIC: `[ptr siguiente linea 2B][num linea
2B][tokens...][00]`, terminado en `00 00`). Las líneas relevantes
de `MADMIX.BAS` (las anteriores son solo `REM` con el título y los
créditos, incluido un "CRACKED BY PAU D'ACI" -- esta copia del
disco está parcheada por un grupo de crack, no es 100% la original
de Topo Soft, aunque no hay indicios de que afecte a la mecánica
de carga):

```basic
70 BLOAD"MADMIX.SCR":BLOAD"MADMIX0.BIN",R
80 BLOAD"MADMIX1.BIN":DEFUSR=&HFA2A:X=USR(0)
```

(la dirección `&HFA2A` está confirmada BYTE A BYTE: aparece en el
volcado crudo como `0C 2A FA`, es decir "constante hex de 2 bytes
= 0xFA2A" -- coincide exactamente con `JUMP_TO_ENGINE` en
`madmix0.asm`. La sintaxis exacta de `DEFUSR=`/`USR(0)` se infiere
de los tokens circundantes con algo menos de certeza que la
dirección en sí, pero la estructura general no admite otra lectura
razonable).

Secuencia completa de arranque:

1. `AUTOEXEC.BAS` → `RUN"madmix",R` → cede el control a `MADMIX.BAS`.
2. `MADMIX.BAS` línea 70: `BLOAD"MADMIX.SCR"` (carga sin ejecutar,
   aterriza en 0x8800). Luego `BLOAD"MADMIX0.BIN",R` carga
   `MADMIX0.BIN` y, por el `,R`, lo EJECUTA en el acto desde su
   `exec` (`0xFA00` = `RELOCATOR`): éste hace el `LDIR` que reubica
   `MADMIX.SCR` a 0x1000, dibuja la portada, y hace `RET` --
   **devolviendo el control al propio BASIC**, que sigue en la
   línea siguiente.
3. `MADMIX.BAS` línea 80: `BLOAD"MADMIX1.BIN"` -- sin `,R` (confirma
   lo que ya se sabía) -- solo copia el bloque a memoria
   (0x8400-0xDDA0), no ejecuta nada todavía. **Este `BLOAD` es
   quien "carga el 1".**
4. `DEFUSR=&HFA2A : X=USR(0)` -- **esto es quien "llama a la rutina
   que ejecuta el 1"**: el propio BASIC, usando el mecanismo
   estándar de MSX-BASIC para invocar código máquina. Salta a
   `0xFA2A` (`JUMP_TO_ENGINE`, sigue residente en memoria desde que
   se cargó `MADMIX0.BIN` en el paso 2 -- nadie lo sobrescribe),
   que restaura la config de slot guardada en `$FFFE` y hace
   `JP $8400` -- el salto final y definitivo al motor de juego. A
   partir de aquí ya no hay vuelta al BASIC.

Con esto queda cerrado el hilo de "quién arranca `MADMIX1.BIN`":
es el propio BASIC orquestador, en dos pasos (`BLOAD` sin `,R` +
`DEFUSR`/`USR` explícito), no `MADMIX0.BIN` por sí solo.

## IMPORTANTE: el .BIN tiene 7 bytes de cabecera MSX al principio

`MADMIX1.BIN` (22952 bytes en disco) empieza con la cabecera
estándar de `BLOAD` de MSX: `FE 00 84 A0 DD 00 84` = ID `$FE` +
inicio `$8400` + fin `$DDA0` (inclusive) + ejecución `$8400`. El
CÓDIGO real por tanto empieza en el **offset de fichero 7**, no en
el 0. Si se leen bytes crudos del `.BIN` para verificar algo,
`direccion = 0x8400 + (offset_fichero - 7)`. Nos mordió una vez
(desalineó una lectura de tabla en 7 bytes) — no lo olvides.

## Mapa de memoria de MADMIX1.BIN (0x8400-0xDDA0)

- `0x8400`: cabecera + tabla de saltos (12 entradas `JP`),
  **verificada byte a byte** contra el `.BIN` original — coincide
  exacto con `src/madmix1.asm`.
- `0x8400-0x8800`: código residente permanente
- `0x8800-0xDD00`: bloque que el loader reubica y ejecuta en
  `0x1000-0x6500` — incluye la lógica de juego real (`0x60DC`
  llamado cada interrupción)
- `0x8EC4-0x8F23`: tabla de tipos de loseta (**96 bytes**,
  completa — CORREGIDO, ver abajo; antes se creía 0x8EC7/93 bytes)
- `0x8F24`: arranque real (`INIT`), **desensamblado y transcrito
  a `src/madmix1.asm` hasta el offset `$8F71`** (ver sección propia
  más abajo)
- `0x9300-0x9700`: fuente/iconos pequeños de 8x8 (marcador,
  puntos), NO son los personajes
- `0x9D40-0xA3E0`: candidato fuerte a sprites de personajes
  (53 bloques de 16x16, formas variadas) — localizado pero
  **sin identificar cuál es cuál** (comecocos, fantasmas,
  hipopótamo, tanque, avión, mariquita, apisonadora, trampillas)
- `~0x9600-0xB700`: marco de caramelo a rayas (patrón 00/FF
  repetido), grande, no incluido todavía en el proyecto
- `0xB940-0xC4A0`: gráficos de losetas del laberinto, 32 bytes
  cada una (16x16, 16 filas x 2 bytes) — SÍ incluido
  (`data/tile_gfx.bin`)
- `0xC4A0-0xC900`: gestor de "ranuras de recurso" (código real,
  desensamblado y entendido, ver abajo)
- `0xC900-0xCF8B`: cabeceras de recursos (`0xCDCB`, `0xCDFF`,
  `0xCE0C`) en formato tipo bytecode (prefijo común `85 64`,
  opcodes ≥0x80) — el intérprete que las consume NO localizado
- `0xD000-0xD500`: candidato a datos de laberinto/nivel (corridas
  largas repetidas = pasillos, valores ≤0xBF) — incluido
  (`data/maze_data.bin`) pero SIN confirmar si son los 15 niveles
  completos o un subconjunto/formato comprimido
- `0xD500-0xDDA0`: sin explorar

## Interrupción VBLANK

- Vector `0x0038` parcheado en caliente con `JP 0x882A`
- ISR en `0x882A`: lee estado VDP (`IN A,(099h)`), si es
  frame-interrupt guarda registros y llama:
  - `0x8860`: housekeeping — semáforo en `0x8430`
  - `0x60DC`: lógica del juego, **cada interrupción sin
    excepción** (NO hay frame-skip 25/50Hz, se comprobó y se
    descartó esa hipótesis)
- `0x89A0` (`WAIT_VBLANK`): pone flag=1, EI, sondea hasta que la
  ISR lo pone a 0 en la siguiente interrupción — equivalente
  funcional de un `HALT`

## API del VDP -- direcciones VERIFICADAS byte a byte contra el .BIN

`0x8931` (FILVRM), `0x8942` (LDIRVM) y `0x8954` (SETVRAM) estaban
correctas (a diferencia de la falsa alarma inicial: buscar quién
las LLAMA con `CALL` directo dio 0 resultados en todo el fichero,
pero eso solo significa que nadie las invoca así en las partes
del código que hemos escaneado -- probablemente se llaman desde
zonas aún sin explorar, o via saltos indirectos). Decodificando
los bytes reales se confirmó que las 3 rutinas son CONTIGUAS, sin
ningún hueco entre ellas (0x8931-0x8960 completo), y el contenido
real difiere un poco del que había en `madmix1.asm` (que era
aproximado/inventado, no transcrito):

- **FILVRM** usa un bucle ANIDADO B/C (`INC B` de compensación,
  luego `OUT/DEC C/JR NZ` interior, `DEC B/JR NZ` exterior) — el
  patrón clásico de BIOS de MSX para contar 16 bits con
  instrucciones de 8 bits, no la resta BC de 16 bits que había
  antes.
- **LDIRVM** es prácticamente igual a lo que había, salvo que usa
  `JP NZ` (3 bytes) en vez de `JR NZ` (2 bytes) para el salto del
  bucle.
- **SETVRAM** tiene 2 instrucciones extra al final,
  `EX (SP),HL` x2 — un "no-op" deliberado de retardo (19 T-states
  cada uno) que exige el VDP tras fijar la dirección de VRAM antes
  del siguiente acceso a puerto.

Las 3 correcciones ya están en `src/madmix1.asm` y compilan con las
direcciones exactas esperadas (verificado con `--sym`).

### Hueco 0x8961-0x899F COMPLETAMENTE transcrito (llenaba el DS antes de WAIT_VBLANK)

Tirando del hilo del hallazgo colateral (la rutina de tabla justo
tras SETVRAM), se decodificó byte a byte TODO el tramo hasta
`WAIT_VBLANK` (0x89A0) — encaja exacto, sin ningún resto. Ya está
transcrito en `src/madmix1.asm`. Cuatro cosas nuevas:

- **`0x8961` `LOOKUP_8978`**: `LD HL,$8978 / AND $78 / RRCA x3 /
  ADD A,L / LD L,A / LD A,H / ADC A,0 / LD H,A / LD A,(HL) / OR
  $10 / RET`. Extrae un índice de 4 bits de los bits 3-6 de A,
  busca en una tabla de 16 bytes en `0x8978` y devuelve el
  resultado con el bit 4 forzado a 1.
- **`0x8978` `DIRBITS_TABLE`** (16 bytes): `01,04,06,0D,0C,05,0A,
  0E,01,04,06,08,02,07,0B,0F`. HIPÓTESIS interesante: los 16
  valores son TODOS combinaciones de los bits `1,2,4,8` (arriba/
  abajo/izquierda/derecha, coincide con los bits de las flechas
  51-54) — faltan exactamente `0,3,9` y se repiten `1,4,6`. Podría
  ser una tabla de decisión de movimiento (¿IA de fantasmas?
  ¿resolución de qué dirección tomar en un cruce con varias
  paredes abiertas?). Sin confirmar el uso real todavía.
- **`0x8988` `ADDR_FROM_DC00`**: `PUSH BC / (SRL B / RR C) x3 / LD
  HL,$DC00 / ADD HL,BC / POP BC / RET`. Divide BC entre 8 (16
  bits) y lo suma a base `0xDC00` — cae DENTRO de la zona
  "0xD500-0xDDA0 sin explorar". HIPÓTESIS: convierte una
  coordenada de píxel en un índice de tabla/atributo de 8 en 8,
  parecido en espíritu a `MAP_COORD_TO_ADDR` (0x8CB6) pero con
  otra tabla base. Sin confirmar a qué corresponde `0xDC00`.
- **`0x899B` `RESET_8437`** — **IDENTIFICA JT_SLOT3** (antes "sin
  identificar" en la tabla de saltos): `XOR A / LD ($8437),A /
  RET`. Pone a cero la variable residente `0x8437`, la misma que
  se lee/compara en el código todavía sin transcribir que empieza
  en `0x8447` (ver más abajo, sección de la tabla de saltos /
  zona residente). Conecta dos hilos sueltos de sesiones
  anteriores: ahora sabemos que `0x8437` es una variable que se
  puede resetear vía la API pública (jump table), aunque aún no
  sabemos para qué se usa exactamente.

## API del VDP (encapsulada, base de todo lo demás)

- `0x8954` SETVRAM(HL): prepara puerto 0x99/0x98 para leer/escribir
  en esa dirección VRAM — la usan todas las demás
- `0x8942` LDIRVM(HL=origen,DE=destino,BC=bytes): copia RAM→VRAM
- `0x8931` FILVRM(HL=destino,BC=cantidad,A=valor): rellena VRAM
- `0x8CA3`/`0x8E15`: igual que LDIRVM pero con `CPL` (máscara/negativo)
- `0x8DFE` aprox: rutina de texto, indexa tabla de fuente en `0x935B`

## Scroll por software (cámara centrada en el comecocos)

- `0x2C02`: posición del comecocos = posición de la cámara
- `0x8CB6`: coordenadas → dirección (AND 07Ch, alinea a rejilla)
- `0xFC60`: matriz del nivel en RAM, 1 byte/celda, bit7 = flag
  (¿comido?), bits 0-6 = índice crudo de loseta (0-127)
- `0x8CDA`: índice crudo AND 07Fh → tabla `0x8EC7` → "tipo" de
  loseta (0x00-0x13, 20 tipos)
- **Cálculo del gráfico** (resuelto): `HL = 0xB940 + 32 ×
  byte_crudo_de_la_matriz` — el gráfico se indexa por el BYTE
  CRUDO directamente, NO por el "tipo" de `0x8EC7`. Dos caminos
  independientes desde el mismo byte: uno para colisión (tipo),
  otro para render (gráfico). Permite que varias losetas
  visualmente distintas compartan el mismo tipo lógico.
- `0x8D5F`/`0x8CFF`/`0x8D10`: cola productor/consumidor de
  "franjas a redibujar" (hasta que se cruza un límite de tile)
- `0x8D1B`: redibuja franja de 2×16 tiles — origen contiguo
  (`0xB940`+offset), destino con paso de 32 bytes/fila (ancho de
  pantalla) hacia buffer-sombra `0xDE04`
- **Sin confirmar**: el punto exacto donde `0xDE04` se vuelca a
  la VRAM real (presumiblemente vía LDIRVM, no localizado)

## Tabla de tipos de loseta (0x8EC4, 96 bytes, completa) — CORREGIDA

Dirección y tamaño corregidos leyendo el `.BIN` original byte a
byte (ver nota de cabecera arriba). Antes se creía `0x8EC7`/93
bytes; los 3 bytes de más al principio eran en realidad la cola
de la rutina anterior (`CB E3` = `SET 4,E`, `7B` = `LD A,E`, `18
AA` = `JR $-86`), no parte de la tabla. Índices 0-47 → tipo 0x00
(suelo/pasillo, el más común, 48 entradas no 45). A partir del 48
hay tipos crecientes 0x01-0x13 (wall variants, esquinas, etc.). 20
tipos distintos en total (0x00-0x13). La tabla termina EXACTO
donde empieza `INIT` (`0x8EC4 + 0x60 = 0x8F24`) — buena
confirmación cruzada. Contenido exacto ya está en `madmix1.asm` como
`TILE_TYPES`.

### Anomalía confirmada por el usuario (jugando/identificando visualmente)

Las losetas de gráfico #51 (arriba), #52 (abajo) y #53 (izquierda)
son flechas que obligan al comecocos a avanzar en esa dirección
(mecánica confirmada jugando al original), y las tres tienen tipo
`2` en la tabla — consistente. Pero la loseta #54 (flecha DERECHA,
misma familia visual y mecánica) tiene tipo `3`, no `2`. Confirmado
directamente contra los valores reales de `TILE_TYPES` (índices
51,52,53,54 → 2,2,2,3). Con las 4 direcciones ya identificadas, la
anomalía queda más nítida: no es un tipo "raro" por ambigüedad de
cuál dirección es cada índice — es específicamente la dirección
DERECHA la que rompe el patrón de las otras tres. Posibles
explicaciones, ninguna confirmada todavía:
- El tipo codifica algo más que "es una flecha" (p.ej. una
  submecánica distinta solo para la flecha derecha).
- Es una inconsistencia/bug real del juego original.
- El índice de gráfico y el índice de tipo no son tan 1:1 como se
  asume — pendiente de revisar con más casos según el usuario
  vaya identificando el resto de losetas visualmente (ver
  `src/recursos/graficos.html`).

Segunda anomalía del mismo estilo: las losetas de gráfico #84,
#85, #86 y #87 son las 4 piezas de un mosaico decorativo con la
cara del comecocos (según el usuario, NO es suelo — es un muro de
adorno que aparece en algunas fases). Tipos reales: `0,10,10,0`
— dos de las cuatro piezas comparten tipo con el suelo normal
(`0`) y las otras dos comparten tipo `10` con otra loseta de muro
ya vista (índice de gráfico 61). O sea: un mismo mosaico visual
(4 piezas contiguas, un solo objeto) tiene 2 tipos lógicos
distintos, y ninguno de esos 2 tipos es exclusivo del mosaico.
Refuerza la sospecha de que "tipo" no es una clasificación
puramente visual/estética sino algo más ligado a colisión/
comportamiento (p.ej. "se puede caminar por encima o no", más que
"qué aspecto tiene"), y que el mapeo gráfico↔tipo tiene más
matices de los asumidos. Sin resolver — pendiente de más casos.

### HALLAZGO IMPORTANTE: "tipo" no distingue muro de suelo

Las losetas 0-44 (45 gráficos: 16 de hierro + 16 de cemento + 13
de ladrillo, ver leyenda completa abajo) son TODAS muros — y las
45 tienen tipo `0`, exactamente el mismo tipo que el suelo llano y
el suelo con bola (45-47). Confirma lo que el usuario avisó desde
el principio ("la mayoría de tipo 0 son suelo O muros"): la tabla
`TILE_TYPES` **no es** la fuente de la distinción caminable/muro.
Esa distinción tiene que resolverse por OTRO mecanismo todavía no
localizado — probablemente comparando el índice de gráfico crudo
contra rangos conocidos (ej. "si está entre 0 y 44, es muro") en
vez de mirar el byte de `TILE_TYPES`. Esto es un cambio de
entendimiento importante: `TILE_TYPES` parece codificar más bien
"comportamientos especiales" (bola clavada, flechas, pistas de
vehículo, etc.) superpuestos a una base de muro/suelo que se
determina de otra forma. Pendiente de localizar esa lógica.

### Trampillas en L (mecánica de 3 estados, 12 losetas)

Mecánica confirmada por el usuario: una trampilla es una pared en
forma de L que el comecocos puede subir/empujar; al hacerlo, la
parte vertical de la L se tumba y la horizontal se levanta,
invirtiendo la trampilla — así el comecocos puede huir de un
fantasma dejándolo al otro lado de la pared ya invertida. El juego
anima la transición (con sonido) en ambos sentidos. Son 3 estados
gráficos distintos, 4 losetas cada uno (esquina superior-izq,
superior-der, inferior-izq, inferior-der):

- **Trampilla A** (L "a derechas", se atraviesa de derecha a
  izquierda): 74 (arriba-izq), 75 (arriba-der), 67 (abajo-izq), 68
  (abajo-der).
- **Trampilla B** (L "a izquierdas", se atraviesa de izquierda a
  derecha): 71 (arriba-izq), 72 (arriba-der), 73 (abajo-izq), 69
  (abajo-der).
- **Transición** (momentánea, sustituye a las 4 de la trampilla
  activa mientras se tumba/vuelca, antes de mostrar la trampilla
  inversa): 76 (arriba-izq), 77 (arriba-der), 78 (abajo-izq), 79
  (abajo-der).

Secuencia en el juego: trampilla A ↔ transición ↔ trampilla B (en
ambos sentidos). Tipos reales de estas 12 losetas: `0,0,15,15`
(A), `17,0,15,16` (B), `18,0,0,0` (transición) — vuelve a aparecer
el tipo `15` ("cruce pared vertical/horizontal" en la leyenda de
muros) en piezas de trampilla sin relación aparente con un cruce
de paredes, reforzando la sospecha de que los tipos se reutilizan
por comportamiento compartido (aquí probablemente "esquina inferior
de estructura, bloquea igual que un cruce") más que por parecido
visual o pertenecer al mismo objeto.

### Leyenda de los 3 estilos de pared (hierro/cemento/ladrillo)

Confirmado por el usuario: los 3 estilos NO se combinan dentro de
un mismo nivel (cada nivel usa uno de los tres). Pieza a pieza
(mismo orden en los 3 estilos, cemento y hierro completos, ladrillo
solo hasta la posición 12):

| # dentro del set | Hierro | Cemento | Ladrillo | Significado |
| --- | --- | --- | --- | --- |
| 0 | 0 | 16 | 32 | pieza individual, no conectable |
| 1 | 1 | 17 | 33 | límite superior de pared vertical |
| 2 | 2 | 18 | 34 | pared vertical |
| 3 | 3 | 19 | 35 | límite inferior de pared vertical |
| 4 | 4 | 20 | 36 | límite izquierdo de pared horizontal |
| 5 | 5 | 21 | 37 | pared horizontal |
| 6 | 6 | 22 | 38 | límite derecho de pared horizontal |
| 7 | 7 | 23 | 39 | esquina inferior izquierda |
| 8 | 8 | 24 | 40 | esquina inferior derecha |
| 9 | 9 | 25 | 41 | esquina superior izquierda |
| 10 | 10 | 26 | 42 | esquina superior derecha |
| 11 | 11 | 27 | 43 | pared horizontal + unión central vertical hacia abajo |
| 12 | 12 | 28 | 44 | pared horizontal + unión central vertical hacia arriba |
| 13 | 13 | 29 | — | pared vertical + unión central horizontal hacia derecha |
| 14 | 14 | 30 | — | pared vertical + unión central horizontal hacia izquierda |
| 15 | 15 | 31 | — | cruce entre pared vertical y pared horizontal |

### Identificaciones visuales confirmadas por el usuario (en curso)

Se van registrando aquí segun el usuario identifica losetas
viendo `src/recursos/graficos.html` (que también se actualiza con
cada una). Índice = número de gráfico (mismo orden que en
`tile_gfx.bin`/`madmix1.asm`/la página HTML).

### `0x9D40-0xA3E0` DESCARTADO como candidato a sprites -- probados 3 formatos, ninguno da forma coherente

Se probaron, viendo `src/recursos/graficos.html` (selector de
modo en la galería de sprites):
1. Raster 16x16 (16 filas x 2 bytes, el formato real de
   `tile_gfx.bin`) — sin forma reconocible.
2. Cuadrante de sprite 16x16 nativo del VDP TMS9918 (4 bloques de
   8x8, orden arriba-izq/abajo-izq/arriba-der/abajo-der) — sin
   forma reconocible.
3. 4x bloques de 8x8 independientes, SIN componer en un 16x16
   (por si fueran sprites pequeños individuales) — sin forma
   reconocible tampoco.

Conclusión: el problema no es el formato de decodificación — lo
más probable es que **`0x9D40-0xA3E0` nunca estuvo confirmado
byte a byte**. Era un "candidato fuerte" de la sesión de análisis
original (anterior a este repo), y ya sabemos que esa sesión tuvo
varios errores reales confirmados después (dirección de
`TILE_TYPES` desplazada 3 bytes, `SP` de `INIT` equivocado,
"CALL 0x1000" malinterpretado) — así que un candidato sin
verificar en esa misma sesión es sospechoso por defecto. Pendiente
de localizar la posición REAL de los sprites de personajes por uno
de estos dos caminos (ninguno intentado todavía):

1. **Estático**: localizar en el desensamblado dónde se escribe el
   registro #6 del VDP (tabla de patrones de sprites, vía puerto
   `0x99`) y desde ahí rastrear la llamada tipo `LDIRVM` que copia
   los datos reales — su HL (origen) sería la dirección real en
   la ROM.
2. **En vivo**: con openMSX + debugger, breakpoint en esa escritura
   a VRAM y leer qué dirección de ROM se está copiando.

**MILESTONE: las 91 losetas de `tile_gfx.bin` están identificadas
visualmente** (única pendiente real: la función exacta de la
loseta #59, similar a la #60 pero sin confirmar). Quedan sin
identificar los 53 sprites de personajes (`0x9D40-0xA3E0`) y el
marco de caramelo (formato aún sin confirmar, ni siquiera
extraído).

| Índice | Tipo real | Identificación |
| --- | --- | --- |
| 51 | 2 | flecha ARRIBA — obliga al comecocos a avanzar en esa dirección |
| 52 | 2 | flecha ABAJO — obliga al comecocos a avanzar en esa dirección |
| 53 | 2 | flecha IZQUIERDA — obliga al comecocos a avanzar en esa dirección |
| 54 | 3 | flecha DERECHA — misma mecánica que 51-53, pero tipo distinto (3 en vez de 2, ver anomalía arriba). Direcciones confirmadas por el usuario: arriba=51, abajo=52, izquierda=53, derecha=54 |
| 45,46,47 | 0,0,0 | suelo con bola (comestible normal), en los 3 tipos de suelo distintos |
| 48,49,50 | 1,1,1 | suelo con bola CLAVADA (un enemigo clava bolas; hace falta una herramienta para desclavarlas y luego volver a comerlas), en los mismos 3 tipos de suelo |
| 63,64,65 | 12,13,14 | suelo ORIGINAL sin bola (los mismos 3 tipos de suelo que 45-47/48-50, ya sin nada encima) |
| 0-15 | 0 (las 16) | **muro de HIERRO** — set completo de 16 piezas conectables (ver leyenda completa abajo) |
| 16-31 | 0 (las 16) | **muro de CEMENTO** (redondeado) — mismas 16 piezas que hierro, mismo orden, otro dibujo |
| 32-44 | 0 (las 13) | **muro de LADRILLO** — solo 13 piezas, análogas a hierro/cemento 0-12 (le faltan las uniones-T y el cruce, índices análogos a 13,14,15) |
| 60 | 9 | **item bola de poder** — al pasar por encima, el comecocos puede comer fantasmas temporalmente |
| 61 | 10 | **item hipopótamo** — te transforma en hipopótamo: puedes pisar/matar fantasmas, pero NO puedes comer bolas mientras dura, y los fantasmas muertos así no dan puntos |
| 62 | 11 | **item herramienta** — hace falta cogerlo para poder desclavar las bolas clavadas (ver 48-50) |
| 59 | 8 | parecida visualmente a la 60 (item de suelo) pero función sin recordar — pendiente |
| 66 | 15 | loseta sólida NEGRA — relleno/suelo liso estándar, previsiblemente usado FUERA de la zona jugable |
| 70 | 0 | muro de ladrillo suelto — el usuario no recuerda niveles que lo usen; podría cubrir alguna de las uniones-T/cruce que faltan en el set de ladrillo (los análogos a hierro/cemento 13,14,15) |
| 88,89,90 | 0,0,0 | estrellas decorativas, de pequeña a grande — relleno/adorno junto a la loseta negra (66), fuera de la zona jugable |
| 74,75,67,68 | 0,0,15,15 | **trampilla A**, en L "a derechas" — se atraviesa de derecha a izquierda. Piezas: 74=arriba-izq, 75=arriba-der, 67=abajo-izq, 68=abajo-der |
| 71,72,73,69 | 17,0,15,16 | **trampilla B**, en L "a izquierdas" — se atraviesa de izquierda a derecha. Piezas: 71=arriba-izq, 72=arriba-der, 73=abajo-izq, 69=abajo-der |
| 76,77,78,79 | 18,0,0,0 | **transición** entre trampilla A y B (y viceversa) — 4 losetas que sustituyen momentáneamente a las 4 de la trampilla mientras el comecocos empuja/vuelca la pared, antes de que aparezca la trampilla invertida. Piezas: 76=arriba-izq, 77=arriba-der, 78=abajo-izq, 79=abajo-der |
| 80 | 0 | inicio IZQUIERDO de la puerta de los fantasmas, se une al muro (complementa a 56/57) |
| 81 | 19 | inicio DERECHO de la puerta de los fantasmas, se une al muro (complementa a 56/57) — comparte tipo `19` con la loseta 82 (remate izquierdo de la pista de avión), pese a ser visual y funcionalmente algo distinto |
| 56,57 | 5,6 | línea eléctrica que hace de puerta de la casa de los fantasmas — visualmente parecen la misma loseta pero tienen tipos distintos (5 y 6), consistente con el patrón "tipo único por loseta" de este rango. HIPÓTESIS del usuario (sin confirmar): una de las dos deja pasar al comecocos y la otra no — recuerda algún nivel con una bola DENTRO de la propia casa de los fantasmas, lo que encajaría con que exista una variante "atravesable" |
| 55 | 4 | pista vertical del TANQUE — analoga a la 58 (extremo a extremo), pero convierte en tanque; ademas de disparar en la direccion de avance, se puede alternar disparo a izquierda/derecha durante el recorrido |
| 58 | 7 | pista de despegue/aterrizaje del avión (tramo recto) — se entra por un extremo y se sale por el otro; conviertes al comecocos en avión y puedes disparar. En el nivel se pintan varias contiguas |
| 82 | 19 | remate IZQUIERDO de la pista de avión |
| 83 | 0 | remate DERECHO de la pista de avión |
| 84,85,86,87 | 0,10,10,0 | 4 piezas de un mosaico decorativo con la cara del comecocos — es muro/adorno de algunas fases, NO suelo (pese a que dos piezas comparten tipo 0 con el suelo) |

Nota de patrón: los tipos 4-14 (índices de gráfico 55-65) parecen
ser, cada uno, EXCLUSIVOS de una sola loseta (una escalera
1-a-1: gráfico 55→tipo4, 56→tipo5 ... 65→tipo14), a diferencia del
tipo 0 (compartido por ~48 losetas) o tipos como 10/15/19
(compartidos por 2-3). Sin confirmar todavía si esos tipos
"únicos" tienen alguna relación entre sí (podrían ser, p.ej.,
losetas especiales cada una con su propia lógica dedicada en el
motor, en vez de pertenecer a una categoría compartida).

Primera pista semántica real sobre qué significa un "tipo": el
tipo `1` agrupa las 3 variantes de "bola clavada" (45-47→48-50,
mismo suelo, bola en otro estado) — parece confirmar que el tipo
SÍ está ligado a comportamiento/interacción (aquí: "¿se puede
comer directamente o hace falta la herramienta primero?"), no solo
a colisión pasillo/muro. Pero esto invierte lo esperado en el
suelo SIN bola (63,64,65): ahí, en vez de compartir un tipo común
"es suelo caminable", cada una de las 3 variantes de terreno tiene
su PROPIO tipo único (12,13,14) — o sea, cuando el suelo tiene
bola (cualquier terreno) el tipo se unifica en 0 o 1 según el
estado de la bola, pero cuando NO tiene bola el tipo SÍ distingue
el terreno. Confirma que "tipo" mezcla al menos dos ejes distintos
(estado de la bola + variante de terreno) de forma no trivial —
sin resolver del todo, pendiente de más identificaciones.

## INIT (0x8F24) — desensamblado y transcrito hasta 0x8F71

Bytes verificados directamente contra el `.BIN` original:

```asm
LD SP, $0FFF          ; NO es $FFF0 como se asumia antes
CALL $881B             ; sin identificar (ver mas abajo)
DI
CALL $1000             ; LITERAL, ver resolucion del misterio abajo
CALL $CF8B             ; vacia ranuras 0,1,2
XOR A  \ LD DE,$CDCB \ CALL $C4A0   ; ranura 0
LD A,1 \ LD DE,$CDFF \ CALL $C4A0   ; ranura 1
LD A,2 \ LD DE,$CE0C \ CALL $C4A0   ; ranura 2
.loop:  CALL $5D0A \ JR Z,.loop     ; sondeo (virtual, sin identificar)
CALL $CF8B
CALL $6429             ; virtual, sin identificar
EI
CALL $CF8B
CALL $5B56             ; virtual, sin identificar -- VER NOTA
CALL $CF8B
LD A,3    \ LD ($2C27),A
LD HL,0   \ LD ($2C29),HL
LD A,1    \ LD ($2C07),A
XOR A     \ LD ($2C2C),A
CALL $CF8B
; sigue sin transcribir a partir de aqui ($8F74)
```

Confirma lo que decían las notas previas (SP, instala algo, CALL
0x1000, 3 llamadas a 0xC4A0 con esos 3 punteros exactos) y añade
detalle nuevo. Transcrito en `src/madmix1.asm` como `INIT`.

### Misterio resuelto: qué hace realmente "CALL 0x1000"

`CALL $1000` en INIT es una instrucción literal (bytes `CD 00
10`), no una idea aproximada. `$1000` es EXACTAMENTE la dirección
donde `MADMIX0.BIN` (58 bytes) se BLOADea. Esto explica todo el
mecanismo de arranque:

1. BASIC llama a `START` (`0x8400`), que hace `JP $8F24` = `INIT`
   (ejecutándose todavía desde la copia ESTATICA, sin reubicar).
2. `INIT` hace su setup y `CALL $1000` → esto invoca a
   `MADMIX0.BIN`, el loader, que vive ahí.
3. `MADMIX0.BIN` hace DI, conmuta slots, `LDIR` 0x8800→0x1000
   (0x5500 bytes) — esto SOBREESCRIBE su propio cuerpo restante
   (solo 58 bytes, muy por debajo de 0x5500) — y luego hace
   `CALL 0x1000` OTRA VEZ, esta vez ejecutando el bloque YA
   reubicado (lo que antes vivía en `0x8800` estático).
4. Esa segunda llamada nunca vuelve en juego normal (bucle de
   juego dirigido por interrupciones) — por eso da igual que la
   cola de `MADMIX0.BIN` (restaura slots, EI, RET) haya quedado
   sobreescrita: nunca se vuelve a ejecutar. Es un "loader que se
   autodestruye tras saltar a su payload", truco clásico de 8
   bits.

### Misterio SIN resolver: mezcla de direcciones estáticas/virtuales

Dentro de `INIT` (que corre desde su copia reubicada, según el
punto anterior), `CALL $881B` usa la dirección ESTATICA tal cual
(no la virtual `$101B`), mientras que las llamadas siguientes
(`$5D0A`, `$6429`, `$5B56`) SI son direcciones bajas/virtuales
(dentro de `0x1000-0x6500`). No está claro por qué esta mezcla —
quizás `$881B` es una rutina que da igual qué copia ejecute, o
quizás la convención estática/virtual del original no es tan
limpia como "todo el bloque reubicado siempre usa direcciones
virtuales". Pendiente de aclarar con trazado en vivo (emulador +
debugger), no asumir una respuesta.

### Hallazgo intrigante SIN investigar: `$5B56` cae dentro de `maze_data.bin`

`$5B56` es una dirección virtual; su estática equivalente es
`0x8800 + ($5B56-$1000) = 0xD356`, que cae DENTRO del rango que
veníamos asumiendo como `maze_data.bin` (`0xD000-0xD500`, ver
`data/maze_data.bin`). Si `INIT` hace un `CALL` a una dirección
que "debería" ser dato de laberinto, o (a) el rango real de
`maze_data` es distinto de `0xD000-0xD500`, o (b) esa zona mezcla
código y datos, o (c) es una coincidencia y `$5B56` cae en otra
zona por un error de cálculo en este documento. Pendiente de
verificar antes de dar por buena la extracción actual de
`maze_data.bin`.

**CORREGIDO/CERRADO** (sesión posterior): el cálculo de "dirección
estática equivalente" de este párrafo (`0x8800 + ($5B56-$1000)`)
partía de la hipótesis de que `madmix1.asm` también se reubicaba con
`PHASE`, hipótesis que se descartó del todo poco después (ver nota
al principio de `madmix1.asm`: el motor corre desde direcciones
ESTÁTICAS, `PHASE` solo aplica de verdad a `madmix_scr.asm`). Con eso
corregido, `CALL $5B56` en `INIT` es simplemente una llamada directa
a código YA reubicado en RAM baja por `MADMIX0.BIN` -- cae dentro de
`madmix_scr.asm` (cerca de `TI_5B62`, en la pantalla de menú
principal), sin ninguna relación con `maze_data.bin`. El verdadero
motivo por el que `maze_data.bin` existe se resolvió por otro camino
completamente distinto -- ver la sección "RESUELTO EL PROPÓSITO DE
`maze_data.bin`" más abajo.

## Gestor de recursos (código real, entendido) -- ACTUALIZADO, ver milestone completo más abajo

Notas iniciales de esta sección (sesión anterior, desensamblado
parcial). **Ampliadas** en la sección "MILESTONE: `0xC4A0-0xD000`
transcrito completo" más abajo -- ahí está el análisis definitivo
(identificado como el driver de sonido del PSG, no solo un
"gestor de recursos" genérico). La dirección `0xCF8B` de
`LOAD_RESOURCE_SLOT_EMPTY` era correcta desde el principio -- un
primer intento de esta sesión la "corrigió" por error a `0xCF8E`
(un fallo propio de extracción de bytes, no del binario), y se
volvió a corregir de vuelta a `0xCF8B` tras verificar con `--sym`
y byte-diff que los `CALL` reales de `INIT` apuntan ahí.

- `0xC9C9`: tabla de 4 ranuras de 46 bytes cada una
- `0xC4A0`: busca ranura libre entre las 4 y la ocupa con
  puntero DE (auto-allocate)
- `0xC4CC`: fuerza directamente la ranura número A = puntero DE
  (sin buscar)
- `0xC88D`: multiplicación de 16 bits genérica, HL = A × DE
- `0xCF8B` (confirmado): vacía las ranuras 0,1,2 (llama a `0xC4CC`
  con DE=0 tres veces) — se llama varias veces durante el arranque
- `0x8F24` (init real): SP, instala ISR, `CALL 0x1000` (bloque
  reubicado — persiste durante todo el juego, no solo al
  arrancar), luego 3 llamadas a `0xC4A0` con índices 0,1,2 y
  punteros a `0xCDCB`/`0xCDFF`/`0xCE0C` (confirmado: son 3 scripts
  de sonido/música reales, dentro del propio bloque de datos del
  driver -- ver milestone más abajo)

## Hipótesis descartadas o corregidas durante la sesión

- ~~Lógica del juego a 25Hz, gráficos a 50Hz~~ → FALSO, todo
  corre a la misma frecuencia de interrupción (ver arriba)
- ~~0xB940 es la matriz del mapa~~ → FALSO, es la tabla de
  gráficos de loseta; la matriz real es `0xFC60`
- ~~0xC300 es una tabla de trayectorias de fantasmas~~ →
  probablemente FALSO, al renderizarlo como bitmap parece ser
  más gráfico de loseta, no datos de movimiento

## MAP_COORD_TO_ADDR (0x8CB6) descifrado completo -- confirma matriz de 32 columnas, y que `maze_data.bin` es UN SOLO nivel, no los 15

Desensamblado completo de `0x8CB6` (via Z80Dasm.exe):

```asm
PUSH AF
PUSH BC
LD HL,($2C02)      ; posicion camara/comecocos (confirmado en otra seccion)
LD D,H
LD E,L
LD A,H
ADD A,B
AND $7C
RRCA
RRCA
LD B,A
LD A,L
ADD A,C
AND $7C
RLCA
RR B
RRA
RR B
RRA
RR B
RRA
LD C,A
LD HL,$FC60
ADD HL,BC
POP BC
POP AF
RET
```

El patrón `AND $7C` + rotaciones (`RRCA` x2 para la fila, `RLCA`+
`RR B`/`RRA` x3 para la columna) es el modismo clásico de Z80/MSX
para calcular `direccion = base + fila×32 + columna`. El **32 sale
directo de las constantes del código**, no es una suposición.

**Esto confirma con hechos, no solo con conteo visual, la
observación del usuario**: contó 25 losetas visibles de ancho en
el nivel 1 + 7 losetas más en el pasillo de "dar la vuelta" = 32
exacto, coincidiendo con la constante real del código.

**Consecuencia importante para el almacenamiento**: `data/maze_data.bin`
mide 1280 bytes. `1280 ÷ 32 = 40` filas exactas -- un número muy
limpio, consistente con que sea **un único nivel completo** de
32×40 losetas (más alto que una pantalla, lo cual encaja con que
la cámara hace scroll vertical seguiendo al comecocos). Pero eso
significa que **`maze_data.bin` NO puede contener los 15 niveles**
-- solo da para uno. **Los otros 14 niveles tienen que estar en
otra parte de la ROM que todavía no hemos localizado.** Candidatos
para seguir buscando: el resto de `0xD500-0xDDA0` (zona todavía sin
mapear del todo, ver hallazgo de la tabla en `0xDC00` justo abajo,
que ya sabemos que NO es datos de nivel) o más allá de `0xDDA0`
si el mapa de memoria original subestimaba el tamaño real del
fichero.

## Zona 0xDC00 (dentro de "0xD500-0xDDA0 sin explorar"): tabla estática confirmada, sin descifrar todavía

Siguiendo el hilo del cursor `$8438` (ver corrección de dirección
más arriba): se comprobó `0xDC00` en los 5 volcados de RAM en vivo
(`ram.bin` a `ram5.bin`, distintos momentos/estados de juego) --
**0 diferencias entre todos ellos**. Es una zona completamente
estática, no se modifica en juego. Se buscó esa secuencia de bytes
en `MADMIX1.BIN` y coincide EXACTA en la misma dirección `0xDC00`
del fichero -- confirma que es simplemente parte de la imagen
estática del `.BIN` tal cual se BLOADea, sin ninguna copia ni
transformación previa.

Contenido completo extraído (`0xDC00`-`0xDD7F`, 384 bytes): una
tabla de valores de 16 bits en pares (byte bajo, byte alto), con
el byte alto casi siempre en el rango `01`-`07` y el bajo variado
-- no tiene pinta de bitmap de sprite típico (demasiado
estructurado). A partir de `0xDD80` hay código Z80 real y
reconocible: conmutación de slots (`OUT ($A8),A` con `A=$55`) +
`JP $8400` (reinicio del juego), y una pequeña rutina de lectura
de puertos PSG (`$A0`-`$A2`, típicamente joystick/teclado en MSX)
-- posible rutina de reset/comprobación especial, sin investigar
el disparador. De `0xDD92` en adelante son bytes `$FF` de relleno
hasta el final documentado del fichero (`0xDDA0`).

**Intento de renderizar la tabla como imagen (máscaras AND/OR)**:
dado que `JTS2_PROCESS_ACTORS` consume esta zona vía 6 `POP DE`
sucesivos (cada `DE` = un par AND/OR de 16 bits que mezcla con el
fondo por `AND E`/`OR D`), se probó renderizar los 192 pares
completos como si cada uno fuera una fila de 8 píxeles (usando el
byte OR). **No salió ninguna forma reconocible** -- solo una franja
con puntos sueltos, coherente con que casi todos los valores solo
tienen los 3 bits bajos activos.

**Conclusión / pendiente**: el planteamiento de "renderizar toda
la tabla de una vez" era probablemente erróneo -- `
JTS2_PROCESS_ACTORS` solo lee 6 pares (12 bytes) por llamada,
empezando en un offset concreto calculado por `ADDR_FROM_DC00`
según la posición del actor en ese momento, no la tabla entera.
Para ver algo con sentido haría falta calcular el offset EXACTO
para un actor real capturado (con posición conocida) y renderizar
solo esos 12 bytes. Tampoco está confirmado que
`JTS2_PROCESS_ACTORS` sea el que dibuja personajes como tal --
podría ser un subsistema distinto (el icono "chispa" del HUD, las
bolas coleccionables, etc.), ya que usa mezcla OR simple sin el
desplazamiento de sub-píxel bit a bit que sí usan
`JTS2_RENDER_A`/`JTS2_RENDER_B` (los que sabemos que SÍ dibujan
actores con movimiento fino). Aparcado aquí -- buen punto de
partida si se retoma esta zona.

## Mecánica de movimiento de fantasmas: paso fijo de 4 píxeles, sincronizado

Confirmado analizando una secuencia de 5 capturas de pantalla
(`src/dump_openmsx/secuencia/paso 1.png` a `paso 5.png`, casa de
los fantasmas con 2-3 fantasmas visibles) que el usuario hizo
pulsando F5 repetidamente en openMSX hasta detectar movimiento, y
capturando en ese instante.

**Metodología**: se detectaron las siluetas de los fantasmas por
"tramos de color sólido" (no por brillo -- el color del fantasma y
el de la pared son casi idéntico tono, pero la pared alterna en
patrón de rejilla píxel a píxel mientras el fantasma es relleno
sólido, así que buscar tramos de ≥4 píxeles del mismo color
consecutivos los separa bien del fondo). Se midió el centro X de
cada silueta en una fila fija (y=48) que atraviesa el cuerpo.

**Corrección de escala importante**: las capturas se hicieron con
openMSX a **zoom x2, con scanlines y 50% de blur activados** -- las
medidas en píxeles del PNG hay que dividirlas entre 2 para tener
píxeles nativos de MSX, y esperar algo de ruido por el blur.

**Resultado** (posiciones en píxeles nativos, tras dividir entre 2):
en cada evento de movimiento (pasos 2→3 con 2 fantasmas, pasos
4→5 con 3 fantasmas), TODOS los fantasmas activos se desplazan
**la misma magnitud, ~4 píxeles nativos (medio tile de 8x8)**,
pero cada uno en su propia dirección (algunos +4, otros −4) --
consistente con que cada fantasma rebota entre sus propios límites
de patrulla, pero el "tick" de movimiento en sí está sincronizado
para todos los actores a la vez.

**Confirmado por el usuario**: el movimiento se dispara de forma
irregular en tiempo real (a veces a la 3ª pulsación de F5, a veces
a la 4ª, a veces a la 5ª -- osea, un contador/temporizador variable
antes de decidir "toca mover"), pero CUANDO se dispara, mueve a
todos los actores a la vez, por la misma distancia fija. Encaja
con `$8437` (contador de actores) siendo recorrido en una sola
pasada por el motor de `JT_SLOT2`/`ACTOR_ENGINE` -- ver sección de
abajo. Todavía sin identificar en el código desensamblado cuál es
el contador/temporizador variable que decide CUÁNDO toca el
siguiente movimiento (posible pista para cuando se retome el
análisis de `ACTOR_ENGINE`: buscar una variable que se
incremente/compare cada frame con un valor no fijo, o aleatorio,
antes de disparar el desplazamiento de 4px).

## MILESTONE: JT_SLOT2 transcrito a madmix1.asm, BYTE A BYTE EXACTO (0 diferencias en 960 bytes)

Todo el motor de actores (0x8440-0x87FF, ver análisis debajo) está
ahora en `src/madmix1.asm` como `ACTOR_ENGINE` y sus sub-rutinas
(`JTS2_RENDER_A`/`B`, `JTS2_COPY_CURSOR`, `JTS2_RESUME`,
`JTS2_XOR_TRANSFORM`, `JTS2_SWAP_SORT`, `JTS2_PROCESS_ACTORS`).
Verificado comparando el `.BIN` compilado contra el original byte
a byte en todo el rango: **0 diferencias en 960 bytes**. Quedan
dos tablas de datos sin extraer (`$87FB`, de la que solo se
conocen 5 bytes reales -- SÍ transcritos -- y `$91C3`, que cae
fuera de este bloque y sigue sin localizar) y el propósito
semántico de varias piezas sigue sin confirmar (ver comentarios en
`madmix1.asm` y el análisis de abajo), pero la ESTRUCTURA y el
CONTENIDO byte a byte están cerrados. Al transcribir se detectaron
y corrigieron varios errores de mi primera pasada (etiquetas de
bucle desplazadas 1-2 instrucciones, dos escrituras
automodificadas con el destino intercambiado) -- todos encontrados
precisamente GRACIAS a la comparación byte a byte, no a inspección
visual.

## JT_SLOT2 (0x8440-0x8800): el motor de "actores" -- zona residente completa desensamblada

Usando `Z80Dasm.exe` (ya incluido en `FISICO\MADMIXGAME_DISC\`) con
los parámetros correctos (`-begin 7 -offset 8400`, para saltarse
la cabecera de 7 bytes y numerar con direcciones reales) se generó
un desensamblado fiable de TODO el hueco residente 0x8440-0x8800
(960 bytes, el objetivo de `JT_SLOT2`). Esto sí que hay que
recordarlo para el futuro: `Z80Dasm.exe -begin 7 -offset 8400
MADMIX1.BIN > salida.txt` da direcciones reales directamente, sin
tener que hacer la aritmética a mano.

Es un sistema de **actores/objetos en movimiento** (personajes,
casi seguro), no solo una rutina suelta. Piezas identificadas:

- **`0x8437`** confirmado como **contador de actores activos**: hay
  un bucle en `0x86BB` que decrementa `0x8437` y avanza un puntero
  IX en -12 bytes cada vez (registros de actor de 12 bytes,
  probablemente), hasta llegar a 0 -- y es la MISMA variable que
  `JT_SLOT3`/`RESET_8437` pone a cero. Encaja: la API pública
  puede "vaciar" la lista de actores activos.
- Un registro de actor accedido vía `IX+0` a `IX+9` (10+ campos:
  posición on-screen, puntero a datos, contador de frames...).
- **`ADDR_FROM_DC00` (0x8988) SE USA DE VERDAD** (`CALL $8988` en
  `0x84AD`) -- confirma la hipótesis anterior: convierte una
  coordenada en una dirección dentro de la zona `0xD500-0xDDA0`.
- Dos tablas de datos: `0x92E3` (registros de 10 bytes, mismo
  layout que el struct de actor -- probablemente "definición
  inicial por tipo de actor/personaje") y `0x91C3` (registros más
  pequeños).
- **Render por software con desplazamiento de sub-píxel**: dos
  bloques de código casi idénticos (`0x85C1` y `0x8624`,
  seleccionados vía `JP (IY)` calculado según la posición del
  actor) hacen rotaciones de bit (`RL`/`RR` encadenados con
  `EXX`) para desplazar una máscara de 24 bits pixel a pixel
  dentro de filas de 32 bytes de stride, con `AND`/`OR` para
  mezclarla con el fondo -- exactamente el mismo estilo que
  `REDRAW_STRIP` (0x8D1B) pero aplicado a un objeto que se mueve
  con movimiento FINO (no saltos de loseta completa).
- **Código automodificable**: en `0x8779` hay una rutina que
  ESCRIBE valores directamente en los operandos de instrucciones
  más adelante (`LD ($87B6),A`, `LD ($87D4),A`, etc.) -- técnica
  clásica de rendimiento en 8 bits de 1987.

### Implicación gorda para el misterio de los sprites de personajes

Si los actores/personajes se renderizan con este sistema de
software (rotación de bits sobre un buffer, igual estilo que las
losetas del laberinto), **puede que NO usen sprites de hardware
del VDP en absoluto** -- lo cual explicaría por qué la búsqueda de
"quién escribe el registro 6 del VDP" no encontró nada, y por qué
NINGÚN formato de sprite de hardware (raster 16x16, cuadrante
16x16, 8x8 independientes) dio una imagen con sentido para
`0x9D40-0xA3E0`: puede que ese candidato nunca fuera sprites de
hardware, sino que los gráficos reales de los personajes estén en
otro sitio, en el MISMO formato raster que `tile_gfx.bin` (que ya
sabemos que decodifica bien).

### Rastreado IX+5/+6 (puntero de gráficos) -- lleva a un callejón sin salida ESTÁTICO

- **`0x92E3`, stride 12 bytes**: confirmado que ES el array de
  actores activos en sí (no una "tabla de definición" separada).
  `IX = $92E3 + (valor_de_$8437_antes_de_incrementar) × 12` -- o
  sea, `$8437` funciona como "índice de la próxima ranura libre"
  al crear un actor, ADEMÁS de como contador al recorrerlos luego.
- **`IX+5`/`IX+6`** (el puntero fuente que alimenta el bucle
  copiador de `0x8687`, el que extrae 3 bytes de cada bloque de 32)
  se rellena desde una variable "cursor" en **`0x8438`** -- y esa
  MISMA rutina de `0x8687` es la que ACTUALIZA `0x8438` al
  terminar (`LD ($8438),DE` en `0x86B0`). Es un cursor que avanza
  secuencialmente cada vez que se crea un actor nuevo, leyendo un
  poco más del mismo flujo de datos.
- El valor INICIAL de ese cursor (antes de crear el primer actor,
  cuando `$8437`==0) es literal **`$0500`** (`LD DE,$0500` en
  `0x851A`) -- una dirección de RAM baja, fuera tanto de la imagen
  estática (0x8400-0xDDA0) como del bloque reubicado (0x1000-0x6500).
  Se buscó en TODO el fichero (22945 bytes) cualquier otra
  instrucción que escriba algo EN `$0500` (osea, qué copia los
  gráficos reales ahí antes de que se lean) -- **no aparece
  ninguna**. Callejón sin salida para el análisis estático: o algo
  deja esos datos ahí por otro medio (el cargador BASIC, la BIOS,
  un BLOAD separado...), o hace falta ver la memoria en vivo con
  un emulador para saber qué hay realmente en `$0500` en ese
  momento del juego.

**Recomendación**: este hilo concreto (encontrar el puntero real a
los gráficos de personajes) ha llegado al límite de lo que da el
análisis estático por ahora. Los dos caminos que quedan abiertos
son (a) descifrar el intérprete de bytecode de las cabeceras de
recursos (`0xCDCB`/`0xCDFF`/`0xCE0C`, confirmado que SÍ es un
bytecode tokenizado con prefijo `85 64` y opcodes ≥`0x80` -- un
lenguaje propio, no un puntero directo, así que hace falta
localizar primero su intérprete, que sigue sin encontrarse) o
(b) trazado en vivo con emulador+debugger, que muy probablemente
resuelva esto mucho más rápido que seguir tirando de bytes a mano.

### CORRECCIÓN IMPORTANTE: la dirección de la copia estaba al revés

Todo lo anterior sobre "IX+5/6 es el puntero FUENTE de gráficos"
estaba mal interpretado. Revisando `JTS2_COPY_CURSOR` (0x8687) con
calma:

```
LD L,(IX+$05) / LD H,(IX+$06)   ; HL = cursor ($8438/IX+5/6)
LD E,(IX+$02) / LD D,(IX+$03)   ; DE = buffer (ADDR_FROM_DC00)
EX DE,HL                         ; AHORA: HL=buffer, DE=cursor
...
LDI                              ; copia (HL)->(DE)
```

`LDI` copia SIEMPRE de `(HL)` a `(DE)`. Tras el `EX DE,HL`, HL es
el buffer (calculado a partir de la posición del actor, dentro de
`0xDC00`) y DE es el cursor. O sea: la copia va del **buffer
dependiente de posición HACIA el cursor en `$0500+`**, no al
revés. El cursor no es "de dónde sale el gráfico" -- es un
**buffer de salida/registro** que se rellena leyendo de la zona
`0xDC00` (dentro de "0xD500-0xDDA0 sin explorar"). Esto explica
por completo por qué la búsqueda de esos bytes en la ROM no dio
nunca ningún resultado (ver más abajo): no es un recurso estático
copiado una vez, es una zona que se recalcula en tiempo de
ejecución a partir de dónde está cada actor.

Se intentó confirmar buscando los bytes reales de `$0500` (de
varios volcados de RAM en vivo) en `MADMIX1.BIN`, en `MADMIX.SCR`
(21768 bytes) e incluso en el `.dsk` completo (737280 bytes) --
**cero coincidencias en los tres**, ni con fragmentos de 8 bytes.
Confirma la conclusión: esta zona no es una copia de un recurso
estático, se genera en tiempo real. Pendiente: investigar qué hay
de verdad en `0xDC00` (la zona real de origen) y su relación con
la posición del actor -- podría conectar con la tabla de 128
bytes/entrada que se menciona justo debajo.

### Hallazgo suelto sin relacionar: "$0500" como CANTIDAD (no dirección) en la zona sin explorar

Buscando `$0500`, aparece 3 veces como `LD BC,$0500` (cantidad,
1280 decimal) en `0xD97B`, `0xD9FB` y `0xDA7B` -- exactamente cada
128 bytes, dentro de la zona "0xD500-0xDDA0 sin explorar". 1280
es tambien el tamaño exacto de `maze_data.bin` (0xD000-0xD500).
Probable coincidencia sin relación con la búsqueda de sprites,
pero sugiere una tabla con entradas de 128 bytes cada una en esa
zona (¿un puntero + longitud por nivel?) -- anotado para retomar
si se investiga `0xD500-0xDDA0` en el futuro.

### CORRECCIÓN + CIERRE: la tabla de 128 bytes NO son niveles -- es la tabla de máscaras de `0xDC00`, y no hay hueco en el .BIN para los 14 niveles restantes

Retomando el hilo anterior: se volcaron en crudo los bytes alrededor
de `0xD97B`/`0xD9FB`/`0xDA7B` y NO son código real -- son datos muy
repetitivos con forma `01 xx` (pares tipo palabra de 16 bits), y el
`LD BC,$0500` es una coincidencia de bytes dentro de ese blob, no una
instrucción real (el desensamblado lineal con Z80Dasm tampoco
produce una instrucción en esa dirección al desensamblar desde
`0x8400` -- confirma que cae dentro de una zona de datos, no de código).

Se recorrió la tabla completa por su patrón de stride de 128 bytes:
empieza en **`0xD8FB`** y termina en **`0xDCFB`+128=`0xDD7B`**, es
decir **9 entradas × 128 bytes = 1152 bytes**, no 3. Comparando las
entradas entre sí, varias son casi byte-a-byte idénticas (p.ej.
`0xD9FB` y `0xDA7B` comparten sus primeros ~32 bytes exactos), lo
cual encaja mucho más con una **tabla de máscaras/patrones de bits**
(para el render sub-píxel de actores, mismo espíritu que las cadenas
`RL`/`RR` de `JTS2_RENDER_A`/`JTS2_RENDER_B`) que con parámetros de
nivel.

**Esto es la MISMA zona que ya conocíamos como "tabla estática de
`0xDC00`"** (ver hallazgo siguiente) -- simplemente se extiende hacia
atrás hasta `0xD8FB`, no empieza en `0xDC00` como se había acotado
antes. Se corrige aquí ese límite.

**Conclusión sobre los 14 niveles restantes**: con este hallazgo, el
`.BIN` completo (`0x8400`-`0xDDA0`, 22952 bytes) queda prácticamente
todo mapeado o justificado:
- `0x8400-0x8800`: jump table + `ACTOR_ENGINE` (confirmado byte a byte)
- `0x8800-0xB940`: código principal (parcialmente transcrito)
- `0xB940-0xC4A0`: `tile_gfx.bin` (2912 bytes, confirmado)
- `0xC4A0-0xD000`: gestor de recursos (2912 bytes, sin transcribir pero identificado como código, no datos de nivel)
- `0xD000-0xD500`: `maze_data.bin`, UN nivel (1280 bytes, confirmado)
- `0xD500-0xD8FB`: todavía sin mapear (~1019 bytes)
- `0xD8FB-0xDD7B`: tabla de máscaras/render de actores (1152 bytes, este hallazgo)
- `0xDD7B-0xDDA0`: cola/relleno (~37 bytes)

**No queda ni remotamente sitio para 14 niveles más de 1280 bytes
cada uno (17920 bytes) en ningún hueco de este fichero.** Además se
comprobó el listado completo del disco
(`FISICO/MADMIXGAME_DISC/.../Mad MIX Game (1987)(Topo Soft)(Sp)/`):
solo existen `AUTOEXEC.BAS`, `MADMIX` (184 bytes, BASIC tokenizado,
es un loader "cracked by Pau d'Aci" que carga los mismos 3 ficheros
de siempre), `MADMIX.BAS`, `MADMIX.SCR` (21768 bytes, pantalla de
carga/título), `MADMIX0.BIN` (58 bytes) y `MADMIX1.BIN` (22952
bytes) -- **no hay ficheros sueltos por nivel** (nada tipo
`LEVEL1.DAT`, `MADMIX2.BIN`, etc.).

**Esto pone en duda la premisa de partida de "15 niveles con mapa
propio de 32×40"**: o (a) los niveles se generan/derivan
proceduralmente o por transformación de un único mapa base
(rotación, espejo, cambio de paleta/tema visual reutilizando la
misma matriz), o (b) "15 niveles" en la memoria del jugador no
significa 15 laberintos geométricamente distintos, sino 15
repeticiones/vueltas con dificultad creciente sobre pocos mapas
base (o el mismo mapa). **Pendiente de contrastar con el usuario**,
que jugó el juego originalmente y puede aclarar si el laberinto
cambia de verdad de forma visible entre niveles.

**Respuesta del usuario: el laberinto SÍ cambia geométricamente
entre niveles** (no es el mismo trazado reciclado con otra
dificultad). Esto obliga a seguir buscando -- los 15 mapas existen
en algún formato, en algún sitio.

### LOCALIZADO: el intérprete de bytecode de recursos (pieza que llevaba varias sesiones pendiente)

Desensamblando `0xC4A0` en el `.BIN` real (no en la posición
interna, todavía incompleta, de `madmix1.asm`) aparece el cuerpo real
del "gestor de ranuras de recurso" ya conocido (`0xC4A0-0xC900`,
ver tabla de zonas), y dentro de él, a partir de `~0xC4EB`, un
**intérprete de bytecode real**:

```
LD C,(IX+2) / LD B,(IX+3)      ; BC = puntero al programa de bytecode
...
LD A,(BC)                      ; lee un byte del programa
CP $80
JP C,$C527                     ; < 0x80: byte "literal" (rama aparte)
SUB $80
LD HL,$C99E
CALL $C8BC                     ; HL = $C99E + A*2 (tabla de punteros de 2 bytes)
JP (HL)                        ; salta a la rutina del opcode
```

Esto es EXACTAMENTE el intérprete que se buscaba desde la sección
anterior ("descifrar el intérprete de bytecode... que sigue sin
encontrarse") -- estaba dentro del mismo `0xC4A0-0xC900` que ya
figuraba como "gestor de recursos, código real" en la tabla de zonas,
solo que no se había entrado en su cuerpo hasta ahora.

**Tabla de despacho `0xC99E`**: 15 punteros válidos (`0xC6E5`,
`0xC703`, `0xC765`, `0xC6EE`, `0xC761`, `0xC733`, `0xC774`, `0xC7AB`,
`0xC74D`, `0xC7F4`, `0xC797`, `0xC70E`, `0xC84B`, `0xC867`, `0xC878`),
todos dentro de `0xC6xx-0xC8xx` (justo antes del propio intérprete),
seguidos de ceros de relleno hasta completar 32 entradas. Es decir:
**15 opcodes reales** (`0x80`-`0x8E`), cada uno con su rutina de
"comando de dibujo" propia -- casi seguro un intérprete de gráficos
vectoriales/comandos compactos (tipo "traza línea", "rellena",
"copia bloque"...) para las cabeceras de recursos `0xCDCB`/`0xCDFF`/
`0xCE0C` ya conocidas.

**Sobre si esto explica los 15 niveles**: de momento NO se puede
confirmar. Lo único que sabemos con certeza de las llamadas reales a
`0xC4A0` es que solo hay **3** en toda la ROM (las de `INIT`, con
punteros a `0xCDCB`/`0xCDFF`/`0xCE0C`, ranuras 0/1/2 -- ver sección
de arriba) -- no hay una cuarta llamada, ni 15, en ningún sitio
detectado hasta ahora. Eso sugiere que estas 3 cargas de recurso son
para algo fijo (paleta, marco de caramelo, título...) y NO para
niveles, salvo que el motor cargue niveles por un camino distinto
(quizás llamando directamente a las rutinas de opcode sin pasar por
el registro de ranura de `0xC4A0`, o los 15 mapas usan otro formato
completamente aparte todavía sin localizar).

**Conclusión honesta de este hallazgo**: es una pieza real y valiosa
del rompecabezas (cierra una pregunta abierta de sesiones anteriores:
"el intérprete no se ha localizado"), pero **no resuelve por sí solo
dónde están los otros 14 niveles**. El hueco grande y genuinamente
sin explorar sigue siendo `0x8800-0xB940` (código principal, la
muestra tomada en `0x8F71-0x8FF0` es lógica de juego real y densa,
no una tabla de datos, pero no se ha recorrido entero) y el propio
cuerpo de las 15 rutinas de opcode (`0xC6E5`-`0xC8xx`) junto con las
cabeceras `0xCDCB`-`0xCF8B`, que aún no se han leído línea a línea.
Siguiente paso razonable: leer qué hace cada una de las 3 cabeceras
conocidas (¿cuántos bytes de programa tiene cada una? ¿qué opcodes
usa?) para saber si este lenguaje sería, en principio, capaz de
codificar un laberinto de 32x40 en un espacio razonable.

### El bytecode tiene CALL/RET de subrutinas -- y una tabla de punteros real en 0xCB72 (pero NO es la tabla de niveles)

Sugerencia del usuario: ya que hay 15 niveles, buscar en la zona de
datos una **tabla de punteros** (probable formato RLE dado que son
mapas de casillas). Se escribió un script que recorre TODO el `.BIN`
buscando tramos de 15+ palabras de 16 bits consecutivas cuyo valor
cae siempre dentro del rango válido `0x8400-0xDDA0` (huella típica
de una tabla de punteros). Salieron 3 zonas candidatas serias:

- `0x8A0E`: **descartada** -- es la instrucción `LDI` (`ED A0`)
  repetida muchas veces seguidas (un bucle desenrollado de copia),
  no una tabla; el byte `ED A0` cae en rango válido por pura
  coincidencia.
- `0xCE10`: **descartada** -- son los propios bytes del programa de
  bytecode de la cabecera `0xCE0C` (operandos/opcodes reales del
  lenguaje), no una tabla de punteros.
- **`0xCB72`: SÍ es una tabla de punteros real.** 12 direcciones
  crecientes (`0xCB9C, 0xCBD3, 0xCC1C, 0xCC45, 0xCC96, 0xCCD0,
  0xCCEF, 0xCD16, 0xCD3F, 0xCD76, 0xCD91, 0xCDAB`), con "trozos"
  de tamaño variable entre entradas consecutivas (26 a 81 bytes) --
  encaja con bloques de longitud variable tipo RLE. Le sigue una
  13ª entrada (`0xCBB0`) y luego 8 entradas repetidas idénticas a la
  primera (`0xCB9C`), probablemente slots sin usar/por defecto.

**Se rastreó qué código usa esta tabla** (única referencia a los
bytes `72 CB` en todo el `.BIN`: `0xC85D`) y resulta ser el
manejador del **opcode `0x8C`** de la propia tabla de despacho
`0xC99E` que ya conocíamos. Desensamblado (`0xC84B-0xC875`):

```
; opcode 0x8C: "CALL subprograma(indice)"
LD A,($C9BC)      ; indice de ranura activa (el mismo $C9BC que
                   ; el usuario vio variar al ritmo de la música)
INC BC
ADD A,A
LD L,A \ LD H,0
LD A,(BC)          ; A = byte-operando = indice de subprograma
INC BC
LD DE,$CA61
ADD HL,DE
LD (HL),C \ INC HL \ LD (HL),B   ; guarda el BC actual (retorno) en $CA61+ranura*2
LD HL,$CB72
CALL $C8BC         ; HL = $CB72 + indice*2  (tabla lookup generico)
LD B,H \ LD C,L
JP $C518           ; retoma el bucle del interprete con BC = nuevo puntero

; opcode 0x8D (siguiente en la tabla): "RET de subprograma"
LD A,($C9BC)
ADD A,A
LD L,A \ LD H,0
LD DE,$CA61
ADD HL,DE
LD C,(HL) \ INC HL \ LD B,(HL)   ; restaura BC guardado
JP $C518
```

Es decir: el lenguaje de bytecode tiene una **llamada a subrutina
real** (con "pila de retorno" de 2 bytes por ranura activa en
`0xCA61+`), y `0xCB72` es la tabla de subprogramas reutilizables
(piezas de dibujo compartidas -- trozos de pared, esquinas, etc.)
que cualquier programa de bytecode puede invocar por índice.
**Esto confirma que el motor de gráficos es mucho más sofisticado
de lo que parecía**, pero NO es -- por sí sola -- la tabla de los
15 niveles: es infraestructura genérica del intérprete, usable por
cualquier recurso (incluido el marco de caramelo o el título).

**Se comprobó también, por si acaso, TODAS las llamadas reales a
`0xC4A0` y a `0xCF8B` en el `.BIN` completo** (búsqueda de bytes
`CD A0 C4` y `CD 8B CF`, que encontraría la llamada pase lo que
pase por el registro DE aunque se cargue dinámicamente):
- `CALL $C4A0`: exactamente 3, todas dentro de `INIT` (las ya
  conocidas, ranuras 0/1/2).
- `CALL $CF8B`: 8, todas agrupadas entre `0x8F2E` y `0x9100` (zona
  de `INIT`/arranque), ninguna dispersa por el resto del código.

**Conclusión**: el mecanismo de "ranura de recurso" de `0xC4A0` NO
se usa para cargar niveles -- se usa exactamente 3 veces, siempre
en el arranque, para recursos no relacionados con el laberinto. La
carga de los 15 niveles tiene que pasar por un camino de código
completamente distinto, casi seguro dentro del gran tramo
`0x8800-0xB940` todavía sin recorrer sistemáticamente (las dos
muestras tomadas ahí son lógica de juego normal y coherente, no
tablas, pero solo son un par de ventanas de ~100 bytes dentro de
~10KB). Ese es el sitio más prometedor para seguir.

### CORRECCIÓN: el tramo "sin explorar" es mucho más pequeño de lo estimado, y ya está prácticamente agotado -- los 15 niveles siguen sin aparecer

El usuario, viendo la memoria en vivo, señaló bloques grandes y
"estructurados pero no idénticos" entre `~0x9530` y `~0xB8A7`.
Comprobado contra el `.BIN` estático:

- Coincide con hallazgos YA documentados de sesiones anteriores
  (tabla de zonas, más arriba): fuente/iconos 8x8 (`0x9300-0x9700`),
  53 bloques de 16x16 descartados como sprites (`0x9D40-0xA3E0`), y
  sobre todo el **marco de caramelo a rayas** (`~0x9600-0xB700`,
  patrón `00/FF` repetido) -- exactamente el patrón `FF FF FF 00 00
  00` que se ve en los volcados crudos. Es decir: **es gráfico
  decorativo ya catalogado, simplemente nunca extraído al
  proyecto**, no datos de nivel nuevos.
- Desensamblando lo que hay INMEDIATAMENTE ANTES de esa zona
  (`0x9100-0x9134`) se confirma que es código real y coherente (un
  bucle de scroll sincronizado a VBLANK) que termina en un `RET`
  limpio en `0x9134`. A partir de `0x9135` el desensamblado
  degenera en basura (patrones `JR NZ`/`SBC`/`XOR` con
  incrementos regulares de operando) -- señal clara de que el
  desensamblador se ha desincronizado entrando en zona de datos.
  **Esto reduce el tramo de código realmente sin explorar de
  `0x8800-0xB940` (~10KB) a solo `0x8800-0x9134` (~2.3KB)**, y esa
  franja ya estaba en su mayoría muestreada en sesiones anteriores
  (ISR, housekeeping, FILVRM/LDIRVM/SETVRAM, LOOKUP_8978,
  ADDR_FROM_DC00, RESET_8437, WAIT_VBLANK, MAP_COORD_TO_ADDR,
  TILE_TYPE_LOOKUP, REDRAW_STRIP, TILE_TYPES, INIT).

Dentro de esa franja pequeña quedaban exactamente 3 incógnitas
reales: los objetivos de `JT_SLOT6` (`0x8E3C`), `JT_SLOT8`
(`0x89AD`) y `JT_SLOT9` (`0x8C34`) -- la única API pública del
motor (jump table en `0x8400`) que aún no se había identificado.
Se desensamblaron los 3:

- **`JT_SLOT8` (`0x89AD`)**: lee la posición cámara/comecocos
  (`$2C02`), comprueba con `AND $03` en qué "cuadrante" de sub-tile
  cae, y despacha (via `RRA`+`JP C`) a distintas rutinas de scroll
  según qué borde de loseta se ha cruzado. Es el **disparador de
  scroll** (parte del seguimiento de cámara ya conocido), no carga
  de nivel.
- **`JT_SLOT9` (`0x8C34`)**: limpia un bloque grande de VRAM (bucle
  de 36 filas escribiendo a `$DE04`+offset, más 2 rellenos de 96
  bytes vía `FILVRM`/`0x8931`), y si `$2C27` (probablemente
  contador de dígitos) es distinto de cero, **dibuja texto/marcador
  con una fuente de `0x92C3`** (la misma zona de "fuente/iconos"
  citada arriba) letra a letra invertida por puerto VDP. Es el
  **refresco del marcador/HUD**, no carga de nivel.
- **`JT_SLOT6` (`0x8E3C`)**: lee un par de flags (`$8EC4`/`$8EC6`,
  dentro de la propia tabla `TILE_TYPES`) y hace un bucle de 5
  comprobaciones sobre una tabla en `0x8E88`, construyendo un
  bitmask en `E`. Parece lógica de colisión/entrada (mismo estilo
  que `DIRBITS_TABLE`), no carga de nivel.

**Conclusión honesta**: se ha agotado la búsqueda estática
razonable dentro del código realmente disponible y sin explorar.
Ninguna de las 3 últimas incógnitas de la jump table es un cargador
de nivel, el mecanismo de recursos (`0xC4A0`) no se usa para
niveles, y no queda espacio en bruto para 15×1280 bytes en ningún
sitio del `.BIN`. **Recomendación**: el camino más rápido desde
aquí es EN VIVO, no estático -- poner un breakpoint de ESCRITURA en
el buffer ya confirmado `$FC60` (donde `MAP_COORD_TO_ADDR` coloca
la matriz de la loseta actual) y ver qué dirección de código hace
esa escritura la primera vez que arranca un nivel (o al cambiar de
nivel). Esa dirección sería, con toda probabilidad, el cargador de
nivel real, sea cual sea su formato de origen.

## RESUELTO: LOS 15 NIVELES NO ESTÁN EN `MADMIX1.BIN` -- ESTÁN EN `MADMIX.SCR`

**Este es el hallazgo más importante de varias sesiones.** Se
siguió la recomendación de arriba: el usuario puso un watchpoint de
escritura en `openMSX` sobre todo el buffer `$FC60-$FE5F`:

```
debug set_watchpoint write_mem {0xfc60 0xfe5f}
```

y arrancó el nivel 1. El primer break cayó en `PC=0x9115`
(descartado: era la animación de parpadeo de la bola, ya conocida).
El SEGUNDO break, justo al arrancar el nivel, cayó en **`PC=0x5943`,
`SP=0x0FFD`** -- **una dirección de la página baja de memoria
(0x4000-0x7FFF), FUERA POR COMPLETO del rango de `MADMIX1.BIN`**
(`0x8400-0xDDA0`).

### El cargador real: `0x5904` (memoria baja, resuelto con volcado de RAM en vivo)

Se volcó la RAM completa en el momento de la parada
(`save_debuggable memory ram_level1_load.bin 0 65536`,
`src/dump_openmsx/ram_level1_load.bin`) y se desensambló con
`Z80Dasm.exe -begin 5904 -offset 5904 ram_level1_load.bin`
(direcciones en hexadecimal como argumento, sin cabecera MSX
porque `save_debuggable` vuelca RAM cruda). Resultado completo,
coherente y sin desincronizar:

```asm
; 0x5904 -- CARGADOR DE NIVEL
LD A,($2C07)        ; A = numero de nivel actual (variable de estado)
LD HL,$59A9         ; HL = tabla de niveles (ver mas abajo)
LD BC,$0014         ; 20 bytes por registro
AND A
JR Z,$5914
  ADD HL,BC          ; HL += 20 x A veces  (HL = tabla + nivel*20)
  DEC A
  JR NZ,$5910
LD DE,$2BF3          ; copia el registro de 20 bytes a RAM de trabajo
LDIR
LD DE,$FC60          ; DE = EL BUFFER DE NIVEL YA CONOCIDO
LD HL,($2BF5)        ; HL = campo2 del registro (puntero a CABECERA fija)
LD BC,$0060          ; 96 bytes (3 filas de 32)
LDIR                 ; copia la cabecera fija a $FC60
LD A,($2BF9)         ; A = campo6 del registro (numero de filas VARIABLE)
LD L,A \ LD H,0
ADD HL,HL (x5)       ; HL = A*32  -- el stride de 32 columnas, otra vez confirmado
LD C,L \ LD B,H       ; BC = filas_variables * 32
LD HL,($2BF3)         ; HL = campo0 del registro (puntero al CUERPO del nivel)
...
; bucle principal (0x593F-0x5947):
RES 7,(HL)            ; limpia el bit "comido" de cada celda fuente
LDI                    ; copia byte a byte, BC veces, hacia $FC60+96 en adelante
JR NZ hasta BC=0
```

**Esto es exactamente el motor de reconstrucción de nivel**: copia
una cabecera fija de 3 filas + un cuerpo de longitud variable
(`campo6 * 32` bytes) a continuación, ambos hacia el buffer `$FC60`
que ya conocíamos por `MAP_COORD_TO_ADDR`.

### El origen: `MADMIX.SCR` NO es una imagen de pantalla -- es un BLOAD de código+datos que se reubica con el truco de `MADMIX0.BIN`

Cabecera real de `MADMIX.SCR` (primeros 7 bytes,
`FE 00 88 00 DD 00 88`): tipo `FE` (BLOAD de código máquina normal,
NO tipo `FF`/pantalla), **start=0x8800, end=0xDD00, exec=0x8800**
-- prácticamente el mismo rango de direcciones donde luego se carga
`MADMIX1.BIN`. Esto encaja EXACTO con el viejo hallazgo (de sesiones
previas, cuando se investigó y luego se descartó `PHASE`/`DEPHASE`
para el motor principal) de que `MADMIX0.BIN` hace un `LDIR` de
`0x8800` a `0x1000`, `BC=$5500`: ese `LDIR` no reubicaba el motor
principal (que sí corre en direcciones estáticas, como ya se
demostró) -- **reubicaba el contenido que `MADMIX.SCR` acababa de
cargar**, momentos antes de que `MADMIX1.BIN` sobrescribiera esa
misma zona con el motor real. Secuencia real de arranque:

1. `BLOAD"MADMIX.SCR"` -- carga ~21KB de código+datos en `0x8800-0xDD00` (posición de paso, no definitiva)
2. `BLOAD"MADMIX0.BIN",R` -- ejecuta el relocador: `LDIR` copia esos ~21KB desde `0x8800` a `0x1000` (memoria baja, permanente)
3. `BLOAD"MADMIX1.BIN"` -- sobrescribe `0x8400-0xDDA0` con el motor de juego (lo que llevamos meses reconstruyendo)
4. El motor (`INIT`, `0x8F71` en adelante) llama a la memoria baja ya reubicada (`CALL $5904`, `CALL $5CD1`, etc. -- llamadas que ya se habían visto en el desensamblado de `INIT` pero se habían dejado sin investigar por asumirlas "externas")

**Verificado byte a byte**: los bytes en `MADMIX.SCR` en la posición
correspondiente a `0x5904` (aplicando el desplazamiento inverso,
+0x7800, y el offset de fichero de `MADMIX.SCR`) coinciden EXACTOS
con los bytes vistos en la RAM viva en `0x5904`. Confirmado con
script, 0 diferencias en 31 bytes comparados.

### La tabla de los 15 niveles: `0x59A9` (reubicado) / `0xD1A9` (en `MADMIX.SCR`), 20 bytes por registro

Extraída completa de `MADMIX.SCR` (15 registros de 20 bytes,
`0x59A9 + nivel*20`):

| nivel | campo0 (puntero cuerpo) | campo2 (puntero cabecera) | campo6 (filas variables) | filas totales (3+campo6) |
| --- | --- | --- | --- | --- |
| 0 | 0x335C | 0x50BC | 22 | 25 |
| 1 | 0x335C | 0x50BC | 22 | 25 |
| 2 | 0x361C | 0x50BC | 15 | 18 |
| 3 | 0x37FC | 0x50BC | 16 | 19 |
| 4 | 0x407C | 0x4AFC | 15 | 18 |
| 5 | 0x3C3C | 0x4AFC | 16 | 19 |
| 6 | 0x3E3C | 0x50BC | 18 | 21 |
| 7 | 0x443C | 0x4AFC | 19 | 22 |
| 8 | 0x425C | 0x4B5C | 15 | 18 |
| 9 | 0x39FC | 0x50BC | 18 | 21 |
| 10 | 0x469C | 0x50BC | 17 | 20 |
| 11 | 0x4BBC | 0x50BC | 21 | 24 |
| 12 | 0x4E5C | 0x4AFC | 19 | 22 |
| 13 | 0xCFA4 | 0x4AFC | 21 | 24 |
| 14 | 0xD244 | 0x50BC | 23 | 26 |

**Nota, CONFIRMADO por el usuario**: nivel 0 y nivel 1 tienen el
registro de 20 bytes IDÉNTICO byte a byte, pero **en el juego real
NO hay 15 niveles, hay 14** -- el usuario confirma que el primer
nivel no se repite al jugar. Es decir: `$2C07` es 1-indexado (nivel
1 = índice 1 de la tabla) y el índice 0 es un registro muerto/sin
usar (relleno, nunca alcanzado por el juego real). **Los 14 niveles
jugables reales son los índices 1-14 de la tabla; el índice 0 no
cuenta.**

**Formato de los datos confirmado visualmente**: se volcaron los
primeros ~48 bytes de varios punteros `campo0` y del `campo2` común
(`0x50BC`, compartido por 8 niveles). Resultado:
- `0x50BC` (cabecera común): **`0x42` repetido 48+ veces seguidas**
  -- una fila entera de un único tile (probablemente el "vacío"
  fuera del laberinto que el usuario describió: "3 filas más por
  arriba"). Con bit7 limpio por `RES 7,(HL)`, tile puro `0x42`.
- Nivel 0 (`0x335C`): `09 05×11 0B 05×11 0A 42×7 02 2D BF 2D BF 2D
  BF 2D BF 2D BF 2D 02 2D BF 2D...` -- reconocible al instante:
  corridas largas de un tile de pared (`0x05`), esquinas (`0x09`/
  `0x0B`/`0x0A`), tramo de vacío (`0x42`), y el patrón alternante
  `0x2D`/`0xBF` (con bit7, `0xBF&0x7F=0x3F`) -- **exactamente los 2
  valores más frecuentes de `maze_data.bin`** (`0x2D` 282 veces,
  `0x3F` 277 veces, ver hallazgo del `LD BC,$0500`/histograma más
  arriba). Es el patrón de pasillo con bolitas alternando.
- Niveles 2 y 4: patrones igual de reconocibles (corridas largas de
  un tile, parejas de "tapas" `0x4A`/`0x4B` y `0x47`/`0x48`
  repitiéndose con periodo regular -- decoración de pared).

**Conclusión final sobre el "ahorro de memoria" que preguntaba el
usuario**: NO hay compresión RLE. Es la matriz cruda de índices de
loseta, idéntica en espíritu a `maze_data.bin`, **pero cada nivel
se almacena con SU PROPIA altura** (18 a 26 filas, no 40 fijas) --
el ahorro viene de no rellenar cada nivel hasta un máximo común,
no de comprimir los datos en sí. Con alturas de 18-26 filas × 32
columnas, cada nivel ocupa entre ~600 y ~850 bytes -- los 15 caben
sin problema en los 21768 bytes de `MADMIX.SCR` (que además incluye
el código del cargador, la tabla, y probablemente más recursos
compartidos como las cabeceras/"tapas" reutilizadas entre niveles).

**Pendiente, ya menor**: decidir si `maze_data.bin`/su copia en
`MADMIX1.BIN` (`0xD000-0xD500`, 40 filas fijas) es una copia
antigua de desarrollo, un nivel de "demo/atracción" independiente,
o algo más.

**HECHO**: `MADMIX.SCR` ya tiene su propio fuente,
`src/madmix_scr.asm`, con `PHASE $1000`/`DEPHASE` (aplicado
correctamente aquí, al contrario que en `madmix1.asm`). Transcribe
todo lo confirmado en esta sesión: el dibujado de la portada
(`0x1000-0x10E4`, tabla de nombres identidad + copia del bitmap +
descompresión de color), `COORD_TO_ADDR` (`0x545F`), el cargador de
nivel completo (`0x5904-0x59A9`) y la tabla de 14 niveles
(`0x59A9-0x5AD5`). **Verificado 0 diferencias byte a byte** contra
`MADMIX.SCR` original en las 7646 bytes confirmadas (cabecera +
código de portada + bitmap + color comprimido + `COORD_TO_ADDR` +
cargador + tabla de niveles). El resto son huecos `DS` honestos
(zonas todavía sin desensamblar, sobre todo los datos crudos de los
14 niveles dispersos entre `0x335C` y `0x545F`).

## HECHO: `0x335C-0x511C` transcrito completo -- los cuerpos/cabeceras de los 14 niveles, con 0 diferencias

Se formalizó en `madmix_scr.asm` lo que ya se sabía conceptualmente
(el contenido que alimenta `niveles.html`): los punteros `campo0`
(cuerpo) y `campo2` (cabecera) de cada registro de `LEVEL_TABLE`
apuntan a esta zona. Se extrajeron los 12 cuerpos únicos + 3
cabeceras únicas directamente del `MADMIX.SCR` original (fórmula de
dirección: `offset_fichero = direccion_reubicada - 0x1000 + 7`,
verificada primero contra los 10 primeros bytes ya conocidos de
`LEVEL_TABLE` antes de fiarse de ella) y se colocaron como bloques
`INCBIN` etiquetados por dirección real (`BODY_L01` .. `BODY_L12`,
`HEADER_4AFC`, `HEADER_4B5C`, `HEADER_50BC`) en `src/data/niveles/`.

**Hallazgo al ordenar los bloques por dirección**: resultaron ser
**perfectamente contiguos entre sí** (cada uno termina exactamente
donde empieza el siguiente, sin relleno), con **una única excepción**:
un hueco real de **576 bytes en `0x48BC-0x4AFC`** que no corresponde
a ningún puntero de `LEVEL_TABLE`. Su contenido tiene el mismo
aspecto que cualquier cuerpo de nivel (tiles `0x42/0x05/0x2D/0xBF/
0x36/0x33`...) y mide exactamente 18 filas × 32 columnas = 576
bytes -- el mismo tamaño que los niveles 6 y 9. Se extrajo igual
(`BODY_HIDDEN_48BC`) y se documentó como **candidato fuerte a nivel
adicional sin usar/de desarrollo**, paralelo a `maze_data.bin` en
`MADMIX1.BIN`: existe, tiene forma de nivel real, pero ningún
registro de la tabla lo referencia, así que el juego nunca lo carga.

**CONFIRMADO VISUALMENTE (`src/recursos/nivel_oculto.html`, renderizado
con el mismo decodificador de losetas que `niveles.html`)**: **es un
15º nivel real, oculto/sin usar**. El usuario (jugador del original)
lo confirma: **las paredes interiores dibujan la silueta de un
comecocos, bordeada por losetas de dirección única** -- un diseño
demasiado deliberado para ser ruido o una mala interpretación de
datos. El usuario añade un dato importante de contexto: **el juego
"se supone" que tiene 15 niveles pero él nunca localizó los 15 jugando
ni en ninguna referencia de internet** -- este hallazgo encaja
exactamente con esa cuenta pendiente. Candidatos para su naturaleza:
huevo de pascua, nivel de prueba de desarrollo, o contenido recortado
antes de publicar. Sigue sin estar enlazado por `LEVEL_TABLE`, así
que en el disco tal cual nunca se alcanza jugando -- pendiente
valorar si merece la pena parchear un registro de la tabla (p.ej. el
0 muerto) para apuntarlo a este bloque y comprobar si es jugable de
verdad en emulador.

## COMPARADO contra la v2.0 (CAS+ROM, bug de "no se puede pasar del nivel 13/14" ya corregido según el usuario): el nivel oculto SIGUE sin usarse -- no es la causa del bug conocido

El usuario aportó `FISICO\MADMIXGAME_CAS\madmix.cas` y `madmix.rom`,
una versión 2.0 con el bug de Spectrum "no se puede pasar del nivel
13/14" ya corregido, para comprobar si el nivel oculto (comecocos)
es la explicación de ese bug (¿el 15º nivel real, roto/inalcanzable,
era el que impedía avanzar?).

**Metodología**: el CAS usa un esquema de carga distinto al disco
(bloques con nombre = su dirección final de destino: `LOADER`,
`LOGOTO`, `COLORS`, `PATS`, `1000`, `28EC`, `8400` -- un cargador de
cinta propio que coloca cada bloque directo en su dirección final,
sin el truco de reubicación de `MADMIX0.BIN`). Localizados los
bloques por sus cabeceras de cinta (marca de sincronismo `1F A6 DE
BA CC 13 7D 74`), se calibró la correspondencia dirección↔offset de
fichero buscando el CONTENIDO conocido (no asumiendo direcciones) y
se verificó con el registro 0 de `LEVEL_TABLE` antes de fiarse de
nada.

**Resultado, con 0 diferencias verificadas byte a byte**: los 12
cuerpos + 3 cabeceras + `LEVEL_TABLE` completa (15 registros) + **el
propio nivel oculto de `0x48BC`** están, en la v2.0, en **las
mismas direcciones exactas y con el mismo contenido exacto** que en
la v1.0 del disco. `LEVEL_TABLE` sigue teniendo exactamente los
mismos 15 registros, ninguno apunta a `0x48BC`. Es decir: **la v2.0
NO tocó esta zona en absoluto** -- ni recolocó el nivel oculto, ni
lo enlazó, ni lo eliminó. Sigue igual de huérfano que en la v1.0.

**Conclusión**: el nivel oculto/comecocos **no es la causa** del bug
de "no se puede pasar del 13/14" -- si lo fuera, arreglar el bug
habría requerido tocar `LEVEL_TABLE` o esta zona de memoria, y no se
tocó ni un bit. El bug real debe estar en otra parte (candidato más
probable: la lógica de avance de nivel/comprobación de fin de partida
en `MADMIX1.BIN`, sin localizar todavía -- pendiente si se quiere
seguir esta pista comparando el bloque `8400` del CAS/ROM contra
`madmix1.asm`). El nivel oculto sigue pareciendo lo que ya se pensaba:
contenido cortado/no conectado deliberadamente, independiente del bug
de progresión de niveles.

**Efecto colateral útil de esta comparación**: al alinear direcciones
del bloque `8400` (el equivalente a `MADMIX1.BIN`) se detectó y
corrigió el bug real de 7 bytes en la cabecera de `madmix1.asm` (ver
sección propia arriba).

## LOCALIZADO (parcialmente): el fix real del bug "nivel 13 no cuenta bien las bolitas" -- sin tocar `madmix1.asm`, solo diagnóstico

Contexto aportado por el usuario: el bug real de la v1.0 (heredado
del original de Spectrum, según fuentes externas que consultó) es
que **el contador de bolitas comidas del nivel 13 no funciona bien**
-- aunque te las comas todas, el nivel nunca se da por completado.
La v2.0 (CAS+ROM) lo arregla: se puede terminar el 13 y pasar al 14,
pero de ahí se vuelve al nivel 1 (no hay un 15 oculto accesible) y
el nivel oculto/comecocos sigue sin usarse (confirmado en la sección
de arriba).

**Metodología**: diff byte a byte completo de los 22945 bytes del
motor (`0x8400-0xDDA0`) entre el `MADMIX1.BIN` original (disco) y el
bloque `8400` del CAS, **verificado además contra el ROM** (build
independiente) para descartar que fuera un artefacto de la cinta --
los tres hallazgos de abajo son byte a byte IDÉNTICOS en CAS y ROM.

**Los únicos cambios reales en todo el motor** (aparte de una zona de
~340 bytes en `0x93DD-0x9532` que ya en el original es DATA, no
código -- el desensamblador degenera igual en ambas versiones, así
que esos diffs son de una tabla, no de lógica; no se ha investigado
su contenido todavía):

1. **`0x8CD4`**, dentro de `MAP_COORD_TO_ADDR` (0x8CB6, ya transcrita
   en `madmix1.asm`): `LD HL,$FC60` → `LD HL,$FC50`. `$FC60` es el
   buffer de la matriz de nivel activo, ya confirmado y usado en
   `LEVEL_LOADER`/`MAP_COORD_TO_ADDR`.
2. **`0x8BE5`**: el mismo cambio (`LD HL,$FC60`→`$FC50`) en una
   rutina GEMELA todavía sin transcribir (vive en el hueco `DS`
   justo antes de `MAP_COORD_TO_ADDR` en `madmix1.asm`, sección
   "Hueco hasta MAP_COORD_TO_ADDR"). Misma estructura de bytes
   alrededor (`21 60 FC` → `21 50 FC`, precedida por `18 1F CB`
   repetido x3 en ambos sitios) -- son dos copias casi idénticas de
   la misma rutina, un patrón ya visto antes en el subsistema de
   activación de ítems.
3. **`0x8F26`**, dentro de `INIT` (0x8F24): `LD SP,$0FFF` →
   `LD SP,$F2FF`. Cambia por completo la zona de memoria donde vive
   la pila. Posiblemente no relacionado con el bug de las bolitas --
   podría ser un ajuste necesario por cómo el cargador de cinta/ROM
   gestiona la memoria baja (el esquema de carga del CAS es distinto
   al del disco, ver sección de arriba), no necesariamente parte del
   fix del contador.
4. **Bloque de ~180 bytes nuevo en `0xC9BC-0xCA73`**: en la v1.0 es
   relleno de ceros puro (sin usar); en la v2.0 tiene código real,
   encajado exactamente en ese hueco sin desplazar nada más del
   fichero (todo lo anterior y posterior sigue idéntico byte a
   byte). Bytes completos:
   ```
   02 01 00 00 CD 5E 00 00 1E 3D 00 01 0E CB CD D0
   CD 4D 00 C0 00×34 FF CD A5 CB 06 00 18 00 01 0F
   CD 5E 00×10 07 00×4 FE 00×4 01 00×9 F2 00×3 0C CE
   13 CE 4E 00 C0 00×29 0A 00 03 00 01 00×3 1E 01 00
   00 09 CE 00×3 F7 00 07 00×4 FE 00×4 01 00
   ```
   Sin desensamblar limpiamente todavía (el punto de entrada real no
   es obvio; los intentos de desensamblado lineal desde `0xC9BC`
   degeneran en NOPs dispersos, señal de que el arranque real de la
   rutina está más adelante o el bloque mezcla código con datos).
   **No contiene referencia literal a `$2C08` (contador de bolitas)
   ni `$2C07` (nivel actual)** como par de bytes `08 2C`/`07 2C`, así
   que si está relacionado con el contador es de forma indirecta
   (vía registro, no dirección literal).

**Conclusión (parcial, sin tocar `madmix1.asm`)**: el candidato más
sólido para el fix real es el cambio `$FC60`→`$FC50` en las dos
copias de la fórmula coordenada→dirección, posiblemente combinado
con el bloque de código nuevo en `0xC9BC` (que encaja perfecto en
temporalidad: alguien tuvo que AÑADIR lógica para que funcionara,
no solo tocar una constante). El cambio de `SP` en `INIT` es sospechoso
de ser un efecto colateral del esquema de carga distinto del CAS/ROM,
no del fix en sí -- pendiente de confirmar. **Siguiente paso lógico
si se retoma**: transcribir la rutina gemela de `0x8BE5` (para
entender qué hace `MAP_COORD_TO_ADDR` "por partida doble") y
desensamblar con más cuidado (probando distintos puntos de entrada)
el bloque nuevo de `0xC9BC-0xCA73`.

**CERRADO (sesión posterior, sin corregir nada -- el objetivo es
terminar de desensamblar la v1.0 tal cual es, no arreglar el bug)**:
las dos piezas pendientes de este hallazgo ya estaban, de hecho,
transcritas -- solo faltaba reconocerlas y darles su referencia
cruzada:

- **La rutina gemela de `0x8BE5`** es `TILE_ADDR_CALC` (`0x8BC9` en
  `madmix1.asm`), transcrita en la sesión que resolvió los 7 huecos
  `JT_SLOT5-9` (mismo modismo `AND $7C` + rotaciones, misma base
  `LD HL,$FC60`). `0x8BE5` cae justo en el byte bajo de esa
  constante -- exactamente el byte que la v2.0 cambia de `$60` a
  `$50`. En esta v1.0 se queda tal cual en `$60` (el bug original,
  sin corregir a propósito), verificado 0 diferencias.
- **El bloque `0xC9BC-0xCA73`** cae dentro de `RM_TABLE_C8DE` (la
  tabla de datos del driver de sonido), justo después de la tabla de
  salto de 15 comandos (`0xC99E-0xC9BB`) -- es la zona ya descrita
  como "estado en RAM de los canales a cero en el original". Se
  comprobó byte a byte contra el `.BIN` real: de los 183 bytes, 181
  son `$00` y solo 2 son distintos (`$07` en `0xCA6A`, `$FE` en
  `0xCA6F`) -- ya transcritos tal cual dentro de la tabla, sin
  ningún hueco `DS` pendiente. Es precisamente donde la v2.0 mete
  código nuevo para el fix; en esta v1.0 es simplemente estado de
  canal en reposo, sin usar todavía.

Ambas notas cruzadas se añadieron como comentarios en `madmix1.asm`
junto a `TILE_ADDR_CALC` y `RM_TABLE_C8DE`, recompilado y
reverificado 0 diferencias byte a byte. No se ha tocado ni un bit
del contenido real -- el objetivo de esta reconstrucción es
reproducir la v1.0 original tal cual es, bug incluido, no arreglarlo.

**Verificado**: los 16 bloques compilan con `sjasmplus --sym` cayendo
cada uno exactamente en su dirección real, y el diff byte a byte
completo contra `MADMIX.SCR` da **0 diferencias en los 7616 bytes**
de `0x335C-0x511C`. Los únicos diffs restantes en todo el fichero
caen en los huecos ya conocidos y todavía sin transcribir: el de 3
bytes en `0x28ED-0x28F0`, la tabla de posiciones de ítems + código
sin desensamblar en `0x511C-0x5904` (incluye el subsistema de
activación de ítems ya documentado más arriba), y la cola sin
explorar `0x5AD5-0x6500`.

## Los 13 bytes restantes del registro de nivel (offsets 7-19): descifrados con código real, no por patrones numéricos

Se retomó el registro de 20 bytes por nivel (`0x59A9`+nivel×20).
En vez de adivinar por el valor numérico de cada campo, se rastreó
**qué código lee cada dirección** ($2BF3-$2C06, donde se copia el
registro completo vía `LDIR`) inmediatamente después de la copia,
dentro de la misma función de carga (`0x5904-0x59A8`) y en el tramo
de `INIT` que se ejecuta justo después. Resultado, campo a campo:

- **Offsets 4-5** (duplicado byte a byte de los offsets 2-3, puntero
  de cabecera): **NO es un duplicado desperdiciado** -- se usa una
  SEGUNDA vez (`0x5965: LD HL,($2BF7) / LD BC,$0060 / LDIR`) para
  copiar la cabecera fija (3 filas) otra vez, esta vez A CONTINUACIÓN
  del cuerpo del nivel que se acaba de copiar. **Confirma la vieja
  observación del usuario**: 3 filas extra arriba Y 3 filas extra
  abajo, simétricas, ambas rellenas con la misma cabecera.
- **Offset 7** (`$2BFA`): se copia a la variable `$2C2B` (un
  "flag pendiente" de un solo uso que `INIT` lee y limpia justo
  después). Si su valor cruza cierto umbral junto con `$2C27`
  (contador ya conocido, puesto a 3 por `INIT`), dispara un dibujado
  condicional de texto/icono en HUD vía una rutina de texto en
  `0x5CD1` (la misma que dibuja glifos de fuente). Valores reales:
  mayoría 0/1, nivel 9 tiene un 2 -- parece un pequeño enum (tipo de
  aviso/icono especial), no un simple booleano.
- **Offset 12** (`$2BFF`): **el hallazgo más claro de todos** --
  es el índice de loseta que sustituye al marcador comodín `0x3C`
  cuando aparece en los datos crudos del cuerpo del nivel (visto
  directamente en el bucle principal del cargador, `0x594B-0x5960`:
  `CP $3C` / si coincide, sustituye por `LD A,($2BFF)` antes de
  escribir). Los valores reales (`0x3F`,`0x40`,`0x41`) son todos de
  la familia "suelo con bola" ya catalogada -- es decir, **el mapa
  base se comparte entre niveles como plantilla, y cada nivel solo
  elige qué variante de loseta "bola" rellena los huecos comodín**.
  Esto también explica por qué varios niveles comparten el mismo
  puntero de cuerpo/cabecera (campo0/campo2): son la MISMA plantilla
  con distinto relleno.
- **Offsets 13-14** (`$2C00`, leídos como palabra de 16 bits): se
  pasan (con el byte alto decrementado en 1) a una función auxiliar
  en `0x545F` que es **la misma fórmula exacta que
  `MAP_COORD_TO_ADDR`** (`AND $7C` + rotaciones = fila×32+columna,
  con base `$FC60`). Es decir, **fila y columna de un punto de
  referencia inicial** dentro de la matriz del nivel -- el resultado
  se guarda en `$2C0A`, la misma variable que después usa la
  animación de parpadeo de la bola (`0x9111`). Candidato más
  probable: la posición de la primera bola/pieza animada del nivel,
  o un punto de referencia para el scroll inicial.
- **Offsets 15-16** (`$2C02`): se copian TAL CUAL (sin pasar por
  ninguna fórmula) directo a `$2C02` -- que es, ya lo sabíamos,
  **la variable de posición cámara/comecocos** que usa
  `MAP_COORD_TO_ADDR` continuamente durante la partida. Es decir:
  **la posición inicial real del comecocos/cámara al arrancar el
  nivel.**
- **Offset 17** (`$2C04`): se copia directo a `$9147`, una posición
  de la tabla de fuente/HUD (junto a `$9148`, que siempre recibe el
  valor fijo `0x78`). Los valores reales son solo 4 distintos
  (`0x30,0x38,0x60,0x70`) repetidos entre niveles -- parece un
  código de carácter/icono para un indicador de HUD de "tipo de
  nivel" o similar, no un valor único por nivel.

**ACTUALIZADO (2026-07-25)** -- offsets 8, 9, 10 y 11 ya están
descifrados con código real; solo 18 y 19 siguen sin ninguna
referencia encontrada. Ver sección "Descifrados offsets 8/11/18/19"
más abajo para el detalle completo (esta nota se queda desactualizada
a propósito, como registro histórico de cómo evolucionó el análisis).

**CONFIRMADO, CORRECCIÓN IMPORTANTE (14 niveles, no 15)**: el
usuario confirma que el juego real tiene 14 niveles, no 15 -- el
nivel 0 (registro idéntico byte a byte al nivel 1) es un registro
muerto de la tabla que el juego nunca alcanza (`$2C07` es
1-indexado; los niveles jugables son los índices 1-14). Corregido
en `src/recursos/niveles.html` (el índice 0 se etiqueta ahora como
"Registro 0 (no jugable)").

### La portada SÍ está en `MADMIX.SCR` -- empaquetada junto al cargador de niveles

Pregunta del usuario: ¿la imagen de portada/carga está también en
`MADMIX.SCR`? Se investigó el tramo de memoria baja reubicada
`0x1000-0x335C` (~9KB, sin explorar hasta ahora, justo antes de
donde empieza el cargador de niveles en `0x5904`/tabla `0x59A9`) y
SÍ contiene una rutina real de carga de imagen a VRAM, desensamblada
completa desde `0x1000`:

```asm
; 0x1000-0x101D: escribe tabla de nombres IDENTIDAD en VRAM $1800
; (el truco de "nombre = indice de patron" ya conocido de
; FINDINGS.md, no es la imagen -- es la infraestructura de siempre)
LD HL,$1800 / OUT ($99),A x2 (fija puntero VRAM $1800, escritura)
LD BC,$0000
bucle: LD A,C / OUT ($98),A / INC BC / LD A,B / CP $03 / JR NZ  ; 768 bytes = 0,1,2..255 x3

; 0x101F-0x103D: COPIA LA IMAGEN DE VERDAD a la tabla de patrones VRAM $0000
LD HL,$10ED        ; puntero FUENTE -- el bitmap en si, en esta misma zona de MADMIX.SCR
LD DE,$0000        ; destino VRAM = $0000 (tabla de patrones, SCREEN 2)
LD BC,$1800        ; 6144 bytes -- EXACTO el tamaño de la tabla de patrones completa
EX DE,HL / fija puntero VRAM (igual patron OUT $99 x2 + EX (SP),HL x2 de retardo)
EX DE,HL
bucle: LD A,(HL) / OUT ($98),A / INC HL / DEC BC / ... JR NZ   ; copia los 6144 bytes

; 0x103F-0x104A: fija registro 7 del VDP (color de borde/fondo) a 1
LD A,$01 / LD B,A / LD C,$07 / OUT($99) / OR $80 / OUT($99)

; 0x104C en adelante: reconstruye la tabla de COLOR (768 bytes, $2000)
; desde $28F0, empaquetada a NIBBLE (4 bits/color) -- desempaquetada
; con una tabla de 16 entradas en $10AC (cada nibble de color ->
; byte de atributo completo foreground/background)
LD BC,$0300 / LD DE,$2000 / LD HL,$28F0
... (bucle de desempaquetado nibble por tabla en $10AC) ...
```

**Conclusión**: `MADMIX.SCR` no es "solo" el cargador de niveles --
hace dos trabajos en el mismo fichero: (1) dibuja la portada/pantalla
de carga completa (patrones + color, con la paleta comprimida a
nibble) justo al arrancar, y (2) queda residente en memoria baja
tras la reubicación de `MADMIX0.BIN` para servir de cargador de
niveles el resto de la partida. Por eso el nombre "SCR" no es
del todo engañoso -- solo incompleto: es pantalla Y datos de juego
a la vez, empaquetados juntos.

**HECHO**: renderizado en `src/recursos/portada.html`. Algoritmo
verificado con exactitud contra el desensamblado (índice1 =
`(ctrl>>3)&0x0F`, índice2 = `(idx1&0x08)|(ctrl&0x07)`, color =
`(tabla16[idx2]<<4)|tabla16[idx1]`, byte de control `0x00` = color
0/0 sin pasar por la tabla). Con la tabla de nombres identidad y la
paleta MSX1 estándar de 16 colores, el resultado es la portada real
del juego a la primera: el comecocos verde en el centro, dos
fantasmas blancos a los lados, y el suelo a cuadros -- confirma que
tanto el desensamblado del algoritmo de descompresión como los
punteros (`0x10AC`/`0x10ED`/`0x28F0`) eran exactos.

## Composición en RAM antes de volcar a VRAM: confirmado para el fondo, matizado para los actores

Pregunta del usuario: dado que el juego no usa sprites ni otras
capacidades de hardware del VDP (ya confirmado en sesiones
anteriores), ¿existe un "espejo de trabajo" en RAM normal donde se
va calculando la imagen, para después volcarla a VRAM? Se investigó
a fondo revisando tanto `madmix1.asm` (la transcripción ya byte-exacta
de `ACTOR_ENGINE`) como el bloque reubicado de `MADMIX.SCR`
(`0x1000-0x6500`) que hasta ahora seguía mayormente sin explorar.

### Confirmado: `JTS2_RENDER_A`/`JTS2_RENDER_B` NO tocan puertos del VDP -- son lectura/escritura de RAM normal

Revisando el código ya transcrito de `madmix1.asm` línea a línea: las
dos rutinas de render sub-píxel de actores hacen `LD A,(HL)` /
`AND`/`OR` / `LD (HL),A` -- **operaciones de memoria normales, NO
`OUT ($98)`/`OUT ($99)` (los puertos del VDP)**. Como la VRAM del
TMS9918 **no está mapeada en el espacio de direcciones del Z80**
(solo se accede vía esos dos puertos), esto demuestra que el render
de actores, igual que el del fondo, **escribe en un búfer de RAM
normal, no en la VRAM directamente** -- corrige lo que se dijo en
sesiones anteriores ("el software escribe directamente en la tabla
de patrones de VRAM"), que era una conclusión demasiado literal de
los volcados de VRAM en vivo.

### El cursor de actores empieza en `0x0500`, NO en `0xDE04` -- son dos búferes distintos

Rastreando `RESET_8437`/`$8437` y el código que llama a
`JTS2_COPY_CURSOR` (justo antes, en `madmix1.asm`):

```asm
LD HL, $8437
LD A, (HL)
AND A
JR NZ, JTS2_851F     ; si $8437 != 0, retoma el cursor guardado en $8438
LD DE, $0500          ; si es la PRIMERA vez, el cursor arranca en $0500
JR JTS2_8523
JTS2_851F:
LD DE, ($8438)
```

Esto **confirma con hechos** (no ya una hipótesis suelta de sesiones
anteriores) que **`0x0500` es el búfer de trabajo dedicado al render
de actores** -- un búfer DISTINTO al `0xDE04` que usa `REDRAW_STRIP`
para el fondo. `JTS2_COPY_CURSOR` copia ahí, desde la tabla de
máscaras de bits (`0xD8FB-0xDD7B`, según la posición del actor), los
fragmentos que luego `JTS2_RENDER_A`/`B` combinan (`AND`/`OR`) con
el contenido ya presente para lograr el desplazamiento sub-píxel.

**Importante para el mapa de memoria**: `0x0500` cae dentro de lo
que en `mapa_memoria.html` estaba marcado como `0x0000-0x1000: sin
analizar (sistema/BIOS)` -- esa zona SÍ contiene datos reales del
juego, hay que corregirlo.

### `0xDE04`: confirmado que es un búfer grande (al menos 144×32 = 4608 bytes), con una rutina de inicialización propia

Buscando todas las referencias al literal `0xDE04` en ambos ficheros
apareció una rutina de reinicio en la zona reubicada de
`MADMIX.SCR` (dirección baja `0x5B8C`):

```asm
LD DE, $DE04
LD B, $90            ; 144 filas
bucle:
  PUSH BC / PUSH DE
  LD H,D / LD L,E
  INC DE
  LD (HL), $FF        ; siembra 1 byte...
  LD BC, $0017         ; ...y LDIR lo replica 23 veces mas (24 bytes total)
  LDIR
  POP HL
  LD BC, $0020         ; avanza a la siguiente fila (paso de 32 bytes)
  ADD HL, BC
  EX DE, HL
  POP BC
  DJNZ bucle
```

Rellena 24 de los 32 bytes de cada una de 144 filas con `$FF`
(dejando 8 bytes de cada fila sin tocar -- probablemente la franja
lateral del marco de caramelo/HUD, que no forma parte del área
jugable). **144 filas es mucho más que una pantalla** (24 filas de
caracteres = 192 filas de píxeles si la unidad fuese por-línea, o
144 filas de píxeles = 18 filas de caracteres si la unidad es
"por línea de píxel" -- coincide sospechosamente con la altura del
nivel MÁS PEQUEÑO encontrado, 18 filas). Confirma que `0xDE04` es
un búfer notablemente más grande de lo que se había asumido antes
(no una simple franja de trabajo), consistente con un "lienzo"
donde cabe de sobra el contenido visible más margen de scroll.

### Hallazgo colateral: tabla RLE en `0xD6B6` (dentro de la zona "sin explorar" de `MADMIX1.BIN`) rellena la tabla de patrones de VRAM

Seleccionando las llamadas a `FILVRM` de la zona reubicada
(`0x6432` en adelante), apareció un mecanismo de relleno RLE que
lee pares `(valor, cuenta)` de una tabla en `0xD6B6` --
**dirección ESTÁTICA dentro de `MADMIX1.BIN`**, justo en el tramo
`0xD500-0xD8FB` que el mapa de memoria tenía como "sin explorar" --
y va llamando a `FILVRM` para pintar la tabla de patrones de VRAM
en bloques (destino empieza en VRAM `$0000`, avanza por la cuenta
de cada par). Antes de eso hay un `FILVRM` que pone toda la tabla
de color (`VRAM $2000`, `0x17F8`≈6136 bytes) al color `1`. Esto
resuelve parte del hueco `0xD500-0xD8FB`: no es un búfer de RAM de
trabajo, es una **tabla de datos RLE consumida por el código
reubicado de MADMIX.SCR**, probablemente el dibujado inicial de un
nivel (relleno base antes de las losetas específicas).

### Hallazgo colateral: rutina de dibujo de glifos de HUD/marcador (`0x5CAF`, dirección baja)

La única llamada a `LDIRVM` encontrada en toda la zona reubicada
(`0x5CBF`) resultó ser un dibujo de UN carácter (8 bytes de fuente
desde una tabla en `0x925B`, dentro de MADMIX1.BIN, más relleno de
color a juego) -- el refresco del marcador/HUD, no un volcado
general de pantalla.

### Conclusión honesta -- lo que falta

**Confirmado**: hay como mínimo DOS búferes de trabajo en RAM
normal con la misma disposición que la VRAM (paso de 32 bytes):
`0x0500` (actores, arranca aquí la primera vez, cursor persistente
en `$8438`) y `0xDE04` (fondo/losetas, al menos 4608 bytes, con su
propia rutina de inicialización a `$FF`). Ambos encajan con la
hipótesis del usuario: todo se compone por software en RAM y
después se transfiere a VRAM.

### RESUELTO: el volcado de `0xDE04` a VRAM ocurre en la ISR (una vez por fotograma), con un bucle propio, sin pasar por `LDIRVM`

Se intentó en vivo (openMSX) un breakpoint de ejecución en la
entrada de `LDIRVM` (`0x8942`) condicionado a que `HL` cayera dentro
de `0xDE04-0xF004` o `0x0500-0x0700` -- **nunca saltó**, ni jugando
un buen rato. Esto en sí mismo fue un dato útil: confirmó que el
volcado NO pasa por la subrutina compartida `LDIRVM`.

Se retomó el análisis estático: se desensambló `REDRAW_STRIP`
(`0x8D1B`) completo por primera vez (antes solo era un stub `TODO`
en `madmix1.asm`) y se confirmó que es una copia `LDI` pura de RAM a
RAM (`TILE_GFX`/`0xB940+` → `0xDE04+`), sin ningún `OUT` -- coherente
con que el watchpoint de `LDIRVM` no saltara por ese lado.

Buscando TODAS las referencias al literal `0xDE04` en `MADMIX1.BIN`
(corrigiendo el offset: la dirección de instrucción es 1 byte antes
de donde aparecen los bytes de la dirección), aparecieron 5 sitios
más, todos dentro de la zona `0x8860-0x8931` (la que ya teníamos
como "housekeeping de la ISR + hueco" en el mapa de memoria) --
**es decir, dentro de la propia rutina de interrupción de VBLANK**.
Uno de ellos, en `0x88E8`, es el volcado real:

```asm
; 0x88E5 en adelante (dentro de la ISR/housekeeping, 0x8860-0x8931)
LD DE, $0220        ; DE = direccion destino en VRAM (tabla de patrones)
LD HL, $DE04         ; HL = ORIGEN: el buffer de fondo
LD B, $12             ; 18 (bucle externo)
PUSH BC / PUSH HL / PUSH DE
EX DE, HL
CALL SETVRAM          ; fija la direccion VRAM (0x0220) a mano, NO via LDIRVM
EX DE, HL
LD D, $20              ; 32 -- el mismo paso de fila que ya conociamos
LD A, L
LD C, $98               ; puerto de datos del VDP
LD E, $18                ; 24 (bucle interno)
bucle_interno:
  LD L, A
  LD B, (HL)             ; lee un byte del buffer 0xDE04
  OUT (C), B              ; ESCRITURA REAL A VRAM
  ADD A, D                 ; A += 32 (avanza de fila DENTRO del mismo byte alto)
  DEC E
  JP NZ, bucle_interno      ; 24 iteraciones
; (el bucle externo, B=18, repite todo con H+1/D-1 -- ver arriba en 0x88A5 en adelante)
```

**Esto confirma, con código real y en su sitio exacto, la
arquitectura completa que planteaba el usuario**: el fondo se
compone en el búfer de RAM `0xDE04` (por `REDRAW_STRIP` cuando hace
falta redibujar una franja) y se vuelca a VRAM **una vez por
fotograma, dentro de la ISR**, con un bucle de `OUT ($98)` escrito a
mano (ni `LDIRVM` ni `FILVRM`, por eso las búsquedas dirigidas a esas
2 rutinas no lo encontraban). El volcado no es "toda la pantalla de
golpe" sino por bloques pequeños (en este punto concreto, 18×24=432
bytes) -- consistente con actualizar solo la franja que ha cambiado
en ese fotograma, no el lienzo entero.

### RESUELTO: `0x0500` NO necesita volcado propio -- es un simple "borrador" de trabajo, y el resultado final vuelve a `0xDE04`

Se desensambló completo el tramo `0x8860-0x8931` buscando un
volcado equivalente para el búfer de actores (`0x0500`) -- **no
aparece ninguna referencia a `0x0500` en toda esa zona**. Esto,
combinado con los dos saltos en vivo que ya habíamos capturado con
el usuario, cierra el círculo:

- **Primer salto en vivo** (`PC=0x869C`, dentro de `JTS2_COPY_CURSOR`):
  `LDI` con `HL=0xE511` (origen, dentro de `0xDE04-0xF004`) y
  `DE=0x0501` (destino, dentro de `0x0500+`).
- **Segundo salto en vivo** (`PC=0x85A4`, dentro de `JTS2_85A2`, el
  paso de MEZCLA de `JTS2_RENDER_A`/`B`): `HL=0xE5F2`, de nuevo
  dentro de `0xDE04-0xF004`.

Es decir: `JTS2_COPY_CURSOR` **copia una foto del fondo actual desde
`0xDE04` hacia `0x0500`** (un simple borrador/zona de trabajo, sin
contenido persistente propio), `JTS2_RENDER_A`/`B` hacen ahí la
aritmética de desplazamiento de bits, pero el **resultado final se
escribe de vuelta en `0xDE04`** (confirmado por el segundo salto:
la propia mezcla ocurre leyendo Y escribiendo dentro del búfer de
fondo, no en `0x0500`). `0x0500` nunca aparece en pantalla por sí
mismo, así que no necesita (ni tiene) su propia rutina de volcado a
VRAM -- el mismo volcado de `0xDE04` (`0x88E8`, ISR de VBLANK) ya
incluye, de rebote, cualquier actor que se haya compuesto encima.

**Conclusión final de todo este hilo**: hay un único lienzo visible
en RAM (`0xDE04`), donde se componen TANTO el fondo (`REDRAW_STRIP`)
COMO los actores (`JTS2_RENDER_A`/`B`, usando `0x0500` solo como
borrador intermedio), y una única familia de rutinas en la ISR de
VBLANK (`0x8860-0x8931`) que lo vuelca a VRAM por bloques, una vez
por fotograma. Arquitectura confirmada de principio a fin, con
evidencia estática Y en vivo cruzada.

## NUEVO SUBSISTEMA encontrado al rellenar huecos de `madmix_scr.asm`: activación de ítems especiales (bola de poder, hipopótamo, herramienta, pista...)

Retomando la tarea de rellenar los huecos `DS` de `madmix_scr.asm`
(`0x2BF0-0x335C`, datos de los 14 niveles dispersos, `0x5478-0x5904`),
el tramo `0x5478-0x5904` resultó ser bastante más que "código
suelto sin identificar": es un **subsistema completo, nunca antes
documentado, para activar los ítems especiales del juego** (bola de
poder, hipopótamo, herramienta, pista de tanque/avión -- los
`items` ya catalogados en `graficos.html` losetas `59-62`/`58`/`82-83`).

### Estructura general (desensamblado, no transcrito todavía a `madmix_scr.asm`)

Dentro de `0x5478-0x5904` hay **dos instancias casi idénticas** de
un mismo manejador (una copia de código por cada tipo de ítem
manejado ahí), cada una con esta forma:

```asm
; manejador (una instancia por tipo de item), ~170-280 bytes:
LD IX, TABLA_ITEM        ; $549B en la 1a instancia, $5588 en la 2a
PUSH BC                   ; B = numero de entradas a comprobar (viene de fuera)
bucle:
  LD C,(IX+0) / LD B,(IX+1)         ; posicion candidata (fila,col empaquetada)
  LD HL,($2C02)                      ; posicion actual del comecocos/camara
  ; ¿coincide (con margen de 2 bits, AND $03) con la posicion actual?
  ...
  CALL $5559                          ; helper LOCAL identico a COORD_TO_ADDR
                                        ; (fila*32+col -> $FC60+offset) -- una
                                        ; copia mas de la misma formula, no
                                        ; reutiliza la de $545F
  ; comprueba bit 7 (loseta "comida") y rango de tipo de loseta (SUB $3F, CP $03)
  ...
  PUSH IX
  CALL $8440                            ; llama DIRECTO al motor de actores
                                          ; (ACTOR_ENGINE) para activar el item
  POP IX
  LD (IX+2), $01                          ; marca la entrada como "activa"
  CALL $57D8                                ; TODO: sin identificar (efecto asociado)
  ; si la distancia esta dentro de ventana (CP $0C fila, CP $09 columna):
  DEC (2C08)                                  ; decrementa el contador ya
                                                ; conocido (se resetea a 0 en
                                                ; el cargador de nivel, ver
                                                ; seccion de los 13 bytes)
  LD (HL), A          ; en $5557, escribe algo en la loseta destino
  CALL $8CEE                                    ; TODO: nueva direccion, sin
                                                  ; identificar (dentro del
                                                  ; motor principal, cerca de
                                                  ; MAP_COORD_TO_ADDR/TILE_TYPE_LOOKUP)
  LD A,(5 o 6)
  LD ($6128), A                                   ; TODO: variable sin
                                                    ; identificar (marcador/HUD?)
  LD BC,$0007 / ADD IX,BC                           ; siguiente entrada (7
                                                      ; bytes/registro)
  POP BC / DEC B / JP NZ,bucle                        ; repite para las B
                                                        ; entradas
  RET
```

### Las tablas referenciadas

Se localizaron **4 direcciones usadas como `LD IX,nnnn`** en este
tramo: `$549B`, `$5588` (cada una referenciada 2 veces, una por
"pasada"), `$5773` y `$511C`. Contenido real comprobado:

- **`$511C`**: tabla limpia de **registros de 7 bytes**, confirmada
  con datos reales (`20 10 00 01 00 00 01`, `10 10 00 01 00 00 02`,
  `10 10 00 01 00 00 03`, `10 10 00 01 00 00 01`...) -- el último
  byte cambia (`01,02,03,01...`, candidato a "tipo de ítem"), los
  primeros bytes parecen posición (fila/columna empaquetada, mismo
  estilo que el resto del motor). **Esto cae DENTRO de lo que
  teníamos catalogado como "datos dispersos de los 14 niveles"
  (`0x335C-0x545F`)** -- es decir, esa zona no contiene solo
  matrices de losetas, también contiene tablas de posición de
  ítems especiales por nivel. Reclasificar pendiente.
- **`$5773`**: NO es una tabla de datos estática -- es una **zona
  de trabajo en RAM** (empieza en ceros en el `.BIN`, confirmado) a
  la que además le sigue código real que la referencia con
  `IX=$5773` (auto-referencia). Coincide con un hallazgo suelto de
  sesiones anteriores en `madmix1.asm`/`MADMIX1.BIN`: hay un bucle en
  `0x58D9` (`LD B,$04 / LD HL,$5773 / LD (HL),$00 / INC HL / INC HL
  / DJNZ`) que limpia esta MISMA dirección desde el otro fichero --
  confirma que `$5773` es una variable compartida entre ambos
  binarios, no algo exclusivo de `MADMIX.SCR`.
- **`$549B`/`$5588`**: las dos tablas de posiciones "activas" que
  usa cada instancia del manejador (formato de 7 bytes/entrada,
  igual que `$511C`).

### HECHO: `0x5478-0x5904` transcrito completo a `madmix_scr.asm`, 0 diferencias byte a byte

Desensamblado con Z80Dasm sin desincronizar en ningún punto del
rango (código y datos conectados de forma coherente por CALL/JP
reales) y transcrito entero. Estructura final, más detallada que la
primera pasada:

- `ITEM_RNG` (`$5478`, 15 bytes) -- el generador pseudoaleatorio ya
  documentado.
- `ITEM_ANIM_TABLE_1`/`ITEM_ANIM_TABLE_2` (`$5487`/`$5574`, 20 bytes
  cada una) -- tablas de frames de animación (índice `tipo*4 + fase
  0-3`), un valor de tile con bit 7 = flag adicional.
- `ITEM_TABLE_1` (`$549B`, **2** entradas de 7 bytes -- no era obvio
  el número exacto hasta transcribir el bucle de inicialización) y
  `ITEM_TABLE_2` (`$5588`, **8** entradas). Contenido de compilación
  real (no ceros): `$20,$10,$01/$02,$01,$00,$00,$01` repetido --
  posición semilla `(0x20,0x10)` + campo "tipo" (1 o 2) + resto fijo.
  Son buffers de trabajo, reinicializados cada nivel por
  `TABLE_INIT`.
- `ITEM_HANDLER_1`/`ITEM_HANDLER_2` (`$54A9`/`$55C0`): el contador de
  entradas a procesar (`B`) se lee de **`($2BFC)`/`($2BFD`)** --
  offsets **9 y 10** del registro de nivel copiado a RAM de trabajo.
  **Primer dato concreto sobre esos offsets todavía sin descifrar**:
  candidato fuerte a "número de ítems tipo 1 / tipo 2 en este
  nivel". Pendiente de confirmar cuando se aborde esa tarea.
- `COORD_TO_ADDR_LOCAL` (`$5559`): tercera copia de la misma fórmula
  coordenada→dirección que `COORD_TO_ADDR` (`$545F`) y
  `MAP_COORD_TO_ADDR` (`$8CB6` en `madmix1.asm`) -- ya van 3 copias
  independientes de la misma fórmula en el juego.
- `GHOST_HINT_HANDLER` (`$566A`): maneja una tabla de 3 entradas en
  `$2C2E` (RAM, fuera de este fichero) comparando la posición del
  comecocos con márgenes asimétricos; dispara `CLEAR_5773_AND_SET`
  con `C=$4D`.
- `CLEAR_5773_AND_SET` (`$56CA`): helper compartido, limpia las 4
  entradas de `$5773` y opcionalmente guarda una posición nueva.
- `ITEM_EXTRA_TABLE` (`$56F5`, 122 bytes hasta `$5772`): más datos de
  animación/efecto sin descifrar campo a campo (estructura
  reconocida: bloques de un tile repetido + cola de 6-7 bytes +
  terminador `$FF`), transcritos como datos crudos verificados.
- `$5773-$5781`: la zona de trabajo RAM ya conocida (compila a cero).
- `ITEM_TIMER_TICK` (`$5782`): recorre las 4 entradas de `$5773`.
- `ITEM_EFFECT` (`$57D8`): filtra por posición y por tipo de ítem
  (`($2C2D)`), dispara sonido/animación vía `$8D70` o delega en
  `GHOST_HINT_HANDLER` para el tipo 3 ("pista").
- `TABLE_INIT` (`$5885`): inicializa las 3 tablas activas (`$511C`
  8 entradas, `ITEM_TABLE_1` 2 entradas, `ITEM_TABLE_2` 8 entradas)
  con la posición semilla `($2C00)`, limpia `$5773` y la tabla de 3
  entradas de `GHOST_HINT_HANDLER` (`$2C2E`). Llamada desde
  `LEVEL_LOADER` (`CALL $5885`).

**Errores encontrados y corregidos durante la transcripción** (misma
categoría que ya nos había pasado antes en el bucle principal):
faltaban dos `JR` explícitos "redundantes" (saltan a la instrucción
siguiente, offset 0) que el código real sí tiene -- uno de ellos
desplazaba +2 bytes TODO lo que venía después, detectado
inmediatamente por `--sym`. También se encontró que las etiquetas de
bucle (`IH1_LOOP`/`IH2_LOOP`) deben incluir el `PUSH BC` de cada
iteración, no solo el cuerpo -- el `JP NZ` real vuelve al `PUSH BC`,
no a la instrucción siguiente. Y un `CALL C,$8440` que en realidad
era `CALL NC,$8440`. **Verificado: 0 diferencias en los 1164 bytes
completos**, y el fichero entero (`0x28ED-0x28F0`, `0x511C-0x545F`,
`0x5AD5-0x6500`) solo difiere ya en los huecos todavía no
transcritos (más el único byte suelto ya documentado en `0x6500`,
fuera de la zona reubicada).

**Pendiente**: 3 sub-rutinas llamadas desde aquí sin identificar
todavía: `$5278` (usada por ambos manejadores, parece determinar si
el ítem es "cogible" -- vuelve con carry si no), `$53A2` (usada por
`ITEM_TIMER_TICK`) y `$8CEE` (dentro de `madmix1.asm`, cerca de
`MAP_COORD_TO_ADDR`); y el propósito exacto de la variable `$6128`.

### HECHO: `0x511C-0x545F` transcrito completo, 0 diferencias -- aquí vivían `$5278` y `$53A2`

Al abordar lo que se pensaba que era "la tabla de posiciones de
ítems", Z80Dasm desensambló TODO el rango (835 bytes) sin
desincronizar ni una vez, desde `$51FE` hasta el `RET` en `$545E`
(justo antes de `COORD_TO_ADDR` en `$545F`). Resultó ser mucho más
que una tabla:

- `ITEM_TABLE_POS_511C` (`$511C`, 8 entradas x 7 bytes): la tabla de
  tipos ya documentada, contenido de compilación real confirmado
  igual que la muestra en vivo de sesiones anteriores (posición
  semilla `0x10`/`0x20,0x10` + campo final = tipo de ítem 0-3).
- Tabla auxiliar de 170 bytes (`$5154-$51FD`): primeros 32 bytes
  indexados como 16 palabras de 16 bits por `((IX+2) AND $0F)*2`
  (casi todas las entradas son un byte repetido); el resto (138
  bytes) con pinta de tabla de bits de dirección, sin decodificar
  campo a campo -- transcrita como datos verificados.
- **`R51FE_MAIN` (`$51FE`)**: la rutina llamada desde el bucle
  principal (ya documentada como `CALL $51FE` en el motor de
  colisión) -- calcula una posición relativa a la cámara (`+8,+16`,
  guardada en `$2C1F`) y, si `($2BFB)` (**CORREGIDO: es offset 8 del
  registro de nivel, no "offset 11" como decía una nota anterior de
  esta misma sesión -- error de aritmética, `$2BFB - $2BF3 = 8`; ver
  sección "Descifrados offsets 8/11/18/19" más abajo para el
  desglose completo y corregido**) es distinto de cero, recorre esa
  cantidad de entradas de `ITEM_TABLE_POS_511C` activando cada una
  vía `ACTOR_ENGINE` + `ITEM_EFFECT`, igual que los otros dos
  manejadores.
- **`HELPER_5278` (`$5278`)**: el helper que faltaba de
  `ITEM_HANDLER_1`/`ITEM_HANDLER_2` -- comprueba si la posición
  candidata está "detrás" de la cámara según la dirección de
  movimiento actual y calcula una dirección aproximada (`D`),
  después prueba las 4 direcciones (vía `HELPER_5414`, que sí usa
  `COORD_TO_ADDR`/`TILE_TYPE_LOOKUP` para ver si hay loseta libre) y
  decide si el ítem es alcanzable.
- **`HELPER_53A2` (`$53A2`)**: resultó ser un **segundo punto de
  entrada dentro de `HELPER_5278`** (se llega tanto por caída normal
  como por `CALL` directo desde `ITEM_TIMER_TICK`) -- calcula
  distancia/dirección normalizada a la cámara con máscaras `RES 7`
  repetidas (limpiando el bit de "loseta comida" en cada resta).
- `HELPER_5414` (`$5414`): mini-helper de 4 direcciones, ya descrito.

**Un error encontrado**: usé por error la etiqueta
`ITEM_ANIM_TABLE_1` (`$5487`) en un `LD HL,` que en realidad
referencia la tabla auxiliar de 170 bytes de aquí mismo (`$517E`,
un desplazamiento dentro de ella) -- coincidencia de que ambas
tablas parecían intercambiables por contexto, detectado al momento
por el diff byte a byte (2 bytes exactos, los del operando de `LD
HL`). **Verificado: 0 diferencias en los 835 bytes completos.**

## HECHO: `0x5AD5-0x6500` transcrito completo -- `madmix_scr.asm` YA NO TIENE NINGÚN HUECO `DS` PENDIENTE

El último tramo sin explorar (2603 bytes, la "cola" del bloque
reubicado que llega hasta el límite duro de los 0x5500 bytes que
copia `MADMIX0.BIN`) resultó ser, con diferencia, el hallazgo más
grande de toda la reconstrucción de `madmix_scr.asm`: **es la
pantalla de MENÚ PRINCIPAL del juego, con submenús de teclado/
joystick/redefinición de teclas/demo, más los CRÉDITOS ORIGINALES.**

### Los créditos reales del juego (texto plano, sin ambigüedad)

Tabla de texto en `0x5FC2` (formato `[longitud][atributo][texto]`,
igual que el resto de tablas de texto de esta zona):

```
POGRAMADO BY:
RAPHAEL GOMEZZZ..
GRAPHICOS BY :
ROBERTO P.ACEBES
MUSIC-A BY:
COMILONAS
TOPOSHOW -1988-
```

**CORREGIDO** (2026-07-25, tras volcar los bytes reales byte a byte
en vez de fiarse de una lectura "idealizada" anterior): el texto
real NO dice "PROGRAMADO"/"GRAFICOS"/"MUSICA" tal cual, sino
literalmente "POGRAMADO" (sin la primera R), "GRAPHICOS" (con PH)
y "MUSIC-A" (con guion) -- se transcribe tal cual, sin "corregir"
la ortografía, porque son los bytes reales del juego de 1987. El
nombre "RAPHAEL GOMEZ" además tiene dos Z de más al final
("GOMEZZZ"), posiblemente un efecto de desvanecido deliberado o un
error nunca corregido. Hay una entrada más en la tabla,
`"MAD$MIX GAME"` (con un `$` literal en vez de espacio), pero
**no está confirmado que se llegue a mostrar en pantalla** -- las
8 llamadas a `TAIL_DECODE` de `TAIL_CREDITS_DRAW` terminan en la
línea de "TOPOSHOW -1988-", sin alcanzar esa última entrada.

### El menú principal (texto en `0x5BF9`)

```
1 TECLADO
2 JOYSTICK
3 REDEFINE TECLAS
4 DEMO
0 JUGAR
```

Cuatro rutinas (`TI_5C3A`/`TI_5C53`/`TI_5C60`/`TI_5C70`, una por
opción alcanzable con el cursor) automodifican en tiempo de
ejecución los bytes de atributo de este texto (`$5BFA`/`$5C07`,
alternando `$F1`/`$91`) para resaltar la opción actual -- código
automodificable real, no una suposición.

### El menú de redefinición de teclas (opción 3, texto en `0x5E03`)

```
PAUSA / FUEGO / ARRIBA / ABAJO / IZQUIERDA / DERECHA
ESPACIO, S.SHIFT, C.SHIFT, ENTER, SHIFT, CTRL, GRAPH, CAPS,
F1-F5, ESCAPE, TAB, STOP, BS, SELECT, HOME, INS, DEL, símbolos...
```

Las 6 primeras entradas son las acciones del juego redefinibles;
el resto son los nombres de las teclas asignables a cada una.

### El "demo" (opción 4): `TAIL_LEVELCYCLE_MAIN` (`$6045`)

Escribe directamente `$2C07` (nivel actual) con un valor de una
tabla de 4 entradas `LEVELCYCLE_TABLE` (`$60D0`, niveles 1/2/4/5,
punteros dentro de `MADMIX1.BIN`) y llama a `LEVEL_LOADER`/
`TABLE_INIT`/`JT_SLOT9`/`JT_SLOT6` para dibujarlo -- confirma que
"demo" es literalmente enseñar varios niveles en bucle sin jugar.

### Otros hallazgos

- Tres copias más de rutinas ya conocidas: una tercera fórmula
  coordenada→dirección (dentro de `TAIL_JOY_READ`... no, ver
  `HELPER_5414`/`COORD_TO_ADDR`), lectura de teclado por matriz
  estándar del BIOS MSX, y un motor de "descompresión"/dibujado de
  recursos (`TAIL_DECODE`, `$5CD1`) que llama al gestor de recursos
  ya conocido (`$C4A0`/`$C4EB`, el mismo que `main.asm`\`madmix1.asm`
  tiene pendiente como "gestor de recursos").
- **Segunda rutina de reubicación** (`TAIL_RELOCATOR2`, `$64AB`),
  gemela a la de `MADMIX0.BIN`: conmuta slots con valores fijos
  (`$55`/`$50`), copia `0x54AB` bytes de `$8400` a `$1000` y
  ejecuta -- candidato fuerte a "volver al menú/reiniciar" en
  caliente desde dentro de la partida.
- Bloque de 811 bytes tras `TAIL_LEVELCYCLE_HELPER` (`LEVELCYCLE_RESOURCE_TABLE`,
  `$60FE`): los primeros 42 bytes son una tabla real de 14 entradas
  `[id,puntero]` (indexada por la variable `$6128`, apuntando a
  direcciones `$CDxx`/`$CExx`/`$CFxx` -- dentro del "gestor de
  recursos"/programas de bytecode que `madmix1.asm` tiene pendiente
  de trazar). Los 768 bytes restantes (desde `$6129`) son el **marco
  de caramelos**, RESUELTO en dos pasos:
  1. Primer intento (índices de carácter directos contra la fuente
     `$925B`): dio una forma parecida a un marco pero con la fila de
     vidas/puntuación visiblemente desplazada -- pista de que la
     lectura no era la correcta.
  2. **Encontrada la rutina real que consume el bloque**:
     `TAIL_CREDITS_MAIN` (`$6454`), que YA estaba transcrita sin
     haber caído en su papel completo -- lee cada byte, lo pasa por
     `TAIL_TILE_LOOKUP` (`$6484`, nibble-swap usando la tabla real
     `LOOKUP_8978` de `MADMIX1.BIN`, 16 bytes en `$8978`, la misma
     que ya conocíamos), y usa el resultado como **valor de relleno
     sólido** para 8 bytes consecutivos vía `FILVRM` -- no son
     glifos con forma libre, son bloques de textura (como las rayas
     del caramelo). Aplicando la transformación real (768 = 32×24,
     la rejilla completa de pantalla MSX) el resultado tiene mucha
     estructura: un valor domina con 432 repeticiones (fondo/hueco
     central) y aparecen grupos claros de borde/rayas. Ver
     `src/recursos/recurso_grafico.html` (incluye ambos intentos,
     con el correcto marcado y el resto como registro).

  **Conclusión (con el usuario, jugador del original)**: el
  resultado renderizado son rayas verticales monocromas -- más
  gruesas justo donde caerían los caramelos, lo que sugiere que el
  mecanismo/transformación SÍ está bien entendido -- pero no una
  imagen "bonita". Se descartó perseguir la tabla de color como
  siguiente paso: en SCREEN 2 el color solo tiñe estas mismas rayas,
  no les da forma. Conclusión más probable (en su momento):
  **este bloque es una textura/relleno de fondo (sombreado detrás de
  la ventana), NO el dibujo del caramelo en sí** -- el gráfico
  detallado del caramelo (con forma reconocible, estilo loseta 16×16
  como las del laberinto) seguía siendo el hueco entonces pendiente
  en `madmix1.asm`. Investigación cerrada aquí en su momento.

  **CORRECCIÓN IMPORTANTE (sesión posterior, ya con el marco de
  caramelo localizado como `RLE_TABLE_D6B6`)**: esta conclusión
  estaba equivocada en el punto exacto que decía descartar -- **este
  bloque de 768 bytes SÍ es la aplicación del color real del marco
  de caramelo**, no una textura de fondo aparte. Se comprobó
  aplicando la transformación real de `TAIL_TILE_LOOKUP` a los 768
  bytes reales de `LEVELCYCLE_RESOURCE_TABLE` (extraídos de
  `MADMIX.SCR` original) y comparando el resultado contra un volcado
  de VRAM real: **coincide EXACTO, byte a byte**, con la tabla de
  color de VRAM (`$2000`) para toda la pantalla -- fila 0 (el borde
  superior del marco) da `$E1,$E1,$E1,$F1,$F1,$E1` (gris/negro,
  blanco/negro -- las esquinas redondeadas) seguido de `$6E`
  repetido (rojo oscuro/gris -- el tramo recto de rayas) y el
  espejo simétrico al final, calculado sin ningún ajuste manual.
  `TAIL_CREDITS_MAIN` (`$6454`) es la rutina real: lee los 768 bytes
  desde `$6129`, los traduce con `TAIL_TILE_LOOKUP` (combina dos
  consultas a `DIRBITS_TABLE`, nibble alto y bajo) y rellena la
  tabla de color de VRAM completa (`$2000`, 768 celdas × 8 bytes) vía
  `FILVRM` -- exactamente el mismo patrón "RLE aparte para la forma,
  tabla de color aparte para el tinte" que ya conocíamos de otros
  gráficos de SCREEN 2. **Con esto queda resuelto del todo dónde se
  aplica el color real (rojo/blanco/gris) del marco de caramelo** --
  la forma viene de `RLE_TABLE_D6B6` (`madmix1.asm`) y el color de
  este bloque de 768 bytes (`madmix_scr.asm`, vía
  `TAIL_CREDITS_MAIN`/`TAIL_TILE_LOOKUP`). El error de la conclusión
  anterior fue evaluar la imagen renderizándola como si los bytes
  fueran patrón (blanco y negro) en vez de reconocerlos como bytes
  de atributo de color (nibble alto = tinta, nibble bajo = fondo).

### Metodología y errores encontrados

Desensamblado completo con Z80Dasm sin desincronizar en ningún
punto real de código (solo las zonas de texto/tablas, esperado).
Transcripción muy laboriosa por la cantidad de **puntos de entrada
dobles dentro de la misma rutina** (reutilización de código: un
`CALL`/`JR` salta a mitad de otra rutina para reusar su cola con un
parámetro distinto, patrón ya visto en `MADMIX0.BIN` pero aquí
mucho más frecuente) -- la mayoría de los errores de esta sesión
fueron etiquetas mal colocadas por asumir el destino "obvio" de un
salto en vez de verificar la dirección real byte a byte, detectados
todos por `--sym`/diff y corregidos uno a uno. **Verificado: 0
diferencias en los 2603 bytes completos.**

**`madmix_scr.asm` está ahora byte a byte completo al 100%**, salvo
2 bytes ya documentados de sesiones anteriores y ajenos a esta tarea
(el hueco de 3 bytes en `0x28ED-0x28F0` y el byte suelto en `0x6500`,
fuera de la zona reubicada por `MADMIX0.BIN`).

## SEGUNDO HALLAZGO GRANDE en los huecos de `madmix_scr.asm`: `0x2BF0-0x335C` es el BUCLE PRINCIPAL DE JUEGO (movimiento, colisión, ítems, trampillas)

Siguiendo con la revisión de huecos, `0x2BF0-0x335C` (~1900 bytes,
solo 4% ceros -- claramente denso, no relleno) resultó ser
desensamblable como código real y coherente desde `0x2CA0` hasta el
final del tramo (`0x335C`). Es, con mucha probabilidad, **la rutina
central de actualización de juego por fotograma** -- el código que
ata literalmente casi todo lo que llevamos meses reconstruyendo:

- Llama a `MAP_COORD_TO_ADDR` (`0x8CB6`), `TILE_TYPE_LOOKUP`
  (`0x8CDA`), `REDRAW_STRIP` (`0x8D1B`), `JT_SLOT6` (`0x8E3C`,
  colisión), `JT_SLOT7` (`0x8D70`), `JT_SLOT8` (`0x89AD`, disparo de
  scroll) y `ACTOR_ENGINE` (`0x8440`) -- prácticamente el índice
  completo de la jump table del motor principal, todo desde un solo
  sitio.
- Hay un **despacho por dirección** claro: lee/calcula un valor de
  entrada (0-15, `AND $0F`), lo usa como índice en una tabla de
  punteros en `$2E3C` (16 entradas de 2 bytes) y salta con
  `JP (IX)` -- un jump table de "qué hacer según la dirección de
  movimiento", posiblemente combinado con qué tipo de loseta hay
  delante (los saltos condicionales comprueban `TILE_TYPE_LOOKUP`
  antes de decidir).
- Llama, condicionadas a flags, a los DOS manejadores de ítems
  especiales que se acaban de encontrar y documentar arriba
  (`CALL Z,$51FE` / `CALL Z,$54A9` / `CALL Z,$55C0`) y a
  `ACTOR_ENGINE` justo después (`CALL Z,$8440`) -- confirma que
  este bucle central es quien DECIDE cuándo activar un ítem y
  cuándo activar un actor, no al revés.
- El tramo final (`~0x32D6-0x335C`, justo antes del límite duro con
  la zona de niveles) es una rutina de **animación de trampilla**:
  escribe explícitamente los índices de loseta `0x43,0x44,0x45,
  0x47,0x48,0x49,0x4A,0x4B` (que son EXACTAMENTE las trampillas
  76-79/71-74 ya catalogadas en `graficos.html` como "transición
  A<->B, se tumba/vuelca") en las 4 posiciones de un cuadrante 2×2,
  llamando a `REDRAW_STRIP` una vez por loseta -- el mecanismo real
  de "la trampilla se voltea" que solo conocíamos de nombre.
- De paso quedan mejor acotadas bastantes variables `$2Cxx` que
  antes solo teníamos sueltas: `$2C0E` funciona como un contador
  que se decrementa y se compara contra `$3C` (el mismo tile
  comodín del registro de nivel, offset 12 -- reutilizado aquí como
  límite), `$2C0D`/`$2C2D` como flags de estado, `$2C04`/`$2C24`
  como selectores de dígito de HUD (ya vistos en el cargador de
  nivel y en `INIT`).

**Sin transcribir todavía** -- es un bloque grande y denso (~1900
bytes) que merece su propia sesión de transcripción cuidadosa en
vez de hacerse deprisa. Quedan también sub-rutinas llamadas desde
aquí sin identificar: `$2E64`, `$5782` (ya visto desde el otro
subsistema de ítems) y el propósito exacto de la tabla de 16
punteros en `$2E3C`.

**Implicación importante**: entre este bucle principal y el
subsistema de ítems especiales documentado justo arriba, los DOS
huecos de código de `madmix_scr.asm` (`0x2BF0-0x335C` y
`0x5478-0x5904`) están MUCHO más entendidos de lo que parecía al
empezar la sesión -- ninguno de los dos es ya un misterio genérico,
son piezas centrales y nombrables del motor de juego.

### HECHO: `0x2BF0-0x335C` transcrito completo a `madmix_scr.asm`, 0 diferencias byte a byte

Transcripción completa: `MAINLOOP_TABLES` (0x2BF0-0x2CA0, via
INCBIN), `MAIN_LOOP` (0x2CA0-0x2E3C), `ML_DISPATCH_TABLE`
(0x2E3C-0x2E64), `CHECK_TILE_DELTA` (0x2E64-0x2E9F),
`DRAW_TILE_HELPER` (0x2E9F-0x2EB7), y los 20 manejadores +
`TRAPDOOR_FLIP_TABLE` (0x2EB7-0x335C), con etiquetas `HANDLER_XXXX`
por dirección real. **Verificado: 0 diferencias en las 1724 bytes**
contra `MADMIX.SCR` original.

Dos errores propios encontrados y corregidos durante la
transcripción (anotados porque son el tipo de fallo que puede
repetirse):

1. **La tabla de despacho tiene 20 entradas, no 16** -- se asumió
   "nibble de 4 bits" (0-15) sin verificar contra la dirección real
   de la rutina siguiente (`CHECK_TILE_DELTA`, que debía caer en
   `0x2E64`); al no cuadrar (caía en `0x2E5C`, exactamente 16
   entradas × 2 bytes antes de lo esperado) se detectó el error.
   Las 4 entradas que faltaban (17-19, más una repetida) resultan
   ser precisamente los 3 bloques de código que parecían "sin
   conectar" (dibujado de variantes de trampilla) -- resuelve esa
   duda de paso.
2. **Una etiqueta de bucle mal colocada**: `JR Z,$2D9C` en el
   original vuelve a repetir el CALCULO COMPLETO del índice de
   tabla (empezando en `LD HL,$2C14`), no solo la relectura de
   `(HL)` -- se había puesto la etiqueta 17 bytes tarde, en la
   instrucción equivocada. Detectado por el único byte que no
   cuadraba en la primera pasada de verificación.

Metodología: verificar por RANGOS con `--sym` (cada etiqueta debe
caer en su dirección real exacta) antes de fiarse del byte-diff
completo -- así se localizan los errores estructurales (bytes de
más/de menos) de forma casi inmediata, en vez de tener que rastrear
un diff genérico.

## VOLCADO DE MEMORIA EN VIVO (openMSX) -- pone en duda la premisa de PHASE/DEPHASE

El usuario capturó memoria en vivo con el juego corriendo en
openMSX (consola Tcl del depurador):

```
save_debuggable memory ram.bin 0 65536
save_debuggable VRAM vram.bin 0 16384
```

Ficheros en `src/dump_openmsx/ram.bin` (64KB, espacio de
direcciones del Z80 tal cual lo ve la CPU en el momento de la
captura) y `src/dump_openmsx/vram.bin` (16KB, VRAM del VDP,
espacio aparte no accesible directamente por el Z80). Comandos
usados guardados en `src/capturar_openmsx.md`.

### Verificación de alineación: el volcado es fiable

Antes de sacar conclusiones se comprobó que el volcado coincide
con lo ya confirmado contra el `.BIN` estático:
- `0x8931` (FILVRM) y `0x8440` (JT_SLOT2) coinciden byte a byte
  con el `.BIN` original -- la página 2 (0x8000-0xBFFF) del
  volcado SÍ es la imagen estática de `MADMIX1.BIN`, como se
  esperaba.

### HALLAZGO IMPORTANTE: el motor corre desde direcciones ESTÁTICAS, no desde la copia reubicada

Se comprobaron 3 rutinas que ya teníamos confirmadas por dirección
ESTÁTICA (dentro del rango que madmix1.asm viene tratando como
"bloque reubicado", 0x8800-0xDD00) contra sus mismas direcciones
ESTÁTICAS en el volcado en vivo:

- `0x8988` (`ADDR_FROM_DC00`): coincide byte a byte.
- `0x899B` (`RESET_8437`): coincide byte a byte.
- `0x8961` (`LOOKUP_8978`): coincide byte a byte.

O sea: el código de estas rutinas está EJECUTÁNDOSE de verdad
desde su posición estática original, tal cual está en el fichero
-- no hace falta ninguna reubicación para que funcionen.

En cambio, la dirección `0x1000` (donde `madmix1.asm` viene asumiendo
que vive la copia reubicada y ejecutándose, virtual de
`LOOKUP_8978` incluido -- comprobado en `0x1161`, que en el
volcado sale TODO A CEROS, sin coincidir) contiene código
COMPLETAMENTE DISTINTO al esperado: inicialización de VDP/pantalla
(`LD HL,$1800` -- la dirección estándar de la tabla de nombres de
pantalla en SCREEN2 por defecto, más un bucle rellenando VRAM
puerto a puerto). No se parece en nada a nuestro `LOOKUP_8978` ni
al resto del bloque reconstruido.

**Hipótesis de trabajo (reemplaza la de la sesión de análisis
original)**: la reubicación de `MADMIX0.BIN` (0x8800→0x1000,
`CALL 0x1000`) es probablemente una operación de **arranque de un
solo uso** (quizá configuración inicial de VDP/pantalla, ejecutada
una vez porque en ESE momento del arranque hace falta código
corriendo desde página baja por algún motivo -- p.ej. mientras el
ROM de disco ocupa otras páginas), NO la instalación permanente de
todo el motor de juego como decía la nota "persiste durante todo
el juego, no solo al arrancar". El motor real (ISR, actores,
scroll, etc.) vive y se ejecuta permanentemente en sus direcciones
ESTÁTICAS (0x8400 en adelante), sin reubicación.

**CORREGIDO en `madmix1.asm`**: se quitó `PHASE $1000`/`DEPHASE` por
completo. Todo el fichero usa ahora direcciones ESTATICAS reales
de principio a fin (un solo `ORG $8400` sin reubicación alguna).
El hecho duro de que `MADMIX0.BIN` copia 0x5500 bytes de 0x8800 a
0x1000 sigue anotado (viene del propio loader), pero ya NO se
interpreta como "hace falta direccionamiento virtual para que el
motor funcione" -- se interpreta como una operación de arranque de
un solo uso (probablemente inicialización de VDP/pantalla, dado lo
que se ve en `0x1000` del volcado) que no afecta a cómo se organiza
el resto del código. Recompilado y verificado: TODAS las
direcciones confirmadas (`ISR` 0x882A, `FILVRM` 0x8931, `LDIRVM`
0x8942, `SETVRAM` 0x8954, `LOOKUP_8978` 0x8961, `ADDR_FROM_DC00`
0x8988, `RESET_8437` 0x899B, `WAIT_VBLANK` 0x89A0,
`MAP_COORD_TO_ADDR` 0x8CB6, `TILE_TYPE_LOOKUP` 0x8CDA,
`REDRAW_STRIP` 0x8D1B, `TILE_TYPES` 0x8EC4, `INIT` 0x8F24) siguen
cayendo exactas, mismo tamaño de fichero (22938 bytes), 0 errores.

**Efecto colateral bueno**: al re-verificar direcciones con este
cambio se encontró que `MAP_COORD_TO_ADDR` caía en `0x8CB8`, no en
`0x8CB6` -- por culpa de una variable `PLAYER_POS` inventada
(nunca confirmada contra el binario) colocada justo delante, que
desplazaba 2 bytes todo lo que venía después. Se quitó `PLAYER_POS`
de ahí; si de verdad existe esa variable en el original, hay que
localizarla por desensamblado antes de volver a colocarla.

### Otros datos del volcado, sin conclusión clara todavía

- **`$8437`** (contador de actores) en vivo = `06` (6 actores
  activos en el momento de la captura) -- consistente con la
  hipótesis de "contador de actores".
- **`$8438`** (cursor de gráficos, hipótesis anterior) en vivo =
  `$06B0` (16 bits, no `$0500` -- normal, ya habrá avanzado tras
  crear varios actores).
- **Array de actores en `0x92E3`** (stride 12 bytes) tiene datos
  reales y distintos por actor, ej. actor 0 = `FB A4 10 E1 0C 00
  05 11 2F 84 00 00` -- confirma que la estructura de 12 bytes es
  real, aunque llama la atención que contenga la secuencia `11 2F
  84` (que son literalmente los bytes de opcode `LD DE,$842F`,
  una instrucción real que aparece en el código de `0x870B`) --
  sin explicar todavía si es coincidencia o si el registro de
  actor incluye de verdad un fragmento de código.
- Se renderizó `$0500` (RAM) como si fueran gráficos de loseta
  (formato raster 16x16) esperando encontrar los sprites de
  personajes ahí -- **no dio una forma reconocible** (ver
  `scratch_img/ram_0500.png`, ya no incluido en el repo). Dado
  que ahora sabemos que `$8438` cambia dinámicamente, probar en
  la dirección que señala `$8438` EN VIVO (`$06B0` en esta
  captura) sería el siguiente paso lógico si se retoma este hilo,
  en vez de la `$0500` inicial (que solo es el valor de arranque
  antes de crear ningún actor).
- Pendiente: analizar `vram.bin` (16KB) -- todavía no se ha mirado
  nada de la VRAM real, que es donde vivirían los patrones de
  sprite de hardware si es que existen.

## Análisis de VRAM (vram.bin) -- CONFIRMA que los personajes son render por software

Reconstruyendo la pantalla completa (tabla de patrones `0x0000`,
tabla de nombres `0x1800`, tabla de color `0x2000`, formato
SCREEN2 estándar) a partir de `vram.bin`, y comparando contra
`src/dump_openmsx/ejemplo.png` (captura de referencia de internet
que aportó el usuario para ver la composición correcta):

- **La tabla de sprites de hardware está vacía/sin usar**: la
  tabla de atributos (`0x1B00`) tiene los 32 sprites aparcados en
  el mismo Y=209/X=0 con números de patrón secuenciales de
  relleno, y la tabla de patrones de sprite (`0x3800`) está
  rellena de un byte constante (`0x01`) -- no hay gráficos reales
  ahí. Refuerza lo que ya sospechábamos: los personajes NO usan
  sprites de hardware.
- **La tabla de nombres (`0x1800`) es identidad pura**: los 768
  bytes son exactamente `00,01,02...FF` repetido 3 veces (una por
  cada "tercio" de pantalla de SCREEN2). Esto confirma que el
  juego NUNCA reutiliza un patrón por índice -- en vez de eso,
  cada celda de pantalla tiene su PROPIO byte de 8x8 dedicado en
  la tabla de patrones, y el motor dibuja escribiendo directamente
  ahí (coincide exactamente con la hipótesis del "motor de
  actores" de `JT_SLOT2`: renderizado por software con
  desplazamiento de bits, no sprites).
- **La reconstrucción inicial (24 filas completas) salía con una
  composición rota** (el usuario lo notó: el HUD de vidas/
  puntuación aparecía desplazado, con 2 filas de losetas y el
  caramelo inferior "sobrando" después). Se probó (sin éxito
  real, ver más abajo) la hipótesis de un scroll vertical por
  rotación de filas.
- **Causa real encontrada**: analizando el color predominante de
  cada una de las 24 filas de pantalla, las filas **21, 22 y 23
  están completamente a 0x00** (negro/sin usar), y las filas
  **16-20 contienen contenido sobrante** (parece un laberinto y un
  caramelo "extra" que no pertenecen a la composición actual). La
  composición real y completa está en las filas **0-15** (128 de
  los 192 píxeles de alto): caramelo arriba, laberinto, caramelo
  abajo, y la franja de HUD (vidas/puntuación) justo debajo,
  exactamente como en `ejemplo.png`. Recortando a esas 16 filas la
  reconstrucción coincide perfectamente con la referencia.
### CORREGIDO: no había que recortar filas -- era un "torn frame" localizado

El primer intento de "arreglo" (recortar a las filas 0-15) estaba
mal: cambia la proporción de la imagen y de todas formas no es lo
que hay que hacer. El usuario aportó `src/dump_openmsx/ejemplo.png`
(captura de referencia de internet, confirmado que es la MISMA
pantalla exacta -- inicio de la fase 1, solo cambian posición del
fantasma y vidas). Comparando estructuralmente (conteo de píxeles
no-negro por franja de 8px, para no depender de si mi paleta de
colores aproximada es exacta) la referencia contra las 24 filas de
la VRAM:

- Filas 0-11 y 16-19 de la VRAM coinciden EXACTAS con la
  referencia, en su misma posición -- esa parte del volcado es
  perfectamente consistente.
- Filas 12-13 de la VRAM (caramelo inferior) tienen el perfil
  EXACTO de lo que en la referencia debería estar en las filas
  20-21 -- el contenido es real pero está en la posición
  equivocada dentro de la VRAM en el instante de la captura.
- Filas 14-15 (HUD, conteo bajo = iconos pequeños) no encajan
  limpiamente en ningún sitio; filas 21-23 (donde debería estar el
  HUD real) están a cero.

**Explicación confirmada por el usuario**: en el momento de la
captura el comecocos NO se movía y el scroll estaba parado --
SOLO el fantasma estaba en movimiento. Como los personajes se
pintan por software (motor de `JT_SLOT2`, ver más arriba,
reescribiendo directamente la tabla de patrones), lo más probable
es que la captura pillara al motor A MITAD de redibujar al
fantasma, justo en la banda de filas donde estaba en ese instante
-- de ahí que solo esa franja concreta (12-15, y por tanto también
lo que le corresponde en 20-23) salga inconsistente, mientras el
resto de la pantalla (estática, sin nada animándose) coincide
perfecto con la referencia. No es un fallo de direccionamiento ni
de la reconstrucción -- es un frame parcialmente a medio escribir,
capturado real.

**RESUELTO con una segunda captura**: el usuario repitió la
captura (`ram2.bin`/`vram2.bin`, mismos ficheros y tamaños que la
primera) y esta vez la reconstrucción sale limpia y coincide con
`ejemplo.png`: marco completo por los 4 lados, comecocos con cara
correcta, HUD con 3 vidas + puntuación justo debajo del marco. Se
volvió a verificar `ram2.bin` contra `ADDR_FROM_DC00` (0x8988) y
`RESET_8437` (0x899B) -- siguen coincidiendo exactos. Imagen final
en `src/dump_openmsx/screen_reconstructed.png` (sin recortar,
256x192 completo).

### CORRECCIÓN: el problema seguía ahí -- no era ni rotación ni "torn frame"

Lo anterior era una conclusión demasiado optimista (el usuario lo
detectó mirando la imagen con más atención de la que yo le di: a
tamaño grande se ve claramente un SEGUNDO tramo de laberinto +
marco de caramelo repetido después del HUD, que no debería estar).
Se repitió la captura una tercera vez (`ram3.bin`/`vram3.bin`) con
un breakpoint puesto a propósito en la ISR confirmada (`0x882A`,
vía `debug breakpoint set 0x882A` en la consola de openMSX) para
garantizar que la captura cae siempre en el mismo instante exacto
del ciclo de dibujado, en vez de una pausa manual con timing
aleatorio. **El resultado es pixel a pixel IDÉNTICO al de la
segunda captura** -- lo cual DESCARTA con bastante seguridad que
sea un "frame a medio escribir" (con sincronización exacta al
mismo punto del ciclo, un problema de timing habría cambiado o
desaparecido).

Se comprobaron los registros reales del VDP en ese instante:
`R2=6` (tabla de nombres → `0x1800`), `R3=255` (tabla de color →
`0x2000`), `R4=3` (tabla de patrones → `0x0000`), `R5=54` (attrs
sprite → `0x1B00`), `R6=7` (patrones sprite → `0x3800`), `R10=0`.
Son EXACTAMENTE las direcciones estándar de SCREEN 2 por defecto
que ya se estaban usando -- descarta que el error sea una tabla
mal ubicada.

**Hipótesis de "bit enmascarado" probada y DESCARTADA**: el patrón
de filas afectadas (12-15 y 20-23, es decir, la mitad "alta" de
cada tercio de 8 filas, donde el name-byte tiene el bit 7 puesto)
sugería que el hardware del VDP podría estar forzando ese bit a 0
al calcular la dirección dentro de cada tercio (un mecanismo de
"mascara" documentado para Graphics II, ver hilos de
smspower.org/meka). Se probó forzando ese bit a 0 en el cálculo
-- el resultado fue PEOR (aparecieron duplicados también en las
filas 0-7, que antes salían bien), así que esta hipótesis
concreta queda descartada.

**Estado actual: sin resolver.** Los registros del VDP son
estándar, la sincronización por breakpoint descarta timing, y la
hipótesis de enmascarado de bits no encaja. El defecto es
consistente y reproducible en 3 capturas distintas, así que es
real y no ruido -- pero no se ha encontrado todavía la causa. No
se recomienda seguir intentando arreglarlo por prueba y error de
fórmulas; si se retoma, lo más productivo sería (a) revisar código
fuente de un emulador real (openMSX, blueMSX) para ver su fórmula
exacta de direccionamiento en modo Graphics 2, en vez de
documentación dispersa, o (b) aceptar que la reconstrucción visual
pixel-perfect de la pantalla es secundaria -- ya tenemos confirmado
lo importante (sin sprites de hardware, tabla de nombres identidad,
renderizado de personajes por software) de forma sólida e
independiente de este detalle sin resolver.

## Gráficos de actores extraídos DIRECTAMENTE de la VRAM (ground truth)

Aprovechando que ya sabemos decodificar la tabla de patrones
correctamente (al menos en las filas "buenas" de la pantalla, ver
sección de volcado de VRAM), se recortaron directamente de
`src/dump_openmsx/screen_reconstructed.png` dos gráficos reales
confirmados:

- **`src/dump_openmsx/actor_comecocos_maze.png`**: la cara del
  comecocos tal como se ve de verdad en el laberinto. Nota
  importante: NO está alineada a la rejilla de 8x8 -- ocupa una
  posición con desplazamiento de sub-píxel, consistente con el
  render por software de movimiento fino que ya vimos en
  `JT_SLOT2`. Esto confirma que un recorte limpio de 16x16 no
  siempre es posible directamente del framebuffer; puede hacer
  falta capturar en un instante alineado a loseta, o aceptar el
  desplazamiento.
- **`src/dump_openmsx/border_candy_corner_TL.png`** (renombrado,
  antes se llamaba por error `actor_ghost_corner_TL.png`): el
  usuario (que conoce el juego) confirma que esto NO es un
  fantasma. Es el remate blanco y redondeado donde se juntan el
  extremo del envoltorio de caramelo HORIZONTAL (arriba) y el
  VERTICAL (lateral) en la esquina -- ambos extremos son blancos y
  redondeados por diseño, y al superponerse en la esquina parecen
  (a mi ojo, equivocadamente) una silueta de fantasma. Las 4
  esquinas tienen el mismo motivo, que es puramente decorativo del
  marco de caramelo, sin relación con los fantasmas del juego.
  Sigue pendiente encontrar una imagen real de un fantasma.

  **CERRADO/OBSOLETO** (sesión posterior): el objetivo de este punto
  era conseguir "ground truth" visual para poder identificar los
  sprites de personajes por comparación. Eso ya se consiguió por una
  vía mucho más directa y fiable -- el usuario (jugador original)
  identificó los 64 sprites a simple vista en
  `src/recursos/ptrtable_sprites.html`, incluidos los de fantasma
  (`SPR27_FANTASMA_DER_1` a `SPR36_FANTASMA_VULN_ABAJO_2`,
  `SPR62_FANTASMA_MUERTO`), verificado con 0 diferencias byte a
  byte. Ya no hace falta perseguir una captura de VRAM con un
  fantasma real -- el propósito de esta tarea está cumplido por
  otro camino.

## Personajes del juego (según el usuario, jugador del original)

Comecocos, fantasmas, hipopótamo, tanque, avión/nave, mariquita
(reponía bolas), apisonadora (las aplastaba), trampillas
(bloqueaban a los fantasmas, se podían girar empujando desde un
lado para invertir el bloqueo y pasar por encima). Sprites
candidatos localizados en `0x9D40-0xA3E0` pero SIN asignar cada
uno a su personaje — pendiente de trazado en vivo o de más
análisis visual.

## Estado del proyecto madmix1.asm

Compila con SjASMPlus, ~22.9KB de salida (el original son 22952
bytes de fichero = 22945 de código). El truco de reubicación
(`PHASE $1000`/`DEPHASE`) YA está implementado: el bloque
`0x8800-0xDD00` se ensambla dentro de `PHASE $1000`, y cada
rutina/dato CONFIRMADO (ISR, API de VDP, WAIT_VBLANK,
MAP_COORD_TO_ADDR, TILE_TYPE_LOOKUP, REDRAW_STRIP, TILE_TYPES,
INIT, TILE_GFX, MAZE_DATA) cae en su dirección real verificada,
con huecos `DS` (relleno de ceros, marcados y comentados) entre
medias para lo que aún no está reconstruido. La tabla de saltos
(0x8400-0x842E) se verificó byte a byte contra el `.BIN` original
y usa direcciones estáticas literales (no símbolos) a propósito,
por cómo interactúa con `PHASE`. `INIT` (0x8F24) está transcrito
byte a byte hasta el offset `0x8F71` (ver sección propia).

**NOTA (desactualizada arriba, corregida aquí)**: `madmix1.asm` ya
NO usa `PHASE`/`DEPHASE` (se descartó tras el volcado de RAM en
vivo, ver sección propia mas abajo) -- corre con `ORG` estatico de
principio a fin.

## CORREGIDO: bug real de 7 bytes en la cabecera de `madmix1.asm` (arrastrado desde el principio, nunca detectado)

Al comparar direcciones con el CAS/ROM de la v2.0 (ver mas abajo) se
detecto que `madmix1.asm` tenia el MISMO problema que ya se habia
encontrado y arreglado en `madmix0.asm` y `madmix_scr.asm`: el
`ORG $8400` colocaba la cabecera MSX (`DB $FE` + 3 `DW`, 7 bytes)
ocupando espacio de direcciones REAL, cuando esos 7 bytes son
metadato de fichero que el `BLOAD` real consume y nunca llega a
estar en memoria. Esto desplazaba `START`/`JT_INIT` +7 respecto a
su direccion real (`--sym` mostraba `START: 0x8407` en vez del
`0x8400` real), Y ademas hacia que el primer hueco `DS` despues de
la tabla de saltos (documentado como "`$842E-$8430`, 2 bytes")
calculara mal su tamano: el hueco real, verificado contra el
`.BIN` original, es **`$8427-$8430`, 9 bytes** (todo ceros en
ambos casos, así que el contenido de esos bytes no cambiaba nada
jugable, pero el fichero compilado quedaba **7 bytes corto por el
final** -- 22938 en vez de los 22945 reales -- y los ultimos bytes
salian `00 00...00` en vez de los reales `...FF FF FF FF CD`).

**Por que no se detecto antes**: la tabla de saltos usa direcciones
literales (no simbolicas) en sus `JP`, asi que los BYTES compilados
de esa zona seguian siendo correctos pese al error de direccionamiento
interno. Y por una casualidad de la aritmetica (`DS destino-$`), el
hueco `$8430-$` (junto con `FRAME_FLAG` y el segundo `DS $8440-$`)
"absorbia" el desplazamiento de +7 exactamente en ese punto, asi que
TODAS las etiquetas posteriores (`FRAME_FLAG`, `ACTOR_ENGINE`,
`TILE_TYPES`, `INIT`...) ya caian en su direccion real correcta --
por eso las verificaciones de secciones posteriores (960 bytes de
`JT_SLOT2`, etc.) siempre dieron "0 diferencias" y el bug pasó
desapercibido durante varias sesiones.

**Arreglo**: cambiar `ORG $8400` por `ORG $83F9` (7 bytes antes),
para que la cabecera ocupe `$83F9-$83FF` y `START` caiga exactamente
en `$8400`. Verificado: `START: EQU 0x8400`, `JT_INIT: EQU 0x8403`
(antes `0x8407`/`0x840A`), tamano compilado correcto (22945 bytes,
igual que el original sin cabecera), **0 diferencias en
`0x8400-0x8440`** (antes tenia el hueco mal dimensionado), y las
secciones ya verificadas (`JT_SLOT2`/`ACTOR_ENGINE` 960 bytes,
`TILE_TYPES` 96 bytes) siguen en 0 diferencias tras el cambio --
el arreglo no rompio nada que ya funcionara.

Lo que YA está: cabecera, tabla de saltos (verificada 100%), ISR
con housekeeping básico, API de VDP completa
(SETVRAM/LDIRVM/FILVRM), esqueletos de las rutinas de scroll,
tabla de tipos de loseta completa y corregida, `INIT` parcialmente
transcrito byte a byte, gráficos de loseta completos
(`data/tile_gfx.bin`), datos de laberinto candidatos
(`data/maze_data.bin`), reubicación de memoria con
`PHASE`/`DEPHASE`.

Lo que FALTA (por orden de impacto en el tamaño):
1. Marco de caramelo (~8KB de datos gráficos, `0x9600-0xB700`)
2. Zona de personajes (~1.7KB, `0x9D40-0xA3E0`)
3. Intérprete de cabeceras de recursos + resto de `0xC900-0xD000`
4. Resto de `0xD500-0xDDA0`, en su mayoría sin explorar (pero ver
   el hallazgo de `$5B56` cayendo dentro de `maze_data.bin` —
   revisar antes de asumir que `0xD000-0xD500` es solo datos)
5. Rellenar de lógica real todas las rutinas marcadas `; TODO`
   (incluyendo continuar `INIT` desde `0x8F74`, y las funciones
   sin identificar de la tabla de saltos: slots 2,3,5,6,7,8,9)
6. Resolver el misterio de mezcla estática/virtual en `INIT`
   (`CALL $881B` vs `CALL $5D0A`/`$6429`/`$5B56`) con trazado en
   vivo (emulador + debugger) — el análisis estático ya no da más
   de sí en este punto concreto.

## MILESTONE: `0xC4A0-0xD000` transcrito completo -- es el DRIVER DE SONIDO/MÚSICA del PSG, no un "gestor de recursos" genérico

Rellenado uno de los huecos `DS` pendientes de `madmix1.asm` (el
más tratable de los cuatro, por tener puntos de entrada conocidos
desde `INIT`). Desensamblado completo con `Z80Dasm.exe -begin 0
-offset 0xC4A0` sobre un slice exacto del `.BIN` original
(`fileOffset = addr - 0x8400 + 7`), transcrito instrucción a
instrucción (generado con un script de PowerShell que parsea la
salida del desensamblador y solo pone etiqueta en las direcciones
que de verdad son destino de `JR`/`JP`/`CALL`/`DJNZ` dentro del
propio bloque, para no inventar nombres de más), y **verificado 0
diferencias byte a byte** compilando el bloque de forma aislada
con `ORG $C4A0` y comparando contra los 2912 bytes reales
extraídos directamente del `.BIN` (evita el problema de que el
resto del fichero `madmix1.asm` todavía no tiene direcciones
reales a partir de `TILE_GFX`, ver nota más abajo).

**Identificación real**: no es un "gestor de recursos" genérico —
es el **driver de sonido/música del PSG** (AY-3-8910, puertos de
E/S `$A0`=registro / `$A1`=dato). Encaja con el crédito real
"MUSIC-A BY: COMILONAS" ya encontrado en la pantalla de créditos
(`madmix_scr.asm`, sección `TAIL_CREDITS_TEXT`; texto real con
guión, no "MUSICA", ver sección de créditos más arriba).

- `LOAD_RESOURCE_SLOT_ALLOC` (`0xC4A0`, confirmado, ya se llamaba
  así en el `asm`): busca hueco libre entre 4 "ranuras" de canal
  de 46 bytes (`$2E`) en una tabla en `0xC9C9`, lo inicializa a
  cero y guarda el puntero DE (el script de sonido) dos veces.
- `RM_C4CC`: helper interno equivalente pero con índice EXPLÍCITO
  en A (no busca hueco) — fuerza la ranura A al puntero DE.
- `RM_C4F9` (bucle reproductor principal, recorre 3 ranuras): por
  cada ranura activa, si no está "esperando" (contador de tics),
  lee un byte de comando desde el puntero de script. Bytes `>=
  0x80` son comandos de una tabla de salto de 15 entradas
  (`RM_TABLE_C99E`, en `0xC99E-0x9BB`): cambiar nota/instrumento,
  ligar volumen a un canal "compañero", activar/desactivar un
  efecto de sonido, terminar/repetir script, fijar máscara de
  ruido, etc. — sin descomponer cada uno de los 15 comandos nota
  a nota (fuera del alcance de este proyecto de preservación
  binaria, no cambia el resultado del binario). Bytes `< 0x80` son
  duración de nota, indexados en una tabla de 96 palabras de
  retardo (`RM_TABLE_C8DE`, en `0xC8DE-0x99D`).
- `RM_C8C9`: cada "tic" vuelca los 11 registros del PSG a los
  puertos `$A0`/`$A1` (bucle `D=$0B`) — el punto de salida real
  hacia el chip de sonido.
- Los 3 punteros de script que `INIT` instala con
  `LOAD_RESOURCE_SLOT_ALLOC` (`$CDCB`/`$CDFF`/`$CE0C`, índices
  0/1/2) caen DENTRO del propio bloque de datos de este driver —
  confirma que son 3 recursos de sonido reales (música + 2
  efectos, o similar), no punteros a datos externos aún sin
  localizar.
- `LOAD_RESOURCE_SLOT_EMPTY` está en `0xCF8B` — la dirección que ya
  se sospechaba antes de desensamblar este bloque, ahora
  **confirmada** (`--sym` + byte-diff contra los 4 `CALL $CF8B`
  reales que hace `INIT`; búsqueda de bytes en todo el `.BIN`
  también encontró 8 apariciones en total, ver más arriba). Un
  primer intento de esta sesión la desplazó por error a `0xCF8E`
  (fallo de extracción propio: los 3 bytes `LD DE,$0000` justo
  antes del `XOR A` se clasificaron mal como datos en vez de
  código) — detectado y corregido al ver 14 diferencias
  inesperadas en los `CALL` de `INIT` durante la verificación
  final. Llama 3 veces a `RM_C4CC` con `A=0,1,2`, fijando siempre
  `DE=$0000` justo antes de cada llamada (las 3 son simétricas).
- El resto de los ~1700 bytes de datos (tabla de duraciones, tabla
  de salto, estado de canales a cero en el `.BIN` original, tablas
  de instrumento/nota en `0xCA53` en adelante, los 3 scripts de
  sonido y una tabla final en `0xCFA4-0xCFFF` con pinta de
  envolvente de percusión) se transcriben como bytes crudos
  (`DB`), verificados byte a byte, sin intentar decodificar cada
  nota — igual que se hizo con `TILE_TYPES` en su momento.

**Nota importante sobre direcciones absolutas**: el hueco grande
anterior (`0x8F74-0xB940`, marco de caramelo + sprites de
personajes, ~11KB) sigue SIN reconstruir y **no** se rellena con
`DS` (a propósito, ver comentario en el propio `.asm`) porque
ninguna dirección intermedia está confirmada todavía. Esto quiere
decir que `TILE_GFX` y TODO lo que viene después en el fichero
ensamblado (incluido este driver de sonido recién transcrito)
caen en una dirección física MENOR que su dirección real hasta que
ese hueco se rellene — es la misma limitación ya documentada en
"Estado del proyecto madmix1.asm". Por eso la verificación de este
bloque se hizo de forma AISLADA (compilando solo estos 2912 bytes
con `ORG $C4A0` propio) en vez de comparar el `.BIN` completo — el
contenido es 100% byte-exacto, solo su posición dentro del
`madmix1.asm` ensamblado hoy no lo es todavía.

## MILESTONE: los 7 huecos pequeños de código sin identificar (`JT_SLOT5/6/7/8/9`, 0x8431-0x8EC4) transcritos completos

Rellenados los 7 huecos `DS` restantes MÁS PEQUEÑOS de `madmix1.asm`
(el hueco grande de gráficos, 0x8F74-0xB940, sigue pendiente).
Mismo método que el driver de sonido: desensamblado por bloque con
`Z80Dasm.exe`, transcripción con script de conversión automática
(etiquetas solo en direcciones que son destino real de
`JR`/`JP`/`CALL`/`DJNZ`), y verificación byte a byte compilando
cada bloque aislado con su `ORG` real (por el mismo problema de
desplazamiento de direcciones que el driver de sonido, ver nota
correspondiente). **0 diferencias en los ~1.531 bytes reales** (el
hueco de 15 bytes en `0x8431-0x8440` no contaba como código: es
zona de variables en RAM, confirmada a cero en el `.BIN` original).

- **`0x8431-0x8440` (15 bytes)**: confirmado todo ceros — zona de
  variables en RAM ($8437/$843A/$843E/$843F, ya usadas en
  `ACTOR_ENGINE`), no relleno de fichero.
- **`0x8800-0x8931` (305 bytes)**: contenía tres cosas.
  - `INSTALL_ISR` (`JT_SLOT5`, `$881B`, identificado): instala el
    vector de interrupción. El stub inventado que existía antes en
    otra posición del fichero (con un `DI` inicial) era erróneo —
    el real NO empieza con `DI` — y se ha eliminado.
  - `ISR` (`0x882A`): tenía **3 bugs reales** en la versión
    anterior, encontrados por diferencia de bytes: (1) faltaba un
    `PUSH AF`/`POP AF` simétrico guardando el `AF` de la sombra
    justo antes/después de los `PUSH`/`POP HL,DE,BC,IX,IY`; (2)
    faltaba un bloque entero de lectura de estado del VDP
    (`IN A,($99)` + `LD A,($10E4)` + 2x `OUT`) justo antes de
    restaurar `AF` y salir; (3) la instrucción final es `RET`, NO
    `RETI` como se pensaba. De paso se **confirmó** que
    `CALL $60DC` es una dirección estática real (no una nota
    antigua que asumía reubicación, como se dudaba): la ISR llama
    de verdad ahí cada VBLANK.
  - `ISR_HOUSEKEEPING` (`0x8860`): el stub anterior era básicamente
    un `RET NZ` con un TODO; el cuerpo real llama siempre a un
    "hook" (`$8889`, ver abajo) y, si `FRAME_FLAG` confirma que ha
    pasado un frame, además llama a `$86BB` (`JTS2_RESUME`, ya
    transcrita), `$899B` (`RESET_8437`) y una rutina nueva `$8CFF`
    (dentro del siguiente hueco). Incluye también `$8889` (un
    `RET` de 1 byte, confirmado — parece un hook de desarrollo
    deshabilitado que ignora el valor de A) y `$8891`, una rutina
    grande de refresco de VDP (usa `LOOKUP_8978`/`FILVRM`/`SETVRAM`
    sobre varias zonas de VRAM) sin identificar del todo.
- **`0x89AD-0x8CB6` (777 bytes)**: `JT_SLOT8` (`SCROLL_DISPATCH`,
  `$89AD`) y `JT_SLOT9` (`$8C34`) son el **scroll por software de
  la cámara**: `SCROLL_DISPATCH` decide entre `SCROLL_UP` (nibble
  con `RLD`), `SCROLL_DOWN` (nibble con `RRD`) y `SCROLL_LR`
  (vertical/horizontal con `LDI`) según los bits bajos de la
  posición de cámara (`$2C02`); las tres usan `TILE_ADDR_CALC`
  (`$8BC9`, variante de `MAP_COORD_TO_ADDR` que además escribe un
  bit de atributo en una tabla en `$8EC7`). `JT_SLOT9` redibuja 4
  franjas verticales y, si `($2C27)` (probable contador de VIDAS)
  es distinto de cero, dibuja B iconos vía una variante NEGADA de
  `LDIRVM` leyendo sprites desde `$92C3` (muy cerca de `$92E3`, la
  tabla de actores ya confirmada).
- **`0x8CDA-0x8EC4` (490 bytes)**: los stubs anteriores de
  `TILE_TYPE_LOOKUP` y `REDRAW_STRIP` no coincidían con el código
  real (`TILE_TYPE_LOOKUP` usa base `$8EC7`, no `$8EC4`, con un
  `AND $1F` adicional; `REDRAW_STRIP` no usa "SCREEN_SHADOW" como
  destino, usa `$DE04` calculado a partir de `$2C02`). Se
  encontraron ademas:
  - Una **cola de redibujado diferido** (`QUEUE_PUSH`/
    `QUEUE_INIT_CHECK`/`QUEUE_POP_DISPATCH`): `QUEUE_PUSH` (el
    llamador todavía no localizado) apila peticiones `(C,B,A)` en
    un buffer circular en RAM (`$8D61-$8D6F`, `$FF`=vacío);
    `QUEUE_INIT_CHECK` es la rutina real detrás del misterioso
    `CALL $8CFF` de `ISR_HOUSEKEEPING`, y vacía la cola llamando a
    `REDRAW_STRIP` por cada entrada.
  - `JT_SLOT7` (`SCORE_DRAW`, `$8D70`): dibuja el marcador de
    puntuación. Calcula los dígitos por resta repetida contra una
    tabla de divisores (1000/100/10) y los dibuja vía `TEXT_BLIT`
    (que interpreta cada byte como índice de carácter en una tabla
    de fuente en `$935B`). **Hallazgo curioso**: si la puntuación
    acumulada llega a `$2710` (10000), en vez de seguir contando
    muestra el texto **"BESTIA"** — un "premio" de texto en vez de
    número —, y si `($60CA)` está activo (probable flag de modo
    demostración, coherente con las rutinas `TAIL_*` de
    `madmix_scr.asm`) muestra **" DEMO "**. Ambos textos y el
    buffer de dígitos son listas de índices terminadas en `$FF`,
    guardadas justo al lado de la tabla de divisores (`0x8DE3-
    0x8DFD`) — esta zona desincroniza el desensamblado lineal
    (los bytes `$30` del relleno de dígitos decodifican por
    casualidad como instrucciones `JR` que caen sobre etiquetas
    reales de más abajo), hay que verificarla con cuidado byte a
    byte en vez de fiarse de la salida en línea recta del
    desensamblador.
  - `JT_SLOT6` (`INPUT_READ`, `$8E3C`): lectura de teclado
    (matriz estándar de MSX, `OUT $AA`/`IN $A9`, 5 filas contra una
    tabla de máscaras en `$8E88`) y joystick (puerto del PSG,
    `OUT $A0`/`IN $A2`), decodificando los bits de dirección con el
    mismo patrón de `LOOKUP_8978`/`DIRBITS_TABLE`. Guarda el
    resultado en un byte "libre" reutilizado dentro de la propia
    tabla `TILE_TYPES` (`$8EC4`/`$8EC6`/`$8EC7`) — confirmado que
    esos bytes valen `$00` en la tabla real, consistente con ser
    reutilizados como flags. La tabla de puertos/máscaras en
    `$8E88-$8E93` (12 bytes) tuvo el mismo problema de
    desincronización del desensamblador que la zona BESTIA/DEMO —
    se resolvió re-desensamblando a partir de la siguiente
    instrucción real conocida (`$8E94`) en vez de fiarse de la
    lectura en línea recta.

Con esto, los únicos huecos que quedan en `madmix1.asm` son: el
grande de gráficos (marco de caramelo + sprites, `0x8F74-0xB940`,
~10.700 bytes), la cola final `0xD500-0xDDA1` (~2.209 bytes) y la
continuación sin transcribir de `INIT` a partir de `0x8F74`
(conocida y documentada desde antes, no parte de esta tarea).

## Descifrados offsets 8/11/18/19 del registro de nivel (offsets 9/10 ya se conocían) -- y un bug de aritmética corregido

Repaso final de los 20 bytes del registro de nivel (base `$2BF3` en
RAM de trabajo, confirmado por `LD DE,$2BF3 / LDIR` en el cargador
de nivel). Análisis puramente de código real (grep de cada dirección
`$2BFx`/`$2C0x` ya usada, sin adivinar por patrones numéricos, misma
disciplina que el resto de esta sección) sobre el código YA
transcrito al 100% en `madmix_scr.asm`.

**Bug encontrado y corregido**: una nota de una sesión anterior
etiquetó `$2BFB` como "offset 11" al documentar `R51FE_MAIN`. Es un
error de aritmética -- `$2BFB - $2BF3 = 8`, no 11. El offset 8 real
es `$2BFB`, y el offset 11 real es `$2BFE` (que además SÍ tiene su
propio significado real, distinto, ver abajo -- no estaba libre).

- **Offset 8** (`$2BFB`): confirmado por `R51FE_MAIN` -- cuenta de
  entradas de `ITEM_TABLE_POS_511C` a activar (el "tercer tipo" de
  ítem, junto a los offsets 9 y 10). Valores reales por nivel: 2-5.
- **Offset 9** (`$2BFC`): ya conocido, `ITEM_HANDLER_1` -- número de
  ítems tipo 1. Valores reales: 0-2 (encaja con las 2 entradas de
  `ITEM_TABLE_1`).
- **Offset 10** (`$2BFD`): ya conocido, `ITEM_HANDLER_2` -- número de
  ítems tipo 2. Valores reales: 0-3 (encaja con las 8 entradas de
  `ITEM_TABLE_2`).
- **Offset 11** (`$2BFE`, NUEVO): se copia a `$2C0E` desde dos
  manejadores del bucle principal, `HANDLER_311B`/`HANDLER_315D`
  (activados al pisar una loseta con un patrón de posición relativa
  concreto -- "tocar la bola/pista especial"). `$2C0E` es un
  **contador regresivo**: el bucle principal lo decrementa cada
  fotograma (`DEC (HL)` sobre `$2C0E`) y compara contra `$3C` (60
  decimal, un literal reusado -- casualmente el mismo valor que el
  comodín de loseta del offset 12, pero es una coincidencia de
  constante, no una relación real) y contra `$32` (50) en
  `R51FE_MAIN`; en ambos casos, una vez el contador baja del umbral,
  se testea el bit 0 (par/impar) -- **el patrón clásico de un
  parpadeo/blink una vez agotada la cuenta atrás**. HANDLER_311B
  también otorga 2 puntos (`LD HL,$0002 / CALL $8D70` = `SCORE_DRAW`
  de `madmix1.asm`) y dispara un efecto de sonido (`$6128`).
  Candidato fuerte: **duración (en fotogramas) del parpadeo de la
  bola/pista especial de cada nivel antes de que cambie de estado**
  -- coherente con `GHOST_HINT_HANDLER`/`ITEM_EFFECT` tipo 3
  ("pista") ya documentados. Valores reales: casi todos `0xFA`(250,
  ~5s a 50Hz), con 4 niveles distintos: nivel 7=`0xC8`(200), nivel
  10=`0x32`(50, ¡ya por debajo del umbral de 60 usado en el bucle
  principal!), nivel 11=`0xFF`(255, máximo), nivel 13=`0x50`(80).
- **Offsets 18-19** (`$2C05`/`$2C06`): **RESUELTO (sesión posterior)**
  -- ver sección dedicada más abajo, "Descifrados offsets 18-19: el
  contador de finalización de nivel". En el momento de escribir esto
  no se había encontrado ninguna referencia porque el consumidor real
  vive en `madmix1.asm` (`IML_90B7`, dentro del bucle principal), que
  todavía no estaba transcrito -- no en el hueco grande de gráficos
  como se sospechaba aquí.

## MILESTONE: el "hueco grande" empieza con la continuación real de INIT (0x8F74-0x9134), y resulta ser el BUCLE PRINCIPAL DEL JUEGO

Al empezar a atacar el hueco grande de gráficos (`0x8F74-0xB940`,
~10.700 bytes, marco de caramelo + sprites), lo primero fue
desensamblar desde el principio para comprobar si de verdad era
gráfico puro desde el primer byte. **No lo era**: los primeros 449
bytes (`0x8F74-0x9134`, terminando en un `NOP` suelto de relleno en
`0x9135`) son código real -- la continuación de `INIT` que llevaba
toda la sesión marcada como "sin transcribir a partir de aquí".
Desensamblado limpio con `Z80Dasm.exe`, transcrito completo y
**verificado 0 diferencias reales** (los 16 bytes que sí difieren
en el chequeo son el mismo problema de desplazamiento de símbolos
ya documentado por el resto del hueco sin rellenar -- confirmado
comparando que `TILE_GFX` se desplazó exactamente 449 bytes más
cerca de su dirección real tras este cambio).

**Hallazgo importante**: `INIT` nunca hace `RET`. Entra en un
bucle (`INIT_MAIN_LOOP`, `0x8FD4`) que resulta ser **el bucle
principal del juego** -- no solo inicialización. Dos saltos hacia
atrás desde este bloque nuevo apuntan a direcciones DENTRO del
`INIT` ya transcrito y verificado (`JP $8F54` y `JP $8F71`),
confirmando el patrón de "doble punto de entrada" ya visto muchas
veces en este proyecto -- añadidas las etiquetas
`INIT_RESUME_8F54`/`INIT_MAINLOOP_ENTRY_8F71` en el `INIT` existente
sin tocar ni un byte de lo ya verificado.

Todas las llamadas de este tramo son a rutinas YA CONFIRMADAS en
otros ficheros, lo que corrobora la lectura:
- `TAIL_DECODE` (`$5CD1`), `TABLE_INIT` (`$5885`),
  `JT_SLOT9_TARGET` (`$8C34`), `TAIL_CREDITS_MAIN` (`$6454`,
  reutilizado aquí para el HUD de partida, no solo para créditos),
  `WAIT_VBLANK` (`$89A0`), `INPUT_READ` (`$8E3C`),
  `LOAD_RESOURCE_SLOT_EMPTY`/`RM_C4CC` (gestor de sonido),
  `TAIL_VDP_FILL` (`$5B8C`), `TAIL_TILE_LOOKUP` (`$6484`) -- todas
  de `madmix_scr.asm`/`madmix1.asm` ya transcritas al 100%.
- `INIT_HELPER_9116`: efecto de revelado de texto carácter a
  carácter (tipo "máquina de escribir"), esperando un `WAIT_VBLANK`
  entre cada uno.
- El resto del bucle hace polling de teclado/joystick y gestiona un
  contador de nivel/vidas (`$2C27`) -- el ciclo de "espera de tecla
  para continuar" típico de estos juegos.

Termina justo donde ya estaba documentado el punto de
desincronización del desensamblado lineal (`0x9135`-`0x9300`, "sin
explorar" en `mapa_memoria.html`) -- confirma que ese límite ya
identificado en una sesión anterior era el correcto.

**Continuación (mismo hueco, 0x9136-0x92E3, 429 bytes más,
TRANSCRITO COMPLETO, 0 diferencias reales)**: justo después del
código, la zona "sin explorar" resultó ser DATOS reales, no gráfico
-- localizados siguiendo cada dirección que el bloque de código
anterior lee/escribe:
- **Mensajes de partida nunca documentados hasta ahora**: `FASE_TEXT`
  (`"FASE 00"`, con plantilla de número de nivel sustituible en
  tiempo real vía `LEVEL_NUM_TABLE`), `EXTRALIFE_TEXT`/`EXTRA_TEXT`
  (`"EN LA PROXIMA... EXTRA"` / `"EXTRA"`), `READY_TEXT`
  (`"READY?"`, el clásico aviso de inicio de nivel) y
  `GAMEOVER_TEXT` (`"ESTAS FRITO"`, mensaje de perder una vida).
- **`PTR_TABLE_91C3` (256 bytes, 64 entradas de 4 bytes)**: cada
  entrada es `[dirección de 16 bits][byte de flag][$18 constante]`.
  Las 64 direcciones tienen un paso fijo EXACTO de 144 bytes
  (`0x90`), de `$953B` a `$B8AB` -- y **caen todas dentro del hueco
  gráfico todavía sin descifrar** (`0x92E3-0xB940`). Es la pista más
  prometedora hasta ahora para trocear ese hueco en sus divisiones
  reales, en vez de adivinar un tamaño de tile fijo (que es
  exactamente por qué fallaron los 3 intentos anteriores de
  localizar los sprites). El byte de flag varía entre `0x00`/`0x04`/
  `0x06` sin patrón identificado; el `$18` final es constante en
  las 64 entradas, sin identificar su propósito.
- **`PATTERN_TAIL_92C3` (32 bytes, justo antes de la tabla de
  actores en `0x92E3`)**: 4 grupos de 8 bytes con pinta de patrón
  real de loseta 8x8 (formato MSX SCREEN 2) -- sin confirmar
  todavía si es el primer recurso señalado por `PTR_TABLE_91C3` o
  simplemente relleno.
- La pequeña tabla de 19 bytes al principio (`0x9136-0x9148`) se usa
  en un bucle de búsqueda (`IML_900F`) comparando contra
  `($9147) AND $78` -- posible tabla de posiciones de columna del
  HUD, sin confirmar el detalle exacto.

**Bug de transcripción encontrado y corregido en el proceso**: al
insertar este bloque, el comentario de cabecera y la primera línea
de datos quedaron pegados sin salto de línea entre medias -- toda
la primera fila de 16 bytes (`$08,$48,$10,...`) quedó absorbida
dentro del comentario y no llegó a compilarse (16 bytes de menos,
detectado inmediatamente porque `TILE_GFX` no coincidía con el
desplazamiento esperado). Corregido regenerando el bloque completo
por script desde los bytes reales del `.BIN`, verificado a cero
diferencias antes de insertarlo de nuevo.

## MILESTONE GRANDE: los 64 SPRITES DE PERSONAJES identificados y transcritos (0x953B-0xB93B, 9216 bytes, 0 diferencias)

Con `PTR_TABLE_91C3` como guía (64 punteros de paso fijo 144 bytes,
ver milestone anterior), se construyó `src/recursos/ptrtable_sprites.html`
para renderizar las 64 entradas como mapa de bits crudo, sin
comprometerse con ninguna hipótesis de formato de antemano. **El
usuario (jugador original del juego) identificó las 64 entradas a
simple vista.** Transcritas completas, 0 diferencias byte a byte
(verificado compilando el bloque aislado con `ORG $953B`).

### Catálogo completo (índice de la tabla → sprite)

```
 0 Comecocos vulnerable derecha, boca cerrada
 1 Comecocos vulnerable derecha, boca abierta 90º
 2 Comecocos vulnerable derecha, boca abierta 95º
 3 Comecocos vulnerable abajo, boca cerrada
 4 Comecocos vulnerable abajo, boca semi abierta
 5 Comecocos vulnerable abajo, boca más abierta
 6 Comecocos vulnerable arriba (de espaldas) -- única vista
 7 Comecocos invencible derecha, boca cerrada
 8 Comecocos invencible derecha, boca abierta 90º
 9 Comecocos invencible derecha, boca abierta 95º
10 Comecocos invencible abajo, boca cerrada
11 Comecocos invencible abajo, boca más abierta
12 Comecocos convertido en avión, hacia arriba
13 Comecocos "obra" (saca bolas) hacia la derecha
14 Comecocos "obra" (saca bolas) hacia abajo
15 Comecocos "obra" (saca bolas) hacia arriba (de espaldas)
16 Comecocos hipopótamo (pisa fantasmas) derecha, paso 1
17 Comecocos hipopótamo derecha, paso 2
18 Comecocos hipopótamo derecha, paso 3
19 Comecocos hipopótamo abajo, paso 1
20 Comecocos hipopótamo abajo, paso 2
21 Comecocos hipopótamo arriba, paso 1
22 Comecocos hipopótamo arriba, paso 2
23 Comecocos tanque a la derecha
24 Comecocos hipopótamo abajo, paso 3
25 Comecocos hipopótamo arriba, paso 3
26 Sprite con 4 círculos en el centro -- SIN IDENTIFICAR
27 Fantasma derecha, paso 1
28 Fantasma derecha, paso 2
29 Fantasma abajo, paso 1
30 Fantasma abajo, paso 2
31 Fantasma arriba (de espaldas), paso 1
32 Fantasma arriba (de espaldas), paso 2
33 Fantasma vulnerable derecha, paso 1
34 Fantasma vulnerable derecha, paso 2
35 Fantasma vulnerable abajo, paso 1
36 Fantasma vulnerable abajo, paso 2
37 Mariquita abajo
38 Mariquita arriba
39 Mariquita derecha
40 Muerte comecocos (bola pequeña), secuencia 0
41 Muerte comecocos (bola grande), secuencia 1
42 Muerte comecocos (descomposición), secuencia 2
43 Muerte comecocos (descomposición), secuencia 3
44 Muerte comecocos (descomposición), secuencia 4 -- último frame
45 "Repugnantoso" derecha, paso 1
46 "Repugnantoso" derecha, paso 2
47 "Repugnantoso" derecha, paso 3
48 "Repugnantoso" abajo, paso 1
49 "Repugnantoso" abajo, paso 2
50 "Repugnantoso" abajo, paso 3
51 "Repugnantoso" arriba, paso 1
52 "Repugnantoso" arriba, paso 2
53 "Repugnantoso" arriba, paso 3
54 "Repugnantoso" despeinado (¿hacia abajo?) -- SIN IDENTIFICAR del todo
55 400 PUNTOS (aparece donde se comió un fantasma)
56 600 PUNTOS (aparece donde se comió un fantasma)
57 Comecocos invencible abajo, boca semi abierta
58 Muerte comecocos abajo, triste, reducción 1 -- INICIO real de la secuencia
59 Muerte comecocos derecha, triste, reducción 2
60 Muerte comecocos arriba (de espaldas), reducción 3
61 Muerte comecocos izquierda, triste, reducción 4 -- sigue en el 40
62 Fantasma muerto
63 Sprite nulo (blanco o negro, todo ceros)
```

**Secuencia real de animación de muerte** (confirmada por el
usuario, NO es el orden de los índices): `58 → 59 → 60 → 61 → 40 →
41 → 42 → 43 → 44`.

### Hallazgo de jugabilidad con implicación directa en el código

Los sprites de personajes **solo existen para las vistas derecha,
abajo y arriba (de espaldas)** -- ninguno tiene sprite propio hacia
la izquierda, casi con toda seguridad para ahorrar memoria. Cuando
el juego dibuja un actor mirando a la izquierda, con toda
probabilidad usa el sprite derecho **invertido horizontalmente en
tiempo de ejecución**. Esto encaja con algo que ya teníamos
transcrito sin entender del todo: `ACTOR_ENGINE` tiene dos rutinas
de dibujado casi gemelas, `JTS2_RENDER_A` (desplazamiento a la
derecha) y `JTS2_RENDER_B` (desplazamiento a la izquierda),
seleccionadas según la posición del actor. Candidato fuerte: una de
las dos hace el volteo horizontal real (además de, o en vez del,
desplazamiento de sub-pixel ya documentado) -- pendiente de
confirmar revisando ese código con esta pista nueva.

### Lo que queda de este hueco

- `0x92E3-0x953B` (600 bytes): todavía sin identificar, justo antes
  de la tabla de sprites.
- `0xB93B-0xB940` (5 bytes): cola sin identificar justo antes de
  `TILE_GFX`.
- El mecanismo exacto de cómo se CONSUME cada bloque de 144 bytes
  (formato de píxel, cómo se determina cuál de los 8 bytes de cada
  grupo de 3 corresponde a qué fila) sigue sin descifrarse a nivel
  de código -- se identificaron visualmente, no se decodificó el
  algoritmo de lectura. `JTS2_XOR_TRANSFORM` (dentro de
  `ACTOR_ENGINE`) lee 3 bytes de la dirección apuntada por la tabla
  y aplica una rotación de bits, pero un análisis cuidadoso del
  código real muestra que solo toca los primeros 3 bytes de cada
  entrada de 144 (repetidamente, 48 veces, con auto-modificación) --
  no recorre los 144 bytes completos. El resto de la entrada
  (el patrón visual real) se consume en otro punto todavía sin
  localizar (candidato: `JTS2_RENDER_A`/`JTS2_RENDER_B`).

## RESUELTOS los 605 bytes residuales del hueco grande -- es la FUENTE DE CARACTERES, y con esto TODO `0x8400-0xD500` queda a 0 diferencias

Los dos huecos que quedaban tras encontrar los sprites --
`0x92E3-0x953B` (600 bytes) y `0xB93B-0xB940` (5 bytes) -- resultaron
ser la **fuente de caracteres** que usa `TAIL_DECODE`/`TEXT_BLIT`
para dibujar todos los textos ya transcritos (créditos, menú,
marcador, "FASE"/"READY?"/"ESTAS FRITO"). Se localizó con la fórmula
real de `TEXT_BLIT` (ya transcrita y verificada): dirección de glifo
= `$925B + código*8`.

- Códigos `$11-$1F` (control, sin usar por ningún texto real) y
  `$20` (espacio): confirmado que son cero real en el `.BIN` --
  glifo en blanco, no relleno inventado.
- A partir de `$21` (`FONT_TABLE_9363`, en `0x9363`) empiezan 59
  glifos reales de 8 bytes cada uno (signos, dígitos, letras
  mayúsculas) -- termina EXACTO donde empieza la tabla de sprites
  (`0x953B`), sin solapar ni un byte.
- El resto (`0xB93B-0xB940`, 5 bytes) es cola sin identificar,
  contenido real `$00,$FF,$FF,$FF,$FF`.

  **REVISADO otra vez (sesión posterior), sin resultado -- probablemente
  relleno sin más**: se buscó, igual que se hizo con éxito para el
  bloque de `0xD500` (que sí resultó tener un consumidor real
  escondido), cualquier referencia a esta dirección en todo el
  código ya transcrito de `madmix1.asm` y `madmix_scr.asm` (ambos al
  100%) -- ni como literal `LD HL,$B93x` ni como puntero en bytes
  crudos low/high. **No se encontró ninguna.** `ACTOR_ENGINE` indexa
  los sprites por número (0-63) sobre bloques fijos de 144 bytes, sin
  necesitar ningún marcador de "fin de tabla", y `0xB940` no es un
  límite redondo que sugiera relleno de alineación deliberado. A
  diferencia del hueco de `0xD500`, aquí no hay pista adicional que
  perseguir -- lo más probable es que sea relleno sin usar, sin
  ninguna función oculta.

**TRANSCRITO COMPLETO, 0 diferencias byte a byte.** Con esto,
`TILE_GFX` cae ahora EXACTO en su dirección real (`0xB940`) por
primera vez en toda la sesión -- ya no hay ningún desplazamiento de
símbolos desde `0x8400` hasta aquí. Verificación completa por
tramos:

```
0x8400-0x92E3: 0 diferencias (3811 bytes)
0x92E3-0xB940: 0 diferencias (9821 bytes) -- el "hueco grande" entero
0xB940-0xC4A0: 0 diferencias (2912 bytes) -- TILE_GFX
0xC4A0-0xD000: 0 diferencias (2912 bytes) -- driver de sonido
0xD000-0xD500: 0 diferencias (1280 bytes) -- MAZE_DATA
```

**Todo `madmix1.asm` desde `0x8400` hasta `0xD500` está a 0
diferencias byte a byte.** El único hueco real que queda en todo el
fichero es `0xD500-0xDDA1` (2209 bytes, la cola final) -- y el
"marco de caramelo" en sí (el gráfico del caramelo, distinto de los
sprites de personajes) sigue sin localizarse dentro de lo ya
transcrito.

## RESUELTA la cola final `0xD500-0xDDA1` -- `madmix1.asm` completo queda a 0 diferencias byte a byte

Se transcribió el último hueco `DS` de todo el fichero. Estructura
real descubierta:

- **`0xD500-0xD6B6`** (438 bytes, `TABLA_SIN_IDENTIFICAR_D500`): sin
  descifrar. Mismo estilo visual que la tabla RLE de justo debajo
  (pares con marcadores `$FF,$FF` repetidos, patrones
  `01,10,01,00`/`01,11,01,01`), pero no se encontró ningún sitio del
  código ya transcrito que cargue una dirección literal dentro de
  este rango. Transcrita byte a byte, sin descifrar.

  **DESCARTADO como cabecera del nivel oculto** (se comprobó porque
  el bloque de cuerpos/cabeceras de `MADMIX.SCR` no tiene sitio para
  una cuarta cabecera propia, ver hallazgo del nivel oculto -- esta
  era la única zona de `MADMIX1.BIN` sin identificar que quedaba
  como candidato). Renderizándola como si fuera una cuadrícula de
  losetas de 32 columnas sale un revoltijo sin ninguna estructura
  reconocible -- nada de habitaciones/pasillos, ni la fila sólida de
  "vacío" que sí tienen las 3 cabeceras reales. Además, 24 de los 438
  bytes caen fuera del rango válido de índice de loseta (0-90) y casi
  todos son pares `$FF,$FF` -- la misma marca de la tabla RLE
  contigua, no de datos de loseta cruda. Conclusión: es del mismo
  tipo de datos que `RLE_TABLE_D6B6` (máscaras/RLE), no una cabecera
  de nivel perdida.

  **RESUELTO DEL TODO (sesión posterior)**: no son máscaras ni RLE de
  gráficos -- son **10 guiones de reproducción automática para el
  modo DEMO**. La pista definitiva: `LEVELCYCLE_TABLE` (`$60D0`,
  `madmix_scr.asm`, ya transcrita) tiene una nota que decía "los
  punteros `$D5xx`/`$D6xx` caen dentro de `MADMIX1.BIN`" sin
  conectarla nunca con este hueco -- sus 4 punteros (`$D524`,
  `$D564`, `$D5D4`, `$D644`) caen TODOS dentro de este rango.
  `TAIL_LEVELCYCLE_MAIN` (`$6045`) usa cada puntero como `IX` y
  recorre pares `[(IX+0)=duración en fotogramas, (IX+1)=dirección
  simulada]`, esperando el fotograma indicado y simulando esa
  dirección (con `AND $1F`) como si fuera una pulsación real, hasta
  encontrar dirección `$FF` (fin del guión, pasa al siguiente nivel
  del ciclo `1→2→4→5→1...`).

  Recorriendo el bloque de un tirón desde `0xD500` (sin usar ningún
  puntero, solo saltando de par en par hasta cada `$FF`), los 438
  bytes se dividen **EXACTOS en 10 guiones consecutivos, sin ni un
  byte sobrante** (100+94+18+66+4+24+18+88+6+20 = 438). Solo 4 de
  esos 10 guiones están referenciados por `LEVELCYCLE_TABLE`
  (`DEMO_SCRIPT_NIVEL1/2/4/5` en `madmix1.asm`) -- y curiosamente el
  puntero del nivel 1 (`$D524`) no apunta al principio real de su
  guión, que empieza en `$D500` (los primeros 18 pares, hasta
  `$D524`, se saltan sin más). Los otros **6 guiones**
  (`DEMO_SCRIPT_SINREF_1` a `_6`) son contenido real y bien formado
  (terminan limpiamente en `$FF` como los demás) pero **sin ningún
  puntero que los referencie** -- mismo patrón de contenido
  desconectado que el nivel oculto y el hueco de `LEVEL_TABLE`
  (candidato lógico: guiones grabados para más niveles, de los que
  solo 4 se llegaron a conectar al ciclador final).

  **TRANSCRITO con las 10 etiquetas** (`DEMO_SCRIPT_NIVEL1/2/4/5` +
  `DEMO_SCRIPT_SINREF_1..6`), recompilado y verificado: cada etiqueta
  cae exacta en su dirección real (`--sym`), 0 diferencias byte a
  byte mantenidas. Corregido también un comentario obsoleto en
  `madmix_scr.asm` que decía "tabla de 6 entradas" para
  `LEVELCYCLE_TABLE` cuando el bucle real (`CP $04`) confirma que
  son 4.
- **`0xD6B6-0xDD82`** (1740 bytes, `RLE_TABLE_D6B6`): tabla RLE real,
  con **dos consumidores confirmados** que reutilizan los mismos
  bytes de dos formas distintas (economía de memoria típica de
  MSX1):
  1. `TAIL_LEVELCYCLE_HELPER2` (`madmix_scr.asm`, `$6429`) la recorre
     secuencialmente como 870 pares `(valor, repetición)`: `BC=$0366`
     iteraciones × 2 bytes = exacto 1740 bytes, terminando justo en
     `$DD82` (verificado por aritmética exacta: `$D6B6 + 2*$0366 =
     $DD82`, coincide con el inicio del código real de abajo). Cada
     par se pasa a `CALL $8931` (`LDIRVM`/`FILVRM`) para rellenar la
     tabla de patrones de VRAM al arrancar un nivel.
  2. `ADDR_FROM_DC00` (`$8988`) + `JTS2_PROCESS_ACTORS` acceden a un
     subtramo de esta misma tabla (`$DC00` en adelante) de forma
     aleatoria (offset según posición en pantalla del actor), como
     máscaras AND/OR de 16 bits para componer sprites contra el
     fondo -- esto **resuelve** la "Zona 0xDC00" que quedó como "sin
     descifrar todavía" en un hallazgo anterior de esta misma tabla:
     no es una tabla aparte, es un subtramo de `RLE_TABLE_D6B6`
     reutilizado con un segundo propósito.
- **`0xDD82-0xDD8A`** (8 bytes, `SLOT_RESTART_DD82`): código real
  (`DI` / `LD A,$55` / `OUT ($A8),A` / `JP START`), sin llamador
  conocido en el código ya transcrito -- posible punto de entrada
  externo (desde `MADMIX0.BIN` u otro mecanismo), disparador sin
  confirmar.
- **`0xDD8A-0xDD93`** (9 bytes, `PSG_WRITE_READ_DD8A`): código real,
  **con llamador confirmado** -- es el destino real de
  `CALL $DD8A` en `IR_JOYREAD`, ya presente en el fichero antes de
  esta sesión (ahora convertido a referencia simbólica). Escribe A
  al registro PSG ya seleccionado por el llamador, selecciona el
  registro 14 (Puerto de E/S A, joystick 1 en MSX) y devuelve su
  valor.
- **`0xDD93-0xDD96`** (3 bytes): cola de código huérfana sin llamador
  conocido, `POP HL` / `EI` / `RET`.
- **`0xDD96-0xDDA0`** (10 bytes): relleno sólido `$FF`.
- **`0xDDA0`** (1 byte, `$CD`): fuera de los datos reales del juego
  -- el primer byte de lo que sería la siguiente instrucción si el
  fichero continuara, pero el `.BIN` termina aquí (relleno de sector
  de disco, no parte del programa).

**TRANSCRITO COMPLETO, 0 diferencias byte a byte** (verificado
compilando el fichero entero y comparando contra el `.BIN` original
completo, contabilizando el desplazamiento de 7 bytes de la cabecera
MSX). **`madmix1.asm` queda así 100% completo, sin ningún hueco `DS`
restante, desde `0x8400` hasta `0xDDA1`.**

## RESUELTO EL MARCO DE CARAMELO -- estaba en `RLE_TABLE_D6B6`, confirmado visualmente

La pregunta abierta desde hacía muchas sesiones ("¿dónde está el
gráfico del marco de caramelo?") quedó resuelta al analizar con más
detalle la tabla RLE `0xD6B6-0xDD82` recién transcrita en la cola
final.

**La pista clave**: sumando las 870 repeticiones de todos los pares
`(valor, repetición)` de la tabla, el total da **exacto 6144 bytes
(`$1800`)** -- el tamaño COMPLETO de la tabla de patrones de VRAM en
SCREEN2. Esto encaja con lo que ya se sabía de la rutina que la
consume (`TAIL_LEVELCYCLE_HELPER2`, `$6429` en `madmix_scr.asm`):
vuelca la tabla SECUENCIALMENTE empezando en VRAM `$0000`, así que
esta tabla RLE no es un simple relleno parcial -- **reconstruye la
tabla de patrones de pantalla completa, de un tirón, antes de que se
dibuje nada más encima**.

**Verificación definitiva**: se expandió el RLE (870 pares → 6144
bytes) y se renderizó como bitmap usando la tabla de nombres
identidad de SCREEN2 (ya confirmada en un volcado de VRAM real de
una sesión anterior: byte de nombre = índice de celda, sin
indirección). El resultado es el marco de caramelo **completo y
perfectamente reconocible**: rayas diagonales rojiblancas arriba y
abajo, los remates blancos redondeados en las 4 esquinas (el mismo
motivo ya identificado antes en `border_candy_corner_TL.png`, que en
su momento se recortó de un volcado de VRAM en vivo sin saber aún de
dónde salían esos bytes en el `.BIN`), y hasta el pequeño motivo de
"brillo"/estrellas cerca de la esquina inferior izquierda --
**pixel a pixel igual** que
`src/dump_openmsx/screen_reconstructed.png` (la reconstrucción de
pantalla real de una sesión anterior). Render guardado en
`src/dump_openmsx/candy_frame_reconstructed.png`.

El centro del render sale negro (vacío) porque esa es exactamente el
área que las losetas del laberinto (`TILE_GFX`, vía `REDRAW_STRIP`)
sobrescriben después, fotograma a fotograma -- el marco sobrevive
intacto en los bordes superior/inferior porque el laberinto nunca
dibuja ahí. Esto también explica por qué la vieja hipótesis
"marco de caramelo en `~0x9600-0xB700`" (de sesiones muy anteriores,
antes de identificar los sprites de personajes) estaba equivocada:
esa zona resultó ser la fuente de caracteres y los 64 sprites, no el
marco -- el marco real vivía en la cola del fichero, disfrazado de
"tabla RLE genérica de relleno de VRAM".

**Conclusión**: el `.BIN` no contiene un "gráfico del caramelo" como
tal en formato tabla-de-tiles (como los de `TILE_GFX`) -- el diseño
completo del marco (rayas + esquinas + brillo) está codificado
directamente como una única tira RLE de la tabla de patrones de
pantalla entera, generada por diseño en vez de dibujada loseta a
loseta. Pendiente menor, no bloqueante: el color (rojo/blanco) del
marco no está en esta tabla -- la rutina pone la tabla de color
entera a un valor constante (`$01`) antes de este volcado, así que el
color real de las rayas se aplica en otro punto todavía no
localizado (candidato para si se retoma: buscar escrituras a VRAM
`$2000`+ posteriores a esta rutina).

## RESUELTO EL PROPÓSITO DE `maze_data.bin` -- es la fuente real (compartida) del cuerpo de los niveles 13 y 14

Pregunta abierta desde hacía muchas sesiones: ¿por qué existe un
laberinto completo y válido de 32×40 losetas (`maze_data.bin`,
`0xD000-0xD500`) residente en `MADMIX1.BIN`, si los 14 niveles reales
viven en `MADMIX.SCR`? Ya se sabía, de sesiones anteriores, que
`LEVEL_TABLE` referenciaba de algún modo esta zona para los niveles
13 y 14, pero sin verificar el mecanismo exacto ni si el resultado
era un laberinto real o ruido.

**El mecanismo, confirmado**: `LEVEL_LOADER` (`$5904`, en
`madmix_scr.asm`) lee el puntero de cuerpo (`campo0`, offset 0 del
registro de 20 bytes) de `LEVEL_TABLE` y lo usa **tal cual, sin
ninguna conversión de dirección**, como origen de un `LDI` que copia
`campo6*32` bytes al buffer de nivel activo. Para los niveles 0-12
ese puntero cae dentro de `0x1000-0x6500` (la copia reubicada de
`MADMIX.SCR` en RAM baja). Pero para los niveles 13 y 14, los
punteros reales de la tabla son **`0xCFA4`** y **`0xD244`** --
¡direcciones dentro del rango estático donde vive `MADMIX1.BIN`
(`0x8400-0xDDA0`), no dentro de la zona reubicada! Como en tiempo de
ejecución ambos ficheros coexisten en RAM (`MADMIX1.BIN` cargado
encima de la copia reubicada de `MADMIX.SCR`, ver la secuencia de
arranque documentada más arriba), el cargador de nivel termina
leyendo el cuerpo de estos dos niveles **directamente de la memoria
residente de `MADMIX1.BIN`**, no de datos dedicados en `MADMIX.SCR`.

- **Nivel 13** (`campo6=21`, cuerpo de 672 bytes desde `0xCFA4`): los
  primeros 92 bytes vienen de `RM_TABLE_CFA4` (la tabla de
  envolvente/percusión del driver de sonido, que termina justo en
  `0xD000`), y los 580 bytes restantes son el principio de
  `maze_data.bin`.
- **Nivel 14** (`campo6=23`, cuerpo de 736 bytes desde `0xD244`): son
  700 bytes de `maze_data.bin` (desde la mitad hasta su final en
  `0xD500`) más 36 bytes que se meten en la tabla contigua
  `TABLA_SIN_IDENTIFICAR_D500` (el hueco de 438 bytes sin descifrar
  transcrito en la cola final).

**Prueba de que esto es diseño deliberado, no coincidencia**: el
cuerpo del nivel 13 termina EXACTO en `0xCFA4+672 = 0xD244` -- que es
literalmente el puntero de cuerpo del nivel 14. Los dos registros
fueron construidos para leerse de un tirón, consecutivos, sin hueco
ni solape, de la misma franja de memoria. Esto no puede pasar por
azar.

**Verificación visual definitiva**: `src/recursos/niveles.html` ya
tenía (de una sesión anterior) los cuerpos reales de los niveles 13 y
14 extraídos con estos mismos punteros exactos. Renderizando esas
entradas con el mismo decodificador de losetas que el resto de
niveles, **ambos salen como laberintos completos, simétricos y
perfectamente jugables** -- pasillos, paredes, sin ningún rastro de
ruido o discontinuidad visual, indistinguibles en estilo del resto de
niveles reales. Coincide también con el hallazgo estadístico ya
apuntado antes: los 2 valores más frecuentes de `maze_data.bin`
(`0x2D`/`0x3F`, patrón de pasillo con bolitas) son EXACTAMENTE los
mismos que dominan los niveles normales -- confirma que
`maze_data.bin` fue diseñado a propósito para producir un laberinto
con pinta real al leerse como datos de nivel, no que sea un
subproducto casual de otra tabla.

**Conclusión**: `maze_data.bin` no es un nivel de desarrollo
descartado ni una copia perdida -- es una pieza de diseño real,
deliberadamente colocada en `MADMIX1.BIN` para servir de **fuente de
datos compartida y reutilizada** para los niveles 13 y 14, ahorrando
tener que duplicar ~1.4 KB de datos de nivel dentro de `MADMIX.SCR`.
Es un truco de ahorro de memoria típico de un motor MSX1 con recursos
muy ajustados: en vez de reservar espacio dedicado para el cuerpo de
dos niveles más, la tabla de niveles simplemente apunta a bytes que
YA están residentes en memoria por otro motivo (la cola del driver de
sonido + este bloque), aceptando que también sean legibles como
losetas válidas. De paso, esto explica en parte por qué
`TABLA_SIN_IDENTIFICAR_D500` (los 36 primeros bytes al menos) tiene
el mismo estilo visual que una tabla de datos de nivel/máscara: es
literalmente el final del cuerpo del nivel 14.

### Por qué recurrieron a este truco: `MADMIX.SCR` está lleno hasta el último byte del presupuesto de reubicación

Hipótesis del usuario, con muy buen respaldo numérico: **`MADMIX.SCR`
no podía crecer más** dentro del mecanismo de reubicación de
`MADMIX0.BIN`, y por eso no había sitio para guardar ahí el cuerpo de
dos niveles más.

`MADMIX0.BIN` (el relocador, 58 bytes) hace un `LDIR` con
`BC=$5500` -- un valor **fijo, escrito literal en el código**, no una
suposición nuestra. Copia exactamente 0x5500 (21.760) bytes desde
`0x8800` hasta `0x1000`.

Y el tamaño real de la zona de `MADMIX.SCR` que ese `LDIR` reubica
coincide EXACTO con ese límite: `0x8800 + 0x5500 = 0xDD00`, que es
precisamente donde termina la zona reubicada. El único byte que sobra
en todo el fichero (el "byte suelto" de contenido desconocido en
`0xDD00`, ver más arriba) queda FUERA de esa zona -- ni siquiera el
`LDIR` lo copia.

Es decir: el presupuesto de "todo lo que se reubica a memoria baja"
(portada, driver de música/loader, menú, créditos, y los cuerpos/
cabeceras de los 12 niveles reales + el oculto) está **lleno hasta el
último byte posible**, sin ni un solo byte de margen. Esto encaja muy
bien con la idea de que los desarrolladores se quedaron sin sitio
para los ~1,4 KB adicionales que habrían necesitado los cuerpos de
los niveles 13 y 14, y en vez de tocar la constante fija del
relocador (posiblemente limitada a su vez por cuánta RAM libre había
de verdad en esa zona baja del MSX antes de chocar con algo
reservado del sistema), optaron por el atajo más barato: apuntar esos
dos niveles a bytes que ya estaban residentes en `MADMIX1.BIN` por
otro motivo, que tiene su propio presupuesto de espacio aparte.

## CONFIRMADO EN EMULADOR: el nivel oculto (comecocos) es un laberinto real y jugable

Se probó por fin en vivo, parcheando una COPIA del `.dsk` original
(sin tocar el disco real ni el código fuente reconstruido): se buscó
el registro del nivel 1 directamente en los bytes crudos del `.dsk`
(offset `52676`, verificado antes contra los 300 bytes ya conocidos
de `LEVEL_TABLE`) y se sobrescribió su puntero de cuerpo (`campo0`)
de `0x335C` (nivel 1 real) a `0x48BC` (el nivel oculto), reutilizando
el resto de metadatos del registro 6 (que también tiene `campo6=18`
filas, igual que el oculto). Parche de 20 bytes en el sitio, mismo
tamaño de fichero, sin tocar la estructura del disco
(`build/nivel_oculto_test.dsk`).

**Resultado, confirmado por el usuario jugándolo en openMSX**: el
nivel carga y **se puede caminar con normalidad** -- confirma de
forma definitiva que `BODY_HIDDEN_48BC` es un laberinto real y
completamente jugable, no ruido ni datos rotos. Aparecieron dos
fallos, ambos explicados por los metadatos "prestados" del registro
6 (no por el laberinto en sí):
- El comecocos aparece en una posición sin sentido para esta
  geometría, justo donde también aparecen los fantasmas -- coincide
  con que la posición inicial (offsets 15-16) y el punto de
  referencia (offsets 13-14) del registro 6 son coordenadas válidas
  para SU laberinto, no para el oculto.
- La puerta de la casa de fantasmas sale duplicada/mal colocada en
  el centro de la pantalla -- la cabecera reutilizada (`0x50BC`) es
  una cabecera genérica compartida, no diseñada para la silueta de
  comecocos de este nivel en concreto.

**Conclusión**: si este nivel hubiera tenido su propio registro real
en `LEVEL_TABLE` (algo que nunca ocurrió -- ningún registro de las 15
entradas lo referencia), habría necesitado su propia cabecera y sus
propias coordenadas iniciales a medida, coherentes con su silueta de
comecocos. Sin eso, es coherente con la hipótesis de que es contenido
cortado/nunca terminado de conectar antes de publicar el juego, no un
bug de carga. Con esto, la tarea aparcada "probar el nivel oculto en
emulador" queda cerrada -- confirmación visual y jugable obtenida, sin
necesidad de perseguir más el ajuste fino de posiciones (no era el
objetivo).

### CORRECCIÓN sobre la puerta de la casa de fantasmas: NO vive en la cabecera, y el nivel oculto ya tiene la suya propia bien colocada

Hipótesis del usuario tras la prueba: ¿quizás la cabecera reutilizada
determina la posición de la casa de fantasmas, y por eso salió mal
colocada? Se comprobó buscando el patrón de la puerta (3 losetas:
`inicio_izquierdo`/`línea_eléctrica`/`inicio_derecho`, índices
`0x50,0x38,0x51` -- ver catálogo de `graficos.html`) en las 3
cabeceras conocidas y en el cuerpo de los 12 niveles reales + el
oculto.

**Resultado, tajante**: ninguna de las 3 cabeceras contiene esas
losetas -- la puerta **vive siempre en el cuerpo** de cada nivel,
como una loseta más del laberinto, en una fila distinta según el
diseño de cada uno (nivel 1: fila 9; nivel 6: fila 2; nivel 10: fila
8; etc.). Y el nivel oculto **ya tiene su propia puerta, completa y
bien colocada**, en su propio cuerpo (`body_hidden_48bc.bin`, fila 8,
columnas 23-25) -- construida por quien diseñó el nivel, igual que
cualquiera de los 12 niveles terminados.

Esto descarta que la cabecera sea la causa de la casa de fantasmas
mal colocada durante la prueba en emulador. La causa real tiene que
estar en los campos de posición que se tomaron prestados del
registro 6 (offsets 13-16: posición inicial del comecocos y punto de
referencia) -- son coordenadas numéricas del registro de
`LEVEL_TABLE`, no algo que el motor calcule buscando la loseta de la
puerta en el mapa, así que heredar los valores del nivel 6 basta para
explicar que aparecieran en un sitio sin sentido para esta geometría.
El laberinto en sí, casa de fantasmas incluida, está completo y bien
diseñado.

### OBSOLETO -- ver ronda posterior "el nivel oculto SI tiene registro real, era el registro 15 mal etiquetado"

La propuesta de abajo (construir un registro nuevo a mano) resultó
innecesaria: el registro ya existía en el binario original, solo
estaba mal clasificado como "20 bytes sin identificar". Se deja el
razonamiento original íntegro por valor histórico/metodológico.

### PENDIENTE DE RESOLVER (documentado, NO implementado): 15 huecos en la tabla para 15 laberintos distintos -- el nivel oculto encajaría como "nivel 15"

Razonamiento numérico, sin tocar nada del código ni de los datos
todavía: `LEVEL_TABLE` tiene exactamente **15 registros** (índices
0-14). Y contando cuántos laberintos REALMENTE DISTINTOS existen en
todo el juego -- los 12 cuerpos únicos de los niveles 1-12, los 2
laberintos distintos que "toman prestados" bytes de `MADMIX1.BIN`
para los niveles 13 y 14, y el nivel oculto de `0x48BC` -- salen
**exactamente 15**. El número de huecos de la tabla coincide con el
número de laberintos distintos que existen. Ahora mismo, sin embargo,
uno de esos huecos (el índice 0) está desperdiciado duplicando
exactamente el registro del nivel 1, y el nivel oculto no tiene
ningún hueco que lo referencie -- es decir, sobra un hueco y falta
uno.

**Posible solución, no implementada**: el nivel oculto encajaría de
forma natural como un **"nivel 15"** al final de la progresión (no
como sustituto del hueco 0). Para lograrlo, según lo ya confirmado en
esta sesión, haría falta:

1. **Reorganizar la tabla**: eliminar el registro 0 (duplicado inútil
   del nivel 1) y desplazar todos los registros una posición hacia
   atrás, de forma que el nivel 1 pase a ocupar el índice 0, el nivel
   2 el índice 1, ..., el nivel 14 el índice 13 -- liberando así el
   índice 14 (el último) para un registro nuevo del nivel oculto.
2. **Construir el registro del nivel oculto**: apuntar `campo0` a
   `0x48BC` (su cuerpo real, ya confirmado jugable) y `campo6` a `18`
   filas; elegir una cabecera compartida existente (las 3 disponibles
   sirven estructuralmente, la puerta de fantasmas ya vive en el
   propio cuerpo, no en la cabecera -- ver hallazgo de arriba); y
   calcular unos metadatos propios (posición inicial del comecocos,
   contadores de ítems, etc.) en vez de tomarlos prestados de otro
   nivel, como se hizo en la prueba rápida del emulador.
3. **Ajustar el código de `INIT`**: cambiar el arranque de `$2C07`
   de `LD A,1` a `LD A,0` (para que la numeración empiece en 0 en vez
   de 1, ahora que el índice 0 pasa a ser un nivel real y no un
   registro muerto).
4. **Ajustar el bucle de avance de nivel**: la comparación
   `CP $10` (16) / reseteo a `$01` en `IML_90B7` (`madmix1.asm`)
   tendría que pasar a comparar contra `15` (`$0F`) y resetear a `$00`,
   para que el ciclo completo sea `0-14` (15 niveles) en vez del
   `1-14` actual.

**Nota de honestidad**: esto son 4 cambios de código/datos
coordinados, no una simple edición de tabla -- y sigue sin resolver
del todo el detalle de si la posición de aparición de los fantasmas
depende únicamente de los campos del registro (ya identificados) o
de algún mecanismo adicional todavía no trazado en vivo (ver la
sección de la prueba en emulador más arriba). Queda como propuesta
razonada, pendiente de implementar y probar si se retoma esta línea
de trabajo -- **no se ha tocado ni un byte de `madmix1.asm`,
`madmix_scr.asm` ni de ningún dato del proyecto para escribir esta
sección.**

## CORRECCIÓN: el "buffer de nivel activo" (0xFC60) llega más lejos de lo documentado, y se identificó el resto de la RAM alta (0xF000-0xFFFF)

Revisando los tramos "sin analizar" que quedaban cerca del final de
los 64KB, usando los 6 volcados de RAM reales ya disponibles
(`src/dump_openmsx/ram*.bin`):

- **`0xF004-0xFA00`** y **`0xFA32-0xFC60`**: confirmado que son
  memoria propia del intérprete MSX-BASIC/DOS -- la primera contiene
  la tabla de nombres de dispositivo estándar (`"PRN LST NUL AUX
  CON"`), la segunda la tabla de palabras clave (`"color auto goto
  list run..."`). Prácticamente 0 diferencias entre los 6 volcados
  (estático). No son parte de ninguno de los 3 binarios
  reconstruidos -- es el hueco donde `MADMIX0.BIN` (`0xFA00-0xFA32`)
  se carga a propósito, precisamente porque esas tablas no hacen
  falta para el resto de la secuencia de arranque (ver hallazgo
  aparte sobre por qué esto no rompe BASIC).
- **CORRECCIÓN sobre `0xFC60`**: el límite documentado hasta ahora
  (`0xFC60-0xFE60`, 512 bytes) era demasiado corto. Comparando
  directamente `0xFC60` en vivo contra `header_50bc.bin` +
  `body_l01.bin` concatenados: **0 diferencias** (con el bit 7
  enmascarado, por las bolitas ya comidas) en los primeros 800 bytes
  -- confirma que el búfer real de nivel activo llega hasta
  **`0xFF80`**, no `0xFE60`. Con el nivel 1 cargado (25 filas: 3 de
  cabecera + 22 de cuerpo) usa exactamente esos 800 bytes; con el
  nivel más alto (14, 26 filas) llegaría a usar hasta 832 bytes
  (`0xFFA0`).
- **`0xFF80-0xFFE0`** (96 bytes): relleno sólido `$42` en el volcado
  analizado -- la parte del mismo búfer que el nivel 1 no necesita
  (reserva para niveles más altos).
- **`0xFFE0-0xFFFF`** (32 bytes, el final absoluto de los 64KB):
  estático en los 6 volcados, con un patrón reconocible de cola de
  pila Z80 (`FB FD E1 DD E1 D1 C9...` = `EI`/`POP IY`/`POP IX`/
  `POP DE`/`RET`, un epílogo típico). Candidato más probable: resto
  de la pila de la fase BASIC (antes de que `INIT` fije `SP=$0FFF`,
  una zona de memoria completamente distinta), congelado ahí porque
  nada vuelve a tocar esa dirección durante la partida. No es parte
  de ninguno de los 3 binarios.

Con esto, `0xF000-0xFFFF` completo queda identificado: parte es el
búfer real de nivel (ahora con su límite correcto) y el resto es
memoria de sistema BASIC/DOS o resto de pila, ninguna de las dos
cosas perteneciente al juego en sí. Corregido en
`src/recursos/mapa_memoria.html` (continuidad reverificada: 0
huecos, 58 segmentos).

## IDENTIFICADO: 0xDDA0-0xDE04 (justo después del final real de `MADMIX1.BIN`) es un manejador de interrupción del sistema, no del juego

Siguiendo con el barrido de zonas "sin analizar", se desensambló con
`Z80Dasm` el tramo `0xDDA0-0xDE03` (justo entre el byte huérfano final
de `MADMIX1.BIN` en `0xDDA0` y el inicio del búfer de fondo en
`0xDE04`) usando los volcados de RAM reales -- **100% estático en los
6 volcados**, igual que los demás hallazgos de sistema de hoy.

A partir de `0xDDA9` (los 9 bytes anteriores parecen ruido de
desincronización, patrón ya visto muchas veces en este proyecto) el
desensamblado es limpio y muy reconocible -- un **manejador de
interrupción clásico**:

```asm
PUSH IX / PUSH IY / PUSH HL / PUSH DE / PUSH BC / PUSH AF
EXX / EX AF,AF' / PUSH AF / PUSH HL
LD HL,($DDD2) / LD A,L / OR H / POP HL
LD IX,$0038                  ; vector de interrupcion del Z80
LD IY,($FCC0)
JR NZ,$DDE8
...
CALL $001C                   ; zona reservada de BIOS/DOS
...
POP AF / POP BC / POP DE / POP HL / POP IY / POP IX
EI
RET
```

Guarda absolutamente todos los registros (patrón obligatorio de
cualquier rutina que se pueda disparar en mitad de una interrupción),
comprueba un flag, y llama a direcciones fijas de muy bajo nivel
(`$0038` es el vector de interrupción de mantenimiento del Z80,
`$001C` y `$F380` caen en la zona reservada de rutinas/variables del
BIOS/DOS de MSX). `LD IY,($FCC0)` podría parecer relacionado con nuestro
búfer de nivel (`0xFC60`+, recién corregido más arriba) por pura
cercanía de dirección, pero no hay ningún indicio de relación real --
es mucho más coherente con una variable de sistema fija que
casualmente cae cerca.

**Conclusión**: con muy alta confianza, esto es código **residente
de MSX-DOS/Disk-BASIC** (un gancho de interrupción genérico, del
estilo "comprobación de CTRL-STOP" u housekeeping equivalente), no
parte de ningún de los 3 binarios del juego -- coherente con el mismo
patrón de esta sesión (contenido de sistema congelado en memoria que
sobra tras el arranque, nunca vuelto a tocar durante la partida). No
se ha identificado con precisión absoluta la rutina exacta del BIOS
(haría falta un desensamblado de referencia del ROM/DOS de MSX para
nombrarla con certeza total), pero la estructura no deja dudas
razonables sobre su naturaleza de sistema. Corregido en
`mapa_memoria.html`.

## IDENTIFICADO: 0x0000-0x04FF -- tabla de ganchos de bajo nivel de MSX, y confirmación en vivo del vector de interrupción real del juego

Completando el barrido de zonas "sin analizar" por el extremo bajo de
la memoria, usando los mismos 6 volcados de RAM (0 diferencias entre
ellos en todo el tramo):

- **`0x0000-0x0037`**: la clásica tabla de ganchos de bajo nivel de
  MSX (vectores RST + huecos de BIOS) -- mayoría a cero, con 5 `JP`
  a direcciones `$DDxx`/`$DExx` (`$DDEE`, `$DE0F`, `$DE4F`, `$DE96`,
  `$DE3D`). Esas direcciones caen TODAS dentro de la zona de sistema
  MSX-DOS/Disk-BASIC identificada antes en esta misma sesión
  (`0xDDA0-0xF004`) -- ganchos heredados del arranque, no del juego
  (y probablemente ya "muertos": sus destinos han sido sobrescritos
  por el búfer de fondo del propio juego, así que si alguna vez se
  invocaran saltarían a datos, no a código real -- pero nada los
  invoca durante la partida).
- **`0x0038`** (el vector de interrupción real del Z80, `RST 38h`):
  **`JP $882A`**. Esta es la única pieza de todo el tramo que SÍ es
  el juego -- confirma en vivo, desde un ángulo distinto, algo que
  ya teníamos transcrito y documentado: `ISR` (`0x882A`, en
  `madmix1.asm`) es la rutina de interrupción real, y
  `INSTALL_ISR` es quien escribe este `JP` aquí en caliente al
  arrancar (`LD HL,$882A` ya estaba en el código transcrito).
- **`0x003B-0x0054`** (26 bytes): una rutina completa y coherente --
  cambia la configuración de slot usando `$FFFF` como variable de
  trabajo (`OUT ($A8),A` / `LD A,($FFFF)` / ... / `RET`). Se buscó
  cualquier `CALL` a esta dirección en todo el código ya transcrito
  de `madmix1.asm` y `madmix_scr.asm` (ambos al 100%) -- **no hay
  ninguno**. Es código de sistema/BIOS, no del juego.
- **`0x0055-0x00FF`**: todo a cero.
- **`0x0100-0x04FF`** (1024 bytes): relleno sólido `$FF`, 100%
  estático en los 6 volcados. Podría confundirse con el búfer de
  actores, pero ese ya está confirmado (sesión anterior) que empieza
  justo después, en `$0500` -- este tramo es simplemente memoria
  reservada sin usar.

Con esto, `0x0000-0x04FF` queda completamente identificado: casi todo
es sistema (heredado del arranque BASIC/DOS, igual que los otros
hallazgos de esta sesión), con la única excepción real del vector de
interrupción en `$0038`, que es una confirmación en vivo adicional de
`ISR`/`INSTALL_ISR`, ya transcritos y verificados desde antes.
Corregido en `mapa_memoria.html` (continuidad reverificada: 0 huecos,
62 segmentos).

## Descifrados offsets 18-19: el contador de finalización de nivel (y el mecanismo real detrás del bug del nivel 13)

Mecanismo confirmado por código real, no por patrones numéricos --
`IML_90B7`, dentro del bucle principal en `madmix1.asm` (la parte que
faltaba transcribir cuando se escribió la nota anterior, de ahí que
no apareciera ninguna referencia):

```asm
LD HL,($2C08)     ; contador de "cosas comidas" en este nivel
LD DE,($2C05)     ; offsets 18-19 del registro, copiados aqui por el LDIR generico
AND A
SBC HL,DE
JR NZ,IML_90E4    ; si no coinciden, el nivel sigue sin terminar
LD HL,$2C07
INC (HL)          ; si coinciden, avanza al siguiente nivel
```

**Offsets 18-19 son el número total de "cosas que comer" para dar
el nivel por completado** -- se compara contra `$2C08`, un contador
de 16 bits que arranca a cero en cada nivel (`LEVEL_LOADER`,
`madmix_scr.asm`) y se incrementa en 4 sitios del motor de colisión
(`0x2CA0-0x335C`, ya transcrito): el manejador de la loseta "suelo
con bola" normal, y 3 manejadores más que comprueban bits distintos
de un byte `B` (candidato: posiciones de "bola especial" adicionales,
usando la loseta de sustitución del comodín, offset 12, como
gráfico) -- los 4 comparten el mismo patrón de "redibuja con
`DRAW_TILE_HELPER` + suma puntos + `INC ($2C08)`".

**Verificación numérica**: se extrajeron los 15 registros de
`niveles_tabla.bin` y se contaron directamente, en los 12 cuerpos de
nivel reales (`src/data/niveles/body_l*.bin`), las losetas de la
familia "suelo con bola" (`0x2D`/`0x2E`/`0x2F`, con el bit 7
enmascarado). Para 4 de los 12 niveles reales, la cuenta directa de losetas
coincide **EXACTA** con el valor de offsets 18-19 -- y de propina,
también coincide exacta para el nivel 13 (cuyo cuerpo "prestado" se
lee de `MADMIX1.BIN`, ver hallazgo de `maze_data.bin`):

| Nivel | offset 18-19 (objetivo) | bolitas contadas en el cuerpo |
| --- | --- | --- |
| 1 | 114 | 114 ✓ |
| 8 | 90 | 90 ✓ |
| 10 | 116 | 116 ✓ |
| 12 | 176 | 176 ✓ |
| 13 | 105 | 105 ✓ (cuerpo prestado de `0xCFA4`) |

Cinco coincidencias exactas de este tipo no son casualidad --
confirman sin lugar a dudas que offsets 18-19 son el recuento de
bolitas objetivo del nivel (el mecanismo clásico de "cómete todas
las bolitas para pasar de fase", como en Pac-Man).

**Nota de honestidad -- pendiente de precisión total (en su momento)**:
para los otros 8 niveles la cuenta directa de losetas NO coincidía
exacta con el objetivo (diferencias de 11 a 116). La causa más
probable eran las losetas "comodín" (`0x3C`) del cuerpo, que
`LEVEL_LOADER` sustituye de forma condicional (según una variable
externa `$2C2C`, que vale 0 en la primera vuelta completa del juego y
solo sube cuando el contador de nivel da la vuelta de 16 a 1) y los 3
manejadores adicionales de "bola especial por bits de B" recién
identificados, cuyas posiciones venían de una tabla distinta
(candidato: `ITEM_TABLE_POS_511C` o similar, ya transcrita) que no se
había cruzado todavía con este recuento. El **mecanismo en sí quedaba
totalmente confirmado y no admitía duda razonable** (código real, con
4 coincidencias exactas) -- lo que quedaba abierto era solo el detalle
fino de por qué el recuento simple no cuadraba para el resto de
niveles.

**RESUELTO del todo (sesión de la herramienta de niveles)**: el
usuario, revisando el editor visual de niveles, señaló que "las
losetas con flecha tienen bola, por lo que deben contabilizarse en las
bolas". Verificado en el código real: los 4 manejadores de flecha
(`HANDLER_2F18`/`HANDLER_2F50`/`HANDLER_2F88`/`HANDLER_2FC0`, tipos de
loseta 3-6) incrementan `($2C08)` exactamente igual que el manejador de
bolita normal (mismo patrón `CALL $8D70` con 2 puntos + `INC HL / LD
($2C08),HL`). Es decir: las losetas de flecha (`0x33`-`0x36`) SÍ dan
"bola" al pisarlas, además de forzar la dirección. Añadiéndolas al
recuento (`tools/mmlvl_tool.py`, `recursos/editor_niveles.html`):
**los 12 niveles coinciden EXACTO con su objetivo de `LEVEL_TABLE`,
sin excepción** -- no hacía falta ninguna losetas comodín ni tabla de
"bola especial" adicional para explicar el desajuste, era sencillamente
que faltaban 4 tipos de loseta en el recuento. Misterio cerrado del
todo.

**Conexión con el bug ya conocido del nivel 13 -- probada y
DESCARTADA**: se pensó que, como el cuerpo del nivel 13 se lee de
`MADMIX1.BIN` (la tabla de envolvente del sonido + `maze_data.bin`,
ver hallazgo del propósito de `maze_data.bin`), el recuento real de
bolitas en ese cuerpo "prestado" podría no coincidir con el objetivo
guardado en su registro, explicando directamente el bug histórico
("aunque te comas todas las bolitas, el nivel 13 nunca se da por
completado"). **Se comprobó de inmediato contando las bolitas reales
del cuerpo del nivel 13 (672 bytes desde `0xCFA4`) contra su objetivo
(`105`): coinciden EXACTO (105 = 105)** -- una **quinta confirmación**
del mecanismo de offsets 18-19, pero esto DESCARTA la hipótesis de
que el bug del nivel 13 sea un simple desajuste de recuento de
bolitas. La causa real del bug histórico sigue siendo, con lo que
sabemos, la más plausible de las dos: el cambio `$FC60`→`$FC50` en la
fórmula de coordenada→dirección (ver sección "LOCALIZADO... el fix
real del bug nivel 13" más arriba).

## HITO: primera prueba "de producción" -- disco generado 100% desde las fuentes, funciona perfectamente en openMSX

Prueba definitiva de que la reconstrucción es real, no solo "coincide
sobre el papel": se compilaron los 3 `.asm` (`madmix0.asm`,
`madmix1.asm`, `madmix_scr.asm`) y se escribieron sus binarios
resultantes **directamente en una copia del `.dsk` original**, en el
sitio exacto donde vive cada fichero (localizado buscando los
primeros 32 bytes de cada fichero original en el `.dsk` crudo,
confirmando además que los 3 están almacenados de forma contigua,
sin fragmentación -- `MADMIX0.BIN` en el offset `9216`, `MADMIX1.BIN`
en `10240`, `MADMIX.SCR` en `33792`).

**Verificación previa a probarlo**: el disco resultante completo
(737.280 bytes) difiere del original en exactamente **4 bytes** --
los mismos 3 de `0x28ED-0x28F0` y el byte suelto de `0x6500` ya
documentados desde hace tiempo (dentro de `MADMIX.SCR`), nada más.
Ni la estructura del disco, ni `AUTOEXEC.BAS`/`MADMIX.BAS`, ni
ningún otro fichero se tocan.

## RESUELTO: estructura completa de la versión de cinta (`.cas`) -- confirma que `MADMIX.SCR` y `MADMIX1.BIN` viven ahí también, y que la reubicación se hace de forma DISTINTA a la del disco

Investigación puramente de lectura sobre
`FISICO\Mad Mix Game (1988)(Topo Soft)(es)[RUN'CAS-']\...cas`
(50242 bytes), disparada por una duda del usuario: ¿existen
equivalentes de `MADMIX0.BIN`/`MADMIX.SCR` en la cinta?

**Estructura completa** (localizada buscando los 12 marcadores de
sincronismo `1F A6 DE BA CC 13 7D 74` del formato CAS y decodificando
cada bloque de cabecera):

| # | Nombre | Tipo | Offset en `.cas` | Tamaño |
| --- | -------- | ------ | ------------------- | -------- |
| 1 | `TOPO` | BASIC ASCII | 32 | 256 B |
| 2 | `LOGOTOPO.CM` | binario | 320 | 4264 B |
| 3 | `MADMIX` | BASIC ASCII | 4616 | 256 B |
| 4 | `LOAD.BIN` | binario, carga en `$DDA0` | 4904 | 312 B (6+306) |
| 5 | `TEST.BIN` | binario, carga en `$C350` | 5248 | 264 B (6+258) |
| 6 | *(sin nombre, sin cabecera)* | datos crudos | 5521 | 21761 B |
| 7 | *(sin nombre, sin cabecera)* | datos crudos | 27297 | 22945 B |

Los bloques 6 y 7 se compararon byte a byte contra los ficheros ya
reconstruidos: **bloque 6 = contenido real de `MADMIX.SCR`** (21761
bytes comparados, 1 sola diferencia, en el último byte) y **bloque 7
= contenido real de `MADMIX1.BIN`** (22945 bytes comparados, 1 sola
diferencia, también en el último byte). Es decir, el motor del juego
es exactamente el mismo binario en ambas ediciones.

**Secuencia de arranque real** (leyendo los listados BASIC en claro):

```basic
' TOPO (primer fichero, autoarranca la cinta)
10 COLOR 1,1,1:SCREEN 2
20 BLOAD"CAS:LOGOTOPO.CM",R      ' carga+ejecuta el logo de Topo Soft
30 RUN"CAS:                      ' nombre vacio = "ejecuta el siguiente que haya"

' MADMIX (segundo programa BASIC, cargado por el RUN de arriba)
10 COLOR 1,1,1:SCREEN 2
20 BLOAD"CAS:LOAD.BIN"           ' sin ",R": solo carga, no ejecuta
30 BLOAD"CAS:TEST.BIN"           ' idem
40 DEF USR=56736!                ' 56736 = 0xDDA0 = entrada de LOAD.BIN
50 A=USR(0)                      ' lo invoca
```

**Desensamblado completo de `LOAD.BIN` (`$DDA0`) y `TEST.BIN`
(`$C350`)** con `Z80Dasm.exe` (extraídos directamente del `.cas`,
sin ambigüedad de offset). Lo relevante:

- `TEST.BIN` es un motor de detección de RAM/slots (barrido
  clásico de MSX: prueba escritura `$20`/`$FA` en `$4000` y `$8000`
  a través de `ENASLT` (`$0024`, auto-modificado como destino del
  `CALL` en `$C3B3`), y guarda dos configuraciones de slot en
  `$E290-E293` -- el mismo patrón de "guardar/restaurar slot" que
  `RELOCATOR` usa con `$FFFD/$FFFE` en `madmix0.asm`, pero aquí para
  averiguar en qué slot físico vive la RAM (necesario al arrancar en
  frío desde cinta, sin el contexto ya establecido que da el
  disco/DOS).
- `LOAD.BIN` es el verdadero orquestador, y aquí está la respuesta
  a la pregunta del usuario:
  ```asm
  CALL $C350              ; TEST.BIN: detecta slots de RAM
  CALL $DE93 / $DE98 / $DE9D   ; aplica las 3 configuraciones de pagina
  LD IX,$1000              ; <-- direccion DESTINO final directa
  LD DE,$5500               ; <-- mismo tamano que el LDIR de RELOCATOR
  LD A,$FF : SCF
  CALL $DDCC                 ; lee de cinta IX=destino, DE=bytes
  CALL $1000                  ; ejecuta el bloque recien cargado (portada)
  LD IX,$8400                ; direccion nativa de MADMIX1.BIN
  LD DE,$59A0                  ; 22944 bytes
  LD A,$FF : SCF
  CALL $DDCC                    ; lee de cinta IX=$8400, DE=bytes
  JP $8400                       ; salta a JT_INIT -- igual que JUMP_TO_ENGINE
  ```
  `$DDCC` es la rutina genérica de lectura de cinta (bit a bit, usa
  ganchos fijos de la ROM BASIC como `$00E1`/`$C961`/`$CDD9`/`$EDD9`/
  `$69ED` empujados a pila, y parpadea el borde escribiendo en el
  puerto `$99` -- el típico parpadeo de borde de los cargadores de
  cinta comerciales). Recibe la dirección destino en `IX` y el
  número de bytes en `DE`, sin más.

**Respuesta a la pregunta ("¿se hace la misma reubicación del `.scr`
en cinta?"): NO, no se hace el mismo mecanismo, pero se llega al
mismo sitio.** En disco, `BLOAD"MADMIX.SCR"` aterriza en `$8800` (su
dirección de carga de fábrica) y hace falta un segundo paso
(`MADMIX0.BIN`/`RELOCATOR`) que copie con `LDIR` esos `0x5500` bytes
de `$8800` a `$1000` antes de poder ejecutar la portada. En cinta,
como el lector de bloques crudo (`$DDCC`) acepta la dirección destino
como parámetro libre (`IX`), el propio `LOAD.BIN` le pide que
**escriba directamente en `$1000`** -- se ahorra por completo el
aterrizaje intermedio en `$8800` y el `LDIR` posterior. Incluso el
recuento de bytes coincide exactamente con el de `RELOCATOR`
(`DE=$5500` en cinta == `BC=$5500` del `LDIR` en `madmix0.asm`), y
`CALL $1000` se ejecuta en ambos casos justo después. Incluso el
"1 byte de diferencia al final" que aparecía en las comparaciones de
los bloques 6 y 7 queda explicado: la cinta solo lee `$5500`/`$59A0`
bytes exactos (los que pide `LD DE,...`); el byte de más que hay en
el fichero `.cas` cae fuera de lo que la rutina realmente usa, así
que es indiferente que no coincida con precisión total.

**Bonus, cierra un cabo suelto de una sesión anterior**: el volcado
de RAM en vivo (arrancando desde DISCO) que identificó
`0xDDA0-0xDE04` como "código de sistema, manejador de interrupción
genérico, sin poder nombrar la rutina ROM exacta" -- **es este mismo
código**, byte a byte. Tres de los cinco ganchos `JP` encontrados
entonces en la tabla baja de memoria (`$DE96`, `$DE3D`, y por
extensión el rango) caen exactamente en el arranque de instrucciones
reales de este desensamblado (`jr $dea2` en `$DE96`, `out ($99),a` en
`$DE3D`, `xor a` en `$DE4F`). Es decir: el propio arranque en disco
también deja residente en RAM alta este motor de carga por cinta
(parte del ROM/runtime de Disk-BASIC, o vestigio heredado de una base
de código compartida entre versiones), aunque nunca lo invoque
durante la partida.

**Hipótesis de por qué -- encaja con algo ya documentado sin conectar
hasta ahora**: `MADMIX.BAS` (el cargador del disco) lleva una línea de
créditos "CRACKED BY PAU D'ACI" (ver sección "secuencia de arranque
completa desde el .BAS" más arriba) -- ya sabíamos que esta copia del
disco es una adaptación de un grupo de crack, no necesariamente la
distribución oficial de Topo Soft. El patrón encaja exactamente con lo
típico de una conversión cinta→disco hecha por terceros: en vez de
replicar la lógica de carga por bloques con dirección libre que usa la
cinta (`$DDCC`, `IX`/`DE` como parámetros), el conversor a disco optó
por el camino fácil -- un `BLOAD` normal (que aterriza donde diga la
cabecera del fichero, `$8800` para `MADMIX.SCR`) seguido de un
reubicador dedicado (`MADMIX0.BIN`) que hace exactamente el mismo
`LDIR` de `0x5500` bytes a `$1000` que la cinta consigue en un solo
paso. Es una explicación plausible y bien apoyada por la evidencia
disponible, aunque no hay forma de confirmarla al 100% sin más
contexto (fecha de publicación de cada edición, si Topo Soft tuvo
alguna vez una edición de disco "de fábrica" propia, etc.).

**Conclusión final, esta sí totalmente verificada**: independientemente
de cuál sea la "original" y cuál la adaptación, la disposición en RAM
del contenido del juego en tiempo de ejecución es **idéntica** en
ambas ediciones -- `MADMIX.SCR` termina reubicado en `$1000-$6500` y
`MADMIX1.BIN` reside en `$8400-$DDA0` tanto si se llega ahí por el
camino largo (disco: `BLOAD`+`LDIR`) como por el corto (cinta: lectura
directa a la dirección final). Todo el trabajo de reconstrucción de
fuentes (`madmix1.asm`/`madmix_scr.asm`) es válido para ambas ediciones
sin cambios.

**El usuario lo cargó en openMSX y confirmó: funciona perfectamente**
-- disco generado desde cero a partir de nuestro código fuente,
indistinguible en la práctica del original. Fichero:
`build/madmix_reconstruido.dsk`.

## Refactorización: tiles, sprites e imágenes ya no viven pinchados dentro del `.asm` -- cada uno en su propio fichero

Por mantenibilidad: los gráficos que hasta ahora estaban como bytes
`DB` literales dentro de `madmix1.asm`/`madmix_scr.asm` se extrajeron
a ficheros individuales bajo `src/data/`, cargados con `INCBIN` uno
detrás de otro en el mismo orden exacto (para que la disposición en
memoria siga siendo byte a byte idéntica). Convención de extensión:
`.til` para losetas, `.spr` para sprites, `.fnt` para fuentes, `.img`
para el resto de gráficos (portada, marco de caramelo).

- **`data/tiles/`** (91 ficheros, 32 bytes cada uno): las losetas del
  laberinto, antes en un único `tile_gfx.bin`. Nombrados con el
  índice y una descripción corta (p.ej.
  `45_suelo_con_bola_1.til`), usando el catálogo ya confirmado de
  `graficos.html`.
- **`data/sprites/`** (64 ficheros, 144 bytes cada uno): los sprites
  de personajes, antes como 64 bloques `DB` inline en `madmix1.asm`.
  Nombrados con el índice y el nombre ya establecido (p.ej.
  `27_fantasma_der_1.spr`).
- **`data/fonts/`**: `fuente_caracteres.fnt` (472 bytes,
  `FONT_TABLE_9363`, 59 glifos). A diferencia de tiles/sprites, va en
  **un único fichero para toda la fuente**, no uno por carácter --
  `TEXT_BLIT` calcula la dirección de cada glifo por fórmula
  (`base + código×8`), lo que exige un bloque contiguo, y además es
  como se editan de verdad las fuentes bitmap (el juego completo de
  caracteres a la vez, no uno a uno).
- **`data/img/`**: el resto de gráficos que no son loseta, sprite ni
  fuente -- `marco_caramelo_forma.img` (1740 bytes, `RLE_TABLE_D6B6`),
  `marco_caramelo_color.img` (768 bytes, el bloque de color de
  `LEVELCYCLE_RESOURCE_TABLE` en `madmix_scr.asm` -- la tabla de 43
  bytes de punteros `[id,puntero]` que precede a este bloque se dejó
  tal cual, inline, porque es una tabla funcional del gestor de
  recursos, no una imagen), y los 3 ficheros de la portada
  (`portada_paleta.img`, `portada_patron.img`, `portada_color.img`,
  renombrados desde `portada_table16.bin`/`portada_pattern.bin`/
  `portada_color_packed.bin` -- ya estaban externalizados, solo se
  movieron a la carpeta y extensión nuevas por consistencia).
- **`data/demos/`** (10 ficheros, extensión `.dem`, 438 bytes en
  total): los 10 guiones de reproducción automática del modo DEMO
  (ver "IDENTIFICADO... 0xD500-0xD6B6 son 10 guiones..." más arriba),
  antes como bloques `DB` inline bajo las etiquetas
  `DEMO_SCRIPT_NIVEL1/2/4/5` y `DEMO_SCRIPT_SINREF_1..6`. Datos
  numéricos (pares duración/dirección), no texto, así que se dejaron
  en formato binario puro, no ASCII. Nombrados por orden e indicando
  si están conectados a un nivel real: `01_nivel1.dem` (100B),
  `02_nivel2.dem` (94B), `03_sinref.dem` (18B), `04_nivel4.dem` (66B),
  `05_sinref.dem` (4B), `06_sinref.dem` (24B), `07_sinref.dem` (18B),
  `08_nivel5.dem` (88B), `09_sinref.dem` (6B), `10_sinref.dem` (20B).

Los blobs antiguos ya superados (`tile_gfx.bin` y los 3 `portada_*.bin`
originales) se borraron. **Verificado tras cada paso**: recompilación
completa de los 3 ficheros, 0 diferencias mantenidas en
`MADMIX0.BIN`/`MADMIX1.BIN`, y los mismos 4 bytes ya conocidos en
`MADMIX.SCR` -- la refactorización no cambió ni un bit del contenido
real, solo de dónde vive en el árbol de ficheros.

## RESUELTO (extracción): los 3 scripts de sonido ya viven en `data/sound/*.snd`

Igual que se hizo con tiles/sprites/fuentes, se separó
`RM_TABLE_C8DE` en ficheros individuales: las tablas del driver
(duración, salto de comandos, instrumento/nota -- 1261 bytes) se
quedan como `DB` inline en `madmix1.asm` (no son "contenido"
independiente), y los 3 scripts reales pasan a
`data/sound/00_script_cdcb.snd` (52 bytes), `01_script_cdff.snd` (13
bytes) y `02_script_ce0c.snd` (383 bytes), cargados con `INCBIN` bajo
las etiquetas `SOUND_SCRIPT_0_CDCB`/`SOUND_SCRIPT_1_CDFF`/
`SOUND_SCRIPT_2_CE0C`. Las referencias en `INIT` (que los instala) y
en `IML_900F` (el soniquete de inicio de nivel, `SOUND_SCRIPT_2_CE0C
+$E4/+$EB/+$F2`) se actualizaron para usar las etiquetas en vez de
direcciones sueltas. **Verificado**: recompilado `madmix1.asm`, 0
diferencias mantenidas.

**Decisión de extensión**: se usó `.snd` para los 3 por igual, NO
`.mus` para el más largo -- sigue sin confirmarse en vivo **cuál de
los 3 scripts es cuál** (índices 0/1/2 vía `LOAD_RESOURCE_SLOT_ALLOC`,
punteros `0xCDCB`/`0xCDFF`/`0xCE0C`), y el hallazgo de
`$CEF0`/`$CEF7`/`$CEFE` (el soniquete de inicio de nivel lee DENTRO
del script 2, no es un script propio) sugiere que el script más largo
podría ser un pool de fragmentos reutilizables en vez de una única
pieza musical continua -- asumir "más largo = música" sin pruebas
sería precisamente el tipo de afirmación no verificada que este
proyecto evita.

**Pista por tamaño (sin confirmar en vivo)**:
- Script 0 (`0xCDCB`, 52 bytes)
- Script 1 (`0xCDFF`, 13 bytes) -- el más corto, candidato claro a un efecto simple
- Script 2 (`0xCE0C`, 383 bytes) -- con diferencia el más largo, candidato claro a la música principal

**Catálogo de sonidos esperado, según el usuario (jugador original)** --
para cuando se retome esta línea y haya que cruzarlo contra lo que
realmente dispara cada tile-handler/evento del motor ya transcrito:

1. Música principal
2. Soniquete de inicio de nivel
3. Soniquete de fin de nivel
4. Ruido de comer bola (bolita normal)
5. Ruido de matar fantasma
6. Ruido de pisar bola (modo hipopótamo)
7. Ruido de sacar bola (modo obra/saca-bolas)
8. Soniquete de reponer bola (cuando la repone la mariquita)
9. Disparo (modo avión)
10. Sonido de pasar por loseta de dirección única
11. Sonido de habilitar trampilla

Son bastantes más de 3 "eventos" distintos para solo 3 scripts de
sonido -- lo más probable es que varios eventos compartan el mismo
script corto (reutilizado con distintos parámetros/notas vía el
"bytecode" de 15 comandos), o que algunos de estos sonidos salgan de
otro mecanismo no relacionado con `RM_TABLE_C8DE` en absoluto. Nada
de esto se ha investigado todavía -- queda aparcado hasta que se
pueda trazar en vivo qué dispara cada uno de los 3 índices.

**Pista nueva encontrada documentando `IML_900F` (madmix1.asm,
bucle principal, secuencia de arranque de nivel/"READY?")**: justo
donde se dibuja `READY_TEXT` ("READY?"), el código llama 3 veces a
`RM_C4CC` (entrada directa de `LOAD_RESOURCE_SLOT_ALLOC` que instala
un canal sin buscar hueco libre) con los punteros `$CEF0`/`$CEF7`/
`$CEFE` -- **estos 3 punteros caen DENTRO del script 2 (`$CE0C`,
383 bytes)**, separados exactamente 7 bytes entre sí (offset +0xE4
respecto a `$CE0C`), y los primeros bytes en esa zona muestran un
patrón que se repite cada 7 bytes (`85,64,8E,X,8C,0B,8B`). Esto es
un candidato muy fuerte al **"soniquete de inicio de nivel"** del
catálogo de arriba (los 3 canales del PSG arrancan a la vez, cada uno
en una fase distinta de la misma secuencia corta, justo cuando
aparece "READY?").

Esto además **matiza la pista de tamaño de arriba**: si el "script 2"
de 383 bytes contiene sub-secuencias cortas y reutilizables como esta
(en vez de ser una única pieza musical continua), no se puede asumir
sin más que sea "la música principal" solo por ser el más largo de
los 3 -- podría ser, en realidad, una tabla compartida de fragmentos
cortos (jingles/efectos) de la que distintos eventos toman su propio
punto de partida. Sin confirmar del todo, pero es la pista más
concreta hasta ahora sobre la estructura interna de ese bloque.

## PENDIENTE: descifrar `ITEM_EXTRA_TABLE` ($56F5, madmix_scr.asm) campo a campo

`ITEM_EXTRA_TABLE` (94 bytes, `madmix_scr.asm` en torno a la línea
2187) es consumida por `ITEM_TIMER_TICK` ($5782) indexada vía
`IX-1` para decidir qué loseta dibujar según `$2C0F`, en la
animación de parpadeo de los 4 "slots activos" de items. Estructura
reconocida a nivel visual pero NO descifrada campo a campo -- se
deja documentada como datos crudos hasta que se investigue más.

Se distinguen 4 bloques terminados en `$FF`, cada uno con: una tira
larga de un mismo índice de loseta repetido (p.ej. `$36`×22,
`$3E`×24 -- el "cuerpo" del item parpadeando), una cola corta de 4-7
índices distintos (`$28,$28,$29,$29,$2A,$2B[,$2C]` -- candidatos a
losetas de esquina/borde del marco de caramelo), y un tramo final de
otro índice repetido (`$38`×10, `$37`×10). Intercalado hay un tramo
de 5+24 bytes (`$0F,$8D,$0E,$0D,$0F` y luego `$03,$00,$06,$80`×6)
que no encaja en ese patrón de índices de loseta -- probablemente
parámetros de temporización/color, sin confirmar.

**Pendiente**: no se sabe si los 4 bloques corresponden 1:1 a los 4
tipos de item de `ITEM_TABLE_POS_511C`, ni qué representan
exactamente los 29 bytes intercalados. Requiere trazar en vivo
`ITEM_TIMER_TICK` para confirmar el mapeo real antes de poder
documentar el formato campo a campo (y, en su caso, valorar si
tendría sentido extraerla a un fichero propio, análogo a como se
hizo con tiles/sprites/demos).

## RESUELTO: `PATTERN_TAIL_92C3` (madmix1.asm) es el icono de vida extra del HUD, no un tile ni relleno

Quedaba marcado como "HIPÓTESIS sin confirmar" si era el primer tile
señalado por `PTR_TABLE_91C3` o simple relleno antes de la tabla de
actores. Investigado a fondo: **es el icono de "vida extra"** (un
comecocos en miniatura) que se dibuja en el HUD una vez por cada vida
restante.

**Prueba, por código real, no por hipótesis de formato**:
`JT_SLOT9_TARGET` (`madmix1.asm:1739-1754`) lee `($2C27)` (contador
de vidas) y, por cada vida, llama dos veces a `JS9_ROWFLIP` leyendo
16+16 bytes desde `HL=$92C3` -- exactamente los 32 bytes completos de
`PATTERN_TAIL_92C3` -- dibujándolos en VRAM con una variante
"negada" (`CPL` antes de cada `OUT`), en columnas desplazadas `$18`
(24 px) por cada vida adicional.

Ensamblando esos 32 bytes en el orden real en que la rutina los
escribe (2 tiles de 8x8 por banda de escritura, 2 bandas -- NO en el
orden entrelazado de 2 bytes/fila que usa nuestro formato `.til`)
sale un círculo con una muesca arriba, el icono clásico de "vida":

```
.....###.##.....
...#####.#..#...
..###..##..###..
.###.##.#######.
.###.#..#######.
#####..#########
###############.
##############.#
############..##
#######.....####
.##############.
.##############.
..############..
...##########...
.....######.....
................
```

Coherente con estar en memoria justo al lado de
`EXTRALIFE_TEXT`/`EXTRA_TEXT` ("EN LA PROXIMA... EXTRA").

**Pista descartada**: la coincidencia de que el rango de direcciones
de `PATTERN_TAIL_92C3` ($92C3-$92E3) encaje también con la fórmula
real de `TEXT_BLIT` (`$925B + código×8`) para los códigos $0D-$10 (un
subconjunto de los "24 códigos especiales" de `FONT_CHARSET_5F2C`) es
pura coincidencia de aritmética de direcciones -- no hay ningún
llamador en el código transcrito que invoque `TEXT_BLIT` con esos
códigos. La identidad real y confirmada es el icono de vida, no un
glifo de fuente.

**Verificado**: recompilado `madmix1.asm` completo tras corregir el
comentario, 0 diferencias mantenidas contra `MADMIX1.BIN`.

**Extraído a fichero**: `data/img/icono_vida.img` (32 bytes),
cargado con `INCBIN` bajo la etiqueta `PATTERN_TAIL_92C3`, siguiendo
la misma convención que el resto de `data/img/` (marco de caramelo,
portada). Verificado de nuevo tras la extracción: 0 diferencias.

## Limpieza: la mayoría de los "TODO: sin identificar" en saltos/CALL eran comentarios obsoletos, no huecos reales

El usuario preguntó si los numerosos "TODO: sin identificar" que
aparecen junto a `CALL $XXXX`/`JP $XXXX` reflejaban de verdad huecos
sin resolver. Revisados todos uno a uno (comprobando con el `--sym`
real del compilador, no de memoria) -- **la mayoría eran comentarios
obsoletos**: el destino ya tenía etiqueta y código transcrito en otra
parte del propio fichero (o en el otro `.asm`), pero el comentario en
el punto de llamada nunca se actualizó cuando esa identificación pasó.

**Confirmados como YA IDENTIFICADOS (comentario corregido)**:

| Dirección | Identidad real | Sitios de llamada corregidos |
| --- | --- | --- |
| `$881B` | `INSTALL_ISR` | `madmix1.asm` (JT_SLOT5, INIT) |
| `$8E3C` | `INPUT_READ` | `madmix1.asm` (JT_SLOT6) |
| `$8D70` | `SCORE_DRAW` | `madmix1.asm` (JT_SLOT7) |
| `$89AD` | `SCROLL_DISPATCH` | `madmix1.asm` (JT_SLOT8) |
| `$8C34` | `JT_SLOT9_TARGET` | `madmix1.asm` (JT_SLOT9) |
| `$8CEE` | `QUEUE_PUSH` (`madmix1.asm`) | `madmix_scr.asm` (2 instancias, manejadores de item) |
| `$5782` | `ITEM_TIMER_TICK` | `madmix_scr.asm` |
| `$5278` | `HELPER_5278` | `madmix_scr.asm` (2 instancias) |
| `$53A2` | `HELPER_53A2` | `madmix_scr.asm` (`ITEM_TIMER_TICK`) |
| `$511C` | `ITEM_TABLE_POS_511C` | `madmix_scr.asm` (`TABLE_INIT`) |
| `$5885` | `TABLE_INIT` | `madmix_scr.asm` (`LEVEL_LOADER`) -- el caso más flagrante: la rutina está definida 160 líneas más arriba, en el MISMO fichero, y aun así el comentario decía "sin transcribir" |
| `$5D0A` | `TAIL_JOY_READ` (`madmix_scr.asm`) | `madmix1.asm` (`INIT`) |
| `$6429` | `TAIL_LEVELCYCLE_HELPER2` (`madmix_scr.asm`) | `madmix1.asm` (`INIT`) |

**Dos casos genuinamente sin nombre propio, pero NO "código
desconocido"** -- son puntos de entrada secundarios dentro de
rutinas YA transcritas al completo, verificado con el `--sym` real:

- `$58F8` cae dentro de `TABLE_INIT` (`$5885`-`$5904`), exactamente
  entre las etiquetas `TI_2C10` y `TI_CLR2C2E` -- un segundo punto de
  entrada que se salta el reseteo de las 3 tablas de items y va
  directo a limpiar `($2C10)/($2C1A)/($2C1B)/($2C0C)` y el bloque
  `$2C2E`. Mismo patrón que `HELPER_5278`/`HELPER_53A2` (dos entradas,
  una cola compartida), solo que a este segundo punto de entrada
  todavía no se le ha puesto nombre propio.
- `$5B56` cae dentro de la rutina de disparo del intro/ciclo de demos
  (`madmix_scr.asm`, bloque `TI_CONT` sobre `$5B50`), también
  transcrita al completo -- sin punto de entrada propio nombrado.

**Verificado**: recompilados ambos ficheros tras corregir todos los
comentarios (cambio de solo texto, cero bytes), diferencias
mantenidas en 0 (`MADMIX1.BIN`) y en los mismos 4 bytes ya conocidos
(`MADMIX.SCR`).

**Corrección sobre la nota anterior**: se apuntó aquí que `$54A9`/
`$55C0` (en `madmix_scr.asm`) quedaban sin revisar por no llevar
comentario -- **error, ya estaban identificados** desde antes como
`ITEM_HANDLER_1`/`ITEM_HANDLER_2` (con etiqueta propia y código
transcrito, línea ~1833/1980), simplemente sin usar el nombre en los
3 sitios de llamada (`$54A9`/`$55C0` en las líneas ~459/461, ~900/902,
~1098/1100). No hacía falta investigarlos, solo faltaba la
verificación cruzada -- corregido aquí mismo.

## RESUELTOS: los dos casos genuinos, `$58F8` y `$5B56` -- no son código nuevo, son direcciones exactas dentro de rutinas ya transcritas

Investigados a fondo con el listado real del compilador (`--lst`,
autoridad frente a cualquier cálculo manual de bytes):

**`$58F8`** = la instrucción `LD B,$03` a mitad de `TABLE_INIT`
(`$5885`, ver más arriba), justo después del bloque `TI_2C10` (que
limpia `($2C10)/($2C1A)/($2C1B)/($2C0C)`) y justo al principio de
`TI_CLR2C2E` (que limpia las 3 entradas/6 bytes de la tabla `$2C2E`).
Es decir: `CALL $58F8` ejecuta **solo** la limpieza del bloque
`$2C2E` y `RET` -- nada más.

Identificado también su único llamador con esta forma:
`HANDLER_31B7` (`madmix_scr.asm`), entrada 15ª/16ª de
`ML_DISPATCH_TABLE` (la tabla de despacho por tipo de loseta, 20
entradas). Cruzando con `TILE_TYPES` (`madmix1.asm`) y el catálogo de
`data/tiles/`: tipo 15 = `suelo_sin_bola_1/2/3` (losetas 63/64/65) +
`muro_ladrillo_suelto` (loseta 70); tipo 16 = `loseta_solida_negra`
(loseta 66). La rama `CP $08` de ese manejador resetea un modo
especial temporal (restaura `($2C24)` desde `($2C18)`, limpia
`($2C2D)`/`($2C0D)`) y marca `$6128=$03` antes de llamar a `$58F8`.

**Pista nueva para la tarea pendiente de sonido**: la tabla `$2C2E`
es la de "posiciones activas de trampilla/pista" (confirmado por
`TRAPDOOR_FLIP_TABLE`, que la itera y marca `$6128=$04`, y
`GHOST_HINT_HANDLER` -- pista del tanque/avión -- que la consulta y
marca `$6128=$07`). Ver también los manejadores de item especial
(`$6128=$05`/`$6128=$06`). **`$6128` recibe un valor pequeño distinto
(3,4,5,6,7...) desde cada mecánica especial del juego** -- candidato
muy fuerte a ser el **índice de efecto de sonido a disparar**, justo
lo que hace falta para la tarea pendiente de separar `RM_TABLE_C8DE`
en `.mus`/`.snd` y cruzarla contra el catálogo de 11 sonidos que dio
el usuario. Sin confirmar todavía (haría falta trazar en vivo qué
lee `$6128` y cuándo), pero es la pista más concreta que ha aparecido
hasta ahora para esa tarea.

**`$5B56`** = la instrucción `CALL $CF8B` (`LOAD_RESOURCE_SLOT_EMPTY`,
ya muy conocida) a mitad de `TI_CONT`, la cola común de `TAIL_INTRO`
(el bucle de modo demo/atrapa-atención). `madmix1.asm` la llama
directamente desde `INIT_RESUME_8F54` (parte del arranque real del
juego) para reutilizar esa cola saltándose `TAIL_KEYWAIT_UP` y
`TAIL_LEVELCYCLE_HELPER2` (que no aplican al arrancar una partida
real, solo al ciclo de demos). Desde ahí ejecuta, en orden:
`LOAD_RESOURCE_SLOT_EMPTY`, `PATCH_OFF_10D8` (ver más abajo,
RESUELTO), `TAIL_VDP_CLEAR`, `TAIL_LEVELCYCLE_HELPER_ALT`, una cuenta
atrás de `$01F4` (500) y `TAIL_KEYMENU_MAIN` -- **es decir, esta
`CALL $5B56` es la que muestra el menú principal al arrancar una
partida real**, reutilizando el mismo código que también lo muestra
tras el timeout del modo demo.

**Actualizacion -- ya tienen etiqueta propia**: `$58F8` es ahora
`TI_2C2E_ENTRY` (los 2 `CALL` en `madmix_scr.asm` ya usan el nombre
simbolico) y `$5B56` es ahora `TI_5B56` (declarada en `madmix_scr.asm`;
el `CALL $5B56` en `madmix1.asm` sigue en numerico por ser
entre-ficheros, pero el comentario ya referencia el nombre real).
Verificado 0 diferencias tras el cambio.

## RESUELTO: el "segundo `CALL $1000`" de `INIT` es literalmente `PORTADA_INIT` otra vez

Cerrando también el hueco de "relación exacta entre el bloque
reubicado en `$1000` y el segundo `CALL $1000` dentro de `INIT`"
(`FLUJO_PROGRAMA.md` §7): `madmix_scr.asm` tiene la etiqueta
`PORTADA_INIT` justo al principio de la zona `PHASE $1000` (línea 63),
y su cuerpo empieza `DI / CALL VDP_WAIT_READY / LD HL,$1800 / ...` --
**exactamente** el patrón `"LD HL,$1800 + bucle de relleno de VRAM"`
que ya se había confirmado por volcado de RAM en vivo en una sesión
anterior para lo que hay realmente en `$1000` en el momento en que
`INIT` (`madmix1.asm`) ejecuta su propio `CALL $1000`. Es decir: no es
código distinto ni un romanticismo de nombres -- `INIT` invoca
literalmente la MISMA rutina `PORTADA_INIT` que `RELOCATOR`
(`madmix0.asm`) y `LOAD.BIN` (cinta, ver hallazgo del `.cas`) ya habían
ejecutado una vez justo después de la reubicación/carga inicial.

Es decir, la portada se dibuja dos veces en total durante el arranque
de una partida real: una vez por el cargador (disco: `RELOCATOR`;
cinta: `LOAD.BIN`), inmediatamente después de reubicar/cargar el
bloque en `$1000`, y una segunda vez por el propio motor de juego
(`INIT`, ya con el control totalmente en manos de `MADMIX1.BIN`) como
parte de su propia secuencia de arranque. El motivo exacto de la
redundancia (higiene defensiva tras los cambios de contexto de
BASIC/VDP entre una llamada y la otra, o solo repetir el efecto de
forma segura) no está confirmado y necesitaría trazado en vivo, pero
el QUÉ (misma rutina, mismos bytes, dos invocaciones) ya no admite
duda -- resuelto por análisis estático puro, cruzando el desensamblado
con el propio código fuente ya transcrito.

## RESUELTO: el byte automodificable `$10E4` -- no hacia falta openMSX, la respuesta estaba en la ISR ya transcrita

Este era el único hueco de los "aparcados para openMSX" que en
realidad NO necesitaba trazado en vivo -- las dos hipótesis de opcode
probadas antes (`$A2`="AND D", `$E2`="JP PO,nn") partían de la
pregunta equivocada: se asumía que `$10E4` era **código** que había
que desensamblar. Repasando la ISR real (`ISR`, `$882A`, ya transcrita
al 100% en `madmix1.asm`) para el diagrama de `INIT_MAIN_LOOP`,
aparece justo antes de salir:

```asm
IN     A,($99)
LD     A,($10E4)     ; <- AQUI
OUT    ($99),A
LD     A,$81
OUT    ($99),A
```

Es el par estándar de escritura a registro del VDP (`OUT dato` /
`OUT $80|numreg`, aquí `numreg=1`). Es decir: **`$10E4` es un DATO,
no una instrucción** -- la ISR lo lee y lo vuelve a escribir en el
registro 1 del VDP **en cada VBLANK**. `PATCH_OFF_10D8`/
`PATCH_ON_10DE` no aplican el apagado/encendido de pantalla
directamente: solo dejan preparado el valor (`$A2`/`$E2`) que la
propia ISR aplicará de verdad, frame a frame, hasta que se parchee lo
contrario. Los 8 bytes que siguen en memoria (`$10E5-$10EC`) nunca se
ejecutan ni se leen como parte de este mecanismo -- son simplemente
lo que ocupa ese hueco en el bloque reubicado (cola sin desensamblar,
irrelevante aquí).

Corregido en `madmix_scr.asm` (comentario de `PATCH_OFF_10D8`/
`PATCH_ON_10DE`) y en `madmix1.asm` (comentario en la propia
`LD A,($10E4)` de la ISR). Verificado 0 diferencias nuevas.

## RESUELTO: `TI_BREAK` es un truco oculto de VIDAS INFINITAS (autopatch en `$909A`)

Investigando el combo secreto de `TI_BREAK` (`CP $EB`/`CP C,$07`, la
tecla ESC en fila 7 de la matriz durante el ciclo de demo de
`TAIL_INTRO`) para darle sentido a `LD ($909A),A`: buscando que hay
realmente en la direccion `$909A` en el listado real
(`sjasmplus --lst`) de `madmix1.asm` aparece **en medio de una
instruccion, no como variable independiente** -- es el byte operando
literal de `SUB $01` dentro de `IML_9078` (la rutina de "vida
perdida"):

```asm
IML_9078:
    ...
    LD     HL,$2C27      ; $2C27 = vidas restantes
    LD     A,(HL)
    SUB    $01             ; <- $909A es el byte "01" de esta instruccion
    LD     (HL),A
    JP     NC,INIT_MAIN_LOOP   ; quedan vidas -> continua
    CALL   $5B8C                ; sin acarreo... GAME OVER
```

`TI_BREAK` hace `XOR A / LD ($909A),A`, es decir escribe un `$00` ahi
-- convierte `SUB $01` en **`SUB $00`** en tiempo de ejecucion. El
resultado: la resta de vidas se convierte en un no-operacion (la
cuenta de vidas nunca baja, y como `SUB $00` nunca activa el acarreo,
tampoco se puede disparar la rama de GAME OVER). El parpadeo de borde
(color `$06`, espera de 4 `HALT`, color `$01`) es sencillamente la
confirmacion visual de que el codigo se ha aceptado -- después el
flujo cae en `TI_CONT` y el juego continua con toda normalidad hasta
el menu principal, sin ningun otro efecto visible salvo el patch ya
aplicado.

**Confirmado por análisis estático puro** (lectura cruzada del
listado real de ambos ficheros), sin necesidad de trazado en vivo.
Cierra el último hueco pendiente de `FLUJO_PROGRAMA.md` §7 que no
dependía de openMSX. Corregido en `madmix_scr.asm` (comentario de
`TAIL_INTRO`/`TI_BREAK`, que antes decia erróneamente "reinicia
sonido/pantalla") y en `madmix1.asm` (comentario en el propio
`SUB $01` de `IML_9078`). Verificado 0 diferencias nuevas en ambos
ficheros.

**Verificado**: recompilados ambos ficheros tras corregir los
comentarios con esta identidad precisa, 0 diferencias mantenidas
(`MADMIX1.BIN`) y los mismos 4 bytes ya conocidos (`MADMIX.SCR`).

## RESUELTO: `$10D8`/`$10DE` (madmix_scr.asm) -- apagan/encienden la pantalla antes y después de redibujar

Ya no son direcciones bajas sin identificar. Son
`PATCH_OFF_10D8`/`PATCH_ON_10DE` (`madmix_scr.asm`, justo después de
`VDP_WAIT_READY`/`VDP_ENABLE_DISPLAY`): dos mini-rutinas de 6 bytes,
casi idénticas, que **automodifican** el byte en `$10E4` (parte de
una instrucción posterior, todavía sin desensamblar):

```
PATCH_OFF_10D8: LD A,$A2 / LD ($10E4),A / RET
PATCH_ON_10DE:  LD A,$E2 / LD ($10E4),A / RET
```

`$A2` y `$E2` son exactamente los mismos valores que
`VDP_WAIT_READY`/`VDP_ENABLE_DISPLAY` escriben en el **registro 1 del
VDP** (TMS9918): ambos activan modo 16K + interrupción, y difieren
solo en el bit 6 (`BLANK`) -- `$A2` = pantalla apagada, `$E2` =
pantalla encendida. Es decir, `PATCH_OFF_10D8`/`PATCH_ON_10DE` dejan
preparado, para una escritura diferida posterior, si esa escritura
va a apagar o encender la pantalla.

**Patrón de uso, confirmado en los 3 sitios donde se llaman**:
apagar pantalla → redibujar (créditos, menú principal, HUD) →
encender pantalla. Evita ver el proceso de redibujado (parpadeo):

- `TAIL_INTRO`: apaga → `TAIL_CREDITS_DRAW` → enciende.
- `TI_CONT`/`TI_5B65`: apaga → limpia VDP + ciclo de nivel + dibuja
  el menú principal → enciende → lee tecla.
- `TAIL_CREDITS_MAIN` / `TAIL_LEVELCYCLE_HELPER_ALT`: encienden al
  terminar de dibujar / apagan al empezar a redibujar.

**Actualización -- resuelto sin necesitar openMSX**: `$10E4` no es una
instrucción, es el DATO que la `ISR` (`$882A`, `madmix1.asm`) lee en
cada VBLANK y reescribe en el registro 1 del VDP. Ver la sección
"RESUELTO: el byte automodificable `$10E4`" más arriba para el
desglose completo.

**Verificado**: recompilados ambos ficheros, 0 diferencias mantenidas
(`MADMIX1.BIN`) y los mismos 4 bytes ya conocidos (`MADMIX.SCR`).

## Documentados los helpers internos del driver de sonido (RM_C4CC-RM_C8C9)

Cerrando la lista de las 89 candidatas a "función real" del
inventario (`recursos/flujo_programa.html`): los últimos huecos eran
todos helpers internos de `LOAD_RESOURCE_SLOT_ALLOC`/`RM_C4F9` (el
reproductor PSG). Identificados y comentados en `madmix1.asm`:

- **`RM_C88D`**: multiplicación 8×16 sin signo (`HL = A*DE`, shift
  and add clásico) — utilidad genérica usada para calcular
  desplazamientos (ranura×tamaño, etc.).
- **`RM_C8A2`**: división 16/16 sin signo (desplazar-y-restar, 16
  iteraciones).
- **`RM_C8BC`**: consulta de tabla de palabras de 16 bits
  (`HL = tabla[A]`, entradas de 2 bytes) — la misma rutina sirve
  tanto para la tabla de duración de nota (`RM_TABLE_C8DE`, 96
  palabras) como para el despacho de comandos (`RM_TABLE_C99E`, 15
  saltos): `LD HL,tabla / CALL RM_C8BC / JP (HL)` es un salto
  indexado clásico.
- **`RM_C8C9`**: vuelca los 11 bytes de sombra de registro
  (`$C9BE`-`$C9C8`) a los 11 registros reales del PSG AY-3-8910 —
  el paso final de cada tic del reproductor.
- **`RM_C82E`** (hallazgo nuevo): activa/desactiva el bit del canal
  actual en `$C9C5` según un parámetro booleano. **`$C9C5` está a
  offset +7 respecto a `$C9BE`** (la base que `RM_C8C9` vuelca a los
  puertos) -- offset 7 es exactamente el **registro 7 del AY-3-8910
  (el mezclador: habilita tono/ruido por canal)**. Es decir,
  `RM_C82E` es la rutina que enciende/apaga un canal en el
  mezclador del PSG.
- **`RM_C699`/`RM_C6B1`/`RM_C6C9`**: relatchean parámetros "objetivo"
  a "actual" de la ranura de canal (o de una tabla fija compartida en
  `$CA53` en el caso de `RM_C6C9`) al empezar una nota nueva -- el
  significado exacto de cada campo sigue sin decodificar (fuera de
  alcance, igual que el resto del "bytecode" del driver).

**Verificado**: recompilado `madmix1.asm`, 0 diferencias mantenidas.

## Documentados los 20 manejadores de `ML_DISPATCH_TABLE` -- catálogo completo tipo↔loseta↔modo, y una corrección importante

Cruzando `TILE_TYPES` (`madmix1.asm`) con el catálogo visual de
`data/tiles/*.til` se obtuvo el mapeo exacto tipo→loseta→manejador
(el índice de despacho ES el valor de tipo, sin desplazamiento,
confirmado en la llamada real que arma la tabla: `A=tipo; ADD A,A;
HL=ML_DISPATCH_TABLE; ADD A,L...`):

| Tipo | Loseta(s) | Manejador | Efecto |
| --- | --- | --- | --- |
| 0 | pared/suelo normal (0-44) + variantes decorativas sueltas | `HANDLER_2EB7` | sin efecto (default) |
| 1 | suelo_con_bola_1/2/3 | `HANDLER_2EC7` | bolita normal: +1 punto, +1 contador fin de nivel |
| 2 | suelo_con_bola_clavada_1/2/3 | `HANDLER_2EFC` | "libera" la bola fija (sin puntos) |
| 3-6 | flecha arriba/abajo/izq/der | `HANDLER_2F18`/`2F50`/`2F88`/`2FC0` | fuerza dirección, +2 puntos, +1 contador |
| 7 | pista_tanque_vertical | `HANDLER_2FF8` | modo especial `$2C2D=8` ("modo tanque") |
| 8, 9 | linea_electrica_puerta_fantasmas_a/b | `HANDLER_2EB7` | sin lógica propia (comparten el default) |
| 10 | pista_avion_recto/remate_izq/remate_der | `HANDLER_3067` | modo especial `$2C2D=9` ("modo avión") |
| 11 | item_suelo_sin_confirmar | `HANDLER_30F3` | sale de modo especial |
| 12 | item_bola_de_poder | `HANDLER_311B` | modo especial `$2C2D=1`, +2 puntos, +1 contador |
| 13 | item_hipopotamo | `HANDLER_315D` | modo especial `$2C2D=2` |
| 14 | item_herramienta | `HANDLER_318E` | modo especial `$2C2D=3` |
| 15, 16 | suelo_sin_bola_*/muro_ladrillo_suelto/loseta_solida_negra | `HANDLER_31B7` | sale de modo especial (ya documentado antes) |
| 17-19 | variantes trampilla_transicion | `ML_3252`/`ML_3299`/`ML_32E2` | animación de apertura de trampilla |

**Catálogo de "modo especial" (`$2C2D`) confirmado**: 1=bola de
poder, 2=hipopótamo, 3=herramienta, 8=tanque, 9=avión — encaja
exactamente con los sprites y el catálogo de sonidos ya conocidos
("modo hipopótamo", "modo obra/saca-bolas", "modo avión").

**CORRECCIÓN importante**: `HANDLER_3067` estaba etiquetado en una
sesión anterior como `"tipo 9": candidato a "bola de poder comida"`.
Es **incorrecto en los dos datos**: por posición en la tabla de
despacho es el manejador del **tipo 10** (no 9), y tipo 10 son las
losetas de la **pista del avión** (`pista_avion_recto`/`remate_izq`/
`remate_der`), no la bola de poder — la bola de poder real es el
**tipo 12**, manejada por `HANDLER_311B`. El bucle de 12 llamadas que
tiene `HANDLER_3067` no es "hacer vulnerables a los fantasmas": activa
`$2C2D=9` (modo avión) y recorre 12 posiciones llamando a
`SCROLL_DISPATCH`/`R51FE_MAIN`/`ITEM_HANDLER_1`/`ITEM_HANDLER_2`/
`ITEM_TIMER_TICK` (y condicionalmente `ACTOR_ENGINE`) — probable
re-sincronización del subsistema de items a lo largo de la pista al
entrar en modo avión, sin decodificar en detalle nota a nota.

**Pista adicional para la tarea de sonido**: en esta pasada aparecen
más valores de `$6128` (el "marcador de evento", candidato a índice
de sonido): `0` (bolita normal), `3` (muchos modos especiales al
activarse), `9` (transición de trampilla), `0B`=11 (bola de poder, al
final, sobrescribiendo el `3` inicial). Son bastantes valores
distintos para solo 3 scripts de sonido -- refuerza la sospecha ya
apuntada de que varios eventos comparten script con distinto punto de
entrada (ver el hallazgo de `$CEF0`/`$CEF7`/`$CEFE` más arriba).

**Verificado**: recompilado `madmix_scr.asm`, 0 diferencias nuevas
(los mismos 4 bytes ya conocidos).

## Herramientas usadas en la sesión de análisis

- `mtools` (`mdir`/`mcopy`) para extraer ficheros del `.dsk`
- `z80dasm` para desensamblado lineal (se desincroniza al cruzar
  zonas de datos — hay que verificar visualmente cada tramo)
- Python + Pillow para renderizar bloques de bytes como mapas de
  bits (16x16 con 2 bytes/fila, o 8x8 con 1 byte/fila) y
  distinguir gráficos de código/datos a ojo

## Pasada de documentación de funciones en `madmix_scr.asm` (paralela a la ya hecha en `madmix1.asm`)

A petición explícita de continuar en `madmix_scr.asm` la misma labor
de identificación/documentación de funciones que en `madmix1.asm`:

- **Barrido de las ~39 etiquetas clasificadas "función"** (target de
  algún `CALL`, ver metodología de `FLUJO_PROGRAMA.md` §0): la
  mayoría ya tenían cabecera propia de una pasada anterior. Solo 5
  carecían de ella (`HELPER_53A2`, `TAIL_VDP_CLEAR`, `TAIL_KEYWAIT_UP`,
  `TAIL_LEVELCYCLE_HELPER_ALT` resultaron ya cubiertas por el
  comentario de una etiqueta vecina -- añadido igualmente un comentario
  propio para que cada una sea autoexplicativa sin tener que mirar al
  lado) más `ITEM_RNG` (ya tenía nota inline suficiente).
- **Documentación línea a línea del preámbulo del motor de
  colisión/movimiento** (`MAIN_LOOP`, `$2CA0`-`$2E9B`, antes del
  despachador `ML_DISPATCH_TABLE`): decisión de dirección válida del
  frame (input real vs. guion de demo), lógica de "solo se permite
  girar si la posición está alineada a loseta" (máscara `E` según
  alineamiento en cada eje), `CHECK_TILE_DELTA` con su caché de tipo
  por columna, y el punto de despacho por `IX`.
- **Hallazgo nuevo**: mientras un "modo especial" está activo
  (`($2C0F)!=0` -- bola de poder, hipopótamo, etc.), el despacho
  normal por tipo de loseta queda **suspendido** (se fuerza tipo 0,
  "sin efecto") y en su lugar el propio preámbulo gestiona la cuenta
  atrás del modo: decrementa `($2C0E)`, hace parpadear el icono de HUD
  en los últimos instantes (`($9147)` para el modo 2/hipopótamo,
  selección de valor fijo para el modo 1/bola de poder), y al agotarse
  vacía el gestor de recursos y limpia `($2C0D)`/`($2C2D)`.
- Documentado también el bucle de trampillas (`ML_2DFA`-`ML_2E36`,
  3 entradas de la tabla `$2C2E`, dos sub-formatos de posición
  distinguidos por bit 0/bit 7) y `CHECK_TILE_DELTA`/
  `DRAW_TILE_HELPER` línea a línea.
- **Corregido de paso un error en `mapa_memoria.html`**: la entrada
  de `0x2CA0-0x335C` seguía diciendo "despachador de 16 entradas" y
  "manejador de tipo 9 = bola de poder" (ambos ya corregidos en su
  momento a 20 entradas / tipo 12, pero no se había propagado a este
  fichero). Corregido.
- **Alcance restante** (no cubierto en esta pasada, para continuar):
  el detalle línea a línea de los 20 `HANDLER_*` del despachador (ya
  tienen documentación de cabecera con el mapeo tipo→loseta→efecto de
  una sesión anterior, pero no todos sus saltos internos comentados
  uno a uno), y de la cadena `HELPER_5278`/`HELPER_5414`/
  `ITEM_HANDLER_1`/`ITEM_HANDLER_2` del subsistema de items
  especiales.

Verificado 0 diferencias nuevas tras cada bloque de cambios
(recompilando y comparando contra `MADMIX.SCR` original).

## Documentados línea a línea los 20 `HANDLER_*` de `ML_DISPATCH_TABLE` -- confirma el patrón de "puerta de modo especial" y corrige una comentario que llevaba la interpretación incompleta

Continuando la misma pasada, con los 20 manejadores del despachador
de tipo de loseta (ya tenían cabecera con el mapeo tipo→loseta→efecto
de una sesión anterior, pero no sus saltos internos comentados uno a
uno). Al hacerlo salió un patrón muy claro y bien confirmado (todos
los manejadores comparan la variable `A` justo al entrar, que en
**todos** los casos viene de `LD A,($2C2D) ... JP (IX)` en el
despachador de `MAIN_LOOP` -- es decir, **`A` es siempre el modo
especial actual en el momento de entrar a cualquier `HANDLER_*`**, no
un parámetro de la loseta en sí):

- **Bolita normal (`HANDLER_2EC7`) y las 4 flechas
  (`HANDLER_2F18`-`2FC0`)**: solo actúan si el modo actual es `< 2`
  (ninguno, o bola de poder) -- con hipopótamo/herramienta/tanque/
  avión activos, NO se pueden comer bolitas ni las flechas fuerzan
  dirección.
- **Bola clavada (`HANDLER_2EFC`)**: al revés que las anteriores, solo
  actúa si el modo es EXACTAMENTE 3 (herramienta) -- fuera de ese
  modo, pisar una bola clavada no hace nada. **Esto es un hallazgo
  nuevo, no estaba en el comentario anterior**: el modo "herramienta"
  sirve literalmente para liberar bolas clavadas (las convierte en
  bolitas normales, restando 3 al índice de loseta: 48→45, 49→46,
  50→47), encajando con el nombre.
- **Activación de modos por pickup (`HANDLER_311B` bola de poder,
  `HANDLER_315D` hipopótamo, `HANDLER_318E` herramienta)**: solo
  actúan si el modo actual es 0 -- los modos son mutuamente
  excluyentes, no se pueden activar dos a la vez.
- **Activación de modos por pista (`HANDLER_2FF8` tanque tipo 7,
  `HANDLER_3067` avión tipo 10)**: si no hay modo activo, lo activan
  (con un flag de "debounce" en un bit de B para no reactivarlo cada
  frame mientras se sigue sobre la pista); si el modo activo YA es el
  suyo (8 o 9 respectivamente), en vez de reactivar solo ejecutan la
  cola de refresco de items/scroll (bucle de 12 pasos a lo largo de la
  pista).
- **Salida de modo por pickup (`HANDLER_30F3`, tipo 11)**: al revés
  que las de activación, solo actúa si YA hay un modo activo --
  restaura color/flags y termina el modo en curso.
- **Salida de modo por pista (`HANDLER_31B7`, tipos 15/16)**: termina
  el modo tanque (rama `CP $08`) o el modo avión (rama `CP $09`, con
  su propio bucle de 12 pasos en sentido inverso al de activación).
- **Transiciones de trampilla (`ML_3252`/`ML_3299`/`ML_32E2`, tipos
  17-19)**: no consultan el modo especial en absoluto, solo la fase de
  movimiento -- dibujan fotogramas concretos de la animación de
  apertura/cierre.

Documentado también, de paso: la caché de tipo de loseta de
`CHECK_TILE_DELTA` se actualiza a mano en `HANDLER_2EC7` (a `$0F` =
`suelo_sin_bola`, el tipo que le corresponde a la loseta recién
"comida") en vez de invalidarse.

Verificado 0 diferencias nuevas tras cada bloque de cambios.

## Documentados `R51FE_MAIN`/`HELPER_5278` (subsistema de items especiales) -- confirma que es la IA de movimiento de un tipo de entidad, con "acercarse al objetivo o azar" como algoritmo real

Continuando la misma pasada de documentación línea a línea, esta vez
sobre `R51FE_MAIN` ($51FE, llamada desde el bucle principal) y su
helper `HELPER_5278` ($5278). Ya tenían cabecera de sesiones
anteriores, pero no el detalle interno.

**Algoritmo confirmado** (entidades de `ITEM_TABLE_POS_511C`, 8
entradas de 7 bytes: X, Y, flag propio, dirección/animación actual,
sub-X, sub-Y, fase rotativa):

1. Calcula un "punto de mira" = cámara + (16,24) mod 128, guardado en
   `$2C1F`.
2. Para cada entidad activa: `HELPER_5278` decide si está en rango
   (según alineamiento con el punto de mira, con posible inversión si
   `($2C0D)` está activo) y calcula la **dirección de acercamiento**
   deseada hacia ese punto (arriba/abajo si coincide la columna,
   izquierda/derecha si coincide la fila).
3. Prueba con `HELPER_5414` (ya documentado, "¿hay loseta libre un
   paso en esta dirección?") las 4 direcciones posibles y arma un
   bitmask de las que SÍ son transitables.
4. Si la dirección deseada es transitable, la usa (siempre si hay un
   modo especial activo, si no con un 50% de probabilidad vía
   `ITEM_RNG`); si no lo es (o toca el 50% restante), elige entre
   TODAS las transitables usando una tabla de 170 bytes (`$517E`) más
   un bit aleatorio de desempate.
5. Aplica el movimiento resultante a la posición fraccional (sub-X/
   sub-Y) de la entidad, con la velocidad de paso reducida a la mitad
   si el flag propio de la entidad o el modo especial "invertido"
   están activos.

Es decir: **es un algoritmo de IA de persecución/patrulla clásico**
("intenta ir hacia el objetivo, si no puedes o por puro azar, muévete
por cualquier camino libre"), aplicado a alguna de las familias de
entidad del juego (candidato: la tabla de 8 entradas encaja con los
fantasmas, aunque no se ha cruzado con certeza total contra los
sprites de fantasma -- `ACTOR_ENGINE` es quien los dibuja realmente
usando la dirección/animación calculada aquí).

**Quedan dos detalles sin resolver del todo**, marcados como tales en
el propio código en vez de inventados: el significado exacto de
`(IX+2)` (probado como flag binario "activo/congelado" pero sin
confirmar su semántica completa) y si el código de dirección
almacenado en `(IX+3)` tras pasar por la tabla `$517E` usa el mismo
convenio de bitmask 1/2/4/8 que el resto del subsistema o uno
secuencial propio (los dos caminos que lo escriben no se han podido
reconciliar del todo con certeza).

Verificado 0 diferencias nuevas tras cada bloque de cambios.

## Cerrado el subsistema de items especiales: `HELPER_5414`, `ITEM_HANDLER_1/2`, `GHOST_HINT_HANDLER`, `CLEAR_5773_AND_SET`, `ITEM_TIMER_TICK`, `ITEM_EFFECT`

Continuando la misma pasada de documentación línea a línea. Dos
correcciones propias detectadas y arregladas en el camino (ver
"Errores encontrados" al final), y varios hallazgos nuevos:

- **`HELPER_5414` confirma el convenio de direcciones real** del
  subsistema de items: `$01`/`$02`/`$04`/`$08` = derecha/izquierda/
  abajo/arriba (verificado directamente por sus operaciones `C+=4`/
  `DEC C`/`B+=4`/`DEC B` sobre la posición). **Esto obligó a corregir
  un comentario que yo mismo había escrito mal en `HELPER_5278`**
  (había reusado por error el convenio de bit-índice de las flechas
  del despachador, que es un convenio DISTINTO y no relacionado).
  También confirma que los tipos de loseta 0 (pared/suelo normal), 7
  (pista tanque), 8 (línea eléctrica puerta fantasmas) y 10 (pista
  avión) son intransitables para estos items -- cualquier otro tipo sí
  lo es.
- **Hallazgo grande: `ITEM_HANDLER_1` e `ITEM_HANDLER_2` son un par
  complementario que gestiona el ciclo de vida de las bolas
  "clavadas"**:
  - `ITEM_HANDLER_1` busca huecos de bolita ya comida
    (`suelo_sin_bola`, índices 63-65) y los **regenera** de vuelta a
    bolita normal (`suelo_con_bola`, 45-47) -- decrementando el
    contador de fin de nivel (`$2C08`) porque ahora vuelve a haber una
    bolita pendiente.
  - `ITEM_HANDLER_2` busca bolitas normales SIN comer (45-47) y las
    **convierte en bolas clavadas** (48-50) -- sin tocar `$2C08`
    (plantar una clavada no cambia cuántas quedan por comer, solo las
    "congela" hasta liberarlas con el modo herramienta,
    `HANDLER_2EFC`).
  - Ambos usan el mismo mecanismo de "item plantado" vía `HELPER_5278`
    (posicionamiento) + `ACTOR_ENGINE` (dibujado) + `(IX+2)` (deja de
    recalcular dirección una vez colocado).
- **`GHOST_HINT_HANDLER`**: vigila la proximidad del comecocos a las
  posiciones activas de pista/trampilla (`$2C2E`, mismo formato que el
  bucle de trampillas de `MAIN_LOOP`) con un margen asimétrico más
  amplio que la propia loseta -- un "aviso" antes de pisarla de
  verdad, que arma `CLEAR_5773_AND_SET` y marca evento `$6128=7`.
- **`ITEM_EFFECT`**: despacha por el modo especial actual (`$2C2D`);
  el modo 3 (herramienta) reutiliza literalmente el mismo camino de
  código que "sin modo especial" (`IE_57FD`), distinguiéndose solo por
  los parámetros de sonido/temporizador elegidos.

**Errores propios encontrados y corregidos en el camino** (ambos
detectados por la disciplina de recompilar+comparar tras cada bloque,
no antes de tocar el binario):
1. Un comentario en `HELPER_5278` que asignaba mal qué valor
   (`$01`/`$02`/`$04`/`$08`) corresponde a qué dirección física --
   corregido tras verificar el convenio real en `HELPER_5414`.
2. **Al añadir un comentario en `HELPER_5414` se borró por accidente
   una instrucción real (`AND A`)** en `H5414_545A` -- detectado en la
   siguiente recompilación (0 diferencias esperado, salió con
   diferencias) y corregido de inmediato añadiendo la instrucción de
   vuelta.

Verificado 0 diferencias nuevas tras cada bloque de cambios (los
mismos 4 bytes ya conocidos en todo momento).

## RESUELTO: `$6128` es el índice de efecto de sonido -- separado el bloque de 383 bytes en 14 ficheros individuales, uno por evento

Retomando la tarea de sonido pendiente desde hace varias sesiones.
Buscando quién llama a la entrada de "tick" del reproductor PSG
(`$C4EB`, justo antes de `RM_C4F9` en `madmix1.asm`, sin etiqueta
propia hasta ahora) apareció la pieza que faltaba:

**`TAIL_LEVELCYCLE_HELPER`** (`$60DC`, `madmix_scr.asm`) -- confirmado
por el propio comentario de la `ISR` (`CALL $60DC`, ejecutado en
**cada VBLANK**) -- hace exactamente esto:

```asm
LD HL, $6128
LD A, (HL)
CP $FF
JR Z, TLH_END              ; $FF = "nada pendiente"
LD (HL), $FF                 ; marca como consumido
LD HL, LEVELCYCLE_RESOURCE_TABLE
... (indexa por A*3) ...
LD A, (HL) / LD E,(HL+1) / LD D,(HL+2)   ; [canal, puntero_lo, puntero_hi]
CALL $C4A0                     ; LOAD_RESOURCE_SLOT_ALLOC: instala el script
TLH_END:
CALL $C4EB                       ; tick del reproductor PSG (SIEMPRE, cada VBLANK)
```

Es decir: **`$6128` es exactamente el "índice de efecto de sonido a
disparar"** que se sospechaba desde hace tiempo -- cualquier parte del
juego que quiera reproducir un sonido escribe su índice en `$6128`, y
en el siguiente VBLANK esta rutina lo recoge, lo busca en
`LEVELCYCLE_RESOURCE_TABLE` (`$60FE`, 14 entradas de 3 bytes) e
instala el script correspondiente en un canal del PSG.

**La tabla completa** (`LEVELCYCLE_RESOURCE_TABLE`, `madmix_scr.asm`):

| índice `$6128` | canal | puntero | disparado desde | bytes | candidato catálogo (usuario) |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | `$CEE2` | `HANDLER_2EC7` (comer bolita normal) | 14 | #4 "ruido de comer bola" |
| 1 | 0 | `$CE8B` | `HANDLER_2EFC` (liberar bola clavada, modo herramienta) | 17 | #7 "ruido de sacar bola" |
| 2 | 0 | `$CF62` | 4× `HANDLER_2Fxx` (flechas) | 14 | #10 "loseta de dirección única" |
| 3 | 1 | `$CF70` | activar/salir modo especial (tanque/avión/herramienta/hipopótamo) | 27 | genérico "cambio de modo" |
| 4 | 0 | `$CE72` | `TRAPDOOR_FLIP_TABLE` | 12 | #9 "Disparo (modo avión)" -- **corregido**, ver más abajo |
| 5 | 1 | `$CF44` | `ITEM_HANDLER_1` (repone bolita comida) | 30 | #8 "reponer bola (mariquita)" |
| 6 | 1 | `$CEAC` | `ITEM_HANDLER_2` (planta bola clavada) | 54 | sin match directo en el catálogo |
| 7 | 1 | `$CE7E` | `GHOST_HINT_HANDLER` (aviso pista) + colas de `ITEM_EFFECT` | 13 | candidato #9/#5 (ambiguo, dos usos) |
| 8 | 0 | `$CF07` | `ITEM_EFFECT` (arma temporizador de modo especial) | 32 | genérico "activar modo" |
| 9 | 0 | `$CE5A` | `ML_3252`/`ML_3299` (transición trampilla) | 24 | relacionado con #11 |
| 10 (`$0A`) | 2 | `$CEF0` | **`IML_900F`** (llamada directa, no vía `$6128`) | 23 | #2 "soniquete de inicio de nivel" |
| 11 (`$0B`) | 2 | `$CE9C` | `HANDLER_311B` (bola de poder, evento final) | 16 | relacionado con #1/#9 |
| 12 (`$0C`) | 0 | `$CDCB` | sin sitio de escritura encontrado (reutiliza el script de música) | -- | #1 "música principal" |
| 13 (`$0D`) | 2 | `$CF27` | `ITEM_EFFECT` (evento final tras consumir modo especial) | 29 | genérico "fin de modo" |

**Hallazgo clave**: lo que llevábamos sesiones tratando como "un solo
script de música de 383 bytes en `$CE0C`" resulta ser: los primeros
78 bytes (`$CE0C`-`$CE5A`) SÍ son el canal 2 de la música de arranque
(instalada junto a `$CDCB`/`$CDFF` por `INIT`), pero el resto son
**13 fragmentos cortos independientes**, cada uno el efecto de sonido
de un evento de juego concreto -- confirmado cruzando la tabla real
contra cada sitio del código que escribe `($6128)` (búsqueda
exhaustiva de `LD ($6128),A` en ambos ficheros). El candidato de
"pool de fragmentos reutilizables" que ya se apuntaba en una sesión
anterior (al encontrar que `$CEF0`/`$CEF7`/`$CEFE` caían dentro del
"script 2") queda así confirmado del todo.

**Cruce con el catálogo de 11 sonidos del usuario**: varios encajan
con alta confianza -- `$6128=0` (comer bolita) con "#4 ruido de comer
bola"; `$6128=5`
(`ITEM_HANDLER_1`) con "#8 reponer bola (mariquita)" -- confirmado
además cruzando el frame de animación del item (`$27`=39 decimal=
sprite `39_mariquita_der`); `$6128=10`/`IML_900F` con "#2 soniquete de
inicio de nivel" (se dispara literalmente cuando aparece "READY?").
Otros (`6`, `7`, `8`, `13`) no tienen un match directo y claro en la
lista de 11 -- quedan marcados como "genérico"/candidato débil en vez
de forzar una etiqueta, honrando el principio de no sobreclamar.

**Corrección posterior (sesión de escucha real): `$6128=4` NO es
"habilitar trampilla", es "Disparo (modo avión)" (#9)**. La primera
hipótesis se apoyaba solo en el nombre de `TRAPDOOR_FLIP_TABLE` y en
que escribe en la tabla de trampillas. Al escuchar
`04_evt04_trampilla_ce72.wav` (renderizado por `mmsnd_render.py`), el
usuario -- jugador original del juego -- identificó por oído que es
"el sonido del disparo", no de trampilla. Verificado en el código:
`TRAPDOOR_FLIP_TABLE` se llama tanto desde el camino de
tanque/trampilla como desde `HANDLER_3067` (el manejador del modo
avión) -- es decir, es una rutina genérica de "voltear un marcador de
posición en `$2C2E`" reutilizada por ambos mecanismos, no exclusiva de
las trampillas. Ficheros renombrados a
`04_evt04_disparo_avion_ce72.snd`/`.txt`; actualizado el label/INCBIN
en `madmix1.asm` y el manifiesto `SCRIPT_ADDR` de `mmsnd_render.py`.
Recompilado y verificado: 0 diffs nuevos contra `MADMIX1.BIN`.

**Trabajo realizado** (a petición explícita del usuario: "solo
separar en ficheros .snd, sin descifrar el bytecode" -- no se ha
intentado decodificar el lenguaje de 15 comandos ni las tablas de
instrumento, ver más abajo):

- Extraídos los 14 segmentos a ficheros individuales en
  `data/sound/02_boot_ch2_ce0c.snd` hasta `15_evt03_modo_especial_cf70.snd`,
  nombrados por dirección + índice de evento + candidato de catálogo
  donde el cruce es sólido (eliminado el antiguo `02_script_ce0c.snd`
  monolítico).
- `madmix1.asm`: la etiqueta única `SOUND_SCRIPT_2_CE0C` se sustituyó
  por 14 etiquetas (`SOUND_BOOT_CH2_CE0C` + `SOUND_EVT00_CEE2` ...
  `SOUND_EVT13_CF27`), cada una con su propio `INCBIN`. Actualizadas
  las 3 llamadas de `IML_900F` (usaban `SOUND_SCRIPT_2_CE0C+$E4/+$EB/+$F2`)
  para usar `SOUND_EVT10_CEF0`/`+7`/`+14` directamente, y la instalación
  de arranque en `INIT` para usar `SOUND_BOOT_CH2_CE0C`.
- Verificado: recompilado, **0 diferencias** contra `MADMIX1.BIN`
  original (cambio puramente de organización del fuente, ningún byte
  compilado distinto).

**Fuera de alcance de esta pasada, explícitamente pendiente**: el
lenguaje de bytecode en sí (15 comandos vía tabla de salto en `$C99E`,
más una segunda tabla de ~20 punteros a "programas de instrumento/
envolvente" que usan el mismo lenguaje, en `$CA76`-`$CDAB` aprox.) no
se ha decodificado -- cada fichero `.snd` sigue siendo bytes crudos,
no editables como texto todavía. No existe una herramienta de la
época que entienda este formato (es un driver propio de Topo Soft,
"MUSIC-A BY: COMILONAS", no un formato público conocido) -- si se
retoma esta línea, la vía realista es decodificar el bytecode
completo y construir un compilador/descompilador propio a un formato
de texto plano.

## RESUELTO: los 15 comandos del bytecode del driver de sonido, descifrados uno a uno

A petición explícita del usuario ("vamos con ello"), se retomó la
parte que había quedado fuera de alcance. Desensamblado manual,
instrucción a instrucción, de las 15 rutinas de la tabla de salto
`$C99E` -- cada dirección de destino se verificó calculando el
desplazamiento exacto en bytes desde la rutina/etiqueta conocida más
cercana (sin asumir nada), confirmando que cada bloque termina
exactamente donde debía empezar el siguiente según la propia tabla de
punteros. Los 15 encajan sin ningún hueco ni solapamiento.

### El bucle de reproducción, por tick

`RM_PLAYER_TICK_C4EB` (llamado cada VBLANK) recorre las 3 ranuras de
canal. Para cada una, lo primero que comprueba es **`(IX+$04)/(IX+$05)`
-- el contador de tics restantes de la nota actual**:

- Si es **distinto de cero**: la nota sigue sonando -- solo decrementa
  el contador (`RM_C564`) y aplica las envolventes de volumen/tono
  (ver más abajo), sin tocar el script.
- Si es **cero**: la nota anterior terminó -- reactiva el canal en el
  mezclador (`RM_C82E` con `A=0`), recupera el puntero de lectura
  actual (`(IX+$02)/(IX+$03)`) y entra en `RM_518`: un **bucle que
  procesa bytes de comando (`>=$80`) uno tras otro, todos en el MISMO
  tick**, hasta encontrar un byte `<$80`, que lo saca del bucle.

Es decir: los comandos son "instantáneos" (se ejecutan todos de golpe
al principio de una nota).

**CORRECCIÓN IMPORTANTE (encontrada al construir el renderizador de
audio, ver más abajo) -- el byte `<$80` NO es una duración, es la
NOTA**: `RM_C527` lo suma a un valor de transposición por canal
(`$CA67`+canal, vía `RM_C882`) y usa esa suma como índice en la tabla
de 96 palabras `$C8DE` -- y esa tabla, mirada con este nuevo
contexto, contiene exactamente la progresión de valores que cabría
esperar de un **periodo de tono del PSG** (decreciente y cada vez más
plano según sube la "nota", el patrón clásico de una escala
cromática). El resultado se guarda en `(IX+$0A/$0B)` -- es decir,
`$C8DE` es una **tabla de nota→periodo de tono**, no de duración. La
duración real en tics vive en otro sitio (`(IX+$06/$07)`, fijada por
los comandos 3/6) y se recarga en `(IX+$04/$05)` cada vez que se
procesa una nota nueva (`RM_C552`). Esto obliga a corregir también el
nombre del comando 0 (ver tabla) y el contenido de `(IX+$09)`/`(IX+$2A)`.

### Estructura del registro de canal (offsets dentro de los 46 bytes de ranura)

| Offset | Contenido |
| --- | --- |
| `+$00/+$01` | Puntero de script ORIGINAL (para el comando de bucle) |
| `+$02/+$03` | Puntero de script de LECTURA actual |
| `+$04/+$05` | Contador de tics restantes de la nota en curso |
| `+$06/+$07` | Duración en tics (fijada por los comandos 3/6, copiada a `+$04/+$05` al procesar cada nota nueva) |
| `+$08` | Máscara de mezclador (tono/ruido) para `RM_C82E` |
| `+$09` | Volumen base (comando 0) |
| `+$0A/+$0B` | Periodo de tono BASE ya resuelto (nota + transposición de canal, vía tabla `$C8DE`) |
| `+$2A` | Acumulador de ENVOLVENTE DE VOLUMEN (se suma al volumen base al escribir el registro de volumen del PSG) |
| `+$2B/+$2C` | Acumulador de ENVOLVENTE/DESLIZAMIENTO DE TONO (16 bits, se suma al periodo base al escribir el registro de tono) |
| `+$2D` | Flags varios (bits probados por `RM_C5A7`/`RM_C612` para decidir si "relatch" un canal compañero) |

### Los 15 comandos (byte de comando = `$80` + número)

| # | Byte | Dirección | Parámetros | Efecto mecánico | Nombre propuesto |
| --- | --- | --- | --- | --- | --- |
| 0 | `$80` | `$C6E5` | 1 byte | Lo guarda tal cual en `(IX+$09)` (volumen base) | **SET_VOLUME** (antes mal llamado SET_NOTE) |
| 1 | `$81` | `$C703` | 1 byte | `AND $09`, guarda en `(IX+$08)` (máscara de mezclador) | **SET_MIXER** |
| 2 | `$82` | `$C765` | 0 | Recarga `BC`/`(IX+$02-03)` desde `(IX+$00-01)` (vuelve al principio del script) | **LOOP** |
| 3 | `$83` | `$C6EE` | 1 byte | Lo multiplica por `($C9BD)` (vía `RM_C88D`) y guarda en `(IX+$06-07)` (duración en tics) | **SET_DURATION** |
| 4 | `$84` | `$C761` | 0 | Salta directo a `RM_C552` (cierre de nota) sin pasar por duración | **HOLD/TIE** (repite duración anterior) |
| 5 | `$85` | `$C733` | 1 byte | Lo multiplica por `$0010`, divide `$0BB8` entre ese valor (vía `RM_C8A2`) y guarda el COCIENTE en `($C9BD)` (verificado: `RM_C8A2` devuelve cociente en BC, resto en HL; el handler usa `LD A,C` tras la división) | **SET_TEMPO/SPEED** (recalcula el multiplicador que usa el comando 3) |
| 6 | `$86` | `$C774` | N bytes (hasta agotar un contador en A) | Suma repetidamente `($C9BD)` a un acumulador y guarda en `(IX+$06-07)` (duración en tics) | **SET_DURATION_MULTI** (variante acumulativa de 3) |
| 7 | `$87` | `$C7AB` | 1 byte | `RES 0/1,(IX+$2D)`, copia 15 bytes desde una tabla (`$CA6A`+índice) a `(IX+$16..)`, y pone a cero `(IX+$0C/$0D/$10/$11/$12/$2A/$2B/$2C)` | **SET_INSTRUMENT** (carga los parámetros de envolvente de volumen/tono de un instrumento y resetea los acumuladores) |
| 8 | `$88` | `$C74D` | 1 byte | `AND $1F`, guarda en `($CA5E)`, llama a `RM_C6C9` (relatch de la tabla fija de envolvente) | **SET_ENVELOPE** |
| 9 | `$89` | `$C7F4` | 1 byte | Copia 6 bytes desde una tabla (`$CB5A`+índice) a la tabla fija `$CA53+4`, resetea `($CA5F)` y sincroniza `($CA60)` con el canal actual | **SET_ENVELOPE_SHAPE** (variante que además fija una tabla de forma de percusión) |
| 10 | `$8A` | `$C797` | 1 byte | `OR` con `(IX+$2D)` y con `($CA5D)` (flags globales) | **SET_FLAGS** |
| 11 | `$8B` | `$C70E` | 0 | Si `($C9BC)` (canal actual) coincide con `($CA60)` (canal "dueño" de la tabla fija), la borra entera (10 bytes) | **RESET_SHARED_ENVELOPE** (solo actúa si eres el canal que la posee) |
| 12 | `$8C` | `$C84B` | 1 byte | Guarda `BC` en una tabla por canal (`$CA61`+canal), busca en una tabla de 2 bytes/entrada (`$CB72`) y el resultado pasa a `BC` | **CALL_SUBPATTERN** (guarda dirección de retorno, salta a un patrón indexado) |
| 13 | `$8D` | `$C867` | 0 | Recupera `BC` desde la tabla `$CA61`+canal (sin parámetro) | **RETURN_SUBPATTERN** (contrapartida del 12: vuelve del patrón) |
| 14 | `$8E` | `$C878` | 1 byte | Escribe el byte tal cual en `(HL)`, con `HL` apuntando a la entrada de estado del canal (`$CA67`+canal, vía `RM_C882`) | **SET_CHANNEL_STATE** |

**Confianza**: la mecánica (qué bytes lee, qué campos toca, a qué tabla
indexa) está verificada al 100% -- viene directamente de leer las
instrucciones reales, no de suposición. Los **nombres** son
interpretación razonada a partir de esa mecánica y del contexto, no
verificación en vivo -- especialmente los comandos 6, 9, 10 y 12/13
(patrones/subrutinas) son la parte más especulativa. El error de
nota↔duración de la primera pasada (comando 0 y byte `<$80`) se
detectó y corrigió al intentar construir el renderizador de audio: en
cuanto se intentó CONSUMIR estos valores para sintetizar sonido de
verdad, la incoherencia (un valor "de duración" alimentando
directamente el registro de tono del PSG) se hizo evidente.

**Aún sin decodificar**: las tablas de instrumento en sí (~20
punteros en `$CA76` aprox. a programas escritos en este mismo
lenguaje, interpretados como "instrumento" en vez de "canal"), y el
significado preciso de cada tabla de 96/170/etc. bytes que estos
comandos indexan (duración, envolvente, forma de percusión). Sigue
sin existir una herramienta de época compatible -- cualquier editor
tendría que ser una herramienta nueva construida a partir de esta
gramática.

## Construido `tools/mmsnd_tool.py` -- descompilador/compilador del bytecode de sonido, con verificación roundtrip en los 16 ficheros reales

A petición explícita del usuario ("monta el formato y el compilador
descompilador"), con los 15 comandos ya descifrados: escrito un script
Python (`src/tools/mmsnd_tool.py`, sin dependencias externas) con:

- `disasm fichero.snd [fichero.txt]`: vuelca el binario a texto plano,
  un mnemónico por línea (`SET_NOTE 0x0E`, `DUR 0x18`,
  `SET_DURATION_MULTI 0x03 0x11 0x22 0x33` para el comando de longitud
  variable, etc.), con `;` para comentarios.
- `asm fichero.txt [fichero.snd]`: la conversión inversa.
- `roundtrip`/`roundtrip-all`: verifica que `disasm`+`asm` reproduce
  el binario original byte a byte -- **la propia prueba de que el
  descifrado del bytecode es correcto**: si un comando tuviera un
  número de parámetros equivocado, el fichero no cuadraría al final
  (se detectaría como truncamiento o sobra de bytes) o se decodificaría
  un byte de comando inválido a mitad de fichero.

**Verificado: los 16 ficheros `.snd` reales (los 3 de música + los 13
efectos) hacen roundtrip exacto, sin excepción** -- cada uno se
descompone limpiamente en instrucciones válidas hasta el último byte,
sin ningún truncamiento ni comando desconocido. Dado que los límites
de cada fichero se obtuvieron de forma completamente independiente
(cruzando `LEVELCYCLE_RESOURCE_TABLE`, no analizando el bytecode en
sí), este resultado es una confirmación fuerte adicional de que la
mecánica de los 15 comandos está bien entendida. El comando de
longitud variable (6, `SET_DURATION_MULTI`) no aparece en ningún
fichero real, así que se verificó aparte con un caso sintético
(`SET_DURATION_MULTI 0x03 0x11 0x22 0x33`) -- roundtrip también
exacto.

Generado un `.txt` gemelo (mismo nombre, extensión `.txt`) para cada
uno de los 16 `.snd` en `data/sound/` -- ese es ahora el fichero que
se edita a mano; el flujo de trabajo para modificar un sonido es:
editar el `.txt`, ejecutar `py tools/mmsnd_tool.py asm fichero.txt
fichero.snd` para regenerar el binario, y recompilar el juego
normalmente (el `.asm` sigue haciendo `INCBIN` del `.snd`, no del
`.txt`).

**⚠️ AVISO -- límite real de qué se puede editar** (detectado por el
usuario, no algo que se me hubiera ocurrido comprobar): cada `.snd` se
compila a una dirección FIJA, calcada del binario original. Cambiar el
**valor** de una instrucción ya existente (otra nota/duración/
instrumento) es seguro. **Añadir o quitar instrucciones, o cambiar la
cuenta de un `SET_DURATION_MULTI`, NO lo es** -- si cambia el número de
bytes total del fichero, todo lo que va detrás en `madmix1.asm` se
desplaza de dirección, y `LEVELCYCLE_RESOURCE_TABLE`
(`madmix_scr.asm`) se queda apuntando a la dirección VIEJA: el juego
compilaría sin ningún error pero saltaría a sitios incorrectos en
tiempo de ejecución (corrupción silenciosa, no un fallo de
compilación). El propio `mmsnd_tool.py` escribe este mismo aviso al
principio de cada `.txt` que genera, y también está en `README.md`.
Mitigación posible pero no implementada (decisión explícita de
documentar en vez de tocar código): reescribir
`LEVELCYCLE_RESOURCE_TABLE` con referencias simbólicas (`DW
SOUND_EVT00_CEE2`) en vez de bytes crudos, para que esa tabla en
concreto se autoactualizara -- no resolvería el resto de direcciones
numéricas fijas que hay más adelante en el fichero.

## Construido `tools/mmsnd_render.py` -- renderizador a WAV, y dos correcciones importantes encontradas al construirlo

A petición explícita del usuario ("puedes hacer otra utilidad que
reproduzca esos sonidos?"). Construir un renderizador de verdad (no
solo partir/recomponer bytes) obliga a CONSUMIR el significado de cada
valor, no solo a saber cuántos bytes ocupa -- y eso sacó a la luz dos
errores reales de la pasada anterior, además de una pieza que faltaba
por completo.

### Corrección 1: el byte `<0x80` es la NOTA, no la duración

Al intentar alimentar el sintetizador con "duración" descubrí que ese
valor se usaba para indexar directamente el registro de TONO del PSG
-- no tenía sentido como duración. Retrazando `RM_C527`: el byte se
suma a una transposición por canal (`$CA67`, 3 bytes, uno por canal --
verificado en el binario original: los 3 son `$00`, sin transponer) y
el resultado indexa la tabla de 96 palabras `$C8DE`, cuyos valores
(vistos ahora con esta luz) son exactamente una progresión de
periodos de tono PSG decrecientes -- una escala cromática. La
duración real vive en otro campo (`+$06/+$07` del registro de canal,
fijado por los comandos 3/6). Esto obligó a renombrar el comando 0
(antes `SET_NOTE`, ahora `SET_VOLUME` -- de verdad fija el volumen
base) y el mnemónico `DUR` de la herramienta a `NOTE`. Corregido en
`mmsnd_tool.py`, `FINDINGS.md` y los 16 `.txt` regenerados
(verificado roundtrip exacto de nuevo tras el cambio de nombre, que no
afecta a los bytes).

### Corrección 2: la polaridad de `RM_C82E` estaba al revés

Documentada en una sesión anterior como "A=0 activa, A!=0 desactiva".
Retrazando el álgebra de bits con cuidado (`CPL`, `OR`, `AND` sobre la
sombra del registro 7 del PSG) para poder decidir si un canal suena o
no: es AL REVÉS -- **un bit a 1 en A ACTIVA** ese generador (bit0=tono,
bit3=ruido), un bit a 0 lo deja silenciado. Tiene sentido con el resto
del código: `RM_C4F9` hace `XOR A` (todo a 0, silencia brevemente,
evita clics) antes de procesar los comandos de una nota nueva, y
`RM_C53A` vuelve a llamar con el valor real fijado por `SET_MIXER`
para dejar el estado audible definitivo. Corregido el comentario en
`madmix1.asm` (verificado 0 diferencias, es solo un comentario).

### Pieza que faltaba: los "subpatrones" compartidos

Los comandos 12/13 (`CALL_SUBPATTERN`/`RETURN_SUBPATTERN`) no eran
solo curiosidad -- **la música real de los 3 canales de arranque los
usa constantemente** (17-20 veces cada script de música, ninguna
llamada a `RETURN_SUBPATTERN` en los 16 ficheros -- viven al final de
cada subpatrón, fuera de los ficheros ya extraídos). Localizados con
la tabla de punteros `$CB72` (**21 entradas, no 20** -- corregido tras
etiquetar la zona byte a byte en `madmix1.asm`, ver más abajo; las
entradas 13-20 repiten el mismo puntero, el del primer subpatrón): 13
subpatrones únicos en
`$CB9C`-`$CDAB` (justo antes de `$CDCB`, el primer script). Extraídos
junto con el resto de tablas auxiliares (transposición `$CA67`,
instrumentos `$CA6A` -- 16 de 15 bytes cada uno --, formas de
envolvente `$CB5A` -- 4 de 6 bytes --) a un único fichero
`data/sound/_engine_tables.bin` (1261 bytes, `$C8DE`-`$CDCB`
completo -- la misma zona que sigue viviendo como `DB` inline en
`madmix1.asm`, aquí solo para que el renderizador tenga datos reales).
**Los 13 subpatrones también pasan el roundtrip exacto** de
`mmsnd_tool.py` (incluida la comprobación de que terminan en
`RETURN_SUBPATTERN`) -- más confirmación de que el modelo del
bytecode es correcto.

### El renderizador (`tools/mmsnd_render.py`)

Emula: generador de tono cuadrado + generador de ruido (LFSR
simplificado, sin verificar contra el polinomio real del AY-3-8910) +
mezclador (con la polaridad ya corregida) + tabla de volumen
logarítmica de 16 pasos (valores estándar del AY-3-8910). Interpreta
el bytecode tick a tick igual que `RM_PLAYER_TICK_C4EB`, incluyendo
`SET_TEMPO`/`SET_DURATION` (con la división de `RM_C8A2` bien
orientada: cociente, no resto -- otro detalle que salió mal a la
primera y se corrigió al ver que la primera prueba daba una nota de
128 segundos en vez de una fracción de segundo).

`py mmsnd_render.py render fichero.snd salida.wav` / `render-all
carpeta/ carpeta_salida/`. Los 16 sonidos ya están renderizados en
`build/sound_preview/*.wav` para escuchar.

**Límite honesto de esta pasada, no resuelto**: las envolventes de
volumen (2 fases) y de tono/deslizamiento (3 fases) están modeladas de
forma simplificada -- la mecánica de recarga está trazada (qué campos
se copian de dónde), pero el detalle fino de cómo se combinan con el
acumulador no se ha verificado escuchando contra el juego real. El
generador de ruido tampoco es una emulación certificada del LFSR real
del chip. Es decir: el resultado es una **reconstrucción razonada,
no una emulación certificada** -- sirve para juzgar de oído si la
lectura del bytecode tiene sentido musical (ritmo, qué nota, cuándo
calla), no como referencia perfecta de timbre. Sin una sesión de
escucha del usuario contra el juego real (o contra el `.cas`/`.dsk` en
openMSX) no se puede afinar más esto.

### Sesión de escucha del usuario -- primera ronda de correcciones

Primer resultado, con los 16 `.wav` ya en `build/sound_preview/`:
`14_evt02_flecha_cf62.wav` y `15_evt03_modo_especial_cf70.wav`
"perfectos" a la primera (ambos son el caso simple: tono puro, sin
`CALL_SUBPATTERN`, sin `SET_ENVELOPE_SHAPE`); `13_evt05_mariquita_
repone_cf44.wav` "casi perfecto, se reconoce pero muy rápido, como si
le faltara la parte final"; `10_evt10_inicio_nivel_cef0.wav`
irreconocible ("¿es lenta? ¿algo le pasa?").

Investigando el caso de la mariquita salió un **error real en el
mapeo de campos del instrumento** (los 15 bytes de cada instrumento,
tabla `$CA6A`): había confundido qué byte es el "retardo entre pasos"
y cuál es "cuántas repeticiones" para cada fase de la envolvente de
volumen. Retrazado bit a bit contra `RM_C699`/`RM_C6B1` (la rutina de
"relatch" que copia estos valores del instrumento a los contadores en
vivo al empezar cada nota) el mapeo real de los 15 bytes es:

```
b[0]/b[1]   = repeticiones fase1/fase2 de volumen
b[2..4]     = repeticiones fase1/2/3 de tono
b[5]/b[6]   = delta fase1/fase2 de volumen
b[7..9]     = delta (CON SIGNO) fase1/2/3 de tono
b[10]/b[11] = retardo entre pasos, fase1/fase2 de volumen
b[12..14]   = retardo entre pasos, fase1/2/3 de tono
```

Cada fase se procesa en orden (1, luego 2, [luego 3 en tono]),
deteniéndose en la primera que siga "activa" -- solo se pasa a la
siguiente fase cuando la actual agota AMBOS su retardo y sus
repeticiones. Corregido en `mmsnd_render.py` (`load_instrument`/
`relatch_envelopes`/`apply_envelopes`, con signo de 16 bits para el
acumulador de tono, sin signo para el de volumen).

También se corrigió un desajuste de temporización de 1 tic por nota:
en el original, `RM_C552` (relatch al empezar la nota) cae en
`RM_C564` (decrementa contador + aplica un paso de envolvente) **sin
salto de por medio** -- el primer tic de cada nota ya cuenta y aplica
un paso, no se espera al tic siguiente. El renderizador no lo hacía
así; corregido.

**El caso `10_evt10_inicio_nivel_cef0`** tiene una explicación
distinta, no un bug del renderizador: `IML_900F` (madmix1.asm) instala
este mismo bloque de datos en los 3 canales SIMULTÁNEAMENTE, cada uno
empezando 7 bytes más adentro (offsets 0/+7/+14) -- es un acorde de 3
voces, no una melodía de una sola voz. Renderizar solo el canal 0
aislado (lo que hace `render` hoy) suena necesariamente incompleto/
irreconocible por diseño, no por error de modelado. Pendiente:
añadir un modo de render multicanal que mezcle las 3 voces para este
caso concreto (y para la música de arranque, que también podría
sonar mejor con los 3 canales `00`/`01`/`02` mezclados en vez de cada
uno por separado).

Verificado tras la corrección: los 16 `.wav` se regeneran sin errores
(`render-all`), duraciones ligeramente más cortas en general (el fix
de temporización quita 1 tic por nota).

### Segunda ronda: `render-chord` para el soniquete de inicio de nivel

El usuario confirmó "muy buena dirección, todo mucho mejor" y que
`10_evt10_inicio_nivel_cef0.wav` ya se reconoce como la música de
inicio, pero "hay notas que parecen lentas y largas". Encaja
exactamente con el diagnóstico de la ronda anterior: al tratar este
fichero como UN canal lineal, el renderizador toca la voz 1 (offset 0,
`CALL_SUBPATTERN 0x0B`) y, en vez de parar donde debería, sigue
leyendo hacia el trozo de la voz 2 (offset +7, que **repite el mismo
subpatrón 0x0B**) y luego el de la voz 3 (offset +14) -- todo
concatenado en una sola voz, en vez de las 3 sonando A LA VEZ como
hace `IML_900F` de verdad.

Añadido `render_chord()`/`render-chord` a `mmsnd_render.py`: crea N
"voces" (cada una su propio `Channel` + su propio oscilador de tono/
ruido) arrancando en offsets distintos DENTRO del mismo fichero, cada
una con su propio límite de "fin natural" (el siguiente offset, o el
final del fichero para la última), las hace avanzar en paralelo tic a
tic y mezcla su salida (con margen de amplitud entre voces para no
recortar). `render()` (una sola voz) se reescribió como caso
particular de la misma maquinaria (`Voice`/`synth_tick`), sin cambiar
su comportamiento -- verificado sin regresión en los 16 `.wav`
existentes (mismas duraciones que antes del refactor).

`py tools/mmsnd_render.py render-chord data/sound/10_evt10_inicio_nivel_cef0.snd salida.wav 0,7,14`
-- resultado: 1.70 s (antes, como voz única, entre 4.80 s y el tope de
seguridad de 8 s, arrastrando la repetición espuria del subpatrón).
Generado en `build/sound_preview/10_evt10_inicio_nivel_ACORDE.wav`,
pendiente de que el usuario lo escuche.

**Nota para el futuro**: la música de arranque (`00`/`01`/`02`) son 3
ficheros SEPARADOS (no offsets dentro de uno), así que no encajan en
`render_chord` tal cual -- si se quiere escuchar esa música con los 3
canales mezclados, haría falta una variante que tome 3 rutas de
fichero en vez de 3 offsets (no implementada todavía, mismo principio).

### Tercera ronda: `04_evt04` renombrado a "disparo (modo avión)", y la "última nota" de la mariquita, investigada tick a tick

El usuario identificó por oído `04_evt04_trampilla_ce72.wav` como "el
sonido del disparo" (#9), no de trampilla -- verificado en el código
que `TRAPDOOR_FLIP_TABLE` (la rutina que escribe `$6128=4`) se llama
tanto desde el camino de tanque/trampilla como desde `HANDLER_3067`
(modo avión), confirmando que es una rutina genérica reutilizada por
ambos, no exclusiva de trampillas. Renombrado a
`04_evt04_disparo_avion_ce72.snd`/`.txt` (label/INCBIN en
`madmix1.asm` y manifiesto `SCRIPT_ADDR` de `mmsnd_render.py`
actualizados); recompilado y verificado: 0 diffs nuevos.

Después, el usuario insistió en que `13_evt05_mariquita_repone_cf44.wav`
"le falta la última nota, o es tan rápida que ni se escucha" (tras la
corrección de envolventes de la primera ronda). Se instrumentó
`Interpreter`/`Channel` con un volcado tic a tic (estado completo:
`read_ptr`, `ticks_left`, `vol_accum`, volumen efectivo) para ver
exactamente qué pasa, en vez de conjeturar. Resultado, verificado
contra el WAV real muestra a muestra:

- El fichero (30 bytes, verificado exacto contra el binario original,
  0 diffs) usa el **instrumento `$0C`** para las notas
  `0x30 0x30 0x28 0x34 0x30 0x2C` con volumen base `0x09` (`SET_VOLUME`).
- Instrumento `$0C`: `01 0E 00 00 00 07 FF 00 00 00 00 01 00 00 00` --
  repeticiones-volumen `[1,14]`, delta-volumen `[7,-1]`,
  retardo-recarga-volumen `[0,1]` (nada de tono: todo a 0).
- Al empezar CUALQUIER nota con este instrumento: fase 1 del volumen
  tiene retardo 0, así que se aplica en el primerísimo tic
  (`vol_accum` pasa de 0 a 7 en el mismo tic que arranca la nota).
  Con volumen base 9, `9+7=16`, y el registro de volumen del PSG es de
  4 bits (`AND $0F` en `$C61D`, verificado byte a byte contra el
  original) -- **16 vuelve a 0: silencio**. Los 2 primeros tics (40 ms)
  de CADA nota que usa este instrumento son silenciosos por diseño;
  a partir del 3er tic la fase 2 hace `vol_accum -= 1` por paso,
  dejando la nota sonando fuerte (volumen efectivo 15, luego 14...).
- Para la última nota (`NOTE 0x2C`, `SET_DURATION 0x05` = 5 tics): tics
  1-2 silenciosos, tics 3-5 audibles y fuertes (igual patrón que las
  notas anteriores de duración 4 y 7) -- el WAV generado sí contiene
  esos 3 tics finales fuertes (confirmado inspeccionando las muestras
  del `.wav`, amplitud máxima ~251/255, igual que en las notas
  anteriores). No hay ningún corte prematuro ni tic perdido en el
  renderizador.
- Es decir: **la mecánica coincide exactamente con el código real**
  (retrazado instrucción a instrucción); no es un fallo de
  transcripción del bytecode (los bytes son exactos) ni un bug nuevo
  del renderizador. Lo que hace que la última nota suene "casi
  inaudible" es que, con `SET_DURATION 0x05`, solo quedan 3 de esos 5
  tics (60 ms) realmente audibles tras el "ataque silencioso" de 40 ms
  que este instrumento concreto impone siempre -- la nota más corta de
  todo el fichero, terminando en seco (sin decaimiento) justo cuando
  se acaba el script.

**Sin resolver / requiere el oído del usuario para decidir el
siguiente paso**: no hay evidencia de error en el modelo ni en los
datos -- si esto sigue sonando "mal" comparado con el juego real, las
hipótesis que quedan son (a) que así suena también en el juego
original (un "clic" de cierre muy breve, quizás intencionado) y el
renderizador ya es fiel, o (b) que en el hardware real este canal, al
llegar al final del script, sigue leyendo hacia la memoria contigua
(el siguiente fragmento, `14_evt02_flecha_cf62.snd`, empieza justo en
`$CF62`) en vez de detenerse limpiamente como hace nuestra heurística
de "fin natural" (`Channel.script_end`) -- es decir, la nota real
podría tener una cola audible que nuestro aislamiento recorta. No se
puede distinguir entre (a) y (b) sin comparar contra el juego corriendo
(openMSX), así que queda aparcado con el resto de verificaciones que
requieren oído/emulador.

### Cuarta ronda: dos bugs reales encontrados y corregidos en mmsnd_render.py, y dos casos que no son bugs

El usuario reportó en rápida sucesión: 05_evt07_pista_ce7e.wav "no
suena", 07_evt11_bola_poder_ce9c.wav "tampoco suena",
02_boot_ch2_ce0c.wav "aquí no escucho nada, como mucho un ruidito al
final", y confirmó por separado que 00_script_cdcb.wav/
01_script_cdff.wav son "el inicio de la canción del título"/"la
batería del inicio" (identificación correcta, no un bug).

**Bug real #1 -- tabla de volumen demasiado burda (VOLUME_TABLE)**: la
tabla usada (0,0,0,0,0,0,0,1,1,2,3,4,6,8,11,16, escalada a 0-255)
redondeaba a 0 los niveles de volumen 1 a 6, silenciando notas que en
el hardware real SÍ suenan (aunque flojas). Este era exactamente el
caso de 07_evt11_bola_poder_ce9c.snd: usa SET_VOLUME 0x06, sin
envolvente que lo mueva -- volumen efectivo constante 6, que con la
tabla vieja daba amplitud 0 (silencio total) en un bucle infinito
(LOOP) que además hacía tocar el tope de seguridad de 300 tics sin
nunca sonar. Corregido sustituyendo la tabla por la curva estándar del
generador de volumen del AY-3-8910 (3dB por paso, nivel = 2 elevado a
((n-15)/2)): el nivel 0 sigue siendo silencio real, pero 1-15 ya nunca
redondean a 0. Verificado: el wav regenerado ya no tiene ninguna
muestra en silencio.

**Bug real #2 -- offset DC negativo constante durante el silencio real
(synth_tick)**: cuando ni el tono ni el ruido están activos (máscara
de mezclador a 0, silencio real del canal), el código seguía restando
la mitad del volumen (el centrado de la onda cuadrada, correcto SOLO
cuando algo suena) usando el volumen BASE del canal aunque no hubiera
nada sonando -- dejaba un nivel DC negativo constante en vez de
silencio verdadero (128 en el wav de 8 bits). Con volumen base alto y
un tramo de silencio largo (ver más abajo, 02_boot_ch2_ce0c.wav tiene
unos 11.5s de silencio real al principio) esto se oía como un
ruido/zumbido de fondo en vez de silencio, exactamente lo que describió
el usuario ("un ruidito"). Corregido: silencio real ahora escribe una
muestra a cero sin tocar el volumen. Verificado con muestra a muestra:
los primeros 11.52s de 02_boot_ch2_ce0c.wav ahora son silencio exacto,
no el offset viejo.

**02_boot_ch2_ce0c.snd (canal 2 de la música de arranque) -- no es un
bug, es un preludio de silencio real de unos 11.5s, verificado tic a
tic**: el script empieza con SET_VOLUME 0x0E, SET_DURATION 0xC0 (192
tics) y tres HOLD seguidos, sin ningún NOTE ni SET_MIXER previo.
Retrazado contra el código real (RM_C4F9/RM_C552/RM_C564, $C761 para
HOLD): HOLD salta directo a RM_C552 (recarga el contador de tics desde
la duración actual) SIN pasar por RM_C53A (relatch de envolvente) ni
por la resolución de nota -- es un "tie" puro, no reinicia nada. Con el
mezclador todavía a 0 (nunca se ha llamado SET_MIXER) y sin tono
resuelto, esos 3 HOLD son 3 veces 192 = 576 tics (11.52s) de silencio
real antes de que el primer CALL_SUBPATTERN 0x02 ejecute su propio
SET_MIXER 0x01 y arranquen las notas de percusión. Confirmado con un
volcado tic a tic (Interpreter.tick instrumentado) que el mezclador
sigue en 0 hasta el tic 576 exacto. El límite de seguridad por defecto
de render() (--max-ticks 300 = 6s) corta el renderizado ENTERO dentro
de ese silencio -- por eso "no se escucha nada": no es un fallo del
intérprete, es que 6s no alcanzan ni para llegar al primer tambor.
Renderizado de nuevo con --max-ticks 1200 (24s): confirma silencio real
hasta 11.52s y percusión audible después. Con --max-ticks 3000 (60s)
tampoco se completa un ciclo entero de LOOP -- el patrón completo de
este canal es largo; queda pendiente (no urgente) afinar cuánto dura un
ciclo completo si se quiere renderizar una vuelta entera.

**05_evt07_pista_ce7e.snd SIGUE en silencio -- causa distinta, no
resuelta**: este script (13 bytes) no contiene ningún NOTE --
SET_TEMPO, SET_DURATION, SET_MIXER 0x08 (solo ruido), SET_VOLUME,
SET_ENVELOPE_SHAPE, SET_ENVELOPE, RESET_SHARED_ENVELOPE, fin. La tabla
de los 15 comandos (comandos 8/9/11) indica que SET_ENVELOPE/
SET_ENVELOPE_SHAPE/RESET_SHARED_ENVELOPE leen y escriben una tabla
compartida en $CA53 (10 bytes, "propiedad" de un canal a la vez vía
$CA60) que es un mecanismo COMPLETAMENTE DISTINTO del envolvente de
volumen/tono por canal que ya tenemos modelado -- muy probablemente el
generador de envolvente HARDWARE real del PSG (registros de
periodo/forma), usado aquí para modular un canal de puro ruido sin
necesidad de ninguna nota. mmsnd_render.py trata estos 3 comandos como
no-ops (solo consumen su byte de parámetro) porque esa tabla compartida
y quien la recorre tic a tic (RM_C6C9 y de dónde se llama en el bucle
principal) no se ha trazado todavía. Sin modelar esa pieza, este efecto
seguirá sonando mudo. Pendiente: trazar RM_C6C9 y el resto del
mecanismo de "envolvente compartida" -- aparcado con el resto de temas
de sonido que requieren más investigación.

Todos los wav de build/sound_preview se regeneraron tras ambas
correcciones (render-all).

### Quinta ronda: 02_boot_ch2_ce0c_full.wav "no está completa" -- tercer bug real, detección de LOOP rota

El usuario, tras las dos correcciones anteriores, confirmó que
02_boot_ch2_ce0c_full.wav (renderizado antes de esas correcciones, con
--max-ticks 2000 = 40s) "ya suena la música del juego" pero preguntó
si no se había grabado todo.

Investigando cuánto dura una vuelta completa: instrumentado un volcado
tic a tic más largo, se confirmó que el guion (78 bytes, 26 llamadas a
CALL_SUBPATTERN antes del LOOP final) SÍ avanza con normalidad a través
de las 26 subpatrones en secuencia (no se queda atascado en ningún
bucle interno) -- simplemente es una pieza larga: unos 11.52s de
silencio inicial (ver ronda anterior) más ~57.6s de percusión real,
unos 69 segundos por vuelta completa. El renderizado de 40s se cortaba
a media vuelta, de ahí "no está completa" -- no es un error de
interpretación del bytecode.

Pero al intentar medir esto se encontró un **tercer bug real**: el
mecanismo que usa render() para parar solo cuando se completa una
vuelta (comparar read_ptr con la dirección de inicio, tic a tic)
**nunca se dispara** en scripts como este, porque tras ejecutar LOOP el
intérprete sigue leyendo comandos sin pausa (SET_TEMPO, SET_VOLUME,
SET_DURATION, HOLD...) hasta la siguiente nota/HOLD -- para cuando se
muestrea el puntero al final del tic, ya no coincide exactamente con
la dirección de inicio. Antes de esta corrección, render() para
02_boot_ch2_ce0c.snd y 07_evt11_bola_poder_ce9c.snd (los dos únicos
.snd reales con LOOP) solo paraba al llegar al tope de seguridad
--max-ticks, nunca de forma limpia en el punto exacto de la vuelta.

Corregido añadiendo un flag `Channel.loop_hit`, puesto a True dentro
del propio manejo del comando LOOP (en el momento exacto en que se
ejecuta, sin depender de comparar punteros después); render() para en
cuanto lo ve. Verificado: 07_evt11_bola_poder_ce9c.wav pasó de 6.00s
(bucle de ruido cortado a lo bruto por el tope de seguridad) a 0.26s
(una vuelta limpia); 01_script_cdff.wav pasó de 6.00s a 2.42s.
Regenerado 02_boot_ch2_ce0c_full.wav con --max-ticks 8000: para solo
(antes del tope) en 69.14s -- confirma una vuelta completa real de
unos 69 segundos (11.52s de silencio + ~57.6s de percusión).


### Sexta ronda: etiquetado de las tablas de datos en madmix1.asm (0xC8DE-0xCDCB)

El usuario preguntó si `RM_TABLE_C8DE` era "el driver en sí" en
ensamblador. Aclarado: no, es puro DATO -- el código del driver
(`RM_C4A0` a `RM_C8C9`) ya está totalmente desensamblado justo encima;
esta zona son las tablas que ese código lee. Antes estaba como un
único volcado `DB` sin más subdivisión que un comentario de cabecera.
A petición del usuario (eligió explícitamente "solo etiquetar en el
.asm", sin extraer a fichero aparte), se añadieron labels+comentario
por tabla, sin tocar ni un byte: `CMD_JUMP_TABLE_C99E` (30B),
`CHANNEL_STATE_ZERO_C9BC` (171B), `SHARED_ENVELOPE_TABLE_CA53` (10B),
`MISC_FLAGS_CA5D` (4B), `SUBPATTERN_RETURN_TABLE_CA61` (6B),
`TRANSPOSE_TABLE_CA67` (3B), `INSTRUMENT_TABLE_CA6A` (240B),
`ENV_SHAPE_TABLE_CB5A` (24B), `SUBPATTERN_TABLE_CB72` (42B),
`SUBPATTERN_BYTECODE_CB9C` (hasta `$CDCB`). Los límites exactos se
calcularon programáticamente contando bytes desde `RM_TABLE_C8DE`
(script auxiliar, no a mano) para no arriesgar un desplazamiento;
varias líneas `DB` había que partirlas en dos o tres porque un límite
de tabla caía a mitad de línea -- mismos bytes, solo reorganizados.
Verificado: recompilado, 0 diferencias, mismo tamaño exacto
(22945 bytes).

De paso, contando bytes con precisión se detectó que `SUBPATTERN_TABLE_CB72`
tiene 21 punteros, no 20 como se había documentado antes (las
entradas 13-20 repiten el puntero del subpatrón 0) -- corregido en este
documento y en `mmsnd_render.py`.


### Séptima ronda: nueva sección `manuales/` -- documentación de referencia para formación

A petición del usuario, se creó `src/manuales/` como tercera pata de
la documentación, junto a `FINDINGS.md` (diario cronológico de
descubrimientos) y `FLUJO_PROGRAMA.md` (organizado por flujo de
ejecución): aquí se documenta CÓMO FUNCIONA cada subsistema ya
resuelto, en formato de manual técnico ordenado, pensado como material
de formación para un programador nuevo y como preservación en sí
mismo -- sin el proceso de investigación por medio.

Primer manual: `manuales/manual_driver_sonido.md`, cubriendo de forma
autocontenida todo lo ya resuelto sobre el driver de sonido del PSG:
el hardware AY-3-8910 y por qué el driver usa tablas precalculadas, la
arquitectura del código/datos, el bucle de tic (`RM_PLAYER_TICK_C4EB`/
`RM_C4F9`), la ranura de canal de 46 bytes campo a campo, los 15
comandos del bytecode con su tabla completa, el instrumento de 15
bytes y la mecánica de envolvente de 2/3 fases, los subpatrones, el
mecanismo `$6128`/`LEVELCYCLE_RESOURCE_TABLE` con la tabla completa de
los 14 índices, la envolvente de hardware compartida sin resolver
(`SHARED_ENVELOPE_TABLE_CA53`, §8 del manual) como
punto de partida explícito para quien retome esa línea, y el flujo de
trabajo real de las dos herramientas (`mmsnd_tool.py`/
`mmsnd_render.py`). Enlazado desde `README.md`. Se irán añadiendo más
manuales según se decida qué otras partes del sistema documentar así.


### Octava ronda: limpieza de mainloop_engine.bin y reorganización de maze_data.bin

El usuario preguntó por el resto de `.bin` sueltos en `data/`
(`maze_data.bin`, `mainloop_tables.bin`, `niveles_tabla.bin`) y de paso
apareció uno no documentado en el README: `mainloop_engine.bin` (1724
bytes). Investigado: no tiene ningún `INCBIN` en ningún `.asm`
(confirmado con grep exhaustivo sobre todo `src/`) -- corresponde al
rango `0x2CA0-0x335C` de `MADMIX.SCR`, que ya se transcribió entero
como código Z80 real con etiquetas (no como blob de datos), así que
nunca hizo falta un `INCBIN` para él. Era una copia de trabajo/
verificación huérfana de la sesión en que se transcribió ese tramo
(mismo papel que `_engine_tables.bin` para el sonido). Confirmado por
el usuario que ya no hace falta -- **borrado**.

Sobre `maze_data.bin`: el usuario preguntó si merecía vivir en
`data/niveles/` como el resto de cuerpos de nivel, ya que lo usan los
niveles 13 y 14. Investigando el detalle exacto (`FINDINGS.md`,
"RESUELTO EL PROPÓSITO DE maze_data.bin") se confirmó que NO es
contenido idéntico compartido por ambos niveles -- son dos mitades
CONTIGUAS SIN SOLAPE, cada una exclusiva de un nivel: los primeros 580
bytes son la cola del cuerpo del nivel 13 (la cabeza, 92 bytes, vive
en `RM_TABLE_CFA4`, la tabla de envolvente del driver de sonido); los
últimos 700 bytes son la cabeza del cuerpo del nivel 14 (la cola, 36
bytes, vive en la tabla sin descifrar tras `$D500`). Dado esto, se
partió el fichero en dos (`data/niveles/body_l13_maze.bin`, 580 bytes,
y `body_l14_maze.bin`, 700 bytes), siguiendo el mismo criterio "un
fichero = un nivel" que el resto de `data/niveles/` -- en vez de mover
el blob de 1280 bytes tal cual con un nombre que sugiriera "contenido
compartido" (que habría sido impreciso). Actualizado el `INCBIN` de
`madmix1.asm` (ahora dos `INCBIN` con labels `BODY_L13_MAZE_D000`/
`BODY_L14_MAZE_D244`, con comentario explicando el reparto exacto y
dejando claro que -- a diferencia del resto de `data/niveles/` -- estos
dos compilan dentro de `MADMIX1.BIN`, no de `MADMIX.SCR`). Verificado:
recompilado, 0 diferencias, mismo tamaño exacto (22945 bytes).
`maze_data.bin` borrado tras la partición. `README.md` actualizado.


### Novena ronda: LEVEL_LOADER ESCRIBE sobre el origen al cargar (RES 7,(HL) antes de LDI), y RM_TABLE_CFA4 rebajada de "tabla de sonido" a "sin consumidor confirmado"

El usuario preguntó, sobre el truco de compartir memoria de
`maze_data.bin`/`RM_TABLE_CFA4` con el nivel 13 (ver "RESUELTO EL
PROPÓSITO DE maze_data.bin" más arriba): ¿la información del nivel 13
es la del fichero más 92 bytes ajenos de sonido sin relación, o el
nivel 13 sobreescribe esos 92 bytes de sonido (y eso debería fallar)?

Verificado leyendo `LEVEL_LOADER` (`madmix_scr.asm`) línea a línea:
NO es una simple lectura no destructiva. El bucle de copia del cuerpo
(tanto `.plain_copy` como `.with_wildcard`) hace:

```asm
RES 7, (HL)     ; limpia el bit "comido" -- EN EL ORIGEN, (HL), no en el destino
LDI              ; copia (HL)->(DE) YA modificado, avanza ambos punteros
```

`HL` es el puntero de cuerpo ORIGINAL de la tabla de niveles (para el
13, `$CFA4`, confirmado extrayendo el registro real de
`niveles_tabla.bin`: `puntero_cuerpo=$CFA4`, `filas=21`,
`21×32=672` bytes). Es decir: el cargador SÍ escribe en el origen,
apagando el bit 7 de cada byte antes de copiarlo al buffer de juego
(`$FC60`) -- no es una lectura inocua.

Comprobado en el binario compilado: de los 92 bytes reales de
`RM_TABLE_CFA4`, **10 tienen el bit 7 puesto** (son `$BF`, offsets
30/32/34/48/50/52/63/67/79/83 relativos a `$CFA4`) y pasan a `$3F` la
primera vez que carga el nivel 13 en una partida.

**¿Por qué esto no rompe nada?** Se buscó con `grep`, exhaustivo, toda
referencia a `$CFA4`/`RM_TABLE_CFA4` en `madmix1.asm` y `madmix_scr.asm`
-- **ninguna rutina la lee nunca**, ni en el driver de sonido (ya
desensamblado por completo, `$C4A0`-`$C8C9`, sin huecos) ni en ningún
otro sitio. Consecuencia importante para la documentación: el nombre
"tabla de envolvente/percusión" que llevaba `RM_TABLE_CFA4` desde una
sesión antigua **era y sigue siendo una conjetura nunca confirmada**
(la nota original ya decía "no identificada nota a nota"). Con el
driver ya completo y sin ningún lector encontrado, la conclusión
correcta NO es "se usó una vez y ya no hace falta" -- es **"no hay
prueba de que se usara nunca, ni una vez"**. Dos hipótesis igual de
plausibles, sin forma de distinguirlas desde el binario final:

1. Resto de una versión anterior del driver (un instrumento/patrón
   abandonado antes de terminar el juego, nunca borrado -- borrar
   bytes tardíamente desplaza todo lo posterior, el mismo riesgo que
   ya conocemos de primera mano en este proyecto).
2. Nunca fue dato de sonido: el parecido de patrón que motivó el
   nombre en su día podría ser casualidad, y en realidad sea relleno
   de nivel colocado a propósito junto a los datos de nivel 13/14.

Corregido el comentario de `RM_TABLE_CFA4` y de `BODY_L13_MAZE_D000`
en `madmix1.asm` para reflejar esto con precisión (sin afirmar "tabla
de sonido" como hecho confirmado). Verificado: recompilado, 0
diferencias, comentario-only.


### Décima ronda: LEVEL_TABLE reescrita como tabla de datos nativa (adiós a niveles_tabla.bin)

El usuario preguntó si `niveles_tabla.bin` (los 15 registros de
nivel, 300 bytes) no debería estar en un formato legible/editable, ya
que ahora se conoce el significado de casi todos sus campos (offsets
0-19). A diferencia del bytecode de sonido (que necesitó un
compilador/descompilador propio porque es un lenguaje inventado), este
caso no requiere ninguna herramienta nueva: los punteros de cuerpo/
cabecera de cada registro (offsets 0-1, 2-3, 4-5) ya tienen etiquetas
reales definidas en el propio `madmix_scr.asm` (`BODY_L01`, `BODY_L2`...
`BODY_L12`, `HEADER_4AFC`, `HEADER_4B5C`, `HEADER_50BC`), así que basta
con sustituir el `INCBIN` por una tabla `DW`/`DB` nativa que las
referencie directamente -- el propio SjASMPlus calcula la dirección
correcta al ensamblar.

Se generó la tabla completa (15 registros) con un script que parte de
los bytes reales de `niveles_tabla.bin`, mapea cada valor de puntero
conocido a su etiqueta, y deja los campos ya descifrados (offsets 6,
8, 9, 10, 11, 12, 17, 18-19) como valores nombrados en vez de hex
suelto; los campos sin identificar (7, 15, 16) se dejan en hex con
comentario honesto de "sin identificar" -- sin inventar significado.
Única excepción a usar etiquetas: los niveles 13 y 14 apuntan a
`$CFA4`/`$D244`, direcciones dentro de `MADMIX1.BIN` -- otro binario,
compilado por separado, sin enlace entre ambos -- así que esos dos
punteros concretos se quedan en hex literal, con un comentario
explicando a qué etiqueta equivalen en `madmix1.asm`
(`RM_TABLE_CFA4`/`BODY_L14_MAZE_D244`).

Verificado: recompilado `madmix_scr.asm`, comparado byte a byte contra
el original -- exactamente los mismos 4 diffs conocidos de siempre
(posiciones ~6388-6390 y el último byte), ninguno nuevo. (Nota de
proceso: la primera verificación dio ~17.756 diffs por un error del
propio script de comparación -- aplicaba el descuento de 7 bytes de
cabecera BLOAD que solo hace falta para `MADMIX1.BIN`, no para
`MADMIX.SCR`, cuyo binario compilado SÍ incluye esa cabecera de
serie. Corregido el script, no el código.) `niveles_tabla.bin`
borrado tras la conversión. `README.md` actualizado.


### Undécima ronda: visores HTML actualizados (flujo_programa.html regenerado, mapa_memoria.html corregido)

El usuario pidió no olvidar actualizar los visores HTML tras los
cambios de esta sesión. Se revisaron los 3 candidatos con referencias
a lo tocado (`maze_data.bin`, `niveles_tabla.bin`, `mainloop_engine.bin`,
las nuevas etiquetas del sonido, `LEVEL_TABLE`):

- **`recursos/flujo_programa.html`**: el `INVENTORY` (591 etiquetas,
  "generado automáticamente desde los .sym") estaba desactualizado en
  dos frentes -- faltaban las ~12 etiquetas nuevas del sonido más
  `BODY_L13_MAZE_D000`/`BODY_L14_MAZE_D244`, `MAZE_DATA` ya no existe,
  y sobre todo **todos los números de línea de `madmix_scr.asm`
  posteriores a `LEVEL_TABLE`** habían cambiado al insertar la tabla
  nativa (un desfase que ya arrastraba desde antes de esta sesión, de
  hecho: ni `TI_2C2E_ENTRY`/`TI_5B56` ni el renombrado
  `TAIL_KEYMENU_MAIN`→`TAIL_MAINMENU_DRAW` de sesiones anteriores
  estaban reflejados). Se regeneró el inventario completo desde cero
  con un script (compila los 3 `.asm` con `--sym`, localiza la línea de
  definición de cada símbolo, y clasifica función/interna/dato/sin ref.
  cruzando `CALL`/`JP`/`JR` -- tanto por nombre simbólico como por
  dirección hex literal, ya que las llamadas ENTRE los 3 binarios
  (compilados por separado, sin enlazador) usan la dirección numérica,
  no el símbolo). Resultado: 623 etiquetas (antes 591), comparadas
  entrada a entrada contra el inventario viejo -- solo 5 diferencias de
  categoría genuinas (mejoras del cálculo, p.ej. detectar `CALL Z,
  $XXXX` con espacio tras la coma, que el heurístico anterior se
  saltaba), el resto son o bien las etiquetas nuevas legítimas o la
  eliminación de `MAZE_DATA`. Actualizados también los contadores por
  categoría en el propio HTML (94 función/279 interna/163 dato/87 sin
  ref.) y en `FLUJO_PROGRAMA.md` §0/README.md (mismo cambio 591→623).
- **`recursos/mapa_memoria.html`**: corregidas las dos entradas que
  mencionaban `maze_data.bin` por nombre (ahora inexistente, partido en
  `body_l13_maze.bin`/`body_l14_maze.bin`) y la que describía
  `RM_TABLE_CFA4` como "probable tabla de envolvente/percusión" sin la
  corrección de esta sesión (sin consumidor confirmado); añadida
  mención de que `LEVEL_TABLE` ya no es un `.bin` sino una tabla nativa.
- **`recursos/niveles.html`**: revisado, sin referencias a los ficheros
  tocados (sus "591" son datos de tile sin relación, no el contador de
  etiquetas).

Verificado: recompilados ambos binarios, 0 diferencias en
`MADMIX1.BIN` y los mismos 4 diffs conocidos de siempre en
`MADMIX.SCR` (los cambios son solo de documentación/HTML, ningún byte
compilado distinto). JSON del `INVENTORY` verificado parseable (623
entradas).


### Duodécima ronda: editor de niveles -- texto legible, tools/mmlvl_tool.py y editor visual (recursos/editor_niveles.html)

El usuario preguntó por el formato de `header_XXXX.bin` (cabeceras de
nivel): son rejillas de losetas (32 columnas x 3 filas), mismo formato
que los cuerpos de nivel -- índices 0-90 del catálogo real de
`data/tiles/*.til`, sin campos con significado propio, dibujadas por
`LEVEL_LOADER` como margen decorativo encima y debajo del cuerpo
jugable. A partir de ahí, propuso el mismo tratamiento que ya recibió
el sonido: formato de texto legible + herramienta de conversión +
(aquí sí tiene sentido, al ser losetas visuales) un editor visual que
use el catálogo ya identificado para pintar niveles sin hex a mano,
respetando las dimensiones fijas actuales y avisando si el número de
bolitas deja de coincidir con `LEVEL_TABLE`.

**Hallazgo nuevo durante la implementación**: el bit 7 de cada byte
SÍ se usa de verdad en los cuerpos reales de nivel (77-160 bytes con
bit7 puesto por fichero, comprobado con un script) -- aunque
`LEVEL_LOADER` lo borra incondicionalmente al cargar (`RES 7,(HL)`,
ver ronda anterior), está presente en el binario original y el
formato de texto debe preservarlo byte a byte. Las 3 cabeceras
compartidas, en cambio, tienen bit7 siempre a 0.

**Segundo hallazgo**: `body_l13_maze.bin`/`body_l14_maze.bin` (580/700
bytes, los fragmentos "prestados" de la ronda anterior) NO son
múltiplos de 32 -- no son rejillas completas, son trozos que empiezan/
terminan a mitad de fila real del nivel al que pertenecen (comparten
memoria con `RM_TABLE_CFA4` y la tabla sin descifrar tras `$D500`).
`tools/mmlvl_tool.py` los trata con un segundo formato de texto ("modo
plano", `; bytes=N` en vez de `; filas=N columnas=N`) -- lista de
bytes sin forma de rejilla, con su propio aviso de tamaño fijo. Quedan
fuera del editor visual (no tiene sentido pintarlos como rejilla
aislada).

**`tools/mmlvl_tool.py`** (mismo espíritu que `mmsnd_tool.py`):
`disasm`/`asm` (bin↔texto, autodetecta modo rejilla o plano según si
el tamaño es múltiplo de 32, valida filas/columnas/bytes declarados
antes de escribir), `roundtrip`/`roundtrip-all` (verificado: los 17
`.bin` de `data/niveles/` -- incluidos los 2 fragmentos planos --
reproducen su binario original exacto), y `check-bolitas fichero.txt
NIVEL` (cuenta losetas "suelo con bola", 0x2D/0x2E/0x2F con bit7
enmascarado, y las compara contra el objetivo real leído directamente
de `LEVEL_TABLE` en `madmix_scr.asm` -- parseando el bloque de 9
líneas por registro, sin manifiesto aparte que se pueda
desincronizar). Verificado contra los 5 niveles con coincidencia
exacta ya conocidos de la ronda de offsets 18-19 (1=114, 8=90,
10=116, 12=176): los 4 comprobables con este comando coinciden
exacto. Nivel 6 (no es de los 5 exactos) da el desajuste ya
documentado (128 contadas vs 151 objetivo) -- comportamiento esperado,
no un bug de la herramienta.

**`recursos/editor_niveles.html`** (nuevo visor, autocontenido, sin
servidor ni fetch, mismo patrón que el resto de `recursos/`): paleta
de las 91 losetas (reutiliza -- copiando, como ya hace `niveles.html`
con `graficos.html` -- el array `TILE_GFX` y el decodificador
`hexToGrid`/`drawTile`), rejilla del nivel activo pintable con clic/
arrastre, casilla para pintar con bit7 puesto, contador de bolitas en
vivo (verde/rojo según coincida con el objetivo de `LEVEL_TABLE`,
embebido como snapshot al generar el HTML -- si `LEVEL_TABLE` cambia
hay que regenerarlo, mismo mantenimiento manual que `TILE_GFX`/
`LEVELS` en los otros visores), botón "Abrir .txt" (`<input
type=file>`, sin problemas de CORS) y "Descargar .txt" (Blob) en el
mismo formato que produce/consume `mmlvl_tool.py` -- el flujo real es
editar visualmente, descargar, mover el fichero a mano a
`data/niveles/` y correr `mmlvl_tool.py asm` antes de recompilar,
igual que ya se hace con los `.snd`. No incluye `body_l13_maze`/
`body_l14_maze` (fragmentos sin alinear a fila) ni valida ítems/
enemigos (tablas de coordenadas aparte, `ITEM_TABLE_1`/`ITEM_TABLE_2`
en `madmix_scr.asm`, no codificadas en la rejilla de losetas --
confirmado con el usuario como fuera de alcance de esta pasada).

Verificado: recompilados ambos binarios tras generar los 16 `.txt` de
rejilla (0 diferencias en `MADMIX1.BIN`, los mismos 4 de siempre en
`MADMIX.SCR` -- generar texto no toca ningún `.bin` ni `.asm`
compilado). El editor HTML se revisó a fondo por código (no hay forma
de tomar una captura de pantalla en este entorno) y se abrió en el
navegador del usuario para que confirme visualmente el pintado/
descarga -- pendiente de su confirmación.


**Ajuste posterior tras confirmar que el editor funciona**: el usuario
pidió bloquear la edición de las 3 cabeceras compartidas
(`header_*.bin`) en `editor_niveles.html` -- al ser puramente
decorativas y compartidas por varios niveles, no tiene sentido
pintarlas ahí. Añadido: pintar/abrir/descargar se deshabilitan cuando
el fichero activo es una cabecera (detectado por el nombre,
`header_*`), con aviso visible en pantalla. También se reportó que el
contador de bolitas no coincide en todos los niveles (ejemplo: nivel
3, 109 contadas vs 120 objetivo) -- verificado con `mmlvl_tool.py
check-bolitas`: es el mismo desajuste ya documentado en la ronda de
offsets 18-19 (comodines `0x3C` sustituidos en tiempo de carga +
posiciones de "bola especial" que no son bytes de loseta), no un bug
nuevo. El editor ahora distingue en el propio contador los niveles
donde SÍ se confirmó coincidencia exacta (1, 8, 10, 12 -- ahí un
desajuste sería una señal real de problema) de los que nunca
coincidieron ni sin editar (el resto, donde el desajuste es esperado
y se marca como tal en vez de en rojo de alarma).


### Decimotercera ronda: misterio cerrado -- las flechas también cuentan como bola

El usuario, probando el editor de niveles, señaló que las losetas de
flecha (tipo "obliga a avanzar en esa dirección") tienen dibujada una
bola y deberían contar en el recuento. Verificado en `madmix_scr.asm`:
los 4 manejadores de flecha (`HANDLER_2F18`/`HANDLER_2F50`/
`HANDLER_2F88`/`HANDLER_2FC0`) hacen exactamente el mismo
`CALL $8D70` (2 puntos) + `INC ($2C08)` que el manejador de bolita
normal -- confirmando que sí, pisar una flecha también cuenta como
"bolita comida". Esto **resuelve del todo** el misterio abierto desde
la sesión de offsets 18-19 ("para los otros 8 niveles la cuenta
directa de losetas NO coincide exacta"): añadiendo las 4 flechas
(`0x33`-`0x36`) al recuento junto a las 3 losetas de bola normal
(`0x2D`-`0x2F`), **los 12 niveles coinciden EXACTO con su objetivo de
`LEVEL_TABLE`, sin ninguna excepción** -- no hacía falta invocar
losetas comodín ni una tabla de "bola especial" adicional, simplemente
faltaban 4 tipos de loseta en el conjunto contado. Corregido
`BALL_TILES` en `tools/mmlvl_tool.py` y `recursos/editor_niveles.html`
(que además ahora marca cualquier desajuste como señal real -- ya no
hay niveles con "desajuste esperado"). Ver también la nota de
resolución añadida directamente en la sección "Descifrados offsets
18-19" más arriba.


### Decimocuarta ronda: niveles 13/14 incorporados al editor (con contexto de solo lectura) + nivel oculto renombrado a "15" (solo etiqueta)

El usuario pidió incorporar los niveles 13 y 14 al editor visual, y
renombrar el nivel oculto a "nivel 15" (aclarando que su enganche real
a `LEVEL_TABLE` sigue sin resolver, tarea explícitamente aparcada).

**Nivel 14, investigado a fondo**: se confirmó que los 36 bytes de
cola que le faltaban a `body_l14_maze.bin` (para completar sus 736
bytes reales, 23×32) son exactamente los primeros 36 bytes de
`data/demos/01_nivel1.dem` (`DEMO_SCRIPT_NIVEL1`, `$D500` en
adelante) -- y que esos 36 bytes **nunca se leen como guión de demo
real**: `LEVELCYCLE_TABLE` (`madmix_scr.asm`) apunta al nivel 1 de
demos en `$D524`, no en `$D500` (`$D524-$D500=$24=36`, exactamente 18
pares de `[duración,dirección]` que el sistema de demos se salta sin
más). Confirmado que ningún otro `CALL`/`LD` en el código transcrito
lee directamente esos 36 bytes -- quedan huérfanos como guión de demo,
igual de "sin consumidor confirmado" que `RM_TABLE_CFA4` para el nivel
13. No hay conflicto real al tratarlos como contexto del nivel 14.

**Verificación numérica combinando el cuerpo completo de cada nivel**
(cabeza/cola prestada + parte propia), contando también las flechas
(ver ronda anterior): **nivel 14 = 267 bolitas contadas, objetivo real
267 -- EXACTO**. **Nivel 13 = 106 contadas, objetivo real 105 -- una
de más**, aislada en los 92 bytes prestados de `RM_TABLE_CFA4` (que ya
sabíamos de identidad incierta) -- no es un fallo del criterio de
conteo (que ya se confirmó exacto en los 12 niveles reales + el 14),
sino una coincidencia numérica en una tabla que probablemente nunca
fue pensada como parte de un nivel.

**Editor (`recursos/editor_niveles.html`)**: los niveles 13 y 14 se
muestran ahora como rejilla COMPLETA (21×32 y 23×32 respectivamente)
para dar contexto visual real, pero con la parte prestada (los
primeros 92 bytes en el 13, los últimos 36 en el 14) sombreada y
bloqueada -- no se puede pintar ahí, y exportar/importar solo afecta
al rango propio de `body_l13_maze.bin`/`body_l14_maze.bin`, en el
mismo formato "plano" (`; bytes=N`) que ya entiende `mmlvl_tool.py`
para estos dos ficheros (sin inventar un formato nuevo). El contador
de bolitas cuenta sobre la rejilla completa (incluida la parte
prestada, porque así es como el juego real la lee), así que el nivel
13 mostrará permanentemente "106 / 105" salvo que se edite la parte
propia para compensar -- documentado en pantalla para que no se lea
como un fallo del editor.

El nivel oculto (`body_hidden_48bc.bin`) se etiqueta ahora en el
desplegable como "nivel 15" con una nota explícita de que es solo
numeración de referencia, sin ningún cambio real en `LEVEL_TABLE` ni
en ningún `.asm` -- el enganche real sigue pendiente y no implementado
a propósito (ver `README.md`, punto pendiente ya documentado).


### Decimoquinta ronda: RM_TABLE_CFA4 y la cola del nivel 14 consolidados como ficheros propios -- y una CORRECCIÓN sobre `niveles.html`

El usuario preguntó por qué bloquear la cabeza del nivel 13
(`RM_TABLE_CFA4`) y la cola del nivel 14 si, en la práctica, ya
funcionan como parte real del cuerpo de esos niveles y nada más las
usa -- editar ahí "machacaría lo mismo que ya se está machacando
ahora". Razonamiento correcto: no hay ningún consumidor confirmado
aparte del nivel correspondiente en ninguno de los dos casos (ya
verificado para `RM_TABLE_CFA4` en la ronda anterior; para la cola del
nivel 14 se confirmó además que `LEVELCYCLE_TABLE` salta esos 36 bytes
a propósito, `$D524` en vez de `$D500`). El único motivo del bloqueo
era mecánico (no eran ficheros propios editables), no de seguridad.

**Consolidado**: `RM_TABLE_CFA4` (92 bytes, antes `DB` inline en
`madmix1.asm`) se extrajo a `data/niveles/body_l13_head_cfa4.bin`
propio, con `INCBIN`. `data/demos/01_nivel1.dem` (100 bytes) se
partió en `data/niveles/body_l14_tail_demo1.bin` (36 bytes, la cola
real del nivel 14) + un `01_nivel1.dem` recortado a los 64 bytes que
sí son guion de demo real (nueva etiqueta
`DEMO_SCRIPT_NIVEL1_REAL_D524` en `$D524`). Verificado: recompilado,
**0 diferencias** en ambos binarios. Ambos ficheros nuevos ya tienen
su `.txt` (`mmlvl_tool.py disasm`), verificados con `roundtrip-all`
(19 ficheros en total ya en `data/niveles/`).

**CORRECCIÓN IMPORTANTE sobre un hallazgo de la ronda anterior**: al
verificar esto se encontró un error propio, no del proyecto. Para
comparar bytes usé `build/MADMIX1.BIN` (mi binario recién compilado)
aplicando la fórmula `direccion - 0x8400 + 7` -- esa fórmula es
correcta SOLO para el `.BIN` **original** del disco (que lleva una
cabecera BLOAD de 7 bytes); `build/MADMIX1.BIN` (la salida de
`sjasmplus`) NO lleva esa cabecera (confirmado: 22945 bytes exactos,
empieza directo en el código real, contra 22952 = 22945+7 del
original). Al aplicar el `+7` de más contra un fichero que ya no lo
necesitaba, todas mis lecturas quedaban desplazadas 7 bytes -- lo que
me llevó a concluir, **erróneamente**, que `recursos/niveles.html`
tenía un bug de "empieza a leer 7 bytes antes" en los niveles 13 y 14.
**Repetida la comprobación leyendo del `.BIN` original** (con la
fórmula `+7` aplicada donde corresponde): `niveles.html` **coincide
exacto** (con el bit 7 enmascarado, que es justo lo que hace su
renderizador) con la reconstrucción real de ambos niveles. No había
ningún bug en `niveles.html` -- se retira esa afirmación.

Esto también invalidaba el recuento de bolitas "106 contra 105" que
se reportó para el nivel 13 en la ronda anterior (calculado con los
mismos datos desplazados). **Recontado con los ficheros ya corregidos
y consolidados: nivel 13 = 105/105 exacto, nivel 14 = 267/267
exacto** -- los 14 niveles reales comprobables (1-12, 13, 14) coinciden
todos sin excepción, sin ninguna anomalía aislada en `RM_TABLE_CFA4`
como se había apuntado por error.

**`recursos/editor_niveles.html` actualizado**: los niveles 13/14 ya
no tienen ninguna zona "sombreada/bloqueada" -- cada uno es una
rejilla completa formada por 2 ficheros propios, AMBOS editables, con
una simple línea de color marcando dónde termina uno y empieza el
otro (solo orientativa, no restrictiva). "Descargar .txt" genera un
fichero por cada parte (mismo formato "plano" que ya usa
`mmlvl_tool.py`); "Abrir .txt" detecta automáticamente a qué parte
pertenece un fichero cargado por su número de bytes declarado.


### Decimosexta ronda: `RM_TABLE_CFA4` NUNCA fue dato de sonido -- renombrada a `BODY_L13_HEAD_CFA4`

El usuario cuestionó la premisa completa detrás de `RM_TABLE_CFA4`: no
solo que no tuviera consumidor confirmado (ya establecido en la ronda
novena), sino que la propia idea de que fuera "una tabla de sonido
reaprovechada/prestada por el nivel 13" pudiera ser, desde el
principio, una deducción nuestra equivocada -- el nombre "RM_TABLE"
viene de una sesión muy antigua que la etiquetó como posible tabla de
envolvente/percusión solo por estar pegada a las tablas de sonido
reales, sin ninguna verificación real. El argumento: es demasiada
coincidencia que sus 92 bytes sean EXACTAMENTE lo que falta para
completar los 672 bytes del cuerpo del nivel 13 (92 aquí +
`BODY_L13_MAZE_D000`, 580 bytes) Y que el contenido decodifique a
losetas con sentido.

**Verificado decodificando los 92 bytes fila a fila** (32 columnas,
catálogo de `data/tiles/*.til`): el resultado NO es ruido ni relleno
-- es una sala de laberinto perfectamente coherente y simétrica
izquierda-derecha: borde completo de `muro_cemento` (esquinas,
paredes horizontales/verticales), interior de `loseta_solida_negra`
con `estrella_pequena/mediana/grande` decorativas en el mismo patrón
que usa el resto de niveles reales, y dos bloques de
`suelo_con_bola`/`suelo_sin_bola` con su `item_bola_poder` a cada
lado -- exactamente la composición de una habitación de nivel real,
no una casualidad de bytes de sonido que "por azar" parecen tiles.

**Conclusión**: el usuario tenía razón. Nunca hubo sonido ahí, ni
siquiera en una versión anterior del driver -- ha sido cabeza del
cuerpo del nivel 13 desde el principio, y el "solape/préstamo con
sonido" que documentamos en rondas anteriores fue una lectura nuestra
equivocada de la proximidad de direcciones, no algo que el juego haga
de verdad.

**Cambios**: la etiqueta `RM_TABLE_CFA4` en `madmix1.asm` se renombró
a `BODY_L13_HEAD_CFA4` (y sus 2 referencias cruzadas, en el comentario
de `BODY_L13_MAZE_D000` y en `madmix_scr.asm` junto al puntero
`$CFA4` de `LEVEL_TABLE`). El comentario que la acompaña se reescribió
para dejar de presentar "sonido reciclado" y "siempre nivel" como dos
hipótesis igual de válidas -- ahora documenta la conclusión con la
evidencia (tamaño exacto + contenido decodificado con sentido) y
mantiene solo la aclaración honesta de que la existencia de una
versión de driver anterior nunca se puede descartar del todo desde el
binario final, aunque ya no tiene ningún peso real frente a la
evidencia de contenido. `recursos/mapa_memoria.html` y `README.md`
actualizados igual (categoría cambiada de "recursos" a "nivel" en el
mapa de memoria).

Recompilado tras el rename: **0 diferencias** en `MADMIX1.BIN`
(fórmula `+7` contra el `.BIN` original) y los mismos **4 diffs
preexistentes de siempre** en `MADMIX.SCR` (offsets ~6388-6390 y el
último byte) -- sin regresión. `recursos/flujo_programa.html`
regenerado (`gen_inventory.py` contra los `.sym` recién compilados):
inventario pasa de 623 a **624** etiquetas (`RM_TABLE_CFA4` quitada,
`BODY_L13_HEAD_CFA4` añadida, y `DEMO_SCRIPT_NIVEL1_REAL_D524` -- una
etiqueta de la ronda anterior que aún no se había incorporado al
inventario -- también añadida); conteos por categoría actualizados a
94 función / 279 interna / 164 dato / 87 sin ref. en el HTML y en
`FLUJO_PROGRAMA.md` §0.


### Decimoséptima ronda: la cola del nivel 14 tampoco fue nunca guion de demo -- unificado en `body_l14.bin`

Mismo razonamiento que la ronda anterior con `RM_TABLE_CFA4`, aplicado
esta vez a los últimos 36 bytes del cuerpo del nivel 14
($D500-$D524, antes `DEMO_SCRIPT_NIVEL1`). El usuario señaló: si
`LEVELCYCLE_TABLE` siempre ha apuntado a $D524 y nunca a $D500, y la
demo funciona bien empezando ahí, entonces esos 36 bytes nunca
estuvieron en la práctica como guion de demo -- la idea de que fueran
"guion real desplazado" fue una deducción nuestra de una sesión
antigua, al ir descubriendo las piezas del puzzle sin ver aún el
cuadre completo.

**Verificado en `LEVELCYCLE_TABLE`** (`madmix_scr.asm`, `$60D0`):
`DB $01,$24,$D5,...` -- el puntero del nivel 1 SIEMPRE ha sido
literal `$D524`, no hay ninguna versión ni variante que apunte a
`$D500`. No existe, por tanto, ningún "guion real que empieza en
$D500 y se lee desde la mitad" -- esa lectura (presente en comentarios
de sesiones anteriores) invertía la causalidad: no es que el guion
empiece en $D500 y el puntero salte 36 bytes por alguna razón; es que
el guion SIEMPRE empezó en $D524, y $D500-$D524 nunca perteneció al
guion en absoluto.

**Consolidado**: `data/niveles/body_l14_maze.bin` (700 bytes, cabeza)
+ `body_l14_tail_demo1.bin` (36 bytes, cola) se combinan en un único
fichero nuevo, `data/niveles/body_l14.bin` (736 bytes = 23×32,
rejilla completa), con su `.txt` gemelo en formato rejilla (ya no
plano). Los dos ficheros antiguos y sus `.txt` se eliminan. En
`madmix1.asm`: `BODY_L14_MAZE_D244` + `DEMO_SCRIPT_NIVEL1` (en
`$D500`) se sustituyen por una única etiqueta `BODY_L14_D244` con un
solo `INCBIN`; la etiqueta `DEMO_SCRIPT_NIVEL1_REAL_D524` se renombra
a `DEMO_SCRIPT_NIVEL1` (ya no hace falta el sufijo "REAL", porque ya
no hay ningún otro `DEMO_SCRIPT_NIVEL1` con el que confundirse) y
queda en su dirección real, `$D524`. También se corrigió el bloque de
comentario grande que documentaba "0xD500-0xD6B6 (438 bytes): 10
guiones de demo" -- pasa a describir correctamente "0xD524-0xD6B6
(402 bytes)", sin la frase (ya inexacta) de que el puntero del nivel
1 "cae a mitad del guion real". El comentario de `LEVELCYCLE_TABLE`
en `madmix_scr.asm` se corrigió igual.

Recompilado tras la reestructuración: **0 diferencias** en
`MADMIX1.BIN` y los mismos **4 diffs preexistentes** en `MADMIX.SCR`
-- sin regresión. `recursos/flujo_programa.html` regenerado: el
inventario baja de 624 a **623** etiquetas (consolidación neta de 1
etiqueta menos: se quitan `BODY_L14_MAZE_D244` y
`DEMO_SCRIPT_NIVEL1_REAL_D524`, se añade `BODY_L14_D244`, y
`DEMO_SCRIPT_NIVEL1` pasa a referirse a `$D524` en vez de `$D500`);
conteos por categoría de vuelta a 94/279/163/87.

`recursos/editor_niveles.html` actualizado: la entrada "nivel14
combinado" (2 segmentos, con línea de separación) pasa a ser una
entrada normal de un solo fichero (`body_l14.bin`), igual que
cualquier otro nivel -- ya no hay ninguna zona ni línea de "partes"
en el nivel 14, exactamente lo que le pasó también al nivel 13 con
`BODY_L13_HEAD_CFA4`, salvo que el nivel 13 SÍ sigue siendo 2
ficheros reales en disco (`body_l13_head_cfa4.bin` + `body_l13_maze.bin`,
sección de comentario propia) porque ahí no hay ninguna razón para
fusionarlos en uno solo más allá de la comodidad -- se mantienen
separados por ahora. `README.md` y `recursos/mapa_memoria.html`
actualizados para reflejar la nueva estructura (rango
0xD244-0xD524 = cuerpo completo del nivel 14; rango 0xD524-0xD6B6 =
10 guiones de demo, 402 bytes).


### Decimoctava ronda: los dos ficheros del nivel 13 también se unifican en uno solo

Cierre simétrico de las dos rondas anteriores: si `BODY_L13_HEAD_CFA4`
(decimosexta ronda) nunca fue dato de sonido y `DEMO_SCRIPT_NIVEL1`
(decimoséptima ronda) nunca fue guion de demo -- ambos siempre fueron,
en la práctica, simplemente partes del cuerpo de su nivel -- no queda
ninguna razón real para seguir manteniendo esas partes en ficheros
separados. A diferencia de la corrección del nivel 14 (que corrigió
una lectura de direcciones objetivamente equivocada), aquí no hay
ningún hecho nuevo que corregir: es una simplificación de conveniencia
una vez que la premisa que justificaba la separación ("una de las dos
mitades es contexto de otra tabla") quedó descartada del todo.

**Consolidado**: `data/niveles/body_l13_head_cfa4.bin` (92 bytes) +
`body_l13_maze.bin` (580 bytes) se combinan en un único fichero
nuevo, `data/niveles/body_l13.bin` (672 bytes = 21×32, rejilla
completa), con su `.txt` gemelo en formato rejilla (ya no plano). Los
dos ficheros antiguos y sus `.txt` se eliminan. En `madmix1.asm`:
`BODY_L13_HEAD_CFA4` + `BODY_L13_MAZE_D000` se sustituyen por una
única etiqueta `BODY_L13_CFA4` con un solo `INCBIN`, y el comentario
que las acompañaba se fusiona en uno solo que documenta ambas
correcciones (descarte de la hipótesis de sonido + unificación).
`madmix_scr.asm` (comentario junto al puntero `$CFA4` de
`LEVEL_TABLE`) actualizado igual.

Recompilado: **0 diferencias** en `MADMIX1.BIN` y los mismos **4
diffs preexistentes** en `MADMIX.SCR` -- sin regresión.
`recursos/flujo_programa.html` regenerado: el inventario baja de 623
a **622** etiquetas (se quitan `BODY_L13_HEAD_CFA4` y
`BODY_L13_MAZE_D000`, se añade `BODY_L13_CFA4`); conteos por
categoría 94/279/162/87. `recursos/editor_niveles.html` actualizado:
la entrada "nivel13 combinado" (2 segmentos, con línea de separación)
pasa a ser una entrada normal de un solo fichero (`body_l13.bin`),
igual que el resto de niveles -- ya no queda ningún nivel con más de
un segmento en el editor (el mecanismo de segmentos múltiples se deja
en el código por si algún fichero futuro lo necesitara, pero ningún
nivel actual lo usa). `README.md` y `recursos/mapa_memoria.html`
actualizados: el rango `0xCFA4-0xD244` pasa a describirse como un
único bloque, "cuerpo COMPLETO del nivel 13".

Con esto, los 15 registros de `LEVEL_TABLE` apuntan todos a un
cuerpo de nivel contenido en un único fichero real de `data/niveles/`
(o, para los 12 niveles normales + el oculto, dentro del bloque
contiguo de `MADMIX.SCR`) -- ya no queda ningún nivel documentado como
"partido en varias partes por razones históricas".


### Decimonovena ronda: `INSTRUMENT_TABLE_CA6A`, `ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_TABLE_CB72` y `SUBPATTERN_BYTECODE_CB9C` reformateadas para que las filas del `DB` cuadren con la geometría de sus comentarios

El usuario señaló que `INSTRUMENT_TABLE_CA6A` decía "16 instrumentos x
15 bytes" pero estaba volcada en `madmix1.asm` como un volcado
hexadecimal de 16 bytes por línea, sin ninguna relación con los
límites reales de cada instrumento (15 bytes) -- y que
`ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_TABLE_CB72` y
`SUBPATTERN_BYTECODE_CB9C` tenían el mismo problema.

**`INSTRUMENT_TABLE_CA6A`** (ya corregida en la ronda anterior a
petición similar): confirmado con código, no solo aritmética
(240/16=15) -- `SET_INSTRUMENT` calcula `HL=indice*15` con `RM_C88D`
(multiplicación 8x16) y copia exactamente `D=$0F=15` bytes desde
`$CA6A+HL`. Reformateada a 16 filas de 15 bytes, una por instrumento.

**`ENV_SHAPE_TABLE_CB5A`** (24 bytes, comentario "4 entradas x 6
bytes"): reformateada a 4 filas de 6 bytes, una por forma de
envolvente.

**`SUBPATTERN_TABLE_CB72`** (42 bytes, "21 punteros de 16 bits"):
antes en filas de 6/8/7 punteros (bytes correctos, pero sin relación
con las 21 entradas declaradas). Reformateada a `DW` con **una
entrada por línea** -- y, siguiendo la convención ya usada en
`ML_DISPATCH_TABLE` (`madmix_scr.asm`), con **etiquetas reales** en
vez de hex literal, para que el propio ensamblador resuelva las
direcciones.

**`SUBPATTERN_BYTECODE_CB9C`** (559 bytes, "13 subpatrones
compartidos"): este caso era más profundo -- el bytecode de cada
subpatrón es de tamaño VARIABLE (no son registros fijos), así que
"cuadrar la geometría" significaba partir el volcado exactamente en
los 13 límites reales, no solo cambiar el ancho de fila. Calculados
los 13 límites a partir de las direcciones únicas de
`SUBPATTERN_TABLE_CB72` (12 en orden de tabla + la entrada 12,
`$CBB0`, que en memoria cae ANTES que la entrada 1 -- confirmado con
un script: 13 direcciones únicas ordenadas por memoria sí sumas
exactos 559 bytes sin huecos ni solapes) se generaron 12 etiquetas
nuevas (`SUBPATTERN_CBB0`, `SUBPATTERN_CBD3`, ... `SUBPATTERN_CDAB`;
la entrada 0, en `$CB9C`, usa directamente `SUBPATTERN_BYTECODE_CB9C`,
sin etiqueta propia duplicada). **Verificación fuerte del propio
modelo del bytecode**: los 13 fragmentos así delimitados terminan
TODOS, sin excepción, en `$8D` (comando 13, RETURN_SUBPATTERN) --
confirmación independiente de que las direcciones del puntero y la
semántica del bytecode encajan perfectamente.
`SUBPATTERN_TABLE_CB72` se reescribió con `DW` apuntando a estas 12
etiquetas nuevas + `SUBPATTERN_BYTECODE_CB9C` para la entrada 0 y las
8 repeticiones (entradas 13-20).

Las cuatro tablas se generaron con un script Python que extrajo los
bytes crudos de las filas actuales, verificó las sumas de longitud
contra los tamaños declarados en los comentarios, y regeneró el `DB`/
`DW` alineado a los límites reales -- ningún byte de datos cambió, solo
el formato de las líneas de origen y la introducción de etiquetas
nuevas donde no las había.

Recompilado: **0 diferencias** en `MADMIX1.BIN` en cada paso
intermedio (uno por tabla) y al final. `recursos/flujo_programa.html`
regenerado: 622 → **634** etiquetas (12 nuevas `SUBPATTERN_*`);
conteos por categoría 94/279/174/87. De paso se corrigió un efecto
colateral en `gen_inventory.py`/el propio inventario:
`SUBPATTERN_BYTECODE_CB9C` había quedado mal clasificada como "sin
ref." en un paso intermedio (por tener otra etiqueta apilada en la
misma dirección justo debajo, rompiendo la heurística "siguiente
línea es DB/DW") -- resuelto al no duplicar la etiqueta de la entrada
0. `FLUJO_PROGRAMA.md` y `README.md` actualizados con el nuevo
recuento.


### Vigésima ronda: los 13 subpatrones compartidos, extraídos a `data/sound/*.spt` (misma herramienta que los `.snd`)

El usuario preguntó si los 13 subpatrones (ver ronda anterior) usan
el mismo bytecode que los `.snd` de eventos y si serían compatibles
con `mmsnd_tool.py`/`mmsnd_render.py` -- y si tendría sentido
extraerlos también a ficheros propios con extensión distinta.

**Verificado antes de tocar nada** (extrayendo los 13 rangos de bytes
y pasándolos por `disassemble()`/`assemble()` de `mmsnd_tool.py` sin
ningún cambio de código): los 13 hacen roundtrip exacto, mismo
lenguaje de 15 comandos, decodificación legible (`SET_INSTRUMENT`,
`SET_VOLUME`, ..., `RETURN_SUBPATTERN`). En `mmsnd_render.py` el
intérprete YA soporta `CALL_SUBPATTERN`/`RETURN_SUBPATTERN` por
completo (así reproduce hoy la música de arranque, que llama
subpatrones constantemente), y un `RETURN_SUBPATTERN` suelto sin
llamada previa (`ch.return_addr is None`) ya se resuelve como "fin de
script" sin error -- pero el manifiesto `SCRIPT_ADDR` de `render()`
no incluye los subpatrones todavía, así que reproducirlos SUELTOS
desde la CLI no funciona sin extender ese manifiesto (no implementado
esta ronda, documentado como pendiente).

**Extraídos**: los 13 subpatrones a `data/sound/*.spt` (extensión
elegida por el usuario para no mezclarlos con los 16 `.snd` reales de
evento/música), nombrados por su índice de entrada en
`SUBPATTERN_TABLE_CB72` (00-12) más su dirección --
`00_subpatron00_cb9c.spt` .. `12_subpatron12_cbb0.spt` (la entrada 12
cae en `$CBB0`, en memoria ANTES que la entrada 1, ver ronda
anterior). Cada uno con su `.txt` gemelo generado con
`mmsnd_tool.py disasm`. `mmsnd_tool.py roundtrip-all` extendido para
recorrer también `.spt` además de `.snd` (una línea de código); los
29 ficheros de `data/sound/` (16 `.snd` + 13 `.spt`) pasan roundtrip
exacto.

El aviso de cabecera de los `.txt` (`WARNING_BANNER`, ahora
`warning_banner(path)`) se hizo consciente de la extensión: para
`.snd` sigue señalando `LEVELCYCLE_RESOURCE_TABLE` (`madmix_scr.asm`)
como consumidor con dirección fija; para `.spt` señala correctamente
`SUBPATTERN_TABLE_CB72` (`madmix1.asm`) -- son tablas de punteros
distintas, y el aviso genérico anterior habría señalado la tabla
equivocada para un `.spt`.

En `madmix1.asm`: los 13 bloques `DB` (ya reformateados en la ronda
anterior con límites correctos) se sustituyeron por `INCBIN` a los
`.spt` nuevos, sin tocar las 13 etiquetas ya existentes
(`SUBPATTERN_BYTECODE_CB9C`/`SUBPATTERN_CBB0`/etc. -- mismas
direcciones). Recompilado: **0 diferencias** en `MADMIX1.BIN`.
`recursos/flujo_programa.html` regenerado: mismo total de etiquetas
(634, ninguna añadida/quitada -- solo cambia de qué línea del fuente
vienen). `_engine_tables.bin` (copia de trabajo para el renderizador)
NO necesitó regenerarse: sigue conteniendo los mismos bytes en
`$C8DE-$CDCB` (incluidos los 13 subpatrones), ya que el cambio fue
solo de dónde vienen esos bytes en el `.asm`, no de su contenido.

`README.md` actualizado: nueva entrada en el árbol de `data/sound/`
para los `.spt`, aviso de tamaño fijo extendido para cubrirlos
(mencionando su consumidor real, `SUBPATTERN_TABLE_CB72`), y
corregida la descripción de `_engine_tables.bin` (ya no dice que los
subpatrones "siguen siendo DB inline" -- ahora son `INCBIN` desde
`.spt`, aunque la copia del renderizador sigue siendo válida sin
cambios porque los bytes finales son idénticos).


### Vigesimoprimera ronda: `data/sound/` organizada en `snd/` y `spt/`, y WAV de referencia para los 13 subpatrones

Con los `.snd` (16 scripts reales) y los `.spt` (13 subpatrones,
ronda anterior) conviviendo sueltos en el mismo directorio, el
usuario pidió organizarlos en subcarpetas propias por tipo:
`data/sound/snd/` y `data/sound/spt/`. `_engine_tables.bin` (copia de
trabajo para el renderizador, no pertenece a ningún grupo -- mezcla
tono/instrumentos/envolvente con los propios subpatrones) se queda en
la raíz de `data/sound/`.

**Movidos**: los 16 `.snd`+`.txt` a `data/sound/snd/`, los 13
`.spt`+`.txt` a `data/sound/spt/`. **`madmix1.asm`** actualizado: las
26 rutas `INCBIN "data/sound/..."` pasan a `INCBIN "data/sound/snd/..."`
/ `"data/sound/spt/..."` según corresponda. Recompilado: **0
diferencias** en `MADMIX1.BIN`.

**`tools/mmsnd_render.py`** actualizado para el nuevo layout:
`load_memory()` ahora busca los 16 scripts reales en
`data/sound/snd/` (antes en `data/sound/` directamente). Se añadió un
manifiesto nuevo, `SUBPATTERN_ADDR` (nombre de fichero `.spt` ->
dirección real, los mismos 13 valores ya usados en `madmix1.asm`) --
a diferencia de los scripts reales, los subpatrones NO se pegan aparte
en `load_memory()` (ya viven dentro de `_engine_tables.bin`, que cubre
`$C8DE`-`$CDCB` completo), así que solo hacía falta enseñarle a
`render()` su dirección de inicio. `render()` ahora comprueba primero
`SCRIPT_ADDR` y si no está, `SUBPATTERN_ADDR` (usando el propio
tamaño del fichero `.spt` en disco como límite de fin -- de todos
modos el final real siempre lo marca el `RETURN_SUBPATTERN` de cada
uno, ya verificado que un `RETURN_SUBPATTERN` sin llamada previa
termina la reproducción sin error). `render-all` extendido igual para
reconocer `.spt` además de `.snd`.

**Generados los 13 WAV de referencia** en `build/sound_preview/`
(mismo sitio que los 16 `.snd`, con `py tools/mmsnd_render.py
render-all data/sound/spt/ build/sound_preview/`): duraciones entre
0.02 s y 0.64 s, todos renderizados sin error. Confirmado también que
los 16 `.snd` se siguen renderizando exactamente igual tras el cambio
de carpeta (`render-all data/sound/snd/ build/sound_preview/`,
mismas duraciones que antes de la reorganización) y que
`mmsnd_tool.py roundtrip-all` sigue pasando limpio apuntando a cada
subcarpeta por separado.

De paso se corrigió una imprecisión en el aviso de cabecera de los
`.txt` generados por `mmsnd_tool.py` (`WARNING_BANNER`, convertido en
`warning_banner(path)`): antes citaba siempre
`LEVELCYCLE_RESOURCE_TABLE` como el consumidor con dirección fija,
que es correcto para `.snd` pero NO para `.spt` (cuyo consumidor real
es `SUBPATTERN_TABLE_CB72`, en `madmix1.asm`, no `madmix_scr.asm`) --
ahora el aviso nombra la tabla correcta según la extensión del
fichero.

`README.md` (árbol de `data/sound/` con las dos subcarpetas) y
`manuales/manual_driver_sonido.md` (rutas actualizadas, nuevo párrafo
en §6.8 sobre los ficheros/WAV de los subpatrones) actualizados.


### Vigesimosegunda ronda: `CMD_JUMP_TABLE_C99E` reformateada a 15 filas, una por comando, con su nombre/efecto en el comentario

Mismo tipo de ajuste que las rondas anteriores sobre las demás tablas
del driver de sonido: `CMD_JUMP_TABLE_C99E` (30 bytes, 15 punteros de
16 bits, uno por comando del bytecode `$80`-`$8E`) estaba volcada en
dos líneas de 16/14 bytes sin relación con sus 15 entradas reales.
Reformateada a 15 líneas `DW`, una por comando, cada una con el
número de comando, el opcode, el nombre y un resumen de su efecto
mecánico -- tomado directamente de la tabla ya verificada en
`FINDINGS.md` ("Los 15 comandos"), con referencias cruzadas a las
etiquetas reales que cada comando consulta/modifica
(`INSTRUMENT_TABLE_CA6A`, `SHARED_ENVELOPE_TABLE_CA53`,
`ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_RETURN_TABLE_CA61`,
`SUBPATTERN_TABLE_CB72`, `TRANSPOSE_TABLE_CA67`). No se crearon
etiquetas nuevas para las 15 direcciones de destino (`$C6E5` etc. --
son puntos intermedios dentro de rutinas ya etiquetadas más arriba en
el fichero, `RM_C6xx`/`RM_C7xx`, no hay un punto de entrada propio
que etiquetar sin invadir ese bloque ya disecado); la tabla sigue
usando direcciones hex literales, igual que antes, solo reorganizadas
por fila.

Recompilado: **0 diferencias** en `MADMIX1.BIN`. `recursos/flujo_programa.html`
regenerado: mismo total de etiquetas (634, ninguna añadida/quitada --
puro cambio de formato de fuente).


### Vigesimotercera ronda: `RM_TABLE_C8DE` (tabla de periodos de tono, 96 notas) reformateada a una fila por nota

Mismo ajuste que las tres rondas anteriores, ahora sobre la última
tabla del driver de sonido que quedaba como volcado hexadecimal sin
relación con su propia geometría: `RM_TABLE_C8DE` (192 bytes = 96
palabras, nota+transposición → periodo de tono del PSG) estaba en 12
líneas de 16 bytes. Reformateada a 96 líneas `DW`, una por nota (0-95),
cada una con el valor decodificado en hex y en decimal.

**Verificación adicional de paso**: los 96 valores son estrictamente
monótonos decrecientes (el periodo baja según sube el índice de
nota) -- confirmado programáticamente sobre los 96, no solo a ojo.
Es exactamente el patrón esperado de una escala cromática ascendente
(periodo de PSG inversamente proporcional a la frecuencia), y refuerza
la lectura ya establecida en una sesión anterior de que esta tabla es
nota→periodo, no duración (ver FINDINGS.md, "CORRECCIÓN IMPORTANTE...
el byte <0x80 NO es una duración, es la NOTA"). No se han asignado
nombres de nota musical (C, C#, D...) a cada fila -- harían falta
datos adicionales (referencia de afinación/octava) que no están
verificados en este proyecto; el comentario se limita al índice
numérico (0-95) y el periodo, que es lo único confirmado por código.

Recompilado: **0 diferencias** en `MADMIX1.BIN`. Ninguna etiqueta
añadida ni quitada (634 igual que antes) -- puro cambio de formato de
fuente. Con esto las 4 tablas del driver de sonido que tenían volcados
hexadecimales sin relación con su geometría documentada
(`INSTRUMENT_TABLE_CA6A`, `ENV_SHAPE_TABLE_CB5A`, `SUBPATTERN_TABLE_CB72`,
`CMD_JUMP_TABLE_C99E`, y ahora `RM_TABLE_C8DE`) están todas alineadas.


### Vigesimocuarta ronda: aplicado el fix real del bug de nivel 13/14 -- unica desviacion deliberada de la v1.0 en todo el proyecto

Tras localizar con precision los 5 sitios reales del fix de la v2.0
(ver ronda anterior: 2 en `madmix1.asm` ya conocidos --
`TILE_ADDR_CALC`/`0x8BE5`, `MAP_COORD_TO_ADDR`/`0x8CD4` -- y 3 nuevos
en `madmix_scr.asm` -- `COORD_TO_ADDR`/`0x5474`,
`COORD_TO_ADDR_LOCAL`/`0x556F`, `LEVEL_LOADER`/`0x591A`) y descartar
que el codigo nuevo de `$C9BC` o el cambio de `SP` tuvieran ningun
mecanismo de ejecucion real conectado (ver ronda anterior: ninguna
llamada, ni vieja ni nueva, apunta a `$C9BC-$CA73` en todo el juego
residente), el usuario pidio aplicar el fix real a nuestro fuente:
**`$FC60` -> `$FC50` en los 5 sitios**.

Esto es la **primera y unica desviacion deliberada** de la
reproduccion byte a byte de la v1.0 original en todo el proyecto --
hasta ahora la disciplina siempre habia sido "reproducir la v1.0 tal
cual es, bugs incluidos, no arreglarla" (ver rondas anteriores sobre
el nivel oculto, el bug de `$FC60`, etc.). Se aplico explicitamente a
peticion del usuario, con el mecanismo ya confirmado (no una
conjetura): el buffer de nivel activo (`$FC60`) es demasiado pequeno
para el cuerpo mas grande del nivel 14, y por eso el contador de
bolitas del nivel 13 nunca completaba bien -- moviendo el buffer 16
bytes antes (`$FC50`) en los 5 sitios donde esta grabado como numero
magico se soluciona, exactamente como lo hizo la reedicion v2.0
(CAS/ROM homebrew de 2013, "arreglado por Manuel Pazos en 2013" segun
sus propios creditos).

**Documentado en el propio codigo**: cada uno de los 5 sitios lleva
ahora un comentario "BUG CORREGIDO" explicando el valor original
(`$FC60`), el motivo, y una referencia cruzada a los demas sitios;
ademas se añadio una nota al principio de ambos ficheros
(`madmix1.asm`/`madmix_scr.asm`) marcando esta como la unica
desviacion deliberada de toda la reconstruccion.

**Verificado**: recompilados ambos ficheros, diff byte a byte contra
los binarios originales de la v1.0:
- `MADMIX1.BIN`: **exactamente 2 diferencias**, en `$8BE5` y `$8CD4`
  (`$60`->`$50`), ninguna otra -- confirma que el cambio no tuvo
  ningun efecto colateral en el resto del motor.
- `MADMIX.SCR`: **exactamente 7 diferencias** -- las 4 ya conocidas y
  sin relacion (`$28ED-$28EF` y el byte suelto de `$6500`) mas las 3
  nuevas esperadas (`$5474`, `$556F`, `$591A`, tambien `$60`->`$50`),
  ninguna mas.

`README.md` actualizado: la afirmacion de "0 diferencias salvo 4
bytes ajenos" ahora documenta explicitamente estos 5 bytes adicionales
como corregidos a proposito, dejando claro que es la unica excepcion
a la regla de reproduccion fiel del proyecto.

**Pendiente si se retoma**: generar un `build/madmix_reconstruido.dsk`
nuevo con esta version corregida (el que ya existe en `build/` es de
antes de este fix) si el usuario quiere probarla en openMSX.


### Vigesimoquinta ronda: `madmix1.asm` + `madmix_scr.asm` unificados en `main.asm` -- llamadas cruzadas ahora usan etiquetas reales, y nuevo fichero para la version de cinta

`madmix1.asm` y `madmix_scr.asm` se compilaban por separado, sin
enlazador -- cualquier llamada/puntero de un fichero a otro no podia
usar una etiqueta real, quedaba como hex literal con el nombre real
en un comentario (~45 sitios en `madmix_scr.asm` hacia `madmix1.asm`,
~15 en la direccion contraria, mas los punteros de `LEVEL_TABLE` de
los niveles 13/14). El usuario pidio unificar ambos para resolver
esto, y que la misma compilacion generara ademas un fichero para la
version de cinta -- verificado en la ronda anterior que el `.cas`
real concatena sus bloques SIN relleno (cada bloque lleva su propia
direccion de destino en la cabecera).

**Hallazgo clave que simplifico la implementacion**: `madmix_scr.asm`
ya usaba `PHASE $1000` sobre `ORG $8800` fisico -- las direcciones
LOGICAS (con las que se resuelven `CALL`/`JP`/punteros) ya eran
`$1000+`, identicas a como cargaria la cinta el mismo contenido
directamente. Los bytes ensamblados del cuerpo real son EXACTAMENTE
los mismos para disco y cinta -- no hizo falta ensamblar nada dos
veces, solo volcar (`SAVEBIN`) el mismo contenido ya ensamblado con
distinto framing.

**Arquitectura implementada**:
- `madmix1_body.asm` / `madmix_scr_body.asm` (nuevos, contenido
  movido desde los ficheros antiguos): solo etiquetas+codigo+datos,
  sin `DEVICE`/`ORG`/cabecera BLOAD/`PHASE`/`DEPHASE`/`SAVEBIN`.
  Unica colision de nombre encontrada entre ambos (verificada
  programaticamente comparando el conjunto completo de etiquetas de
  nivel superior): `END_OF_FILE` -- renombrada `END_OF_FILE_M1` /
  `END_OF_FILE_SCR`.
- `main.asm` (nuevo, punto de entrada real): `INCLUDE` de ambos
  cuerpos en una sola pasada -- comparten un unico espacio de
  simbolos. Genera `build/MADMIX1.BIN` y `build/MADMIX.SCR` (mismo
  `ORG`/`PHASE`/cabecera BLOAD que antes, ahora sobre el contenido
  incluido) y ademas `build/madmix_cas_scr.bin` (el mismo cuerpo
  logico de `MADMIX.SCR`, sin cabecera, para cinta).
- `madmix0.asm`: sin tocar, se sigue compilando aparte (exclusivo de
  disco, sin referencias cruzadas con los otros dos).

**Detalle tecnico real encontrado al implementar** (no trivial, vale
la pena dejarlo anotado): dentro de un bloque `PHASE`, `$` es la
direccion LOGICA simulada, pero `SAVEBIN` recupera bytes por la
posicion FISICA real donde SjASMPlus los escribio en su mapa de
memoria interno -- un primer intento de `SAVEBIN ..., $1000, ...`
(la direccion logica) devolvio 21760 ceros, porque nunca se escribio
nada realmente en la direccion fisica `$1000` (los bytes fisicos del
cuerpo de `MADMIX.SCR` viven en `$8807` en adelante, justo tras la
cabecera BLOAD en `$8800`). Corregido anadiendo una etiqueta
`SCR_BODY_START_PHYS` justo ANTES de `PHASE $1000` (fuera del
bloque, en direccion fisica real) y usando esa etiqueta como base del
`SAVEBIN` de cinta. Tambien se verifico, con una prueba minima antes
de tocar ninguna referencia cruzada, que SjASMPlus SI permite que dos
secciones `ORG` dentro de la misma pasada ocupen rangos de direccion
fisica solapados (`madmix1_body.asm` en `$8400-$DDA0` fisico y
`madmix_scr_body.asm` en `$8800-$DD00` fisico coexisten sin error --
tiene sentido: en la maquina real tampoco coexisten a la vez, `MADMIX.SCR`
ocupa esa zona transitoriamente antes de reubicarse y ser
sobreescrita por el motor).

**Sustitucion de hex por etiquetas**: generada y aplicada
automaticamente cruzando cada `CALL`/`JP`/`JR` con direccion hex
fuera del rango propio de cada cuerpo contra el `.sym` unificado
(`build/main.sym`) -- 68 sustituciones en `madmix_scr_body.asm`, 17
en `madmix1_body.asm`, mas los 2 punteros de `LEVEL_TABLE` (nivel
13/14, ahora `DW BODY_L13_CFA4, ...`/`DW BODY_L14_D244, ...`
directos). Quedan exactamente 3 direcciones sin convertir, a
proposito: `$2C36` (x2, ya documentado como "llamada a RAM, no
codigo estatico, sin identificar") y `$0040` (vector de sistema,
`JP $0040`) -- ninguna de las dos es una etiqueta de codigo real, no
se pueden ni se deben convertir.

**Verificado en cada paso** (mecanica primero, sustitucion despues,
LEVEL_TABLE al final): recompilado y byte-diff contra el `.dsk`
original tras cada tanda -- **siempre exactamente 2 diferencias en
`MADMIX1.BIN`** (`$8BE5`/`$8CD4`, el fix `$FC60`->`$FC50` ya
aplicado) **y 7 en `MADMIX.SCR`** (las 4 ya conocidas sin relacion +
las 3 del mismo fix) -- ni una diferencia mas, ni una menos, en
ningun momento del proceso. `build/madmix_cas_scr.bin` verificado
byte a byte identico a `MADMIX.SCR` sin sus 7 bytes de cabecera
(0 diferencias, 21760 bytes).

**Nuevo**: `tools/gen_cas_bin.py` concatena `madmix_cas_scr.bin` +
`MADMIX1.BIN` (sin relleno) en `build/madmix_cas.bin` (44705 bytes)
mas un manifiesto de texto (`build/madmix_cas.bin.txt`) con los 2
destinos/longitudes reales. Pendiente, fuera de alcance de esta
ronda: empaquetar esos 2 tramos en bloques de cinta reales (marcas
de sincronismo, checksum) y reconstruir `LOAD.BIN`/`TEST.BIN` (el
cargador de cinta, hoy solo analizado por lectura) como fuente propia.

**Ficheros eliminados** (contenido movido, ya no top-level
compilables): `madmix1.asm`, `madmix_scr.asm`. `README.md`
actualizado (introduccion, arbol de ficheros, seccion "Compilar",
~20 referencias descriptivas sueltas a los nombres antiguos).

**Seguimiento pendiente, no resuelto en esta ronda**:
`tools/gen_inventory.py` asume 3 `.sym` separados (uno por fichero)
para clasificar cada etiqueta por "fichero de origen" en el
inventario de `flujo_programa.html`. Con `main.asm` unificando dos de
los tres en un solo `.sym` (`build/main.sym`), ese script necesitaria
decidir el "fichero" de cada etiqueta por RANGO DE DIRECCION en vez
de por `.sym` de origen -- `recursos/flujo_programa.html` NO se ha
regenerado en esta ronda, sigue reflejando la clasificacion de antes
de la unificacion (los nombres/direcciones de las etiquetas siguen
siendo correctos, solo la generacion automatica del inventario
quedaria desactualizada si se necesitara volver a correr
`gen_inventory.py` tal cual esta hoy).


### Vigesimosexta ronda: cargadores completos de disco y cinta reconstruidos en `load_disk/`/`load_cas/`, integrados en `main.asm`

El usuario creo `src/load_disk/` y `src/load_cas/` (vacias) pidiendo
reconstruir todo lo especifico de cada version -- cargador de disco
(`madmix0.asm`, `.bas`) y cargador de cinta (`LOAD.BIN`/`TEST.BIN`,
`.bas`, el logo de Topo Soft) -- de forma que una unica compilacion
de `main.asm` genere absolutamente todo. `LOGOTOPO.CM` (el logo,
4253/4254 bytes, nunca analizado) se dejo explicitamente fuera
("Organizar todo excepto el logo", decision explicita del usuario).

**Primer paso, validacion tecnica previa a escribir nada real**:
`TEST.BIN` (cinta) vive en `$C350`, direccion que ya usa
`madmix1_body.asm` (driver de sonido, estatico, sin `PHASE`) -- a
diferencia del solape SCR/M1 ya validado (dos *representaciones*
distintas, fisica vs. fase), aqui serian dos contenidos NO
relacionados en la MISMA direccion fisica. Prueba minima (`ORG`
solapado con un segundo `ORG` interior, cada uno con su propio
`SAVEBIN`): confirmado que `SAVEBIN` captura una foto del buffer
fisico en el momento de su propia llamada, en ORDEN DE FUENTE, no
"el ultimo que escribe gana" globalmente -- si el `SAVEBIN` de un
bloque se ejecuta ANTES de que otro bloque posterior reescriba esa
misma direccion, el primero conserva su contenido intacto. Consecuencia
practica: en `main.asm`, el bloque de `MADMIX1.BIN` debe ir ANTES que
el de `TEST.BIN` -- asi el `SAVEBIN` del motor ya capturo el driver de
sonido real en `$C350` antes de que `TEST.BIN` reutilice esa misma
direccion fisica (exactamente como en la maquina real: `TEST.BIN` la
ocupa transitoriamente al arrancar por cinta, luego el motor la
sobreescribe al cargarse).

**`madmix0.asm` -> `load_disk/madmix0_body.asm`**: movido siguiendo
el mismo patron `_body.asm` que el motor/pantalla (contenido sin
`DEVICE`/`ORG`/cabecera/`SAVEBIN`), con sus dos `CALL`/`JP` internos
ahora usando etiquetas compartidas (`PORTADA_INIT`, `START`) en vez
de `$1000`/`$8400`. **Error real cometido y corregido durante esta
ronda**: la cabecera BLOAD (`DW start,end,exec`) de `MADMIX0.BIN` NO
puede usar la etiqueta `RELOCATOR` como base -- BLOAD descarta los 7
bytes de cabecera antes de situar los datos en RAM, asi que la dir.
de carga REAL declarada en el fichero es `$FA00` (la posicion de la
propia cabecera), no `$FA07` (donde `RELOCATOR` cae fisicamente en
NUESTRO ensamblado, que si incluye la cabecera fisicamente antes del
cuerpo). Usar la etiqueta produjo primero un fichero de 51 bytes (le
faltaba la cabecera entera) y despues, tras corregir el `SAVEBIN`,
3 bytes de cabecera erroneos (calculados con un offset de +7 respecto
a los correctos). Solucion: cabecera con constantes literales
(`DW $FA00, $FA32, $FA00`, igual que el `madmix0.asm` original),
`SAVEBIN` con una etiqueta `MADMIX0_HEADER_START` colocada DENTRO del
`ORG` (no antes -- otro error de una sola linea, corregido en el
acto: una etiqueta puesta antes de un `ORG` toma la direccion previa
al `ORG`, no la nueva). Verificado 0 diferencias en los 58 bytes
completos tras corregir ambos fallos.

**`LOAD.BIN`/`TEST.BIN` (cinta) reconstruidos por primera vez como
fuente propia**: hasta ahora solo estaban analizados en prosa
(desensamblado narrativo en una ronda anterior). Esta vez se
extrajeron los bytes REALES del `.cas` de 1988 (localizando los
bloques con nombre "LOAD"/"TEST" por sus marcadores de sincronismo,
leyendo la cabecera de 6 bytes start/end/exec de cada uno: `LOAD.BIN`
$DDA0-$DECA/299B, `TEST.BIN` $C350-$C44C/253B) y se desensamblaron
con `Z80Dasm.exe` byte a byte, sin ambiguedad. `load_cas/load_bin_body.asm`
y `load_cas/test_bin_body.asm` son la conversion de ese desensamblado
a fuente real, con etiquetas para todos los saltos/llamadas internos
verificables.

**Hallazgo no trivial en `TEST.BIN`**: su ultimo tramo (`ENASLT_HELPER`,
122 bytes, $C3D2-$C44C) es una PLANTILLA que nunca se ejecuta en su
posicion original -- `TEST.BIN` la copia con `LDIR` a una zona de
trabajo transitoria en `$AFC8` (fuera del alcance del juego) y solo
se ejecuta desde ahi. Sus 5 saltos `CALL`/`JP` absolutos ya estan
escritos por el autor original para la direccion FINAL post-reubicacion
($AFxx/$Bxxx) -- deben dejarse como hex literal (usar una etiqueta
aqui, aunque "correspondiera" logicamente a un punto de este mismo
bloque, produciria bytes erroneos: nuestro ensamblador resolveria la
etiqueta a su direccion DENTRO de `$C350`, no a la direccion real
`$AFC8`-relativa que el codigo espera en tiempo de ejecucion). Sus 2
saltos `JR`/`DJNZ` (relativos, funcionan igual reubicados o no) SI se
convirtieron a etiquetas reales. Detalle documentado con comentarios
en el propio `.asm`.

**Errores de transcripcion detectados y corregidos antes de dar la
reconstruccion por buena** (namodo "reconstruir primero, verificar
despues" de siempre): en `load_bin_body.asm`, el orden real de las 6
variantes "aplicar configuracion de pagina" (`PAGE_CONFIG_1/2/3` +
sus 3 gemelas no usadas) tiene cada una su propio `JR` explicito (no
hay caida en cascada, un primer borrador lo asumia mal); faltaba la
instruccion `LD B,$0C` en el bucle de "hooks" de `TAPE_READ`. En
`test_bin_body.asm` y `load_bin_body.asm` faltaba en ambos el ultimo
byte suelto del fichero real (`$E1`/`$00` respectivamente, tras la
ultima instruccion real). Todos detectados por diff byte a byte
contra los bytes extraidos del `.cas`, ninguno llego a FINDINGS.md
sin corregir.

**Verificado**: `TEST.BIN` (253B) y `LOAD.BIN` (299B) generados por
`main.asm` son byte a byte identicos a los extraidos del `.cas` de
1988 -- 0 diferencias en ambos.

**`AUTOEXEC.BAS`/`MADMIX.BAS` (disco, tokenizados) reconstruidos como
listado editable**: nueva herramienta `tools/msxbasic_tool.py`
(`detok`/`tok`/`roundtrip`). A diferencia de las demas herramientas
del proyecto, NO usa una tabla de tokens MSX-BASIC estandar completa
(arriesgado reconstruir de memoria sin una referencia fiable) --
usa una tabla PARCIAL con solo los tokens verificados EMPIRICAMENTE
contra el texto ya decodificado en una ronda anterior (`BLOAD`, `RUN`,
`DEF`, `USR`, `=`, la constante hex de 2 bytes con prefijo `$0C`, los
enteros compactos `$11`-`$1B`=0-10). Cualquier byte fuera de ese
conjunto se representa como escape `{$XX}` en el listado -- garantiza
un roundtrip exacto incluso para tokens sin identificar (varias de
las lineas 40/50/60 de `MADMIX.BAS`, aparentemente `SCREEN`/`COLOR`/
similar, quedan con placeholders en vez de adivinar valores). Roundtrip
verificado 0 diferencias en ambos ficheros (19B y 183B).

Curiosidad de paso: la carpeta del disco tiene TAMBIEN un fichero
"MADMIX" (sin extension, 184 bytes) casi identico a `MADMIX.BAS`
(183 bytes) pero con un valor entero distinto en la linea 40 (170 vs.
1) -- no forma parte de la secuencia de arranque real (`AUTOEXEC.BAS`
llama a `RUN"madmix",R`, que en MSX-DOS BASIC busca `.BAS` por
defecto), asi que no se ha reconstruido; queda como observacion sin
investigar mas.

**`TOPO.bas`/`MADMIX.bas` (cinta, ya ASCII plano)**: extraidos
directamente del `.cas` de 1988 (bloques de datos ASCII sin cabecera
de direccion, a diferencia de los binarios -- confirma que el "tipo"
de bloque, marcado en los 10 bytes de tipo-ID antes del nombre
`$EA` vs. `$D0`, es lo que determina si el bloque lleva cabecera
start/end/exec o no) y copiados tal cual a `load_cas/`, sin
necesidad de ninguna herramienta de tokenizacion.

**`LOGOTOPO.CM`**: copiado tal cual (sin analizar, 4254 bytes) a
`load_cas/LOGOTOPO.CM.bin`, con `load_cas/LOGOTOPO.CM.txt` explicando
el porque (decision explicita del usuario, "Organizar todo excepto
el logo") y dejando un TODO visible. `main.asm` NO genera este
fichero todavia.

**`main.asm` ampliado** con 2 bloques nuevos (`MADMIX0.BIN` tras
`MADMIX1.BIN` a proposito, ver arriba; `TEST.BIN`/`LOAD.BIN` tras
`MADMIX0.BIN`) -- pasa a ser el UNICO punto de compilacion para
disco y cinta (sustituye tambien la invocacion aparte de
`sjasmplus madmix0.asm` que ya no existe). Verificado de nuevo tras
todos los cambios: `build/madmix_reconstruido.dsk` sigue dando
exactamente las mismas 9 diferencias de siempre (offsets
12268/12507/40180-40182/51323/51574/52513/55559), ninguna nueva.

**Seguimiento pendiente, no resuelto en esta ronda**: desensamblar
`LOGOTOPO.CM` (fuera de alcance, decision explicita del usuario);
identificar semanticamente los tokens sin resolver de `MADMIX.BAS`
(lineas 40/50/60, probablemente `SCREEN`/`COLOR`/similar); empaquetar
`load_cas/` en un `.cas` real completo con marcas de sincronismo y
checksums (`gen_cas_bin.py`, de la ronda anterior, solo concatena
motor+pantalla, no incluye BASICs/LOAD.BIN/TEST.BIN/logo); adaptar
`tools/gen_inventory.py` a la clasificacion por rango de direccion
(pendiente desde la ronda anterior).


### Vigesimoseptima ronda: salidas de compilacion organizadas en `build/cas/`/`build/disk/`

El usuario creo `src/build/cas/` y `src/build/disk/` pidiendo que la
compilacion ubique cada binario generado en la carpeta que
corresponda (cinta o disco). `main.asm` (los `SAVEBIN`), `tools/gen_cas_bin.py`
y el script de parcheo del `.dsk` actualizados en consecuencia:

- `build/disk/` -- `MADMIX1.BIN`, `MADMIX.SCR`, `MADMIX0.BIN`,
  `AUTOEXEC.BAS`, `MADMIX.BAS`, `madmix_reconstruido.dsk`: todo lo
  necesario para generar el disco, autocontenido.
- `build/cas/` -- `MADMIX1.BIN`, `madmix_cas_scr.bin`, `TEST.BIN`,
  `LOAD.BIN`, `madmix_cas.bin`/`.bin.txt`: todo lo necesario para
  generar la cinta, autocontenido.

`MADMIX1.BIN` (el motor del juego, exactamente el mismo binario en
ambas ediciones, verificado en una ronda anterior) vive DUPLICADO en
las dos carpetas -- primer diseño de esta ronda lo dejaba compartido
en `build/` a secas, pero el usuario señaló que entonces `build/disk/`
no era autocontenida (habria que ir a buscarlo fuera para poder
generar el disco). Corregido: `main.asm` llama dos veces al mismo
`SAVEBIN` (`build/disk/MADMIX1.BIN` y `build/cas/MADMIX1.BIN`) --
verificado que ambas copias son byte a byte identicas. `gen_cas_bin.py`
y el script de parcheo del `.dsk` actualizados para leer cada uno su
propia copia local, no la carpeta del otro.

Verificado tras el cambio: recompilacion limpia desde cero produce
los mismos tamanos de siempre en las rutas nuevas, y
`build/disk/madmix_reconstruido.dsk` sigue dando exactamente las
mismas 9 diferencias conocidas, ninguna nueva.

**Correccion sobre la marcha, misma ronda**: el usuario pregunto si
los ficheros sueltos en la RAIZ de `build/` (`m0.sym`, `m1.sym`,
`mscr.sym`, `madmix0.sym`, `madmix1.sym`, `madmix_scr.sym`,
`madmix_scr.lst`, y una copia vieja de `MADMIX1.BIN`) servian para
algo. Comprobado borrandolos y recompilando desde cero (`sjasmplus
main.asm`, sin flags): NINGUNO se regenera -- son restos huerfanos de
invocaciones sueltas de sesiones anteriores (de cuando `madmix0.asm`/
`madmix1.asm`/`madmix_scr.asm` se compilaban por separado), no forman
parte del proceso de build reproducible actual. Eliminados.

Ademas, el usuario aclaro la intencion real de `build/cas/`/`build/disk/`:
son para los binarios "ingrediente" de cada version (autocontenidos,
ver arriba), pero el ENTREGABLE FINAL empaquetado (`madmix_reconstruido.dsk`,
`madmix_cas.bin`) debe vivir en la RAIZ de `build/`, no dentro de esas
subcarpetas. Corregido: `tools/gen_cas_bin.py` y el script de parcheo
del `.dsk` (`build_disk.py`, en el scratchpad de la sesion, nunca
persistido al repositorio) escriben ahora su salida final en
`build/madmix_cas.bin`/`.bin.txt` y `build/madmix_reconstruido.dsk`
respectivamente, leyendo sus ingredientes de `build/cas/`/`build/disk/`.
Verificado de nuevo: mismos tamanos, mismas 9 diferencias del `.dsk`,
ninguna nueva.

**Correccion final y avance real de la misma ronda**: el usuario aclaro
que `build/madmix_cas.bin` (el ingrediente intermedio, sin formato de
bloques de cinta) SI debia quedarse en `build/cas/` -- lo que debia ir
en la RAIZ de `build/` era el `.cas` REAL, con bloques de cinta de
verdad (sync/nombre/cabecera), que hasta ahora no existia. Nuevo
`tools/gen_cas_file.py`: empaqueta `load_cas/TOPO.bas`,
`load_cas/LOGOTOPO.CM.bin` (sin analizar, copia verbatim),
`load_cas/MADMIX.bas` y `build/cas/LOAD.BIN`/`TEST.BIN`/
`madmix_cas_scr.bin`/`MADMIX1.BIN` en `build/madmix_reconstruido.cas`,
reproduciendo el formato real del `.cas` de 1988 (marcador de
sincronismo `1F A6 DE BA CC 13 7D 74`; bloque de NOMBRE para los
ficheros con nombre -- tipo-ID `$EA`x10 para BASIC ASCII, `$D0`x10
para binario, + 6 caracteres de nombre -- seguido de un bloque de
DATOS: BASIC = texto + relleno `$1A` hasta 256 bytes; binario =
cabecera de 6 bytes start/end/exec + payload; los 2 bloques finales
sin nombre llevan datos crudos).

**Hallazgo real durante la implementacion**: los 2 bloques "crudos"
(sin nombre) llevan tambien un marcador de 1 byte (`$FF`) justo tras
el SYNC, ANTES del payload real -- no documentado en ninguna ronda
anterior. Detectado por un desplazamiento de 1 byte en TODO el resto
del `.cas` reconstruido al compararlo por primera vez (35193
diferencias en cascada, clasico sintoma de "falta/sobra exactamente 1
byte en algun punto anterior"). Corregido añadiendo el marcador antes
del payload en ambos bloques crudos.

**Verificado, resultado final**: `build/madmix_reconstruido.cas`
(50242 bytes, tamaño EXACTO) comparado byte a byte contra el `.cas`
original de 1988: **solo 9 diferencias, las 3 categorias YA
conocidas** -- 3 bytes en la misma posicion relativa que el ya
documentado `$28ED-$28EF` (ajeno, preexistente); 5 bytes
correspondientes al fix deliberado `$FC60`->`$FC50` (2 en el bloque
ENGINE + 3 en el bloque SCR, mismo reparto que en la comparacion del
`.dsk`); y 1 byte en la ultima posicion del fichero (el ya conocido
"1 byte de diferencia en el ultimo byte de MADMIX1.BIN", fuera del
rango que `LOAD.BIN` realmente lee con `LD DE,$59A0`). **Cero
diferencias inesperadas** -- validacion muy fuerte de que TODA la
cadena de reconstruccion de cinta (TOPO.bas, MADMIX.bas, LOAD.BIN,
TEST.BIN, LOGOTOPO.CM sin analizar, madmix_cas_scr.bin, MADMIX1.BIN,
y ahora el propio empaquetado en bloques de cinta) es correcta de
principio a fin.

**Seguimiento pendiente**: el significado exacto del marcador `$FF`
de los bloques crudos y de las colas irregulares sin explicar
(`EB 00 00 00 00 00 00` tras el bloque SCR) no se ha identificado --
se preservan como constantes literales copiadas del `.cas` original,
sin derivarlas del contenido.

### Vigesimoctava ronda: unificar las dos carpetas `tools/` en una sola, en la raiz del repositorio

El usuario detecto que habia dos carpetas `tools/` -- una en la raiz
del repositorio (`madmixgame/tools/`, con solo `msxbasic_tool.py`,
creada ahi por descuido en la ronda del BASIC tokenizado) y otra
dentro de `src/` (`src/tools/`, con el resto de herramientas:
`gen_cas_bin.py`, `gen_cas_file.py`, `mmlvl_tool.py`,
`mmsnd_render.py`, `mmsnd_tool.py`). Pidio unificar en una sola,
en la raiz.

Movidos los 5 scripts de `src/tools/` a `tools/` (raiz); `src/tools/`
eliminada (solo tenia un `__pycache__` residual). Como todos estos
scripts calculan rutas relativas a su propia ubicacion
(`os.path.dirname(__file__)`), subir un nivel de carpeta rompe esas
rutas si no se ajustan -- corregido añadiendo un segmento `src/` de
mas en cada uno:
- `gen_cas_bin.py`/`gen_cas_file.py`: `build/` -> `src/build/`.
- `mmsnd_render.py`: `data/sound/...` -> `src/data/sound/...` (2
  sitios: `ENGINE_FILE` y `scripts_dir`), mas los ejemplos de uso del
  docstring actualizados a rutas relativas a la raiz del repo.
- `mmlvl_tool.py`: de paso, se encontro y corrigio un bug real
  preexistente sin relacion con la mudanza -- `cmd_check_bolitas`
  segia leyendo `madmix_scr.asm` (fichero eliminado hace varias
  rondas, renombrado a `madmix_scr_body.asm` en la unificacion de
  `main.asm`) -- el comando `check-bolitas` llevaba rondas rompiendo
  en silencio (nunca se habia vuelto a invocar desde esa
  unificacion). Corregido a `src/madmix_scr_body.asm`.
- `msxbasic_tool.py`: sin cambios necesarios (recibe todas las rutas
  como argumentos de linea de comandos, no calcula ninguna relativa a
  si mismo).

Verificado ejecutando los 6 scripts desde la nueva ubicacion (`py
tools/nombre.py ...` desde la raiz del repo): `gen_cas_bin.py`,
`gen_cas_file.py` (regenera el `.cas` reconstruido, mismas 9
diferencias de siempre), `mmlvl_tool.py check-bolitas` (nivel 1: 114
bolitas, objetivo 114, OK -- confirma el fix de la ruta), `mmsnd_tool.py
roundtrip` y `mmsnd_render.py render` (ambos sobre un script real,
sin errores). `README.md` actualizado: nueva seccion en "Estructura"
mostrando `tools/` como hermano de `src/` en la raiz del repositorio
(antes aparecia, incorrectamente, como subcarpeta de `src/`), y todas
las rutas de ejemplo de los comandos (`mcopy`, `msxbasic_tool.py`)
ajustadas a rutas relativas a la raiz del repo (con el prefijo
`src/build/...` donde corresponde).


### Vigesimonovena ronda: `dump_openmsx/`, `manuales/` y `recursos/` tambien se mueven a la raiz del repositorio

Mismo patron que la ronda anterior con `tools/`: el usuario pidio
mover estas 3 carpetas de `src/` a la raiz del repositorio
(`madmixgame/dump_openmsx`, `madmixgame/manuales`,
`madmixgame/recursos`), quedando como hermanas de `src/` y `tools/`.

Verificado antes de mover que ninguna de las 3 tiene referencias
relativas reales que se puedan romper (`href=`, `src=`, `fetch(`,
enlaces Markdown `](../...)`) -- los `.html` de `recursos/` son
autocontenidos (sin dependencias externas, confirmado por grep) y
`manuales/` no tiene enlaces relativos de ida y vuelta. Movidas sin
incidencias.

Corregidas las menciones de ruta que si necesitaban ajuste (quitar el
prefijo `src/`, que ya no aplica):
- `src/madmix1_body.asm` (4 comentarios que referencian
  `recursos/ptrtable_sprites.html` y `dump_openmsx/*.png` como
  material de apoyo para el lector).
- `recursos/mapa_memoria.html`, `recursos/graficos.html`, y sus copias
  en `recursos/descartado/` (texto informativo dentro de los datos JS,
  no enlaces reales, pero se corrigieron igualmente por exactitud).
- `README.md`: nueva seccion en "Estructura" mostrando las 4 carpetas
  (`tools/`, `recursos/`, `manuales/`, `dump_openmsx/`) como hermanas
  de `src/` en la raiz, eliminadas las entradas duplicadas que quedaban
  anidadas dentro del subarbol de `src/`.
- De paso, en `manuales/README.md` se corrigio una mencion suelta a
  `madmix1.asm` (nombre viejo, ya no existe desde la unificacion de
  `main.asm` hacia varias rondas) por `madmix1_body.asm`.

**No tocado a proposito**: los ~25 mentions de `src/recursos`/
`src/dump_openmsx` dentro de `FINDINGS.md` (este mismo fichero) se
dejan tal cual -- es un diario cronologico, describe la estructura tal
como era EN EL MOMENTO de cada hallazgo, no se reescribe
retroactivamente. Verificado tras el movimiento: `sjasmplus main.asm` sigue compilando
sin errores (0 errores, mismos 2 warnings de siempre).

**Limpieza adicional, mismo dia**: el usuario pidio limpiar tambien
`build/` (la carpeta suelta en la raiz del repositorio, distinta de
`src/build/`) -- contenia binarios y `.sym`/`.lst` de sesiones muy
antiguas (`24-26/07`, de cuando `madmix0.asm`/`madmix1.asm`/
`madmix_scr.asm` se compilaban por separado y el build todavia no se
habia establecido en `src/build/`). Verificado que nada la
referenciaba (ni `main.asm`, ni ningun script de `tools/`, ni
`README.md`) antes de borrarla entera -- 10 ficheros, ninguno
irremplazable (todo regenerable desde el codigo fuente actual).

### Trigesima ronda: `tools/build_all.py` + `tools/gen_disk_and_cas.py` -- por fin un script real (persistido) para compilar y empaquetar TODO

Hallazgo al preguntar el usuario "¿tiene el proyecto un script que
compile todo?": la respuesta era que NO -- el paso que parchea el
`.dsk` original con los binarios recompilados llevaba TODA la sesión
(y varias anteriores) viviendo solo en un script de usar-y-tirar del
scratchpad de la conversación, nunca guardado en el repositorio.
Cualquier `.dsk` regenerado dependia de que quien lo pidiera
recordara reconstruir ese script desde cero.

Corregido con 2 scripts nuevos en `tools/`, pensados para poder
regenerar TODO el proyecto sin depender de memoria de sesión:

- **`build_all.py`**: invoca `sjasmplus main.asm` con el directorio
  de trabajo correcto (`src/`, ya que `main.asm` usa rutas de
  `SAVEBIN` relativas al cwd, no a su propia ubicacion) y crea antes
  `src/build/disk/`/`src/build/cas/` si no existen (`sjasmplus` no
  crea subcarpetas por si solo -- error real encontrado en la primera
  prueba: `error: opening file for write: build/disk/MADMIX1.BIN` al
  probar desde un `src/build/` borrado por completo).
- **`gen_disk_and_cas.py`**: toma los binarios ya compilados en
  `src/build/disk/`/`src/build/cas/` y genera los 2 ENTREGABLES
  FINALES -- `src/build/madmix_reconstruido.dsk` (la logica de
  parcheo que antes solo vivia en el scratchpad, ahora persistida de
  verdad) y `src/build/madmix_reconstruido.cas` (delegando en
  `gen_cas_bin.py` + `gen_cas_file.py`, ya existentes). Verifica que
  los ingredientes existen antes de arrancar y avisa con un mensaje
  claro si falta ejecutar `build_all.py` primero.

**Verificado de punta a punta**: borrado `src/build/` por completo,
`py tools/build_all.py` + `py tools/gen_disk_and_cas.py` desde cero
reproducen exactamente el mismo `.dsk` (9 diferencias, las mismas de
siempre) y el mismo `.cas` (9 diferencias, las mismas de siempre) que
todas las verificaciones manuales anteriores de esta sesión -- primera
vez que el flujo completo se prueba sin ningun paso manual ni ningun
script fuera del repositorio.

### Trigesimoprimera ronda: el `.dsk` se construye DESDE CERO -- ya no parte de una copia del original a parchear

El usuario, revisando `gen_disk_and_cas.py`, pregunto si de verdad
hacia falta partir de una copia del `.dsk` original para generar el
`.dsk` final, y pidio que la generacion fuera desde cero. Se investigo
la estructura FAT12 real del `.dsk` (leyendo boot sector + BPB + FATs +
directorio raiz byte a byte) para confirmar que es reproducible por
completo: formato MSX-DOS estandar de 720KB (512B/sector, 2
sectores/cluster = 1024B/cluster, 1 sector reservado, 2 copias de FAT
de 3 sectores cada una, 112 entradas de directorio raiz, 1440 sectores
totales, descriptor de medio `$F9`), con los 6 ficheros del disco
asignados de forma SECUENCIAL sin fragmentacion (decodificando las
cadenas FAT12 reales: MADMIX=cluster 2, MADMIX.BAS=3, MADMIX0.BIN=4,
MADMIX1.BIN=5-27, MADMIX.SCR=28-49, AUTOEXEC.BAS=50 -- exactamente lo
esperado por tamano de fichero, sin huecos).

**Nuevo `tools/gen_dsk_file.py`**: construye el `.dsk` entero
(boot sector + 2 tablas FAT12 + directorio raiz + area de datos) a
partir de los binarios ya compilados, sin necesitar el `.dsk` original
como base. Solo 3 piezas de informacion NO se pueden derivar de nada
(no son "codigo/datos del juego", son metadatos/boilerplate del propio
formato de disco o de terceros) y se preservan como recursos verbatim
en `load_disk/`, extraidos UNA vez del `.dsk` original:

- **`boot_sector.bin`** (512 bytes): sector de arranque MSX-DOS
  estandar, boilerplate generico de la herramienta de formateo
  (identificador OEM "DSKTOOL " embebido en el propio sector), nada
  especifico de Mad Mix Game.
- **`MADMIX_dup.bin`** (184 bytes): un SEXTO fichero que tiene el disco
  original, "MADMIX" sin extension -- casi identico a `MADMIX.BAS`
  pero 1 byte mas largo con un valor distinto en la linea 40 (170 vs
  1). NO forma parte del arranque real (`AUTOEXEC.BAS` hace
  `RUN"madmix",R`, que en MSX-DOS BASIC busca `.BAS` por defecto).
  Posible version de desarrollo/prueba dejada por descuido. Sin
  analizar en detalle (mismo tratamiento que `LOGOTOPO.CM`).
- **`dsk_slack.bin`** (5012 bytes): el relleno de cola de cluster de
  los 6 ficheros (ninguno llena su ultimo cluster exacto). **Hallazgo
  real, no trivial**: este relleno NO es cero -- el disquete original
  era un SOPORTE REUTILIZADO, con restos legibles de un uso anterior
  sin relacion con el juego (fragmentos de ruta de fichero como
  `...GIF\CRAZE_GAM_JAP_MSX2.GIF` y `...GIF\BOMULUS_GAM_ENG_MSX1.GIF`,
  aparentando una sesion de catalogacion/volcado de ROMs MSX de quien
  imago originalmente este disco). MSX-DOS nunca lee mas alla del
  tamano declarado en el directorio, asi que esto no afecta al juego
  en absoluto -- pero sin preservarlo tal cual, el `.dsk` generado
  seria funcionalmente identico pero NO byte a byte identico en esas
  zonas. Descubierto por diff: un primer intento con relleno a cero
  produjo 1671 diferencias (todas dentro de estas zonas de cola,
  nunca en el contenido real de ningun fichero) en vez de las 9
  esperadas -- diagnosticado y corregido capturando el relleno real.

La cabecera BLOAD de 7 bytes de `MADMIX1.BIN` (que su `SAVEBIN` no
incluye, misma asimetria de siempre) se calcula en el propio script a
partir del tamano real del cuerpo compilado (`$FE` + start/end/exec),
sin necesitar copiarla de ningun sitio -- `MADMIX0.BIN`/`MADMIX.SCR` ya
incluyen la suya en su `SAVEBIN`, no hace falta tocarlos.

`gen_disk_and_cas.py` simplificado: ahora solo orquesta
`gen_dsk_file.py` + `gen_cas_bin.py` + `gen_cas_file.py`, sin logica
propia de parcheo.

**Verificado de nuevo tras el cambio**: `.dsk` generado 100% desde
cero, comparado byte a byte contra el original: exactamente las
mismas 9 diferencias conocidas de siempre (el fix `$FC60`->`$FC50` y
los 2 bytes ajenos preexistentes), ninguna nueva -- confirma que la
comprension del formato FAT12 y de las 3 piezas no derivables es
completa y correcta.

**Simplificacion inmediata, mismo dia**: el usuario considero que no
merecia la pena preservar el relleno de cola de cluster (`dsk_slack.bin`,
5012 bytes de "basura" de un disquete reutilizado, sin ninguna
relacion con el juego) solo por fidelidad byte a byte. Eliminados
`load_disk/dsk_slack.bin`/`.txt`; `gen_dsk_file.py` rellena ahora con
CEROS en su lugar (mas simple, sin ninguna dependencia del `.dsk`
original para esas zonas). Consecuencia esperada y aceptada: la
comparacion byte a byte contra el original ya NO da "solo 9
diferencias" -- da 1671 (las 9 de siempre + el relleno completo de
cola de cada uno de los 6 ficheros, ninguna de ellas en una zona que
MSX-DOS llegue a leer nunca). Documentado en `README.md` para que no
se lea como una regresion la proxima vez que se compare el `.dsk`.


### Ronda adicional: `mainloop_tables.bin` separado -- los 3 bytes de codigo real ya no viven mezclados con las tablas de datos

El usuario, revisando `MAINLOOP_TABLES` (`INCBIN "data/mainloop_tables.bin"`,
176 bytes, `0x2BF0-0x2CA0`), pregunto si los primeros 3 bytes eran
codigo ensamblador de verdad. Comprobado volcando el hex real:
**si** -- `E1 FB C9` = `POP HL` / `EI` / `RET`, exactamente el mismo
patron de codigo huerfano (sin llamador conocido) que ya existia en
`0xDD93` de `madmix1_body.asm`.

El usuario planteo una duda metodologica valida antes de aceptar esto:
Â¿y si esos 3 bytes en realidad son la COLA de una secuencia de codigo
mas larga que empieza DENTRO del INCBIN anterior
(`data/img/portada_color.img`), y lo que creiamos "datos de imagen"
en sus ultimos bytes es en realidad el principio de esas mismas
instrucciones? Verificado desensamblando un bloque combinado (Ãºltimos
64 bytes de `portada_color.img` + primeros 30 bytes de
`mainloop_tables.bin`) con `Z80Dasm.exe`: la cola de `portada_color.img`
desensambla como ruido totalmente incoherente (`LD B,(HL)` / `LD B,L`
/ `LD B,H` repetidos sin ningun patron logico -- tipico de bytes de
imagen/color comprimido, no de codigo real), mientras que los 3 bytes
en `0x2BF0` SI forman una secuencia coherente y con sentido (restaura
pila, reactiva interrupciones, retorna). Confirma que el limite entre
ambos ficheros es el correcto -- el fragmento de codigo empieza
exactamente en `0x2BF0`, no antes.

**Corregido**: los 3 bytes de codigo se escriben ahora como
instrucciones reales en `madmix_scr_body.asm` (`POP HL` / `EI` / `RET`,
con comentario explicando el hallazgo), igual que ya se hacia en
`0xDD93`. `data/mainloop_tables.bin` recortado a 173 bytes (ya sin
esos 3 bytes, ahora expresados como codigo). La etiqueta
`MAINLOOP_TABLES` pasa a apuntar exactamente a donde empiezan las
variables de estado + tablas reales (`0x2BF3`), mas precisa que antes
(antes incluia por error los 3 bytes de codigo bajo una etiqueta de
"tablas").

Verificado: recompilado, 0 diferencias nuevas -- `MADMIX.SCR` sigue
dando exactamente las mismas 7 diferencias conocidas de siempre.
`.dsk`/`.cas` regenerados, sin cambios en el recuento esperado.

**Confirmacion adicional, mismo dia**: el usuario observo que estas 3
instrucciones (aqui y en `0xDD93` de `madmix1_body.asm`) estan
MUERTAS -- nunca se llaman. Verificado con busqueda exhaustiva
(`grep`) de `2BF0`/`DD93` en todo `src/*.asm`: **cero** referencias
`JP`/`JR`/`CALL` a ninguna de las dos direcciones en todo el codigo
fuente reconstruido. Confirmado: no es "sin llamador identificado
todavia", es codigo muerto de verdad (probablemente un resto de una
version anterior del codigo fuente original, cuyo punto de entrada
real se elimino o se movio en su dia sin limpiar estos 3 bytes
finales -- comun en ensamblado a mano de los 80, ya que el ensamblador
no elimina codigo inalcanzable). Comentarios de ambos sitios
actualizados para reflejar la confirmacion en vez de la formulacion
mas tentativa de antes.


### Ronda adicional: `mainloop_tables.bin` eliminado -- todo su contenido pasa a datos nativos etiquetados en `madmix_scr_body.asm`

El usuario, retomando el bloque `MAINLOOP_TABLES`, planteo que "estos
datos parecen variables" y que no tenia sentido mantenerlos como
fichero `.bin` opaco -- pidio acotarlos con comentario explicando que
es cada uno. Como ya se habia identificado en la ronda anterior que
los primeros 3 bytes eran codigo muerto real (`POP HL`/`EI`/`RET`),
tenia razon: el resto no es una "tabla" homogenea, son campos con
significado individual, la mayoria YA descifrados con codigo real en
rondas anteriores de esta sesion (ver "Los 13 bytes restantes del
registro de nivel" y "Descifrados offsets 8/11/18/19 del registro de
nivel").

**Reescrito completo, 173 bytes, en 3 partes**:

1. **`LEVEL_REC_WORK`** (`$2BF3-$2C06`, 20 bytes): la copia de trabajo
   del registro de 20 bytes de `LEVEL_TABLE` (confirmado por
   `LD DE,$2BF3 / LDIR` en el cargador de nivel) -- cada uno de los 20
   campos con su propia etiqueta y comentario (`LEVEL_REC_BODY_PTR`,
   `LEVEL_REC_HEADER_PTR`, `LEVEL_REC_ROWS`, `LEVEL_REC_ITEM1/2/3_COUNT`,
   `LEVEL_REC_BLINK_DURATION`, `LEVEL_REC_WILDCARD_TILE`,
   `LEVEL_REC_REF_ROWCOL`, `LEVEL_REC_START_POS`, `LEVEL_REC_HUD_ICON`,
   `LEVEL_REC_BALL_TARGET`), usando el descifrado campo a campo ya
   documentado. Los VALORES horneados en la ROM son solo una
   instantanea del ultimo nivel procesado en tiempo de compilacion
   (sin significado propio -- la partida real siempre los sobreescribe
   al cargar cada nivel).
2. **Variables de estado de partida** (`$2C07-$2C37`, 49 bytes):
   etiquetadas individualmente donde ya habia evidencia de codigo real
   (`CURRENT_LEVEL`, `BALLS_EATEN_COUNT`, `BALL_BLINK_POS/TIMER`,
   `SPECIAL_MODE_FLAG/COUNTDOWN/ACTIVE/COLOR_PAIR`, `MOVE_DIRECTION`,
   `SAVED_COLOR`/`CURRENT_COLOR`, `REFERENCE_POINT`, `LIVES_REMAINING`,
   `PENDING_HUD_FLAG`, `FIRST_LOOP_FLAG`, `SPECIAL_MODE`,
   `HINT_POS_TABLE`) -- los huecos genuinamente sin ningun acceso
   encontrado en el codigo se dejan como `DS n,$00` con comentario
   "sin identificar" (son cero de verdad, no relleno inventado).
   **Hallazgo nuevo de paso**: `SAVED_COLOR`/`CURRENT_COLOR` ($2C18/
   $2C24, ambos `$78` por defecto) y `SPECIAL_MODE_COLOR_PAIR` ($2C16,
   `$1018`) se identificaron cruzando los valores reales del binario
   con los sitios de escritura ya transcritos (`LD BC,$1018` /
   `LD BC,$1C18` en los manejadores de modo tanque/avion) -- antes
   estaban documentados solo como "variables de color sin agrupar".
3. **`JR MAIN_LOOP`** (`$2C36-$2C37`, 2 bytes): **hallazgo nuevo, no
   documentado antes**. Estos 2 bytes ya se sabian "llamados
   directamente como CALL a RAM" desde 2 sitios sin mas detalle
   ("$2C36, llamada a RAM, no codigo estatico, sin identificar").
   Verificado que su contenido por defecto (`$18,$68`) NO es ruido --
   decodifica exactamente como `JR $2CA0`, el salto relativo aterriza
   pixel a pixel en `MAIN_LOOP`. Probable "trampolin" autopatchable
   (mecanismo de parcheo en tiempo de ejecucion aun sin identificar,
   pero el valor de fabrica es un salto trivial de vuelta al bucle
   principal). Escrito como instruccion real (`JR MAIN_LOOP`), no como
   bytes sueltos -- el ensamblador la resuelve automaticamente a los
   mismos 2 bytes.
4. **Tablas del motor** (`$2C38-$2CA0`, 104 bytes): sin cambios de
   contenido, solo etiquetas reales nuevas (`TILE_DISPATCH_TABLE`,
   `TILE_DISPATCH_PTRS` con `DW SUBTABLE_A/B/C/D` en vez de hex suelto,
   y las 4 sub-tablas con su propia etiqueta).

`data/mainloop_tables.bin` **eliminado** -- ya no hace falta, todo su
contenido vive como datos nativos en `madmix_scr_body.asm`.

**Verificado**: recompilado, 0 diferencias nuevas -- `MADMIX.SCR`
sigue dando exactamente las mismas 7 diferencias conocidas de
siempre (confirma que los 173 bytes reescritos a mano, incluida la
instruccion `JR MAIN_LOOP` reconstruida, son byte a byte identicos a
los del `.bin` que sustituyen). `.dsk`/`.cas` regenerados sin cambios
en el recuento esperado.

### Ronda adicional: las nuevas etiquetas de `mainloop_tables.bin` se sustituyen de verdad en todo el codigo (231 sitios)

El usuario seÃ±alo, correctamente, que las etiquetas creadas en la
ronda anterior (`CURRENT_LEVEL`, `BALLS_EATEN_COUNT`, etc.) no se
usaban en ningun sitio -- solo existian en su propia definicion. Si
de verdad eran variables reales, el resto del codigo tenia que
llamarlas por su nombre, no seguir usando hex suelto.

**Correccion importante encontrada al hacerlo**: buscar solo en
`madmix_scr_body.asm` (como hice en la ronda anterior, guiandome por
`FINDINGS.md`) fue INSUFICIENTE -- muchas de estas variables se leen/
escriben SOLO desde `madmix1_body.asm` (comparten espacio de
direcciones porque `madmix_scr_body.asm` se reubica a memoria baja).
Al cruzar AMBOS ficheros con grep aparecieron referencias reales a
direcciones que en la ronda anterior habia marcado, por error, como
"sin identificar":

- `$2C11-15` (5 bytes que crei hueco): en realidad `DIR_BEHAVIOR_SELECTOR`,
  `TILE_TYPE_CACHE`, `TILE_COL_CACHE`, `DIR_TABLE_INDEX`, `RAW_DIRECTION`
  -- todas usadas en el bucle de despacho de direccion de `MAIN_LOOP`.
- `$2C16-17`: NO era "par de color" (mi suposicion inicial al ver dos
  escrituras `LD BC,$1018`/`$1C18`) -- es `CAMERA_POS`, la posicion de
  camara actual (confirmado por `LD BC,($2C16) ; posicion de camara
  actual` en `MAIN_LOOP`); los modos tanque/avion simplemente la FIJAN
  a un valor concreto mientras duran.
- `$2C19`: `GAME_STATE_FLAG`, usado solo desde `madmix1_body.asm`.
- `$2C1A/$2C1B`: no solo "se limpian junto con otros" como crei --
  son variables activas por derecho propio: `FORCED_DIRECTION`
  (direccion forzada por flechas) y `FORCED_DIR_TIMER` (cuenta atras).
- `$2C1C/$2C1D`: `DIR_INPUT_LATCH`/`INPUT_EDGE_FLAG`, logica real de
  deteccion de flanco de pulsacion en `MAIN_LOOP`.
- `$2C1E`: `TRAPDOOR_PHASE`, variante de animacion de trampilla.
- `$2C22-23` (que crei parte de un hueco de 3 bytes): `RNG_SEED`, la
  semilla del generador pseudoaleatorio `ITEM_RNG` ($5478).
- `$2C25-26`: `SCROLL_LR_PARAM`, usado en `SCROLL_DISPATCH`/`SCROLL_LR`
  (`madmix1_body.asm`) -- significado preciso reconocido como "sin
  confirmar" ya en el codigo existente, pero es una variable real, no
  un hueco.
- `$2C29-2A`: `SCORE_ACCUM`, la puntuacion acumulada de la partida (si
  llega a 10000/`$2710` activa `BESTIA_TEXT`).

Los huecos que SI se confirmaron genuinos (cero referencias en
NINGUNO de los dos ficheros, verificado con grep cruzado): `$2C21`,
`$2C28`, `$2C34-35` -- 4 bytes en total, muy lejos de los ~30 que se
habian asumido en la primera pasada.

Tambien se aÃ±adieron 2 alias en direcciones ya etiquetadas por otro
motivo: `PACMAN_POS` (mismo byte que `LEVEL_REC_START_POS`, offset
15-16 del registro de nivel -- la posicion viva del comecocos/camara
se referencia DECENAS de veces durante toda la partida, mucho mas que
como campo del registro) y `RAM_HOOK_2C36` (etiqueta que faltaba
delante de la instruccion `JR MAIN_LOOP` de la ronda anterior, para
poder sustituir los 2 sitios `CALL $2C36`).

**Sustitucion aplicada**: script de una sola vez (no persistido,
scratchpad de la sesion) que separa cada linea en codigo+comentario
(por el primer `;` fuera de comillas) y sustituye direccion por
etiqueta SOLO en la parte de codigo -- los comentarios que mencionan
la direccion hex se dejan intactos como referencia cruzada. 231
sustituciones en total: 174 en `madmix_scr_body.asm`, 57 en
`madmix1_body.asm`.

**Verificado**: recompilado, exactamente las mismas diferencias
conocidas de siempre en ambos binarios -- **7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`**, ninguna nueva -- confirma que las 231 sustituciones
son 100% equivalentes byte a byte (esperable, ya que sustituir una
direccion hex por una etiqueta que resuelve a esa misma direccion no
puede cambiar ningun byte generado). `.dsk`/`.cas` regenerados, mismos
recuentos de siempre (1671 y 9 respectivamente).

### Ronda adicional: `recursos/mapa_memoria.html` y `recursos/flujo_programa.html` puestos al dia -- `tools/gen_inventory.py` reconstruido y persistido

El usuario pregunto si los visores HTML se estaban actualizando en
cada avance de esta sesion -- la respuesta honesta era que NO. Se
revisaron los dos:

- **`mapa_memoria.html`**: la entrada de `0x2BF0-0x2CA0` describia
  literalmente el estado ANTERIOR al hallazgo de esta sesion ("los
  primeros 9 bytes son cola de codigo + relleno sin identificar del
  todo"). Corregida y dividida en 4 entradas reales: codigo muerto
  (`0x2BF0-3`), `LEVEL_REC_WORK` (`0x2BF3-2C07`), variables de estado
  de partida (`0x2C07-2C36`), `RAM_HOOK_2C36` (`0x2C36-8`), y las
  tablas del motor (`0x2C38-2CA0`).

- **`flujo_programa.html`**: el inventario de "634 etiquetas" resulto
  ser un array JS estatico, generado UNA vez por un script
  (`gen_inventory.py`) que nunca se guardo en el repositorio (mismo
  patron que el parcheo del `.dsk` antes de esta sesion) -- llevaba
  desactualizado desde antes de la unificacion de `main.asm`: nombres
  de fichero viejos (`madmix_scr`/`madmix1` en vez de
  `madmix_scr_body.asm`/`madmix1_body.asm`), numeros de linea de hace
  varias rondas, y CERO etiquetas de `load_disk/`/`load_cas/` o del
  desglose de `mainloop_tables.bin`.

**Reconstruido `tools/gen_inventory.py`, persistido esta vez**:
lee `src/build/main.lst` (el listado completo de sjasmplus, generado
con `--lst=`) en vez de `--sym` -- el `.sym` solo da nombre+direccion,
insuficiente ahora que `main.asm` compila TODO en una pasada: varias
direcciones se REUTILIZAN a proposito entre ficheros fuente distintos
(`$C350` es a la vez el driver de sonido de `madmix1_body.asm` Y
`TEST_BIN_ENTRY` de `load_cas/test_bin_body.asm`, solape ya validado
en una ronda anterior) -- solo el listado, con sus marcadores
"# file opened/closed", permite saber de que fichero FUENTE viene
cada etiqueta sin ambiguedad (por posicion en el fuente, no por
direccion final).

**2 bugs reales encontrados y corregidos durante la construccion**
(verificados con pruebas dirigidas antes de confiar en el resultado):
1. El regex de parseo de linea no consumia correctamente el volcado
   de bytes generados (de longitud variable, hasta 4 pares hex por
   linea de listado) antes del texto fuente -- en lineas con `DB`/`DS`
   que si volcaban bytes, el "texto" capturado quedaba contaminado
   con esos bytes hex por delante, rompiendo la deteccion de
   "le sigue un DB/DW/DS/INCBIN" (primer intento: dato paso de 174 a
   solo 20 etiquetas). Corregido cambiando el regex para consumir
   explicitamente 0-4 pares hex opcionales antes del texto.
2. Una etiqueta con comentario en la MISMA linea (`LEVEL_TABLE:    ;
   300 bytes...`, patron muy comun en este proyecto) se tomaba como
   si el comentario fuera "la siguiente instruccion real", en vez de
   seguir buscando -- causaba que decenas de etiquetas de datos
   reales cayeran en "sinref" por error (segundo intento: dato subio
   a 99, seguia bajo lo esperado). Corregido para saltar tambien los
   restos de linea que empiezan por `;`.

**Resultado final**: 729 etiquetas (antes 634 -- refleja las nuevas
de `load_disk/`/`load_cas/` y el desglose de `mainloop_tables.bin`),
clasificadas 93 funcion / 218 interna / 224 dato / 194 sin ref.
Verificado con casos concretos conocidos (`LEVEL_TABLE`->dato,
`RELOCATOR`/`LOAD_BIN_ENTRY`->sinref igual que en el inventario viejo,
`MAIN_LOOP`->interna, `TEST_BIN_ENTRY`->funcion, fichero correcto
`test_bin_body.asm` no confundido con `madmix1_body.asm` pese a
compartir direccion $C350).

`tools/build_all.py` actualizado para generar tambien
`src/build/main.lst` (flag `--lst=`) en cada compilacion completa, asi
`gen_inventory.py` siempre tiene datos frescos sin un paso manual
aparte. `README.md` actualizado (conteo de etiquetas, entrada nueva en
`tools/`, explicacion de por que hace falta el listado y no el .sym).

**Correccion inmediata, mismo dia**: el usuario encontro un hueco
real en la ronda de sustitucion de hex por etiquetas -- `$2C38` y
`$2C48` (las direcciones de `TILE_DISPATCH_TABLE`/`TILE_DISPATCH_PTRS`)
seguian usadas como hex literal en 4 sitios de codigo real
(`madmix_scr_body.asm`, lineas ~468/549/1875/1904: `LD HL,$2C38`/
`$2C48`), porque el script de sustitucion de la ronda anterior solo
cubria el rango de variables de estado (`$2BF3-$2C37`), no las
direcciones de las tablas del motor que ya tenian etiqueta desde la
ronda de conversion de `mainloop_tables.bin`. Sustituidos los 4 sitios
por `TILE_DISPATCH_TABLE`/`TILE_DISPATCH_PTRS`; verificado cruzando
tambien `madmix1_body.asm` (sin ninguna referencia a esas 2
direcciones ahi). Recompilado: mismas 7 diferencias conocidas de
siempre en `MADMIX.SCR`, ninguna nueva. `.dsk`/`.cas`/inventario HTML
regenerados.

**Otra correccion, mismo dia**: el usuario encontro `PATCH_OFF_10D8`/
`PATCH_ON_10DE` escritos como `DB` con hex literal (con un comentario
diciendo la instruccion equivalente) en vez de instrucciones reales
-- mismo tipo de deuda que el codigo muerto de `$2BF0`/`$DD93` de
rondas anteriores, pero aqui SI son codigo alcanzable (llamadas reales
desde `TI_CONT`/`TAIL_LEVELCYCLE_HELPER_ALT`/`TAIL_CREDITS_MAIN`).
Reescritas como instrucciones reales (`LD A,$A2`/`LD ($10E4),A`/`RET`
y `LD A,$E2`/`LD ($10E4),A`/`RET`) y renombradas a nombres
descriptivos: `QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` (reflejan lo que
hacen -- precargan el byte que la ISR aplicara al registro 1 del VDP
en el siguiente VBLANK, no cambian la pantalla en el acto). Los 9
bytes de datos que seguian ($10E4 en adelante) se quedan igual, son
genuinamente datos, no parte de estas 2 rutinas. Actualizados los 6
sitios que las llamaban (`madmix_scr_body.asm`) y el comentario
cruzado en `madmix1_body.asm`. Verificado: recompilado, mismas
diferencias conocidas de siempre en ambos binarios (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`), ninguna nueva. `.dsk`/`.cas`/
inventario HTML regenerados (729 etiquetas, mismo recuento).

**Tercera correccion, mismo dia**: el usuario pregunto si los 9 bytes
de datos justo despues de `QUEUE_SCREEN_ON` (`$10E4-$10EC`) eran
variables. Repasado: el PRIMER byte (`$10E4`) ya estaba confirmado
desde una ronda anterior (el valor de registro 1 del VDP que la ISR
relee y reescribe cada VBLANK, ver "RESUELTO: el byte automodificable
`$10E4`") pero seguia sin etiqueta propia, solo mencionado en
comentarios. Anadida `VDP_REG1_PENDING` y sustituidas las 3
referencias reales (`QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` en
`madmix_scr_body.asm`, la lectura de la ISR en `madmix1_body.asm`).
Los 8 bytes siguientes (`$10E5-$10EC`) se verificaron de nuevo (grep
en ambos ficheros) -- siguen sin ninguna referencia real encontrada,
se quedan como `DB` con los valores originales exactos y comentario
"sin identificar" (ya investigados y aparcados para trazado en vivo
en una ronda anterior, no resueltos por analisis estatico). Verificado:
recompilado, mismas diferencias de siempre en ambos binarios, ninguna
nueva. `.dsk`/`.cas`/inventario HTML regenerados (730 etiquetas, +1
por `VDP_REG1_PENDING`).


### Ronda adicional: los 65 `ML_XXXX` de `MAIN_LOOP` renombrados a nombres descriptivos

El usuario senalo que la convencion `ML_` + direccion hex (p.ej.
`ML_2CAD`) no aporta informacion autoexplicativa, y pidio depurarla
empezando por `MAIN_LOOP` (el resto de convenciones similares del
proyecto -- `JTS2_`, `RM_`, `GH_`, `TI_`, `KMD_`, `H5278_`, etc. --
quedan para otra ronda, alcance acordado explicitamente con el
usuario).

Leido el motor de colision/movimiento completo (`MAIN_LOOP`,
`0x2CA0-0x335C`, ~1200 lineas) para entender el papel real de cada
una de las 65 etiquetas `ML_XXXX` antes de renombrar -- sin adivinar,
usando los comentarios ya existentes (este tramo ya estaba muy bien
documentado de rondas anteriores). Renombradas todas a nombres que
reflejan su funcion real, agrupadas por bloque:

- Preambulo (decision de direccion/input, alineamiento, despacho):
  `ML_READ_REAL_INPUT`, `ML_STORE_DIRECTION`, `ML_LATCH_CLEAR`,
  `ML_LATCH_STORE`, `ML_ALIGN_START`, `ML_ALIGN_CHECK_Y`,
  `ML_ALIGN_APPLY`, `ML_DIR_FINALIZE`, `ML_TILE_TYPE_INDEX`,
  `ML_DISPATCH_LOOKUP`.
- Gestion de modo especial activo (bola de poder/hipopotamo):
  `ML_SPECIAL_MODE_TICK`, `ML_POWER_BLINK_COLOR`, `ML_POWER_MODE_END`,
  `ML_HIPPO_MODE_TICK`, `ML_HIPPO_BLINK_ICON`, `ML_HIPPO_MODE_END`.
- Subtabla de direccion + scroll/items: `ML_DIR_SUBTABLE_LOOKUP`,
  `ML_DIR_SUBTABLE_LOOP`, `ML_DIR_BEHAVIOR_STORE`, `ML_SCROLL_PREP`,
  `ML_SCROLL_DISPATCH_CALL`, `ML_SCROLL_AND_ITEMS`.
- Bucle de trampillas activas: `ML_TRAPDOOR_LOOP`,
  `ML_TRAPDOOR_FORMAT_B`, `ML_TRAPDOOR_FORMAT_B_POS`,
  `ML_TRAPDOOR_ROW_FIXED`, `ML_TRAPDOOR_DRAW`, `ML_TRAPDOOR_NEXT`.
- Internos de `CHECK_TILE_DELTA`/`DRAW_TILE_HELPER`:
  `ML_DELTA_CHECK_LEFT/DOWN/UP`, `ML_DELTA_RESOLVE`,
  `ML_DELTA_MASK_RESULT`, `ML_DRAWTILE_COL_CHECK`, `ML_DRAWTILE_REDRAW`.
- Colas de los 16 manejadores de tipo de loseta (cada una vuelve al
  despacho principal): `HANDLER_2EB7_CONT`, `HANDLER_2EC7_EXIT`,
  `HANDLER_2EFC_EXIT`, `HANDLER_2F18/2F50/2F88/2FC0_EXIT`,
  `HANDLER_2FF8_MODE_CHECK/ACTIVATE/TAIL`, `HANDLER_3067_ACTIVATE/LOOP`,
  `HANDLER_30F3_EXIT`, `HANDLER_311B_EXIT`, `HANDLER_315D_EXIT`,
  `HANDLER_318E_EXIT`, `HANDLER_31B7_PLANE_CHECK/LOOP`.
- Cola comun de "salir de modo especial" (compartida por varios
  manejadores): `SPECIAL_MODE_EXIT_TAIL`, `SPECIAL_MODE_EXIT_REENTER`.
- `TRAPDOOR_FLIP_TABLE` interno: `TRAPDOOR_FLIP_SCAN/SET/STORE`.
- Cuenta atras de direccion forzada: `FORCED_DIR_TIMER_TICK`,
  `FORCED_DIR_CLEAR`, `FORCED_DIR_TICK_DONE`.
- Animacion de apertura/cierre de trampilla (tipos 17-19):
  `TRAPDOOR_ANIM_OPEN_A/B`, `TRAPDOOR_ANIM_CLOSE_A/B`,
  `TRAPDOOR_ANIM_EXIT`.

Aplicado con un script de sustitucion global (palabra completa, en
AMBOS ficheros -- una mencion cruzada en un comentario de
`madmix1_body.asm` tambien actualizada) -- a diferencia de la ronda de
hex-a-etiqueta, aqui SI se tocan los comentarios (son referencias por
NOMBRE, no direcciones hex, asi que quedarian desactualizadas/
enganosas si no se actualizan tambien).

**De paso, 4 llamadas hex sueltas encontradas y corregidas** en el
mismo tramo (`CALL Z,$51FE`/`$54A9`/`$55C0`/`CALL $5782`, 3 sitios
cada una): ya tenian etiqueta real (`R51FE_MAIN`, `ITEM_HANDLER_1`,
`ITEM_HANDLER_2`, `ITEM_TIMER_TICK`) pero no se habian sustituido en
estas 12 llamadas.

Tambien actualizados 2 comentarios de cabecera que describian la
convencion vieja ("Etiquetas ML_XXXX = direccion real (hex)...") y la
advertencia de "no confundir el indice de la tabla con la direccion
del manejador" (sigue siendo valida, pero referida ahora a los
NOMBRES nuevos, no a que sean hex).

**Verificado**: recompilado, mismas diferencias conocidas de siempre
en ambos binarios (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`), ninguna
nueva -- 215 sustituciones de nombre + 12 de hex-a-etiqueta, cero
cambios de byte. `.dsk`/`.cas`/inventario HTML regenerados (730
etiquetas, funcion sube de 93 a 97 por las 4 llamadas recien
etiquetadas).

**Pendiente, alcance acordado con el usuario**: el resto de
convenciones `PREFIJO_hex` del proyecto (`JTS2_`, `RM_`, `GH_`, `TI_`,
`KMD_`, `H5278_`, `H53A2_`, `H5414_`, `IH1_`/`IH2_`, etc., varios
cientos de etiquetas) se quedan para una ronda futura -- se empezo
deliberadamente solo por `MAIN_LOOP` para validar el criterio de
nombrado antes de escalar.

### Ronda adicional: los 14 `HANDLER_XXXX` (manejadores de tipo de loseta) renombrados a `HNDLR_` + nombre descriptivo en espanol

Tras el rename de `ML_XXXX` en `MAIN_LOOP`, el usuario pidio continuar
con los manejadores de tipo de loseta (`HANDLER_2EB7`, `HANDLER_2EC7`,
etc. -- las 14 entradas de `ML_DISPATCH_TABLE`), esta vez con nombres
en **espanol** (a diferencia de la ronda `ML_`, donde se opto por
ingles siguiendo la convencion dominante del proyecto) -- divergencia
explicita pedida por el usuario para este grupo concreto, con 3
ejemplos dados literalmente: `HANDLER_2EC7` -> `HNDLR_BOLITA_NORMAL`,
`HANDLER_2EFC` -> `HNDLR_BOLITA_CLAVADA`, `HANDLER_2F18` ->
`HNDLR_FLECHA_ARRIBA`.

Mapa completo aplicado (14 manejadores base, segun el tipo de loseta
que atienden en `ML_DISPATCH_TABLE`, documentado en el bloque de
comentarios de `madmix_scr_body.asm` ~linea 793-806):

| Etiqueta vieja  | Etiqueta nueva            | Tipo(s) de loseta |
| ----------------- | ---------------------------- | ------------------- |
| HANDLER_2EB7    | HNDLR_SUELO_NORMAL          | 0, 8, 9 (pared/suelo normal + linea electrica puerta fantasmas, sin logica propia) |
| HANDLER_2EC7    | HNDLR_BOLITA_NORMAL         | 1 (bolita normal) |
| HANDLER_2EFC    | HNDLR_BOLITA_CLAVADA        | 2 (bola fija/clavada) |
| HANDLER_2F18    | HNDLR_FLECHA_ARRIBA         | 3 |
| HANDLER_2F50    | HNDLR_FLECHA_ABAJO          | 4 |
| HANDLER_2F88    | HNDLR_FLECHA_IZQUIERDA      | 5 |
| HANDLER_2FC0    | HNDLR_FLECHA_DERECHA        | 6 |
| HANDLER_2FF8    | HNDLR_PISTA_TANQUE          | 7 (pista tanque vertical) |
| HANDLER_3067    | HNDLR_PISTA_AVION           | 10 (pista avion) |
| HANDLER_30F3    | HNDLR_ITEM_SUELO            | 11 (item suelo sin confirmar del todo) |
| HANDLER_311B    | HNDLR_BOLA_PODER            | 12 (bola de poder real) |
| HANDLER_315D    | HNDLR_HIPOPOTAMO            | 13 (item hipopotamo) |
| HANDLER_318E    | HNDLR_HERRAMIENTA           | 14 (item herramienta) |
| HANDLER_31B7    | HNDLR_SUELO_SIN_BOLA        | 15, 16 (suelo sin bola/muro suelto + loseta solida negra) |

Y sus 18 sub-etiquetas asociadas (colas de retorno al despacho
principal, creadas en la ronda `ML_` anterior), renombradas en
consonancia (mismo sufijo, nuevo prefijo): `HNDLR_SUELO_NORMAL_CONT`,
`HNDLR_BOLITA_NORMAL_EXIT`, `HNDLR_BOLITA_CLAVADA_EXIT`,
`HNDLR_FLECHA_ARRIBA_EXIT`, `HNDLR_FLECHA_ABAJO_EXIT`,
`HNDLR_FLECHA_IZQUIERDA_EXIT`, `HNDLR_FLECHA_DERECHA_EXIT`,
`HNDLR_PISTA_TANQUE_MODE_CHECK`, `HNDLR_PISTA_TANQUE_ACTIVATE`,
`HNDLR_PISTA_TANQUE_TAIL`, `HNDLR_PISTA_AVION_ACTIVATE`,
`HNDLR_PISTA_AVION_LOOP`, `HNDLR_ITEM_SUELO_EXIT`,
`HNDLR_BOLA_PODER_EXIT`, `HNDLR_HIPOPOTAMO_EXIT`,
`HNDLR_HERRAMIENTA_EXIT`, `HNDLR_SUELO_SIN_BOLA_PLANE_CHECK`,
`HNDLR_SUELO_SIN_BOLA_PLANE_LOOP`.

Aplicado con script de sustitucion global (palabra completa, claves
ordenadas por longitud descendente para que una sub-etiqueta como
`HANDLER_31B7_PLANE_CHECK` nunca quede "tapada" por su prefijo
`HANDLER_31B7` en la alternancia regex -- aunque en la practica `\b`
ya lo impedia, al ser `_` caracter de palabra). Se tocan AMBOS
ficheros y tambien los comentarios (referencias por nombre, igual
criterio que la ronda `ML_`): 124 sustituciones en
`madmix_scr_body.asm`, 5 en `madmix1_body.asm` (comentarios de
`SOUND_EVT*` que citaban el manejador relacionado con cada efecto de
sonido), 129 en total.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs contra los binarios originales en la linea base
exacta de siempre -- 7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN` (comparando
el cuerpo tras la cabecera BLOAD de 7 bytes) -- cero diferencias
nuevas. `.dsk`/`.cas` regenerados
(`py tools/gen_disk_and_cas.py`). Inventario HTML regenerado
(`py tools/gen_inventory.py`): mismo total de 730 etiquetas
(funcion=97, interna=218, dato=225, sinref=190) -- el rename no cambia
clasificacion, solo nombres.

**Pendiente, mismo alcance acordado que en la ronda `ML_`**: el resto
de convenciones `PREFIJO_hex` del proyecto (`JTS2_`, `RM_`, `GH_`,
`TI_`, `KMD_`, `H5278_`, `H53A2_`, `H5414_`, `IH1_`/`IH2_`, etc.)
siguen fuera de alcance hasta que el usuario pida continuar.



### Ronda adicional: `TRAPDOOR_ANIM_OPEN_A/OPEN_B/CLOSE_A/CLOSE_B` renombradas a `HNDLR_TRAMPILLA_*` (tipos de loseta 17-19), con correccion de lateralidad

El usuario planteo la hipotesis de que estas 3 entradas eran
"trampilla abierta a izquierda / abierta a derecha / cerrada" y pidio
verificar si el emparejamiento izquierda/derecha era correcto.
Contrastando contra el catalogo de losetas (`TILE_TYPES` en
`madmix1_body.asm` ~linea 3060-3072, fuente de verdad de los nombres
de tile) se confirmo que la idea general era correcta pero el
emparejamiento estaba INVERTIDO respecto a la hipotesis inicial:

- Tile 68 = `trampilla_a_abajo_derecha` -> tipo de loseta 17 ->
  despachado por la entrada que era `TRAPDOOR_ANIM_OPEN_A`
- Tile 73 = `trampilla_b_abajo_izquierda` -> tipo de loseta 18 ->
  despachado por la entrada que era `TRAPDOOR_ANIM_OPEN_B`
- Tiles 78/79 = `trampilla_transicion_abajo_izquierda/derecha` -> tipo
  de loseta 19 -> despachado por la entrada que era
  `TRAPDOOR_ANIM_CLOSE_A`

Es decir, `OPEN_A` = apertura hacia la DERECHA (no izquierda) y
`OPEN_B` = apertura hacia la IZQUIERDA (no derecha).

Ademas se detecto un matiz no obvio: la letra A/B de
`CLOSE_A`/`CLOSE_B` NO corresponde al mismo lado que la A/B de
`OPEN_A`/`OPEN_B` -- es al reves. `HNDLR_TRAMPILLA_CERRADA` (antes
`CLOSE_A`) es la UNICA entrada de `ML_DISPATCH_TABLE` para el tipo 19
(cierre, ambos lados comparten esta misma loseta de "transicion"), y
decide internamente que variante de dibujo usar leyendo
`TRAPDOOR_PHASE` (la fase que dejo marcada la apertura previa: $01 si
abrio `HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA`, $02 si abrio
`HNDLR_TRAMPILLA_ABIERTA_DERECHA`). Si la fase es 2 (abrio por la
derecha) salta a la variante `_B` para dibujar ese cierre; si es 1
(abrio por la izquierda) se queda en el cuerpo de `HNDLR_TRAMPILLA_CERRADA`
mismo. Documentado con un comentario explicito en el codigo para que
no se pierda este detalle en el futuro.

Mapa aplicado:

| Etiqueta vieja           | Etiqueta nueva                       |
|---------------------------|---------------------------------------|
| TRAPDOOR_ANIM_OPEN_A       | HNDLR_TRAMPILLA_ABIERTA_DERECHA       |
| TRAPDOOR_ANIM_OPEN_B       | HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA     |
| TRAPDOOR_ANIM_CLOSE_A      | HNDLR_TRAMPILLA_CERRADA               |
| TRAPDOOR_ANIM_CLOSE_B      | HNDLR_TRAMPILLA_CERRADA_B (variante interna, no es entrada propia de la tabla de despacho) |

`TRAPDOOR_ANIM_EXIT` (cola de retorno compartida por las 3, analoga a
`SPECIAL_MODE_EXIT_TAIL`/`FORCED_DIR_TIMER_TICK`) se deja sin
renombrar -- sigue el mismo criterio de las rondas anteriores de no
tocar las colas comunes que ya tenian nombre descriptivo propio.

21 sustituciones (19 en `madmix_scr_body.asm`, 2 en
`madmix1_body.asm`, palabra completa, tocando tambien comentarios).
Actualizado ademas el bloque de comentarios de cabecera (~linea 701 y
~1442) para reflejar los nombres nuevos y la explicacion de
lateralidad/variante `_B`.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas` e inventario HTML
regenerados: mismo total de 730 etiquetas (funcion=97, interna=218,
dato=225, sinref=190).



### Ronda adicional: los 8 bytes de `$10E5-$10EC` etiquetados como `VDP_SCR2_REGS_TABLE` (hipotesis fuerte, sin lector confirmado)

Analisis en profundidad de los 8 bytes que seguian a `VDP_REG1_PENDING`
sin identificar (`$02, $E2, $06, $80, $00, $36, $07, $11`). Se
consideraron 2 hipotesis en competencia:

1. **Codigo muerto**: decodifican en 4 instrucciones Z80 validas
   (`LD (BC),A` / `JP PO,$8006` / `NOP` / `LD (HL),$07`) + 1 byte
   incompleto (`$11`, inicio de `LD DE,nnnn` cuyo operando cae ya
   dentro de `portada_patron.img`). Descartada: el destino del salto,
   `$8006`, cae ANTES de donde empieza `MADMIX1.BIN` (`ORG $83F9`) --
   una zona vacia sin ningun codigo real conocido, sin sentido como
   destino de un `JP`.
2. **Tabla de registros R0-R7 del VDP para SCREEN 2**: `R1=$E2`
   (pantalla encendida, coincide con el valor que usan
   `QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON`), `R2=$06` (tabla de nombres
   en `$1800`, `$1800/$400=6`), `R3=$80` (tabla de color en `$2000`,
   bit7=bloque alto), `R4=$00` (tabla de patrones en `$0000`) --
   los 4 coinciden EXACTOS con la disposicion de VRAM que
   `PORTADA_INIT` fija a mano por encima (mismo fichero, unas pocas
   lineas antes). Demasiada coincidencia para ser azar.

Se descarto ademas que el acceso a `VDP_REG1_PENDING` (byte anterior,
`$10E4`) pudiera tocar estos 8 bytes de forma indirecta: sus 3
referencias reales (`madmix1_body.asm` ISR + 2 sitios en
`QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON`) usan las 3 direccionamiento
absoluto directo (`LD A,(VDP_REG1_PENDING)`/`LD (VDP_REG1_PENDING),A`,
opcodes de 3 bytes con dato final `$E4,$10`), ninguna usa puntero
(`HL`) que pudiera desbordar hacia direcciones superiores.

**Decision del usuario**: la hipotesis de tabla de registros VDP es
"la mas razonable, demasiados datos coincidentes". Etiquetada como
`VDP_SCR2_REGS_TABLE` con comentario por registro (R0-R7) y nota
explicita de que sigue sin lector confirmado -- no se ha encontrado
ningun bucle en ninguno de los ficheros fuente (`madmix_scr_body.asm`,
`madmix1_body.asm`, `load_disk/`, `load_cas/`) que la lea; la
explicacion mas plausible es que la pantalla ya llega configurada asi
por el `SCREEN 2` de MSX-BASIC (ejecutado por `AUTOEXEC.BAS`/
`MADMIX.BAS` antes del `BLOAD`), y esta tabla seria una copia sin usar
por el propio juego (resto de una version anterior que la aplicaba con
un bucle generico, luego sustituida por los `OUT` manuales que se ven
en `PORTADA_INIT`/`VDP_WAIT_READY`/`VDP_ENABLE_DISPLAY`).

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas` e inventario HTML
regenerados: 731 etiquetas (antes 730), categoria `dato` sube de 225 a
226 por la nueva etiqueta.



### Ronda adicional: el nivel oculto SI tiene registro real en `LEVEL_TABLE` -- era el registro 15, mal etiquetado como "20 bytes sin identificar"

El usuario pidio analizar `$5AD5-$5AE8` (20 bytes documentados hasta
ahora como "datos sin identificar, antes del primer tramo de codigo"
de la zona de menu/creditos). La pista clave: `LEVEL_TABLE` termina
EXACTO en `$5AD5` (300 bytes = 15 registros de 20 bytes cada uno) --
estos 20 bytes tienen el mismo tamano EXACTO que un registro de nivel.

**Decodificados con el mismo formato de campo que los 15 registros
documentados**:

```
DW $48BC, $50BC, $50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
DB 18, $01               ; campo6=filas variables (total=21), campo7 sin identificar
DB 3, 1, 1                ; items tipo 3/1/2
DB $96                    ; duracion parpadeo (150 fotogramas)
DB $3F                     ; tile comodin
DB $60, $30                ; fila/columna de referencia inicial
DB $48, $10                ; offsets 15-16, sin identificar (igual que en el resto)
DB $70                     ; icono HUD
DW 165                     ; objetivo de bolitas
```

`$48BC` es EXACTO `BODY_HIDDEN_48BC` (el 15Âº laberinto, ya confirmado
jugable en una sesion anterior parcheando una copia del `.dsk`).
`$50BC` es EXACTO `HEADER_50BC` (la misma cabecera compartida que usan
los niveles 0/1). Todos los demas campos caen en rangos identicos a
los del resto de niveles (tile comodin `$3F`, icono HUD `$70` --
mismos valores que los niveles 0/1). **No es ruido: es un registro de
nivel completo, valido y bien formado.**

**Y es ALCANZABLE en partida normal**, no solo "compatible por
formato". Verificado cruzando 2 rutinas:

- `LEVEL_LOADER` (`madmix_scr_body.asm`, `$5A76e` aprox.) calcula la
  direccion del registro como `LEVEL_TABLE + CURRENT_LEVEL*20` (bucle
  que suma 20, `CURRENT_LEVEL` veces) -- **sin ningun tope propio**,
  el comentario que decia "numero de nivel actual (1-14, el 0 esta
  muerto)" no reflejaba el rango real usado por el codigo.
- `IML_90B7` (`madmix1_body.asm`), al completar un nivel: `INC (HL)`
  sobre `CURRENT_LEVEL`, luego `CP $10` (16) -- si NO es 16, continua
  SIN resetear. Es decir: al completar el nivel 14, `CURRENT_LEVEL`
  pasa a 15, la comprobacion (`15 != 16`) NO resetea, y la siguiente
  carga de nivel usa `CURRENT_LEVEL=15`, leyendo exactamente este
  registro. Solo se resetea a 1 la vez SIGUIENTE, si se completa
  TAMBIEN el nivel 15.

**Conclusion**: el juego real tiene **15 niveles jugables**, no 14 --
el ultimo (el laberinto con forma de comecocos, ya renderizado en
`recursos/nivel_oculto.html`) se juega de verdad completando los 14
niveles "normales" en una sola partida sin perder el ciclo. La
seccion antigua de este mismo documento ("PENDIENTE DE RESOLVER: 15
huecos... el nivel oculto no tiene ningun hueco que lo referencie")
proponia construir un registro nuevo a mano para lograr esto -- esa
propuesta queda **obsoleta**: el registro ya existia en el binario
original desde siempre, solo estaba mal clasificado.

**Cambios**: en `madmix_scr_body.asm`, el bloque de 20 bytes se
reescribe con `DW BODY_HIDDEN_48BC, HEADER_50BC, HEADER_50BC` + los
campos restantes desglosados igual que el resto de niveles (ya no es
un `DB` anonimo, el ensamblador resuelve los punteros); comentario de
cabecera de `LEVEL_TABLE` actualizado (300->320 bytes, 15->16
registros, "14 niveles"->"15 niveles"); comentario de `LEVEL_LOADER`
corregido (rango real 1-15); comentario de `IML_90B7` ampliado
explicando el porque no resetea en 15. `README.md` actualizado (arbol
de ficheros, descripcion de `niveles.html`) para reflejar 15 niveles
reales en vez de "14 + 1 oculto sin usar".

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- son solo etiquetas/comentarios
sobre bytes ya existentes, cero cambios de contenido. `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 731 etiquetas (este
registro no crea una etiqueta nueva, sigue el mismo patron anonimo
que el resto de registros de `LEVEL_TABLE`, que tampoco tienen
etiqueta individual por nivel).

**Pendiente, menor**: seria interesante en el futuro renderizar/
contar bolitas reales del laberinto oculto (`data/niveles/`, si se
llega a extraer como fichero propio como los demas niveles) contra el
objetivo `165` recien decodificado, para una verificacion cruzada
adicional -- no bloqueante, el hallazgo ya esta confirmado por la
coincidencia exacta de los punteros de cuerpo/cabecera.



### Ronda adicional: `body_hidden_48bc.bin` renombrado a `body_l15.bin`, HTML de niveles actualizado, y confirmada la estructura cabecera+cuerpo+pie

Tras confirmar que el nivel 15 (antes "oculto") tiene registro real en
`LEVEL_TABLE`, se renombra el fichero y la etiqueta para que dejen de
sonar a "hallazgo aparte" y pasen a ser un nivel mas, igual que
`BODY_L01`..`BODY_L14`:

- `data/niveles/body_hidden_48bc.bin` -> `data/niveles/body_l15.bin`
  (mismos 576 bytes, sin cambios de contenido). `.txt` gemelo
  regenerado con `mmlvl_tool.py disasm` (18 filas x 32 columnas).
- Etiqueta `BODY_HIDDEN_48BC` -> `BODY_L15` en `madmix_scr_body.asm`
  (definicion + 3 referencias: comentario de cabecera de niveles,
  comentario de cabecera de `LEVEL_TABLE`, y el propio registro 15) y
  en `madmix1_body.asm` (comentario cruzado de `IML_90B7`).
- **Verificacion cruzada exacta**: `mmlvl_tool.py check-bolitas
  body_l15.txt 15` cuenta **165 bolitas reales** en el cuerpo, que
  coincide EXACTO con el objetivo de 165 decodificado en el registro
  de `LEVEL_TABLE` -- confirma el hallazgo del todo, mas alla de la
  coincidencia de punteros ya verificada. Se actualizo tambien el tope
  duro de `mmlvl_tool.py` (antes `>= 15` registros al leer
  `LEVEL_TABLE`, ahora `>= 16`) y su docstring (rango de nivel 0-15).

**Duda planteada por el usuario, verificada en el codigo**: cada nivel
NO se compone solo de cabecera+cuerpo -- `LEVEL_LOADER`
(`madmix_scr_body.asm`) hace 3 copias en este orden: cabecera ARRIBA
(offset 2, 96 bytes) -> cuerpo (offset 0, filas variables) -> cabecera
ABAJO (offset 4, otros 96 bytes, un autentico PIE identico en formato
a la cabecera). Confirmado ademas que, en los 16 registros de
`LEVEL_TABLE` (incluido el nuevo del nivel 15), cabecera-arriba y
cabecera-abajo son SIEMPRE el mismo puntero -- nunca difieren.

**`recursos/niveles.html` actualizado**: el nivel 15 pasa a ser una
entrada normal mas de `LEVELS` (compuesta con `header_50bc.bin` +
`body_l15.bin`, igual criterio "cabecera-arriba + cuerpo, sin pie" que
usan las otras 15 entradas), mostrada AL FINAL como "Nivel 15" con un
aviso explicando la resolucion -- se elimina el objeto `HIDDEN_LEVEL`
aparte, la funcion `buildHiddenLevelCard()`, el gancho de insercion
`i===10` (que lo colocaba en su posicion real de memoria, entre nivel
10 y 11) y las clases CSS `.hidden-level`/`.badge-hidden`, ya sin uso.
Las 2 notas de introduccion del HTML se reescriben para reflejar la
conclusion correcta (16 registros, no 15; el "pie" repetido; nivel 15
real y jugable, no oculto).

**`recursos/editor_niveles.html`**: el texto descriptivo del nivel 15
se corrigio (nombre de fichero, objetivo real de bolitas, alcanzable
en partida normal). El bloque de datos incrustado (`LEVEL_FILES`,
JSON con hex de cada `.bin` generado en una sesion pasada sin script
generador conocido) sigue usando el nombre/metadatos antiguos
(`ballTarget: null`, `hiddenUnwired: true`) -- **pendiente**, no
tocado a mano por riesgo de corromper el hex; se deja anotado en el
propio HTML.

**Verificado**: recompilado sin errores, mismos diffs de siempre en
ambos binarios (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 731 etiquetas.



### Ronda adicional: `ITEM_TABLE_POS_511C` reanalizada -- estructura de 7 bytes confirmada, corregido un campo mal identificado, y 2 tablas auxiliares etiquetadas por primera vez

El usuario pidio reanalizar `ITEM_TABLE_POS_511C` y el bloque
siguiente (170 bytes en `$5154-$51FD`) para reorganizarlos con
comentarios reales. Cruzando `HELPER_5278`/`HELPER_53A2`/`TABLE_INIT`
con `ITEM_TABLE_1`/`ITEM_TABLE_2` (misma estructura de 7 bytes,
confirmada) se establecio el formato real de cada una de las 8
entradas:

```
offset 0: posicion X (loseta entera)
offset 1: posicion Y (loseta entera)
offset 2: modo/comportamiento (0=persiguiendo activamente -- unico
          valor real de items tipo 3; 1/2="plantado", exclusivos de
          ITEM_TABLE_1/2, nunca de esta tabla)
offset 3: codigo de direccion de movimiento en curso (1/2/4/8)
offset 4: subposicion X (parte fraccional)
offset 5: subposicion Y (parte fraccional)
offset 6: fase de animacion (0-3, rotativa)
```

**Correccion importante**: el offset 6 se documentaba en una ronda
antigua como "campo final variable (tipo de item, 0-3)" -- releyendo
`R51FE_MAIN` se confirma que en realidad es la FASE DE ANIMACION
(`LD A,(IX+6); INC A; AND $03; LD (IX+6),A`, incrementada cada vez que
se procesa la entrada) -- los valores de compilacion distintos entre
las 8 entradas (1,2,3,1,2,1,0,1) son solo para que no animen todas
sincronizadas, no un "tipo" de nada.

**El bloque de 170 bytes ($5154-$51FD) resulto tener 3 partes, no 2**:

1. `ITEM_MODE_SPRITE_PTRS` ($5154, 32 bytes = 16 palabras, etiqueta
   nueva): indexada por `(offset2 AND $0F)*2` desde `R51FE_MAIN`. En
   la practica SOLO la entrada 0 se consulta jamas (offset2 nunca
   cambia de 0 para items tipo 3) -- y esa entrada 0 es
   autorreferencial (`$5156`, cae dentro de la propia tabla). Las
   entradas 1-15 (nunca alcanzadas en tiempo real) son candidatas a
   herencia de una version anterior del motor.
2. **Hueco sin explicar de 10 bytes** ($5174-$517D:
   `A2,A2,23,23,24,24,1F,1F,20,20`) -- descubierto al recalcular con
   precision donde arranca la siguiente tabla real (`$517E`, no
   `$5174` como sugeria el comentario antiguo de "32 bytes"). Tiene la
   misma "forma" (pares de bytes repetidos) que `ITEM_MODE_SPRITE_PTRS`
   pero cae fuera de su rango indexable y antes de la tabla siguiente
   -- sin ninguna referencia real encontrada.
3. `ITEM_DIR_CHOICE_TABLE` ($517E, 128 bytes, etiqueta nueva):
   indexada por `HELPER_5278` como
   `(direcciones libres)<<3 | (gate alineamiento)<<1 | (bit aleatorio)`
   -> direccion final elegida. Contenido verificado coherente con el
   algoritmo, sin decodificar fila a fila (128 combinaciones posibles).

Sustituidas las 2 referencias hex sueltas (`LD HL,$5154` en
`R51FE_MAIN`, `LD HL,$517E` en `HELPER_5278`) por las etiquetas
nuevas.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- son solo etiquetas/comentarios
sobre bytes ya existentes, cero cambios de contenido. `.dsk`/`.cas`/
inventario HTML regenerados: 733 etiquetas (antes 731, +2 por
`ITEM_MODE_SPRITE_PTRS`/`ITEM_DIR_CHOICE_TABLE`), categoria `dato`
sube de 226 a 228.



### Ronda adicional: `ITEM_DIR_CHOICE_TABLE` totalmente decodificada -- es dato, y su "gate" resulto ser la direccion previa, no un simple flag de alineamiento

El usuario pregunto si `ITEM_DIR_CHOICE_TABLE` era codigo o datos.
Confirmado que es DATO puro (solo se lee con `LD A,(HL)`, ningun
`JP`/`JR`/`CALL` de todo el proyecto apunta ahi).

Al reorganizar sus 128 bytes en 16 bloques de 8 (uno por combinacion
de "direcciones libres", el bitmask que ya se sabia que forma la
mitad alta del indice) se detecto que el comentario de la ronda
anterior ("gate de alineamiento", un simple bit 0/1) era INCOMPLETO:
siguiendo el codigo real (`H5278_531E`), el valor E que aporta los
bits 1-2 del indice sale de `TILE_DISPATCH_TABLE[(IX+3)]` (la
direccion de movimiento YA en curso, offset 3 del registro de 7 bytes
de items) -- no de un flag binario. `TILE_DISPATCH_TABLE` en los
indices 0/1/2/4/8 vale `$00/$01/$02/$03/$04`; tras `SUB $01` (con
clamp a 0 si hay acarreo) y `ADD A,A` (doblado), el resultado es
`0/0/2/4/6` segun la direccion previa sea
ninguna-o-derecha/izquierda/abajo/arriba respectivamente -- es decir,
SI ocupa el bit 2 del indice final en ciertos casos (contrario a lo
que se penso: no hay "mitad de la tabla nunca leida", los 128 bytes
SI son alcanzables).

**Estructura real, confirmada byte a byte**: cada uno de los 16
bloques de 8 bytes se divide en 4 pares (bit aleatorio desempata
dentro del par): par0 = si no habia direccion previa o iba a la
derecha, par1 = si iba a la izquierda, par2 = si iba abajo, par3 = si
iba arriba. El contenido real confirma que es una tabla de "mantener
la direccion de movimiento si sigue libre, si no elegir otra libre"
(sesgo de continuidad): cuando solo hay UNA direccion libre en el
bloque, los 8 bytes son identicos a esa direccion sin importar cual
fuera la anterior; cuando hay varias, cada par tiende a devolver la
misma direccion que se traia si esta en el conjunto de libres.

Reescrita la tabla completa como 16 `DB` de 8 bytes (antes filas de 16
bytes sin alinear a esta estructura), cada una comentada con su
bitmask de direcciones libres y el detalle de los 4 pares. Corregidos
2 comentarios de codigo que aun hablaban de "gate de alineamiento"
(en `H5278_531E`/`H5278_532D` y en el `LD HL,ITEM_DIR_CHOICE_TABLE`)
para reflejar que es la direccion previa categorizada.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- la reestructuracion preserva
exactamente los mismos 128 bytes en el mismo orden, cero cambios de
contenido. `.dsk`/`.cas`/inventario HTML regenerados: mismo total de
733 etiquetas (no se aÃ±aden etiquetas nuevas, solo se reorganizan
filas `DB` existentes).



### Ronda adicional: `ITEM_MODE_SPRITE_PTRS` resuelta por completo -- el "puntero autorreferencial" era el mecanismo real, y confirma el volteo horizontal (bit7) sin trazado en vivo

El usuario pidio reanalizar `ITEM_MODE_SPRITE_PTRS` para organizarla y
comentarla. La ronda anterior ya habia detectado que la entrada 0
apuntaba dentro de la propia tabla pero lo dejo como "candidato,
detalle sin confirmar". Rastreando el uso real de la palabra leida
(registro DE) en `R51FE_MAIN` se confirma que NO es una eleccion entre
"16 punteros de modo": es UN SOLO puntero (autorreferencial, a
proposito) al que se le SUMA `direccion(1-4)*4 + fase(0-3)` para leer
el sprite final -- es decir, la tabla completa es: puntero a si misma
(2 bytes) + los datos reales de sprite para las 4 direcciones (2
fotogramas cada una).

**Correccion de un comentario existente (no introducido en esta
sesion)**: `HELPER_5278` etiquetaba `C = velocidad de paso segun
alineamiento` tras la consulta a `TILE_DISPATCH_TABLE` -- FALSO en
este contexto: esa misma tabla, indexada por la direccion final
elegida ($01/$02/$04/$08), la convierte en un CODIGO COMPACTO 1-4
(derecha/izquierda/abajo/arriba) que se devuelve al llamador y se usa
para indexar tablas de sprite (`ITEM_MODE_SPRITE_PTRS`,
`ITEM_ANIM_TABLE_1`, `ITEM_ANIM_TABLE_2`) -- confirmado cruzando los 3
consumidores, los 3 coinciden exactamente en el mismo patron
`direccion(1-4)*4+fase(0-3)`.

**Hallazgo colateral importante**: el grupo "izquierda" de las 3
tablas (`ITEM_MODE_SPRITE_PTRS`, `ITEM_ANIM_TABLE_1`,
`ITEM_ANIM_TABLE_2`) es SIEMPRE el grupo "derecha" con el bit7 puesto
-- confirma, por analisis estatico puro y sin necesidad de trazado en
vivo, el mecanismo de "no hay sprites hacia la izquierda, se voltea
horizontalmente el de la derecha" ya documentado como hipotesis
aparcada para los sprites de personajes. Aqui queda demostrado de
forma independiente y concluyente.

**Reestructuracion aplicada**: las 3 tablas (`ITEM_MODE_SPRITE_PTRS`,
`ITEM_ANIM_TABLE_1`, `ITEM_ANIM_TABLE_2`) se reescriben con una fila
`DB` de 4 bytes por direccion (offset "nunca leido" + derecha +
izquierda + abajo + arriba), con comentario explicito de cual es cual
y por que el primer grupo nunca se lee (la direccion jamas vale 0).
`ITEM_MODE_SPRITE_PTRS` ademas documenta su cola de 10 bytes propia
(offset 22-31, fuera de rango) junto con el hueco de 10 bytes ya
conocido de la ronda anterior ($5174-$517D) como un unico tramo de 20
bytes sin explicar. Corregidos tambien 2 comentarios inline
(`R51FE_MAIN` y `HELPER_5278`) que quedaban desactualizados con la
vieja interpretacion.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- la reestructuracion preserva
exactamente los mismos bytes, cero cambios de contenido. `.dsk`/
`.cas`/inventario HTML regenerados: mismo total de 733 etiquetas (no
se aÃ±aden etiquetas nuevas, solo se reorganizan filas `DB` y
comentarios existentes).



### Ronda adicional: los 10 bytes finales del hueco ($5174-$517D) analizados como codigo vs. datos -- candidato a sprite huerfano, no codigo

El usuario pregunto si `DB $A2,$A2,$23,$23,$24,$24,$1F,$1F,$20,$20`
(el hueco sin explicar entre `ITEM_MODE_SPRITE_PTRS` e
`ITEM_DIR_CHOICE_TABLE`) era codigo o datos.

**Desensamblado probado**: decodifica COMPLETO en los 10 bytes exactos
(sin instruccion a medias) como `AND D`/`AND D`/`INC HL`/`INC HL`/
`INC H`/`INC H`/`RRA`/`RRA`/`JR NZ,+32` -- pero la secuencia no tiene
ningun sentido funcional (instrucciones identicas repetidas sin
proposito reconocible, muy distinto del codigo muerto real ya
confirmado en este proyecto, `POP HL`/`EI`/`RET`, que si es una
secuencia con sentido).

**Como datos**, en cambio, encaja perfecto: son 5 PARES de bytes
identicos (`$A2,$A2`/`$23,$23`/`$24,$24`/`$1F,$1F`/`$20,$20`) --
exactamente la misma convencion de "2 fotogramas repetidos" que usan
`ITEM_MODE_SPRITE_PTRS`/`ITEM_ANIM_TABLE_1`/`ITEM_ANIM_TABLE_2`. Ademas
`$1F`/`$20` coinciden EXACTOS con los sprites de "arriba" ya
documentados en `ITEM_MODE_SPRITE_PTRS`, y `$A2` es `$22` con el bit7
puesto (mismo patron de volteo horizontal confirmado en la ronda
anterior). Sin ninguna referencia real encontrada en el codigo (ni
directa ni indirecta).

**Conclusion**: candidato fuerte a datos de sprite huerfanos (quiza
una 5a entrada o variante descartada), no codigo. Actualizado el
comentario (cabecera de seccion + la propia linea `DB`) para
reflejarlo, en vez de "hueco sin explicar" a secas.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo cambio de comentarios, cero
cambios de contenido. `.dsk`/`.cas`/inventario HTML regenerados: mismo
total de 733 etiquetas.



### Ronda adicional: los 3 tipos de "item movil" identificados como personajes reales -- fantasma, mariquita y "repugnantoso"

Cruzando los indices de sprite exactos que usa cada una de las 3
tablas de items moviles (`ITEM_TABLE_POS_511C`/`ITEM_TABLE_1`/
`ITEM_TABLE_2`, ya analizadas en rondas anteriores) contra el catalogo
de sprites de personajes ya identificado por el usuario en una sesion
anterior (`madmix1_body.asm`, `SPR27`.. `SPR53`), se confirmo la
identidad real de los 3 "tipos":

- **Tipo 3** (`ITEM_TABLE_POS_511C`, 8 entradas) = **FANTASMA**.
  Sprites `$1B/$1C`=`SPR27/28_FANTASMA_DER`, `$1D/$1E`=
  `SPR29/30_FANTASMA_ABAJO`, `$1F/$20`=`SPR31/32_FANTASMA_ARRIBA`
  (izquierda = derecha volteada). Confirma que `R51FE_MAIN`/
  `HELPER_5278` (con su tabla de "mantener direccion si se puede",
  `ITEM_DIR_CHOICE_TABLE`) es la IA de movimiento de los fantasmas.
  Maximo arquitectonico: 8 fantasmas simultaneos (tamano fijo de la
  tabla); cuantos estan realmente activos en un nivel concreto lo
  decide `LEVEL_REC_ITEM3_COUNT` (offset 8 del registro de nivel, 0-8).
- **Tipo 1** (`ITEM_TABLE_1`, 2 entradas) = **MARIQUITA**. Sprites
  `$27`=`SPR39_MARIQUITA_DER`, `$25`=`SPR37_MARIQUITA_ABAJO`,
  `$26`=`SPR38_MARIQUITA_ARRIBA`. Coincide exacto con "mariquita
  reponia bolas" ya documentado por el usuario, y con el efecto ya
  confirmado del manejador (regenera bolitas ya comidas).
- **Tipo 2** (`ITEM_TABLE_2`, 8 entradas) = **"REPUGNANTOSO"**
  (la "apisonadora" mencionada por el usuario). Sprites
  `$2D-$2F`=`SPR45-47_REPUGNANTE_DER`, `$30-$32`=
  `SPR48-50_REPUGNANTE_ABAJO`, `$33-$35`=`SPR51-53_REPUGNANTE_ARRIBA`.
  Coincide con el efecto ya confirmado (CONTRARIO a la mariquita:
  convierte bolitas normales en bolas clavadas en vez de regenerarlas).

**Renombradas las etiquetas de mariquita y repugnante** (el usuario
pidio explicitamente estas 2, dejando fantasma para una posible ronda
futura):

| Antes | Despues |
|-------|---------|
| `ITEM_TABLE_1` | `ITEM_TABLE_MARIQUITA` |
| `ITEM_HANDLER_1` | `HNDLR_MARIQUITA` |
| `ITEM_ANIM_TABLE_1` | `ITEM_ANIM_TABLE_MARIQUITA` |
| `LEVEL_REC_ITEM1_COUNT` | `LEVEL_REC_MARIQUITA_COUNT` |
| `IH1_LOOP`/`IH1_54DB`/`IH1_54DC`/`IH1_NEXT` | `MARIQUITA_LOOP`/`MARIQUITA_SKIP`/`MARIQUITA_STORE`/`MARIQUITA_NEXT` |
| `ITEM_TABLE_2` | `ITEM_TABLE_REPUGNANTE` |
| `ITEM_HANDLER_2` | `HNDLR_REPUGNANTE` |
| `ITEM_ANIM_TABLE_2` | `ITEM_ANIM_TABLE_REPUGNANTE` |
| `LEVEL_REC_ITEM2_COUNT` | `LEVEL_REC_REPUGNANTE_COUNT` |
| `IH2_LOOP`/`IH2_55F4`/`IH2_55F5`/`IH2_NEXT` | `REPUGNANTE_LOOP`/`REPUGNANTE_SKIP`/`REPUGNANTE_STORE`/`REPUGNANTE_NEXT` |

77 sustituciones (75 en `madmix_scr_body.asm`, 2 en `madmix1_body.asm`,
palabra completa, tocando tambien comentarios). Actualizados ademas
los bloques de comentario de cabecera de `HNDLR_MARIQUITA`/
`HNDLR_REPUGNANTE` y el campo `LEVEL_REC_ITEM3_COUNT` para citar la
identidad confirmada de personaje en vez de solo "tipo N".

`ITEM_TABLE_POS_511C` (fantasma) queda sin renombrar por ahora --
identidad confirmada mediante el comentario, pendiente de una posible
ronda futura si se pide.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/inventario HTML
regenerados: mismo total de 733 etiquetas (renombrado puro, sin
etiquetas nuevas ni eliminadas).



### Ronda adicional: `ITEM_TABLE_POS_511C` y su manejador renombrados a FANTASMA, cerrando el trio mariquita/repugnante/fantasma

Completando la ronda anterior (mariquita/repugnante), el usuario pidio
renombrar tambien la tabla/manejador de tipo 3, ya confirmada como
FANTASMA por los sprites `SPR27-32_FANTASMA_*`.

| Antes | Despues |
|-------|---------|
| `ITEM_TABLE_POS_511C` | `ITEM_TABLE_FANTASMA` |
| `R51FE_MAIN` | `HNDLR_FANTASMA` (mismo patron `HNDLR_` que mariquita/repugnante) |
| `R51FE_LOOP` | `FANTASMA_LOOP` |
| `R51FE_NEXT` | `FANTASMA_NEXT` |
| `R51FE_END` | `FANTASMA_END` |
| `R51FE_5242` | `FANTASMA_SPECIAL_ADJUST` |
| `R51FE_5248` | `FANTASMA_DRAW` |
| `LEVEL_REC_ITEM3_COUNT` | `LEVEL_REC_FANTASMA_COUNT` |
| `ITEM_MODE_SPRITE_PTRS` | `ITEM_ANIM_TABLE_FANTASMA` (unifica el nombre con `ITEM_ANIM_TABLE_MARIQUITA`/`ITEM_ANIM_TABLE_REPUGNANTE`, incluso siendo la unica autorreferencial de las 3) |

`HELPER_5278`/`HELPER_53A2`/`HELPER_5414`/`ITEM_DIR_CHOICE_TABLE` se
dejan SIN renombrar a proposito: son infraestructura de movimiento
COMPARTIDA por las 3 criaturas (mariquita, repugnante y fantasma la
llaman igual), no exclusiva del fantasma.

48 sustituciones en `madmix_scr_body.asm` (0 en `madmix1_body.asm`,
sin referencias cruzadas). Se encontraron y corrigieron ademas 3
artefactos textuales sueltos de la ronda anterior (abreviaturas tipo
"HNDLR_MARIQUITA/2" que eran resto de la vieja notacion
"ITEM_HANDLER_1/2" antes del rename, ahora expandidas a los 2/3
nombres completos). Anadida una nota de "IDENTIDAD CONFIRMADA" en la
cabecera de `ITEM_ANIM_TABLE_FANTASMA` citando los `SPR27-32` exactos.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/inventario HTML
regenerados: mismo total de 733 etiquetas (renombrado puro).

Con esto, los 3 tipos de "item movil" del motor quedan con nombre de
personaje real en vez de "tipo 1/2/3": `ITEM_TABLE_FANTASMA`/
`HNDLR_FANTASMA`, `ITEM_TABLE_MARIQUITA`/`HNDLR_MARIQUITA`,
`ITEM_TABLE_REPUGNANTE`/`HNDLR_REPUGNANTE`.



### Ronda adicional: `recursos/flujo_programa.html` puesto al dia -- las tablas 3 y 4 (manejador por tipo de loseta / variables de estado) llevaban varias rondas de renombrado sin actualizar

El usuario seÃ±alo que la seccion de "datos" del HTML de flujo seguia
referenciando solo direcciones hexadecimales sin el nombre de
etiqueta. Revisando el fichero se encontraron 2 tablas escritas a mano
(no generadas por `gen_inventory.py`, que solo rellena el array
`INVENTORY` de la seccion 5) completamente desactualizadas:

- **Tabla 3 (despachador de tipo de loseta)**: usaba los nombres
  antiguos `HANDLER_2EB7`/`HANDLER_2EC7`/.../`ML_3252`/`ML_3299`/
  `ML_32E2` (de antes de las 2 rondas de renombrado a `HNDLR_*`).
  Reescrita fila por fila con los 20 tipos (antes agrupados a bulto
  "0-7 sin detallar"), nombres actuales, y descripciones corregidas
  (p.ej. tipo 10 ya no dice "candidato a bola de poder comida" sino
  "pista del avion, CORREGIDO" -- esa correccion ya estaba en
  `FINDINGS.md` desde hace tiempo pero nunca llego a este HTML).
- **Tabla 4 (variables de estado compartido)**: 11 filas que solo
  mostraban la direccion hex, sin ninguna etiqueta. Completadas todas
  con el nombre real (`PACMAN_POS`, `CURRENT_LEVEL`,
  `BALLS_EATEN_COUNT`, `SPECIAL_MODE_FLAG/COUNTDOWN/ACTIVE`,
  `MOVE_DIRECTION`, `DIR_BEHAVIOR_SELECTOR`, `LIVES_REMAINING`,
  `SCORE_ACCUM`, `SPECIAL_MODE`, `HINT_POS_TABLE`). Las 2 excepciones
  reales sin etiqueta (`$6128`, `$FC50`) se dejan en hex pero con nota
  explicita de "sin etiqueta propia" en vez de aparentar que la tienen
  -- honestidad sobre lo que de verdad no esta simbolizado en el
  codigo fuente. De paso se actualizo `$FC60`->`$FC50` (el fix de bug
  ya documentado) y se anadio que el buffer es cabecera+cuerpo+PIE (
  hallazgo de una ronda reciente, tampoco reflejado hasta ahora aqui).
- Tambien corregida una caja del diagrama de flujo (seccion 1) que
  decia `ITEM_HANDLER_1/2` con descripcion "items especiales (bola de
  poder, hipopotamo...)" -- ambas cosas desactualizadas/incorrectas,
  ahora dice `HNDLR_MARIQUITA/HNDLR_REPUGNANTE` con la descripcion
  real confirmada en la ronda de identificacion de personajes.

No hay cambios de codigo fuente ni de bytes compilados en esta ronda
-- es documentacion pura (HTML). Revisado el resto del fichero por si
quedaban mas referencias desactualizadas: `TRAPDOOR_ANIM_EXIT` (dentro
del array `INVENTORY`) es la unica mencion de "TRAPDOOR_ANIM" que
queda, y es correcta (esa etiqueta se dejo sin renombrar a proposito
en su ronda, por ser una cola comun ya con nombre descriptivo).
`GHOST_HINT_HANDLER`/`TRAPDOOR_FLIP_TABLE` (mencionadas en el
diagrama) tambien verificadas, sigen siendo sus nombres reales
actuales.



### Ronda adicional: `LD IX, $511C` en `TABLE_INIT` sustituido por la etiqueta real (se habia quedado en hex pese a ya tener nombre)

El usuario detecto que `TABLE_INIT` seguia usando `$511C` como hex
literal aunque el propio comentario ya decia "ITEM_TABLE_FANTASMA (ya
tiene etiqueta propia...)" -- se le habia escapado a las rondas de
renombrado anteriores porque, a diferencia de `ITEM_TABLE_MARIQUITA`/
`ITEM_TABLE_REPUGNANTE` (que en esa misma funcion YA se referenciaban
por nombre desde el principio), esta era la unica de las 3 que seguia
en hex puro. Sustituida por `ITEM_TABLE_FANTASMA`.

De paso, renombrados los 3 bucles de `TABLE_INIT` (tambien
hex-based, mismo problema de fondo): `TI_511C_LOOP`/`TI_549B_LOOP`/
`TI_5588_LOOP` -> `TI_FANTASMA_LOOP`/`TI_MARIQUITA_LOOP`/
`TI_REPUGNANTE_LOOP`.

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/inventario HTML
regenerados: mismo total de 733 etiquetas.



### Ronda adicional: `ITEM_EXTRA_TABLE` reestructurada -- resuelto el mecanismo de "offset de entrada" y detectado un truco de reutilizacion de byte

El usuario pidio profundizar en `ITEM_EXTRA_TABLE` ($56F5, 126 bytes,
consultada por `ITEM_TIMER_TICK`) para poder estructurarla y
comentarla. Cruzando los 7 valores reales que le pasan los 4
llamadores (`GHOST_HINT_HANDLER`, `IE_581B`, `IE_584A`, `IE_5870`) a
`CLEAR_5773_AND_SET` via el registro `C`, se confirmo el mecanismo
completo:

**El valor de C NO es un contador generico -- sus 7 bits bajos (AND
$7F) son el OFFSET DE ENTRADA directo dentro de la tabla.** Esto
permite que cada evento entre en un punto distinto de una misma
secuencia: desde el principio (animacion larga) o saltando directo a
la cola comun de cierre (para un "flash" corto). El bit7 de C
distingue el contexto (`GHOST_HINT_HANDLER` vs `ITEM_EFFECT`) segun
ya documentaba `CLEAR_5773_AND_SET`.

**Estructura real, 3 secuencias terminadas en `$FF`**:
- Secuencia A (offset 1-39): `flecha_derecha`(tile 54) x22 + cierre
  comun + `linea_electrica_puerta_fantasmas_a`(56) x10 + `$FF`.
- Secuencia B (offset 40-84): 5 bytes sin descifrar (`$0F,$8D,$0E,
  $0D,$0F`) + patron repetido sin descifrar (`$03,$00,$06,$80` x6) +
  ciclo de 4 iconos (`pista_avion`(58)/`item_suelo`(59)/`bola_poder`
  (60)/`hipopotamo`(61)) + cierre comun + `$FF`.
- Secuencia C (offset 85-125): `item_herramienta`(62) x24 + cierre
  comun + `pista_tanque_vertical`(55) x10 + `$FF`.
- Cierre comun a las 3: `$28,$28,$29,$29,$2A,$2B[,$2C]` -- esquinas/
  uniones de muro de ladrillo (losetas 40-44 del catalogo).

**Hallazgo del "truco de ahorro de memoria"**: el `$FF` que cierra la
secuencia A (offset 39) se REUTILIZA a proposito como punto de entrada
valido a la secuencia B (entrada real `$A7`, usada por `IE_581B`
cuando el item es hipopotamo) -- funciona porque `ITEM_TIMER_TICK`
solo comprueba "es $FF" en el byte SIGUIENTE al que dibuja, nunca en
el actual.

**Hipotesis fuerte sobre la semantica** (no confirmada visualmente):
las losetas dibujadas son REALES del catalogo del mapa (no sprites
decorativos inventados), dibujadas con `ACTOR_ENGINE` en la posicion
de un "aviso" temporal -- posible "flash de celebracion" que muestra
iconos de power-up al activar un modo especial (secuencia B) o al
sumar puntos/avisar de una pista de trampilla (secuencias A/C y las
colas cortas).

**Cambios aplicados**: 7 etiquetas nuevas (`ITEM_EXTRA_SEQ_A`,
`ITEM_EXTRA_SEQ_A_TAIL`, `ITEM_EXTRA_SEQ_B_ENTRY`,
`ITEM_EXTRA_SEQ_B_MAIN`, `ITEM_EXTRA_SEQ_B_TAIL`, `ITEM_EXTRA_SEQ_C`,
`ITEM_EXTRA_SEQ_C_TAIL`) marcando cada punto de entrada real dentro
del bloque `DB`, con comentario explicando el mecanismo completo en la
cabecera de seccion. Los 7 sitios donde se carga el valor de `C`
(`GHOST_HINT_HANDLER`, `IE_581B` x2, `IE_584A` x2, `IE_5870` x3) se
anotaron con un comentario indicando a que etiqueta corresponde cada
valor hex -- NO se sustituyeron por la etiqueta directamente porque el
byte real combina offset+flag de contexto, no es la direccion
absoluta de la etiqueta (sustituir habria producido un byte
incorrecto).

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- la reestructuracion preserva
exactamente los mismos 126 bytes, cero cambios de contenido. `.dsk`/
`.cas`/inventario HTML regenerados: 740 etiquetas (antes 733, +7 por
las nuevas), categoria `dato` sube de 228 a 235.

**Pendiente**: el tramo de 29 bytes sin descifrar dentro de la
secuencia B (`$0F,$8D,$0E,$0D,$0F` + `$03,$00,$06,$80` x6) sigue sin
explicacion; y la hipotesis del "flash de celebracion" no se ha
confirmado renderizando visualmente.



### Ronda adicional: corregido un comentario antiguo invertido en `CLEAR_5773_AND_SET` (el bit7 de C no era lo que decia)

Explicando a que sirve `ITEM_EXTRA_TABLE` se releyo `CLEAR_5773_AND_SET`
para precisar donde se dibuja cada "destello" y se detecto que el
comentario antiguo ("C con bit7 puesto = caso GHOST_HINT_HANDLER")
estaba AL REVES: de los 7 valores reales verificados en la ronda
anterior, `GHOST_HINT_HANDLER` usa `$4D` (bit7 LIMPIO) mientras que
`IE_581B` usa `$AD`/`$A7` (bit7 PUESTO) -- justo lo contrario de lo
que decia el comentario. Corregido: bit7 puesto = las 2 llamadas de
`IE_581B` (activar modo especial, sale sin guardar posicion); bit7
limpio = `GHOST_HINT_HANDLER`/`IE_584A`/`IE_5870` (SI guardan la
posicion actual del item en la entrada).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
cambio de comentario.



### Ronda adicional: `ITEM_EXTRA_TABLE` renombrada a `ITEM_TABLE_EFECTOS_DESTELLO`

El usuario pidio renombrar `ITEM_EXTRA_TABLE` para que su nombre
refleje su funcion real (efecto visual de destello temporal, no datos
de nivel), siguiendo el patron `ITEM_TABLE_*` ya usado para
fantasma/mariquita/repugnante:

| Antes | Despues |
|-------|---------|
| `ITEM_EXTRA_TABLE` | `ITEM_TABLE_EFECTOS_DESTELLO` |
| `ITEM_EXTRA_SEQ_A` | `EFECTOS_DESTELLO_SEQ_A` |
| `ITEM_EXTRA_SEQ_A_TAIL` | `EFECTOS_DESTELLO_SEQ_A_TAIL` |
| `ITEM_EXTRA_SEQ_B_ENTRY` | `EFECTOS_DESTELLO_SEQ_B_ENTRY` |
| `ITEM_EXTRA_SEQ_B_MAIN` | `EFECTOS_DESTELLO_SEQ_B_MAIN` |
| `ITEM_EXTRA_SEQ_B_TAIL` | `EFECTOS_DESTELLO_SEQ_B_TAIL` |
| `ITEM_EXTRA_SEQ_C` | `EFECTOS_DESTELLO_SEQ_C` |
| `ITEM_EXTRA_SEQ_C_TAIL` | `EFECTOS_DESTELLO_SEQ_C_TAIL` |

22 sustituciones en `madmix_scr_body.asm` (sin referencias cruzadas en
`madmix1_body.asm`).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas (renombrado
puro).



### Ronda adicional: las 7 sub-etiquetas de `ITEM_TABLE_EFECTOS_DESTELLO` pasan de "solo documentacion" a estar REALMENTE referenciadas en el codigo

El usuario seÃ±alo que las 7 sub-etiquetas (`EFECTOS_DESTELLO_SEQ_A`,
`_A_TAIL`, `_B_ENTRY`, `_B_MAIN`, `_B_TAIL`, `_C`, `_C_TAIL`) estaban
sin referencias reales -- eran solo marcadores puestos para
documentar donde empieza cada tramo dentro del `DB`, pero el codigo
seguia usando los valores hex literales (`$4D`, `$AD`, `$A7`, `$6D`,
`$17`, `$55`, `$01`) con un simple comentario indicando a que
etiqueta "corresponderian".

**Se sustituyeron los 7 literales por expresiones de diferencia de
etiquetas**, que el propio ensamblador resuelve a la misma constante
exacta en tiempo de compilacion:

- `LD C, $4D` -> `LD C, EFECTOS_DESTELLO_SEQ_B_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $6D` -> `LD C, EFECTOS_DESTELLO_SEQ_C_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $17` (x2) -> `LD C, EFECTOS_DESTELLO_SEQ_A_TAIL - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $55` -> `LD C, EFECTOS_DESTELLO_SEQ_C - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $01` -> `LD C, EFECTOS_DESTELLO_SEQ_A - ITEM_TABLE_EFECTOS_DESTELLO`
- `LD C, $AD` -> `LD C, (EFECTOS_DESTELLO_SEQ_B_MAIN - ITEM_TABLE_EFECTOS_DESTELLO) | $80`
- `LD C, $A7` -> `LD C, (EFECTOS_DESTELLO_SEQ_B_ENTRY - ITEM_TABLE_EFECTOS_DESTELLO) | $80`

El bit7 (que distingue el contexto "IE_581B, sin guardar posicion" del
resto, ver ronda anterior sobre `CLEAR_5773_AND_SET`) se anade con
`| $80` donde corresponde. Verificado en el `.lst` que las 7
expresiones generan BYTE A BYTE los mismos valores que los literales
que sustituyen (`0E 4D`, `0E AD`, `0E A7`, `0E 6D`, `0E 17`x2, `0E 55`,
`0E 01`).

Con esto, si en el futuro se inserta o quita algun byte de
`ITEM_TABLE_EFECTOS_DESTELLO`, estos 7 puntos de entrada se
recalcularian solos en la siguiente compilacion -- ya no son numeros
magicos independientes que haya que mantener sincronizados a mano.

**Nota sobre el inventario**: `gen_inventory.py` clasifica "funcion"/
"interna" solo por uso literal en `CALL`/`JP`/`JR` -- una referencia
dentro de una expresion aritmetica (`LABEL - LABEL`) no la detecta esa
heuristica, asi que estas 7 etiquetas se siguen contabilizando como
"dato" en el recuento (igual que antes, 740 etiquetas sin cambios) --
la mejora real es que el CODIGO las usa de verdad, no un cambio en la
categoria del inventario.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- cero cambios de
contenido compilado. `.dsk`/`.cas`/inventario HTML regenerados.



### Ronda adicional: `DRAW_TILE_HELPER` renombrada a `DIBUJAR_CAMBIO_LOSETA`

El usuario penso que el nombre en espanol describe mejor la funcion
real (escribe una nueva loseta en el mapa y la redibuja en VRAM,
usada por casi todos los manejadores de tipo de loseta). Renombrada
junto a sus 2 sub-etiquetas internas:

| Antes | Despues |
|-------|---------|
| `DRAW_TILE_HELPER` | `DIBUJAR_CAMBIO_LOSETA` |
| `ML_DRAWTILE_COL_CHECK` | `DIBUJAR_CAMBIO_LOSETA_CHECK_COL` |
| `ML_DRAWTILE_REDRAW` | `DIBUJAR_CAMBIO_LOSETA_REDRAW` |

16 sustituciones en `madmix_scr_body.asm` (sin referencias cruzadas en
`madmix1_body.asm`). Revisados `recursos/flujo_programa.html` y
`recursos/mapa_memoria.html` (memoria: "actualizar HTMLs de
recursos") -- ninguno menciona este nombre, nada que sincronizar.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas (renombrado
puro).



### Ronda adicional: `SCORE_DRAW` renombrada a `DIBUJAR_MARCADOR_PUNTOS`

| Antes | Despues |
|-------|---------|
| `SCORE_DRAW` | `DIBUJAR_MARCADOR_PUNTOS` |
| `SCORE_DRAW_COMMON` | `DIBUJAR_MARCADOR_PUNTOS_COMMON` |
| `SCORE_DRAW_DIGITS` | `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` |

24 sustituciones (11 en `madmix_scr_body.asm`, 13 en
`madmix1_body.asm`, donde vive la definicion real, JT_SLOT7/$8D70).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas.
`recursos/flujo_programa.html` (caja del diagrama de flujo + fila de
la tabla de despacho JT_INIT) y `recursos/mapa_memoria.html` (segmento
0x8D1B-0x8E3C) actualizados con el nombre nuevo.



### Ronda adicional: `HELPER_5278` renombrada a `MOVER_ITEM_MOVIL`

El usuario pidio un nombre descriptivo para `HELPER_5278` (decide
direccion + aplica movimiento para los 3 personajes moviles:
fantasma/mariquita/repugnante). Renombrada a `MOVER_ITEM_MOVIL`.
`HELPER_53A2` (su segundo punto de entrada, solo visibilidad/posicion
VRAM) se deja sin renombrar por ahora -- no se confirmo esa parte de
la propuesta.

17 sustituciones de identificador + **2 sitios donde el codigo aun
usaba el hex literal `CALL $5278`** (en vez del simbolo) tambien
corregidos a `CALL MOVER_ITEM_MOVIL` -- mismo tipo de descuido que
`$511C` en `TABLE_INIT` (ronda anterior).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas.
`recursos/mapa_memoria.html` (segmento 0x51FE-0x5478) actualizado.



### Ronda adicional: sustitucion de 8 palabras de terminologia propia del usuario en las etiquetas de codigo

El usuario pidio sustituir 8 palabras por su propia terminologia en
las etiquetas de codigo (alcance elegido explicitamente via pregunta:
solo `HNDLR_*`/`ITEM_TABLE_*`/`LEVEL_REC_*` y sus sub-etiquetas, SIN
tocar nombres de fichero `.til`/`.spr` ni el catalogo de sprites
`SPR*` de `madmix1_body.asm`):

| Palabra antigua | Palabra nueva |
|------------------|----------------|
| HIPOPOTAMO | HIPODOSO |
| TANQUE | COCOTANQUE |
| AVION | COCONAVE |
| FANTASMA | PELMAZOIDE |
| MARIQUITA | MARICOCO |
| REPUGNANTE | REGPUNANTOSO |
| HERRAMIENTA | EXCAVATOFONO |
| FLECHA | AUTOCOCO |

Aplicado a las 43 etiquetas afectadas (con sus sub-etiquetas: `_EXIT`,
`_LOOP`, `_MODE_CHECK`, `_ACTIVATE`, `_TAIL`, `_SKIP`, `_STORE`,
`_NEXT`, `_DRAW`, `_SPECIAL_ADJUST`, `_END`, `TI_*_LOOP`, etc.), 206
sustituciones en total (203 en `madmix_scr_body.asm`, 3 en
`madmix1_body.asm` -- comentarios que citaban las etiquetas por
nombre). Las menciones en prosa de las mismas palabras en minuscula
(nombres de loseta: "flecha_arriba", "pista_tanque_vertical", "modo
avion"...) y las etiquetas `SPR*_FANTASMA_*`/`SPR*_MARIQUITA_*`/
`SPR*_REPUGNANTE_*` del catalogo de sprites se dejan SIN TOCAR a
proposito (fuera del alcance elegido).

**Verificado**: recompilado sin errores (mismos 2 warnings de
siempre), diffs en la linea base exacta de siempre (7 en
`MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- renombrado puro, cero cambios de
contenido. `.dsk`/`.cas`/inventario HTML regenerados: mismo total de
740 etiquetas. `recursos/flujo_programa.html` (tabla de despacho +
caja del diagrama) y `recursos/mapa_memoria.html` (4 segmentos de la
zona 0x511C-0x5904) actualizados con los nombres nuevos, anotando
"antes X" donde aporta contexto.

**Nota para el futuro**: si se decide extender esta terminologia a los
nombres de fichero (`data/tiles/*.til`, `data/sprites/*.spr`) y al
resto de HTML de recursos, el usuario ya declino ese alcance mayor
esta vez -- sÃ©ria una ronda aparte.



### Ronda adicional: `JT_SLOT2: JP $8440` sustituido por `JP ACTOR_ENGINE` (comentario desactualizado)

El usuario pregunto a donde salta `$8440` (linea 10 de
`madmix1_body.asm`, entrada `JT_SLOT2` de la tabla de saltos). El
comentario decia "sin nombre propio confirmado todavia", pero
`ACTOR_ENGINE` (linea 95 del mismo fichero) ya es una etiqueta real y
confirmada desde hace varias sesiones -- el comentario simplemente no
se habia actualizado nunca desde antes de que se confirmara el
nombre. Corregido: `JP $8440` -> `JP ACTOR_ENGINE`, comentario
actualizado.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
sustitucion de hex por etiqueta ya existente, cero cambios de
contenido.



### Ronda adicional: toda la tabla de saltos (JT_INIT..JT_TILE_TYPE) sustituida por etiquetas reales en vez de hex

Al preguntar el usuario a donde saltaba `$8F24` (`JT_INIT`), se
detecto que TODA la tabla de saltos de 12 entradas (la "API publica"
del motor, `$8400`) tenia el mismo patron sistemico: cada entrada
hacia `JP $XXXX` con un comentario nombrando la etiqueta ya
confirmada, en vez de usar la etiqueta directamente. Corregidas las
10 entradas restantes (ya se habian corregido `JT_INIT`/`JT_SLOT2` en
la ronda anterior):

| Entrada | Antes | Despues |
|---------|-------|---------|
| JT_SLOT3 | `JP $899B` | `JP RESET_8437` |
| JT_WAIT_VBLANK | `JP $89A0` | `JP WAIT_VBLANK` |
| JT_SLOT5 | `JP $881B` | `JP INSTALL_ISR` |
| JT_SLOT6 | `JP $8E3C` | `JP INPUT_READ` |
| JT_SLOT7 | `JP $8D70` | `JP DIBUJAR_MARCADOR_PUNTOS` |
| JT_SLOT8 | `JP $89AD` | `JP SCROLL_DISPATCH` |
| JT_SLOT9 | `JP $8C34` | `JP JT_SLOT9_TARGET` |
| JT_REDRAW_STRIP | `JP $8D1B` | `JP REDRAW_STRIP` |
| JT_MAP_ADDR | `JP $8CB6` | `JP MAP_COORD_TO_ADDR` |
| JT_TILE_TYPE | `JP $8CDA` | `JP TILE_TYPE_LOOKUP` |

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- sustitucion de
hex por etiquetas ya existentes, cero cambios de contenido. `.dsk`/
`.cas`/inventario HTML regenerados: 740 etiquetas (sin cambio en el
total), pero varias etiquetas que solo eran alcanzables via esta tabla
(y por tanto se contaban como "sin ref." al no detectarse el
`JP $XXXX` hex) pasan a clasificarse correctamente como "interna"
ahora que el `JP` las nombra por simbolo -- categoria interna sube de
218 a 221, sin ref. baja de 190 a 187.



### Ronda adicional: `ACTOR_ENGINE` renombrada a `MOTOR_ACTORES`

32 sustituciones (26 en `madmix_scr_body.asm`, 6 en
`madmix1_body.asm`, donde vive la definicion real en `$8440`).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas.
`recursos/flujo_programa.html`, `recursos/mapa_memoria.html` y
`recursos/ptrtable_sprites.html` actualizados (las unicas menciones
restantes quedan en `recursos/descartado/`, ficheros obsoletos sin
relevancia).



### Ronda adicional: 2 CALL hex mas corregidos en ISR_HOUSEKEEPING (CALL $86BB/$899B -> JTS2_RESUME/RESET_8437)

Al explicar RESET_8437 se encontraron, dentro de ISR_HOUSEKEEPING, 2
CALL que seguian en hex literal pese a tener etiqueta real ya
confirmada (mismo patron que la tabla de saltos, rondas anteriores):
`CALL $86BB` -> `CALL JTS2_RESUME`, `CALL $899B` -> `CALL RESET_8437`.
`CALL $8CFF` se deja igual -- sigue genuinamente sin identificar
(confirmado en el propio comentario de cabecera de la funcion).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo sustitucion
de hex por etiquetas ya existentes, cero cambios de contenido.



### Ronda adicional: `RESET_8437` renombrada a `RESET_CONTADOR_ACTORES`

6 sustituciones en `madmix1_body.asm` (definicion, comentarios y el
`CALL`/`JP` reales, ya corregidos de hex a etiqueta en la ronda
anterior).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: 740 etiquetas (funcion sube de 97 a 99,
interna baja de 221 a 220, sin ref. baja de 187 a 186 -- efecto
acumulado de que `gen_inventory.py` no se habia vuelto a ejecutar
desde el fix de `CALL $86BB/$899B` -> `JTS2_RESUME`/`RESET_8437` de la
ronda anterior; ahora ambas quedan correctamente detectadas como
"funcion" via `CALL` con nombre real). `recursos/flujo_programa.html`
y `recursos/mapa_memoria.html` actualizados (3 menciones).



### Ronda adicional: `INSTALL_ISR` renombrada a `ACTIVAR_INTERRUPCION_MODO_1`

De paso se corrigio otro `CALL $881B` (en `INIT`) que seguia en hex
pese a tener etiqueta confirmada -- mismo patron sistemico que las
rondas anteriores (jump table, `RESET_CONTADOR_ACTORES`).

5 sustituciones en `madmix1_body.asm`.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: 740 etiquetas (funcion sube de 99 a 100,
interna baja de 220 a 219, por el fix del `CALL` hex). `recursos/
flujo_programa.html` y `recursos/mapa_memoria.html` actualizados.



### Ronda adicional: `INPUT_READ` renombrada a `LEER_ENTRADA`

13 sustituciones (4 en `madmix_scr_body.asm`, 9 en
`madmix1_body.asm`). De paso corregidos 2 `CALL $8E3C` mas que
seguian en hex en `madmix1_body.asm` (mismo patron sistemico de
rondas anteriores).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas (ya estaba
clasificada como "funcion" antes por otras llamadas con nombre).
`recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### Ronda adicional: `SCROLL_DISPATCH` renombrada a `GESTIONAR_SCROLL`

10 sustituciones (6 en `madmix_scr_body.asm`, 4 en
`madmix1_body.asm`). `ML_SCROLL_DISPATCH_CALL` (sub-etiqueta distinta
de `MAIN_LOOP`, de una ronda de renombrado anterior) se deja intacta
a proposito -- es un identificador propio, no la misma etiqueta.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`/
inventario HTML regenerados: mismo total de 740 etiquetas.
`recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### Ronda adicional: 9 CALL hex mas corregidos (FILVRM/SETVRAM/DIBUJAR_MARCADOR_PUNTOS) al revisar JT_SLOT9_TARGET

Explicando `JT_SLOT9_TARGET` se encontraron 9 sitios mas con el mismo
patron sistemico (hex literal con etiqueta ya confirmada, sin
sustituir): `CALL $8931` (x3) -> `CALL FILVRM`, `CALL $8954` (x2) ->
`CALL SETVRAM`, `CALL $8D70` (x2, dentro de la propia
`JT_SLOT9_TARGET`) -> `CALL DIBUJAR_MARCADOR_PUNTOS`. De paso,
corregidos 2 comentarios que citaban "$8D70" en prosa y habian quedado
desactualizados/redundantes tras rondas anteriores (uno decia
"todavia sin transcribir", ya falso desde hace tiempo).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo sustitucion
de hex por etiquetas ya existentes + correccion de comentarios, cero
cambios de contenido. `.dsk`/`.cas`/inventario HTML regenerados: mismo
total de 740 etiquetas.



### Cadena completa del scroll: GESTIONAR_SCROLL -> SCROLL_UP/DOWN/LR -> SCROLL_TAIL -> ACTUALIZAR_VRAM_FRAME (antes GH_8891)

Investigando en detalle la mecanica de scroll se establecio la cadena
completa de responsabilidades, aclarando una confusion inicial sobre
"quien escribe en VRAM":

1. `GESTIONAR_SCROLL` (antes `SCROLL_DISPATCH`) lee `PACMAN_POS` y
   decide, segun los bits bajos de X/Y, si toca desplazar 4px arriba,
   abajo o lateral, saltando (no llamando) a una de tres rutinas.
2. `SCROLL_UP`/`SCROLL_DOWN` (nibble `RLD`/`RRD`) y `SCROLL_LR`
   (`LDI`) desplazan el contenido del bufer de trabajo en RAM
   `$DE04` (144 filas x 32 bytes) 4 pixeles en la direccion elegida.
3. Las tres confluyen en `SCROLL_TAIL`: si ademas se cruzo una loseta
   completa (test `XOR D / AND $01`), recorre 9 pasos (`B=$09`,
   coincide con la altura visible confirmada) llamando a
   `TILE_ADDR_CALC` para traer de la RAM residente del nivel la
   loseta nueva, y la escribe en el MISMO bufer `$DE04` (no en VRAM)
   via dos variantes de copia por bits (`SCOPY_A`/`SCOPY_B`).
4. La escritura real en VRAM la hace una rutina **distinta e
   incondicional, una vez por frame**: `ACTUALIZAR_VRAM_FRAME`
   (renombrada desde `GH_8891`, llamada desde `ISR_HOUSEKEEPING`).
   Su tramo final (a partir de `$88ED`) fija la direccion VRAM $0220
   con `SETVRAM` y vuelca byte a byte, con `OUT ($98),B`, el
   contenido de `$DE04` -- 18 filas de datos (coincide con 9 filas de
   losetas x 2, si cada loseta de 16px ocupa 2 filas de patron de
   8px). El resto de `ACTUALIZAR_VRAM_FRAME` (no relacionado con el
   scroll) gestiona ademas color/parpadeo de otras zonas de VRAM
   ($2220, $2A80, $2B80) segun `GAME_STATE_FLAG`.

**Conclusion clave**: ni `GESTIONAR_SCROLL` ni `SCROLL_TAIL` tocan la
VRAM real directamente -- solo preparan el bufer intermedio `$DE04`
en RAM. Es `ACTUALIZAR_VRAM_FRAME`, ejecutada incondicionalmente cada
frame desde la interrupcion, quien copia ese bufer a la VRAM real.

**Bug de la sesion, encontrado y corregido en el propio proceso**: al
sustituir hex por etiqueta en `STAIL_DISPATCH` (`LD IX,$8B5C` / `LD
IX,$8B85`, saltos hacia `SCOPY_A`/`SCOPY_B`) se asumio erroneamente
que esas dos direcciones apuntaban a las propias etiquetas
`SCOPY_A:`/`SCOPY_B:` ya existentes. Verificando contra `main.sym`
tras recompilar se detecto que **no coincidian** (habia un preambulo
de 7 y 4 bytes respectivamente, configuracion de registros C/B/A,
ANTES de cada etiqueta) -- provocaba 2 bytes de diferencia extra en
`MADMIX1.BIN` (4 en vez de las 2 esperadas). Corregido anadiendo
`SCOPY_A_ENTRY:`/`SCOPY_B_ENTRY:` justo en el punto real de entrada
(antes del preambulo) y apuntando `LD IX,` a esas nuevas etiquetas.
De paso se anadio tambien `STAIL_RESUME:` (el punto de retorno tras
`JP (IX)`, saltado via `LD IY,$8B4D` -- este si coincidia exacto con
la direccion real, sin bug).

**Verificado**: recompilado, diffs en la linea base exacta de siempre
(7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`, los bytes deliberados
`$FC60->$FC50`). `.dsk`/`.cas`/inventario HTML regenerados: 743
etiquetas totales (funcion=100 interna=219 dato=235 sinref=189).
`recursos/flujo_programa.html` (tabla JT_INIT, filas JT_SLOT8/9) y
`recursos/mapa_memoria.html` (segmentos ISR_HOUSEKEEPING, GESTIONAR_SCROLL
y bufer $DE04) actualizados con la cadena completa.



### SCROLL_TAIL -> SCROLL_LOSETA_BUFFER_VRAM

Renombrada `SCROLL_TAIL` (cola compartida de `SCROLL_UP`/`SCROLL_DOWN`/
`SCROLL_LR` que redibuja la loseta expuesta en el buffer `$DE04`) a
`SCROLL_LOSETA_BUFFER_VRAM`, nombre mas descriptivo acorde al resto
de la cadena ya documentada (`GESTIONAR_SCROLL` -> `SCROLL_UP`/`DOWN`/
`LR` -> `SCROLL_LOSETA_BUFFER_VRAM` -> `ACTUALIZAR_VRAM_FRAME`).

De paso, revisando las referencias cruzadas se corrigieron 2
comentarios historicos desactualizados:
- El bloque de cabecera de JT_SLOT8/JT_SLOT9 decia que
  `TILE_ADDR_CALC`/`SCROLL_TAIL`/`SCOPY_A`/`SCOPY_B` "traducian
  coordenadas de loseta a direccion de VRAM" y volcaban "la franja
  nueva a la tabla de patrones" -- **falso** segun el hallazgo de la
  ronda anterior (escriben en el buffer RAM `$DE04`, no en VRAM;
  `ACTUALIZAR_VRAM_FRAME` es quien vuelca a VRAM real). Corregido con
  nota explicita.
- El comentario de `SCROLL_ADDR_CALC` decia que la llamaba "el
  despachador de scroll (SCROLL_TAIL/STAIL_DISPATCH) tras mover" --
  **falso**, ya se habia detectado en la ronda anterior que su unica
  llamada real es desde `JT_SLOT9_TARGET` (redibujado TOTAL de
  camara, 36 pasadas), no del scroll incremental. Corregido aqui de
  paso (quedaba pendiente desde la ronda anterior).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total, solo renombrado). `recursos/flujo_programa.html` y
`recursos/mapa_memoria.html` actualizados (todas las menciones a
`SCROLL_TAIL` sustituidas).



### Reinterpretacion del buffer $DE04: es un lienzo de PIXELES, no "el buffer del nivel activo"

El usuario noto una inconsistencia real: el buffer en $DE04 (144 filas
x 32 bytes = 4608 bytes) es MAS GRANDE que el buffer del nivel activo
completo en $FC50 (cabecera+cuerpo+pie, maximo real ~928 bytes = 29
filas x 32, nivel con mas filas variables: 23+3+3=29). Si $DE04 fuera
"todo el nivel proyectado a VRAM" no tendria sentido que fuera mas
grande que el propio nivel de origen.

Investigando la rutina `TAIL_VDP_FILL` ($5B8C, la que inicializa
$DE04 con $FF en 24 de cada 32 bytes/fila) se encontraron dos cosas:

1. **El nombre y el comentario eran enganosos**: pese a llamarse
   "TAIL_VDP_FILL" y decir en el comentario "rellena VRAM", el codigo
   NO toca VRAM en absoluto -- son puros `LD (HL),$FF` + `LDIR` sobre
   RAM normal. Comentario corregido.
2. **Se llama SOLO desde `TAIL_VDP_CLEAR`, en el flujo de
   menu/pantalla de demo** (`TI_5B62`/`TAIL_INTRO`), no desde la
   carga de nivel real. Es decir: **$DE04 no es exclusivo del nivel
   activo** -- es un lienzo de trabajo generico que se reutiliza
   tanto para el menu (con su propio marco de caramelo) como para la
   partida real.

**La pieza que resuelve el tamano**: `ACTUALIZAR_VRAM_FRAME` (0x8891)
vuelca este buffer a la direccion VRAM `$0220`, que cae dentro de la
**tabla de patrones** ($0000-$17FF), escribiendo byte a byte con `OUT
($98)` -- la MISMA tecnica que usa `PORTADA_INIT` para la portada
(bitmap sin comprimir + tabla de nombres "identidad": nombre de
patron = indice de patron = posicion en pantalla). Bajo esa hipotesis
(la tabla de nombres identidad se fija una vez en `PORTADA_INIT` y no
se vuelve a tocar), "dibujar" se reduce a escribir bytes de bitmap en
direcciones consecutivas de la tabla de patrones.

Con esa lectura, las dimensiones de $DE04 encajan EXACTAS con la
rejilla visible ya confirmada en la sesion anterior (12x9 losetas):
- **144 filas = 9 filas de losetas x 16px/loseta** (coincide con la
  altura visible confirmada).
- **32 bytes/fila = 256px = ancho total de pantalla** (16 losetas de
  16px). De esos 32 bytes, `TAIL_VDP_FILL` rellena 24 (192px = 12
  losetas, el area jugable ya confirmada) y deja 8 sin tocar (64px =
  4 losetas, cubiertas por el marco de caramelo decorativo).

**Conclusion**: $DE04 y el buffer del nivel ($FC50) operan en niveles
de abstraccion distintos y por eso no son comparables en tamano.
$FC50 guarda tipos de loseta (1 byte cada una, por eso es pequeno).
$DE04 guarda el BITMAP DE PIXELES ya renderizado, listo para volcar
tal cual a la tabla de patrones de VRAM -- de ahi que sea mucho mas
grande, y que ademas se comparta con las pantallas de menu/demo (no
es "el buffer del nivel", es el lienzo de render de la ventana
visible en resolucion de pixel).

**Verificado**: cambio de comentario unicamente (sin alterar bytes),
recompilado, diffs en la linea base exacta de siempre (7/2).
`recursos/mapa_memoria.html` (entrada 0xDE04) reescrita con esta
reinterpretacion.



### Uso real de la tabla de saltos JT_INIT: solo el slot 0 tiene llamadores externos

Verificando con grep en TODO el codigo fuente transcrito (`.asm`) las
llamadas a las direcciones fijas de la tabla de saltos (`$8400`-
`$8424`, 12 entradas) y a sus etiquetas por nombre, se confirmo una
distincion importante entre el slot 0 y el resto:

- **`JT_INIT`/`START` (`$8400`/`$8403`) SI tiene llamadores reales**:
  el cargador de disco (`load_disk/madmix0_body.asm`, `JP START`) y
  el cargador de cinta (`load_cas/load_bin_body.asm`, `LD IX,START` /
  `JP START`) saltan aqui justo tras cargar `MADMIX1.BIN` en RAM --
  es el punto de entrada real usado para arrancar el motor desde
  fuera. Tambien hay un punto de reinicio interno (`SLOT_RESTART_DD82`)
  que vuelve aqui.
- **Los otros 11 slots (`JT_SLOT2` hasta `JT_TILE_TYPE`, `$8406`-
  `$8424`) NO tienen NINGUN llamador** en todo el codigo fuente
  transcrito -- ni por hex ni por nombre. Cada sitio que necesita
  `MOTOR_ACTORES`, `LEER_ENTRADA`, `DIBUJAR_MARCADOR_PUNTOS`,
  `GESTIONAR_SCROLL`, `JT_SLOT9_TARGET`, etc. llama DIRECTAMENTE a la
  etiqueta real, nunca a traves de la tabla.

Esto explica ademas por que, antes de sustituir el hex por etiquetas
en la ronda anterior ("toda la tabla de saltos... sustituida por
etiquetas reales"), varias de esas funciones se clasificaban como
"sin referencia" por `gen_inventory.py`: el propio `JP $XXXX` de la
tabla era la UNICA referencia textual hacia ellas en todo el codigo,
pero eso no significa que la tabla se use como mecanismo de
despacho real -- es al reves, la tabla depende de que alguien lea el
codigo para saber a donde apuntan sus entradas, no al contrario.

**HIPOTESIS (no verificable al 100% sin analizar `LOGOTOPO.CM`, fuera
de alcance, ni los guiones BASIC en detalle)**: la tabla se penso
como una "API publica" del motor -- quiza usada durante el
desarrollo original para poder mover las funciones reales sin romper
llamadores externos, o pensada para que codigo externo la invocara a
direcciones fijas y estables. En la version final solo el slot 0
(arranque) cumple ese papel real; el resto quedo como convencion/
organizacion del codigo, no como mecanismo de despacho activo.

No aplica verificacion de bytes (no se toco codigo, solo
documentacion).



### INIT -> INICIO

Renombrada la etiqueta `INIT` (arranque real del motor, destino de
`JT_INIT`, $8F24) a `INICIO`, a peticion del usuario. Sustitucion de
palabra completa (`\bINIT\b`) para no afectar a `PORTADA_INIT` ni a
`JT_INIT` (que la referencian como prefijo/sufijo con guion bajo, no
como palabra suelta) ni a las etiquetas compuestas `INIT_MAIN_LOOP`/
`INIT_RESUME_8F54`/`INIT_MAINLOOP_ENTRY_8F71`/`INIT_HELPER_9116`/
`INIT_LOOP_8FD1`/`INIT_8FB7`/`INIT_8FCE`/`INIT_8FEA`, que quedan
igual (no son la etiqueta renombrada, son etiquetas propias
distintas que ya usaban "INIT" como parte de su propio nombre).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total, solo renombrado). `recursos/flujo_programa.html` y
`recursos/mapa_memoria.html` actualizados (todas las menciones en
prosa a la funcion `INIT` sustituidas por `INICIO`).



### JT_SLOT9_TARGET -> REDIBUJAR_PANTALLA_COMPLETA

Renombrada `JT_SLOT9_TARGET` (redibujado TOTAL de camara + iconos de
vida, 36 pasadas de `SCROLL_ADDR_CALC`, distinto del scroll
incremental de `GESTIONAR_SCROLL`) a `REDIBUJAR_PANTALLA_COMPLETA`,
tras confirmar en la conversacion que se invoca solo en puntos
concretos (arranque de partida, cambio de nivel, perdida de vida,
ciclado de niveles de muestra en el menu/demo) y NUNCA dentro del
bucle continuo de frame a frame del juego (ver ronda anterior sobre
`INIT_MAIN_LOOP`/`IML_9078`/`IML_90B7`).

De paso, se corrigieron los 2 sitios en `madmix1_body.asm` que aun
usaban `CALL $8C34` (hex) en vez de la etiqueta, pese a que el
comentario ya la nombraba -- mismo patron sistemico de siempre.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados (todas las menciones sustituidas, y la entrada del
segmento de memoria ampliada con la aclaracion de cuando se invoca).



### Normalizacion completa de la tabla de saltos: las 12 entradas con nombre descriptivo

El usuario detecto una inconsistencia real: tras varias rondas de
renombrado, algunas entradas de la tabla de saltos ($8400) tenian
nombre descriptivo (`JT_WAIT_VBLANK`, `JT_MAP_ADDR`, `JT_TILE_TYPE`,
heredadas de sesiones anteriores; `JT_REDIBUJAR_LOSETA_VRAM`, efecto
colateral de un renombrado mecanico de texto en esta misma sesion)
mientras que el resto seguian con el nombre generico `JT_SLOTn`
(`JT_INIT`, `JT_SLOT2`, `JT_SLOT3`, `JT_SLOT5`, `JT_SLOT6`,
`JT_SLOT7`, `JT_SLOT8`, `JT_SLOT9`) pese a que sus destinos ya tenian
nombre propio confirmado desde hace tiempo. No habia ningun criterio
real detras -- simplemente los renombrados anteriores nunca tocaron
la etiqueta de la propia entrada de tabla porque su texto viejo no
coincidia con el nombre de la funcion destino.

Normalizadas las 12 entradas para que todas seaigan el mismo patron
(nombre de la entrada = "JT_" + nombre del destino real):

| Antes | Despues | Destino |
|-------|---------|---------|
| `JT_INIT` | `JT_INICIO` | `INICIO` |
| `JT_SLOT2` | `JT_MOTOR_ACTORES` | `MOTOR_ACTORES` |
| `JT_SLOT3` | `JT_RESET_CONTADOR_ACTORES` | `RESET_CONTADOR_ACTORES` |
| `JT_SLOT5` | `JT_ACTIVAR_INTERRUPCION` | `ACTIVAR_INTERRUPCION_MODO_1` |
| `JT_SLOT6` | `JT_LEER_ENTRADA` | `LEER_ENTRADA` |
| `JT_SLOT7` | `JT_DIBUJAR_MARCADOR_PUNTOS` | `DIBUJAR_MARCADOR_PUNTOS` |
| `JT_SLOT8` | `JT_GESTIONAR_SCROLL` | `GESTIONAR_SCROLL` |
| `JT_SLOT9` | `JT_REDIBUJAR_PANTALLA_COMPLETA` | `REDIBUJAR_PANTALLA_COMPLETA` |

(`JT_WAIT_VBLANK`, `JT_REDIBUJAR_LOSETA_VRAM`, `JT_MAP_ADDR`,
`JT_TILE_TYPE` ya estaban bien, sin cambios.) Aplicado tambien en los
comentarios de `load_disk/madmix0_body.asm` y `load_cas/load_bin_body.asm`
que mencionaban `JT_INIT` en prosa.

De paso, a peticion del usuario, se realineo en columna el bloque
completo de las 12 entradas `JP` para que sea legible (la mezcla de
nombres largos y cortos tras los renombrados sucesivos habia quedado
con espaciado irregular).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
renombrado de etiquetas y reformateo de espacios en blanco, cero
cambios de contenido. `.dsk`/`.cas`/inventario HTML regenerados: 743
etiquetas (sin cambio de total). `recursos/flujo_programa.html`
(seccion 2, tabla de despacho completa) y `recursos/mapa_memoria.html`
(todas las entradas de segmento que citaban `JT_SLOTn`) actualizados.



### REDIBUJAR_PANTALLA_COMPLETA -> REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM ; REDIBUJAR_LOSETA_VRAM -> REDIBUJAR_LOSETA_BUFFER_VRAM

Dos renombrados mas para dejar explicito en el propio nombre que
estas funciones escriben en el BUFFER intermedio en RAM ($DE04), no
en la VRAM real directamente (distincion clave establecida en rondas
anteriores sobre ACTUALIZAR_VRAM_FRAME):

- `REDIBUJAR_PANTALLA_COMPLETA` -> `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`
  (confirmado en esta conversacion que escribe en `$DE04` de forma
  indirecta, a traves de las 36 llamadas a `SCROLL_ADDR_CALC`).
- `REDIBUJAR_LOSETA_VRAM` -> `REDIBUJAR_LOSETA_BUFFER_VRAM`.

Las entradas de la tabla de saltos correspondientes se renombraron
igual para mantener el patron "JT_" + nombre del destino:
`JT_REDIBUJAR_PANTALLA_COMPLETA` -> `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`,
`JT_REDIBUJAR_LOSETA_VRAM` -> `JT_REDIBUJAR_LOSETA_BUFFER_VRAM`. El
bloque de la tabla de saltos ($8400) se realineo de nuevo en columna
tras el cambio de longitud de estos nombres.

Con esto, las 3 funciones que escriben en el lienzo `$DE04` quedan
nombradas de forma uniforme y explicita sobre que NO tocan VRAM real:
`SCROLL_LOSETA_BUFFER_VRAM`, `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`
y `REDIBUJAR_LOSETA_BUFFER_VRAM`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### MAP_COORD_TO_ADDR -> MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA

Renombrada `MAP_COORD_TO_ADDR` (convierte una coordenada relativa de
fila/columna, respecto a `PACMAN_POS`, en una direccion absoluta
dentro del buffer de tipos de loseta del nivel activo, `$FC50` --
formula "base + fila*32 + columna", gemela de `TILE_ADDR_CALC` que
hace lo mismo pero para el lienzo de pixeles `$DE04`) a
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, a peticion del usuario. La
entrada de la tabla de saltos `JT_MAP_ADDR` (slot 10) se renombro
igual, a `JT_MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, siguiendo el patron
ya normalizado de esta tabla.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados (todas las menciones sustituidas).



### TILE_TYPE_LOOKUP -> CONSULTAR_TIPO_LOSETA

Renombrada `TILE_TYPE_LOOKUP` (recibe una direccion dentro del buffer
de losetas del nivel, quita el bit 7 "comida" y usa el resto como
indice en una segunda tabla de traduccion en `$8EC7`, +3 respecto a
`TILE_TYPES`/`$8EC4`, aplicando `AND $1F` para obtener el tipo final
de loseta -- consulta indirecta por tabla, no lectura directa) a
`CONSULTAR_TIPO_LOSETA`. La entrada de tabla de saltos `JT_TILE_TYPE`
(slot 11) se renombro igual, a `JT_CONSULTAR_TIPO_LOSETA`.

Con esto la cadena completa de "posicion -> tipo de loseta" queda
nombrada de principio a fin: `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
(coordenada relativa -> direccion) + `CONSULTAR_TIPO_LOSETA`
(direccion -> tipo) -> alimenta `ML_DISPATCH_TABLE` (tipo -> manejador).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### Detalle del bucle de cada frame en flujo_programa.html: SIEMPRE vs CONDICIONAL vs EVENTO

El usuario detecto que la seccion "cada frame / cada movimiento" del
diagrama (recursos/flujo_programa.html) agrupaba varias funciones
como si todas se ejecutaran igual en cada frame, cuando en realidad
unas son incondicionales, otras dependen de una condicion, y otras
son eventos disparados desde mas adentro del despacho. Se investigo
el cuerpo real de `MAIN_LOOP` (madmix_scr.asm:409, invocada cada
frame desde `IML_9078`/madmix1.asm via el "trampolin" `RAM_HOOK_2C36`)
para separar exactamente que ocurre siempre y que no:

- **SIEMPRE** (sin condicion, dentro de `MAIN_LOOP`): `LEER_ENTRADA`
  (o direccion del guion de demo), `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
  + `CHECK_TILE_DELTA` (con cache de columna -- solo llama a
  `CONSULTAR_TIPO_LOSETA` si la columna cambio respecto al frame
  anterior), despacho a `ML_DISPATCH_TABLE` (forzado a "sin efecto"
  si hay un modo especial activo), `GESTIONAR_SCROLL`,
  `ITEM_TIMER_TICK`, y un bucle de 3 entradas de trampillas activas
  (`HINT_POS_TABLE`/$2C2E) que redibuja cada una via `MOTOR_ACTORES`.
- **CONDICIONAL** (solo si `($8EC6)`=0, "teclado no bloqueado"):
  `HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO` y el
  redibujado de `MOTOR_ACTORES` para el propio comecocos.
- **EVENTO** (disparado desde DENTRO de un manejador `HNDLR_*`
  segun el tipo de loseta pisada, no un paso fijo del frame):
  `DIBUJAR_MARCADOR_PUNTOS` (solo cuando cambia la puntuacion),
  `TRAPDOOR_FLIP_TABLE`/`GHOST_HINT_HANDLER` (arman/mueven una
  trampilla), `LOAD_RESOURCE_SLOT_*` (sonido).
- **NO pertenece a este bucle en absoluto**:
  `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` -- confirmado en rondas
  anteriores que solo se dispara en transiciones (arranque, cambio
  de nivel, perdida de vida, ciclado de demo), nunca cada frame. Se
  reubico en el diagrama junto a `INIT_MAIN_LOOP`.

Reescrita la seccion del diagrama en `recursos/flujo_programa.html`
con 3 filas nuevas (SIEMPRE/CONDICIONAL/EVENTO, con una etiqueta de
color por categoria via las nuevas clases CSS `.tag-always`/
`.tag-cond`/`.tag-event`) en vez de una sola fila ambigua "cada frame
/ cada movimiento". Tambien se anadio `.flow-note` para una nota
explicativa mas larga sobre `IML_9078`/`IML_90B7`. De paso se
corrigio la caja de `.box`/`.box b` (CSS) para que los nombres largos
de las ultimas rondas de renombrado (`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`,
`REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`...) se envuelvan dentro de
la caja en vez de desbordarla (`overflow-wrap`/`word-break`).

No aplica verificacion de bytes (cambio puramente de documentacion
HTML, sin tocar ningun .asm).



### Comentario desactualizado corregido: PTR_TABLE_91C3 ya estaba resuelto

El comentario justo antes de `PTR_TABLE_91C3` (madmix1_body.asm)
segui redactado como si fuera un misterio sin resolver ("candidato
fuerte a ser la clave", "probablemente..."), pese a que unas lineas
mas abajo, el bloque "SPRITES DE PERSONAJES" (0x953B-0xB93B) ya
confirma que es exactamente eso: la tabla de 64 punteros a los
sprites de personajes, identificados uno a uno por el usuario via
recursos/ptrtable_sprites.html. Contradiccion interna clasica de las
que se han ido corrigiendo toda la sesion. Corregido en ambos sitios:
el comentario de cabecera en `madmix1_body.asm` y la entrada
equivalente en `recursos/mapa_memoria.html` (segmento
0x9136-0x92E3).

**Verificado**: recompilado, diffs en la linea base exacta de
siempre (7/2) -- solo cambio de comentarios, cero cambios de
contenido.



### PTR_TABLE_91C3 -> PTR_TABLA_SPRITES, reconstruida con etiquetas DW en vez de hex

Renombrada `PTR_TABLE_91C3` a `PTR_TABLA_SPRITES` y reescritas sus 64
entradas (256 bytes) usando `DW SPRxx_...` (la etiqueta real de cada
sprite de personaje, ya existente en el catalogo de sprites) en vez
de los bytes de direccion en crudo -- generado y verificado con un
script (parsea las direcciones crudas + la lista de etiquetas SPR con
su direccion en comentario, y empareja por direccion exacta) para
evitar errores de transcripcion manual en las 64 entradas.

De paso, se encontro y corrigio el UNICO sitio real que leia esta
tabla por hex: `LD BC, $91C3` dentro de `MOTOR_ACTORES` (linea ~176),
con un comentario ya desactualizado ("tabla real esta MUY lejos...
sin extraer todavia") que databa de antes de que la tabla y los
sprites se identificaran -- mismo patron sistemico de hex-sin-
sustituir de toda la sesion, ahora corregido a `LD BC,
PTR_TABLA_SPRITES`.

Se descarto la alternativa de anadir una etiqueta nueva con prefijo
`PTR_` por cada uno de los 64 punteros: no hace falta, porque (a)
cada bloque de sprite ya tiene su propia etiqueta descriptiva
(`SPR00_PM_VULN_DER_CERRADA`, etc.) y (b) solo hay UN sitio en todo
el codigo que lee la tabla, por indice calculado (no por direccion
literal repetida en varios sitios) -- no habria ningun llamador que
usara esas hipoteticas etiquetas `PTR_*` individuales.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- la
reconstruccion con `DW`/etiquetas reproduce exactamente los mismos
256 bytes que la version en hex crudo. `.dsk`/`.cas`/inventario HTML
regenerados: 743 etiquetas (sin cambio de total -- el clasificador de
`gen_inventory.py` no detecta referencias via `DW`, solo `CALL`/`JP`/
`JR` literales, asi que las 64 etiquetas SPR mantienen su
clasificacion previa pese a tener ahora una referencia real).
`recursos/mapa_memoria.html` y `recursos/ptrtable_sprites.html`
actualizados (esta ultima tambien tenia un titulo desactualizado,
"sin decodificar todavia", contradicho por su propia nota "RESUELTO"
un parrafo despues -- corregido tambien).



### PORTADA_INIT -> DIBUJAR_PORTADA

Renombrada `PORTADA_INIT` (rutina en $1000, madmix_scr.asm: apaga
pantalla, escribe tabla de nombres identidad, vuelca el bitmap de la
portada a la tabla de patrones, reconstruye el color, enciende
pantalla) a `DIBUJAR_PORTADA`. Referenciada desde varios ficheros
ademas de madmix_scr.asm/madmix1.asm: `load_disk/madmix0_body.asm`
(el RELOCATOR del disco la llama tras el LDIR de reubicacion) y
`load_cas/load_bin_body.asm` (LOAD.BIN de cinta apunta ahi con
`LD IX,`/`CALL`). Todas sincronizadas.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### LOAD_RESOURCE_SLOT_EMPTY -> VACIAR_CANALES_SONIDO

Renombrada `LOAD_RESOURCE_SLOT_EMPTY` ($CF8B: llama 3 veces al
helper interno del driver de sonido `RM_C4CC` con `DE=$0000` y
`A=0/1/2`, vaciando las 3 ranuras/canales del reproductor PSG -- el
"parar todo el sonido en curso" antes de cargar nivel/menu/creditos)
a `VACIAR_CANALES_SONIDO`.

De paso, se encontraron y corrigieron 3 sitios mas con el mismo
patron sistemico de hex-sin-sustituir: `CALL $CF8B` en `INIT_MAIN_LOOP`
y 2 mas en el tramo final de `IML_90E4`/`IML_POLL_90F2` (uno de ellos
codigo inalcanzable, ya documentado como tal, pero corregido igual
por consistencia).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### LOAD_RESOURCE_SLOT_ALLOC -> INSTALAR_RECURSO_SONIDO

Renombrada `LOAD_RESOURCE_SLOT_ALLOC` ($C4A0: busca hueco libre entre
4 ranuras de canal de 46 bytes en $C9C9 e instala ahi el puntero de
un script de musica/SFX) a `INSTALAR_RECURSO_SONIDO`, contraparte de
`VACIAR_CANALES_SONIDO`.

De paso, se corrigieron 3 sitios mas con el patron sistemico de
hex-sin-sustituir: `CALL $C4CC` (x3, instalacion directa de los 3
canales de musica al arrancar nivel) -> `CALL RM_C4CC` (el helper
interno ya identificado, con indice de ranura explicito en A en vez
de busqueda de hueco libre).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### SOUND_SCRIPT_0_CDCB / SOUND_SCRIPT_1_CDFF / SOUND_BOOT_CH2_CE0C -> SOUND_SCRIPT_MELODIA_CANAL_0/1/2

Renombrados los 3 scripts de musica principal (instalados por
INICIO al arrancar, uno por canal del driver PSG) con nombres
consistentes entre si:
- `SOUND_SCRIPT_0_CDCB` -> `SOUND_SCRIPT_MELODIA_CANAL_0`
- `SOUND_SCRIPT_1_CDFF` -> `SOUND_SCRIPT_MELODIA_CANAL_1`
- `SOUND_BOOT_CH2_CE0C` -> `SOUND_SCRIPT_MELODIA_CANAL_2`

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos (flujo_programa.html/
mapa_memoria.html), no requieren sincronizacion.



### TAIL_JOY_READ -> LEER_TECLADO

Renombrada `TAIL_JOY_READ` ($5D0A) a `LEER_TECLADO`. Pese a su nombre
anterior, esta funcion NO lee el joystick -- lee el TECLADO por
matriz (puertos $AA/$A9, metodo estandar de la BIOS MSX), recorriendo
las 9 filas hasta encontrar una tecla pulsada (Z=0, A=columnas,
C=fila) o confirmar que no hay ninguna (Z=1 tras las 9 filas). La
usan `TAIL_KEYWAIT_RELEASE`/`TAIL_KEYWAIT_UP` (esperas de tecla en
menus) y `TAIL_LEVELCYCLE_MAIN` (sondeo en el ciclador de niveles de
muestra del modo demo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos, no requieren
sincronizacion.



### TAIL_LEVELCYCLE_HELPER2 -> DIBUJAR_MARCO_CARAMELO_VRAM

Renombrada `TAIL_LEVELCYCLE_HELPER2` ($6429) a
`DIBUJAR_MARCO_CARAMELO_VRAM`. Funcion: limpia la tabla de color de
VRAM ($2000, FILVRM con $01) y descomprime `RLE_TABLE_D6B6` (870
bytes, pares [valor,contador]) volcando el resultado con FILVRM
directo a la tabla de patrones de VRAM (destino arranca en $0000) --
dibuja la FORMA del marco de caramelo. Es la "hermana" de
`TAIL_CREDITS_MAIN`, que aplica el COLOR de ese mismo marco (leyendo
`LEVELCYCLE_RESOURCE_TABLE`/$6129).

De paso, se corrigio un comentario claramente desactualizado/mal
colocado justo encima de la funcion: describia "copia con
conmutacion de slots... datos por bloques de $6129 (id+8 bytes)...
segundo punto de entrada en $647C" -- eso es en realidad la
descripcion de `TAIL_CREDITS_MAIN` ($6129) y de
`TAIL_LEVELCYCLE_HELPER_ALT` ($647C, una funcion DISTINTA, no un
segundo punto de entrada de esta). El comentario correcto ya existia
justo DESPUES de la funcion (sin tocar, seguia siendo valido);
se elimino/sustituyo el de ANTES por uno que describe lo que la
funcion hace de verdad.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Comentario corregido: INIT_RESUME_8F54 no se alcanza via TAIL_CREDITS_MAIN

El comentario de cabecera de `INIT_RESUME_8F54` decia "reentrada
real... tras el bucle de espera de 'CALL $6454'" (TAIL_CREDITS_MAIN),
pero el unico salto real (`JP INIT_RESUME_8F54`, en la secuencia de
Game Over) no pasa por `$6454` en absoluto -- viene del bucle de
espera de ~150 frames (`IML_LOOP_90B1`) tras mostrar el mensaje
"ESTAS FRITO". Se llega a esta etiqueta por 2 caminos reales:
1. Cayendo aqui sin salto, la primera vez que arranca la maquina
   (justo tras dibujar la portada, instalar los 3 canales de musica
   y esperar una tecla).
2. Via el `JP INIT_RESUME_8F54` desde la secuencia de Game Over.

Corregido el comentario para reflejar esto.

**Verificado**: recompilado, diffs en la linea base exacta de
siempre (7/2) -- solo cambio de comentario, cero cambios de
contenido.



### INIT_RESUME_8F54 -> REINICIAR_PARTIDA

Renombrada `INIT_RESUME_8F54` a `REINICIAR_PARTIDA`. Se alcanza por
2 caminos (ver ronda anterior sobre el comentario corregido): cayendo
sin salto desde el arranque real de la maquina, o via `JP` desde la
secuencia de Game Over (tras el mensaje "ESTAS FRITO" y ~150 frames
de espera). Su cuerpo vacia el sonido, muestra el menu principal
(`TI_5B56`) y resetea vidas=3/puntuacion=0/nivel=1 -- la "vuelta
limpia a partida nueva".

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### LIVES_REMAINING -> VIDAS_RESTANTES

Renombrada la variable `LIVES_REMAINING` ($2C27, vidas restantes del
jugador) a `VIDAS_RESTANTES`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### SCORE_ACCUM -> PUNTUACION ; CURRENT_LEVEL -> NIVEL_ACTUAL

Renombradas dos variables de estado de partida:
- `SCORE_ACCUM` ($2C29, word) -> `PUNTUACION` (puntuacion acumulada).
- `CURRENT_LEVEL` ($2C07) -> `NIVEL_ACTUAL` (nivel actual, 1-15).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### FIRST_LOOP_FLAG -> CONTADOR_VUELTAS_NIVELES (y hallazgo: afecta al diseno de niveles en vueltas posteriores)

Renombrada `FIRST_LOOP_FLAG` a `CONTADOR_VUELTAS_NIVELES`, tras
confirmar que no es un simple booleano sino un CONTADOR de vueltas
completas al ciclo de los 15 niveles: se incrementa en `IML_90D8`
(madmix1.asm) cada vez que `NIVEL_ACTUAL` da la vuelta de 16 a 1
(completado tambien el nivel oculto/15), y se resetea a 0 en
`REINICIAR_PARTIDA`.

**Hallazgo de diseno no documentado hasta ahora**: en `LEVEL_LOADER`
(madmix_scr.asm, lineas ~3122-3157) este contador decide como se
copia el cuerpo de un nivel a la RAM activa:
- Valor 0 (primera vuelta): copia el nivel tal cual (.plain_copy).
- Valor !=0 (segunda vuelta o mas): activa `.with_wildcard` --
  sustituye, alternando una si y otra no, cada loseta "comodin"
  ($3C) del mapa por `LEVEL_REC_WILDCARD_TILE` (un tile especifico
  de ese registro de nivel). Es decir, el diseno de los niveles
  cambia ligeramente a partir de la segunda vuelta completa --  un
  mecanismo discreto de variacion tipo "vuelta +" nunca documentado
  antes en el proyecto.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Hex corregido: JP $8F71 -> JP INIT_MAINLOOP_ENTRY_8F71

Explicando `INIT_MAINLOOP_ENTRY_8F71` se encontro el mismo patron
sistemico de siempre: `JP $8F71` en `IML_90D8` (linea ~2609) usaba
hex en vez de la etiqueta ya confirmada, pese a que el propio
comentario ya la nombraba. Corregido.

Aprovechando la explicacion: `INIT_MAINLOOP_ENTRY_8F71` es el punto
de "recargar el HUD del nivel actual sin resetear vidas/puntuacion"
-- contraparte de `REINICIAR_PARTIDA` (que si resetea todo). Se
alcanza cayendo sin salto tras `REINICIAR_PARTIDA` (partida nueva) o
via este `JP` desde `IML_90D8` cada vez que se completa un nivel y
se avanza al siguiente.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
sustitucion de hex por etiqueta ya existente, cero cambios de
contenido.



### INIT_MAINLOOP_ENTRY_8F71 -> PANTALLA_PRESENTACION_NIVEL

Renombrada `INIT_MAINLOOP_ENTRY_8F71` a `PANTALLA_PRESENTACION_NIVEL`.
Es el punto de "recargar el HUD del nivel actual sin resetear vidas/
puntuacion" -- contraparte de `REINICIAR_PARTIDA` (que si resetea
todo). Se alcanza cayendo sin salto tras `REINICIAR_PARTIDA` (partida
nueva) o via `JP` desde `IML_90D8` cada vez que se completa un nivel.
Su cuerpo dibuja el texto "FASE XX", el aviso de vida extra y el
"READY?" antes de cargar el nivel con `LEVEL_LOADER` -- de ahi el
nombre, es la pantalla de presentacion/transicion entre niveles.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### GAME_STATE_FLAG -> FLAG_NIVEL_RECIEN_CARGADO

Renombrada `GAME_STATE_FLAG` a `FLAG_NIVEL_RECIEN_CARGADO`, tras
confirmar su rol exacto: flag de "consumir una vez". Se arma a 1 en
2 puntos de `PANTALLA_PRESENTACION_NIVEL` (justo antes de llamar a
`LEVEL_LOADER`, y otra vez tras dibujar "READY?"), y lo consume
`ACTUALIZAR_VRAM_FRAME` (llamada una vez por frame desde la
interrupcion): lo lee, lo pone a 0 inmediatamente, y segun su valor
decide entre un refresco mas profundo de VRAM (FILVRM sobre $2220)
o el camino incremental normal.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Hex corregido: 5x CALL $89A0 -> CALL WAIT_VBLANK

El usuario pregunto si habia etiqueta para `$89A0` (dentro de
`PANTALLA_PRESENTACION_NIVEL`) -- si, es `WAIT_VBLANK` (ya
confirmada, destino de `JT_WAIT_VBLANK`). Se encontraron 5 sitios en
`madmix1_body.asm` que seguian usando `CALL $89A0` en vez de la
etiqueta, pese a que el comentario ya la nombraba en cada uno.
Corregidos todos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
sustitucion de hex por etiqueta ya existente, cero cambios de
contenido. `.dsk`/`.cas`/inventario HTML regenerados: 743 etiquetas
(sin cambio de total).



### LEVEL_LOADER -> CARGAR_NIVEL

Renombrada `LEVEL_LOADER` a `CARGAR_NIVEL`: carga el registro del
nivel actual desde `LEVEL_TABLE`, copia cabecera+cuerpo+pie al buffer
activo ($FC50), resetea contador de bolitas/posicion de camara/color/
modo especial/icono HUD, y llama a `TABLE_INIT`.

De paso se corrigieron 3 sitios mas con el patron sistemico de
hex-sin-sustituir: `CALL $5885` (x2, uno de ellos dentro de la propia
`CARGAR_NIVEL`) -> `CALL TABLE_INIT`, y `CALL $5904` -> `CALL
CARGAR_NIVEL` (en `TAIL_LEVELCYCLE_MAIN`, el ciclador de niveles de
muestra del modo demo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html`, `recursos/mapa_memoria.html`,
`recursos/niveles.html` y `recursos/editor_niveles.html`
actualizados.



### Hex corregido: LD HL,$9153 -> LD HL,LEVEL_NUM_TABLE

El usuario pregunto si `$9153` (dentro de `PANTALLA_PRESENTACION_NIVEL`,
justo tras `CARGAR_NIVEL`) tenia etiqueta -- si, es `LEVEL_NUM_TABLE`
(la cadena " 0 1 2...9101112131415" con los numeros de nivel en texto
de 2 digitos). El codigo indexa esta tabla por `NIVEL_ACTUAL*2` para
sacar el numero a mostrar en el HUD ("FASE XX"). Mismo patron
sistemico de siempre (hex en vez de etiqueta ya existente),
corregido.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
sustitucion de hex por etiqueta ya existente, cero cambios de
contenido. `.dsk`/`.cas`/inventario HTML regenerados: 743 etiquetas
(sin cambio de total).



### LEVEL_NUM_TABLE -> TABLA_NUMEROS_NIVEL

Renombrada `LEVEL_NUM_TABLE` (cadena " 0 1 2...9101112131415" con los
numeros de nivel en texto de 2 digitos, indexada por NIVEL_ACTUAL*2)
a `TABLA_NUMEROS_NIVEL`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### Hex corregido: $9151/$9149 -> FASE_TEXT+8/FASE_TEXT (aritmetica de etiqueta)

`$9151` no tenia etiqueta propia, pero cae dentro de `FASE_TEXT`
($9149: `DB $08,$B0," FASE 00"`) -- es justo el primer digito del
placeholder "00" (offset +8), donde el codigo escribe el numero de
nivel real leido de `TABLA_NUMEROS_NIVEL` antes de dibujar el texto.
Sustituido `LD DE,$9151` por `LD DE,FASE_TEXT+8` (aritmetica de
etiqueta, mismo patron ya usado en rondas anteriores para otras
tablas) y de paso `LD DE,$9149` (la misma direccion base) por `LD
DE,FASE_TEXT`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- el
ensamblador calcula los mismos bytes exactos, cero cambios de
contenido. `.dsk`/`.cas`/inventario HTML regenerados: 743 etiquetas
(sin cambio de total).



### FASE_TEXT -> TEXTO_FASE

Renombrada `FASE_TEXT` (plantilla "FASE 00" con el numero de nivel
sustituible, offset +8) a `TEXTO_FASE`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Nueva etiqueta: TABLA_POSICIONES_HUD ($9136) + desglose del hex

La tabla anonima de 19 bytes en `$9136` (justo antes de `TEXTO_FASE`)
no tenia etiqueta propia; se usaban los hex crudos `$9136`/`$9147`/
`$9148` en varios sitios de `madmix1_body.asm` y `madmix_scr_body.asm`.
Analizando el contenido se encontro estructura real, no aleatoria:

```
$08,$48, $10,$50, $18,$58, $20,$60, $28,$68, $30,$70, $38,$78, $40, $00,$00,$00,$00
```

Son pares `(v, v+$40)` con `v` subiendo de 8 en 8 (`$08..$38`), mas un
`$40` suelto -- exactamente todos los multiplos de 8 entre `$08` y
`$78`, el rango que sobrevive a la mascara `AND $78` usada por el
bucle de busqueda `IML_900F`. Los ultimos 4 bytes (offsets 15-18) son
relleno/valores que se sobreescriben en tiempo real ($9147=offset 17,
$9148=offset 18: icono/color de HUD). Probable indicio de dos filas
de columnas del HUD separadas $40 posiciones entre si (sin confirmar
el detalle fino de para que sirve cada fila).

Aplicado: etiqueta `TABLA_POSICIONES_HUD` en `$9136`, desglosada en
varias lineas de `DB` mostrando el patron (en vez de una unica linea
de hex), y sustituidos los usos `LD HL,$9136` / `($9147)` / `($9148)`
por `TABLA_POSICIONES_HUD` / `TABLA_POSICIONES_HUD+17` /
`TABLA_POSICIONES_HUD+18` en ambos ficheros `_body.asm`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (una mas: la nueva
etiqueta de tabla). `recursos/mapa_memoria.html` actualizado con la
nueva etiqueta y el detalle del patron.



### LEVEL_REC_WORK -> REGISTRO_NIVEL

Renombrada `LEVEL_REC_WORK` (una de las 3 etiquetas apiladas en
`$2BF3` junto a `MAINLOOP_TABLES` y `LEVEL_REC_BODY_PTR`, sin
distancia entre ellas) a `REGISTRO_NIVEL`. Es el inicio de la copia
de trabajo en RAM (20 bytes) del registro de nivel que `CARGAR_NIVEL`
copia desde `LEVEL_TABLE` (ROM) via `LDIR` al cargar cada nivel. Sin
referencias en codigo (solo se usaba como etiqueta de definicion).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Los 15 campos de REGISTRO_NIVEL renombrados a espanol

Renombrados los 15 campos del registro de nivel (offsets 0-19,
`$2BF3-$2C06`), todos con prefijo `LEVEL_REC_`/sueltos en ingles,
a nombres en espanol con el prefijo comun `REGISTRO_NIVEL_`:

- `LEVEL_REC_BODY_PTR` -> `REGISTRO_NIVEL_CUERPO_PTR` (offset 0-1)
- `LEVEL_REC_HEADER_PTR` -> `REGISTRO_NIVEL_CABECERA_PTR` (offset 2-3)
- `LEVEL_REC_HEADER_PTR2` -> `REGISTRO_NIVEL_PIE_PTR` (offset 4-5;
  duplicado del anterior, se reusa para copiar la cabecera tambien
  debajo del cuerpo -- de ahi "PIE")
- `LEVEL_REC_ROWS` -> `REGISTRO_NIVEL_FILAS` (offset 6)
- `FLAG_VIDA_EXTRA_NIVEL` -> `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` (offset 7)
- `LEVEL_REC_PELMAZOIDE_COUNT` -> `REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (offset 8)
- `LEVEL_REC_MARICOCO_COUNT` -> `REGISTRO_NIVEL_CONTADOR_MARICOCOS` (offset 9)
- `LEVEL_REC_REGPUNANTOSO_COUNT` -> `REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS` (offset 10)
- `LEVEL_REC_BLINK_DURATION` -> `REGISTRO_NIVEL_DURACION_PARPADEO` (offset 11)
- `LEVEL_REC_WILDCARD_TILE` -> `REGISTRO_NIVEL_LOSETA_COMODIN` (offset 12)
- `LEVEL_REC_REF_ROWCOL` -> `REGISTRO_NIVEL_FILA_COLUMNA` (offset 13-14)
- `LEVEL_REC_START_POS` -> `REGISTRO_NIVEL_POSICION_INICIAL` (offset 15-16,
  alias del campo -- ver siguiente)
- `PACMAN_POS` -> `REGISTRO_NIVEL_POSICION_COMECOCOS` (mismo offset 15-16
  que el anterior: es la posicion viva del comecocos/camara durante
  toda la partida, $2C02, usada por decenas de sitios)
- `LEVEL_REC_HUD_ICON` -> `REGISTRO_NIVEL_ICONO_HUD` (offset 17)
- `LEVEL_REC_BALL_TARGET` -> `REGISTRO_NIVEL_OBJETIVO_BOLAS` (offset 18-19)

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total, son renombrados 1:1). `recursos/mapa_memoria.html` y
`recursos/flujo_programa.html` actualizados (bloques manuales con
los nombres antiguos).



### CURRENT_COLOR -> COLOR_ACTUAL

Renombrada `CURRENT_COLOR` a `COLOR_ACTUAL` (variable de estado de
partida junto a `SAVED_COLOR`, usada para el color de atributo del
HUD/textos).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### TABLA_POSICIONES_HUD: por que esta en pares (columna, columna+$40)

El usuario pregunto si la tabla no seria mas bien de pares
(posicion,color) por entrada. Investigando el consumidor real
(`IML_900F`, mas abajo en el mismo bloque de `INICIO`) se confirmo
el mecanismo exacto: tras la busqueda, el color del HUD/`READY?`
se deriva de `(TABLA_POSICIONES_HUD+17) AND $48 XOR $5F` via
`TAIL_TILE_LOOKUP` -- **no** se lee ningun byte de color de la
tabla en si. Pero la mascara `$48` conserva el bit 3 y el bit 6, y
el bit 6 es EXACTAMENTE el que distingue cada pareja `(v, v+$40)`
de la tabla. Osea: no son pares (posicion,color) independientes --
es el mismo bit de la misma variable objetivo el que decide a la
vez el orden/fila de busqueda en la tabla Y aporta color. Actualizado
el comentario de la tabla en `madmix1_body.asm` y el detalle
correspondiente en `recursos/mapa_memoria.html` para reflejar esto
(sustituyendo tambien el hex crudo `$9147` residual por
`TABLA_POSICIONES_HUD+17`).

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`). `recursos/mapa_memoria.html` actualizado.



### TAIL_TILE_LOOKUP -> OBTENER_COLOR_VDP

Renombrada `TAIL_TILE_LOOKUP` ($6484) a `OBTENER_COLOR_VDP`. El
prefijo `TAIL_` era un resto del nombrado provisional de la sesion
que desensambló el ultimo tramo sin explorar de `madmix_scr.asm`
(`0x5AD5-0x6500`, la "cola" del bloque reubicado -- ver la ronda
'`0x5AD5-0x6500` transcrito completo'), sin relacion con lo que hace
la funcion. Confirmado su comportamiento exacto: dado un byte de
entrada, extrae dos codigos de 4 bits (uno de bits 3-6, otro de bits
0-2 combinado con el bit 6 reutilizado), busca cada uno en
`DIRBITS_TABLE` ($8978) y combina los resultados en un byte de color
VDP (nibble alto = tinta, nibble bajo = fondo, formato de la tabla de
color de SCREEN2). Uso confirmado en `APLICAR_COLOR_PANTALLA` (color
real del marco de caramelo/pantalla) y en `IML_900F` (color del HUD/
`READY?`). Actualizado tambien su comentario de cabecera para
reflejar esto explicitamente.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/graficos.html`
actualizados.



### CLEAR_TEXT_1/2 -> TEXTO_VACIO_1/2, READY_TEXT -> TEXTO_READY

Renombradas las 3 entradas de texto que dibuja `IML_900F` junto al
mensaje de inicio de nivel: `CLEAR_TEXT_1`/`CLEAR_TEXT_2` (las dos
lineas en blanco que "borran" antes/despues) a `TEXTO_VACIO_1`/
`TEXTO_VACIO_2`, y `READY_TEXT` ("READY?") a `TEXTO_READY`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Nueva etiqueta: MOSTRAR_READY_Y_ARRANCAR_NIVEL ($902A)

El usuario planteo una duda arquitectonica legitima: ¿la funcionalidad
de `IML_900F` termina en el `XOR A` (salida del bucle), siendo todo
lo que sigue desde `LD ($8EC6),A` un bloque distinto con otra
finalidad? Se comprobo por grep que ningun `JP`/`JR`/`CALL` en todo
el codigo fuente apunta a esa direccion ($902A) -- se alcanza
exclusivamente por caida natural al salir del bucle. Aun asi, son dos
funcionalidades bien diferenciadas encadenadas: `IML_900F` es el
bucle de busqueda/espera (efecto de barrido visible en el icono del
HUD); desde `$902A` en adelante es la "presentacion" del inicio de
nivel (reactiva el teclado, calcula el color del HUD/READY?, dibuja
las 3 lineas de texto, marca FLAG_NIVEL_RECIEN_CARGADO y arranca los
3 canales del soniquete de nivel) -- ya no depende del resultado de
la busqueda salvo por el color.

Aplicado: nueva etiqueta `MOSTRAR_READY_Y_ARRANCAR_NIVEL` en `$902A`
(puramente documental, sin cambiar el flujo real de ejecucion), con
un comentario explicando la division y por que se alcanza solo por
caida natural.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (una mas: la nueva
etiqueta). `recursos/mapa_memoria.html` actualizado.



### IML_900F -> BUSCAR_COLUMNA_HUD

Tras separar `MOSTRAR_READY_Y_ARRANCAR_NIVEL` (ronda anterior), el
propio `IML_900F` se queda solo con el bucle de busqueda/espera en
`TABLA_POSICIONES_HUD`. Renombrada a `BUSCAR_COLUMNA_HUD`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### Hex corregido: $9145 -> TABLA_POSICIONES_HUD+15

`$9145` (el puntero de 2 bytes que `BUSCAR_COLUMNA_HUD` deja apuntando
a la entrada que coincidio, reutilizado despues por el efecto
"maquina de escribir" de `INIT_HELPER_9116`) no tenia etiqueta
propia, pero cae dentro de `TABLA_POSICIONES_HUD` (offset 15: justo
el primer byte libre tras los 15 valores reales de busqueda, offsets
0-14). Sustituidas las 3 referencias en `madmix1_body.asm` por
`TABLA_POSICIONES_HUD+15` (aritmetica de etiqueta).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### MAIN_LOOP -> MOTOR_MOVIMIENTO_COLISION, RAM_HOOK_2C36 -> ENLACE_MOTOR_MOVIMIENTO_COLISION

El usuario propuso renombrar `RAM_HOOK_2C36` a un nombre que
describiera el motor al que apunta, pero se le señaló que eso
describiria mal al propio gancho (que es un trampolin, no el motor
en si) -- encajaria mejor en `MAIN_LOOP`, la rutina que de verdad hace
ese trabajo (su propio comentario de cabecera ya la llamaba "MOTOR DE
COLISION/MOVIMIENTO"). El usuario acepto renombrar ambas cosas
coherentemente: `MAIN_LOOP` -> `MOTOR_MOVIMIENTO_COLISION` y
`RAM_HOOK_2C36` -> `ENLACE_MOTOR_MOVIMIENTO_COLISION`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/flujo_programa.html`
actualizados.



### RM_C4CC -> INSTALAR_RECURSO_SONIDO_EN_A

Renombrada `RM_C4CC` a `INSTALAR_RECURSO_SONIDO_EN_A`: mismo cuerpo
que `INSTALAR_RECURSO_SONIDO` pero con el indice de ranura EXPLICITO
en `A` (en vez de buscar un hueco libre). Sin cambios en HTML (sin
referencias fuera de codigo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### IML_WAIT_90EC -> PAUSAR_PARTIDA

Renombrada `IML_WAIT_90EC` a `PAUSAR_PARTIDA`. Confirmado su doble
uso: (1) espera obligatoria de 50 frames + sondeo de tecla al empezar
cada nivel (desde `MOSTRAR_READY_Y_ARRANCAR_NIVEL`), y (2) pausa real
disparada por el jugador durante la partida via el bit 5 (sin
identificar) del input, comprobado en `IML_90E4`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).



### IML_9078 -> BUCLE_PRINCIPAL_JUEGO

Renombrada `IML_9078` a `BUCLE_PRINCIPAL_JUEGO`: es, literalmente,
el bucle principal del juego (a diferencia de `PREPARAR_INICIO_NIVEL`,
que solo es la secuencia de transicion) -- cada vuelta avanza el
motor (`ENLACE_MOTOR_MOVIMIENTO_COLISION`), comprueba el temporizador
de "vida perdida" (`MODO_ESPECIAL_ACTIVE`), cae en `IML_90B7`
(comprueba fin de nivel) y en `IML_90E4` (sondea la tecla de pausa),
y vuelve a repetirse.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/flujo_programa.html`
actualizados.



### IML_90B7 -> VERIFICAR_FIN_NIVEL

Renombrada `IML_90B7` a `VERIFICAR_FIN_NIVEL`: el tramo de
`BUCLE_PRINCIPAL_JUEGO` que compara `BALLS_EATEN_COUNT` contra
`REGISTRO_NIVEL_OBJETIVO_BOLAS` y, si coinciden, avanza `NIVEL_ACTUAL`
y salta a `PANTALLA_PRESENTACION_NIVEL`; si no, sigue hacia el sondeo
de pausa (`IML_90E4`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/flujo_programa.html`
actualizados.


### CORREGIDO: INIT_HELPER_9116 NO es una "maquina de escribir" que revela texto

El comentario historico de `INIT_HELPER_9116` afirmaba que revelaba
el HUD (FASE/READY/etc) "posicion a posicion", como una maquina de
escribir. Repasando lo ya confirmado sobre `REGISTRO_NIVEL_ICONO_HUD`
y `COLOR_ACTUAL` (ronda "Nueva etiqueta: MOSTRAR_READY_Y_ARRANCAR_NIVEL"
y el analisis de `ACTUALIZAR_VRAM_FRAME`), esa descripcion es
incorrecta: los bytes que copia son los valores crudos de
`TABLA_POSICIONES_HUD` ($08/$48/.../$78/$40), NO codigos de texto.
`REGISTRO_NIVEL_ICONO_HUD` no dibuja texto -- alimenta
`ACTUALIZAR_VRAM_FRAME`, que rellena (FILVRM, relleno solido) 18
bloques de VRAM en `$2220` si el valor cambio; `COLOR_ACTUAL` se
relee ahi mismo TODOS los frames sin condicion para rellenar otras 2
zonas de color VRAM (`$2A80`/`$2B80`). El efecto real es un
parpadeo/destello rapido de icono+color de transicion, no un
revelado letra a letra del `READY?` (ese texto se dibuja aparte, de
una sola vez, en `MOSTRAR_READY_Y_ARRANCAR_NIVEL`). Comentario de
cabecera corregido en `madmix1_body.asm`, con nota pendiente de
confirmar en vivo (emulador) el aspecto real de este destello.

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`). `recursos/mapa_memoria.html` actualizado.


### CORREGIDO: comentario de la llamada a TAIL_VDP_FILL en la secuencia de GAME OVER

El comentario en la llamada a `TAIL_VDP_FILL` desde la secuencia de
GAME OVER (`madmix1_body.asm`) decia "rellena el borde de VRAM" --
incorrecto en las dos cosas, segun lo ya confirmado en el propio
comentario de cabecera de `TAIL_VDP_FILL`: rellena el AREA JUGABLE
(no el borde/marco) del buffer RAM `$DE04` (no VRAM directamente).
Corregido para reflejar esto.

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`).


### VERIFICADO EN VIVO: TAIL_VDP_FILL en GAME OVER pone el area de juego NEGRA, sin parpadeo

El usuario probo en el emulador la secuencia de Game Over (perder
todas las vidas): el area de juego se pone **negra** y aparece
"ESTAS FRITO", **sin ningun flash ni parpadeo visible**. Esto resuelve
la duda abierta sobre que color de tinta usa el relleno de `$FF` de
`TAIL_VDP_FILL` (confirma que es negro en ese momento) y confirma que
el efecto es un relleno estatico de una sola vez, no un flash/blink
-- coherente con que `TAIL_VDP_FILL` solo se llama una vez (no en un
bucle de alternancia). Comentario de la llamada en `madmix1_body.asm`
actualizado con esta verificacion.

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`).


### TAIL_VDP_FILL -> RELLENAR_SOLIDO_BUFFER_VRAM

Renombrada `TAIL_VDP_FILL` a `RELLENAR_SOLIDO_BUFFER_VRAM`. Cerrado
el hallazgo del relleno de `$DE04`: siempre es un relleno SOLIDO de
una sola vez (sin parametros ni bucle de alternancia), solo del area
jugable (24 de 32 bytes/fila, no del marco de caramelo). Confirmado
en vivo por el usuario en la secuencia de Game Over: el area de juego
se pone negra (color de tinta = negro en ese momento) sin ningun
parpadeo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### RELLENAR_SOLIDO_BUFFER_VRAM -> RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM, GAMEOVER_TEXT -> TEXTO_GAME_OVER

Dos renombrados mas en la secuencia de Game Over: `RELLENAR_SOLIDO_BUFFER_VRAM`
(nombre anterior de esta misma ronda) se afino a
`RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM` para dejar explicito que solo
rellena el area jugable (no el marco); y `GAMEOVER_TEXT` ("ESTAS
FRITO") a `TEXTO_GAME_OVER`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### IML_LOOP_90B1 -> ESPERA_150_FRAMES

Renombrada `IML_LOOP_90B1` a `ESPERA_150_FRAMES`: el bucle
`HALT`/`DJNZ` (B=$96=150) que mantiene visible el mensaje de Game
Over antes de reiniciar la partida.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### BALLS_EATEN_COUNT -> CONTADOR_BOLAS_COMIDAS

Renombrada `BALLS_EATEN_COUNT` a `CONTADOR_BOLAS_COMIDAS`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/flujo_programa.html`
actualizados.


### BALL_BLINK_POS -> POSICION_PARPADEO_BOLA, MODO_ESPECIAL_COUNTDOWN -> MODO_ESPECIAL_CUENTA_ATRAS, MODO_ESPECIAL_ACTIVE -> MODO_ESPECIAL_ACTIVO

Tres renombrados de variables de estado de partida (traduccion directa
al espanol, sin cambio de significado).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` y `recursos/flujo_programa.html`
actualizados.


### IML_90FD -> SALTAR_A_BUCLE_PRINCIPAL_JUEGO

Renombrada `IML_90FD` a `SALTAR_A_BUCLE_PRINCIPAL_JUEGO`: el punto de
reencuentro comun (desde el sondeo de pausa sin activar, o tras
reanudar de `PAUSAR_PARTIDA`) que hace `JP BUCLE_PRINCIPAL_JUEGO`. De
paso se identifico que las 2 instrucciones siguientes (`CALL
VACIAR_CANALES_SONIDO` / `JP $0040`) son codigo inalcanzable (el `JP`
incondicional de arriba nunca cae ahi) -- `$0040` cae ademas en medio
de la tabla de saltos de la BIOS del MSX, no es una direccion de
entrada valida por si misma.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### IML_90E4 -> VERIFICAR_ENTRADA

Renombrada `IML_90E4` a `VERIFICAR_ENTRADA`: sondea el teclado/
joystick (bit 5, aun sin identificar el boton/tecla fisica exacta,
candidato a pausa/confirmacion) cuando el nivel todavia no se ha
completado, y si esta activo entra en `PAUSAR_PARTIDA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### IML_WAITLOOP_90EF -> BUCLE_PAUSA

Renombrada `IML_WAITLOOP_90EF` a `BUCLE_PAUSA`: el bucle `HALT`/`DJNZ`
de la espera fija de 50 frames dentro de `PAUSAR_PARTIDA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### IML_90D8 -> SIGUIENTE_NIVEL

Renombrada `IML_90D8` a `SIGUIENTE_NIVEL`: el punto de reencuentro
comun tras completar cualquier nivel (se llega ahi por salto directo
en el caso normal, o por caida natural tras el bloque de reset a
nivel 1 cuando se completa la vuelta entera del ciclo incluyendo el
nivel 15 oculto) -- llama a INIT_HELPER_9116, copia el flag de vida
extra, y salta a PANTALLA_PRESENTACION_NIVEL.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### CORREGIDO: comentario erroneo sobre el ritmo del parpadeo de INIT_HELPER_9106

Un comentario anadido manualmente por el usuario en la llamada a
`INIT_HELPER_9106` (dentro de `VERIFICAR_FIN_NIVEL`) afirmaba "parpadeo
cada 4 frames" -- no encaja con el codigo real (usa el bit 6 del
contador, que cambia cada 64 incrementos) ni con la verificacion en
vivo ya hecha por el usuario (esa loseta no parpadea visiblemente).
Corregido para remitir al mecanismo real del parpadeo visible del
comecocos (`ML_POWER_BLINK_COLOR`, ya documentado en una ronda
anterior).

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`).


### INIT_HELPER_9106 -> ACTUALIZAR_LOSETA_BOLA_ESPECIAL, INIT_HELPER_9116 -> DESTELLO_ICONO_COLOR_HUD

El usuario pregunto si las dos funciones `INIT_HELPER_9106`/
`INIT_HELPER_9116` (mismo nombre generico heredado, solo difieren en
la direccion) hacian lo mismo. Comparando el codigo real: NO -- una
escribe un unico byte en una loseta fija del laberinto (la bola
especial, sin bucle propio, se apoya en que el llamador ya corre una
vez por frame) y la otra recorre varios bytes de TABLA_POSICIONES_HUD
en un bucle propio con su propia espera de VBLANK, escribiendo en
variables de icono/color del HUD. Renombradas para dejarlo claro:
`INIT_HELPER_9106` -> `ACTUALIZAR_LOSETA_BOLA_ESPECIAL`,
`INIT_HELPER_9116` -> `DESTELLO_ICONO_COLOR_HUD`. De paso se corrigio
un comentario de indice (madmix1_body.asm ~2397) que aun describia
`DESTELLO_ICONO_COLOR_HUD` como "revelado de texto tipo maquina de
escribir" -- ya corregido en el comentario de cabecera de la funcion
en una ronda anterior, pero no en este segundo sitio.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_READ_REAL_INPUT -> SALTAR_A_LEER_ENTRADA

Renombrada `ML_READ_REAL_INPUT` a `SALTAR_A_LEER_ENTRADA`: la rama de
`MOTOR_MOVIMIENTO_COLISION` (modo normal, no demo) que llama a
`LEER_ENTRADA` para obtener la direccion real del jugador.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### RAW_DIRECTION -> DIRECCION_SIN_PROCESAR

Renombrada `RAW_DIRECTION` a `DIRECCION_SIN_PROCESAR`: la direccion
"cruda" de cada frame, guardada por `ML_STORE_DIRECTION` antes de
cualquier validacion de alineamiento (paralelo a
`DIRECCION_DE_MOVIMIENTO`, que es la version ya filtrada/validada).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### DIR_INPUT_LATCH -> FLAG_DIRECCION_NUEVA

Renombrada `DIR_INPUT_LATCH` a `FLAG_DIRECCION_NUEVA`: flag booleano
(0/1, no una direccion) que se arma solo en el primer frame en que se
detecta una direccion tras no haber ninguna -- distingue "pulsacion
recien llegada" de "direccion mantenida varios frames".

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_LATCH_CLEAR -> LIMPIAR_FLAG_DIRECCION

Renombrada `ML_LATCH_CLEAR` a `LIMPIAR_FLAG_DIRECCION`: la rama que
desarma `FLAG_DIRECCION_NUEVA` (lo pone a 0) cuando no hay ninguna
direccion pulsada este frame.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_LATCH_STORE -> COPIAR_FLAG_DIRECCION

Renombrada `ML_LATCH_STORE` a `COPIAR_FLAG_DIRECCION`: punto de
confluencia de las 3 ramas del mecanismo de latch (input mantenido/
nuevo/ninguno) que copia el resultado en `INPUT_EDGE_FLAG`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_STORE_DIRECTION -> PROCESAR_DIRECCION

Renombrada `ML_STORE_DIRECTION` a `PROCESAR_DIRECCION`: recibe la
direccion de este frame (de teclado real o guion de demo), la guarda
en `DIRECCION_SIN_PROCESAR`/`B`, y actualiza el mecanismo de latch de
"pulsacion nueva" (`FLAG_DIRECCION_NUEVA`/`INPUT_EDGE_FLAG`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### CAMERA_POS -> POSICION_ACTUAL_CAMARA

Renombrada `CAMERA_POS` a `POSICION_ACTUAL_CAMARA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_ALIGN_START -> CALCULAR_MASCARA_ALINEAMIENTO

Renombrada `ML_ALIGN_START` a `CALCULAR_MASCARA_ALINEAMIENTO`: arranca
el calculo de la mascara de giros validos segun alineamiento con la
loseta (eje X/Y), a partir del valor de alineamiento `C` (real o
forzado por `DIRECCION_FORZADA`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_ALIGN_CHECK_Y -> COMPROBAR_ALINEAMIENTO_Y

Renombrada `ML_ALIGN_CHECK_Y` a `COMPROBAR_ALINEAMIENTO_Y`: segunda
mitad del calculo de la mascara de alineamiento (eje Y, tras el
chequeo de X en `CALCULAR_MASCARA_ALINEAMIENTO`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_ALIGN_APPLY -> APLICAR_MASCARA_ALINEAMIENTO

Renombrada `ML_ALIGN_APPLY` a `APLICAR_MASCARA_ALINEAMIENTO`: aplica
la mascara (E) a la direccion candidata (C) -- si sigue siendo valida
se acepta, si no se recupera la direccion del frame anterior (B).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_DIR_FINALIZE -> FIJAR_DIRECCION_FINAL

Renombrada `ML_DIR_FINALIZE` a `FIJAR_DIRECCION_FINAL`: guarda
`DIRECCION_DE_MOVIMIENTO` definitiva y arranca la consulta de tipo de
loseta (`CHECK_TILE_DELTA`), con reintento usando la direccion del
frame anterior (B) si la primera consulta da tipo normal (0).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### CHECK_TILE_DELTA -> CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION

Renombrada `CHECK_TILE_DELTA` a
`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`: desplaza la posicion de
camara una loseta segun el bit de direccion recibido, y consulta el
tipo de esa loseta (con cache de columna/tipo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_TILE_TYPE_INDEX -> CALCULAR_INDICE_TIPO_LOSETA

Renombrada `ML_TILE_TYPE_INDEX` a `CALCULAR_INDICE_TIPO_LOSETA`:
convierte el tipo de loseta en el indice de palabra de
`ML_DISPATCH_TABLE`, y aplica el override que fuerza indice 0 mientras
dura un modo especial (`MODO_ESPECIAL_ACTIVO`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_DISPATCH_LOOKUP -> OBTENER_MANEJADOR_LOSETA

Renombrada `ML_DISPATCH_LOOKUP` a `OBTENER_MANEJADOR_LOSETA`: indexa
`ML_DISPATCH_TABLE` con el offset ya calculado y deja el puntero real
del manejador en `IX`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_DISPATCH_TABLE -> TABLA_MANEJADORES_LOSETA

Renombrada `ML_DISPATCH_TABLE` a `TABLA_MANEJADORES_LOSETA`: los 20
punteros de despacho por tipo de loseta (0-19).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### RESUELTO: TILE_DISPATCH_TABLE -> TABLA_CLASE_ALINEAMIENTO

El usuario pidio analizar totalmente el uso de `TILE_DISPATCH_TABLE`
(marcada como "sin confirmar su uso exacto mas alla de guardarse en
C"). Rastreando hacia adelante desde `OBTENER_MANEJADOR_LOSETA` se
encontro que C (el valor de esta tabla, 0-4) se combina en
`ML_DIR_SUBTABLE_LOOP` con el indice rotativo `DIR_TABLE_INDEX`
(offset = C*4 + indice) para seleccionar una entrada de las subtablas
de 20 bytes (`SUBTABLE_A/B/C/D`) -- exactamente el mecanismo de
`SELECTOR_SPRITE_COMECOCOS` ya resuelto en una ronda anterior. Se
encontro ademas un SEGUNDO uso, en la IA de fantasmas/items (lineas
~2036-2074): ahi la misma tabla convierte una direccion en formato
bitmask ($01/$02/$04/$08) en el mismo codigo compacto 1-4, para
indexar tablas de sprite de fantasmas/maricoco/repugnantoso -- un
proposito mas generico ("compactar bitmask de direccion a indice") que
el nombre elegido no cubre del todo, pero el usuario confirmo
mantener `TABLA_CLASE_ALINEAMIENTO` (mas preciso para el uso
principal/original) en vez de un nombre mas neutro.

Renombrada `TILE_DISPATCH_TABLE` -> `TABLA_CLASE_ALINEAMIENTO`,
comentarios de cabecera y de los 2 puntos de uso actualizados para
reflejar el mecanismo resuelto.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_DELTA_CHECK_LEFT -> COMPROBAR_LOSETA_IZQUIERDA

Renombrada `ML_DELTA_CHECK_LEFT` a `COMPROBAR_LOSETA_IZQUIERDA`: uno
de los 4 eslabones de la cadena de `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`
que comprueba bit a bit cual direccion (derecha/izquierda/abajo/
arriba) esta activa en el bitmask recibido.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_DELTA_RESOLVE -> IDENTIFICAR_PROXIMA_LOSETA

Renombrada `ML_DELTA_RESOLVE` a `IDENTIFICAR_PROXIMA_LOSETA`: punto de
reunion de la cadena de comprobacion de direccion, donde se convierte
la posicion ya desplazada a direccion VRAM real y se identifica (con
cache) el tipo de loseta.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### ML_DELTA_CHECK_DOWN -> COMPROBAR_LOSETA_ABAJO, ML_DELTA_CHECK_UP -> COMPROBAR_LOSETA_ARRIBA

Completan la cadena de 4 eslabones de `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`
(derecha inline, `COMPROBAR_LOSETA_IZQUIERDA`, `COMPROBAR_LOSETA_ABAJO`,
`COMPROBAR_LOSETA_ARRIBA`), todos con nombre consistente ahora.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### PENDIENTE: asimetria +4/-1 en CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION

El usuario pregunto si los comentarios de la cadena
`COMPROBAR_LOSETA_IZQUIERDA/ABAJO/ARRIBA` eran correctos. La parte de
que bit corresponde a que direccion esta bien (bit0=derecha,
bit1=izquierda, bit2=abajo, bit3=arriba, confirmado por el orden de
las 4 rotaciones `RRA`), pero se encontro una asimetria real sin
explicar: derecha/abajo suman `$04` (un paso de loseta completo, que
sobrevive siempre al `AND $7C` de `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
en `madmix1_body.asm:1811-1827`), mientras que izquierda/arriba solo
restan 1 (`DEC C`/`DEC B`) -- un cambio que podria NO cruzar ningun
limite de loseta, dependiendo de la sub-posicion actual del
comecocos. No confirmado si es comportamiento deliberado del original
o un caso sin explorar. Anotado como comentario `PENDIENTE` en el
codigo (justo antes de `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`),
a la espera de verificarlo en vivo en el emulador.

**Verificado**: recompilado sin errores (cambio solo de comentarios),
diffs en la linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en
`MADMIX1.BIN`).


### TILE_COL_CACHE -> CACHE_COLUMNA_LOSETA, TILE_TYPE_CACHE -> CACHE_TIPO_LOSETA

Renombrado el par de cachés de `IDENTIFICAR_PROXIMA_LOSETA` que
evitan repetir `CONSULTAR_TIPO_LOSETA` cuando la columna consultada es
la misma que la ultima vez.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### ML_DELTA_MASK_RESULT -> ENMASCARAR_TIPO_LOSETA

Renombrada `ML_DELTA_MASK_RESULT` a `ENMASCARAR_TIPO_LOSETA`: punto de
reunion final de `IDENTIFICAR_PROXIMA_LOSETA` (cache o consulta real)
que aplica `AND $1F` para quedarse con los 5 bits bajos (0-19) antes
de devolver el control.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### INPUT_EDGE_FLAG -> COPIA_FLAG_DIRECCION_NUEVA

Renombrada `INPUT_EDGE_FLAG` a `COPIA_FLAG_DIRECCION_NUEVA`: copia
consultable de `FLAG_DIRECCION_NUEVA` que el resto del motor usa para
detectar el flanco de pulsacion (p.ej. `TRAPDOOR_FLIP_TABLE` solo se
llama una vez por pulsacion nueva, no en cada frame mantenido).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### CORREGIDO: "trampillas" -> "pista de tanque/avion" (HINT_POS_TABLE/TRAPDOOR_FLIP_TABLE y familia)

El usuario cuestiono por que se hablaba de "trampillas" al explicar
`TRAPDOOR_FLIP_TABLE` -- correctamente: es un error de terminologia
heredado de una hipotesis antigua sin confirmar. El propio codigo ya
tenia la respuesta resuelta en el comentario de cabecera de
`GHOST_HINT_HANDLER` ("Manejador de 'pista' (tanque/avion...") y en
el comentario de `SOUND_EVT04_CE72` ("CONFIRMADO por el usuario...
Disparo (modo avion)"), que nunca se habian cruzado con el resto de
comentarios ambiguos "trampilla/pista" repartidos por el fichero.

**Importante**: existen DOS sistemas distintos que compartian
vocabulario por error:
1. **Trampillas REALES** (tipos de loseta 17-19): `HNDLR_TRAMPILLA_ABIERTA_DERECHA/IZQUIERDA/CERRADA(_B)`,
   `TRAPDOOR_PHASE`, `TRAPDOOR_ANIM_EXIT`, `SOUND_EVT09_CE5A`, los
   ficheros `data/tiles/*trampilla*.til` -- estos SI son trampillas,
   sin cambios.
2. **Pista de tanque/avion** (tabla `$2C2E`, activada por
   `HNDLR_PISTA_COCOTANQUE`/`HNDLR_PISTA_COCONAVE`, consultada por
   `GHOST_HINT_HANDLER`) -- esto NUNCA fue sobre trampillas, renombrado:
   - `HINT_POS_TABLE` -> `TABLA_PISTA_TANQUE_AVION`
   - `TRAPDOOR_FLIP_TABLE` -> `REGISTRAR_PISTA_TANQUE_AVION`
   - `TRAPDOOR_FLIP_SCAN` -> `BUSCAR_HUECO_PISTA`
   - `TRAPDOOR_FLIP_SET` -> `FIJAR_PISTA`
   - `TRAPDOOR_FLIP_STORE` -> `GUARDAR_PISTA`
   - `ML_TRAPDOOR_LOOP` -> `ML_PISTA_LOOP`
   - `ML_TRAPDOOR_NEXT` -> `ML_PISTA_NEXT`
   - `ML_TRAPDOOR_FORMAT_B`/`_POS` -> `ML_PISTA_FORMATO_B`/`_POS`
   - `ML_TRAPDOOR_ROW_FIXED` -> `ML_PISTA_FILA_FIJA`
   - `ML_TRAPDOOR_DRAW` -> `ML_PISTA_DIBUJAR`

   Corregidos ademas ~15 comentarios sueltos que decian "trampilla(s)"
   en el contexto de este segundo sistema (definicion de la tabla,
   bucle de dibujado en MOTOR_MOVIMIENTO_COLISION, GHOST_HINT_HANDLER,
   HNDLR_PISTA_COCOTANQUE, TI_2C2E_ENTRY, SOUND_EVT04_CE72).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total, renombrados 1:1). `recursos/mapa_memoria.html` y
`recursos/flujo_programa.html` actualizados.


### ITEM_TIMER_TICK -> ACTUALIZAR_DESTELLO_ITEMS

Renombrada `ITEM_TIMER_TICK` a `ACTUALIZAR_DESTELLO_ITEMS`: anima
hasta 4 entradas simultaneas de la secuencia de "destello" de items
especiales (`ITEM_TABLE_EFECTOS_DESTELLO`), llamada una vez por frame
sin condicion.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` actualizado.


### SAVED_COLOR -> COLOR_GUARDADO

Renombrada `SAVED_COLOR` a `COLOR_GUARDADO`: copia de seguridad de
`COLOR_ACTUAL`, guardada/restaurada en las transiciones de entrada/
salida de los modos especiales.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.


### TI_2C2E_ENTRY -> INICIALIZAR_PARCIAL_ITEMS_NIVEL

Renombrada `TI_2C2E_ENTRY` a `INICIALIZAR_PARCIAL_ITEMS_NIVEL`:
segundo punto de entrada a `INICIALIZAR_ITEMS_NIVEL` que solo limpia
`TABLA_PISTA_TANQUE_AVION`, usado al salir de los modos tanque/avion.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 744 etiquetas (sin cambio de
total).


### TI_CLR2C2E -> .LOOP_LIMPIEZA (etiqueta local)

Renombrada `TI_CLR2C2E` a `.LOOP_LIMPIEZA` (etiqueta local de
SjASMPlus, scope `INICIALIZAR_PARCIAL_ITEMS_NIVEL`): el bucle que
pone a 0 el flag "activa" de las 3 entradas de
`TABLA_PISTA_TANQUE_AVION`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (una menos por ser
ahora local, mismo patron ya visto con `.CONTINUAR_RESPAWN`).


### TI_CLR5773 -> .LOOP_LIMPIEZA_DESTELLO (etiqueta local)

Renombrada `TI_CLR5773` a `.LOOP_LIMPIEZA_DESTELLO` (etiqueta local):
el bucle dentro de `INICIALIZAR_ITEMS_NIVEL` que limpia las 4 entradas
de la tabla `$5773` de efectos de destello activos (la misma que
consulta `ACTUALIZAR_DESTELLO_ITEMS`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (una menos por ser
ahora local, mismo patron ya visto con `.CONTINUAR_RESPAWN`/`.LOOP_LIMPIEZA`).


### TI_2C10 -> CONTINUAR_RESET_EXCAVATOFONO, analisis del valor $0E

Renombrada `TI_2C10` a `CONTINUAR_RESET_EXCAVATOFONO`: punto de
reunion dentro de `INICIALIZAR_ITEMS_NIVEL` donde, si `MODO_ESPECIAL`
es 3 (EXCAVATOFONO), se escribe `$0E` en 4 variables
(`DIRECCION_DE_MOVIMIENTO`/`DIRECCION_FORZADA`/
`TEMPORIZADOR_DIRECCION_FORZADA`/`TEMPORIZADOR_PARPADEO_BOLA`) en vez
de `0`. Analizado a peticion del usuario: `DIRECCION_FORZADA=$0E`
tiene justificacion real -- es un valor (`0b1110`) que sobrevive a
`AND` contra las 3 mascaras posibles de alineamiento (`$0F`/`$03`/
`$0C`), garantizando que la direccion forzada se acepte siempre tras
un respawn en modo EXCAVATOFONO, sin importar el alineamiento
sub-loseta. `TEMPORIZADOR_DIRECCION_FORZADA=$0E` (14 frames) es
plausible como duracion real de ese forzado. Las otras 2 escrituras
(`DIRECCION_DE_MOVIMIENTO`, `TEMPORIZADOR_PARPADEO_BOLA`) no tienen
justificacion propia clara -- probable reutilizacion del registro A
(ya cargado con $0E) por ahorro de codigo, sin significado especifico
para esas dos variables.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total).


### LEVEL_TABLE -> TABLA_NIVELES

Renombrada `LEVEL_TABLE` a `TABLA_NIVELES`: los 16 registros de 20
bytes de todos los niveles del juego (indice 0 = registro muerto,
indice 15 = nivel 15 oculto).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html`, `recursos/editor_niveles.html`
y `recursos/niveles.html` actualizados.


### `BODY_L*` -> `CUERPO_L*`, `HEADER_*` -> `CABECERA_*` (etiquetas de TABLA_NIVELES)

A peticion del usuario, sustituido "BODY" por "CUERPO" y "HEADER" por
"CABECERA" en todas las etiquetas que forman el contenido de
`TABLA_NIVELES`: `BODY_L01/L2/L3/L4/L5/L6/L7/L8/L9/L10/L11/L12/L15`
-> `CUERPO_L*` (en `madmix_scr_body.asm`), `BODY_L13_CFA4`/
`BODY_L14_D244` -> `CUERPO_L13_CFA4`/`CUERPO_L14_D244` (definidas en
`madmix1_body.asm`, referenciadas desde `madmix_scr_body.asm`), y
`HEADER_4AFC`/`HEADER_4B5C`/`HEADER_50BC` -> `CABECERA_4AFC`/
`CABECERA_4B5C`/`CABECERA_50BC`. Se dejo sin tocar `MADMIX0_HEADER_START`
(en `main.asm`), que es una etiqueta distinta sin relacion con el
registro de nivel. De paso se actualizaron 2 menciones historicas en
comentarios (nombres antiguos `BODY_L13_HEAD_CFA4`/`BODY_L13_MAZE_D000`/
`BODY_L14_MAZE_D244`) por consistencia de terminologia.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total, renombrados 1:1). `recursos/mapa_memoria.html` actualizado.


### Formato: hex -> decimal en campos "recuento" (REGISTRO_NIVEL_FILAS)

A raiz de una pregunta del usuario sobre si los campos de
`REGISTRO_NIVEL`/`TABLA_NIVELES` deben ir en hex, se acordo un
criterio: decimal para campos que son recuentos/duraciones puros
(filas, contadores de items, duracion de parpadeo, objetivo de
bolitas), hex para los que son direcciones/indices en tablas de bits
(posiciones empaquetadas, icono HUD). Aplicado el primer caso:
`REGISTRO_NIVEL_FILAS` (valor "de fabrica" en la declaracion RAM,
sin significado propio real ya que `CARGAR_NIVEL` lo sobreescribe
siempre) `DB $12` -> `DB 18`. Cambio de formato puro, mismo byte.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).


### Formato: hex -> decimal en el resto de campos "recuento" de REGISTRO_NIVEL

Aplicado el criterio acordado (decimal para recuentos/duraciones, hex
para direcciones/indices) al resto de campos de la declaracion RAM de
`REGISTRO_NIVEL`: `REGISTRO_NIVEL_VIDA_EXTRA_FLAG` (`$01`->`1`),
`REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (`$02`->`2`),
`REGISTRO_NIVEL_CONTADOR_MARICOCOS`/`REPUGNANTOSOS` (`$01`->`1` cada
uno), `REGISTRO_NIVEL_DURACION_PARPADEO` (`$C8`->`200`),
`REGISTRO_NIVEL_OBJETIVO_BOLAS` (`$0000`->`0`). Dejados en hex, tras
revisar cada uno: `REGISTRO_NIVEL_FILA_COLUMNA`/`POSICION_COMECOCOS`
(coordenadas empaquetadas usadas en aritmetica de direcciones),
`REGISTRO_NIVEL_ICONO_HUD` (indice en `TABLA_POSICIONES_HUD`), y
`REGISTRO_NIVEL_LOSETA_COMODIN` -- este ultimo verificado con mas
cuidado: el codigo real hace `OR $80` sobre el (no viene pre-marcado
en el dato), pero su valor `$C0`=192 no encaja con el catalogo
conocido de ~91 losetas decimales, asi que no esta claro que
convertirlo a decimal aporte claridad real -- se deja en hex.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).


### Formato: hex -> decimal en variables de estado de partida ($2C07-$2C2D)

Revisadas las declaraciones de variables entre `NIVEL_ACTUAL` ($2C07)
y `MODO_ESPECIAL` ($2C2D), aplicando el mismo criterio (decimal para
recuentos/flags/enumerados/indices pequenos con significado numerico
propio; hex para bitmasks de direccion, coordenadas empaquetadas,
colores VDP, semillas, o valores sin confirmar). Convertidas a
decimal: `NIVEL_ACTUAL`, `CONTADOR_BOLAS_COMIDAS`,
`TEMPORIZADOR_PARPADEO_BOLA`, `MODO_ESPECIAL_FLAG`,
`MODO_ESPECIAL_CUENTA_ATRAS`, `MODO_ESPECIAL_ACTIVO`,
`CACHE_TIPO_LOSETA`, `DIR_TABLE_INDEX`, `FLAG_NIVEL_RECIEN_CARGADO`,
`TEMPORIZADOR_DIRECCION_FORZADA`, `FLAG_DIRECCION_NUEVA`,
`COPIA_FLAG_DIRECCION_NUEVA`, `TRAPDOOR_PHASE`, `VIDAS_RESTANTES`
(`$03`->`3`), `PUNTUACION`, `FLAG_VIDA_EXTRA`,
`CONTADOR_VUELTAS_NIVELES`, `MODO_ESPECIAL` (el resto eran `$00`->`0`,
mismo valor, cambio de formato puro). Dejados en hex tras revisar
cada uno: `POSICION_PARPADEO_BOLA`/`CACHE_COLUMNA_LOSETA`/
`REFERENCE_POINT` (direcciones/coordenadas), `SELECTOR_SPRITE_COMECOCOS`
(atado al sentinela hex `$FE`), `DIRECCION_DE_MOVIMIENTO`/
`DIRECCION_SIN_PROCESAR`/`DIRECCION_FORZADA` (bitmask de direccion),
`POSICION_ACTUAL_CAMARA` (coordenada empaquetada), `COLOR_GUARDADO`/
`COLOR_ACTUAL` (nibbles de color VDP empaquetados), `RNG_SEED`
(semilla arbitraria), `SCROLL_LR_PARAM` (significado sin confirmar,
valores vistos con pinta de mascara de bits).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).


### Formato: hex -> decimal en TABLA_CLASE_ALINEAMIENTO

Convertidos a decimal los 16 bytes de `TABLA_CLASE_ALINEAMIENTO`
(`$00-$04` -> `0-4`): son las 5 clases de alineamiento ya resueltas,
no un bitmask ni una direccion. Ganancia de legibilidad pequena (son
valores de un solo digito) pero consistente con el criterio de
"indice/clase -> decimal". `TABLA_PISTA_TANQUE_AVION` se dejo sin
tocar (es un `DS 6,$00` de relleno reservado, sin datos de fabrica
con significado propio).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).


### Comentarios VRAM anadidos + hex corregido en las 7 llamadas a TAIL_DECODE de PANTALLA_PRESENTACION_NIVEL/IML_9078

A peticion del usuario, se anadio un comentario explicito en cada
`LD HL,$XXXX` que precede a un `CALL TAIL_DECODE` en
`madmix1_body.asm`, aclarando que ese valor es una posicion dentro
de la tabla de patrones de VRAM (SCREEN2, $0000-$17FF) -- NO una
direccion de RAM del Z80, y por tanto NUNCA se debe convertir en
aritmetica de etiqueta (a diferencia de los `DE` de la misma
llamada, que si son direcciones RAM del Z80 hacia los registros de
texto).

De paso, se encontraron y corrigieron los `DE`/direcciones que SI
eran hex-sin-sustituir (mismo patron sistemico de siempre):
- `DE,$918B` -> `DE,EXTRA_TEXT`
- `DE,$9173` -> `DE,EXTRALIFE_TEXT`
- `DE,$9192` -> `DE,CLEAR_TEXT_1`
- `DE,$919E` -> `DE,READY_TEXT`
- `DE,$91AA` -> `DE,CLEAR_TEXT_2`
- `DE,$91B6` -> `DE,GAMEOVER_TEXT`
- `($9193),A`/`($919F),A`/`($91AB),A` -> `(CLEAR_TEXT_1+1),A`/
  `(READY_TEXT+1),A`/`(CLEAR_TEXT_2+1),A` (aritmetica de etiqueta,
  offset +1 = byte de atributo/color de cada registro de texto)

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- solo
comentarios y sustitucion de hex por etiquetas ya existentes, cero
cambios de contenido. `.dsk`/`.cas`/inventario HTML regenerados: 743
etiquetas (sin cambio de total).



### TAIL_DECODE -> DIBUJAR_TEXTO_VRAM

Renombrada `TAIL_DECODE` (motor generico de "imprimir una cadena de
texto coloreada en VRAM": DE=registro [longitud][atributo/color][C
bytes de caracteres], HL=posicion VRAM en la tabla de patrones; cada
byte >=$20 dibuja un caracter real via TAIL_VDP_PATTERN_WRITE, cada
byte <$20 se interpreta como contador de columnas en blanco a saltar)
a `DIBUJAR_TEXTO_VRAM`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado (2 menciones).



### EXTRA_TEXT -> TEXTO_EXTRA ; EXTRALIFE_TEXT -> TEXTO_VIDA_EXTRA

Renombrados dos textos de HUD mas, siguiendo el patron ya usado con
TEXTO_FASE:
- `EXTRA_TEXT` ("EXTRA") -> `TEXTO_EXTRA`
- `EXTRALIFE_TEXT` ("EN LA PROXIMA... EXTRA") -> `TEXTO_VIDA_EXTRA`

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### PENDING_HUD_FLAG -> FLAG_VIDA_EXTRA

Renombrada `PENDING_HUD_FLAG` a `FLAG_VIDA_EXTRA`, tras confirmar su
rol exacto: flag de "vida extra pendiente de otorgar", con el mismo
patron de "consumir una vez" que `FLAG_NIVEL_RECIEN_CARGADO`. Se
arma en `IML_90D8` (al completar un nivel, copiando
`LEVEL_REC_HUD_FLAG` -- offset 7 del registro de nivel -- antes de
que `CARGAR_NIVEL` lo sobrescriba con los datos del siguiente nivel)
y se consume en `PANTALLA_PRESENTACION_NIVEL`: se suma a
`VIDAS_RESTANTES` (con tope, no aplica si llegaria a 5 o mas) y, si
se aplica, dibuja `TEXTO_EXTRA` ("EXTRA") en pantalla.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### INIT_8FB7 -> SIN_VIDA_EXTRA

Renombrada `INIT_8FB7` a `SIN_VIDA_EXTRA`. No es una funcion propia
-- es el punto de encuentro dentro de `PANTALLA_PRESENTACION_NIVEL`
al que caen los 2 saltos condicionales del bloque de `FLAG_VIDA_EXTRA`
cuando NO se otorga la vida extra (flag a 0, o el calculo se pasaria
de 5 vidas). A partir de ahi arranca un segundo chequeo, distinto:
si `LEVEL_REC_HUD_FLAG` (del nivel recien cargado) vale 1 y hay menos
de 4 vidas, dibuja `TEXTO_VIDA_EXTRA` ("EN LA PROXIMA... EXTRA") como
aviso de que el siguiente nivel dara vida extra.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### Comentario anadido: tope de 5 vidas en el chequeo de vida extra

Anadido un comentario explicito en el `CP $05` de
`PANTALLA_PRESENTACION_NIVEL` (dentro del bloque de `FLAG_VIDA_EXTRA`):
"el numero maximo de vidas es 5 -- por encima no se otorgan mas
vidas extra". Aclara el proposito del chequeo ya explicado en la
conversacion: si `VIDAS_RESTANTES + FLAG_VIDA_EXTRA` alcanzaria 5,
la vida extra se descarta en silencio.

**Verificado**: recompilado, diffs en la linea base exacta de
siempre (7/2) -- solo comentario, cero cambios de contenido.



### LEVEL_REC_HUD_FLAG -> FLAG_VIDA_EXTRA_NIVEL

Renombrado el campo offset 7 del registro de nivel (20 bytes,
`LEVEL_TABLE`/`LEVEL_REC_WORK`) de `LEVEL_REC_HUD_FLAG` a
`FLAG_VIDA_EXTRA_NIVEL`, distinguiendolo de `FLAG_VIDA_EXTRA` (la
variable de relay en RAM que copia este valor al completar el
nivel). Marca, por nivel, si completarlo otorga una vida extra;
se lee dos veces en la transicion de nivel: una para el nivel recien
completado (relay a FLAG_VIDA_EXTRA) y otra para el nivel recien
cargado (aviso "EN LA PROXIMA... EXTRA").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### INIT_8FCE -> PAUSA_TEXTO_FASE ; INIT_LOOP_8FD1 -> PAUSA_TEXTO_FASE_LOOP

Renombradas dos etiquetas mas dentro de la secuencia de transicion
de nivel:
- `INIT_8FCE` -> `PAUSA_TEXTO_FASE`: punto de encuentro (no es
  funcion propia) donde caen los saltos condicionales del bloque de
  aviso de vida extra ("EN LA PROXIMA... EXTRA"); reactiva
  interrupciones y arranca una espera fija de 80 frames mostrando el
  HUD de fase/vida extra.
- `INIT_LOOP_8FD1` -> `PAUSA_TEXTO_FASE_LOOP`: el cuerpo del bucle
  HALT/DJNZ de esos 80 frames.

Se investigo tambien, a raiz de una pregunta del usuario, que el
verdadero "READY? se queda congelado hasta pulsar una tecla" ocurre
MAS ADELANTE en la secuencia (tras esta pausa fija), en el bucle
`IML_POLL_90F2` (bucle indefinido, sondea LEER_TECLADO hasta detectar
cualquier tecla/direccion) precedido por otra espera fija de 50
frames en `IML_WAIT_90EC` -- ambos con nombres propuestos
(`ESPERA_INICIO_NIVEL`/`ESPERAR_TECLA_INICIO`) pero AUN NO
renombrados, pendientes de una futura ronda si el usuario los
confirma.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### INIT_MAIN_LOOP -> PREPARAR_INICIO_NIVEL

Renombrada `INIT_MAIN_LOOP` a `PREPARAR_INICIO_NIVEL`, tras el
analisis detallado de su cuerpo en esta conversacion: NO es el bucle
principal del juego (eso es `IML_9078`/`IML_90B7`) -- es la secuencia
de un solo paso "nivel recien cargado -> reposicionar HUD segun
camara -> dibujar READY? -> arrancar musica -> entrar en la espera
de tecla", ejecutada solo en las transiciones (arranque, cambio de
nivel, perdida de vida), nunca cada frame.

De paso se corrigio el comentario de cabecera (lineas ~2375-2391)
que databa de una hipotesis anterior y decia explicitamente "resulta
ser el BUCLE PRINCIPAL DEL JUEGO -- INICIO nunca hace RET, entra en
este bucle y no vuelve a salir" -- contradicho por el hallazgo ya
documentado de que el bucle real es IML_9078/IML_90B7 y
PREPARAR_INICIO_NIVEL se re-entra puntualmente, no de forma continua.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### TABLE_INIT -> INICIALIZAR_ITEMS_NIVEL (comentario ampliado)

Renombrada `TABLE_INIT` a `INICIALIZAR_ITEMS_NIVEL`, tras una
discusion sobre la distincion "item" (estado persistente por nivel:
posicion/fase de fantasmas, mariquita, repugnantoso) vs. "actor"
(entrada transitoria por frame en la tabla de MOTOR_ACTORES, gestionada
por RESET_CONTADOR_ACTORES) -- se descarto el nombre inicialmente
propuesto ("INICIALIZAR_TABLA_ACTORES") por describir la funcion
equivocada, ya que esta rutina no toca la tabla de actores en
absoluto.

Se amplio tambien el comentario de cabecera para detallar exactamente
que inicializa: las 3 tablas de items (ITEM_TABLE_PELMAZOIDE/
MARICOCO/REGPUNANTOSO, reposicionadas al punto de referencia del
nivel), la zona de flash $5773, los flags de direccion forzada
(con el caso especial SPECIAL_MODE=3), y (via su segundo punto de
entrada TI_2C2E_ENTRY) la tabla HINT_POS_TABLE de trampillas/pista.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### Comentario corregido: TAIL_LEVELCYCLE_HELPER_ALT ($02C0 es MAS CORTO que $0300, no mas largo)

El comentario de `TAIL_LEVELCYCLE_HELPER_ALT` decia que `BC=$02C0`
era un "recorrido mas largo" que el de `TAIL_CREDITS_MAIN`
(`BC=$0300`) -- aritmetica simple lo desmiente: `$02C0`=704 decimal,
`$0300`=768 decimal, 704 < 768. Es decir, el ciclador de niveles de
muestra procesa MENOS celdas de color que el refresco de HUD/creditos,
no mas. Corregido.

**Verificado**: recompilado, diffs en la linea base exacta de
siempre (7/2) -- solo cambio de comentario, cero cambios de
contenido.



### TAIL_CREDITS_MAIN -> APLICAR_COLOR_PANTALLA

Renombrada `TAIL_CREDITS_MAIN` a `APLICAR_COLOR_PANTALLA`. Se
descarto un nombre atado al "marco de caramelo" (p.ej.
`APLICAR_COLOR_MARCO_CARAMELO`) porque la tabla que procesa
(`LEVELCYCLE_RESOURCE_TABLE`, 768 bytes) cubre la REJILLA DE COLOR
COMPLETA de la pantalla (32x24 celdas, toda la tabla de color de
VRAM $2000), no solo el borde -- y se reutiliza tanto para el HUD de
nivel como para la pantalla de demo, no solo para los creditos pese
al nombre original.

De paso se corrigio otra entrada de `recursos/mapa_memoria.html`
(segmento 0x8F24-0x9136) que aun describia `PREPARAR_INICIO_NIVEL`
como "el BUCLE PRINCIPAL DEL JUEGO" -- desactualizada desde la ronda
del rename de esa etiqueta, donde ya se corrigio la version en el
.asm pero no esta entrada del mapa de memoria.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### SPECIAL_MODE -> MODO_ESPECIAL (familia completa)

Renombrada `SPECIAL_MODE` ($2C2D, enum 0=ninguno/1=bola de poder/
2=hipopotamo/3=herramienta/8=tanque/9=avion) a `MODO_ESPECIAL`. Por
sustitucion de subcadena, arrastro tambien -- de forma intencionada,
para mantener consistencia -- al resto de la familia:
- `SPECIAL_MODE_FLAG` -> `MODO_ESPECIAL_FLAG`
- `SPECIAL_MODE_COUNTDOWN` -> `MODO_ESPECIAL_COUNTDOWN`
- `SPECIAL_MODE_ACTIVE` -> `MODO_ESPECIAL_ACTIVE`
- `ML_SPECIAL_MODE_TICK` -> `ML_MODO_ESPECIAL_TICK`

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### DIR_BEHAVIOR_SELECTOR -> SELECTOR_DIRECCION_SCROLL_FINO

Renombrada `DIR_BEHAVIOR_SELECTOR` ($2C11) a
`SELECTOR_DIRECCION_SCROLL_FINO`, tras cerrar su funcion exacta en
esta conversacion: es el valor, leido de una subtabla indexada por
direccion de movimiento + posicion exacta (0-15) dentro de la loseta
actual (via TILE_DISPATCH_TABLE/TILE_DISPATCH_PTRS/SUBTABLE_A-D), que
se pasa como parametro a GESTIONAR_SCROLL para decidir, cada frame,
si toca disparar el scroll FINO de 4px (SCROLL_UP/SCROLL_DOWN/
SCROLL_LR) y en que eje -- NO decide directamente el redibujado de
loseta nueva (eso es un chequeo posterior y separado, basado en
PACMAN_POS, dentro de SCROLL_LOSETA_BUFFER_VRAM).

Contexto de la investigacion (larga, con varias correcciones propias
en el camino): tambien se aclaro de paso, a raiz de dudas del
usuario, el mecanismo real de perdida de vida -- ITEM_EFFECT ($57D8)
detecta colision comecocos-enemigo por ventana VRAM fija (la camara
siempre esta centrada en el comecocos), y CONFIRMADO que el modo
especial 3 (EXCAVATOFONO/herramienta) NO protege de morir (redirige
via "JP Z,IE_57FD" al mismo tratamiento que modo 0/normal, solo con
duracion de temporizador distinta) -- solo los modos 1 (bola de
poder) y 2 (hipodoso) evitan la muerte por contacto.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### SELECTOR_DIRECCION_SCROLL_FINO -> SELECTOR_SPRITE_COMECOCOS (correccion importante)

Tras un rastreo registro a registro muy detallado (con ayuda de un
agente de exploracion dedicado), se corrigio la hipotesis anterior
sobre esta variable ($2C11). NO es principalmente un parametro de
scroll fino -- eso fue un error de lectura en una ronda anterior (el
parametro real que recibe GESTIONAR_SCROLL viene de un registro H
distinto, el bitmask de direccion crudo, no de esta variable).

El uso real confirmado: sus 7 bits bajos viajan (via ML_SCROLL_PREP,
registro B, preservado en la pila durante las llamadas a
GESTIONAR_SCROLL/manejadores de item) hasta la llamada a
MOTOR_ACTORES para dibujar al comecocos, donde se usan como INDICE en
PTR_TABLA_SPRITES (registro B, madmix1_body.asm:171-181). Es decir:
es el SELECTOR DEL FOTOGRAMA DE ANIMACION del comecocos (que fase de
boca + orientacion dibujar) -- el bit7 es el volteo horizontal
(reutiliza el sprite de la derecha para la izquierda, igual mecanismo
que los fantasmas). Los valores reales de las sub-tablas de
direccion ($00,$01,$02 para una direccion, $03,$04,$05 para otra,
etc.) son literalmente indices de sprite de las 3 fases de boca del
comecocos, cicladas por DIR_TABLE_INDEX segun la posicion exacta
dentro de la loseta -- esto es lo que produce el efecto visual de
"boca abriendose y cerrandose" al caminar.

Esto explica tambien, cerrando el hilo de investigacion de varias
rondas: por que PANTALLA_PRESENTACION_NIVEL precarga esta variable a
14 (indice de SPR14_PM_OBRA_ABAJO, sprite de "obra"/excavadora) o 0
(SPR00, comecocos normal) segun si MODO_ESPECIAL era 3 al perder una
vida -- es pura continuidad visual: que el comecocos aparezca
dibujado con el sprite correcto (excavadora vs normal) desde el
primer frame tras el respawn, sin parpadear brevemente con el sprite
equivocado.

Renombrada en consecuencia a `SELECTOR_SPRITE_COMECOCOS`. Se amplio
tambien el comentario de cabecera de `ML_DIR_SUBTABLE_LOOP`
(madmix_scr_body.asm, antes decia "candidato fuerte... sin confirmar
el detalle fino") con el hallazgo completo ya cerrado.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### INIT_8FEA -> SPRITE_COMECOCOS_INICIAL

Renombrada `INIT_8FEA` a `SPRITE_COMECOCOS_INICIAL` -- es el punto de
encuentro del if/else que decide si `SELECTOR_SPRITE_COMECOCOS` arranca
con el indice del sprite de excavadora (14, si se perdio la vida en
modo EXCAVATOFONO) o el normal (0), y ahi mismo se guarda ese valor.
Comentario actualizado para reflejar el hallazgo ya cerrado (indice
real de sprite, no un "flag de modo especial" generico).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 743 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### SPRITE_COMECOCOS_INICIAL -> .CONTINUAR_RESPAWN (etiqueta local)

Renombrada `SPRITE_COMECOCOS_INICIAL` a `.CONTINUAR_RESPAWN`, esta vez
como etiqueta LOCAL (sintaxis de punto de sjasmplus, con ambito
dentro de `PREPARAR_INICIO_NIVEL`) en vez de global -- unico uso real
era dentro de esa misma funcion. De paso se conservaron/ampliaron los
comentarios que el usuario habia anadido a mano sobre estas lineas
(aclarando "comecocos especial (EXCAVATOFONO) para modo especial 3",
"comecocos normal (SPR00) para todos los demas modos").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (baja 1 respecto a
la ronda anterior -- la etiqueta local se contabiliza distinto en
`gen_inventory.py`, no es una perdida real de contenido). Sin
menciones en los HTML activos.



### MOVE_DIRECTION -> DIRECCION_DE_MOVIMIENTO ; FORCED_DIRECTION -> DIRECCION_FORZADA

Renombradas dos variables de estado de partida:
- `MOVE_DIRECTION` ($2C10) -> `DIRECCION_DE_MOVIMIENTO`: la direccion
  final y validada del comecocos para el frame actual (resultado del
  chequeo de alineamiento en MAIN_LOOP; sirve tambien de respaldo
  para el frame siguiente si la nueva direccion candidata no es
  valida).
- `FORCED_DIRECTION` ($2C12 aprox.) -> `DIRECCION_FORZADA`: override
  de "direccion sticky" activado por los manejadores de flecha (fuerza
  una mascara de alineamiento concreta en vez de la real).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total). `recursos/flujo_programa.html` y `recursos/mapa_memoria.html`
actualizados.



### FORCED_DIR_TIMER -> TEMPORIZADOR_DIRECCION_FORZADA

Renombrada `FORCED_DIR_TIMER` a `TEMPORIZADOR_DIRECCION_FORZADA`
(incluye de paso `FORCED_DIR_TIMER_TICK` -> `TEMPORIZADOR_DIRECCION_FORZADA_TICK`,
cola comun de limpieza de HNDLR_SUELO_SIN_BOLA).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total). `recursos/mapa_memoria.html` actualizado.



### BALL_BLINK_TIMER -> TEMPORIZADOR_PARPADEO_BOLA

Renombrada `BALL_BLINK_TIMER` a `TEMPORIZADOR_PARPADEO_BOLA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 742 etiquetas (sin cambio de
total). Sin menciones en los HTML activos.



### Formato: hex -> decimal en el resto del codigo (uso de las variables ya convertidas)

A peticion del usuario, tras convertir a decimal las declaraciones RAM
de la seccion anterior ($2C07-$2C2D) y `TABLA_CLASE_ALINEAMIENTO`, se
revisó el RESTO de `madmix_scr_body.asm`/`madmix1_body.asm` en busca
de asignaciones (`LD A,$XX`/`LD (HL),$XX`) o comparaciones (`CP $XX`)
sobre esas mismas variables que seguian en hex, para que el estilo sea
consistente entre la declaracion y cada uso. Cambios aplicados:

- Los 16 registros de `TABLA_NIVELES` (offset 11, "duracion parpadeo"):
  `$FA`->`250` (11 registros), `$C8`->`200` (2), `$32`->`50`,
  `$FF`->`255`, `$50`->`80`, `$96`->`150`. Tambien un comentario que
  citaba el valor en hex ("compara CP $10 (16)") corregido a decimal.
- `NIVEL_ACTUAL`: `CP $10`->`CP 16` y `LD (HL),$01`->`LD (HL),1` en
  `VERIFICAR_FIN_NIVEL`/`SIGUIENTE_NIVEL` (madmix1_body.asm).
- `CONTADOR_BOLAS_COMIDAS`: `LD HL,$0000`->`LD HL,0` en el reset de
  `CARGAR_NIVEL`.
- `MODO_ESPECIAL`/`MODO_ESPECIAL_FLAG`: todas las activaciones de modo
  (tanque=8, avion=9, bola de poder=1, hipodoso=2, excavatofono=3) y
  sus comparaciones (`HNDLR_PISTA_COCOTANQUE`, `HNDLR_PISTA_COCONAVE`,
  `HNDLR_ITEM_SUELO`, `HNDLR_HIPODOSO`, `HNDLR_EXCAVATOFONO`,
  `HNDLR_SUELO_SIN_BOLA`, `HNDLR_SUELO_NORMAL`, `HNDLR_BOLITA_NORMAL`,
  `ML_MODO_ESPECIAL_TICK`, `ML_HIPPO_MODE_TICK`) pasadas de hex a
  decimal. En `CONTINUAR_RESET_EXCAVATOFONO` solo se convirtio el
  `CP $03`->`CP 3` sobre `MODO_ESPECIAL`; el `LD A,$0E` que arma
  `DIRECCION_FORZADA`/`TEMPORIZADOR_DIRECCION_FORZADA`/etc. se dejo en
  hex a proposito (ver mas abajo el mismo criterio).
- `MODO_ESPECIAL_CUENTA_ATRAS`: `CP $3C`->`CP 60` (las 2 apariciones,
  umbral de cuenta atras en `ML_MODO_ESPECIAL_TICK`).
- El armado del contador de muerte tras `MODO_ESPECIAL_ACTIVO`
  (`IE_581B`): `CP $03`->`CP 3`, `LD A,$28`->`LD A,40`,
  `LD A,$2D`->`LD A,45` (duraciones de 40/45 fotogramas ya confirmadas
  en una ronda anterior).
- `CACHE_TIPO_LOSETA`: `LD A,$0F`->`LD A,15` (junto con el comentario)
  en `HNDLR_BOLITA_NORMAL`, al marcar la loseta como "comida".
- `FLAG_NIVEL_RECIEN_CARGADO`/`FLAG_DIRECCION_NUEVA`/
  `COPIA_FLAG_DIRECCION_NUEVA`/`FLAG_VIDA_EXTRA`: todas las
  asignaciones a 0/1 de estos flags booleanos convertidas
  (`ACTUALIZAR_VRAM_FRAME`, `PREPARAR_INICIO_NIVEL`,
  `MOTOR_MOVIMIENTO_COLISION`, `PANTALLA_PRESENTACION_NIVEL`).
- `TRAPDOOR_PHASE`/`TEMPORIZADOR_DIRECCION_FORZADA`: convertida la
  comparacion `HNDLR_TRAMPILLA_CERRADA` (`CP $02`->`CP 2`, sobre el
  valor ya leido de `TRAPDOOR_PHASE`) y su asignacion de
  `TEMPORIZADOR_DIRECCION_FORZADA` (`LD A,$03`->`LD A,3`). Se
  aprovecho tambien para pasar a decimal los chequeos genericos de
  "fase de movimiento correcta" (`AND $03`/`CP $02`->`CP 2`) que
  aparecen repetidos en los 3 manejadores de trampilla, por
  consistencia con el resto. Los `LD A,$02`/`LD A,$01` que arman a la
  vez `DIRECCION_FORZADA` (hex, bitmask de direccion) Y `TRAPDOOR_PHASE`
  (decimal) desde el mismo registro se dejaron en hex -- mismo
  criterio que en `CONTINUAR_RESET_EXCAVATOFONO`: cuando un unico
  valor alimenta una variable "hex" y otra "decimal" a la vez, gana el
  formato de la variable primaria/compartida.
- `VIDAS_RESTANTES`: `CP $05`->`CP 5` (tope de 5 vidas) y `CP $04`->
  `CP 4` (aviso de vida extra proxima) en `PANTALLA_PRESENTACION_NIVEL`;
  tambien `LD (HL),$00`->`LD (HL),0` para `FLAG_VIDA_EXTRA` en el
  mismo bloque. Dejado en hex a proposito: `SUB $01` en el
  decremento de `VIDAS_RESTANTES` (`REINICIAR_PARTIDA`/muerte) -- es el
  byte operando exacto que el truco de vidas infinitas de TI_BREAK
  parchea a `SUB $00`, documentado ya como tal en el propio comentario,
  asi que se mantiene en hex para no romper la correspondencia con esa
  nota.
- `PUNTUACION`: `LD DE,$2710`->`LD DE,10000`, el umbral de puntos que
  activa el texto "BESTIA" en `DIBUJAR_MARCADOR_PUNTOS`.

Revisadas sin cambios necesarios (ya estaban en decimal o no tenian
literales hex asociados): `DIR_TABLE_INDEX` (solo `AND $03`, mascara
de modulo, se deja en hex), `MODO_ESPECIAL_ACTIVO` (unico sitio con
literal ya convertido en una ronda anterior; el resto son `XOR A`/
`AND A`/`DEC (HL)`, sin operando), `CONTADOR_VUELTAS_NIVELES` (ya
estaba en decimal en `REINICIAR_PARTIDA`, el resto son lecturas sin
comparacion).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/`.cas`
regenerados (sin cambio de etiquetas, `gen_inventory.py` no aplica --
cambio de formato puro, ningun simbolo nuevo). Sin cambios necesarios
en `recursos/mapa_memoria.html`/`recursos/flujo_programa.html` (no
citan estos valores hex en su texto).



### Estudio (sin aplicar): propuesta de nombres en español para la familia `JTS2_` de `MOTOR_ACTORES`

A peticion del usuario, analisis de las ~28 etiquetas internas de
`MOTOR_ACTORES` (0x8440-0x87FF, `madmix1_body.asm:95-775`) que
todavia arrastran el prefijo de desensamblado `JTS2_` (placeholder
generico, igual que en su dia `IML_`/`TI_`/`TAIL_`). **Este apartado
es solo estudio -- no se ha renombrado nada en el codigo todavia**,
a la espera de que el usuario confirme cuales de las propuestas
quiere aplicar.

**Contexto (ya resuelto en rondas anteriores, resumen)**: `MOTOR_ACTORES`
es la rutina que registra un actor (comecocos, fantasma, item...) en
la tabla de actores activos de 12 bytes en `$92E3` (contador en
`$8437`), calcula su posicion de dibujado y lo pinta de inmediato en
un buffer con desplazamiento de sub-pixel (mezcla AND/OR bit a bit
via el truco de leer/escribir memoria rapido con SP). El array
completo se recorre una segunda vez, ya en la ISR
(`ISR_HOUSEKEEPING`), via `JTS2_RESUME`.

**Pieza nueva de contexto, encontrada al cruzar esta rutina con el
hallazgo ya existente de la "Zona 0xDC00"** (comentario en
`RLE_TABLE_D6B6`, `madmix1_body.asm:4440-4446`): la direccion que
calcula `ADDR_FROM_DC00` (usada por `MOTOR_ACTORES` para IX+2/3) cae
dentro de la MISMA tabla que sostiene el marco decorativo
("marco_caramelo"), en su subtramo `$DC00` en adelante -- y ese
mismo comentario ya documentaba que esa subzona se lee como PARES DE
MASCARAS AND/OR de composicion de sprite contra el fondo. Esto encaja
exactamente con el patron AND/OR de `JTS2_85A2`/`JTS2_PROCESS_ACTORS`
mas abajo: la tabla en `$DC00+` no es un buffer de "salida" generico
sino, mas probablemente, una tabla de MASCARAS DE RECORTE/COMPOSICION
por posicion de pantalla, y `JTS2_COPY_CURSOR` lo que hace es
CAPTURAR (prefetch) las mascaras que le tocan a cada actor de este
frame hacia el cursor en RAM baja (`$0500+`), para que el resto del
pipeline (`JTS2_85A2`/render y, mas tarde, `JTS2_PROCESS_ACTORS`) las
consuma sin tener que recalcular la direccion cada vez.

**Hallazgo colateral**: `JTS2_PROCESS_ACTORS` (la "segunda pasada",
con codigo automodificable) **no tiene ningun `CALL`/`JP` confirmado
en todo el codigo ya transcrito** -- no coincide con el `CALL $8CFF`
sin identificar de `ISR_HOUSEKEEPING` (direcciones distintas). Puede
que se llame desde un hueco todavia sin transcribir, desde un salto
calculado, o que sea codigo muerto/de una version anterior del motor.
Por eso su nombre propuesto se marca de confianza media y se
recomienda NO renombrarla hasta encontrar su llamador real.

#### Subrutinas y datos con nombre propio (quitando el prefijo `JTS2_`)

| Etiqueta actual | Direccion | Propuesta | Confianza | Motivo |
| --- | --- | --- | --- | --- |
| `JTS2_85A2` | 0x85A2 | `MEZCLAR_Y_AVANZAR_FILA_ACTOR` | Alta | Cola COMPARTIDA por `JTS2_RENDER_A`/`JTS2_RENDER_B`: mezcla 3 bytes con AND/OR contra `(HL)`, avanza `HL` 32 bytes (una fila) y repite via `EX AF,AF'`/`DEC A` hasta agotar el contador de filas. |
| `JTS2_RENDER_A` | 0x85C1 | `DIBUJAR_FILA_DESPLAZADA_DERECHA` | Alta | Variante con `RRA`/`RR L,H` (desplaza el patron a la derecha) antes de fusionar con `JTS2_85A2`. |
| `JTS2_RENDER_B` | 0x8624 | `DIBUJAR_FILA_DESPLAZADA_IZQUIERDA` | Alta | Gemela de la anterior con `RLA`/`RL H,L` (desplaza a la izquierda). |
| `JTS2_COPY_CURSOR` | 0x8687 | `CAPTURAR_MASCARAS_ACTOR` | Media-alta | Extrae del area `$DC00+` (mascaras AND/OR por posicion, ver arriba) hacia el cursor en RAM baja, para el actor recien registrado. |
| `JTS2_SAVED_IX` | 0x86B9 | `IX_ACTOR_GUARDADO` | Alta | Word de datos: copia de `IX` (puntero al registro del actor) que `JTS2_RESUME` retoma. |
| `JTS2_RESUME` | 0x86BB | `CONTINUAR_CAPTURA_MASCARAS_ACTORES` | Alta | Repite la misma captura de `CAPTURAR_MASCARAS_ACTOR` recorriendo el array hacia atras (paso -12), llamada desde `ISR_HOUSEKEEPING` cada vblank. |
| `JTS2_XOR_TRANSFORM` | 0x86FA | `INVERTIR_BITS_PATRON_ACTOR` | Media-alta | `RLC C`/`RRA` x8 por byte = truco clasico de invertir el orden de los 8 bits de un byte. Se dispara solo si el bit7 del valor `D` (comparacion de mascaras de camara) difiere -- mismo convenio ya confirmado en `SELECTOR_SPRITE_COMECOCOS` (bit7 = volteo horizontal), asi que es candidato fuerte a ser "la mitad bit a bit" de un volteo horizontal de sprite. Proposito exacto (volteo real vs. otra transformacion) sin confirmar con una prueba en vivo. |
| `JTS2_SWAP_SORT` | 0x873A | `INVERTIR_ORDEN_BYTES_PATRON_ACTOR` | Media-alta | Intercambia bytes entre dos punteros que convergen hacia el centro -- el complemento natural de `INVERTIR_BITS_PATRON_ACTOR`: invertir tambien el ORDEN de los bytes de la fila (no solo los bits de cada uno) completa un volteo horizontal de un grafico de mas de 8px de ancho. Se dispara con el bit6 del mismo valor `D`. Mismo nivel de confianza que la anterior (mecanismo claro, proposito final por confirmar). |
| `JTS2_PROCESS_ACTORS` | 0x8779 | `COMPONER_ACTORES_EN_BUFFER` | Media (ver aviso de llamador sin confirmar arriba) | Segunda pasada sobre el array completo, sin desplazamiento de sub-pixel (mezcla OR simple), con codigo automodificable; termina poniendo `$8437` a 0 -- parece la "composicion final" tras el sub-pixel-blit incremental de `MOTOR_ACTORES`. |
| `JTS2_TABLE_87FB` | 0x87FB | `TABLA_MASCARA_RECORTE_BORDE` | Baja-media | Solo 5 bytes reales, indexada por posicion horizontal gruesa (`AND $F8`, dividida entre 8 sin multiplicar). Hipotesis: mascara de recorte para actores cerca del borde de pantalla; sin confirmar contra que se compara realmente. |
| `JTS2_SELFMOD_1` | 0x8707 (operando) | `OPERANDO_MASCARA_A_IDA` | Media | Ver siguiente fila -- patron simetrico completo. |
| `JTS2_SELFMOD_2` | -- | `OPERANDO_MASCARA_B_IDA` | Media | " |
| `JTS2_SELFMOD_3` | -- | `OPERANDO_MASCARA_C_IDA` | Media | " |
| `JTS2_SELFMOD_4` | -- | `OPERANDO_MASCARA_C_VUELTA` | Media | " |
| `JTS2_SELFMOD_5` | -- | `OPERANDO_MASCARA_B_VUELTA` | Media | " |
| `JTS2_SELFMOD_6` | -- | `OPERANDO_MASCARA_A_VUELTA` | Media | Los 6 operandos automodificados de `COMPONER_ACTORES_EN_BUFFER` se rellenan por pares identicos desde `IX+7/8/9` (1=6, 2=5, 3=4) -- un patron "ida y vuelta" de 6 pasos, coherente con el ajuste de fila de `JTS2_87E6` (avanza y a veces envuelve, como recorriendo dos mitades de un bloque). |
| `JTS2_8774` | 0x8774 | `SALIR_MOTOR_ACTORES` | Alta | Epilogo COMPARTIDO (`POP BC/DE/HL/AF`+`RET`) de toda la familia: usado como salida temprana desde el guard de `MOTOR_ACTORES`, y como fin natural de `INVERTIR_BITS_PATRON_ACTOR`/`INVERTIR_ORDEN_BYTES_PATRON_ACTOR`/`MEZCLAR_Y_AVANZAR_FILA_ACTOR`. |

#### Puntos de fusion/rama internos -- propuestos como etiquetas LOCALES (patron ya usado en el proyecto, p.ej. `.LOOP_LIMPIEZA`)

Estos no se llaman nunca desde fuera de su rutina "padre", asi que
encajan con el patron de etiqueta local (`.nombre`, ambito a la
etiqueta global anterior) ya usado en otras partes del proyecto.

**Dentro de `MOTOR_ACTORES`** (guarda de entrada + preparacion del
actor, antes de entrar en el bucle de dibujado):

| Etiqueta actual | Propuesta local | Motivo |
| --- | --- | --- |
| `JTS2_8455` | `.DESCARTAR_ACTOR` | Salida compartida de las 3 guardas de rango (contador>=10, B>=$40, E fuera de $04-$73). |
| `JTS2_8457` | `.COMPROBAR_LIMITE_VERTICAL` | Completa la guarda de `E` (limite superior `$74`) antes de caer en `.DESCARTAR_ACTOR`. |
| `JTS2_846D` | `.CONTINUAR_TRAS_SELECCION_MITAD` | Fusion tras elegir `$90`/`$B0` (mitad de pantalla/camara) en `$843E`. |
| `JTS2_84A9` | `.CONTINUAR_TRAS_CLIP_VERTICAL` | Fusion tras comparar `D` contra `$843E`. |
| `JTS2_84EE` | `.CALCULAR_RECORTE_CAMARA` | Rama alternativa del calculo de recorte vertical relativo a la camara. |
| `JTS2_8502` | `.CONTINUAR_TRAS_RECORTE` | El actor sobrevive al recorte -- continua calculando IX+0/1. |
| `JTS2_84FD` | `.DESCARTAR_ACTOR_FUERA_DE_CAMARA` | Bail-out especifico del calculo de recorte (salta a `SALIR_MOTOR_ACTORES`). |
| `JTS2_8510` | `.CONTINUAR_TRAS_LIMITAR_FILAS` | Fusion tras forzar el contador de filas (`IX+4`) a minimo 1. |
| `JTS2_851F` | `.CONTINUAR_CURSOR_ACTOR` | Rama: no es el primer actor del frame -> reutiliza el cursor ya en curso (`$8438`). |
| `JTS2_8523` | `.GUARDAR_CURSOR_ACTOR` | Fusion: guarda el puntero de cursor en `IX+5/6` y llama a `CAPTURAR_MASCARAS_ACTOR`. |
| `JTS2_8545` | `.CONTINUAR_TRAS_INVERSION_BITS` | Fusion tras la llamada opcional a `INVERTIR_BITS_PATRON_ACTOR`. |
| `JTS2_854F` | `.CONTINUAR_TRAS_INVERSION_BYTES` | Fusion tras la llamada opcional a `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`. |
| `JTS2_856D` | `.CONTINUAR_TRAS_ELEGIR_DIRECCION` | Fusion tras elegir `IY`=render derecha/izquierda. |
| `JTS2_8584` | `.BUCLE_DIBUJAR_ACTOR` | Bucle principal: lectura rapida por SP de un par de filas fuente + `JP (IY)` a la variante de render. |

**Dentro de `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`** (misma
estructura interna en ambas, nombres identicos por simetria):

| Etiqueta actual (der.) | Etiqueta actual (izq.) | Propuesta local | Motivo |
| --- | --- | --- | --- |
| `JTS2_85C5` | `JTS2_8628` | `.DESPLAZAR_SUBPIXEL_FILA1` | Primer bucle de desplazamiento de sub-pixel bit a bit (`DJNZ`). |
| `JTS2_85D8` | `JTS2_863B` | `.ESCRIBIR_FILA1` | Mezcla AND/OR de la primera de las dos filas de 3 bytes + recarga por SP de la siguiente fila fuente. |
| `JTS2_860E` | `JTS2_8671` | `.DESPLAZAR_SUBPIXEL_FILA2` | Segundo bucle de desplazamiento, para la fila siguiente. |
| `JTS2_8621` | `JTS2_8684` | `.CONTINUAR_FILA2` | Fusion final -> `JP MEZCLAR_Y_AVANZAR_FILA_ACTOR` (reutiliza la cola compartida para la segunda fila). |

**Dentro de `CAPTURAR_MASCARAS_ACTOR`**: `JTS2_869A` -> `.BUCLE_CAPTURA`
(bucle de copia de 6 bytes/iteracion, `DEC A`/`JP NZ`).

**Dentro de `CONTINUAR_CAPTURA_MASCARAS_ACTORES`**: `JTS2_86BF` ->
`.SIGUIENTE_ACTOR` (cabecera del bucle externo: decrementa `$8437`,
`RET Z` si llega a 0); `JTS2_86D9` -> `.BUCLE_CAPTURA` (bucle interno,
misma estructura que en `CAPTURAR_MASCARAS_ACTOR` con los `EX DE,HL`
extra por recorrer el array al reves).

**Dentro de `INVERTIR_BITS_PATRON_ACTOR`**: `JTS2_8707` ->
`.BUCLE_BLOQUES` (bucle externo, 48 iteraciones fijas); `JTS2_870E` ->
`.BUCLE_INVERTIR_BYTE` (bucle interno, la inversion de bits en si,
`DJNZ` sobre la altura en `$8435`).

**Dentro de `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`**: `JTS2_874E` ->
`.COMPROBAR_CONVERGENCIA` (cabecera del bucle: calcula el puntero
final y compara si ya coincide con el inicial); `JTS2_8760` ->
`.INTERCAMBIAR_BLOQUE` (rama: los punteros aun difieren, intercambia
un bloque); `JTS2_8762` -> `.BUCLE_INTERCAMBIO` (bucle interno de
intercambio byte a byte).

**Dentro de `COMPONER_ACTORES_EN_BUFFER`**: `JTS2_8786` ->
`.SIGUIENTE_ACTOR` (cabecera del bucle externo: instala los 6
operandos automodificados y prepara `SP`/`HL`/`B`); `JTS2_87B2` ->
`.BUCLE_COMPONER` (bucle interno de 6 pasos, `POP DE`/`AND E`/`OR D`/
`LD (HL),A` con los operandos automodificados); `JTS2_87E6` ->
`.AJUSTAR_SALTO_FILA` (fusion: comprueba `H AND $06` y ajusta `L`/`H`
para saltar al siguiente bloque de fila cuando toca).

**Pendiente antes de aplicar**: confirmar con el usuario que criterio
usar para las 6 tablas de arriba (aplicar todo de golpe vs. por
bloques), y decidir si `COMPONER_ACTORES_EN_BUFFER`/
`TABLA_MASCARA_RECORTE_BORDE` se renombran ya (con su confianza
media/baja marcada en el propio nombre, como se ha hecho antes con
otras hipotesis del proyecto) o se dejan para cuando aparezca mas
evidencia (llamador real de la primera, uso real confirmado de la
segunda).

**Nota de verificacion**: apartado de analisis puro, sin cambios en
ningun `.asm` -- no aplica recompilar ni diff.



### Aplicado el estudio: renombrada toda la familia `JTS2_` de `MOTOR_ACTORES`

El usuario confirmo ("OK, PROCEDE A SUSTITUIR") aplicar integra la
propuesta del estudio anterior. Renombradas las 45 etiquetas
`JTS2_xxxx` de `madmix1_body.asm:95-787` (0x8440-0x8787):

- **17 subrutinas/datos globales** (quitando el prefijo `JTS2_`):
  `TABLA_MASCARA_RECORTE_BORDE`, `CAPTURAR_MASCARAS_ACTOR`,
  `INVERTIR_BITS_PATRON_ACTOR`, `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`,
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`,
  `MEZCLAR_Y_AVANZAR_FILA_ACTOR`, `IX_ACTOR_GUARDADO`,
  `CONTINUAR_CAPTURA_MASCARAS_ACTORES`, `SALIR_MOTOR_ACTORES`,
  `COMPONER_ACTORES_EN_BUFFER`, y los 6 operandos automodificados
  (ver mas abajo, terminaron como locales en vez de globales).
- **28 puntos de fusion/rama internos**, convertidos a etiquetas
  LOCALES (`.nombre`) segun la tabla del estudio, cada una con
  ambito a su rutina padre real: `MOTOR_ACTORES` (14),
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA` (4 cada una, mismos
  nombres locales por simetria), `CAPTURAR_MASCARAS_ACTOR` (1),
  `CONTINUAR_CAPTURA_MASCARAS_ACTORES` (2), `INVERTIR_BITS_PATRON_ACTOR`
  (2), `INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (3), `COMPONER_ACTORES_EN_BUFFER`
  (2, sin contar los operandos).

**Ajuste durante la aplicacion (2 casos donde el ambito local puro no
funcionaba)**:

- Los 6 `JTS2_SELFMOD_1..6` se propusieron como nombres GLOBALES en el
  estudio, pero al aplicarlos rompian el ambito de `.BUCLE_COMPONER`
  (cada uno es un LABEL real en mitad del bucle, y sjasmplus ata las
  etiquetas locales SIEMPRE a la ultima etiqueta NO local -- al ser
  globales, cada `OPERANDO_MASCARA_*` reiniciaba el ambito). Se
  convirtieron a locales tambien (`.OPERANDO_MASCARA_A_IDA` etc.),
  ahora correctamente anidados bajo `COMPONER_ACTORES_EN_BUFFER`.
- `.BUCLE_DIBUJAR_ACTOR` (dentro de `MOTOR_ACTORES`) se referencia
  tambien desde dentro de `MEZCLAR_Y_AVANZAR_FILA_ACTOR` (bucle
  compartido que reentra en el bucle de dibujado por SP-trick) --
  mismo problema de ambito. En vez de hacerlo global, se uso la
  sintaxis de sjasmplus `ETIQUETA_PADRE.local` (`JP NZ,
  MOTOR_ACTORES.BUCLE_DIBUJAR_ACTOR`), que preserva el ambito local
  real sin sacrificar el nombre.

**Comentarios actualizados**: la cabecera narrativa de `MOTOR_ACTORES`
(lineas 36-94) se amplio con el cruce nuevo (`CAPTURAR_MASCARAS_ACTOR`
lee de la MISMA tabla de mascaras AND/OR del marco de caramelo,
`$DC00+`, no de un buffer de fondo propio) y con la hipotesis de
volteo horizontal para `INVERTIR_BITS_PATRON_ACTOR`/
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (marcada explicitamente como
hipotesis sin confirmar en vivo). El comentario de
`COMPONER_ACTORES_EN_BUFFER` deja explicito que su llamador real
sigue sin identificar.

Sincronizados tambien `src/README.md` y `src/FLUJO_PROGRAMA.md`
(menciones sueltas a `JTS2_RENDER_A/B`, `JTS2_RESUME`,
`JTS2_PROCESS_ACTORS`, y de paso 2 nombres ya obsoletos de una ronda
anterior, `RESET_8437` -> `RESET_CONTADOR_ACTORES`) y
`recursos/mapa_memoria.html` (4 menciones en el bloque de segmentos
0x0500 e 0xD6B6). `recursos/flujo_programa.html` no necesito edicion
manual -- sus unicas menciones vivian en el bloque `INVENTORY`
autogenerado, resuelto con `gen_inventory.py`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: **703 etiquetas** (baja de 742 a
703, -39 -- consistente con el mecanismo ya documentado de que cada
etiqueta LOCAL nueva resta 1 del total de `gen_inventory.py`: se
crearon exactamente 39 etiquetas locales nuevas, 28 puntos de
fusion/rama + 6 operandos automodificados + los 5 sitios que ya eran
locales antes no cuentan -- cero perdida real de contenido).
`recursos/flujo_programa.html` regenerado; `recursos/mapa_memoria.html`
actualizado a mano.



### Estudio (sin aplicar): propuesta de nombres en español para las etiquetas `H5278_` de `MOVER_ITEM_MOVIL`

A peticion del usuario, analisis de `MOVER_ITEM_MOVIL` ($5278,
`madmix_scr_body.asm:1935-2132`) y de sus 14 etiquetas internas
`H5278_xxxx`. **Solo estudio -- no se ha renombrado nada en el codigo
todavia**, a la espera de confirmacion del usuario.

**Que hace `MOVER_ITEM_MOVIL`** (el nombre global ya es bueno, no se
propone cambiarlo): mueve un item "movil" (fantasma via
`HNDLR_PELMAZOIDE`, o mariquita/repugnantoso via `HNDLR_MARICOCO`/
`HNDLR_REGPUNANTOSO`) un paso hacia el comecocos. Estructura en 4
fases:

1. **Calcular direccion de acercamiento** (D=$01/$02/$04/$08) comparando
   la posicion del item contra `REFERENCE_POINT` (camara+8,+16, o su
   version NEGADA si `MODO_ESPECIAL_FLAG` esta activo -- "camara
   invertida"). Se salta esta fase entera (D se queda a 0) si el item
   esta "congelado" (`IX+2`!=0) o si `MODO_ESPECIAL_ACTIVO` (cuenta
   atras) esta en curso.
2. **Solo si esta alineado a loseta** (`IX+0/1` sub-posicion=0):
   recalcula la direccion final. Prueba las 4 direcciones libres con
   `HELPER_5414`; si la direccion deseada (fase 1) es una de las
   libres, la usa (siempre si `MODO_ESPECIAL_FLAG` esta activo, o el
   50% de las veces por tirada de `ITEM_RNG` si no); si no puede o
   toca reroll, elige entre TODAS las libres via `TABLA_CLASE_ALINEAMIENTO`
   y `ITEM_DIR_CHOICE_TABLE` (sesgo de "mantener direccion anterior si
   se puede").
3. **Aplica el movimiento**: guarda la direccion final en `IX+3`,
   la convierte al codigo compacto 1-4 (via `TABLA_CLASE_ALINEAMIENTO`),
   calcula el paso (`$0100` normal, `$0080` mitad de paso si `IX+2`
   esta activo O si `MODO_ESPECIAL_FLAG` esta activo) y lo suma/resta
   a la subposicion X o Y segun el codigo.
4. **Cae sin salto en `HELPER_53A2`** (su "segundo punto de entrada",
   con nombre global propio -- fuera del alcance `H5278_` de este
   estudio): calcula la posicion VRAM del item relativa a la camara y
   si es visible. `HELPER_53A2` tambien se llama con `CALL $53A2`
   directo desde `ACTUALIZAR_DESTELLO_ITEMS` quien se salta las fases 1-3.

**Hallazgo colateral 1 (posible comentario invertido, sin corregir)**:
el comentario junto a `BIT 7, A` en la fase 2 (antes de
`H5278_5340`, item activo/`IX+2`!=0) dice "solo se elige al azar si
la posicion fraccional tiene el bit alto puesto, si no mantiene la
direccion actual". La logica real del `JR NZ, H5278_5340` que sigue
dice lo CONTRARIO: `BIT 7,A` deja `Z=0` (NZ) cuando el bit7 SI esta
puesto, y en ese caso el salto **evita** la eleccion aleatoria
(salta directo a aplicar `A=(IX+3)`, la direccion ya en curso); solo
cuando el bit7 esta a 0 el codigo cae en `H5278_531E` (eleccion
aleatoria). Es decir: bit7 puesto -> MANTIENE direccion; bit7 a
cero -> ELIGE al azar -- exactamente al reves de lo que dice el
comentario actual. No se ha corregido (fuera del alcance de "solo
renombrar"), pero merece una pasada de correccion aparte.

**Hallazgo colateral 2**: la llamada real a `HELPER_53A2` desde
`ACTUALIZAR_DESTELLO_ITEMS` (linea ~2885) sigue en hex, `CALL $53A2`,
pese a que la etiqueta ya existe -- mismo patron sistemico de "hex
sin sustituir" encontrado muchas veces en el proyecto. Tampoco
corregido en esta pasada de solo-analisis.

#### Propuesta: las 14 etiquetas como LOCALES (`.nombre`), ambito `MOVER_ITEM_MOVIL`

Igual que en el estudio de `MOTOR_ACTORES`, ninguna de estas 14 se
llama desde fuera de la rutina, asi que encajan como etiquetas
locales.

| Etiqueta actual | Propuesta local | Motivo |
| --- | --- | --- |
| `H5278_5293` | `.COMPROBAR_ESTADO_ITEM` | Entrada cuando `MODO_ESPECIAL_FLAG`=0 (modo normal): comprueba si el item esta congelado (`IX+2`) o si hay cuenta atras de modo especial en curso, antes de decidir si calcula direccion. |
| `H5278_529F` | `.CALCULAR_DIRECCION_ACERCAMIENTO` | Punto donde arranca la comparacion BC (posicion item) contra HL (punto de referencia) para obtener la direccion hacia el objetivo. |
| `H5278_52B3` | `.COMPROBAR_FILA` | Rama: la columna no coincidia, prueba si coincide la fila (eje vertical vs horizontal). |
| `H5278_52C5` | `.COMPROBAR_ALINEAMIENTO_LOSETA` | Punto de fusion de TODAS las ramas de la fase 1 (con o sin direccion calculada); primera instruccion aqui comprueba si el item esta alineado a loseta. |
| `H5278_5303` | `.ELEGIR_ENTRE_LIBRES` | No se puede ir hacia el objetivo (o toca reroll aleatorio): prepara el indice para elegir entre TODAS las direcciones libres. |
| `H5278_531E` | `.ELEGIR_DIRECCION_ALEATORIA` | Elige una nueva direccion al azar entre las libres, via `TABLA_CLASE_ALINEAMIENTO` + `ITEM_DIR_CHOICE_TABLE`. |
| `H5278_532D` | `.CONTINUAR_INDICE_DIRECCION_PREVIA` | Fusion tras clasificar la direccion previa (`SUB $01` con clamp a 0) en el indice de `ITEM_DIR_CHOICE_TABLE`. |
| `H5278_5340` | `.FIJAR_DIRECCION_Y_PASO` | Fusion COMPARTIDA por casi todas las ramas anteriores: guarda la direccion final elegida en `IX+3` y calcula el tamano de paso (normal/mitad). |
| `H5278_5360` | `.CONTINUAR_TRAS_ELEGIR_PASO` | Fusion tras decidir paso normal (`$0100`) o mitad (`$0080`) segun `IX+2`. |
| `H5278_5369` | `.CONTINUAR_TRAS_MODO_INVERTIDO` | Fusion tras comprobar si `MODO_ESPECIAL_FLAG` fuerza tambien medio paso. |
| `H5278_5373` | `.COMPROBAR_CODIGO_IZQUIERDA` | Tras aplicar (o no) el codigo 1 (derecha, X+=paso), comprueba el codigo 2 (izquierda). |
| `H5278_537D` | `.COMPROBAR_CODIGO_ABAJO` | Guarda la subposicion/posicion X final, cambia HL a la subposicion Y, comprueba el codigo 3 (abajo). |
| `H5278_5392` | `.COMPROBAR_CODIGO_ARRIBA` | Tras aplicar (o no) el codigo 3, comprueba el codigo 4 (arriba). |
| `H5278_539C` | `.GUARDAR_POSICION_Y` | Guarda la subposicion/posicion Y final; cae sin salto en `HELPER_53A2`. |

**Nota de verificacion**: apartado de analisis puro, sin cambios en
ningun `.asm` -- no aplica recompilar ni diff.



### Aplicado el estudio: renombradas las 14 etiquetas `H5278_` de `MOVER_ITEM_MOVIL`

El usuario confirmo ("ok, actualiza") aplicar la propuesta del
estudio anterior. Renombradas las 14 etiquetas `H5278_xxxx` de
`madmix_scr_body.asm:1935-2130` a locales (`.nombre`, ambito
`MOVER_ITEM_MOVIL`) exactamente segun la tabla del estudio. Incluye
tambien la referencia cruzada en el comentario de `ITEM_DIR_CHOICE_TABLE`
(`H5278_531E-H5278_533A`, donde `H5278_533A` nunca fue una etiqueta
real, solo una direccion de cierre en prosa) -> `MOVER_ITEM_MOVIL.ELEGIR_DIRECCION_ALEATORIA`
(sintaxis de sjasmplus para referenciar una etiqueta local desde
fuera de su rutina, en un comentario).

De paso, aplicados tambien los 2 hallazgos colaterales del estudio
(pequeños, de bajo riesgo, ya completamente diagnosticados):

- `CALL $53A2` (en `ITT_57A8`, dentro de `ACTUALIZAR_DESTELLO_ITEMS`) -> `CALL HELPER_53A2`,
  mismo patron sistemico de hex sin sustituir por la etiqueta ya
  existente.
- Corregido el comentario invertido junto al `BIT 7,A` de
  `.ELEGIR_ENTRE_LIBRES`/`.ELEGIR_DIRECCION_ALEATORIA`: decia "solo se
  elige al azar si el bit alto esta puesto, si no mantiene la
  direccion actual"; la logica real del `JR NZ` que sigue es la
  contraria -- bit7 puesto MANTIENE la direccion actual (salta a
  `.FIJAR_DIRECCION_Y_PASO` con `A=(IX+3)`), bit7 a cero es lo que
  hace caer en la eleccion aleatoria. Cambio de comentario, cero
  cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: **689 etiquetas** (baja de 703 a
689, -14, exactamente las 14 etiquetas locales nuevas -- mismo
mecanismo de conteo ya documentado, cero perdida real). Efecto
colateral esperado en el desglose del inventario: `funcion` sube de
100 a 101 y `sinref` baja en 1 -- `HELPER_53A2` pasa de parecer "sin
referencias" a tener una llamada real detectable, gracias al fix de
`CALL $53A2` -> `CALL HELPER_53A2`. Sin cambios necesarios en
`recursos/mapa_memoria.html` (su unica mencion de esta zona ya usaba
los nombres globales `MOVER_ITEM_MOVIL`/`HELPER_53A2`/`HELPER_5414`,
sin citar ninguna de las sub-etiquetas renombradas) ni en
`src/README.md`/`src/FLUJO_PROGRAMA.md` (mismo caso).



### Bug corregido en `tools/gen_inventory.py`: `DJNZ` no contaba como referencia

El usuario reporto que `recursos/flujo_programa.html` marcaba como
"sin referencia" etiquetas que si tenian llamadas reales en el
codigo (ejemplo detectado: `HNDLR_PISTA_COCONAVE_LOOP`, referenciada
solo por `DJNZ HNDLR_PISTA_COCONAVE_LOOP` en la linea 1227 de
`madmix_scr_body.asm`, nunca por `JP`/`JR`/`CALL`).

Causa raiz: `JUMP_RE` en `gen_inventory.py` solo buscaba
`\b(?:JP|JR)\b ETIQUETA` -- **`DJNZ` no estaba en la lista**, pese a
ser una instruccion de salto condicional (relativo, decrementa B)
tan valida como `JR` para marcar una etiqueta como "interna". Como
`DJNZ` es el idioma estandar para el final de casi todos los bucles
del proyecto, esto afectaba a un numero grande de etiquetas
genuinamente usadas. Corregido añadiendo `DJNZ` a la alternativa de
`JUMP_RE`.

Aprovechada la revision para documentar en el propio script (docstring)
2 limitaciones conocidas que NO se han corregido en esta pasada (heuristica
basada en texto, no en flujo real):

- No detecta referencias via tabla de datos (`DW ETIQUETA` usado como
  jump table, p.ej. `TABLA_MANEJADORES_LOSETA`) ni via registro
  (`LD IY,ETIQUETA` + `JP (IY)`, el patron que usan
  `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA` de `MOTOR_ACTORES`) --
  estas etiquetas pueden seguir saliendo como "sin referencia" pese a
  tener uso real.
- Las etiquetas LOCALES (con punto, `.nombre`) no se registran en el
  inventario en absoluto -- `LABEL_RE` no reconoce el punto inicial,
  asi que quedan fuera por completo (no aparecen ni como "sin
  referencia" ni de ninguna otra forma). Esto ya se sabia de forma
  indirecta (explica la bajada de "total etiquetas" en cada ronda que
  crea etiquetas locales nuevas), pero no estaba documentado como
  limitacion explicita del script hasta ahora.

**Verificado**: cambio solo en la herramienta Python, ningun `.asm`
tocado -- diffs de `MADMIX.SCR`/`MADMIX1.BIN` sin verificar de nuevo
(no aplica, no se recompilo nada). `recursos/flujo_programa.html`
regenerado: mismo total (689 etiquetas), pero `interna` sube de 180 a
212 (+32) y `sinref` baja de 172 a 140 (-32) -- 32 etiquetas que
tenian uso real solo via `DJNZ` quedan correctamente reclasificadas.



### Segundo bug corregido en `gen_inventory.py`: usos indirectos (tabla de saltos `DW`, `LD IY/IX/HL,ETIQUETA`+salto por registro) tampoco contaban

El usuario siguio viendo funciones con llamada real marcadas "sin
referencia" (ejemplo señalado: `DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`,
que solo se referencia con `LD IY, DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`
seguido de `JP (IY)` mas adelante en `MOTOR_ACTORES` -- exactamente la
limitacion ya anotada en el docstring del script tras el fix anterior
de `DJNZ`, pero sin corregir todavia).

Causa raiz mas amplia: `CALL_RE`/`JUMP_RE` solo detectan referencias
que son LITERALMENTE el operando de `CALL`/`JP`/`JR`/`DJNZ`. Cualquier
otra forma de "usar" una etiqueta (guardarla en un registro para saltar
despues via `JP (IY)`/`(IX)`/`(HL)`, o como entrada `DW ETIQUETA` de
una tabla de saltos como `TABLA_MANEJADORES_LOSETA`) no se detectaba
en absoluto.

Arreglado con un enfoque mas general: nueva funcion `collect_mentions`
que recoge TODOS los identificadores que aparecen como operando en
cualquier linea de codigo (fuera de comentarios, excluyendo el propio
`NOMBRE:` de cada definicion de etiqueta). Nueva regla de clasificacion,
ultimo recurso antes de `sinref`: si el nombre aparece mencionado en
cualquier otro sitio del codigo -> `interna` (uso indirecto detectado,
aunque no sea un `JP`/`CALL` literal).

**Verificado**: cambio solo en la herramienta Python, ningun `.asm`
tocado -- diff de `MADMIX.SCR` re-confirmado sin cambios (7, no se
recompilo nada). `recursos/flujo_programa.html` regenerado: mismo
total (689), `interna` sube de 212 a 315 (+103), `sinref` baja de 140
a 37 (-103). Revisadas a mano las 37 etiquetas que quedan como
`sinref`: encajan con casos ya documentados de "sin llamador conocido"
(los 11 slots sin uso de `JT_*`, `SLOT_RESTART_DD82`,
`COMPONER_ACTORES_EN_BUFFER` -- ver el estudio de `MOTOR_ACTORES` mas
arriba), puntos de entrada de ISR/reset alcanzados por vector de
hardware (no por texto), marcadores de fin de fichero (`END_OF_FILE_SCR`)
y unos pocos candidatos genuinos a revisar en una futura sesion
(`TB_ROW`, `MAINLOOP_TABLES`, `TAIL_BITDISPATCH_END`,
`ENASLT_HELPER_*`/`TAPE_MOTOR_HELPER_*`/`PAGE_CONFIG_E291_*` en los
cargadores de cinta). Nota de limitacion actualizada en el docstring
del script (heuristica de texto: un nombre que coincida por casualidad
con codigo no relacionado se marcaria "interna" sin serlo -- no se ha
visto ningun caso real todavia).



### SCROLL_ADDR_CALC -> DIBUJAR_FILA_LOSETAS_BUFFER_VRAM

Renombrada `SCROLL_ADDR_CALC` a `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`:
tras explicarla, no calcula ningun "scroll" -- redibuja UNA FILA
completa (12 losetas) del laberinto en el buffer de trabajo `$DE04`,
llamando dos veces por fila a `TILE_ADDR_CALC` (su "gemela", ya
identificada) para localizar el grafico real de cada loseta.
Llamada 36 veces (una por fila visible) desde
`REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` para el redibujado TOTAL de
camara (arranque, cambio de nivel, perdida de vida, ciclo de demo) --
a diferencia de `SCROLL_LOSETA_BUFFER_VRAM`, que es el redibujado
INCREMENTAL de una sola loseta al cruzarla.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 689 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/flujo_programa.html` (tabla de
`JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`) y
`recursos/mapa_memoria.html` (2 menciones, segmentos 0x8C34 y 0xDE04)
actualizados.


### TILE_ADDR_CALC -> MAPEAR_LOSETA_A_GRAFICO

Renombrada `TILE_ADDR_CALC` a `MAPEAR_LOSETA_A_GRAFICO`, en paralelo
con su gemela ya identificada `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
(mismo verbo, misma estructura "X_A_Y"). Dada una posicion de loseta
(fila/columna empaquetada), busca su tipo en el buffer del nivel
cargado (`$FC50`) y devuelve en `HL` la direccion real de su grafico
en `TILE_GFX` ($B940), guardandola tambien en `($8433)`. Llamada
desde `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` (2 veces por fila) y desde
`SCROLL_LOSETA_BUFFER_VRAM`/`GESTIONAR_SCROLL` (redibujado incremental
de una sola loseta).

**Pendiente, sin renombrar ni resolver todavia**: el tramo final de la
rutina (lineas ~1683-1709, etiqueta interna `TAC_TAIL`) consulta una
segunda tabla en `$8EC7` (misma zona que `TILE_TYPES`+3, usada por
`CONSULTAR_TIPO_LOSETA`) y, si el bit7 original del tipo de loseta
("comida") estaba puesto, hace un `XOR (HL)` que invierte un bit de
esa entrada -- candidato a "conmutar variante grafica/color de una
loseta ya comida", sin confirmar en vivo ni cruzar con nada mas
todavia. Sin comentario propio en el codigo -- pendiente de una
sesion futura.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 689 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/mapa_memoria.html` actualizado (1
mencion, segmento 0x89AD-0x8C34, `GESTIONAR_SCROLL`).



### SAC_LOOP -> .BUCLE_LOSETAS_FILA (etiqueta local)

Renombrada `SAC_LOOP` a `.BUCLE_LOSETAS_FILA`, como etiqueta LOCAL
(ambito `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`, su unico uso). Es el
bucle de 12 pasadas que copia el grafico de cada loseta de la fila al
buffer, llamando dos veces a `MAPEAR_LOSETA_A_GRAFICO` (al principio
y a mitad del bucle, para avanzar a la loseta siguiente).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 688 etiquetas (baja 1, mismo
mecanismo de siempre para etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos.



### Comentarios + decimal en los 3 `LD` de cabecera de DIBUJAR_FILA_LOSETAS_BUFFER_VRAM

A peticion del usuario, revisados los 3 valores `LD B,$20`/`LD C,$FF`/
`LD A,$0C` de la cabecera de `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`
(justo antes de `.BUCLE_LOSETAS_FILA`) contra el criterio ya acordado
de hex/decimal. Solo `LD A,$0C` -> `LD A,12` encaja como decimal (es
el contador puro del bucle, 12 losetas por fila). `LD B,$20` (paso de
32 bytes entre franjas de la tabla de patrones VRAM) y `LD C,$FF`
(byte bajo de `BC`, solo relevante para el decremento automatico de
`LDI`, sin uso propio comprobado en el bucle) se dejan en hex --
mismo criterio de "direccion/paso empaquetado" y "valor sin
confirmar" ya aplicado en rondas anteriores. Añadido un comentario a
cada una de las 3 lineas explicando su papel.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### SCROLL_LR_PARAM: confirmado que el valor de retorno (DE) no lo consume ningun llamador

A raiz de una pregunta del usuario sobre `SCROLL_LR_PARAM` ($2C25,
`madmix_scr_body.asm:345`), investigados los 3 sitios donde se llama
a `GESTIONAR_SCROLL` (unico punto de entrada real a las rutinas que
escriben esta variable) para ver si alguno usa de verdad el `DE` de
retorno.

Los 3 (`madmix_scr_body.asm:665`, `:1209`, `:1439`) siguen el MISMO
patron: `PUSH DE` justo antes de `CALL GESTIONAR_SCROLL` y `POP DE`
un poco despues (tras los `CALL`s a `HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/
`HNDLR_REGPUNANTOSO`/`ACTUALIZAR_DESTELLO_ITEMS`), restaurando el `DE`
que tenian ANTES de la llamada -- descartan sistematicamente el `DE`
que devuelve `GESTIONAR_SCROLL`.

Pieza que cierra el caso: `GESTIONAR_SCROLL` no llama a
`SCROLL_UP`/`SCROLL_DOWN`/`SCROLL_LR` con `CALL` sino con `JP`
(tail-call) -- asi que el `RET` final de
`DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`/`SCROLL_LOSETA_BUFFER_VRAM` (que
carga `DE,(SCROLL_LR_PARAM)` justo antes de retornar) devuelve
DIRECTO a esos 3 sitios, sin ningun consumidor intermedio dentro de
`GESTIONAR_SCROLL`.

**Conclusion**: en el codigo ya transcrito y verificado byte a byte,
el valor que `SCROLL_LR_PARAM` deja en `DE` al retornar **no lo usa
nadie** -- confirmado en los 3 unicos llamadores reales de
`GESTIONAR_SCROLL`. Sigue sin resolverse el motivo de que cada
direccion de scroll escriba un valor distinto en la variable
(`SCROLL_LR`: `$0400`/`$FC00` segun la rama; `SCROLL_DOWN`: `$0004`;
`SCROLL_UP`: `$00FC`) si nadie lo lee despues -- candidato a "salida
muerta" (posible resto de una convencion de llamada mas antigua, o
pensada para un consumidor que nunca se conecto/ya no existe en esta
version), pero no se ha renombrado la variable ni cambiado nada en el
codigo: sigue sin confirmar el proposito ORIGINAL del valor en si,
solo que carece de consumidor real hoy.

**Nota de verificacion**: apartado de analisis puro, sin cambios en
ningun `.asm` -- no aplica recompilar ni diff.



### Etiquetas internas de IR_JOYREAD renombradas a español

A peticion del usuario, tras explicar `IR_JOYREAD` (lectura de
joystick por el puerto del PSG dentro de `LEER_ENTRADA`, que
reordena los bits para que el resultado use el mismo formato que la
lectura de teclado), renombradas sus 5 etiquetas internas
`IRJ_B1..B5` (locales, unico uso dentro de la rutina) segun la dirección/boton
que cada una deja atras al pasar a la siguiente prueba -- el usuario
confirmo que el "boton" (bit4, antes `IRJ_B5`) es el disparo:

- `IRJ_B1` -> `.COMPROBAR_ABAJO`
- `IRJ_B2` -> `.COMPROBAR_IZQUIERDA`
- `IRJ_B3` -> `.COMPROBAR_DERECHA`
- `IRJ_B4` -> `.COMPROBAR_DISPARO`
- `IRJ_B5` -> `.CONTINUAR_TRAS_DISPARO`

De paso, comentario `; bitN = direccion` añadido a cada uno de los 5
`RRA` que prueban el bit correspondiente (arriba/abajo/izquierda/
derecha/disparo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 683 etiquetas (baja de 688 a 683,
-5, exactamente las 5 etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos (README.md menciona
`IR_JOYREAD` por su nombre global, sin cambios; las sub-etiquetas
nunca se citaron fuera del propio `.asm`).



### IR_JOYREAD -> LEER_JOYSTICK

Renombrada `IR_JOYREAD` a `LEER_JOYSTICK`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 683 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/mapa_memoria.html` (segmento
0xDD8A-0xDD93, `PSG_WRITE_READ_DD8A`) y `src/README.md` actualizados.



### PSG_WRITE_READ_DD8A -> CONFIGURAR_Y_LEER_JOYSTICK_PSG

Renombrada `PSG_WRITE_READ_DD8A` a `CONFIGURAR_Y_LEER_JOYSTICK_PSG`:
escribe en el registro PSG ya seleccionado (termina de poner el
mezclador en modo entrada, valor preparado por `LEER_JOYSTICK`),
selecciona el registro 14 (Puerto de E/S A) y lee el estado del
joystick 1. Añadido tambien un comentario en la linea de la unica
llamada real (`LEER_JOYSTICK`) explicando las dos mitades de la
rutina.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 683 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/mapa_memoria.html` (segmento
0xDD8A-0xDD93) y `src/README.md` actualizados.



### IR_JOYLOOP -> COMPROBAR_PAUSA (hallazgo: identificada la 6a accion redefinible)

Renombrada `IR_JOYLOOP` a `COMPROBAR_PAUSA`. Pese al nombre "LOOP"
que traia, no es un bucle -- es una UNICA prueba de puerto adicional
(la 6a pareja de `IR_PORT_TABLE`), compartida por los dos caminos de
`LEER_ENTRADA`: se alcanza cayendo sin salto desde el final de
`IR_KBTEST` (escaneo de teclado, 5 pruebas) o saltando directo desde
`LEER_JOYSTICK` (tras leer el joystick). Tambien hace de epilogo
compartido: funde (`OR`) el bit resultante con el acumulador en
`$8EC4` y retorna.

**Hallazgo, a partir de una pista del usuario**: las 6 acciones
redefinibles del menu del juego son "PAUSA/FUEGO/ARRIBA/ABAJO/
IZQUIERDA/DERECHA" -- exactamente 6, el mismo numero que las 6
parejas de `IR_PORT_TABLE` (5 para `IR_KBTEST` + 1 para esta prueba
extra). Como las 4 direcciones + disparo ya estaban confirmadas en
las 5 pruebas normales (`IR_KBTEST` y los 5 `RRA` de `LEER_JOYSTICK`),
la 6a prueba compartida SOLO puede ser PAUSA -- consistente con que
se lea siempre por teclado, incluso en modo joystick (pausa no suele
mapearse a un boton del stick). Comentarios actualizados en la
cabecera de `LEER_ENTRADA`, en la propia etiqueta y en el bloque de
datos de `IR_PORT_TABLE` reflejando el hallazgo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 683 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### $8EC6 -> FLAG_ENTRADA_BLOQUEADA (nueva etiqueta)

A peticion del usuario, puesta etiqueta propia a `$8EC6` (byte
"libre" dentro de `TILE_TYPES`, offset 2, siempre `$00` en la ROM):
`FLAG_ENTRADA_BLOQUEADA`. Es el flag que hace que `LEER_ENTRADA`
retorne sin leer nada (bit0 puesto -> `RET NZ` inmediato) mientras
dura la animacion de busqueda de columna del HUD al cargar un nivel
(`PREPARAR_INICIO_NIVEL` lo activa antes de `BUSCAR_COLUMNA_HUD`,
`MOSTRAR_READY_Y_ARRANCAR_NIVEL` lo desactiva al terminar).

Como no tenia entidad propia -- es un byte en mitad de la primera
fila de 16 `DB $00` de `TILE_TYPES` -- se partio esa fila en dos
`DB` (2 bytes + etiqueta + 14 bytes) para poder ponerle la etiqueta
sin tocar ningun byte de salida. Sustituidos los 3 usos reales
(`LD HL,$8EC6`/`LD ($8EC6),A` x2) y actualizados los 2 comentarios de
cabecera que lo mencionaban.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 684 etiquetas (+1, etiqueta nueva
real -- categoria "dato"). `recursos/flujo_programa.html` (2
menciones) y `src/FLUJO_PROGRAMA.md` (3 menciones) actualizados.



### $8EC4 -> ACUMULADOR_ENTRADA (nueva etiqueta) + tercer bug en gen_inventory.py

A peticion del usuario, misma operacion que con `$8EC6`: puesta
etiqueta propia a `$8EC4` -- que coincide exactamente con el inicio
de `TILE_TYPES` -- como `ACUMULADOR_ENTRADA`. Es el byte que
`LEER_ENTRADA` limpia (si `A=0`) o deja intacto (si `A!=0`) antes de
leer, y donde los 3 caminos de salida (`IR_KBTEST`/`COMPROBAR_PAUSA`/
`LEER_JOYSTICK`) funden con `OR` el resultado antes de retornar --
el "acumulador" que otros sitios del codigo comprueban despues con
`AND $3F`/`AND $06`. Al coincidir con la direccion de `TILE_TYPES`,
no hizo falta partir ningun `DB` -- se añadio como segunda etiqueta
apilada justo encima (`TILE_TYPES:` / `ACUMULADOR_ENTRADA:`, mismo
byte). Sustituidos los 3 usos reales y actualizados los 2 comentarios
de cabecera que mencionaban `$8EC4` en el contexto de `LEER_ENTRADA`
(dejados intactos los 2 mencionados en el contexto, distinto, de
`CONSULTAR_TIPO_LOSETA`/`TILE_TYPES` como tabla de tipos de loseta).

**Efecto secundario encontrado y corregido**: apilar `ACUMULADOR_ENTRADA:`
justo debajo de `TILE_TYPES:` hizo que `gen_inventory.py` reclasificara
`TILE_TYPES` de "dato" a "sin referencia" -- el buscador de "que sigue
a la etiqueta" no sabia saltar por encima de OTRA etiqueta apilada
(con o sin comentario propio) para llegar al `DB` real. Mismo tipo de
bug que los 2 ya corregidos antes en esta herramienta (`DJNZ` sin
detectar, usos indirectos sin detectar). Arreglado el bucle de
busqueda para que las lineas que son solo otra etiqueta (con o sin
comentario) sean transparentes y la busqueda continue hasta la
sentencia real.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 685 etiquetas (+1, etiqueta nueva
real -- categoria "dato"). El fix de `gen_inventory.py` corrigio
ademas 3 casos preexistentes similares en el resto del proyecto (no
solo `TILE_TYPES`): `dato` sube de 237 a 241 (+4 total), `sinref` baja
de 38 a 34 (-4). Sin menciones que sincronizar en los HTML/`.md`
activos (las 2 menciones de `$8EC4` en `mapa_memoria.html` son de un
contexto distinto, `CONSULTAR_TIPO_LOSETA`, sin relacion con este
renombrado).



### IR_49 -> .CONTINUAR_TRAS_LIMPIAR_ACUMULADOR (etiqueta local)

Renombrada `IR_49` a `.CONTINUAR_TRAS_LIMPIAR_ACUMULADOR`, local a
`LEER_ENTRADA` (unico uso). Es el punto de fusion de las 2 ramas del
parametro `A`: si `A=0` limpia `ACUMULADOR_ENTRADA` antes de caer
aqui; si `A!=0` salta aqui directo sin limpiar. Desde aqui el codigo
es identico para ambos casos (despacha a `IR_KBLOOP`/`LEER_JOYSTICK`
segun `$8427`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 684 etiquetas (baja 1, mismo
mecanismo de siempre para etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos.



### LEER_TECLADO -> COMPROBAR_PULSACION

Renombrada `LEER_TECLADO` ($5D0A) a `COMPROBAR_PULSACION`: no lee ni
decodifica ninguna tecla concreta, hace un unico barrido de las 9
filas de la matriz y devuelve con el flag Z si encontro alguna tecla
pulsada (`Z`=ninguna, `NZ`=si) -- una consulta puntual, no una espera
(el bucle de espera lo hacen sus llamadores, `TAIL_KEYWAIT_RELEASE`/
`TAIL_KEYWAIT_UP`, llamandola repetidamente). Se libera asi el nombre
`LEER_TECLADO` para `IR_KBLOOP` (renombrado en la siguiente ronda),
evitando la colision que habria si `IR_KBLOOP` tambien se llamara
`LEER_TECLADO`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 684 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### IR_KBLOOP -> LEER_TECLADO_DIRECCIONES

Renombrada `IR_KBLOOP` a `LEER_TECLADO_DIRECCIONES`, ahora que
`LEER_TECLADO` quedo libre (ronda anterior). Es la mitad "teclado" de
`LEER_ENTRADA`, homologa de `LEER_JOYSTICK`: escanea las 5 primeras
parejas fila/mascara de `IR_PORT_TABLE` (arriba/abajo/izquierda/
derecha/disparo) via `IR_PORTTEST`, construyendo en `E` el mismo
formato de bits que `LEER_JOYSTICK`, y cae sin salto en
`COMPROBAR_PAUSA` para la 6a prueba compartida.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 684 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### $8427 -> MODO_ENTRADA (nueva etiqueta) + valores concretos que confirman la polaridad invertida

A peticion del usuario, puesta etiqueta propia a `$8427` (dentro del
hueco de relleno `$8427-$8430`, siempre `$00` en la ROM): `MODO_ENTRADA`.
Es el selector de teclado/joystick que lee `LEER_ENTRADA` para
despachar a `LEER_TECLADO_DIRECCIONES` (0) o `LEER_JOYSTICK` (!=0).
No hizo falta partir nada -- la etiqueta se puso justo antes del
`DS $8430-$,$00` que ya reservaba el hueco completo.

De paso, al localizar los 3 sitios reales que lo escriben
(`madmix_scr_body.asm`, menu principal), se pudieron poner NUMEROS
concretos a la sospecha de polaridad invertida que ya arrastraba el
comentario de cabecera de `LEER_ENTRADA` desde hace varias rondas:
`TI_5C60` (opcion de menu "1 TECLADO") escribe `MODO_ENTRADA=1`,
`TI_5C70` ("2 JOYSTICK") escribe `MODO_ENTRADA=0` -- EXACTAMENTE al
reves de como lo interpreta el despachador de `LEER_ENTRADA` (1 ->
joystick, 0 -> teclado). Comentario ampliado con esta confirmacion;
sigue sin resolverse si es un bug real del original o si hay otro
sitio sin localizar que vuelve a tocar la variable entre la seleccion
del menu y la partida.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 685 etiquetas (+1, etiqueta nueva
real -- clasificada "interna" por el inventario, no "dato": al ser un
`DS` de relleno en vez de un `DB` con valor propio, el heuristico de
`gen_inventory.py` la cuenta por sus referencias en vez de por dato
adyacente -- clasificacion razonable, no un bug). `src/FLUJO_PROGRAMA.md`
(tabla de opciones del menu) actualizado.



### LEER_TECLADO_DIRECCIONES -> LEER_TECLADO

Renombrada `LEER_TECLADO_DIRECCIONES` a `LEER_TECLADO`, ahora que ese
nombre volvio a quedar libre tras renombrar la rutina que lo ocupaba
antes a `COMPROBAR_PULSACION` (ronda anterior). Sin cambios de
comportamiento, solo el nombre final que faltaba en esta cadena de
renombrados de `LEER_ENTRADA` y su familia.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 685 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### Desglosados los 6 pares de IR_PORT_TABLE con comentario por tramo

A peticion del usuario, la unica linea `DB` de 12 bytes de
`IR_PORT_TABLE` se desglosa en 6 lineas de 2 bytes (una pareja
fila/mascara cada una), con comentario indicando a que accion
corresponde: arriba, abajo, izquierda, derecha, disparo y pausa (esta
ultima, la usada por `COMPROBAR_PAUSA`). Cambio de formato puro,
mismos bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### IR_PORT_TABLE -> TABLA_TECLAS_MSX

Renombrada `IR_PORT_TABLE` a `TABLA_TECLAS_MSX`: las 6 parejas
fila/mascara de la matriz de teclado estandar del MSX usadas por
`LEER_TECLADO`/`COMPROBAR_PAUSA` para las 6 acciones de control
configurables.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 685 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### IR_KBTEST/IR_65/IR_68 renombradas + hallazgo: ESCANEAR_FILAS_TECLADO es una rutina compartida entre ficheros

Al renombrar las 3 etiquetas confirmadas con el usuario, se detecto
que `IR_KBTEST` **no era puramente local** a `LEER_TECLADO` como se
penso al principio: `madmix_scr_body.asm:3696` (dentro de lo que
tenia nombre `TAIL_FONT_ROUTINE`) la llama directamente con `CALL`,
con su propia tabla (`TAIL_UNK_5C93`, 6 parejas, todas fila `$F0`) y
`B=6` en vez de `B=5`. Renombrar a etiqueta local habria roto la
compilacion (y de hecho la rompio en un primer intento, corregido
antes de continuar) -- se convirtio en global: `IR_KBTEST` ->
`ESCANEAR_FILAS_TECLADO`. `IR_65`/`IR_68` (las 2 ramas internas de su
bucle, sin llamador externo) si son puramente locales:
`IR_65` -> `.TECLA_NO_PULSADA`, `IR_68` -> `.CONTINUAR_BUCLE_TECLAS`.

**Hallazgo colateral**: `TAIL_FONT_ROUTINE` no tiene nada que ver con
fuentes/patrones (nombre historico de una hipotesis descartada) --
al llamar a `ESCANEAR_FILAS_TECLADO` con su tabla de 6 teclas (todas
en la fila `$F0`) y devolver el bitmask en `E`, comprobado bit a bit
por su llamador (`TI_5B62`/`TI_5B65`, el bucle del menu principal)
justo despues, es en realidad el **lector de teclas del menu
principal** (equivalente de `LEER_TECLADO`/`LEER_JOYSTICK` pero para
la navegacion de menus). Comentario de cabecera corregido, marcada
como candidata a renombrar (p.ej. `LEER_TECLAS_MENU_PRINCIPAL`) en
una futura ronda -- no renombrada todavia, fuera del alcance de esta
peticion concreta.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- tras
corregir un primer intento que introducia un `JR` extra no presente
en el original (tentacion de "caer sin salto" convertida por error en
salto explicito al mover el comentario; detectado y corregido antes
de dar la ronda por buena). `.dsk`/`.cas`/inventario HTML
regenerados: 683 etiquetas (baja de 685 a 683, -2, las 2 etiquetas
locales nuevas -- cero perdida real). Sin menciones que sincronizar
en los HTML/`.md` activos (`FLUJO_PROGRAMA.md` ya describia
`TAIL_FONT_ROUTINE` correctamente como "lee una tecla", sin mencionar
fuentes).



### IR_PORTTEST -> COMPROBAR_TECLA_MSX

Renombrada `IR_PORTTEST` a `COMPROBAR_TECLA_MSX`: el helper de mas
bajo nivel de toda la familia de lectura de teclado -- selecciona la
fila de la matriz (`IX+0`, puerto `$AA`), lee las columnas (puerto
`$A9`) y aisla con `AND (IX+1)` el bit de una tecla concreta. Llamado
por `ESCANEAR_FILAS_TECLADO` (una vez por pareja de la tabla) y por
`COMPROBAR_PAUSA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 683 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### IR_79 -> .FINALIZAR_LECTURA (etiqueta local)

Renombrada `IR_79` a `.FINALIZAR_LECTURA`, local a `COMPROBAR_PAUSA`
(unico uso). Es el punto de fusion tras comprobar la tecla PAUSA
(pulsada o no): funde `E` con `ACUMULADOR_ENTRADA` (`OR (HL)`) y
retorna -- mismo patron que `.CONTINUAR_BUCLE_TECLAS` en
`ESCANEAR_FILAS_TECLADO`, pero para esta unica comprobacion.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 682 etiquetas (baja 1, mismo
mecanismo de siempre para etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos.



### Separado el byte propio de FLAG_ENTRADA_BLOQUEADA del resto de la fila de TILE_TYPES

A peticion del usuario, el `DB` de 14 bytes que empezaba en
`FLAG_ENTRADA_BLOQUEADA` se separa en su propio byte (`DB $00`) mas
los 13 bytes de relleno restantes en su propia linea -- mismo
tratamiento ya aplicado a `ACUMULADOR_ENTRADA`. Cambio de formato
puro, mismos bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### TILE_TYPES desplazada de $8EC4 a $8EC7 (direccion real de la tabla)

A raiz de encontrar quien usa el byte contiguo a `FLAG_ENTRADA_BLOQUEADA`
($8EC7), el usuario pidio mover la etiqueta `TILE_TYPES` a esa
direccion. Confirmado que es correcto: el UNICO consumidor real de la
tabla de tipos de loseta, `CONSULTAR_TIPO_LOSETA`, usa
`HL=$8EC7+A / AND $1F` como base -- los 3 bytes anteriores
($8EC4-$8EC6) no son parte de la tabla, son la zona reutilizada por
`LEER_ENTRADA` (`ACUMULADOR_ENTRADA`/`FLAG_ENTRADA_BLOQUEADA`).

`TILE_TYPES` se mueve a `$8EC7` (sin quitar ningun byte -- el bloque
reservado completo de 96 bytes sigue emitiendose igual, termina
EXACTO en `INICIO`/`$8F24` como ya estaba verificado). De paso,
sustituidos los 2 usos reales que seguian en hex (`LD HL,$8EC7` en
`MAPEAR_LOSETA_A_GRAFICO` y en `CONSULTAR_TIPO_LOSETA`) por la
etiqueta, y actualizados todos los comentarios que describian
`TILE_TYPES` como si empezara en `$8EC4` (cabecera del bloque de
datos, cabecera de `GESTIONAR_SCROLL`, cabecera del bloque
`CONSULTAR_TIPO_LOSETA`/`LEER_ENTRADA`, cabecera de `LEER_ENTRADA`
en si).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 682 etiquetas (sin cambio de
total, la etiqueta ya existia, solo cambia su direccion).
`recursos/mapa_memoria.html` (2 menciones, segmentos 0x8E3C-0x8EC4 y
0x8EC4-0x8F24) y `src/FLUJO_PROGRAMA.md` (1 mencion) actualizados.



### TILE_TYPES -> TABLA_TIPOS_LOSETA

Renombrada `TILE_TYPES` a `TABLA_TIPOS_LOSETA`: la tabla de tipos de
loseta/colision (indexada por el mismo numero que el grafico),
consultada por `CONSULTAR_TIPO_LOSETA` y escrita por
`MAPEAR_LOSETA_A_GRAFICO`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 682 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/mapa_memoria.html` (2 menciones) y
`src/FLUJO_PROGRAMA.md` (1 mencion) actualizados.



### Formato: hex -> decimal en TABLA_TIPOS_LOSETA

A raiz de confirmar que los bytes de `TABLA_TIPOS_LOSETA` coinciden
exacto, uno a uno, con el catalogo tipo<->loseta ya confirmado en
rondas anteriores (offsets 45-92 cruzados contra `data/tiles/*.til` y
`HNDLR_TRAMPILLA_*`/`HNDLR_PISTA_COCONAVE`/etc., encaje perfecto sin
ninguna discrepancia), convertidos sus 93 bytes de hex a decimal:
mismo criterio ya aplicado a `TABLA_CLASE_ALINEAMIENTO` -- es un
indice/enumerado puro (0-19) usado directamente como despacho en
`TABLA_MANEJADORES_LOSETA`, no un bitmask ni una direccion. Cambio de
formato puro, mismos bytes (`$01`->`1` ... `$13`->`19`, y los `$00`
que ya eran iguales en ambos formatos).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Separado el byte de relleno de ACUMULADOR_ENTRADA

A raiz de una pregunta del usuario, confirmado que el segundo byte
del `DB $00,$00` de `ACUMULADOR_ENTRADA` ($8EC5) no tiene ninguna
referencia real en el codigo (buscado en todo el proyecto, cero
resultados) -- es puro relleno del bloque reservado, a diferencia del
primer byte ($8EC4) que si es el acumulador real de `LEER_ENTRADA`.
Separado en su propia linea con comentario explicito, mismo
tratamiento que `FLAG_ENTRADA_BLOQUEADA`. Cambio de formato puro,
mismos bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Formato: hex -> decimal en FLAG_ENTRADA_BLOQUEADA (ACUMULADOR_ENTRADA se deja en hex)

A raiz de una pregunta del usuario sobre si `ACUMULADOR_ENTRADA`/
`FLAG_ENTRADA_BLOQUEADA` deberian ir en decimal: `FLAG_ENTRADA_BLOQUEADA`
si (`$00`->`0`) -- es un booleano puro (`BIT 0,(HL)`), mismo caso ya
aplicado a `FLAG_NIVEL_RECIEN_CARGADO`/`FLAG_DIRECCION_NUEVA`.
`ACUMULADOR_ENTRADA` se deja en hex -- no es booleano ni enumerado,
es un acumulador de BITMASK (arriba/abajo/izquierda/derecha/disparo/
pausa, armado con `SET`/`RL`), misma familia que
`DIRECCION_DE_MOVIMIENTO`/`DIRECCION_SIN_PROCESAR`/`DIRECCION_FORZADA`,
ya dejadas en hex por el mismo motivo. Cambio de formato puro, mismo
byte (`$00`=`0`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### RM_C4BC/RM_C4C6/RM_C4C9 renombradas a etiquetas locales (busqueda de ranura libre en INSTALAR_RECURSO_SONIDO)

Analizado el detalle de `INSTALAR_RECURSO_SONIDO` (driver de sonido):
antes de buscar, comprueba si la ranura CONCRETA que pide el llamador
(indice en `A`) ya esta libre; si lo esta, se usa directamente sin
buscar. Si no, recorre las 3 ranuras de 46 bytes desde `$C9C9`
buscando una libre (puntero de 2 bytes a `$0000`); si encuentra una,
la usa; si las 3 estan ocupadas, cae de vuelta a la ranura
originalmente solicitada (fallback, la sobrescribe). Renombradas,
todas locales (unico uso dentro de la rutina):

- `RM_C4BC` -> `.BUSCAR_RANURA_LIBRE` (el bucle de busqueda)
- `RM_C4C6` -> `.USAR_RANURA_SOLICITADA` (la pedida por el llamador, libre de entrada o fallback si ninguna otra lo estaba)
- `RM_C4C9` -> `.USAR_RANURA_ENCONTRADA` (la que encontro el bucle de busqueda)

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 679 etiquetas (baja de 682 a 679,
-3, exactamente las 3 etiquetas locales nuevas -- cero perdida real).
Sin menciones en los HTML/`.md` activos.



### RM_C4D8 -> LIMPIAR_E_INSTALAR_RANURA

Renombrada `RM_C4D8` a `LIMPIAR_E_INSTALAR_RANURA`: cola compartida
entre `INSTALAR_RECURSO_SONIDO` (salta aqui por `JR` tras elegir
ranura) e `INSTALAR_RECURSO_SONIDO_EN_A` (cae sin salto, sin buscar
ranura). Pone a cero los 46 bytes de la ranura elegida y graba el
puntero al recurso de sonido dos veces seguidas al principio. Se deja
global (no puede ser local, la usan 2 rutinas globales distintas).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 679 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### RM_C4DC -> .BUCLE_LIMPIAR_RANURA (etiqueta local)

Renombrada `RM_C4DC` a `.BUCLE_LIMPIAR_RANURA`, local a
`LIMPIAR_E_INSTALAR_RANURA` (unico uso). Es el bucle que pone a cero
los 46 bytes de la ranura, byte a byte con `DJNZ`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 678 etiquetas (baja 1, mismo
mecanismo de siempre para etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos.



### RM_PLAYER_TICK_C4EB -> TICK_REPRODUCTOR_PSG

Renombrada `RM_PLAYER_TICK_C4EB` a `TICK_REPRODUCTOR_PSG`: punto de
entrada real del "tick" del reproductor de sonido PSG, llamado desde
`TAIL_LEVELCYCLE_HELPER` en cada VBLANK.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 678 etiquetas (sin cambio de
total, renombrado 1:1). `recursos/flujo_programa.html` (1 mencion) y
`src/FLUJO_PROGRAMA.md` (1 mencion) actualizados.



### RM_C4F9 -> PROCESAR_CANAL_PSG

Renombrada `RM_C4F9` a `PROCESAR_CANAL_PSG`: cabecera del bucle de 3
canales de `TICK_REPRODUCTOR_PSG`. Por cada ranura, comprueba si esta
"esperando" (salta a `RM_C564` si es asi); si no, lee el siguiente
byte del script (comando via `CMD_JUMP_TABLE_C99E` si `>=$80`,
duracion de nota via `RM_TABLE_C8DE` si no). Se deja global (mismo
estilo ya usado por el resto de etiquetas `RM_Cxxxx` de este driver de
sonido, todavia no convertidas a locales).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 678 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML activos;
`src/FLUJO_PROGRAMA.md` (1 mencion) actualizado.



### RM_C564..RM_C6B1 renombradas: motor de envolventes de volumen/tono del driver de sonido

A peticion del usuario ("tira del hilo" / "renombra ya"), analizado y
renombrado el tramo de `TICK_REPRODUCTOR_PSG` que aplica las
envolventes por tick. Al cruzarlo con el bloque ya existente en
`FINDINGS.md` ("RESUELTO: los 15 comandos del bytecode del driver de
sonido"), se confirmo que es exactamente el mecanismo ya descrito ahi
(tabla de offsets del registro de canal, comando 7 `SET_INSTRUMENT`
que carga los parametros de envolvente) -- se uso esa terminologia ya
establecida ("envolvente") en vez de "modulacion"/"tremolo/vibrato"
que se habia barajado en la conversacion.

Renombradas (todas las `.locales` con ambito `APLICAR_ENVOLVENTES_CANAL`):

- `RM_C564` -> `APLICAR_ENVOLVENTES_CANAL` (global, saltada desde `PROCESAR_CANAL_PSG`): decrementa el contador de tics de la nota y aplica un paso de cada envolvente.
- `RM_C579` -> `.BUCLE_ENVOLVENTE_VOLUMEN`, `RM_C586` -> `.RECARGAR_PASO_ENVOLVENTE_VOLUMEN`, `RM_C5A2` -> `.CONTINUAR_ENVOLVENTE_VOLUMEN`, `RM_C5A7` -> `.FIN_ENVOLVENTE_VOLUMEN` (envolvente de volumen, acumulador `+$2A`).
- `RM_C5B2` -> `.INICIAR_ENVOLVENTE_TONO`, `RM_C5BA` -> `.BUCLE_ENVOLVENTE_TONO`, `RM_C5C7` -> `.RECARGAR_PASO_ENVOLVENTE_TONO`, `RM_C5F1` -> `.SUMAR_PASO_ENVOLVENTE_TONO`, `RM_C604` -> `.CONTINUAR_TRAS_PASO_ENVOLVENTE_TONO`, `RM_C60D` -> `.CONTINUAR_ENVOLVENTE_TONO`, `RM_C612` -> `.FIN_ENVOLVENTE_TONO` (envolvente de tono/deslizamiento, acumulador `+$2B/+$2C`, con signo).
- `RM_C61D` -> `COMBINAR_Y_ESCRIBIR_CANAL` (global, tambien saltada directo desde `PROCESAR_CANAL_PSG` cuando el script esta vacio): suma acumuladores + valores base y escribe los registros de volumen/tono del PSG, avanza a la siguiente ranura.
- `RM_C699` -> `REINICIAR_ENVOLVENTE_VOLUMEN`, `RM_C6B1` -> `REINICIAR_ENVOLVENTE_TONO` (globales, llamadas tanto al armar una nota nueva como cuando una envolvente se agota del todo): recargan cuenta atras/pasos desde los valores de instrumento.

Añadido tambien un comentario de cabecera en `APLICAR_ENVOLVENTES_CANAL`
resumiendo el mecanismo y remitiendo a la tabla de offsets ya
documentada en `FINDINGS.md`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 667 etiquetas (baja de 678 a 667,
-11, exactamente las 11 etiquetas locales nuevas -- cero perdida
real). Sin menciones en los HTML/`.md` activos (las de `FINDINGS.md`
son historicas, se dejan sin tocar).



### RM_C518/RM_C527 renombradas + 2 hex sin sustituir corregidos (despachador de comandos del bytecode PSG)

Renombrado el bucle de despacho de comandos ya descrito en
`FINDINGS.md` ("RESUELTO: los 15 comandos..."): `RM_C518` ->
`DESPACHAR_COMANDO_PSG` (global, vuelven aqui las ~13 rutinas de
comando tras ejecutarse -- lee el siguiente byte del script; si es
`>=$80` despacha via `CMD_JUMP_TABLE_C99E`, si no cae en la resolucion
de nota); `RM_C527` -> `.RESOLVER_NOTA` (local, unico uso: suma la
nota a la transposicion del canal y la busca en `RM_TABLE_C8DE` para
obtener el periodo de tono base).

De paso, corregidos los 2 `LD HL,$Cxxx` que seguian en hex pese a que
`CMD_JUMP_TABLE_C99E`/`RM_TABLE_C8DE` ya tenian etiqueta propia --
mismo patron sistemico de siempre.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (baja 1, la unica
etiqueta local nueva -- cero perdida real). Sin menciones en los
HTML/`.md` activos.



### RM_C82E -> ACTUALIZAR_MEZCLADOR_CANAL

Renombrada `RM_C82E` a `ACTUALIZAR_MEZCLADOR_CANAL`: activa/desactiva
tono y ruido del canal actual en la sombra del registro mezclador del
PSG (`$C9C5`), ya documentada con detalle en una ronda anterior
("renderizador de audio", polaridad corregida).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### CMD_JUMP_TABLE_C99E -> TABLA_COMANDOS_PSG

Renombrada `CMD_JUMP_TABLE_C99E` a `TABLA_COMANDOS_PSG`: la tabla de
saltos de los 15 comandos del bytecode del driver de sonido, ya
completamente descifrada en una ronda anterior.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### RM_C8BC -> LEER_PALABRA_INDEXADA

Renombrada `RM_C8BC` a `LEER_PALABRA_INDEXADA`: helper generico de
consulta de tabla de palabras de 16 bits (`HL`=tabla, `A`=indice ->
`HL`=valor en `tabla+A*2`), usado tanto para la duracion/tono de nota
(`RM_TABLE_C8DE`) como para el despacho de comandos
(`TABLA_COMANDOS_PSG`). De paso corregida una mencion obsoleta al
nombre antiguo `RM_TABLE_C99E` en su propio comentario de cabecera
(ya renombrada a `TABLA_COMANDOS_PSG` en una ronda anterior).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### RM_C882 -> OBTENER_PUNTERO_TRANSPOSICION

Renombrada `RM_C882` a `OBTENER_PUNTERO_TRANSPOSICION`: calcula
`HL = TRANSPOSE_TABLE_CA67 + canal actual`. Usada por
`DESPACHAR_COMANDO_PSG.RESOLVER_NOTA` para sumar la transposicion a
la nota antes de buscar el periodo de tono, y por el comando 14
(`SET_CHANNEL_STATE`, ya documentado en `FINDINGS.md`) para fijarla.
Comentario de cabecera actualizado con ambos usos confirmados (el
segundo ya no queda como "sin confirmar", se habia resuelto en una
ronda anterior sobre los 15 comandos).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### RM_TABLE_C8DE -> TABLA_NOTAS_PSG

Renombrada `RM_TABLE_C8DE` a `TABLA_NOTAS_PSG` (ronda unica, el
usuario ajusto el nombre justo despues de `TABLA_NOTAS` a
`TABLA_NOTAS_PSG` antes de verificar, asi que se aplican ambos pasos
juntos): la tabla de 96 palabras nota+transposicion -> periodo de
tono real del PSG, ya descifrada por completo en una ronda anterior
("RESUELTO: los 15 comandos...").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 666 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### Renombradas las 26 etiquetas RM_ restantes del driver de sonido + hallazgo: tercera envolvente compartida (ruido)

A peticion del usuario ("analiza todas las funciones RM_ y su flujo"
/ "aplicalo todo"), analizado y renombrado el resto del driver de
sonido de una sola vez.

**Hallazgo principal**: el tramo `madmix1_body.asm:3617-3660` (antes
sin etiqueta propia, solo alcanzable cayendo sin salto tras el bucle
de 3 canales de `TICK_REPRODUCTOR_PSG`) es una **tercera envolvente**,
con la misma estructura exacta (cuenta atras/pasos/incremento/periodo)
que las de volumen/tono ya renombradas, pero sobre la tabla
COMPARTIDA `$CA53` en vez de por canal -- combina `($CA5E)+($CA5F)` y
escribe el resultado en `$C9C4`, la sombra del **registro 6 del PSG
(periodo de RUIDO)**. Tiene sentido que sea compartida: el AY-3-8910
solo tiene un generador de ruido para los 3 canales. Se le puso
etiqueta global nueva, `APLICAR_ENVOLVENTE_RUIDO`, con comentario de
cabecera explicando el hallazgo.

**Renombradas** (globales, cuando se llaman desde mas de un sitio o
desde fuera de su bloque inmediato):
`RM_C53A`->`ARMAR_NOTA`, `RM_C552`->`CERRAR_NOTA` (destino de `JP`
directo desde el comando HOLD/TIE), `RM_C6C9`->`REINICIAR_ENVOLVENTE_RUIDO`
(relatch de `$CA53`, homologa de `REINICIAR_ENVOLVENTE_VOLUMEN`/`_TONO`),
`RM_C88D`->`MULTIPLICAR_8X16`, `RM_C8A2`->`DIVIDIR_16X16`,
`RM_C8C9`->`VOLCAR_REGISTROS_PSG` (vuelca la sombra de registros a
hardware, paso final de cada tic).

**Renombradas a locales** (bucles/ramas internas sin uso externo, 20
en total): `.BUCLE_ENVOLVENTE_RUIDO`/`.RECARGAR_PASO_ENVOLVENTE_RUIDO`/
`.CONTINUAR_ENVOLVENTE_RUIDO`/`.FIN_ENVOLVENTE_RUIDO`/`.ESCRIBIR_RUIDO_PSG`
(en `APLICAR_ENVOLVENTE_RUIDO`); `.BUCLE_REINICIO_VOLUMEN`/
`.BUCLE_REINICIO_TONO`/`.BUCLE_REINICIO_RUIDO` (en sus respectivas
`REINICIAR_ENVOLVENTE_*`); `.BUCLE_LIMPIAR_RANURA_COMPLETA` (comando
candidato a `RESET_SHARED_ENVELOPE`), `.BUCLE_ACUMULAR_DURACION`
(comando `SET_DURATION_MULTI`), `.BUCLE_COPIAR_INSTRUMENTO` (comando
`SET_INSTRUMENT`), `.BUCLE_COPIAR_FORMA_ENVOLVENTE` (comando
`SET_ENVELOPE_SHAPE`) -- estos 4 son bucles internos de cuerpos de
comando que siguen SIN etiqueta propia (ver nota abajo);
`.BUCLE_DESPLAZAR_MASCARA`/`.APLICAR_MASCARA_MEZCLADOR` (en
`ACTUALIZAR_MEZCLADOR_CANAL`); `.BUCLE_MULTIPLICAR`/`.CONTINUAR_MULTIPLICAR`
(en `MULTIPLICAR_8X16`); `.BUCLE_DIVIDIR`/`.CONTINUAR_DIVIDIR` (en
`DIVIDIR_16X16`); `.SIN_ACARREO` (en `LEER_PALABRA_INDEXADA`, rama
que faltaba de una ronda anterior); `.BUCLE_VOLCAR_REGISTROS` (en
`VOLCAR_REGISTROS_PSG`).

**Pendiente, fuera de esta ronda**: los cuerpos de los 15 comandos del
bytecode (`SET_VOLUME`, `SET_MIXER`, etc., ya nombrados en la tabla de
`FINDINGS.md` "Los 15 comandos") siguen sin ninguna etiqueta propia --
solo se referencian por direccion cruda desde `TABLA_COMANDOS_PSG`.
Ponerselas requeriria insertar 15 etiquetas nuevas y reescribir esa
tabla de `DW $Cxxx` a `DW ETIQUETA`, un cambio mayor que se deja para
una futura ronda si se quiere completar del todo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 647 etiquetas (baja de 666 a 647,
-19 -- 1 etiqueta global nueva (`APLICAR_ENVOLVENTE_RUIDO`) menos 20
etiquetas locales nuevas, cuadra exacto). Sin menciones en los
HTML/`.md` activos (solo en `FINDINGS.md`, historicas).



### CHANNEL_STATE_ZERO_C9BC -> AREA_TRABAJO_PSG

Renombrada `CHANNEL_STATE_ZERO_C9BC` a `AREA_TRABAJO_PSG`: no es solo
"estado de canal" -- son los 171 bytes completos de RAM de trabajo de
todo el driver de sonido (indice de canal, sombra de los 11 registros
del PSG, las 3 ranuras de canal, y las tablas compartidas hasta
`TRANSPOSE_TABLE_CA67`), todo a `$00` en la v1.0 original (en la v2.0
CAS/ROM aqui se inserta el parche del bug del nivel 13, ya
documentado).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 647 etiquetas (sin cambio de
total, renombrado 1:1). Sin menciones en los HTML/`.md` activos.



### INSTRUMENT_TABLE_CA6A -> TABLA_INSTRUMENTOS_PSG

Renombrada `INSTRUMENT_TABLE_CA6A` a `TABLA_INSTRUMENTOS_PSG`: 16
instrumentos x 15 bytes, copiados a la ranura de canal por el comando
`SET_INSTRUMENT`. De paso, `src/README.md` actualizado (mencionaba
tambien el nombre antiguo `RM_TABLE_C8DE` de una ronda anterior,
corregido a `TABLA_NOTAS_PSG` de paso).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 647 etiquetas (sin cambio de
total, renombrado 1:1). `src/README.md` (1 mencion, 2 nombres
corregidos) actualizado.



### ENV_SHAPE_TABLE_CB5A -> TABLA_ENVOLVENTES_PSG

Renombrada `ENV_SHAPE_TABLE_CB5A` a `TABLA_ENVOLVENTES_PSG`: 4 formas
de envolvente de percusion x 6 bytes, copiadas por el comando
`SET_ENVELOPE_SHAPE` a `SHARED_ENVELOPE_TABLE_CA53+4`. De paso,
`src/README.md` actualizado (misma mencion que en la ronda anterior).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas`/inventario HTML regenerados: 647 etiquetas (sin cambio de
total, renombrado 1:1). `src/README.md` (1 mencion) actualizado.



### 7 hex sin sustituir corregidos: $C9BC -> AREA_TRABAJO_PSG

A peticion del usuario, localizados y corregidos los 7 sitios reales
que seguian usando `$C9BC` en hex (indice de canal actual) pese a
coincidir con el inicio exacto de `AREA_TRABAJO_PSG`: `PROCESAR_CANAL_PSG`,
el comando `RESET_SHARED_ENVELOPE`, `ACTUALIZAR_MEZCLADOR_CANAL` (x2),
los comandos `CALL_SUBPATTERN`/`RETURN_SUBPATTERN` y
`OBTENER_PUNTERO_TRANSPOSICION`. Mismo patron sistemico de siempre.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Corregido el tamaño comentado de AREA_TRABAJO_PSG: 171 -> 151 bytes

A peticion del usuario ("verifica si el tamaño del bloque es
correcto"), contados los bytes reales declarados (`DB`) de
`AREA_TRABAJO_PSG`: 2 + 9x16 + 5 = **151 bytes**, no 171 como decia
el comentario en 2 sitios (la cabecera de indice del bloque de datos
y la propia etiqueta). El bloque en si SI estaba bien -- termina
exacto donde empieza `SHARED_ENVELOPE_TABLE_CA53` ($CA53-$C9BC=151,
cuadra) -- era solo el numero del comentario el que estaba mal.
Corregido en ambos sitios. Cambio de comentario, cero cambio de
bytes.

**Verificado**: recompilado, diffs en la linea base exacta de
siempre (7/2) -- solo comentario, cero cambios de contenido.



### 4 hex sin sustituir corregidos: $CA53 -> SHARED_ENVELOPE_TABLE_CA53

A peticion del usuario, mismo patron sistemico de siempre pero esta
vez sobre la tabla de envolvente compartida (ruido). Localizados y
corregidos los 4 sitios reales que seguian usando `$CA53` en hex pese
a coincidir con el inicio exacto de `SHARED_ENVELOPE_TABLE_CA53`:
`APLICAR_ENVOLVENTE_RUIDO` (`LD IY,...`), `REINICIAR_ENVOLVENTE_RUIDO`
(`LD IY,...`), el comando `RESET_SHARED_ENVELOPE` (`LD HL,...`) y el
comando `SET_ENVELOPE_SHAPE` (`LD IY,...` antes de
`.BUCLE_COPIAR_FORMA_ENVOLVENTE`). Los 2 comentarios que ya
mencionaban `$CA53` en prosa se dejaron tal cual (correctos).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### SHARED_ENVELOPE_TABLE_CA53 -> TABLA_ENVOLVENTE_RUIDO_PSG

A peticion del usuario, renombrada siguiendo el patron `TABLA_X_PSG`
ya establecido (`TABLA_NOTAS_PSG`, `TABLA_INSTRUMENTOS_PSG`,
`TABLA_ENVOLVENTES_PSG`), usando "RUIDO" porque las funciones que la
manejan ya se llaman `APLICAR_ENVOLVENTE_RUIDO`/
`REINICIAR_ENVOLVENTE_RUIDO` -- deja claro que es la envolvente de
ruido compartida entre canales (estado en vivo), a diferencia de
`TABLA_ENVOLVENTES_PSG` (formas plantilla). 8 ocurrencias renombradas
en `madmix1_body.asm` (4 en codigo, 4 en comentarios).

**Verificado**: recompilado sin errores (recompilando `main.lst`
antes de regenerar el inventario -- si no, `gen_inventory.py` lee
datos obsoletos de un `.lst` desactualizado), diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 647 etiquetas (sin cambio de total, renombrado 1:1).



### SUBPATTERN_TABLE_CB72 -> TABLA_SUBPATRONES_PSG

A peticion del usuario, renombrada siguiendo el mismo patron
`TABLA_X_PSG` -- es la tabla de 21 punteros de 16 bits (`DW`) que
`CALL_SUBPATTERN` indexa para saltar a uno de los 13 subpatrones
compartidos. Renombrada en `madmix1_body.asm` (14 menciones, todas en
comentarios) y en `src/README.md` (2 menciones). Tambien corregido el
mismo nombre en el banner de aviso que `tools/mmsnd_tool.py` escribe
al principio de cada `.txt` de subpatron (`warning_banner()`), y
regenerados los 13 `.txt` de `src/data/sound/spt/` con
`py tools/mmsnd_tool.py disasm` para que el aviso quede actualizado
(contenido binario/instrucciones sin cambios, solo el nombre en el
comentario). `manuales/manual_driver_sonido.md` se dejo sin tocar --
es un documento congelado con varios otros nombres ya obsoletos, no
forma parte de los docs vivos que se sincronizan cada ronda.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 647 etiquetas (sin cambio de total, renombrado 1:1).



### 1 hex sin sustituir corregido: $CA6A -> TABLA_INSTRUMENTOS_PSG

A peticion del usuario, mismo patron sistemico de siempre. Localizado
y corregido el unico sitio real que seguia usando `$CA6A` en hex
(dentro del comando `SET_INSTRUMENT`, `LD DE,$CA6A` como base antes
de `ADD HL,DE` para calcular `base + indice*15`) pese a coincidir con
el inicio exacto de `TABLA_INSTRUMENTOS_PSG`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### 2 hex sin sustituir corregidos: $CB5A -> TABLA_ENVOLVENTES_PSG, $CB72 -> TABLA_SUBPATRONES_PSG

A peticion del usuario, comprobado el mismo patron sistemico para las
2 tablas recien renombradas. Localizado y corregido 1 sitio real por
tabla: `$CB5A` en el comando `SET_ENVELOPE_SHAPE` (`LD DE,$CB5A` como
base antes de `ADD HL,DE` para `base + indice*6`), y `$CB72` en el
comando `CALL_SUBPATTERN` (`LD HL,$CB72` antes de
`LEER_PALABRA_INDEXADA`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### ISR -> ENTRADA_INTERRUPCION_VBLANK

A peticion del usuario. El label `ISR` no es una funcion llamada por
codigo (nadie hace `CALL ISR`/`JP ISR`) -- es el punto de entrada al
que salta la CPU por hardware via el vector de interrupcion modo 1
(`$0038/$0039`, instalado por `ACTIVAR_INTERRUPCION_MODO_1`). El
nuevo nombre refleja eso: "ENTRADA" en vez de una palabra que sugiera
llamada explicita. Renombrado en `madmix1_body.asm` (6 menciones),
`madmix_scr_body.asm` (4 menciones), `FLUJO_PROGRAMA.md` (varias
menciones) y `recursos/mapa_memoria.html` (4 menciones). NO se toco
`src/README.md` linea 568: es un parrafo de historial de sesion ya
congelado (usa incluso `INSTALL_ISR`, un nombre aun mas antiguo, sin
sincronizar) -- mismo criterio que con otros registros de historial.
`ISR_HOUSEKEEPING` (funcion real, distinta, si se llama por codigo)
NO se toco -- verificado que ningun reemplazo la afecto.

**Nota pendiente**: `INSTALL_ISR` sigue apareciendo tal cual (sin
sincronizar al nombre real `ACTIVAR_INTERRUPCION_MODO_1`) en
`FLUJO_PROGRAMA.md` (lineas ~137/169) y en el parrafo de historial de
`README.md` -- fuera de alcance de esta ronda, candidato a limpieza
futura.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 647 etiquetas (sin cambio de total, renombrado 1:1).



### GH_885D_EARLYEXIT -> .NO_ES_IRQ_VBLANK (local)

A peticion del usuario. Es la salida temprana de
`ENTRADA_INTERRUPCION_VBLANK` cuando `IN A,($99)` + `AND A`/`JP P,...`
detecta que el bit de signo no esta activo (no era una IRQ real de
VBLANK) -- descarta la interrupcion espuria sin ejecutar
`ISR_HOUSEKEEPING`/`TAIL_LEVELCYCLE_HELPER`. Verificado que solo se
referencia desde dentro de `ENTRADA_INTERRUPCION_VBLANK` (la unica
llamada, en la misma rutina) -- convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 646 etiquetas (baja 1, quirk conocido de global->local).



### ISR_HOUSEKEEPING -> GESTIONAR_FRAME

A peticion del usuario. Llamada desde `ENTRADA_INTERRUPCION_VBLANK`
en cada VBLANK: decide si ya toca el trabajo pesado de un frame
completo usando `FRAME_FLAG` como semaforo -- si es asi, refresca
VRAM (`ACTUALIZAR_VRAM_FRAME`), avanza actores
(`CONTINUAR_CAPTURA_MASCARAS_ACTORES`/`RESET_CONTADOR_ACTORES`) y
vacia la cola de redibujado diferido (antes `$8CFF`, ya identificado
en otra ronda). El nombre en espanol refleja lo que hace ("gestionar
el frame") en vez del acronimo ingles "housekeeping" heredado del
analisis anterior. Renombrado en `madmix1_body.asm` (6 menciones),
`src/README.md` (1 mencion), `src/FLUJO_PROGRAMA.md` (3 menciones) y
`recursos/mapa_memoria.html` (1 mencion).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 646 etiquetas (sin cambio de total, renombrado 1:1).



### GH_8889_HOOK -> FUNCION_INHABIL

A peticion del usuario. Confirmado byte a byte que el cuerpo es solo
`RET` (1 byte) -- no hace nada, pese a que las 4 llamadas (3 desde
`GESTIONAR_FRAME`, 1 desde `ACTUALIZAR_VRAM_FRAME`) precargan `A` con
distintos valores ($0F/$01/$01/$06) que se ignoran por completo.
Queda global (llamada desde 2 rutinas distintas, no solo una).
Hipotesis sin confirmar: un hook de desarrollo (debug/sonido)
deshabilitado, cuyo cuerpo real se sobreescribio con un `RET` antes
de la version final, dejando las llamadas como vestigio. Renombrado
solo en `madmix1_body.asm` (6 menciones) -- sin menciones en
`README.md`/`FLUJO_PROGRAMA.md`/`mapa_memoria.html`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 646 etiquetas (sin cambio de total, renombrado 1:1).



### GH_8882_SKIP -> .SIN_TRABAJO_DE_FRAME (local)

A peticion del usuario. Es el punto de convergencia dentro de
`GESTIONAR_FRAME` al que salta el `JR NZ` cuando `FRAME_FLAG` no
confirmaba un frame nuevo -- se salta todo el bloque pesado
(`ACTUALIZAR_VRAM_FRAME`, avance de actores, vaciado de cola) y cae
aqui directo para la ultima llamada a `FUNCION_INHABIL` y `RET`.
Verificado que solo se referencia desde dentro de `GESTIONAR_FRAME`
(la unica llamada, en la misma rutina) -- convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 645 etiquetas (baja 1, quirk conocido de global->local).



### 2 hex sin sustituir corregidos: $8430 -> FRAME_FLAG

A peticion del usuario, mismo patron sistemico de siempre. Localizados
y corregidos los 2 sitios reales que seguian usando `$8430` en hex
dentro de `GESTIONAR_FRAME` (`LD A,($8430)` / `LD ($8430),A`) pese a
coincidir con el inicio exacto de `FRAME_FLAG`. La linea 27
(`DS $8430-$, $00`, el relleno justo ANTES de `FRAME_FLAG`) se dejo
en hex a proposito -- no puede referenciar la propia etiqueta que
define ese mismo punto.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Comentados los 4 parametros sin efecto de FUNCION_INHABIL

A peticion del usuario, anadido un comentario en cada una de las 4
lineas `LD A,$0F/$01/$01/$06` que preceden a una llamada a
`FUNCION_INHABIL` (3 en `GESTIONAR_FRAME`, 1 en
`ACTUALIZAR_VRAM_FRAME`), dejando explicito que el valor cargado no
tiene ningun efecto porque el cuerpo de `FUNCION_INHABIL` es solo
`RET`. Cambio de solo comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### 1 hex sin sustituir corregido: $8CFF -> QUEUE_INIT_CHECK

A peticion del usuario, mismo patron sistemico de siempre. La rutina
real detras de la vieja llamada "misteriosa" `CALL $8CFF` dentro de
`GESTIONAR_FRAME` ya estaba identificada mas abajo en el fichero como
`QUEUE_INIT_CHECK` (vacia la cola de redibujado diferido cada frame),
pero el `CALL` seguia en hex, igual que el comentario de cabecera de
`GESTIONAR_FRAME` que la mencionaba como "sin identificar todavia"
(ya obsoleto, corregido de paso). Sincronizado tambien
`src/FLUJO_PROGRAMA.md` (1 mencion, §5.9). `src/README.md` linea 573
se dejo sin tocar -- es el mismo parrafo de historial de sesion ya
congelado identificado en la ronda de `ISR`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### QUEUE_INIT_CHECK -> VACIAR_COLA_REDIBUJADO

A peticion del usuario. El nombre anterior ("comprobacion de inicio")
se quedaba corto: la rutina no solo comprueba, recorre y vacia por
completo la cola circular de losetas pendientes de redibujar
(rellenada por `QUEUE_PUSH`), llamando a `REDIBUJAR_LOSETA_BUFFER_VRAM`
por cada entrada hasta el centinela `$FF`. Renombrado en
`madmix1_body.asm` (5 menciones), `src/FLUJO_PROGRAMA.md` (2
menciones) y `recursos/mapa_memoria.html` (1 mencion). Anadido
tambien un comentario en el sitio de la llamada (dentro de
`GESTIONAR_FRAME`) explicando la funcionalidad.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 645 etiquetas (sin cambio de total, renombrado 1:1;
subtotales funcion/sinref variaron en 1 cada uno por reclasificacion
de la heuristica, no por perdida/creacion de etiquetas).



### GH_888A_VDPOUT -> FIJAR_COLOR_BORDE_VDP

A peticion del usuario. Fija el registro 7 del VDP (TMS9918 --
color de borde/fondo) al valor de A: `OUT ($99),A` (dato) seguido de
`LD A,$87` / `OUT ($99),A` (numero de registro con el bit de modo
escritura activado). Definida en `madmix1_body.asm` pero llamada
exclusivamente desde `madmix_scr_body.asm` (2 sitios) -- confirmado
que se queda global. Nombrado por funcion (que hace) en vez de
mecanismo generico ("VDPOUT").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 645 etiquetas (sin cambio de total, renombrado 1:1).



### Nueva etiqueta: $8888 -> ULTIMO_ICONO_HUD_CACHEADO

A peticion del usuario. `$8888` no tenia etiqueta -- caia justo en el
byte de relleno (transcrito antes como `NOP`, mismo valor `$00`) justo
despues del `RET` de `.SIN_TRABAJO_DE_FRAME` dentro de
`GESTIONAR_FRAME`. Resulta ser una variable real de 1 byte
compartida entre los 2 ficheros: cachea el ultimo icono de nivel
dibujado en el HUD -- `ACTUALIZAR_VRAM_FRAME` (madmix1_body.asm) la
compara cada frame contra `REGISTRO_NIVEL_ICONO_HUD` para decidir si
hace falta redibujar (salvo que `FLAG_NIVEL_RECIEN_CARGADO` fuerce el
redibujado), y `APLICAR_COLOR_PANTALLA` (madmix_scr_body.asm) la
resetea a 0 al aplicar la paleta de color de pantalla (carga de
nivel). Convertido el `NOP` a `DB $00` con la etiqueta -- mismo byte
exacto, representa mejor su naturaleza real de dato, no de
instruccion muerta. Sustituidos los 2 sitios reales de uso
(`madmix1_body.asm` y `madmix_scr_body.asm`) que usaban `$8888` en
hex crudo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- byte
identico confirmado entre `NOP` y `DB $00`. `.dsk`/`.cas` regenerados.
Inventario HTML regenerado: 646 etiquetas (sube 1, etiqueta nueva,
categoria `dato`).



### GH_88A4 -> .REDIBUJAR_ICONO_HUD (local)

A peticion del usuario. Es la rama de `ACTUALIZAR_VRAM_FRAME` que
actualiza `ULTIMO_ICONO_HUD_CACHEADO` y repinta la zona de VRAM del
icono (bucle de 18 rellenos via `FILVRM` desde `$2220`) -- se llega
aqui si `FLAG_NIVEL_RECIEN_CARGADO` fuerza el redibujado, o por caida
natural cuando la comparacion contra la cache indica que el icono
cambio. Verificado que solo se referencia desde dentro de
`ACTUALIZAR_VRAM_FRAME` -- convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 645 etiquetas (baja 1, quirk conocido de global->local).



### RESUELTO: LOOKUP_8978/DIRBITS_TABLE eran color VDP, no direcciones -- renombrados

A peticion del usuario ("hay que analizar para saber que es realmente
esto"). La hipotesis anterior en el comentario de cabecera de
`LOOKUP_8978` ("tabla de decision de movimiento, IA de fantasmas?")
era incorrecta. La prueba estaba ya en el codigo, sin conectar:
`OBTENER_COLOR_VDP` (madmix_scr_body.asm, `$6484`) tiene un comentario
que dice explicitamente que compone 2 consultas a la misma tabla para
traducir un byte a un color VDP completo de SCREEN2 (nibble alto =
tinta, nibble bajo = fondo). Confirmado tambien que las direcciones
en los nombres estaban cruzadas: la RUTINA esta en `$8961` (no
`$8978` como sugeria "LOOKUP_8978") y la TABLA esta en `$8978` (asi
que el "8978" del nombre en realidad pertenecia a la tabla).
Renombrados: `LOOKUP_8978` -> `CONSULTAR_COLOR_VDP` (version simple,
solo nibble bajo/fondo, usada en `ACTUALIZAR_VRAM_FRAME` para pintar
el icono del HUD y la zona de `COLOR_ACTUAL`), `DIRBITS_TABLE` ->
`TABLA_COLORES_VDP` (16 colores VDP 0-15, no bits de direccion).
Corregido el comentario de cabecera desactualizado. Sustituidos de
paso los 2 sitios reales que usaban `CALL $8961` en hex
(`madmix1_body.asm`) y los 2 que usaban `LD HL,$8978`
(`madmix_scr_body.asm`, dentro de `OBTENER_COLOR_VDP`) -- mismo
patron sistemico de siempre. Sincronizados `src/FLUJO_PROGRAMA.md`,
`recursos/mapa_memoria.html` y `recursos/graficos.html` (esta ultima,
aunque no es de las 2 HTML de sincronizacion habitual, referenciaba
el nombre exacto en prosa y en un comentario JS). `src/README.md`
linea 545 se dejo sin tocar -- es otro parrafo de historial de sesion
ya congelado (menciona ademas `TAIL_TILE_LOOKUP`, nombre aun mas
antiguo de `OBTENER_COLOR_VDP`, sin sincronizar).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 645 etiquetas (sin cambio de total, renombrado 1:1;
subtotales variaron por reclasificacion de la heuristica).



### GH_88BC -> .SIN_CAMBIO_ICONO_HUD (local), GH_88AD -> .BUCLE_RELLENO_ICONO_HUD (local)

A peticion del usuario. `GH_88BC` es la rama gemela de
`.REDIBUJAR_ICONO_HUD` dentro de `ACTUALIZAR_VRAM_FRAME`: se toma
cuando el icono del HUD NO cambio, hace un `LDIR` de 1323 bytes desde
`$4000` sobre si mismo (mismo origen y destino -- no cambia memoria,
solo consume ciclos, aparente relleno de temporizacion para igualar
el tiempo de esta rama con el de redibujado real) y una llamada muerta
a `FUNCION_INHABIL`, antes de converger en el codigo comun.

Al renombrar `GH_88BC` a local aparecio un error de compilacion
("Label not found") por la misma trampa de scoping ya documentada
antes en la sesion: `GH_88AD` (una etiqueta global) caia entre medias,
rompiendo la cadena de ambito local. Solucionado convirtiendo tambien
`GH_88AD` a local (`.BUCLE_RELLENO_ICONO_HUD`, el bucle de 18
rellenos de VRAM via `FILVRM`) -- verificado que solo se referenciaba
desde dentro de la misma rutina.

**Verificado**: recompilado sin errores tras el ajuste de scoping,
diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 643 etiquetas (baja 2, dos
conversiones global->local).



### $00C0 -> 192 (decimal)

A peticion del usuario. Es el parametro BC (longitud) de la llamada a
`FILVRM` dentro de `.BUCLE_RELLENO_ICONO_HUD` -- un recuento de
bytes, no una direccion ni una mascara, encaja en la politica ya
establecida de decimal para recuentos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Comentadas las 10 llamadas a FILVRM

A peticion del usuario, anadido en cada uno de los 10 sitios que
hacen `CALL FILVRM` (5 en `madmix1_body.asm`, 5 en
`madmix_scr_body.asm`) un comentario indicando que es el equivalente
a la rutina del mismo nombre del BIOS de MSX. Cambio de solo
comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### GH_88CB -> .APLICAR_COLOR_Y_SCROLL_VRAM (local)

A peticion del usuario. Es el punto de convergencia dentro de
`ACTUALIZAR_VRAM_FRAME` donde caen las 2 ramas del icono del HUD
(`.REDIBUJAR_ICONO_HUD`/`.SIN_CAMBIO_ICONO_HUD`) -- trabajo que
ocurre TODOS los frames sin condicion: refresca 2 zonas de color VRAM
(`$2A80`/`$2B80`) a partir de `COLOR_ACTUAL` via `CONSULTAR_COLOR_VDP`,
y vuelca el buffer de trabajo `$DE04` a VRAM `$0220` (el mismo buffer
que desplazan las rutinas `SCROLL_*`) -- es la parte que aplica de
verdad el scroll del laberinto a pantalla cada frame. Verificado que
solo se referencia desde dentro de `ACTUALIZAR_VRAM_FRAME` --
convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 642 etiquetas (baja 1, quirk conocido de global->local).



### Comentarios aclarando $2220 (VRAM real) vs $4000 (memoria Z80, no VRAM)

A peticion del usuario. `$2220` (en `.REDIBUJAR_ICONO_HUD`) es
direccion VRAM real -- se pasa como `HL` a `FILVRM`, que solo escribe
VRAM via el puerto `$98`. `$4000` (en `.SIN_CAMBIO_ICONO_HUD`) NO es
VRAM -- se usa directamente con `LDIR` (acceso normal a memoria del
Z80, sin pasar por `FILVRM`/`SETVRAM`), es una direccion del espacio
de memoria del Z80 usada solo como relleno del `LDIR` de
temporizacion ya documentado. Anadido un comentario en cada linea
aclarando la diferencia. Cambio de solo comentarios, cero cambio de
bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### MISTERIO SIN RESOLVER: $052B (1323) en .SIN_CAMBIO_ICONO_HUD -- hipotesis de temporizacion DESCARTADA

El usuario desconfio del valor `$052B` (1323, contador del `LDIR` de
relleno sobre `$4000`). Calculo de ciclos aproximado para comparar
ambas ramas de `ACTUALIZAR_VRAM_FRAME`: `.REDIBUJAR_ICONO_HUD` (18x
`FILVRM` de 192 bytes, solo el bucle interno `OUT/DEC/JR NZ` ~28
ciclos/byte) ≈ 97000 ciclos; `.SIN_CAMBIO_ICONO_HUD` (`LDIR` con
BC=1323, ~21 ciclos/byte) ≈ 27800 ciclos. No cuadra ni de lejos
(~3.5x de diferencia), asi que la hipotesis de "relleno para igualar
el tiempo de la otra rama" (escrita en una ronda anterior de esta
misma sesion) queda DESCARTADA. Marcado explicitamente en el codigo
como misterio sin resolver -- no se ha encontrado explicacion
alternativa. Cambio de solo comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### 4 nuevas constantes VRAM/RAM: ZONA_COLOR_VRAM_DESTELLO_A/B, ZONA_PATRON_VRAM_LABERINTO, BUFFER_LOSETAS_TRABAJO

A peticion del usuario, etiquetadas las direcciones del bloque
`.APLICAR_COLOR_Y_SCROLL_VRAM`: `$2A80`/`$2B80` (VRAM, zonas de color
de 16 bytes del destello icono/color HUD) -> `ZONA_COLOR_VRAM_DESTELLO_A`/
`ZONA_COLOR_VRAM_DESTELLO_B`; `$0220` (VRAM, destino del volcado del
buffer de losetas) -> `ZONA_PATRON_VRAM_LABERINTO`; `$DE04` (memoria
del Z80, NO VRAM -- el buffer de trabajo de losetas) ->
`BUFFER_LOSETAS_TRABAJO`. Como en el proyecto nunca se habia usado
`EQU` (sin precedente en ningun fichero), las 4 se definieron como
constantes justo ANTES de `ACTUALIZAR_VRAM_FRAME` (no dentro), para
no repetir la trampa de scoping de rondas anteriores. Sustituidos
todos los sitios reales que usaban estos valores en hex crudo:
`$2A80`/`$2B80` (2 sitios), `$0220` (1 sitio), `$DE04` (7 sitios: 6 en
`madmix1_body.asm`, 1 en `madmix_scr_body.asm`) -- mismo patron
sistemico de siempre, aqui con etiquetas nuevas en vez de ya
existentes. Tambien pasados a decimal los 2 recuentos de `FILVRM`
($0010->16) y el recuento de filas del bucle de scroll ($12->18)
dentro del mismo bloque. Sincronizados los comentarios de cabecera de
`ACTUALIZAR_VRAM_FRAME` y varias entradas de prosa en
`recursos/mapa_memoria.html`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 646 etiquetas (sube 4, las 4 constantes nuevas).



### GH_88ED -> .BUCLE_FILA_CARACTERES_VRAM (local), GH_88FC -> .BUCLE_COLUMNA_CARACTERES_VRAM (local)

A peticion del usuario. Son los 2 bucles anidados que vuelcan
`BUFFER_LOSETAS_TRABAJO` a VRAM al final de `ACTUALIZAR_VRAM_FRAME`:
transponen el lienzo lineal de pixeles (144 filas x 32 bytes) al
formato por-caracter que espera la tabla de patrones de SCREEN2 (8
bytes consecutivos = las 8 lineas de un caracter). El externo
(`DJNZ`, B=18) recorre 18 filas de caracteres (bandas de 8 lineas de
pixeles); el interno (`JP NZ`, E=24) recorre las 24 columnas de cada
banda, leyendo 8 bytes por columna (salto de 32 = una fila del buffer)
y volcandolos seguidos a VRAM. Verificado que ambos solo se
referencian entre si dentro de `ACTUALIZAR_VRAM_FRAME` -- convertidos
a locales.

**Verificado**: recompilado sin errores (sin problema de scoping esta
vez), diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 644 etiquetas (baja 2, dos
conversiones global->local).



### Comentadas las cabeceras de FILVRM, LDIRVM y SETVRAM

A peticion del usuario, anadido un comentario de una linea en cada
una de las 3 rutinas de la API del VDP explicando su funcionalidad:
`FILVRM` (rellena BC bytes de VRAM desde HL con el byte fijo A),
`LDIRVM` (copia BC bytes de RAM HL a VRAM DE, byte a byte) y
`SETVRAM` (posiciona el puntero de escritura del VDP en la direccion
VRAM de HL -- equivalente a `SETWRT` del BIOS, confirmado por el
patron de escritura a puerto `$99` que coincide exacto). Cambio de
solo comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### Analizados los 5 bytes sin explicar entre CONSULTAR_COLOR_VDP y TABLA_COLORES_VDP

A peticion del usuario, buscado quien accede a los 5 bytes `DB $00`
que caen entre `CONSULTAR_COLOR_VDP` (termina en `$8972`, 18 bytes
desde `$8961`) y `TABLA_COLORES_VDP` (`$8978`) -- direcciones
`$8973`-`$8977`. No se encontro ningun `JP`/`CALL` ni aritmetica de
etiqueta que los referencie en ninguno de los 2 ficheros. Dato
observado: `$8978` es multiplo exacto de 8 -- HIPOTESIS (sin
confirmar consumidor real): relleno de alineacion de la tabla a un
limite de 8 bytes, a diferencia del bloque FILVRM/LDIRVM/SETVRAM de
mas arriba, que quedan exactamente contiguos sin hueco. Comentario
actualizado en la linea con este analisis. Cambio de solo
comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### ADDR_FROM_DC00 -> CALCULAR_DIRECCION_MASCARA_ACTOR

A peticion del usuario. Al preguntar por `$DC00` se localizo un
hallazgo posterior ya existente en FINDINGS.md que resuelve del todo
la vieja
"Zona 0xDC00 sin descifrar": NO es una tabla aparte, es un SUBTRAMO
de `RLE_TABLE_D6B6` (la tabla RLE del marco de caramelo) reutilizado
con un segundo proposito -- economia de memoria tipica de MSX1. Esta
rutina (+ `COMPONER_ACTORES_EN_BUFFER`) accede a ese subtramo de forma
aleatoria como mascaras AND/OR de 16 bits para componer sprites
contra el fondo. Renombrada para reflejar el proposito real (antes
solo describia el mecanismo "desde DC00"). Comentario de cabecera
reescrito con el hallazgo completo. Renombrada en `madmix1_body.asm`
(6 menciones), `src/README.md` (1 mencion) y
`recursos/mapa_memoria.html` (2 menciones).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 644 etiquetas (sin cambio de total, renombrado 1:1).



### RLE_TABLE_D6B6 -> TABLA_RLE_MARCO_CARAMELO

A peticion del usuario. Renombrada la tabla RLE que reconstruye el
marco de caramelo completo de VRAM (870 pares valor/repeticion, 1740
bytes, `$D6B6-$DD82`) -- mantiene "RLE" (el formato real de
compresion) y anade la identidad ya confirmada visualmente (el marco
de caramelo), coincidiendo con el nombre del fichero de datos ya
existente (`marco_caramelo_forma.img`). Renombrada en
`madmix1_body.asm` (definicion + 3 menciones), `madmix_scr_body.asm`
(2 menciones), `src/README.md` (2 menciones), `recursos/mapa_memoria.html`
(3 menciones, aprovechando tambien para corregir una mencion suelta
de `LOOKUP_8978` que se habia escapado en una ronda anterior) y
`recursos/graficos.html` (2 menciones).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 644 etiquetas (sin cambio de total, renombrado 1:1).



### SD_89BA -> .COMPROBAR_EJE_Y (local)

A peticion del usuario. Es el punto de convergencia dentro de
`GESTIONAR_SCROLL` entre el camino directo (2 bits bajos de L, sub-
pixel X, ya alineados a tile) y el camino con caida (se enmascara C a
sus 2 bits bajos antes de llegar aqui) -- desde aqui la comprobacion
pasa al eje Y (2 bits bajos de H) de la misma manera. Verificado que
solo se referencia desde dentro de `GESTIONAR_SCROLL` -- convertido a
local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 643 etiquetas (baja 1, quirk conocido de global->local).



### SD_89C2 -> .DECIDIR_DIRECCION_SCROLL (local)

A peticion del usuario. Es el gemelo de `.COMPROBAR_EJE_Y` pero para
el eje Y ya resuelto: convergen aqui el camino directo (2 bits bajos
de H, sub-pixel Y, ya alineados a tile) y el camino con caida (`AND
$0C` sobre C, bits 2-3) antes de llegar. Desde aqui arranca la
cascada final de 4 `RRA`/`JP C,...` que decide SCROLL_UP/DOWN/LR (o
ninguno). Verificado que solo se referencia desde dentro de
`GESTIONAR_SCROLL` -- convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 642 etiquetas (baja 1, quirk conocido de global->local).



### SCROLL_UP -> SCROLL_ARRIBA, SCROLL_DOWN -> SCROLL_ABAJO

A peticion del usuario, traducidas al espanol las 2 rutinas de scroll
vertical (la lateral, `SCROLL_LR`, se deja tal cual -- no se pidio
cambiarla). Renombradas en `madmix1_body.asm` (definiciones +
menciones en comentarios/llamadas) y en `recursos/mapa_memoria.html`
(2 entradas, incluyendo un atajo de prosa "SCROLL_UP/DOWN/LR"
reescrito a la forma completa por claridad).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 642 etiquetas (sin cambio de total, renombrado 1:1).



### SCROLL_LR resultaba ser 2 rutinas distintas: SCROLL_DERECHA (ya etiquetada) y SCROLL_IZQUIERDA (nueva, antes sin nombre)

A peticion del usuario ("analizalo en profundidad"). La cascada de 4
bits de `GESTIONAR_SCROLL` (`RRA`/`JP C,...`) no elegia entre 3
rutinas sino entre 4: `SCROLL_ARRIBA`, `SCROLL_ABAJO`, la antigua
`SCROLL_LR` (etiquetada, alcanzada por `JP C`), y un CUARTO bloque
**sin etiqueta**, alcanzado solo por caida cuando el `RET NC` final no
retorna (acarreo activo en la 4a rotacion). Ambos bloques comparten
cola `SLR_800A_TAIL` (bucle de 140 iteraciones x 24 `LDI`, direcciones
opuestas via `BC=$FFE0`/`-32` vs `BC=$0020`/`+32`) y difieren en un
flag (`A=$FF`/`-1` vs `A=$01`/`+1`) que al final del bucle se SUMA
directamente a `REGISTRO_NIVEL_POSICION_COMECOCOS` (`ADD A,H`/`LD
H,A`). HIPOTESIS de confianza media-alta (asumiendo convenio estandar
de X creciente hacia la derecha, sin confirmar en vivo): sumar +1
mueve la camara a la derecha, restar 1 a la izquierda. Renombrados:
`SCROLL_LR` (ya etiquetada, flag +1) -> `SCROLL_DERECHA`; el bloque
sin nombre (flag -1) -> nueva etiqueta `SCROLL_IZQUIERDA`. Comentarios
de cabecera actualizados con la hipotesis y su nivel de confianza.
Sincronizados `madmix_scr_body.asm` (1 mencion) y
`recursos/mapa_memoria.html` (2 entradas).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 643 etiquetas (sube 1, la nueva etiqueta SCROLL_IZQUIERDA).



### SCROLL_LR_PARAM -> PARAMETRO_DESPLAZAMIENTO_SCROLL

A peticion del usuario. El nombre anterior sugeria uso exclusivo de
las rutinas laterales, pero en realidad la escriben las 4 direcciones
(`SCROLL_IZQUIERDA=$0400`, `SCROLL_DERECHA=$FC00`, `SCROLL_ABAJO=$0004`,
`SCROLL_ARRIBA=$00FC`) como un delta (dx,dy) de 4px empaquetado (H=eje
horizontal, L=eje vertical, el otro siempre a 0), leido despues por
2 consumidores (`DE=(PARAMETRO_DESPLAZAMIENTO_SCROLL)`) al final de
sendos bucles de redibujado. Dato que refuerza la hipotesis
IZQUIERDA/DERECHA de la ronda anterior: los signos de este parametro
(+4 IZQUIERDA / -4 DERECHA) son opuestos a los del ajuste directo de
`REGISTRO_NIVEL_POSICION_COMECOCOS` (-1/+1) -- relacion fisicamente
esperada entre "hacia donde se mueve la camara" y "hacia donde se
desplaza el contenido redibujado". Renombrada en `madmix1_body.asm`
(6 menciones), `madmix_scr_body.asm` (definicion + 1 mencion) y
`recursos/mapa_memoria.html` (1 mencion).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 643 etiquetas (sin cambio de total, renombrado 1:1).



### SLR_800A_TAIL -> APLICAR_DESPLAZAMIENTO_LATERAL

A peticion del usuario. Es la cola compartida entre `SCROLL_IZQUIERDA`
y `SCROLL_DERECHA`: copia 24 de cada 32 bytes por fila (140 filas,
via `BC` como paso -32/+32 entre vueltas) del lienzo
`BUFFER_LOSETAS_TRABAJO`, y al terminar suma el flag +1/-1 a
`REGISTRO_NIVEL_POSICION_COMECOCOS`. Se queda global (referenciada
desde 2 rutinas globales distintas, no anidada dentro de solo una).
Solo en `madmix1_body.asm` (4 menciones) -- sin menciones en otros
ficheros vivos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 643 etiquetas (sin cambio de total, renombrado 1:1).



### SLR_LOOP -> .BUCLE_FILA_DESPLAZAMIENTO (local)

A peticion del usuario. Es el cuerpo del bucle de 140 iteraciones
dentro de `APLICAR_DESPLAZAMIENTO_LATERAL`: por cada fila, copia 24
bytes (24 `LDI` seguidos) y avanza `HL`/`DE` por el paso de fila.
Verificado que solo se referencia desde dentro de la misma rutina --
convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 642 etiquetas (baja 1, quirk conocido de global->local).



### SDOWN_OUTER -> .BUCLE_FILA_SCROLL_ABAJO (local), SDOWN_INNER -> .BUCLE_NIBBLE_SCROLL_ABAJO (local)

A peticion del usuario. Son los 2 bucles anidados de `SCROLL_ABAJO`:
el externo recorre las 144 filas del lienzo; el interno hace 24 `RRD`
por fila (con `INC L` entre cada uno) -- el truco clasico de Z80 de
encadenar `RRD` a traves de bytes consecutivos usando `A` como
"nibble de acarreo" para propagar un desplazamiento de 1 nibble (el
scroll fino de 4px que ya documentaba el comentario de cabecera de
`GESTIONAR_SCROLL`). Al renombrar el externo aparecio la misma trampa
de scoping de siempre (`SDOWN_INNER` global entre medias) --
solucionado convirtiendo tambien el interno a local. Verificado que
ambos solo se referencian entre si dentro de `SCROLL_ABAJO`.

**Verificado**: recompilado sin errores (tras el ajuste de scoping),
diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 640 etiquetas (baja 2, dos
conversiones global->local).



### SUP_OUTER -> .BUCLE_FILA_SCROLL_ARRIBA (local), SUP_INNER -> .BUCLE_NIBBLE_SCROLL_ARRIBA (local)

A peticion del usuario. Gemelos de los de `SCROLL_ABAJO` pero para
`SCROLL_ARRIBA`: usan `RLD`/`DEC L` (en vez de `RRD`/`INC L`) --
recorren la fila en sentido contrario y rotan los nibbles al reves,
coherente con ser la direccion opuesta. Mismo patron de nombrado y
misma trampa de scoping de siempre (`SUP_INNER` global entre medias
al renombrar el externo) -- solucionado convirtiendo tambien el
interno a local. Verificado que ambos solo se referencian entre si
dentro de `SCROLL_ARRIBA`.

**Verificado**: recompilado sin errores (tras el ajuste de scoping),
diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 638 etiquetas (baja 2, dos
conversiones global->local).



### Comentadas las 4 etiquetas de bucle de SCROLL_ARRIBA/SCROLL_ABAJO

A peticion del usuario, anadido un comentario de una linea en cada
una de las 4 etiquetas de bucle explicando su funcionalidad
(`.BUCLE_FILA_SCROLL_ABAJO`/`.BUCLE_NIBBLE_SCROLL_ABAJO`/
`.BUCLE_FILA_SCROLL_ARRIBA`/`.BUCLE_NIBBLE_SCROLL_ARRIBA`).
**Autocorregido un error propio durante la edicion**: el primer intento
de comentar `.BUCLE_NIBBLE_SCROLL_ARRIBA` borro por accidente la
instruccion `RLD` que segui a la etiqueta (el `old_string` del Edit no
incluia esa linea en el reemplazo). Detectado y corregido antes de
recompilar, re-verificado con diffs en la linea base exacta de
siempre (7/2) para confirmar que no quedo ningun byte desplazado.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### Comentadas las etiquetas SCROLL_ARRIBA/SCROLL_ABAJO

A peticion del usuario, anadido un comentario de una linea en cada
una de las 2 etiquetas resumiendo su funcionalidad completa (desplaza
el lienzo 4px en su direccion, 144 filas x 24 RRD/RLD encadenados por
fila, actualiza `PARAMETRO_DESPLAZAMIENTO_SCROLL`/
`REGISTRO_NIVEL_POSICION_COMECOCOS`). Cambio de solo comentarios, cero
cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### $0020 -> 32 (decimal) en SCROLL_ABAJO/SCROLL_ARRIBA, mas comentario

A peticion del usuario. Es el paso entre filas del lienzo
`BUFFER_LOSETAS_TRABAJO` (`LD DE,...` antes de los bucles `.BUCLE_FILA_*`)
-- un recuento/paso, no una direccion ni mascara, encaja en la
politica ya establecida de decimal para recuentos. Aplicado por
consistencia en las 2 rutinas (`SCROLL_ABAJO` y `SCROLL_ARRIBA` usan
el mismo valor con el mismo proposito). Anadido tambien un comentario
en cada sitio indicando que es el dato.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados (sin cambio de
etiquetas, `gen_inventory.py` no aplica).



### Analizado y comentado el bloque de setup de SCROLL_ARRIBA; $DE1B resulto ser BUFFER_LOSETAS_TRABAJO+23

A peticion del usuario. Analizadas las 8 lineas de configuracion de
`SCROLL_ARRIBA` (delta empaquetado, `EXX`+C/D como constantes de fase
consumidas en `SCROLL_LOSETA_BUFFER_VRAM` via `ADD A,C`/`XOR D` para
elegir `SCOPY_A`/`SCOPY_B`, flag de direccion `+1`). Hallazgo: `$DE1B`
no era una direccion suelta -- es exactamente
`BUFFER_LOSETAS_TRABAJO+23` (fin de la fila jugable de 24 bytes;
`SCROLL_ARRIBA` recorre cada fila hacia atras con `DEC L`, al
contrario que `SCROLL_ABAJO`). Corregido a la forma con etiqueta+offset
-- mismo patron sistemico de "hex sin sustituir" de siempre, aqui con
aritmetica de etiqueta en vez de sustitucion directa. Confirmacion de
paso: en `SCROLL_LOSETA_BUFFER_VRAM` el flag de direccion se suma a
`REGISTRO_NIVEL_POSICION_COMECOCOS.L` (no `.H` como en el scroll
lateral) -- consistente con que `L`=eje vertical, `H`=eje horizontal
en esa variable. `$00FC`/`$2F`/`$0F`/`$01` se dejaron en hex (deltas
con signo y constantes de mascara/fase, no recuentos puros) con
comentario explicando cada uno.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `BUFFER_LOSETAS_TRABAJO+23` compila byte-identico a `$DE1B`.
`.dsk`/`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py`
no aplica).



### $90 -> 144 y $02 -> 2 (decimal) en los bucles de SCROLL_ARRIBA/SCROLL_ABAJO, mas comentarios

A peticion del usuario. `LD C,$90` (contador del bucle externo, 144
filas) y `LD B,$02` (contador del bucle interno, 2 vueltas x 12 pares
RRD-o-RLD/INC-o-DEC L = 24 por fila) son recuentos puros -- pasados a
decimal por la politica ya establecida. Aplicado en las 2 rutinas
(`SCROLL_ABAJO` y `SCROLL_ARRIBA`) por consistencia. Anadido tambien
comentario en `PUSH HL` y `XOR A` de ambos bloques.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Comentado el bloque de setup de SCROLL_ABAJO (gemelo de SCROLL_ARRIBA)

A peticion del usuario. Mismo analisis que el bloque de
`SCROLL_ARRIBA`: ningun valor es un recuento puro (delta empaquetado
con signo `$0004`, constantes de fase `$00`/`$F0`, flag de direccion
con signo `$FF`) -- se quedan en hex, con comentario en cada uno.
`LD HL,BUFFER_LOSETAS_TRABAJO` ya usaba la etiqueta (es el inicio de
la fila jugable, sentido opuesto al `+23` de `SCROLL_ARRIBA`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Analizado y comentado el bloque de setup de SCROLL_DERECHA + contador de APLICAR_DESPLAZAMIENTO_LATERAL

A peticion del usuario. Hallazgo: `$EF84` no era una direccion suelta
-- es exactamente `BUFFER_LOSETAS_TRABAJO+4480` (fila 140 del lienzo,
4480/32=140). Corregido a la forma con etiqueta+offset, mismo patron
sistemico de siempre. Pasados a decimal `$0020`->32 (paso de fila,
recuento puro) y `$8C`->140 (contador del bucle externo de
`APLICAR_DESPLAZAMIENTO_LATERAL`, compartido por `SCROLL_IZQUIERDA` y
`SCROLL_DERECHA`). El resto (`$FC00` delta empaquetado con signo,
`$23` constante de ajuste sin confirmar del todo, `$01` flag de
direccion con signo) se quedan en hex, con comentario en cada uno,
consistente con el resto de bloques de scroll.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `BUFFER_LOSETAS_TRABAJO+4480` compila byte-identico a `$EF84`.
`.dsk`/`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py`
no aplica).



### Comentado GESTIONAR_SCROLL completo + bloque de setup de SCROLL_IZQUIERDA

A peticion del usuario. Comentada cada linea de `GESTIONAR_SCROLL`
(lectura de posicion de camara, guardado del parametro de entrada,
las 2 comprobaciones de bits bajos L/H, la cascada final RRA/JP C, y
el RET NC). En el bloque de `SCROLL_IZQUIERDA`, mismo tratamiento que
su gemela `SCROLL_DERECHA`: `$FFE0` -> `-32` (mismo paso de fila que
`SCROLL_DERECHA` pero en sentido inverso, compila identico en
complemento a 2) y `$EFE4` -> `BUFFER_LOSETAS_TRABAJO+4576` (fila 143,
la ultima del lienzo, 4576/32=143) -- corregido a etiqueta+offset,
mismo patron sistemico de siempre. El resto (`$0400` delta, `$00`
constante de ajuste, `$FF` flag de direccion) se quedan en hex con
comentario, igual que en los bloques gemelos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `LD BC,-32` y `BUFFER_LOSETAS_TRABAJO+4576` compilan
byte-identico a `$FFE0`/`$EFE4`. `.dsk`/`.cas` regenerados (sin
cambio de etiquetas, `gen_inventory.py` no aplica).



### SCOPY_A_ENTRY -> COPIAR_LOSETA_FASE_A, SCOPY_B_ENTRY -> COPIAR_LOSETA_FASE_B

A peticion del usuario. Son los 2 puntos de entrada alternativos a
los que salta `STAIL_LOOP` (dentro de `SCROLL_LOSETA_BUFFER_VRAM`)
via `JP (IX)`, elegidos por una prueba de paridad de 1 bit
(`(L_nuevo + C_sombra) XOR D_sombra) AND 1`, usando las constantes de
fase ya comentadas antes). Confirmado: este mecanismo es especifico
del scroll VERTICAL (`SCROLL_ARRIBA`/`SCROLL_ABAJO`) -- el lateral
(`SCROLL_IZQUIERDA`/`SCROLL_DERECHA`) termina en una rutina distinta
(`DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) que nunca pasa por aqui, corrigiendo
una imprecision que tenia `recursos/mapa_memoria.html` ("las 4
confluyen en SCROLL_LOSETA_BUFFER_VRAM"). Diferencia entre las 2
fases: A hace un `EX DE,HL` extra que B no hace -- HIPOTESIS sin
confirmar del todo: compensa una alineacion de byte par/impar al
cruzar el limite de una loseta (16px = 4 pasos de scroll de 4px, pero
la prueba de 1 bit distingue solo 2 posibilidades, no 4). Se
mantienen GLOBALES (no locales) para no repetir la trampa de scoping
ya vista -- las etiquetas `STAIL_DISPATCH`/`STAIL_LOOP`/`STAIL_RESUME`
caen entre medias de la definicion y no se tocaron. Sincronizado
`recursos/mapa_memoria.html` (1 mencion, aprovechando para corregir
la imprecision del parrafo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 638 etiquetas (sin cambio de total, renombrado 1:1).



### STAIL_DISPATCH -> .PREPARAR_BUCLE_LOSETAS (local)

A peticion del usuario. Es el punto de convergencia dentro de
`SCROLL_LOSETA_BUFFER_VRAM` entre las 2 ramas de seleccion de fase
(`JR Z` directo para fase A, caida para fase B): prepara `IY`
(retorno), recupera el puntero (`POP DE`) y arma el contador del
bucle externo (`C`/`B=9`) antes de entrar a `STAIL_LOOP`. Verificado
que solo se referencia desde dentro de `SCROLL_LOSETA_BUFFER_VRAM`,
sin ninguna etiqueta global entre medias -- convertido a local sin
problema de scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 637 etiquetas (baja 1, quirk conocido de global->local).



### Comentado .PREPARAR_BUCLE_LOSETAS, $09 -> 9 (decimal)

A peticion del usuario. Anadido comentario en cada linea del bloque
(punto de retorno para las fases, transferencia de D entre bancos de
registros, recuperacion del puntero de fila, contador del bucle). El
unico recuento puro (`$09`, iteraciones del bucle externo `STAIL_LOOP`
-- 9 losetas) se paso a decimal; el resto son transferencias de
registros/direcciones sin conversion aplicable.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`). `.dsk`/
`.cas` regenerados (sin cambio de etiquetas, `gen_inventory.py` no
aplica).



### Comentada la cabecera de SCROLL_LOSETA_BUFFER_VRAM

A peticion del usuario. Anadido comentario en cada linea del bloque
inicial: cambio de banco de registros, lectura/actualizacion de la
posicion de camara con el flag de direccion, y la prueba de fase de 1
bit (`ADD A,C`/`XOR D`/`AND $01`) que decide `COPIAR_LOSETA_FASE_A`
vs `COPIAR_LOSETA_FASE_B`. Ningun valor era convertible a decimal
(`AND $01` es una mascara de bit). `RES 0,H` se dejo marcado como
proposito sin confirmar.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### STAIL_LOOP -> .BUCLE_LOSETAS (local), STAIL_RESUME -> .CONTINUAR_BUCLE_LOSETAS (local)

A peticion del usuario. `.BUCLE_LOSETAS` es el inicio del bucle de 9
losetas dentro de `SCROLL_LOSETA_BUFFER_VRAM`: por cada una, calcula
su direccion grafica (`MAPEAR_LOSETA_A_GRAFICO`) y despacha a la fase
elegida (`JP (IX)`). `.CONTINUAR_BUCLE_LOSETAS` es donde vuelve esa
fase al terminar (`JP (IY)`): deshace el intercambio DE/HL, avanza el
indice en el banco alternativo (+4) y repite (`DJNZ`) hasta agotar el
contador; al salir, recarga `PARAMETRO_DESPLAZAMIENTO_SCROLL` en `DE`
y `RET`. Misma trampa de scoping de siempre al renombrar
`STAIL_RESUME` (con `STAIL_LOOP` global entre medias) -- solucionado
convirtiendo tambien `STAIL_LOOP` a local. Verificado que ambos solo
se referencian entre si dentro de `SCROLL_LOSETA_BUFFER_VRAM`.

**Verificado**: recompilado sin errores (tras el ajuste de scoping),
diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 635 etiquetas (baja 2, dos
conversiones global->local).



### SCOPY_A -> .BUCLE_COPIAR_LOSETA_FASE_A (local), SCOPY_B -> .BUCLE_COPIAR_LOSETA_FASE_B (local)

A peticion del usuario. Son los bucles internos (4 vueltas cada uno)
dentro de `COPIAR_LOSETA_FASE_A`/`COPIAR_LOSETA_FASE_B`: el cuerpo
real que copia los bytes de la loseta nueva. `.BUCLE_COPIAR_LOSETA_FASE_A`
hace 4x4=16 `LDI` (copia directa, paso de fila `B=32` entre cada uno,
16 bytes = loseta de 16x16px). `.BUCLE_COPIAR_LOSETA_FASE_B` hace el
mismo numero de vueltas pero con `LD A,(DE)` + 4x `RRCA` + `AND C` +
`OR (HL)` + `LD (HL),A` -- un mezclado a nivel de nibble con el
contenido ya existente, en vez de copia directa, consistente con la
hipotesis de que la fase B compensa un desalineamiento de byte que la
fase A no tiene. Verificado que ambos solo se referencian dentro de
su rutina respectiva -- convertidos a locales sin problema de
scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 633 etiquetas (baja 2, dos conversiones global->local).



### Comentado y convertido a decimal el bloque completo de .BUCLE_LOSETAS/COPIAR_LOSETA_FASE_A/B

A peticion del usuario. Pasados a decimal los recuentos puros: `$04`
(paso de avance de indice, y contador de vueltas de ambas fases) ->
`4`; `$20` (paso entre filas de origen) -> `32`; `$00` en `ADC A,$00`
(propagacion de acarreo, x2) -> `0`. Se dejo en hex `$FF` (mascara
usada con `AND C`). Anadido comentario en cada linea con valor o
proposito relevante; dado que `COPIAR_LOSETA_FASE_B` repite 4 veces
un grupo identico de 13 instrucciones, se comento solo la primera
aparicion de cada patron repetido en vez de las 4 por separado.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados (sin cambio de
etiquetas, `gen_inventory.py` no aplica).



### TAC_TAIL -> .RESTAURAR_Y_SALIR (local)

A peticion del usuario. Es el epilogo comun de
`MAPEAR_LOSETA_A_GRAFICO`: desapila los 4 registros guardados al
principio (`HL`/`BC`/`DE`/`AF`) y retorna. Se llega tanto por salto
directo (bit 7 de B a cero) como por caida (bit 7 a uno, tras
escribir en `TABLA_TIPOS_LOSETA`). Hallazgo de paso: un `AND $00`
justo antes anula por completo la lectura de `(HL)`, vestigio
probable de una comprobacion mas compleja simplificada en algun
momento -- documentado en el codigo. Verificado que solo se
referencia desde dentro de `MAPEAR_LOSETA_A_GRAFICO` -- convertido a
local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 632 etiquetas (baja 1, quirk conocido de global->local).



### Comentado y convertido a decimal MAPEAR_LOSETA_A_GRAFICO completo; $B940 -> TILE_GFX

A peticion del usuario. Hallazgo: `$B940` (base sumada a la direccion
grafica calculada) ya tenia etiqueta real (`TILE_GFX`) sin sustituir
-- mismo patron sistemico de siempre. Pasados a decimal los valores
que no eran mascaras: `LD L,$00`->`0` (semilla del calculo de indice,
no direccion), `LD A,$02`->`2` (valor de estado/modo escrito en
`$8435`), `ADC A,$00`->`0` (propagacion de acarreo), `LD B,$10`->`16`.
Hallazgo curioso sobre este ultimo: `B` no se vuelve a leer entre esa
asignacion y el `POP BC` final de `.RESTAURAR_Y_SALIR` -- parece no
tener ningun efecto observable (similar en espiritu a los parametros
sin efecto de `FUNCION_INHABIL`, documentado en el codigo).
Anadido comentario en cada linea. Las mascaras (`$7C` x2, `$7F`,
`$03`, `$3F`, `$80`, `$00` en el `AND` degenerado ya documentado)
se quedaron en hex.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `TILE_GFX` compila byte-identico a `$B940`. `.dsk`/`.cas`
regenerados (sin cambio de etiquetas, `gen_inventory.py` no aplica).



### JS9_LOOP1 -> .BUCLE_REDIBUJADO_CAMARA (local)

A peticion del usuario. Es el bucle principal de
`REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`: 36 vueltas (`B=$24`), una
por cada franja de la camara, para el redibujado TOTAL (no
incremental) -- llama a `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM` por vuelta
y avanza los punteros de destino (128 bytes) y de banco alternativo
(`INC H`). Verificado que solo se referencia dentro de la misma
rutina (mas 2 menciones en comentarios, tambien sincronizadas) --
convertido a local sin problema de scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 631 etiquetas (baja 1, quirk conocido de global->local).



### JS9_LOOP2 -> .BUCLE_ICONOS_VIDA (local)

A peticion del usuario. Dibuja el icono de vida una vez por cada vida
restante (`B=VIDAS_RESTANTES`): 2 bandas de 16 bytes por icono
(`CALL JS9_ROWFLIP` x2) y avanza 24px (`$18`) entre iconos. Verificado
que solo se referencia dentro de la misma rutina (mas 2 menciones en
comentarios, sincronizadas) -- convertido a local sin problema de
scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 630 etiquetas (baja 1, quirk conocido de global->local).



### JS9_ROWFLIP -> LDIRVM_INVERTIDO

A peticion del usuario. Vuelca BC bytes desde HL a VRAM (destino DE,
via SETVRAM) invirtiendo cada byte (CPL) antes de escribirlo -- una
variante invertida de LDIRVM, mismo "modo invertido" que usa TEXT_BLIT
en otro sitio (sin confirmar la razon exacta: reutilizacion de datos
graficos con 2 apariencias, o efecto visual deliberado). Se queda
global (sigue el mismo patron que FILVRM/LDIRVM/SETVRAM, la "API de
VDP"). Renombrada tambien `JS9_ROWFLIP_LOOP` -> `LDIRVM_INVERTIDO_LOOP`
(capturada por el mismo reemplazo, sin problema de scoping ya que es
su unica referencia). Sincronizados los comentarios que decian
"modo negado" -> "modo invertido" para consistencia terminologica.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 630 etiquetas (sin cambio de total, renombrado 1:1).



### Comentado y convertido a decimal el resto de REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM, MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA y CONSULTAR_TIPO_LOSETA

A peticion del usuario. Hallazgo: `$8DE9` ya tenia etiqueta real
(`SCORE_DIGIT_BUFFER`) sin sustituir -- mismo patron sistemico de
siempre; tambien `$8DEA` -> `SCORE_DIGIT_BUFFER+1`. Confirmado que
`LD D,$16`/`LD E,$48` (en `.BUCLE_ICONOS_VIDA`) forman la misma
direccion VRAM `$1648` usada justo antes para el relleno con `FILVRM`
-- el relleno prepara la zona donde luego se dibujan los iconos.
Pasados a decimal los recuentos puros: `$24`->`36` (franjas de
camara), `$0080`->`128` (paso de destino), `$0060`->`96` (x2,
relleno FILVRM), `$0010`->`16` (x2, bandas de icono), `$18`->`24`
(paso horizontal entre iconos), `$0005`->`5` (copia de digitos),
`$00` en `ADC A,$00` (x2, en `CONSULTAR_TIPO_LOSETA`) ->`0`.
`LD HL,$0000` (parametro de `DIBUJAR_MARCADOR_PUNTOS`) ->`0`. Se
dejaron en hex las direcciones (`$1648`, `$92C3`, `$FC50`) y las
mascaras (`AND $7C` x2, `AND $7F`, `AND $1F`, `LD A,$FF`/`LD (HL),$30`
como valores de byte, no recuentos). Anadido comentario en cada linea
relevante de las 3 rutinas.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `SCORE_DIGIT_BUFFER`/`SCORE_DIGIT_BUFFER+1` compilan
byte-identico a `$8DE9`/`$8DEA`. `.dsk`/`.cas` regenerados (sin
cambio de etiquetas, `gen_inventory.py` no aplica).



### QUEUE_PUSH -> APILAR_PETICION_REDIBUJADO

A peticion del usuario. Apila una entrada (C,B,A) en la cola circular
de redibujado diferido ($8D61-$8D6F, centinela $FF) via el puntero de
escritura $8D5F. Se queda global -- confirmado que la llaman 2 sitios
reales en `madmix_scr_body.asm` (HNDLR_MARICOCO/HNDLR_REGPUNANTOSO,
al regenerar una bolita ya comida). Renombrada para usar la misma
terminologia en espanol que su contraparte `VACIAR_COLA_REDIBUJADO`.
Sincronizada en `madmix1_body.asm` (definicion + 2 menciones en
comentarios) y `madmix_scr_body.asm` (2 llamadas + 2 menciones en
comentarios).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 630 etiquetas (sin cambio de total, renombrado 1:1).



### QIC_LOOP -> .BUCLE_VACIAR_COLA (local), QUEUE_POP_DISPATCH -> .DESPACHAR_ENTRADA_COLA (local)

A peticion del usuario. `.BUCLE_VACIAR_COLA` recorre la cola circular
de redibujado desde `$8D61` hasta el centinela `$FF`, reiniciando el
puntero de escritura al llegar al final. `.DESPACHAR_ENTRADA_COLA` es
donde cae si hay una entrada real: interpreta los siguientes 3 bytes
como `(C,B,A)` y llama a `REDIBUJAR_LOSETA_BUFFER_VRAM`. Misma trampa
de scoping de siempre al renombrar el bucle externo (`QUEUE_POP_DISPATCH`
global entre medias) -- solucionado convirtiendo tambien este a local.
Sincronizados `src/FLUJO_PROGRAMA.md` y `recursos/mapa_memoria.html`
(esta ultima tambien aprovechada para corregir una mencion suelta de
`QUEUE_PUSH` que se habia escapado en la ronda anterior).

**Verificado**: recompilado sin errores (tras el ajuste de scoping),
diffs en la linea base exacta de siempre (7/2). `.dsk`/`.cas`
regenerados. Inventario HTML regenerado: 628 etiquetas (baja 2, dos
conversiones global->local).



### RS_LOOP -> .BUCLE_FILA_LOSETA (local)

A peticion del usuario. Es el bucle principal de
`REDIBUJAR_LOSETA_BUFFER_VRAM` ("RS" era un resto del nombre antiguo
`REDRAW_STRIP`, ya renombrada): 16 filas, copiando 2 bytes por fila
(`LDI` x2 desde `TILE_GFX`) y avanzando el destino 30 bytes (que
sumados a los 2 ya copiados dan 32, el ancho de fila del lienzo).
Verificado que solo se referencia dentro de la misma rutina --
convertido a local.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 627 etiquetas (baja 1, quirk conocido de global->local).



### Comentado y convertido a decimal APILAR_PETICION_REDIBUJADO/VACIAR_COLA_REDIBUJADO/REDIBUJAR_LOSETA_BUFFER_VRAM; $B940 -> TILE_GFX

A peticion del usuario. Hallazgo: `$B940` (base grafica de losetas)
otra vez sin sustituir por la etiqueta real `TILE_GFX` -- mismo
patron sistemico visto ya varias veces en esta sesion. Pasados a
decimal los recuentos puros: `LD L,$00`->`0` (semilla de calculo,
no direccion), `LD B,$10`->`16` (filas de la loseta), `LD BC,$001E`->`30`
(paso de destino). Se dejaron en hex las direcciones/punteros de la
cola (`$8D5F`, `$8D61`), el centinela `$FF` y las mascaras (`AND $03`,
`AND $02`, `AND $7F`). Anadido comentario en cada linea relevante de
las 3 rutinas.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) -- confirma
que `TILE_GFX` compila byte-identico a `$B940`. `.dsk`/`.cas`
regenerados (sin cambio de etiquetas, `gen_inventory.py` no aplica).



### SCORE_DIGIT_BUFFER -> BUFFER_DIGITOS_PUNTUACION

A peticion del usuario. Buffer de 7 bytes (`"000000",$FF`) donde
`DIBUJAR_MARCADOR_PUNTOS_DIGITOS` escribe la puntuacion convertida a
digitos ASCII, que `TEXT_BLIT` dibuja despues en `$16B0`. Traducido a
espanol (nombre en ingles, inconsistente con el resto del proyecto).
Renombrada en `madmix1_body.asm` (8 menciones). `src/README.md` linea
614 se dejo sin tocar -- parrafo de historial de sesion ya congelado
(checklist con tachado).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 627 etiquetas (sin cambio de total, renombrado 1:1).



### TEXT_BLIT -> DIBUJAR_TEXTO_INVERTIDO_VRAM

A peticion del usuario. Dibuja una cadena de texto (formato lista de
codigos terminada en $FF) volcando cada glifo a VRAM invertido (CPL),
mismo mecanismo que LDIRVM_INVERTIDO -- de ahi el nombre. Se evito el
nombre `DIBUJAR_TEXTO_VRAM` por colisionar con una rutina YA existente
y distinta en `madmix_scr_body.asm` (renombrada de `TAIL_DECODE` en
una sesion anterior). Renombrada en `madmix1_body.asm` (9 menciones,
incluye la sub-etiqueta `TEXT_BLIT_LOOP` -> `DIBUJAR_TEXTO_INVERTIDO_VRAM_LOOP`
capturada por el mismo reemplazo), `src/README.md` (1 mencion) y
`recursos/mapa_memoria.html` (1 mencion).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 627 etiquetas (sin cambio de total, renombrado 1:1).



### Comentado DIBUJAR_MARCADOR_PUNTOS

A peticion del usuario. Ningun valor era convertible a decimal (el
`10000` ya estaba en decimal; `$16B0`/`$60CA` son direcciones).
Anadido comentario en cada linea explicando la logica: flag de modo
demo, suma del delta a la puntuacion, comparacion contra el umbral
del premio "BESTIA", y conversion a digitos ASCII. Cambio de solo
comentarios, cero cambio de bytes.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios). `.dsk`/`.cas` regenerados.



### SCORE_DIVISORS -> DIVISORES_PUNTUACION

A peticion del usuario. Tabla de 3 divisores de 16 bits (1000, 100,
10) usada por `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` para extraer los
primeros 3 digitos de la puntuacion por resta repetida (el ultimo
digito sale directo del resto). Traducido a espanol, mismo patron que
`BUFFER_DIGITOS_PUNTUACION`. Renombrada solo en `madmix1_body.asm` (2
menciones) -- sin menciones en otros ficheros vivos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 627 etiquetas (sin cambio de total, renombrado 1:1).



### SDD_LOOP -> .BUCLE_DIVISORES (local), SDD_INNER -> .BUCLE_RESTA_DIGITO (local)

A peticion del usuario. `.BUCLE_DIVISORES` recorre los divisores
(1000, 100, 10) de `DIVISORES_PUNTUACION`, llamando a
`.BUCLE_RESTA_DIGITO` para extraer cada digito por resta repetida
(sale del bucle tras procesar el divisor 10, dejando el ultimo digito
directo en el resto). `.BUCLE_RESTA_DIGITO` es el algoritmo clasico
de extraccion de digito por resta repetida: cuenta cuantas veces se
puede restar el divisor sin acarreo negativo. Verificado que ambas
solo se referencian dentro de `DIBUJAR_MARCADOR_PUNTOS_DIGITOS` --
convertidas a locales sin problema de scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 625 etiquetas (baja 2, dos conversiones global->local).



### SDD_EMIT_DIGIT -> .EMITIR_DIGITO (local)

A peticion del usuario. Convierte un digito (A, 0-9) a caracter ASCII
(+$30) y lo escribe en la siguiente posicion libre de
`BUFFER_DIGITOS_PUNTUACION`, avanzando el puntero guardado en el
banco alternativo de registros. Llamada desde 2 sitios dentro de
`DIBUJAR_MARCADOR_PUNTOS_DIGITOS`. Verificado que solo se referencia
dentro de esa rutina -- convertida a local sin problema de scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 624 etiquetas (baja 1, quirk conocido de global->local).



### Comentado y convertido a decimal DIBUJAR_MARCADOR_PUNTOS_DIGITOS/.EMITIR_DIGITO

A peticion del usuario. Pasados a decimal los valores que no eran
direcciones ni mascaras: `LD DE,$0000`->`0` (offset inicial, no
direccion) y `CP $0A`->`CP 10` (comparacion contra el ultimo divisor,
10). Se dejo en hex `ADD A,$30` (constante de conversion a ASCII,
"+$30" ya documentado asi en el comentario de cabecera). Anadido
comentario en cada linea explicando el algoritmo de extraccion de
digitos por resta repetida y el manejo de los bancos de registros
(EXX) para el puntero destino.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2, solo comentarios/decimal). `.dsk`/`.cas`
regenerados.



### TB_OUTER -> .BUCLE_FILAS_CARACTER (local), TB_ROW -> .DIBUJAR_FILA_CARACTER (local), TB_NEXTCOL -> .FIN_FILA (local)

A peticion del usuario. Dentro de `DIBUJAR_TEXTO_INVERTIDO_VRAM`:
`.BUCLE_FILAS_CARACTER` es el bucle externo (8 vueltas, una por fila
del caracter de 8x8). `.DIBUJAR_FILA_CARACTER` es el codigo que lee
el byte de fuente, lo invierte (CPL) y lo escribe 2 veces a VRAM en
posiciones consecutivas -- hallazgo: nunca se salta ahi con JP/JR, es
codigo en linea sin ser realmente un bucle propio, pese a tener
etiqueta. `.FIN_FILA` es el punto de convergencia antes del DJNZ,
tras decidir si hace falta "envolver" a la siguiente franja de VRAM
(reparto en tercios de la tabla de patrones SCREEN2, mecanismo exacto
sin confirmar del todo). Verificado que las 3 solo se referencian
entre si dentro de la misma rutina -- convertidas a locales sin
problema de scoping.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados. Inventario HTML
regenerado: 621 etiquetas (baja 3, tres conversiones global->local).



### Comentado y convertido a decimal DIBUJAR_TEXTO_INVERTIDO_VRAM completo

A peticion del usuario. Pasados a decimal los recuentos puros: `LD
H,$00`->`0` (extension de codigo a 16 bits), `LD B,$08`->`8`
(contador de filas), `SUB $08`->`8` y `ADD A,$08`->`8` (pasos de
columna, x2). Se dejaron en hex `CP $FF` (centinela), `AND $06`
(mascara) y `LD BC,$935B` (direccion -- sin etiqueta exacta, cae 8
bytes antes de `FONT_TABLE_9363`, documentado en el comentario).
Anadido comentario en cada linea explicando el calculo de direccion
de glifo, el volcado invertido por fila, y la logica de "envolver" de
franja VRAM.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados (sin cambio de
etiquetas, `gen_inventory.py` no aplica).


### Barrido final de etiquetas en ingles en madmix1_body.asm

A peticion del usuario, auditadas TODAS las etiquetas (globales y
locales) de `madmix1_body.asm` en busca de nombres todavia en ingles.
Aplicado en un unico lote (~40 renombrados) tras aprobacion explicita
del usuario ("aplicalo todo"), siguiendo las convenciones ya fijadas
en la sesion y, donde existia, el nombre descriptivo ya usado en los
ficheros de datos correspondientes (`src/data/sound/*.spt`/`*.snd`):

- Graficos/HUD: `TILE_GFX` -> `GRAFICOS_LOSETAS`; `PATTERN_TAIL_92C3`
  -> `ICONO_VIDA_EXTRA`; `FONT_TABLE_9363` -> `TABLA_FUENTE_CARACTERES`.
- Driver de sonido PSG (tablas): `MISC_FLAGS_CA5D` ->
  `FLAGS_ENVOLVENTE_COMPARTIDA_PSG`; `SUBPATTERN_RETURN_TABLE_CA61` ->
  `TABLA_RETORNO_SUBPATRONES_PSG`; `TRANSPOSE_TABLE_CA67` ->
  `TABLA_TRANSPOSICION_PSG`.
- Los 13 subpatrones de bytecode PSG (`SUBPATTERN_xxxx` por direccion)
  renombrados a `SUBPATRON_NN_HHHH` (numero de entrada con cero a la
  izquierda + sufijo hexadecimal), calcando exactamente el nombre ya
  usado por los ficheros `.spt` de `src/data/sound/spt/`.
- Los 3 punteros de guion instalados por `INICIO`
  (`SOUND_SCRIPT_MELODIA_CANAL_0/1/2` -> `GUION_MELODIA_CANAL_0/1/2`)
  y los 15 guiones de eventos de sonido (`SOUND_EVTxx_...` ->
  `GUION_EVTxx_...`, conservando el descriptor ya existente en cada
  nombre: trampilla, disparo de avion, pista, bola clavada, etc.).
- Los 10 guiones de modo demo: `DEMO_SCRIPT_NIVEL1/2/4/5` ->
  `GUION_DEMO_NIVEL1/2/4/5`; `DEMO_SCRIPT_SINREF_1..6` ->
  `GUION_DEMO_SINREF_1..6`.
- `SLOT_RESTART_DD82` -> `REINICIO_SLOT_DD82`; `BESTIA_TEXT` ->
  `TEXTO_BESTIA`; `DEMO_TEXT` -> `TEXTO_DEMO`.

De paso, sincronizados varios sitios que habian quedado desfasados de
rondas ANTERIORES de renombrado (encontrados durante el barrido de
`recursos/mapa_memoria.html`): una mencion suelta a `QUEUE_PUSH` (ya
renombrada a `APILAR_PETICION_REDIBUJADO` en una ronda previa) en la
descripcion de `REDIBUJAR_LOSETA_BUFFER_VRAM`.

**Verificado**: recompilado sin errores (9676 lineas), diffs en la
linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).
`recursos/flujo_programa.html` regenerado (recompilando primero
`main.lst`, antes de `gen_inventory.py`, para evitar leer datos
obsoletos): 621 etiquetas (funcion=102 interna=244 dato=242 sinref=33).
`.dsk`/`.cas` regenerados sin incidencias. Sincronizados tambien
`src/FLUJO_PROGRAMA.md` (`SOUND_SCRIPT_2_CE0C` -> `GUION_MELODIA_CANAL_2`,
confirmado por direccion `$CE0C`; `BESTIA_TEXT`/`DEMO_TEXT` ->
`TEXTO_BESTIA`/`TEXTO_DEMO`), `recursos/mapa_memoria.html` (varias
entradas del array `SEGMENTS`) y `recursos/graficos.html` (variable
JS `TILE_GFX` -> `GRAFICOS_LOSETAS`, incluido su `.forEach`, por
consistencia con la nueva etiqueta aunque sea codigo cliente y no
prosa). Las menciones a nombres antiguos dentro de narrativa historica
congelada de `src/README.md` (parrafos en pasado sobre hallazgos de
sesiones anteriores: `DEMO_SCRIPT_NIVEL1`, `SLOT_RESTART_DD82`,
`TILE_GFX`) se dejan intactas a proposito, siguiendo el criterio ya
establecido en esta sesion de no reescribir retroactivamente relatos
de descubrimiento pasados.


### MOTOR_ACTORES / DIBUJAR_FILA_DESPLAZADA_DERECHA/IZQUIERDA: datos revisados

A peticion del usuario, revisados todos los literales numericos del
cuerpo completo de `MOTOR_ACTORES` (0x8440) y de sus dos rutinas de
dibujado sub-pixel `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`_IZQUIERDA`,
convirtiendo a decimal los que son limites/conteos/pasos puros y
anadiendo un comentario a cada literal y a los bloques logicos mas
relevantes:

- Las 4 guardas de entrada, ya resumidas en la cabecera de la rutina
  como "$0A/$40/$04/$74": `CP $0A` -> `CP 10` (maximo de actores
  activos simultaneos, coincide con `$8437`, ver `RESET_CONTADOR_ACTORES`);
  `CP $40` -> `CP 64` (numero de entradas de `PTR_TABLA_SPRITES`,
  limite de indice de sprite valido); `CP $04` -> `CP 4` y
  `CP $74` -> `CP 116` (limites de columna visible minima/maxima).
  Actualizada tambien la cabecera de la rutina (linea ~46) para
  citarlos en decimal y mantenerla consistente con el codigo, ya
  que es documentacion viva de esta misma rutina (no un relato
  historico congelado).
- `LD (HL), $90`/`LD (HL), $B0` -> `144`/`176`: dos limites de
  recorte vertical de camara seleccionados segun el bit 5 de A: no
  se ha logrado confirmar su significado exacto (documentado como
  hipotesis sin cerrar, igual que otros valores "mitad" ya vistos
  en la rutina).
- `ADD A, $10` -> `ADD A, 16`: compensacion fija de filas antes de
  llamar a `CALCULAR_DIRECCION_MASCARA_ACTOR` (proposito exacto sin
  confirmar, posible candidato a franja reservada en la parte
  superior de pantalla).
- `LD A, $03` -> `LD A, 3`: constante fija que se guarda en `$8435`
  sin uso identificado en el resto del codigo transcrito (sin
  confirmar).
- Los 3 `LD BC, $0020` (uno en `MEZCLAR_Y_AVANZAR_FILA_ACTOR`, uno
  en cada rutina de dibujado) -> `LD BC, 32`: paso de fila en
  VRAM/buffer, mismo patron ya usado en el resto del motor de
  losetas.
- Se ha dejado en hexadecimal todo lo demas segun la convencion ya
  establecida: direcciones (`$843E`, `$92E3`, `$8433`, `$0500`,
  etc.), mascaras de bits (`AND $F8`/`$07`/`$C0`/`$80`/`$40`) y los
  desplazamientos `(IX+$NN)` de los campos del registro de actor de
  12 bytes (offsets de estructura, estilo ya uniforme en todo el
  fichero).
- Anadidos comentarios de campo a cada escritura/lectura de
  `(IX+$NN)` (posicion, direccion de mascara, contador de filas,
  cursor, mascara de recorte de borde) resumiendo el mapeo ya descrito
  en la cabecera de la rutina, y comentarios de bloque en las dos
  rutinas de dibujado sub-pixel (bucle de desplazamiento bit a bit,
  mezcla AND/OR contra el fondo, avance de fila, repeticion para la
  segunda fila del par).

**Verificado**: recompilado sin errores (9676 lineas), diffs en la
linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).
Cambio puramente de notacion/comentarios, ninguna etiqueta nueva ni
renombrada -- no ha hecho falta regenerar inventario ni `.dsk`/`.cas`.


### CAPTURAR_MASCARAS_ACTOR y familia (0x8687-0x87FF): datos revisados

Continuacion del mismo barrido de datos/comentarios sobre el resto del
bloque de `MOTOR_ACTORES`: `CAPTURAR_MASCARAS_ACTOR`,
`CONTINUAR_CAPTURA_MASCARAS_ACTORES`, `INVERTIR_BITS_PATRON_ACTOR`,
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` y `COMPONER_ACTORES_EN_BUFFER`.

- `LD BC, $00FF` (aparece 2 veces, una en cada rutina de captura):
  dejado en hexadecimal a proposito, no es un simple contador --
  C=$FF es un valor "de seguridad" para que los 3 `DEC` implicitos
  de las `LDI` que siguen no hagan borrow hacia B (B debe quedarse
  en 0 para que el `ADD HL,BC` posterior de +29 funcione). Anadido
  comentario explicandolo.
- `LD C, $1D` (4 apariciones) -> `LD C, 29`: junto a los 3 bytes ya
  copiados por las `LDI` suma exactamente 32, el paso de fila ya
  documentado en la cabecera de `MOTOR_ACTORES` ("3 bytes de cada
  bloque de 32").
- `LD DE, $FFF4` en `CONTINUAR_CAPTURA_MASCARAS_ACTORES`: dejado en
  hexadecimal (delta con signo, ya cubierto por la convencion), pero
  anadido comentario aclarando que equivale a -12 (retrocede un
  registro de actor completo).
- `LD B, $30` en `INVERTIR_BITS_PATRON_ACTOR` -> `LD B, 48`: tope de
  bloques del bucle externo (limite superior, el contador real de
  bytes por bloque lo da `($8435)`).
- En `COMPONER_ACTORES_EN_BUFFER`: `ADD A, $20` -> `ADD A, 32` (mismo
  paso de fila que en el resto del motor) y `SUB $08` -> `SUB 8`
  (compensa las 3 filas ya sumadas via H, volviendo a la base del
  bloque de 8). `LD DE, $000A` -> `LD DE, 10`: HALLAZGO -- esta
  rutina avanza el puntero IX SOLO 10 bytes por actor, no 12 como
  hace `MOTOR_ACTORES`/`CONTINUAR_CAPTURA_MASCARAS_ACTORES` sobre el
  mismo array. Discrepancia documentada tal cual, sin resolver;
  encaja con que esta rutina sigue sin tener ningun llamador
  confirmado en el codigo ya transcrito (ver cabecera de la funcion
  y FINDINGS.md), lo que podria explicar por que un desajuste asi
  nunca se manifesto en el juego real.
- Anadidos comentarios de campo (que hace cada `(IX+$NN)`, que
  registro guarda cada bloque de mascaras "ida y vuelta") y de flujo
  (bucle de convergencia de `INVERTIR_ORDEN_BYTES_PATRON_ACTOR`,
  auto-modificacion de operandos en `COMPONER_ACTORES_EN_BUFFER`) sin
  tocar direcciones, mascaras de bits ni offsets de estructura, que
  se dejan en hexadecimal por la misma convencion de siempre.

**Verificado**: recompilado sin errores (9678 lineas), diffs en la
linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).
Cambio puramente de notacion/comentarios, ninguna etiqueta nueva ni
renombrada -- no ha hecho falta regenerar inventario ni `.dsk`/`.cas`.


### API de VRAM (FILVRM/LDIRVM/SETVRAM) y vecinas: datos revisados

Ultima tanda del mismo barrido: `FILVRM`, `LDIRVM`, `SETVRAM`
(equivalentes a las rutinas homonimas de la BIOS de MSX),
`CONSULTAR_COLOR_VDP`, `CALCULAR_DIRECCION_MASCARA_ACTOR`,
`RESET_CONTADOR_ACTORES` y `WAIT_VBLANK`.

A diferencia de las tandas anteriores, aqui no habia practicamente
ningun literal candidato a decimal: son rutinas de bajo nivel del
VDP, y todos sus valores son puertos ($98/$99), mascaras de bits
(`AND $3F`/`OR $40` del comando SETWRT, `AND $78`/`OR $10` de
`CONSULTAR_COLOR_VDP`) o la propia direccion base `$DC00` -- los
tres casos que la convencion de esta sesion mantiene siempre en
hexadecimal. `TABLA_COLORES_VDP` tampoco se toca: son codigos de
color VDP (0-15), naturalmente hexadecimales por como se extraen
(nibbles). Limitado por tanto a anadir comentarios por instruccion:
que hace cada `OUT`/`CALL SETVRAM` en las 3 rutinas de VRAM, el
significado de `AND $3F`/`OR $40` (dos bits de comando "fijar
puntero de escritura" del VDP), el aislamiento/rotacion de bits en
`CONSULTAR_COLOR_VDP`, y en `WAIT_VBLANK` una nota cruzando con
`GESTIONAR_FRAME` (confirmado leyendo su codigo, linea ~903): es esa
rutina, no la ISR en si, la que pone `FRAME_FLAG` de vuelta a 0 al
procesar el frame.

**Verificado**: recompilado sin errores (9678 lineas), diffs en la
linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`).
Cambio puramente de comentarios, ningun literal convertido, ninguna
etiqueta nueva ni renombrada -- no ha hecho falta regenerar
inventario ni `.dsk`/`.cas`.


### CAPTURAR_MASCARAS_ACTOR y familia, parte 2: driver PSG completo (INSTALAR_RECURSO_SONIDO .. VOLCAR_REGISTROS_PSG)

A peticion del usuario ("haz lo mismo con el resto de datos desde la
linea 3392 hasta el final del fichero"), revisado el resto completo
de `madmix1_body.asm`: todo el CODIGO del driver de sonido PSG
(`INSTALAR_RECURSO_SONIDO`, `INSTALAR_RECURSO_SONIDO_EN_A`,
`LIMPIAR_E_INSTALAR_RANURA`, `TICK_REPRODUCTOR_PSG`/`PROCESAR_CANAL_PSG`/
`DESPACHAR_COMANDO_PSG` con los 15 cuerpos de comando sin etiqueta
propia, `APLICAR_ENVOLVENTES_CANAL`, `APLICAR_ENVOLVENTE_RUIDO`,
`REINICIAR_ENVOLVENTE_VOLUMEN/TONO/RUIDO`, `ACTUALIZAR_MEZCLADOR_CANAL`,
`OBTENER_PUNTERO_TRANSPOSICION`, `MULTIPLICAR_8X16`, `DIVIDIR_16X16`,
`LEER_PALABRA_INDEXADA`, `VOLCAR_REGISTROS_PSG`) y el tramo final
(`REINICIO_SLOT_DD82`, `CONFIGURAR_Y_LEER_JOYSTICK_PSG`). Las tablas de
datos puras (0xC8DE-0xDDA0: notas, comandos, instrumentos, envolventes,
subpatrones, guiones de sonido/demo, niveles 13/14, marco de caramelo)
ya estaban bien documentadas de rondas anteriores (`TABLA_NOTAS_PSG` ya
tenia el equivalente decimal por nota) y no necesitaban cambios --
son bytes con signo/empaquetados (formato de instrumento) o datos via
`INCBIN`, coherente con la convencion de dejarlos en hexadecimal.

- Contadores de bucle puros convertidos a decimal: `LD D,2`/`LD D,3`
  (fases de volumen/tono de la envolvente, coinciden exactamente con
  el formato de instrumento ya documentado: 2 repeticiones de volumen,
  3 de tono), `LD B,3` (3 canales), `LD D,3`->`LD D,3` en
  `INSTALAR_RECURSO_SONIDO` (3 ranuras), `LD B,8`/`LD B,16` en
  `MULTIPLICAR_8X16`/`DIVIDIR_16X16`, `LD D,11` en
  `VOLCAR_REGISTROS_PSG` (11 registros del PSG), `LD A,14` en
  `CONFIGURAR_Y_LEER_JOYSTICK_PSG` (registro del PSG que lee el
  joystick).
- Tamanos/pasos puros convertidos: `46` (tamano de ranura de canal,
  4 sitios), `10` (bytes de `TABLA_ENVOLVENTE_RUIDO_PSG`), `15`
  (tamano de instrumento), `6` (tamano de forma de envolvente), `16`
  y `3000` (multiplicador/divisor de `SET_TEMPO`, sin verificar el
  porque de `3000` en concreto).
- Dejados en hexadecimal (mascaras/centinelas, convencion de
  siempre): `AND $09`/`$1F`/`$0F` (mascaras), `CP $80`/`SUB $80`
  (marca de formato del bytecode, comando vs nota), `$09` en
  `ACTUALIZAR_MEZCLADOR_CANAL` (NO es un contador pese a parecerlo --
  es un patron de bits bit0+bit3 que se desplaza con `SLA`, verificado
  con cuidado antes de descartar la conversion), y `LD BC,$00FF`/
  `LD DE,$FFF4` en la familia `CAPTURAR_MASCARAS_ACTOR` (ya
  documentados en la ronda anterior).
- HALLAZGO de "hex sin sustituir por etiqueta ya existente" (mismo
  patron sistemico de rondas anteriores): 5 usos de `($CA5D)` ->
  `(FLAGS_ENVOLVENTE_COMPARTIDA_PSG)`, 2 usos de `$CA61` ->
  `TABLA_RETORNO_SUBPATRONES_PSG`, 1 uso de `$CA67` ->
  `TABLA_TRANSPOSICION_PSG`. Ademas, 2 offsets dentro de zonas ya
  etiquetadas pasados a aritmetica `ETIQUETA+N` (mismo patron que
  `BUFFER_LOSETAS_TRABAJO+23` de una ronda anterior): `$CA60` ->
  `FLAGS_ENVOLVENTE_COMPARTIDA_PSG+3`, `$CA5F` -> `+2` (via la misma
  base), `$CA5E` -> `+1`, y `$CA54` -> `TABLA_ENVOLVENTE_RUIDO_PSG+1`.
- Identificados con confianza (por coincidencia exacta de los campos
  que tocan con la descripcion ya existente en la tabla
  `TABLA_COMANDOS_PSG`) los 15 cuerpos de comando sin etiqueta propia
  del bytecode PSG, y anadido un comentario de una linea a cada uno
  con su nombre/numero de comando (`SET_VOLUME`, `SET_MIXER`, `LOOP`,
  `SET_DURATION`, `HOLD`, `SET_TEMPO`, `SET_DURATION_MULTI`,
  `SET_INSTRUMENT`, `SET_ENVELOPE`, `SET_ENVELOPE_SHAPE`, `SET_FLAGS`,
  `RESET_SHARED_ENVELOPE`, `CALL_SUBPATTERN`, `RETURN_SUBPATTERN`,
  `SET_CHANNEL_STATE`) -- ninguno llevaba etiqueta en el original
  porque `DESPACHAR_COMANDO_PSG` salta a ellos por `JP (HL)` indexando
  `TABLA_COMANDOS_PSG`, no por nombre.

**Verificado**: recompilado sin errores (9686 lineas), diffs en la
linea base exacta de siempre (7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`) --
confirma que las 8 sustituciones de hex por etiqueta/aritmetica
`ETIQUETA+N` resuelven a las mismas direcciones exactas que el hex
original. Cambio puramente de notacion/comentarios/etiquetas
existentes, ninguna etiqueta nueva ni renombrada -- no ha hecho falta
regenerar inventario ni `.dsk`/`.cas`.


### VDP_WAIT_READY -> APAGAR_PANTALLA_VDP

Renombrada `VDP_WAIT_READY` (`madmix_scr_body.asm`, $10BC) a
`APAGAR_PANTALLA_VDP`: el nombre anterior era enganoso -- pese a decir
"WAIT", la rutina NO espera nada, solo lee el registro de estado del
VDP (`IN A,($99)`, efecto util: limpia el flag de interrupcion VBLANK
pendiente) y escribe `$A2` en el registro 1 del VDP, que con bit6=0
apaga la pantalla (BLANK), dejando IE activo y sprites grandes. La
que si espera de verdad es su vecina `VDP_ENABLE_DISPLAY` (bucle
`JP P` esperando el VBLANK antes de reactivar la pantalla con `$E2`)
-- el nombre viejo describia la rutina equivocada.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` no tenia menciones. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores sobre `PORTADA_INIT`/los parches `$10D8`/`$10DE`) se dejan
intactas a proposito, mismo criterio de siempre.


### identity_loop -> .BUCLE_TABLA_IDENTIDAD (local)

Renombrado el bucle local `.identity_loop` (dentro de
`DIBUJAR_PORTADA`, `madmix_scr_body.asm`) a `.BUCLE_TABLA_IDENTIDAD`:
escribe la tabla de nombres identidad de la portada (768 bytes en
VRAM $1800, nombre=indice de patron), el mismo truco ya identificado
en el motor principal para tratar la tabla de patrones como un array
directo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md` ni `recursos/*.html`.


### PORTADA_PATTERN -> PORTADA_PATRON

Renombrada `PORTADA_PATTERN` a `PORTADA_PATRON` (`madmix_scr_body.asm`,
$10ED): bitmap sin comprimir de la pantalla de portada, 6144 bytes
(`INCBIN "data/img/portada_patron.img"`) que `DIBUJAR_PORTADA` vuelca
directo a la tabla de patrones de VRAM ($0000). Simple traduccion
("PATTERN" -> "PATRON") para que coincida exactamente con el nombre
del fichero de datos ya existente.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md`.


### PORTADA_COLOR_PACKED -> PORTADA_COLOR

Renombrada `PORTADA_COLOR_PACKED` a `PORTADA_COLOR` (`madmix_scr_body.asm`,
$28F0): bloque de color comprimido de la portada, 768 bytes
(`INCBIN "data/img/portada_color.img"`) que `BUCLE_DESCOMPRIMIR_COLOR_PORTADA` descomprime
byte a byte (cada byte codifica 2 indices de 4 bits en `PALETA_COLORES_PORTADA`,
combinados en un nibble alto/bajo) para reconstruir la tabla de color
real de SCREEN2 en VRAM $2000. "Empaquetado" ya lo explica el
comentario del bloque, no hacia falta en el nombre; coincide con el
fichero de datos ya existente.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md`.


### COLOR_LOOP -> BUCLE_DESCOMPRIMIR_COLOR_PORTADA

Renombrada `COLOR_LOOP` a `BUCLE_DESCOMPRIMIR_COLOR_PORTADA`: bucle
principal que recorre los 768 grupos de `PORTADA_COLOR`, descomprimiendo
cada byte en un color real de SCREEN2 (via `PALETA_COLORES_PORTADA`) y
repitiendolo 8 veces (una columna de 8 lineas) al escribirlo en la
tabla de color VRAM $2000. Global (sin punto, referenciado por `JR
NZ,` desde si mismo), a diferencia del bucle local `.BUCLE_RELLENAR_COLOR` que
contiene dentro.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en la
entrada anterior de este mismo fichero (`PORTADA_COLOR_PACKED ->
PORTADA_COLOR`).


### COLOR_ZERO_CASE -> ESCRIBIR_COLUMNA_COLOR

Renombrada `COLOR_ZERO_CASE` a `ESCRIBIR_COLUMNA_COLOR`: el nombre
anterior solo describia una de sus DOS formas de entrada (salto
directo cuando el byte de control es 0, color 0/0 sin descomprimir).
Tambien se alcanza por caida natural tras descomprimir el caso normal
-- es la rutina COMPARTIDA que escribe el byte de color ya resuelto
(en A) 8 veces en VRAM (una columna de 8 lineas, ya descrito en el
comentario de la linea siguiente).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md`.


### PORTADA_TABLE16 -> PALETA_COLORES_PORTADA

Renombrada `PORTADA_TABLE16` a `PALETA_COLORES_PORTADA` (nombre
propuesto por el usuario, distinto de la traduccion literal
`PORTADA_PALETA`): tabla de paleta, 16 bytes (`INCBIN
"data/img/portada_paleta.img"`) con los valores de color reales de
SCREEN2 (0-15), indexada por `BUCLE_DESCOMPRIMIR_COLOR_PORTADA` para
traducir los dos indices de 4 bits de cada byte comprimido en el
nibble bajo/alto del color final.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizadas tambien las 2 menciones recien anadidas en
entradas anteriores de este mismo fichero.


### color_fill -> .BUCLE_RELLENAR_COLOR (local)

Renombrado el bucle local `.color_fill` (dentro de
`ESCRIBIR_COLUMNA_COLOR`) a `.BUCLE_RELLENAR_COLOR`: escribe el mismo
byte de color 8 veces seguidas en VRAM, rellenando una columna de 8
lineas de un caracter.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en la
entrada anterior de este mismo fichero.


### DIBUJAR_PORTADA completa: datos revisados

A peticion del usuario, revisados todos los literales numericos del
cuerpo completo de `DIBUJAR_PORTADA` (dibujado de la pantalla de
portada: tabla de nombres identidad, bitmap de patrones, descompresion
de color), convirtiendo a decimal los conteos/tamanos puros y
anadiendo comentarios:

- `CP $03` -> `CP 3`: la tabla de nombres identidad se escribe en 3
  paginas de 256 bytes (768 en total).
- `LD BC, $1800` -> `LD BC, 6144`: tamano completo de la tabla de
  patrones de SCREEN2 (bitmap de `PORTADA_PATRON`).
- `LD A, $01` -> `LD A, 1` y `LD C, $07` -> `LD C, 7`: color de
  borde/fondo (indice de paleta) y numero de registro del VDP (R7),
  ya citados en decimal en el comentario existente ("registro 7...
  = 1").
- `LD BC, $0300` -> `LD BC, 768`: numero de grupos de color a
  descomprimir, coincide con el comentario de bloque ya existente
  ("768 grupos de 8 lineas").
- `LD BC, $0008` -> `LD BC, 8`: lineas por columna de caracter
  (reutilizado despues para avanzar el puntero VRAM de destino en 8).
- Dejado en hexadecimal el resto segun la convencion de siempre:
  direcciones VRAM (`$1800`, `$0000`, `$2000`) y mascaras/comandos
  del VDP (`AND $3F`/`OR $40`/`OR $80`/`AND $07`/`AND $78`/`AND $08`).
- Anadidos comentarios a cada paso: fijado de direccion VRAM (SETWRT),
  extraccion de los 2 indices de 4 bits del byte comprimido, guardado/
  restaurado de los 2 contadores distintos que comparten el registro
  BC en el tramo de `ESCRIBIR_COLUMNA_COLOR` (el conteo de relleno de
  8 y el contador de grupos restantes).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). Cambio puramente de notacion/comentarios,
ninguna etiqueta nueva ni renombrada -- no ha hecho falta regenerar
inventario ni `.dsk`/`.cas`.


### TRAPDOOR_PHASE -> LADO_APERTURA_TRAMPILLA

Renombrada `TRAPDOOR_PHASE` a `LADO_APERTURA_TRAMPILLA` (nombre
propuesto por el usuario, mas preciso que la primera propuesta
`FASE_TRAMPILLA`): variable de estado de 1 byte ($2C1E) que guarda
POR QUE LADO se abrio la trampilla en curso (1=izquierda, fijado por
`HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA`; 2=derecha, fijado por
`HNDLR_TRAMPILLA_ABIERTA_DERECHA`), para que `HNDLR_TRAMPILLA_CERRADA`
sepa que variante de animacion de cierre dibujar. Actualizado tambien
el comentario de la declaracion para reflejar el significado real
(lado, no una "fase" generica).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (indice de
variables de estado de partida). Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### REFERENCE_POINT -> PUNTO_REFERENCIA_CAMARA

Renombrada `REFERENCE_POINT` a `PUNTO_REFERENCIA_CAMARA` (`$2C1F-20`):
posicion de 16 bits calculada como camara + desplazamiento fijo (mod
128), recalculada cada frame por `HNDLR_PELMAZOIDE`, usada por
`MOTOR_MOVIMIENTO_ITEM` para decidir si un item movil ("pelmazoide") esta
"detras de camara"/fuera de pantalla. Ya descrita en los comentarios
existentes como "punto de mira"/"punto de referencia"; el nombre deja
claro que es relativo a la camara, no un punto fijo del mapa.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (indice de
variables de estado de partida). Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### RNG_SEED -> SEMILLA_ALEATORIA

Renombrada `RNG_SEED` a `SEMILLA_ALEATORIA` (`$2C22-23`): semilla de
16 bits del generador pseudoaleatorio `GENERAR_ALEATORIO` ($5478), que la lee,
la mezcla con el registro `R` de refresco del Z80 via `XOR` y la
regrada cada vez que se pide un numero aleatorio. "RNG" (siglas de
Random Number Generator) traducido; coincide con el comentario ya
existente ("semilla del generador pseudoaleatorio").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (indice de
variables de estado de partida). Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### TILE_DISPATCH_PTRS/SUBTABLE_A-D -> PUNTEROS_SUBTABLA_DIRECCION/SUBTABLA_DIRECCION_A-D

Renombrada `TILE_DISPATCH_PTRS` a `PUNTEROS_SUBTABLA_DIRECCION` y sus
4 sub-tablas `SUBTABLE_A/B/C/D` a `SUBTABLA_DIRECCION_A/B/C/D`
(`$2C48-$2C9F`): el nombre anterior era enganoso -- no tiene nada que
ver con tipos de loseta, es una tabla de 4 punteros indexada por la
DIRECCION de movimiento (E, ya decidida por el motor de colision) que
selecciona la sub-tabla (20 bytes = 5 filas x 4 columnas) usada por
`ML_DIR_SUBTABLE_LOOP` para elegir el fotograma de animacion del
comecocos (fase de boca + orientacion). No se ha podido confirmar que
direccion concreta (arriba/abajo/izquierda/derecha) corresponde a cada
letra A/B/C/D, asi que se mantienen las letras en vez de inventar un
mapeo sin verificar.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
"tablas del motor de colision/loseta"). Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### ML_MODO_ESPECIAL_TICK -> TICK_MODO_ESPECIAL

Renombrada `ML_MODO_ESPECIAL_TICK` a `TICK_MODO_ESPECIAL` (quitado el
prefijo `ML_`, resto sin traducir de una familia de etiquetas mas
amplia): rutina de actualizacion por-frame de los modos especiales
temporizados (bola de poder=1, hipopotamo=2) -- decrementa el
contador de duracion, gestiona el parpadeo del icono de HUD en los
ultimos instantes, y al agotarse el tiempo limpia los flags de modo.
Tambien es el punto de convergencia comun al que saltan ~20 rutinas
manejadoras de tipo de loseta tras terminar su trabajo. "TICK" se
mantiene (no se traduce): ya es un prestamo tecnico aceptado en este
proyecto (ver `TICK_REPRODUCTOR_PSG`), significa "avanzar un estado
un paso discreto de tiempo" -- aqui coincide 1:1 con un frame, pero
el nombre describe la accion, no la cadencia.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_HIPPO_MODE_TICK -> TICK_MODO_HIPOPOTAMO

Renombrada `ML_HIPPO_MODE_TICK` a `TICK_MODO_HIPOPOTAMO`: gemela de
`TICK_MODO_ESPECIAL` para el modo especial 2 (hipopotamo) -- mismo
patron (decrementa el temporizador, parpadeo del icono de HUD en los
ultimos instantes), pero el parpadeo se implementa alternando el bit
6 del icono por XOR en vez de elegir entre dos valores fijos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_POWER_MODE_END -> FIN_MODO_BOLA_PODER

Renombrada `ML_POWER_MODE_END` a `FIN_MODO_BOLA_PODER`: se alcanza
cuando el temporizador del modo bola de poder llega a 0 -- vacia las
ranuras de sonido (`VACIAR_CANALES_SONIDO`) y apaga los flags de modo
especial, devolviendo el juego al estado normal.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_POWER_BLINK_COLOR -> PARPADEO_COLOR_BOLA_PODER

Renombrada `ML_POWER_BLINK_COLOR` a `PARPADEO_COLOR_BOLA_PODER`:
punto donde se fija el color parpadeante del icono de HUD en los
ultimos instantes del modo bola de poder (alterna entre `$30` fijo y
`COLOR_GUARDADO`, segun el bit bajo del contador).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_DIR_SUBTABLE_LOOKUP/ML_HIPPO_MODE_END/ML_HIPPO_BLINK_ICON -> OBTENER_SUBTABLA_DIRECCION/FIN_MODO_HIPOPOTAMO/PARPADEO_ICONO_HIPOPOTAMO

Continuacion de la limpieza de la familia de prefijo `ML_` (probable
"Main Loop") en el motor de colision/movimiento:

- `ML_DIR_SUBTABLE_LOOKUP` -> `OBTENER_SUBTABLA_DIRECCION`: calcula y
  carga en DE el puntero a la subtabla de direccion elegida (indexando
  `PUNTEROS_SUBTABLA_DIRECCION` con la direccion final *2), en
  paralelo con `OBTENER_PUNTERO_TRANSPOSICION` del driver PSG.
- `ML_HIPPO_MODE_END` -> `FIN_MODO_HIPOPOTAMO`: gemela de
  `FIN_MODO_BOLA_PODER` para el modo especial 2 (restaura
  `COLOR_GUARDADO` y apaga los flags de modo).
- `ML_HIPPO_BLINK_ICON` -> `PARPADEO_ICONO_HIPOPOTAMO`: gemela de
  `PARPADEO_COLOR_BOLA_PODER`, pero alterna el bit del icono de HUD
  por XOR en vez de elegir entre dos colores fijos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_DIR_SUBTABLE_LOOP/DIR_TABLE_INDEX/ML_DIR_BEHAVIOR_STORE -> BUCLE_SUBTABLA_DIRECCION/INDICE_SUBTABLA_DIRECCION/GUARDAR_SELECTOR_SPRITE_COMECOCOS

Continuacion de la limpieza de la familia `ML_`/nombres en ingles del
motor de colision/movimiento, alrededor del bucle que resuelve el
fotograma de animacion del comecocos:

- `ML_DIR_SUBTABLE_LOOP` -> `BUCLE_SUBTABLA_DIRECCION`: recorre las 4
  entradas de la subtabla de direccion elegida buscando una que no
  sea el centinela $FF.
- `DIR_TABLE_INDEX` -> `INDICE_SUBTABLA_DIRECCION` (`$2C14`): indice
  rotativo (0-3) que ese bucle avanza cada llamada.
- `ML_DIR_BEHAVIOR_STORE` -> `GUARDAR_SELECTOR_SPRITE_COMECOCOS`:
  punto donde se guarda el valor ya resuelto (real o heredado via
  centinela $FE) en `SELECTOR_SPRITE_COMECOCOS`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (indice de
variables de estado de partida y bloque "tablas del motor de
colision/loseta"). Las menciones en `FINDINGS.md` (narrativa
historica de sesiones anteriores) se dejan intactas a proposito,
mismo criterio de siempre.


### ML_SCROLL_PREP/ML_SCROLL_DISPATCH_CALL/ML_SCROLL_AND_ITEMS -> PREPARAR_SCROLL/PREPARAR_LLAMADA_SCROLL/DISPARAR_SCROLL_Y_ITEMS

Continuacion de la limpieza de la familia `ML_` en el motor de
colision/movimiento, el tramo que dispara el scroll y los manejadores
de item especial tras resolver el fotograma de animacion:

- `ML_SCROLL_PREP` -> `PREPARAR_SCROLL`: descompone el valor anterior
  (bit7 aparte del resto) y prepara los parametros de la tanda de
  llamadas siguiente.
- `ML_SCROLL_DISPATCH_CALL` -> `PREPARAR_LLAMADA_SCROLL`: termina de
  preparar los parametros y decide la variante de H segun si hay un
  modo especial activo.
- `ML_SCROLL_AND_ITEMS` -> `DISPARAR_SCROLL_Y_ITEMS`: dispara
  `GESTIONAR_SCROLL` y, si el teclado no esta bloqueado, los
  manejadores de item especial (`HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/
  `HNDLR_REGPUNANTOSO`) + `ACTUALIZAR_DESTELLO_ITEMS`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ML_PISTA_LOOP/NEXT/FORMATO_B/FORMATO_B_POS/FILA_FIJA/DIBUJAR -> BUCLE_PISTA_TANQUE_AVION/SIGUIENTE_PISTA/PISTA_FORMATO_B/PISTA_FORMATO_B_POS/PISTA_FILA_FIJA/DIBUJAR_PISTA

Ultima tanda de limpieza de la familia `ML_`: el bucle de pista de
tanque/avion (recorre las 3 entradas de `TABLA_PISTA_TANQUE_AVION`,
calcula la direccion VRAM segun el sub-formato codificado en cada
entrada y llama a `MOTOR_ACTORES` para dibujar el efecto, o libera la
entrada si el calculo se sale de rango):

- `ML_PISTA_LOOP` -> `BUCLE_PISTA_TANQUE_AVION`
- `ML_PISTA_NEXT` -> `SIGUIENTE_PISTA`
- `ML_PISTA_FORMATO_B` -> `PISTA_FORMATO_B` (solo se quita el prefijo,
  "FORMATO_B" ya estaba en espanol)
- `ML_PISTA_FORMATO_B_POS` -> `PISTA_FORMATO_B_POS` (idem)
- `ML_PISTA_FILA_FIJA` -> `PISTA_FILA_FIJA` (idem)
- `ML_PISTA_DIBUJAR` -> `DIBUJAR_PISTA`

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores, con los nombres previos `ML_TRAPDOOR_*`) se dejan
intactas a proposito, mismo criterio de siempre.


### FORCED_DIR_CLEAR/FORCED_DIR_TICK_DONE -> LIMPIAR_DIRECCION_FORZADA/FIN_TICK_DIRECCION_FORZADA

Renombradas `FORCED_DIR_CLEAR` a `LIMPIAR_DIRECCION_FORZADA` (limpia
`DIRECCION_FORZADA` de verdad cuando el temporizador ya llego a 0) y
`FORCED_DIR_TICK_DONE` a `FIN_TICK_DIRECCION_FORZADA` (punto de salida
comun de `TEMPORIZADOR_DIRECCION_FORZADA_TICK`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### TRAPDOOR_ANIM_EXIT -> FIN_ANIMACION_TRAMPILLA

Renombrada `TRAPDOOR_ANIM_EXIT` a `FIN_ANIMACION_TRAMPILLA`: punto de
salida comun de `HNDLR_TRAMPILLA_ABIERTA_DERECHA`/
`HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA` tras dibujar (o no) el fotograma
de la animacion de apertura.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### ITEM_TABLE_PELMAZOIDE -> TABLA_ITEMS_PELMAZOIDE

Renombrada `ITEM_TABLE_PELMAZOIDE` a `TABLA_ITEMS_PELMAZOIDE`
(`$511C`): tabla activa de 8 entradas (7 bytes cada una) de los items
tipo 3 (fantasmas -- ya identificados via `SPR27-32_FANTASMA_*`).
"ITEM_TABLE" en ingles + "PELMAZOIDE" ya en espanol (termino ya
consistente en `HNDLR_PELMAZOIDE`, etc.); mismo patron que
`TABLA_PISTA_TANQUE_AVION`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque de
`0x511C-0x5154`). Las menciones en `FINDINGS.md` (narrativa historica
de sesiones anteriores) se dejan intactas a proposito, mismo criterio
de siempre.


### ITEM_ANIM_TABLE_PELMAZOIDE/ITEM_DIR_CHOICE_TABLE -> TABLA_ANIMACION_PELMAZOIDE/TABLA_ELECCION_DIRECCION

Renombradas las dos tablas de datos del bloque `$5154-$51FE`:

- `ITEM_ANIM_TABLE_PELMAZOIDE` -> `TABLA_ANIMACION_PELMAZOIDE` (32
  bytes): tabla de seleccion de sprite por direccion+fase de los
  fantasmas, indexada por `HNDLR_PELMAZOIDE` como
  `direccion(1-4)*4+fase(0-3)`; hermana de `TABLA_ITEMS_PELMAZOIDE`
  (la de estado) pero esta es la de animacion/graficos.
- `ITEM_DIR_CHOICE_TABLE` -> `TABLA_ELECCION_DIRECCION` (128 bytes,
  `$517E`): dato puro indexado por `MOTOR_MOVIMIENTO_ITEM` como
  `(direcciones libres)<<3 | (direccion previa)<<1 | (bit aleatorio)`,
  devuelve la direccion final elegida (sesgo "mantener direccion si
  se puede"); generica de `MOTOR_MOVIMIENTO_ITEM`, no especifica de
  los pelmazoides.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
`0x5154-0x51FE`). Las menciones en `FINDINGS.md` (narrativa historica
de sesiones anteriores) se dejan intactas a proposito, mismo criterio
de siempre.


### PELMAZOIDE_LOOP/PELMAZOIDE_DRAW/PELMAZOIDE_SPECIAL_ADJUST -> BUCLE_PELMAZOIDE/DIBUJAR_PELMAZOIDE/AJUSTAR_SPRITE_MODO_ESPECIAL

Renombradas 3 etiquetas de `HNDLR_PELMAZOIDE` (`MOVER_ITEM_MOVIL`, ya
completamente en espanol en su momento, luego renombrada aparte a
`MOTOR_MOVIMIENTO_ITEM` en una ronda posterior, ver mas abajo):

- `PELMAZOIDE_LOOP` -> `BUCLE_PELMAZOIDE`: recorre las entradas
  activas de `TABLA_ITEMS_PELMAZOIDE` llamando a `MOTOR_MOVIMIENTO_ITEM`.
  Cuidado al aplicar: existe una etiqueta DISTINTA `TI_PELMAZOIDE_LOOP`
  (linea ~3058) que contiene "PELMAZOIDE_LOOP" como subcadena -- NO se
  ha tocado, edits dirigidos en vez de `replace_all` para evitar
  corromperla.
- `PELMAZOIDE_DRAW` -> `DIBUJAR_PELMAZOIDE`: dibuja el sprite ya
  resuelto (direccion+fase).
- `PELMAZOIDE_SPECIAL_ADJUST` -> `AJUSTAR_SPRITE_MODO_ESPECIAL`: con
  el modo bola de poder activo, desplaza +20 bytes para usar la
  segunda mitad de cada grupo de `TABLA_ANIMACION_PELMAZOIDE` (sprite
  variante del fantasma durante el modo especial).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`.


### MOVER_ITEM_MOVIL -> MOTOR_MOVIMIENTO_ITEM

Renombrada `MOVER_ITEM_MOVIL` a `MOTOR_MOVIMIENTO_ITEM`: el nombre
anterior ya estaba completamente en espanol pero sonaba redundante
("mover item movil"). Motor de movimiento generico compartido por los
3 tipos de item movil (pelmazoide/fantasma, mariquita,
"repugnantoso"): valida la posicion, calcula la direccion de
acercamiento hacia la camara, prueba direcciones libres via
`CONSULTAR_LOSETA_LIBRE_DIRECCION` y elige la direccion final via `TABLA_ELECCION_DIRECCION`.
Nombre elegido para encajar con la misma familia que
`MOTOR_MOVIMIENTO_COLISION`/`MOTOR_ACTORES`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
`0x51FE-0x5478`). Sincronizadas tambien las menciones recien anadidas
en 2 entradas anteriores de este mismo fichero. Las menciones en
`FINDINGS.md` de narrativa historica genuina (rondas anteriores sobre
`HELPER_5278`/estudio de sub-etiquetas) se dejan intactas a proposito.


### ITEM_EFFECT -> ACTIVAR_EFECTO_ITEM

Renombrada `ITEM_EFFECT` a `ACTIVAR_EFECTO_ITEM` (`$57D8`): efecto de
activacion de un item, llamado tras `MOTOR_ACTORES` desde los 3
manejadores de item movil. Filtra por una ventana fija de posicion
VRAM (cerca del comecocos) y por el tipo de item leido de `($2C2D)`,
y dispara sonidos/animaciones/modos especiales via
`ARMAR_AVISO_DESTELLO`/`$8D70`, o delega en `AVISAR_PROXIMIDAD_PISTA` cuando
el tipo es 3 (pista).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### PELMAZOIDE_NEXT/PELMAZOIDE_END -> SIGUIENTE_PELMAZOIDE/FIN_PELMAZOIDE

Renombradas `PELMAZOIDE_NEXT` a `SIGUIENTE_PELMAZOIDE` (avanza a la
siguiente entrada de `TABLA_ITEMS_PELMAZOIDE`, se alcanza tanto si la
posicion no era valida como tras dibujar y comprobar el efecto) y
`PELMAZOIDE_END` a `FIN_PELMAZOIDE` (el `RET` final de
`HNDLR_PELMAZOIDE`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md` ni `recursos/mapa_memoria.html`.


### HELPER_5414 -> CONSULTAR_LOSETA_LIBRE_DIRECCION

Renombrada `HELPER_5414` a `CONSULTAR_LOSETA_LIBRE_DIRECCION`
(`$5414`): comprueba, para cada uno de los 4 bits de direccion
(`A=$01/$02/$04/$08` = derecha/izquierda/abajo/arriba), si la
posicion del item tiene loseta libre un paso en esa direccion (via
`CONSULTAR_TIPO_LOSETA`). Se llama 4 veces seguidas desde
`MOTOR_MOVIMIENTO_ITEM` acumulando un bitmask de direcciones libres.
Mismo estilo que `CONSULTAR_TIPO_LOSETA`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
`0x51FE-0x5478`). Sincronizada tambien la mencion recien anadida en
una entrada anterior de este mismo fichero. Las menciones en
`FINDINGS.md` (narrativa historica de sesiones anteriores) se dejan
intactas a proposito, mismo criterio de siempre.


### HELPER_53A2/H53A2_53BA -> CALCULAR_POSICION_VRAM_ITEM/.CONTINUAR_AJUSTE_COLUMNA (local)

Renombrada `HELPER_53A2` a `CALCULAR_POSICION_VRAM_ITEM` (`$53A2`):
segundo punto de entrada de `MOTOR_MOVIMIENTO_ITEM`, llamado directo
desde `ACTUALIZAR_DESTELLO_ITEMS` (sin pasar por las comprobaciones de
"detras de camara"). Calcula la direccion VRAM (D/E) de la posicion
del item relativa a la camara actual y la comprueba contra los
limites visibles de pantalla; devuelve con carry si cae fuera de
rango, o DE=direccion VRAM si es visible.

Convertida tambien a LOCAL (unico uso dentro de la misma funcion)
`H53A2_53BA` -> `.CONTINUAR_AJUSTE_COLUMNA`: punto de convergencia de
un ajuste de columna -- calcula `(E-8) mod 64` (envuelto con `RES 7`),
la columna del item ajustada a la ventana visible de 64 (candidato a
mitad/cuadrante del buffer de losetas, mismo tipo de particion "mitad"
ya visto en `MOTOR_ACTORES`, sin confirmar del todo).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
620 etiquetas (baja 1 por la conversion global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/mapa_memoria.html` sincronizado (bloque `0x51FE-0x5478`).
Las menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### H53A2_53C7/H53A2_5411 -> .CONTINUAR_AJUSTE_FILA/.SALIR_FUERA_DE_RANGO (locales)

Convertidas a locales las 2 etiquetas restantes de
`CALCULAR_POSICION_VRAM_ITEM` (unico uso dentro de la misma funcion):

- `H53A2_53C7` -> `.CONTINUAR_AJUSTE_FILA`: gemela de
  `.CONTINUAR_AJUSTE_COLUMNA` pero para la fila (`(D-8) mod 64`).
- `H53A2_5411` -> `.SALIR_FUERA_DE_RANGO`: punto de salida comun de
  las 4 comprobaciones de limite (fila contra `$2C`, columna contra
  `$38`) -- pone el carry y retorna, tal como describe la cabecera de
  la funcion ("devuelve con carry si la posicion cae fuera de rango").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
618 etiquetas (baja 2 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md` ni `recursos/mapa_memoria.html`.


### CALCULAR_POSICION_VRAM_ITEM completa: datos revisados

A peticion del usuario, revisados todos los literales numericos del
cuerpo completo de `CALCULAR_POSICION_VRAM_ITEM`, convirtiendo a
decimal los que son limites/offsets puros y anadiendo un comentario a
cada linea relevante:

- `SUB $08` (4 apariciones) -> `SUB 8`: mismo offset de referencia
  respecto a la camara que usa `PUNTO_REFERENCIA_CAMARA` (`+8`), aqui
  restado en vez de sumado.
- `CP $40`/`LD C, $40`/`LD B, $40` -> `64`: mitad del rango de
  columna/fila y ajuste de wrap correspondiente (reutilizado despues
  como sumando para compensar el wrap).
- `CP $2C` -> `CP 44` y `CP $38` -> `CP 56`: limites superiores de
  fila/columna visible.
- `ADD A, $0E` -> `ADD A, 14`: offset base de la construccion de la
  direccion VRAM final (candidato, sin confirmar del todo el porque
  exacto de este valor).
- Dejado en hexadecimal `ADD A, $F8` (delta con signo, -8, misma
  convencion de siempre) y `ADC A, $00` (propagacion de acarreo
  trivial).
- Anadidos comentarios explicando el flujo completo: limpieza del
  bit7 de flag de scroll antes de tratar la posicion de camara como
  coordenada pura, el porque de cada ajuste de wrap, y el calculo
  final de direccion VRAM (columna*2+14, fila*4-8) con propagacion de
  acarreo desde 2 bits de (IX+4)/(IX+5).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). Cambio puramente de notacion/comentarios,
ninguna etiqueta nueva ni renombrada -- no ha hecho falta regenerar
inventario ni `.dsk`/`.cas`.


### H5414_5427/H5414_542F/H5414_543A/H5414_5440 -> .COMPROBAR_IZQUIERDA/.COMPROBAR_ABAJO/.COMPROBAR_ARRIBA/.CONSULTAR_LOSETA_DESPLAZADA (locales)

Convertida a locales la cadena de decodificacion de bits de
`CONSULTAR_LOSETA_LIBRE_DIRECCION` (cascada de `RRA` que prueba cada
uno de los 4 bits de `A`, 1/2/4/8, y aplica el desplazamiento de
coordenada correspondiente):

- `H5414_5427` -> `.COMPROBAR_IZQUIERDA` (bit1, tras descartar derecha)
- `H5414_542F` -> `.COMPROBAR_ABAJO` (bit2, tras descartar izquierda)
- `H5414_543A` -> `.COMPROBAR_ARRIBA` (bit3, tras descartar abajo)
- `H5414_5440` -> `.CONSULTAR_LOSETA_DESPLAZADA` (punto de convergencia
  comun de las 4 ramas, justo antes de `CALL MAPEAR_COORDENADA_A_DIRECCION`/
  `CONSULTAR_TIPO_LOSETA`)

Las otras 3 etiquetas de la misma familia (`H5414_5456`/`H5414_545A`/
`H5414_545C`) se renombraron en una ronda posterior, ver mas abajo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
614 etiquetas (baja 4 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md` ni `recursos/mapa_memoria.html`.


### H5414_5456/H5414_545A/H5414_545C -> .LOSETA_BLOQUEADA/.LOSETA_LIBRE/.FIN_CONSULTA_LOSETA (locales)

Convertidas a locales las 3 etiquetas restantes de
`CONSULTAR_LOSETA_LIBRE_DIRECCION`, cierre de la clasificacion de tipo
de loseta:

- `H5414_5456` -> `.LOSETA_BLOQUEADA`: convergencia de los tipos 0
  (pared/suelo), 7 (pista tanque), 8 (linea electrica) y 10 (pista
  avion) -- pone A=0 y SCF (carry=bloqueado).
- `H5414_545A` -> `.LOSETA_LIBRE`: cualquier otro tipo -- A=D (la
  direccion probada) y limpia el carry.
- `H5414_545C` -> `.FIN_CONSULTA_LOSETA`: salida comun final
  (POP DE/POP BC/RET) de ambos caminos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
611 etiquetas (baja 3 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sincronizada
tambien la mencion recien anadida en la entrada anterior de este
mismo fichero. Sin menciones en `recursos/mapa_memoria.html`.


### CONSULTAR_LOSETA_LIBRE_DIRECCION completa: datos revisados

A peticion del usuario, revisados todos los literales numericos del
cuerpo completo de `CONSULTAR_LOSETA_LIBRE_DIRECCION`:

- `CP $08`/`CP $07`/`CP $0A` -> `CP 8`/`CP 7`/`CP 10`: tipos de
  loseta, ya citados en decimal en el comentario de cabecera ("Tipos
  0... 7... 8... y 10") -- ahora el codigo coincide con la prosa.
- Dejados en hexadecimal los 4 `LD A, $01/$02/$04/$08` (codigos de
  direccion derecha/izquierda/abajo/arriba, convencion de bitmask ya
  establecida en toda la sesion, no son conteos puros).
- Anadido un comentario a cada `LD A, $0X` explicando que guarda el
  codigo de direccion para el resultado en D.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). Cambio puramente de notacion/comentarios,
ninguna etiqueta nueva ni renombrada -- no ha hecho falta regenerar
inventario ni `.dsk`/`.cas`.


### COORD_TO_ADDR -> MAPEAR_COORDENADA_A_DIRECCION

Renombrada `COORD_TO_ADDR` a `MAPEAR_COORDENADA_A_DIRECCION`
(`$545F`): convierte una coordenada (BC) en la direccion del buffer
de nivel, misma formula exacta que `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`
(`fila*32+columna`), aplicada aqui a BC en vez de a la posicion de
camara -- incluye el mismo fix de la v2.0 (`$FC60` -> `$FC50`) para el
bug del contador de bolitas del nivel 13. Nombre elegido para encajar
con esa misma familia. Cuidado al aplicar: existe una copia
independiente `MAPEAR_COORDENADA_A_DIRECCION_LOCAL` (antes
`COORD_TO_ADDR_LOCAL`, renombrada aparte en una ronda posterior) que
en su momento contenia "COORD_TO_ADDR" como
subcadena -- NO se ha tocado, edits dirigidos en vez de `replace_all`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(611 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en una
entrada anterior de este mismo fichero. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### ITEM_RNG -> GENERAR_ALEATORIO

Renombrada `ITEM_RNG` a `GENERAR_ALEATORIO` (`$5478`): generador
pseudoaleatorio generico (no especifico de items pese al nombre
anterior) -- lee `SEMILLA_ALEATORIA`, la mezcla con el registro `R`
de refresco del Z80 via `XOR`, y la vuelve a guardar. Coincide con la
nueva `SEMILLA_ALEATORIA` ya establecida.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(611 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`.
Sincronizada tambien la mencion recien anadida en una entrada anterior
de este mismo fichero. Las menciones en `FINDINGS.md` (narrativa
historica de sesiones anteriores) se dejan intactas a proposito,
mismo criterio de siempre.


### ITEM_TABLE_MARICOCO/ITEM_ANIM_TABLE_MARICOCO -> TABLA_ITEMS_MARICOCO/TABLA_ANIMACION_MARICOCO

Renombradas siguiendo el mismo patron ya aplicado a pelmazoide:
`ITEM_TABLE_MARICOCO` -> `TABLA_ITEMS_MARICOCO` (`$549B`, tabla activa
tipo 1, 2 entradas x 7 bytes) y `ITEM_ANIM_TABLE_MARICOCO` ->
`TABLA_ANIMACION_MARICOCO` (`$5487`, 20 bytes, tabla de sprite por
direccion+fase, mismo mecanismo confirmado que
`TABLA_ANIMACION_PELMAZOIDE`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(611 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
`0x5478-0x5904`). Sin menciones en `FINDINGS.md`.


### HNDLR_MARICOCO/HNDLR_REGPUNANTOSO completos + MAPEAR_COORDENADA_A_DIRECCION_LOCAL: renombrado en bloque

A peticion del usuario, completado el paralelismo entre las 3
subunidades de item movil (pelmazoide ya hecho en rondas anteriores,
ahora mariquita y repugnantoso):

- `MARICOCO_LOOP` -> `BUCLE_MARICOCO`; `MARICOCO_NEXT` ->
  `SIGUIENTE_MARICOCO`; `MARICOCO_SKIP` -> `SIN_REGENERAR_MARICOCO`
  (converge cuando no toca regenerar la bolita).
- `REGPUNANTOSO_LOOP` -> `BUCLE_REGPUNANTOSO`; `REGPUNANTOSO_NEXT` ->
  `SIGUIENTE_REGPUNANTOSO`; `REGPUNANTOSO_SKIP` ->
  `SIN_PLANTAR_REGPUNANTOSO` (converge cuando no toca plantar la bola
  clavada).
- `ITEM_TABLE_REGPUNANTOSO` -> `TABLA_ITEMS_REGPUNANTOSO`;
  `ITEM_ANIM_TABLE_REGPUNANTOSO` -> `TABLA_ANIMACION_REGPUNANTOSO`
  (mismo patron ya aplicado a pelmazoide/mariquita).
- `COORD_TO_ADDR_LOCAL` -> `MAPEAR_COORDENADA_A_DIRECCION_LOCAL`
  (`$5559`): tercera copia independiente de la misma formula que
  `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`/`MAPEAR_COORDENADA_A_DIRECCION`,
  con el mismo fix de la v2.0 (`$FC60` -> `$FC50`).

Cuidado al aplicar: existen etiquetas DISTINTAS `TI_MARICOCO_LOOP`/
`TI_REGPUNANTOSO_LOOP` que contienen "MARICOCO_LOOP"/"REGPUNANTOSO_LOOP"
como subcadena -- NO se han tocado, edits dirigidos en vez de
`replace_all` para esas dos.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(611 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `recursos/mapa_memoria.html` sincronizado (bloque
`0x5478-0x5904`). Sincronizada tambien la mencion recien anadida en
una entrada anterior de este mismo fichero. Las menciones en
`FINDINGS.md` (narrativa historica de sesiones anteriores) se dejan
intactas a proposito, mismo criterio de siempre.


### GHOST_HINT_HANDLER/CLEAR_5773_AND_SET y su familia: renombrado en bloque

Renombrado el subsistema de "aviso de pista" completo:

- `GHOST_HINT_HANDLER` (`$566A`) -> `AVISAR_PROXIMIDAD_PISTA`:
  comprueba las 3 entradas de pista tanque/avion contra la posicion
  del comecocos con un margen asimetrico "de aviso" (mas amplio que
  la propia loseta, para detectar la proximidad antes de pisarla) y
  arma el aviso via `CLEAR_5773_AND_SET`.
- `CLEAR_5773_AND_SET` (`$56CA`) -> `ARMAR_AVISO_DESTELLO`: limpia/
  busca hueco libre entre las 4 entradas de `$5773` y guarda el
  marcador de aviso.

Convertida a locales toda la cadena interna (uso exclusivo dentro de
cada funcion):

- `GHH_LOOP` -> `.BUCLE_PISTA`; `GHH_SKIP` -> `.SIGUIENTE_PISTA`;
  `GHH_5768A` -> `.FORMATO_B` (mismo formato B ya visto en
  `PISTA_FORMATO_B`); `GHH_5694` -> `.FORMATO_B_POS` (paralelo a
  `PISTA_FORMATO_B_POS`); `GHH_5699` -> `.FILA_FIJA` (paralelo a
  `PISTA_FILA_FIJA`); `GHH_569C` -> `.COMPROBAR_MARGEN_PISTA`
  (arranca la comprobacion de margen asimetrico).
- `CS_LOOP` -> `.BUCLE_RANURA_AVISO`; `CS_NEXT` ->
  `.SIGUIENTE_RANURA_AVISO`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
603 etiquetas (baja 8 por las 8 conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/mapa_memoria.html` sincronizado (indice de variables de
estado de partida). Sincronizada tambien la mencion recien anadida en
una entrada anterior de este mismo fichero. Las menciones en
`FINDINGS.md` (narrativa historica de sesiones anteriores) se dejan
intactas a proposito, mismo criterio de siempre.


### ITT_LOOP/ITT_57A8/ITT_57AD/ITT_NEXT -> locales en ACTUALIZAR_DESTELLO_ITEMS

Convertida a locales la cadena interna de `ACTUALIZAR_DESTELLO_ITEMS`
("ITT" = Item Timer Tick, unico uso dentro de la misma funcion):

- `ITT_LOOP` -> `.BUCLE_DESTELLO`: recorre las 4 entradas activas de
  `$5773`.
- `ITT_57A8` -> `.CALCULAR_POSICION_DESTELLO`: calcula la posicion
  VRAM via `CALCULAR_POSICION_VRAM_ITEM` cuando no hay una posicion
  fija forzada por el modo especial.
- `ITT_57AD` -> `.DIBUJAR_FRAME_DESTELLO`: con la posicion ya resuelta
  (fija o calculada), indexa `ITEM_TABLE_EFECTOS_DESTELLO` por la fase
  para obtener el frame/loseta y dibuja con `MOTOR_ACTORES` si la
  posicion era valida.
- `ITT_NEXT` -> `.SIGUIENTE_DESTELLO`: avanza a la siguiente entrada.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
599 etiquetas (baja 4 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones
en `recursos/mapa_memoria.html`. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### IE_57FD/IE_581B/IE_WAIT/IE_5833/IE_584A/IE_5856/IE_5870/IE_587C/IE_5881 -> locales en ACTIVAR_EFECTO_ITEM

Convertida a locales toda la cadena interna de `ACTIVAR_EFECTO_ITEM`
("IE" = Item Effect, decide que hacer segun el modo especial activo
cuando un item coincide con la posicion del comecocos):

- `IE_57FD` -> `.ACTIVAR_NUEVO_MODO_ESPECIAL`: activa un modo especial
  nuevo (sin modo activo, o reentrada desde modo 3/herramienta).
- `IE_581B` -> `.INICIAR_MODO_ESPECIAL`: arma el temporizador, dispara
  evento `$6128=8` y pasa a esperar.
- `IE_WAIT` -> `.ESPERAR_EVENTO`: espera activa a que se consuma
  `$6128`.
- `IE_5833` -> `.MODO_BOLA_PODER_ACTIVO`; `IE_584A` ->
  `.SUMAR_PUNTOS_MODO1` (suma puntos + aviso + evento 7).
- `IE_5856` -> `.MODO_HIPOPOTAMO_ACTIVO`; `IE_5870` ->
  `.SUMAR_PUNTOS_MODO2` (mismo cierre que modo1, duplicado para modo2).
- `IE_587C` -> `.MODO_HERRAMIENTA_ACTIVO`: reutiliza el tratamiento
  de `.ACTIVAR_NUEVO_MODO_ESPECIAL`.
- `IE_5881` -> `.DELEGAR_AVISO_PISTA`: salida de reserva, delega en
  `AVISAR_PROXIMIDAD_PISTA`.

De paso, corregidas las menciones en prosa de estas etiquetas dentro
de las cabeceras de `ARMAR_AVISO_DESTELLO` e `ITEM_TABLE_EFECTOS_DESTELLO`
(fuera del ambito de `ACTIVAR_EFECTO_ITEM`) para usar notacion con
ambito (`ACTIVAR_EFECTO_ITEM.NOMBRE`) en vez de la etiqueta local
suelta, evitando ambiguedad sobre a que funcion pertenecen.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
590 etiquetas (baja 9 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`recursos/mapa_memoria.html`. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### TI_PELMAZOIDE_LOOP/TI_MARICOCO_LOOP/TI_REGPUNANTOSO_LOOP -> locales en INICIALIZAR_ITEMS_NIVEL

Convertidas a locales las 3 etiquetas restantes con prefijo `TI_`
("Tabla de Items", no confundir con la familia `ITT_` de
`ACTUALIZAR_DESTELLO_ITEMS`, ya renombrada aparte): los 3 bucles de
`INICIALIZAR_ITEMS_NIVEL` que resetean cada tabla de items
(pelmazoide/mariquita/repugnantoso) a su posicion de referencia
inicial del nivel, limpiando sus campos de modo/fase. Uso exclusivo
dentro de esta funcion.

- `TI_PELMAZOIDE_LOOP` -> `.BUCLE_RESET_PELMAZOIDE`
- `TI_MARICOCO_LOOP` -> `.BUCLE_RESET_MARICOCO`
- `TI_REGPUNANTOSO_LOOP` -> `.BUCLE_RESET_REGPUNANTOSO`

Estas 3 etiquetas se dejaron deliberadamente sin tocar en la ronda
anterior (renombrado de `MARICOCO_LOOP`/`REGPUNANTOSO_LOOP`) por
compartir subcadena con ellas -- esta ronda las cierra.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
587 etiquetas (baja 3 por las conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`recursos/mapa_memoria.html`. Las menciones en `FINDINGS.md` de
rondas anteriores (que describian estas etiquetas como "distintas,
sin tocar" en su momento) se dejan intactas a proposito, mismo
criterio de siempre.


### ACTUALIZAR_DESTELLO_ITEMS/ACTIVAR_EFECTO_ITEM/INICIALIZAR_ITEMS_NIVEL/CARGAR_NIVEL: datos revisados

A peticion del usuario, revisados todos los literales numericos de
este bloque completo (`ACTUALIZAR_DESTELLO_ITEMS`, `ACTIVAR_EFECTO_ITEM`,
`INICIALIZAR_ITEMS_NIVEL`/`INICIALIZAR_PARCIAL_ITEMS_NIVEL`,
`CARGAR_NIVEL`), convirtiendo a decimal los limites/conteos/indices
puros y anadiendo comentarios:

- `ACTUALIZAR_DESTELLO_ITEMS`: `LD B, $04` -> `4` (entradas activas de
  `$5773`). `LD D, $38`/`LD E, $40` -> `56`/`64`: posicion VRAM fija
  que resulta ser justo el centro de la ventana que comprueba
  `ACTIVAR_EFECTO_ITEM` -- detalle nuevo, anotado en el comentario.
- `ACTIVAR_EFECTO_ITEM`: los 4 limites de la ventana de posicion ->
  `50`/`62`/`60`/`68` (coincide con el rango citado ahora en decimal
  en la cabecera). Las comparaciones de estado/modo (`H==1`, modo
  especial `1`/`2`/`3`, etc.) y los marcadores de evento `$6128`
  (`8`, `7`, `13`) tambien convertidos -- corregida de paso la
  cabecera, que citaba par metros en hex (`$28`/`$AD`/`$2D`/`$A7`) ya
  desactualizados frente al codigo (que ya usaba `40`/`45` decimal de
  una ronda anterior).
- `INICIALIZAR_ITEMS_NIVEL`: los conteos de entradas (`7` bytes/
  entrada, `8`/`2`/`8` entradas por tabla, `4` entradas de `$5773`,
  `3` entradas de pista) y el valor especial `14` del modo
  herramienta (antes `$0E`, corregida tambien la mencion en la
  cabecera de la funcion).
- `CARGAR_NIVEL`: `LD BC, $0014` -> `20` y los 2 `LD BC, $0060` ->
  `96` (ya tenian el comentario decimal, ahora el codigo coincide).
  `CP $3C` -> `CP 60` (tile comodin). Dejados en hexadecimal el resto
  segun la convencion de siempre: direcciones/valores empaquetados
  (`$FC50`, `$1018`), mascaras de bits (`AND $01`/`$80`/`$7F`) y el
  byte de color/atributo `$78`.

**Verificado**: recompilado sin errores (9687 lineas), diffs en la
linea base exacta de siempre (7/2). Cambio puramente de notacion/
comentarios, ninguna etiqueta nueva ni renombrada -- no ha hecho
falta regenerar inventario ni `.dsk`/`.cas`.


### TAIL_INTRO -> GESTIONAR_INTRODUCCION

Renombrada `TAIL_INTRO` a `GESTIONAR_INTRODUCCION` (`$5AE9`): gestiona
toda la pantalla de introduccion -- apaga pantalla, dibuja creditos
(`DIBUJAR_CREDITOS`, antes `TAIL_CREDITS_DRAW`), enciende pantalla, y
entra en un bucle de hasta 70 iteraciones (copia un bloque de VRAM/RAM
sobre si mismo) esperando pulsacion de tecla/joystick (ESC activa el
truco oculto de vidas infinitas). Al terminar dibuja la portada,
instala los 3 recursos de sonido y espera de nuevo; tambien es el
punto de retorno del dispatcher de menu. "TAIL_" es prefijo de una
familia mas amplia (`TAIL_CREDITS_TEXT`/etc.) todavia sin tocar.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(587 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `recursos/mapa_memoria.html`. Las
menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### QUEUE_SCREEN_OFF/QUEUE_SCREEN_ON/TAIL_CREDITS_DRAW -> PROGRAMAR_APAGADO_PANTALLA/PROGRAMAR_ENCENDIDO_PANTALLA/DIBUJAR_CREDITOS

Renombradas `QUEUE_SCREEN_OFF`/`QUEUE_SCREEN_ON` a
`PROGRAMAR_APAGADO_PANTALLA`/`PROGRAMAR_ENCENDIDO_PANTALLA`: no
apagan/encienden la pantalla directamente -- solo programan el valor
de registro 1 del VDP (`VDP_REG1_PENDING`) que
`ENTRADA_INTERRUPCION_VBLANK` releera y aplicara de verdad en el
proximo VBLANK. Distintas de `APAGAR_PANTALLA_VDP` (ya renombrada
antes, esa si escribe directo). `TAIL_CREDITS_DRAW` (`$5F77`) ->
`DIBUJAR_CREDITOS`: dibuja la pantalla de creditos (limpia y escribe
los 3 bloques de texto via `DIBUJAR_TEXTO_VRAM`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(587 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en una
entrada anterior de este mismo fichero. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### TI_LOOP -> .BUCLE_ESPERA_INTRO (local)

Convertida a local `TI_LOOP` (dentro de `GESTIONAR_INTRODUCCION`) a
`.BUCLE_ESPERA_INTRO`: en cada iteracion hace un `LDIR` que copia el
bloque `$4000` SOBRE SI MISMO (origen=destino=$4000, 16384 bytes) --
sin efecto real sobre los datos, casi seguro usado solo como
temporizador de espera entre cada sondeo de tecla/joystick
(`COMPROBAR_PULSACION`), hasta 70 veces o hasta detectar pulsacion
(`.COMPROBAR_TRUCO_VIDAS_INFINITAS`, antes `TI_BREAK`, renombrada en
una ronda posterior).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
586 etiquetas (baja 1 por la conversion global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sin menciones
en `FINDINGS.md`.


### TI_BREAK/TI_WAIT -> .COMPROBAR_TRUCO_VIDAS_INFINITAS/.BUCLE_ESPERA_TIMEOUT (locales)

Convertida a local `TI_BREAK` (dentro de `GESTIONAR_INTRODUCCION`) a
`.COMPROBAR_TRUCO_VIDAS_INFINITAS`: comprueba si la tecla que rompio
`.BUCLE_ESPERA_INTRO` es ESC (fila 7 de la matriz) y, si es asi,
activa el truco oculto de vidas infinitas -- parchea en caliente la
instruccion `SUB $01` de `BUCLE_PRINCIPAL_JUEGO` (madmix1_body.asm) a
`SUB $00` (perder una vida deja de restar y de disparar Game Over),
confirmando visualmente con un parpadeo del color de borde. Sea o no
ESC, cae en `.CONTINUAR_INTRO` (antes `TI_CONT`, renombrada en una
ronda posterior).

Al aplicar se disparo la trampa clasica de ambito de etiquetas locales:
`TI_WAIT` (bucle de espera con timeout, `BC=$2710`) es una etiqueta
GLOBAL que quedaba entre la referencia (linea 3472) y la definicion
(linea 3506) de la nueva local -- error "Label not found" al
recompilar. Verificado que `TI_WAIT` no tenia mas referencias externas
y convertida tambien a local: `TI_WAIT` -> `.BUCLE_ESPERA_TIMEOUT`.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
584 etiquetas (baja 2 por las 2 conversiones global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sincronizada
tambien la mencion recien anadida en una entrada anterior de este
mismo fichero. Las menciones en `FINDINGS.md` (narrativa historica de
sesiones anteriores) se dejan intactas a proposito, mismo criterio de
siempre.


### TI_CONT -> .CONTINUAR_INTRO (local)

Convertida a local `TI_CONT` (dentro de `GESTIONAR_INTRODUCCION`) a
`.CONTINUAR_INTRO`: punto de convergencia tras el chequeo del truco
de vidas infinitas (activado o no) -- espera a que se suelte la tecla
(`ESPERAR_TECLA_SOLTADA`, antes `TAIL_KEYWAIT_UP`), dibuja el marco de caramelo
(`DIBUJAR_MARCO_CARAMELO_VRAM`), y cae en `MOSTRAR_MENU_PRINCIPAL`
(antes `TI_5B56`, renombrada en una ronda posterior) -- esta SI sigue
siendo global, llamada externamente desde `REINICIAR_PARTIDA` en
`madmix1_body.asm`). Corregida de paso una mencion en prosa fuera de
ambito (cabecera de `PROGRAMAR_APAGADO_PANTALLA`/
`PROGRAMAR_ENCENDIDO_PANTALLA`, mucho mas arriba en el fichero) a
notacion con ambito (`GESTIONAR_INTRODUCCION.CONTINUAR_INTRO`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
583 etiquetas (baja 1 por la conversion global->local, patron ya
esperado). `.dsk`/`.cas` regenerados sin incidencias. Sincronizada
tambien la mencion recien anadida en una entrada anterior de este
mismo fichero. Las menciones en `FINDINGS.md` (narrativa historica de
sesiones anteriores) se dejan intactas a proposito, mismo criterio de
siempre.


### TAIL_KEYWAIT_UP/TAIL_KEYWAIT_RELEASE -> ESPERAR_TECLA_SOLTADA/ESPERAR_TECLA_PULSADA

Renombradas corrigiendo un nombre ENGANOSO detectado al analizarlas:
`TAIL_KEYWAIT_UP` (`$5D04`) -> `ESPERAR_TECLA_SOLTADA` (espera
mientras `COMPROBAR_PULSACION` devuelve NZ -- tecla pulsada -- hasta
que ya no hay ninguna, el nombre original SI describia bien esta),
pero `TAIL_KEYWAIT_RELEASE` (`$5CFE`) -> `ESPERAR_TECLA_PULSADA`: pese
a su nombre anterior ("RELEASE"), en realidad espera mientras
`COMPROBAR_PULSACION` devuelve Z (nada pulsado) hasta detectar una
pulsacion -- es decir, espera que se PULSE una tecla, no que se
suelte. Se ve claro en el uso conjunto tipico (`CALL
ESPERAR_TECLA_SOLTADA` seguido de `JP ESPERAR_TECLA_PULSADA`): primero
espera a soltar la tecla actual, luego espera la siguiente pulsacion
-- el nombre viejo de la segunda describia la funcion equivocada.
Actualizado tambien el comentario de cabecera de ambas para reflejar
el comportamiento real por separado (antes una sola linea ambigua
"Espera a soltar tecla / a pulsar tecla").

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(583 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en una
entrada anterior de este mismo fichero. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### TAIL_VDP_CLEAR/TAIL_LEVELCYCLE_HELPER_ALT/TI_5B62/TAIL_MAINMENU_DRAW/TAIL_FONT_ROUTINE/TI_5BA7/TVF_LOOP: renombrado en bloque

Renombradas 7 etiquetas del flujo de menu/intro:

- `TAIL_VDP_CLEAR` (`$5CA0`) -> `LIMPIAR_VRAM_AREA_JUEGO`: limpia el
  area principal de VRAM (patrones $2000-$37FF) tras rellenar el
  buffer de trabajo.
- `TAIL_LEVELCYCLE_HELPER_ALT` (`$647C`) -> `APLICAR_COLOR_CICLO_NIVELES`:
  variante de `APLICAR_COLOR_PANTALLA` para el ciclador de niveles de
  muestra (BC=704 en vez de 768, mismo bucle).
- `TI_5B62` -> `REINICIAR_TIMEOUT_MENU`: reinicia el timeout del menu
  a su valor por defecto (500 frames) y cae en el dibujado del menu.
- `TAIL_MAINMENU_DRAW` (`$5BCC`) -> `DIBUJAR_MENU_PRINCIPAL`: dibuja
  las 5 lineas de texto del menu principal.
- `TAIL_FONT_ROUTINE` (`$5C80`) -> `LEER_TECLAS_MENU_PRINCIPAL`: pese
  al nombre anterior, es el lector de las 6 teclas de navegacion del
  menu (nombre ya propuesto en un comentario de una ronda anterior).
- `TI_5BA7` -> `DESPACHAR_ACCION_MENU`: despacha por bit de A hacia
  las 4 variantes del menu (pausa/disparo, etc.).
- `TVF_LOOP` (dentro de `RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`, uso
  exclusivo ahi) -> `.BUCLE_RELLENAR_FILA` (local): recorre las 144
  filas del buffer rellenando cada una.

`TI_5B62`/`TI_5BA7` NO se pudieron convertir a locales de
`GESTIONAR_INTRODUCCION` pese a estar conceptualmente en su flujo,
porque entre medias hay una etiqueta global distinta
(`RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`) que rompe el ambito.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado:
582 etiquetas (baja 1 por la conversion global->local de `TVF_LOOP`,
patron ya esperado). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/mapa_memoria.html` sincronizado (bloque del lienzo de
bitmap en RAM). Las menciones en `FINDINGS.md` (narrativa historica
de sesiones anteriores) se dejan intactas a proposito, mismo criterio
de siempre.


### TI_5B56 -> MOSTRAR_MENU_PRINCIPAL

Renombrada `TI_5B56` a `MOSTRAR_MENU_PRINCIPAL` (`$5B56`): segundo
punto de entrada real de `.CONTINUAR_INTRO`, llamado externamente
desde `REINICIAR_PARTIDA` en `madmix1_body.asm` -- se salta la espera
de tecla y el dibujado del marco de caramelo (no aplican al arranque
real de una partida), y va directo a preparar y mostrar el menu
principal. Al ser una referencia cruzada entre ficheros, actualizada
tambien la llamada real y su comentario en `madmix1_body.asm`
(`REINICIAR_PARTIDA`, ~linea 2452), que ademas citaba en cascada
varios nombres antiguos ya renombrados en rondas anteriores
(`TAIL_INTRO`, `TAIL_KEYWAIT_UP`, `QUEUE_SCREEN_OFF`,
`TAIL_VDP_CLEAR`, `TAIL_LEVELCYCLE_HELPER_ALT`, `TAIL_MAINMENU_DRAW`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(582 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `src/FLUJO_PROGRAMA.md` sincronizado (2 menciones, una
dentro de un diagrama de caja ASCII -- recalculado el relleno para
mantener el ancho de caja de 65 caracteres). Sincronizada tambien la
mencion recien anadida en una entrada anterior de este mismo fichero.
Las menciones en `FINDINGS.md` (narrativa historica de sesiones
anteriores) se dejan intactas a proposito, mismo criterio de siempre.


### TI_5B65 -> ACTUALIZAR_MENU_PRINCIPAL

Renombrada `TI_5B65` a `ACTUALIZAR_MENU_PRINCIPAL` (nombre elegido por
el usuario, consistente con el patron ya usado en
`ACTUALIZAR_VRAM_FRAME`/`ACTUALIZAR_DESTELLO_ITEMS` para rutinas de
refresco periodico, en vez de `ACTIVAR_X` que sugeriria un disparo
puntual): punto donde converge tanto el inicio del menu (timeout
recien reiniciado por `REINICIAR_TIMEOUT_MENU`) como cada vuelta
posterior del ciclo -- guarda el timeout en `$6043`, dibuja el menu,
enciende pantalla, lee las teclas de navegacion y despacha la accion
correspondiente; se re-ejecuta cada frame mientras el menu esta
activo.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(582 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `src/FLUJO_PROGRAMA.md` sincronizado (2 menciones
directas); esa seccion tiene ademas MUCHOS otros nombres desfasados de
rondas anteriores (`PATCH_OFF_10D8`, `TAIL_MAINMENU_DRAW`,
`TAIL_FONT_ROUTINE`, `TI_5BA7`, `TAIL_INTRO`, etc.) que quedan fuera
de alcance de esta ronda -- limpieza pendiente aparte. Sin menciones
en `recursos/mapa_memoria.html`. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### GESTIONAR_INTRODUCCION/RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM: datos revisados

A peticion del usuario, revisados todos los literales numericos del
bloque completo de `GESTIONAR_INTRODUCCION` y
`RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM`:

- `LD B, $46` -> `LD B, 70` (iteraciones del bucle de espera, ya
  documentado en decimal en una ronda anterior de renombrado).
- `LD BC, $2710` -> `LD BC, 10000` (frames de timeout antes de volver
  a la intro).
- `CP $07` -> `CP 7` (fila 7 de la matriz de teclado).
- `LD B, $90` -> `LD B, 144` (filas del buffer, ya citado en decimal
  en el comentario de cabecera), `LD BC, $0017` -> `23` (bytes del
  area jugable por fila) y `LD BC, $0020` -> `32` (paso de fila,
  mismo patron que el resto del motor).
- HALLAZGO "hex sin sustituir por etiqueta ya existente" (mismo
  patron sistemico de rondas anteriores, esta vez cruzando ficheros):
  `CALL $1000` -> `CALL DIBUJAR_PORTADA` (la propia etiqueta de este
  fichero, ya usada asi en `madmix1_body.asm`/`load_disk`/`load_cas`
  pero nunca corregida aqui) y `LD DE, $CDCB`/`$CDFF`/`$CE0C` ->
  `GUION_MELODIA_CANAL_0`/`_1`/`_2` (etiquetas de `madmix1_body.asm`,
  mismo espacio de nombres al compilar todo en una sola pasada via
  `main.asm`). Tambien convertidos a decimal los indices `LD A,
  $01`/`$02` -> `1`/`2` de las llamadas a `INSTALAR_RECURSO_SONIDO`,
  igual que ya estaba en `INICIO` (`madmix1_body.asm`).
- Queda un `CALL $1000` mas sin corregir en este mismo fichero (linea
  ~4410, funcion distinta, fuera del bloque pedido en esta ronda).
- Dejados en hexadecimal el resto segun la convencion de siempre:
  direcciones (`$4000`, `$909A`), el centinela de relleno (`$FF`), y
  los codigos de tecla/color VDP (`$EB`, `$06`, `$01` de
  `FIJAR_COLOR_BORDE_VDP` -- codigos de matriz/paleta, no conteos).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2) -- confirma que las 4 sustituciones de hex
por etiqueta resuelven a las mismas direcciones exactas que el hex
original. Cambio puramente de notacion/comentarios/etiquetas
existentes, ninguna etiqueta nueva ni renombrada -- no ha hecho falta
regenerar inventario ni `.dsk`/`.cas`.


### TI_5C3A/TI_5C53/TI_5C60/TI_5C70 -> SELECCIONAR_OPCION_*

Renombradas las 4 rutinas de seleccion del menu principal (cada una
automodifica los bytes de atributo de `TEXTO_MENU_PRINCIPAL` (antes `MAINMENU_TEXT`) para resaltar
la opcion actual):

- `TI_5C3A` (opcion 3, redefine teclas) -> `SELECCIONAR_OPCION_REDEFINIR_TECLAS`
- `TI_5C53` (opcion 4, demo) -> `SELECCIONAR_OPCION_DEMO`
- `TI_5C60` (opcion 1, teclado) -> `SELECCIONAR_OPCION_TECLADO`
- `TI_5C70` (opcion 2, joystick) -> `SELECCIONAR_OPCION_JOYSTICK`

Las 4 tienen que seguir siendo globales: entre `DESPACHAR_ACCION_MENU`
y ellas hay 2 etiquetas globales intermedias (`GESTIONAR_TIMEOUT_MENU`, antes `TAIL_BITDISPATCH_END`,
`DIBUJAR_MENU_PRINCIPAL`) que romperian el ambito si se intentaran
convertir a locales.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `src/FLUJO_PROGRAMA.md` sincronizado (tabla
de las 4 opciones del menu). Sin menciones en
`recursos/mapa_memoria.html`. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### TAIL_BITDISPATCH_END -> GESTIONAR_TIMEOUT_MENU

Renombrada `TAIL_BITDISPATCH_END` a `GESTIONAR_TIMEOUT_MENU`: punto al
que se cae (nadie salta aqui explicitamente) cuando ninguna de las 4
opciones del menu coincidio con la tecla leida en
`DESPACHAR_ACCION_MENU`. Gestiona el temporizador del menu: si `A!=0`
(otra tecla no reconocida) reinicia el timeout y vuelve a mostrar el
menu; si `A==0` (sin tecla) decrementa el contador y, al llegar a 0,
vuelve a `GESTIONAR_INTRODUCCION` (modo attract) en vez de esperar
para siempre.

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(582 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sincronizada tambien la mencion recien anadida en una
entrada anterior de este mismo fichero. Las menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores) se dejan intactas a
proposito, mismo criterio de siempre.


### MAINMENU_TEXT -> TEXTO_MENU_PRINCIPAL

Renombrada `MAINMENU_TEXT` a `TEXTO_MENU_PRINCIPAL`: los 5 registros
de texto del menu principal ("1 TECLADO", "2 JOYSTICK", "3 REDEFINE
TECLAS", "4 DEMO", "0 JUGAR"), dibujados por `DIBUJAR_MENU_PRINCIPAL`.
Mismo patron `TEXTO_X` ya establecido (`TEXTO_FASE`, `TEXTO_READY`,
`TEXTO_GAME_OVER`, `TEXTO_DEMO`, `TEXTO_BESTIA`).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(582 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. `src/FLUJO_PROGRAMA.md` sincronizado (1 mencion).
Sincronizada tambien la mencion recien anadida en una entrada anterior
de este mismo fichero. Sin menciones en `recursos/mapa_memoria.html`.


### pattern_loop -> .BUCLE_VOLCAR_PATRON_PORTADA (local)

Renombrado el bucle local `.pattern_loop` (dentro de `DIBUJAR_PORTADA`)
a `.BUCLE_VOLCAR_PATRON_PORTADA`: vuelca byte a byte los 6144 bytes de
`PORTADA_PATRON` a la tabla de patrones de VRAM ($0000).

**Verificado**: recompilado sin errores, diffs en la linea base
exacta de siempre (7/2). `recursos/flujo_programa.html` regenerado
(621 etiquetas, sin cambio de total). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `FINDINGS.md`.


### TAIL_KEYMENU_DRAW/TAIL_LEVELCYCLE_MAIN/TAIL_UNK_5C93/TAIL_VDP_PATTERN_WRITE renombradas

Renombradas las 4 ultimas etiquetas de la familia `TAIL_` en esta
zona del menu/demo:

- `TAIL_KEYMENU_DRAW` (`$5D1F`) -> `DIBUJAR_MENU_REDEFINIR_TECLAS`:
  dibuja el submenu completo de redefinicion de teclas.
- `TAIL_LEVELCYCLE_MAIN` (`$6045`) -> `GESTIONAR_CICLO_NIVELES`:
  motor del ciclado de niveles de muestra (modo demo, opcion 4).
- `TAIL_UNK_5C93` -> `TABLA_TECLAS_MENU_PRINCIPAL`: tabla de 12 bytes
  (6 parejas fila/mascara, todas fila `$F0`) usada por
  `LEER_TECLAS_MENU_PRINCIPAL` para leer las 6 teclas de seleccion del
  menu principal.
- `TAIL_VDP_PATTERN_WRITE` (`$5CAF`) -> `ESCRIBIR_PATRON_VRAM`:
  escribe un patron de 8 filas en VRAM via doble `FILVRM`/`LDIRVM`.

A peticion del usuario, se reorganizo ademas `TABLA_TECLAS_MENU_PRINCIPAL`
en 6 lineas `DB` (una pareja por linea, mismo formato que
`TABLA_TECLAS_MSX`) con un comentario por pareja indicando a que bit
final del resultado corresponde y que opcion de menu dispara (deducido
rastreando `ESCANEAR_FILAS_TECLADO` -- cada `RL E` desplaza los bits ya
leidos, asi que la ULTIMA pareja de la tabla acaba en el bit 0 del
resultado y la PRIMERA en el bit mas alto -- y `DESPACHAR_ACCION_MENU`,
que comprueba los bits 5/1/3/4). HALLAZGO: las parejas 4 y 5 de la
tabla son IDENTICAS (`$F0,$08` las dos) -- leen la misma tecla dos
veces; el bit que produce la pareja 4 (bit 2 del resultado) no se
comprueba en ningun sitio, es un bit muerto/desperdiciado del diseno
original.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado (582
etiquetas, sin cambio de total, las 4 son renombrados 1:1). `.dsk`/
`.cas` regenerados sin incidencias. Unica mencion en
`recursos/mapa_memoria.html` (`TAIL_LEVELCYCLE_MAIN` en el bloque
`0xD524-0xD6B6`) sincronizada. Sin tocar `src/FLUJO_PROGRAMA.md`: las
4 etiquetas solo aparecen dentro del gran parrafo de la seccion 5.8 ya
señalado como desfasado y fuera de alcance en una ronda anterior
(sigue conteniendo muchos otros nombres antiguos sin actualizar,
p.ej. `TI_5BA7`, `TAIL_INTRO`, `TAIL_FONT_ROUTINE`) -- limpieza
pendiente aparte, mismo criterio de siempre.


### TD_LOOP/TD_SKIP/TD_INCDE -> locales de DIBUJAR_TEXTO_VRAM

Confirmado por grep que las 3 etiquetas son puramente internas a
`DIBUJAR_TEXTO_VRAM` (ningun otro fichero las referencia), convertidas
a locales:

- `TD_LOOP` -> `.BUCLE_CARACTER`: bucle principal que recorre los `C`
  "caracteres" del registro de texto; si el byte leido es `>=$20`
  (codigo de patron real) llama a `ESCRIBIR_PATRON_VRAM` y avanza `HL`
  8 columnas.
- `TD_SKIP` -> `.SALTAR_COLUMNAS`: HALLAZGO -- los bytes `<$20` NO son
  caracteres imprimibles, son un CONTADOR de columnas de 8px en
  blanco a saltar (el propio byte se usa como cuenta del bucle,
  sumando 8 a `L` cada vuelta). Es el mecanismo de huecos/espaciado
  del formato de texto de este juego.
- `TD_INCDE` -> `.CONTINUAR_CARACTER`: cola comun a ambos caminos
  (avanza `DE`, decrementa `C`, repite `.BUCLE_CARACTER` o sale con
  `EI`/`RET`).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 579
etiquetas (582 -> 579, -3 por ser 3 conversiones global->local).
`.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.


### LIMPIAR_VRAM_AREA_JUEGO/ESCRIBIR_PATRON_VRAM/DIBUJAR_TEXTO_VRAM: datos revisados

A peticion del usuario, revisados todos los literales numericos del
bloque completo (`LIMPIAR_VRAM_AREA_JUEGO`, `ESCRIBIR_PATRON_VRAM`,
`DIBUJAR_TEXTO_VRAM`):

- `LD BC, $1800` -> `LD BC, 6144` (tamano completo de la tabla de
  patrones de VRAM, `$2000-$37FF`, ya citado en decimal en el
  comentario de cabecera de la rutina anterior).
- `LD BC, $0008` (x2, en `ESCRIBIR_PATRON_VRAM`) y `LD A, $08` (x2, en
  `DIBUJAR_TEXTO_VRAM`) -> `8` (mismo stride "8 columnas/8 filas" ya
  documentado en los comentarios de cabecera).
- `LD H, $00` / `ADC A, $00` -> `0`.
- `LD HL, $2000`/`LD DE, $925B`/`CP $20` se dejan en hex (direcciones
  de VRAM/RAM y umbral de codigo de caracter). `LD A, $01` en
  `LIMPIAR_VRAM_AREA_JUEGO` tambien se deja en hex: no es un contador,
  es el propio patron de bits (bit 0 activo) que `FILVRM` vuelca en
  cada byte de la tabla de patrones.
- HALLAZGO (arquitectura, no solo formato): el "2o byte" de cabecera
  de `DIBUJAR_TEXTO_VRAM` (guardado en `AF'` con el primer
  `EX AF,AF'`) no se usaba en ningun sitio VISIBLE del bucle principal
  -- se recupera dentro de `ESCRIBIR_PATRON_VRAM` (su propio
  `EX AF,AF'`+`PUSH AF`) justo antes de la segunda mitad
  `FILVRM`/`SET 5,H`. Es decir: el registro de texto no solo trae el
  numero de caracteres y la tabla de codigos, tambien el valor de
  color/atributo a rellenar en la mitad "color" de cada patron de 8
  filas -- documentado ahora en los comentarios de cabecera de ambas
  rutinas.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (`gen_inventory.py` no
aplica). `.dsk`/`.cas` regenerados sin incidencias.


### TJR_LOOP -> .BUCLE_FILA (local de COMPROBAR_PULSACION)

Renombrada `TJR_LOOP` (`$5D0C`) a `.BUCLE_FILA`, local de
`COMPROBAR_PULSACION` (`$5D0A`, sin referencias externas confirmadas
por grep): recorre las 9 filas (0-8) de la matriz de teclado
seleccionando cada una por el puerto `$AA` (preservando el nibble alto
con `AND $F0` y sumando el numero de fila) y leyendo columnas por
`$A9`; sale con `NZ` si encuentra alguna tecla pulsada en la fila
actual, o con `Z` si agota las 9 filas sin encontrar ninguna.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 578
etiquetas (579 -> 578, -1 por ser global->local). `.dsk`/`.cas`
regenerados sin incidencias. Sin menciones en
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.


### TAIL_FONT_CLEAR/TAIL_FONT_SELECT/TAIL_KEYMENU_HILITE + locales de DIBUJAR_MENU_REDEFINIR_TECLAS renombradas

Renombrado el resto del bloque del submenu de redefinicion de teclas:

- `TAIL_FONT_CLEAR` (`$5EDA`) -> `REINICIAR_TECLAS_USADAS`: pese al
  nombre no tiene nada que ver con fuentes -- limpia (`RES 7`) las 72
  posiciones de una tabla de "usadas" (reutiliza la tabla de tipo de
  loseta compartida `$8E88` como scratch) antes de empezar a detectar
  pulsaciones nuevas.
- `TAIL_FONT_SELECT` (`$5EEB`) -> `ESPERAR_TECLA_NUEVA`: recorre las 9
  filas de la matriz de teclado buscando la primera tecla NUEVA (bit 7
  a 0 en su entrada de la tabla de "usadas"), la marca y escribe el
  par fila/mascara real de esa tecla en el buffer de redefinicion,
  guardando ademas un indice lineal (0-71) en `$5F76`.
- `TAIL_KEYMENU_HILITE` (`$5DF1`) -> `DIBUJAR_NOMBRE_TECLA_ASIGNADA`:
  busca en la tabla de nombres de tecla (`$5E56`) la entrada numero
  `B` y salta a `DIBUJAR_TEXTO_VRAM` para dibujarla. Su bucle interno
  local `KH_LOOP` -> `.BUCLE_BUSCAR_NOMBRE`.
- `KMD_5D46`/`KMD_5D67`/`KMD_5D88`/`KMD_5DA9`/`KMD_5DCA` (puntos de
  reunion entre los 6 bloques casi identicos de
  `DIBUJAR_MENU_REDEFINIR_TECLAS`, uno por accion redefinible) ->
  locales `.CONTINUAR_TECLA_2`.`.CONTINUAR_TECLA_3`.`.CONTINUAR_TECLA_4`.
  `.CONTINUAR_TECLA_5`.`.CONTINUAR_TECLA_6`.
- `KMD_5DEB` -> `.FIN_DIBUJAR_MENU`: ademas de cerrar el 6o bloque, es
  la cola real de la funcion (espera a soltar y luego pulsar una
  tecla antes de salir).

Todas las locales confirmadas sin referencias externas por grep antes
de convertir.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 571
etiquetas (578 -> 571, -7 por las 7 conversiones global->local: 6
`KMD_*` + `KH_LOOP`; las otras 3 son renombrados globales 1:1).
`.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md`. `src/FLUJO_PROGRAMA.md` NO tocado: `TAIL_KEYMENU_HILITE`/
`TAIL_FONT_SELECT` solo aparecen dentro del mismo gran parrafo de la
seccion 5.8 ya señalado como desfasado y fuera de alcance en rondas
anteriores.


### KEYMENU_TEXT_5E03 -> TEXTO_MENU_REDEFINIR_TECLAS

Renombrada `KEYMENU_TEXT_5E03` (`$5E03`-`$5ED9`, 215 bytes) a
`TEXTO_MENU_REDEFINIR_TECLAS`: la tabla de texto completa del submenu
de redefinicion de teclas -- los 6 nombres de accion (PAUSA, FUEGO,
ARRIBA, ABAJO, IZQUIERDA, DERECHA) seguidos de los ~28 nombres de
tecla asignables, cada registro en formato
`[longitud][atributo][texto ASCII]`. Mismo patron `TEXTO_X` ya
establecido (`TEXTO_MENU_PRINCIPAL`, `TEXTO_FASE`...).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (571, renombrado 1:1).
`.dsk`/`.cas` regenerados sin incidencias. Las menciones en
`src/README.md` (checklist tachado, narrativa historica) y
`src/FLUJO_PROGRAMA.md` (mismo parrafo de la seccion 5.8 ya desfasado)
se dejan intactas, mismo criterio de siempre.


### TFC_LOOP -> .BUCLE_LIMPIAR_MARCAS (local de REINICIAR_TECLAS_USADAS)

Renombrada `TFC_LOOP` a `.BUCLE_LIMPIAR_MARCAS`, local de
`REINICIAR_TECLAS_USADAS` (sin referencias externas confirmadas por
grep): recorre las 72 posiciones de la tabla `$5F2C` limpiando el bit
7 (marca de "usada") de cada una.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 570
etiquetas (571 -> 570, -1 por ser global->local). `.dsk`/`.cas`
regenerados sin incidencias. Sin menciones en
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.


### REINICIAR_TECLAS_USADAS: datos revisados + hallazgo "$8E88 no tiene etiqueta?"

A peticion del usuario, revisados los literales de
`REINICIAR_TECLAS_USADAS`: `LD B, $48` -> `LD B, 72` (numero de
entradas a limpiar). De paso, el usuario pregunto si `$8E88` (usado
como direccion base del buffer scratch) tenia etiqueta propia --
CONFIRMADO: es exactamente `TABLA_TECLAS_MSX` (`madmix1_body.asm:2333`,
mismo espacio de nombres al compilar via `main.asm`), mismo patron
sistemico "hex sin sustituir por etiqueta ya existente" de rondas
anteriores. Corregido `LD HL, $8E88` -> `LD HL, TABLA_TECLAS_MSX`.

HALLAZGO adicional: el comentario de cabecera de la rutina ("limpia la
tabla de tipo de loseta compartida $8E88") era una hipotesis antigua
EQUIVOCADA -- no existe ninguna tabla de tipo de loseta en esa
direccion (las reales viven en `$2E3C`/`$FC50`, sin relacion). Se
corrigio el comentario para reflejar que en realidad reutiliza
`TABLA_TECLAS_MSX` como buffer scratch.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismo byte de direccion, solo cambia la fuente).
Sin cambio de etiquetas. `.dsk`/`.cas` regenerados sin incidencias.


### TFS_ROW0/TFS_ROW/TFS_BIT/TFS_NEXTBIT/TFS_SHIFT/TFS_FOUND -> locales de ESPERAR_TECLA_NUEVA + HALLAZGO: TABLA_TECLAS_MSX es el destino real de la redefinicion

Renombradas las 6 etiquetas internas de `ESPERAR_TECLA_NUEVA`, todas
locales (sin referencias externas confirmadas por grep):

- `TFS_ROW0` -> `.REINICIAR_ESCANEO`: punto de reinicio del escaneo
  completo (`DE=$F000`, fila inicial + indice lineal a 0).
- `TFS_ROW` -> `.BUCLE_FILA`: bucle por fila (selecciona fila en
  `$AA`, lee columnas de `$A9`).
- `TFS_BIT` -> `.BUCLE_BIT`: bucle por bit de la fila; si esta a 0
  (tecla pulsada) salta a manejarla.
- `TFS_NEXTBIT` -> `.TECLA_DETECTADA`: reconstruye la mascara de bit
  real y escribe el par fila/mascara.
- `TFS_SHIFT` -> `.BUCLE_CONSTRUIR_MASCARA`: bucle que reconstruye la
  mascara de un solo bit a partir de la posicion donde se rompio el
  bucle de bits.
- `TFS_FOUND` -> `.TECLA_NUEVA`: la tecla no estaba ya usada -- la
  marca, guarda su valor en `$5F76` y actualiza el puntero de
  escritura.

HALLAZGO de arquitectura (no solo naming): el puntero de escritura
(`$5F74`) que `.TECLA_DETECTADA` usa para volcar cada par fila/mascara
detectado apunta a `TABLA_TECLAS_MSX` (`madmix1_body.asm`, ver ronda
anterior de este mismo fichero) -- y NO es un buffer scratch como se
penso en la ronda anterior: es el DESTINO REAL de la redefinicion.
Hay exactamente 6 acciones redefinibles = 6 pares fila/mascara = 12
bytes = el tamano exacto de `TABLA_TECLAS_MSX`, asi que el submenu de
redefinicion sobreescribe en caliente, byte a byte, la tabla real que
usa `LEER_TECLADO` para leer arriba/abajo/izquierda/derecha/disparo/
pausa. Comentarios corregidos en `REINICIAR_TECLAS_USADAS`/
`ESPERAR_TECLA_NUEVA` para reflejarlo. Ademas, la tabla de 72
"marcas" en `$5F2C` limpiadas por `REINICIAR_TECLAS_USADAS` resulto
ser `FONT_CHARSET_5F2C` (renombrada a `TABLA_CODIGOS_TECLA` en la
siguiente ronda, ver mas abajo): sus 72 bytes de datos reales
(digitos/simbolos/A-Z + 24 codigos especiales) sirven de "mapa de
caracteres validos", y el mecanismo de "tecla usada" reutiliza el bit
7 (siempre 0 en esos valores) como flag superpuesto.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 564
etiquetas (570 -> 564, -6 por las 6 conversiones global->local).
`.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md`.


### FONT_CHARSET_5F2C -> TABLA_CODIGOS_TECLA + reorganizada en 9 filas con comentarios

Renombrada `FONT_CHARSET_5F2C` a `TABLA_CODIGOS_TECLA`: CORREGIDO, no
es una fuente/bitmap -- es el mapa de 72 posiciones de escaneo de
teclado (fila x8+bit, mismo orden que `ESPERAR_TECLA_NUEVA`) a
identidad de esa tecla. Descifrado fila a fila cruzando los datos con
el orden de escaneo:

- Filas `$F0`-`$F5` (48 bytes): glifo ASCII imprimible real de esa
  tecla (digitos, simbolos, A-Z), pasable tal cual a
  `ESCRIBIR_PATRON_VRAM`.
- Filas `$F6`-`$F8` (24 bytes): codigo especial `1`-`24`, indice a
  `TEXTO_MENU_REDEFINIR_TECLAS` para teclas no imprimibles (de ahi el
  `CP $24` de `DIBUJAR_MENU_REDEFINIR_TECLAS`: decide entre dibujar el
  nombre completo o el glifo suelto).
- 3 bytes finales de relleno, nunca alcanzados (el escaneo real solo
  cubre 72 posiciones).

A peticion del usuario, reorganizada de un bloque plano de hex a 9
lineas (una por fila de teclado), con comentario de fila; las 6 filas
de glifos imprimibles como literales de cadena (`DB "01234567"`, etc,
salvo backslash/llaves/punto y coma sueltos de la fila `$F1` y el `:`/
espacio de la fila `$F2`, separados en literales de caracter/hex para
no romper el string) y las 3 filas de codigos especiales en decimal
(son indices, no mascaras). Verificado que SjASMPlus acepta `\`/`{`/
`}`/`;` dentro de un literal de cadena sin necesitar escape. Tambien
sustituidos los 2 usos de `$5F2C` sin etiqueta (en
`REINICIAR_TECLAS_USADAS`/`ESPERAR_TECLA_NUEVA`) por
`TABLA_CODIGOS_TECLA`.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes, solo cambia formato/etiqueta). Sin
cambio de etiquetas (564, renombrado 1:1). `.dsk`/`.cas` regenerados
sin incidencias. Mencion en `src/FLUJO_PROGRAMA.md` NO tocada (mismo
parrafo de la seccion 5.8 ya desfasado). Mencion antigua en
`FINDINGS.md` (linea ~4353, narrativa historica de una sesion muy
anterior) dejada intacta; la mencion de la entrada anterior (esta
misma sesion) corregida hacia adelante arriba.


### HALLAZGO: los "3 bytes de relleno" tras TABLA_CODIGOS_TECLA eran PUNTERO_ESCRITURA_TECLA/CODIGO_TECLA_ACTUAL

A peticion del usuario, revisadas las direcciones hex sueltas
(`$5F74`/`$5F76`) del bloque `REINICIAR_TECLAS_USADAS`/
`ESPERAR_TECLA_NUEVA`/`DIBUJAR_MENU_REDEFINIR_TECLAS`. No
correspondian a ninguna etiqueta previa, pero SI encajaban por
desplazamiento: los 3 bytes que se habian dejado como "relleno, nunca
alcanzado" al final de `TABLA_CODIGOS_TECLA` (`$5F74`-`$5F76`, justo
tras sus 72 entradas reales `$5F2C`-`$5F73`) NO son relleno inerte --
son exactamente el tamano de las dos variables reales que usa este
mismo bloque de codigo. Confirmado por aritmetica exacta:
`DIBUJAR_CREDITOS` empieza en `$5F77` = `$5F74`+3.

Divididos esos 3 bytes en dos etiquetas propias (mismo valor inicial
0, mismos bytes):
- `PUNTERO_ESCRITURA_TECLA` (word, `$5F74`-`$5F75`): puntero de
  escritura hacia `TABLA_TECLAS_MSX` durante la redefinicion.
- `CODIGO_TECLA_ACTUAL` (byte, `$5F76`): codigo de la tecla asignada
  actual, leido tambien por `DIBUJAR_MENU_REDEFINIR_TECLAS`.

Sustituidos todos los usos de `$5F74`/`$5F76` (codigo y comentarios)
por las nuevas etiquetas.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes -- la aritmetica de direcciones era
exacta). `recursos/flujo_programa.html` regenerado: 566 etiquetas
(564 -> 566, +2 por las 2 etiquetas nuevas). `.dsk`/`.cas` regenerados
sin incidencias. Sin menciones en `src/FLUJO_PROGRAMA.md`.


### Etiquetas propias para cada registro de TEXTO_MENU_REDEFINIR_TECLAS referenciado por direccion

A peticion del usuario, revisadas las direcciones hex dentro del
rango de `TEXTO_MENU_REDEFINIR_TECLAS` (`$5E03`-`$5ED9`). Encontradas
7, las 6 usadas en `DIBUJAR_MENU_REDEFINIR_TECLAS` (como `DE` para
`DIBUJAR_TEXTO_VRAM`, apuntando cada una al registro de una accion
redefinible) mas 1 en `DIBUJAR_NOMBRE_TECLA_ASIGNADA` (inicio de la
sub-seccion de nombres de tecla indexada por `B`). En vez de
expresarlas como `TABLA+offset`, se creo una etiqueta propia por cada
registro referenciado (mismo criterio que `GUION_MELODIA_CANAL_0/1/2`
en `madmix1_body.asm`: piezas de datos distintas dentro de un mismo
bloque, cada una con su propia etiqueta):

- `$5E0A` (FUEGO) -> `TEXTO_TECLA_FUEGO`
- `$5E11` (ARRIBA) -> `TEXTO_TECLA_ARRIBA`
- `$5E19` (ABAJO) -> `TEXTO_TECLA_ABAJO`
- `$5E20` (IZQUIERDA) -> `TEXTO_TECLA_IZQUIERDA`
- `$5E2B` (DERECHA) -> `TEXTO_TECLA_DERECHA`
- `$5E03` (PAUSA) -> ya tenia etiqueta: es el propio inicio de
  `TEXTO_MENU_REDEFINIR_TECLAS`, solo se sustituyo el hex por ella.
- `$5E56` (inicio de la sub-tabla de nombres de tecla asignable,
  indexada por el codigo especial 1-24 de `TABLA_CODIGOS_TECLA`) ->
  `TABLA_NOMBRES_TECLA_ASIGNABLE` (coincide exactamente con la entrada
  degenerada `DB $01,$01,$01`, justo tras `ENTER`).

Precedente NO aplicado (a proposito) a `TEXTO_MENU_PRINCIPAL`/
`DIBUJAR_MENU_PRINCIPAL` (mismo patron de 5 punteros `DE` hex): queda
como posible ronda separada, no pedida esta vez.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes -- offsets exactos). `recursos/flujo_programa.html`
regenerado: 572 etiquetas (566 -> 572, +6 etiquetas nuevas). `.dsk`/
`.cas` regenerados sin incidencias. Sin menciones en
`src/FLUJO_PROGRAMA.md`.


### Etiquetadas TODAS las entradas de TEXTO_MENU_REDEFINIR_TECLAS, incluidas las sin referencias actuales

A peticion del usuario, etiquetadas las 24 entradas restantes de la
tabla que aun estaban sin etiqueta propia (algunas sin ninguna
referencia en el resto del codigo transcrito por ahora):

- `TEXTO_TECLA_ESPACIO_1`/`TEXTO_TECLA_SSHIFT`/`TEXTO_TECLA_CSHIFT`/
  `TEXTO_TECLA_ENTER_1`: las 4 entradas entre `DERECHA` y
  `TABLA_NOMBRES_TECLA_ASIGNABLE` -- sin referencias actuales.
- Las 24 entradas indexadas por el codigo especial 1-24 de
  `TABLA_CODIGOS_TECLA` (destino real de `DIBUJAR_NOMBRE_TECLA_ASIGNADA`):
  `TEXTO_TECLA_SHIFT`(1), `_CTRL`(2), `_GRAPH`(3), `_CAPS`(4),
  `_CODE`(5, HALLAZGO: texto vacio -- un solo espacio -- en la
  posicion que le corresponde a CODE en la fila estandar SHIFT/CTRL/
  GRAPH/CAPS/CODE), `_F1`..`_F5`(6-10), `_ESCAPE`(11), `_TAB`(12),
  `_STOP`(13), `_BS`(14), `_SELECT`(15), `_ENTER_2`(16, duplicado de
  `_ENTER_1`), `_ESPACIO_2`(17, duplicado de `_ESPACIO_1`), `_HOME`(18),
  `_INS`(19), `_DEL`(20), `_EXCLAMACION`(21), `_COMILLAS`(22),
  `_ALMOHADILLA`(23), `_DOLAR`(24).

Cada entrada con un comentario indicando su codigo especial (o "sin
referencias actuales" para las 4 previas al indice). Formato de datos
sin cambios (mismas cadenas/bytes, solo se anadieron etiquetas).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes). `recursos/flujo_programa.html`
regenerado: 600 etiquetas (572 -> 600, +28 etiquetas nuevas). `.dsk`/
`.cas` regenerados sin incidencias. Sin menciones en `FINDINGS.md`/
`src/FLUJO_PROGRAMA.md`.


### Anadida TEXTO_TECLA_PAUSA (misma direccion que TEXTO_MENU_REDEFINIR_TECLAS)

El usuario senalo que faltaba etiqueta propia para la entrada PAUSA,
aunque coincida con la direccion de la etiqueta global de la tabla.
Anadida `TEXTO_TECLA_PAUSA:` justo debajo de `TEXTO_MENU_REDEFINIR_TECLAS:`
(mismo byte, dos etiquetas a la misma direccion, mismo patron que el
resto de entradas con nombre propio). Sustituido el `LD DE,
TEXTO_MENU_REDEFINIR_TECLAS` de `DIBUJAR_MENU_REDEFINIR_TECLAS` por
`LD DE, TEXTO_TECLA_PAUSA`, consistente con las otras 5 acciones.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes). `recursos/flujo_programa.html`
regenerado: 601 etiquetas (600 -> 601, +1). `.dsk`/`.cas` regenerados
sin incidencias.


### Mismo tratamiento para TEXTO_MENU_PRINCIPAL/DIBUJAR_MENU_PRINCIPAL

A peticion del usuario, aplicado el mismo criterio que
`TEXTO_MENU_REDEFINIR_TECLAS` a la tabla gemela `TEXTO_MENU_PRINCIPAL`
(dejada pendiente a proposito en una ronda anterior): etiqueta propia
por cada uno de los 5 registros, incluida la primera (coincide con la
direccion de la etiqueta global de la tabla, mismo patron que
`TEXTO_TECLA_PAUSA`):

- `$5BF9` (TECLADO) -> `TEXTO_OPCION_TECLADO` (misma direccion que
  `TEXTO_MENU_PRINCIPAL`)
- `$5C06` (JOYSTICK) -> `TEXTO_OPCION_JOYSTICK`
- `$5C14` (REDEFINE TECLAS) -> `TEXTO_OPCION_REDEFINIR_TECLAS`
- `$5C27` (DEMO) -> `TEXTO_OPCION_DEMO`
- `$5C2F` (JUGAR) -> `TEXTO_OPCION_JUGAR`

Sustituidos los 5 `LD DE,` de `DIBUJAR_MENU_PRINCIPAL`. De paso,
tambien sustituidos los bytes de atributo automodificados por las 4
rutinas `SELECCIONAR_OPCION_*` (`$5BFA`/`$5C07`, offset +1 de las dos
primeras entradas) por `TEXTO_OPCION_TECLADO+1`/
`TEXTO_OPCION_JOYSTICK+1` (aritmetica etiqueta+offset, mismo patron ya
usado con `TABLA_TECLAS_MSX+10`).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes -- offsets exactos). `recursos/flujo_programa.html`
regenerado: 606 etiquetas (601 -> 606, +5). `.dsk`/`.cas` regenerados
sin incidencias. Sin menciones en `src/FLUJO_PROGRAMA.md`/
`recursos/mapa_memoria.html`.


### TAIL_CREDITS_TEXT -> TEXTO_CREDITOS_PROGRAMADO_POR + etiqueta por entrada + HALLAZGO: "MAD$MIX GAME" SI se dibuja (es la primera de las 8 llamadas, no la que falta)

A peticion del usuario, revisadas las direcciones hex de
`DIBUJAR_CREDITOS`. Las 8 caian dentro de la tabla de creditos, pero
solo la primera (`TAIL_CREDITS_TEXT`) tenia etiqueta propia. Creadas
las 7 restantes y renombrada la tabla (de paso corrige el prefijo
`TAIL_` desfasado):

- `TAIL_CREDITS_TEXT` -> `TEXTO_CREDITOS_PROGRAMADO_POR` ("POGRAMADO BY:")
- `$5FD4` -> `TEXTO_CREDITOS_NOMBRE_PROGRAMADOR` ("RAPHAEL GOMEZZZ..")
- `$5FE8` -> `TEXTO_CREDITOS_GRAFICOS_POR` ("GRAPHICOS BY :")
- `$5FFA` -> `TEXTO_CREDITOS_NOMBRE_GRAFICOS` ("ROBERTO P.ACEBES")
- `$600C` -> `TEXTO_CREDITOS_MUSICA_POR` ("MUSIC-A BY:")
- `$6019` -> `TEXTO_CREDITOS_NOMBRE_MUSICA` ("COMILONAS")
- `$6024` -> `TEXTO_CREDITOS_TOPOSHOW` ("TOPOSHOW -1988-")
- `$6035` -> `TEXTO_CREDITOS_TITULO` ("MAD$MIX GAME")

HALLAZGO (corrige una nota historica equivocada): la entrada
`"MAD$MIX GAME"` (`TEXTO_CREDITOS_TITULO`) tenia un comentario que
decia que "no se alcanza desde ninguna de las 8 llamadas" de
`DIBUJAR_CREDITOS`. Es incorrecto -- SI se alcanza: es la PRIMERA de
las 8 llamadas (`HL=$0248`, arriba del todo de la pantalla), pese a
estar colocada la ULTIMA en el layout de datos (la rutina usa
direcciones literales hardcoded, no un bucle secuencial, tal y como
ya advertia el comentario de cabecera de la tabla). De paso corregido
el comentario de cabecera de `DIBUJAR_CREDITOS` ("7 patrones fijos" ->
son 8).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes). `recursos/flujo_programa.html`
regenerado: 613 etiquetas (606 -> 613, +7). `.dsk`/`.cas` regenerados
sin incidencias. Mencion en `madmix_scr_body.asm:3445` (comentario en
otra funcion) tambien actualizada. Menciones en `FINDINGS.md`
(narrativa historica de sesiones anteriores, incluida una nota "TAIL_
CREDITS_TEXT/etc. todavia sin tocar" de una ronda anterior de esta
misma sesion, correcta en su momento) y `src/README.md` (checklist
tachado) dejadas intactas. Sin menciones en `src/FLUJO_PROGRAMA.md`.


### GESTIONAR_CICLO_NIVELES/DESPACHAR_EFECTO_SONIDO/APLICAR_COLOR_PANTALLA/REUBICADOR_REINICIO_JUEGO: 11 etiquetas renombradas

Renombrado el resto de la region del ciclador de niveles de muestra,
el despachador de sonido y el segundo reubicador:

- `TLC_LOOP`/`TLC_INNER`/`TLC_5CAD`/`TLC_END` (locales de
  `GESTIONAR_CICLO_NIVELES`, sin refs externas) -> `.BUCLE_NIVEL_DEMO`/
  `.REPRODUCIR_GUION_DEMO`/`.COMPROBAR_FIN_GUION`/`.FIN_CICLO_NIVELES`.
- `LEVELCYCLE_TABLE` -> `TABLA_CICLO_NIVELES`: la tabla de 4 entradas
  `[nivel,puntero]` que consume el bucle anterior.
- `TAIL_LEVELCYCLE_HELPER` -> `DESPACHAR_EFECTO_SONIDO`: HALLAZGO, pese
  al nombre NO es parte del ciclador de niveles -- es el despachador
  de efectos de sonido llamado en CADA VBLANK (si hay evento pendiente
  en `$6128` instala su script; siempre hace tick al reproductor PSG).
  Referencia cruzada real (`CALL`) desde `madmix1_body.asm` actualizada.
- `LEVELCYCLE_RESOURCE_TABLE` -> `TABLA_RECURSOS_SONIDO_EVENTO`: la
  tabla `[canal,puntero]` que indexa el despachador anterior.
- `TLH2_LOOP` (local de `DIBUJAR_MARCO_CARAMELO_VRAM`) ->
  `.BUCLE_DESCOMPRIMIR_MARCO`.
- `TCM_ENTRY2` -> `APLICAR_COLOR_DESDE_TABLA`: segundo punto de entrada
  de `APLICAR_COLOR_PANTALLA`, sigue global porque
  `APLICAR_COLOR_CICLO_NIVELES` salta aqui directamente desde fuera.
- `TCM_LOOP` (local, bajo el alcance de `APLICAR_COLOR_DESDE_TABLA`) ->
  `.BUCLE_APLICAR_COLOR`.
- `TAIL_RELOCATOR2` -> `REUBICADOR_REINICIO_JUEGO`: segunda rutina de
  reubicacion gemela a la de `MADMIX0.BIN`, sin llamador confirmado
  todavia.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 607
etiquetas (613 -> 607, -6 por las 6 conversiones global->local).
`.dsk`/`.cas` regenerados sin incidencias. `src/FLUJO_PROGRAMA.md`
sincronizado (2 menciones directas en secciones activas, §2 y §5.9);
las menciones restantes (`TAIL_LEVELCYCLE_HELPER2`/`TAIL_RELOCATOR2`/
`LEVELCYCLE_TABLE`/`LEVELCYCLE_RESOURCE_TABLE` en el gran parrafo de
la seccion 5.8 ya desfasado) dejadas intactas, mismo criterio de
siempre. `recursos/mapa_memoria.html` sincronizado (bloques
`0x5AE9-0x6500` y `0xD244-0xD524`/`0xD524-0xD6B6`, 4 menciones); la
mencion "antes TAIL_LEVELCYCLE_HELPER2" (nombre historico distinto,
ya resuelto en una ronda anterior) dejada intacta.


### TABLA_CICLO_NIVELES reorganizada: nivel en decimal + punteros con etiqueta real

A peticion del usuario, revisado si `TABLA_CICLO_NIVELES` conviene en
hex o decimal: cada registro de 3 bytes mezclaba un indice de nivel
(decimal, como el resto de indices simples) con un puntero de 2 bytes
que, HALLAZGO, coincidia exacto con `GUION_DEMO_NIVEL1`/`_NIVEL2`/
`_NIVEL4`/`_NIVEL5` (`madmix1_body.asm`, mismo espacio de nombres
compartido via `main.asm`) -- mismo patron sistemico de "hex sin
sustituir por etiqueta ya existente". Reorganizada en 8 lineas (`DB`
nivel + `DW` puntero por entrada, 4 pares), con el nivel en decimal
(1,2,4,5) y el puntero como la etiqueta real en vez de 2 bytes hex.
De paso corregido el comentario de cabecera: citaba los nombres
antiguos `DEMO_SCRIPT_NIVEL1/2/4/5` (nunca llegaron a usarse en el
fichero, la tabla real siempre se llamo `GUION_DEMO_NIVEL1/2/4/5`).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes -- punteros exactos). Sin cambio de
etiquetas (`gen_inventory.py` no aplica). `.dsk`/`.cas` regenerados
sin incidencias.


### TLH_END -> .TICK_SIEMPRE (local de DESPACHAR_EFECTO_SONIDO)

Renombrada `TLH_END` a `.TICK_SIEMPRE`, local de
`DESPACHAR_EFECTO_SONIDO` (sin referencias externas confirmadas por
grep): punto de convergencia donde confluyen los dos caminos (evento
pendiente instalado, o `$FF`/nada pendiente) antes del
`CALL TICK_REPRODUCTOR_PSG` final, que siempre se ejecuta.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 606
etiquetas (607 -> 606, -1 por ser global->local). `.dsk`/`.cas`
regenerados sin incidencias.


### Ultimas etiquetas en ingles sueltas del fichero: VDP_ENABLE_DISPLAY/VDP_REG1_PENDING/VDP_SCR2_REGS_TABLE/MAINLOOP_TABLES/LOADER_END/END_OF_FILE_SCR

A peticion del usuario, revisado si quedaban etiquetas en ingles en
`madmix_scr_body.asm` (aparte de la familia `TAIL_`/`HNDLR_` ya
tratada). Encontrado un grupo suelto y renombrado:

- `VDP_ENABLE_DISPLAY` -> `ENCENDER_PANTALLA_VDP` (hermana de
  `APAGAR_PANTALLA_VDP`, que ya estaba en espanol).
- `VDP_REG1_PENDING` -> `VDP_REGISTRO1_PENDIENTE`. Referencia cruzada
  real (`LD A,(...)`) desde `madmix1_body.asm:879` actualizada.
- `VDP_SCR2_REGS_TABLE` -> `TABLA_REGISTROS_SCREEN2_VDP`.
- `MAINLOOP_TABLES` -- HALLAZGO: **eliminada**, no renombrada. Coincidia
  exactamente con la misma direccion que `REGISTRO_NIVEL` (linea
  siguiente) y no tenia ninguna referencia real en el codigo (solo
  narrativa historica en `FINDINGS.md`) -- purabente redundante, a
  diferencia de casos previos como `TEXTO_TECLA_PAUSA` donde la
  etiqueta coincidente si representaba una entidad distinta.
- `LOADER_END` -> `FIN_CARGADOR_NIVEL`: tambien coincide en direccion
  (con `TABLA_NIVELES`, `$59A9`), pero SI tiene proposito propio --
  es el ancla del `DS $59A9-$, $00` que verifica/rellena si
  `CARGAR_NIVEL` no termina justo ahi.
- `END_OF_FILE_SCR` -> `FIN_FICHERO_SCR`: marcador de fin de bloque,
  sin referencia real desde `main.asm` (el `SAVEBIN` usa la etiqueta
  distinta `END_OF_FILE_SCR_DISK`, no tocada).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 605
etiquetas (606 -> 605, -1 por la eliminacion de `MAINLOOP_TABLES`; los
otros 5 son renombrados 1:1). `.dsk`/`.cas` regenerados sin
incidencias. Sin menciones en `src/FLUJO_PROGRAMA.md`/
`recursos/mapa_memoria.html`.


### Ronda de mantenimiento: recursos/flujo_programa.html llevaba TODA la sesion sin sincronizar (secciones 1-4, prosa manual)

El usuario senalo que la seccion 1 ("Diagrama de flujo grande") de
`recursos/flujo_programa.html` tenia informacion obsoleta. Al revisar
se confirmo un fallo de proceso: durante toda esta sesion se sincronizo
`src/FLUJO_PROGRAMA.md` y `recursos/mapa_memoria.html` tras cada
renombrado, pero NO `recursos/flujo_programa.html` -- se asumio
erroneamente que ese fichero era enteramente generado por
`tools/gen_inventory.py`. En realidad solo la seccion 5 (inventario) y
las 4 lineas de conteo por tipo se regeneran; las secciones 1-4
(diagrama de flujo grande, tabla de despacho `JT_INICIO`, despachador
de tipo de loseta, variables de estado) son prosa manual, igual que
`FLUJO_PROGRAMA.md`.

Verificados y corregidos, cruzando cada nombre citado contra el codigo
fuente actual (no contra `src/build/main.sym`, que esta obsoleto desde
el 29/07 y todavia tiene nombres viejos -- se uso `main.lst`, fresco,
como apoyo para direcciones sin etiqueta explicita):

- `TI_CONT`/`$5B56` -> `.CONTINUAR_INTRO` (local de
  `GESTIONAR_INTRODUCCION`) / `MOSTRAR_MENU_PRINCIPAL`
- `TAIL_KEYMENU_MAIN` -> `DIBUJAR_MENU_PRINCIPAL`
- `TI_5B65` -> `ACTUALIZAR_MENU_PRINCIPAL`
- `TAIL_KEYMENU_DRAW` -> `DIBUJAR_MENU_REDEFINIR_TECLAS`
- `TAIL_LEVELCYCLE_MAIN` -> `GESTIONAR_CICLO_NIVELES`
- `CHECK_TILE_DELTA` -> `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`
- `ML_DISPATCH_TABLE` -> `TABLA_MANEJADORES_LOSETA` (2 menciones,
  incluida la cabecera de la seccion 3)
- `GHOST_HINT_HANDLER` -> `AVISAR_PROXIMIDAD_PISTA`
- `TAIL_INTRO` -> `GESTIONAR_INTRODUCCION`
- `SLOT_RESTART_DD82` -> `REINICIO_SLOT_DD82`
- `TI_2C2E_ENTRY` -> `INICIALIZAR_PARCIAL_ITEMS_NIVEL`
- `ML_2D37` -> `TICK_MODO_ESPECIAL`
- 2 menciones sueltas de "634 etiquetas" en prosa (nunca tocadas por
  `gen_inventory.py`, que solo actualiza el `<h2>` y los 4
  `<li><b>N tipo</b>` via regex) -> 605.

Confirmados SIN cambios (ya eran los nombres actuales):
`RELOCATOR`, `JUMP_TO_ENGINE`, `JT_INICIO`/`INICIO`/`START`,
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, `FLAG_ENTRADA_BLOQUEADA`,
`JT_MOTOR_ACTORES`/`MOTOR_ACTORES`,
`JT_RESET_CONTADOR_ACTORES`/`RESET_CONTADOR_ACTORES`,
`PTR_TABLA_SPRITES`, y las menciones "antes X" ya correctas de
`BALLS_EATEN_COUNT`/`MODO_ESPECIAL_COUNTDOWN`/`MODO_ESPECIAL_ACTIVE`/
`HINT_POS_TABLE`.

Guardada memoria reforzada (`feedback_actualizar_htmls_recursos`)
para no repetir este fallo: tratar `recursos/flujo_programa.html`
exactamente igual que `FLUJO_PROGRAMA.md`/`mapa_memoria.html` en la
checklist de cierre de cada ronda, nunca asumir que "ya lo regenera
el script".

**Verificado**: cambios puramente de documentacion (HTML), no afectan
al ensamblado -- no aplica recompilar ni diff de binario. Revisado con
grep que no quedan menciones de los nombres antiguos.


### MARICOCO_STORE/REGPUNANTOSO_STORE -> locales .GUARDAR_ESTADO_REGENERACION/.GUARDAR_ESTADO_PLANTADO

Renombradas `MARICOCO_STORE`/`REGPUNANTOSO_STORE` (puntos de reunion
locales dentro de `BUCLE_MARICOCO`/`BUCLE_REGPUNANTOSO`: confluyen el
camino "cumple condicion" y "no cumple", guardando un valor + la
direccion VRAM en scratch antes de `MOTOR_MOVIMIENTO_ITEM`) a
`.GUARDAR_ESTADO_REGENERACION`/`.GUARDAR_ESTADO_PLANTADO`.

Trampa de scoping local esperada y resuelta: al convertir a local, la
etiqueta global intermedia `SIN_REGENERAR_MARICOCO`/
`SIN_PLANTAR_REGPUNANTOSO` (entre `BUCLE_*` y el `JR` que referencia
la nueva local) rompia la compilacion ("Label not found:
BUCLE_MARICOCO.GUARDAR_ESTADO_REGENERACION"). Confirmado por grep que
ambas eran puramente internas, convertidas tambien a locales:
`.SIN_REGENERAR_MARICOCO`/`.SIN_PLANTAR_REGPUNANTOSO`.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 601
etiquetas (605 -> 601, -4 por las 4 conversiones global->local).
`.dsk`/`.cas` regenerados sin incidencias. Sin menciones en
`FINDINGS.md`/`src/FLUJO_PROGRAMA.md` (las de `FINDINGS.md` son
narrativa historica).


### TABLA_ITEMS_MARICOCO/TABLA_ITEMS_REGPUNANTOSO: datos convertidos a decimal

A peticion del usuario, revisado el formato de `TABLA_ITEMS_MARICOCO`
(confirmado: mismo formato de 7 bytes por entrada que
`TABLA_ITEMS_PELMAZOIDE`, `[X,Y,modo/plantado,dir,subX,subY,fase]`,
ya documentado en el comentario de esa tabla). Ninguno de los 7 campos
es mascara de bits real (todos son coordenadas/flags/indices
pequenos), asi que se convirtieron a decimal las 2 entradas de
`TABLA_ITEMS_MARICOCO` y las 8 de `TABLA_ITEMS_REGPUNANTOSO`
(`$20,$10,$01/$02,$01,$00,$00,$01` -> `32,16,1/2,1,0,0,1`), anadiendo
el mismo desglose de campos por comentario que ya tenia
`TABLA_ITEMS_PELMAZOIDE`. `TABLA_ITEMS_PELMAZOIDE` en si NO se toco
(no se pidio esta ronda, sigue en hex) -- queda como posible
inconsistencia menor a resolver en una ronda futura si se quiere
uniformar las 3 tablas.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes -- solo cambio de formato). Sin cambio
de etiquetas. `.dsk`/`.cas` regenerados sin incidencias.


### Nuevo recurso: recursos/flujo_detallado.html -- grafo de llamadas real (Mermaid.js), generado por tools/gen_flow_diagram.py

A peticion del usuario, creado un nuevo visor HTML con el grafo de
llamadas real del programa (no a mano como la seccion 1 de
`flujo_programa.html`, sino generado desde `src/build/main.lst`,
mismo enfoque que `gen_inventory.py`). Decisiones de alcance acordadas
con el usuario antes de construirlo:

- Nodos: solo las 102 etiquetas clasificadas **"funcion"** (destino de
  al menos un `CALL`) -- el mismo conjunto que la categoria "funcion"
  del inventario existente. NO incluye los ~180 "interna" (destino
  solo de `JP`/`JR`, sin `CALL`) -- en particular, los manejadores de
  tipo de loseta (`HNDLR_SUELO_NORMAL`, etc., alcanzados solo por
  `JP (IX)` desde `TABLA_MANEJADORES_LOSETA`) NO aparecen como nodos.
  Documentado explicitamente en el propio HTML como limitacion de
  alcance, no como omision accidental.
- Render: Mermaid.js (CDN) en un `flowchart TD` con un `subgraph` por
  categoria (color), zoom +/-/reset y checkboxes para
  mostrar/ocultar categorias.
- Categorias/colores: reutilizados los mismos `--c-*` de
  `flujo_programa.html` (boot/motor/items/hud/menu/sonido), mas una
  categoria nueva `graficos` (gestion VRAM) pedida explicitamente por
  el usuario, antes repartida sin criterio propio entre motor/menu.
  Categorizacion hecha a mano (dict explicito en el script, no
  heuristica de nombre) por ser solo 102 nodos -- el script avisa por
  stdout de cualquier "funcion" nueva sin categoria explicita en
  rondas futuras.

HALLAZGO/BUG real durante la construccion, corregido antes de dar la
tarea por buena: la primera version atribuia cada `CALL` a la ULTIMA
etiqueta "funcion" vista en el fichero, sin tener en cuenta que entre
dos etiquetas "funcion" consecutivas puede haber CIENTOS de lineas
pertenecientes a rutinas reales pero no-funcion (alcanzadas solo por
`JR`/`JP`, p.ej. `LEER_TECLADO`/`LEER_JOYSTICK` entre
`COMPROBAR_TECLA_MSX` y `ACTUALIZAR_LOSETA_BOLA_ESPECIAL`, 444 lineas
de separacion) -- resultaba en aristas FALSAS (p.ej.
`COMPROBAR_TECLA_MSX` -- una rutina de 6 lineas sin una sola llamada
real -- apareciendo como si llamara a `DIBUJAR_PORTADA`/
`MOSTRAR_MENU_PRINCIPAL`/etc.). Corregido calculando el propietario
lexico real de cada linea usando TODAS las etiquetas globales (de
cualquier tipo) como limites, y descartando (no reatribuyendo) los
`CALL` cuyo propietario real no es "funcion" -- bajo el numero de
aristas de 181 (con el bug) a 85 (correctas), con 178 llamadas
descartadas explicitamente documentadas en la nota del HTML en vez de
ocultarse en silencio.

**Verificado**: fichero de documentacion puro (HTML+script Python), no
afecta al ensamblado -- no aplica recompilar ni diff de binario. Nodos
generados: 102 (boot=11, menu=9, motor=17, items=13, hud=10,
graficos=28, sonido=14, otros=0 -- todos categorizados). Aristas: 85.
Anadidas entradas en `src/README.md` (arbol de `tools/` y seccion
"Visores HTML").


### Inventario sistematico de direcciones hex sin etiqueta en madmix_scr_body.asm -- primer lote: sustituciones por etiqueta ya existente

A peticion del usuario, escrito un script de auditoria (cruza cada
`LD HL/DE/IX/IY,$XXXX` / `CALL/JP $XXXX` / `($XXXX)` de
`madmix_scr_body.asm` contra las etiquetas reales de
`madmix_scr_body.asm`+`madmix1_body.asm`) para detectar hex sin
sustituir por etiqueta ya existente, con exclusion explicita de: `LD
BC,$XXXX` (casi siempre contador de `LDIR`, no direccion), valores
inmediatamente antes/despues de `FILVRM`/`LDIRVM`/`SETVRAM`/`OUT
($99)` (argumentos de posicion/patron VRAM, no direcciones RAM,
mismo criterio de siempre) y verificacion manual caso a caso del
resto (varios "RANGE" del script resultaron ser falsos positivos:
valores aritmeticos de puntos, deltas de movimiento empaquetados,
posiciones de camara empaquetadas -- descartados sin aplicar cambio).

Aplicado el primer lote (direcciones que YA tenian etiqueta real):

- `$1000` (`LD DE,$1000` y `CALL $1000`, dentro de
  `REUBICADOR_REINICIO_JUEGO`) -> `DIBUJAR_PORTADA`. Es el "segundo
  `CALL $1000` sin corregir" que quedaba senalado como pendiente
  desde una ronda muy anterior de esta misma sesion.
- `$8400` (misma rutina) -> `START`.
- `$D6B6` (en `DIBUJAR_MARCO_CARAMELO_VRAM`) -> `TABLA_RLE_MARCO_CARAMELO`.
- `$8EC6` (3 usos + 2 menciones en comentarios) -> `FLAG_ENTRADA_BLOQUEADA`
  (ya existia en `madmix1_body.asm`, mismo espacio de nombres).

HALLAZGO aparte, documentado pero sin aplicar cambio: `$925B`
(`ESCRIBIR_PATRON_VRAM`, patrones de fuente/texto) cae EXACTO en
`PTR_TABLA_SPRITES+152` (`madmix1_body.asm`, entrada 38 de 64 de la
tabla de punteros de sprites de personajes) -- datos semanticamente
distintos que numericamente se solapan; merece investigacion aparte
antes de decidir si hay reuso real de memoria o es coincidencia.

Quedan pendientes (siguiente ronda, etiquetas NUEVAS a crear):
`$5556`/`$5557` (scratch de `.GUARDAR_ESTADO_REGENERACION`),
`$5667`/`$5668` (gemelo de REGPUNANTOSO), `$5773` (`TABLA_RANURAS_AVISO`,
4 bytes), `$5BBC` (direccion de retorno "trampa" en
`GESTIONAR_TIMEOUT_MENU`), `$5C9F` (acumulador de
`LEER_TECLAS_MENU_PRINCIPAL`), `$6128` (marcador de evento/sonido
pendiente, 27 usos), `$6129` (inicio de los datos de color del marco
de caramelo), `$60CA`/`$60CB`/`$60CD` (estado real del ciclador de
niveles de muestra, el comentario historico "cola que compila a
cero" era incorrecto).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (`gen_inventory.py` no
aplica). `.dsk`/`.cas` regenerados sin incidencias.


### Segundo lote del inventario de direcciones hex: 11 etiquetas nuevas creadas

Continuacion de la ronda anterior -- creadas las etiquetas nuevas para
las direcciones que no tenian ninguna (todas variables/scratch reales,
verificadas caso a caso leyendo el codigo antes de tocar nada):

- `$5556`/`$5557` (scratch de la instancia 1, tras `SIGUIENTE_MARICOCO`)
  -> `ESTADO_REGENERACION_MARICOCO` (byte) / `VRAM_REGENERACION_MARICOCO` (word).
- `$5667`/`$5668` (gemelo, instancia 2) -> `ESTADO_PLANTADO_REGPUNANTOSO` /
  `VRAM_PLANTADO_REGPUNANTOSO`.
- `$5773` (primeros 8 de los 15 bytes de la "zona de trabajo RAM
  compartida con MADMIX1.BIN") -> `TABLA_RANURAS_AVISO` (4 entradas x
  2 bytes). Los 7 bytes restantes ($577B-$5781) se dejan sin etiqueta,
  documentados como "sin consumidor confirmado en este fichero".
- `$5BBC`: HALLAZGO -- no es una direccion de datos, es una direccion
  de retorno "trampa": `ACTUALIZAR_MENU_PRINCIPAL` la empuja a mano en
  la pila antes de despachar la opcion de menu, de forma que el `RET`
  bare de cada `SELECCIONAR_OPCION_*` (llamados por `JP`, no `CALL`)
  aterrice exactamente en el `POP AF` de `GESTIONAR_TIMEOUT_MENU`,
  saltandose su `POP HL`. Anadida como etiqueta local
  `GESTIONAR_TIMEOUT_MENU.CONTINUAR_TRAS_OPCION`, referenciada con la
  notacion `PADRE.local` (mismo patron ya usado en comentarios este
  proyecto, aqui aplicado por primera vez dentro de codigo real).
- `$5C9F`: HALLAZGO -- coincide exacto con el opcode del `NOP` (`$00`)
  que sirve de "caida normal" tras `TABLA_TECLAS_MENU_PRINCIPAL`
  (documentado en su propio comentario de cabecera) -- mismo patron
  de "byte reutilizado con doble papel" que otros hallazgos de esta
  sesion. Etiquetado el `NOP` mismo como `ACUMULADOR_TECLAS_MENU` (sin
  anadir ningun byte).
- `$6128` (27 usos) -> `EVENTO_SONIDO_PENDIENTE`. HALLAZGO: no es un
  byte "colgado" independiente -- es literalmente el byte 43 de la
  fila `DB` de `TABLA_RECURSOS_SONIDO_EVENTO` (que solo necesita 42 =
  14 entradas x 3 bytes), separado en su propia etiqueta sin anadir
  bytes.
- `$6129` -> `TABLA_COLOR_MARCO_CARAMELO` (inicio del `INCBIN
  "data/img/marco_caramelo_color.img"`, 768 bytes).
- `$60CA`/`$60CB`/`$60CD`: HALLAZGO -- el comentario historico decia
  "cola tras .FIN_CICLO_NIVELES, compila a cero" / "variable/cola de
  alineacion antes de la tabla", pero son variables REALES y
  activamente usadas (incluso desde `MOTOR_MOVIMIENTO_COLISION` y
  `ACTIVAR_EFECTO_ITEM`, fuera de `GESTIONAR_CICLO_NIVELES`) ->
  `INDICE_CICLO_NIVELES` (byte, indice 0-3 del nivel de muestra en
  curso) / `PUNTERO_GUION_DEMO` (word, cursor en el guion activo) /
  `CONTADOR_FRAME_GUION_DEMO` (byte). Los 2 bytes finales
  ($60CE-$60CF) se dejan sin etiqueta, sin consumidor confirmado.

Todas las sustituciones verificadas con grep antes de aplicar (sin
colisiones de subcadena) y sin anadir/quitar ningun byte -- longitud
de `MADMIX.SCR`/`MADMIX1.BIN` identica byte a byte a la de siempre,
ademas de la linea base 7/2.

Sincronizado `src/FLUJO_PROGRAMA.md` (3 menciones en secciones activas,
§5.9 y la tabla de variables de §4) y `recursos/mapa_memoria.html` (1
mencion). Dejadas intactas las menciones dentro de parrafos ya
senalados como desfasados en rondas anteriores (§5.6/§5.8, con otros
nombres antiguos sin actualizar).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2, mismos bytes, misma longitud exacta). `recursos/flujo_programa.html`
regenerado: 612 etiquetas (601 -> 612, +11 nuevas). `.dsk`/`.cas`
regenerados sin incidencias.


### LOAD_BIN_ENTRY -> ORQUESTADOR_CARGA_CINTA

Renombrada `LOAD_BIN_ENTRY` (`src/load_cas/load_bin_body.asm`, `$DDA0`)
a `ORQUESTADOR_CARGA_CINTA`: el punto de entrada real de `LOAD.BIN`
(invocado desde BASIC via `DEF USR=56736!:A=USR(0)`), equivalente
cinta de `RELOCATOR`+`JUMP_TO_ENGINE` juntos -- detecta slots de RAM
(`DETECTAR_SLOTS_RAM`), configura paginas, lee de cinta directo a `$1000`
(portada) y la ejecuta, lee el motor completo directo a `$8400`
(`START`) y salta ahi, sin aterrizaje intermedio ni `LDIR` (a
diferencia de la version de disco). Referencia real en
`src/main.asm` (`SAVEBIN "build/cas/LOAD.BIN", ...`) actualizada.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (renombrado 1:1). `.dsk`/
`.cas` regenerados sin incidencias.


### PAGE_CONFIG_1/2/3 -> APLICAR_SLOT_PAGINA_0/1/2

Renombradas `PAGE_CONFIG_1`/`_2`/`_3` (`src/load_cas/load_bin_body.asm`)
a `APLICAR_SLOT_PAGINA_0`/`_1`/`_2`: cada una aplica la configuracion
de slot guardada por `DETECTAR_SLOTS_RAM` en `$E293` a una de las 3
primeras "paginas" de 16KB del mapa MSX (sistema clasico de 4 paginas
x slot/sub-slot via puerto `$A8`+`EXPTBL`/`$FFFF`), saltando a un
"setup" `D`/`E` propio y de ahi al conmutador comun
`APLICAR_CAMBIO_SLOT` (nombre asignado en una ronda posterior de esta
misma sesion). Son 3 de las 6 variantes "aplicar configuracion
de pagina/slot" que ya documentaba el comentario de cabecera (las
otras 3, con `$E291`, no se llaman desde este fichero -- sin tocar).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (renombrado 1:1). `.dsk`/
`.cas` regenerados sin incidencias.


### TAPE_READ -> LEER_CINTA

Renombrada `TAPE_READ` (`src/load_cas/load_bin_body.asm`, `$DDCC`) a
`LEER_CINTA`: rutina generica de lectura de cinta bit a bit (recibe
destino en `IX` y numero de bytes en `DE`), usada por
`ORQUESTADOR_CARGA_CINTA` tanto para leer el bloque de la portada como
el motor completo. Usa ganchos fijos de la ROM BASIC y parpadea el
borde (puerto VDP `$99`). Renombrado quirurgico (no `replace_all`):
`TAPE_READ` es subcadena de `TAPE_READ_HOOK_LOOP`/`_BIT`/`_BIT_STORE`/
`_BIT_CALL`/`_ABORT`/`_UNHOOK_LOOP` (familia de locales relacionados,
sin tocar todavia, candidatos a una ronda aparte).

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (renombrado 1:1). `.dsk`/
`.cas` regenerados sin incidencias.


### TAPE_READ_HOOK_LOOP -> .BUCLE_GUARDAR_GANCHOS (local de LEER_CINTA)

Renombrada `TAPE_READ_HOOK_LOOP` a `.BUCLE_GUARDAR_GANCHOS`, local de
`LEER_CINTA` (sin referencias externas): respalda 12 entradas (24
bytes) de una tabla fija de vectores del BASIC/ROM (`$FCA6` hacia
abajo) empujandolas a la pila, antes de instalar los ganchos propios
de `LEER_CINTA`. Su pareja `TAPE_READ_UNHOOK_LOOP` (renombrada en una
ronda posterior de esta misma sesion a `.BUCLE_RESTAURAR_GANCHOS`)
hace lo contrario al final: las restaura desde la pila.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). `recursos/flujo_programa.html` regenerado: 611
etiquetas (612 -> 611, -1 por ser global->local). `.dsk`/`.cas`
regenerados sin incidencias.


### TEST_BIN_ENTRY -> DETECTAR_SLOTS_RAM

Renombrada `TEST_BIN_ENTRY` (`src/load_cas/test_bin_body.asm`, `$C350`)
a `DETECTAR_SLOTS_RAM`: motor de deteccion de RAM/slots de `TEST.BIN`,
invocado por `ORQUESTADOR_CARGA_CINTA` como primer paso antes de tocar
la cinta -- recorre las combinaciones de slot primario/secundario en
las paginas `$4000`/`$8000` (patron clasico de deteccion via `ENASLT`)
y guarda 2 configuraciones de slot resultantes en `$E290-$E293`.
Referencia real en `src/main.asm` (`SAVEBIN "build/cas/TEST.BIN",
...`) actualizada, junto con el `CALL` real desde
`ORQUESTADOR_CARGA_CINTA`. Mencion "viva" de la entrada anterior de
esta misma sesion corregida hacia adelante; menciones historicas de
sesiones anteriores en `FINDINGS.md` dejadas intactas.

**Verificado**: recompilado sin errores, diffs en la linea base exacta
de siempre (7/2). Sin cambio de etiquetas (renombrado 1:1). `.dsk`/
`.cas` regenerados sin incidencias.


### Revision completa de `load_cas/load_bin_body.asm`: ultimas 14 etiquetas en ingles/crypticas renombradas

Revisadas TODAS las etiquetas de funcion que quedaban en ingles o con
nombres crípticos en este fichero (`LOAD.BIN`, orquestador de la
carga por cinta). Tres grupos, todos confirmados y aplicados:

**Grupo A -- familia de locales dentro de `LEER_CINTA`** (bucle de
lectura de cinta bit a bit, ya con `TAPE_READ`->`LEER_CINTA` hecho en
la ronda anterior):
- `TAPE_READ_BIT_STORE` -> `.ALMACENAR_BYTE`: guarda el byte ya
  ensamblado bit a bit en el destino (`(BC)`).
- `TAPE_READ_BIT_CALL` -> `.LLAMAR_GANCHO_BIT`: invoca el gancho ROM
  que lee el siguiente bit de cinta.
- `TAPE_READ_BIT` -> `.BUCLE_LEER_BIT`: el bucle principal, un giro
  por bit leido.
- `TAPE_READ_ABORT` -> `.FINALIZAR_LECTURA`: punto de convergencia
  real de exito Y fallo (nombre anterior "ABORT" era enganoso -- no
  es solo la salida de error, es donde confluyen ambos caminos:
  restaura ganchos ROM y devuelve flag de resultado en todos los
  casos).
- `TAPE_READ_UNHOOK_LOOP` -> `.BUCLE_RESTAURAR_GANCHOS`: ya renombrada
  en la ronda anterior (ver entrada de arriba), incluida aqui solo
  para review de conjunto.

**Grupo B -- codigo sin invocar desde este fichero** (vestigio o
gancho para un caso no usado en esta edicion, mismo puerto VDP `$99`
que `LEER_CINTA`):
- `TAPE_MOTOR_HELPER_A` -> `AYUDANTE_MOTOR_CINTA_A`
- `TAPE_MOTOR_HELPER_B` -> `AYUDANTE_MOTOR_CINTA_B`

**Grupo C -- familia "aplicar configuracion de pagina/slot"** (6
variantes + el conmutador comun, ya documentadas en el comentario de
cabecera desde la ronda de `PAGE_CONFIG_1/2/3`): las 3 gemelas con
`$E291` (NO invocadas desde este fichero, contraparte muerta de las 3
que SI llama `ORQUESTADOR_CARGA_CINTA`) y los 3 "setups" D/E + el
conmutador final:
- `PAGE_CONFIG_E291_A` -> `APLICAR_SLOT_ORIGINAL_PAGINA_0`
- `PAGE_CONFIG_E291_B` -> `APLICAR_SLOT_ORIGINAL_PAGINA_1`
- `PAGE_CONFIG_E291_C` -> `APLICAR_SLOT_ORIGINAL_PAGINA_2`
- `PAGE_CONFIG_SETUP_A` -> `CONFIGURAR_MASCARA_PAGINA_0`
- `PAGE_CONFIG_SETUP_B` -> `CONFIGURAR_MASCARA_PAGINA_1`
- `PAGE_CONFIG_SETUP_C` -> `CONFIGURAR_MASCARA_PAGINA_2`
- `PAGE_SWITCH_COMMON` -> `APLICAR_CAMBIO_SLOT`

Con esto, `load_cas/load_bin_body.asm` queda sin ninguna etiqueta en
ingles o cryptica pendiente (todas las funciones/locales del fichero
tienen ya nombre descriptivo en espanol). Menciones "vivas" de
`PAGE_SWITCH_COMMON` y `TAPE_READ_UNHOOK_LOOP` en entradas de esta
misma sesion (arriba) corregidas hacia adelante; menciones historicas
de sesiones anteriores dejadas intactas.

**Verificado**: recompilado sin errores (0 errores, 2 warnings
preexistentes sin relacion). Diffs en la linea base exacta de
siempre: **7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`** (offsets
`$8BE5`/`$8CD4`, el fix historico ya documentado). Sin cambio de
etiquetas fuera de este fichero (renombrados 1:1, sin insercion ni
eliminacion de bytes). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/flujo_programa.html` regenerado: 606 etiquetas (inventario
limpio, sin menciones de los nombres antiguos). `tools/gen_flow_diagram.py`
tenia el diccionario `CATEGORY` con 5 nombres desactualizados
(`TEST_BIN_ENTRY`, `TAPE_READ`, `PAGE_CONFIG_1/2/3`) de rondas
anteriores a esta sesion de renombrados -- corregidos y
`recursos/flujo_detallado.html` regenerado (mismos 102 nodos/85
aristas, sin cambio estructural). `recursos/mapa_memoria.html` y
`recursos/flujo_secuencial.html` ya no tenian menciones de ninguno de
los 14 nombres antiguos (nada que sincronizar en esos dos).


### Revision de variables/literales de `load_cas/load_bin_body.asm`: decimal donde procede + etiquetas nuevas para $E290-$E293

Revision completa de todos los literales numericos del fichero
(peticion explicita del usuario: "revisa todas las variables,
convierte a decimal las que procedan y revisa si hay etiquetas para
todas"). Dos resultados:

**Decimal donde procede** (contadores puros, sin semantica de
mascara/signo/direccion): `LD DE, $5500` -> `LD DE, 21760` (tamano en
bytes del bloque destino a `DIBUJAR_PORTADA`, igual que el LDIR de
`RELOCATOR` en disco); `LD DE, $59A0` -> `LD DE, 22944` (tamano en
bytes del bloque destino a `START`); los dos `LD B, $0C` -> `LD B, 12`
(la tabla de 12 ganchos ROM que `.BUCLE_GUARDAR_GANCHOS`/
`.BUCLE_RESTAURAR_GANCHOS` empujan/restauran); `CP $01` -> `CP 1`
(comparacion final de resultado, no mascara). El resto de literales
del fichero se dejan en hex a proposito: direcciones (`$FCA6`,
`$FCA4`, `$FC8E`, `$FC9A`, `$FC9E`, ganchos ROM `$00E1`/`$C961`/
`$CDD9`/`$EDD9`/`$69ED`, `$FFFF`), puertos (`$A8`, `$99`, `$AB`),
mascaras de bits (`$0F`, y los pares D/E de la familia
`CONFIGURAR_MASCARA_PAGINA_x`: `$03`/`$FC`, `$0C`/`$F3`, `$30`/`$CF`
-- notese que este `$0C` es mascara, NO el contador de bucle de
arriba, mismo valor pero semantica distinta), bytes de comando VDP
(`$87`), deltas con signo usados en aritmetica de solapamiento
(`$0372`, `$FFE8` = -24), el sentinela `$FF` (parametro de
`LEER_CINTA`) y constantes de proposito desconocido en codigo muerto
sin invocar (`AYUDANTE_MOTOR_CINTA_B`: `$13`, `$09`, `$01`) o
alimentando directamente al hook ROM `$FC9A` (`$E4`, `$F3`).

**Etiquetas nuevas -- `$E290`-`$E293`**: 4 bytes de RAM libre (fuera
de cualquier binario del proyecto) usados como variable de trabajo
COMPARTIDA entre `test_bin_body.asm` (los escribe, en `SLOT_SAVE_A`/
`SLOT_SAVE_B`) y `load_bin_body.asm` (los lee, familias
`APLICAR_SLOT_ORIGINAL_PAGINA_x`/`APLICAR_SLOT_PAGINA_x`) -- hasta
ahora 4 hex literales sueltos repetidos 6 veces entre ambos ficheros,
sin ninguna etiqueta. Mismo patron que `BUFFER_LOSETAS_TRABAJO: EQU
$DE04` en `madmix1_body.asm` (RAM de trabajo con nombre real aunque
no este respaldada por ningun `DB` del proyecto). Creadas como `EQU`
en `test_bin_body.asm` (antes de `SLOT_SAVE_A`, disponibles para
`load_bin_body.asm` via el espacio de simbolos compartido de
`main.asm`):
- `SLOT_PRIMARIO_A` = `$E290`, `EXPTBL_COMPLEMENTO_A` = `$E291`
  (config "A", guardada por `SLOT_SAVE_A`, la que usa la familia
  muerta `APLICAR_SLOT_ORIGINAL_PAGINA_x`).
- `SLOT_PRIMARIO_B` = `$E292`, `EXPTBL_COMPLEMENTO_B` = `$E293`
  (config "B", guardada por `SLOT_SAVE_B`, la que SI usa
  `ORQUESTADOR_CARGA_CINTA` via `APLICAR_SLOT_PAGINA_x`).

Cabeceras de ambos ficheros actualizadas para referenciar los nombres
nuevos en vez de hex literal.

**Verificado**: recompilado sin errores (0 errores, 2 warnings
preexistentes sin relacion). Diffs en la linea base exacta de
siempre: 7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`. `.dsk`/`.cas`
regenerados sin incidencias. `recursos/flujo_programa.html`
regenerado: 610 etiquetas (606 -> 610, +4 por las nuevas `EQU`).
`recursos/mapa_memoria.html` sin cambios -- el rango `$E290-$E293` es
RAM libre fuera de todos los binarios mapeados por ese documento
(igual criterio que `$FCA6`/`$AFC8`, tampoco mapeados alli).


### Revision completa de `load_cas/test_bin_body.asm`: 13 etiquetas de funcion/salto renombradas

Revisadas todas las etiquetas de funcion y salto que quedaban en
ingles o poco descriptivas en este fichero (`TEST.BIN`, motor de
deteccion de RAM/slots). Tres grupos:

**Grupo A -- guardar configuracion de slot** (usadas por
`DETECTAR_SLOTS_RAM` antes y despues de la deteccion, para poder
restaurar el slot original al final):
- `SLOT_SAVE_A` -> `GUARDAR_CONFIG_SLOT_A`
- `SLOT_SAVE_B` -> `GUARDAR_CONFIG_SLOT_B`
- `SLOT_SAVE_COMMON` -> `GUARDAR_SLOT_COMUN` (cola comun de las dos
  anteriores; NO puede ser local -- `GUARDAR_CONFIG_SLOT_B`, que debe
  seguir global por ser invocada desde `DETECTAR_SLOTS_RAM`, queda
  entre el `JR` de A y esta etiqueta -- misma trampa de scoping de
  locales ya documentada en rondas anteriores).

**Grupo B -- `DETECTAR_RAM_PAGINA`** (recibe la pagina en `HL`;
prueba las 16 combinaciones de slot/subslot via `ENASLT` escribiendo/
leyendo un patron `$20`/`$FA` para distinguir RAM real de ROM/nada):
- `RAM_TEST` -> `DETECTAR_RAM_PAGINA`
- `RAM_TEST_OUTER` -> `.BUCLE_SLOT_SECUNDARIO` (local, bucle de 4
  subslots)
- `RAM_TEST_TRY` -> `.BUCLE_SLOT_PRIMARIO` (local, bucle de 4 slots
  primarios, intenta cada combinacion)
- `RAM_TEST_NEXT` -> `.SIGUIENTE_COMBINACION` (local, combinacion
  fallida, continua)
- `RAM_TEST_FOUND` -> `.RAM_ENCONTRADA` (local, RAM detectada)

**Grupo C -- plantilla reubicable `ENASLT` extendido** (copiada a
`$AFC8` en tiempo de ejecucion; gestiona el caso de subslots, que el
`ENASLT` estandar de ROM no resuelve directamente):
- `ENASLT_HELPER` -> `ENASLT_EXTENDIDO`: punto de entrada -- si la
  pagina no usa subslot, mezcla directamente en el puerto `$A8`; si
  si, salta a gestionar el subslot.
- `ENASLT_HELPER_C` -> `ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT`: caso con
  subslot -- actualiza la tabla de cache de subslots (`$FCC5`+offset)
  y reintenta.
- `ENASLT_HELPER_B` -> `ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO`:
  calcula la pareja de mascaras AND/OR para insertar 2 bits en la
  posicion de pagina correcta del registro de slot primario.
- `ENASLT_HELPER_D` -> `ENASLT_EXTENDIDO_MASCARA_SUBSLOT`: lo mismo
  pero para el registro de subslot (`EXPTBL`/puerto `$A8`).
- `ENASLT_HELPER_B_MID`/`ENASLT_HELPER_B_LOOP` (bucles internos de la
  mascara primaria, sin referencia externa) -> locales
  `.BUCLE_DESPLAZAR_MASCARA`/`.BUCLE_REPLICAR_MASCARA`.
- `ENASLT_HELPER_D_MID` (bucle interno de la mascara de subslot) ->
  local `.BUCLE_DESPLAZAR_MASCARA` (mismo nombre local que el de
  arriba, pero en el scope de `ENASLT_EXTENDIDO_MASCARA_SUBSLOT` --
  sin colision, los locales se resuelven por scope).

Nota sobre certeza: el Grupo C es el que menos se ha podido verificar
al 100% -- se entiende el proposito general (construir mascaras de 2
bits por pagina para slots/subslots) pero no cada micro-detalle
aritmetico de B/C/D. Comentarios cruzados en hex (`= X tras
reubicarse en $AFC8`) actualizados a los nombres nuevos, incluyendo
sintaxis `PADRE.local` para los dos casos de `.BUCLE_DESPLAZAR_MASCARA`.

**Verificado**: recompilado sin errores (0 errores, 2 warnings
preexistentes sin relacion). Diffs en la linea base exacta de
siempre: 7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`. `.dsk`/`.cas`
regenerados sin incidencias. `recursos/flujo_programa.html`
regenerado: 603 etiquetas (610 -> 603, -7 por las 7 conversiones
global->local: 4 en el Grupo B + 3 en el Grupo C).
`tools/gen_flow_diagram.py` tenia `SLOT_SAVE_A`/`SLOT_SAVE_B`/
`RAM_TEST` en el diccionario `CATEGORY` -- corregidos y
`recursos/flujo_detallado.html` regenerado (mismos 102 nodos/85
aristas, sin cambio estructural). `recursos/mapa_memoria.html` y
`src/FLUJO_PROGRAMA.md` sin menciones de ninguno de los 13 nombres
antiguos (nada que sincronizar).


### Revision de datos/literales de `load_cas/test_bin_body.asm`: decimal donde procede

Revisados todos los literales numericos del fichero (peticion
explicita del usuario). Comprobado tambien que no queda ningun hex
literal que deba sustituirse por una etiqueta ya existente -- las 4
`EQU` (`SLOT_PRIMARIO_A`/`EXPTBL_COMPLEMENTO_A`/`SLOT_PRIMARIO_B`/
`EXPTBL_COMPLEMENTO_B`) y las etiquetas de funcion de la ronda
anterior ya se usaban en todos los sitios correctos.

**Decimal donde procede** (contadores puros): `LD BC, $007A` ->
`LD BC, 122` (tamano en bytes de `ENASLT_EXTENDIDO` para el `LDIR` de
reubicacion, coincide con el "122 bytes" ya documentado en la
cabecera); `LD C, $04`/`LD B, $04` -> `LD C, 4`/`LD B, 4` (las 4
combinaciones de slot secundario/primario que recorre
`DETECTAR_RAM_PAGINA`); `LD B, $00` -> `LD B, 0` (extension a 16 bits
del indice de tabla en `ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT`).

El resto se deja en hex a proposito: direcciones (`$8000`, `$4000`,
`$0000` como paginas MSX; `$0024` ENASLT; `$C3B3` operando
automodificado; `$AFC8`; `$FCC5`; `$FFFF` EXPTBL), puertos (`$A8`),
bytes de formato/mascara empaquetados de `ENASLT` (`$80`, `$83`,
`$03`, `$C0`, `$3F`, el paso `$04` de `ADD A,$04` que avanza un campo
de bits, no un contador independiente), constantes de patron de
deteccion de RAM (`$20`/`$FA`, "escritura complementaria" segun la
cabecera), constantes de construccion de mascara por suma modular
(`$AB`, `$55`), y el vector de interrupcion estandar `RST $38`.

**Hallazgo aparte, no aplicado**: `$C3B3` (lineas donde
`DETECTAR_SLOTS_RAM` automodifica el `CALL $0024` de dentro de
`.BUCLE_SLOT_PRIMARIO`) es el operando real de esa instruccion, DENTRO
del propio binario de `TEST.BIN` -- mismo patron de "byte
automodificado sin etiqueta propia" que otros ya resueltos esta sesion
(p.ej. `$5C9F`/`ACUMULADOR_TECLAS_MENU` en `madmix_scr_body.asm`).
Etiquetarlo requeriria partir la instruccion `CALL $0024` en
`DB $CD` + `DW $0024` con una etiqueta en medio (mismos bytes,
0 diferencias) -- mas invasivo que una simple sustitucion, se deja
pendiente de confirmacion expresa del usuario en vez de aplicarlo
directamente.

**Verificado**: recompilado sin errores (0 errores, 2 warnings
preexistentes sin relacion). Diffs en la linea base exacta de
siempre: 7 en `MADMIX.SCR`, 2 en `MADMIX1.BIN`. `.dsk`/`.cas`
regenerados sin incidencias. `recursos/flujo_programa.html`
regenerado: 603 etiquetas (sin cambio, solo se tocaron literales, no
simbolos).


### Etiqueta nueva para el operando automodificado en $C3B3 (confirmado por el usuario)

Aplicado el hallazgo dejado pendiente en la entrada anterior:
`DETECTAR_SLOTS_RAM` automodifica dos veces (antes y despues de
reubicar `ENASLT_EXTENDIDO`) el operando de la instruccion
`CALL $0024` que vive dentro de `.BUCLE_SLOT_PRIMARIO`
(`DETECTAR_RAM_PAGINA`) -- hasta ahora referenciado como hex literal
suelto `$C3B3` en las dos escrituras, sin ninguna etiqueta propia
pese a estar dentro del binario del proyecto.

Partida la instruccion `CALL $0024` en `DB $CD` (opcode fijo) +
`DW $0024` con una etiqueta local `.OPERANDO_ENASLT_AUTOMODIFICADO`
justo en el operando -- mismos 3 bytes exactos (`CD 24 00`),
confirmado en el listado (`C3B2 CD` / `C3B3 24 00`). Las dos
escrituras en `DETECTAR_SLOTS_RAM` ahora usan
`LD (DETECTAR_RAM_PAGINA.OPERANDO_ENASLT_AUTOMODIFICADO), HL`
(sintaxis `PADRE.local`, ya usada antes esta sesion).

Nota sobre el inventario: las etiquetas locales (prefijo `.`) NUNCA
se cuentan en `gen_inventory.py` (su regex de deteccion de etiquetas
exige que el primer caracter sea letra o `_`, un punto no matchea) --
confirma retroactivamente por que las conversiones global->local de
rondas anteriores siempre BAJABAN el total en vez de mantenerlo (la
etiqueta local nueva simplemente nunca se cuenta, no es que se sume y
reste). `.OPERANDO_ENASLT_AUTOMODIFICADO` no aparece en el inventario
por el mismo motivo -- comportamiento esperado, no un fallo del
generador.

**Verificado**: recompilado sin errores. Diffs en la linea base
exacta de siempre (7/2). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/flujo_programa.html` regenerado: 603 etiquetas (sin cambio,
la nueva etiqueta es local y no se cuenta, ver nota arriba).


### Comentarios anadidos a todos los datos/variables de `load_cas/test_bin_body.asm`

Peticion explicita del usuario: revisar todos los literales/direcciones
del fichero y anadir comentario donde faltaba. Cambios de solo
comentarios (0 bytes de codigo tocados), entre otros:
- `LD A, ($8000)`/`LD ($8000), A`: guardado/restauracion del byte
  original que el test de RAM sobreescribe.
- `LD HL, $4000`/`$8000`/`$0000` (los 3 `CALL DETECTAR_RAM_PAGINA`):
  identificadas como pagina 1/2/0.
- `IN A, ($A8)` en `GUARDAR_SLOT_COMUN`: lectura del slot primario activo.
- `LD A, $80`/`AND $83`/`ADD A, $04` en `DETECTAR_RAM_PAGINA`: formato
  empaquetado del byte de configuracion para `ENASLT` (slot primario en
  bits 0-1, bit superior fijo) y como el bucle interno avanza ese campo.
- `$20`/`$FA`: identificados explicitamente como "patron de prueba
  #1"/"#2" en cada uso, con la logica de exito/fallo explicada.
- Cabecera nueva sobre `ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO`/
  `_SUBSLOT`: describe la tecnica general (aislar num. de pagina,
  desplazar una mascara base, replicar el valor via suma modular de
  `$55`), con nota explicita de que el detalle bit a bit no esta
  verificado al 100% (mismo hedge ya usado en la ronda de renombrado).
  Cada `AND`/`OR`/`IN`/`OUT` de esas dos funciones comentado con su
  papel en esa tecnica.
- Los 2 `RST $38` de relleno tras el `RET` real (nunca se ejecutan,
  igual que el `DB $E1` que ya tenia comentario) marcados como tal.

**Verificado**: recompilado sin errores. Diffs en la linea base
exacta de siempre (7/2, solo comentarios, 0 bytes de codigo). `.dsk`/
`.cas` regenerados sin incidencias.


### Comentarios anadidos a todos los datos/variables de `load_cas/load_bin_body.asm`

Mismo tratamiento que la entrada anterior, ahora en `LOAD.BIN`
(peticion explicita del usuario: "haz lo mismo en este fichero").
Cambios de solo comentarios (0 bytes de codigo tocados). Destacan:
- Los dos `LD A, $FF` (parametro de `LEER_CINTA`) y los `LD A, $E4`/
  `$F3` (modo para el gancho `$FC9A`, via `$FC9E`): comentados con
  hedge explicito de que su semantica exacta no esta verificada al
  100% (son parametros de un gancho ROM externo, no logica propia).
- `$0372`/`$FFE8`: identificados como pareja de deltas de una
  comprobacion de solapamiento de zona protegida (`$FFE8` = -24),
  mismo hedge.
- Los `$87` sueltos (aparecen 4 veces, incluido en el codigo muerto
  `AYUDANTE_MOTOR_CINTA_A/B`): identificados con confianza como "VDP
  -- selecciona registro 7 (color)" (segundo `OUT` del patron estandar
  de escritura a registro VDP).
- **Hallazgo con alta confianza**: las 3 parejas D/E de
  `CONFIGURAR_MASCARA_PAGINA_0/1/2` (`$03`/`$FC`, `$0C`/`$F3`,
  `$30`/`$CF`) son exactamente los pares mascara/complemento para los
  bits 1-0/3-2/5-4 (2 bits por pagina) del registro de slot -- D
  aisla los bits de esa pagina, E es su complemento exacto (usado
  para limpiar esos mismos bits antes de insertar el valor nuevo en
  `APLICAR_CAMBIO_SLOT`). Sin hedge, patron matematicamente exacto
  (`$FC` = NOT `$03`, etc.).
- Resto del codigo muerto en `AYUDANTE_MOTOR_CINTA_B` (`$13`, `$09`,
  puerto `$AB`) comentado con hedge explicito de incertidumbre (rutina
  nunca invocada, sin forma de verificar contra ejecucion real).

**Verificado**: recompilado sin errores. Diffs en la linea base
exacta de siempre (7/2, solo comentarios, 0 bytes de codigo). `.dsk`/
`.cas` regenerados sin incidencias.


### Nuevo `recursos/mapa_memoria_logotopo.html`, preparado para el futuro desensamblado de LOGOTOPO.CM

Peticion explicita del usuario: crear un mapa de memoria a semejanza
de `mapa_memoria.html` pero dedicado a `LOGOTOPO.CM` (el logo de
cinta de Topo Soft, explicitamente fuera de alcance de la
reorganizacion de `load_cas/`, ver `src/load_cas/LOGOTOPO.CM.txt`),
listo para rellenarse cuando se retome ese sub-proyecto de RE.

Misma plantilla visual/CSS/estructura de tablas que el mapa
principal, pero con una diferencia deliberada: la escala de la barra
NO es el mapa de memoria completo (0x0000-0xFFFF) sino una escala
PROPIA acotada solo al rango real de `LOGOTOPO.CM` (`RANGE_START`/
`RANGE_END` = 0x9470/0xA50D, 4253 bytes) -- `pct()` recalculada en
consecuencia, y la regla de direcciones usa paso de 0x100 en vez de
0x1000 (rango demasiado pequeno para que los saltos de 0x1000 den mas
de 1-2 marcas). `FILES` tiene una unica entrada (sin reubicacion:
`exec` == `start` == 0x9470 en la cabecera real del bloque de cinta).

`SEGMENTS` arranca con solo 2 entradas: los 3 bytes ya confirmados
sin desensamblar nada (`JP $95D1`, primer opcode real, ya documentado
en `LOGOTOPO.CM.txt`) y el resto entero marcado "sin explorar
todavia" -- pensado para irse subdividiendo segmento a segmento
exactamente igual que se hizo historicamente con `mapa_memoria.html`.

`src/README.md` actualizado (nueva entrada en "Visores HTML"); de
paso, quitado un contador de etiquetas ("729") ya desactualizado en
la entrada de `flujo_programa.html` (ese documento ya muestra su
propio recuento en vivo en su cabecera generada, duplicarlo en
`README.md` solo genera otra fuente que se desincroniza).

**Verificado**: pagina nueva, no afecta a la compilacion ni a los
binarios -- no aplica recompilar/diff de bytes. Estructura HTML/JS
revisada visualmente contra `mapa_memoria.html` (misma plantilla,
solo cambia el rango/escala y el contenido de `SEGMENTS`/`FILES`).


## RETOMADO: desensamblado de LOGOTOPO.CM -- primer bloque de codigo transcrito y verificado (0x9470-0x9693, 549 bytes, 0 diferencias)

Peticion explicita del usuario: "Desensambla LOGOTOPO.CM.bin y
empezamos a trabajar con el" -- retoma el sub-proyecto que se habia
dejado deliberadamente pospuesto (ver entrada anterior y
`src/load_cas/LOGOTOPO.CM.txt`).

**Desensamblado inicial**: `Z80Dasm.exe -offset 9470
src/load_cas/LOGOTOPO.CM.bin` (nuestra copia ya excluye la cabecera
BLOAD de 7 bytes -- empieza directo en `C3 D1 95`, sin necesitar
`-begin`). Salida completa (3645 lineas) guardada en
`src/load_cas/LOGOTOPO_dasm_raw.txt` como referencia para las
siguientes rondas.

**Hallazgo clave, mismo patron que el resto del proyecto**: el
desensamblado LINEAL de Z80Dasm no distingue codigo de datos --
buscando tramos largos de `nop` (blocks de `$00`, tipicos de zonas de
imagen/color con fondo negro) se localizaron decenas de rupturas de
sincronismo a partir de `0x9694` (saltos a direcciones absurdas como
`$6c0c`, instrucciones sueltas sin sentido como `ex af,af'` en medio
de lo que deberia ser una tabla). Inspeccion manual confirmo que el
tramo `0x9470-0x9693` es codigo real y coherente (termina en
`JP $0059`, un tail-call limpio) y que justo despues, en `0x9694`,
empieza contenido que decodifica como basura -- frontera natural para
la primera transcripcion.

**Transcrito y verificado el primer bloque** (`0x9470-0x9693`, 549
bytes): convertido de sintaxis Z80Dasm a SjASMPlus con un script
Python de un solo uso (normaliza mnemonicos a mayusculas, detecta
todos los destinos de `JR`/`DJNZ`/`JP`/`CALL` dentro del rango y les
asigna una etiqueta placeholder `L_XXXX` = direccion real en hex --
mismo criterio que nombres antiguos de este proyecto como
`HANDLER_311B`/`R51FE_MAIN` antes de entenderlos). Nuevo fichero
`src/load_cas/logotopo_cm_body.asm`, con cabecera explicando el
estado "EN PROGRESO". El resto del bloque de cinta (`0x9694-0xA50C`,
3705 bytes) queda como `INCBIN` de
`src/data/logotopo/datos_sin_analizar_9691.bin` (mismo patron
histórico de este proyecto: transcribir por partes, mantener el
resto como `INCBIN` hasta la siguiente ronda) + 1 byte suelto final
($00, fuera del rango start/end real de la cabecera .cas, mismo
patron que otros ficheros de este fichero de cinta).

**Estructura de alto nivel ya identificada** (13 rutinas, nombres
provisionales por direccion):
- `L_9470`: entrada real (`JP L_95D1`, salta por encima de las
  definiciones de subrutinas hasta el punto de arranque real).
- `L_94A6`/`L_967E`: escriben N bytes consecutivos en VRAM con el
  valor de A, via un hook ROM en `$004D` -- patron de uso (A=byte,
  HL=direccion VRAM antes del `CALL`) coincide con la convencion
  estandar de `WRTVRM`, probable pero NO confirmado al 100% contra
  una tabla de referencia de hooks BIOS.
- `L_9473`: dibuja un rectangulo/marco con temporizacion por `HALT`
  (3 frames entre iteraciones) -- candidato a efecto de "dibujado
  progresivo".
- `L_94B1`: rutina de "glifo"/caracter grande -- lee un indice, lo
  busca en una tabla de punteros (`$96F8`), copia pares
  (ancho,posicion) desde una tabla de formas en `$9728` a un buffer
  de trabajo, y compone contra VRAM byte a byte. Usa CODIGO
  AUTOMODIFICADO (`LD ($94F1),A`/`LD ($94DD),A` sobreescriben los
  operandos de instrucciones `LD B,n`/`LD C,n` mas arriba en la misma
  rutina) -- mismo patron ya visto en `test_bin_body.asm`
  (`ENASLT_EXTENDIDO`) y en `madmix_scr_body.asm` esta sesion.
- `L_950B`/`L_9532`/`L_954D`/`L_956B`/`L_958E`/`L_95AE`: 6 "efectos"
  de entrada del logo, cada uno prepara parametros
  (`$94BD`/`$94B2`/`$94E9`/`$94F3`, tambien automodificados) y llama
  en bucle a `L_94B1`/`L_94A6`, consumiendo tablas de datos en
  `$96B2`/`$96CC`/`$96E9` (todavia sin analizar, dentro del `INCBIN`).
- `L_95D1`: SECUENCIA PRINCIPAL real (a la que salta `L_9470`).
  Limpia la tabla de color VRAM completa (`L_9602`) y encadena los 6
  efectos + 2 rellenos VRAM (`L_9688`) + el dibujado de rejilla/marco
  (`L_962B`) en un orden fijo -- la mejor pista de alto nivel de "como
  se construye el logo en pantalla" disponible todavia.
- `L_9602`: rellena 0x1800 (6144) bytes en VRAM `$2000` con `$F0`,
  byte a byte via `$004D` -- 6144 coincide EXACTO con el tamano de la
  tabla de color de SCREEN2 (32x8x24). Hipotesis de alta confianza:
  borra/prepara la tabla de color antes de dibujar.
- `L_9614`: escribe un patron (`$81`) en VRAM `$2F78` en bloques de 2
  filas x 64 bytes -- candidato a "dibujar marco/borde solido".
  `L_9688`: HL=$0000/DE=$C000/BC=$1800, salta a un hook ROM en
  `$0059` -- candidato a `FILVRM`/`LDIRVM`/`LDIRMV` segun la tabla
  estandar de hooks BIOS, identidad exacta SIN CONFIRMAR (los 3
  registros cargados no bastan por si solos para distinguir cual sin
  verificar contra una referencia real).
- `L_962B`: dos "cajas" de lineas (`$71` x5 filas, `$31` x6 filas, via
  `L_967E`) que arrancan en `$2658`, con desplazamiento repetido 16
  veces hasta que E llega a `$98` -- candidato a rejilla/marco
  decorativo, pendiente de descifrar del todo.

**Integracion en `main.asm`**: nuevo bloque `ORG $9470` /
`INCLUDE "load_cas/logotopo_cm_body.asm"` / `SAVEBIN
"build/cas/LOGOTOPO.CM", ...`, colocado DESPUES del bloque de
`MADMIX1.BIN` a proposito -- `$9470-$A50D` coincide con el rango
ESTATICO de `MADMIX1.BIN` (fuente de caracteres/sprites,
`$92E3-$B93B`), mismo patron ya verificado con `TEST.BIN`/`$C350`
(driver de sonido): `SAVEBIN` toma una foto del buffer en su propio
momento, en orden de fuente, asi que no hay conflicto real.

**Verificado**: recompilado sin errores. `build/cas/LOGOTOPO.CM`
generado (4253 bytes) con **0 diferencias** byte a byte contra
`src/load_cas/LOGOTOPO.CM.bin` (los 4253 bytes reales, sin contar el
byte suelto). Linea base de siempre intacta en los 3 binarios
existentes: `MADMIX.SCR` 7 diferencias, `MADMIX1.BIN` (disco Y cinta)
2 diferencias cada uno -- confirma que reutilizar el rango de
direcciones de `MADMIX1.BIN` no tuvo ningun efecto colateral.
`.dsk`/`.cas` reconstruidos regenerados sin incidencias (todavia NO
incluyen `LOGOTOPO.CM` en el paquete -- `gen_cas_file.py` sigue sin
tocar, pendiente para cuando el desensamblado este mas avanzado).
`recursos/mapa_memoria_logotopo.html` actualizado: el segmento unico
"sin explorar" se dividio en el bloque `0x9470-0x9693` (ya
codigo/verificado) y el resto sin analizar.

**Pendiente para la siguiente ronda**: desensamblar el resto
(`0x9694-0xA50C`, 3705 bytes) -- previsiblemente una mezcla de tablas
de datos (formas/punteros ya referenciados desde el bloque de arriba)
y mas codigo; entender en detalle las 13 rutinas ya transcritas
(nombres `L_XXXX` son solo placeholders); confirmar la identidad
exacta de los hooks ROM en `$0059` (y reforzar la de `$004D`) contra
una tabla de referencia de hooks BIOS MSX.


### LOGOTOPO.CM: renombradas ENTRADA_LOGOTOPO/DIBUJAR_LOGO_TOPOSOFT, decodificadas las tablas de indices/formas, y renderizador nuevo

**Renombradas** (confirmadas por el usuario): `LOGOTOPO_ENTRY` ->
`ENTRADA_LOGOTOPO` (el `JP` inicial, `$9470`) y `L_95D1` ->
`DIBUJAR_LOGO_TOPOSOFT` (la secuencia real que dibuja el logo).
Recompilado, 0 diferencias en `LOGOTOPO.CM` (4253 bytes) y linea base
de siempre intacta (7/2).

**Hallazgo: mas codigo automodificado del que se penso al transcribir**.
Revisando en detalle `L_94B1` para responder que hace cada `CALL` de
`DIBUJAR_LOGO_TOPOSOFT`, se confirmo que `$94B2`, `$94BD` y `$94E9`
son TAMBIEN operandos automodificados (bytes bajos de 3 instrucciones
placeholder `LD HL,$0000` dentro de `L_94B1`, no solo `$94F1`/`$94DD`
que ya estaban comentados) -- son indices que el llamador inyecta
antes de cada `CALL L_94B1`. Y `$94F3` no es una direccion de datos:
es literalmente el OPCODE de la instruccion `OR (HL)` en `$94F3`
(dentro de `L_94F2`) -- `DIBUJAR_LOGO_TOPOSOFT` lo pone a `$00`
(NOP, via `XOR A`) al principio, y `L_956B` lo restaura a `$B6`
(`OR (HL)`) explicitamente mas tarde, un interruptor "combinar con
VRAM SI/NO" tambien automodificado.

**Mecanismo confirmado**: `$94BD` (indice de "forma") se dobla y se
busca como palabra en la tabla de punteros `$9694` (15 entradas
validas, indices 0-14 -- confirmado por solapamiento real de
direcciones: la entrada 15 cae ya dentro de la tabla de `L_950B` en
`$96B2`); el valor se suma a `$9728` para dar la direccion real de
los datos de la forma. Cada forma tiene cabecera de 2 bytes: 1er byte
(automodifica el operando de `LD B,n` en `L_94F0`) = bytes escritos
por segmento; 2o byte (automodifica el operando de `LD C,n` en
`L_94DC`) = numero de segmentos. `$94B2` (indice de "ancho/posicion")
alimenta la tabla `$96F8`, que resulto ser solo una secuencia
incremental (`$00C0,$00C1,$00C2...`) usada como delta de fila -- NO
aporta contenido visual, solo posicionamiento.

**Tablas de indices decodificadas** (bytes extraidos directos del
`.bin`, script de un solo uso, sin cambios en el codigo fuente):
- `$96B2` (usada por `L_950B`, animada con `HALT`): `1,1,2,2,3,3,4,4,
  5,5,6,6,5,5,4,4,3,3,2,2,1,1,0,0,FF` -- patron simetrico "crece y
  decrece" (pulso), 24 entradas + fin.
- `$96CC` (usada por `L_958E`, sin `HALT`, 2 bytes/entrada): fila
  creciente `$30->$70` con forma `6,5,4,4,3,2,2,1,2,2,3,4,5,6` --
  candidato a curva/franja de grosor variable.
- `$96E9` (usada por `L_95AE`, animada con `HALT`, posicion FIJA):
  `11,12,13,12,11,12,13,14,FF` -- mismo patron de pulso en otro rango
  de indices (formas 7-10, mucho mas grandes que las 0-6).

**Renderizador nuevo**: `recursos/logotopo_formas.html` -- extrae
(script de un solo uso) las 15 formas de la tabla `$9694` y las
renderiza como tiles 8x8 monocromos (1 bit/pixel, MSB=izquierda,
formato nativo de la tabla de patrones VDP), con control de
"columnas" ajustable por tarjeta para experimentar con la disposicion
real (los datos crudos no bastan por si solos para saber si van en 1
fila larga o en una rejilla -- la cabecera B/C da la disposicion mas
literal, usada como valor por defecto). Verificado que los bytes
extraidos son datos de imagen reales (no basura): patrones de
sombreado clasicos como `$AA`/`$55` (tablero de ajedrez a nivel de
bit) y `$FF`/`$C0` (rellenos solidos) aparecen por todas partes en
las formas 7-10 (las 4 mas grandes, 280-792 bytes).

**Pendiente**: identificacion visual de cada forma (que letra/icono
representa) -- tarea para el usuario con el renderizador ya
construido, punto de partida para nombrar `L_950B`/`L_9532`/etc. con
mas seguridad.

**Nota de proceso**: al inyectar el JSON de las formas en el HTML via
PowerShell (`Get-Content -Raw` + `WriteAllText`), el fichero se
corrompio (mojibake: `—`/`ó`/`í` etc. mal codificados) -- PowerShell
interpreto el UTF-8 con la codepage equivocada en el roundtrip.
Corregido reescribiendo el fichero completo de una vez con la
herramienta de escritura nativa (sin pasar por PowerShell para texto
con caracteres no-ASCII). Guardado en memoria para futuras sesiones.


### CONFIRMADA VISUALMENTE la animacion completa del logo -- 9 rutinas renombradas

El usuario identifico la animacion real usando
`recursos/logotopo_formas.html` (y compartio un video de referencia,
segunda mitad de https://www.youtube.com/watch?v=gm3muULn91E, no
consultado directamente -- confirmacion verbal suficiente): el logo
anima las letras T-O-P-O deslizandose/revelandose para formar "Topo",
debajo la palabra "Soft" rotando sobre si misma, y remata con una
estrella parpadeante a la derecha de la T. Mapeo exacto confirmado:
idx7=T, idx8=1a O, idx9=P, idx10=2a O -- coincide EXACTO con lo que
ya se habia deducido por codigo (cada rutina fija `$94BD` a un indice
de forma constante antes de dibujar).

**Renombradas** (9 etiquetas, todas verificadas -- recompilado sin
errores, `LOGOTOPO.CM` 0 diferencias, linea base de siempre intacta
7/2):
- `L_94B1` -> `DIBUJAR_FORMA_ANIMADA` (el motor generico de dibujado
  de formas, ya entendido con detalle: indice en `$94BD`, tabla de
  punteros `$9694` de 15 formas, cabecera de 2 bytes
  bytes-por-segmento/numero-de-segmentos).
- `L_9532` -> `DIBUJAR_T_TOPO` (forma fija=7, desliza via `$94E9`).
- `L_954D` -> `DIBUJAR_P_TOPO_ANIMADA` (forma fija=9, desliza con
  `HALT` entre pasos).
- `L_956B` -> `DIBUJAR_O1_TOPO` (forma fija=8, 7 pasos con distinto
  offset de tabla de posicion).
- `L_958E` -> `DIBUJAR_O2_TOPO_ANIMADA` (forma fija=10, 14 pasos con
  fila creciente `$30->$70` -- revelado tipo "trazo").
- `L_950B` -> `DIBUJAR_SOFT_ROTANDO` (formas 0-6 via tabla `$96B2`,
  patron de pulso 0->6->0, llamada 3 veces desde la secuencia
  principal).
- `L_95AE` -> `DIBUJAR_ESTRELLA_ANIMADA` (formas 11-14 via tabla
  `$96E9`, mismo patron de pulso).
- `L_9602` -> `LIMPIAR_TABLA_COLOR_VRAM`.
- `L_9688` -> `LIMPIAR_TABLA_PATRONES_VRAM`.

Cabeceras de comentario de `DIBUJAR_FORMA_ANIMADA` y
`DIBUJAR_LOGO_TOPOSOFT` reescritas para reflejar el entendimiento
confirmado (antes describian hipotesis sueltas, "efectos sin
identificar"). `recursos/logotopo_formas.html` actualizado: cada
tarjeta muestra ahora el nombre real de la forma (p.ej. "idx7 -- T de
Topo") en vez de solo el indice numerico. `recursos/mapa_memoria_logotopo.html`
actualizado con la confirmacion visual y los nombres nuevos.

**Quedan sin identificar** 3-4 rutinas decorativas que NO usan el
motor de formas (dibujan con patrones fijos `$71`/`$31`/`$81`
directamente): `L_962B` (dos "cajas" de lineas), `L_9614` (relleno de
patron en bloques), `L_9473`/`L_94A6`/`ENTRADA_LOGOTOPO`-area
(rectangulo con `HALT`) -- preguntado al usuario si recuerda algun
marco/linea/rectangulo en la animacion, sin respuesta confirmada
todavia.

**Verificado**: recompilado sin errores. `LOGOTOPO.CM` 0 diferencias.
Linea base de siempre intacta (7/2). `.dsk`/`.cas` regenerados sin
incidencias.


### Completada la identificacion visual del logo: 4 rutinas mas renombradas -- animacion completa entendida

El usuario aporto el resto de la secuencia visual: tras dibujarse
"TOPO", el texto se colorea con una animacion que se expande desde el
centro hacia los lados; despues "Soft" rota; al terminar, un punto de
luz recorre "Soft" por su linea superior y acaba junto a la estrella,
sobre la esquina de la T. El ORDEN coincide exacto con el orden real
de las llamadas en `DIBUJAR_LOGO_TOPOSOFT` (verificado antes de
renombrar, no despues): tras las 4 letras de TOPO vienen 2 rutinas
sin identificar, luego `DIBUJAR_SOFT_ROTANDO` x3, luego una tercera
rutina sin identificar, luego `DIBUJAR_ESTRELLA_ANIMADA` -- mapeo
1:1 con "colorea TOPO (2 rutinas) -> Soft rota -> punto de luz (1
rutina) -> estrella".

**Renombradas** (4 etiquetas, confirmadas por el usuario):
- `L_962B` -> `ANIMAR_COLOR_TOPO`: la animacion de color expandiendose
  desde el centro (dos "cajas" de lineas de color arrancando en
  `$2658`, repitiendo 16 veces con pausa `HALT` de 4 frames entre
  cada paso -- la pausa confirma que es una animacion, no un dibujado
  instantaneo).
- `L_9614` -> `RELLENAR_COLOR_TOPO`: remate/consolidacion del color
  justo despues (llamada inmediatamente tras `ANIMAR_COLOR_TOPO`).
- `L_9473` -> `ANIMAR_PUNTO_LUZ_SOFT`: el punto de luz que recorre
  "Soft" (recorre un rango de direcciones VRAM `$2F78->$2FB8` con
  `HALT` como temporizador entre posiciones -- llamada justo despues
  de las 3 rotaciones de `DIBUJAR_SOFT_ROTANDO` y justo antes de
  `DIBUJAR_ESTRELLA_ANIMADA`, posicion exacta esperada).
- `L_94A6` -> `ESCRIBIR_8_BYTES_VRAM` (el helper generico "escribe 8
  bytes en VRAM(HL) con el valor de A", usado por varias de las
  rutinas ya identificadas -- renombrado por claridad, no por ser
  parte visual propia).

Con esto, **todas las rutinas de primer nivel** del bloque ya
transcrito (`$9470-$9693`) tienen nombre real describiendo su papel
en la animacion -- solo quedan etiquetas locales de bucle (`L_XXXX`)
sin renombrar, que no lo necesitan (puntos de convergencia internos,
no funciones independientes). Cabeceras de comentario de las 3
rutinas principales y de `DIBUJAR_LOGO_TOPOSOFT`/cabecera del fichero
reescritas para reflejar el entendimiento completo.

`recursos/mapa_memoria_logotopo.html` actualizado (nota superior +
detalle del segmento) reflejando la animacion completa confirmada.

**Verificado**: recompilado sin errores. `LOGOTOPO.CM` 0 diferencias.
Linea base de siempre intacta (7/2). `.dsk`/`.cas` regenerados sin
incidencias.


### `gen_cas_file.py` ya empaqueta el LOGOTOPO.CM ensamblado por nosotros, no la copia verbatim

Peticion explicita del usuario: ahora que `logotopo_cm_body.asm` esta
verificado (0 diferencias contra el `.bin` de referencia), el `.cas`
empaquetado debe usar NUESTRO binario compilado, no la copia verbatim
de `load_cas/LOGOTOPO.CM.bin` que se usaba hasta ahora.

Cambiado `tools/gen_cas_file.py`: la lectura de `logotopo` paso de
`load_cas/LOGOTOPO.CM.bin` (copia verbatim) a `build/cas/LOGOTOPO.CM`
(generado por `main.asm` desde `logotopo_cm_body.asm`). Detalle
importante: `build/cas/LOGOTOPO.CM` son los 4253 bytes reales del
cuerpo (`SAVEBIN` termina en `END_OF_FILE_LOGOTOPO`, ANTES del byte
suelto final) -- el bloque real de 1988 SI incluye ese byte suelto
($00) como parte del payload (ya documentado en la ronda de creacion
del fichero), asi que se restaura sumando `+ bytes([0x00])` en Python
tras leer el fichero, con comentario explicando por que. Docstring
del fichero y `src/README.md` actualizados (ya no dicen "copia
verbatim" para `LOGOTOPO.CM`).

**Verificado**: `py tools/build_all.py` + `py tools/gen_disk_and_cas.py`
desde cero. `build/madmix_reconstruido.cas` (50242 bytes, tamaño
exacto) comparado byte a byte contra el `.cas` original de 1988
(`FISICO/Mad Mix Game (1988).../...cas`): **exactamente las mismas 9
diferencias de siempre** (offsets 11902-11904 = `$28ED-$28EF`
preexistente ajeno; 23045/23296/24235/29318/29557 = fix deliberado
`$FC60->$FC50`; 50241 = ultimo byte del fichero, ya conocido) --
**ninguna diferencia nueva**, confirma que sustituir la fuente de
`LOGOTOPO.CM` por la nuestra no afecto al empaquetado. `.dsk` sin
tocar (no depende de `LOGOTOPO.CM`, no aplica).


### Segmentado el resto de LOGOTOPO.CM (INCBIN unico -> tablas y 15 formas con etiquetas reales), y CORREGIDO un error de esta misma sesion: no habia "byte suelto", eran 4254 bytes reales

Peticion explicita del usuario: seccionar `datos_sin_analizar_9691.bin`
(el INCBIN opaco de 3705 bytes) en las imagenes ya identificadas
(las 15 formas, ya confirmadas visualmente) y el resto de bloques
pendientes.

**Corregido un error introducido en una ronda anterior de esta misma
sesion**: al calcular los limites exactos de cada forma con la tabla
de punteros real (en vez de asumir empaquetado secuencial), se vio
que `FORMA_ESTRELLA_4` deberia terminar exactamente en `$A50D` -- la
misma direccion que se habia documentado como "byte suelto, contenido
desconocido, fuera del rango real". La cabecera `start=$9470
end=$A50D` del bloque `.cas` usa "end" INCLUSIVE (misma convencion ya
usada, y verificada, para `LOAD.BIN`/`TEST.BIN` -- `$DECA-$DDA0=298`
+1 = 299 bytes, el tamano real documentado), no exclusive como se
asumio al partir el fichero por primera vez. El cuerpo real son
**4254 bytes** (`$9470-$A50D` ambos inclusive), sin ningun byte fuera
de rango: el ultimo byte es simplemente el ultimo byte real del
bitmap de `FORMA_ESTRELLA_4`. Corregido en `logotopo_cm_body.asm`
(cabecera del fichero, `END_OF_FILE_LOGOTOPO` ahora tras la ultima
forma) y en `gen_cas_file.py` (ya no hace falta el `+bytes([0x00])`
que restauraba el byte que faltaba).

**Estructura real descubierta** (verificada con un script de
extraccion que usa la tabla de punteros REAL, no asume contigueidad):

- `TABLA_PUNTEROS_FORMAS` (`$9694-$96B1`, 30 bytes): 15 palabras,
  ahora escritas como diferencia de etiquetas (`FORMA_X-TABLA_FORMAS`)
  en vez de hex literal, para que sigan correctas si cambia el tamano
  de alguna forma.
- `TABLA_ANIMACION_SOFT` (`$96B2-$96CA`, 25 bytes) + 1 byte suelto
  sin explicar (`$96CB`) + `TABLA_TRAZO_O2_TOPO` (`$96CC-$96E8`, 29
  bytes) + `TABLA_ANIMACION_ESTRELLA` (`$96E9-$96F1`, 9 bytes): las 3
  tablas de indices ya decodificadas en una ronda anterior, ahora con
  etiqueta y datos reales (antes solo documentadas en prosa).
- `VARIABLES_TRABAJO_FORMA` (`$96F2-$96F7`, 6 bytes a cero): incluye
  los 2 punteros de trabajo (`$96F4`/`$96F6`) que `DIBUJAR_FORMA_ANIMADA`
  usa como scratch RAM.
- `TABLA_DELTA_POSICION` (`$96F8-$9727`, 48 bytes): **corregido un
  segundo error** en la misma ronda -- los primeros intentos de
  escribirla como `DW $00C0..$00D7` dieron 48 diferencias al
  recompilar (el byte alto real es el que incrementa, `$C000..$D700`,
  no el bajo -- `LD E,(IX+0)` lee el byte BAJO primero, `LD D,(IX+0)`
  el ALTO despues, así que la memoria real es "00 C0 00 C1..." =
  DE=$C000,$C100... no $00C0,$00C1...). Corregido y verificado 0
  diferencias.
- `TABLA_FORMAS` (`$9728-$A50D`, resto): las 15 formas reales,
  extraidas cada una a su propio fichero binario en
  `src/data/logotopo/formas/` (mismo patron que `.til`/`.spr` de
  otras partes del proyecto), con cabecera de 2 bytes (`DB ancho,
  filas`) escrita directamente en el `.asm`. **Hallazgo nuevo**: el
  orden FISICO en el fichero no es 0..14 secuencial -- hay un bloque
  de 40 bytes de datos graficos HUERFANOS (mismo patron de sombreado
  `$AA`/`$55` que las formas reales, pero SIN ninguna entrada de
  `TABLA_PUNTEROS_FORMAS` que los referencie) entre `FORMA_O1_TOPO` y
  `FORMA_P_TOPO` -- mismo tipo de hallazgo que los 6 guiones de demo
  sin usar ya documentados en `madmix1_body.asm` (ver
  `mapa_memoria.html`). Preservado tal cual en
  `src/data/logotopo/formas/huerfano_9eea.bin`, sin uso conocido.

Eliminado `src/data/logotopo/datos_sin_analizar_9691.bin` (superado
por la segmentacion real, ya no referenciado en ningun sitio).
`recursos/mapa_memoria_logotopo.html` reescrito con el desglose
completo (8 segmentos en vez de 1 generico "sin explorar"), corregido
el mismo error de "end" exclusive/inclusive en `RANGE_END`/`FILES`.
`src/README.md` actualizado (tamano 4254, estado "COMPLETO", nueva
entrada para `logotopo_formas.html` en "Visores HTML").

**Verificado**: recompilado sin errores. `build/cas/LOGOTOPO.CM`
ahora 4254 bytes (antes 4253), **0 diferencias** contra
`LOGOTOPO.CM.bin` completo (los 4254 bytes reales, ya no 4253+1).
Linea base de siempre intacta (`MADMIX.SCR` 7, `MADMIX1.BIN` 2).
`.dsk`/`.cas` regenerados: `madmix_reconstruido.cas` comparado de
nuevo contra el `.cas` original de 1988, **mismas 9 diferencias de
siempre, ninguna nueva** -- confirma que la correccion del tamano no
afecto al empaquetado final.


### Renombradas todas las etiquetas L_ restantes de LOGOTOPO.CM (25 locales + 1 global) -- fichero sin ningun placeholder pendiente

Peticion explicita del usuario: revisar las 26 etiquetas `L_XXXX`
placeholder que quedaban en `logotopo_cm_body.asm`, explicar que hace
cada una y proponer nombre.

**2 etiquetas eliminadas** (`L_94DC`, `L_94F0`, dentro de
`DIBUJAR_FORMA_ANIMADA`): sin ninguna referencia real de
`JR`/`JP`/`DJNZ` -- se habian anadido de mas al transcribir, sin
aportar ningun punto de convergencia real. Quitadas sin mas.

**24 etiquetas convertidas a locales** (puntos de bucle internos, sin
referencias externas a su rutina): `.BUCLE_AVANZAR_PUNTO`/
`.BUCLE_ESPERA_3_FRAMES` (`ANIMAR_PUNTO_LUZ_SOFT`); `.BUCLE_8_BYTES`
(`ESCRIBIR_8_BYTES_VRAM`); `.BUCLE_SEGMENTO`/`.BUCLE_BYTE`
(`DIBUJAR_FORMA_ANIMADA`); `.BUCLE_POSICION` (`DIBUJAR_T_TOPO` y,
por separado, `DIBUJAR_P_TOPO_ANIMADA` -- mismo nombre local, scopes
distintos); `.BUCLE_SEGMENTO`/`.ULTIMO_SEGMENTO` (`DIBUJAR_O1_TOPO`,
el segundo es el tramo final con `JP` en vez de `CALL`, tail-call);
`.BUCLE_TRAZO`/`.ULTIMO_TRAZO` (`DIBUJAR_O2_TOPO_ANIMADA`, mismo
patron); `.BUCLE_FOTOGRAMA`/`.BUCLE_ESPERA_4_FRAMES`
(`DIBUJAR_ESTRELLA_ANIMADA`); `.BUCLE_RELLENO`
(`LIMPIAR_TABLA_COLOR_VRAM`); `.BUCLE_FILA`/`.BUCLE_BYTE`
(`RELLENAR_COLOR_TOPO`); `.BUCLE_EXPANSION`/`.BUCLE_CAJA_1A`/
`.BUCLE_CAJA_1B`/`.BUCLE_CAJA_2A`/`.BUCLE_CAJA_2B`/
`.BUCLE_ESPERA_4_FRAMES` (`ANIMAR_COLOR_TOPO`, la animacion dibuja
las mismas 2 "cajas" de lineas dos veces, en 2 puntos de arranque
distintos -- de ahi el sufijo 1/2); `.BUCLE_8_BYTES`
(`ESCRIBIR_8_BYTES_VRAM_C`, ver abajo).

**1 etiqueta renombrada como GLOBAL** (`L_967E` -> 
`ESCRIBIR_8_BYTES_VRAM_C`): a diferencia de las demas, SI se llama
desde otra rutina (`ANIMAR_COLOR_TOPO`, 4 veces) -- no podia
convertirse a local. Es gemela de `ESCRIBIR_8_BYTES_VRAM` (mismo
patron "escribe 8 bytes en VRAM(HL) con el valor de A via WRTVRM"),
pero usa `C` como contador en vez de `B` -- de ahi el sufijo `_C`.

**Trampa de scoping de locales, pisada 2 veces en esta misma ronda**
(ya documentada en rondas anteriores del proyecto, sigue siendo
facil de pisar): convertir una etiqueta a local rompe la compilacion
si una etiqueta GLOBAL/no-local queda entre su definicion y su
referencia. Ocurrio con `L_949F` (entre la definicion de
`.BUCLE_AVANZAR_PUNTO` y su `JR` de vuelta) y otra vez con la
reconversion de una ronda anterior de esta sesion -- solucionado
convirtiendo tambien esas etiquetas intermedias a locales, mismo
patron de fix ya usado en `madmix_scr_body.asm` (SIN_REGENERAR_MARICOCO)
y `test_bin_body.asm` (ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO) esta
misma sesion.

Cabecera del fichero actualizada: ya no queda ninguna etiqueta
`L_XXXX` placeholder en todo `logotopo_cm_body.asm`.

**Verificado**: recompilado sin errores. `LOGOTOPO.CM` 0 diferencias
(4254 bytes). Linea base de siempre intacta (`MADMIX.SCR` 7,
`MADMIX1.BIN` 2). `.dsk`/`.cas` regenerados sin incidencias.
`recursos/flujo_programa.html` regenerado: 643 etiquetas (670 -> 643,
-27: -26 conversiones global->local +1 nueva global, -2 eliminadas).


### Revision de datos/variables de `logotopo_cm_body.asm`: 6 hex sustituidos por etiquetas de tabla + decimal donde procede

Peticion explicita del usuario: revisar todos los datos/variables,
convertir a decimal lo que proceda, comprobar si algun hex puede
sustituirse por una etiqueta ya existente, y comentar cada uno.

**6 direcciones hex sustituidas por la etiqueta real** (todas
apuntaban exacto a una de las tablas ya etiquetadas en la ronda de
segmentacion anterior, sin cambio de bytes):
- `LD DE, $96F8` -> `LD DE, TABLA_DELTA_POSICION` (en `DIBUJAR_FORMA_ANIMADA`)
- `LD DE, $9694` -> `LD DE, TABLA_PUNTEROS_FORMAS` (idem)
- `LD HL, $9728` -> `LD HL, TABLA_FORMAS` (idem)
- `LD HL, $96B2` -> `LD HL, TABLA_ANIMACION_SOFT` (en `DIBUJAR_SOFT_ROTANDO`)
- `LD HL, $96CC` -> `LD HL, TABLA_TRAZO_O2_TOPO` (en `DIBUJAR_O2_TOPO_ANIMADA`)
- `LD HL, $96E9` -> `LD HL, TABLA_ANIMACION_ESTRELLA` (en `DIBUJAR_ESTRELLA_ANIMADA`)

**Decimal donde procede**: todos los indices de forma (`$94BD`),
indices de tabla de posicion (`$94B2`) y posiciones/filas (`$94E9`)
automodificados por las 6 rutinas "efecto" -- confirmados como
valores de indice/posicion puros, no direcciones ni mascaras (p.ej.
`LD A,$07`->`LD A,7` = indice de `FORMA_T_TOPO`). Todos los
contadores de bucle puros (`LD B,$XX`/`LD C,$XX` usados con
`DJNZ`/`DEC`, nunca como mascara). Los tamanos de tabla de color/patron
completa (`LD BC,$1800`->`6144`, x2). Los pasos de posicion
(`ADD A,$08`->`8`, `ADD A,$10`->`16`, `SUB $08`->`8`) y las
comparaciones de posicion final (`CP $18`->`24`, `CP $50`->`80`,
`CP $98`->`152`). Por consistencia con ese mismo criterio, tambien
`TABLA_TRAZO_O2_TOPO` (bytes de posicion/fila, antes `$30..$70`,
ahora `48..112`).

**Se deja en hex a proposito**: direcciones VRAM (`$2F78`, `$2658`,
`$2000`, `$0000`), bytes de color/patron VDP (`$81`, `$F1`, `$F0`,
`$71`, `$31`), el opcode real de "OR (HL)" (`$B6`, es un opcode, no
un dato), sentinelas de tabla (`$FF`), el delta con signo `$FFE8`-style
(`$FFF8` = -8), y los placeholders automodificados de
`DIBUJAR_FORMA_ANIMADA` (`LD HL,$0000` x3 -- su valor real nunca se
usa, se sobreescribe siempre antes de leerse).

**Hallazgo aparte, no aplicado**: `$2F78` se usa IDENTICO como dirección
de arranque en dos rutinas distintas (`ANIMAR_PUNTO_LUZ_SOFT` y
`RELLENAR_COLOR_TOPO`) sin ninguna etiqueta propia -- candidato a una
nueva `EQU` (como se hizo con `$E290-$E293` en `test_bin_body.asm`),
pero la relacion semantica entre ambos usos sigue sin estar clara
(ver comentario ya existente en `RELLENAR_COLOR_TOPO`). Igual que
`$2658` (`ANIMAR_COLOR_TOPO`) y `$2000` (`LIMPIAR_TABLA_COLOR_VRAM`).
Se deja pendiente de confirmacion expresa del usuario antes de
etiquetar, en vez de aplicarlo directamente.

**Verificado**: recompilado sin errores. `LOGOTOPO.CM` 0 diferencias
(4254 bytes, solo comentarios/sustituciones de etiqueta, 0 bytes de
codigo cambiados). Linea base de siempre intacta (`MADMIX.SCR` 7).
`.dsk`/`.cas` regenerados sin incidencias.


### Confirmado por el usuario: creadas las 3 etiquetas VRAM pendientes de la entrada anterior

`$2000`/`$2658`/`$2F78` -- las 3 direcciones VRAM (todas dentro de la
tabla de color de SCREEN2, `$2000-$37FF`) que se repetian identicas
en varias rutinas sin etiqueta propia -- confirmadas por el usuario.
Creadas como `EQU` al principio del fichero, junto a `ENTRADA_LOGOTOPO`:
- `VRAM_TABLA_COLOR` = `$2000` (base completa de la tabla, usada por
  `LIMPIAR_TABLA_COLOR_VRAM`).
- `VRAM_COLOR_ZONA_TOPO` = `$2658` (usada por `ANIMAR_COLOR_TOPO`).
- `VRAM_COLOR_ZONA_SOFT` = `$2F78` (usada IDENTICA por
  `ANIMAR_PUNTO_LUZ_SOFT` y `RELLENAR_COLOR_TOPO` -- el nombre
  "ZONA_SOFT" es una etiqueta de conveniencia, la relacion semantica
  exacta entre ambos usos sigue sin confirmar del todo, nota dejada
  en el comentario de `RELLENAR_COLOR_TOPO`).

**Verificado**: recompilado sin errores. `LOGOTOPO.CM` 0 diferencias
(solo sustituciones de etiqueta, 0 bytes de codigo cambiados). Linea
base de siempre intacta (`MADMIX.SCR` 7). `.dsk`/`.cas` regenerados
sin incidencias. `recursos/flujo_programa.html` regenerado: 646
etiquetas (643 -> 646, +3 nuevas `EQU`).


## Reescritura completa de `FLUJO_PROGRAMA.md` (estaba congelado desde muy al principio del proyecto)

Revision de "fin de trabajo/documentacion" solicitada por el usuario:
al comparar `FLUJO_PROGRAMA.md` contra el codigo actual se confirmo
que casi todo el documento (secciones 1 a 6, ~550 lineas) usaba
nombres de ANTES de las (al menos) 250+ rondas de renombrado
registradas en este mismo fichero -- sin ninguna nota "antes X ahora
Y", es decir, desactualizado de verdad, no historia deliberada (unica
excepcion parcial: §5.10, que ya usaba en su mayoria nombres
actuales). Confirmado con el usuario: reescritura completa ahora, no
solo marcar como historico ni actualizar parcialmente.

Se releyo el codigo fuente actual (`madmix0_body.asm`,
`madmix1_body.asm`, `madmix_scr_body.asm`) seccion a seccion para
reconstruir el documento desde cero, verificando cada etiqueta citada
contra el codigo real (grep de las ~85 etiquetas globales + varias
locales mencionadas: TODAS existen en el codigo actual, 0
inventadas).

**Correccion de arquitectura, no solo de nombres**: la version vieja
decia que `INIT_MAIN_LOOP` (`$8FD4`) era "el bucle principal". Es
incorrecto -- esa direccion es `PREPARAR_INICIO_NIVEL`, una secuencia
de UN SOLO PASO que solo se ejecuta en transiciones (arranque, cambio
de nivel, perdida de vida), nunca cada frame. El bucle real que se
repite cada frame es `BUCLE_PRINCIPAL_JUEGO`/`VERIFICAR_FIN_NIVEL`
(antes `IML_9078`/`IML_90B7`), un poco mas adelante en el mismo
bloque. Corregido en el nuevo §4, con diagrama y aclaracion explicita
de que el motor de movimiento/colision/scroll corre en paralelo desde
la interrupcion VBLANK (`ENTRADA_INTERRUPCION_VBLANK`/
`GESTIONAR_FRAME`), no dentro del cuerpo de `BUCLE_PRINCIPAL_JUEGO`.

Tambien se actualizo la tabla de opciones del menu principal (§5.8)
con el detalle completo de `DESPACHAR_ACCION_MENU` (bits 1/3/4/5 ->
las 4 opciones, bit 0 = "JUGAR" sale del bucle) y se documento el
truco oculto de vidas infinitas (`.COMPROBAR_TRUCO_VIDAS_INFINITAS`
dentro de `GESTIONAR_INTRODUCCION`, activado con ESC en la intro,
parchea en caliente `SUB $01` -> `SUB $00` en `BUCLE_PRINCIPAL_JUEGO`)
que la version vieja no mencionaba.

Se anadio una seccion final §7 explicita listando los puntos
genuinamente pendientes/hipotesis sin confirmar en vivo (el segundo
`CALL $1000` de `INICIO`, el bit de pausa de `VERIFICAR_ENTRADA`, el
volteo horizontal de sprites en `MOTOR_ACTORES`, las tablas de
instrumento del driver de sonido), para no dar a entender que esta
todo cerrado.

`recursos/flujo_programa.html` (que si se habia mantenido sincronizado
sesion a sesion, a diferencia de `FLUJO_PROGRAMA.md`) tenia solo 2
puntos sueltos desactualizados, corregidos: la abreviatura
"SCROLL_UP/DOWN/LR" (nombres reales actuales:
`SCROLL_ARRIBA`/`SCROLL_ABAJO`/`APLICAR_DESPLAZAMIENTO_LATERAL`) en
la tabla de la §2, y el conteo manual "605 etiquetas" en la nota
introductoria y en la leyenda de clasificacion (desactualizado desde
hace varias rondas de creacion de etiquetas nuevas; corregido a 646,
recalculado con `gen_inventory.py`).

**Verificado**: recompilado sin errores tras `gen_inventory.py`
(646 etiquetas, sin cambios de codigo). Grep final sobre
`FLUJO_PROGRAMA.md` de ~85 nombres antiguos conocidos (todas las
familias de renombrado registradas en este fichero relevantes al
documento): 0 coincidencias.


### Reescritura completa de `manuales/manual_driver_sonido.md` -- estaba desactualizado, y su §8 ("sin resolver") llevaba tiempo resuelto sin que el manual lo reflejara

A peticion del usuario ("creo que el manual del driver de sonido esta
desactualizado, revisalo"). Comparado contra el codigo actual
(`madmix1_body.asm:3390-4426`, region completa del driver): el manual
usaba practicamente todos los nombres de ANTES de la ronda de
renombrado documentada mas arriba ("Renombradas las 26 etiquetas RM_
restantes del driver de sonido..."), sin ninguna nota "antes/ahora" --
desactualizado de verdad, igual que le paso a `FLUJO_PROGRAMA.md`.
Reescrito por completo, mismo criterio: solo lo genuinamente
desactualizado, preservando el resto de la prosa.

**Hallazgo de fondo, no solo de nombres**: la §8 del manual ("Lo que
queda sin resolver: la envolvente de hardware compartida") describia
un misterio que **ya estaba resuelto** en el codigo desde la ronda de
renombrado del driver (ver mas arriba) -- simplemente nadie habia
vuelto a este manual para reflejarlo. La envolvente compartida es
especificamente la envolvente de **RUIDO** (registro 6 del PSG,
periodo de ruido), no un generador de envolvente de hardware generico
por encima de volumen/tono como sugeria la version vieja. Mecanismo
completo: `APLICAR_ENVOLVENTE_RUIDO` (misma estructura de fases que
las envolventes de volumen/tono, una sola fase, sobre la tabla fija
`TABLA_ENVOLVENTE_RUIDO_PSG` en vez de por canal) se alcanza cayendo
sin salto tras el bucle de 3 canales de `TICK_REPRODUCTOR_PSG`, escribe
el resultado en `$C9C4` (sombra del registro 6) y termina en
`VOLCAR_REGISTROS_PSG`. `REINICIAR_ENVOLVENTE_RUIDO` es su relatch.
De paso, corregida la descripcion del comando 11
(`RESET_SHARED_ENVELOPE`): el manual decia "borra la envolvente
compartida, solo si el canal es el dueño" -- en realidad SIEMPRE borra
los 46 bytes completos de la ranura del canal que lo ejecuta, y
ADEMAS borra la tabla compartida de 10 bytes si ese canal es el dueño.
Seccion 8 reescrita de "sin resolver" a "resuelto", con la mecanica
completa.

Resto de cambios: arquitectura (§3), bucle de tick (§4) y tabla de
comandos (§6) actualizados con los nombres reales
(`INSTALAR_RECURSO_SONIDO`, `TICK_REPRODUCTOR_PSG`,
`PROCESAR_CANAL_PSG`, `DESPACHAR_COMANDO_PSG`, `ARMAR_NOTA`,
`CERRAR_NOTA`, `APLICAR_ENVOLVENTES_CANAL`, `ACTUALIZAR_MEZCLADOR_CANAL`,
`MULTIPLICAR_8X16`/`DIVIDIR_16X16`/`LEER_PALABRA_INDEXADA`,
`VOLCAR_REGISTROS_PSG`, `TABLA_NOTAS_PSG`, `TABLA_COMANDOS_PSG`,
`AREA_TRABAJO_PSG`, `TABLA_RETORNO_SUBPATRONES_PSG`,
`TABLA_TRANSPOSICION_PSG`, `TABLA_INSTRUMENTOS_PSG`,
`TABLA_ENVOLVENTES_PSG`, `TABLA_SUBPATRONES_PSG`, los 13
`SUBPATRON_NN_XXXX` individuales, `GUION_MELODIA_CANAL_0/1/2`, los 13
`GUION_EVTxx_..._CExx`, `VACIAR_CANALES_SONIDO`). §7 actualizada con
`DESPACHAR_EFECTO_SONIDO`/`EVENTO_SONIDO_PENDIENTE`/
`TABLA_RECURSOS_SONIDO_EVENTO`, tabla de indices ampliada con la
etiqueta real de cada guion, y corregido el disparador del acorde de
inicio de nivel (es `MOSTRAR_READY_Y_ARRANCAR_NIVEL`, no `IML_900F`
como decia la version vieja -- verificado leyendo el codigo real,
`madmix1_body.asm:2625-2654`).

**Verificado**: grep final sobre el manual de todos los nombres
antiguos conocidos del driver (`LOAD_RESOURCE_SLOT_*`, `RM_*`,
`*_TABLE_C*`, `TAIL_LEVELCYCLE_HELPER`, `LEVELCYCLE_RESOURCE_TABLE`,
`IML_900F`, `$6128` suelto): 0 coincidencias fuera de las 2
menciones deliberadas con framing "antes/ahora". No es un cambio de
codigo (solo documentacion), no aplica recompilacion.



### Nuevo manual: `manuales/manual_motor_colision_ia.md` (motor de movimiento/colision + IA de los 3 tipos de item)

A peticion del usuario, tras sugerirlo yo mismo como segundo candidato
al terminar la revision del manual de sonido. Documento nuevo (no una
correccion de uno existente), mismo estilo/estructura que
`manual_driver_sonido.md`. Releido el codigo fuente real de
`madmix_scr_body.asm` seccion a seccion (motor de colision
`$2CA0-$335C`, tabla de despacho de 20 tipos `$2E3C`, motor generico de
movimiento de item `$5278`, y los 3 manejadores de item
`HNDLR_PELMAZOIDE`/`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO` mas
`ACTIVAR_EFECTO_ITEM`/`AVISAR_PROXIMIDAD_PISTA`/`ARMAR_AVISO_DESTELLO`/
`ACTUALIZAR_DESTELLO_ITEMS`) para reconstruir la explicacion desde
cero, en vez de resumir solo lo ya escrito en `FLUJO_PROGRAMA.md`.

Contenido nuevo, no solo reorganizacion de lo ya sabido: aclara que
`HNDLR_MARICOCO` (mariquita) y `HNDLR_REGPUNANTOSO` (repugnantoso) son
un PAR con efecto contrario sobre la misma franja de indices de loseta
(63-65 "sin bola" -> regenera a 45-47 "con bola" vs. 45-47 -> planta a
48-50 "con bola clavada"), comparten motor de movimiento
(`MOTOR_MOVIMIENTO_ITEM`) y helper de coordenadas
(`MAPEAR_COORDENADA_A_DIRECCION_LOCAL`, uno de los 5 sitios del bug del
nivel 13 ya documentado), y se diferencian en cuando fijan su flag de
"plantado" ((IX+2), al final vs. al entrar) y en si tocan
`CONTADOR_BOLAS_COMIDAS`. Tambien deja constancia expresa de que este
motor NO es pathfinding real (sin BFS/A*, solo mira las 4 losetas
adyacentes) y de que los 8 fantasmas de `TABLA_ITEMS_PELMAZOIDE`
ejecutan el mismo codigo sin distincion de personalidad por fantasma
(a diferencia del Pac-Man original).

**Verificado**: grep final sobre el manual de las 56 etiquetas citadas
(manejadores, tablas, variables de estado) contra `madmix_scr_body.asm`:
las 56 existen tal cual en el codigo actual, 0 inventadas. No es un
cambio de codigo (solo documentacion nueva), no aplica recompilacion.



### Nuevo manual: `manuales/manual_subsistema_grafico.md` (VDP en SCREEN 2, motor de actores sin sprites hardware, losetas y scroll por software)

A peticion del usuario, tercer manual de la serie, siguiendo mi propia
sugerencia inicial (la primera vez que se hablo de "que otros manuales
podriamos hacer" en esta sesion, antes de escribir el de colision/IA).
Releido el codigo fuente real de `madmix1_body.asm` (motor de actores
completo `MOTOR_ACTORES`/`COMPONER_ACTORES_EN_BUFFER`/inversion de
patron, API de VDP `FILVRM`/`LDIRVM`/`SETVRAM`, sistema de losetas
`MAPEAR_LOSETA_A_GRAFICO`/`ACTUALIZAR_VRAM_FRAME`) y `madmix_scr_body.asm`
(`DIBUJAR_PORTADA` con su descompresion de color, `APLICAR_COLOR_PANTALLA`/
`OBTENER_COLOR_VDP`).

**Verificacion expresa del punto central del manual** (la hipotesis
"hereda el funcionamiento del Spectrum" que motivo la idea): grep de
`SPRT`/menciones de tabla de atributos o registros 5/6 del VDP
(sprites hardware) en todo `src/*.asm` -- 0 coincidencias. Confirma que
el motor de actores nunca toca el plano de sprites hardware del VDP:
compone cada personaje con mascaras AND/OR + desplazamiento sub-pixel
bit a bit directamente sobre la tabla de patrones de `SCREEN 2`, el
mismo algoritmo de blitting que usaria un juego de Spectrum (que no
tiene sprites hardware). Documentado tambien un hallazgo ya conocido
pero no explicado antes en un solo sitio: `CALCULAR_DIRECCION_MASCARA_ACTOR`
reutiliza un subtramo de `TABLA_RLE_MARCO_CARAMELO` (la tabla RLE del
marco de caramelo del HUD) como mascaras de recorte de actor -- doble
proposito de la misma tabla, economia de memoria tipica de un MSX1 de
64KB (ver FINDINGS.md, "Zona 0xDC00", entrada mucho mas antigua).

**Verificado**: grep final sobre el manual de las ~42 etiquetas citadas
contra `madmix1_body.asm`/`madmix_scr_body.asm`: todas existen tal cual
en el codigo actual, 0 inventadas. No es un cambio de codigo (solo
documentacion nueva), no aplica recompilacion.



### Nuevo manual: `manuales/manual_niveles.md` (formato de los 15 niveles, registro de 20 bytes, carga y fin de nivel)

A peticion del usuario, cuarto manual de la serie -- el candidato "mas
practico" que yo mismo propuse. Releido el codigo fuente real de
`madmix_scr_body.asm` (`CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL`/
`INICIALIZAR_PARCIAL_ITEMS_NIVEL`, el registro de nivel completo de 20
bytes campo a campo, la cabecera de `TABLA_NIVELES` con el registro 0
muerto y los 3 ficheros de cabecera compartida, `GESTIONAR_CICLO_NIVELES`)
y de `madmix1_body.asm` (`VERIFICAR_FIN_NIVEL`).

De paso, corregidos 3 nombres antiguos que quedaban sueltos en el
docstring de `tools/mmlvl_tool.py` (no se habian actualizado en la
ronda de renombrado que les dio nombre real): `LEVEL_LOADER` ->
`CARGAR_NIVEL`, `LEVEL_TABLE` -> `TABLA_NIVELES`, `MAP_COORD_TO_ADDR`
-> `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`/`MAPEAR_COORDENADA_A_DIRECCION`.
Verificado que el script sigue siendo Python valido tras el cambio
(`py -m py_compile`).

Contenido nuevo, no solo reorganizacion: documenta por primera vez en
un solo sitio la alternancia de sustitucion del comodin `$3C` segun
`CONTADOR_VUELTAS_NIVELES` (nunca se sustituye en la primera vuelta al
ciclo de 15 niveles; en vueltas posteriores, alterna) y deja constancia
expresa de que el "nivel oculto" (15) es alcanzable en partida normal
sin ningun truco, completando el 14 -- `VERIFICAR_FIN_NIVEL` no le da
ningun trato especial.

**Verificado**: grep final sobre el manual de las 35 etiquetas citadas
(registro de nivel, cargador, tablas) contra `madmix_scr_body.asm`/
`madmix1_body.asm`: todas existen tal cual en el codigo actual, 0
inventadas. Cambio de codigo minimo (3 nombres en un docstring,
verificado con py_compile), no aplica recompilacion de sjasmplus.



### Confirmado por datos reales: el punto de referencia del registro de nivel es siempre la casa de los fantasmas

A raiz de una pregunta directa del usuario ("en todos los niveles los
enemigos salen todos siempre desde la casa de los fantasmas?"),
verificado cruzando `REGISTRO_NIVEL_FILA_COLUMNA` (offset 13-14 del
registro, el punto donde `INICIALIZAR_ITEMS_NIVEL` coloca las 3 tablas
de item) contra el cuerpo real de cada nivel. El catalogo de losetas
tiene una estructura dedicada de 3 losetas
`puerta_fantasmas_inicio_izquierdo`/`linea_electrica_puerta_fantasmas_a`/
`puerta_fantasmas_inicio_derecho` (`$50`/`$38`/`$51`) que marca
visualmente la casa en el mapa -- la loseta central (`$38`, tipo 8 en
`TABLA_MANEJADORES_LOSETA`) es de las pocas NO transitables por estos
items (ver `manual_motor_colision_ia.md` §5).

**Nivel 1** (`body_l01.bin`): la puerta aparece en el cuerpo en la
columna 12 (fila de cuerpo 9, columnas 11-13, centro 12).
`REGISTRO_NIVEL_FILA_COLUMNA` = `$30,$34` = columna cruda 48/4=12
(EXACTA), fila cruda 52/4=13 -- un desfase de +1 fila respecto a la
puerta real (fila de buffer completo 12), coherente con que los items
aparecen justo debajo de la puerta (la loseta central esta bloqueada).

**Nivel 2** (`body_l2.bin`): la puerta aparece en columna 16 (fila de
cuerpo 11, columnas 15-17, centro 16). `REGISTRO_NIVEL_FILA_COLUMNA` =
`$40,$3C` = columna cruda 64/4=16 (EXACTA), mismo desfase de +1 fila.

Mismo patron exacto en ambos niveles pese a tener dimensiones y
valores de referencia completamente distintos -- confirma con
evidencia de datos, no solo por el mecanismo del codigo, que el diseño
original coloca deliberadamente el punto de referencia de cada nivel
en su propia casa de fantasmas. Documentado en `manual_niveles.md`
§5.1 (no verificado exhaustivamente en los 15 niveles, pero el patron
es sistemico y no hay razon para esperar una excepcion).

**Aparte**: corregido `LEVEL_LOADER` (nombre antiguo de `CARGAR_NIVEL`)
en la plantilla `WARNING_BANNER`/`FLAT_BANNER` de `tools/mmlvl_tool.py`
y, para que el arreglo sea real y no solo de cara a futuras
regeneraciones, en los 18 ficheros `.txt` de `data/niveles/` que ya
tenian el aviso grabado con el nombre viejo.

**Verificado**: `py -m py_compile` sobre `mmlvl_tool.py` sin errores;
`roundtrip-all` de los 18 ficheros de nivel tras el cambio: 18/18
identicos (cambio de solo un comentario, 0 bytes de datos afectados).

## CORREGIDO: el formato real de los 64 sprites de personajes es 24×24 con 2 planos entrelazados (máscara+patrón), NO 24×48 de una sola imagen

El milestone que resolvió `PTR_TABLA_SPRITES` (más arriba, "MILESTONE
GRANDE: los 64 SPRITES DE PERSONAJES identificados y transcritos")
dejó documentado que cada entrada de 144 bytes se reagrupaba en 48
filas de 24 px de ancho, formato que el usuario identificó a simple
vista sobre `ptrtable_sprites.html` en su momento. Esa lectura
producía sprites reconocibles pero **con rayas horizontales
blancas/negras de fondo y aspecto alargado** -- fue el propio usuario
quien, viendo el catálogo ya publicado (`recursos/ptrtable_sprites.html`
y el mosaico de actores del póster), notó ese defecto visual y
preguntó si en realidad los datos de dos patrones se estaban
mezclando, ya que en la versión de ZX Spectrum del juego los sprites
son de 24×24 con dos patrones.

**Comprobación empírica** (antes de tocar ningún fichero): se
renderizaron por separado, para varios `.spr` reales
(`27_fantasma_der_1.spr`, `00_pm_vuln_der_cerrada.spr`), tres
hipótesis de reagrupado de los 144 bytes:

1. 48 filas de 3 bytes seguidas (la lectura antigua) -- rayas de
   fondo en todas las filas, aspecto alargado. Confirma el defecto
   que reportó el usuario.
2. Dos bloques de 24 filas (bytes 0-71 y 72-143 como dos imágenes
   24×24 apiladas) -- **sigue con rayas** en ambas mitades. Descarta
   esta hipótesis.
3. Filas entrelazadas par/impar (fila real 0 = bytes 0-2, fila 1 =
   bytes 3-5, fila 2 = bytes 6-8, ...) -- **sin rayas, dos imágenes
   24×24 limpias y reconocibles**: la fantasma sale perfecta en ambos
   planos, igual el comecocos (círculo con ojo y boca).

Es decir: cada una de las 24 filas reales del sprite ocupa **6 bytes
consecutivos** (3 de un plano + 3 del otro), no 3 bytes sueltos
repetidos 48 veces como se asumió. Encaja exacto con el algoritmo de
blitting que ya estaba documentado en `manual_subsistema_grafico.md`
§4 desde antes de este hallazgo: "máscara AND (conserva el fondo
donde el sprite es transparente) seguida de OR (aplica el patrón del
sprite)" -- un mask+bitmap clásico necesita dos planos del mismo
tamaño, uno por operación. También encaja con lo que ya se sabía y no
se terminaba de explicar: `JTS2_XOR_TRANSFORM` lee 3 bytes, 48 veces
seguidas, con auto-modificación -- son 24 pares [máscara, patrón], no
48 filas de una imagen única.

De los dos planos, el que produce el aspecto "normal" de cada
personaje (cuerpo claro con detalles oscuros, ej. el comecocos como
círculo blanco con ojo/boca oscuros) es el que se etiqueta aquí como
**patrón/tinta** (offset +3 de cada grupo de 6 bytes); el otro, con
aspecto mayormente sólido y los mismos huecos en negativo, se etiqueta
como **máscara** (offset +0). La asignación mask=primeros 3 bytes /
patrón=siguientes 3 bytes es la interpretación más coherente con el
algoritmo AND-luego-OR ya documentado, pero el propio código Z80 que
consume esta tabla (qué rutina exacta de `MOTOR_ACTORES` lee cada
plano) sigue sin localizarse línea a línea -- igual que ya constaba
sin resolver en el milestone original.

**Actualizado**: `recursos/ptrtable_sprites.html` (decodificador y
las 3 vistas, ahora Vista 3 muestra patrón y máscara lado a lado),
`recursos/mmg_poster_dossier.html` (mosaico "Catálogo real de
actores"), `src/README.md` (tabla de formatos de píxel y árbol de
ficheros), comentario de cabecera en `src/madmix1_body.asm` antes de
`SPR00_PM_VULN_DER_CERRADA`. No afecta a ningún byte de datos ni de
binario compilado -- es una corrección de cómo se INTERPRETA/muestra
el mismo `.spr` ya transcrito al 100%, no de los bytes en sí.

