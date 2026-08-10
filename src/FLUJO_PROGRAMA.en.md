# Mad Mix Game — program flow and function inventory

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

This document complements `FINDINGS.md` (which is a **chronological
findings diary**) and is organized by **execution flow**: what calls
what, in what order everything happens, and what each subsystem does.
The end goal is for the source code
(`madmix0_body.asm`/`madmix1_body.asm`/`madmix_scr_body.asm`) to read
as if it had been written by a period programmer who documented their
work well: real names instead of loose addresses, and a clear
explanation of what each routine does and why.

**It's a living document.** It doesn't aim to cover the project's
~650 labels all at once — it grows session by session, exactly like
`FINDINGS.md` does. What follows is the big picture:
boot, main loop and the subsystems already well understood. Each
section explicitly states what's confirmed and what's a hypothesis or
still pending.

**Full rewrite** (this round): the document had been frozen at a very
early stage of the project, with English/cryptic
names that had long been superseded by hundreds of
renaming rounds already applied to the real source code (see
`FINDINGS.md`). Everything that follows is verified directly against
the current code, not reconstructed from memory.

Visual companion: `recursos/flujo_programa.html` (flow diagram
+ a complete, searchable inventory of every label).

## 0. A label is not a function — how the work is prioritized

The source files' labels are a mixed bag: most
are NOT functions in the structured-programming sense (a
single entry point, a `RET`, a clear responsibility) — many are
plain internal jump marks (loop headers, one branch of a case,
shared exit points) living inside the body of
another routine — most of these have already been converted to
**local** labels (`.NAME`, with a dot) during the renaming
rounds — and another large group are **data** labels
(tiles, sprites, text, tables), not code.

`recursos/flujo_programa.html` §5 keeps the
automatic, filterable classification (function/internal/data/no
reference), useful for triage when starting to work on a new
area of the code.

---

## 1. The big picture, in 3 acts

The real game is **3 chained BLOAD files**, each with its
standard MSX header (`$FE` + start/end/exec), all generated from
`src/main.asm` (a single assembly pass, sharing one
symbol space):

1. **`MADMIX.SCR`** (`madmix_scr_body.asm`, loads at `$8800`, auto-
   runs): draws the cover art, and also contains —relocated
   later to low memory, see below— the collision/movement engine
   (each frame's "main loop"), the item-activation
   subsystem, the loader + table of the 15 playable levels, and the
   main menu + credits.
2. **`MADMIX0.BIN`** (`load_disk/madmix0_body.asm`, loads and auto-
   runs at `$FA00`, 58 bytes): the "relocator". It has **two
   entry points**:
   - `RELOCATOR` (`$FA00`, the one that auto-runs on load):
     saves the active slot config (two copies, one normal
     and one "twisted" for the other entry point), copies `$5500`
     bytes from `$8800` (where `MADMIX.SCR` just landed) to
     `$1000`, and **runs that relocated block exactly once**
     (`CALL DIBUJAR_PORTADA`). It does not draw the game engine
     permanently — it's a one-off boot operation.
   - `JUMP_TO_ENGINE` (`$FA2A`, a second, independent
     entry point): restores the other saved slot config
     and jumps straight to `$8400` (`JT_INICIO`, the real engine). Invoked
     by an explicit `CALL`/`USR` from the orchestrating BASIC,
     after also loading `MADMIX1.BIN`.
3. **`MADMIX1.BIN`** (`madmix1_body.asm`, loads at `$8400`, with no
   auto-run — `JUMP_TO_ENGINE` starts it by hand, see the previous
   point): the real game engine. Contains the public jump
   table (`JT_INICIO` and friends, see §3), `INICIO` and the main
   per-frame loop, the actor engine, the sound driver, the
   91 tiles, the 64 sprites, the text font and the raw data
   for 12 levels + 1 hidden + 10 demo scripts.

**Important confirmed detail**: the block relocated to `$1000`
(from `MADMIX.SCR`) contains ALL the cover-art + collision
engine + levels + demo + menu + credits code, but it's only run from
there **the first time** (drawing the cover art, both from `RELOCATOR`
and again from `INICIO`, see §2). The rest of that code is
referenced afterward by its **static addresses inside
`MADMIX.SCR` as-is** (`$5xxx`-`$6xxx`), not at `$1xxx`-`$2xxx` —
the block relocated to `$1000` and `MADMIX.SCR`'s static code
are the SAME logical representation at different physical addresses
(the same `PHASE`/`DEPHASE` pattern `main.asm` reproduces).

---

## 2. Boot sequence, step by step

```
Orchestrating BASIC (AUTOEXEC.BAS/MADMIX.BAS, out of scope)
  │
  ├─ BLOAD "MADMIX.SCR",R  ──────────────────────────────────────┐
  │                                                                │
  │  MADMIX.SCR loads at $8800 and AUTO-RUNS right there         │
  │  (cover art boot: palette, pattern, color -- DIBUJAR_PORTADA) │
  │                                                                │
  ├─ BLOAD "MADMIX0.BIN",R  (loads at $FA00, AUTO-RUNS)      │
  │     RELOCATOR ($FA00):                                        │
  │       - saves slot config at $FFFD (and a "twisted" one    │
  │         at $FFFE, for the other entry point)               │
  │       - switches to RAM at page 0                              │
  │       - LDIR $8800 -> $1000, 0x5500 bytes                      │
  │       - CALL DIBUJAR_PORTADA (runs the relocated block         │
  │         ONCE: draws the cover art)                          │
  │       - restores slots, EI, RET                                │
  │                                                                │
  ├─ BLOAD "MADMIX1.BIN"  (loads at $8400, WITHOUT ",R" -- doesn't │
  │     auto-run, JUMP_TO_ENGINE starts it by hand)            │
  │                                                                │
  └─ CALL/USR -> JUMP_TO_ENGINE ($FA2A, MADMIX0.BIN):              │
        restores the OTHER saved slot config (from $FFFE)              │
        JP START  (JT_INICIO, MADMIX1.BIN's real engine)           │
                                                                     │
INICIO ($8F24, madmix1_body.asm) -- NEVER does a RET:                │
  - LD SP,$0FFF                                                     │
  - CALL ACTIVAR_INTERRUPCION_MODO_1                                │
  - DI / CALL DIBUJAR_PORTADA (draws the cover art AGAIN -- it's     │
    drawn twice when starting a real game: once by the       │
    loader, once here by the engine itself)                        │
  - clears+installs the 3 sound slots (INSTALAR_RECURSO_SONIDO, │
    scripts GUION_MELODIA_CANAL_0/1/2)                              │
  - waits for keypress (polls COMPROBAR_PULSACION in a loop)          │
  - EI                                                               │
  - REINICIAR_PARTIDA: clears resources (VACIAR_CANALES_SONIDO),      │
    CALL MOSTRAR_MENU_PRINCIPAL (enters the MAIN MENU         │
    loop, waits for "0 PLAY" to be chosen -- see §5.8),        │
    lives=3, score=0, level=1, laps=0                       │
  - PANTALLA_PRESENTACION_NIVEL (normal re-entry each lap):  │
    draws HUD, CALL CARGAR_NIVEL, PREPARAR_INICIO_NIVEL (single-step │
    sequence: HUD, "READY?", starts the level's music)             │
  - falls into BUCLE_PRINCIPAL_JUEGO -- THE REAL PER-FRAME LOOP    ┘
```

**Confirmed** (transcribed and verified 0 differences): the whole
sequence above. Still not precisely traced live is the
exact purpose of a second `CALL $1000` that `INICIO` does (an
instruction literally confirmed in the bytes, but whose visual effect,
distinct from the loader's first cover-art draw, hasn't been fully
isolated).

---

## 3. The `JT_INICIO` dispatch table — the engine's "public API"

At `$8400` (start of `MADMIX1.BIN`), 12 `JP` entries, all
identified with a transcribed destination:

| Slot | Label | Destination | What it does |
|---|---|---|---|
| 0 | `JT_INICIO` | `INICIO` (`$8F24`) | Real engine boot (§2), never returns |
| 1 | `JT_MOTOR_ACTORES` | `MOTOR_ACTORES` (`$8440`) | Sub-pixel actor/render engine (§5.1) |
| 2 | `JT_RESET_CONTADOR_ACTORES` | `RESET_CONTADOR_ACTORES` (`$899B`) | `XOR A / LD ($8437),A / RET` — resets an actor variable |
| 3 | `JT_WAIT_VBLANK` | `WAIT_VBLANK` (`$89A0`) | Vertical sync wait |
| 4 | `JT_ACTIVAR_INTERRUPCION` | `ACTIVAR_INTERRUPCION_MODO_1` (`$881B`) | Installs the real interrupt vector |
| 5 | `JT_LEER_ENTRADA` | `LEER_ENTRADA` (`$8E3C`) | Keyboard/joystick reading (§5.5) |
| 6 | `JT_DIBUJAR_MARCADOR_PUNTOS` | `DIBUJAR_MARCADOR_PUNTOS` (`$8D70`) | Draws the score marker (§5.6) |
| 7 | `JT_GESTIONAR_SCROLL` | `GESTIONAR_SCROLL` (`$89AD`) | Camera's software scroll (§5.4) |
| 8 | `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` | `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` (`$8C34`) | Redraws camera strips + life icons (§5.4) |
| 9 | `JT_REDIBUJAR_LOSETA_BUFFER_VRAM` | `REDIBUJAR_LOSETA_BUFFER_VRAM` (`$8D1B`) | Copies a 16×16 background tile into the buffer |
| 10 | `JT_MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` | `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (`$8CB6`) | Camera coordinate → address in the level matrix |
| 11 | `JT_CONSULTAR_TIPO_LOSETA` | `CONSULTAR_TIPO_LOSETA` (`$8CDA`) | Tile address → type (collision) |

Almost nobody in the rest of the code calls these slots by number —
almost every call site calls the real address directly (`CALL
MOTOR_ACTORES`, `CALL MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA`, etc.), so
this table works more like a "documented index/API" than an
active dispatch mechanism.

---

## 4. The main loop (`BUCLE_PRINCIPAL_JUEGO`, `$8FD4`+)

**Important architecture correction versus older versions
of this document**: the routine at `$8FD4` is NOT directly "the
main loop" — its label is `PREPARAR_INICIO_NIVEL`, and it is
a **single-step** sequence ("level just loaded → position the
HUD → draw READY? → start the music → wait for the player") that only
runs during transitions (boot, level change, losing a
life). The real loop that repeats **every frame** is
`BUCLE_PRINCIPAL_JUEGO`, a bit further down in the same block.

After `INICIO`, the game spends the rest of its life in this flow —
confirmed there is no "going back": the two known
re-entries (`JP PREPARAR_INICIO_NIVEL` / `JP PANTALLA_PRESENTACION_NIVEL`)
re-enter `INICIO` itself, already transcribed, they don't jump
anywhere else.

**Architecture clarification**: Pac-Man/ghost movement,
camera redrawing and the collision engine (`TABLA_MANEJADORES_LOSETA`,
§5.2) are NOT in the body of `BUCLE_PRINCIPAL_JUEGO` listed
below — they're triggered from `ENTRADA_INTERRUPCION_VBLANK` (`$882A`) on
every VBLANK, via `GESTIONAR_FRAME` (see §5.10). In other
words, two "threads" cooperating via interrupt:
`ENTRADA_INTERRUPCION_VBLANK` moves/draws the game frame by frame in
the background, while `BUCLE_PRINCIPAL_JUEGO` in the
foreground waits (`HALT`, via `WAIT_VBLANK`) and checks global
conditions (special-mode timer, level end, pause) at the pace of
those same frames.

### Step-by-step diagram

```
REINICIAR_PARTIDA (real boot / after GAME OVER)   PANTALLA_PRESENTACION_NIVEL (each normal lap)
        │                                                       │
        ▼                                                       │
  clears resources, MOSTRAR_MENU_PRINCIPAL, lives=3,              │
  score=0, level=1, laps=0                              │
        │                                                       │
        └───────────────────────────────┬──────────────────────┘
                                         ▼
                              clears resources (VACIAR_CANALES_SONIDO)
                                         │
                    draws 3 lines of HUD (DIBUJAR_TEXTO_VRAM: TEXTO_FASE,
                    and if applicable TEXTO_VIDA_EXTRA) based on level (NIVEL_ACTUAL)
                    and level-register flags (REGISTRO_NIVEL_VIDA_EXTRA_FLAG)
                                         │
                                         ▼
                            waits 80 frames (PAUSA_TEXTO_FASE_LOOP)
┌───────────────────────────────────────┴────────────────────────────────────┐
│ PREPARAR_INICIO_NIVEL ($8FD4) -- a SINGLE-STEP sequence, not the loop     │
│  1. clears resources, INICIALIZAR_ITEMS_NIVEL (resets 3 item tables +   │
│     mode flags)                                                          │
│  2. REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM (redraws camera + life icons) │
│  3. APLICAR_COLOR_PANTALLA (same drawing engine as the HUD/credits)   │
│  4. sets Pac-Man's initial sprite (normal, or "excavatofono" if       │
│     MODO_ESPECIAL=3)                                                        │
│  5. clears direction/timer flags                                │
│  6. REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM again (after clearing flags)   │
│  7. locks the keyboard (FLAG_ENTRADA_BLOQUEADA=1)                              │
│  8. BUSCAR_COLUMNA_HUD: looks in TABLA_POSICIONES_HUD (19 bytes) for the entry │
│     matching the camera column -- 1 VBLANK wait per         │
│     entry tried (visible sweep effect), sets HUD position     │
│  9. unlocks the keyboard (FLAG_ENTRADA_BLOQUEADA=0)                           │
│ 10. MOSTRAR_READY_Y_ARRANCAR_NIVEL: computes attribute color (via          │
│     OBTENER_COLOR_VDP) based on camera column, draws TEXTO_VACIO_1 /      │
│     TEXTO_READY / TEXTO_VACIO_2 ("erase and paint" effect)             │
│ 11. installs the level-start jingle (3 channels,                     │
│     GUION_EVT10_INICIO_NIVEL_CEF0 + offsets 0/7/14)                        │
└───────────────────────────────────────┬────────────────────────────────────┘
                                         ▼
                    PAUSAR_PARTIDA: waits 50 frames + polls until any
                    input (first lap: enters here directly, without checking
                    pause first)
┌───────────────────────────────────────┴────────────────────────────────────┐
│ BUCLE_PRINCIPAL_JUEGO -- REAL PER-FRAME TICK (repeats while playing)   │
│  · CALL ENLACE_MOTOR_MOVIMIENTO_COLISION (self-modifying trampoline, see   │
│    §5.2) + WAIT_VBLANK                                                     │
│  · if MODO_ESPECIAL_ACTIVO [respawn/invulnerability timer] > 0:    │
│    decrements it; if it reaches 0 RIGHT NOW → "life lost": DESTELLO_ICONO_  │
│    COLOR_HUD, realigns the camera to a multiple of 4 tiles, subtracts 1 life        │
│    (VIDAS_RESTANTES) [target of the infinite-lives trick, see           │
│    `.COMPROBAR_TRUCO_VIDAS_INFINITAS` in `GESTIONAR_INTRODUCCION`, §5.8] → │
│      · lives remain → JP PREPARAR_INICIO_NIVEL (resets the level's HUD)    │
│      · no lives left → GAME OVER: fills the playable area with black,            │
│        TEXTO_GAME_OVER, waits ~150 frames, JP REINICIAR_PARTIDA           │
│  ▼                                                                          │
│ VERIFICAR_FIN_NIVEL -- level end                                        │
│  · ACTUALIZAR_LOSETA_BOLA_ESPECIAL (special-ball blink, every     │
│    lap -- verified live that it is NOT visible, a different mechanism)     │
│  · compares CONTADOR_BOLAS_COMIDAS against REGISTRO_NIVEL_OBJETIVO_BOLAS →   │
│      · matches → level completed: INC NIVEL_ACTUAL; if it reaches 16,       │
│        goes back to level 1 and increments CONTADOR_VUELTAS_NIVELES;         │
│        DESTELLO_ICONO_COLOR_HUD (reveals the new HUD) →                 │
│        JP PANTALLA_PRESENTACION_NIVEL                                      │
│      · doesn't match → continues                                        │
│  ▼                                                                          │
│ VERIFICAR_ENTRADA -- polls for "pause" (bit 5 of LEER_ENTRADA, exact       │
│ key unconfirmed)                                                      │
│      · bit set → PAUSAR_PARTIDA: fixed 50-frame wait + polling     │
│        until any input (same pattern as the initial input),        │
│        clears sound                                                        │
│      · bit clear → continues directly                                        │
│  ▼                                                                          │
│  JP BUCLE_PRINCIPAL_JUEGO -- next frame                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

Notes:
- The real movement of Pac-Man, the scroll and the collision engine
  (`TABLA_MANEJADORES_LOSETA`) happen in parallel, triggered by
  `ENTRADA_INTERRUPCION_VBLANK` on every VBLANK — they are not shown
  above because they are not part of `BUCLE_PRINCIPAL_JUEGO`'s
  own body (see §5.10 for the interrupt chain).
- The "unidentified bit 5" of `VERIFICAR_ENTRADA` is the only real
  gap left in this diagram — a strong candidate for a
  pause key, unconfirmed (would need live tracing or simply
  trying the key in the real game).

---

## 5. Subsystems

### 5.1 Actor engine — `MOTOR_ACTORES` (`$8440`-`$8800`, 960 B)

Draws/moves Pac-Man and the ghosts with sub-pixel rendering
(a fine offset within the tile, not just tile by tile). Uses a
RAM buffer at `$0500`-`$1000` for the intermediate work before
dumping to VRAM. Called from practically every game
subsystem (item handlers, tile handlers, `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`)
to redraw an actor after its state changes.

**Confirmed**: there are only right/down/up-facing sprites in
the data — never left-facing. `INVERTIR_BITS_PATRON_ACTOR`/
`INVERTIR_ORDEN_BYTES_PATRON_ACTOR` (hypothesis, not confirmed live)
do the horizontal flip at runtime, the same bit7 convention
already confirmed in `SELECTOR_SPRITE_COMECOCOS`.

### 5.2 Tile-type dispatcher — `TABLA_MANEJADORES_LOSETA` (`$2E3C`, `madmix_scr_body.asm`)

20 pointers, indexed by the **type** of the tile Pac-Man is
moving into (`CONSULTAR_TIPO_LOSETA`, values 0-19). It's the
heart of the "collision/movement engine"
(`MOTOR_MOVIMIENTO_COLISION`) that decides what happens when the
player enters each tile.

**Preamble documented line by line** (`MOTOR_MOVIMIENTO_COLISION`,
before the dispatch): decides the frame's valid direction (real input
or a demo script if `GESTIONAR_CICLO_NIVELES` is active), only
allows turning at tile-aligned positions, and checks
`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` (with a per-column cache)
to find the destination tile's type. While a special mode
is active (`MODO_ESPECIAL_ACTIVO!=0`), per-type dispatch is
suspended (type 0 is forced) and the preamble itself manages the
mode's countdown (HUD icon blink, mode end).

**Confirmed pattern**: `A` on entering any handler is always
the current special mode (`MODO_ESPECIAL`), not a tile
parameter. See `FINDINGS.md` for the full per-handler breakdown.

| Type | Tile(s) | Effect |
|---|---|---|
| 0 | normal wall/floor (0-44) + loose decorative variants | no effect (default) |
| 1 | `suelo_con_bola_1/2/3` | normal ball: +1 point, +1 level-end counter |
| 2 | `suelo_con_bola_clavada_1/2/3` | "frees" the stuck ball (no points) |
| 3-6 | up/down/left/right arrows | forces direction, +2 points, +1 counter |
| 7 | `pista_tanque_vertical` | "tank" special mode |
| 8, 9 | `linea_electrica_puerta_fantasmas_a/b` | no logic of its own (shares the default) |
| 10 | `pista_avion_recto`/`remate_izq`/`remate_der` | "plane" special mode |
| 11 | `item_suelo_sin_confirmar` | exits special mode |
| 12 | `item_bola_de_poder` (the real one) | "power ball" special mode, +2 points, +1 counter |
| 13 | `item_hipopotamo` | "hippo" special mode |
| 14 | `item_herramienta` | "tool" special mode |
| 15, 16 | `suelo_sin_bola_*`/`muro_ladrillo_suelto`/`loseta_solida_negra` | exits special mode |
| 17-19 | `trampilla_transicion` variants | trapdoor-opening animation |

Related: a working-RAM table (`$2C2E`, outside this
file) holds up to 3 active track/trapdoor positions,
checked both by the collision engine and by
`AVISAR_PROXIMIDAD_PISTA` (§5.3).

### 5.3 Special item subsystem

Pieces and their real role (see `FINDINGS.md` for the full
line-by-line breakdown):

- **`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO`** (`$2377`/`$2563` approx.,
  own tables `TABLA_ITEMS_MARICOCO`/`TABLA_ITEMS_REGPUNANTOSO`)
  are a complementary pair managing the life cycle of "stuck"
  balls: `HNDLR_MARICOCO` **regenerates** already-eaten ball
  gaps (`suelo_sin_bola`, 63-65) back into a normal ball (45-47),
  decrementing the level-end counter because there's a
  pending one again; `HNDLR_REGPUNANTOSO` **plants** new stuck
  balls by turning un-eaten normal balls (45-47) into stuck
  ones (48-50), without touching that counter. Both position their items via
  `MOTOR_MOVIMIENTO_ITEM`/`CONSULTAR_LOSETA_LIBRE_DIRECCION` ("approach
  the target or roam randomly" AI) and draw with `MOTOR_ACTORES`; once
  placed they mark their table entry to stop recomputing
  direction ("planted").
- **`HNDLR_PELMAZOIDE`** (`$51FE`, table `TABLA_ITEMS_PELMAZOIDE`, 8
  entries × 7 bytes): the ghosts' movement AI — it tries to
  approach a target point (camera+offset), and if it can't or by
  chance (`GENERAR_ALEATORIO`), moves in any walkable
  direction via `CONSULTAR_LOSETA_LIBRE_DIRECCION` (tile types
  0/7/8/10 are not walkable for these entities).
- **`AVISAR_PROXIMIDAD_PISTA`** (`$566A`): watches Pac-Man's
  proximity to the active tank/plane tracks (table at `$2C2E`)
  with a wide margin, arms a warning via `ARMAR_AVISO_DESTELLO`.
- **`ACTUALIZAR_DESTELLO_ITEMS`** (`$5782`): timer for the 4
  "active item slots", uses a flash-effect table to
  decide the animation tile.
- **`ACTIVAR_EFECTO_ITEM`**: dispatches the collision effect based on
  the current special mode; the "tool" mode reuses the same
  path as "no special mode".

### 5.4 Camera: scroll and lives HUD

- `GESTIONAR_SCROLL` (`$89AD`, `JT_GESTIONAR_SCROLL`): decides scroll
  up/down/sideways based on bits of the camera position
  (`REGISTRO_NIVEL_POSICION_COMECOCOS`).
- `REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM` (`$8C34`,
  `JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM`): redraws the whole
  camera (36 passes of `DIBUJAR_FILA_LOSETAS_BUFFER_VRAM`) and, if
  lives remain, draws the life icon once per remaining life; along
  the way clears and redraws the score marker.
- `MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` (`$8CB6`): the shared
  coordinate→address formula in the level matrix (32-column stride).

### 5.5 Input — `LEER_ENTRADA` (`$8E3C`, `JT_LEER_ENTRADA`)

Reads the keyboard (standard MSX matrix) and joystick (PSG
port), decodes directions with the same bit-extraction pattern as
`CONSULTAR_COLOR_VDP`/`TABLA_COLORES_VDP` (reused here for
direction, not color), and stores the result in
`ACUMULADOR_ENTRADA`/`FLAG_ENTRADA_BLOQUEADA` ("free" bytes
reused right before `TABLA_TIPOS_LOSETA`).

### 5.6 HUD — `DIBUJAR_MARCADOR_PUNTOS` (`$8D70`, `JT_DIBUJAR_MARCADOR_PUNTOS`)

Draws the score marker. If demo mode is active
(`INDICE_CICLO_NIVELES`) shows `TEXTO_DEMO` (" DEMO ") instead of
the number; otherwise, adds to the running score (`PUNTUACION`); if
it reaches 10000 shows `TEXTO_BESTIA` ("BESTIA") instead of
continuing to count up; otherwise, converts the number to ASCII
digits (`DIBUJAR_MARCADOR_PUNTOS_DIGITOS`) and draws it with
`DIBUJAR_TEXTO_INVERTIDO_VRAM`.

### 5.7 Level loading — `CARGAR_NIVEL`/`INICIALIZAR_ITEMS_NIVEL` (`$5904`, `$5885`)

`CARGAR_NIVEL` reads the 20-byte register from `TABLA_NIVELES` based on
`NIVEL_ACTUAL`, copies header + body (replacing the wildcard tile
if applicable) into buffer `$FC50`, and sets Pac-Man's
starting position. `INICIALIZAR_ITEMS_NIVEL` (`$5885`) resets the 3
moving-item tables + several special-mode flags. It has a
**second entry point**, `INICIALIZAR_PARCIAL_ITEMS_NIVEL`
(halfway through the routine), which only clears the active-track
table (`$2C2E`) — used separately when leaving tank/plane modes
without repeating the rest of the reset.

### 5.8 Main menu, intro/demo and key redefinition

- `GESTIONAR_INTRODUCCION` (`$5AE9`, formerly attract mode): waits
  for a key; if none is pressed within the time limit, it cycles sample
  levels (`GESTIONAR_CICLO_NIVELES`) playing the scripts in
  `data/demos/*.dem`. **RESOLVED**: if the key is ESC (row 7),
  it activates a hidden infinite-lives trick
  (`.COMPROBAR_TRUCO_VIDAS_INFINITAS`, local) that hot-patches
  `BUCLE_PRINCIPAL_JUEGO`'s `SUB $01` into `SUB $00`.
- `.CONTINUAR_INTRO`/`MOSTRAR_MENU_PRINCIPAL`/`ACTUALIZAR_MENU_PRINCIPAL`
  (`$5B50`-`$5B71` approx.): the common "continue" tail after the intro —
  turns off the screen (`PROGRAMAR_APAGADO_PANTALLA`), clears resources,
  clears VRAM (`LIMPIAR_VRAM_AREA_JUEGO`), advances the level
  cycle (`APLICAR_COLOR_CICLO_NIVELES`), and enters **the main
  menu loop**: draws `DIBUJAR_MENU_PRINCIPAL`, turns the
  screen back on (`PROGRAMAR_ENCENDIDO_PANTALLA`), reads a key
  (`LEER_TECLAS_MENU_PRINCIPAL`) and checks bit 0 of the result:
  - **bit 0 set** → exits the menu loop, clears camera position/color,
    `WAIT_VBLANK`, `RET` — this is the **"PLAY"** signal, and it
    returns control to whoever called the menu (`INICIO` at
    real boot, or the return point after the intro), which continues
    on toward `BUCLE_PRINCIPAL_JUEGO`.
  - **bit 0 clear** → `DESPACHAR_ACCION_MENU` dispatches by bit
    (1/3/4/5) to the 4 numbered options (see table below); if it
    doesn't match any of them and the value is nonzero, it resets
    the menu timer (`GESTIONAR_TIMEOUT_MENU`); if it's
    exactly zero (no key), it counts down toward
    `GESTIONAR_INTRODUCCION` (attract mode) instead of waiting
    forever.
  - Each of the 4 options (except "PLAY", which exits the loop)
    **returns to the menu loop itself**, redrawing the menu with the
    option highlighted.

| Option | Bit | Routine | What it does | Returns to the menu? |
|---|---|---|---|---|
| 1 KEYBOARD | 3 | `SELECCIONAR_OPCION_TECLADO` | sets input method, highlights option 1 | Yes |
| 2 JOYSTICK | 4 | `SELECCIONAR_OPCION_JOYSTICK` | sets input method, highlights option 2 | Yes |
| 3 REDEFINE KEYS | 1 | `SELECCIONAR_OPCION_REDEFINIR_TECLAS` | `CALL DIBUJAR_MENU_REDEFINIR_TECLAS` (real key submenu), clears VRAM, redraws | Yes |
| 4 DEMO | 5 | `SELECCIONAR_OPCION_DEMO` | `CALL GESTIONAR_CICLO_NIVELES` (cycles sample levels playing `data/demos/*.dem`), clears resources/VRAM, redraws | Yes — it's a demo module that runs and comes back, it does NOT leave the menu permanently |
| 0 PLAY | 0 | (exits the loop) | clears camera position/color + `WAIT_VBLANK` | No — continues on to `BUCLE_PRINCIPAL_JUEGO`, the real game |

`DIBUJAR_MENU_REDEFINIR_TECLAS`: the real key-redefinition
submenu (`TEXTO_MENU_REDEFINIR_TECLAS`, text for the 6 actions +
key names), using `ESPERAR_TECLA_NUEVA` to detect the
pressed key via `TABLA_CODIGOS_TECLA`.
- `APLICAR_COLOR_PANTALLA`/`DIBUJAR_CREDITOS`: the real credits
  screen ("POGRAMADO BY: RAPHAEL GOMEZZZ..", etc.) — it also triggers
  applying the candy frame's real color
  (`TABLA_RECURSOS_SONIDO_EVENTO`... the color table itself, see
  `FINDINGS.md`).
- `REUBICADOR_REINICIO_JUEGO`: a second relocation routine, a twin of
  `MADMIX0.BIN`'s `RELOCATOR` — a candidate for "hot-return to the
  menu", not confirmed live.

### 5.9 Sound driver (`$C4A0`-`$CF8B`, in `madmix1_body.asm`)

`INSTALAR_RECURSO_SONIDO` (`$C4A0`) looks for a free slot among the
channel slots (46 bytes each, at `$C9C9`); the main
player (`TICK_REPRODUCTOR_PSG`/`PROCESAR_CANAL_PSG`) reads
commands/durations from a script and dumps the AY-3-8910 PSG's 11
registers every tick. `VACIAR_CANALES_SONIDO` (`$CF8B`) clears the 3
slots.

**`EVENTO_SONIDO_PENDIENTE`** (`$6128`) is the index of the sound
effect to trigger (see `FINDINGS.md` for the full breakdown).
`DESPACHAR_EFECTO_SONIDO` (`$60DC`, `madmix_scr_body.asm`), called
on every VBLANK from the ISR, consumes `(EVENTO_SONIDO_PENDIENTE)` and
looks it up in `TABLA_RECURSOS_SONIDO_EVENTO` (`$60FE`, 14 entries
`[channel, pointer]`) to install the corresponding script into the
PSG player.

The 15 bytecode commands have been deciphered one by one (see
`FINDINGS.md`). Every `.snd` has a twin `.txt` in editable plain
text, generated and verified with `tools/mmsnd_tool.py` (exact
byte-for-byte roundtrip). Pending: the instrument tables themselves (~20
pointers to programs written in this same language) haven't
been decoded yet.

### 5.10 Interrupt — `ENTRADA_INTERRUPCION_VBLANK` (`$882A`) + `GESTIONAR_FRAME` (`$8860`)

`ENTRADA_INTERRUPCION_VBLANK` saves registers, does housekeeping
(`GESTIONAR_FRAME`: calls `CONTINUAR_CAPTURA_MASCARAS_ACTORES`,
`RESET_CONTADOR_ACTORES`, refreshes VRAM via `ACTUALIZAR_VRAM_FRAME`,
drains the deferred-redraw queue via
`VACIAR_COLA_REDIBUJADO`/`.DESPACHAR_ENTRADA_COLA` →
`REDIBUJAR_LOSETA_BUFFER_VRAM`) and restores. Installed by
`ACTIVAR_INTERRUPCION_MODO_1` at boot (`$0038` → `JP $882A`,
confirmed live).

---

## 6. Most important shared state variables

Quick reference (working RAM, almost all inside the "active
level register" copied to `REGISTRO_NIVEL`/`$2C0X`-`$2C2D` or nearby):

| Variable | What it is |
|---|---|
| `REGISTRO_NIVEL_POSICION_COMECOCOS` (`$2C02`) | Camera/Pac-Man position |
| `REGISTRO_NIVEL_OBJETIVO_BOLAS` (`$2C05`/`$2C06`) | Target number of balls to eat (offsets 18-19 of the level register) |
| `NIVEL_ACTUAL` (`$2C07`) | Current level (1-14; 0 reuses level 1's register) |
| `CONTADOR_BOLAS_COMIDAS` (`$2C08`) | Live counter of remaining balls/items |
| Special-mode flags (`$2C0D`-`$2C11`) | Hippo/obra/plane..., reset by `INICIALIZAR_ITEMS_NIVEL` |
| `$2C18`/`$2C24` | Pair saved/restored when entering and leaving a special mode |
| `VIDAS_RESTANTES` (`$2C27`) | Lives remaining |
| `PUNTUACION` (`$2C29`) | Accumulated score |
| `MODO_ESPECIAL` (`$2C2D`) | Active special-mode selector (0=normal) |
| `CONTADOR_VUELTAS_NIVELES` | Complete laps around the 15-level cycle |
| `EVENTO_SONIDO_PENDIENTE` (`$6128`) | Index of the sound effect to trigger (§5.9) |

---

## 7. Pending / hypotheses not confirmed live

- The exact purpose of the second `CALL $1000` inside `INICIO`
  (§2) — different from the loader's cover-art drawing.
- Bit 5 of `LEER_ENTRADA` (a candidate for a pause key, §4) — not
  confirmed which physical key it is.
- The exact horizontal sprite-flipping mechanism in
  `MOTOR_ACTORES` (§5.1) — candidates identified, not traced
  live.
- The sound driver's instrument tables (§5.9) — not
  decoded note by note.
- See `FINDINGS.md` for the full catalog of findings, hypotheses
  and corrections — this document only summarizes the high-level flow.
