; Reconstrucción, comentarios y etiquetas de este fichero: Rafael Eduardo Martín Candial

START:
    LD SP, $FFF0
; --- Tabla de saltos (API publica del motor), 12 entradas JP --
; Direcciones ESTATICAS tal cual el binario original (verificado
; byte a byte contra el desensamblado en FISICO\ORI\MADMIX1.ASM).
; La primera entrada es esta misma JP (START cae directamente en
; ella, no hay una JP duplicada como se penso en un borrador
; anterior).
JT_INICIO:                                     JP INICIO                                     ; arranque real del motor, nunca retorna (confirmado)
JT_MOTOR_ACTORES:                              JP MOTOR_ACTORES                              ; motor de actores/render sub-pixel de personajes (confirmado, ver mas abajo)
JT_RESET_CONTADOR_ACTORES:                     JP RESET_CONTADOR_ACTORES                     ; XOR A / LD ($8437),A / RET (confirmado)
JT_WAIT_VBLANK:                                JP WAIT_VBLANK                                ; confirmado
JT_ACTIVAR_INTERRUPCION:                       JP ACTIVAR_INTERRUPCION_MODO_1                ; identificado, ver mas abajo; INICIO lo llama directo al empezar
JT_LEER_ENTRADA:                               JP LEER_ENTRADA                               ; identificado, ver mas abajo
JT_DIBUJAR_MARCADOR_PUNTOS:                    JP DIBUJAR_MARCADOR_PUNTOS                    ; identificado, ver mas abajo
JT_GESTIONAR_SCROLL:                           JP GESTIONAR_SCROLL                           ; identificado, ver mas abajo
JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM:    JP REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM    ; identificado, ver mas abajo
JT_REDIBUJAR_LOSETA_BUFFER_VRAM:               JP REDIBUJAR_LOSETA_BUFFER_VRAM               ; confirmado
JT_MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA:          JP MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA           ; confirmado
JT_CONSULTAR_TIPO_LOSETA:                      JP CONSULTAR_TIPO_LOSETA                      ; confirmado

    ; Hueco $8427-$8430 (9 bytes, no 2 -- corregido tras arreglar el
    ; ORG de la cabecera, ver arriba): todo ceros en el original,
    ; probablemente relleno. El primer byte (MODO_ENTRADA) se reutiliza
    ; en RAM como selector de teclado/joystick para LEER_ENTRADA.
MODO_ENTRADA:
    DS $8430-$, $00

FRAME_FLAG: DB 0                  ; semaforo real de ENTRADA_INTERRUPCION_VBLANK, direccion confirmada 0x8430

    ; Hueco $8431-$8440 (15 bytes): CONFIRMADO todo ceros en el
    ; original (desensamblado real via Z80Dasm.exe). Es zona de
    ; variables en RAM en tiempo de ejecucion (varias direcciones
    ; de aqui dentro, como $8437/$843A/$843E/$843F, se usan como
    ; scratch en MOTOR_ACTORES mas abajo), no relleno de fichero.
    DS $8440-$, $00

; ==============================================================
;  JT_MOTOR_ACTORES (0x8440) -- MOTOR DE ACTORES, transcrito byte a byte
;  completo (0x8440-0x87FF) desde el desensamblado fiable de
;  Z80Dasm.exe -begin 7 -offset 8400. Ver FINDINGS.md, seccion
;  "JT_MOTOR_ACTORES (0x8440-0x8800)" para el analisis narrativo completo,
;  y "Estudio... familia JTS2_" para el detalle del renombrado de
;  todas las etiquetas internas (JTS2_xxxx -> nombres reales de abajo).
;  Resumen de lo que SI se entiende:
;   - Entrada: valida un rango de coordenadas (guardas contra
;     10/64/4/116) antes de continuar; si esta fuera de rango,
;     vuelve pronto (posible filtro "esta este actor en pantalla").
;   - $8437 = contador de actores activos (confirmado, ver
;     RESET_CONTADOR_ACTORES y el volcado de RAM en vivo). Aqui se INCREMENTA
;     (0x8529) al crear un actor nuevo.
;   - IX = $92E3 + ($8437_antes_de_incrementar) * 12: el array de
;     actores activos es de verdad esta tabla, con registros de
;     12 bytes. Campos usados: IX+0/1=posicion pantalla (HL),
;     IX+2/3=direccion buffer (resultado de CALCULAR_DIRECCION_MASCARA_ACTOR),
;     IX+4=contador/tamaÃ±o, IX+5/6=puntero CURSOR de salida en RAM
;     baja (ver mas abajo, direccion CORREGIDA -- antes se penso
;     que era "fuente de graficos", es al reves), IX+7/8/9=tres
;     bytes de TABLA_MASCARA_RECORTE_BORDE ($87FB) indexada por
;     posicion horizontal.
;   - CORREGIDO: CAPTURAR_MASCARAS_ACTOR copia DESDE el buffer de
;     CALCULAR_DIRECCION_MASCARA_ACTOR (IX+2/3, calculado a partir de la posicion del
;     actor) HACIA el cursor en RAM baja ($0500 en adelante,
;     IX+5/6/$8438) -- NO al reves. El truco esta en el EX DE,HL
;     justo antes del LDI: LDI copia (HL)->(DE), y tras el EX,
;     HL=buffer y DE=cursor. NUEVO (cruzado con el hallazgo "Zona
;     0xDC00" de TABLA_RLE_MARCO_CARAMELO/madmix1_body.asm:4440): ese buffer en
;     $DC00+ es la MISMA tabla que sostiene el marco decorativo, leida
;     ahi como pares de MASCARAS AND/OR de composicion de sprite
;     contra el fondo -- asi que lo que hace esta rutina es CAPTURAR
;     (prefetch) las mascaras que le tocan a cada actor de este frame
;     hacia el cursor, no "guardar el fondo para restaurarlo" como se
;     penso en un principio. Explica por que buscar sus bytes en la
;     ROM (MADMIX1.BIN, MADMIX.SCR, incluso el .dsk completo) no
;     encontro nada aparte -- no es un recurso estatico propio, reusa
;     la tabla del marco. El cursor ($8438) avanza cada vez que se
;     crea un actor, extrayendo 3 bytes de cada bloque de 32 desde
;     el buffer hasta agotar IX+4 bloques.
;   - CONTINUAR_CAPTURA_MASCARAS_ACTORES (0x86BB) recorre el array de actores hacia atras
;     (paso de -12 bytes) decrementando $8437 como contador de
;     iteracion -- una carga de recursos repartida en varias
;     llamadas (cooperativa), no de una sola vez.
;   - Renderizado: dos rutinas casi identicas (DIBUJAR_FILA_DESPLAZADA_DERECHA en
;     0x85C1 con desplazamiento a la derecha, DIBUJAR_FILA_DESPLAZADA_IZQUIERDA en
;     0x8624 con desplazamiento a la izquierda) hacen scroll de
;     sub-pixel bit a bit sobre franjas de 32 bytes de paso,
;     usando el SP como puntero rapido (intercambiando la pila via
;     EXX) para mezclar con AND/OR contra el fondo. Selecionadas
;     via JP (IY) segun la posicion del actor.
;   - COMPONER_ACTORES_EN_BUFFER (0x8779) es otra pasada distinta sobre
;     el mismo array, con codigo automodificable (escribe los
;     campos IX+7/8/9 directamente en operandos de instrucciones
;     mas adelante) y un patron de mezcla OR mas simple (sin
;     desplazamiento de bits) en 6 iteraciones -- probablemente
;     dibuja SIN el suavizado de sub-pixel. Termina reseteando
;     $8437 a 0. SIN CALL/JP confirmado en el codigo ya transcrito --
;     su llamador real sigue sin identificar (ver FINDINGS.md).
;   - INVERTIR_BITS_PATRON_ACTOR (0x86FA) y INVERTIR_ORDEN_BYTES_PATRON_ACTOR
;     (0x873A): dos rutinas auxiliares llamadas condicionalmente segun
;     bits de un valor D calculado a partir de $8436 y (HL). HIPOTESIS
;     (sin confirmar en vivo): juntas completan un volteo horizontal
;     del patron del actor -- la primera invierte el ORDEN DE LOS BITS
;     de cada byte (RLC/RRA x8, el truco clasico), la segunda invierte
;     el ORDEN DE LOS BYTES de la fila; mismo convenio bit7=volteo
;     horizontal ya confirmado en SELECTOR_SPRITE_COMECOCOS.
;  Direcciones estaticas confirmadas (no se ha necesitado PHASE
;  para nada de esto, ver hallazgo del volcado de RAM en vivo).
; ==============================================================
MOTOR_ACTORES:                  ; objetivo real de JT_MOTOR_ACTORES (0x8440)
    BIT 7, E                    ; bit7 de la columna (E) como filtro previo de entrada
    RET NZ                      ; activo -> ni siquiera intenta dibujar este actor
    PUSH AF
    LD A, ($8437)                ; contador de actores activos
    CP 10                        ; 10 = maximo de actores activos simultaneos (tabla IX de 12 bytes/registro)
    JR NC, .DESCARTAR_ACTOR
    LD A, B
    CP 64                        ; 64 = entradas de PTR_TABLA_SPRITES (limite de indice de sprite valido)
    JR NC, .DESCARTAR_ACTOR
    LD A, E
    CP 4                         ; columna minima visible (descarta actor demasiado a la izquierda)
    JR NC, .COMPROBAR_LIMITE_VERTICAL
.DESCARTAR_ACTOR:
    POP AF
    RET
.COMPROBAR_LIMITE_VERTICAL:
    CP 116                       ; columna maxima visible (descarta actor demasiado a la derecha)
    JR NC, .DESCARTAR_ACTOR
    POP AF
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    PUSH BC
    BIT 5, A
    LD HL, $843E                 ; $843E = limite vertical de recorte de camara (scratch en RAM)
    LD (HL), 144                 ; una de dos mitades posibles segun bit5 de A (144/176) -- uso exacto sin confirmar
    JR Z, .CONTINUAR_TRAS_SELECCION_MITAD
    LD (HL), 176
.CONTINUAR_TRAS_SELECCION_MITAD:
    SLA E
    RES 0, D
    LD ($8431), DE
    LD A, ($8437)
    LD L, A
    LD H, $00
    ADD HL, HL
    ADD HL, HL
    LD C, L
    LD B, H
    ADD HL, HL                   ; HL = ($8437 antes de incrementar) * 12 -- tamano del registro de actor
    ADD HL, BC
    LD BC, $92E3                 ; base del array de actores (12 bytes/registro, ver cabecera de la rutina)
    ADD HL, BC
    PUSH HL
    POP IX                       ; IX = registro del actor actual dentro del array
    LD A, E
    LD HL, TABLA_MASCARA_RECORTE_BORDE
    AND $F8
    RRCA
    RRCA
    RRCA
    ADD A, L
    LD L, A
    LD A, (HL)
    LD (IX+$07), A               ; IX+7/8/9 = 3 bytes de TABLA_MASCARA_RECORTE_BORDE, indexados por columna
    INC HL
    LD A, (HL)
    LD (IX+$08), A
    INC HL
    LD A, (HL)
    LD (IX+$09), A
    LD HL, $843E
    LD A, D
    CP (HL)
    JR C, .CONTINUAR_TRAS_CLIP_VERTICAL
    XOR A
.CONTINUAR_TRAS_CLIP_VERTICAL:
    LD C, E
    ADD A, 16                    ; +16 filas de compensacion antes de calcular la direccion/mascara del actor
    LD B, A
    CALL CALCULAR_DIRECCION_MASCARA_ACTOR
    LD (IX+$02), L               ; IX+2/3 = direccion del buffer de mascaras (CALCULAR_DIRECCION_MASCARA_ACTOR)
    LD (IX+$03), H
    POP BC
    LD L, B
    LD H, $00
    ADD HL, HL
    ADD HL, HL
    LD BC, PTR_TABLA_SPRITES  ; RESUELTO: tabla de 64 punteros a sprites de personajes (ver mas abajo)
    ADD HL, BC
    LD C, (HL)
    INC HL
    LD B, (HL)
    LD ($8433), BC               ; $8433 = puntero al sprite fuente de este actor
    INC HL
    PUSH HL
    LD A, (HL)
    AND $07                      ; bits 0-2 = fotograma/direccion de animacion del sprite (0-7)
    LD ($843F), A
    LD A, 3                      ; constante fija almacenada en $8435 (proposito exacto sin confirmar)
    LD ($8435), A
    INC HL
    LD A, (HL)
    LD ($8436), A
    LD L, $00
    LD E, A
    LD A, ($8432)
    LD D, A
    ADD A, E
    JR NC, .CALCULAR_RECORTE_CAMARA
    LD H, A
    LD A, E
    SUB H
    LD L, A
    ADD A, A
    ADD A, L
    ADD A, A
    LD L, A
    LD A, H
    JR .CONTINUAR_TRAS_RECORTE
.CALCULAR_RECORTE_CAMARA:
    PUSH HL
    LD HL, $843E
    SUB (HL)
    POP HL
    LD H, A
    LD A, E
    JR C, .CONTINUAR_TRAS_RECORTE
    SUB H
    JR Z, .DESCARTAR_ACTOR_FUERA_DE_CAMARA
    JR NC, .CONTINUAR_TRAS_RECORTE
.DESCARTAR_ACTOR_FUERA_DE_CAMARA:
    POP HL
    POP AF
    JP SALIR_MOTOR_ACTORES
.CONTINUAR_TRAS_RECORTE:
    LD H, $00
    ADD HL, BC
    LD (IX+$00), L               ; IX+0/1 = posicion final en pantalla del actor
    LD (IX+$01), H
    SRL A
    JR NZ, .CONTINUAR_TRAS_LIMITAR_FILAS
    INC A
.CONTINUAR_TRAS_LIMITAR_FILAS:
    LD (IX+$04), A               ; IX+4 = numero de filas/bloques de 32 bytes a dibujar
    LD HL, $8437
    LD A, (HL)
    AND A
    JR NZ, .CONTINUAR_CURSOR_ACTOR
    LD DE, $0500                 ; $0500 = base del cursor en RAM baja (primer actor de este frame)
    JR .GUARDAR_CURSOR_ACTOR
.CONTINUAR_CURSOR_ACTOR:
    LD DE, ($8438)                ; cursor heredado del actor anterior (avanza secuencialmente entre actores)
.GUARDAR_CURSOR_ACTOR:
    LD (IX+$05), E               ; IX+5/6 = cursor de salida de este actor en RAM baja
    LD (IX+$06), D
    INC (HL)
    CALL CAPTURAR_MASCARAS_ACTOR
    LD A, ($8436)
    ADD A, A
    LD B, A
    POP HL
    POP AF
    AND $C0                      ; bits 6-7 = flags de volteo (orden de bits / orden de bytes)
    LD D, A
    LD A, (HL)
    AND $C0
    XOR D
    LD D, A
    AND $80                      ; bit7 = volteo del orden de los bits dentro de cada byte
    JR Z, .CONTINUAR_TRAS_INVERSION_BITS
    XOR (HL)
    LD (HL), A
    CALL INVERTIR_BITS_PATRON_ACTOR
.CONTINUAR_TRAS_INVERSION_BITS:
    LD A, D
    AND $40                      ; bit6 = volteo del orden de los bytes de la fila
    JR Z, .CONTINUAR_TRAS_INVERSION_BYTES
    XOR (HL)
    LD (HL), A
    CALL INVERTIR_ORDEN_BYTES_PATRON_ACTOR
.CONTINUAR_TRAS_INVERSION_BYTES:
    LD A, ($8431)
    BIT 7, (HL)
    LD IY, DIBUJAR_FILA_DESPLAZADA_DERECHA    ; variante por defecto: desplazamiento sub-pixel a la derecha
    JR Z, .CONTINUAR_TRAS_ELEGIR_DIRECCION
    LD L, A
    LD A, ($843F)
    AND A
    LD A, L
    JR Z, .CONTINUAR_TRAS_ELEGIR_DIRECCION
    CPL
    LD L, A
    LD IY, DIBUJAR_FILA_DESPLAZADA_IZQUIERDA  ; si procede, cambia a la variante de desplazamiento a la izquierda
    LD A, ($843F)
    ADD A, L
    INC A
.CONTINUAR_TRAS_ELEGIR_DIRECCION:
    AND $07                       ; bits 0-2 = cantidad de desplazamiento sub-pixel (0-7)
    EXX
    LD C, A
    EXX
    LD A, (IX+$04)
    LD L, (IX+$00)
    LD H, (IX+$01)
    LD ($843C), HL
    LD L, (IX+$02)
    LD H, (IX+$03)
.BUCLE_DIBUJAR_ACTOR:
    EX AF, AF'
    DI
    LD ($843A), SP                ; intercambia SP para leer las 3 mascaras del cursor como si fuera pila
    LD SP, ($843C)
    POP DE
    POP BC
    EXX
    POP HL
    LD ($843C), SP
    LD SP, ($843A)
    EI
    LD A, C
    LD B, A
    AND A
    EXX
    LD A, B
    JP (IY)                       ; salta a la variante de dibujado (derecha/izquierda) elegida arriba

; --- DIBUJAR_FILA_DESPLAZADA_DERECHA / DIBUJAR_FILA_DESPLAZADA_IZQUIERDA: dos variantes casi identicas
; de dibujado con desplazamiento de bits sub-pixel (derecha / izquierda) ---
MEZCLAR_Y_AVANZAR_FILA_ACTOR:
    LD B, A                      ; byte central del sprite, ya desplazado, guardado para mezclar el tercer byte
    LD A, (HL)
    AND C                        ; C/D/E = mascaras de recorte (fondo a conservar) de cada uno de los 3 bytes
    EXX
    OR H                         ; H'/L'/B = bytes del sprite ya desplazados (mitad "rapida" via EXX)
    EXX
    LD (HL), A
    DEC L
    LD A, (HL)
    AND D
    EXX
    OR L
    EXX
    LD (HL), A
    DEC L
    LD A, (HL)
    AND E
    OR B
    LD (HL), A
    LD BC, 32                    ; 32 = paso de fila en VRAM/buffer (avanza a la fila siguiente del actor)
    ADD HL, BC
    EX AF, AF'
    DEC A
    JP NZ, MOTOR_ACTORES.BUCLE_DIBUJAR_ACTOR
    JP SALIR_MOTOR_ACTORES

DIBUJAR_FILA_DESPLAZADA_DERECHA:
    JR Z, .ESCRIBIR_FILA1         ; B=0 (sin desplazamiento sub-pixel) -> escribe directamente
    EX DE, HL
    EXX
.DESPLAZAR_SUBPIXEL_FILA1:
    AND A
    RRA                           ; desplaza a la derecha bit a bit (B veces) el sprite entre A/L/H y C/H'/L'
    RR L
    RR H
    EXX
    SCF
    RR L
    RR H
    RR C
    EXX
    DJNZ .DESPLAZAR_SUBPIXEL_FILA1
    EXX
    EX DE, HL
.ESCRIBIR_FILA1:
    LD B, A
    LD A, (HL)
    AND E                         ; mezcla el sprite ya desplazado con el fondo via las mascaras C/D/E
    OR B
    LD (HL), A
    INC L
    LD A, (HL)
    AND D
    EXX
    OR L
    EXX
    LD (HL), A
    INC L
    LD A, (HL)
    AND C
    EXX
    OR H
    EXX
    LD (HL), A
    LD BC, 32                     ; 32 = paso de fila en VRAM/buffer, avanza a la fila siguiente
    ADD HL, BC
    DI
    LD ($843A), SP                ; vuelve a leer las 3 mascaras del cursor via SP (misma tecnica que arriba)
    LD SP, ($843C)
    POP DE
    POP BC
    EXX
    POP HL
    LD ($843C), SP
    LD SP, ($843A)
    EI
    LD A, C
    LD B, A
    AND A
    EXX
    LD A, B
    JR Z, .CONTINUAR_FILA2         ; repite el mismo desplazamiento+mezcla para la segunda fila del par
    EX DE, HL
    EXX
.DESPLAZAR_SUBPIXEL_FILA2:
    AND A
    RRA
    RR L
    RR H
    EXX
    SCF
    RR L
    RR H
    RR C
    EXX
    DJNZ .DESPLAZAR_SUBPIXEL_FILA2
    EXX
    EX DE, HL
.CONTINUAR_FILA2:
    JP MEZCLAR_Y_AVANZAR_FILA_ACTOR

DIBUJAR_FILA_DESPLAZADA_IZQUIERDA:
    JR Z, .ESCRIBIR_FILA1         ; B=0 (sin desplazamiento sub-pixel) -> escribe directamente
    EX DE, HL
    EXX
.DESPLAZAR_SUBPIXEL_FILA1:
    AND A
    RL H                          ; desplaza a la izquierda bit a bit (B veces) el sprite entre H/L/A y C/H'/L'
    RL L
    RLA
    EXX
    SCF
    RL C
    RL H
    RL L
    EXX
    DJNZ .DESPLAZAR_SUBPIXEL_FILA1
    EXX
    EX DE, HL
.ESCRIBIR_FILA1:
    LD B, A
    LD A, (HL)
    AND E                         ; mezcla el sprite ya desplazado con el fondo via las mascaras C/D/E
    OR B
    LD (HL), A
    INC L
    LD A, (HL)
    AND D
    EXX
    OR L
    EXX
    LD (HL), A
    INC L
    LD A, (HL)
    AND C
    EXX
    OR H
    EXX
    LD (HL), A
    LD BC, 32                     ; 32 = paso de fila en VRAM/buffer, avanza a la fila siguiente
    ADD HL, BC
    DI
    LD ($843A), SP                ; vuelve a leer las 3 mascaras del cursor via SP (misma tecnica que arriba)
    LD SP, ($843C)
    POP DE
    POP BC
    EXX
    POP HL
    LD ($843C), SP
    LD SP, ($843A)
    EI
    LD A, C
    LD B, A
    AND A
    EXX
    LD A, B
    JR Z, .CONTINUAR_FILA2         ; repite el mismo desplazamiento+mezcla para la segunda fila del par
    EX DE, HL
    EXX
.DESPLAZAR_SUBPIXEL_FILA2:
    AND A
    RL H
    RL L
    RLA
    EXX
    SCF
    RL C
    RL H
    RL L
    EXX
    DJNZ .DESPLAZAR_SUBPIXEL_FILA2
    EXX
    EX DE, HL
.CONTINUAR_FILA2:
    JP MEZCLAR_Y_AVANZAR_FILA_ACTOR

; --- CAPTURAR_MASCARAS_ACTOR (0x8687) -- CORREGIDO: copia DESDE el buffer
; IX+2/3 (CALCULAR_DIRECCION_MASCARA_ACTOR, depende de la posicion del actor) HACIA
; el cursor IX+5/6 en RAM baja ($0500+), 3 bytes de cada bloque de
; 32, IX+4 veces (el EX DE,HL antes del LDI invierte lo que parece
; a primera vista: LDI copia (HL)->(DE), y tras el EX, HL=buffer,
; DE=cursor). Avanza y guarda el cursor en $8438 y el propio IX en
; IX_ACTOR_GUARDADO para CONTINUAR_CAPTURA_MASCARAS_ACTORES. El cursor es un buffer de SALIDA,
; no el origen del grafico -- ver nota grande en la cabecera de
; MOTOR_ACTORES. ---
CAPTURAR_MASCARAS_ACTOR:
    LD L, (IX+$05)
    LD H, (IX+$06)
    LD E, (IX+$02)
    LD D, (IX+$03)
    EX DE, HL
    LD A, (IX+$04)
    LD BC, $00FF                 ; C=$FF para que los 3 DEC de LDI no hagan borrow hacia B (B debe seguir en 0)
.BUCLE_CAPTURA:
    LDI                          ; copia 3 bytes (mascara AND/OR/AND) del bloque de 32 actual
    LDI
    LDI
    LD C, 29                     ; 29: junto a los 3 bytes ya copiados suma 32 (paso de fila de la tabla origen)
    ADD HL, BC
    LDI
    LDI
    LDI
    LD C, 29
    ADD HL, BC
    DEC A
    JP NZ, .BUCLE_CAPTURA
    LD ($8438), DE
    LD (IX_ACTOR_GUARDADO), IX
    RET
IX_ACTOR_GUARDADO: DW 0

; --- CONTINUAR_CAPTURA_MASCARAS_ACTORES (0x86BB): recorre el array de actores hacia
; atras (paso -12) usando $8437 como contador, repartiendo la
; carga de graficos en varias llamadas (cooperativo) ---
CONTINUAR_CAPTURA_MASCARAS_ACTORES:
    LD IX, (IX_ACTOR_GUARDADO)
.SIGUIENTE_ACTOR:
    LD HL, $8437
    LD A, (HL)
    DEC (HL)
    AND A
    RET Z
    LD L, (IX+$05)
    LD H, (IX+$06)
    LD E, (IX+$02)
    LD D, (IX+$03)
    EX DE, HL
    LD A, (IX+$04)
    LD BC, $00FF                 ; C=$FF para que los 3 DEC de LDI no hagan borrow hacia B (B debe seguir en 0)
.BUCLE_CAPTURA:
    EX DE, HL
    LDI                          ; copia 3 bytes del bloque de 32 actual (mismo patron que CAPTURAR_MASCARAS_ACTOR)
    LDI
    LDI
    EX DE, HL
    LD C, 29                     ; 29: junto a los 3 bytes ya copiados suma 32 (paso de fila de la tabla origen)
    ADD HL, BC
    EX DE, HL
    LDI
    LDI
    LDI
    EX DE, HL
    LD C, 29
    ADD HL, BC
    DEC A
    JP NZ, .BUCLE_CAPTURA
    LD DE, $FFF4                 ; $FFF4 = -12: retrocede un registro de actor completo en el array
    ADD IX, DE
    JR .SIGUIENTE_ACTOR

; --- INVERTIR_BITS_PATRON_ACTOR (0x86FA): invierte el orden de los 8
; bits de cada byte (RLC/RRA x8 repetido, el truco clasico de espejo
; bit a bit), cuenta atras en $842F, luego LDIR -- llamada condicional
; segun bit7 de $8436. HIPOTESIS: la mitad "bit a bit" de un volteo
; horizontal del patron del actor (ver INVERTIR_ORDEN_BYTES_PATRON_ACTOR
; para la mitad "orden de bytes"); proposito exacto sin confirmar en
; vivo todavia. ---
INVERTIR_BITS_PATRON_ACTOR:
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    LD B, 48                     ; 48 = tope de bloques a procesar (limite superior, no necesariamente alcanzado)
    LD A, ($8435)
    LD C, A
    LD HL, ($8433)
.BUCLE_BLOQUES:
    PUSH BC
    PUSH HL
    LD B, C                      ; B = numero real de bytes del bloque actual (desde $8435)
    PUSH BC
    LD DE, $842F
.BUCLE_INVERTIR_BYTE:
    LD C, (HL)
    RLC C                        ; RLC/RRA x8: mueve cada bit de C a A en orden inverso (espejo bit a bit)
    RRA
    RLC C
    RRA
    RLC C
    RRA
    RLC C
    RRA
    RLC C
    RRA
    RLC C
    RRA
    RLC C
    RRA
    RLC C
    RRA
    LD (DE), A                   ; guarda el byte ya invertido, avanzando DE hacia atras ($842F en adelante)
    INC HL
    DEC DE
    DJNZ .BUCLE_INVERTIR_BYTE
    POP BC
    POP HL
    INC DE
    LD B, $00                    ; B=0, C conserva el numero de bytes del bloque -> BC = contador para el LDIR
    EX DE, HL
    LDIR                         ; copia el bloque ya invertido ($842F+) de vuelta sobre el original
    EX DE, HL
    POP BC
    DJNZ .BUCLE_BLOQUES
    JR SALIR_MOTOR_ACTORES

; --- INVERTIR_ORDEN_BYTES_PATRON_ACTOR (0x873A): intercambia bytes entre
; dos punteros que convergen hacia el centro, mientras difieran.
; HIPOTESIS: la mitad "orden de bytes" de un volteo horizontal del
; patron del actor (ver INVERTIR_BITS_PATRON_ACTOR para la mitad "bit
; a bit"); proposito exacto sin confirmar en vivo todavia. ---
INVERTIR_ORDEN_BYTES_PATRON_ACTOR:
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    LD DE, ($8433)                ; DE = puntero HL (extremo bajo, avanza hacia el centro)
    LD A, ($8436)
    ADD A, A
    LD C, A
    LD B, $00
    LD L, C
    LD H, B
    ADD HL, HL
    ADD HL, BC
    ADD HL, DE                    ; HL = DE + ($8436 * 6) -- extremo alto inicial (avanza hacia el centro)
.COMPROBAR_CONVERGENCIA:
    LD B, $00
    LD A, ($8435)
    ADD A, A
    LD C, A                       ; BC = tamano del bloque a intercambiar (2 * $8435)
    AND A
    SBC HL, BC                    ; HL -= BC: retrocede el extremo alto un bloque
    LD A, D
    XOR H
    JR NZ, .INTERCAMBIAR_BLOQUE
    LD A, E
    XOR L
    JR Z, SALIR_MOTOR_ACTORES     ; los dos punteros coinciden exactamente -> ya converge, termina
.INTERCAMBIAR_BLOQUE:
    PUSH HL
    LD B, C
.BUCLE_INTERCAMBIO:
    LD A, (DE)                    ; intercambia byte a byte el bloque de DE (extremo bajo) con HL (extremo alto)
    LD C, (HL)
    LD (HL), A
    LD A, C
    LD (DE), A
    INC DE
    INC HL
    DJNZ .BUCLE_INTERCAMBIO
    POP HL
    LD A, D
    XOR H
    JR NZ, .COMPROBAR_CONVERGENCIA
    LD A, E
    XOR L
    JR NZ, .COMPROBAR_CONVERGENCIA
SALIR_MOTOR_ACTORES:
    POP BC
    POP DE
    POP HL
    POP AF
    RET

; --- COMPONER_ACTORES_EN_BUFFER (0x8779): segunda pasada sobre el array
; de actores, con codigo automodificable (escribe IX+7/8/9 en los 6
; operandos OPERANDO_MASCARA_*_IDA/VUELTA de abajo, en pares
; identicos 1=6/2=5/3=4 -- patron "ida y vuelta") y mezcla OR simple
; (sin sub-pixel) en 6 iteraciones. Termina reseteando $8437 a 0.
; SIN CALL/JP confirmado en el codigo ya transcrito -- llamador real
; sin identificar, ver FINDINGS.md. ---
COMPONER_ACTORES_EN_BUFFER:
    LD A, ($8437)
    AND A
    RET Z
    LD IX, $92E3                  ; mismo array/base de actores que MOTOR_ACTORES
    LD ($843A), SP
.SIGUIENTE_ACTOR:
    EX AF, AF'
    LD A, (IX+$07)                 ; IX+7/8/9 = las 3 mascaras de recorte de borde de este actor
    LD (.OPERANDO_MASCARA_A_IDA), A    ; auto-modifica los 6 operandos AND de abajo (patron "ida y vuelta")
    LD (.OPERANDO_MASCARA_A_VUELTA), A
    LD A, (IX+$08)
    LD (.OPERANDO_MASCARA_B_IDA), A
    LD (.OPERANDO_MASCARA_B_VUELTA), A
    LD A, (IX+$09)
    LD (.OPERANDO_MASCARA_C_IDA), A
    LD (.OPERANDO_MASCARA_C_VUELTA), A
    LD L, (IX+$05)                 ; SP = cursor de mascaras del actor (IX+5/6, se lee con POP igual que en MOTOR_ACTORES)
    LD H, (IX+$06)
    LD SP, HL
    LD L, (IX+$02)                 ; HL = direccion destino en el buffer (IX+2/3)
    LD H, (IX+$03)
    LD B, (IX+$04)                 ; B = numero de filas a componer para este actor (IX+4)
.BUCLE_COMPONER:
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_A_IDA:
    LD (HL), A
    INC L
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_B_IDA:
    LD (HL), A
    INC L
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_C_IDA:
    LD (HL), A
    INC H
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_C_VUELTA:
    LD (HL), A
    DEC L
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_B_VUELTA:
    LD (HL), A
    DEC L
    POP DE
    LD A, (HL)
    AND E
    OR D
.OPERANDO_MASCARA_A_VUELTA:
    LD (HL), A
    INC H
    LD A, H
    AND $06                        ; bits 1-2 de H: detecta si sigue dentro de las 3 filas de este bloque de 8
    JP NZ, .AJUSTAR_SALTO_FILA
    LD A, L
    ADD A, 32                      ; 32 = paso de fila en VRAM/buffer, igual que en el resto del motor
    LD L, A
    JR C, .AJUSTAR_SALTO_FILA
    LD A, H
    SUB 8                          ; 8 = compensa las 3 filas ya sumadas via H (vuelve a la base del bloque)
    LD H, A
.AJUSTAR_SALTO_FILA:
    DJNZ .BUCLE_COMPONER
    LD DE, 10                      ; avanza SOLO 10 bytes por actor (no 12 como en MOTOR_ACTORES/CONTINUAR_CAPTURA_MASCARAS_ACTORES)
                                    ; -- discrepancia sin explicar; coincide con que esta rutina no tiene
                                    ; llamador confirmado en el codigo ya transcrito (ver cabecera arriba)
    ADD IX, DE
    EX AF, AF'
    DEC A
    JP NZ, .SIGUIENTE_ACTOR
    LD SP, ($843A)
    XOR A
    LD ($8437), A
    RET

; TABLA_MASCARA_RECORTE_BORDE: confirmada byte a byte contra el .BIN original.
; Solo 5 bytes caben aqui antes de 0x8800 (limite ya confirmado) --
; sea cual sea el uso real de esta tabla (indexada por posicion
; horizontal AND $F8 sumada directamente, sin multiplicar -- lo
; que sugiere que en la practica solo se consultan unos pocos
; valores de indice, no las 32 entradas que en teoria permitiria
; el rango de E), estos son los bytes reales, no un relleno.
TABLA_MASCARA_RECORTE_BORDE:
    DB $00, $00, $00, $00, $77

; ==============================================================
;  0x8800-0xDDA0 -- CONFIRMADO que corre desde direcciones
;  ESTATICAS (ver volcado de memoria en vivo, FINDINGS.md). Ya no
;  se envuelve en PHASE/DEPHASE.
; ==============================================================

    ; 0x8800-0x8816 (23 bytes, valor $77 repetido = opcode LD (HL),A)
    ; + 0x8817-0x881A (4 bytes $00): no se han identificado como
    ; codigo con sentido propio (23 copias identicas de la misma
    ; instruccion de 1 byte parecen relleno/espacio no usado, no
    ; una rutina real) -- transcritos como datos crudos para no
    ; sugerir una interpretacion que no se ha verificado.
    DB $77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77
    DB $77,$77,$77,$77,$77,$77,$77,$00,$00,$00,$00

; ACTIVAR_INTERRUPCION_MODO_1 (JT_ACTIVAR_INTERRUPCION, $881B -- IDENTIFICADO): instala el vector
; de interrupcion (opcode JP + direccion de ENTRADA_INTERRUPCION_VBLANK en $0038/$0039).
; Llamado directo desde INICIO ("CALL $881B"). OJO: a diferencia de
; una version anterior (stub inventado, descartado), el original
; NO empieza con DI.
ACTIVAR_INTERRUPCION_MODO_1:
    LD     A,$C3
    LD     HL,$882A
    LD     ($0038),A
    LD     ($0039),HL
    IM     1
    EI
    RET

; --------------------------------------------------------------
;  INTERRUPCION VBLANK (ENTRADA_INTERRUPCION_VBLANK en 0x882A original, confirmado) --
;  CORREGIDA tras desensamblar este bloque: la version anterior
;  tenia 3 bugs reales (encontrados por diferencia de bytes, no
;  por sospecha): (1) faltaba un PUSH AF / POP AF simetrico
;  guardando el AF de la sombra (EX AF,AF') justo antes de los
;  PUSH HL/DE/BC/IX/IY; (2) faltaba un bloque entero de lectura de
;  estado del VDP (IN A,($99) + LD A,($10E4) + 2x OUT) justo antes
;  de restaurar AF y salir; (3) la instruccion final es RET, NO
;  RETI como se penso. Tambien CONFIRMA que "CALL $60DC" es una
;  direccion ESTATICA real (no una nota de una sesion antigua que
;  ya asumia reubicacion, como se dudaba) -- lo que sea que viva en
;  $60DC en tiempo de ejecucion (probablemente parte del bucle
;  principal de madmix_scr.asm reubicado a esa direccion) se llama
;  de verdad desde aqui cada VBLANK.
; --------------------------------------------------------------
ENTRADA_INTERRUPCION_VBLANK:
    DI
    PUSH   AF
    IN     A,($99)
    AND    A
    JP     P,.NO_ES_IRQ_VBLANK
    PUSH   HL
    PUSH   DE
    PUSH   BC
    EXX
    EX     AF,AF'
    PUSH   AF
    PUSH   HL
    PUSH   DE
    PUSH   BC
    PUSH   IX
    PUSH   IY
    CALL   GESTIONAR_FRAME
    CALL   DESPACHAR_EFECTO_SONIDO
    POP    IY
    POP    IX
    POP    BC
    POP    DE
    POP    HL
    POP    AF
    EX     AF,AF'
    EXX
    POP    BC
    POP    DE
    POP    HL
    IN     A,($99)
    LD     A,(VDP_REGISTRO1_PENDIENTE) ; RESUELTO: $10E4 es el byte de dato que precargan QUEUE_SCREEN_OFF/
                               ; QUEUE_SCREEN_ON (madmix_scr_body.asm) con $A2/$E2 -- cada VBLANK ENTRADA_INTERRUPCION_VBLANK
                               ; vuelve a escribirlo en el registro 1 del VDP (los 2 OUT
                               ; siguientes son el par dato/registro estandar, regnum=1=$81),
                               ; asi que el apagado/encendido de pantalla se aplica frame a
                               ; frame, no en el instante del patch
    OUT    ($99),A
    LD     A,$81
    OUT    ($99),A
.NO_ES_IRQ_VBLANK:
    POP    AF
    EI
    RET
; GESTIONAR_FRAME (0x8860, confirmado) -- CORREGIDA: la version
; anterior era un stub ("RET NZ" + comentario TODO) que se saltaba
; casi todo el cuerpo real. El cuerpo real: SIEMPRE llama a
; FUNCION_INHABIL (ver mas abajo) al principio y casi al final
; (antes se pensaba que la salida temprana no llamaba a nada); si
; FRAME_FLAG confirma que ha pasado un frame, ademas llama a
; ACTUALIZAR_VRAM_FRAME (rutina grande de refresco de VDP, ver mas abajo),
; $86BB (CONTINUAR_CAPTURA_MASCARAS_ACTORES, ya transcrita: reparte la carga de recursos
; de actores en varias llamadas), $899B (RESET_CONTADOR_ACTORES) y VACIAR_COLA_REDIBUJADO
; (vacia la cola de redibujado diferido, ver mas abajo). La nota
; anterior de "0xC4A0 x3" era incorrecta.
GESTIONAR_FRAME:
    LD     A,$0F                   ; parametro sin efecto: FUNCION_INHABIL es solo RET, se descarta
    CALL   FUNCION_INHABIL
    LD     A,(FRAME_FLAG)
    LD     B,A
    XOR    A
    LD     (FRAME_FLAG),A
    INC    A
    CP     B
    JR     NZ,.SIN_TRABAJO_DE_FRAME
    CALL   ACTUALIZAR_VRAM_FRAME
    LD     A,$01                   ; parametro sin efecto: FUNCION_INHABIL es solo RET, se descarta
    CALL   FUNCION_INHABIL
    CALL   CONTINUAR_CAPTURA_MASCARAS_ACTORES
    CALL   RESET_CONTADOR_ACTORES
    CALL   VACIAR_COLA_REDIBUJADO   ; drena la cola circular de losetas pendientes, redibujando cada una en VRAM hasta el centinela $FF
.SIN_TRABAJO_DE_FRAME:
    LD     A,$01                   ; parametro sin efecto: FUNCION_INHABIL es solo RET, se descarta
    CALL   FUNCION_INHABIL
    RET
; ULTIMO_ICONO_HUD_CACHEADO ($8888): NO es codigo, es una variable de
; 1 byte que ocupa el hueco de relleno tras el RET de arriba (mismo
; byte $00, transcrito antes como NOP). Cachea el ultimo icono de
; nivel dibujado en el HUD: ACTUALIZAR_VRAM_FRAME la compara contra
; REGISTRO_NIVEL_ICONO_HUD para decidir si hace falta redibujar, y
; APLICAR_COLOR_PANTALLA (madmix_scr_body.asm) la resetea a 0 al
; aplicar la paleta de color de pantalla.
ULTIMO_ICONO_HUD_CACHEADO:
    DB     $00

; FUNCION_INHABIL ($8889): un simple RET, 1 byte -- confirmado byte a
; byte, no es un error de transcripcion. Se llama 3 veces desde
; GESTIONAR_FRAME con distintos valores de A precargados ($0F,
; $01, $01/$06) que la rutina ignora por completo. HIPOTESIS: un
; "hook" de desarrollo deshabilitado (p.ej. debug/sonido) cuyo
; cuerpo se sobreescribio con un RET, dejando las llamadas intactas
; -- no hay confirmacion de que hiciera antes.
FUNCION_INHABIL:
    RET
; --- Fija el registro 7 del VDP (color de borde/fondo en TMS9918)
; al valor de A: escribe A en el puerto $99 y luego $87 ($80 OR 7,
; modo escritura de registro + numero de registro). ---
FIJAR_COLOR_BORDE_VDP:
    OUT    ($99),A
    LD     A,$87
    OUT    ($99),A
    RET

; Constantes usadas por ACTUALIZAR_VRAM_FRAME (ver abajo) -- no son
; datos compilados, solo alias con nombre para direcciones VRAM/RAM
; ya usadas como literal hex en varios sitios del fichero. Colocadas
; ANTES de la rutina (y no dentro) para no romper el ambito de las
; etiquetas locales de ACTUALIZAR_VRAM_FRAME (misma trampa de scoping
; ya documentada antes en la sesion).
ZONA_COLOR_VRAM_DESTELLO_A: EQU $2A80  ; VRAM, zona de color (16 bytes) del destello icono/color HUD (ver DESTELLO_ICONO_COLOR_HUD)
ZONA_COLOR_VRAM_DESTELLO_B: EQU $2B80  ; VRAM, zona de color (16 bytes) del destello icono/color HUD (ver DESTELLO_ICONO_COLOR_HUD)
ZONA_PATRON_VRAM_LABERINTO: EQU $0220  ; VRAM, destino del volcado de BUFFER_LOSETAS_TRABAJO (patron visible del laberinto)
BUFFER_LOSETAS_TRABAJO:     EQU $DE04  ; RAM del Z80 (NO VRAM) -- buffer de trabajo de losetas que ACTUALIZAR_VRAM_FRAME vuelca a VRAM cada frame

; ACTUALIZAR_VRAM_FRAME ($8891): rutina grande de refresco de VDP
; llamada desde GESTIONAR_FRAME una vez por frame confirmado. Usa
; las 3 rutinas ya identificadas CONSULTAR_COLOR_VDP ($8961), FILVRM ($8931)
; y SETVRAM ($8954) sobre varias zonas de VRAM ($2220,
; ZONA_COLOR_VRAM_DESTELLO_A/B)
; y lee/escribe flags de estado del juego ($2C19, $2C04, $2C24) --
; HIPOTESIS sobre esa parte: parpadeo/animacion de algun elemento
; (posible pista o efecto de nivel), sin confirmar el detalle exacto.
; CONFIRMADO en cambio el tramo final (lineas $88ED en adelante): con
; SETVRAM fija la direccion VRAM ZONA_PATRON_VRAM_LABERINTO en
; adelante y en un bucle de 18 filas vuelca byte a byte, via
; OUT ($98),B, el contenido del buffer de trabajo
; BUFFER_LOSETAS_TRABAJO -- el mismo buffer que SCROLL_ARRIBA/SCROLL_ABAJO/SCROLL_IZQUIERDA/SCROLL_DERECHA/
; SCROLL_LOSETA_BUFFER_VRAM desplazan y redibujan en RAM. Es decir:
; SCROLL_LOSETA_BUFFER_VRAM NO escribe en VRAM directamente, solo
; prepara BUFFER_LOSETAS_TRABAJO; es esta funcion
; quien copia ese buffer a la VRAM real, una vez por frame.
ACTUALIZAR_VRAM_FRAME:
    DI
    LD     HL,FLAG_NIVEL_RECIEN_CARGADO
    LD     A,(HL)
    LD     (HL),0
    AND    A
    LD     A,(REGISTRO_NIVEL_ICONO_HUD)
    LD     HL,ULTIMO_ICONO_HUD_CACHEADO
    JR     NZ,.REDIBUJAR_ICONO_HUD
    CP     (HL)
    JR     Z,.SIN_CAMBIO_ICONO_HUD
.REDIBUJAR_ICONO_HUD:
    LD     (HL),A
    CALL   CONSULTAR_COLOR_VDP
    LD     HL,$2220            ; direccion VRAM real (destino de FILVRM, tabla de color SCREEN2), no memoria del Z80
    LD     D,$12
.BUCLE_RELLENO_ICONO_HUD:
    LD     BC,192
    PUSH   HL
    CALL   FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    DI
    POP    HL
    INC    H
    DEC    D
    JR     NZ,.BUCLE_RELLENO_ICONO_HUD
    JR     .APLICAR_COLOR_Y_SCROLL_VRAM
.SIN_CAMBIO_ICONO_HUD:
    LD     HL,$4000            ; direccion de memoria del Z80 (NO VRAM); origen Y destino del LDIR de abajo (DE=HL), sin efecto observable en memoria
    LD     D,H
    LD     E,L
    LD     BC,$052B            ; MISTERIO SIN RESOLVER: 1323. Hipotesis de "relleno de temporizacion para igualar el tiempo de .REDIBUJAR_ICONO_HUD" DESCARTADA (calculo de ciclos no cuadra, ~27800 vs ~97000) -- proposito real sin confirmar, ver FINDINGS.md
    LDIR
    LD     A,$06                   ; parametro sin efecto: FUNCION_INHABIL es solo RET, se descarta
    CALL   FUNCION_INHABIL
.APLICAR_COLOR_Y_SCROLL_VRAM:
    LD     A,(COLOR_ACTUAL)
    CALL   CONSULTAR_COLOR_VDP
    LD     HL,ZONA_COLOR_VRAM_DESTELLO_A
    LD     BC,16
    CALL   FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    DI
    LD     HL,ZONA_COLOR_VRAM_DESTELLO_B
    LD     BC,16
    CALL   FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    DI
    LD     DE,ZONA_PATRON_VRAM_LABERINTO
    LD     HL,BUFFER_LOSETAS_TRABAJO
    LD     B,18
.BUCLE_FILA_CARACTERES_VRAM:
    PUSH   BC
    PUSH   HL
    PUSH   DE
    EX     DE,HL
    CALL   SETVRAM
    EX     DE,HL
    LD     D,$20
    LD     A,L
    LD     C,$98
    LD     E,$18
.BUCLE_COLUMNA_CARACTERES_VRAM:
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    LD     L,A
    LD     B,(HL)
    OUT    (C),B
    ADD    A,D
    INC    A
    DEC    E
    JP     NZ,.BUCLE_COLUMNA_CARACTERES_VRAM
    POP    DE
    INC    D
    POP    HL
    INC    H
    POP    BC
    DJNZ   .BUCLE_FILA_CARACTERES_VRAM
    RET


; --------------------------------------------------------------
;  API DEL VDP  (0x8931 / 0x8942 / 0x8954 originales -- direcciones
;  CONFIRMADAS y contenido CONFIRMADO byte a byte contra el .BIN
;  original, y AHORA TAMBIEN contra el volcado de RAM en vivo. Las
;  3 rutinas quedan exactamente contiguas, sin ningun hueco entre
;  ellas (0x8931-0x8960 completo, 0 bytes de relleno).
; --------------------------------------------------------------
FILVRM:                 ; rellena BC bytes de VRAM desde HL con el byte fijo A (equivalente a la rutina FILVRM del BIOS de MSX)
    DI
    PUSH AF
    CALL SETVRAM         ; posiciona el puntero de escritura del VDP en HL
    POP AF
    INC B               ; compensa el DJNZ-sin-DJNZ de abajo (bucle anidado B/C)
.loop_inner:
    OUT ($98), A          ; escribe el byte fijo en el puerto de datos de VRAM
    DEC C                 ; bucle interno: hasta 256 bytes (C=0 -> 256 iteraciones)
    JR NZ, .loop_inner
    DEC B                 ; bucle externo: repite el interno B veces (BC completo = total de bytes)
    JR NZ, .loop_inner
    EI
    RET

LDIRVM:                 ; copia BC bytes de RAM (HL) a VRAM (destino en DE), byte a byte (equivalente a la rutina LDIRVM del BIOS de MSX)
    DI
    EX DE, HL
    CALL SETVRAM         ; posiciona el puntero de escritura del VDP en el destino (tras el EX, en HL)
    EX DE, HL
.loop:
    LD A, (HL)             ; lee el byte origen de RAM
    OUT ($98), A            ; lo escribe en el puerto de datos de VRAM
    INC HL
    DEC BC
    LD A, B
    OR C
    JP NZ, .loop        ; original usa JP, no JR (18 bytes total la rutina)
    EI
    RET

SETVRAM:                ; posiciona el puntero de escritura del VDP en la direccion VRAM de HL, vale para el resto de la API (equivalente a la rutina SETWRT del BIOS de MSX)
    LD A, L
    OUT ($99), A          ; byte bajo de la direccion VRAM al puerto de control
    LD A, H
    AND $3F                ; descarta los 2 bits altos (direccion VRAM de 14 bits)
    OR $40                  ; fuerza los bits 6-7 a 01: comando "fijar puntero de escritura" del VDP
    OUT ($99), A            ; byte alto + comando al puerto de control
    EX (SP), HL         ; x2 = no-op deliberado: retardo que exige
    EX (SP), HL         ; el VDP tras fijar la direccion de VRAM
    RET

; --------------------------------------------------------------
;  0x8961-0x899F -- CONFIRMADO byte a byte (llenaba un hueco DS),
;  y RE-CONFIRMADO contra el volcado de RAM en vivo en su
;  direccion ESTATICA (ver FINDINGS.md). Rellena EXACTO hasta
;  WAIT_VBLANK (0x89A0), sin ningun resto.
; --------------------------------------------------------------

; CONSULTAR_COLOR_VDP: A = valor con datos en bits 3-6 -> extrae esos
; 4 bits (AND $78 + RRCA x3, equivale a (A AND $78) rotado a bits
; 0-3), los usa como indice 0-15 en TABLA_COLORES_VDP, y devuelve en A
; el valor de tabla OR $10. RESUELTO (ver OBTENER_COLOR_VDP,
; madmix_scr_body.asm, mismo mecanismo componiendo 2 consultas): la
; tabla NO son bits de direccion (hipotesis anterior descartada), son
; 16 colores VDP (0-15) -- esta version simple devuelve solo el color
; de fondo (nibble bajo) de un byte de color SCREEN2, con el bit 4
; forzado via OR $10.
CONSULTAR_COLOR_VDP:
    LD HL, TABLA_COLORES_VDP
    AND $78                ; aisla los 4 bits de indice de color (bits 3-6)
    RRCA
    RRCA
    RRCA                    ; los rota a bits 0-3 (indice 0-15 dentro de la tabla)
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00               ; propaga el acarreo del ADD anterior hacia H
    LD H, A
    LD A, (HL)
    OR $10                    ; fuerza el bit 4 del resultado (ver cabecera de la rutina)
    RET

    DB $00, $00, $00, $00, $00      ; 5 bytes ($8973-$8977) sin consumidor conocido (sin JP/CALL/aritmetica de etiqueta que los referencie) -- HIPOTESIS: relleno de alineacion, ya que TABLA_COLORES_VDP arranca justo despues en $8978, multiplo exacto de 8

TABLA_COLORES_VDP:
    DB $01, $04, $06, $0D, $0C, $05, $0A, $0E
    DB $01, $04, $06, $08, $02, $07, $0B, $0F

; CALCULAR_DIRECCION_MASCARA_ACTOR: BC -> HL = $DC00 + (BC >> 3).
; Divide BC entre 8 (3x SRL B/RR C, desplazamiento de 16 bits) y lo
; suma a base $DC00. RESUELTO (ver FINDINGS.md, "Zona 0xDC00"): $DC00
; NO es una tabla aparte, es un SUBTRAMO de TABLA_RLE_MARCO_CARAMELO (la tabla
; RLE del marco de caramelo, $D6B6-$DD82) reutilizado con un segundo
; proposito -- economia de memoria tipica de MSX1. Uso primario: la
; recorre secuencialmente DESPACHAR_EFECTO_SONIDO2 (madmix_scr.asm)
; como 870 pares (valor,repeticion) para pintar el marco en VRAM. Uso
; secundario (esta rutina + COMPONER_ACTORES_EN_BUFFER): accede a un
; subtramo desde $DC00 de forma ALEATORIA (offset segun posicion en
; pantalla del actor, el BC de entrada) como mascaras AND/OR de 16
; bits para componer sprites contra el fondo. CONFIRMADO que se usa
; de verdad (llamada real desde JT_MOTOR_ACTORES/el motor de actores,
; y coincide byte a byte con el volcado de RAM en vivo).
CALCULAR_DIRECCION_MASCARA_ACTOR:
    PUSH BC
    SRL B
    RR C
    SRL B
    RR C
    SRL B
    RR C                     ; BC = BC / 8 (desplazamiento de 16 bits, 3 veces)
    LD HL, $DC00
    ADD HL, BC
    POP BC
    RET

; RESET_CONTADOR_ACTORES (JT_RESET_CONTADOR_ACTORES, 0x899B -- IDENTIFICADO): pone a cero la
; variable residente 0x8437, confirmada como CONTADOR DE ACTORES
; ACTIVOS (ver JT_MOTOR_ACTORES/motor de actores en FINDINGS.md -- en el
; volcado de RAM en vivo valia 6 con varios actores en pantalla).
RESET_CONTADOR_ACTORES:
    XOR A
    LD ($8437), A
    RET

; --------------------------------------------------------------
;  ESPERA DE INTERRUPCION  (0x89A0 original, confirmado)
; --------------------------------------------------------------
WAIT_VBLANK:
    LD A, 1
    LD (FRAME_FLAG), A     ; arma el semaforo (vuelve a 0 cuando GESTIONAR_FRAME procesa el frame, ver mas abajo)
    EI
.wait:
    LD A, (FRAME_FLAG)
    AND A
    JR NZ, .wait            ; espera activa hasta que el semaforo vuelva a 0
    RET

; ==============================================================
;  0x89AD-0x8CB6 -- JT_GESTIONAR_SCROLL (GESTIONAR_SCROLL, $89AD) y JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM
;  ($8C34), IDENTIFICADAS: es el SCROLL POR SOFTWARE de la
;  ventana de juego (movimiento de la camara), complementario al
;  "scroll por software" de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA/CONSULTAR_TIPO_LOSETA/
;  REDIBUJAR_LOSETA_BUFFER_VRAM que ya estaba confirmado justo despues de este
;  bloque.
;   - GESTIONAR_SCROLL lee la posicion de camara ($2C02) y decide
;     entre 3 rutinas via una cadena de RRA/JP C sobre los bits
;     bajos de fila/columna: SCROLL_ARRIBA (RLD, nibble a la
;     izquierda), SCROLL_ABAJO (RRD, nibble a la derecha) y
;     SCROLL_IZQUIERDA/SCROLL_DERECHA (lateral por LDI, ver mas abajo
;     -- comparten cola APLICAR_DESPLAZAMIENTO_LATERAL, se distinguen por el flag +1/-1
;     que suman a REGISTRO_NIVEL_POSICION_COMECOCOS al final; IZQUIERDA/
;     DERECHA es HIPOTESIS de confianza media-alta, no confirmada en
;     vivo). Si ningun bit relevante esta activo, no hace falta
;     redibujar nada (RET NC).
;   - Las 3 usan MAPEAR_LOSETA_A_GRAFICO ($8BC9, variante de
;     MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA que ademas guarda el resultado en $8433 y
;     ESCRIBE un bit de atributo en TABLA_TIPOS_LOSETA ($8EC7, la MISMA tabla
;     que consulta CONSULTAR_TIPO_LOSETA -- confirmado, sin relacion
;     exacta aclarada todavia) para traducir coordenadas
;     de loseta a direccion dentro del buffer BUFFER_LOSETAS_TRABAJO, y
;     SCROLL_LOSETA_BUFFER_VRAM/COPIAR_LOSETA_FASE_A/COPIAR_LOSETA_FASE_B para volcar ahi la
;     franja nueva via LDI o nibble-swap con RRCA -- CORREGIDO: esto
;     NO escribe en VRAM directamente (ver ACTUALIZAR_VRAM_FRAME,
;     $8891, que vuelca BUFFER_LOSETAS_TRABAJO a VRAM real una vez por frame).
;   - REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM ($8C34): redibuja 4 franjas verticales
;     (bucle .BUCLE_REDIBUJADO_CAMARA, 0x24=36 veces) llamando a DIBUJAR_FILA_LOSETAS_BUFFER_VRAM,
;     luego CALL DIBUJAR_MARCADOR_PUNTOS (JT_DIBUJAR_MARCADOR_PUNTOS, con HL=0 -- redibuja
;     el marcador sin sumar puntos), un FILVRM de dos franjas de $60 bytes en
;     $1648/$1748 (posible limpieza de puntuacion/marcador), y si
;     ($2C27) (contador, probablemente VIDAS restantes) es
;     distinto de cero, dibuja B iconos de 16x2 filas via
;     LDIRVM_INVERTIDO (variante INVERTIDA de LDIRVM: invierte cada byte
;     con CPL antes de escribirlo) leyendo sprite-graphics desde
;     $92C3 (muy cerca de $92E3, la tabla de actores activos ya
;     confirmada) -- consistente con la hipotesis de que $2C27 es
;     el contador de vidas del jugador.
;   - Sin confirmar: el significado preciso de cada offset ($2C25,
;     $8433, $8435, TABLA_TIPOS_LOSETA via MAPEAR_LOSETA_A_GRAFICO) mas alla
;     de lo descrito.
; ==============================================================
GESTIONAR_SCROLL:
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS) ; HL = posicion de camara (H=eje horizontal, L=eje vertical)
    LD     C,A                    ; guarda el parametro de entrada (valor recibido por GESTIONAR_SCROLL)
    LD     A,L
    AND    $03                    ; prueba los 2 bits bajos de L (sub-pixel vertical)
    JR     Z,.COMPROBAR_EJE_Y
    LD     A,C
    AND    $03                    ; enmascara C a sus 2 bits bajos
    LD     C,A
.COMPROBAR_EJE_Y:
    LD     A,H
    AND    $03                    ; prueba los 2 bits bajos de H (sub-pixel horizontal)
    LD     A,C
    JR     Z,.DECIDIR_DIRECCION_SCROLL
    AND    $0C                    ; enmascara C a sus bits 2-3
.DECIDIR_DIRECCION_SCROLL:
    RRA
    JP     C,SCROLL_ARRIBA
    RRA
    JP     C,SCROLL_ABAJO
    RRA
    JP     C,SCROLL_DERECHA
    RRA
    RET    NC                     ; ningun bit activo: no hace falta scroll
SCROLL_IZQUIERDA:                ; HIPOTESIS confianza media-alta: resta 1 a REGISTRO_NIVEL_POSICION_COMECOCOS al final (ver APLICAR_DESPLAZAMIENTO_LATERAL), sin confirmar en vivo
    LD     HL,$0400                        ; delta empaquetado (H=$04=+4 horizontal, L=0)
    LD     (PARAMETRO_DESPLAZAMIENTO_SCROLL),HL
    LD     HL,BUFFER_LOSETAS_TRABAJO       ; puntero base, se guarda para el bucle de filas
    PUSH   HL
    EXX                                    ; cambia al banco alternativo para preparar C, consumido mas tarde en APLICAR_DESPLAZAMIENTO_LATERAL
    LD     C,$00                           ; constante de ajuste (ADD A,C en APLICAR_DESPLAZAMIENTO_LATERAL); SCROLL_DERECHA usa $23
    EXX                                    ; vuelve al banco principal
    LD     A,$FF                           ; flag de direccion (-1, se suma a REGISTRO_NIVEL_POSICION_COMECOCOS.H; SCROLL_DERECHA usa $01/+1)
    LD     BC,-32                          ; paso entre filas del lienzo, en sentido inverso (SCROLL_DERECHA usa +32)
    LD     DE,BUFFER_LOSETAS_TRABAJO+4576  ; = $EFE4: fila 143 del lienzo (4576/32=143, la ultima fila)
    LD     L,E
    LD     H,D
    ADD    HL,BC
    ADD    HL,BC
    ADD    HL,BC
    ADD    HL,BC                          ; HL = BUFFER_LOSETAS_TRABAJO+4448 (fila 139)
    JR     APLICAR_DESPLAZAMIENTO_LATERAL
SCROLL_DERECHA:                  ; HIPOTESIS confianza media-alta: suma 1 a REGISTRO_NIVEL_POSICION_COMECOCOS al final (ver APLICAR_DESPLAZAMIENTO_LATERAL), sin confirmar en vivo
    LD     HL,$FC00                        ; delta empaquetado (H=$FC=-4 horizontal, L=0)
    LD     (PARAMETRO_DESPLAZAMIENTO_SCROLL),HL
    LD     HL,BUFFER_LOSETAS_TRABAJO+4480  ; = $EF84: fila 140 del lienzo (4480/32=140)
    PUSH   HL                              ; guarda el puntero para el bucle de filas
    EXX                                    ; cambia al banco alternativo para preparar C, consumido mas tarde en APLICAR_DESPLAZAMIENTO_LATERAL
    LD     C,$23                           ; constante de ajuste (ADD A,C en APLICAR_DESPLAZAMIENTO_LATERAL); SCROLL_IZQUIERDA usa $00
    EXX                                    ; vuelve al banco principal
    LD     A,$01                           ; flag de direccion (+1, se suma a REGISTRO_NIVEL_POSICION_COMECOCOS.H; SCROLL_IZQUIERDA usa $FF/-1)
    LD     BC,32                           ; paso entre filas del lienzo (ancho de fila de BUFFER_LOSETAS_TRABAJO)
    LD     DE,BUFFER_LOSETAS_TRABAJO
    LD     L,E
    LD     H,D
    ADD    HL,BC
    ADD    HL,BC
    ADD    HL,BC
    ADD    HL,BC                          ; HL = BUFFER_LOSETAS_TRABAJO+128 (fila 4)
APLICAR_DESPLAZAMIENTO_LATERAL:
    PUSH   AF                              ; guarda el flag de direccion (+1/-1) para usarlo al final
    LD     A,140                           ; contador del bucle externo: 140 filas
.BUCLE_FILA_DESPLAZAMIENTO:
    PUSH   HL
    PUSH   DE
    PUSH   BC
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    LDI
    POP    BC
    POP    HL
    ADD    HL,BC
    EX     DE,HL
    POP    HL
    ADD    HL,BC
    DEC    A
    JP     NZ,.BUCLE_FILA_DESPLAZAMIENTO
    EXX
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS)
    POP    AF
    ADD    A,H
    LD     H,A
    RES    0,L
    LD     (REGISTRO_NIVEL_POSICION_COMECOCOS),HL
    ADD    A,C
    LD     H,A
    EXX
    POP    DE
; --- Redibuja una franja completa de fondo tras mover la camara: por
; cada una de 12 columnas (A=$0C) copia 4 palabras (2x LDI) desde la
; direccion que calcula MAPEAR_LOSETA_A_GRAFICO (la "gemela" de
; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA, ver mas abajo) hacia el buffer de fondo,
; avanzando el origen (E) entre grupos. CORREGIDO: no la llama el
; despachador de scroll incremental (SCROLL_LOSETA_BUFFER_VRAM/
; .PREPARAR_BUCLE_LOSETAS) sino REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM, en un bucle de 36 pasadas --
; es el redibujado TOTAL de camara, no el incremental. ---
DIBUJAR_FILA_LOSETAS_BUFFER_VRAM:
    CALL   MAPEAR_LOSETA_A_GRAFICO
    LD     B,$20                  ; paso de 32 bytes entre franjas de la tabla de patrones VRAM
    LD     C,$FF                  ; byte bajo de BC para el decremento automatico de LDI; valor sin uso propio, no se comprueba
    LD     A,12                   ; contador del bucle: 12 losetas por fila
.BUCLE_LOSETAS_FILA:
    EX     AF,AF'
    LD     A,E
    LDI
    LDI
    ADD    A,B
    LD     E,A
    LDI
    LDI
    ADD    A,B
    LD     E,A
    LDI
    LDI
    ADD    A,B
    LD     E,A
    LDI
    LDI
    ADD    A,$A2
    LD     E,A
    EXX
    LD     A,$04
    ADD    A,L
    LD     L,A
    EXX
    CALL   MAPEAR_LOSETA_A_GRAFICO
    EX     AF,AF'
    DEC    A
    JR     NZ,.BUCLE_LOSETAS_FILA
    LD     DE,(PARAMETRO_DESPLAZAMIENTO_SCROLL)
    RET
SCROLL_ABAJO:                    ; desplaza el lienzo BUFFER_LOSETAS_TRABAJO 4px hacia abajo (144 filas x 24 RRD encadenados por fila) y actualiza PARAMETRO_DESPLAZAMIENTO_SCROLL/REGISTRO_NIVEL_POSICION_COMECOCOS
    LD     HL,$0004                        ; delta empaquetado (H=0 horizontal, L=$04=+4 vertical)
    LD     (PARAMETRO_DESPLAZAMIENTO_SCROLL),HL
    EXX                                    ; cambia al banco alternativo para preparar C/D, consumidos mas tarde en SCROLL_LOSETA_BUFFER_VRAM
    LD     C,$00                           ; constante de fase (ADD A,C en SCROLL_LOSETA_BUFFER_VRAM)
    LD     D,$F0                           ; constante de fase (XOR D en SCROLL_LOSETA_BUFFER_VRAM, decide COPIAR_LOSETA_FASE_A vs COPIAR_LOSETA_FASE_B)
    EXX                                    ; vuelve al banco principal
    LD     A,$FF                           ; flag de direccion (-1, se suma a REGISTRO_NIVEL_POSICION_COMECOCOS.L en SCROLL_LOSETA_BUFFER_VRAM; SCROLL_ARRIBA usa $01/+1)
    LD     HL,BUFFER_LOSETAS_TRABAJO       ; inicio de la fila jugable, SCROLL_ABAJO recorre cada fila hacia adelante (INC L)
    PUSH   HL                              ; guarda el puntero de inicio de fila para el bucle de filas
    PUSH   AF                              ; guarda el flag de direccion para usarlo mas tarde en SCROLL_LOSETA_BUFFER_VRAM
    LD     DE,32                  ; paso entre filas del lienzo (ancho de fila de BUFFER_LOSETAS_TRABAJO)
    LD     C,144                  ; contador del bucle externo: 144 filas del lienzo
.BUCLE_FILA_SCROLL_ABAJO:        ; recorre las 144 filas del lienzo (DEC C/JR NZ); por fila: guarda el puntero, resetea A (nibble de acarreo) y llama al bucle de nibbles
    PUSH   HL                     ; guarda el puntero de inicio de esta fila
    XOR    A                      ; A=0: nibble de acarreo inicial para esta fila
    LD     B,2                    ; contador del bucle interno: 2 vueltas x 12 pares RRD/INC L = 24 RRD por fila
.BUCLE_NIBBLE_SCROLL_ABAJO:      ; 24 RRD encadenados (INC L entre cada uno), A como nibble de acarreo entre bytes -- propaga el scroll fino de 4px a lo largo de la fila
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    RRD
    INC    L
    DJNZ   .BUCLE_NIBBLE_SCROLL_ABAJO
    POP    HL
    ADD    HL,DE
    DEC    C
    JR     NZ,.BUCLE_FILA_SCROLL_ABAJO
    JR     SCROLL_LOSETA_BUFFER_VRAM
SCROLL_ARRIBA:                   ; desplaza el lienzo BUFFER_LOSETAS_TRABAJO 4px hacia arriba (144 filas x 24 RLD encadenados por fila) y actualiza PARAMETRO_DESPLAZAMIENTO_SCROLL/REGISTRO_NIVEL_POSICION_COMECOCOS
    LD     HL,$00FC                        ; delta empaquetado (H=0 horizontal, L=$FC=-4 vertical)
    LD     (PARAMETRO_DESPLAZAMIENTO_SCROLL),HL
    EXX                                    ; cambia al banco alternativo para preparar C/D, consumidos mas tarde en SCROLL_LOSETA_BUFFER_VRAM
    LD     C,$2F                           ; constante de fase (ADD A,C en SCROLL_LOSETA_BUFFER_VRAM)
    LD     D,$0F                           ; constante de fase (XOR D en SCROLL_LOSETA_BUFFER_VRAM, decide COPIAR_LOSETA_FASE_A vs COPIAR_LOSETA_FASE_B)
    EXX                                    ; vuelve al banco principal
    LD     A,$01                           ; flag de direccion (+1, se suma a REGISTRO_NIVEL_POSICION_COMECOCOS.L en SCROLL_LOSETA_BUFFER_VRAM; SCROLL_ABAJO usa $FF/-1)
    LD     HL,BUFFER_LOSETAS_TRABAJO+23    ; = $DE1B: fin de la fila jugable (24 bytes), SCROLL_ARRIBA recorre cada fila hacia atras (DEC L)
    PUSH   HL
    PUSH   AF
    LD     DE,32                  ; paso entre filas del lienzo (ancho de fila de BUFFER_LOSETAS_TRABAJO)
    LD     C,144                  ; contador del bucle externo: 144 filas del lienzo
.BUCLE_FILA_SCROLL_ARRIBA:       ; recorre las 144 filas del lienzo (DEC C/JP NZ); por fila: guarda el puntero, resetea A (nibble de acarreo) y llama al bucle de nibbles
    PUSH   HL                     ; guarda el puntero de inicio de esta fila
    XOR    A                      ; A=0: nibble de acarreo inicial para esta fila
    LD     B,2                    ; contador del bucle interno: 2 vueltas x 12 pares RLD/DEC L = 24 RLD por fila
.BUCLE_NIBBLE_SCROLL_ARRIBA:     ; 24 RLD encadenados (DEC L entre cada uno, sentido contrario a SCROLL_ABAJO), A como nibble de acarreo -- propaga el scroll fino de 4px a lo largo de la fila
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    RLD
    DEC    L
    DJNZ   .BUCLE_NIBBLE_SCROLL_ARRIBA
    POP    HL
    ADD    HL,DE
    DEC    C
    JP     NZ,.BUCLE_FILA_SCROLL_ARRIBA
SCROLL_LOSETA_BUFFER_VRAM:
    EXX                            ; cambia al banco alternativo, donde SCROLL_ARRIBA/SCROLL_ABAJO dejaron las constantes de fase C/D
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS)  ; HL = posicion de camara actual
    POP    AF                      ; recupera el flag de direccion (+1/-1) guardado antes del bucle de filas
    ADD    A,L                     ; aplica el delta de direccion al eje vertical (L)
    LD     L,A
    RES    0,H                     ; limpia el bit 0 de H (proposito exacto sin confirmar)
    LD     (REGISTRO_NIVEL_POSICION_COMECOCOS),HL  ; guarda la posicion de camara ya actualizada
    ADD    A,C                     ; suma la constante de fase (C) al nuevo valor de L
    LD     L,A                     ; L temporal, solo para la prueba de fase que sigue (no se guarda en memoria)
    XOR    D                       ; combina con la otra constante de fase (D)
    AND    $01                     ; prueba el bit 0: decide fase A (0) o fase B (1)
    LD     IX,COPIAR_LOSETA_FASE_A
    JR     Z,.PREPARAR_BUCLE_LOSETAS
    LD     IX,COPIAR_LOSETA_FASE_B
.PREPARAR_BUCLE_LOSETAS:
    LD     IY,.CONTINUAR_BUCLE_LOSETAS        ; punto de retorno para COPIAR_LOSETA_FASE_A/B (JP (IY) al terminar)
    LD     A,D                    ; guarda D (byte alto de la posicion de camara ya actualizada) para pasarlo al banco principal
    EXX                           ; vuelve al banco principal de registros
    POP    DE                     ; recupera el puntero guardado por SCROLL_ARRIBA/SCROLL_ABAJO antes del bucle de filas
    LD     C,A                    ; C = valor guardado de D (banco alternativo)
    LD     B,9                    ; contador del bucle externo: 9 losetas
.BUCLE_LOSETAS:
    PUSH   BC                     ; guarda el contador de losetas restantes
    CALL   MAPEAR_LOSETA_A_GRAFICO
    EX     DE,HL
    JP     (IX)                   ; despacha a la fase elegida (COPIAR_LOSETA_FASE_A/B)
.CONTINUAR_BUCLE_LOSETAS:
    EX     DE,HL
    EXX                           ; banco alternativo
    LD     A,4                    ; paso de avance del indice de loseta destino
    ADD    A,H
    LD     H,A
    EXX                           ; vuelve al banco principal
    POP    BC
    DJNZ   .BUCLE_LOSETAS         ; repite para las 9 losetas
    LD     DE,(PARAMETRO_DESPLAZAMIENTO_SCROLL)
    RET
COPIAR_LOSETA_FASE_A:             ; HIPOTESIS: variante de copia para una de 2 fases de alineacion de byte al cruzar limite de loseta, sin confirmar el porque exacto
    EX     DE,HL
    LD     C,$FF                  ; mascara (AND C, usada tambien por COPIAR_LOSETA_FASE_B con el valor que deje aqui)
    LD     B,32                   ; paso entre filas de origen (ancho de fila del lienzo)
    LD     A,4                    ; contador del bucle: 4 vueltas x 4 LDI = 16 bytes (loseta 16x16px)
.BUCLE_COPIAR_LOSETA_FASE_A:
    EX     AF,AF'                 ; guarda el contador de vueltas, libera A para el calculo de E
    LD     A,E
    LDI                           ; copia directa (x4, avanzando el origen por B=32 entre cada una)
    INC    L
    ADD    A,B
    LD     E,A
    LDI
    INC    L
    ADD    A,B
    LD     E,A
    LDI
    INC    L
    ADD    A,B
    LD     E,A
    LDI
    INC    L
    ADD    A,B
    LD     E,A
    LD     A,D
    ADC    A,0                    ; propaga el acarreo a D
    LD     D,A
    EX     AF,AF'                 ; recupera el contador de vueltas
    DEC    A
    JP     NZ,.BUCLE_COPIAR_LOSETA_FASE_A
    EX     DE,HL
    JP     (IY)                   ; vuelve a .CONTINUAR_BUCLE_LOSETAS
COPIAR_LOSETA_FASE_B:             ; HIPOTESIS: variante de copia para la otra fase de alineacion de byte (sin el EX DE,HL de COPIAR_LOSETA_FASE_A), sin confirmar el porque exacto
    LD     B,32                   ; paso entre filas de origen (ancho de fila del lienzo)
    LD     A,4                    ; contador del bucle: 4 vueltas x 4 grupos = 16 bytes (loseta 16x16px)
.BUCLE_COPIAR_LOSETA_FASE_B:
    EX     AF,AF'                 ; guarda el contador de vueltas
    LD     A,(DE)                 ; mezclado a nivel de nibble con el contenido ya existente en destino (x4 grupos identicos)
    RRCA
    RRCA
    RRCA
    RRCA
    AND    C
    OR     (HL)
    LD     (HL),A
    INC    E
    INC    E
    LD     A,L
    ADD    A,B
    LD     L,A
    LD     A,(DE)
    RRCA
    RRCA
    RRCA
    RRCA
    AND    C
    OR     (HL)
    LD     (HL),A
    INC    E
    INC    E
    LD     A,L
    ADD    A,B
    LD     L,A
    LD     A,(DE)
    RRCA
    RRCA
    RRCA
    RRCA
    AND    C
    OR     (HL)
    LD     (HL),A
    INC    E
    INC    E
    LD     A,L
    ADD    A,B
    LD     L,A
    LD     A,(DE)
    RRCA
    RRCA
    RRCA
    RRCA
    AND    C
    OR     (HL)
    LD     (HL),A
    INC    E
    INC    E
    LD     A,L
    ADD    A,B
    LD     L,A
    LD     A,H
    ADC    A,0                    ; propaga el acarreo a H
    LD     H,A
    EX     AF,AF'                 ; recupera el contador de vueltas
    DEC    A
    JP     NZ,.BUCLE_COPIAR_LOSETA_FASE_B
    JP     (IY)                   ; vuelve a .CONTINUAR_BUCLE_LOSETAS
; --- Esta es la rutina "gemela" de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA (0x8CB6, ver
; mas abajo) que se menciona en el hallazgo del bug del nivel 13 en
; FINDINGS.md: mismo modismo AND $7C + rotaciones = fila*32+columna,
; misma base de buffer de nivel.
;
; BUG CORREGIDO (a peticion del usuario, ver FINDINGS.md "aplicado el
; fix real de la v2.0"): la v1.0 original tenia aqui $FC60 (0x8BE5,
; el byte bajo de "LD HL,$FC60" mas abajo) -- ese buffer no tiene
; espacio suficiente para el cuerpo mas grande del nivel 14, y por
; eso el contador de bolitas del nivel 13 nunca completaba bien (bug
; ya documentado, heredado del original de Spectrum). La v2.0
; (CAS/ROM, homebrew de 2013) lo corrige desplazando el buffer 16
; bytes antes, a $FC50, en los 5 sitios donde esta constante esta
; grabada como numero magico (2 en madmix1.asm, 3 en madmix_scr.asm
; -- COORD_TO_ADDR, COORD_TO_ADDR_LOCAL, CARGAR_NIVEL). Aplicado
; aqui tal cual: $FC60 -> $FC50. Esta es la UNICA desviacion
; deliberada de la reproduccion byte a byte de la v1.0 original en
; todo el proyecto -- todo lo demas sigue siendo la v1.0 tal cual,
; bugs incluidos. Verificado: recompilado, la unica diferencia
; resultante contra el .BIN original es este byte, en las 5
; direcciones esperadas. ---
MAPEAR_LOSETA_A_GRAFICO:
    PUSH   AF                     ; guarda los registros del llamador (se restauran en .RESTAURAR_Y_SALIR)
    PUSH   DE
    PUSH   BC
    EXX                           ; trabaja en el banco alternativo
    LD     A,H
    AND    $7C                    ; mascara de bits de la coordenada H (posicion de camara)
    RRCA
    RRCA
    LD     B,A
    LD     A,L
    AND    $7C                    ; mascara de bits de la coordenada L
    RLCA
    RR     B
    RRA
    RR     B
    RRA
    RR     B
    RRA
    LD     C,A                    ; BC = indice combinado de fila/columna
    PUSH   BC
    EXX                           ; vuelve al banco principal
    POP    BC
    LD     HL,$FC50            ; BUG CORREGIDO: $FC60 en la v1.0 original, ver comentario arriba -- buffer del nivel activo (1 byte por tipo de loseta, ver FINDINGS.md)
    ADD    HL,BC                  ; HL = direccion de la loseta en el buffer del nivel
    LD     A,(HL)                 ; A = tipo de loseta (byte crudo del nivel)
    LD     B,A                    ; guarda el tipo de loseta completo para mas adelante
    AND    $7F                    ; descarta el bit 7 (se trata aparte mas abajo)
    LD     L,0                    ; L=0: semilla del calculo de indice grafico (bit a bit via RRA/RR L)
    RRA
    RR     L
    RRA
    RR     L
    RRA
    RR     L
    LD     H,A
    LD     DE,GRAFICOS_LOSETAS            ; base de los graficos de loseta
    ADD    HL,DE                  ; HL = direccion grafica real de la loseta
    LD     ($8433),HL             ; guarda la direccion grafica (variable sin nombre confirmado, ver comentario mas arriba)
    EXX                           ; banco alternativo otra vez
    LD     A,H
    AND    $03                    ; mascara de 2 bits de la coordenada H
    ADD    A,A
    ADD    A,A
    LD     E,A
    LD     A,L
    RRCA
    RRCA
    LD     A,E
    RLA
    EXX                           ; vuelve al banco principal
    ADD    A,L
    LD     L,A
    PUSH   HL                     ; guarda la direccion grafica para el llamador (recuperada en .RESTAURAR_Y_SALIR)
    LD     A,2                    ; valor de estado/modo (proposito exacto sin confirmar)
    LD     ($8435),A
    LD     A,B                    ; recupera el tipo de loseta completo
    AND    $3F                    ; indice (bits 0-5) en TABLA_TIPOS_LOSETA
    LD     HL,TABLA_TIPOS_LOSETA
    ADD    A,L
    LD     L,A
    LD     A,H
    ADC    A,0                    ; propaga el acarreo
    LD     H,A
    LD     A,B                    ; recupera el tipo de loseta completo otra vez
    LD     B,16                   ; NOTA: B no se vuelve a leer antes de POP BC en .RESTAURAR_Y_SALIR -- parece sin efecto observable
    AND    $80                    ; extrae solo el bit 7 (flag de atributo)
    LD     D,A
    LD     A,(HL)                 ; lee el byte actual de TABLA_TIPOS_LOSETA[indice]
    AND    $00                    ; anula por completo la lectura anterior (vestigio de una comprobacion mas compleja, ver FINDINGS.md)
    XOR    D
    LD     D,A
    JR     Z,.RESTAURAR_Y_SALIR   ; si el bit 7 estaba a cero, no toca la tabla
    XOR    (HL)                   ; si estaba a uno, alterna ese bit en TABLA_TIPOS_LOSETA[indice]
    LD     (HL),A
.RESTAURAR_Y_SALIR:
    POP    HL
    POP    BC
    POP    DE
    POP    AF
    RET
; --- REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM (JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM): redibuja la camara -- bucle de $24
; (36) pasos (.BUCLE_REDIBUJADO_CAMARA), una llamada a DIBUJAR_FILA_LOSETAS_BUFFER_VRAM por paso,
; avanzando una fila cada vez (INC H) -- y, si quedan vidas
; (($2C27)!=0), dibuja el icono de vida
; (ICONO_VIDA_EXTRA, ver FINDINGS.md) una vez por vida restante
; (.BUCLE_ICONOS_VIDA/LDIRVM_INVERTIDO), desplazando $18 px por icono. De paso
; limpia BUFFER_DIGITOS_PUNTUACION a "000000" y redibuja el marcador
; (CALL DIBUJAR_MARCADOR_PUNTOS) antes del bucle de vidas. ---
REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM:
    LD     B,36                   ; contador del bucle externo: 36 franjas de camara
    LD     DE,BUFFER_LOSETAS_TRABAJO  ; destino base en el lienzo
    EXX                           ; banco alternativo
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS)
    EXX                           ; vuelve al banco principal
.BUCLE_REDIBUJADO_CAMARA:
    PUSH   BC
    EXX                           ; banco alternativo
    PUSH   HL
    EXX                           ; vuelve al banco principal
    PUSH   DE
    CALL   DIBUJAR_FILA_LOSETAS_BUFFER_VRAM
    POP    HL
    LD     BC,128                 ; paso de destino: 4 filas de 32 bytes
    ADD    HL,BC
    EX     DE,HL
    EXX                           ; banco alternativo
    POP    HL
    INC    H                      ; avanza pagina del banco alternativo
    EXX                           ; vuelve al banco principal
    POP    BC
    DJNZ   .BUCLE_REDIBUJADO_CAMARA
    LD     HL,0                   ; delta=0: solo redibuja el marcador, no suma puntos
    CALL   DIBUJAR_MARCADOR_PUNTOS
    LD     HL,$1648               ; zona VRAM de los iconos de vida (coincide con D/E mas abajo)
    PUSH   HL
    LD     A,$FF                  ; byte de relleno (blanco/vacio)
    LD     BC,96                  ; recuento de bytes a rellenar
    CALL   FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    POP    HL
    INC    H                      ; siguiente pagina VRAM
    LD     BC,96                  ; recuento de bytes a rellenar
    CALL   FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    LD     A,(VIDAS_RESTANTES)
    AND    A                      ; prueba si es cero
    RET    Z                      ; sin vidas: no dibuja iconos
    LD     B,A                    ; contador del bucle: una vuelta por vida restante
    LD     E,$48                  ; byte bajo de la direccion VRAM del primer icono (junto con D, forma $1648)
.BUCLE_ICONOS_VIDA:
    PUSH   BC
    LD     D,$16                  ; byte alto de la direccion VRAM del icono
    LD     HL,$92C3               ; origen grafico del icono (ICONO_VIDA_EXTRA, ver FINDINGS.md)
    LD     BC,16                  ; recuento de bytes: primera banda del icono
    CALL   LDIRVM_INVERTIDO
    INC    D                      ; siguiente banda VRAM (+256)
    LD     BC,16                  ; recuento de bytes: segunda banda del icono
    CALL   LDIRVM_INVERTIDO
    LD     A,24                   ; paso horizontal entre iconos, en pixels
    ADD    A,E
    LD     E,A                    ; avanza al siguiente icono
    POP    BC
    DJNZ   .BUCLE_ICONOS_VIDA
    LD     HL,BUFFER_DIGITOS_PUNTUACION  ; buffer de digitos ASCII del marcador (6 bytes)
    LD     (HL),$30               ; ASCII '0' (48), primer digito
    LD     DE,BUFFER_DIGITOS_PUNTUACION+1
    LD     BC,5                   ; recuento: copia el '0' a los otros 5 digitos
    LDIR
    LD     HL,0                   ; delta=0: solo redibuja el marcador, no suma puntos
    CALL   DIBUJAR_MARCADOR_PUNTOS
    RET
; --- Vuelca BC bytes desde HL a VRAM (destino en DE, via SETVRAM)
; invirtiendo cada byte (CPL) antes de escribirlo -- mismo
; "modo invertido" que DIBUJAR_TEXTO_INVERTIDO_VRAM. Usada por .BUCLE_ICONOS_VIDA para dibujar el
; icono de vida (ICONO_VIDA_EXTRA, ver FINDINGS.md), 16 bytes por
; banda en 2 bandas. ---
LDIRVM_INVERTIDO:
    DI
    EX     DE,HL
    CALL   SETVRAM
    EX     DE,HL
LDIRVM_INVERTIDO_LOOP:
    LD     A,(HL)
    CPL
    OUT    ($98),A
    INC    HL
    DEC    BC
    LD     A,B
    OR     C
    JP     NZ,LDIRVM_INVERTIDO_LOOP
    EI
    RET


; ==============================================================
;  SCROLL POR SOFTWARE  (0x8CB6 / 0x8CDA / 0x8D1B originales,
;  confirmados -- en ESE orden de direcciones)
; ==============================================================
; NOTA: "PLAYER_POS" (variable inventada, nunca confirmada contra
; el binario original) se quito de aqui -- estaba colocada justo
; antes de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA y lo desplazaba 2 bytes de su
; direccion real confirmada (0x8CB6), rompiendo el byte-exact sin
; que nadie lo notara hasta verificarlo con --sym. Si de verdad
; existe una variable de posicion del jugador, hay que localizarla
; por desensamblado antes de volver a colocarla en algun sitio.

; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA (0x8CB6) -- CONFIRMADO y transcrito completo.
; HL=($2C02) es la posicion del comecocos/camara; B,C son un
; desplazamiento (fila,columna) relativo. El patron AND $7C +
; rotaciones es el modismo clasico Z80/MSX para "direccion = base
; + fila*32 + columna" -- el 32 (ancho de la matriz de nivel en
; losetas) sale de estas constantes, no es una suposicion. Ver
; FINDINGS.md: confirma que el usuario contÃ³ bien (25 losetas
; visibles + 7 del pasillo de vuelta = 32).
;
; BUG CORREGIDO (ver MAPEAR_LOSETA_A_GRAFICO mas arriba, 0x8BC9, y FINDINGS.md):
; la v1.0 original tenia $FC60 aqui tambien (0x8CD4) -- mismo bug del
; buffer de nivel demasiado pequeno para el cuerpo del nivel 14,
; mismo fix de la v2.0 aplicado: $FC60 -> $FC50.
MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA:
    PUSH AF
    PUSH BC
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)  ; posicion actual de camara
    LD D, H
    LD E, L
    LD A, H
    ADD A, B                ; suma el desplazamiento de fila (B) a la coordenada H
    AND $7C                 ; mascara de bits de fila
    RRCA
    RRCA
    LD B, A
    LD A, L
    ADD A, C                ; suma el desplazamiento de columna (C) a la coordenada L
    AND $7C                 ; mascara de bits de columna
    RLCA
    RR B
    RRA
    RR B
    RRA
    RR B
    RRA
    LD C, A                 ; BC = indice combinado fila*32+columna
    LD HL, $FC50            ; BUG CORREGIDO: $FC60 en la v1.0 original, ver comentario arriba -- buffer del nivel activo
    ADD HL, BC               ; HL = direccion absoluta de la loseta
    POP BC
    POP AF
    RET

; ==============================================================
;  0x8CDA-0x8EC4 -- CORREGIDOS/COMPLETADOS CONSULTAR_TIPO_LOSETA y
;  REDIBUJAR_LOSETA_BUFFER_VRAM (los stubs anteriores no coincidian con el codigo
;  real), mas la cola de redibujado diferido (QUEUE_*, sin nombre
;  previo), JT_DIBUJAR_MARCADOR_PUNTOS (DIBUJAR_MARCADOR_PUNTOS, marcador de puntuacion) y
;  JT_LEER_ENTRADA (LEER_ENTRADA, lectura de teclado/joystick).
;   - CONSULTAR_TIPO_LOSETA: CORREGIDO -- el stub decia "sumar A a HL
;     con acarreo" sobre el bloque reservado ($8EC4); el real usa
;     base TABLA_TIPOS_LOSETA ($8EC7, +3 respecto al bloque reservado) y
;     enmascara el resultado con AND $1F, no solo lee el byte tal cual.
;   - APILAR_PETICION_REDIBUJADO/VACIAR_COLA_REDIBUJADO/.DESPACHAR_ENTRADA_COLA: cola de
;     peticiones de redibujado diferido. APILAR_PETICION_REDIBUJADO (CORREGIDO:
;     llamadores localizados en madmix_scr.asm -- HNDLR_MARICOCO/
;     HNDLR_REGPUNANTOSO, al regenerar una bolita ya comida) apila
;     (C,B,A) en un buffer circular en RAM ($8D61-$8D6F, $FF =
;     vacio) via el puntero $8D5F.
;     VACIAR_COLA_REDIBUJADO es la rutina real detras de "CALL $8CFF"
;     en GESTIONAR_FRAME: cada frame vacia la cola llamando a
;     REDIBUJAR_LOSETA_BUFFER_VRAM(C,B,A) por cada entrada, hasta el centinela.
;   - REDIBUJAR_LOSETA_BUFFER_VRAM: CORREGIDO -- el stub anterior decia "copia de
;     franja 2x16, origen GRAFICOS_LOSETAS, destino SCREEN_SHADOW"; el
;     real usa la posicion de camara ($2C02) + los parametros
;     (B,C) de la cola para calcular una direccion en BUFFER_LOSETAS_TRABAJO, y
;     copia 16 bytes (2x LDI) desde GRAFICOS_LOSETAS (base $B940, ver
;     LD BC,$B940 -- confirma el nombre) en un bucle de $10 pasos.
;   - DIBUJAR_MARCADOR_PUNTOS (JT_DIBUJAR_MARCADOR_PUNTOS, $8D70): dibuja el marcador. Si el
;     acumulado ($2C29) llega a $2710 (10000), en vez de seguir
;     contando muestra el texto TEXTO_BESTIA ("BESTIA") -- un
;     "premio" de texto en vez de numero. Si ($60CA) esta activo
;     (probable flag de modo demo) muestra TEXTO_DEMO (" DEMO ")
;     en su lugar. Si no, calcula los digitos por resta repetida
;     contra DIVISORES_PUNTUACION (1000/100/10) y los dibuja via
;     DIBUJAR_TEXTO_INVERTIDO_VRAM, que interpreta cada byte como indice de caracter
;     en una tabla de fuente en $935B (parece coincidir con ASCII
;     para letras, sin confirmar el resto de la tabla).
;   - LEER_ENTRADA (JT_LEER_ENTRADA, $8E3C): lee FLAG_ENTRADA_BLOQUEADA
;     ($8EC6, byte "libre" del bloque reservado justo antes de
;     TABLA_TIPOS_LOSETA, reutilizado como flag -- confirmado por valor: la
;     ROM tiene $00 ahi) y, si no esta activo, hace un escaneo de
;     teclado (OUT $AA / IN $A9, el metodo estandar MSX de matriz de
;     teclado) sobre 5 filas comparando contra una tabla de mascaras
;     en $8E88, y luego lee el joystick por el puerto del PSG
;     (OUT $A0 / IN $A2) decodificando los bits en E via SET 0-4 --
;     coincide con el mismo patron de extraccion de bits usado en
;     CONSULTAR_COLOR_VDP/TABLA_COLORES_VDP (bits 3-6 -> indice 0-15),
;     reutilizado aqui para decodificar direccion, no color. El
;     resultado combinado se guarda en
;     ACUMULADOR_ENTRADA ($8EC4, mismo bloque reservado) via
;     OR/LD (HL),A.
; ==============================================================
CONSULTAR_TIPO_LOSETA:
    PUSH   HL
    PUSH   DE
    LD     A,(HL)                 ; A = byte crudo de loseta
    AND    $7F                    ; descarta el bit 7
    LD     HL,TABLA_TIPOS_LOSETA
    ADD    A,L                    ; HL = TABLA_TIPOS_LOSETA + indice
    LD     L,A
    LD     A,H
    ADC    A,0                    ; propaga el acarreo
    LD     H,A
    LD     A,(HL)                 ; A = tipo de loseta
    AND    $1F                    ; mascara final del tipo (5 bits)
    POP    DE
    POP    HL
    RET
APILAR_PETICION_REDIBUJADO:
    PUSH   HL
    LD     HL,($8D5F)             ; puntero de escritura de la cola circular
    LD     (HL),C                 ; primer byte de la entrada (fila)
    INC    HL
    LD     (HL),B                 ; segundo byte de la entrada (columna)
    INC    HL
    LD     (HL),A                 ; tercer byte de la entrada
    INC    HL
    LD     (HL),$FF               ; nuevo centinela de fin de cola
    LD     ($8D5F),HL             ; guarda el puntero avanzado
    POP    HL
    RET
VACIAR_COLA_REDIBUJADO:
    LD     HL,$8D61               ; inicio del buffer circular de la cola
.BUCLE_VACIAR_COLA:
    LD     A,(HL)
    CP     $FF                    ; centinela de fin de cola
    JR     NZ,.DESPACHAR_ENTRADA_COLA
    LD     HL,$8D61               ; cola vacia: reinicia el puntero de escritura al principio
    LD     (HL),$FF
    LD     ($8D5F),HL
    RET
.DESPACHAR_ENTRADA_COLA:
    LD     C,A                    ; primer byte de la entrada
    INC    HL
    LD     B,(HL)                 ; segundo byte de la entrada
    INC    HL
    LD     A,(HL)                 ; tercer byte de la entrada
    INC    HL
    CALL   REDIBUJAR_LOSETA_BUFFER_VRAM
    JR     .BUCLE_VACIAR_COLA
REDIBUJAR_LOSETA_BUFFER_VRAM:
    PUSH   HL
    PUSH   DE
    PUSH   AF
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS)
    LD     A,H
    AND    $03                    ; mascara de bits de la coordenada H
    LD     H,A
    LD     A,L
    AND    $02                    ; mascara de bits de la coordenada L
    RR     H
    RRA
    LD     L,A
    LD     A,B                    ; fila de la entrada de la cola
    ADD    A,A
    ADD    A,H
    LD     H,A
    LD     A,C                    ; columna de la entrada de la cola
    ADD    A,A
    ADD    A,L
    LD     L,A                    ; HL = indice combinado en el lienzo
    LD     BC,BUFFER_LOSETAS_TRABAJO
    ADD    HL,BC                  ; HL = direccion destino en el lienzo
    EX     DE,HL
    POP    AF                     ; recupera el tercer byte de la entrada (tipo de loseta)
    AND    $7F                    ; descarta el bit 7
    LD     L,0                    ; semilla del calculo de indice grafico
    RRA
    RR     L
    RRA
    RR     L
    RRA
    RR     L
    LD     H,A
    LD     BC,GRAFICOS_LOSETAS            ; base de los graficos de loseta
    ADD    HL,BC                  ; HL = direccion grafica origen
    LD     B,16                   ; contador del bucle: 16 filas de la loseta
.BUCLE_FILA_LOSETA:
    PUSH   BC
    LDI                           ; copia 2 bytes por fila (el ancho real de la loseta)
    LDI
    LD     BC,30                  ; paso de destino: 30+2=32, ancho de fila del lienzo
    EX     DE,HL
    ADD    HL,BC
    EX     DE,HL
    POP    BC
    DJNZ   .BUCLE_FILA_LOSETA
    POP    DE
    POP    HL
    RET

; $8D5F/$8D60 (puntero de APILAR_PETICION_REDIBUJADO, 2 bytes) y $8D61-$8D6F (el
; buffer circular de la cola, 15 bytes) -- estado inicial real en
; el .BIN: puntero a 0 y buffer todo $FF (cola vacia). NOP/RST 38h
; son simplemente como se desensamblan los bytes $00/$FF sueltos,
; no hay codigo real aqui.
    NOP
    NOP
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
    RST    38H
; --- Dibuja el marcador de puntos (JT_DIBUJAR_MARCADOR_PUNTOS). Si ($60CA) esta activo
; (modo demo, ver TAIL_* en madmix_scr.asm) muestra TEXTO_DEMO
; (" DEMO ") en vez del numero. Si no, suma DE a la puntuacion
; acumulada ($2C29); si llega a $2710 (10000) muestra TEXTO_BESTIA
; ("BESTIA") en vez de seguir contando; si no, convierte el numero a
; digitos ASCII (DIBUJAR_MARCADOR_PUNTOS_DIGITOS) sobre BUFFER_DIGITOS_PUNTUACION. Dibuja
; el resultado con DIBUJAR_TEXTO_INVERTIDO_VRAM en la posicion fija de pantalla $16B0. ---
DIBUJAR_MARCADOR_PUNTOS:
    PUSH   AF
    PUSH   HL                     ; HL de entrada = delta a sumar a la puntuacion (0 = solo redibujar)
    PUSH   DE
    PUSH   BC
    PUSH   IX
    LD     A,($60CA)              ; flag de modo demo (probable)
    AND    A                      ; prueba si esta activo
    LD     IX,TEXTO_DEMO
    JR     NZ,DIBUJAR_MARCADOR_PUNTOS_COMMON  ; en demo: muestra " DEMO " en vez del numero
    EX     DE,HL                  ; DE = delta de entrada
    LD     HL,(PUNTUACION)
    ADD    HL,DE                  ; suma el delta a la puntuacion acumulada
    LD     (PUNTUACION),HL
    LD     A,H
    LD     DE,10000               ; umbral del premio "BESTIA"
    SBC    HL,DE                  ; compara la puntuacion contra 10000
    LD     IX,TEXTO_BESTIA
    JR     NC,DIBUJAR_MARCADOR_PUNTOS_COMMON  ; si llega o supera 10000: muestra "BESTIA" en vez de seguir contando
    ADD    HL,DE                  ; deshace la resta (HL = puntuacion real, por debajo del umbral)
    LD     DE,BUFFER_DIGITOS_PUNTUACION
    CALL   DIBUJAR_MARCADOR_PUNTOS_DIGITOS  ; convierte la puntuacion a digitos ASCII
    LD     IX,BUFFER_DIGITOS_PUNTUACION
DIBUJAR_MARCADOR_PUNTOS_COMMON:
    LD     HL,$16B0               ; posicion fija en pantalla del marcador
    CALL   DIBUJAR_TEXTO_INVERTIDO_VRAM
    POP    IX
    POP    BC
    POP    DE
    POP    HL
    POP    AF
    RET
; --- Convierte la puntuacion (HL) en digitos ASCII escritos en el
; buffer (DE, normalmente BUFFER_DIGITOS_PUNTUACION): resta repetida contra
; DIVISORES_PUNTUACION (1000,100,10, ver mas abajo) para los primeros 3
; digitos via .EMITIR_DIGITO, y el resto (0-9, ya en L) para el
; ultimo. Algoritmo clasico de extraccion de digitos por resta. ---
DIBUJAR_MARCADOR_PUNTOS_DIGITOS:
    PUSH   DE                     ; guarda DE de entrada (puntero destino) para pasarlo al banco alternativo
    EXX                           ; banco alternativo
    POP    DE                     ; DE (alternativo) = puntero destino, usado luego por .EMITIR_DIGITO
    EXX                           ; vuelve al banco principal
    LD     IX,DIVISORES_PUNTUACION
    LD     DE,0                   ; offset inicial en el buffer destino (via banco alternativo)
.BUCLE_DIVISORES:
    XOR    A                      ; A=0: contador de digito para este divisor
    LD     C,(IX+$00)             ; byte bajo del divisor actual
    LD     B,(IX+$01)             ; byte alto del divisor actual
    INC    IX                     ; avanza al siguiente divisor
    INC    IX
.BUCLE_RESTA_DIGITO:
    INC    A                      ; cuenta un intento de resta mas
    SBC    HL,BC                  ; resta el divisor
    JR     NC,.BUCLE_RESTA_DIGITO ; sin acarreo: todavia cabe otra resta
    DEC    A                      ; corrige el intento que ya se paso (dio acarreo)
    CALL   .EMITIR_DIGITO
    ADD    HL,BC                  ; deshace la ultima resta fallida
    LD     A,B
    OR     C                      ; comprueba si el divisor actual era 10 (el ultimo)
    CP     10
    JR     NZ,.BUCLE_DIVISORES    ; si no era 10, sigue con el siguiente divisor
    LD     A,L                    ; ultimo digito: el resto ya cabe directo en L (0-9)
    CALL   .EMITIR_DIGITO
    RET
; --- Escribe un digito (A, 0-9) como caracter ASCII ("+$30") en la
; siguiente posicion libre del buffer (puntero en el juego de
; registros alterno, EXX, avanzado con INC E cada vez). ---
.EMITIR_DIGITO:
    PUSH   HL
    EXX                           ; banco alternativo
    PUSH   DE                     ; guarda el puntero destino (alternativo)
    EXX                           ; vuelve al banco principal
    POP    HL                     ; HL = puntero destino
    ADD    HL,DE                  ; HL += offset acumulado
    ADD    A,$30                  ; convierte el digito (0-9) a caracter ASCII ('0'-'9')
    LD     (HL),A
    POP    HL
    INC    E                      ; avanza el offset para el siguiente digito
    RET
; 0x8DE3-0x8DFD (27 bytes): NO es codigo -- el desensamblado lineal
; se desincroniza aqui (confirmado: las bytes $30,$30 del relleno
; de digitos decodifican por casualidad como "JR NC,+48" y
; caen sobre etiquetas reales de mas abajo, puro azar de valores).
; Es una zona de datos real, con 3 partes:
;  - DIVISORES_PUNTUACION ($8DE3): 3 palabras (1000,100,10) usadas por
;    DIBUJAR_MARCADOR_PUNTOS_DIGITOS para extraer digitos decimales de la
;    puntuacion por resta repetida (algoritmo clasico).
;  - BUFFER_DIGITOS_PUNTUACION ($8DE9): 6 bytes ASCII inicializados a
;    "000000", donde .EMITIR_DIGITO escribe cada digito calculado;
;    terminados en $FF (indice de fin de lista para DIBUJAR_TEXTO_INVERTIDO_VRAM).
;    REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM (bloque anterior, $8C34) reinicia este buffer
;    a "000000" con un LDIR antes de cada redibujado si hay que
;    limpiarlo.
;  - Dos textos alternativos al marcador numerico, tambien listas
;    de indices terminadas en $FF, usados por DIBUJAR_MARCADOR_PUNTOS segun el
;    caso: TEXTO_BESTIA ($8DF0, "BESTIA") se usa cuando la
;    puntuacion acumulada llega a $2710 (10000) en vez de seguir
;    contando -- un "premio" de texto en vez de numero. TEXTO_DEMO
;    ($8DF7, " DEMO ") se usa cuando ($60CA) es distinto de cero,
;    consistente con un flag de modo demostracion (ver TAIL_* en
;    madmix_scr.asm). Los indices coinciden con el codigo ASCII de
;    cada letra porque, aparentemente, la tabla de fuente en
;    $935B (ver DIBUJAR_TEXTO_INVERTIDO_VRAM mas abajo) esta indexada igual que ASCII
;    para ese rango de caracteres -- no confirmado en detalle.
DIVISORES_PUNTUACION:
    DB $E8,$03,$64,$00,$0A,$00
BUFFER_DIGITOS_PUNTUACION:
    DB "000000",$FF
TEXTO_BESTIA:
    DB "BESTIA",$FF
TEXTO_DEMO:
    DB " DEMO ",$FF
; --- Dibuja una cadena de texto: IX apunta a una lista de codigos de
; caracter terminada en $FF (formato de TEXTO_FASE/TEXTO_READY/
; TEXTO_BESTIA/etc, ver mas abajo). Por cada codigo calcula la
; direccion real del glifo ($925B + codigo*8, formula confirmada --
; ver TABLA_FUENTE_CARACTERES/ICONO_VIDA_EXTRA en FINDINGS.md) y vuelca sus
; 8 filas a VRAM (via SETVRAM, $8954), invirtiendo cada byte (CPL,
; mismo truco "negado" que el icono de vida) y escribiendolo dos
; veces por fila -- avanza el cursor 8 columnas por caracter hasta
; leer el $FF de fin de cadena. ---
DIBUJAR_TEXTO_INVERTIDO_VRAM:
    EX     DE,HL                  ; DE = puntero a la lista de codigos de caracter (parametro de entrada en HL)
DIBUJAR_TEXTO_INVERTIDO_VRAM_LOOP:
    LD     A,(IX+$00)             ; A = codigo de caracter actual
    INC    IX
    CP     $FF                    ; centinela de fin de cadena
    RET    Z
    PUSH   DE                     ; guarda la posicion VRAM del cursor
    LD     L,A
    LD     H,0                    ; HL = codigo (extendido a 16 bits)
    ADD    HL,HL
    ADD    HL,HL
    ADD    HL,HL                  ; HL = codigo*8
    DEC    H                      ; HL -= 256
    LD     BC,$935B               ; base de la formula de glifo (8 bytes antes de TABLA_FUENTE_CARACTERES)
    ADD    HL,BC                  ; HL = direccion del glifo ($925B + codigo*8)
    LD     B,8                    ; contador del bucle: 8 filas del caracter
    DI
.BUCLE_FILAS_CARACTER:
    EX     DE,HL                  ; DE = direccion del glifo (temporalmente)
    CALL   SETVRAM                ; posiciona el puntero VRAM en el cursor (en DE)
    EX     DE,HL                  ; recupera HL = direccion del glifo
.DIBUJAR_FILA_CARACTER:
    LD     A,(HL)                 ; A = byte de fuente de esta fila
    CPL                           ; invierte el byte (modo invertido)
    OUT    ($98),A                ; escribe el byte invertido a VRAM
    NOP
    NOP
    NOP
    INC    E                      ; avanza a la siguiente columna VRAM
    OUT    ($98),A                ; vuelve a escribir el mismo byte (columna duplicada)
    INC    E
    INC    HL                     ; siguiente byte de fuente (fila siguiente)
    LD     A,E
    AND    $06                    ; mascara de bits para decidir si hace falta envolver de franja VRAM
    JP     NZ,.FIN_FILA
    LD     A,E
    SUB    8                      ; retrocede la columna 8 posiciones
    LD     E,A
    INC    D                      ; avanza a la siguiente franja/tercio de VRAM
.FIN_FILA:
    DJNZ   .BUCLE_FILAS_CARACTER
    EI
    POP    DE                     ; recupera la posicion VRAM del cursor
    LD     A,E
    ADD    A,8                    ; avanza el cursor 8 columnas para el siguiente caracter
    LD     E,A
    JR     DIBUJAR_TEXTO_INVERTIDO_VRAM_LOOP
; --- Lectura de teclado/joystick (JT_LEER_ENTRADA). Puerta de bloqueo en
; FLAG_ENTRADA_BLOQUEADA (bit 0 -- si esta activo, RET inmediato; ver
; PREPARAR_INICIO_NIVEL/BUSCAR_COLUMNA_HUD, que lo activa mientras dura
; la animacion de busqueda del HUD). El parametro A decide si limpiar
; ACUMULADOR_ENTRADA ($8EC4, byte "libre" del bloque reservado justo
; antes de TABLA_TIPOS_LOSETA) antes de leer (A=0, lectura fresca) o acumular
; sobre el valor ya existente
; (A!=0, permite ir juntando bits de varias llamadas seguidas -- ver
; los AND $3F/AND $06 que comprueban bits concretos en otros sitios).
; Segun (MODO_ENTRADA) despacha a:
;  - LEER_TECLADO (si MODO_ENTRADA=0): escanea la matriz de
;    teclado estandar (5 pares puerto/mascara de TABLA_TECLAS_MSX:
;    arriba/abajo/izquierda/derecha/disparo) mas 1 prueba extra de
;    puerto (COMPROBAR_PAUSA, mismo mecanismo -- CONFIRMADO: las 6
;    acciones redefinibles del menu son "PAUSA/FUEGO/ARRIBA/ABAJO/
;    IZQUIERDA/DERECHA", asi que esta 6a prueba compartida es la
;    tecla de PAUSA, leida siempre por teclado incluso en modo
;    joystick), componiendo bit a bit en E (RL E, desplaza un 1 o un
;    0 segun COMPROBAR_TECLA_MSX) hasta 6 bits.
;  - LEER_JOYSTICK (si MODO_ENTRADA!=0): lee el joystick por el puerto
;    del PSG, y tambien cae en COMPROBAR_PAUSA para la misma 6a
;    prueba compartida.
; NOTA: la polaridad de MODO_ENTRADA aqui (0 -> escaneo de teclado)
; parece invertida respecto a como quedo etiquetado en
; madmix_scr_body.asm -- CONFIRMADO con los valores reales: TI_5C60
; (opcion de menu "1 TECLADO") escribe MODO_ENTRADA=1, TI_5C70
; ("2 JOYSTICK") escribe MODO_ENTRADA=0 -- exactamente al reves de lo
; que interpreta este despachador (1 -> joystick, 0 -> teclado).
; Pendiente verificar en vivo si es un bug real del original o si
; algun otro sitio sin localizar vuelve a tocar la variable entre la
; seleccion del menu y la partida. ---
LEER_ENTRADA:
    LD     HL,FLAG_ENTRADA_BLOQUEADA
    BIT    0,(HL)
    RET    NZ
    LD     HL,ACUMULADOR_ENTRADA
    AND    A
    JR     NZ,.CONTINUAR_TRAS_LIMPIAR_ACUMULADOR
    LD     (HL),A
.CONTINUAR_TRAS_LIMPIAR_ACUMULADOR:
    LD     A,(MODO_ENTRADA)
    AND    A
    JR     Z,LEER_TECLADO
    JP     LEER_JOYSTICK
; --- ESCANEAR_FILAS_TECLADO: bucle generico y REUTILIZABLE de escaneo
; de matriz de teclado -- IX=tabla de B parejas (fila,mascara), E=0 al
; entrar, devuelve en E los B bits leidos (desplazados con RL, 1=tecla
; pulsada). CONFIRMADO compartido: ademas de LEER_TECLADO (5 teclas de
; control + PAUSA en COMPROBAR_PAUSA), lo llama directo TAIL_FONT_ROUTINE
; (madmix_scr_body.asm, con su propia tabla TAIL_UNK_5C93 de 6 parejas,
; todas fila $F0) para leer el menu principal -- pese a su nombre
; ("FONT"), en realidad es el lector de teclas del menu (su resultado
; en E se comprueba bit a bit justo despues de la llamada). ---
LEER_TECLADO:
    LD     IX,TABLA_TECLAS_MSX
    LD     E,$00
    LD     B,$05
ESCANEAR_FILAS_TECLADO:
    CALL   COMPROBAR_TECLA_MSX              ; lee un puerto de la matriz (tabla[IX])
    JR     NZ,.TECLA_NO_PULSADA        ; tecla no pulsada -> mete un 0 en E (abajo)
    SCF
    RL     E                            ; tecla pulsada -> mete un 1 en E (desplazando)
    JP     .CONTINUAR_BUCLE_TECLAS
.TECLA_NO_PULSADA:
    AND    A
    RL     E
.CONTINUAR_BUCLE_TECLAS:
    INC    IX
    INC    IX
    DJNZ   ESCANEAR_FILAS_TECLADO
COMPROBAR_PAUSA:
    LD     IX,TABLA_TECLAS_MSX+10        ; 6a prueba de puerto: tecla PAUSA (mismo mecanismo, entrada final de la tabla)
    CALL   COMPROBAR_TECLA_MSX
    JR     NZ,.FINALIZAR_LECTURA
    SET    5,E
.FINALIZAR_LECTURA:
    LD     A,E
    OR     (HL)                        ; funde (OR) los 6 bits leidos con ACUMULADOR_ENTRADA
    LD     (HL),A
    RET
COMPROBAR_TECLA_MSX:                            ; IX+0=numero de fila/puerto, IX+1=mascara de bit -- lee y enmascara
    LD     A,(IX+$00)
    OUT    ($AA),A
    IN     A,($A9)
    AND    (IX+$01)
    RET

; 0x8E88-0x8E93 (12 bytes): NO es codigo -- tabla de datos real
; (5 pares puerto/mascara para el bucle de LEER_TECLADO -- arriba/
; abajo/izquierda/derecha/disparo -- + 1 par para la tecla de PAUSA de
; COMPROBAR_PAUSA, todos leidos via COMPROBAR_TECLA_MSX con IX
; indexado). El desensamblado lineal se desincroniza aqui igual
; que en el bloque BESTIA/DEMO de mas arriba -- confirmado
; realineando el desensamblado a partir de 0x8E94 (siguiente
; instruccion real), que ya NO coincide con lo que parecia salir
; de seguir leyendo en linea recta.
TABLA_TECLAS_MSX:
    DB $F8,$01                 ; offset 0: arriba
    DB $F4,$40                 ; offset 2: abajo
    DB $F2,$40                 ; offset 4: izquierda
    DB $F4,$10                 ; offset 6: derecha
    DB $F4,$20                 ; offset 8: disparo
    DB $F3,$20                 ; offset 10: pausa (COMPROBAR_PAUSA)
LEER_JOYSTICK:
    LD     A,$07
    OUT    ($A0),A
    IN     A,($A2)
    OR     $C0
    PUSH   AF
    LD     A,$07
    OUT    ($A0),A
    POP    AF
    CALL   CONFIGURAR_Y_LEER_JOYSTICK_PSG  ; termina de poner el mezclador en modo entrada y lee el registro 14 (joystick 1)
    NOP
    LD     E,$00
    RRA                            ; bit0 = arriba
    JR     C,.COMPROBAR_ABAJO
    SET    3,E
.COMPROBAR_ABAJO:
    RRA                            ; bit1 = abajo
    JR     C,.COMPROBAR_IZQUIERDA
    SET    2,E
.COMPROBAR_IZQUIERDA:
    RRA                            ; bit2 = izquierda
    JR     C,.COMPROBAR_DERECHA
    SET    1,E
.COMPROBAR_DERECHA:
    RRA                            ; bit3 = derecha
    JR     C,.COMPROBAR_DISPARO
    SET    0,E
.COMPROBAR_DISPARO:
    RRA                            ; bit4 = disparo
    JR     C,.CONTINUAR_TRAS_DISPARO
    SET    4,E
.CONTINUAR_TRAS_DISPARO:
    LD     A,E
    JR     COMPROBAR_PAUSA


; ==============================================================
;  DATOS: tabla de tipos de loseta
;  El bloque reservado completo es 0x8EC4-0x8F23 (96 bytes = 0x60,
;  termina EXACTO en INICIO/0x8F24 -- verificado, ver historial en
;  FINDINGS.md sobre por que NO son 93 bytes). Los primeros 3 bytes
;  (0x8EC4-0x8EC6, siempre $00 en la ROM) NO son parte de la tabla de
;  tipos -- se reutilizan en RAM como ACUMULADOR_ENTRADA/
;  FLAG_ENTRADA_BLOQUEADA (variables de LEER_ENTRADA, sin relacion
;  con losetas). CONFIRMADO por el unico consumidor real
;  (CONSULTAR_TIPO_LOSETA, aritmetica HL=$8EC7+A/AND $1F): la tabla
;  TABLA_TIPOS_LOSETA en si arranca en 0x8EC7, tres bytes despues del inicio
;  del bloque reservado.
; ==============================================================
ACUMULADOR_ENTRADA:                     ; $8EC4, offset 0 del bloque reservado: siempre $00 en la ROM (loseta tipo 0), reutilizado en RAM como acumulador de resultado de LEER_ENTRADA
    DB $00
    DB $00                                ; $8EC5, offset 1: relleno sin referencia real en el codigo
FLAG_ENTRADA_BLOQUEADA:                 ; $8EC6, offset 2 del bloque reservado: siempre $00 en la ROM (loseta tipo 0), reutilizado en RAM como flag de bloqueo de LEER_ENTRADA
    DB 0
TABLA_TIPOS_LOSETA:                             ; $8EC7 -- aqui arranca de verdad la tabla de tipos (ver cabecera)
    DB 0,0,0,0,0,0,0,0,0,0,0,0,0
    DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DB 1,1,1,2,2,2,3,4,5,6,7,8,9,10,11,12
    DB 13,14,15,15,15,16,0,17,0,15,0,0,18,0,0,0
    DB 0,19,19,0,0,10,10,0,0,0,0,0,0,0,0,0

; ==============================================================
;  ARRANQUE REAL (0x8F24 original, confirmado -- llamado desde
;  START/JT_INICIO con la direccion ESTATICA $8F24; CONFIRMADO por
;  volcado de RAM en vivo que ejecuta desde ahi mismo, sin
;  reubicacion)
;
;  CORREGIDO byte a byte contra el .BIN original (antes esta
;  rutina era un stub inventado). Hallazgos importantes:
;
;  - SP real es $0FFF, NO $FFF0 como se asumia.
;  - "CALL $1000" es una instruccion LITERAL confirmada (bytes
;    CD 00 10): INICIO llama directamente a DIBUJAR_PORTADA
;    (madmix_scr.asm, reubicada en $1000) -- la MISMA rutina que ya
;    ejecuto una vez el cargador (disco: RELOCATOR en madmix0.asm;
;    cinta: LOAD.BIN, ver FINDINGS.md) justo tras reubicar/cargar
;    ese bloque. Osea que la portada se dibuja dos veces al
;    arrancar una partida real: una por el cargador, otra aqui por
;    el propio motor de juego. El motor real (MADMIX1.BIN) sigue en
;    sus direcciones estaticas de siempre, sin reubicacion.
;  - Las 3 llamadas a $C4A0 SI son con indices 0,1,2 y punteros
;    $CDCB/$CDFF/$CE0C, tal cual decia FINDINGS.md -- confirmado.
;  - Las llamadas a direcciones BAJAS que vienen despues ($5D0A =
;    COMPROBAR_PULSACION, $6429 = DIBUJAR_MARCO_CARAMELO_VRAM, $5B56 =
;    MOSTRAR_MENU_PRINCIPAL) ya estan totalmente identificadas -- viven en las
;    direcciones ESTATICAS reales de madmix_scr.asm, no en ningun
;    bloque reubicado.
;  - Esta transcripcion llega hasta donde se ha verificado byte a
;    byte (offset $8F24-$8F71); despues sigue sin transcribir.
; ==============================================================
INICIO:
    LD SP, $0FFF
    CALL ACTIVAR_INTERRUPCION_MODO_1
    DI
    CALL DIBUJAR_PORTADA          ; DIBUJAR_PORTADA (madmix_scr.asm, reubicada en $1000) otra vez -- ver nota arriba
    CALL VACIAR_CANALES_SONIDO   ; = $CF8B, "vacia" ranuras 0,1,2
    XOR A
    LD DE, GUION_MELODIA_CANAL_0
    CALL INSTALAR_RECURSO_SONIDO   ; = $C4A0, indice A=0
    LD A, 1
    LD DE, GUION_MELODIA_CANAL_1
    CALL INSTALAR_RECURSO_SONIDO   ; = $C4A0, indice A=1
    LD A, 2
    LD DE, GUION_MELODIA_CANAL_2
    CALL INSTALAR_RECURSO_SONIDO   ; = $C4A0, indice A=2
.wait_5D0A:
    CALL COMPROBAR_PULSACION          ; COMPROBAR_PULSACION (madmix_scr.asm, identificado) -- se sondea (JR Z en bucle)
    JR Z, .wait_5D0A
    CALL VACIAR_CANALES_SONIDO
    CALL DIBUJAR_MARCO_CARAMELO_VRAM          ; DIBUJAR_MARCO_CARAMELO_VRAM (madmix_scr.asm, identificado)
    EI
REINICIAR_PARTIDA:                  ; CORREGIDO: se llega aqui por 2 caminos -- cayendo desde el
                                    ; arranque real de la maquina (sin salto, justo arriba) o via
                                    ; "JP REINICIAR_PARTIDA" mas abajo, tras el bucle de espera de
                                    ; ~150 frames del mensaje de Game Over (ESPERA_150_FRAMES), no tras
                                    ; "CALL $6454"/APLICAR_COLOR_PANTALLA como decia antes
    CALL VACIAR_CANALES_SONIDO
    CALL MOSTRAR_MENU_PRINCIPAL          ; MOSTRAR_MENU_PRINCIPAL en madmix_scr_body.asm: segundo punto de entrada a la cola de GESTIONAR_INTRODUCCION, saltandose ESPERAR_TECLA_SOLTADA/DIBUJAR_MARCO_CARAMELO_VRAM (no aplican al arranque real). Desde aqui ejecuta VACIAR_CANALES_SONIDO, PROGRAMAR_APAGADO_PANTALLA (apaga pantalla mientras redibuja), LIMPIAR_VRAM_AREA_JUEGO, APLICAR_COLOR_CICLO_NIVELES y DIBUJAR_MENU_PRINCIPAL -- es decir, esta CALL es la que muestra el menu principal al arrancar una partida real
    CALL VACIAR_CANALES_SONIDO
    LD A, 3
    LD (VIDAS_RESTANTES), A
    LD HL, 0
    LD (PUNTUACION), HL
    LD A, 1
    LD (NIVEL_ACTUAL), A
    XOR A
    LD (CONTADOR_VUELTAS_NIVELES), A
PANTALLA_PRESENTACION_NIVEL:          ; reentrada real (JP PANTALLA_PRESENTACION_NIVEL mas abajo) -- este CALL se repite en cada vuelta del bucle principal
    CALL VACIAR_CANALES_SONIDO

; ==============================================================
;  CONTINUACION REAL DE INICIO (0x8F74-0x9134, 449 bytes) --
;  TRANSCRITA COMPLETA, 0 diferencias byte a byte. Es mucho mas que
;  "inicializacion": INICIO nunca hace RET, cae en esta secuencia de
;  arranque/recarga de nivel. CORREGIDO: PREPARAR_INICIO_NIVEL
;  (0x8FD4) NO es el bucle principal del juego -- es la secuencia
;  "nivel recien cargado -> posicionar HUD -> dibujar READY? ->
;  arrancar musica -> esperar al jugador" que se ejecuta solo en las
;  transiciones (arranque, cambio de nivel, perdida de vida), nunca
;  cada frame. El bucle real de cada frame es BUCLE_PRINCIPAL_JUEGO/VERIFICAR_FIN_NIVEL, mas
;  abajo. Resumen (todas las llamadas son a rutinas YA CONFIRMADAS en
;  otros ficheros, lo que corrobora la lectura):
;   - Dibuja 3 lineas de texto de HUD/pantalla via DIBUJAR_TEXTO_VRAM
;     ($5CD1, en madmix_scr.asm) segun el nivel actual ($2C07) y
;     dos flags del registro de nivel ($2C2B/offset7, $2BFA/offset7
;     tambien -- OJO, dos usos distintos de la misma direccion en
;     puntos distintos del arranque).
;   - PREPARAR_INICIO_NIVEL (0x8FD4): cada vuelta llama a
;     VACIAR_CANALES_SONIDO, INICIALIZAR_ITEMS_NIVEL ($5885), REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM
;     ($8C34) y APLICAR_COLOR_PANTALLA ($6454) -- el mismo motor de
;     dibujado/decodificacion de recursos que la pantalla de
;     creditos, reutilizado aqui para el HUD de la partida.
;   - DESTELLO_ICONO_COLOR_HUD: CORREGIDO, no es revelado de texto --
;     copia byte a byte desde un puntero (dentro de TABLA_POSICIONES_HUD)
;     a REGISTRO_NIVEL_ICONO_HUD/COLOR_ACTUAL ($2C04/$2C24), esperando
;     un VBLANK (WAIT_VBLANK, $89A0) entre cada uno -- produce un
;     parpadeo/destello de icono+color, no un mensaje tipo "maquina de
;     escribir" (ver comentario de cabecera de la funcion).
;   - BUCLE_PRINCIPAL_JUEGO/VERIFICAR_FIN_NIVEL en adelante: temporizador de nivel --
;     decrementa vidas/tiempo ($2C27), y hace polling de teclado/
;     joystick (LEER_ENTRADA, $8E3C) esperando una tecla para
;     continuar, con las dos reentradas ya señaladas arriba
;     (PANTALLA_PRESENTACION_NIVEL para la vuelta normal del bucle,
;     REINICIAR_PARTIDA para cuando expira el tiempo de espera).
;   - Termina en 0x9135 con un NOP suelto (relleno de 1 byte); a
;     partir de 0x9136 el desensamblado lineal se desincroniza
;     (zona de datos, ver hueco siguiente).
; ==============================================================

    LD     A,1
    LD     (FLAG_NIVEL_RECIEN_CARGADO),A
    CALL   WAIT_VBLANK
    CALL   CARGAR_NIVEL
    LD     A,(NIVEL_ACTUAL)
    ADD    A,A
    LD     HL,TABLA_NUMEROS_NIVEL
    ADD    A,L
    LD     L,A
    LD     A,H
    ADC    A,$00
    LD     H,A
    LD     DE,TEXTO_FASE+8
    LDI
    LDI
    LD     HL,$0A60             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_FASE
    LD     DE,TEXTO_FASE
    CALL   DIBUJAR_TEXTO_VRAM
    LD     HL,FLAG_VIDA_EXTRA
    LD     A,(HL)
    LD     (HL),0
    AND    A
    JR     Z,SIN_VIDA_EXTRA
    LD     HL,VIDAS_RESTANTES
    ADD    A,(HL)
    CP     5                  ; el numero maximo de vidas es 5 -- por encima no se otorgan mas vidas extra
    JR     NC,SIN_VIDA_EXTRA
    LD     (HL),A
    LD     HL,$0E70             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_EXTRA
    LD     DE,TEXTO_EXTRA
    CALL   DIBUJAR_TEXTO_VRAM
SIN_VIDA_EXTRA:
    LD     A,(REGISTRO_NIVEL_VIDA_EXTRA_FLAG)
    CP     1
    JR     NZ,PAUSA_TEXTO_FASE
    LD     A,(VIDAS_RESTANTES)
    CP     4
    JR     NC,PAUSA_TEXTO_FASE
    LD     HL,$1228             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_VIDA_EXTRA
    LD     DE,TEXTO_VIDA_EXTRA
    CALL   DIBUJAR_TEXTO_VRAM
PAUSA_TEXTO_FASE:
    EI
    LD     B,$50                ; pausa fija de 80 frames
PAUSA_TEXTO_FASE_LOOP:
    HALT
    DJNZ   PAUSA_TEXTO_FASE_LOOP
PREPARAR_INICIO_NIVEL:
    CALL   VACIAR_CANALES_SONIDO  ; vacia las 3 ranuras de sonido antes de recargar el nivel
    CALL   INICIALIZAR_ITEMS_NIVEL                  ; INICIALIZAR_ITEMS_NIVEL (madmix_scr.asm): reinicializa las 3 tablas de items + flags de modo
    CALL   REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM   ; redibuja las franjas de camara + iconos de vida
    CALL   APLICAR_COLOR_PANTALLA                    ; APLICAR_COLOR_PANTALLA (madmix_scr.asm): mismo motor de dibujado que los creditos, reutilizado aqui para el HUD
    LD     A,(MODO_ESPECIAL)
    CP     $03
    LD     A,$0E                             ; comecocos especial (EXCAVATOFONO) para modo especial 3
    JR     Z,.CONTINUAR_RESPAWN        ; si es normal o excavatofono hacemos respwan igual, sino continuamos en modo normal. modo especial 3 (EXCAVATOFONO) activo -> A=$0E (indice de SPR14_PM_OBRA_ABAJO); si no, A=0 (SPR00, normal)
    XOR    A                                 ; comecocos normal (SPR00) para todos los demas modos
.CONTINUAR_RESPAWN:
    LD     (SELECTOR_SPRITE_COMECOCOS),A          ; precarga el sprite/fotograma inicial del comecocos para el primer frame del nivel
    XOR    A
    LD     (DIRECCION_DE_MOVIMIENTO),A
    LD     (DIRECCION_FORZADA),A
    LD     (TEMPORIZADOR_DIRECCION_FORZADA),A
    LD     (TEMPORIZADOR_PARPADEO_BOLA),A
    CALL   REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM   ; otra vez: redibuja camara/vidas tras resetear los flags de modo
    LD     A,$01
    LD     (FLAG_ENTRADA_BLOQUEADA),A             ; bloquea lectura de teclado/joystick mientras dura la busqueda/animacion de mas abajo
    LD     HL,TABLA_POSICIONES_HUD
    LD     A,(TABLA_POSICIONES_HUD+18)
    LD     (COLOR_ACTUAL),A
    LD     A,(TABLA_POSICIONES_HUD+17)
    LD     C,A
; --- Busca en la tabla de 19 bytes de TABLA_POSICIONES_HUD la entrada cuya posicion
; de columna (AND $78) coincide con la camara actual (C): recorre
; entrada a entrada, esperando VBLANK en cada una (efecto de barrido
; visible), hasta encontrar coincidencia. El resultado posiciona el
; HUD ($2C04) y queda tambien en TABLA_POSICIONES_HUD+15 (reutiliza el
; relleno de la tabla como puntero de 2 bytes). CALL ENLACE_MOTOR_MOVIMIENTO_COLISION: RESUELTO
; (ver madmix_scr_body.asm) -- es `JR MOTOR_MOVIMIENTO_COLISION`, un trampolin de
; codigo automodificable en RAM de trabajo, no una direccion sin
; identificar. ---
BUSCAR_COLUMNA_HUD:
    PUSH   BC
    PUSH   HL
; Llamar a ENLACE_MOTOR_MOVIMIENTO_COLISION desde dentro de
; BUSCAR_COLUMNA_HUD no es un efecto secundario accidental: es la
; forma deliberada de dejar avanzar un frame "real" completo (con su
; temporizacion/scroll/timers) mientras la propia maquina de estados
; del motor congela jugador y enemigos gracias al mismo flag que
; activo la busqueda.
    CALL   ENLACE_MOTOR_MOVIMIENTO_COLISION               ; RESUELTO: JR MOTOR_MOVIMIENTO_COLISION (trampolin automodificable, ver madmix_scr_body.asm)
    POP    HL
    POP    BC
    LD     A,C
    AND    $78
    CP     (HL)
    LD     A,(HL)
    LD     (REGISTRO_NIVEL_ICONO_HUD),A
    PUSH   AF
    CALL   WAIT_VBLANK
    POP    AF
    LD     (TABLA_POSICIONES_HUD+15),HL   ;  se guarda la dirección (el puntero de 2 bytes) de la entrada donde se encontró la coincidencia.
    INC    HL
    JR     NZ,BUSCAR_COLUMNA_HUD          ; sin coincidencia todavia -> prueba la siguiente entrada
    XOR    A
; --- Fin de la busqueda de BUSCAR_COLUMNA_HUD (arriba). Desde aqui es otro
; bloque, con otra finalidad: la "presentacion" del inicio de nivel --
; ya no depende del resultado de la busqueda salvo por el color.
; Reactiva el teclado, calcula el color del HUD/READY? a partir de la
; columna objetivo, dibuja las 3 lineas (blanco/READY?/blanco), marca
; FLAG_NIVEL_RECIEN_CARGADO y arranca los 3 canales del soniquete de
; inicio de nivel. Alcanzado solo por caida natural (ningun JP/JR/CALL
; salta aqui directamente). ---
MOSTRAR_READY_Y_ARRANCAR_NIVEL:
    LD     (FLAG_ENTRADA_BLOQUEADA),A             ; vuelve a poner el flag a 0: reactiva la lectura de teclado/joystick en LEER_ENTRADA (bloqueada mientras duraba la busqueda de arriba)
    LD     A,C
    AND    $48
    XOR    $5F
    CALL   OBTENER_COLOR_VDP                ; OBTENER_COLOR_VDP (madmix_scr.asm, ver graficos.html/marco de caramelo): deriva un byte de atributo de color a partir de la columna de camara (C)
    LD     (TEXTO_VACIO_1+1),A    ; escribe ese color en el byte de atributo (offset+1) de TEXTO_VACIO_1
    LD     (TEXTO_READY+1),A       ; ...de TEXTO_READY
    LD     (TEXTO_VACIO_2+1),A     ; ...de TEXTO_VACIO_2 -- las 3 comparten el mismo color, dependiente de la posicion de camara
    LD     HL,$0C60             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_VACIO_1
    LD     DE,TEXTO_VACIO_1
    CALL   DIBUJAR_TEXTO_VRAM                    ; DIBUJAR_TEXTO_VRAM (madmix_scr.asm): dibuja TEXTO_VACIO_1 (linea en blanco, "borra" antes del mensaje)
    LD     HL,$0D60             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_READY
    LD     DE,TEXTO_READY
    CALL   DIBUJAR_TEXTO_VRAM                    ; dibuja TEXTO_READY ("READY?")
    LD     HL,$0E60             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_VACIO_2
    LD     DE,TEXTO_VACIO_2
    CALL   DIBUJAR_TEXTO_VRAM                    ; dibuja TEXTO_VACIO_2 (linea en blanco, "borra" despues del mensaje)
    LD     A,1
    LD     (FLAG_NIVEL_RECIEN_CARGADO),A
    LD     A,$00
    LD     DE,GUION_EVT10_INICIO_NIVEL_CEF0             ; RESUELTO: mismo script que $6128=10 (soniquete de inicio de nivel)
    CALL   INSTALAR_RECURSO_SONIDO_EN_A                       ; INSTALAR_RECURSO_SONIDO_EN_A (entrada directa de INSTALAR_RECURSO_SONIDO, sin busqueda de hueco libre): instala el canal 0
    LD     A,$01
    LD     DE,GUION_EVT10_INICIO_NIVEL_CEF0+7               ; mismo bloque, offset +7 respecto al anterior
    CALL   INSTALAR_RECURSO_SONIDO_EN_A                          ; instala el canal 1
    LD     A,$02
    LD     DE,GUION_EVT10_INICIO_NIVEL_CEF0+14                 ; mismo bloque, offset +7 respecto al anterior (patron que se repite cada 7 bytes)
    CALL   INSTALAR_RECURSO_SONIDO_EN_A                            ; instala el canal 2 -- los 3 canales arrancan aqui, en el mismo punto donde se dibuja TEXTO_READY
    JR     PAUSAR_PARTIDA       ; primera vuelta: entra directo en la espera de 50 frames de abajo, sin sondear teclado antes
; --- Tic real "por frame" del bucle principal. $2C0F es un
; temporizador de respawn/invulnerabilidad (tambien consultado por
; ACTUALIZAR_DESTELLO_ITEMS en madmix_scr.asm): si esta a cero no hace nada mas
; aqui (sigue en VERIFICAR_FIN_NIVEL, el chequeo de fin de nivel); si llega a
; cero JUSTO AHORA, dispara la secuencia de "vida perdida": efecto
; maquina de escribir, realinea la camara a multiplo de 4 losetas, y
; resta una vida. Si quedan vidas, reinicia el bucle principal; si
; no, GAME OVER (rellena el borde, dibuja TEXTO_GAME_OVER, espera y
; reinicia via REINICIAR_PARTIDA). ---
BUCLE_PRINCIPAL_JUEGO:
    CALL   ENLACE_MOTOR_MOVIMIENTO_COLISION                ; RESUELTO: JR MOTOR_MOVIMIENTO_COLISION (misma llamada que en BUSCAR_COLUMNA_HUD)
    CALL   WAIT_VBLANK
    LD     HL,MODO_ESPECIAL_ACTIVO
    LD     A,(HL)
    AND    A
    JR     Z,VERIFICAR_FIN_NIVEL            ; temporizador ya a cero -> nada que hacer aqui, sigue con el chequeo de fin de nivel
    DEC    (HL)
    JR     NZ,VERIFICAR_FIN_NIVEL            ; temporizador aun no llega a cero -> sigue con el chequeo de fin de nivel
    CALL   DESTELLO_ICONO_COLOR_HUD        ; llega a cero ahora: dispara "vida perdida"
    LD     HL,(REGISTRO_NIVEL_POSICION_COMECOCOS)
    LD     A,L
    AND    $FC
    LD     L,A
    LD     (REGISTRO_NIVEL_POSICION_COMECOCOS),HL
    LD     HL,VIDAS_RESTANTES
    LD     A,(HL)
    SUB    $01                      ; $909A = byte operando de este "$01" -- objetivo del truco de
                                     ; vidas infinitas de TI_BREAK (madmix_scr.asm): pulsar ESC en la
                                     ; fila 7 durante el ciclo de demo lo parchea a "SUB $00"
    LD     (HL),A
    JP     NC,PREPARAR_INICIO_NIVEL       ; quedan vidas -> reinicia el bucle principal (redibuja HUD del nivel actual)
    CALL   RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM                    ; sin vidas -> GAME OVER: rellena de $FF el area jugable del buffer RAM BUFFER_LOSETAS_TRABAJO -- CORREGIDO: no es el borde, es el area jugable, y no toca VRAM directamente (la vuelca ACTUALIZAR_VRAM_FRAME). VERIFICADO en vivo por el usuario: el area de juego se pone NEGRA (color de tinta = negro en ese momento) y no hay parpadeo -- es un relleno estatico de una sola vez, no un flash/blink
    CALL   WAIT_VBLANK
    LD     HL,$0C58             ; posicion VRAM (tabla de patrones, SCREEN2) donde se dibuja TEXTO_GAME_OVER
    LD     DE,TEXTO_GAME_OVER
    CALL   DIBUJAR_TEXTO_VRAM                     ; dibuja TEXTO_GAME_OVER ("ESTAS FRITO")
    EI
    LD     B,$96
ESPERA_150_FRAMES:
    HALT
    DJNZ   ESPERA_150_FRAMES               ; espera ~150 frames mostrando el mensaje
    JP     REINICIAR_PARTIDA              ; reinicia la partida (vacia recursos, vidas=3, vuelve al menu principal)
; --- CONFIRMA offsets 18-19 del registro de nivel ($2C05/$2C06,
; ver FINDINGS.md): objetivo de "bolitas a comer" para dar el nivel
; por completado. $2C08 es el contador real (arranca a 0 en cada
; nivel, incrementado por 4 manejadores del motor de colision en
; madmix_scr.asm). Verificado numericamente: coincide EXACTO con la
; cuenta real de losetas 0x2D/0x2E/0x2F en 5 de los 13 niveles
; comprobados (1,8,10,12,13) -- para el resto, probablemente influyen
; las losetas comodin ($3C) y las posiciones de "bola especial"
; adicionales, sin reconciliar del todo. ---
VERIFICAR_FIN_NIVEL:
    CALL   ACTUALIZAR_LOSETA_BOLA_ESPECIAL ; llamada una vez por frame (VERIFICAR_FIN_NIVEL se ejecuta cada frame). Incrementa TEMPORIZADOR_PARPADEO_BOLA y usa su bit 6 (cambia cada 64 incrementos, no cada 4) para escribir $38/$39 en la loseta de POSICION_PARPADEO_BOLA -- CORREGIDO: verificado en vivo por el usuario que esa loseta NO parpadea visiblemente en el juego real; el parpadeo del comecocos que SI se ve en pantalla durante el modo especial es otro mecanismo distinto (ML_POWER_BLINK_COLOR en madmix_scr_body.asm, alterna COLOR_ACTUAL en los ultimos 60 frames del modo).
    LD     HL,(CONTADOR_BOLAS_COMIDAS)
    LD     DE,(REGISTRO_NIVEL_OBJETIVO_BOLAS)
    AND    A
    SBC    HL,DE
    JR     NZ,VERIFICAR_ENTRADA          ; contador aun no alcanza el objetivo -> nivel no completado, sigue esperando input
    LD     HL,NIVEL_ACTUAL
    INC    (HL)                  ; coincide: nivel completado, avanza al siguiente registro
    LD     A,(HL)
    CP     16                     ; RESUELTO: aqui es donde NIVEL_ACTUAL pasa por 15 sin
                                   ; resetear -- tras completar el nivel 14, esto carga el
                                   ; registro 15 de TABLA_NIVELES (madmix_scr_body.asm), el
                                   ; NIVEL 15 (CUERPO_L15). Solo al completarlo
                                   ; TAMBIEN (NIVEL_ACTUAL llega a 16) se resetea abajo.
    JR     NZ,SIGUIENTE_NIVEL            ; no ha llegado a 16 todavia (incluye el nivel 15, oculto) -> continua
    LD     (HL),1                  ; llego a 16 (completo tambien el nivel oculto) -> vuelve al nivel 1
    LD     A,(CONTADOR_VUELTAS_NIVELES)
    INC    A
    LD     (CONTADOR_VUELTAS_NIVELES),A                ; contador de vueltas completas al ciclo de niveles
SIGUIENTE_NIVEL:
    CALL   DESTELLO_ICONO_COLOR_HUD
    LD     A,(REGISTRO_NIVEL_VIDA_EXTRA_FLAG)
    LD     (FLAG_VIDA_EXTRA),A
    JP     PANTALLA_PRESENTACION_NIVEL   ; recarga el HUD para el nivel actual
; --- Nivel todavia no completado: sondea teclado/joystick (bit 5 sin
; identificar todavia -- candidato a tecla de pausa/confirmacion). Si
; no esta activo, vuelve directo al siguiente frame (BUCLE_PRINCIPAL_JUEGO); si
; esta activo, hace una pausa fija de 50 frames y luego sondea hasta
; detectar cualquier tecla/direccion antes de continuar. ---
VERIFICAR_ENTRADA:
    XOR    A
    CALL   LEER_ENTRADA                  ; sondea teclado/joystick
    BIT    5,A                      ; SE HA PULSADO PAUSA/CONFIRMACION? (bit 5 sin identificar todavia)
    JR     Z,SALTAR_A_BUCLE_PRINCIPAL_JUEGO                ; no activo -> siguiente frame sin pausa
PAUSAR_PARTIDA:
    EI
    LD     B,$32
BUCLE_PAUSA:
    HALT
    DJNZ   BUCLE_PAUSA           ; bit activo: pausa fija de 50 frames
IML_POLL_90F2:
    XOR    A
    CALL   LEER_ENTRADA
    AND    $3F
    JR     Z,IML_POLL_90F2               ; sondea hasta detectar cualquier tecla/direccion
    CALL   VACIAR_CANALES_SONIDO  ; detectada: vacia los canales de sonido
SALTAR_A_BUCLE_PRINCIPAL_JUEGO:
    JP     BUCLE_PRINCIPAL_JUEGO                         ; siguiente frame del bucle principal
    CALL   VACIAR_CANALES_SONIDO  ; codigo inalcanzable (el JP de arriba nunca cae aqui)
    JP     $0040                  ; codigo inalcanzable (el JP de arriba nunca cae aqui) 
; --- Parpadeo de la bola especial: incrementa el contador $2C0C
; (reutilizado como reloj de animacion, no como flag de modo aqui) y
; usa su bit 6 (cambia cada 64 llamadas) para escribir en VRAM, en
; la posicion guardada en ($2C0A) -- la posicion de la bola especial,
; fijada por CARGAR_NIVEL -- alternando entre las losetas $38 y $39.
; Llamada una vez por vuelta de VERIFICAR_FIN_NIVEL (una vez por movimiento). ---
ACTUALIZAR_LOSETA_BOLA_ESPECIAL:
    LD     HL,TEMPORIZADOR_PARPADEO_BOLA
    INC    (HL)
    LD     A,(HL)
    AND    $40
    RLCA
    RLCA
    ADD    A,$38
    LD     HL,(POSICION_PARPADEO_BOLA)
    LD     (HL),A
    RET
; --- CORREGIDO: esto NO es una "maquina de escribir" que revela texto.
; Recorre HACIA ATRAS (DEC HL) en TABLA_POSICIONES_HUD desde donde la
; dejo la busqueda de BUSCAR_COLUMNA_HUD (TABLA_POSICIONES_HUD+15),
; copiando cada byte (valores crudos de la tabla, $08/$48/$10/.../$78/
; $40 -- NO codigos de texto/glifo) a REGISTRO_NIVEL_ICONO_HUD ($2C04)
; y COLOR_ACTUAL ($2C24), con una espera de VBLANK entre cada uno,
; hasta leer un $00 (centinela de fin de tabla). Ninguna de las dos
; variables dibuja texto directamente: REGISTRO_NIVEL_ICONO_HUD
; alimenta ACTUALIZAR_VRAM_FRAME, que si cambio respecto al frame
; anterior rellena (FILVRM, relleno solido, no copia de bytes) 18
; bloques de VRAM en $2220; COLOR_ACTUAL se relee ahi mismo TODOS los
; frames sin condicion para rellenar otras 2 zonas de color VRAM
; (ZONA_COLOR_VRAM_DESTELLO_A/B). El efecto real es un PARPADEO/DESTELLO rapido de
; icono+color de transicion, no un revelado letra a letra del "READY?"
; (ese texto se dibuja aparte, de una sola vez, en
; MOSTRAR_READY_Y_ARRANCAR_NIVEL). Guarda tambien el ultimo valor en
; TABLA_POSICIONES_HUD+18, que PREPARAR_INICIO_NIVEL relee la vuelta
; siguiente para restaurar (COLOR_ACTUAL). Pendiente: confirmar en
; vivo (emulador) que aspecto tiene realmente este destello. ---
DESTELLO_ICONO_COLOR_HUD:
    LD     A,(COLOR_ACTUAL)
    LD     (TABLA_POSICIONES_HUD+18),A
    LD     HL,(TABLA_POSICIONES_HUD+15)
IH9116_LOOP:
    PUSH   BC
    PUSH   HL
    POP    HL
    POP    BC
    LD     A,(HL)
    AND    A
    LD     (REGISTRO_NIVEL_ICONO_HUD),A
    LD     (COLOR_ACTUAL),A
    PUSH   AF
    CALL   WAIT_VBLANK
    POP    AF
    DEC    HL
    JP     NZ,IH9116_LOOP        ; sigue hasta leer $00 (centinela de fin de tabla)
    RET
    NOP

; VACIAR_CANALES_SONIDO y INSTALAR_RECURSO_SONIDO ya NO se
; declaran aqui como stubs: viven en su direccion ESTATICA real
; dentro del bloque "GESTOR DE RECURSOS" mas abajo (0xC4A0 y
; 0xCF8B respectivamente, ambas confirmadas por --sym + byte-diff
; contra los CALL reales de INICIO -- ver FINDINGS.md). ACTIVAR_INTERRUPCION_MODO_1
; (el JT_ACTIVAR_INTERRUPCION real, $881B) tampoco se declara aqui como stub: vive
; en su direccion real, ver bloque de ENTRADA_INTERRUPCION_VBLANK mas abajo -- el stub
; que habia aqui antes (con un DI inicial que el original NO tiene)
; era una version inventada/sin verificar, eliminada.

; ==============================================================
;  0x9136-0x92E3 (429 bytes) -- textos reales del HUD/mensajes de
;  partida, mas una tabla de punteros hacia el hueco grafico
;  todavia sin descifrar. Localizados siguiendo las referencias
;  reales del bloque de codigo anterior (continuacion de INICIO).
;
;  TEXTOS CONFIRMADOS (formato [longitud][atributo][texto], igual
;  que las demas tablas de texto ya vistas en madmix_scr.asm):
;   - TEXTO_FASE (" FASE 00"): plantilla del indicador de nivel: el
;     "00" final se sobreescribe en tiempo real con 2 bytes de
;     TABLA_NUMEROS_NIVEL (indexada por nivel*2) antes de dibujarse.
;   - TEXTO_VIDA_EXTRA ("EN LA PROXIMA... EXTRA") y TEXTO_EXTRA
;     ("EXTRA"): aviso de vida extra.
;   - TEXTO_READY ("  READY?  "): el clasico mensaje de inicio de
;     nivel, con dos entradas de blancos (TEXTO_VACIO_1/2) para
;     borrar antes/despues.
;   - TEXTO_GAME_OVER ("ESTAS FRITO"): mensaje de perder una vida --
;     nunca documentado hasta ahora.
;
;  PTR_TABLA_SPRITES (256 bytes, 64 entradas de 4 bytes): cada entrada
;  es [direccion de 16 bits][byte de flag][$18 constante]. Las 64
;  direcciones son CORRELATIVAS con paso fijo de 144 bytes exacto
;  (0x90), de $953B a $B8AB. RESUELTO (ver bloque "SPRITES DE
;  PERSONAJES" mas abajo, 0x953B-0xB93B): es la tabla de punteros a
;  los 64 sprites de personajes (144 bytes cada uno), identificados
;  uno a uno por el usuario jugando al original -- ver
;  recursos/ptrtable_sprites.html. El byte de flag varia entre
;  0x00/0x04/0x06 sin patron obvio identificado todavia; el $18
;  final es constante en las 64 entradas, sin identificar su
;  proposito.
;
;  ICONO_VIDA_EXTRA (32 bytes, justo antes de la tabla de actores
;  en 0x92E3): RESUELTO -- es el ICONO DE VIDA EXTRA del HUD (un
;  comecocos en miniatura, circular con una muesca arriba), NO un
;  tile de laberinto ni relleno. Confirmado por el llamador real:
;  REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM (ver mas abajo, 0x8C34-0x8CB6) lee ($2C27)
;  (contador de vidas) y por cada vida restante llama 2 veces a
;  LDIRVM_INVERTIDO leyendo 16+16 bytes desde HL=$92C3 (los 32 bytes
;  completos), dibujandolos en VRAM con una variante "negada"
;  (CPL antes de cada OUT) en columnas desplazadas $18 (24px) por
;  vida. Ensamblados en el orden real de escritura (2 tiles de 8x8
;  por banda, 2 bandas), forman un circulo con muesca -- el icono
;  clasico de "vida" del jugador. No tiene relacion con
;  PTR_TABLA_SPRITES (esa es la tabla de punteros de los 64 sprites,
;  ver milestone de sprites mas abajo) ni con la fuente de
;  caracteres (la coincidencia de que su rango de direcciones
;  encaje tambien con la formula de DIBUJAR_TEXTO_INVERTIDO_VRAM para codigos $0D-$10
;  es solo eso, una coincidencia de aritmetica de direcciones --
;  no hay ningun llamador que use DIBUJAR_TEXTO_INVERTIDO_VRAM con esos codigos).
;
;  La tabla de 19 bytes al principio (0x9136-0x9148, TABLA_POSICIONES_HUD)
;  se usa en un bucle de BUSQUEDA (BUSCAR_COLUMNA_HUD, ver bloque INICIO anterior:
;  compara contra (TABLA_POSICIONES_HUD+17) AND $78 hasta encontrar
;  coincidencia) -- posible tabla de posiciones de columna HUD, sin
;  confirmar el detalle. Contiene todos los multiplos de 8 entre $08 y
;  $78 (justo el rango que sobrevive a la mascara AND $78), en pares
;  (columna, columna+$40). RESUELTO el porque de esta estructura en
;  pares: el bit 6 (el que distingue columna de columna+$40) es
;  EXACTAMENTE uno de los 2 bits (junto al bit 3) que sobreviven a la
;  mascara AND $48 con la que BUSCAR_COLUMNA_HUD deriva despues el color del
;  HUD/READY? a partir de este mismo valor objetivo (via
;  OBTENER_COLOR_VDP) -- no es una tabla de pares (posicion,color); es
;  una unica variable cuyos bits se reutilizan con dos propositos: el
;  bit 6 decide fila/orden de busqueda Y aporta color a la vez.
; ==============================================================
TABLA_POSICIONES_HUD:
    DB $08,$48, $10,$50, $18,$58, $20,$60
    DB $28,$68, $30,$70, $38,$78, $40
    DB $00,$00,$00,$00      ; offsets 15-18: relleno/valores que se sobreescriben en tiempo real (($9147)/($9148))
TEXTO_FASE:
    DB $08,$B0," FASE 00"
TABLA_NUMEROS_NIVEL:
    DB " 0 1 2 3 4 5 6 7 8 9101112131415"
TEXTO_VIDA_EXTRA:
    DB $16,$F0,"EN LA PROXIMA... EXTRA"
TEXTO_EXTRA:
    DB $05,$60,"EXTRA"
TEXTO_VACIO_1:
    DB $0A,$00,"          "
TEXTO_READY:
    DB $0A,$00,"  READY?  "
TEXTO_VACIO_2:
    DB $0A,$00,"          "
TEXTO_GAME_OVER:
    DB $0B,$60,"ESTAS FRITO"
PTR_TABLA_SPRITES:
    DW SPR00_PM_VULN_DER_CERRADA
    DB $06,$18
    DW SPR01_PM_VULN_DER_BOCA90
    DB $06,$18
    DW SPR02_PM_VULN_DER_BOCA95
    DB $06,$18
    DW SPR03_PM_VULN_ABAJO_CERRADA
    DB $00,$18
    DW SPR04_PM_VULN_ABAJO_SEMI
    DB $00,$18
    DW SPR05_PM_VULN_ABAJO_MAS
    DB $00,$18
    DW SPR06_PM_VULN_ARRIBA
    DB $00,$18
    DW SPR07_PM_INV_DER_CERRADA
    DB $06,$18
    DW SPR08_PM_INV_DER_BOCA90
    DB $06,$18
    DW SPR09_PM_INV_DER_BOCA95
    DB $06,$18
    DW SPR10_PM_INV_ABAJO_CERRADA
    DB $00,$18
    DW SPR11_PM_INV_ABAJO_MAS
    DB $00,$18
    DW SPR12_PM_AVION_ARRIBA
    DB $00,$18
    DW SPR13_PM_OBRA_DER
    DB $04,$18
    DW SPR14_PM_OBRA_ABAJO
    DB $00,$18
    DW SPR15_PM_OBRA_ARRIBA
    DB $00,$18
    DW SPR16_PM_HIPO_DER_1
    DB $00,$18
    DW SPR17_PM_HIPO_DER_2
    DB $00,$18
    DW SPR18_PM_HIPO_DER_3
    DB $00,$18
    DW SPR19_PM_HIPO_ABAJO_1
    DB $00,$18
    DW SPR20_PM_HIPO_ABAJO_2
    DB $00,$18
    DW SPR21_PM_HIPO_ARRIBA_1
    DB $00,$18
    DW SPR22_PM_HIPO_ARRIBA_2
    DB $00,$18
    DW SPR23_PM_TANQUE_DER
    DB $00,$18
    DW SPR24_PM_HIPO_ABAJO_3
    DB $00,$18
    DW SPR25_PM_HIPO_ARRIBA_3
    DB $00,$18
    DW SPR26_DESCONOCIDO_CIRCULOS
    DB $00,$18
    DW SPR27_FANTASMA_DER_1
    DB $00,$18
    DW SPR28_FANTASMA_DER_2
    DB $00,$18
    DW SPR29_FANTASMA_ABAJO_1
    DB $00,$18
    DW SPR30_FANTASMA_ABAJO_2
    DB $00,$18
    DW SPR31_FANTASMA_ARRIBA_1
    DB $00,$18
    DW SPR32_FANTASMA_ARRIBA_2
    DB $00,$18
    DW SPR33_FANTASMA_VULN_DER_1
    DB $00,$18
    DW SPR34_FANTASMA_VULN_DER_2
    DB $00,$18
    DW SPR35_FANTASMA_VULN_ABAJO_1
    DB $00,$18
    DW SPR36_FANTASMA_VULN_ABAJO_2
    DB $00,$18
    DW SPR37_MARIQUITA_ABAJO
    DB $00,$18
    DW SPR38_MARIQUITA_ARRIBA
    DB $00,$18
    DW SPR39_MARIQUITA_DER
    DB $06,$18
    DW SPR40_MUERTE_PM_SEQ0
    DB $00,$18
    DW SPR41_MUERTE_PM_SEQ1
    DB $00,$18
    DW SPR42_MUERTE_PM_SEQ2
    DB $00,$18
    DW SPR43_MUERTE_PM_SEQ3
    DB $00,$18
    DW SPR44_MUERTE_PM_SEQ4
    DB $00,$18
    DW SPR45_REPUGNANTE_DER_1
    DB $06,$18
    DW SPR46_REPUGNANTE_DER_2
    DB $06,$18
    DW SPR47_REPUGNANTE_DER_3
    DB $06,$18
    DW SPR48_REPUGNANTE_ABAJO_1
    DB $00,$18
    DW SPR49_REPUGNANTE_ABAJO_2
    DB $00,$18
    DW SPR50_REPUGNANTE_ABAJO_3
    DB $00,$18
    DW SPR51_REPUGNANTE_ARRIBA_1
    DB $00,$18
    DW SPR52_REPUGNANTE_ARRIBA_2
    DB $00,$18
    DW SPR53_REPUGNANTE_ARRIBA_3
    DB $00,$18
    DW SPR54_REPUGNANTE_DESPEINADO
    DB $00,$18
    DW SPR55_PUNTOS_400
    DB $00,$18
    DW SPR56_PUNTOS_600
    DB $00,$18
    DW SPR57_PM_INV_ABAJO_SEMI
    DB $00,$18
    DW SPR58_MUERTE_PM_RED1
    DB $00,$18
    DW SPR59_MUERTE_PM_RED2
    DB $00,$18
    DW SPR60_MUERTE_PM_RED3
    DB $00,$18
    DW SPR61_MUERTE_PM_RED4
    DB $00,$18
    DW SPR62_FANTASMA_MUERTO
    DB $00,$18
    DW SPR63_NULO
    DB $00,$18
ICONO_VIDA_EXTRA:                  ; icono de vida extra, ver comentario arriba
    INCBIN "data/img/icono_vida.img"
; --------------------------------------------------------------
;  0x92E3-0x953B (600 bytes): FUENTE DE CARACTERES usada por
;  DIBUJAR_TEXTO_VRAM/DIBUJAR_TEXTO_INVERTIDO_VRAM (ver madmix_scr.asm/madmix1.asm) --
;  confirmado por la formula real de DIBUJAR_TEXTO_INVERTIDO_VRAM: direccion de
;  glifo = $925B + codigo*8. Structure: codigos $11-$1F (control,
;  sin usar) y $20 (espacio) son cero real en el .BIN -- glifo
;  en blanco, no relleno inventado. A partir de $21 empiezan los
;  59 glifos reales (signos, digitos, letras mayusculas) usados
;  de verdad por los textos ya transcritos (creditos, menu,
;  marcador, FASE/READY/ESTAS FRITO). Termina justo donde empieza
;  la tabla de sprites (0x953B) -- limite exacto, sin solapar.
; --------------------------------------------------------------

    DS $935B-$, $00   ; codigos $11-$1F sin usar (control), cero real
    DS $9363-$, $00   ; codigo $20 (espacio): glifo en blanco, cero real

TABLA_FUENTE_CARACTERES:
    ; 59 glifos de 8 bytes cada uno, codigos $21 (!) a $5B ([),
    ; extraidos a data/fonts/fuente_caracteres.fnt (ver el propio
    ; fichero para el detalle byte a byte; formato: 8 bytes/glifo,
    ; MSB primero, un bit por pixel, 8x8).
    INCBIN "data/fonts/fuente_caracteres.fnt"


; ==============================================================
;  SPRITES DE PERSONAJES (0x953B-0xB93B, 9216 bytes = 64 x 144)
;  IDENTIFICADOS POR EL USUARIO (jugador original del juego),
;  viendo recursos/ptrtable_sprites.html. TRANSCRITO COMPLETO,
;  0 diferencias byte a byte (verificado compilando el bloque
;  aislado con ORG $953B). Cada entrada es una de las 64 apuntadas
;  por PTR_TABLA_SPRITES (dentro de MOTOR_ACTORES, ver mas arriba).
;
;  DATO IMPORTANTE DE JUGABILIDAD (confirmado por el usuario): los
;  sprites de personajes SOLO incluyen vistas hacia la derecha,
;  abajo y arriba (de espaldas) -- NINGUNO tiene sprite propio hacia
;  la izquierda, casi seguro para ahorrar memoria. Cuando hay que
;  dibujar mirando a la izquierda, el juego probablemente usa el
;  sprite de la derecha invertido horizontalmente en tiempo de
;  ejecucion -- candidato fuerte: una de las dos rutinas
;  DIBUJAR_FILA_DESPLAZADA_DERECHA/DIBUJAR_FILA_DESPLAZADA_IZQUIERDA de MOTOR_ACTORES (desplazamiento a la
;  derecha / a la izquierda respectivamente) hace precisamente ese
;  volteo, en vez de (o ademas de) el desplazamiento de sub-pixel ya
;  documentado -- pendiente de confirmar con mas detalle en el
;  propio codigo.
;
;  Contenido (catalogo completo):
;   - Comecocos: vulnerable/invencible (derecha con 3 fases de
;     boca, abajo con 2-3 fases, arriba solo 1 vista), mas formas
;     especiales del juego: avion, obra (saca bolas), hipopotamo
;     (pisa fantasmas, 3 pasos x 3 direcciones), tanque.
;   - Fantasma: normal y vulnerable (derecha/abajo/arriba, 2 pasos
;     cada uno), mas fantasma muerto (SPR62).
;   - Mariquita (abajo/arriba/derecha, sin animacion de paso).
;   - "Repugnantoso": otro personaje, derecha/abajo/arriba a 3 pasos
;     cada uno, mas una variante "despeinado" sin identificar del
;     todo (SPR54).
;   - Secuencia de MUERTE del comecocos: el orden real de
;     reproduccion (confirmado por el usuario) es 58,59,60,61,
;     40,41,42,43,44 -- NO el orden de los indices de la tabla.
;   - Marcador de puntos por fantasma comido: SPR55 (400) y SPR56
;     (600) -- aparecen temporalmente en la posicion del fantasma
;     comido.
;   - SPR26 y SPR63 sin identificar del todo (el segundo parece un
;     sprite nulo/vacio, todo ceros).
; ==============================================================

; ==============================================================
;  64 SPRITES DE PERSONAJES (0x953B-0xB93B, 9216 bytes, 144 cada
;  uno) -- extraidos a fichero individual por sprite en
;  data/sprites/ (formato 24x48 reagrupado, ver
;  recursos/ptrtable_sprites.html para el catalogo visual
;  completo y FINDINGS.md para el detalle de la identificacion).
; ==============================================================
SPR00_PM_VULN_DER_CERRADA:  ; $953B -- Comecocos vulnerable a la derecha, boca cerrada
    INCBIN "data/sprites/00_pm_vuln_der_cerrada.spr"
SPR01_PM_VULN_DER_BOCA90:  ; $95CB -- Comecocos vulnerable a la derecha, boca abierta 90 grados
    INCBIN "data/sprites/01_pm_vuln_der_boca90.spr"
SPR02_PM_VULN_DER_BOCA95:  ; $965B -- Comecocos vulnerable a la derecha, boca abierta 95 grados (mas abierta)
    INCBIN "data/sprites/02_pm_vuln_der_boca95.spr"
SPR03_PM_VULN_ABAJO_CERRADA:  ; $96EB -- Comecocos vulnerable hacia abajo, boca cerrada
    INCBIN "data/sprites/03_pm_vuln_abajo_cerrada.spr"
SPR04_PM_VULN_ABAJO_SEMI:  ; $977B -- Comecocos vulnerable hacia abajo, boca semi abierta
    INCBIN "data/sprites/04_pm_vuln_abajo_semi.spr"
SPR05_PM_VULN_ABAJO_MAS:  ; $980B -- Comecocos vulnerable hacia abajo, boca mas abierta
    INCBIN "data/sprites/05_pm_vuln_abajo_mas.spr"
SPR06_PM_VULN_ARRIBA:  ; $989B -- Comecocos vulnerable hacia arriba (de espaldas), unica vista
    INCBIN "data/sprites/06_pm_vuln_arriba.spr"
SPR07_PM_INV_DER_CERRADA:  ; $992B -- Comecocos invencible a la derecha, boca cerrada
    INCBIN "data/sprites/07_pm_inv_der_cerrada.spr"
SPR08_PM_INV_DER_BOCA90:  ; $99BB -- Comecocos invencible a la derecha, boca abierta 90 grados
    INCBIN "data/sprites/08_pm_inv_der_boca90.spr"
SPR09_PM_INV_DER_BOCA95:  ; $9A4B -- Comecocos invencible a la derecha, boca abierta 95 grados
    INCBIN "data/sprites/09_pm_inv_der_boca95.spr"
SPR10_PM_INV_ABAJO_CERRADA:  ; $9ADB -- Comecocos invencible hacia abajo, boca cerrada
    INCBIN "data/sprites/10_pm_inv_abajo_cerrada.spr"
SPR11_PM_INV_ABAJO_MAS:  ; $9B6B -- Comecocos invencible hacia abajo, boca mas abierta
    INCBIN "data/sprites/11_pm_inv_abajo_mas.spr"
SPR12_PM_AVION_ARRIBA:  ; $9BFB -- Comecocos convertido en avion, hacia arriba
    INCBIN "data/sprites/12_pm_avion_arriba.spr"
SPR13_PM_OBRA_DER:  ; $9C8B -- Comecocos obra (saca bolas) hacia la derecha
    INCBIN "data/sprites/13_pm_obra_der.spr"
SPR14_PM_OBRA_ABAJO:  ; $9D1B -- Comecocos obra (saca bolas) hacia abajo
    INCBIN "data/sprites/14_pm_obra_abajo.spr"
SPR15_PM_OBRA_ARRIBA:  ; $9DAB -- Comecocos obra (saca bolas) hacia arriba (de espaldas)
    INCBIN "data/sprites/15_pm_obra_arriba.spr"
SPR16_PM_HIPO_DER_1:  ; $9E3B -- Comecocos hipopotamo (pisa fantasmas) a la derecha, paso 1
    INCBIN "data/sprites/16_pm_hipo_der_1.spr"
SPR17_PM_HIPO_DER_2:  ; $9ECB -- Comecocos hipopotamo a la derecha, paso 2
    INCBIN "data/sprites/17_pm_hipo_der_2.spr"
SPR18_PM_HIPO_DER_3:  ; $9F5B -- Comecocos hipopotamo a la derecha, paso 3
    INCBIN "data/sprites/18_pm_hipo_der_3.spr"
SPR19_PM_HIPO_ABAJO_1:  ; $9FEB -- Comecocos hipopotamo hacia abajo, paso 1
    INCBIN "data/sprites/19_pm_hipo_abajo_1.spr"
SPR20_PM_HIPO_ABAJO_2:  ; $A07B -- Comecocos hipopotamo hacia abajo, paso 2
    INCBIN "data/sprites/20_pm_hipo_abajo_2.spr"
SPR21_PM_HIPO_ARRIBA_1:  ; $A10B -- Comecocos hipopotamo hacia arriba, paso 1
    INCBIN "data/sprites/21_pm_hipo_arriba_1.spr"
SPR22_PM_HIPO_ARRIBA_2:  ; $A19B -- Comecocos hipopotamo hacia arriba, paso 2
    INCBIN "data/sprites/22_pm_hipo_arriba_2.spr"
SPR23_PM_TANQUE_DER:  ; $A22B -- Comecocos tanque a la derecha
    INCBIN "data/sprites/23_pm_tanque_der.spr"
SPR24_PM_HIPO_ABAJO_3:  ; $A2BB -- Comecocos hipopotamo hacia abajo, paso 3
    INCBIN "data/sprites/24_pm_hipo_abajo_3.spr"
SPR25_PM_HIPO_ARRIBA_3:  ; $A34B -- Comecocos hipopotamo hacia arriba, paso 3
    INCBIN "data/sprites/25_pm_hipo_arriba_3.spr"
SPR26_DESCONOCIDO_CIRCULOS:  ; $A3DB -- Sprite con cuatro circulos en el centro -- pendiente identificar
    INCBIN "data/sprites/26_desconocido_circulos.spr"
SPR27_FANTASMA_DER_1:  ; $A46B -- Fantasma a la derecha, paso 1
    INCBIN "data/sprites/27_fantasma_der_1.spr"
SPR28_FANTASMA_DER_2:  ; $A4FB -- Fantasma a la derecha, paso 2
    INCBIN "data/sprites/28_fantasma_der_2.spr"
SPR29_FANTASMA_ABAJO_1:  ; $A58B -- Fantasma hacia abajo, paso 1
    INCBIN "data/sprites/29_fantasma_abajo_1.spr"
SPR30_FANTASMA_ABAJO_2:  ; $A61B -- Fantasma hacia abajo, paso 2
    INCBIN "data/sprites/30_fantasma_abajo_2.spr"
SPR31_FANTASMA_ARRIBA_1:  ; $A6AB -- Fantasma hacia arriba (de espaldas), paso 1
    INCBIN "data/sprites/31_fantasma_arriba_1.spr"
SPR32_FANTASMA_ARRIBA_2:  ; $A73B -- Fantasma hacia arriba (de espaldas), paso 2
    INCBIN "data/sprites/32_fantasma_arriba_2.spr"
SPR33_FANTASMA_VULN_DER_1:  ; $A7CB -- Fantasma vulnerable a la derecha, paso 1
    INCBIN "data/sprites/33_fantasma_vuln_der_1.spr"
SPR34_FANTASMA_VULN_DER_2:  ; $A85B -- Fantasma vulnerable a la derecha, paso 2
    INCBIN "data/sprites/34_fantasma_vuln_der_2.spr"
SPR35_FANTASMA_VULN_ABAJO_1:  ; $A8EB -- Fantasma vulnerable hacia abajo, paso 1
    INCBIN "data/sprites/35_fantasma_vuln_abajo_1.spr"
SPR36_FANTASMA_VULN_ABAJO_2:  ; $A97B -- Fantasma vulnerable hacia abajo, paso 2
    INCBIN "data/sprites/36_fantasma_vuln_abajo_2.spr"
SPR37_MARIQUITA_ABAJO:  ; $AA0B -- Mariquita hacia abajo
    INCBIN "data/sprites/37_mariquita_abajo.spr"
SPR38_MARIQUITA_ARRIBA:  ; $AA9B -- Mariquita hacia arriba
    INCBIN "data/sprites/38_mariquita_arriba.spr"
SPR39_MARIQUITA_DER:  ; $AB2B -- Mariquita a la derecha
    INCBIN "data/sprites/39_mariquita_der.spr"
SPR40_MUERTE_PM_SEQ0:  ; $ABBB -- Muerte comecocos (bola pequenya), secuencia 0
    INCBIN "data/sprites/40_muerte_pm_seq0.spr"
SPR41_MUERTE_PM_SEQ1:  ; $AC4B -- Muerte comecocos (bola grande), secuencia 1
    INCBIN "data/sprites/41_muerte_pm_seq1.spr"
SPR42_MUERTE_PM_SEQ2:  ; $ACDB -- Muerte comecocos (descomposicion), secuencia 2
    INCBIN "data/sprites/42_muerte_pm_seq2.spr"
SPR43_MUERTE_PM_SEQ3:  ; $AD6B -- Muerte comecocos (descomposicion), secuencia 3
    INCBIN "data/sprites/43_muerte_pm_seq3.spr"
SPR44_MUERTE_PM_SEQ4:  ; $ADFB -- Muerte comecocos (descomposicion), secuencia 4 -- ultimo sprite de la muerte
    INCBIN "data/sprites/44_muerte_pm_seq4.spr"
SPR45_REPUGNANTE_DER_1:  ; $AE8B -- Repugnantoso a la derecha, paso 1
    INCBIN "data/sprites/45_repugnante_der_1.spr"
SPR46_REPUGNANTE_DER_2:  ; $AF1B -- Repugnantoso a la derecha, paso 2
    INCBIN "data/sprites/46_repugnante_der_2.spr"
SPR47_REPUGNANTE_DER_3:  ; $AFAB -- Repugnantoso a la derecha, paso 3
    INCBIN "data/sprites/47_repugnante_der_3.spr"
SPR48_REPUGNANTE_ABAJO_1:  ; $B03B -- Repugnantoso hacia abajo, paso 1
    INCBIN "data/sprites/48_repugnante_abajo_1.spr"
SPR49_REPUGNANTE_ABAJO_2:  ; $B0CB -- Repugnantoso hacia abajo, paso 2
    INCBIN "data/sprites/49_repugnante_abajo_2.spr"
SPR50_REPUGNANTE_ABAJO_3:  ; $B15B -- Repugnantoso hacia abajo, paso 3
    INCBIN "data/sprites/50_repugnante_abajo_3.spr"
SPR51_REPUGNANTE_ARRIBA_1:  ; $B1EB -- Repugnantoso hacia arriba (de espaldas), paso 1
    INCBIN "data/sprites/51_repugnante_arriba_1.spr"
SPR52_REPUGNANTE_ARRIBA_2:  ; $B27B -- Repugnantoso hacia arriba (de espaldas), paso 2
    INCBIN "data/sprites/52_repugnante_arriba_2.spr"
SPR53_REPUGNANTE_ARRIBA_3:  ; $B30B -- Repugnantoso hacia arriba (de espaldas), paso 3
    INCBIN "data/sprites/53_repugnante_arriba_3.spr"
SPR54_REPUGNANTE_DESPEINADO:  ; $B39B -- Repugnantoso despeinado hacia abajo (?) -- pendiente identificar
    INCBIN "data/sprites/54_repugnante_despeinado.spr"
SPR55_PUNTOS_400:  ; $B42B -- 400 puntos (aparece donde se comio un fantasma)
    INCBIN "data/sprites/55_puntos_400.spr"
SPR56_PUNTOS_600:  ; $B4BB -- 600 puntos (aparece donde se comio un fantasma)
    INCBIN "data/sprites/56_puntos_600.spr"
SPR57_PM_INV_ABAJO_SEMI:  ; $B54B -- Comecocos invencible hacia abajo, boca semi abierta
    INCBIN "data/sprites/57_pm_inv_abajo_semi.spr"
SPR58_MUERTE_PM_RED1:  ; $B5DB -- Muerte comecocos hacia abajo, triste, reduccion 1 -- inicio real de la secuencia de muerte
    INCBIN "data/sprites/58_muerte_pm_red1.spr"
SPR59_MUERTE_PM_RED2:  ; $B66B -- Muerte comecocos a la derecha, triste, reduccion 2
    INCBIN "data/sprites/59_muerte_pm_red2.spr"
SPR60_MUERTE_PM_RED3:  ; $B6FB -- Muerte comecocos hacia arriba (de espaldas), reduccion 3
    INCBIN "data/sprites/60_muerte_pm_red3.spr"
SPR61_MUERTE_PM_RED4:  ; $B78B -- Muerte comecocos, izquierda, triste, reduccion 4 -- sigue en SPR40
    INCBIN "data/sprites/61_muerte_pm_red4.spr"
SPR62_FANTASMA_MUERTO:  ; $B81B -- Fantasma muerto
    INCBIN "data/sprites/62_fantasma_muerto.spr"
SPR63_NULO:  ; $B8AB -- Sprite nulo (blanco o negro, todo ceros)
    INCBIN "data/sprites/63_nulo.spr"

; --------------------------------------------------------------
;  Hueco 0xB93B-0xB940 (5 bytes): cola sin identificar justo
;  antes de GRAFICOS_LOSETAS. Contenido real: $00,$FF,$FF,$FF,$FF.
; --------------------------------------------------------------
    DB $00,$FF,$FF,$FF,$FF



; ==============================================================
;  DATOS BINARIOS GRANDES -- via INCBIN
; ==============================================================
; 2912 bytes = exacto 0xB940-0xC4A0, 91 losetas de 32 bytes cada
; una (formato 16x16, 2 bytes/fila) -- extraidas a fichero individual
; por loseta en data/tiles/ (ver graficos.html para el catalogo
; visual completo de cada una).
GRAFICOS_LOSETAS:
    INCBIN "data/tiles/00_muro_hierro_pieza_individual.til"  ; tile 0
    INCBIN "data/tiles/01_muro_hierro_limite_superior_vertical.til"  ; tile 1
    INCBIN "data/tiles/02_muro_hierro_pared_vertical.til"  ; tile 2
    INCBIN "data/tiles/03_muro_hierro_limite_inferior_vertical.til"  ; tile 3
    INCBIN "data/tiles/04_muro_hierro_limite_izquierdo_horizontal.til"  ; tile 4
    INCBIN "data/tiles/05_muro_hierro_pared_horizontal.til"  ; tile 5
    INCBIN "data/tiles/06_muro_hierro_limite_derecho_horizontal.til"  ; tile 6
    INCBIN "data/tiles/07_muro_hierro_esquina_inf_izq.til"  ; tile 7
    INCBIN "data/tiles/08_muro_hierro_esquina_inf_der.til"  ; tile 8
    INCBIN "data/tiles/09_muro_hierro_esquina_sup_izq.til"  ; tile 9
    INCBIN "data/tiles/10_muro_hierro_esquina_sup_der.til"  ; tile 10
    INCBIN "data/tiles/11_muro_hierro_horizontal_union_abajo.til"  ; tile 11
    INCBIN "data/tiles/12_muro_hierro_horizontal_union_arriba.til"  ; tile 12
    INCBIN "data/tiles/13_muro_hierro_vertical_union_derecha.til"  ; tile 13
    INCBIN "data/tiles/14_muro_hierro_vertical_union_izquierda.til"  ; tile 14
    INCBIN "data/tiles/15_muro_hierro_cruce.til"  ; tile 15
    INCBIN "data/tiles/16_muro_cemento_pieza_individual.til"  ; tile 16
    INCBIN "data/tiles/17_muro_cemento_limite_superior_vertical.til"  ; tile 17
    INCBIN "data/tiles/18_muro_cemento_pared_vertical.til"  ; tile 18
    INCBIN "data/tiles/19_muro_cemento_limite_inferior_vertical.til"  ; tile 19
    INCBIN "data/tiles/20_muro_cemento_limite_izquierdo_horizontal.til"  ; tile 20
    INCBIN "data/tiles/21_muro_cemento_pared_horizontal.til"  ; tile 21
    INCBIN "data/tiles/22_muro_cemento_limite_derecho_horizontal.til"  ; tile 22
    INCBIN "data/tiles/23_muro_cemento_esquina_inf_izq.til"  ; tile 23
    INCBIN "data/tiles/24_muro_cemento_esquina_inf_der.til"  ; tile 24
    INCBIN "data/tiles/25_muro_cemento_esquina_sup_izq.til"  ; tile 25
    INCBIN "data/tiles/26_muro_cemento_esquina_sup_der.til"  ; tile 26
    INCBIN "data/tiles/27_muro_cemento_horizontal_union_abajo.til"  ; tile 27
    INCBIN "data/tiles/28_muro_cemento_horizontal_union_arriba.til"  ; tile 28
    INCBIN "data/tiles/29_muro_cemento_vertical_union_derecha.til"  ; tile 29
    INCBIN "data/tiles/30_muro_cemento_vertical_union_izquierda.til"  ; tile 30
    INCBIN "data/tiles/31_muro_cemento_cruce.til"  ; tile 31
    INCBIN "data/tiles/32_muro_ladrillo_pieza_individual.til"  ; tile 32
    INCBIN "data/tiles/33_muro_ladrillo_limite_superior_vertical.til"  ; tile 33
    INCBIN "data/tiles/34_muro_ladrillo_pared_vertical.til"  ; tile 34
    INCBIN "data/tiles/35_muro_ladrillo_limite_inferior_vertical.til"  ; tile 35
    INCBIN "data/tiles/36_muro_ladrillo_limite_izquierdo_horizontal.til"  ; tile 36
    INCBIN "data/tiles/37_muro_ladrillo_pared_horizontal.til"  ; tile 37
    INCBIN "data/tiles/38_muro_ladrillo_limite_derecho_horizontal.til"  ; tile 38
    INCBIN "data/tiles/39_muro_ladrillo_esquina_inf_izq.til"  ; tile 39
    INCBIN "data/tiles/40_muro_ladrillo_esquina_inf_der.til"  ; tile 40
    INCBIN "data/tiles/41_muro_ladrillo_esquina_sup_izq.til"  ; tile 41
    INCBIN "data/tiles/42_muro_ladrillo_esquina_sup_der.til"  ; tile 42
    INCBIN "data/tiles/43_muro_ladrillo_horizontal_union_abajo.til"  ; tile 43
    INCBIN "data/tiles/44_muro_ladrillo_horizontal_union_arriba.til"  ; tile 44
    INCBIN "data/tiles/45_suelo_con_bola_1.til"  ; tile 45
    INCBIN "data/tiles/46_suelo_con_bola_2.til"  ; tile 46
    INCBIN "data/tiles/47_suelo_con_bola_3.til"  ; tile 47
    INCBIN "data/tiles/48_suelo_con_bola_clavada_1.til"  ; tile 48
    INCBIN "data/tiles/49_suelo_con_bola_clavada_2.til"  ; tile 49
    INCBIN "data/tiles/50_suelo_con_bola_clavada_3.til"  ; tile 50
    INCBIN "data/tiles/51_flecha_arriba.til"  ; tile 51
    INCBIN "data/tiles/52_flecha_abajo.til"  ; tile 52
    INCBIN "data/tiles/53_flecha_izquierda.til"  ; tile 53
    INCBIN "data/tiles/54_flecha_derecha.til"  ; tile 54
    INCBIN "data/tiles/55_pista_tanque_vertical.til"  ; tile 55
    INCBIN "data/tiles/56_linea_electrica_puerta_fantasmas_a.til"  ; tile 56
    INCBIN "data/tiles/57_linea_electrica_puerta_fantasmas_b.til"  ; tile 57
    INCBIN "data/tiles/58_pista_avion_recto.til"  ; tile 58
    INCBIN "data/tiles/59_item_suelo_sin_confirmar.til"  ; tile 59
    INCBIN "data/tiles/60_item_bola_de_poder.til"  ; tile 60
    INCBIN "data/tiles/61_item_hipopotamo.til"  ; tile 61
    INCBIN "data/tiles/62_item_herramienta.til"  ; tile 62
    INCBIN "data/tiles/63_suelo_sin_bola_1.til"  ; tile 63
    INCBIN "data/tiles/64_suelo_sin_bola_2.til"  ; tile 64
    INCBIN "data/tiles/65_suelo_sin_bola_3.til"  ; tile 65
    INCBIN "data/tiles/66_loseta_solida_negra.til"  ; tile 66
    INCBIN "data/tiles/67_trampilla_a_abajo_izquierda.til"  ; tile 67
    INCBIN "data/tiles/68_trampilla_a_abajo_derecha.til"  ; tile 68
    INCBIN "data/tiles/69_trampilla_b_abajo_derecha.til"  ; tile 69
    INCBIN "data/tiles/70_muro_ladrillo_suelto.til"  ; tile 70
    INCBIN "data/tiles/71_trampilla_b_arriba_izquierda.til"  ; tile 71
    INCBIN "data/tiles/72_trampilla_b_arriba_derecha.til"  ; tile 72
    INCBIN "data/tiles/73_trampilla_b_abajo_izquierda.til"  ; tile 73
    INCBIN "data/tiles/74_trampilla_a_arriba_izquierda.til"  ; tile 74
    INCBIN "data/tiles/75_trampilla_a_arriba_derecha.til"  ; tile 75
    INCBIN "data/tiles/76_trampilla_transicion_arriba_izquierda.til"  ; tile 76
    INCBIN "data/tiles/77_trampilla_transicion_arriba_derecha.til"  ; tile 77
    INCBIN "data/tiles/78_trampilla_transicion_abajo_izquierda.til"  ; tile 78
    INCBIN "data/tiles/79_trampilla_transicion_abajo_derecha.til"  ; tile 79
    INCBIN "data/tiles/80_puerta_fantasmas_inicio_izquierdo.til"  ; tile 80
    INCBIN "data/tiles/81_puerta_fantasmas_inicio_derecho.til"  ; tile 81
    INCBIN "data/tiles/82_pista_avion_remate_izquierdo.til"  ; tile 82
    INCBIN "data/tiles/83_pista_avion_remate_derecho.til"  ; tile 83
    INCBIN "data/tiles/84_mosaico_comecocos_1.til"  ; tile 84
    INCBIN "data/tiles/85_mosaico_comecocos_2.til"  ; tile 85
    INCBIN "data/tiles/86_mosaico_comecocos_3.til"  ; tile 86
    INCBIN "data/tiles/87_mosaico_comecocos_4.til"  ; tile 87
    INCBIN "data/tiles/88_estrella_pequena.til"  ; tile 88
    INCBIN "data/tiles/89_estrella_mediana.til"  ; tile 89
    INCBIN "data/tiles/90_estrella_grande.til"  ; tile 90

; ==============================================================
;  GESTOR DE RECURSOS (0xC4A0-0xD000) -- IDENTIFICADO: es el
;  DRIVER DE SONIDO/MUSICA del PSG (AY-3-8910, puertos $A0/$A1),
;  transcrito byte a byte completo desde el desensamblado de
;  Z80Dasm.exe. Encaja con el credito real "MUSIC-A BY: COMILONAS"
;  (con guion, no "MUSICA") hallado en la pantalla de creditos
;  (madmix_scr.asm). Resumen:
;
;   - INSTALAR_RECURSO_SONIDO (0xC4A0): busca hueco libre entre
;     4 "ranuras" de 46 bytes ($2E) en una tabla en 0xC9C9 (D=3
;     iteraciones tras la primera = 4 en total), y si lo encuentra
;     lo inicializa a cero y guarda el puntero DE (el recurso, un
;     script de musica/SFX) dos veces (offsets +0/1 y +2/3).
;   - INSTALAR_RECURSO_SONIDO_EN_A: helper interno, identico pero con indice EXPLICITO
;     en A (no busca hueco) -- inicializa la ranura A y guarda DE.
;   - PROCESAR_CANAL_PSG (bucle principal del reproductor, B=3 ranuras): por
;     cada ranura activa (campo +4/5 = contador de "espera"), si
;     no esta esperando, lee un byte de comando desde el puntero
;     de script (BC, offsets +2/3): bytes >=0x80 son comandos (via
;     TABLA_COMANDOS_PSG, tabla de salto de 15 comandos: nueva nota/
;     instrumento, ligar volumen a un canal companero, activar/
;     desactivar SFX, terminar/repetir script, etc.), bytes <0x80
;     son duracion de nota (indexados en TABLA_NOTAS_PSG, tabla de
;     96 palabras de retardo en tics). El resultado final de cada
;     ranura se copia a los registros del PSG en VOLCAR_REGISTROS_PSG (bucle de
;     11 registros, puerto $A0=numero de registro, $A1=valor).
;   - Los 3 punteros de script que instala INICIO ($CDCB/$CDFF/$CE0C,
;     ver INICIO mas arriba) caen dentro del bloque de datos de abajo
;     -- son 3 recursos reales (musica + 2 efectos, o similar),
;     confirmando que este bloque completo (datos incluidos) es
;     el contenido real del "gestor de recursos", no relleno.
;   - VACIAR_CANALES_SONIDO vive en 0xCF8B (CONFIRMADO: era la
;     direccion ya sospechada antes de desensamblar este bloque;
;     un primer intento de esta sesion la desplazo por error a
;     0xCF8E al clasificar mal 3 bytes de codigo como datos --
;     detectado y corregido via --sym + byte-diff contra los CALL
;     reales de INICIO) -- llama 3 veces a INSTALAR_RECURSO_SONIDO_EN_A con A=0,1,2,
;     fijando siempre DE=$0000 justo antes de cada llamada.
;   - No se ha intentado descomponer los ~1700 bytes de tablas y
;     scripts en su significado nota a nota (fuera de alcance de
;     este proyecto de preservacion binaria) -- se transcriben
;     como datos crudos, verificados byte a byte contra el .BIN
;     original.
; ==============================================================
INSTALAR_RECURSO_SONIDO:                 ; = $C4A0 (confirmado)
    PUSH   AF
    PUSH   DE
    AND    $7F                    ; descarta el bit 7 del indice de recurso
    LD     DE,46                  ; 46 = tamano de una ranura de canal
    CALL   MULTIPLICAR_8X16
    LD     DE,$C9C9               ; $C9C9 = tabla de 3 ranuras de canal (dentro de AREA_TRABAJO_PSG, offset +13)
    ADD    HL,DE
    PUSH   HL
    LD     A,(HL)
    INC    HL
    OR     (HL)
    JR     Z,.USAR_RANURA_SOLICITADA
    LD     D,3                    ; 3 ranuras de canal a probar
    LD     HL,$C9C9
    LD     BC,46                  ; 46 = paso entre ranuras (mismo tamano de arriba)
.BUSCAR_RANURA_LIBRE:
    INC    HL
    LD     A,(HL)
    DEC    HL
    OR     (HL)
    JR     Z,.USAR_RANURA_ENCONTRADA
    ADD    HL,BC
    DEC    D
    JR     NZ,.BUSCAR_RANURA_LIBRE
.USAR_RANURA_SOLICITADA:
    POP    HL
    JR     LIMPIAR_E_INSTALAR_RANURA
.USAR_RANURA_ENCONTRADA:
    POP    DE
    JR     LIMPIAR_E_INSTALAR_RANURA
; --- INSTALAR_RECURSO_SONIDO_EN_A: mismo cuerpo que INSTALAR_RECURSO_SONIDO (limpia la
; ranura de 46 bytes y guarda el puntero DE dos veces) pero con el
; indice de ranura EXPLICITO en A, sin buscar hueco libre -- lo usan
; VACIAR_CANALES_SONIDO e BUSCAR_COLUMNA_HUD (madmix1.asm) para instalar un
; recurso en una ranura concreta (0/1/2) directamente. ---
INSTALAR_RECURSO_SONIDO_EN_A:
    PUSH   AF
    PUSH   DE
    LD     DE,46                  ; 46 = tamano de una ranura de canal
    CALL   MULTIPLICAR_8X16
    LD     DE,$C9C9
    ADD    HL,DE
LIMPIAR_E_INSTALAR_RANURA:
    PUSH   HL
    XOR    A
    LD     B,46                   ; 46 bytes a limpiar (tamano de una ranura completa)
.BUCLE_LIMPIAR_RANURA:
    LD     (HL),A
    INC    HL
    DJNZ   .BUCLE_LIMPIAR_RANURA
    POP    HL
    POP    DE
    LD     (HL),E                 ; guarda el puntero DE dos veces (offsets 0-1 y 2-3 de la ranura)
    INC    HL
    LD     (HL),D
    INC    HL
    LD     (HL),E
    INC    HL
    LD     (HL),D
    POP    AF
    RET
; --- TICK_REPRODUCTOR_PSG: punto de entrada real del "tick" del
; reproductor PSG -- llamado desde DESPACHAR_EFECTO_SONIDO ($60DC,
; madmix_scr.asm) en CADA VBLANK (ver RESUELTO "$6128 es el indice de
; efecto de sonido", FINDINGS.md). Prepara punteros (IX=tabla de
; canales $C9C9, DE=sombra de registros PSG $C9BE, HL=$C9C6) y entra
; en el bucle de 3 canales PROCESAR_CANAL_PSG. ---
TICK_REPRODUCTOR_PSG:
    PUSH   AF
    LD     B,3                    ; 3 canales del PSG
    XOR    A
    LD     IX,$C9C9
    LD     DE,$C9BE
    LD     HL,$C9C6
PROCESAR_CANAL_PSG:
    PUSH   AF
    PUSH   HL
    PUSH   DE
    PUSH   BC
    LD     (AREA_TRABAJO_PSG),A
    LD     A,(IX+$04)
    OR     (IX+$05)
    JP     NZ,APLICAR_ENVOLVENTES_CANAL
    XOR    A
    CALL   ACTUALIZAR_MEZCLADOR_CANAL
    LD     C,(IX+$02)
    LD     B,(IX+$03)
    LD     A,B
    OR     C
    JP     Z,COMBINAR_Y_ESCRIBIR_CANAL
DESPACHAR_COMANDO_PSG:
    LD     A,(BC)
    CP     $80                    ; byte < $80 = nota+duracion, byte >= $80 = comando (bit7 como marca de formato)
    JP     C,.RESOLVER_NOTA
    SUB    $80                    ; resta la base de comando para indexar TABLA_COMANDOS_PSG (0-14)
    LD     HL,TABLA_COMANDOS_PSG
    CALL   LEER_PALABRA_INDEXADA
    JP     (HL)
.RESOLVER_NOTA:
    PUSH   AF
    CALL   OBTENER_PUNTERO_TRANSPOSICION
    POP    AF
    ADD    A,(HL)
    LD     HL,TABLA_NOTAS_PSG
    CALL   LEER_PALABRA_INDEXADA
    LD     (IX+$0A),L
    LD     (IX+$0B),H
    INC    BC
ARMAR_NOTA:
    LD     A,(IX+$08)
    CALL   ACTUALIZAR_MEZCLADOR_CANAL
    CALL   REINICIAR_ENVOLVENTE_VOLUMEN
    LD     (IX+$2A),$00
    CALL   REINICIAR_ENVOLVENTE_TONO
    LD     (IX+$2B),$00
    LD     (IX+$2C),$00
CERRAR_NOTA:
    LD     (IX+$02),C
    LD     (IX+$03),B
    LD     L,(IX+$06)
    LD     H,(IX+$07)
    LD     (IX+$04),L
    LD     (IX+$05),H
; --- APLICAR_ENVOLVENTES_CANAL: decrementa el contador de tics de la
; nota en curso y aplica un paso de las 2 envolventes del canal (ver
; tabla de offsets en FINDINGS.md, "RESUELTO: los 15 comandos..."):
; volumen (+$0C/+$0E/+$1B/+$20 -> acumulador +$2A, 4 bits) y tono/
; deslizamiento (+$10/+$13/+$1D/+$22 -> acumulador +$2B/+$2C, 16 bits
; con signo). Cada envolvente tiene cuenta atras al siguiente paso,
; pasos restantes, incremento por paso y periodo de recarga; si se
; agota del todo, REINICIAR_ENVOLVENTE_VOLUMEN/TONO la reinician desde
; sus valores de instrumento (+$16/+$20 y +$18/+$22). Termina en
; COMBINAR_Y_ESCRIBIR_CANAL, que suma acumuladores + base y escribe
; los registros de volumen/tono del PSG. ---
APLICAR_ENVOLVENTES_CANAL:
    LD     L,(IX+$04)
    LD     H,(IX+$05)
    DEC    HL
    LD     (IX+$04),L
    LD     (IX+$05),H
    PUSH   IX
    POP    IY
    LD     D,2                    ; 2 fases de volumen (instrumento: repeticiones fase1/fase2)
    LD     C,$00
.BUCLE_ENVOLVENTE_VOLUMEN:
    LD     A,(IY+$0C)
    OR     A
    JR     Z,.RECARGAR_PASO_ENVOLVENTE_VOLUMEN
    DEC    A
    LD     (IY+$0C),A
    INC    C
    JR     .FIN_ENVOLVENTE_VOLUMEN
.RECARGAR_PASO_ENVOLVENTE_VOLUMEN:
    LD     A,(IY+$0E)
    OR     A
    JR     Z,.CONTINUAR_ENVOLVENTE_VOLUMEN
    DEC    A
    LD     (IY+$0E),A
    LD     A,(IX+$2A)
    ADD    A,(IY+$1B)
    LD     (IX+$2A),A
    LD     A,(IY+$20)
    LD     (IY+$0C),A
    INC    C
    JR     .FIN_ENVOLVENTE_VOLUMEN
.CONTINUAR_ENVOLVENTE_VOLUMEN:
    INC    IY
    DEC    D
    JR     NZ,.BUCLE_ENVOLVENTE_VOLUMEN
.FIN_ENVOLVENTE_VOLUMEN:
    LD     A,C
    OR     A
    JR     NZ,.INICIAR_ENVOLVENTE_TONO
    BIT    0,(IX+$2D)
    CALL   NZ,REINICIAR_ENVOLVENTE_VOLUMEN
.INICIAR_ENVOLVENTE_TONO:
    PUSH   IX
    POP    IY
    LD     D,3                    ; 3 fases de tono (instrumento: repeticiones fase1/2/3)
    LD     C,$00
.BUCLE_ENVOLVENTE_TONO:
    LD     A,(IY+$10)
    OR     A
    JR     Z,.RECARGAR_PASO_ENVOLVENTE_TONO
    DEC    A
    LD     (IY+$10),A
    INC    C
    JR     .FIN_ENVOLVENTE_TONO
.RECARGAR_PASO_ENVOLVENTE_TONO:
    LD     A,(IY+$13)
    OR     A
    JR     Z,.CONTINUAR_ENVOLVENTE_TONO
    DEC    A
    LD     (IY+$13),A
    LD     A,(IY+$1D)
    OR     A
    JP     P,.SUMAR_PASO_ENVOLVENTE_TONO
    LD     A,(IY+$1D)
    CPL
    INC    A
    LD     E,A
    LD     A,(IX+$2B)
    SUB    E
    LD     (IX+$2B),A
    LD     A,(IX+$2C)
    SBC    A,$00
    AND    $0F
    LD     (IX+$2C),A
    JR     .CONTINUAR_TRAS_PASO_ENVOLVENTE_TONO
.SUMAR_PASO_ENVOLVENTE_TONO:
    LD     A,(IX+$2B)
    ADD    A,(IY+$1D)
    LD     (IX+$2B),A
    LD     A,(IX+$2C)
    ADC    A,$00
    AND    $0F
    LD     (IX+$2C),A
.CONTINUAR_TRAS_PASO_ENVOLVENTE_TONO:
    LD     A,(IY+$22)
    LD     (IY+$10),A
    INC    C
    JR     .FIN_ENVOLVENTE_TONO
.CONTINUAR_ENVOLVENTE_TONO:
    INC    IY
    DEC    D
    JR     NZ,.BUCLE_ENVOLVENTE_TONO
.FIN_ENVOLVENTE_TONO:
    LD     A,C
    OR     A
    JR     NZ,COMBINAR_Y_ESCRIBIR_CANAL
    BIT    1,(IX+$2D)
    CALL   NZ,REINICIAR_ENVOLVENTE_TONO
COMBINAR_Y_ESCRIBIR_CANAL:
    POP    BC
    POP    DE
    POP    HL
    LD     A,(IX+$09)
    ADD    A,(IX+$2A)
    AND    $0F
    LD     (HL),A
    LD     A,(IX+$0A)
    ADD    A,(IX+$2B)
    LD     (DE),A
    INC    DE
    LD     A,(IX+$0B)
    ADC    A,(IX+$2C)
    LD     (DE),A
    INC    DE
    PUSH   DE
    LD     DE,46                  ; 46 = tamano de ranura, avanza IX a la siguiente ranura de canal
    ADD    IX,DE
    POP    DE
    POP    AF
    INC    A
    INC    HL
    DEC    B
    JP     NZ,PROCESAR_CANAL_PSG
; --- APLICAR_ENVOLVENTE_RUIDO: cae aqui tras terminar el bucle de 3
; canales -- una TERCERA envolvente, esta vez COMPARTIDA (no por
; canal) sobre la tabla fija $CA53, con la misma estructura exacta
; que las envolventes de volumen/tono (cuenta atras/pasos/incremento/
; periodo). Combina ($CA5E)+($CA5F) y lo escribe en $C9C4 -- la
; sombra del registro 6 del PSG (periodo de RUIDO). Tiene sentido que
; sea compartida: el AY-3-8910 solo tiene un generador de ruido para
; los 3 canales. Termina en VOLCAR_REGISTROS_PSG (vuelca toda la
; sombra a hardware) y cae en el POP AF/RET final de
; TICK_REPRODUCTOR_PSG. ---
APLICAR_ENVOLVENTE_RUIDO:
    LD     IY,TABLA_ENVOLVENTE_RUIDO_PSG
    LD     D,2                    ; 2 campos de la envolvente compartida (mismo patron que la envolvente de volumen)
    LD     C,$00
.BUCLE_ENVOLVENTE_RUIDO:
    LD     A,(IY+$00)
    OR     A
    JR     Z,.RECARGAR_PASO_ENVOLVENTE_RUIDO
    DEC    A
    LD     (IY+$00),A
    INC    C
    JR     .FIN_ENVOLVENTE_RUIDO
.RECARGAR_PASO_ENVOLVENTE_RUIDO:
    LD     A,(IY+$02)
    OR     A
    JR     Z,.CONTINUAR_ENVOLVENTE_RUIDO
    DEC    A
    LD     (IY+$02),A
    LD     A,($CA5F)
    ADD    A,(IY+$06)
    LD     ($CA5F),A
    LD     A,(IY+$08)
    LD     (IY+$00),A
    INC    C
    JR     .FIN_ENVOLVENTE_RUIDO
.CONTINUAR_ENVOLVENTE_RUIDO:
    INC    IY
    DEC    D
    JR     NZ,.BUCLE_ENVOLVENTE_RUIDO
.FIN_ENVOLVENTE_RUIDO:
    LD     A,C
    OR     A
    JR     NZ,.ESCRIBIR_RUIDO_PSG
    LD     A,(FLAGS_ENVOLVENTE_COMPARTIDA_PSG)
    BIT    2,A
    CALL   NZ,REINICIAR_ENVOLVENTE_RUIDO
.ESCRIBIR_RUIDO_PSG:
    LD     A,($CA5E)
    LD     E,A
    LD     A,($CA5F)
    ADD    A,E
    LD     ($C9C4),A
    CALL   VOLCAR_REGISTROS_PSG
    POP    AF
    RET
; --- REINICIAR_ENVOLVENTE_VOLUMEN/REINICIAR_ENVOLVENTE_TONO: relatchean parametros de la ranura de canal
; actual (IX): copian el valor "objetivo" de 2 campos a su campo
; "actual" (REINICIAR_ENVOLVENTE_VOLUMEN: +$20->+$0C y +$16->+$0E, para las 2 entradas de
; alcanzabilidad de IY vistas en .BUCLE_ENVOLVENTE_VOLUMEN mas arriba; REINICIAR_ENVOLVENTE_TONO: mismo
; patron con +$22->+$10 y +$18->+$13, 3 entradas). Llamadas al
; empezar una nota nueva (ARMAR_NOTA) y al reiniciar el "companero" de
; una nota (.FIN_ENVOLVENTE_VOLUMEN). No decodificado que representa cada campo en
; concreto (fuera de alcance -- driver de sonido no descompuesto
; nota a nota, ver header de mas arriba). ---
REINICIAR_ENVOLVENTE_VOLUMEN:
    PUSH   IX
    LD     D,2                    ; 2 fases de volumen (mismo criterio que APLICAR_ENVOLVENTES_CANAL)
.BUCLE_REINICIO_VOLUMEN:
    LD     A,(IX+$20)
    LD     (IX+$0C),A
    LD     A,(IX+$16)
    LD     (IX+$0E),A
    INC    IX
    DEC    D
    JR     NZ,.BUCLE_REINICIO_VOLUMEN
    POP    IX
    RET
REINICIAR_ENVOLVENTE_TONO:
    LD     D,3                    ; 3 fases de tono (mismo criterio que APLICAR_ENVOLVENTES_CANAL)
    PUSH   IX
.BUCLE_REINICIO_TONO:
    LD     A,(IX+$22)
    LD     (IX+$10),A
    LD     A,(IX+$18)
    LD     (IX+$13),A
    INC    IX
    DEC    D
    JR     NZ,.BUCLE_REINICIO_TONO
    POP    IX
    RET
; --- REINICIAR_ENVOLVENTE_RUIDO: mismo patron de relatch pero sobre la tabla FIJA (no
; por-canal) en $CA53 (compartida entre canales, ver .BUCLE_COPIAR_FORMA_ENVOLVENTE/ACTUALIZAR_MEZCLADOR_CANAL
; mas abajo -- candidata a tabla de envolvente/percusion comun).
; Copia (+$08->+$00) y (+$04->+$02) en sus 2 primeras entradas. ---
REINICIAR_ENVOLVENTE_RUIDO:
    LD     D,2                    ; 2 campos de la envolvente compartida
    PUSH   IY
    LD     IY,TABLA_ENVOLVENTE_RUIDO_PSG
.BUCLE_REINICIO_RUIDO:
    LD     A,(IY+$08)
    LD     (IY+$00),A
    LD     A,(IY+$04)
    LD     (IY+$02),A
    INC    IY
    DEC    D
    JR     NZ,.BUCLE_REINICIO_RUIDO
    POP    IY
    RET
; --- A partir de aqui: cuerpos de los 15 manejadores de comando del
; bytecode PSG. No llevan etiqueta propia en el original -- el "JP (HL)"
; de DESPACHAR_COMANDO_PSG aterriza directo en cada direccion via
; TABLA_COMANDOS_PSG (ver la tabla, mas abajo, para el nombre/numero de
; comando de cada uno; identificados aqui por los campos que tocan). ---
    INC    BC                     ; SET_VOLUME (comando 0): guarda el parametro tal cual en (IX+$09)
    LD     A,(BC)
    LD     (IX+$09),A
    INC    BC
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_DURATION (comando 3): parametro * ($C9BD) -> (IX+$06/$07)
    LD     A,(BC)
    LD     DE,($C9BD)
    LD     D,$00
    CALL   MULTIPLICAR_8X16
    LD     (IX+$06),L
    LD     (IX+$07),H
    INC    BC
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_MIXER (comando 1): AND $09 (bits tono+ruido) -> (IX+$08)
    LD     A,(BC)
    AND    $09
    LD     (IX+$08),A
    INC    BC
    JP     DESPACHAR_COMANDO_PSG
    PUSH   IX                     ; RESET_SHARED_ENVELOPE (comando 11): silencia toda la ranura de canal...
    POP    HL
    XOR    A
    LD     B,46                   ; 46 bytes = ranura de canal completa
.BUCLE_LIMPIAR_RANURA_COMPLETA:
    LD     (HL),A
    INC    HL
    DJNZ   .BUCLE_LIMPIAR_RANURA_COMPLETA
    LD     A,(AREA_TRABAJO_PSG)
    LD     HL,FLAGS_ENVOLVENTE_COMPARTIDA_PSG+3    ; ($CA60) = canal "dueno" de la envolvente compartida
    XOR    (HL)
    JP     NZ,COMBINAR_Y_ESCRIBIR_CANAL            ; ...y si eres el dueno, ademas borra TABLA_ENVOLVENTE_RUIDO_PSG
    LD     HL,TABLA_ENVOLVENTE_RUIDO_PSG
    LD     DE,TABLA_ENVOLVENTE_RUIDO_PSG+1
    LD     BC,10                  ; 10 bytes de TABLA_ENVOLVENTE_RUIDO_PSG
    LD     (HL),A
    LDIR
    INC    DE
    LD     (DE),A
    JP     COMBINAR_Y_ESCRIBIR_CANAL
    INC    BC                     ; SET_TEMPO (comando 5): recalcula el multiplicador ($C9BD) que usa SET_DURATION
    LD     A,(BC)
    PUSH   BC
    LD     DE,16
    CALL   MULTIPLICAR_8X16
    LD     BC,3000
    PUSH   HL
    POP    DE
    CALL   DIVIDIR_16X16
    LD     A,C
    LD     ($C9BD),A
    POP    BC
    INC    BC
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_ENVELOPE (comando 8): AND $1F (indice 0-31) -> ($CA5E), relatch de la envolvente
    LD     A,(BC)
    PUSH   AF
    AND    $1F
    LD     (FLAGS_ENVOLVENTE_COMPARTIDA_PSG+1),A
    CALL   REINICIAR_ENVOLVENTE_RUIDO
    POP    AF
    INC    BC                     ; bit7 del parametro original: si esta a 1, sigue despachando mas comandos;
    OR     A                      ; si esta a 0, cae directo en ARMAR_NOTA (dispara la nota con esta envolvente)
    JP     M,DESPACHAR_COMANDO_PSG
    JP     ARMAR_NOTA
    INC    BC                     ; HOLD (comando 4): sin parametro, salta directo al cierre de nota
    JP     CERRAR_NOTA
    LD     C,(IX+$00)             ; LOOP (comando 2): recarga BC/(IX+$02-03) desde (IX+$00-01) (vuelve al principio del guion)
    LD     B,(IX+$01)
    LD     (IX+$02),C
    LD     (IX+$03),B
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_DURATION_MULTI (comando 6): variante acumulativa de SET_DURATION, N bytes (cuenta en A)
    LD     A,(BC)
    INC    BC
    LD     DE,$0000
.BUCLE_ACUMULAR_DURACION:
    PUSH   AF
    LD     A,(BC)
    PUSH   DE
    LD     DE,($C9BD)
    LD     D,$00
    CALL   MULTIPLICAR_8X16
    POP    DE
    ADD    HL,DE
    EX     DE,HL
    INC    BC
    POP    AF
    DEC    A
    JR     NZ,.BUCLE_ACUMULAR_DURACION
    LD     (IX+$06),L
    LD     (IX+$07),H
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_FLAGS (comando 10): OR con (IX+$2D) (flags del canal) y con ($CA5D) (flags globales)
    LD     A,(BC)
    LD     E,A
    OR     (IX+$2D)
    LD     (IX+$2D),A
    LD     A,(FLAGS_ENVOLVENTE_COMPARTIDA_PSG)
    OR     E
    LD     (FLAGS_ENVOLVENTE_COMPARTIDA_PSG),A
    INC    BC
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_INSTRUMENT (comando 7): copia 15 bytes de TABLA_INSTRUMENTOS_PSG+indice a (IX+$16..)
    RES    0,(IX+$2D)
    RES    1,(IX+$2D)
    LD     A,(BC)
    LD     DE,15                  ; 15 = tamano de cada instrumento (bytes)
    CALL   MULTIPLICAR_8X16
    LD     DE,TABLA_INSTRUMENTOS_PSG
    ADD    HL,DE
    PUSH   IX
    LD     D,15                   ; copia los 15 bytes del instrumento
.BUCLE_COPIAR_INSTRUMENTO:
    LD     A,(HL)
    LD     (IX+$16),A
    INC    HL
    INC    IX
    DEC    D
    JP     NZ,.BUCLE_COPIAR_INSTRUMENTO
    POP    IX
    INC    BC
    LD     (IX+$0C),$00           ; limpia los acumuladores de envolvente del canal (relatch limpio para la nota siguiente)
    LD     (IX+$0D),$00
    LD     (IX+$10),$00
    LD     (IX+$11),$00
    LD     (IX+$12),$00
    LD     (IX+$2A),$00
    LD     (IX+$2B),$00
    LD     (IX+$2C),$00
    JP     DESPACHAR_COMANDO_PSG
    INC    BC                     ; SET_ENVELOPE_SHAPE (comando 9): copia 6 bytes de TABLA_ENVOLVENTES_PSG+indice a TABLA_ENVOLVENTE_RUIDO_PSG+4
    LD     A,(FLAGS_ENVOLVENTE_COMPARTIDA_PSG)
    RES    2,A
    LD     (FLAGS_ENVOLVENTE_COMPARTIDA_PSG),A
    LD     A,(BC)
    LD     DE,6                   ; 6 = tamano de una forma de envolvente (bytes)
    CALL   MULTIPLICAR_8X16
    LD     DE,TABLA_ENVOLVENTES_PSG
    ADD    HL,DE
    LD     IY,TABLA_ENVOLVENTE_RUIDO_PSG
    LD     (IY+$00),$00
    LD     (IY+$01),$00
    LD     D,6                    ; copia los 6 bytes de la forma de envolvente
.BUCLE_COPIAR_FORMA_ENVOLVENTE:
    LD     A,(HL)
    LD     (IY+$04),A
    INC    HL
    INC    IY
    DEC    D
    JR     NZ,.BUCLE_COPIAR_FORMA_ENVOLVENTE
    XOR    A
    LD     (FLAGS_ENVOLVENTE_COMPARTIDA_PSG+2),A    ; ($CA5F) = flag de reset de la envolvente compartida
    INC    BC
    LD     A,(AREA_TRABAJO_PSG)
    LD     (FLAGS_ENVOLVENTE_COMPARTIDA_PSG+3),A    ; ($CA60) = este canal pasa a ser el "dueno" de la envolvente
    JP     DESPACHAR_COMANDO_PSG
; --- ACTUALIZAR_MEZCLADOR_CANAL: activa/desactiva tono/ruido del canal actual ((AREA_TRABAJO_PSG),
; 0-2) en $C9C5. CORREGIDO (rastreo bit a bit completo, ver
; FINDINGS.md "renderizador de audio" -- la nota anterior tenia la
; polaridad AL REVES): A es una mascara de 2 bits (bit0=tono,
; bit3=ruido, ya reubicados a la posicion del canal actual dentro de
; $C9C5 por el bucle de desplazamiento) -- bit a 1 en A ACTIVA
; (audible) ese generador para este canal, bit a 0 lo deja
; silenciado. Por eso "XOR A" (A=0, todo a 0) al principio de cada
; nota en PROCESAR_CANAL_PSG SILENCIA el canal brevemente (evita clicks al
; re-disparar), y luego ARMAR_NOTA vuelve a llamar con (IX+$08) (el
; valor real fijado por SET_MIXER) para dejar el estado audible
; definitivo. $C9C5 esta a offset +7 respecto a $C9BE (base que
; VOLCAR_REGISTROS_PSG vuelca a los puertos del PSG), es decir, $C9C5 es la SOMBRA
; del registro 7 del PSG (mezclador: 0=audible, 1=silenciado en el
; propio chip -- por eso esta rutina invierte la mascara con CPL
; antes de aplicarla). ---
ACTUALIZAR_MEZCLADOR_CANAL:
    PUSH   DE
    CPL
    LD     E,A
    LD     D,$09                  ; $09 = mascara base bit0(tono)+bit3(ruido) del canal 0 (no es un contador: se desplaza con SLA)
    LD     A,(AREA_TRABAJO_PSG)
.BUCLE_DESPLAZAR_MASCARA:
    DEC    A
    JP     M,.APLICAR_MASCARA_MEZCLADOR
    SCF
    RL     E                      ; desplaza la mascara (E) y el patron base (D) tantas posiciones como indique el canal actual
    SLA    D
    JR     .BUCLE_DESPLAZAR_MASCARA
.APLICAR_MASCARA_MEZCLADOR:
    LD     A,($C9C5)
    OR     D
    AND    E
    LD     ($C9C5),A
    POP    DE
    RET
; CALL_SUBPATTERN (comando 12): guarda BC (direccion de retorno) en TABLA_RETORNO_SUBPATRONES_PSG+canal y salta via TABLA_SUBPATRONES_PSG
    LD     A,(AREA_TRABAJO_PSG)
    INC    BC
    ADD    A,A
    LD     L,A
    LD     H,$00
    LD     A,(BC)
    INC    BC
    LD     DE,TABLA_RETORNO_SUBPATRONES_PSG
    ADD    HL,DE
    LD     (HL),C
    INC    HL
    LD     (HL),B
    LD     HL,TABLA_SUBPATRONES_PSG
    CALL   LEER_PALABRA_INDEXADA
    LD     B,H
    LD     C,L
    JP     DESPACHAR_COMANDO_PSG
; RETURN_SUBPATTERN (comando 13): recupera BC desde TABLA_RETORNO_SUBPATRONES_PSG+canal
    LD     A,(AREA_TRABAJO_PSG)
    ADD    A,A
    LD     L,A
    LD     H,$00
    LD     DE,TABLA_RETORNO_SUBPATRONES_PSG
    ADD    HL,DE
    LD     C,(HL)
    INC    HL
    LD     B,(HL)
    JP     DESPACHAR_COMANDO_PSG
; SET_CHANNEL_STATE (comando 14): escribe el parametro tal cual en TABLA_TRANSPOSICION_PSG+canal
    INC    BC
    CALL   OBTENER_PUNTERO_TRANSPOSICION
    LD     A,(BC)
    INC    BC
    LD     (HL),A
    JP     DESPACHAR_COMANDO_PSG
; --- OBTENER_PUNTERO_TRANSPOSICION: HL = TABLA_TRANSPOSICION_PSG + canal
; actual ((AREA_TRABAJO_PSG)) -- puntero a la entrada de transposicion de ese
; canal (1 byte por canal). Usada en DESPACHAR_COMANDO_PSG.RESOLVER_NOTA
; para sumar la transposicion a la nota antes de buscar el periodo de
; tono; el segundo uso (comando 14, SET_CHANNEL_STATE, ver
; FINDINGS.md) es el que la FIJA, escribiendo el byte tal cual. ---
OBTENER_PUNTERO_TRANSPOSICION:
    LD     A,(AREA_TRABAJO_PSG)
    LD     L,A
    LD     H,$00
    LD     DE,TABLA_TRANSPOSICION_PSG
    ADD    HL,DE
    RET
; --- MULTIPLICAR_8X16: multiplicacion 8x16 bits sin signo, HL = A*DE (shift
; and add clasico: por cada uno de los 8 bits de A, si el bit es 1
; suma DE a HL, luego DE se duplica). Uso general: calcular
; desplazamientos (ranura*tamano, etc.) -- p.ej. INSTALAR_RECURSO_SONIDO
; la usa con DE=46 (tamano de ranura). ---
MULTIPLICAR_8X16:
    LD     HL,$0000
    AND    A
    RET    Z
    PUSH   BC
    LD     B,8                    ; 8 bits del multiplicador (A)
.BUCLE_MULTIPLICAR:
    SRL    A
    JR     NC,.CONTINUAR_MULTIPLICAR
    ADD    HL,DE
.CONTINUAR_MULTIPLICAR:
    SLA    E
    RL     D
    DJNZ   .BUCLE_MULTIPLICAR
    POP    BC
    RET
; --- DIVIDIR_16X16: division 16/16 bits sin signo (algoritmo clasico de
; desplazar-y-restar, 16 iteraciones): BC entre DE, cociente final en
; BC, resto en HL. ---
DIVIDIR_16X16:
    PUSH   AF
    LD     HL,$0000
    LD     A,B
    LD     B,16                   ; 16 bits (division de 16/16)
.BUCLE_DIVIDIR:
    RL     C
    RLA
    ADC    HL,HL
    SBC    HL,DE
    JR     NC,.CONTINUAR_DIVIDIR
    ADD    HL,DE
.CONTINUAR_DIVIDIR:
    CCF
    DJNZ   .BUCLE_DIVIDIR
    RL     C
    RLA
    LD     B,A
    POP    AF
    RET
; --- LEER_PALABRA_INDEXADA: consulta de tabla de palabras de 16 bits -- HL = valor
; de 16 bits leido en (HL + A*2). La usan tanto la duracion de nota
; (tabla TABLA_NOTAS_PSG, 96 palabras) como el despacho de comandos
; (tabla TABLA_COMANDOS_PSG, 15 saltos): "HL=tabla; CALL LEER_PALABRA_INDEXADA; JP (HL)"
; es literalmente un salto indexado (jump table). ---
LEER_PALABRA_INDEXADA:
    PUSH   AF
    ADD    A,A
    ADD    A,L
    LD     L,A
    JR     NC,.SIN_ACARREO
    INC    H
.SIN_ACARREO:
    LD     A,(HL)
    INC    HL
    LD     H,(HL)
    LD     L,A
    POP    AF
    RET
; --- VOLCAR_REGISTROS_PSG: vuelca a hardware -- copia los 11 bytes de sombra de
; registro ($C9BE-$C9C8, incluyendo el mezclador $C9C5 que toca
; ACTUALIZAR_MEZCLADOR_CANAL) a los 11 registros reales del PSG AY-3-8910 (puerto
; $A0=numero de registro, $A1=valor). Es el paso final de cada tic
; del reproductor (PROCESAR_CANAL_PSG). ---
VOLCAR_REGISTROS_PSG:
    LD     HL,$C9BE
    LD     A,$00
    LD     D,11                   ; 11 registros del PSG AY-3-8910
.BUCLE_VOLCAR_REGISTROS:
    PUSH   AF
    LD     C,(HL)
    OUT    ($A0),A
    LD     A,C
    OUT    ($A1),A
    POP    AF
    INC    A
    INC    HL
    DEC    D
    JR     NZ,.BUCLE_VOLCAR_REGISTROS
    RET


; --- Datos del driver de sonido (0xC8DE-0xCDCB): son TODO datos,
; ninguna instruccion Z80 (el codigo del driver esta arriba, ya
; desensamblado). Se desglosa en las siguientes tablas etiquetadas
; a continuacion (ver FINDINGS.md, "Los 15 comandos" y "el
; renderizador de audio" para el detalle de cada una):
;   TABLA_NOTAS_PSG                (0xC8DE, 96 palabras) -- nota+transposicion -> periodo de tono
;   TABLA_COMANDOS_PSG          (0xC99E, 15 palabras) -- salto de los 15 comandos del bytecode
;   AREA_TRABAJO_PSG      (0xC9BC, 151 bytes)   -- estado de canal en reposo (ver nota nivel 13 abajo)
;   TABLA_ENVOLVENTE_RUIDO_PSG   (0xCA53, 10 bytes)    -- envolvente compartida (SET_ENVELOPE y cia.)
;   FLAGS_ENVOLVENTE_COMPARTIDA_PSG              (0xCA5D, 4 bytes)     -- flags asociados a la envolvente compartida
;   TABLA_RETORNO_SUBPATRONES_PSG (0xCA61, 6 bytes)     -- retorno de CALL_SUBPATTERN por canal
;   TABLA_TRANSPOSICION_PSG         (0xCA67, 3 bytes)     -- transposicion en vivo por canal
;   TABLA_INSTRUMENTOS_PSG        (0xCA6A, 240 bytes)   -- 16 instrumentos x 15 bytes
;   TABLA_ENVOLVENTES_PSG         (0xCB5A, 24 bytes)    -- 4 formas de envolvente x 6 bytes
;   TABLA_SUBPATRONES_PSG        (0xCB72, 42 bytes)    -- 21 punteros a los 13 subpatrones
;   SUBPATRON_00_CB9C     (0xCB9C-0xCDCB)       -- bytecode de los 13 subpatrones compartidos
; Todo verificado byte a byte contra el .BIN original.
;
; NOTA sobre el bug conocido del nivel 13 (ver FINDINGS.md, seccion
; "LOCALIZADO... el fix real del bug nivel 13"): comparando esta
; v1.0 contra la v2.0 (CAS/ROM, bug ya corregido), el tramo
; 0xC9BC-0xCA73 (181 de 183 bytes a $00, con solo dos bytes sueltos
; $07 en 0xCA6A y $FE en 0xCA6F -- confirmado leyendo el .BIN
; original byte a byte) es precisamente donde la v2.0 inserta ~180
; bytes de codigo nuevo para el fix. En ESTA version (v1.0, la que
; reconstruye este fichero), AREA_TRABAJO_PSG/
; TABLA_ENVOLVENTE_RUIDO_PSG/FLAGS_ENVOLVENTE_COMPARTIDA_PSG/TABLA_RETORNO_SUBPATRONES_PSG/
; TABLA_TRANSPOSICION_PSG son solo estado en reposo (todo a cero salvo los
; dos bytes sueltos ya mencionados), sin usar todavia -- las labels de
; abajo son la misma zona de memoria, solo con nombre puesto a cada
; campo segun lo que el driver leeria/escribiria ahi en tiempo de
; ejecucion. ---
; --- TABLA_NOTAS_PSG (0xC8DE, 192 bytes = 96 palabras): tabla de
; nota+transposicion -> periodo de tono del PSG (DESPACHAR_COMANDO_PSG.RESOLVER_NOTA suma la nota
; del bytecode a la transposicion del canal, TABLA_TRANSPOSICION_PSG, y
; usa el resultado como indice aqui, x2 -- ver FINDINGS.md, 'CORRECCION
; IMPORTANTE... el byte <0x80 NO es una duracion, es la NOTA'). Monotona
; decreciente (periodo baja segun sube el indice de nota, el patron
; esperado de una escala cromatica ascendente) -- verificado en los
; 96 valores. Reformateada a una fila por nota (antes volcado hexadecimal
; en filas de 16 bytes sin relacion con las 96 entradas). ---
TABLA_NOTAS_PSG:
    DW $0D5D    ; nota  0 -> periodo $0D5D (3421)
    DW $0C9D    ; nota  1 -> periodo $0C9D (3229)
    DW $0BE7    ; nota  2 -> periodo $0BE7 (3047)
    DW $0B3C    ; nota  3 -> periodo $0B3C (2876)
    DW $0A9B    ; nota  4 -> periodo $0A9B (2715)
    DW $0A03    ; nota  5 -> periodo $0A03 (2563)
    DW $0973    ; nota  6 -> periodo $0973 (2419)
    DW $08EB    ; nota  7 -> periodo $08EB (2283)
    DW $086B    ; nota  8 -> periodo $086B (2155)
    DW $07F2    ; nota  9 -> periodo $07F2 (2034)
    DW $0780    ; nota 10 -> periodo $0780 (1920)
    DW $0714    ; nota 11 -> periodo $0714 (1812)
    DW $06AE    ; nota 12 -> periodo $06AE (1710)
    DW $064E    ; nota 13 -> periodo $064E (1614)
    DW $05F4    ; nota 14 -> periodo $05F4 (1524)
    DW $059E    ; nota 15 -> periodo $059E (1438)
    DW $054D    ; nota 16 -> periodo $054D (1357)
    DW $0501    ; nota 17 -> periodo $0501 (1281)
    DW $04B9    ; nota 18 -> periodo $04B9 (1209)
    DW $0475    ; nota 19 -> periodo $0475 (1141)
    DW $0435    ; nota 20 -> periodo $0435 (1077)
    DW $03F9    ; nota 21 -> periodo $03F9 (1017)
    DW $03C0    ; nota 22 -> periodo $03C0 (960)
    DW $038A    ; nota 23 -> periodo $038A (906)
    DW $0357    ; nota 24 -> periodo $0357 (855)
    DW $0327    ; nota 25 -> periodo $0327 (807)
    DW $02FA    ; nota 26 -> periodo $02FA (762)
    DW $02CF    ; nota 27 -> periodo $02CF (719)
    DW $02A7    ; nota 28 -> periodo $02A7 (679)
    DW $0281    ; nota 29 -> periodo $0281 (641)
    DW $025D    ; nota 30 -> periodo $025D (605)
    DW $023B    ; nota 31 -> periodo $023B (571)
    DW $021B    ; nota 32 -> periodo $021B (539)
    DW $01FC    ; nota 33 -> periodo $01FC (508)
    DW $01E0    ; nota 34 -> periodo $01E0 (480)
    DW $01C5    ; nota 35 -> periodo $01C5 (453)
    DW $01AC    ; nota 36 -> periodo $01AC (428)
    DW $0194    ; nota 37 -> periodo $0194 (404)
    DW $017D    ; nota 38 -> periodo $017D (381)
    DW $0168    ; nota 39 -> periodo $0168 (360)
    DW $0153    ; nota 40 -> periodo $0153 (339)
    DW $0140    ; nota 41 -> periodo $0140 (320)
    DW $012E    ; nota 42 -> periodo $012E (302)
    DW $011D    ; nota 43 -> periodo $011D (285)
    DW $010D    ; nota 44 -> periodo $010D (269)
    DW $00FE    ; nota 45 -> periodo $00FE (254)
    DW $00F0    ; nota 46 -> periodo $00F0 (240)
    DW $00E2    ; nota 47 -> periodo $00E2 (226)
    DW $00D6    ; nota 48 -> periodo $00D6 (214)
    DW $00CA    ; nota 49 -> periodo $00CA (202)
    DW $00BE    ; nota 50 -> periodo $00BE (190)
    DW $00B4    ; nota 51 -> periodo $00B4 (180)
    DW $00AA    ; nota 52 -> periodo $00AA (170)
    DW $00A0    ; nota 53 -> periodo $00A0 (160)
    DW $0097    ; nota 54 -> periodo $0097 (151)
    DW $008F    ; nota 55 -> periodo $008F (143)
    DW $0087    ; nota 56 -> periodo $0087 (135)
    DW $007F    ; nota 57 -> periodo $007F (127)
    DW $0078    ; nota 58 -> periodo $0078 (120)
    DW $0071    ; nota 59 -> periodo $0071 (113)
    DW $006B    ; nota 60 -> periodo $006B (107)
    DW $0065    ; nota 61 -> periodo $0065 (101)
    DW $005F    ; nota 62 -> periodo $005F (95)
    DW $005A    ; nota 63 -> periodo $005A (90)
    DW $0055    ; nota 64 -> periodo $0055 (85)
    DW $0050    ; nota 65 -> periodo $0050 (80)
    DW $004C    ; nota 66 -> periodo $004C (76)
    DW $0047    ; nota 67 -> periodo $0047 (71)
    DW $0043    ; nota 68 -> periodo $0043 (67)
    DW $0040    ; nota 69 -> periodo $0040 (64)
    DW $003C    ; nota 70 -> periodo $003C (60)
    DW $0039    ; nota 71 -> periodo $0039 (57)
    DW $0035    ; nota 72 -> periodo $0035 (53)
    DW $0032    ; nota 73 -> periodo $0032 (50)
    DW $0030    ; nota 74 -> periodo $0030 (48)
    DW $002D    ; nota 75 -> periodo $002D (45)
    DW $002A    ; nota 76 -> periodo $002A (42)
    DW $0028    ; nota 77 -> periodo $0028 (40)
    DW $0026    ; nota 78 -> periodo $0026 (38)
    DW $0024    ; nota 79 -> periodo $0024 (36)
    DW $0022    ; nota 80 -> periodo $0022 (34)
    DW $0020    ; nota 81 -> periodo $0020 (32)
    DW $001E    ; nota 82 -> periodo $001E (30)
    DW $001C    ; nota 83 -> periodo $001C (28)
    DW $001B    ; nota 84 -> periodo $001B (27)
    DW $0019    ; nota 85 -> periodo $0019 (25)
    DW $0018    ; nota 86 -> periodo $0018 (24)
    DW $0016    ; nota 87 -> periodo $0016 (22)
    DW $0015    ; nota 88 -> periodo $0015 (21)
    DW $0014    ; nota 89 -> periodo $0014 (20)
    DW $0013    ; nota 90 -> periodo $0013 (19)
    DW $0012    ; nota 91 -> periodo $0012 (18)
    DW $0011    ; nota 92 -> periodo $0011 (17)
    DW $0010    ; nota 93 -> periodo $0010 (16)
    DW $000F    ; nota 94 -> periodo $000F (15)
    DW $000E    ; nota 95 -> periodo $000E (14)
TABLA_COMANDOS_PSG:                 ; $C99E (30 bytes, 15 palabras) -- tabla de salto de los 15 comandos
; del bytecode de sonido (byte de comando = $80 + numero). Mecanica de cada uno verificada
; leyendo el codigo real (ver FINDINGS.md, "Los 15 comandos"); los nombres son interpretacion
; razonada, no verificacion en vivo. Mismo lenguaje que usan .snd/.spt (ver OPS en mmsnd_tool.py). ---
    DW $C6E5    ; comando 0  ($80) SET_VOLUME -- guarda el byte tal cual en (IX+$09), volumen base
    DW $C703    ; comando 1  ($81) SET_MIXER -- AND $09, guarda en (IX+$08), mascara de mezclador
    DW $C765    ; comando 2  ($82) LOOP -- recarga BC/(IX+$02-03) desde (IX+$00-01), vuelve al principio del script
    DW $C6EE    ; comando 3  ($83) SET_DURATION -- multiplica el parametro por ($C9BD), guarda en (IX+$06-07)
    DW $C761    ; comando 4  ($84) HOLD -- salta directo al cierre de nota sin pasar por duracion nueva
    DW $C733    ; comando 5  ($85) SET_TEMPO -- recalcula ($C9BD), el multiplicador que usa SET_DURATION
    DW $C774    ; comando 6  ($86) SET_DURATION_MULTI -- variante acumulativa de SET_DURATION (N bytes, cuenta en A)
    DW $C7AB    ; comando 7  ($87) SET_INSTRUMENT -- copia 15 bytes de TABLA_INSTRUMENTOS_PSG+indice a (IX+$16..)
    DW $C74D    ; comando 8  ($88) SET_ENVELOPE -- AND $1F, guarda en ($CA5E), relatch de TABLA_ENVOLVENTE_RUIDO_PSG
    DW $C7F4    ; comando 9  ($89) SET_ENVELOPE_SHAPE -- copia 6 bytes de TABLA_ENVOLVENTES_PSG+indice a TABLA_ENVOLVENTE_RUIDO_PSG+4
    DW $C797    ; comando 10 ($8A) SET_FLAGS -- OR con (IX+$2D) y con ($CA5D), flags globales
    DW $C70E    ; comando 11 ($8B) RESET_SHARED_ENVELOPE -- borra TABLA_ENVOLVENTE_RUIDO_PSG si eres el canal "dueno"
    DW $C84B    ; comando 12 ($8C) CALL_SUBPATTERN -- guarda BC en TABLA_RETORNO_SUBPATRONES_PSG+canal, salta via TABLA_SUBPATRONES_PSG
    DW $C867    ; comando 13 ($8D) RETURN_SUBPATTERN -- recupera BC desde TABLA_RETORNO_SUBPATRONES_PSG+canal
    DW $C878    ; comando 14 ($8E) SET_CHANNEL_STATE -- escribe el byte tal cual en TABLA_TRANSPOSICION_PSG+canal
AREA_TRABAJO_PSG:             ; $C9BC (151 bytes) -- estado de canal en reposo en esta v1.0; en la v2.0 (CAS/ROM) aqui se inserta el parche del bug del nivel 13 (ver FINDINGS.md)
    DB $00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    DB $00,$00,$00,$00,$00
TABLA_ENVOLVENTE_RUIDO_PSG:          ; $CA53 (10 bytes) -- tabla de envolvente compartida entre canales (SET_ENVELOPE/SET_ENVELOPE_SHAPE/RESET_SHARED_ENVELOPE la leen/escriben; REINICIAR_ENVOLVENTE_RUIDO la recorre) -- ver FINDINGS.md, mecanismo sin trazar del todo
    DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
FLAGS_ENVOLVENTE_COMPARTIDA_PSG:                     ; $CA5D (4 bytes) -- flags/estado misceláneo asociado a la envolvente compartida (($CA5E)=parametro de SET_ENVELOPE, ($CA5F)=flag de reset, ($CA60)=canal "dueño"); no desglosado byte a byte
    DB $00
    DB $00,$00,$00
TABLA_RETORNO_SUBPATRONES_PSG:        ; $CA61 (6 bytes, 2 por canal) -- direccion de retorno de CALL_SUBPATTERN/RETURN_SUBPATTERN por canal
    DB $00,$00,$00,$00,$00,$00
TABLA_TRANSPOSICION_PSG:                ; $CA67 (3 bytes, 1 por canal) -- transposicion de nota (SET_CHANNEL_STATE escribe aqui en tiempo de ejecucion); verificado 00 00 00 en este .BIN
    DB $00,$00,$00
; --- TABLA_INSTRUMENTOS_PSG (0xCA6A, 240 bytes): tabla de registros de
; tamano fijo confirmada por codigo, no solo por aritmetica (240/16=15).
; SET_INSTRUMENT (.BUCLE_COPIAR_INSTRUMENTO mas abajo en este fichero) calcula el indice
; con MULTIPLICAR_8X16 (multiplicacion 8x16, HL=A*DE) usando DE=$000F (15), y
; copia exactamente D=$0F=15 bytes desde $CA6A+indice*15 al estado del
; canal -- 16 instrumentos reales de 15 bytes cada uno. Mapeo de los 15
; bytes de cada fila (retrazado contra REINICIAR_ENVOLVENTE_VOLUMEN/REINICIAR_ENVOLVENTE_TONO, confirmado
; escuchando el renderizador contra la descripcion del usuario, ver
; FINDINGS.md "error real en el mapeo de campos del instrumento"):
;   b[0]/b[1]   = repeticiones fase1/fase2 de volumen
;   b[2..4]     = repeticiones fase1/2/3 de tono
;   b[5]/b[6]   = delta fase1/fase2 de volumen
;   b[7..9]     = delta (CON SIGNO) fase1/2/3 de tono
;   b[10]/b[11] = retardo entre pasos, fase1/fase2 de volumen
;   b[12..14]   = retardo entre pasos, fase1/2/3 de tono
; Reformateada a una fila por instrumento (antes volcado hexadecimal
; en bloques de 16 bytes sin relacion con los limites reales de cada
; registro) para que la estructura sea visible en el propio fuente. ---
TABLA_INSTRUMENTOS_PSG:
    DB $07,$00,$00,$00,$00,$FE,$00,$00,$00,$00,$01,$00,$00,$00,$00    ; instrumento 0 ($00)
    DB $0A,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$02,$00,$00,$00,$00    ; instrumento 1 ($01)
    DB $06,$00,$1E,$00,$00,$FE,$00,$E2,$00,$00,$01,$00,$01,$00,$00    ; instrumento 2 ($02)
    DB $01,$01,$00,$00,$00,$04,$FC,$00,$00,$00,$01,$01,$00,$00,$00    ; instrumento 3 ($03)
    DB $01,$01,$01,$01,$00,$04,$FC,$03,$FD,$00,$01,$01,$01,$01,$00    ; instrumento 4 ($04)
    DB $01,$01,$14,$01,$00,$00,$F1,$00,$00,$00,$03,$01,$00,$00,$00    ; instrumento 5 ($05)
    DB $0F,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$01,$00,$00,$00,$00    ; instrumento 6 ($06)
    DB $0A,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$03,$00,$00,$00,$00    ; instrumento 7 ($07)
    DB $01,$0B,$32,$00,$00,$04,$FF,$08,$00,$00,$00,$03,$00,$00,$00    ; instrumento 8 ($08)
    DB $01,$0E,$32,$00,$00,$07,$FF,$09,$00,$00,$00,$02,$01,$00,$00    ; instrumento 9 ($09)
    DB $01,$0A,$00,$00,$00,$03,$FF,$00,$00,$00,$00,$02,$00,$00,$00    ; instrumento 10 ($0A)
    DB $00,$03,$00,$00,$00,$00,$FC,$00,$00,$00,$00,$01,$00,$00,$00    ; instrumento 11 ($0B)
    DB $01,$0E,$00,$00,$00,$07,$FF,$00,$00,$00,$00,$01,$00,$00,$00    ; instrumento 12 ($0C) -- usado por la mariquita (ver FINDINGS.md)
    DB $0A,$00,$01,$06,$00,$FF,$00,$01,$01,$00,$01,$00,$01,$01,$00    ; instrumento 13 ($0D)
    DB $00,$00,$01,$01,$32,$00,$00,$B0,$50,$81,$00,$00,$00,$00,$01    ; instrumento 14 ($0E)
    DB $00,$00,$06,$06,$00,$00,$00,$F8,$08,$00,$00,$00,$01,$01,$00    ; instrumento 15 ($0F)
TABLA_ENVOLVENTES_PSG:                ; $CB5A (24 bytes, 4 entradas x 6 bytes) -- formas de envolvente de percusion (SET_ENVELOPE_SHAPE copia una de estas 6-tuplas a TABLA_ENVOLVENTE_RUIDO_PSG+4)
    DB $0A,$00,$03,$00,$01,$00    ; entrada 0
    DB $1E,$00,$F7,$00,$01,$00    ; entrada 1
    DB $01,$03,$0F,$FB,$00,$01    ; entrada 2
    DB $20,$00,$FF,$00,$0A,$00    ; entrada 3

TABLA_SUBPATRONES_PSG:               ; $CB72 (42 bytes, 21 punteros de 16 bits) -- tabla de punteros a los
; 13 subpatrones compartidos (CALL_SUBPATTERN indexa aqui); entradas 13-20 repiten el
; mismo puntero (SUBPATRON_00_CB9C, el primer subpatron) -- ver FINDINGS.md. REFORMATEADO
; a DW con etiquetas reales (antes hex literal en filas de 6/8/7 punteros sin relacion
; con las 21 entradas declaradas) para que el ensamblador resuelva las direcciones. ---
    DW SUBPATRON_00_CB9C    ; entrada 0
    DW SUBPATRON_01_CBD3    ; entrada 1
    DW SUBPATRON_02_CC1C    ; entrada 2
    DW SUBPATRON_03_CC45    ; entrada 3
    DW SUBPATRON_04_CC96    ; entrada 4
    DW SUBPATRON_05_CCD0    ; entrada 5
    DW SUBPATRON_06_CCEF    ; entrada 6
    DW SUBPATRON_07_CD16    ; entrada 7
    DW SUBPATRON_08_CD3F    ; entrada 8
    DW SUBPATRON_09_CD76    ; entrada 9
    DW SUBPATRON_10_CD91    ; entrada 10
    DW SUBPATRON_11_CDAB    ; entrada 11
    DW SUBPATRON_12_CBB0    ; entrada 12
    DW SUBPATRON_00_CB9C    ; entrada 13 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 14 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 15 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 16 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 17 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 18 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 19 (repite)
    DW SUBPATRON_00_CB9C    ; entrada 20 (repite)

; --- $CB9C-$CDCB (559 bytes): bytecode de los 13 subpatrones compartidos
; (mismo lenguaje de 15 comandos que los .snd de eventos), llamados via
; CALL_SUBPATTERN desde 02_boot_ch2_ce0c.snd y otros -- ver FINDINGS.md.
; EXTRAIDOS a ficheros propios en data/sound/*.spt (extension distinta a
; .snd para no mezclarlos con los 16 scripts reales de evento/musica, pero
; MISMO bytecode -- mmsnd_tool.py disasm/asm/roundtrip funciona sin ningun
; cambio sobre ellos, verificado: los 13 pasan roundtrip exacto). Limites
; calculados a partir de las direcciones unicas de TABLA_SUBPATRONES_PSG
; (sin bytes sobrantes ni solapados, 559 bytes en total) y CADA UNO
; termina en $8D (comando 13, RETURN_SUBPATTERN) -- confirma el modelo
; del bytecode. Nombrados por indice de entrada en TABLA_SUBPATRONES_PSG
; (00-12), no por orden de memoria. ---
SUBPATRON_00_CB9C:            ; $CB9C (20 bytes) -- entrada 0 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/00_subpatron00_cb9c.spt"
SUBPATRON_12_CBB0:                     ; $CBB0 (35 bytes) -- entrada 12 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/12_subpatron12_cbb0.spt"
SUBPATRON_01_CBD3:                     ; $CBD3 (73 bytes) -- entrada 1 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/01_subpatron01_cbd3.spt"
SUBPATRON_02_CC1C:                     ; $CC1C (41 bytes) -- entrada 2 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/02_subpatron02_cc1c.spt"
SUBPATRON_03_CC45:                     ; $CC45 (81 bytes) -- entrada 3 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/03_subpatron03_cc45.spt"
SUBPATRON_04_CC96:                     ; $CC96 (58 bytes) -- entrada 4 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/04_subpatron04_cc96.spt"
SUBPATRON_05_CCD0:                     ; $CCD0 (31 bytes) -- entrada 5 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/05_subpatron05_ccd0.spt"
SUBPATRON_06_CCEF:                     ; $CCEF (39 bytes) -- entrada 6 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/06_subpatron06_ccef.spt"
SUBPATRON_07_CD16:                     ; $CD16 (41 bytes) -- entrada 7 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/07_subpatron07_cd16.spt"
SUBPATRON_08_CD3F:                     ; $CD3F (55 bytes) -- entrada 8 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/08_subpatron08_cd3f.spt"
SUBPATRON_09_CD76:                     ; $CD76 (27 bytes) -- entrada 9 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/09_subpatron09_cd76.spt"
SUBPATRON_10_CD91:                     ; $CD91 (26 bytes) -- entrada 10 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/10_subpatron10_cd91.spt"
SUBPATRON_11_CDAB:                     ; $CDAB (32 bytes) -- entrada 11 de TABLA_SUBPATRONES_PSG
    INCBIN "data/sound/spt/11_subpatron11_cdab.spt"

; --- Los scripts de sonido reales. RESUELTO (ver FINDINGS.md,
; "$6128 es el indice de efecto de sonido"): $CDCB/$CDFF/$CE0C son la
; musica principal de 3 canales que instala INICIO al arrancar; lo que
; antes se trataba como "un solo script de 383 bytes en $CE0C" es en
; realidad ESE canal 2 de la musica (78 bytes, $CE0C-$CE5A) seguido
; de 13 fragmentos cortos INDEPENDIENTES, cada uno el efecto de un
; evento de juego concreto -- confirmado cruzando
; DESPACHAR_EFECTO_SONIDO/TABLA_RECURSOS_SONIDO_EVENTO (madmix_scr.asm,
; $60DC/$60FE: tabla real indice-de-$6128 -> puntero de script) contra
; cada sitio del codigo que escribe ($6128). Nombrado por indice de
; evento + candidato del catalogo de sonidos del usuario donde el
; cruce es solido; bytecode en si sin descifrar (fuera de alcance,
; ver FINDINGS.md). ---
GUION_MELODIA_CANAL_0:                 ; $CDCB (52 bytes) -- musica, canal 0
    INCBIN "data/sound/snd/00_script_cdcb.snd"
GUION_MELODIA_CANAL_1:                 ; $CDFF (13 bytes) -- musica, canal 1
    INCBIN "data/sound/snd/01_script_cdff.snd"
GUION_MELODIA_CANAL_2:                 ; $CE0C (78 bytes) -- musica, canal 2
    INCBIN "data/sound/snd/02_boot_ch2_ce0c.snd"
GUION_EVT09_TRAMPILLA_TRANSICION_CE5A:                    ; $CE5A (24 bytes) -- $6128=9: transicion apertura/cierre de trampilla (HNDLR_TRAMPILLA_ABIERTA_DERECHA/HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA)
    INCBIN "data/sound/snd/03_evt09_trampilla_transicion_ce5a.snd"
GUION_EVT04_DISPARO_AVION_CE72:                    ; $CE72 (12 bytes) -- $6128=4: REGISTRAR_PISTA_TANQUE_AVION -- CONFIRMADO por el usuario (jugador original) que es el "Disparo (modo avion)" del catalogo (#9). REGISTRAR_PISTA_TANQUE_AVION es generica (la llama tambien HNDLR_PISTA_COCONAVE/avion, no solo el modo tanque) -- RESUELTO: no tiene nada que ver con las trampillas reales (tipos 17-19), es la funcion de registro de pista
    INCBIN "data/sound/snd/04_evt04_disparo_avion_ce72.snd"
GUION_EVT07_PISTA_CE7E:                    ; $CE7E (13 bytes) -- $6128=7: aviso de pista tanque/avion (GHOST_HINT_HANDLER) + cola de ITEM_EFFECT
    INCBIN "data/sound/snd/05_evt07_pista_ce7e.snd"
GUION_EVT01_BOLA_CLAVADA_CE8B:                    ; $CE8B (17 bytes) -- $6128=1: liberar bola clavada (HNDLR_BOLITA_CLAVADA, modo herramienta) -- candidato catalogo #7
    INCBIN "data/sound/snd/06_evt01_bola_clavada_ce8b.snd"
GUION_EVT11_BOLA_PODER_CE9C:                    ; $CE9C (16 bytes) -- $6128=11: bola de poder activada (HNDLR_BOLA_PODER, evento final)
    INCBIN "data/sound/snd/07_evt11_bola_poder_ce9c.snd"
GUION_EVT06_PLANTA_CLAVADA_CEAC:                    ; $CEAC (54 bytes) -- $6128=6: plantar bola clavada (HNDLR_REGPUNANTOSO)
    INCBIN "data/sound/snd/08_evt06_planta_clavada_ceac.snd"
GUION_EVT00_BOLITA_CEE2:                    ; $CEE2 (14 bytes) -- $6128=0: comer bolita normal (HNDLR_BOLITA_NORMAL) -- candidato catalogo #4
    INCBIN "data/sound/snd/09_evt00_bolita_cee2.snd"
GUION_EVT10_INICIO_NIVEL_CEF0:                    ; $CEF0 (23 bytes) -- $6128=10 y llamado directo desde BUSCAR_COLUMNA_HUD (offsets
                                      ; +0/+7/+14, madmix1.asm): soniquete de inicio de nivel -- candidato catalogo #2
    INCBIN "data/sound/snd/10_evt10_inicio_nivel_cef0.snd"
GUION_EVT08_ARMA_MODO_CF07:                    ; $CF07 (32 bytes) -- $6128=8: arma el temporizador de modo especial (ITEM_EFFECT, IE_57FD)
    INCBIN "data/sound/snd/11_evt08_arma_modo_cf07.snd"
GUION_EVT13_FIN_MODO_CF27:                    ; $CF27 (29 bytes) -- $6128=13: evento final tras consumirse un modo especial (ITEM_EFFECT, IE_WAIT)
    INCBIN "data/sound/snd/12_evt13_fin_modo_cf27.snd"
GUION_EVT05_MARIQUITA_REPONE_CF44:                    ; $CF44 (30 bytes) -- $6128=5: reponer bolita comida (HNDLR_MARICOCO, "mariquita" -- sprite $27=39=mariquita_der) -- candidato catalogo #8
    INCBIN "data/sound/snd/13_evt05_mariquita_repone_cf44.snd"
GUION_EVT02_FLECHA_CF62:                    ; $CF62 (14 bytes) -- $6128=2: pasar por loseta-flecha (4 HANDLER_2Fxx) -- candidato catalogo #10
    INCBIN "data/sound/snd/14_evt02_flecha_cf62.snd"
GUION_EVT03_MODO_ESPECIAL_CF70:                    ; $CF70 (27 bytes) -- $6128=3: activar/terminar modo especial generico (tanque/avion/herramienta/hipopotamo)
    INCBIN "data/sound/snd/15_evt03_modo_especial_cf70.snd"


VACIAR_CANALES_SONIDO:                 ; = $CF8B (confirmado; ver nota sobre correccion abajo)
    LD     DE,$0000
    XOR    A
    CALL   INSTALAR_RECURSO_SONIDO_EN_A
    LD     DE,$0000
    LD     A,$01
    CALL   INSTALAR_RECURSO_SONIDO_EN_A
    LD     DE,$0000
    LD     A,$02
    CALL   INSTALAR_RECURSO_SONIDO_EN_A
    EI
    RET

; --- Cuerpo COMPLETO del nivel 13 (0xCFA4-0xD243, 672 bytes = 21x32) ---
; CORREGIDO (antes partido en dos: 92 bytes con la etiqueta antigua
; RM_TABLE_CFA4/CUERPO_L13_HEAD_CFA4 + 580 bytes en CUERPO_L13_MAZE_D000,
; historicamente el antiguo maze_data.bin sin nombre propio). Los
; primeros 92 bytes se etiquetaron en una sesion muy antigua como
; "posible tabla de envolvente/percusion de sonido" solo por estar
; pegados a las tablas de sonido reales -- NUNCA confirmado: con el
; driver de sonido ya desensamblado por completo (arriba, $C4A0-$C8C9)
; se confirmo que ninguna rutina de sonido, ni de ningun otro
; subsistema, hace jamas referencia a esa direccion.
;
; DESCARTADA la hipotesis de sonido: decodificando esos 92 bytes como
; losetas (indice = bits 0-6, ver data/tiles/*.til) el contenido no es
; ruido ni relleno -- es una sala de laberinto perfectamente coherente
; y simetrica izquierda-derecha: borde de muro_cemento, dos bloques de
; suelo_con_bola con su item_bola_poder a cada lado, y estrellas
; decorativas en el mismo patron que usa el resto de niveles reales.
; Es demasiada coincidencia que su tamano sea EXACTAMENTE lo que falta
; para completar el cuerpo de 672 bytes del nivel 13 (92+580) Y que el
; contenido decodifique a tiles con sentido -- nunca fue dato de
; sonido, siempre fue nivel 13, y el "solape con sonido" documentado
; en sesiones anteriores fue una deduccion nuestra equivocada, no algo
; que el juego haga de verdad. CARGAR_NIVEL modifica 10 de esos 92
; bytes en RAM cada vez que el nivel 13 carga (limpia el bit 7 de los
; bytes $BF, ver FINDINGS.md) exactamente igual que hace con el resto
; del cuerpo del nivel.
;
; A diferencia del resto de ficheros en data/niveles/ (que compilan
; dentro de MADMIX.SCR via madmix_scr.asm), este y CUERPO_L14_D244
; compilan aqui, dentro de MADMIX1.BIN -- el ahorro de memoria viene
; de que ambos binarios coexisten en RAM en tiempo de ejecucion, asi
; que CARGAR_NIVEL puede leer el cuerpo de estos 2 niveles
; directamente de aqui en vez de duplicarlo en MADMIX.SCR. Prueba de
; diseño deliberado: el cuerpo del nivel 13 termina EXACTO donde
; empieza el puntero de cuerpo del nivel 14. Unificado en un unico
; fichero editable (antes 2 ficheros, sin ninguna razon real para
; mantenerlos separados), igual que el resto de niveles de
; data/niveles/. ---
CUERPO_L13_CFA4:                       ; $CFA4 (672 bytes) -- cuerpo completo del nivel 13
    INCBIN "data/niveles/body_l13.bin"

; --- Cuerpo COMPLETO del nivel 14 (0xD244-0xD523, 736 bytes = 23x32) ---
; CORREGIDO (antes partido en CUERPO_L14_MAZE_D244 + GUION_DEMO_NIVEL1,
; 700+36 bytes): una sesion antigua dedujo que los ultimos 36 bytes
; ($D500-$D524) eran el arranque real del guion de demo "nivel 1",
; simplemente reasignado por TABLA_CICLO_NIVELES a $D524 por alguna
; razon -- de ahi el nombre GUION_DEMO_NIVEL1 en esa direccion. Esa
; deduccion era erronea: TABLA_CICLO_NIVELES SIEMPRE ha apuntado a
; $D524, nunca a $D500 (ver TABLA_CICLO_NIVELES en madmix_scr.asm), es
; decir, $D500-$D524 nunca ha sido ni un byte de guion de demo --
; siempre ha sido la cola del cuerpo del nivel 14, exactamente el
; mismo caso que CUERPO_L13_CFA4 (ver su comentario arriba: misma
; logica, mismo tipo de error de una sesion antigua). Unificado en un
; unico fichero editable, igual que el resto de niveles de
; data/niveles/. ---
CUERPO_L14_D244:                       ; $D244 (736 bytes) -- cuerpo completo del nivel 14
    INCBIN "data/niveles/body_l14.bin"

; ==============================================================
;  0xD524-0xD6B6 (402 bytes): RESUELTO -- son 10 GUIONES de
;  reproduccion automatica para el modo DEMO ("ciclador de niveles
;  de muestra"). Cada guion es una secuencia de pares
;  [duracion en fotogramas, direccion simulada] terminada en un
;  par con direccion $FF. Consumidos por TAIL_LEVELCYCLE_MAIN
;  ($6045, madmix_scr.asm) via TABLA_CICLO_NIVELES ($60D0): lee
;  [nivel, puntero de 16 bits] y usa el puntero como IX para
;  esperar el fotograma indicado por (IX+0) y simular la direccion
;  (IX+1) (con AND $1F) como si fuera una pulsacion real, hasta
;  encontrar direccion $FF (fin de guion, pasa al siguiente nivel
;  del ciclo).
;
;  Los 402 bytes se dividen EXACTOS en 10 guiones consecutivos
;  (verificado recorriendolos de un tiron desde 0xD524, sin ningun
;  byte sobrante): solo 4 estan referenciados por TABLA_CICLO_NIVELES
;  (niveles 1, 2, 4 y 5). Los otros 6 guiones NO tienen ningun
;  puntero que los referencie -- contenido real y bien formado, pero
;  sin conectar, mismo patron que el nivel oculto y el hueco de
;  TABLA_NIVELES (ver FINDINGS.md).
; ==============================================================
; 0xD524: nivel 1 -- referenciado exacto por TABLA_CICLO_NIVELES
GUION_DEMO_NIVEL1:
    INCBIN "data/demos/01_nivel1.dem"
; 0xD564: nivel 2 -- referenciado exacto por TABLA_CICLO_NIVELES
GUION_DEMO_NIVEL2:
    INCBIN "data/demos/02_nivel2.dem"
; 0xD5C2: sin referenciar -- candidato a nivel 3 (hueco logico entre 2 y 4)
GUION_DEMO_SINREF_1:
    INCBIN "data/demos/03_sinref.dem"
; 0xD5D4: nivel 4 -- referenciado exacto por TABLA_CICLO_NIVELES
GUION_DEMO_NIVEL4:
    INCBIN "data/demos/04_nivel4.dem"
; 0xD616: sin referenciar
GUION_DEMO_SINREF_2:
    INCBIN "data/demos/05_sinref.dem"
; 0xD61A: sin referenciar
GUION_DEMO_SINREF_3:
    INCBIN "data/demos/06_sinref.dem"
; 0xD632: sin referenciar
GUION_DEMO_SINREF_4:
    INCBIN "data/demos/07_sinref.dem"
; 0xD644: nivel 5 -- referenciado exacto por TABLA_CICLO_NIVELES
GUION_DEMO_NIVEL5:
    INCBIN "data/demos/08_nivel5.dem"
; 0xD69C: sin referenciar
GUION_DEMO_SINREF_5:
    INCBIN "data/demos/09_sinref.dem"
; 0xD6A2: sin referenciar, termina justo donde empieza TABLA_RLE_MARCO_CARAMELO
GUION_DEMO_SINREF_6:
    INCBIN "data/demos/10_sinref.dem"

; ==============================================================
;  0xD6B6-0xDD82 (1740 bytes): ES EL MARCO DE CARAMELO -- CONFIRMADO
;  VISUALMENTE. Es una tabla RLE que DIBUJAR_MARCO_CARAMELO_VRAM
;  (madmix_scr.asm, $6429) vuelca SECUENCIALMENTE en la tabla de
;  patrones de VRAM completa ($0000-$17FF, 6144 bytes): 870 pares
;  (valor,repeticion), BC=$0366 iteraciones x 2 bytes = exacto 1740
;  bytes de tabla, terminando justo en $DD82 (donde empieza el
;  codigo de mas abajo -- verificado por aritmetica exacta:
;  $D6B6 + 2*$0366 = $DD82), y la SUMA de las 870 repeticiones da
;  EXACTO 6144 = $1800, el tamano completo de la tabla de patrones
;  de SCREEN2. Expandiendo el RLE y renderizando con la tabla de
;  nombres identidad (ya confirmada en volcado de VRAM real, ver
;  FINDINGS.md) sale el marco de caramelo COMPLETO Y RECONOCIBLE:
;  rayas diagonales rojiblancas arriba/abajo, remates redondeados en
;  las 4 esquinas y el motivo de "brillo" cerca de la esquina
;  inferior izquierda -- pixel a pixel igual que
;  `dump_openmsx/screen_reconstructed.png` (ver render en
;  `dump_openmsx/candy_frame_reconstructed.png`). El centro sale
;  negro en el render aislado porque ese es precisamente el area que
;  las losetas del laberinto (GRAFICOS_LOSETAS) sobrescriben despues -- el
;  marco sobrevive porque el laberinto nunca dibuja ahi.
;
;  Aparte de este uso principal, CALCULAR_DIRECCION_MASCARA_ACTOR ($8988, en este
;  fichero) + COMPONER_ACTORES_EN_BUFFER acceden a un SUBTRAMO de esta
;  misma tabla ($DC00 en adelante) de forma ALEATORIA (offset segun
;  la posicion en pantalla del actor), leyendo pares de 16 bits como
;  mascaras AND/OR de composicion de sprite contra el fondo (ver
;  hallazgo "Zona 0xDC00" en FINDINGS.md) -- confirmado en vivo que
;  esta subzona es completamente estatica en RAM durante el juego.
; ==============================================================
TABLA_RLE_MARCO_CARAMELO:
    INCBIN "data/img/marco_caramelo_forma.img"

; ==============================================================
;  0xDD82-0xDD8A (8 bytes): CODIGO real, sin llamador conocido en
;  el codigo ya transcrito (posible punto de entrada externo, p.ej.
;  desde MADMIX0.BIN u otro mecanismo de reinicio/comprobacion --
;  disparador sin confirmar, ver FINDINGS.md). Conmuta la
;  configuracion de slot primario (A=$55, mismo patron que usa
;  MADMIX0.BIN via el puerto $A8) y salta de vuelta al arranque.
; ==============================================================
REINICIO_SLOT_DD82:
    DI
    LD     A,$55
    OUT    ($A8),A
    JP     START             ; = $8400

; ==============================================================
;  0xDD8A-0xDD93 (9 bytes): CODIGO real, CON llamador confirmado --
;  es el destino real de "CALL $DD8A" en LEER_JOYSTICK. Escribe A
;  (el valor de mezcla del PSG ya preparado por el llamador) y
;  despues selecciona el registro 14 del PSG (Puerto de E/S A,
;  usado en MSX para leer el joystick 1) y devuelve su valor en A.
; ==============================================================
CONFIGURAR_Y_LEER_JOYSTICK_PSG:
    OUT    ($A1),A
    LD     A,14                   ; registro 14 del PSG (Puerto de E/S A, usado en MSX para leer el joystick 1)
    OUT    ($A0),A
    IN     A,($A2)
    RET

; --- 0xDD93-0xDD96 (3 bytes): CODIGO MUERTO confirmado -- POP HL /
; EI / RET, sin NINGUN JP/JR/CALL en todo el codigo fuente
; reconstruido que apunte aqui (busqueda exhaustiva, ver FINDINGS.md).
; Mismo patron exacto en 0x2BF0 de madmix_scr_body.asm (tambien
; muerto, mismo hallazgo). ---
    POP    HL
    EI
    RET

    DS $DDA0-$, $FF   ; 0xDD96-0xDD9F (10 bytes): relleno solido $FF

; ==============================================================
;  Byte final $DDA0 ($CD): fuera de los datos reales del juego.
;  $DDA0 es el ultimo byte INCLUSIVE del rango real cargado (ver
;  nota de mas arriba sobre por que el limite real es $DDA1
;  exclusivo); este $CD es simplemente el primer byte de lo que
;  seria la siguiente instruccion si el fichero continuara, pero
;  el .BIN termina aqui -- relleno de sector de disco, no parte
;  del programa.
; ==============================================================
    DB $CD

END_OF_FILE_M1:
