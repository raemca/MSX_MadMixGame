; ============================================================
;  LOGOTOPO.CM (version de cinta, Topo Soft 1987/88) - MSX1
;  El logo de Topo Soft que se ve al arrancar la cinta -- 4254 bytes,
;  extraido del bloque "LOGOTO" del .cas de 1988 (sync en offset 312,
;  start=$9470 end=$A50D INCLUSIVE exec=$9470) y desensamblado con
;  Z80Dasm.exe. NOTA: "end" en la cabecera .cas es inclusivo (igual
;  convencion que LOAD.BIN/TEST.BIN) -- el cuerpo real son los 4254
;  bytes $9470-$A50D, sin ningun "byte suelto" fuera de rango (una
;  entrada anterior de esta misma sesion decia 4253+1 suelto, error
;  corregido al segmentar TABLA_FORMAS: el ultimo byte es real,
;  parte del bitmap de FORMA_ESTRELLA_4).
;
;  Invocado desde BASIC: "BLOAD"CAS:LOGOTOPO.CM",R" (TOPO.bas linea
;  20), ANTES de "RUN"CAS:" que cede el control a MADMIX.bas -- es lo
;  primero que se ejecuta al arrancar la cinta, incluso antes que
;  LOAD.BIN/TEST.BIN.
;
;  COMPLETO -- sub-proyecto de RE propio, deliberadamente pospuesto al
;  principio (ver src/load_cas/LOGOTOPO.CM.txt), ya retomado y
;  terminado por completo: el bloque de codigo ($9470-$9693, 549
;  bytes) y las tablas/formas de datos ($9694-$A50D, 3706 bytes:
;  TABLA_PUNTEROS_FORMAS, 3 tablas de animacion, TABLA_DELTA_POSICION,
;  y TABLA_FORMAS con las 15 formas + 1 bloque huerfano) estan
;  transcritos, verificados byte a byte (0 diferencias) y CONFIRMADOS
;  VISUALMENTE por el usuario -- ver DIBUJAR_LOGO_TOPOSOFT y
;  recursos/logotopo_formas.html.
;
;  Todas las rutinas de primer nivel y todas las etiquetas locales de
;  bucle tienen ya nombre real (ninguna `L_XXXX` placeholder pendiente).
;  NO comparte espacio de simbolos con madmix1_body.asm/madmix_scr_body.asm
;  todavia (se ejecuta antes de que esos binarios existan en RAM).
; Ingeniería inversa, herramientas y documentación de este proyecto: Rafael Eduardo Martín Candial
; ============================================================

; --- direcciones VRAM (tabla de color de SCREEN2, $2000-$37FF) que
; se repiten identicas en varias rutinas sin tener etiqueta propia --
; relacion semantica exacta entre las 3 zonas todavia sin confirmar
; del todo (ver comentarios de cada rutina que las usa). ---
VRAM_TABLA_COLOR:      EQU $2000  ; base completa de la tabla de color (LIMPIAR_TABLA_COLOR_VRAM)
VRAM_COLOR_ZONA_TOPO:  EQU $2658  ; zona de color de "Topo" (ANIMAR_COLOR_TOPO)
VRAM_COLOR_ZONA_SOFT:  EQU $2F78  ; zona de color de "Soft" (ANIMAR_PUNTO_LUZ_SOFT/RELLENAR_COLOR_TOPO)

ENTRADA_LOGOTOPO:
    JP DIBUJAR_LOGO_TOPOSOFT                   ; $9470  C3 D1 95

; --- ANIMAR_PUNTO_LUZ_SOFT: CONFIRMADO VISUALMENTE por el usuario --
; el punto de luz que recorre la palabra "Soft" por su linea superior
; tras terminar de rotar, acabando junto a la estrella (coincide en
; posicion exacta en DIBUJAR_LOGO_TOPOSOFT: justo despues de las 3
; llamadas a DIBUJAR_SOFT_ROTANDO y justo antes de
; DIBUJAR_ESTRELLA_ANIMADA). Recorre un rango de direcciones VRAM
; ($2F78->$2FB8) escribiendo con ESCRIBIR_8_BYTES_VRAM (A=$81/$F1 en
; las 2 orientaciones), con HALT como temporizador (3 frames) entre
; posiciones -- crea el efecto de movimiento. ---
ANIMAR_PUNTO_LUZ_SOFT:
    LD HL, VRAM_COLOR_ZONA_SOFT  ; $9473  21 78 2F
    LD DE, $2FB8                ; $9476  11 B8 2F  ; VRAM color, fin del rango (comparado, no escrito)
    LD BC, $00F7                ; $9479  01 F7 00  ; paso VRAM entre las 2 escrituras por posicion
.BUCLE_AVANZAR_PUNTO:
    AND A                       ; $947C  A7
    SBC HL, DE                  ; $947D  ED 52
    RET Z                       ; $947F  C8
    ADD HL, DE                  ; $9480  19
    LD A, $81                   ; $9481  3E 81  ; byte de color VRAM (orientacion 1)
    CALL ESCRIBIR_8_BYTES_VRAM                 ; $9483  CD A6 94
    PUSH HL                     ; $9486  E5
    ADD HL, BC                  ; $9487  09
    LD A, $81                   ; $9488  3E 81  ; byte de color VRAM (orientacion 1)
    CALL ESCRIBIR_8_BYTES_VRAM                 ; $948A  CD A6 94
    POP HL                      ; $948D  E1
    PUSH HL                     ; $948E  E5
    LD A, $F1                   ; $948F  3E F1  ; byte de color VRAM (orientacion 2)
    CALL ESCRIBIR_8_BYTES_VRAM                 ; $9491  CD A6 94
    ADD HL, BC                  ; $9494  09
    LD A, $F1                   ; $9495  3E F1  ; byte de color VRAM (orientacion 2)
    CALL ESCRIBIR_8_BYTES_VRAM                 ; $9497  CD A6 94
    POP HL                      ; $949A  E1
    EI                          ; $949B  FB
    PUSH BC                     ; $949C  C5
    LD B, 3                     ; $949D  06 03  ; 3 frames de pausa por posicion
.BUCLE_ESPERA_3_FRAMES:
    HALT                        ; $949F  76
    DJNZ .BUCLE_ESPERA_3_FRAMES                 ; $94A0  10 FD
    POP BC                      ; $94A2  C1
    DI                          ; $94A3  F3
    JR .BUCLE_AVANZAR_PUNTO                   ; $94A4  18 D6

; --- ESCRIBIR_8_BYTES_VRAM: escribe 8 bytes consecutivos en VRAM (HL) con el valor
; de A, via el hook ROM en $004D -- patron de uso (A=byte, HL=destino
; VRAM antes del CALL) coincide con la convencion estandar de WRTVRM,
; probable identidad aunque no confirmada al 100% contra una tabla de
; hooks de referencia. ---
ESCRIBIR_8_BYTES_VRAM:
    PUSH BC                     ; $94A6  C5
    LD B, 8                     ; $94A7  06 08  ; 8 bytes a escribir
.BUCLE_8_BYTES:
    CALL $004D                  ; $94A9  CD 4D 00  ; probable WRTVRM (hook ROM MSX)
    INC HL                      ; $94AC  23
    DJNZ .BUCLE_8_BYTES                 ; $94AD  10 FA
    POP BC                      ; $94AF  C1
    RET                         ; $94B0  C9

; --- DIBUJAR_FORMA_ANIMADA: motor generico de dibujado de "formas"
; (las letras T/O/P/O de "Topo", los 7 fotogramas de "Soft" rotando,
; los 4 fotogramas de la estrella -- CONFIRMADO VISUALMENTE por el
; usuario). Recibe el indice de forma en $94BD (automodificado por el
; llamador): lo dobla, lo busca en la tabla de punteros $9694 (15
; formas validas, indices 0-14), suma el offset a $9728 para llegar a
; los datos reales. Cabecera de 2 bytes por forma: 1er byte = bytes
; por segmento (automodifica "LD B,n" en $94F0), 2o byte = numero de
; segmentos (automodifica "LD C,n" en $94DC). $94B2 (tambien
; automodificado) indexa una segunda tabla en $96F8 que solo da un
; delta de posicion/fila (no aporta contenido visual). $94F1/$94DD/
; $94B2/$94BD/$94E9 son TODOS operandos automodificados por el
; llamador antes de cada CALL -- $94F3 es directamente el OPCODE de
; "OR (HL)" en .BUCLE_BYTE (interruptor combinar-con-VRAM-si/no, tambien
; automodificado). Ver recursos/logotopo_formas.html para las 15
; formas ya renderizadas. ---
DIBUJAR_FORMA_ANIMADA:
    LD HL, $0000                ; $94B1  21 00 00
    ADD HL, HL                  ; $94B4  29
    LD DE, TABLA_DELTA_POSICION  ; $94B5  11 F8 96
    ADD HL, DE                  ; $94B8  19
    LD ($96F6), HL              ; $94B9  22 F6 96
    LD HL, $0000                ; $94BC  21 00 00
    ADD HL, HL                  ; $94BF  29
    LD DE, TABLA_PUNTEROS_FORMAS ; $94C0  11 94 96
    ADD HL, DE                  ; $94C3  19
    LD E, (HL)                  ; $94C4  5E
    INC HL                      ; $94C5  23
    LD D, (HL)                  ; $94C6  56
    LD HL, TABLA_FORMAS          ; $94C7  21 28 97
    ADD HL, DE                  ; $94CA  19
    LD A, (HL)                  ; $94CB  7E
    LD ($94F1), A               ; $94CC  32 F1 94  ; automodifica el operando de "LD B,n" en $94F0
    INC HL                      ; $94CF  23
    LD A, (HL)                  ; $94D0  7E
    LD ($94DD), A               ; $94D1  32 DD 94  ; automodifica el operando de "LD C,n" en $94DC
    INC HL                      ; $94D4  23
    LD ($96F4), HL              ; $94D5  22 F4 96
    LD IX, ($96F6)              ; $94D8  DD 2A F6 96
    LD C, 10                    ; $94DC  0E 0A  ; placeholder, automodificado con el nº real de segmentos (ver arriba)
.BUCLE_SEGMENTO:
    LD E, (IX+$00)               ; $94DE  DD 5E 00
    INC IX                      ; $94E1  DD 23
    LD D, (IX+$00)               ; $94E3  DD 56 00
    INC IX                      ; $94E6  DD 23
    LD HL, $0000                ; $94E8  21 00 00
    ADD HL, DE                  ; $94EB  19
    LD DE, ($96F4)              ; $94EC  ED 5B F4 96
    LD B, 0                     ; $94F0  06 00  ; placeholder, automodificado con el ancho real del segmento (ver arriba)
.BUCLE_BYTE:
    LD A, (DE)                  ; $94F2  1A
    OR (HL)                     ; $94F3  B6
    INC DE                      ; $94F4  13
    RES 7, H                    ; $94F5  CB BC
    RES 6, H                    ; $94F7  CB B4
    CALL $004D                  ; $94F9  CD 4D 00  ; probable WRTVRM (hook ROM MSX)
    INC HL                      ; $94FC  23
    SET 6, H                    ; $94FD  CB F4
    SET 7, H                    ; $94FF  CB FC
    DJNZ .BUCLE_BYTE                 ; $9501  10 EF
    LD ($96F4), DE              ; $9503  ED 53 F4 96
    DEC C                       ; $9507  0D
    JR NZ, .BUCLE_SEGMENTO               ; $9508  20 D4
    RET                         ; $950A  C9

; --- DIBUJAR_SOFT_ROTANDO/DIBUJAR_T_TOPO/DIBUJAR_P_TOPO_ANIMADA/DIBUJAR_O1_TOPO/DIBUJAR_O2_TOPO_ANIMADA/DIBUJAR_ESTRELLA_ANIMADA: "efectos" de entrada
; del logo -- cada uno prepara parametros ($94BD/$94B2/$94E9/$94F3,
; automodificados por otras partes del codigo) y llama en bucle a
; DIBUJAR_FORMA_ANIMADA/ESCRIBIR_8_BYTES_VRAM, con pausas via HALT/EI/DI en varios de ellos.
; Consumen tablas de datos en $96B2/$96CC/$96E9 (punteros dentro del
; bloque todavia sin analizar). Semantica linea a linea pendiente. ---
DIBUJAR_SOFT_ROTANDO:
    LD A, 15                    ; $950B  3E 0F  ; indice fijo en TABLA_DELTA_POSICION (via $94B2)
    LD ($94B2), A               ; $950D  32 B2 94
    LD A, 120                   ; $9510  3E 78  ; posicion/fila base fija (via $94E9)
    LD ($94E9), A               ; $9512  32 E9 94
    XOR A                       ; $9515  AF
    LD ($94F3), A               ; $9516  32 F3 94
    LD HL, TABLA_ANIMACION_SOFT  ; $9519  21 B2 96
.BUCLE_FOTOGRAMA:
    LD A, (HL)                  ; $951C  7E
    CP $FF                      ; $951D  FE FF  ; sentinela de fin de tabla
    RET Z                       ; $951F  C8
    LD ($94BD), A               ; $9520  32 BD 94
    PUSH HL                     ; $9523  E5
    EI                          ; $9524  FB
    LD B, 2                     ; $9525  06 02  ; 2 frames de pausa por fotograma
.BUCLE_ESPERA_2_FRAMES:
    HALT                        ; $9527  76
    DJNZ .BUCLE_ESPERA_2_FRAMES                 ; $9528  10 FD
    DI                          ; $952A  F3
    CALL DIBUJAR_FORMA_ANIMADA                 ; $952B  CD B1 94
    POP HL                      ; $952E  E1
    INC HL                      ; $952F  23
    JR .BUCLE_FOTOGRAMA                   ; $9530  18 EA
DIBUJAR_T_TOPO:
    LD A, 7                     ; $9532  3E 07  ; indice de forma FORMA_T_TOPO (idx7)
    LD ($94BD), A               ; $9534  32 BD 94
    LD A, 6                     ; $9537  3E 06  ; indice fijo en TABLA_DELTA_POSICION (via $94B2)
    LD ($94B2), A               ; $9539  32 B2 94
    LD A, 0                     ; $953C  3E 00  ; posicion inicial (via $94E9)
.BUCLE_POSICION:
    CP 24                       ; $953E  FE 18  ; posicion final
    RET Z                       ; $9540  C8
    LD ($94E9), A               ; $9541  32 E9 94
    PUSH AF                     ; $9544  F5
    CALL DIBUJAR_FORMA_ANIMADA                 ; $9545  CD B1 94
    POP AF                      ; $9548  F1
    ADD A, 8                    ; $9549  C6 08  ; paso de posicion
    JR .BUCLE_POSICION                   ; $954B  18 F1
DIBUJAR_P_TOPO_ANIMADA:
    LD A, 9                     ; $954D  3E 09  ; indice de forma FORMA_P_TOPO (idx9)
    LD ($94BD), A               ; $954F  32 BD 94
    LD A, 7                     ; $9552  3E 07  ; indice fijo en TABLA_DELTA_POSICION (via $94B2)
    LD ($94B2), A               ; $9554  32 B2 94
    LD A, 144                   ; $9557  3E 90  ; posicion inicial (via $94E9)
.BUCLE_POSICION:
    CP 80                       ; $9559  FE 50  ; posicion final
    RET Z                       ; $955B  C8
    LD ($94E9), A               ; $955C  32 E9 94
    PUSH AF                     ; $955F  F5
    EI                          ; $9560  FB
    HALT                        ; $9561  76  ; 1 frame de pausa por posicion
    DI                          ; $9562  F3
    CALL DIBUJAR_FORMA_ANIMADA                 ; $9563  CD B1 94
    POP AF                      ; $9566  F1
    SUB 8                       ; $9567  D6 08  ; paso de posicion (decreciente)
    JR .BUCLE_POSICION                   ; $9569  18 EE
DIBUJAR_O1_TOPO:
    LD A, $B6                   ; $956B  3E B6  ; opcode real de "OR (HL)" (activa el combinado con VRAM)
    LD ($94F3), A               ; $956D  32 F3 94
    LD A, 8                     ; $9570  3E 08  ; indice de forma FORMA_O1_TOPO (idx8)
    LD ($94BD), A               ; $9572  32 BD 94
    LD A, 56                    ; $9575  3E 38  ; posicion/fila fija (via $94E9)
    LD ($94E9), A               ; $9577  32 E9 94
    LD A, 0                     ; $957A  3E 00  ; indice de segmento inicial (via $94B2)
.BUCLE_SEGMENTO:
    CP 7                        ; $957C  FE 07  ; nº de segmentos
    JR Z, .ULTIMO_SEGMENTO                ; $957E  28 0B
    LD ($94B2), A               ; $9580  32 B2 94
    PUSH AF                     ; $9583  F5
    CALL DIBUJAR_FORMA_ANIMADA                 ; $9584  CD B1 94
    POP AF                      ; $9587  F1
    INC A                       ; $9588  3C
    JR .BUCLE_SEGMENTO                   ; $9589  18 F1
.ULTIMO_SEGMENTO:
    JP DIBUJAR_FORMA_ANIMADA                   ; $958B  C3 B1 94
DIBUJAR_O2_TOPO_ANIMADA:
    LD A, 10                    ; $958E  3E 0A  ; indice de forma FORMA_O2_TOPO (idx10)
    LD ($94BD), A               ; $9590  32 BD 94
    LD HL, TABLA_TRAZO_O2_TOPO   ; $9593  21 CC 96
.BUCLE_TRAZO:
    LD A, (HL)                  ; $9596  7E
    CP $FF                      ; $9597  FE FF  ; sentinela de fin de tabla
    JR Z, .ULTIMO_TRAZO                ; $9599  28 10
    INC HL                      ; $959B  23
    LD ($94E9), A               ; $959C  32 E9 94
    LD A, (HL)                  ; $959F  7E
    INC HL                      ; $95A0  23
    LD ($94B2), A               ; $95A1  32 B2 94
    PUSH HL                     ; $95A4  E5
    CALL DIBUJAR_FORMA_ANIMADA                 ; $95A5  CD B1 94
    POP HL                      ; $95A8  E1
    JR .BUCLE_TRAZO                   ; $95A9  18 EB
.ULTIMO_TRAZO:
    JP DIBUJAR_FORMA_ANIMADA                   ; $95AB  C3 B1 94
DIBUJAR_ESTRELLA_ANIMADA:
    LD HL, TABLA_ANIMACION_ESTRELLA ; $95AE  21 E9 96
.BUCLE_FOTOGRAMA:
    LD A, (HL)                  ; $95B1  7E
    CP $FF                      ; $95B2  FE FF  ; sentinela de fin de tabla
    RET Z                       ; $95B4  C8
    PUSH HL                     ; $95B5  E5
    LD ($94BD), A               ; $95B6  32 BD 94
    LD A, 176                   ; $95B9  3E B0  ; posicion/fila fija (via $94E9)
    LD ($94E9), A               ; $95BB  32 E9 94
    LD A, 13                    ; $95BE  3E 0D  ; indice fijo en TABLA_DELTA_POSICION (via $94B2)
    LD ($94B2), A               ; $95C0  32 B2 94
    EI                          ; $95C3  FB
    LD B, 4                     ; $95C4  06 04  ; 4 frames de pausa por fotograma
.BUCLE_ESPERA_4_FRAMES:
    HALT                        ; $95C6  76
    DJNZ .BUCLE_ESPERA_4_FRAMES                 ; $95C7  10 FD
    DI                          ; $95C9  F3
    CALL DIBUJAR_FORMA_ANIMADA                 ; $95CA  CD B1 94
    POP HL                      ; $95CD  E1
    INC HL                      ; $95CE  23
    JR .BUCLE_FOTOGRAMA                   ; $95CF  18 E0

; --- DIBUJAR_LOGO_TOPOSOFT: SECUENCIA PRINCIPAL -- esto es lo primero
; que se ejecuta de verdad (ENTRADA_LOGOTOPO solo salta hasta aqui).
; CONFIRMADO VISUALMENTE por el usuario, secuencia completa: limpia
; la tabla de color VRAM (LIMPIAR_TABLA_COLOR_VRAM); dibuja las 4
; letras de "TOPO" (DIBUJAR_T_TOPO, DIBUJAR_P_TOPO_ANIMADA,
; DIBUJAR_O1_TOPO, DIBUJAR_O2_TOPO_ANIMADA, intercalando 2 limpiezas
; de la tabla de patrones via LIMPIAR_TABLA_PATRONES_VRAM); colorea
; "TOPO" expandiendose desde el centro (ANIMAR_COLOR_TOPO) y remata
; el color (RELLENAR_COLOR_TOPO); "Soft" rota sobre si misma
; (DIBUJAR_SOFT_ROTANDO, llamada 3 veces); un punto de luz recorre
; "Soft" por su linea superior (ANIMAR_PUNTO_LUZ_SOFT); y termina con
; la estrella parpadeante junto a la T (DIBUJAR_ESTRELLA_ANIMADA). ---
DIBUJAR_LOGO_TOPOSOFT:
    DI                          ; $95D1  F3
    XOR A                       ; $95D2  AF
    LD ($94F3), A               ; $95D3  32 F3 94
    CALL LIMPIAR_TABLA_COLOR_VRAM                 ; $95D6  CD 02 96
    CALL DIBUJAR_T_TOPO                 ; $95D9  CD 32 95
    CALL DIBUJAR_P_TOPO_ANIMADA                 ; $95DC  CD 4D 95
    CALL LIMPIAR_TABLA_PATRONES_VRAM                 ; $95DF  CD 88 96
    CALL DIBUJAR_O1_TOPO                 ; $95E2  CD 6B 95
    CALL LIMPIAR_TABLA_PATRONES_VRAM                 ; $95E5  CD 88 96
    CALL DIBUJAR_O2_TOPO_ANIMADA                 ; $95E8  CD 8E 95
    CALL ANIMAR_COLOR_TOPO                 ; $95EB  CD 2B 96
    CALL RELLENAR_COLOR_TOPO                 ; $95EE  CD 14 96
    CALL DIBUJAR_SOFT_ROTANDO                 ; $95F1  CD 0B 95
    CALL DIBUJAR_SOFT_ROTANDO                 ; $95F4  CD 0B 95
    CALL DIBUJAR_SOFT_ROTANDO                 ; $95F7  CD 0B 95
    CALL ANIMAR_PUNTO_LUZ_SOFT                 ; $95FA  CD 73 94
    CALL DIBUJAR_ESTRELLA_ANIMADA                 ; $95FD  CD AE 95
    EI                          ; $9600  FB
    RET                         ; $9601  C9

; --- LIMPIAR_TABLA_COLOR_VRAM: rellena 0x1800 (6144) bytes en VRAM $2000 con $F0, byte
; a byte via WRTVRM ($004D) -- 6144 bytes coincide EXACTO con el
; tamano de la tabla de color de SCREEN2 (32x8x24). Hipotesis de alta
; confianza: borra/prepara la tabla de color antes de dibujar. ---
LIMPIAR_TABLA_COLOR_VRAM:
    LD HL, VRAM_TABLA_COLOR      ; $9602  21 00 20
    LD BC, 6144                 ; $9605  01 00 18  ; bytes (tamano completo de la tabla de color)
.BUCLE_RELLENO:
    LD A, $F0                   ; $9608  3E F0  ; byte de color VRAM (relleno)
    CALL $004D                  ; $960A  CD 4D 00  ; probable WRTVRM (hook ROM MSX)
    INC HL                      ; $960D  23
    DEC BC                      ; $960E  0B
    LD A, B                     ; $960F  78
    OR C                        ; $9610  B1
    JR NZ, .BUCLE_RELLENO               ; $9611  20 F5
    RET                         ; $9613  C9

; --- RELLENAR_COLOR_TOPO: escribe un patron ($81) en
; VRAM_COLOR_ZONA_SOFT en bloques de 2 filas x 64 bytes, avanzando de
; $C0 en $C0 -- candidato a rematar/consolidar el color de "TOPO"
; justo despues de la animacion de ANIMAR_COLOR_TOPO (coincide en
; posicion exacta en DIBUJAR_LOGO_TOPOSOFT, llamada justo despues).
; Comparte direccion base con ANIMAR_PUNTO_LUZ_SOFT pese al nombre
; "ZONA_SOFT" (el mismo punto VRAM sirve, aparentemente, a dos
; efectos distintos) -- relacion semantica exacta sin confirmar. ---
RELLENAR_COLOR_TOPO:
    LD HL, VRAM_COLOR_ZONA_SOFT  ; $9614  21 78 2F
    LD A, $81                   ; $9617  3E 81  ; byte de color VRAM (relleno)
    LD C, 2                     ; $9619  0E 02  ; 2 bloques/filas
.BUCLE_FILA:
    LD B, 64                    ; $961B  06 40  ; 64 bytes por bloque/fila
.BUCLE_BYTE:
    CALL $004D                  ; $961D  CD 4D 00  ; probable WRTVRM (hook ROM MSX)
    INC HL                      ; $9620  23
    DJNZ .BUCLE_BYTE                 ; $9621  10 FA
    LD DE, $00C0                ; $9623  11 C0 00  ; salto VRAM al siguiente bloque
    ADD HL, DE                  ; $9626  19
    DEC C                       ; $9627  0D
    JR NZ, .BUCLE_FILA               ; $9628  20 F1
    RET                         ; $962A  C9

; --- ANIMAR_COLOR_TOPO: CONFIRMADO VISUALMENTE por el usuario -- la
; animacion de color de "TOPO" expandiendose desde el centro hacia
; los lados, justo despues de dibujar las 4 letras (coincide en
; posicion exacta en DIBUJAR_LOGO_TOPOSOFT). Estructura: dos "cajas"
; de lineas ($71 x5 filas, $31 x6 filas, via ESCRIBIR_8_BYTES_VRAM_C) que arrancan en
; $2658 (dentro de la tabla de color VRAM), con un desplazamiento que
; se repite 16 veces (paso 16) hasta que E llega a 152, con pausa de
; HALT (4 frames) entre cada repeticion -- la animacion de expansion.
; Detalle linea a linea todavia pendiente. ---
ANIMAR_COLOR_TOPO:
    LD DE, 8                    ; $962B  11 08 00  ; paso VRAM entre las 2 cajas
    LD HL, VRAM_COLOR_ZONA_TOPO  ; $962E  21 58 26  ; punto de arranque (centro)
.BUCLE_EXPANSION:
    PUSH HL                     ; $9631  E5
    LD B, 5                     ; $9632  06 05  ; 5 lineas
    PUSH DE                     ; $9634  D5
.BUCLE_CAJA_1A:
    LD A, $71                   ; $9635  3E 71  ; byte de color VRAM
    CALL ESCRIBIR_8_BYTES_VRAM_C                 ; $9637  CD 7E 96
    LD DE, $00F8                ; $963A  11 F8 00  ; salto VRAM a la siguiente linea
    ADD HL, DE                  ; $963D  19
    DJNZ .BUCLE_CAJA_1A                 ; $963E  10 F5
    LD B, 6                     ; $9640  06 06  ; 6 lineas
.BUCLE_CAJA_1B:
    LD A, $31                   ; $9642  3E 31  ; byte de color VRAM
    CALL ESCRIBIR_8_BYTES_VRAM_C                 ; $9644  CD 7E 96
    ADD HL, DE                  ; $9647  19
    DJNZ .BUCLE_CAJA_1B                 ; $9648  10 F8
    POP DE                      ; $964A  D1
    POP HL                      ; $964B  E1
    PUSH HL                     ; $964C  E5
    ADD HL, DE                  ; $964D  19
    PUSH DE                     ; $964E  D5
    LD B, 5                     ; $964F  06 05  ; 5 lineas (segunda caja)
.BUCLE_CAJA_2A:
    LD A, $71                   ; $9651  3E 71  ; byte de color VRAM
    CALL ESCRIBIR_8_BYTES_VRAM_C                 ; $9653  CD 7E 96
    LD DE, $00F8                ; $9656  11 F8 00  ; salto VRAM a la siguiente linea
    ADD HL, DE                  ; $9659  19
    DJNZ .BUCLE_CAJA_2A                 ; $965A  10 F5
    LD B, 6                     ; $965C  06 06  ; 6 lineas (segunda caja)
.BUCLE_CAJA_2B:
    LD A, $31                   ; $965E  3E 31  ; byte de color VRAM
    CALL ESCRIBIR_8_BYTES_VRAM_C                 ; $9660  CD 7E 96
    ADD HL, DE                  ; $9663  19
    DJNZ .BUCLE_CAJA_2B                 ; $9664  10 F8
    POP DE                      ; $9666  D1
    POP HL                      ; $9667  E1
    LD A, E                     ; $9668  7B
    CP 152                      ; $9669  FE 98  ; posicion final de la expansion
    RET Z                       ; $966B  C8
    EI                          ; $966C  FB
    LD B, 4                     ; $966D  06 04  ; 4 frames de pausa por paso de expansion
.BUCLE_ESPERA_4_FRAMES:
    HALT                        ; $966F  76
    DJNZ .BUCLE_ESPERA_4_FRAMES                 ; $9670  10 FD
    DI                          ; $9672  F3
    ADD A, 16                   ; $9673  C6 10  ; paso de posicion
    LD E, A                     ; $9675  5F
    PUSH DE                     ; $9676  D5
    LD DE, $FFF8                ; $9677  11 F8 FF  ; = -8, ajuste VRAM con signo
    ADD HL, DE                  ; $967A  19
    POP DE                      ; $967B  D1
    JR .BUCLE_EXPANSION                   ; $967C  18 B3

; --- ESCRIBIR_8_BYTES_VRAM_C: escribe 8 bytes consecutivos en VRAM (HL) con A --
; identico en estructura a ESCRIBIR_8_BYTES_VRAM (mismo patron WRTVRM x8), pero como
; rutina separada (C en vez de B como contador). ---
ESCRIBIR_8_BYTES_VRAM_C:
    LD C, 8                     ; $967E  0E 08  ; 8 bytes a escribir
.BUCLE_8_BYTES:
    CALL $004D                  ; $9680  CD 4D 00  ; probable WRTVRM (hook ROM MSX)
    INC HL                      ; $9683  23
    DEC C                       ; $9684  0D
    JR NZ, .BUCLE_8_BYTES               ; $9685  20 F9
    RET                         ; $9687  C9

; --- LIMPIAR_TABLA_PATRONES_VRAM: HL=$0000, DE=$C000, BC=$1800 (6144), salta a un hook
; ROM en $0059 -- candidato a FILVRM/LDIRVM/LDIRMV segun la tabla
; estandar de hooks BIOS, identidad exacta SIN CONFIRMAR (los 3
; registros cargados no bastan por si solos para distinguir cual es
; sin verificar contra una referencia). Mismo tamano (0x1800=6144)
; que LIMPIAR_TABLA_COLOR_VRAM, refuerza que este bloque tambien toca la tabla de color
; completa de SCREEN2. ---
LIMPIAR_TABLA_PATRONES_VRAM:
    LD HL, $0000                ; $9688  21 00 00  ; VRAM, base de la tabla de patrones (pagina 0)
    LD DE, $C000                ; $968B  11 00 C0  ; sin usar por FILVRM, ver cabecera
    LD BC, 6144                 ; $968E  01 00 18  ; bytes (tamano completo de la tabla de patrones)
    JP $0059                    ; $9691  C3 59 00  ; hook ROM MSX, identidad exacta sin confirmar

; --- TABLA_PUNTEROS_FORMAS: 15 palabras, offset (desde TABLA_FORMAS)
; de cada una de las 15 "formas" animadas del logo. Indexada por
; $94BD (doblado) desde DIBUJAR_FORMA_ANIMADA. CONFIRMADO VISUALMENTE
; por el usuario: idx0-6 = "Soft" rotando (7 fotogramas), idx7-10 =
; letras T-O-P-O, idx11-14 = estrella (4 fotogramas). Escritas como
; diferencia de etiquetas (no hex literal) para que sigan siendo
; correctas si el tamano de alguna forma cambia. Ver
; recursos/logotopo_formas.html (renderizador, mismo orden idx). ---
TABLA_PUNTEROS_FORMAS:
    DW FORMA_SOFT_1-TABLA_FORMAS, FORMA_SOFT_2-TABLA_FORMAS
    DW FORMA_SOFT_3-TABLA_FORMAS, FORMA_SOFT_4-TABLA_FORMAS
    DW FORMA_SOFT_5-TABLA_FORMAS, FORMA_SOFT_6-TABLA_FORMAS
    DW FORMA_SOFT_7-TABLA_FORMAS
    DW FORMA_T_TOPO-TABLA_FORMAS, FORMA_O1_TOPO-TABLA_FORMAS
    DW FORMA_P_TOPO-TABLA_FORMAS, FORMA_O2_TOPO-TABLA_FORMAS
    DW FORMA_ESTRELLA_1-TABLA_FORMAS, FORMA_ESTRELLA_2-TABLA_FORMAS
    DW FORMA_ESTRELLA_3-TABLA_FORMAS, FORMA_ESTRELLA_4-TABLA_FORMAS

; --- TABLA_ANIMACION_SOFT: 24 indices de forma (0-6) en patron de
; pulso simetrico (crece y decrece), terminador $FF. Consumida por
; DIBUJAR_SOFT_ROTANDO (con HALT entre cada paso) -- la animacion
; real de "Soft" rotando sobre si misma, CONFIRMADA VISUALMENTE. ---
TABLA_ANIMACION_SOFT:
    DB 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6
    DB 5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 0, 0
    DB $FF

    ; byte suelto sin explicar (posible relleno/alineacion, mismo
    ; valor $FF que el terminador de arriba)
    DB $FF

; --- TABLA_TRAZO_O2_TOPO: 14 pares (posicion/fila, indice en
; TABLA_DELTA_POSICION) que usa DIBUJAR_O2_TOPO_ANIMADA para revelar
; la 2a O de "Topo" trazo a trazo -- posicion creciente 48->112 con
; "grosor" en patron de pulso (6..1..6), terminador $FF en el byte de
; posicion. CONFIRMADO VISUALMENTE (revelado animado de la O). ---
TABLA_TRAZO_O2_TOPO:
    DB 48, 6,   48, 5,   48, 4,   56, 4,   56, 3,   64, 2,   72, 2
    DB 80, 1,   88, 2,   96, 2,   104, 3,  112, 4,  112, 5,  112, 6
    DB $FF

; --- TABLA_ANIMACION_ESTRELLA: 8 indices de forma (11-14) en patron
; de pulso, terminador $FF. Consumida por DIBUJAR_ESTRELLA_ANIMADA
; (con HALT entre cada paso) -- la estrella parpadeante junto a la T,
; CONFIRMADA VISUALMENTE. ---
TABLA_ANIMACION_ESTRELLA:
    DB 11, 12, 13, 12, 11, 12, 13, 14
    DB $FF

; --- VARIABLES_TRABAJO_FORMA: 6 bytes a cero en reposo. Incluye los
; 2 punteros de trabajo que DIBUJAR_FORMA_ANIMADA usa como RAM en
; tiempo de ejecucion: ($96F4)=puntero a los datos de la forma en
; curso, ($96F6)=puntero a la entrada de TABLA_DELTA_POSICION --
; reutilizan este hueco de la zona de datos estatica como scratch
; (mismo patron de variable "prestada" ya visto en otras partes de
; este proyecto). ---
VARIABLES_TRABAJO_FORMA:
    DB 0, 0, 0, 0, 0, 0

; --- TABLA_DELTA_POSICION: 24 palabras secuenciales $C000..$D700
; (byte alto = $C0+n, byte bajo siempre $00 -- NO son $00C0.."$00D7"),
; indexadas (x2) por $94B2 desde DIBUJAR_FORMA_ANIMADA. El byte alto
; se suma a H y se enmascara despues con RES 7,H/RES 6,H antes de
; usarse como direccion VRAM real -- el efecto neto (una vez
; enmascarados los bits 7-6) es un delta secuencial 0..23, con los
; bits altos ($C0=%11xxxxxx) probablemente un tag de "direccion VRAM"
; (mismo patron que el DE=$C000 de LIMPIAR_TABLA_PATRONES_VRAM). No
; aporta contenido visual, solo el delta de posicion/fila que se suma
; a la base ($94E9) de cada segmento dibujado. ---
TABLA_DELTA_POSICION:
    DW $C000, $C100, $C200, $C300, $C400, $C500, $C600, $C700
    DW $C800, $C900, $CA00, $CB00, $CC00, $CD00, $CE00, $CF00
    DW $D000, $D100, $D200, $D300, $D400, $D500, $D600, $D700

; --- TABLA_FORMAS: los datos reales de las 15 "formas" animadas,
; cada una con cabecera de 2 bytes (ancho en bytes por segmento,
; numero de segmentos) seguida del bitmap (1 bit/pixel, MSB=izquierda,
; formato nativo de la tabla de patrones VDP) -- ver
; DIBUJAR_FORMA_ANIMADA y recursos/logotopo_formas.html (renderizador
; visual, identificacion CONFIRMADA por el usuario). El orden fisico
; en el fichero NO es 0..14 secuencial: hay un bloque de 40 bytes de
; datos graficos HUERFANOS (mismo patron de sombreado $AA/$55 que las
; formas reales, pero SIN ninguna entrada de TABLA_PUNTEROS_FORMAS
; que los referencie -- mismo tipo de hallazgo que los 6 guiones de
; demo sin usar de madmix1_body.asm) entre FORMA_O1_TOPO y
; FORMA_P_TOPO. ---
TABLA_FORMAS:
FORMA_SOFT_1:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_1.bin"
FORMA_SOFT_2:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_2.bin"
FORMA_SOFT_3:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_3.bin"
FORMA_SOFT_4:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_4.bin"
FORMA_SOFT_5:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_5.bin"
FORMA_SOFT_6:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_6.bin"
FORMA_SOFT_7:
    DB 64, 2
    INCBIN "data/logotopo/formas/forma_soft_7.bin"
FORMA_T_TOPO:
    DB 72, 11
    INCBIN "data/logotopo/formas/forma_t_topo.bin"
FORMA_O1_TOPO:
    DB 40, 7
    INCBIN "data/logotopo/formas/forma_o1_topo.bin"

; --- bloque huerfano (40 bytes, ver cabecera de TABLA_FORMAS) ---
DATOS_HUERFANOS_9EEA:
    INCBIN "data/logotopo/formas/huerfano_9eea.bin"

FORMA_P_TOPO:
    DB 48, 10
    INCBIN "data/logotopo/formas/forma_p_topo.bin"
FORMA_O2_TOPO:
    DB 56, 10
    INCBIN "data/logotopo/formas/forma_o2_topo.bin"
FORMA_ESTRELLA_1:
    DB 24, 5
    INCBIN "data/logotopo/formas/forma_estrella_1.bin"
FORMA_ESTRELLA_2:
    DB 24, 5
    INCBIN "data/logotopo/formas/forma_estrella_2.bin"
FORMA_ESTRELLA_3:
    DB 24, 5
    INCBIN "data/logotopo/formas/forma_estrella_3.bin"
FORMA_ESTRELLA_4:
    DB 24, 5
    INCBIN "data/logotopo/formas/forma_estrella_4.bin"

END_OF_FILE_LOGOTOPO:
