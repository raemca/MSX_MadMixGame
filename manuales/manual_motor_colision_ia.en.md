# Movement/collision engine and item AI manual — Mad Mix Game (MSX1)

*Reverse engineering, analysis and documentation: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

> Source: `madmix_scr.asm`, region `$2CA0`-`$5904` approx. (collision
> engine, tile dispatch table, special-item subsystem). For the
> chronicle of how each piece was discovered, see
> `FINDINGS.md`; this document assumes everything is already
> identified and explains the final result in an orderly way.

## 1. What this is and what it is NOT

This is the subsystem that decides, **every frame**, where Pac-Man
moves and what happens when he steps on something — and, separately
but tightly linked, the "AI" of the 3 entity types that move around
the map without being the player: the ghosts (`HNDLR_PELMAZOIDE`), the
ladybug (`HNDLR_MARICOCO`) and the "repugnantoso" (`HNDLR_REGPUNANTOSO`).

**It is not** real pathfinding (there is no BFS/A\* nor knowledge of
the full map): each entity decides its direction by looking only at
the 4 tiles immediately adjacent to its current position, with a
table biased toward "keep going the same way" and one random bit to
break ties. It's the same kind of CPU-cheap solution as the player's
own collision engine (§3) — both literally share the same random-choice
table indexed by range of free directions. **Nor** is there any
"chase/flee" behavior distinction per ghost like in the original
Pac-Man (Blinky/Pinky/Inky/Clyde): all 8 entries of
`TABLA_ITEMS_PELMAZOIDE` run the same code, with the same bias
of "approach a fixed camera-linked reference point" — see
§6 for the important nuance of what that point really is.

## 2. General architecture

```
$2C36 ─── ENLACE_MOTOR_MOVIMIENTO_COLISION      -- trampoline (JR), called from madmix1.asm every frame
$2CA0 ─┬─ MOTOR_MOVIMIENTO_COLISION              -- decides direction, alignment, special mode (§3)
       ├─ TABLA_MANEJADORES_LOSETA ($2E3C)      -- 20 pointers, one per tile type (§4)
       ├─ CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION ($2E64) -- tile type 1 step ahead (with cache)
       ├─ HNDLR_SUELO_NORMAL / HNDLR_BOLITA_NORMAL / HNDLR_BOLITA_CLAVADA / HNDLR_AUTOCOCO_* / ... -- 20 handlers (§4)
       └─ tank/plane track loop (inside MOTOR_MOVIMIENTO_COLISION, at the end)
$5278 ─┬─ MOTOR_MOVIMIENTO_ITEM                  -- GENERIC item movement engine (§5), used by all 3 types
       ├─ CALCULAR_POSICION_VRAM_ITEM ($53A2)   -- 2nd entry point: only visible position, no movement
       └─ CONSULTAR_LOSETA_LIBRE_DIRECCION ($5414) -- is there a walkable tile 1 step in this direction?
$51FE ─── HNDLR_PELMAZOIDE                       -- ghost AI, up to 8 active (§6.1)
$5478 ─── GENERAR_ALEATORIO                      -- shared pseudo-random generator (simplified LFSR)
$5487 ─── HNDLR_MARICOCO                         -- ladybug AI, up to 2 active, REGENERATES eaten balls (§6.2)
$5574 ─── HNDLR_REGPUNANTOSO                     -- "repugnantoso" AI, up to 8 active, PLANTS stuck balls (§6.3)
$566A ─── AVISAR_PROXIMIDAD_PISTA                -- nearby tank/plane track warning (§7)
$56CA ─── ARMAR_AVISO_DESTELLO / ACTUALIZAR_DESTELLO_ITEMS -- animation "flash" queue (§7)
$57D8 ─── ACTIVAR_EFECTO_ITEM                    -- triggers special modes / points when stepping on an item (§8)
```

All of this lives in `madmix_scr.asm` (the "loading screen", which
actually contains much more than graphics — see `README.md`), as
opposed to the actor/render engine (`madmix1.asm`, see
`FLUJO_PROGRAMA.md` §5.1) and the sound driver (`manual_driver_sonido.md`).

## 3. The collision engine: `MOTOR_MOVIMIENTO_COLISION`

Called **once per frame** from the main loop
(`BUSCAR_COLUMNA_HUD`/`BUCLE_PRINCIPAL_JUEGO`, `madmix1.asm`) through
the `ENLACE_MOTOR_MOVIMIENTO_COLISION` trampoline (`$2C36`, 2 bytes,
`JR MOTOR_MOVIMIENTO_COLISION`). In order, it:

1. **Reads direction**: if the level demo cycler is active
   (`(INDICE_CICLO_NIVELES)≠0`, demo mode) it uses the script's
   precomputed direction; otherwise it calls `LEER_ENTRADA` (real
   keyboard/joystick).
2. **Filters by alignment**: a direction is only valid if Pac-Man
   is tile-aligned on the axis perpendicular to it (you can't turn
   mid-corridor). If the requested direction isn't valid, the
   previous frame's direction is kept.
3. **Checks the tile one step ahead** in the chosen direction
   (`CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION`, with a column cache
   so the calculation isn't repeated if it hasn't changed). If the
   type is "no effect" (0), it retries with the previous frame's
   direction in case that one does hit something special.
4. **Active special mode** (`MODO_ESPECIAL_ACTIVO≠0`): while a
   special mode lasts (power ball/hippo/tool/tank-plane),
   normal per-tile-type dispatch is **fully suspended** — type 0 (no
   effect) is forced. The special mode's own tick (HUD icon
   blinking, countdown, mode end) is handled separately, in the same
   block (`TICK_MODO_ESPECIAL`).
5. **Dispatches** to the handler from the 20-entry table (§4)
   according to the resulting tile type.
6. **Pac-Man sprite selector**: with the final direction already
   decided, it indexes one of 4 20-byte subtables (`SUBTABLA_DIRECCION_A`
   to `_D`, one per direction) with a rotating index — the value
   obtained is the **real animation frame** (mouth open/closed +
   orientation, with bit 7 as horizontal flip) passed to
   `MOTOR_ACTORES` for redrawing. This is NOT a scroll parameter,
   despite what an earlier working hypothesis suggested — see
   `FINDINGS.md` for the full register-by-register trace.
7. **Triggers scroll + items + redraw**: calls `GESTIONAR_SCROLL`,
   and if the keyboard isn't locked (`FLAG_ENTRADA_BLOQUEADA=0`),
   runs in fixed order `HNDLR_PELMAZOIDE` → `HNDLR_MARICOCO` →
   `HNDLR_REGPUNANTOSO` → `ACTUALIZAR_DESTELLO_ITEMS` (always) →
   `MOTOR_ACTORES` (redraws Pac-Man).
8. **Tank/plane track loop**: walks the 3 entries of
   `TABLA_PISTA_TANQUE_AVION` and draws each active one with
   `MOTOR_ACTORES` directly (this does NOT go through the tile-type
   system).

**Open item, not resolved**: there is an asymmetry between opposite
direction pairs in `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` —
right/down advance a full tile step (+4), but left/up only subtract 1
unit (it may not even cross a tile boundary depending on the current
sub-position). Not confirmed whether this is deliberate or a case
that hasn't been fully explored — see `FINDINGS.md`.

## 4. The per-tile-type dispatch table (`TABLA_MANEJADORES_LOSETA`, 20 entries, `$2E3C`)

The dispatch index is directly the type value returned by
`CONSULTAR_TIPO_LOSETA` (no shift). Mapping type → real tile
→ handler (cross-checked against `TABLA_TIPOS_LOSETA` in `madmix1.asm`
and the `data/tiles/*.til` catalog):

| Type | Tile(s) | Handler | Effect |
|---|---|---|---|
| 0 | normal wall/floor + decorative tiles with no handling of their own; also types 8/9 | `HNDLR_SUELO_NORMAL` | no game effect (general case) |
| 1 | suelo_con_bola (normal ball) | `HNDLR_BOLITA_NORMAL` | eats the ball: +1 point, counts toward level end |
| 2 | suelo_con_bola_clavada (stuck ball) | `HNDLR_BOLITA_CLAVADA` | only with "tool" mode (3): frees it (turns it into a normal ball) |
| 3-6 | arrow up/down/left/right | `HNDLR_AUTOCOCO_*` | forces that direction (if not already locked), +2 points, counts toward level end |
| 7 | pista_tanque_vertical | `HNDLR_PISTA_COCOTANQUE` | (not detailed in this manual, see `graficos.html`) |
| 8, 9 | ghost-door power line | `HNDLR_SUELO_NORMAL` | generic; type 9 has a special exit (end of "plane" mode) |
| 10 | pista_avion (straight/end pieces) | `HNDLR_PISTA_COCONAVE` | shares an exit tail with type 9 |
| 11 | item_suelo_sin_confirmar | `HNDLR_ITEM_SUELO` | (not detailed in this manual) |
| 12 | item_bola_de_poder | `HNDLR_BOLA_PODER` | activates special mode 1 (power ball) |
| 13 | item_hipopótamo | `HNDLR_HIPODOSO` | activates special mode 2 (hippo) |
| 14 | item_herramienta | `HNDLR_EXCAVATOFONO` | activates special mode 3 (tool) |
| 15, 16 | suelo_sin_bola / muro_ladrillo_suelto / loseta_solida_negra | `HNDLR_SUELO_SIN_BOLA` | no effect (ball already eaten / decorative) |
| 17, 18, 19 | trampilla_transicion variants | `HNDLR_TRAMPILLA_ABIERTA_DERECHA`/`_IZQUIERDA`/`HNDLR_TRAMPILLA_CERRADA` | L-shaped trapdoor mechanic (3 states) |

**Two handlers documented in detail, as an example of the general
pattern** (all of them follow the same shape: filter by current
special mode and by "movement phase" so the same tile isn't counted
twice, then act):

- `HNDLR_BOLITA_NORMAL`: only acts if there is NO "strong" special
  mode in progress (mode < 2) and the movement phase is the right
  one. Sets `EVENTO_SONIDO_PENDIENTE=0`, replaces the tile with its
  "eaten" version (bit 7), adds 1 point and increments
  `CONTADOR_BOLAS_COMIDAS` (read by `VERIFICAR_FIN_NIVEL`,
  `madmix1.asm`).
- `HNDLR_AUTOCOCO_*` (arrows): same filter, plus a check that that
  direction isn't already locked (bitmask in B). If it's free:
  marks the event, replaces the tile, sets `DIRECCION_FORZADA`
  and also counts as a ball (+2 points, +1 to the level-end
  counter) — arrows count toward completing the level in addition
  to forcing the turn.

## 5. The generic item movement engine: `MOTOR_MOVIMIENTO_ITEM`

All 3 entity types (§6) share **the same routine** for movement
decisions — only the active-position table, the animation sprite
table, and what they do on reaching their spot change. It receives in
`IX` the pointer to the active entry (common 7-byte format:
`[X, Y, mode/planted, direction, subX, subY, phase]`).

**Entry point 1** (`$5278`, normal use): computes whether the item
should move toward a **reference point** (`PUNTO_REFERENCIA_CAMARA`,
see §6.1 for exactly what that is) and in which direction:

1. If the item is "inactive/frozen" (`(IX+2)≠0`, see §6.2/§6.3
   for when that flag gets set) or a special mode is in progress, it
   does NOT compute a new approach direction — it keeps the one it
   already had.
2. If not, it compares its position against the reference point
   (aligned to multiples of 4): same column axis → vertical
   direction; same row axis → horizontal; neither → no clear
   direction.
3. **Only if tile-aligned** (sub-tile position = 0) is it allowed to
   change direction: it checks the 4 directions with
   `CONSULTAR_LOSETA_LIBRE_DIRECCION` and builds a "free" bitmask.
   If the desired direction (step 2) is one of the free ones, it uses
   it — but only 100% of the time if a special mode is active; if
   not, 50% of the time (a roll with `GENERAR_ALEATORIO`), so
   movement isn't perfectly deterministic.
4. If the desired direction is NOT free (or the 50% roll came up
   "no"), it chooses among ALL free directions using
   `TABLA_ELECCION_DIRECCION` (16 groups × 8 values, indexed by free
   bitmask + previous direction + 1 random tie-breaking bit) — the
   same "prefer to keep going" bias table described in that table's
   header comment in the code (§1).
5. Applies the movement (normal step `$0100` or half step `$0080` if
   `(IX+2)` is active or an "inverted" special mode is on) by
   adding/subtracting from the X or Y axis according to the final
   direction code.

**Entry point 2**, `CALCULAR_POSICION_VRAM_ITEM` (`$53A2`, called
directly from `ACTUALIZAR_DESTELLO_ITEMS`): does NOT move anything,
it only computes whether the item's current position falls inside
the visible screen window and, if so, the VRAM address (D/E)
where to draw it.

`CONSULTAR_LOSETA_LIBRE_DIRECCION` (`$5414`) treats as **walkable**
every tile type except 0 (normal wall/floor), 7 (tank track), 8
(power line) and 10 (plane track) — meaning these items only move
over tiles "with special decoration" (balls, arrows, trapdoors...),
never over plain flat corridor. Consistent with being entities of the
item subsystem, not Pac-Man/ghost in the main engine's sense.

## 6. The 3 active item types

All 3 share the same table format (7 bytes/entry) and use
`MOTOR_MOVIMIENTO_ITEM` to move, but each has its own handler, sprite
table, and — above all — its own **effect on reaching its spot**.

### 6.1 `HNDLR_PELMAZOIDE` — ghosts (`TABLA_ITEMS_PELMAZOIDE`, up to 8 active, `$51FE`)

The only one of the 3 that **truly chases**: it computes a "target
point" (`PUNTO_REFERENCIA_CAMARA`) as `camera_position + (16, 24)`
(offsets `+8`/`+16` on column/row, modulo 128) — that is, a point
fixed relative to the visible window, not Pac-Man's exact position.
With an "inverted" special mode active (power ball), the reference
point is used **negated**: ghosts flee instead of chasing. The number
of active ghosts for this level comes from
`REGISTRO_NIVEL_CONTADOR_PELMAZOIDES` (a field in the level register).

Animation: `TABLA_ANIMACION_PELMAZOIDE`, 2 sprites per direction
(alternated by a phase index 0-3), with an alternate variant
(+20 bytes) when the "vulnerable" special mode is active and the
remaining time indicates it's time to blink. After drawing, it calls
`ACTIVAR_EFECTO_ITEM` to check collision with Pac-Man at that same
position (§8).

### 6.2 `HNDLR_MARICOCO` — the ladybug (`TABLA_ITEMS_MARICOCO`, up to 2 active, `$5487`)

Sprites confirmed by the user (the game's original player):
`SPR39_MARIQUITA_DER`/`SPR37_..._ABAJO`/`SPR38_..._ARRIBA`. Its
effect: **regenerates already-eaten balls**. Every frame, if its
position and the camera's are tile-aligned, it checks the tile
beneath it: if it is one of `suelo_sin_bola_1/2/3` (ball already
eaten, indices 63-65), it's marked as a candidate to regenerate. On
moving there (via `MOTOR_MOVIMIENTO_ITEM`) and being confirmed
inside the visible window, it **rewrites the tile as
`suelo_con_bola`** (45-47), decrements `CONTADOR_BOLAS_COMIDAS` (a
ball is pending again) and queues the redraw with
`EVENTO_SONIDO_PENDIENTE=5`. After the first time it's drawn, it sets
`(IX+2)=1` — from then on it's **"planted"**: it stops recomputing
direction/chasing anything, it just stays still.

### 6.3 `HNDLR_REGPUNANTOSO` — the "repugnantoso" (`TABLA_ITEMS_REGPUNANTOSO`, up to 8 active, `$5574`)

Confirmed sprites: `SPR45-53_REPUGNANTE_DER/ABAJO/ARRIBA` (catalog
name: "steamroller"). Structure identical to the ladybug, but with
the **opposite** effect: it looks for un-eaten normal balls (indices
45-47) and turns them into **stuck/fixed balls** (48-50) — it is the
handler that "plants" new stuck balls on the map (freeing them again
is the job of the "tool" special mode, `HNDLR_BOLITA_CLAVADA`,
§4). Unlike the ladybug, it sets `(IX+2)=2` **right on entering** the
loop (not at the end) and does NOT touch `CONTADOR_BOLAS_COMIDAS`
when planting — planting a stuck ball doesn't change how many balls
are left to eat, it only "freezes" them until they're freed. Uses
`EVENTO_SONIDO_PENDIENTE=6`.

Both (`HNDLR_MARICOCO`/`HNDLR_REGPUNANTOSO`) use the same helper
`MAPEAR_COORDENADA_A_DIRECCION_LOCAL` (an independent copy of the
`MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA` formula) — it is one of the 5
places where the real level-13 ball-counter bug of the original v1.0
lived (`$FC60` → `$FC50`, fixed in the v2.0 CAS/ROM, see
`FINDINGS.md`).

## 7. Tank/plane track and the "flash" queue: warning, blink, points

`TABLA_PISTA_TANQUE_AVION` (`$2C2E`, 3 entries × 2 bytes, working
RAM) holds the active track positions — filled by
`REGISTRAR_PISTA_TANQUE_AVION` (out of scope for this manual). Two
different consumers:

- **Real drawing**: the loop at the end of `MOTOR_MOVIMIENTO_COLISION`
  (§3, step 8) decodes each entry and calls `MOTOR_ACTORES`
  directly.
- **Proximity warning**: `AVISAR_PROXIMIDAD_PISTA` (`$566A`) decodes
  the same entries but only to check whether Pac-Man is
  inside an **asymmetric** margin around the track (column
  [-4,+12), row [-8,+20) — a wider detection zone than the tile
  itself, to warn BEFORE stepping on it). If it matches, it calls
  `ARMAR_AVISO_DESTELLO` and sets `EVENTO_SONIDO_PENDIENTE=7`.

`ARMAR_AVISO_DESTELLO` (`$56CA`) is a pool of 4 slots
(`TABLA_RANURAS_AVISO`) that arms a "flash" animation — each
caller passes a byte that is the **entry offset** inside
`ITEM_TABLE_EFECTOS_DESTELLO` (3 tile sequences with an `$FF`
sentinel, not a generic counter), which lets each event enter at a
different point of the same sequence (the full long animation, or
just the short "closing" part). `ACTUALIZAR_DESTELLO_ITEMS` (always
called, every frame, from `MOTOR_MOVIMIENTO_COLISION`) walks the 4
slots and draws the corresponding frame with `MOTOR_ACTORES`.

**Identity of the 3 sequences** (cross-checked against
`data/tiles/*.til`): A = right arrow + closing + power line; B =
(undeciphered stretch) + cycle of the 4 item/power-up icons (plane
track/floor item/power ball/hippo) + closing; C = tool item +
closing + tank track. Strong hypothesis, not visually confirmed: it
is a celebration "flash" that draws real catalog icons with the
sprite engine, not a made-up decorative animation — sequence B in
particular cycles through exactly the 4 power-up icons when a
special mode activates.

**Undeciphered**: 5 bytes at the junction of sequences A/B (offset
40-44, `$0F,$8D,$0E,$0D,$0F`, don't fit the "repeated tile" pattern
of the rest) and a repeated 24-byte pattern at the start of
sequence B (`$03,$00,$06,$80` ×6) — see `FINDINGS.md`.

## 8. `ACTIVAR_EFECTO_ITEM` — what happens when stepping on a special item

Called from the 3 handlers in §6 after drawing each item (also,
under the same semantic name, from the power ball/hippo/tool
tile-type handler — not to be confused: this documents the
moving-item version). First filter: if a special mode is already
active, it doesn't repeat the effect (avoids re-triggering while it
lasts). Second filter: a fixed VRAM position window (row
[50,62), column [60,68) — "near the center of the screen") outside
of which it delegates directly to `AVISAR_PROXIMIDAD_PISTA` as a
fallback.

Inside the window, depending on whether a special mode is already in
progress:

- **No special mode** (or mode 3/tool): if the item isn't already
  consumed and there's no demo/cycle in progress, it activates the
  corresponding special mode — duration 40 frames if it comes from
  the "mode 3" context, 45 frames if the item is the hippo — arms
  the flash warning, fires `EVENTO_SONIDO_PENDIENTE=8` and
  **actively waits** (polling loop) for the sound manager to consume
  it before marking the final event (13).
- **Power ball (1) or hippo (2) mode already active**: if the item
  isn't already consumed, it adds points (`DIBUJAR_MARCADOR_PUNTOS`,
  with the exact points table depending on whether it's the first or
  a later hit) and sets `EVENTO_SONIDO_PENDIENTE=7`.

## 9. Relevant state variables (working RAM, `$2Cxx`)

Already with real names (see `FLUJO_PROGRAMA.md` §6 for the full
table of the main engine's shared variables); the ones most cited in
this manual:

| Variable | What it is |
|---|---|
| `DIRECCION_DE_MOVIMIENTO` | final direction decided this frame (bitmask) |
| `DIRECCION_SIN_PROCESAR` | raw direction read from `LEER_ENTRADA`, before filtering |
| `FLAG_DIRECCION_NUEVA` | press edge (new input after release) |
| `DIRECCION_FORZADA` | "sticky" override triggered by arrows/`CONSULTAR_LOSETA_LIBRE_DIRECCION` |
| `MODO_ESPECIAL_ACTIVO` | timer of the special mode in progress (0 = none) |
| `MODO_ESPECIAL` | ID of the current special mode (1=power ball, 2=hippo, 3=tool, 8/9=tank/plane) |
| `MODO_ESPECIAL_CUENTA_ATRAS` | special mode duration countdown |
| `MODO_ESPECIAL_FLAG` | "inverted camera" flag (ghosts flee instead of chasing) |
| `PUNTO_REFERENCIA_CAMARA` | ghosts' target point, camera+(16,24) |
| `SELECTOR_SPRITE_COMECOCOS` | Pac-Man's animation frame (not scroll, see §3) |
| `CACHE_COLUMNA_LOSETA`/`CACHE_TIPO_LOSETA` | cache of the last tile-type lookup |
| `CONTADOR_BOLAS_COMIDAS` | balls eaten this level (read by `VERIFICAR_FIN_NIVEL`) |
| `EVENTO_SONIDO_PENDIENTE` | index of the sound effect to trigger (see `manual_driver_sonido.md` §7) |

## 10. To dig further

- `FINDINGS.md` — every section related to the collision engine and
  the 3 item types, in chronological order, with the full reasoning
  behind each discovery.
- `FLUJO_PROGRAMA.md` §5.2/§5.3 — a shorter summary, in the context
  of the game's full flow (actor engine, HUD, menu...).
- Genuinely open points, in case someone wants to continue:
  - The right/down (+4) vs left/up (-1) asymmetry in
    `CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION` (§3).
  - The 5 undeciphered bytes at the junction of sequences A/B of
    `ITEM_TABLE_EFECTOS_DESTELLO`, and the repeated 24-byte pattern
    at the start of sequence B (§7).
  - The tile-type handlers not detailed in this manual
    (`HNDLR_PISTA_COCOTANQUE`, `HNDLR_PISTA_COCONAVE`, `HNDLR_ITEM_SUELO`,
    `HNDLR_BOLA_PODER`, `HNDLR_HIPODOSO`, `HNDLR_EXCAVATOFONO`, the 3
    trapdoor handlers) — mechanics already traced in `FINDINGS.md`,
    pending consolidation here if needed.
