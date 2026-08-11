# Mad Mix Game — proyecto de reconstrucción (MSX1)

*[Read this in English](README.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

Reconstrucción por ingeniería inversa de **los 3 binarios** del
disco original.

**`main.asm`** es el punto de entrada real para compilar el motor y
la pantalla de carga: unifica `madmix1_body.asm` + `madmix_scr_body.asm`
en una única pasada de ensamblado (comparten un solo espacio de
símbolos), así que todas las llamadas/punteros cruzados entre ambos
usan etiquetas reales en vez de direcciones hex literales — antes se
compilaban por separado, sin enlazador, y cualquier referencia de un
fichero a otro quedaba como hex con el nombre real en un comentario.
Ver `FINDINGS.md` para el detalle completo de esta unificación.

- **`madmix1_body.asm`** → parte de `build/MADMIX1.BIN` (el motor de
  juego). Direcciones ESTATICAS de principio a fin (`ORG $8400`, sin
  reubicación). Se probó reproducir el truco de reubicación de
  `MADMIX0.BIN` con `PHASE $1000`/`DEPHASE`, pero un volcado de
  memoria en vivo (openMSX) demostró que el motor de juego corre
  desde direcciones estáticas, no desde una copia reubicada.
- **`madmix_scr_body.asm`** → parte de `build/disk/MADMIX.SCR`. Pese al
  nombre/extensión original, **no es una imagen de pantalla**: es
  código+datos que en el disco `MADMIX0.BIN` reubica de `0x8800` a
  `0x1000` (`main.asm` aplica `PHASE`/`DEPHASE` sobre este cuerpo al
  generar `MADMIX.SCR`, al revés que con `madmix1_body.asm`).
  Contiene el dibujado de la portada, el motor de colisión/movimiento
  (el "bucle principal"), el subsistema de activación de ítems, el
  cargador + tabla de los 15 niveles jugables (el 15º, antes creído
  "oculto sin usar", tiene registro propio y es alcanzable en partida
  normal -- ver más abajo), y la pantalla de menú principal + créditos.
  **Completo al 100%**, salvo 2 bytes ajenos ya documentados.
- **`load_disk/madmix0_body.asm`** → `MADMIX0.BIN` (58 bytes, el
  "relocador"). Exclusivo de la versión de disco (hace el `LDIR` de
  reubicación que la cinta no necesita, ya que la cinta carga directo
  en destino), pero **ya integrado en `main.asm`** (comparte espacio
  de símbolos, usa `PORTADA_INIT`/`START` en vez de `$1000`/`$8400`).
  Tiene DOS puntos de entrada: uno que hace el `LDIR` de reubicación
  de `MADMIX.SCR` (0x8800→0x1000) y llama al dibujado de portada, y
  otro (`0xFA2A`) que salta directo al motor de `MADMIX1.BIN` —
  invocado por un `CALL`/`USR` aparte desde el BASIC orquestador, ya
  que `MADMIX1.BIN` se carga sin `",R"`. **Completo al 100%.**
- **`load_cas/load_bin_body.asm`/`test_bin_body.asm`** → `LOAD.BIN`
  (299 bytes) y `TEST.BIN` (253 bytes), el cargador de la versión de
  **cinta**: `TEST.BIN` detecta slots de RAM, `LOAD.BIN` aplica esa
  configuración y lee de cinta directamente a `$1000`/`$8400` (sin el
  paso de reubicación que sí hace el disco) — ver `FINDINGS.md` para
  el detalle de por qué disco y cinta llegan al mismo sitio por
  caminos distintos. Reconstruidos por desensamblado byte a byte del
  `.cas` de 1988 con `Z80Dasm.exe`, **completos al 100%**, 0
  diferencias.
- **`load_disk/AUTOEXEC.bas`/`MADMIX.bas`** y
  **`load_cas/TOPO.bas`/`MADMIX.bas`** → los cargadores BASIC de cada
  versión. Los de disco están tokenizados (reconstruidos con
  `tools/msxbasic_tool.py`, ver más abajo); los de cinta ya son ASCII
  plano en el `.cas` original, se copian tal cual.
- **`load_cas/logotopo_cm_body.asm`** → `LOGOTOPO.CM` (4254 bytes), el
  logo animado de Topo Soft de la versión de cinta. **COMPLETO**:
  bloque de código (`0x9470-0x9693`, 549 bytes) y datos
  (`0x9694-0xA50D`: `TABLA_PUNTEROS_FORMAS`, 3 tablas de animación,
  `TABLA_DELTA_POSICION`, y `TABLA_FORMAS` con las 15 formas + 1
  bloque huérfano sin referencia) transcritos, verificados byte a
  byte (0 diferencias) y **confirmados visualmente por el técnico**
  (letras T-O-P-O deslizándose, coloreado expandiéndose desde el
  centro, "Soft" rotando, punto de luz recorriéndola, estrella
  parpadeante) — ver `recursos/logotopo_formas.html`,
  `load_cas/LOGOTOPO.CM.txt` y `FINDINGS.md`.

`main.asm` también genera `build/cas/madmix_cas_scr.bin` (el cuerpo
lógico de `MADMIX.SCR`, sin cabecera BLOAD) que, junto con
`build/MADMIX1.BIN`, forma el contenido de la **versión de cinta**
(`.cas`) — ver la sección "Compilar" más abajo para el detalle.

Ver `FINDINGS.md` para el detalle técnico completo de cada
hallazgo. **Los tres ficheros están completos al 100%** y compilan
a **0 diferencias** byte a byte contra los originales, salvo:
4 bytes ya documentados sin relación con el motor (3 en
`0x28ED-0x28F0` y 1 en `0x6500`, ambos dentro de `madmix_scr_body.asm`,
contenido ajeno), y **5 bytes de una desviación deliberada**: el
bug real del contador de bolitas del nivel 13 (`$FC60`→`$FC50`,
2 sitios en `madmix1_body.asm` + 3 en `madmix_scr_body.asm`) está corregido
a propósito, igual que lo arregló la reedición v2.0 (CAS/ROM
homebrew de 2013) — es la **única** corrección intencionada de
todo el proyecto; todo lo demás sigue reproduciendo la v1.0 tal
cual es, bugs incluidos. Ver `FINDINGS.md` para el análisis
completo de la comparación contra la v2.0.

Ver `FLUJO_PROGRAMA.md` para el análisis organizado por **flujo de
ejecución** (arranque, tabla de despacho, bucle principal, cada
subsistema) en vez de por orden cronológico de descubrimiento —
complementa a `FINDINGS.md`. Su compañero visual es
`recursos/flujo_programa.html` (diagrama del flujo + inventario
buscable de las 729 etiquetas de todos los ficheros fuente,
regenerado con `tools/gen_inventory.py` a partir del listado de
sjasmplus). Es un trabajo en marcha: el objetivo final es que cada
rutina tenga nombre propio y explicación clara, como si el código lo
hubiera documentado un programador experto de la época.

Ver `manuales/` para manuales técnicos de referencia, pensados como
material de formación para un programador nuevo (y como preservación
en sí mismos) — a diferencia de `FINDINGS.md` (que documenta CÓMO se
descubrió cada cosa) y `FLUJO_PROGRAMA.md` (organizado por flujo de
ejecución), aquí se documenta CÓMO FUNCIONA cada subsistema ya
entendido, de forma ordenada y sin el proceso de investigación por
medio. Empieza con `manuales/manual_driver_sonido.md` (el driver de
sonido del PSG); se irán añadiendo más según se decida qué otras
partes documentar así.

**Probado en producción**: tanto `src/build/madmix_reconstruido.dsk`
como `src/build/madmix_reconstruido.cas` (ambos generados DESDE CERO
por `tools/gen_disk_and_cas.py`, sin partir de una copia de ningún
original) **cargan y funcionan a la perfección en openMSX** — las
dos versiones, disco y cinta, confirmadas.

## Requisitos

- [SjASMPlus](https://github.com/z00m128/sjasmplus) en el PATH —
  compila `src/main.asm` (motor, pantalla, cargadores de disco/cinta).
- Python 3 (`py` en Windows) — necesario para generar los entregables
  finales (`tools/gen_disk_and_cas.py` y todo lo que orquesta:
  `gen_dsk_file.py`, `gen_cas_bin.py`, `gen_cas_file.py`), y para el
  resto de herramientas de `tools/` (sonido, niveles, BASIC
  tokenizado). Sin dependencias externas (todo con la librería
  estándar) — **no hace falta `mtools`**: el `.dsk` se construye la
  estructura FAT12 desde cero en Python (ver `tools/gen_dsk_file.py`),
  no se inyecta nada con herramientas de terceros.
- [openMSX](https://openmsx.org/) para probarlo (opcional, solo para
  ejecutar el resultado).

## Estructura

`tools/`, `manuales/`, `recursos/` y `dump_openmsx/` viven en la RAÍZ
del repositorio (hermanas de `src/`, no dentro de él) — una única
copia de cada una para todo el proyecto:

```
madmixgame/
├── tools/                          ← todas invocables como `py tools/nombre.py ...` desde la raíz
│   ├── build_all.py                ← COMPILA TODO (sjasmplus src/main.asm, con el cwd y las carpetas build/disk/ y build/cas/ correctas) -- primer paso de "un solo comando" para regenerar el proyecto
│   ├── gen_disk_and_cas.py         ← segundo paso: genera los 2 ENTREGABLES FINALES, src/build/madmix_reconstruido.dsk y src/build/madmix_reconstruido.cas, a partir de lo que compiló build_all.py (delega en gen_dsk_file.py + gen_cas_bin.py + gen_cas_file.py)
│   ├── gen_dsk_file.py             ← construye el .dsk DESDE CERO (boot sector, 2 tablas FAT12, directorio raíz, área de datos -- sin partir de una copia del original ni parchearla), ver FINDINGS.md para el formato completo -- invocado por gen_disk_and_cas.py
│   ├── mmsnd_tool.py               ← descompilador/compilador del bytecode de sonido (disasm/asm/roundtrip/roundtrip-all, funciona igual sobre `.snd` y `.spt` -- mismo bytecode, ver FINDINGS.md)
│   ├── mmsnd_render.py             ← renderiza un .snd a WAV (emula PSG + interprete del bytecode) -- reconstrucción razonada, no emulación certificada, ver aviso en FINDINGS.md
│   ├── mmlvl_tool.py               ← descompilador/compilador de las rejillas de losetas de nivel (disasm/asm/roundtrip/roundtrip-all/check-bolitas, ver FINDINGS.md)
│   ├── gen_cas_bin.py              ← concatena madmix_cas_scr.bin + MADMIX1.BIN en src/build/cas/madmix_cas.bin (ingrediente intermedio, sin bloques .cas reales) -- invocado por gen_disk_and_cas.py
│   ├── gen_cas_file.py             ← empaqueta TODOS los ingredientes de load_cas/ y build/cas/ en src/build/madmix_reconstruido.cas, un .cas REAL (sync/nombre/cabecera) -- verificado byte a byte contra el .cas de 1988, solo 9 diferencias ya conocidas, ver FINDINGS.md -- invocado por gen_disk_and_cas.py
│   ├── msxbasic_tool.py            ← detok/tok/roundtrip de BASIC tokenizado MSX (AUTOEXEC.BAS/MADMIX.BAS del disco). Tabla de tokens PARCIAL -- solo los verificados empiricamente (BLOAD/RUN/DEF/USR/=/constante hex/enteros compactos); cualquier otro byte se representa como escape {$XX}, ver FINDINGS.md
│   ├── gen_inventory.py            ← regenera el inventario de recursos/flujo_programa.html (729 etiquetas, clasificadas función/interna/dato/sin ref.) a partir de src/build/main.lst -- ejecutar tras cualquier cambio de etiquetas en el codigo fuente, ver FINDINGS.md
│   └── gen_flow_diagram.py         ← regenera recursos/flujo_detallado.html (grafo Mermaid.js de llamadas reales entre las etiquetas "función", coloreado por subsistema) a partir de src/build/main.lst -- ejecutar tras cualquier cambio de etiquetas/llamadas, ver FINDINGS.md
├── recursos/                       ← visores HTML autocontenidos (ver sección "Visores HTML" más abajo)
├── manuales/                       ← manuales técnicos de referencia (formación + preservación), ver manuales/README.md
│   └── manual_driver_sonido.md     ← cómo funciona el driver de sonido del PSG (arquitectura, bytecode, tablas, $6128, herramientas)
├── dump_openmsx/                   ← volcados de RAM/VRAM reales y renders PNG usados para verificar hallazgos (marco de caramelo, sprites, niveles 13/14, etc.)
└── src/
    ├── main.asm                        ← punto de entrada real: UNICO punto de compilacion para disco y cinta (genera MADMIX1.BIN, MADMIX.SCR, madmix_cas_scr.bin, MADMIX0.BIN, TEST.BIN, LOAD.BIN, LOGOTOPO.CM)
    ├── madmix1_body.asm                ← cuerpo del motor (parte de MADMIX1.BIN) -- ya no compilable por separado
    ├── madmix_scr_body.asm             ← cuerpo de portada + bucle principal + niveles (parte de MADMIX.SCR) -- ya no compilable por separado
    ├── load_disk/                      ← fuentes exclusivas de la version de DISCO
    │   ├── madmix0_body.asm            ← cuerpo de MADMIX0.BIN (relocador, 58 bytes) -- ya no compilable por separado
    │   ├── AUTOEXEC.bas                ← listado editable (detokenizado con tools/msxbasic_tool.py) de AUTOEXEC.BAS
    │   ├── MADMIX.bas                  ← listado editable (detokenizado) de MADMIX.BAS -- cargador real, hace los BLOAD
    │   ├── boot_sector.bin/.txt        ← sector de arranque MSX-DOS estandar (720KB), NO especifico del juego -- boilerplate de la herramienta de formateo, preservado verbatim para tools/gen_dsk_file.py
    │   └── MADMIX_dup.bin/.txt         ← 6º fichero del disco original ("MADMIX" sin extension, casi identico a MADMIX.BAS, NO forma parte del arranque real) -- copia verbatim SIN ANALIZAR, ver .txt
    ├── load_cas/                       ← fuentes exclusivas de la version de CINTA (.cas)
    │   ├── load_bin_body.asm           ← cuerpo de LOAD.BIN (orquestador de carga, 299 bytes) -- ya no compilable por separado
    │   ├── test_bin_body.asm           ← cuerpo de TEST.BIN (deteccion de RAM/slots, 253 bytes) -- ya no compilable por separado
    │   ├── TOPO.bas                    ← listado tal cual (ya ASCII plano en el .cas) -- autoarranca la cinta, carga el logo
    │   ├── MADMIX.bas                  ← listado tal cual -- carga LOAD.BIN/TEST.BIN y los invoca
    │   ├── LOGOTOPO.CM.bin             ← el logo de Topo Soft, copia binaria de referencia (ver LOGOTOPO.CM.txt)
    │   ├── logotopo_cm_body.asm        ← cuerpo de LOGOTOPO.CM (4254 bytes) -- COMPLETO, ver FINDINGS.md
    │   └── LOGOTOPO.CM.txt             ← nota explicando el estado/historia de LOGOTOPO.CM
    ├── data/
    │   ├── tiles/                      ← las 91 losetas del laberinto, 1 fichero .til por loseta (32 bytes, formato 16x16)
    │   ├── sprites/                    ← los 64 sprites de personajes, 1 fichero .spr por sprite (144 bytes, formato 24x24 con 2 planos entrelazados: máscara+patrón, 6 bytes/fila x 24 filas)
    │   ├── fonts/                      ← fuentes de texto (extensión .fnt), un único fichero por fuente completa (la posición de cada glifo se calcula por fórmula, exige un bloque contiguo):
    │   │   └── fuente_caracteres.fnt   ← fuente de texto (59 glifos de 8 bytes, códigos $21-$5B)
    │   ├── img/                        ← el resto de gráficos que no son loseta, sprite ni fuente (extensión .img):
    │   │   ├── portada_paleta.img      ← tabla de 16 valores para descomprimir el color de la portada
    │   │   ├── portada_patron.img      ← bitmap de la portada (6144 bytes, sin comprimir)
    │   │   ├── portada_color.img       ← color de la portada, comprimido a nibble (768 bytes)
    │   │   ├── marco_caramelo_forma.img ← forma del marco de caramelo (tabla RLE, 1740 bytes)
    │   │   ├── marco_caramelo_color.img ← color real del marco de caramelo (768 bytes)
    │   │   └── icono_vida.img          ← icono de vida extra del HUD (16x16, 32 bytes, orden de bytes tile-major, no entrelazado como .til)
    │   ├── demos/                      ← los 10 guiones de reproducción automática del modo DEMO, 1 fichero .dem por guion (pares [duración en fotogramas, dirección simulada]; solo 4 de los 10 están conectados a un nivel real, ver FINDINGS.md)
    │   ├── sound/                      ← scripts del driver de sonido PSG, bytecode propio de Topo Soft ya DESCIFRADO (ver FINDINGS.md, "los 15 comandos del bytecode del driver de sonido"). Organizada en dos subcarpetas por tipo de fichero (ver FINDINGS.md, "organización de data/sound/ en snd/ y spt/"). Cada `.snd`/`.spt` (binario, el que se compila con INCBIN) tiene un `.txt` gemelo (formato de texto propio, un mnemónico por línea — ver `tools/mmsnd_tool.py`) que es el que se edita a mano:
    │   │   ├── snd/                     ← los 16 scripts reales de música/evento
    │   │   │   ├── 00_script_cdcb.snd/.txt      ← música, canal 0 (52 bytes)
    │   │   │   ├── 01_script_cdff.snd/.txt      ← música, canal 1 (13 bytes)
    │   │   │   ├── 02_boot_ch2_ce0c.snd/.txt    ← música, canal 2 (78 bytes)
    │   │   │   └── 03_evt09_....snd/.txt a 15_evt03_....snd/.txt  ← 13 efectos de sonido individuales, uno por evento de `$6128` (antes tratados como un solo bloque de 383 bytes junto al canal 2 — separados esta sesión, cada uno con su índice de evento y candidato del catálogo de sonidos en el nombre/comentario)
    │   │   ├── spt/                     ← los 13 subpatrones compartidos ($CB9C-$CDCB, llamados via `CALL_SUBPATTERN` desde los scripts de música), extensión `.spt` (mismo bytecode que `.snd`, `mmsnd_tool.py` los trata sin ningún cambio — solo se distinguen para no mezclarlos con los 16 scripts reales) — antes `DB` inline en `madmix1_body.asm`, consolidados a fichero propio esta sesión, ver FINDINGS.md. Nombrados por índice de entrada en `TABLA_SUBPATRONES_PSG` (00-12), no por orden de memoria (la entrada 12, `$CBB0`, cae en memoria entre las entradas 0 y 1): `00_subpatron00_cb9c.spt/.txt` .. `12_subpatron12_cbb0.spt/.txt`
    │   │   └── _engine_tables.bin      ← copia de trabajo de `$C8DE-$CDCB` completo (tono, instrumentos, formas de envolvente Y los 13 subpatrones) para que `mmsnd_render.py` tenga un único bloque de memoria simulada donde resolver `CALL_SUBPATTERN` — sigue siendo solo una instantánea de los bytes compilados, no una fuente editable; la tabla de tono/instrumentos/envolvente sigue viviendo como `DB` inline en `madmix1_body.asm`, los subpatrones vienen de sus `.spt` propios (INCBIN) en `spt/`, pero los bytes finales son idénticos en ambos casos, así que esta copia no necesitó regenerarse
    │   └── niveles/                    ← cuerpos/cabeceras crudos de cada nivel (13 cuerpos + 3 cabeceras, incluye el nivel 15 -- antes creído "oculto/sin usar", confirmado real y jugable en partida normal, ver manual_niveles.md y FINDINGS.md). Rejillas de losetas ya DESCIFRADAS (índice 0-90 = catálogo real de `data/tiles/*.til`, bit 7 = flag sin confirmar en tiempo de ejecución). Cada `.bin` (el que se compila con INCBIN) tiene un `.txt` gemelo (formato de texto propio, un byte hex por celda, una fila por línea — ver `tools/mmlvl_tool.py`) que es el que se edita a mano, igual que el `.snd`/`.txt` del sonido:
    │       ├── body_l13.bin/.txt       ← cuerpo COMPLETO del nivel 13 (672 bytes = 21×32, rejilla completa). A DIFERENCIA del resto de este directorio, este fichero y `body_l14.bin` compilan dentro de MADMIX1.BIN (INCBIN en madmix1_body.asm), no en MADMIX.SCR — RESUELTO: es el antiguo `maze_data.bin` partido y luego reunificado, ver FINDINGS.md "RESUELTO EL PROPÓSITO DE maze_data.bin". Antes partido en `body_l13_head_cfa4.bin` (92B; antes `RM_TABLE_CFA4`/`BODY_L13_HEAD_CFA4`) + `body_l13_maze.bin` (580B) — unificados: los primeros 92 bytes NUNCA fueron dato de sonido (etiqueta antigua descartada), decodifican a una sala de laberinto coherente, misma factura que el resto de niveles reales
    │       └── body_l14.bin/.txt       ← cuerpo COMPLETO del nivel 14 (736 bytes = 23×32, rejilla completa). Antes partido en `body_l14_maze.bin` (700B) + `body_l14_tail_demo1.bin`/`DEMO_SCRIPT_NIVEL1` (36B, antes creído el arranque de un guion de demo) — unificado tras confirmar que LEVELCYCLE_TABLE SIEMPRE apuntó a `$D524`, nunca a `$D500`, así que esos 36 bytes nunca fueron guion de demo: siempre fueron cola del cuerpo del nivel 14, mismo tipo de error que `body_l13.bin`, ver FINDINGS.md

> ⚠️ **AVISO — mismo límite que el sonido**: cada `.bin` de `data/niveles/`
> se compila con `INCBIN` a una dirección FIJA. Puedes cambiar el
> VALOR de cualquier celda (qué loseta va ahí) sin ningún problema.
> **Cambiar el número de filas o columnas de la rejilla, o el número
> de bytes de un fragmento plano, NO es seguro**: desplazaría de
> dirección todo lo que va detrás en `madmix_scr_body.asm`/`madmix1_body.asm`.
> `tools/mmlvl_tool.py asm` rechaza con error cualquier `.txt` que no
> declare las mismas dimensiones que el original.

**`LEVEL_TABLE`** (los 15 registros de nivel, antes `niveles_tabla.bin`)
ya NO es un `.bin` aparte: se reescribió como tabla de datos nativa
directamente en `madmix_scr_body.asm` (`DW`/`DB`), con los punteros de
cuerpo/cabecera como etiquetas reales (`BODY_L01`, `HEADER_50BC`,
etc.) en vez de hex suelto — el propio ensamblador resuelve la
dirección correcta, y cambiar qué cuerpo/cabecera usa un nivel es
tan simple como cambiar una etiqueta. Excepción: los niveles 13 y 14
apuntan a direcciones dentro de `MADMIX1.BIN` (otro binario, sin
enlazar con este), así que esos dos punteros concretos siguen en hex
literal, con un comentario explicando a qué etiqueta equivalen allí.
Ver `FINDINGS.md` para el detalle campo a campo de los 20 bytes del
registro.
    ├── build/                      ← aquí caen los binarios compilados: build/madmix_reconstruido.dsk y build/madmix_reconstruido.cas son los ENTREGABLES FINALES (en la raíz); build/disk/ y build/cas/ guardan los binarios "ingrediente" de cada versión, autocontenidos (y build/sound_preview/*.wav, los 16 sonidos ya renderizados)
    ├── FINDINGS.md                 ← diario de descubrimientos (cronológico)
    ├── FLUJO_PROGRAMA.md           ← análisis por flujo de ejecución (arranque, despacho, subsistemas) -- complementa a FINDINGS.md
    └── README.md
```

**Nota sobre `data/tiles/`, `data/sprites/`, `data/fonts/`, `data/img/`, `data/demos/` y `data/sound/`**: cada objeto (loseta, sprite, imagen, guion de demo o script de sonido) vive en su propio fichero — así se pueden editar/regenerar desde fuera del `.asm` sin tocar código. El `.asm` los carga con `INCBIN`, uno detrás de otro en el orden exacto en que aparecen en el binario original, para que la disposición en memoria siga siendo byte a byte idéntica. Excepción: las **fuentes** (`data/fonts/`) van en un único fichero por fuente completa, no un fichero por carácter — el código calcula la dirección de cada glifo por fórmula (`base + código×8`), lo que exige que estén contiguos como una sola tabla, y además es como se editan de verdad las fuentes bitmap (el juego completo de caracteres a la vez). Los **scripts de sonido** (`data/sound/`) usan la extensión `.snd` para el binario (el que compila el `.asm` con `INCBIN`, byte a byte idéntico al original) y `.txt` para su gemelo en texto plano editable — el bytecode de los 15 comandos ya está descifrado (ver `FINDINGS.md`), así que el `.txt` es la forma real de editarlos: se modifica el `.txt` y se regenera el `.snd` con `py tools/mmsnd_tool.py asm fichero.txt fichero.snd` antes de recompilar el juego. Los **13 subpatrones compartidos** (llamados via `CALL_SUBPATTERN` desde los scripts de música) usan el MISMO bytecode y la MISMA herramienta, pero con extensión `.spt` para no mezclarlos con los 16 scripts reales de evento/música. Las tablas de tono/instrumento/envolvente del driver (`TABLA_NOTAS_PSG`, `TABLA_INSTRUMENTOS_PSG`, `TABLA_ENVOLVENTES_PSG`) se quedan como `DB` inline — son la "maquinaria" fija del intérprete (registros de tamaño constante, no bytecode), no contenido variable de un script/subpatrón en concreto.

> ⚠️ **AVISO — límite real de qué se puede editar en los `.txt` de sonido**: cada `.snd`/`.spt` se compila con `INCBIN` a una dirección FIJA, calcada del binario original. Cambiar el VALOR de una instrucción que ya existe (otra nota, duración, instrumento...) es 100% seguro. **Añadir o quitar instrucciones, o cambiar la cuenta de un `SET_DURATION_MULTI`, NO lo es**: si cambia el número de bytes total, todo lo que va detrás en `madmix1_body.asm` se desplaza de dirección, y `LEVELCYCLE_RESOURCE_TABLE` (en `madmix_scr_body.asm`, que dispara cada sonido por `$6128`) se queda apuntando a la dirección VIEJA — el juego compilaría sin ningún error pero saltaría a sitios incorrectos en tiempo de ejecución. Para los `.spt` el riesgo es el mismo pero con un impacto mayor: `TABLA_SUBPATRONES_PSG` (`madmix1_body.asm`) apunta a cada uno por dirección real vía etiqueta, así que cambiar el tamaño de UN subpatrón desplaza TODOS los que van detrás en memoria y rompe los punteros de los que ya se habían compilado antes de ese cambio. Esta misma advertencia está repetida al principio de cada `.txt` generado por la herramienta.

### Tamaños en píxeles de cada formato (para verlos/editarlos con YY-CHR, Tilemap Studio, GIMP, etc.)

Todos son monocromo, 1 bit por píxel, MSB primero — el formato
"crudo" más simple que soporta cualquier editor de tiles/CHR. Todos
van en orden lineal fila a fila sin entrelazado, **excepto
`data/sprites/`**, que entrelaza 2 planos (máscara AND + patrón/tinta
OR, ver `recursos/ptrtable_sprites.html` y `manual_subsistema_grafico.md`
§4) fila a fila: 3 bytes de máscara + 3 bytes de patrón por cada una
de las 24 filas reales:

| Carpeta | Extensión | Tamaño en píxeles | Bytes/fila | Bytes por fichero |
|---|---|---|---|---|
| `data/tiles/` | `.til` | 16×16 | 2 | 32 |
| `data/sprites/` | `.spr` | 24×24, 2 planos entrelazados (máscara+patrón) | 6 (3+3) | 144 |
| `data/fonts/` | `.fnt` | 8×8 por glifo (59 glifos seguidos) | 1 | 472 (59×8) |
| `data/img/marco_caramelo_forma.img` | `.img` | — (tabla RLE, no bitmap plano) | — | 1740 |
| `data/img/marco_caramelo_color.img` | `.img` | — (atributos de color VRAM, no bitmap) | — | 768 |
| `data/img/portada_patron.img` | `.img` | 256×192 (pantalla completa) | 32 | 6144 |
| `data/img/portada_color.img` | `.img` | — (color comprimido a nibble, no bitmap plano) | — | 768 |
| `data/img/portada_paleta.img` | `.img` | — (tabla de 16 valores) | — | 16 |
| `data/img/icono_vida.img` | `.img` | 16×16 (2×2 patrones de 8×8, orden tile-major, NO entrelazado como `.til`) | 1 (por patrón de 8×8) | 32 |

Nota: no todos los `.img` son bitmaps planos editables como imagen
directamente — los que dice "no bitmap" están comprimidos o son
tablas de atributos/color, hace falta pasarlos por su transformación
real (ver `FINDINGS.md`) antes de que tengan sentido visual.

## Visores HTML (`recursos/`)

Páginas autocontenidas (sin dependencias externas) que se abren
directo en el navegador:

- **`graficos.html`** — las 91 losetas del laberinto identificadas,
  con área de composición 4×4 para probar encajes.
- **`niveles.html`** — los 15 niveles reales reconstruidos con las
  losetas, a partir de la tabla descubierta en `MADMIX.SCR`. El 15º
  (`0x48BC-0x4AFC`) se documentó primero como "oculto/sin usar" --
  **RESUELTO**: SÍ tiene registro propio en `LEVEL_TABLE` (el
  registro 15, antes mal etiquetado como "20 bytes sin identificar"
  justo despues del registro 14) y SÍ es alcanzable en partida normal
  (`LEVEL_LOADER` no tiene tope propio; el contador de nivel pasa por
  15 antes de resetear a 1 al completar el ciclo, ver `FINDINGS.md`) —
  confirmado visualmente como un laberinto real con forma de
  comecocos, y **probado jugándolo de verdad en openMSX**
  (parcheando una copia del `.dsk` para que el nivel 1 apunte a él):
  se camina con normalidad, confirmando que es contenido real y
  jugable, no ruido (ver `FINDINGS.md` para el detalle del parche y
  los defectos esperables por reutilizar metadatos de otro nivel en
  aquella prueba, hecha antes de encontrar su registro real).
- **`portada.html`** — la pantalla de portada reconstruida desde
  los datos crudos de `MADMIX.SCR`.
- **`mapa_memoria.html`** — mapa completo de la RAM (0x0000-0xFFFF)
  con el origen de cada zona y de qué fichero viene (con llaves
  encima de la barra marcando la posición final/permanente de cada
  uno de los 3 binarios), documento vivo que se amplía según se
  descubre más.
- **`mapa_memoria_logotopo.html`** — misma plantilla visual que
  `mapa_memoria.html` pero con escala propia acotada solo al rango de
  `LOGOTOPO.CM` (0x9470-0xA50D, 4254 bytes, el logo de Topo Soft de la
  versión de cinta). **COMPLETO**: todo el fichero transcrito,
  verificado byte a byte y confirmado visualmente — ver
  `src/load_cas/logotopo_cm_body.asm` y `FINDINGS.md`.
- **`logotopo_formas.html`** — renderizador de las 15 "formas"
  animadas de `LOGOTOPO.CM` (tiles 8x8 monocromos, columnas
  ajustables por tarjeta), cada una con su nombre real confirmado por
  el técnico (letras T/O/P/O de "Topo", 7 fotogramas de "Soft"
  rotando, 4 fotogramas de la estrella).
- **`ptrtable_sprites.html`** — las 64 entradas gráficas de
  `PTR_TABLE_91C3` (`madmix1_body.asm`, dentro del hueco grande
  `0x92E3-0xB940` todavía sin descifrar), renderizadas como mapa de
  bits crudo en 3 vistas distintas, sin ninguna interpretación
  todavía — punto de partida para descifrar el resto del hueco
  gráfico.
- **`flujo_programa.html`** — compañero visual de `FLUJO_PROGRAMA.md`:
  diagrama del flujo grande (arranque → tabla de despacho → bucle
  principal → subsistemas) más el inventario completo y buscable de
  las etiquetas de todos los ficheros fuente (motor, pantalla,
  cargadores de disco y cinta) — regenerado con
  `tools/gen_inventory.py`, que resuelve fichero/línea real a partir
  del listado de sjasmplus (necesario porque algunas direcciones se
  reutilizan a propósito entre ficheros, p.ej. `TEST.BIN`/driver de
  sonido en `$C350`, ver FINDINGS.md). Documento vivo.
- **`flujo_detallado.html`** — grafo de llamadas real (Mermaid.js),
  generado por `tools/gen_flow_diagram.py` a partir de
  `src/build/main.lst`: un nodo por cada etiqueta "función" (destino
  de al menos un `CALL`), coloreado por subsistema (arranque, menú,
  motor, items, HUD, gráficos/VRAM, sonido), con aristas = llamadas
  `CALL` reales entre ellas (punteadas + código de condición si el
  `CALL` es condicional). Alcance deliberado: NO incluye los
  manejadores de tipo de loseta ni el resto de etiquetas "interna"
  (solo alcanzadas por `JP`/`JR`, nunca `CALL`) — ver la nota del
  propio HTML para el detalle exacto de qué se descarta y por qué.
  Documento vivo, regenerar tras renombrados con
  `py tools/gen_flow_diagram.py`.
- **`flujo_secuencial.html`** — variante paso a paso (no grafo) del
  mismo flujo de ejecución que `flujo_detallado.html`, coloreada por
  subsistema (arranque, motor, items, HUD, menú, sonido, gráficos,
  decisión); útil para seguir la secuencia lineal sin la complejidad
  visual de un grafo de nodos.
- **`editor_niveles.html`** — editor visual de las rejillas de losetas
  de `data/niveles/` (13 cuerpos + 3 cabeceras, los 15 niveles reales):
  paleta de las 91 losetas reales (reutiliza el decodificador de
  `graficos.html`), pinta con clic/arrastre, contador de bolitas en
  vivo contra el objetivo real de `LEVEL_TABLE`, y botones para
  abrir/descargar el mismo formato `.txt` que usa `tools/mmlvl_tool.py`
  (autocontenido, sin servidor — el guardado es una descarga de
  fichero, no escritura directa a disco). Las cabeceras son de solo
  lectura (compartidas por varios niveles). Los niveles 13
  (`body_l13.bin`, 21×32) y 14 (`body_l14.bin`, 23×32) son cada uno un
  único fichero, como cualquier otro nivel — ambos estuvieron
  partidos en dos ficheros hasta que se confirmó que esas particiones
  venían de deducciones erróneas de sesiones antiguas (el nivel 13 no
  compartía nada con sonido; los últimos 36 bytes del nivel 14 no eran
  un guion de demo reasignado); unificados y consolidados (ver
  `FINDINGS.md`). El nivel 15 (`body_l15.bin`) es igual de normal:
  tiene registro propio en `LEVEL_TABLE` (el registro 15) y se alcanza
  jugando con normalidad tras completar el 14 — la etiqueta "nivel
  oculto" de análisis previos de este mismo proyecto queda descartada,
  ver `manual_niveles.md` §4 y `FINDINGS.md`. No valida posiciones de
  ítems/enemigos (tablas de coordenadas aparte, fuera de esta primera
  pasada).
- **`mmg_poster_dossier.html`** — póster/dossier visual de una sola
  página con el resumen del proyecto (formato cartel), pensado para
  mostrar el trabajo de un vistazo sin navegar el resto de visores.

Versiones antiguas o descartadas de algunos de estos visores
(renderizados que resultaron erróneos, o contenido que acabó
integrado en otro documento) se conservan sin mantenimiento activo en
`recursos/descartado/`, como referencia histórica.

## Compilar

```
py tools/build_all.py
py tools/gen_disk_and_cas.py
```

El primer script compila TODO el código fuente (equivale a
`sjasmplus src/main.asm`, invocado con el directorio de trabajo
correcto y creando `src/build/disk/`/`src/build/cas/` si hiciera
falta). El segundo toma esos binarios ya compilados y genera los 2
entregables finales: `src/build/madmix_reconstruido.dsk` y
`src/build/madmix_reconstruido.cas`. Ambos verifican sus propias
entradas y avisan con un error claro si falta algo (p.ej. si se salta
el primer paso).

**El `.dsk` se construye DESDE CERO** (`tools/gen_dsk_file.py`): boot
sector, las 2 tablas FAT12, el directorio raíz y el área de datos se
ensamblan por completo en el propio script -- no parte de una copia
del `.dsk` original para parchearla encima (como sí se hacía antes).
Las únicas 2 piezas que no se derivan de nada (boot sector estándar
MSX-DOS y un 6º fichero del disco sin relación con el arranque real)
se preservan como recursos verbatim en `load_disk/` -- ver el propio
`gen_dsk_file.py` y `FINDINGS.md` para el detalle completo del
formato FAT12 real.

El relleno de cola de cada cluster (la parte de cada fichero que no
llena su último cluster completo) se rellena con CEROS, no con el
contenido real del disco original: el disquete original es un soporte
REUTILIZADO y ese relleno contiene restos legibles de un uso previo
sin relación con el juego (ver `FINDINGS.md`) — no vale la pena
preservar "basura" ajena solo por fidelidad byte a byte, ya que
MSX-DOS nunca lee esa zona (solo usa el tamaño declarado en el
directorio). Por eso la comparación byte a byte contra el `.dsk`
original ya NO da solo 9 diferencias, sino esas 9 más el tamaño del
relleno de cola de cada fichero — todas dentro de zonas sin ningún
efecto funcional.

Estos dos scripts son el equivalente a "compilar todo el proyecto de
un tirón" — el resto de esta sección detalla qué hace cada pieza por
dentro, por si hace falta ejecutar algo suelto (p.ej. solo `sjasmplus
src/main.asm` sin regenerar `.dsk`/`.cas`, o solo `tools/gen_cas_file.py`
tras cambiar únicamente algo de `load_cas/`).

```
sjasmplus src/main.asm
```

Único punto de compilación de los binarios crudos, para disco y
cinta a la vez (lo que hace `tools/build_all.py` por dentro). Genera:

- `build/disk/MADMIX1.BIN` y `build/cas/MADMIX1.BIN` — el motor del
  juego, dos copias IDÉNTICAS (mismo `SAVEBIN` llamado dos veces): es
  exactamente el mismo binario en ambas ediciones (verificado, ver
  `FINDINGS.md`), pero cada carpeta se mantiene AUTOCONTENIDA — todo
  lo necesario para generar su `.dsk`/`.cas` vive dentro de ella.
- `build/disk/MADMIX.SCR`, `build/disk/MADMIX0.BIN` — específicos de
  la versión de **disco** (`MADMIX.SCR` con cabecera BLOAD física en
  `$8800`; `MADMIX0.BIN` el "relocador", `load_disk/madmix0_body.asm`).
- `build/cas/madmix_cas_scr.bin` (el cuerpo lógico de `MADMIX.SCR`,
  sin cabecera BLOAD), `build/cas/TEST.BIN`, `build/cas/LOAD.BIN` —
  específicos de la versión de **cinta**
  (`load_cas/test_bin_body.asm`/`load_bin_body.asm`).

**`madmix1_body.asm`/`madmix_scr_body.asm`/`load_disk/madmix0_body.asm`/
`load_cas/*_body.asm` YA NO son compilables por separado**: todos
comparten un único espacio de símbolos dentro de `main.asm` (así las
llamadas cruzadas usan etiquetas reales en vez de hex), así que cada
uno necesita las etiquetas de los demás para resolver — compilarlos a
solas fallaría con símbolos indefinidos. `main.asm` es el único punto
de entrada real.

Detalle técnico no trivial (ver `FINDINGS.md` para el análisis
completo): `TEST.BIN` vive en `$C350`, la misma dirección física que
usa el driver de sonido de `madmix1_body.asm` (reutilización
transitoria de RAM, igual que en la máquina real) — por eso el bloque
de `MADMIX1.BIN` va ANTES que el de `TEST.BIN` en `main.asm`: `SAVEBIN`
captura una foto del buffer en el momento de su propia llamada, así
que el orden de los bloques importa.

### Versión de cinta (`.cas`)

```
py tools/gen_cas_bin.py
```

Genera `build/madmix_cas.bin` (en la RAÍZ de `build/`, el entregable
final — `build/cas/` solo guarda los binarios "ingrediente"):
`build/cas/madmix_cas_scr.bin` (destino real `$1000`) seguido, SIN
relleno, de `build/cas/MADMIX1.BIN` (destino real `$8400`) —
verificado que así concatena sus bloques el `.cas` real (tanto el
original de 1988 como la reedición v2.0 de 2013): cada bloque de
cinta lleva su propia dirección de destino en la cabecera, así que no
hace falta ningún hueco de memoria entre ellos en el propio fichero.
Se escribe también `build/madmix_cas.bin.txt`, un manifiesto corto
con los 2 offsets/destinos/longitudes.

```
py tools/gen_cas_file.py
```

Genera `build/madmix_reconstruido.cas` — un `.cas` REAL y completo
(bloques de sincronismo, nombre y cabecera de verdad, formato
estándar de emulador MSX), empaquetando `load_cas/TOPO.bas`,
`load_cas/MADMIX.bas`, y `build/cas/LOGOTOPO.CM`/`LOAD.BIN`/`TEST.BIN`/
`madmix_cas_scr.bin`/`MADMIX1.BIN` — los 5 binarios de cinta salen
YA de nuestra propia fuente compilada por `main.asm` (`LOGOTOPO.CM`
ya no se copia verbatim del `.bin` de referencia, ver
`load_cas/logotopo_cm_body.asm`). **Verificado byte a byte contra
el `.cas` original de 1988: solo 9 diferencias, las 3 ya
conocidas** (el fix deliberado `$FC60→$FC50`, la diferencia
preexistente ajena en `$28ED-$28EF`, y el byte suelto final de
`MADMIX1.BIN` — exactamente las mismas categorías que en la
comparación del `.dsk`, ver `FINDINGS.md`).

### BASIC del disco (tokenizado)

```
py tools/msxbasic_tool.py tok src/load_disk/AUTOEXEC.bas src/build/disk/AUTOEXEC.BAS
py tools/msxbasic_tool.py tok src/load_disk/MADMIX.bas src/build/disk/MADMIX.BAS
py tools/msxbasic_tool.py roundtrip src/build/disk/AUTOEXEC.BAS
```

`load_disk/AUTOEXEC.bas`/`MADMIX.bas` son los listados ya
detokenizados (editables como texto plano); `tok` los vuelve a
tokenizar para producir el `.BAS`/`.BIN` real que espera el disco.
Tabla de tokens PARCIAL (ver `tools/msxbasic_tool.py`) — solo cubre
lo verificado empíricamente; cualquier byte no identificado se
preserva exacto vía escape `{$XX}` en el listado.

## Probarlo (reutilizando el .dsk original)

`py tools/gen_disk_and_cas.py` (ver "Compilar" más arriba) ya genera
`src/build/madmix_reconstruido.dsk` listo para abrir en openMSX —
esto de abajo es el equivalente manual, paso a paso, por si hace
falta inyectar en OTRA copia del disco (no la que usa ese script).
Requiere [mtools](http://www.gnu.org/software/mtools/) — a diferencia
del flujo principal, que no lo necesita para nada.

No hace falta tocar `AUTOEXEC.BAS` ni `MADMIX.BAS` — siguen
funcionando tal cual. Sustituimos los binarios reconstruidos
dentro de una COPIA del disco original:

```
copy Mad_MIX_Game.dsk copia.dsk
mcopy -o src/build/disk/MADMIX1.BIN -i copia.dsk ::MADMIX1.BIN
mcopy -o src/build/disk/MADMIX.SCR -i copia.dsk ::MADMIX.SCR
mcopy -o src/build/disk/MADMIX0.BIN -i copia.dsk ::MADMIX0.BIN
```

Y luego arrancar `copia.dsk` en openMSX como el disco original.

## Pendiente antes de que sean binarios completos

1. ~~Reproducir el reubicado de memoria (`PHASE`/`DEPHASE`)~~ —
   probado e implementado en `madmix1_body.asm`, pero luego DESCARTADO ahí:
   un volcado de memoria en vivo demostró que el motor de
   `MADMIX1.BIN` corre desde direcciones estáticas. **Sí se usa,
   correctamente, en `madmix_scr_body.asm`** — ese es el caso real donde
   aplica (confirmado también en vivo).
2. ~~Rellenar los huecos `DS` de `madmix1_body.asm` con contenido real~~ —
   **HECHO POR COMPLETO: `madmix1_body.asm` ya NO tiene ningún hueco `DS`
   pendiente, 0 diferencias byte a byte de principio a fin
   (`0x8400-0xDDA1`).** La última cola, `0xD500-0xDDA1` (2209 bytes),
   resultó ser: **10 guiones de reproducción automática del modo
   DEMO** (`0xD500-0xD6B6`, 438 bytes, pares `[duración en
   fotogramas, dirección simulada]` terminados en `$FF`) —
   consumidos por `TAIL_LEVELCYCLE_MAIN` vía `LEVELCYCLE_TABLE`, que
   solo referencia 4 de los 10 (niveles 1/2/4/5); los otros 6 son
   guiones reales sin conectar (a diferencia del nivel 15, que en su
   momento también parecía "sin conectar" pero resultó tener registro
   real en `LEVEL_TABLE` — ver más abajo; estos 6 guiones siguen sin
   ningún puntero conocido que los use);
   **¡EL MARCO DE CARAMELO EN SÍ!** (`TABLA_RLE_MARCO_CARAMELO`,
   `0xD6B6-0xDD82`, 1740 bytes) — una tabla RLE cuyas 870
   repeticiones suman exacto 6144 bytes (la tabla de patrones de
   VRAM completa), confirmado renderizándola: rayas rojiblancas,
   esquinas redondeadas y brillo, pixel a pixel igual que la
   reconstrucción de pantalla real (ver punto sobre el marco de
   caramelo más abajo para el detalle). De paso, un subtramo de esta
   misma tabla (desde `$DC00`) resultó tener un SEGUNDO uso — leído
   aleatoriamente como máscaras AND/OR de 16 bits para componer
   sprites (`CALCULAR_DIRECCION_MASCARA_ACTOR`/`COMPONER_ACTORES_EN_BUFFER`) — esto resuelve
   la "Zona 0xDC00" que quedaba como "sin descifrar" en un hallazgo
   de una sesión anterior; y dos fragmentos de código real al final
   (`SLOT_RESTART_DD82`, sin llamador conocido, y
   `CONFIGURAR_Y_LEER_JOYSTICK_PSG`, destino confirmado de un `CALL`
   ya existente en `LEER_JOYSTICK`), más relleno `$FF` y un byte huérfano final
   (`$CD` en `0xDDA0`, fuera del rango real cargado). Ver
   `FINDINGS.md` para el detalle completo. El antiguo "hueco grande"
   (~10.700 bytes, ya resuelto antes de esta cola final) quedó
   totalmente resuelto y documentado en capas: (a) 449 bytes de
   continuación real de `INIT` (`INIT` nunca hace `RET`, entra en el
   BUCLE PRINCIPAL DEL JUEGO); (b) 429 bytes de textos de partida
   nunca vistos (`"FASE 00"`, `"READY?"`, `"ESTAS FRITO"`, aviso de
   vida extra) y la tabla de 64 punteros `PTR_TABLE_91C3`; (c) 600
   bytes de **fuente de caracteres** (`FONT_TABLE_9363`,
   `0x92E3-0x953B`) confirmada mediante la fórmula real de
   `DIBUJAR_TEXTO_INVERTIDO_VRAM` (`glifo = $925B + código*8`) — códigos `$11-$20` son
   ceros reales (control/espacio en blanco), y de `$21` a `$5B` los
   59 glifos reales; (d) **¡LOS SPRITES DE PERSONAJES YA ESTÁN
   IDENTIFICADOS Y TRANSCRITOS!** (`0x953B-0xB93B`, 9216 bytes, 64
   sprites, 0 diferencias byte a byte) — el técnico (jugador
   original) los identificó a simple vista viendo
   `recursos/ptrtable_sprites.html`: comecocos (vulnerable/
   invencible con fases de boca, avión, "obra"/saca-bolas,
   hipopótamo, tanque), fantasma (normal/vulnerable/muerto),
   mariquita, "repugnantoso", la secuencia completa de muerte del
   comecocos y el marcador de puntos por fantasma comido (400/600).
   Dato clave de jugabilidad: **no hay sprites hacia la izquierda**,
   solo derecha/abajo/arriba — se invierte horizontalmente el de la
   derecha en tiempo de ejecución (ver `FINDINGS.md` para el
   catálogo completo y las rutinas de código,
   `DIBUJAR_FILA_DESPLAZADA_DERECHA`/`DIBUJAR_FILA_DESPLAZADA_IZQUIERDA`
   — mecanismo exacto del bit 7 aparcado, requiere trazado en vivo);
   (e) 5 bytes de cola sin identificar
   (`0xB93B-0xB940`: `$00,$FF,$FF,$FF,$FF`) justo antes de
   `TILE_GFX`, que ahora aterriza en su dirección real `0xB940` por
   primera vez. **¡EL "MARCO DE CARAMELO" YA ESTÁ LOCALIZADO Y
   CONFIRMADO VISUALMENTE!** Estaba en la tabla RLE de la cola final
   (`TABLA_RLE_MARCO_CARAMELO`, `0xD6B6-0xDD82`, dentro de este mismo hueco —
   ver punto 2 más abajo): las 870 repeticiones de sus pares
   `(valor,repetición)` suman exacto 6144 bytes (`$1800`, la tabla de
   patrones de VRAM completa de SCREEN2). Expandiendo el RLE y
   renderizando con la tabla de nombres identidad (confirmada en un
   volcado de VRAM real) sale el marco completo y reconocible: rayas
   diagonales rojiblancas, remates redondeados en las 4 esquinas y
   el motivo de brillo — pixel a pixel igual que
   `dump_openmsx/screen_reconstructed.png` (render en
   `dump_openmsx/candy_frame_reconstructed.png`, ver
   `FINDINGS.md`). No es una loseta 16×16 como las de `TILE_GFX` —
   es toda la tabla de patrones de pantalla generada de una vez por
   diseño, y sobrevive solo en los bordes porque el laberinto
   dibujado encima ocupa el centro. **¡Y EL COLOR REAL DEL MARCO
   TAMBIÉN ESTÁ LOCALIZADO!** La rutina que consume el bloque de 768
   bytes de `$60FE` (`TAIL_CREDITS_MAIN` + `TAIL_TILE_LOOKUP`, en
   `madmix_scr_body.asm`, nibble-swap contra `DIRBITS_TABLE` de
   `madmix1_body.asm`, relleno sólido vía `FILVRM`) — que en una sesión
   anterior se había investigado y descartado como "textura/
   sombreado de fondo, no el marco" — resultó ser exactamente eso:
   **el color real (rojo oscuro/gris/blanco) del marco de caramelo**,
   aplicado a la tabla de color de VRAM. Verificado aplicando la
   transformación real a los 768 bytes y comparando contra un volcado
   de VRAM real: coincide exacto, byte a byte (ver `FINDINGS.md`). La
   conclusión anterior estaba equivocada por renderizar los bytes
   como patrón (blanco/negro) en vez de como atributos de color.
   ~~Gestor de recursos (`0xC4A0-0xD000`)~~ —
   **hecho**, 0 diferencias byte a byte en los 2912 bytes
   (verificado compilando el bloque aislado con `ORG $C4A0`, ver
   `FINDINGS.md`): resultó ser el **driver de sonido/música del
   PSG** (AY-3-8910), no un gestor de recursos genérico — encaja
   con el crédito real "MUSIC-A BY: COMILONAS" (ver más abajo, nota
   de ortografía real). Se confirmó que
   `LOAD_RESOURCE_SLOT_EMPTY` está en `0xCF8B`, tal como ya se
   sospechaba. ~~Los 7 huecos pequeños de código sin identificar
   (`JT_SLOT5/6/7/8/9`, 0x8431-0x8EC4)~~ — **hecho**, 0 diferencias
   byte a byte en los ~1.531 bytes reales (el hueco de 0x8431 no
   contaba, era zona de variables en RAM ya a cero). Hallazgos:
   `INSTALL_ISR` (JT_SLOT5, $881B) real, sin el `DI` inicial que
   tenía un stub inventado anterior (eliminado); la `ISR` tenía 3
   bugs reales (faltaba un `PUSH AF`/`POP AF` simétrico, faltaba
   un bloque de lectura de estado del VDP, y terminaba en `RETI`
   en vez de `RET`); `GESTIONAR_FRAME` hacía mucho más de lo que
   el stub decía (llama a `CONTINUAR_CAPTURA_MASCARAS_ACTORES`,
   `RESET_CONTADOR_ACTORES` y una nueva rutina `$8CFF`);
   `JT_SLOT8`/`JT_SLOT9` ($89AD/$8C34) son el
   **scroll por software de la cámara** (arriba/abajo/lateral) más
   el dibujado del contador de vidas; `TILE_TYPE_LOOKUP` y
   `REDRAW_STRIP` tenían stubs que no coincidían con el código
   real; se encontró una **cola de redibujado diferido** (`QUEUE_*`)
   y `JT_SLOT7` ($8D70) resultó ser el **dibujado del marcador de
   puntuación**, con dos textos alternativos curiosos: "BESTIA" (si
   la puntuación llega a 10000) y " DEMO " (en modo demostración);
   `JT_SLOT6` ($8E3C) es la **lectura de teclado/joystick**.
3. ~~Transcribir el motor de colisión/movimiento (`0x2CA0-0x335C`)~~
   — hecho, 0 diferencias byte a byte. ~~Transcribir los cuerpos y
   cabeceras de los 14 niveles (`0x335C-0x511C`)~~ — hecho, 0
   diferencias byte a byte en los 7616 bytes (ver
   `src/data/niveles/`); de paso se descubrió un **15º nivel** en
   `0x48BC-0x4AFC` (`BODY_HIDDEN_48BC`), en aquel momento sin
   registro conocido en `LEVEL_TABLE` — **confirmado
   visualmente** (ver `recursos/niveles.html`, que ya incluye este
   nivel 15): las paredes
   dibujan la silueta de un comecocos bordeada de losetas de
   dirección única. Encaja con que el juego "se supone" que tiene 15
   niveles pero nunca se localizaron los 15 jugando ni en fuentes
   externas. **Actualización posterior**: sí tiene registro real en
   `LEVEL_TABLE` (el registro 15, antes mal etiquetado) y se alcanza
   jugando con normalidad tras completar el nivel 14 — no es un nivel
   "oculto/sin usar", es un nivel normal más; ver `manual_niveles.md`
   §4 y `FINDINGS.md`. ~~Transcribir el subsistema de activación de ítems
   especiales (`0x5478-0x5904`)~~ — hecho, 0 diferencias byte a byte
   en los 1164 bytes. ~~Transcribir `0x511C-0x545F`~~ — hecho, 0
   diferencias byte a byte en los 835 bytes; resultó ser mucho más
   que una tabla de posiciones: ahí vivían `HELPER_5278`/`HELPER_53A2`
   (los dos helpers que faltaban del subsistema de ítems) y
   `R51FE_MAIN`, una tercera rutina de activación llamada desde el
   bucle principal. ~~Transcribir la cola `0x5AD5-0x6500`~~ — hecho,
   0 diferencias byte a byte en los 2603 bytes; resultó ser **la
   pantalla de menú principal del juego** (teclado/joystick/
   redefinir teclas/demo) con código automodificable real, más
   **los créditos originales** — texto real, byte a byte, SIN
   "corregir" la ortografía (ver `FINDINGS.md`): "POGRAMADO BY:
   RAPHAEL GOMEZZZ..", "GRAPHICOS BY : ROBERTO P.ACEBES",
   "MUSIC-A BY: COMILONAS", "TOPOSHOW -1988-". **`madmix_scr_body.asm`
   ya no tiene ningún hueco `DS` pendiente** (salvo 2 bytes ya
   documentados y ajenos a esta tarea: `0x28ED-0x28F0` y el byte
   suelto en `0x6500`). ~~Tablas de texto en hex puro~~ — **hecho**:
   se reescribieron `MAINMENU_TEXT`, `KEYMENU_TEXT_5E03` y
   `TAIL_CREDITS_TEXT` (y `BESTIA_TEXT`/`DEMO_TEXT`/
   `SCORE_DIGIT_BUFFER` en `madmix1_body.asm`) de bytes hex sueltos a
   strings literales (`DB "TEXTO"`) allí donde el original
   probablemente los escribió así — más fiel al objetivo de
   legibilidad humana del proyecto, 0 diferencias byte a byte
   re-verificadas tras el cambio.
4. ~~Descifrar los 6 bytes de metadatos de nivel que quedan sin
   identificar (offsets 8, 9, 10, 11, 18, 19 del registro de 20
   bytes)~~ — **hecho para 4 de los 6** (ver `FINDINGS.md`, de paso
   se corrigió un error de aritmética de una nota anterior que
   llamaba "offset 11" a lo que en realidad es el offset 8).
   Offsets 8/9/10: número de ítems tipo 3/1/2 en este nivel
   (confirmado, los tres manejadores del subsistema de items los
   leen como contador de bucle). Offset 11: duración en fotogramas
   del parpadeo de la bola/pista especial antes de cambiar de
   estado (confirmado por código real en el bucle principal — un
   contador regresivo comparado contra un umbral, con test de
   paridad tipo blink). ~~Offsets 18 y 19~~ — **RESUELTO**: es el
   número objetivo de "bolitas a comer" para dar el nivel por
   completado — `IML_90B7` (bucle principal, `madmix1_body.asm`) compara
   estos dos bytes (`$2C05`, 16 bits) contra `$2C08` (contador real,
   incrementado por 4 manejadores del motor de colisión cada vez que
   se come una bolita/bola especial) y solo entonces avanza de nivel.
   Verificado contando directamente las losetas "suelo con bola"
   (`0x2D`/`0x2E`/`0x2F`) en el cuerpo real de cada nivel: coincidía
   **exacto** solo en 5 de los 13 niveles comprobados al principio (1,
   8, 10, 12 y 13 — este último con su cuerpo "prestado" de
   `MADMIX1.BIN`, ver punto 5). **RESUELTO del todo después**: las
   losetas de flecha (`0x33`-`0x36`) también cuentan como bola al
   pisarlas (`HANDLER_2F18`/`2F50`/`2F88`/`2FC0` incrementan el mismo
   contador) — sumándolas, **los 12 niveles reales coinciden exacto,
   sin excepción** (ver `FINDINGS.md`, "misterio cerrado -- las flechas
   también cuentan como bola").
5. ~~Decidir el propósito real de `maze_data.bin`~~ — **RESUELTO** (y
   corregido más tarde, ver más abajo).
   `LEVEL_LOADER` usa el puntero de cuerpo de `LEVEL_TABLE`
   directamente, sin conversión de dirección. Para los niveles 0-12
   ese puntero cae en la copia reubicada de `MADMIX.SCR`
   (`0x1000-0x6500`), pero para los niveles **13** y **14** los
   punteros reales (`0xCFA4` y `0xD244`) caen dentro del rango
   ESTÁTICO de `MADMIX1.BIN` — como ambos ficheros coexisten en RAM
   en tiempo de ejecución, el cargador termina leyendo el cuerpo de
   estos dos niveles directamente de memoria residente: nivel 13 lee
   92 bytes de `BODY_L13_HEAD_CFA4` + 580 bytes de
   `body_l13_maze.bin`; nivel 14 lee sus 736 bytes completos de
   `body_l14.bin`. **Prueba de que es diseño deliberado**: el cuerpo
   del nivel 13 termina EXACTO (`0xCFA4+672=0xD244`) donde empieza el
   puntero del nivel 14 — no puede ser casualidad. Renderizando los
   cuerpos reales con el decodificador de losetas (ya estaban en
   `recursos/niveles.html` de una sesión anterior, ver también
   `dump_openmsx/level13_from_madmix1_memory.png` y
   `level14_from_maze_data.png`) salen **laberintos completos,
   simétricos y jugables**, sin rastro de ruido. El antiguo
   `maze_data.bin` (partido después en `body_l13_maze.bin` +
   `body_l14.bin`) es una pieza de diseño real, colocada a propósito
   en `MADMIX1.BIN` como fuente de datos compartida/reutilizada para
   ahorrar espacio en vez de duplicar ~1,4 KB de nivel dentro de
   `MADMIX.SCR`.

   **Corrección sobre `0xCFA4` (antes `RM_TABLE_CFA4`)**: se etiquetó
   en una sesión antigua como "posible tabla de envolvente/percusión
   de sonido" solo por su cercanía a las tablas de sonido reales —
   nunca confirmado, y con el driver de sonido ya desensamblado por
   completo se confirmó que ninguna rutina de sonido la lee.
   Decodificando sus 92 bytes como losetas el contenido es una sala
   de laberinto coherente y simétrica (muros, suelo con bola, ítem de
   bola de poder, estrellas), igual que cualquier otro nivel real —
   nunca fue dato de sonido, siempre fue la cabeza del cuerpo del
   nivel 13; renombrada a `BODY_L13_HEAD_CFA4`.

   **Corrección sobre los últimos 36 bytes del nivel 14 (antes
   `DEMO_SCRIPT_NIVEL1`, `0xD500-0xD524`)**: por el mismo tipo de
   error, una sesión antigua dedujo que eran el arranque real del
   guion de demo "nivel 1" — solo reasignado por `LEVELCYCLE_TABLE` a
   `0xD524` por alguna razón. Falso: `LEVELCYCLE_TABLE` SIEMPRE ha
   apuntado a `0xD524`, nunca a `0xD500` (verificado en la propia
   tabla, `madmix_scr_body.asm`), así que esos 36 bytes nunca fueron
   ejecutados como guion de demo — siempre fueron la cola del cuerpo
   del nivel 14. Unificado con la cabeza (antes `body_l14_maze.bin`,
   700 bytes) en un único fichero editable, `body_l14.bin` (736 bytes
   = 23×32), como cualquier otro nivel. La etiqueta real de demo
   `DEMO_SCRIPT_NIVEL1` ahora vive donde siempre estuvo en la
   práctica: `0xD524`. Ver `FINDINGS.md` para el detalle completo de
   ambas correcciones.
