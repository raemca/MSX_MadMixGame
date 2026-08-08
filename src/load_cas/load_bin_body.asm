; ============================================================
;  LOAD.BIN (version de cinta, Topo Soft 1987/88) - MSX1
;  El orquestador real de la carga por cinta -- 299 bytes, extraido
;  del bloque "LOAD  " del .cas de 1988 (start=$DDA0 end=$DECA
;  exec=$DDA0) y desensamblado byte a byte con Z80Dasm.exe (disasm
;  limpio de principio a fin, sin ambiguedad de offset).
;
;  Invocado desde BASIC: "DEF USR=56736!:A=USR(0)" (56736=$DDA0),
;  tras "BLOAD CAS:LOAD.BIN" + "BLOAD CAS:TEST.BIN" (ambos SIN ",R",
;  solo cargan, no ejecutan -- ver MADMIX.bas).
;
;  Hace, en un unico paso, lo que en disco requieren DOS ficheros
;  (MADMIX.SCR aterrizando en $8800 + MADMIX0.BIN/RELOCATOR haciendo
;  el LDIR a $1000): como su rutina de lectura de cinta (LEER_CINTA,
;  $DDCC) acepta la direccion destino como parametro libre (IX), pide
;  que escriba DIRECTAMENTE en $1000 y luego en $8400 -- se ahorra el
;  aterrizaje intermedio y el LDIR. Ver FINDINGS.md, seccion "RESUELTO:
;  estructura completa de la version de cinta", para el analisis
;  completo de esta diferencia disco/cinta.
;
;  Comparte espacio de simbolos con madmix1_body.asm/madmix_scr_body.asm
;  (via main.asm) -- referencia DIBUJAR_PORTADA/START en vez de $1000/$8400
;  literales, y DETECTAR_SLOTS_RAM (test_bin_body.asm) en vez de $C350.
; Ingeniería inversa, herramientas y documentación de este proyecto: Rafael Eduardo Martín Candial (raemca@hotmail.com)
; ============================================================

ORQUESTADOR_CARGA_CINTA:
    CALL DETECTAR_SLOTS_RAM      ; TEST.BIN: detecta slots de RAM
    CALL APLICAR_SLOT_PAGINA_0
    CALL APLICAR_SLOT_PAGINA_1
    CALL APLICAR_SLOT_PAGINA_2
    LD IX, DIBUJAR_PORTADA       ; direccion destino final directa ($1000)
    LD DE, 21760                ; bytes -- mismo tamano que el LDIR de RELOCATOR (disco)
    LD A, $FF                  ; parametro que LEER_CINTA compara con el
                              ; valor leido de la ROM (posible cabecera/
                              ; tipo de bloque esperado, no verificado al 100%)
    SCF
    CALL LEER_CINTA              ; lee de cinta IX=destino, DE=bytes
    CALL DIBUJAR_PORTADA             ; ejecuta el bloque recien cargado (portada)
    LD IX, START                   ; direccion nativa de MADMIX1.BIN ($8400)
    LD DE, 22944                    ; bytes
    LD A, $FF                  ; mismo parametro que arriba
    SCF
    CALL LEER_CINTA
    JP START                           ; salta a JT_INICIO -- igual que JUMP_TO_ENGINE (disco)

; --- Rutina generica de lectura de cinta (bit a bit). Recibe la
; direccion destino en IX y el numero de bytes en DE. Usa ganchos
; fijos de la ROM BASIC ($00E1/$C961/$CDD9/$EDD9/$69ED, empujados a
; pila) y parpadea el borde escribiendo en el puerto $99 (VDP) --
; el tipico parpadeo de borde de los cargadores de cinta comerciales. ---
LEER_CINTA:
    DI
    EX AF, AF'
    EXX
    PUSH BC
    PUSH DE
    PUSH HL
    LD HL, $FCA6              ; variable de sistema MSX (zona de trabajo)
    LD B, 12                  ; 12 entradas (24 bytes) de la tabla de ganchos
.BUCLE_GUARDAR_GANCHOS:
    DEC HL
    LD D, (HL)
    DEC HL
    LD E, (HL)
    PUSH DE
    DJNZ .BUCLE_GUARDAR_GANCHOS
    LD A, H
    LD H, B
    LD L, B
    ADD HL, SP
    LD SP, $FCA4                ; variable de sistema MSX (zona de trabajo)
    LD DE, $C961                 ; gancho ROM
    PUSH DE
    LD DE, $EDD9                  ; gancho ROM
    PUSH DE
    LD DE, $00E1                   ; gancho ROM
    PUSH DE
    LD DE, $CDD9                    ; gancho ROM
    PUSH DE
    LD DE, $69ED                     ; gancho ROM
    PUSH DE
    PUSH HL
    EXX
    LD C, $A8                  ; puerto de conmutacion MSX (slot primario)
    IN H, (C)
    AND H
    LD L, A
    CALL $FC9A                        ; gancho de sistema (rutina ROM, comprobacion
                                      ; de tecla/interrupcion en la RAM de trabajo)
    JR C, .FINALIZAR_LECTURA
    LD A, $E4                  ; modo/parametro para el siguiente $FC9A
                              ; (valor no verificado al 100%)
    LD ($FC9E), A               ; variable de sistema MSX (zona de trabajo)
    CALL $FC9A
    JR C, .FINALIZAR_LECTURA
    LD B, A
    EX AF, AF'
    CP B
    SCF
    JR NZ, .FINALIZAR_LECTURA
    JR .LLAMAR_GANCHO_BIT
.BUCLE_LEER_BIT:
    POP AF
    PUSH IX
    EXX
    POP BC
    LD HL, $0372                ; delta usado para comprobar si el destino
                              ; (BC) cae dentro de una zona protegida --
                              ; logica de solapamiento, no verificada al 100%
    ADD HL, BC
    JR NC, .ALMACENAR_BYTE
    EX DE, HL
    LD HL, $FFE8                ; = -24, segundo delta de la misma comprobacion
    ADD HL, DE
    JR C, .ALMACENAR_BYTE
    POP HL
    PUSH HL
    ADD HL, DE
    LD (HL), A
    LD A, (BC)
.ALMACENAR_BYTE:
    LD (BC), A
    EXX
    INC IX
    DEC DE
.LLAMAR_GANCHO_BIT:
    CALL $FC9A
    JR C, .FINALIZAR_LECTURA
    PUSH AF
    XOR B
    LD B, A
    LD A, E
    OUT ($99), A               ; VDP -- parpadeo de borde (indicador de carga)
    OR D
    LD A, $87                  ; VDP -- selecciona registro 7 (color)
    OUT ($99), A
    JR NZ, .BUCLE_LEER_BIT
    POP AF
.FINALIZAR_LECTURA:
    SBC A, A
    OR B
    EX AF, AF'
    LD A, $F3                  ; modo/parametro para el $FC9A de cierre
                              ; (valor no verificado al 100%)
    LD ($FC9E), A               ; variable de sistema MSX (zona de trabajo)
    XOR A
    CALL $FC9A
    EXX
    POP HL
    LD SP, HL
    LD HL, $FC8E                 ; variable de sistema MSX (zona de trabajo)
    LD B, 12                     ; 12 entradas (24 bytes), simetrico al guardado
.BUCLE_RESTAURAR_GANCHOS:
    POP DE
    LD (HL), E
    INC HL
    LD (HL), D
    INC HL
    DJNZ .BUCLE_RESTAURAR_GANCHOS
    POP HL
    POP DE
    POP BC
    EXX
    EX AF, AF'
    CP 1
    RET

; --- Codigo sin invocar desde ningun otro punto de este fichero
; (no referenciado por CALL/JR/JP dentro de LOAD.BIN) -- posible
; vestigio o gancho para un caso no usado en esta edicion. Parece
; una pareja de rutinas de apagado/reinicio del "parpadeo de borde"
; (mismo puerto $99 que LEER_CINTA). ---
AYUDANTE_MOTOR_CINTA_A:
    LD E, A
    AND $0F                    ; conserva el nibble bajo (uso exacto no
                              ; verificado -- codigo sin invocar)
    OUT ($99), A               ; VDP
    LD A, $87                  ; VDP -- selecciona registro 7 (color)
    OUT ($99), A
    SCF
    RET
AYUDANTE_MOTOR_CINTA_B:
    LD E, $13                  ; valor guardado en E, sin uso posterior en
                              ; esta rutina (codigo sin invocar)
    LD A, $09
    OUT ($AB), A                ; puerto distinto de $99/$A8 -- proposito
                              ; no verificado (codigo sin invocar)
    LD A, $01                  ; VDP -- dato para el registro 7 de abajo
    OUT ($99), A
    LD A, $87                  ; VDP -- selecciona registro 7 (color)
    OUT ($99), A
    RET

; --- 6 variantes de "aplicar configuracion de pagina/slot" -- 3 usan
; la config guardada en EXPTBL_COMPLEMENTO_A/SLOT_PRIMARIO_A ($E291/
; $E290, no invocadas desde este fichero, ver comentario de arriba), 3
; usan EXPTBL_COMPLEMENTO_B/SLOT_PRIMARIO_B ($E293/$E292, las que SI
; llama ORQUESTADOR_CARGA_CINTA, arriba). Todas confluyen en 3 posibles
; "setups" (D/E) y de ahi al conmutador comun APLICAR_CAMBIO_SLOT. ---
APLICAR_SLOT_ORIGINAL_PAGINA_0:
    LD HL, EXPTBL_COMPLEMENTO_A   ; y, tras el DEC HL de abajo, SLOT_PRIMARIO_A
    JR CONFIGURAR_MASCARA_PAGINA_0
APLICAR_SLOT_ORIGINAL_PAGINA_1:
    LD HL, EXPTBL_COMPLEMENTO_A
    JR CONFIGURAR_MASCARA_PAGINA_1
APLICAR_SLOT_ORIGINAL_PAGINA_2:
    LD HL, EXPTBL_COMPLEMENTO_A
    JR CONFIGURAR_MASCARA_PAGINA_2
APLICAR_SLOT_PAGINA_0:
    LD HL, EXPTBL_COMPLEMENTO_B   ; y, tras el DEC HL de abajo, SLOT_PRIMARIO_B
    JR CONFIGURAR_MASCARA_PAGINA_0
APLICAR_SLOT_PAGINA_1:
    LD HL, EXPTBL_COMPLEMENTO_B
    JR CONFIGURAR_MASCARA_PAGINA_1
APLICAR_SLOT_PAGINA_2:
    LD HL, EXPTBL_COMPLEMENTO_B
    JR CONFIGURAR_MASCARA_PAGINA_2
CONFIGURAR_MASCARA_PAGINA_0:
    LD D, $03                  ; mascara AND: bits 1-0 (pagina 0) del
                              ; registro de slot
    LD E, $FC                  ; complemento de D -- limpia esos mismos
                              ; bits antes de insertar el valor nuevo
    JR APLICAR_CAMBIO_SLOT
CONFIGURAR_MASCARA_PAGINA_1:
    LD D, $0C                  ; mascara AND: bits 3-2 (pagina 1)
    LD E, $F3                  ; complemento de D
    JR APLICAR_CAMBIO_SLOT
CONFIGURAR_MASCARA_PAGINA_2:
    LD D, $30                  ; mascara AND: bits 5-4 (pagina 2)
    LD E, $CF                  ; complemento de D
APLICAR_CAMBIO_SLOT:
    DI
    LD A, (HL)                 ; (HL) = EXPTBL_COMPLEMENTO_x -- valor de subslot guardado
    AND D
    LD B, A
    LD A, ($FFFF)              ; EXPTBL
    CPL
    AND E
    OR B
    LD ($FFFF), A              ; mezcla el subslot guardado en EXPTBL
    DEC HL
    LD A, (HL)                 ; (HL) = SLOT_PRIMARIO_x -- valor de slot primario guardado
    AND D
    LD B, A
    IN A, ($A8)                 ; puerto de conmutacion MSX (slot primario)
    AND E
    OR B
    OUT ($A8), A                ; mezcla el slot primario guardado
    RET
    DB $00                      ; byte suelto tras el final real de la rutina,
                                ; contenido desconocido

END_OF_FILE_LOADBIN:
