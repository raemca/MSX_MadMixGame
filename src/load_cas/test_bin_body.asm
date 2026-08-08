; ============================================================
;  TEST.BIN (version de cinta, Topo Soft 1987/88) - MSX1
;  Motor de deteccion de RAM/slots -- 253 bytes, extraido del
;  bloque "TEST  " del .cas de 1988 (start=$C350 end=$C44C exec=$C350)
;  y desensamblado byte a byte con Z80Dasm.exe (sin ambiguedad de
;  offset, disasm limpio de principio a fin).
;
;  Invocado por LOAD.BIN (ver load_bin_body.asm) como primer paso,
;  antes de tocar la cinta: recorre las combinaciones de slot
;  primario/secundario de las paginas $4000 y $8000 (escritura
;  complementaria $20/$FA, patron clasico de deteccion de RAM en
;  MSX via ENASLT) y guarda dos configuraciones de slot resultantes
;  en SLOT_PRIMARIO_A/EXPTBL_COMPLEMENTO_A/SLOT_PRIMARIO_B/
;  EXPTBL_COMPLEMENTO_B ($E290-$E293) -- LOAD.BIN las aplica luego con
;  las familias APLICAR_SLOT_ORIGINAL_PAGINA_x/APLICAR_SLOT_PAGINA_x
;  (ver load_bin_body.asm).
;
;  Detalle no trivial encontrado al desensamblar: el bloque final
;  (ENASLT_EXTENDIDO, $C3D2-$C44C, 122 bytes) es una PLANTILLA que
;  nunca se ejecuta en su posicion original -- se copia con LDIR a
;  una zona de trabajo transitoria en $AFC8 (fuera del alcance de
;  este proyecto, no pertenece al juego) y solo se ejecuta desde
;  ahi. Sus saltos CALL/JP absolutos ya estan escritos para la
;  direccion FINAL post-reubicacion ($AFxx/$Bxxx) -- se han dejado
;  como hex literal (imprescindible para no romper la fidelidad de
;  bytes) con un comentario indicando a que punto de este mismo
;  bloque equivalen. Sus saltos JR/DJNZ, al ser relativos, SI se
;  han convertido a etiquetas reales (funcionan igual reubicados o
;  no).
; Ingeniería inversa, herramientas y documentación de este proyecto: Rafael Eduardo Martín Candial (raemca@hotmail.com)
; ============================================================

DETECTAR_SLOTS_RAM:
    DI
    LD A, ($8000)            ; guarda el byte original de $8000 (se
                              ; sobreescribe durante el test de RAM, se
                              ; restaura al final)
    PUSH AF
    CALL GUARDAR_CONFIG_SLOT_A
    LD HL, $0024            ; ENASLT (rutina ROM estandar de cambio de slot)
    LD (DETECTAR_RAM_PAGINA.OPERANDO_ENASLT_AUTOMODIFICADO), HL
    LD HL, $4000              ; pagina 1 ($4000-$7FFF)
    CALL DETECTAR_RAM_PAGINA
    LD HL, $8000              ; pagina 2 ($8000-$BFFF)
    CALL DETECTAR_RAM_PAGINA
    LD HL, ENASLT_EXTENDIDO     ; plantilla a reubicar (ver cabecera)
    LD DE, $AFC8             ; zona de trabajo transitoria, fuera del juego
    LD BC, 122                ; bytes (tamano de ENASLT_EXTENDIDO)
    LDIR
    LD HL, $AFC8               ; misma zona de trabajo transitoria de arriba
    LD (DETECTAR_RAM_PAGINA.OPERANDO_ENASLT_AUTOMODIFICADO), HL  ; repunta el CALL
                              ; auto-modificado a la copia reubicada
    LD HL, $0000               ; pagina 0 ($0000-$3FFF)
    CALL DETECTAR_RAM_PAGINA            ; ahora vía la copia reubicada
    CALL GUARDAR_CONFIG_SLOT_B
    LD A, (SLOT_PRIMARIO_A)
    OUT ($A8), A             ; restaura slot primario (puerto de conmutacion MSX)
    LD A, (EXPTBL_COMPLEMENTO_A)
    LD ($FFFF), A            ; EXPTBL (variable de sistema MSX)
    POP AF
    LD ($8000), A            ; restaura el byte original guardado al principio
    EI
    RET

; --- $E290-$E293: 4 bytes de RAM libre (fuera de cualquier binario del
; proyecto) usados como variable de trabajo COMPARTIDA con
; load_bin_body.asm -- este fichero las escribe (aqui abajo), aquel las
; lee (familias APLICAR_SLOT_ORIGINAL_PAGINA_x/APLICAR_SLOT_PAGINA_x). ---
SLOT_PRIMARIO_A:         EQU $E290
EXPTBL_COMPLEMENTO_A:    EQU $E291
SLOT_PRIMARIO_B:         EQU $E292
EXPTBL_COMPLEMENTO_B:    EQU $E293

GUARDAR_CONFIG_SLOT_A:
    LD HL, SLOT_PRIMARIO_A
    JR GUARDAR_SLOT_COMUN
GUARDAR_CONFIG_SLOT_B:
    LD HL, SLOT_PRIMARIO_B
GUARDAR_SLOT_COMUN:
    IN A, ($A8)               ; lee el slot primario activo (puerto de
                              ; conmutacion MSX)
    LD (HL), A
    INC HL
    LD A, ($FFFF)            ; EXPTBL
    CPL
    LD (HL), A
    RET

DETECTAR_RAM_PAGINA:
    LD A, $80                 ; byte de configuracion empaquetado para
                              ; ENASLT (formato ROM: slot primario en bits
                              ; 0-1, indicador de subslot en bit 2); $80
                              ; arranca con el bit superior puesto
    LD C, 4                   ; 4 combinaciones de slot secundario
.BUCLE_SLOT_SECUNDARIO:
    AND $83                   ; conserva el bit superior + los 2 bits de
                              ; slot primario, limpia el resto antes de
                              ; empezar una nueva vuelta del bucle interno
    LD B, 4                   ; 4 combinaciones de slot primario
.BUCLE_SLOT_PRIMARIO:
    PUSH AF
    PUSH BC
    PUSH HL
    DB $CD                    ; CALL -- opcode fijo, operando de abajo automodificado
.OPERANDO_ENASLT_AUTOMODIFICADO:
    DW $0024                  ; ENASLT al principio, copia reubicada en $AFC8
                               ; despues (ver DETECTAR_SLOTS_RAM)
    POP HL
    LD (HL), $20               ; patron de prueba #1 (ver cabecera:
                              ; "escritura complementaria $20/$FA")
    LD A, (HL)
    CP $20                     ; si no se lee lo escrito, no hay RAM real
                              ; en esta combinacion de slot -- siguiente
    JR NZ, .SIGUIENTE_COMBINACION
    LD (HL), $FA               ; patron de prueba #2
    LD A, (HL)
    CP $FA                     ; los dos patrones cuadran -> RAM confirmada
    JR Z, .RAM_ENCONTRADA
.SIGUIENTE_COMBINACION:
    POP BC
    POP AF
    ADD A, $04                 ; avanza el campo de 2 bits del slot
                              ; primario dentro del byte empaquetado (bit 2)
    DJNZ .BUCLE_SLOT_PRIMARIO
    INC A
    DEC C
    JR NZ, .BUCLE_SLOT_SECUNDARIO
    RET
.RAM_ENCONTRADA:
    POP BC
    POP AF
    RET

; --- Plantilla reubicable (ver cabecera): 122 bytes, copiada tal
; cual a $AFC8 en tiempo de ejecucion, nunca ejecutada aqui mismo. ---
ENASLT_EXTENDIDO:
    CALL $AFE8                ; = ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO tras reubicarse en $AFC8
    JP M, $AFD5                ; = ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT tras reubicarse en $AFC8
    IN A, ($A8)                ; caso sin subslot: lee el registro de
                              ; slot primario actual
    AND C                      ; limpia los 2 bits de la pagina afectada
                              ; (mascara calculada por MASCARA_SLOT_PRIMARIO)
    OR B                       ; inserta el nuevo valor de slot en esos bits
    OUT ($A8), A               ; aplica el resultado al puerto de slot primario
    RET
ENASLT_EXTENDIDO_GESTIONAR_SUBSLOT:
    PUSH HL
    CALL $B00C                 ; = ENASLT_EXTENDIDO_MASCARA_SUBSLOT tras reubicarse en $AFC8
    LD C, A
    LD B, 0                   ; BC = extension a 16 bits de C (indice en tabla)
    LD A, L
    AND H
    OR D
    LD HL, $FCC5                ; variable de sistema MSX (zona de trabajo)
    ADD HL, BC
    LD (HL), A
    POP HL
    LD A, C
    JR ENASLT_EXTENDIDO
; --- Calcula la pareja de mascaras AND(C)/OR(B) para escribir el
; numero de slot primario (2 bits) en la posicion correcta del
; registro de slot, segun la pagina de memoria en H. No verificado
; bit a bit al 100%, pero la estructura (aislar num. de pagina,
; desplazar una mascara base esa cantidad de posiciones, replicar el
; valor via suma modular de $55) es consistente en toda la funcion. ---
ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO:
    PUSH AF
    LD A, H
    RLCA
    RLCA
    AND $03                    ; aisla el numero de pagina (0-3) tras
                              ; rotar los bits 7-6 de H a los bits 1-0
    LD E, A
    LD A, $C0                  ; mascara base (bits 7-6), se ira
                              ; desplazando segun la pagina
.BUCLE_DESPLAZAR_MASCARA:
    RLCA
    RLCA
    DEC E
    JP P, $AFF1                  ; = ENASLT_EXTENDIDO_MASCARA_SLOT_PRIMARIO.BUCLE_DESPLAZAR_MASCARA tras reubicarse en $AFC8
    LD E, A
    CPL
    LD C, A                     ; mascara AND final (excluye la pagina objetivo)
    POP AF
    PUSH AF
    AND $03                     ; numero de slot primario a insertar (0-3)
    INC A
    LD B, A
    LD A, $AB                   ; semilla para replicar el valor de slot en
                              ; la posicion correcta via suma modular
.BUCLE_REPLICAR_MASCARA:
    ADD A, $55                  ; paso de replicacion ($55 = 01010101)
    DJNZ .BUCLE_REPLICAR_MASCARA
    LD D, A
    AND E
    LD B, A                     ; mascara OR final (valor de slot ya posicionado)
    POP AF
    AND A
    RET
; --- Analogo a MASCARA_SLOT_PRIMARIO pero para el registro de subslot
; (EXPTBL, via puerto $A8 + $FFFF) -- misma tecnica de replicacion por
; suma modular de $55. Tampoco verificado bit a bit al 100%. ---
ENASLT_EXTENDIDO_MASCARA_SUBSLOT:
    PUSH AF
    LD A, D
    AND $C0                     ; conserva los 2 bits ya calculados por
                              ; MASCARA_SLOT_PRIMARIO (parte alta de D)
    LD C, A
    POP AF
    PUSH AF
    LD D, A
    IN A, ($A8)                 ; lee el slot primario actual
    LD B, A
    AND $3F                     ; limpia los 2 bits superiores (pagina
                              ; objetivo) antes de insertar el subslot
    OR C
    OUT ($A8), A                ; selecciona temporalmente el subslot a
                              ; consultar/modificar
    LD A, D
    RRCA
    RRCA
    AND $03                     ; aisla de nuevo el numero de pagina (0-3)
    LD D, A
.BUCLE_DESPLAZAR_MASCARA:
    LD A, $AB                   ; misma semilla de replicacion que en
                              ; MASCARA_SLOT_PRIMARIO
    ADD A, $55
    DEC D
    JP P, $B024                   ; = ENASLT_EXTENDIDO_MASCARA_SUBSLOT.BUCLE_DESPLAZAR_MASCARA tras reubicarse en $AFC8
    AND E
    LD D, A
    LD A, E
    CPL
    LD H, A
    LD A, ($FFFF)                  ; EXPTBL
    CPL
    LD L, A
    AND H
    OR D
    LD ($FFFF), A               ; mezcla el nuevo valor de subslot en EXPTBL
    LD A, B
    OUT ($A8), A                ; restaura el slot primario original leido arriba
    POP AF
    AND $03                     ; resultado final (0-3) devuelto en A
    RET
    RST $38                     ; relleno tras el RET real, no se ejecuta
    RST $38                     ; (mismo motivo)
    DB $E1                      ; byte suelto tras el final real de la rutina,
                                ; contenido desconocido

END_OF_FILE_TESTBIN:
