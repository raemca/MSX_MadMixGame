; Reconstrucción, comentarios y etiquetas de este fichero: Rafael Eduardo Martín Candial


; --- Punto de entrada real (CALL $1000 desde RELOCATOR en
; madmix0.asm): dibuja la portada. Apaga pantalla, escribe la tabla
; de nombres identidad (768 bytes, nombre=indice de patron), vuelca
; el bitmap sin comprimir (PORTADA_PATRON, 6144 bytes) a la tabla de
; patrones VRAM, reconstruye el color desde el formato comprimido a
; nibble (ver BUCLE_DESCOMPRIMIR_COLOR_PORTADA mas abajo) y enciende pantalla. ---
DIBUJAR_PORTADA:
    DI
    CALL APAGAR_PANTALLA_VDP         ; $10BC
    LD HL, $1800                ; tabla de nombres (VRAM)
    LD A, L
    OUT ($99), A                 ; byte bajo de la direccion VRAM
    LD A, H
    AND $3F                      ; descarta los 2 bits altos (direccion VRAM de 14 bits)
    OR $40                       ; comando "fijar puntero de escritura" del VDP
    OUT ($99), A                 ; byte alto + comando
    EX (SP), HL                 ; x2 = retardo VDP tras fijar direccion
    EX (SP), HL
    LD BC, $0000                 ; C = byte de nombre a escribir (0, 1, 2...), B = contador de paginas de 256
.BUCLE_TABLA_IDENTIDAD:
    LD A, C
    OUT ($98), A                 ; nombre = C (nombre = indice de patron, el truco "identidad")
    INC BC
    LD A, B
    CP 3                         ; 3 paginas de 256 = 768 bytes: tabla de nombres IDENTIDAD
    JR NZ, .BUCLE_TABLA_IDENTIDAD        ; 768 bytes: tabla de nombres IDENTIDAD
                                 ; (nombre = indice de patron), truco ya
                                 ; conocido del motor principal
    LD HL, PORTADA_PATRON        ; origen: bitmap sin comprimir de la portada
    LD DE, $0000                 ; VRAM $0000 = tabla de patrones (destino)
    LD BC, 6144                  ; 6144 bytes = tamano completo de la tabla de patrones de SCREEN2
    EX DE, HL                    ; HL = destino VRAM, DE = origen (para fijar la direccion VRAM primero)
    LD A, L
    OUT ($99), A
    LD A, H
    AND $3F
    OR $40
    OUT ($99), A
    EX (SP), HL
    EX (SP), HL
    EX DE, HL                    ; HL = origen (PORTADA_PATRON), listo para volcar
.BUCLE_VOLCAR_PATRON_PORTADA:
    LD A, (HL)
    OUT ($98), A
    INC HL
    DEC BC
    LD A, B
    OR C
    JR NZ, .BUCLE_VOLCAR_PATRON_PORTADA          ; 6144 bytes: bitmap completo de la portada
    LD A, 1                      ; 1 = color de borde/fondo (indice de paleta, ver PALETA_COLORES_PORTADA)
    LD B, A
    LD C, 7                      ; 7 = numero de registro del VDP (R7 = color de borde/texto)
    LD A, B
    OUT ($99), A                 ; escribe el valor de color al puerto de datos del VDP
    LD A, C
    OR $80                       ; bit7 = comando "escribir registro" del VDP
    OUT ($99), A                  ; registro 7 del VDP (borde/fondo) = 1

; --- descompresion de la tabla de color (768 grupos de 8 lineas) ---
    LD BC, 768                    ; 768 grupos de color a descomprimir (bucle externo)
    LD DE, $2000                  ; VRAM $2000 = tabla de color
    LD HL, PORTADA_COLOR
BUCLE_DESCOMPRIMIR_COLOR_PORTADA:
    PUSH BC                       ; guarda el contador de grupos restantes
    LD A, (HL)
    AND A
    JR Z, ESCRIBIR_COLUMNA_COLOR          ; byte de control 0 = color 0/0 directo
    PUSH HL                       ; guarda el puntero de origen
    PUSH BC                       ; duplica el contador (se libera con el POP BC de mas abajo)
    LD B, A
    AND $07                       ; aisla los 3 bits bajos -> indice1 (nibble bajo de color)
    LD C, A
    LD A, B
    AND $78                       ; aisla 4 bits centrales
    RRCA
    RRCA
    RRCA                          ; los rota a bits 0-3
    LD L, A
    AND $08                       ; bit3 del byte de control, se combina en el indice2
    OR C
    LD C, A
    LD A, L
    LD HL, PALETA_COLORES_PORTADA
    ADD A, L
    LD L, A
    LD B, (HL)                     ; tabla16[indice1] -> nibble bajo
    LD HL, PALETA_COLORES_PORTADA
    LD A, C
    ADD A, L
    LD L, A
    LD A, (HL)                     ; tabla16[indice2] -> nibble alto
    RRCA
    RRCA
    RRCA
    RRCA
    OR B
    POP BC
    POP HL
ESCRIBIR_COLUMNA_COLOR:
    LD BC, 8                      ; 8 lineas por columna de caracter (repeticiones de relleno)
    INC HL                        ; salta el byte de control ya leido
    EX DE, HL                     ; HL = destino VRAM, DE = origen (para fijar direccion VRAM)
    PUSH BC
    PUSH AF
    LD A, L
    OUT ($99), A
    LD A, H
    AND $3F
    OR $40
    OUT ($99), A
    EX (SP), HL
    EX (SP), HL
    POP AF
    INC B
.BUCLE_RELLENAR_COLOR:
    OUT ($98), A
    DEC C
    JP NZ, .BUCLE_RELLENAR_COLOR             ; repite el mismo color 8 veces (una
                                    ; columna de 8 lineas de un caracter)
    DEC B
    JP NZ, .BUCLE_RELLENAR_COLOR
    POP BC                         ; recupera el 8 (bytes escritos) para avanzar el destino
    ADD HL, BC                     ; HL (destino VRAM) += 8, avanza a la siguiente columna
    EX DE, HL                      ; HL = origen actualizado, DE = destino
    POP BC                         ; recupera el contador de grupos restantes (guardado al entrar al bucle)
    DEC BC
    LD A, B
    OR C
    JR NZ, BUCLE_DESCOMPRIMIR_COLOR_PORTADA
    CALL ENCENDER_PANTALLA_VDP         ; $10C7 (via $10A8)
    RET

; --- tabla de 16 valores para la descompresion de color ---
PALETA_COLORES_PORTADA:
    INCBIN "data/img/portada_paleta.img"   ; 16 bytes = exacto 0x10AC-0x10BC

; --- Apaga la pantalla: lee el estado del VDP (limpia el flag de
; interrupcion pendiente) y escribe $A2 en el registro 1 (modo: 16K,
; bit6=BLANK a 0 -> pantalla apagada, IE activo, sprites grandes).
; Se llama al empezar a dibujar la portada, para evitar ver el
; proceso de escritura en VRAM. ---
APAGAR_PANTALLA_VDP:
    IN A, ($99)
    LD A, $A2
    OUT ($99), A
    LD A, $81
    OUT ($99), A
    RET

; --- Espera al siguiente VBLANK (bit 7 del estado del VDP) y
; enciende la pantalla: escribe $E2 en el registro 1 (igual que
; $A2 de arriba pero con bit6=1 -> pantalla encendida). ---
ENCENDER_PANTALLA_VDP:
    IN A, ($99)
    AND A
    JP P, ENCENDER_PANTALLA_VDP
    IN A, ($99)
    LD A, $E2
    OUT ($99), A
    LD A, $81
    OUT ($99), A
    RET

; --- RESUELTO: estas son las direcciones $10D8/$10DE llamadas desde
; GESTIONAR_INTRODUCCION.CONTINUAR_INTRO/APLICAR_COLOR_CICLO_NIVELES/APLICAR_COLOR_PANTALLA (ver
; FINDINGS.md/FLUJO_PROGRAMA.md, antes marcadas "sin identificar").
; PROGRAMAR_APAGADO_PANTALLA/PROGRAMAR_ENCENDIDO_PANTALLA son dos mini-rutinas que precargan,
; en el byte de $10E4 (DATO, no codigo -- ver nota de RESOLUCION mas
; abajo), el valor de registro 1 que se usara la PROXIMA vez que se
; escriba -- PROGRAMAR_APAGADO_PANTALLA ($10D8) lo deja listo para "pantalla
; apagada" ($A2, igual que APAGAR_PANTALLA_VDP), PROGRAMAR_ENCENDIDO_PANTALLA ($10DE)
; para "pantalla encendida" ($E2, igual que ENCENDER_PANTALLA_VDP).
; Patron clasico: apagar pantalla antes de redibujar un menu/pantalla
; para evitar parpadeo, encenderla al terminar.
;
; RESUELTO (analisis estatico puro, sin openMSX -- las 2 hipotesis de
; opcode probadas antes eran la pregunta equivocada: $10E4 no es
; codigo, es un DATO): ENTRADA_INTERRUPCION_VBLANK (madmix1_body.asm, `ENTRADA_INTERRUPCION_VBLANK`/$882A) hace
; `IN A,($99) / LD A,($10E4) / OUT ($99),A / LD A,$81 / OUT ($99),A`
; justo antes de salir -- es decir, en CADA VBLANK vuelve a escribir
; el byte de $10E4 en el registro 1 del VDP. Asi que PROGRAMAR_APAGADO_PANTALLA/
; PROGRAMAR_ENCENDIDO_PANTALLA no disparan el cambio de pantalla directamente: solo
; dejan preparado el valor que ENTRADA_INTERRUPCION_VBLANK aplicara de verdad en la
; siguiente interrupcion, frame a frame, hasta que se parchee lo
; contrario. Los 8 bytes siguientes ($10E5-$10EC) NO son continuacion
; de esas rutinas -- son simplemente lo que ocupa ese hueco de memoria
; en el bloque reubicado (cola sin desensamblar, no relevante para
; este mecanismo).
PROGRAMAR_APAGADO_PANTALLA:              ; antes PATCH_OFF_10D8 ($10D8)
    LD A, $A2
    LD (VDP_REGISTRO1_PENDIENTE), A
    RET
PROGRAMAR_ENCENDIDO_PANTALLA:                ; antes PATCH_ON_10DE ($10DE)
    LD A, $E2
    LD (VDP_REGISTRO1_PENDIENTE), A
    RET
VDP_REGISTRO1_PENDIENTE:
    DB $E2                     ; $10E4: valor de registro 1 del VDP que ENTRADA_INTERRUPCION_VBLANK relee y reescribe cada VBLANK (ver ENTRADA_INTERRUPCION_VBLANK, madmix1_body.asm) -- confirmado, ver FINDINGS.md

; --- HIPOTESIS FUERTE, sin lector confirmado (analisis estatico no
; encuentra ningun bucle que la lea, ni en madmix_scr_body.asm ni en
; madmix1_body.asm/cargadores): tabla de los 8 registros R0-R7 del VDP
; para inicializar SCREEN 2. Se descarto la lectura como "codigo
; muerto" (decodificaba en LD (BC),A/JP PO,$8006/NOP/LD (HL),$07 + 1
; byte incompleto, pero el salto caia en $8006, zona vacia antes de
; que empiece MADMIX1.BIN en $83F9 -- sin sentido como destino real).
; A favor de la lectura como tabla: R1/R2/R3/R4 coinciden EXACTOS con
; la disposicion de VRAM que fija a mano DIBUJAR_PORTADA mas arriba
; (nombres en $1800, patrones en $0000, color en $2000) -- demasiada
; coincidencia para ser azar. Probablemente la pantalla ya llega
; configurada asi via el "SCREEN 2" de MSX-BASIC (ejecutado por
; AUTOEXEC.BAS/MADMIX.BAS antes del BLOAD) y esta tabla es una copia
; sin usar por el propio juego (resto de una version que la aplicaba
; con un bucle generico, luego sustituido por los OUT manuales que se
; ven arriba). ---
TABLA_REGISTROS_SCREEN2_VDP:
    DB $02                     ; R0: modo grafico 2
    DB $E2                     ; R1: pantalla encendida, sprites grandes (16x16 x2)
    DB $06                     ; R2: tabla de nombres en $1800 ($1800/$400=6) -- coincide con DIBUJAR_PORTADA
    DB $80                     ; R3: tabla de color en $2000 (bit7=bloque alto) -- coincide con BUCLE_DESCOMPRIMIR_COLOR_PORTADA
    DB $00                     ; R4: tabla de patrones en $0000 -- coincide con el volcado del bitmap
    DB $36                     ; R5: tabla de atributos de sprite en $1B00 (sin sprites en esta pantalla, sin contraste posible)
    DB $07                     ; R6: tabla de patrones de sprite en $3800 (idem, sin contraste posible)
    DB $11                     ; R7: color de borde/texto

PORTADA_PATRON:
    INCBIN "data/img/portada_patron.img"    ; 6144 bytes = exacto 0x10ED-0x28ED

    DS $28F0-$, $00                       ; $28ED-$28F0: 3 bytes sin explicar

PORTADA_COLOR:
    INCBIN "data/img/portada_color.img" ; 768 bytes = exacto 0x28F0-0x2BF0

; --- 0x2BF0-0x2BF2 (3 bytes): CODIGO MUERTO confirmado -- POP HL /
; EI / RET, sin NINGUN JP/JR/CALL en todo el codigo fuente reconstruido
; que apunte aqui (busqueda exhaustiva, ver FINDINGS.md). Mismo patron
; exacto que en 0xDD93 de madmix1_body.asm (tambien muerto, mismo
; hallazgo). Verificado desensamblando el limite junto con la cola del
; INCBIN anterior (portada_color.img): esa cola desensambla como ruido
; incoherente (LD B,(HL) / LD B,L repetidos sin ningun sentido --
; tipico de datos de imagen, no de codigo real), mientras que estos 3
; bytes SI forman una secuencia coherente -- confirma que
; el fragmento de codigo empieza exactamente aqui, no antes. ---
    POP    HL
    EI
    RET

; --- REGISTRO DE NIVEL, copia de trabajo (0x2BF3-0x2C06, 20 bytes) ---
; Cada nivel copia aqui su registro de 20 bytes de TABLA_NIVELES via
; LDIR (LD DE,$2BF3) al cargar -- los valores de mas abajo son solo
; el "de fabrica" horneado en la ROM (instantanea del ultimo nivel
; procesado en tiempo de compilacion, sin significado propio: la
; partida real siempre los sobreescribe). Los 20 campos estan
; descifrados con codigo real, ver FINDINGS.md "Descifrados offsets
; 8/11/18/19 del registro de nivel" para el detalle campo a campo.
REGISTRO_NIVEL:
REGISTRO_NIVEL_CUERPO_PTR:
    DW $0000                  ; offset 0-1: puntero al CUERPO del nivel
REGISTRO_NIVEL_CABECERA_PTR:
    DW $0000                  ; offset 2-3: puntero a la CABECERA fija
REGISTRO_NIVEL_PIE_PTR:
    DW $0000                  ; offset 4-5: duplicado del anterior (se reusa para copiar la cabecera tambien debajo del cuerpo)
REGISTRO_NIVEL_FILAS:
    DB 18                     ; offset 6: numero de filas del cuerpo (variable por nivel)
REGISTRO_NIVEL_VIDA_EXTRA_FLAG:
    DB 1                      ; offset 7: flag de aviso HUD (copiado a FLAG_VIDA_EXTRA)
REGISTRO_NIVEL_CONTADOR_PELMAZOIDES:
    DB 2                      ; offset 8: cuenta de entradas de TABLA_ITEMS_PELMAZOIDE (tipo 3, fantasmas -- ver sprites SPR27-32, FINDINGS.md)
REGISTRO_NIVEL_CONTADOR_MARICOCOS:
    DB 1                      ; offset 9: cuenta de entradas de HNDLR_MARICOCO (tipo 1)
REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS:
    DB 1                      ; offset 10: cuenta de entradas de HNDLR_REGPUNANTOSO (tipo 2)
REGISTRO_NIVEL_DURACION_PARPADEO:
    DB 200                    ; offset 11: duracion (fotogramas) del parpadeo de la bola/pista especial
REGISTRO_NIVEL_LOSETA_COMODIN:
    DB $C0                    ; offset 12: loseta real que sustituye al comodin $3C en el cuerpo
REGISTRO_NIVEL_FILA_COLUMNA:
    DW $1010                  ; offset 13-14: fila/columna de un punto de referencia inicial (formula MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA), copiado a POSICION_PARPADEO_BOLA
REGISTRO_NIVEL_POSICION_INICIAL:
REGISTRO_NIVEL_POSICION_COMECOCOS:
    DW $0001                  ; offset 15-16 del registro / posicion viva del comecocos-camara durante toda la partida ($2C02, usada por decenas de sitios via MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA)
REGISTRO_NIVEL_ICONO_HUD:
    DB $38                    ; offset 17: codigo de caracter/icono de HUD, copiado a TABLA_POSICIONES_HUD+17
REGISTRO_NIVEL_OBJETIVO_BOLAS:
    DW 0                      ; offset 18-19: objetivo de "bolitas a comer" para completar el nivel (comparado contra CONTADOR_BOLAS_COMIDAS en VERIFICAR_FIN_NIVEL, madmix1_body.asm)

; --- VARIABLES DE ESTADO DE PARTIDA (0x2C07-0x2C37) ---
; Confirmadas con codigo real cruzando madmix_scr_body.asm Y
; madmix1_body.asm (varias solo se referencian desde el segundo --
; primera pasada de esta ronda las marco por error como "huecos sin
; identificar", corregido). Los pocos huecos que quedan estan
; verificados de verdad: cero por defecto y CERO referencias en
; ninguno de los dos ficheros.
NIVEL_ACTUAL:
    DB 0                       ; $2C07: numero de nivel actual (1-indexado)
CONTADOR_BOLAS_COMIDAS:
    DW 0                       ; $2C08-09: contador de "cosas comidas" este nivel (objetivo: REGISTRO_NIVEL_OBJETIVO_BOLAS)
POSICION_PARPADEO_BOLA:
    DW $0000                   ; $2C0A-0B: posicion usada por la animacion de parpadeo de la bola (ver 0x9111)
TEMPORIZADOR_PARPADEO_BOLA:
    DB 0                       ; $2C0C: temporizador de parpadeo (reiniciado por INICIALIZAR_ITEMS_NIVEL/ARMAR_AVISO_DESTELLO)
MODO_ESPECIAL_FLAG:
    DB 0                       ; $2C0D: flag de modo especial temporal activo
MODO_ESPECIAL_CUENTA_ATRAS:
    DB 0                       ; $2C0E: contador regresivo de duracion del modo especial (parpadeo)
MODO_ESPECIAL_ACTIVO:
    DB 0                       ; $2C0F: bandera != 0 = hay un modo especial activo
DIRECCION_DE_MOVIMIENTO:
    DB $00                     ; $2C10: direccion elegida este frame (o el anterior), ver MOTOR_MOVIMIENTO_COLISION
SELECTOR_SPRITE_COMECOCOS:
    DB $00                     ; $2C11: ultimo valor real leido de la subtabla de direccion (centinela $FE = "hereda anterior"); candidato a selector de comportamiento/animacion por direccion, detalle fino sin confirmar
CACHE_TIPO_LOSETA:
    DB 0                       ; $2C12: cache del ultimo tipo de loseta consultado por CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION
CACHE_COLUMNA_LOSETA:
    DB $00                     ; $2C13: cache de la ultima columna consultada (evita repetir CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION)
INDICE_SUBTABLA_DIRECCION:
    DB 0                       ; $2C14: indice rotativo (0-3) de la subtabla de direccion, avanza 1 cada llamada
DIRECCION_SIN_PROCESAR:
    DB $00                     ; $2C15: direccion "cruda" de este frame (antes de aplicar la mascara de alineamiento), guardada por MOTOR_MOVIMIENTO_COLISION
POSICION_ACTUAL_CAMARA:
    DW $1018                   ; $2C16-17: posicion de camara actual (columna,fila) -- GESTIONAR_SCROLL la lee, los modos tanque/avion la fijan a un valor concreto ($1018/$1C18) mientras duran
COLOR_GUARDADO:
    DB $78                     ; $2C18: color/atributo HUD guardado antes de activar un modo especial
FLAG_NIVEL_RECIEN_CARGADO:
    DB 0                       ; $2C19: flag de estado del juego (leido/escrito junto con REGISTRO_NIVEL_ICONO_HUD/COLOR_ACTUAL, ver madmix1_body.asm)
DIRECCION_FORZADA:
    DB $00                     ; $2C1A: direccion "forzada" (activada por las losetas de flecha, CONSULTAR_LOSETA_LIBRE_DIRECCION y come-cola de trampillas), 0 = sin forzar
TEMPORIZADOR_DIRECCION_FORZADA:
    DB 0                       ; $2C1B: cuenta atras de cuantos frames mas dura la direccion forzada
FLAG_DIRECCION_NUEVA:
    DB 0                       ; $2C1C: flag "hay input de direccion nuevo tras soltar" (armado/desarmado en MOTOR_MOVIMIENTO_COLISION)
COPIA_FLAG_DIRECCION_NUEVA:
    DB 0                       ; $2C1D: copia del flag anterior, candidato a "flanco de pulsacion" (se consulta mas abajo en el motor)
LADO_APERTURA_TRAMPILLA:
    DB 0                       ; $2C1E: lado por el que se abrio la trampilla en curso, 1=izquierda/2=derecha (fijado por HNDLR_TRAMPILLA_ABIERTA_DERECHA/HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA)
PUNTO_REFERENCIA_CAMARA:
    DW $0000                   ; $2C1F-20: "punto de mira" (camara+8,+16), usado por MOTOR_MOVIMIENTO_ITEM/HNDLR_PELMAZOIDE
    DS 1, $00                  ; $2C21: sin identificar (verificado: cero referencias en ambos ficheros)
SEMILLA_ALEATORIA:
    DW $0000                   ; $2C22-23: semilla del generador pseudoaleatorio de GENERAR_ALEATORIO ($5478)
COLOR_ACTUAL:
    DB $78                     ; $2C24: color/atributo HUD activo (restaurado desde COLOR_GUARDADO al salir de un modo especial)
PARAMETRO_DESPLAZAMIENTO_SCROLL:
    DW $0000                   ; $2C25-26: parametro de SCROLL_IZQUIERDA/SCROLL_DERECHA (madmix1_body.asm) -- significado preciso sin confirmar, valores vistos $0400/$FC00
VIDAS_RESTANTES:
    DB 3                       ; $2C27: vidas restantes (INICIO lo pone a 3)
    DS 1, $00                  ; $2C28: sin identificar (verificado: cero referencias en ambos ficheros)
PUNTUACION:
    DW 0                       ; $2C29-2A: puntuacion acumulada de la partida (si llega a 10000/$2710 muestra BESTIA_TEXT, ver madmix1_body.asm)
FLAG_VIDA_EXTRA:
    DB 0                       ; $2C2B: flag pendiente de un solo uso (copiado desde REGISTRO_NIVEL_VIDA_EXTRA_FLAG)
CONTADOR_VUELTAS_NIVELES:
    DB 0                       ; $2C2C: vale 0 en la primera vuelta completa del juego (contador de vueltas al ciclo de niveles)
MODO_ESPECIAL:
    DB 0                       ; $2C2D: modo especial actual (0=ninguno, 1=bola de poder, 2=hipopotamo, 3=herramienta, 8=tanque, 9=avion)
TABLA_PISTA_TANQUE_AVION:
    DS 6, $00                  ; $2C2E-33: 3 entradas de 2 bytes (posiciones activas de pista de tanque/avion, ver AVISAR_PROXIMIDAD_PISTA/REGISTRAR_PISTA_TANQUE_AVION)
    DS 2, $00                  ; $2C34-35: sin identificar (verificado: cero referencias en ambos ficheros)

; --- 0x2C36-0x2C37 (2 bytes): "gancho" llamado directamente desde 2
; sitios ya identificados como "CALL a RAM" (ver FINDINGS.md, "$2C36
; -- llamada a RAM, no codigo estatico"). NUEVO en esta ronda: el
; contenido por defecto SI es codigo real y coherente, no ruido --
; decodifica exactamente como "JR MOTOR_MOVIMIENTO_COLISION" (bytes $18,$68), el
; salto relativo aterriza exacto en 0x2CA0. Probable "trampolin"
; autopatchable, sobreescrito en tiempo de ejecucion por un mecanismo
; aun sin identificar. ---
ENLACE_MOTOR_MOVIMIENTO_COLISION:
    JR MOTOR_MOVIMIENTO_COLISION

; --- Tablas del motor de colision (0x2C38-0x2CA0) ---
; RESUELTO: clasifica la posicion sub-loseta (nibble bajo de la
; direccion VRAM, 0-15) en 5 "clases de alineamiento" (0-4). El valor
; (en C) se combina en BUCLE_SUBTABLA_DIRECCION con el indice rotativo
; INDICE_SUBTABLA_DIRECCION (C*4 + indice) para seleccionar una entrada de la
; subtabla de 20 bytes (5 filas x 4 columnas) de la direccion elegida
; -- pieza confirmada del SELECTOR_SPRITE_COMECOCOS (fotograma de
; animacion del comecocos), ver comentario de OBTENER_SUBTABLA_DIRECCION
; mas abajo y FINDINGS.md para el rastreo completo. ---
TABLA_CLASE_ALINEAMIENTO:
    DB 0, 1, 2, 1, 3, 1, 2, 3    ; 0x2C38: tabla de 16 bytes, indexada por nibble bajo de direccion
    DB 4, 1, 2, 1, 3, 1, 2, 1
PUNTEROS_SUBTABLA_DIRECCION:
    DW SUBTABLA_DIRECCION_A, SUBTABLA_DIRECCION_B, SUBTABLA_DIRECCION_C, SUBTABLA_DIRECCION_D   ; 0x2C48: 4 punteros a las sub-tablas de abajo
SUBTABLA_DIRECCION_A:
    DB $FE, $FE, $FE, $FE, $00, $01, $02, $01, $80, $81, $82, $81, $03, $04, $05, $04, $06, $06, $06, $06
SUBTABLA_DIRECCION_B:
    DB $FE, $FE, $FE, $FE, $07, $08, $09, $08, $87, $88, $89, $88, $0A, $39, $0B, $39, $06, $06, $06, $06
SUBTABLA_DIRECCION_C:
    DB $FE, $FE, $FE, $FE, $10, $11, $12, $11, $90, $91, $92, $91, $13, $18, $14, $18, $15, $19, $16, $19
SUBTABLA_DIRECCION_D:
    DB $FE, $FE, $FE, $FE, $0D, $0D, $0D, $0D, $8D, $8D, $8D, $8D, $0E, $0E, $0E, $0E, $0F, $0F, $0F, $0F

; ==============================================================
;  MOTOR DE COLISION/MOVIMIENTO (0x2CA0-0x335C) -- el "bucle
;  principal" del juego. Despachador de 16 entradas segun el tipo
;  de loseta hacia la que se mueve el comecocos (tabla de punteros
;  en 0x2E3C), con un manejador dedicado por tipo: flechas (fuerzan
;  direccion), varios tipos de pared/pasillo (marcan loseta
;  "comida", activan HUD, llaman a los 2 manejadores de item
;  especial de 0x5478-0x5904 y a MOTOR_ACTORES), pista de tanque/avion
;  (itera la tabla de posiciones activas en $2C2E) y un manejador de "tipo
;  9" que hace un bucle de 12 llamadas a MOTOR_ACTORES (candidato a
;  "bola de poder comida -> todos los fantasmas vulnerables a la
;  vez"). Las etiquetas internas (antes ML_XXXX = direccion real en
;  hex) se renombraron a nombres descriptivos -- ver FINDINGS.md para
;  el mapeo completo nombre nuevo -> direccion original, util para
;  cruzar con el desensamblado.
; ==============================================================
; --- Decide la direccion a usar este frame (B) y la deja en ($2C10)
; para el resto del motor: si el ciclador de niveles de muestra esta
; activo ((INDICE_CICLO_NIVELES)!=0, ver GESTIONAR_CICLO_NIVELES) usa la direccion ya
; precalculada en D (guion de demo); si no, lee input real
; (LEER_ENTRADA, $8E3C). ---
MOTOR_MOVIMIENTO_COLISION:
    LD A, (DIRECCION_DE_MOVIMIENTO)          ; direccion del frame anterior (se restaura mas
    PUSH AF                  ; abajo con POP BC si el chequeo de loseta falla)
    LD A, (INDICE_CICLO_NIVELES)
    AND A
    JR Z, SALTAR_A_LEER_ENTRADA            ; modo normal -> lee input de verdad
    LD A, D                    ; modo demo/ciclador -> usa la direccion del guion
    JR PROCESAR_DIRECCION
SALTAR_A_LEER_ENTRADA:
    CALL LEER_ENTRADA               ; JT_LEER_ENTRADA (colision) = LEER_ENTRADA: A = bitmask de direccion
PROCESAR_DIRECCION:
    LD (DIRECCION_SIN_PROCESAR), A             ; guarda la direccion "cruda" de este frame
    LD B, A                    ; B = direccion cruda (fallback si la nueva no es valida)
    AND $10                     ; bit 4: candidato a "hay input de direccion" (0=no)
    LD HL, FLAG_DIRECCION_NUEVA
    LD C, 0
    JR Z, LIMPIAR_FLAG_DIRECCION              ; sin input nuevo -> C=0 (fuerza mantener direccion previa mas abajo)
    LD A, (HL)
    AND A
    JR NZ, COPIAR_FLAG_DIRECCION              ; ($2C1C) ya estaba a 1 -> lo deja igual, solo actualiza ($2C1D)
    LD C, 1
    LD (HL), C                   ; primera vez que se detecta input tras soltar -> arma el flag ($2C1C)=1
    JR COPIAR_FLAG_DIRECCION
LIMPIAR_FLAG_DIRECCION:
    LD (HL), 0                  ; sin input -> desarma el flag ($2C1C)
COPIAR_FLAG_DIRECCION:
    INC HL
    LD (HL), C                     ; ($2C1D) = copia del flag de arriba (candidato: "flanco de pulsacion",
                                     ; usado mas abajo para decidir si se acepta la nueva direccion)
    LD A, B
    LD BC, (POSICION_ACTUAL_CAMARA)                    ; posicion de camara actual
    CALL MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA                          ; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA: HL=direccion VRAM, A=offset dentro de loseta
    POP BC                                ; recupera direccion del frame anterior (guardada al entrar)
    AND $0F
    LD C, A                                ; C = alineamiento sub-loseta actual (0-15)
    LD A, (DIRECCION_FORZADA)                            ; override de "direccion sticky" (activado por CONSULTAR_LOSETA_LIBRE_DIRECCION/
    AND A                                      ; los manejadores de flecha -- fuerza una mascara concreta
    JR Z, CALCULAR_MASCARA_ALINEAMIENTO                               ; en vez de la calculada por alineamiento real)
    LD C, A
CALCULAR_MASCARA_ALINEAMIENTO:
    PUSH DE                                       ; DE = direccion candidata (bitmask) que se esta evaluando
    LD A, E
    LD E, $0F
    AND $03
    JR Z, COMPROBAR_ALINEAMIENTO_Y                                  ; alineado en X (E&3=0) -> mascara completa en ese eje
    LD E, $03                                        ; no alineado en X -> solo se permite seguir en X
COMPROBAR_ALINEAMIENTO_Y:
    LD A, D
    AND $03
    JR Z, APLICAR_MASCARA_ALINEAMIENTO                                     ; alineado en Y -> nada que restringir por Y
    LD E, $0C                                           ; no alineado en Y -> solo se permite seguir en Y
                                                          ; (si tampoco estaba alineado en X, esta linea
                                                          ; pisa la mascara de arriba: da prioridad al eje Y)
APLICAR_MASCARA_ALINEAMIENTO:
    LD A, C
    AND E                                                 ; aplica la mascara de alineamiento a la direccion candidata
    JR NZ, FIJAR_DIRECCION_FINAL                                          ; sigue siendo valida -> se queda con ella
    LD A, B                                                   ; invalida (giro no permitido aqui) -> vuelve a la
                                                                ; direccion del frame anterior (B)
FIJAR_DIRECCION_FINAL:
    LD C, A
    LD (DIRECCION_DE_MOVIMIENTO), A                                              ; direccion final de este frame, ya decidida
    CALL CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION        ; $2E64 -- consulta el TIPO de loseta un paso mas alla en esa direccion
    JR NZ, CALCULAR_INDICE_TIPO_LOSETA                ; tipo especial (!=0) detectado con la direccion elegida -> sigue
    LD A, B                        ; tipo=0 (sin efecto especial: pasillo/pared normal, ver tabla de
    LD C, A                          ; tipos) -> repite la consulta con la direccion del frame anterior
    LD (DIRECCION_DE_MOVIMIENTO), A                     ; (B) por si esa SI acierta con una loseta especial (el tipo real
    CALL CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION        ; $2E64  de bloqueo/paso libre no se decide aqui, ver nota mas abajo)
CALCULAR_INDICE_TIPO_LOSETA:
    ADD A, A                  ; A = tipo*2 (indice de palabra en TABLA_MANEJADORES_LOSETA)
    PUSH HL                     ; guarda direccion VRAM de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA
    LD L, A
    LD A, (MODO_ESPECIAL_ACTIVO)                ; temporizador de "modo especial" activo (mismo que consulta
    AND A                          ; BUCLE_PRINCIPAL_JUEGO en madmix1.asm) -- si esta a 0, se usa el tipo real
    JR Z, OBTENER_MANEJADOR_LOSETA                   ; calculado arriba; si no, se fuerza tipo 0 (sin efecto) abajo,
    LD L, $00                        ; porque mientras dura un modo especial (bola de poder/hipopotamo/
                                       ; etc.) el dispatch normal de loseta queda suspendido
OBTENER_MANEJADOR_LOSETA:
    LD A, L
    LD HL, TABLA_MANEJADORES_LOSETA     ; $2E3C
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD E, (HL)
    INC HL
    LD D, (HL)
    PUSH DE
    POP IX                    ; IX = manejador real (o HNDLR_SUELO_NORMAL/no-op si el modo especial lo forzo)
    LD A, C
    AND $0F
    LD B, C
    LD HL, TABLA_CLASE_ALINEAMIENTO  ; RESUELTO: clasifica la posicion sub-loseta (nibble bajo de
    ADD A, L                      ; la direccion) en 5 clases (0-4); C alimenta despues
    LD L, A                        ; BUCLE_SUBTABLA_DIRECCION (selector de sprite del comecocos)
    LD C, (HL)
    POP HL                          ; restaura direccion VRAM
    POP DE                           ; restaura bitmask de direccion original
    LD A, (MODO_ESPECIAL_ACTIVO)                     ; vuelve a comprobar el temporizador de modo especial...
    AND A
    LD A, (MODO_ESPECIAL)                       ; ...pero carga en A el ID de modo especial (($2C2D)) para lo
    JR NZ, TICK_MODO_ESPECIAL                       ; que sigue -- si el temporizador esta activo, salta a tratar
    AND A                                  ; el modo especial en si (TICK_MODO_ESPECIAL); si no, despacha derecho
    JP (IX)                                 ; al manejador de tipo de loseta normal
; --- Con un modo especial en curso ($2C0F!=0): decrementa su
; temporizador de duracion ($2C0E) y, distinguiendo modo 1 (bola de
; poder) de modo 2 (hipopotamo) via el ID en E, actualiza el icono de
; HUD correspondiente; al llegar el temporizador a 0 vacia el gestor
; de recursos y apaga los flags de modo (($2C0D)/($2C2D)). Para
; cualquier otro modo (3/8/9...) esto no hace nada y cae directo a
; OBTENER_SUBTABLA_DIRECCION. ---
TICK_MODO_ESPECIAL:
    AND $07
    LD E, A
    CP 1                      ; modo especial 1 = bola de poder
    JR NZ, TICK_MODO_HIPOPOTAMO
    LD HL, MODO_ESPECIAL_CUENTA_ATRAS                ; contador de duracion del modo (decrementado cada frame)
    DEC (HL)
    JR Z, FIN_MODO_BOLA_PODER                 ; llega a 0 justo ahora -> termina el modo
    LD A, (HL)
    CP 60
    JR NC, TICK_MODO_HIPOPOTAMO                  ; todavia queda tiempo de sobra -> nada mas que hacer
    AND $01
    LD A, $30
    JR Z, PARPADEO_COLOR_BOLA_PODER                     ; parpadeo del icono de HUD en los ultimos instantes del modo
    LD A, (COLOR_GUARDADO)
PARPADEO_COLOR_BOLA_PODER:
    LD (COLOR_ACTUAL), A
    JR TICK_MODO_HIPOPOTAMO
FIN_MODO_BOLA_PODER:
    CALL VACIAR_CANALES_SONIDO                ; "vacia" ranuras de recurso (gestor de recursos)
    XOR A
    LD (MODO_ESPECIAL_FLAG), A               ; apaga los flags de modo especial -- vuelve al juego normal
    LD (MODO_ESPECIAL), A
; --- Mismo patron que arriba pero para el modo especial 2
; (hipopotamo): decrementa ($2C0E), y en los ultimos instantes
; alterna el bit 6 del icono de HUD (TABLA_POSICIONES_HUD+17) por XOR en vez de elegir
; entre dos valores fijos -- parpadeo equivalente, implementado
; distinto. Al agotarse el temporizador (FIN_MODO_HIPOPOTAMO), igual que el modo
; 1: vacia flags y sale por OBTENER_SUBTABLA_DIRECCION. ---
TICK_MODO_HIPOPOTAMO:
    CP 2                      ; modo especial 2 = hipopotamo
    JR NZ, OBTENER_SUBTABLA_DIRECCION
    LD HL, MODO_ESPECIAL_CUENTA_ATRAS
    DEC (HL)
    JR Z, FIN_MODO_HIPOPOTAMO
    LD A, (HL)
    CP 60
    JR NC, OBTENER_SUBTABLA_DIRECCION
    AND $01
    LD A, (TABLA_POSICIONES_HUD+17)
    JR NZ, PARPADEO_ICONO_HIPOPOTAMO
    XOR $40
PARPADEO_ICONO_HIPOPOTAMO:
    LD (REGISTRO_NIVEL_ICONO_HUD), A
    LD (COLOR_ACTUAL), A
    JR OBTENER_SUBTABLA_DIRECCION
FIN_MODO_HIPOPOTAMO:
    LD A, (COLOR_GUARDADO)
    LD (COLOR_ACTUAL), A
    XOR A
    LD (MODO_ESPECIAL_FLAG), A
    LD (MODO_ESPECIAL), A
; --- Punto de reunion tras el chequeo de modo especial (o dispatch
; directo si no habia modo activo): E contenia la direccion final
; (bitmask), se usa *2 para indexar la tabla de 4 punteros en $2C48
; (subtabla de 20 bytes por direccion, ver cabecera del motor de
; colision) -- DE queda apuntando a la subtabla de la direccion
; elegida, consumida por el bucle BUCLE_SUBTABLA_DIRECCION de justo debajo (no por el
; de pista de tanque/avion, que es un bloque distinto mas abajo). ---
OBTENER_SUBTABLA_DIRECCION:
    LD A, E
    ADD A, A
    LD HL, PUNTEROS_SUBTABLA_DIRECCION
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD E, (HL)
    INC HL
    LD D, (HL)
; --- Recorre las 4 entradas de 4 bytes de la subtabla de direccion
; (DE) usando un indice rotativo ($2C14, 0-3, avanza 1 cada llamada)
; combinado con C (el valor de TABLA_CLASE_ALINEAMIENTO, $2C38):
; centinela $FF -> prueba la siguiente entrada (bucle); $FE -> hereda
; el ultimo valor real de ($2C11) en vez de uno nuevo; cualquier otro
; valor se adopta directo y se guarda en ($2C11) (la misma variable
; que ajusta PANTALLA_PRESENTACION_NIVEL para el "modo especial 3").
; RESUELTO: sus 7 bits bajos viajan (via PREPARAR_SCROLL, registro B)
; hasta MOTOR_ACTORES, donde se usan como indice en PTR_TABLA_SPRITES
; -- es el SELECTOR DEL FOTOGRAMA DE ANIMACION del comecocos (que fase
; de boca + orientacion dibujar), no un parametro de scroll como se
; penso en un principio: el bit7 es el volteo horizontal (reutiliza
; el sprite de la derecha para la izquierda, igual que en los
; fantasmas). Ver FINDINGS.md para el rastreo completo registro a
; registro. ---
BUCLE_SUBTABLA_DIRECCION:
    LD HL, INDICE_SUBTABLA_DIRECCION
    LD A, (HL)
    INC A
    AND $03
    LD (HL), A
    LD L, A
    LD A, C
    ADD A, A
    ADD A, A
    ADD A, L
    LD L, A
    LD H, $00
    ADD HL, DE
    LD A, (HL)
    CP $FF
    JR Z, BUCLE_SUBTABLA_DIRECCION             ; centinela "vacio" -> reintenta con la siguiente entrada
    CP $FE
    JR NZ, GUARDAR_SELECTOR_SPRITE_COMECOCOS              ; valor real -> se usa tal cual
    LD A, (SELECTOR_SPRITE_COMECOCOS)                 ; centinela "hereda anterior" -> mantiene el valor previo
GUARDAR_SELECTOR_SPRITE_COMECOCOS:
    LD (SELECTOR_SPRITE_COMECOCOS), A
; --- Descompone el valor anterior (bit 7 aparte del resto) y prepara
; los parametros de la tanda de llamadas de abajo: dispara el scroll
; (GESTIONAR_SCROLL), y si toca ((FLAG_ENTRADA_BLOQUEADA)=0, teclado no bloqueado)
; ejecuta los 2 manejadores de item especial + ACTUALIZAR_DESTELLO_ITEMS +
; MOTOR_ACTORES para redibujar. Detalle fino de la descomposicion de
; bits sin confirmar. ---
PREPARAR_SCROLL:
    LD D, A
    AND $7F
    LD H, B
    LD B, A
    LD A, D
    AND $80
    LD D, $38
PREPARAR_LLAMADA_SCROLL:
    LD E, $40
    LD L, A
    LD A, (MODO_ESPECIAL_ACTIVO)              ; modo especial activo -> variante de H para el disparo de scroll
    AND A
    JR Z, DISPARAR_SCROLL_Y_ITEMS
    LD H, $00
DISPARAR_SCROLL_Y_ITEMS:
    LD A, L
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    LD A, H
    CALL GESTIONAR_SCROLL               ; JT_GESTIONAR_SCROLL (disparo de scroll)
    LD A, (FLAG_ENTRADA_BLOQUEADA)
    AND A                     ; (FLAG_ENTRADA_BLOQUEADA)=0 -> teclado no bloqueado (ver BUSCAR_COLUMNA_HUD/INICIALIZAR_ITEMS_NIVEL) -> procesa items
    PUSH AF
    CALL Z, HNDLR_PELMAZOIDE            ; manejador de item especial (instancia 1)
    POP AF
    PUSH AF
    CALL Z, HNDLR_MARICOCO            ; manejador de item especial (instancia 2)
    POP AF
    CALL Z, HNDLR_REGPUNANTOSO            ; HNDLR_REGPUNANTOSO (misma condicion)
    CALL ACTUALIZAR_DESTELLO_ITEMS               ; ACTUALIZAR_DESTELLO_ITEMS (siempre, sin condicion)
    POP BC
    POP DE
    POP HL
    POP AF
    CALL Z, MOTOR_ACTORES            ; MOTOR_ACTORES -- redibuja el comecocos con la nueva posicion/estado
; --- Bucle de pista de tanque/avion: recorre las 3 entradas (6 bytes) de la
; tabla de posiciones activas $2C2E (ver REGISTRAR_PISTA_TANQUE_AVION/
; AVISAR_PROXIMIDAD_PISTA, que la rellenan). Byte 0 de cada entrada = flag
; activo (0 = entrada vacia, sigue con la siguiente); byte 1 codifica
; en el bit 0 cual de dos sub-formatos de posicion usar y en el bit 7
; (rama PISTA_FORMATO_B/PISTA_FORMATO_B_POS) un signo/orientacion adicional -- calcula la
; direccion VRAM final (D/E) y llama a MOTOR_ACTORES para dibujar el
; efecto en esa posicion; si el calculo se sale de rango, borra la
; entrada (queda libre para una futura pista). ---
    LD B, $03
    LD HL, TABLA_PISTA_TANQUE_AVION
BUCLE_PISTA_TANQUE_AVION:
    PUSH BC
    LD A, (HL)
    AND A
    JR Z, SIGUIENTE_PISTA             ; entrada vacia (byte 0 = 0) -> pasa a la siguiente
    INC HL
    LD D, (HL)
    BIT 0, D
    JR Z, PISTA_FORMATO_B              ; formato B (bit0=0) -> rama de abajo
    DEC HL                       ; formato A (bit0=1): resta $10 directo, columna fija $40
    SUB $10
    LD D, A
    LD E, $40
    JR NC, DIBUJAR_PISTA                ; dentro de rango -> sigue a dibujar
    LD (HL), $00                   ; se sale de rango -> libera la entrada (pista ya no valida)
    JR SIGUIENTE_PISTA
PISTA_FORMATO_B:
    BIT 7, (HL)                  ; formato B, sub-caso por el bit 7 (signo/orientacion)
    DEC HL
    JR Z, PISTA_FORMATO_B_POS                  ; bit7=0 -> resta $08 (rama de abajo la usa sumando)
    SUB $08
    LD E, A
    CP $08
    JR NC, PISTA_FILA_FIJA                   ; dentro de rango -> sigue a dibujar
    LD (HL), $00                      ; fuera de rango -> libera la entrada
    JR SIGUIENTE_PISTA
PISTA_FORMATO_B_POS:
    ADD A, $08                    ; bit7=1 -> suma $08 en vez de restar
    LD E, A
    CP $70
    JR C, PISTA_FILA_FIJA                   ; dentro de rango -> sigue a dibujar
    LD (HL), $00                     ; fuera de rango -> libera la entrada
    JR SIGUIENTE_PISTA
PISTA_FILA_FIJA:
    LD E, A
    LD D, $38                    ; fila fija $38 para los dos sub-casos de formato B
DIBUJAR_PISTA:
    LD (HL), A
    LD B, $1A
    XOR A
    CALL MOTOR_ACTORES               ; MOTOR_ACTORES
SIGUIENTE_PISTA:
    INC HL
    INC HL
    POP BC
    DJNZ BUCLE_PISTA_TANQUE_AVION
    RET

; --- tabla de despacho por tipo de loseta (0x2E3C-0x2E64, 20
; punteros -- CORREGIDO: se penso que eran 16 hasta que
; CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION no cuadraba con su direccion real 0x2E64;
; 0x2E64-0x2E3C=40 bytes=20 entradas, no 32/16). Las ultimas 3
; entradas (tipos 17-19) son HNDLR_TRAMPILLA_ABIERTA_DERECHA/HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA/
; HNDLR_TRAMPILLA_CERRADA -- resuelve de paso la duda de "quien llama a
; esos bloques". OJO al leer los nombres: son el nombre de la
; ETIQUETA de destino, no el INDICE/tipo de loseta que la usa (p.ej.
; HNDLR_TRAMPILLA_CERRADA es la entrada de tipo 19, no la "A" de nada) --
; confusion real que ya paso una vez al transcribir esto en su momento
; (cuando las etiquetas eran solo direccion hex), ver FINDINGS.md.
TABLA_MANEJADORES_LOSETA:
    DW HNDLR_SUELO_NORMAL, HNDLR_BOLITA_NORMAL, HNDLR_BOLITA_CLAVADA, HNDLR_AUTOCOCO_ARRIBA
    DW HNDLR_AUTOCOCO_ABAJO, HNDLR_AUTOCOCO_IZQUIERDA, HNDLR_AUTOCOCO_DERECHA, HNDLR_PISTA_COCOTANQUE
    DW HNDLR_SUELO_NORMAL, HNDLR_SUELO_NORMAL, HNDLR_PISTA_COCONAVE, HNDLR_ITEM_SUELO
    DW HNDLR_BOLA_PODER, HNDLR_HIPODOSO, HNDLR_EXCAVATOFONO, HNDLR_SUELO_SIN_BOLA
    DW HNDLR_SUELO_SIN_BOLA, HNDLR_TRAMPILLA_ABIERTA_DERECHA, HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA, HNDLR_TRAMPILLA_CERRADA

; --- CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION (0x2E64) -- aplica un desplazamiento de 1
; loseta en una direccion (rotando A bit a bit sobre BC) y consulta
; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA + CONSULTAR_TIPO_LOSETA en esa posicion. ---
; PENDIENTE: asimetria sin explicar entre pares de direccion opuestos
; -- derecha/abajo suman $04 (un paso de loseta completo, sobrevive
; siempre al AND $7C de MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA), pero
; izquierda/arriba solo restan 1 (puede que NI SIQUIERA cruce un
; limite de loseta, segun la sub-posicion actual). Sin confirmar si
; es un comportamiento deliberado del juego original o un caso sin
; explorar del todo -- pendiente de verificar en vivo (emulador) si
; detectar loseta a la izquierda/arriba se comporta distinto a
; derecha/abajo. Ver FINDINGS.md.
CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION:
    PUSH BC
    LD BC, (POSICION_ACTUAL_CAMARA)            ; BC = posicion de camara actual (columna,fila)
    RRA
    JR NC, COMPROBAR_LOSETA_IZQUIERDA              ; bit0 de la direccion (derecha) no activo -> sigue probando
    LD A, C
    ADD A, $04                    ; derecha: +1 columna (4 = paso de una loseta en esta unidad)
    LD C, A
    JR IDENTIFICAR_PROXIMA_LOSETA
COMPROBAR_LOSETA_IZQUIERDA:
    RRA
    JR NC, COMPROBAR_LOSETA_ABAJO              ; bit1 (izquierda) no activo -> sigue probando
    DEC C                         ; izquierda: -1 columna
    JR IDENTIFICAR_PROXIMA_LOSETA
COMPROBAR_LOSETA_ABAJO:
    RRA
    JR NC, COMPROBAR_LOSETA_ARRIBA              ; bit2 (abajo) no activo -> sigue probando
    LD A, B
    ADD A, $04                    ; abajo: +1 fila
    LD B, A
    JR IDENTIFICAR_PROXIMA_LOSETA
COMPROBAR_LOSETA_ARRIBA:
    RRA
    JR NC, IDENTIFICAR_PROXIMA_LOSETA              ; bit3 (arriba) no activo -> ninguna direccion (BC sin cambios)
    DEC B                         ; arriba: -1 fila
IDENTIFICAR_PROXIMA_LOSETA:
    CALL MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA                ; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA: HL=direccion de la loseta desplazada
    LD A, (CACHE_COLUMNA_LOSETA)              ; cache de la ultima columna consultada (evita repetir
    CP L                          ; CONSULTAR_TIPO_LOSETA para la misma loseta en llamadas seguidas)
    LD A, (CACHE_TIPO_LOSETA)                  ; valor de tipo cacheado
    JR Z, ENMASCARAR_TIPO_LOSETA                    ; misma columna que la ultima vez -> reusa el cache
    LD A, L
    LD (CACHE_COLUMNA_LOSETA), A
    CALL CONSULTAR_TIPO_LOSETA                ; CONSULTAR_TIPO_LOSETA (columna distinta -> consulta real)
    LD (CACHE_TIPO_LOSETA), A
ENMASCARAR_TIPO_LOSETA:
    AND $1F                  ; tipo final enmascarado a 5 bits (0-19, numero de entradas de la tabla)
    POP BC
    RET

; --- DIBUJAR_CAMBIO_LOSETA (0x2E9F) -- escribe A en (HL), ajusta BC
; segun el caso (bordes de franja) y llama a REDIBUJAR_LOSETA_BUFFER_VRAM. ---
DIBUJAR_CAMBIO_LOSETA:
    PUSH BC
    LD B, A
    LD (HL), B
    PUSH BC
    LD A, C
    LD BC, $0406              ; BC = tamano de franja por defecto (4 filas x 6 columnas)
    CP $04
    JR NZ, DIBUJAR_CAMBIO_LOSETA_CHECK_COL              ; caso especial de borde (C original=4): 1 fila menos
    DEC B
DIBUJAR_CAMBIO_LOSETA_CHECK_COL:
    CP $02
    JR NZ, DIBUJAR_CAMBIO_LOSETA_REDRAW              ; caso especial de borde (C original=2): 1 columna menos
    DEC C
DIBUJAR_CAMBIO_LOSETA_REDRAW:
    POP AF
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM                ; REDIBUJAR_LOSETA_BUFFER_VRAM
    POP BC
    RET

; --- manejadores por tipo de loseta (indexados desde TABLA_MANEJADORES_LOSETA,
; nombrados por su direccion real -- ver nota de la tabla arriba).
; El indice de despacho ES el valor de tipo de CONSULTAR_TIPO_LOSETA (sin
; desplazamiento, confirmado en la llamada real de mas arriba:
; "A=tipo; ADD A,A; HL=TABLA_MANEJADORES_LOSETA; ADD A,L..."). Mapeo
; tipo->loseta real confirmado cruzando TABLA_TIPOS_LOSETA (madmix1.asm) con
; el catalogo de data/tiles/*.til:
;   0 = pared/suelo normal (0-44) + variantes decorativas sin
;       manejo propio (67,69,71,72,74-77,80,81,84-90); tambien
;       comparten este manejador los tipos 8 y 9 (ver mas abajo).
;   1 = suelo_con_bola_1/2/3 (bolita normal)      -> HNDLR_BOLITA_NORMAL
;   2 = suelo_con_bola_clavada_1/2/3 (bola fija)  -> HNDLR_BOLITA_CLAVADA
;   3-6 = flecha_arriba/abajo/izquierda/derecha   -> HNDLR_AUTOCOCO_ARRIBA/2F50/2F88/2FC0
;   7 = pista_tanque_vertical                     -> HNDLR_PISTA_COCOTANQUE
;   8,9 = linea_electrica_puerta_fantasmas_a/b    -> HNDLR_SUELO_NORMAL (generico, sin logica propia)
;   10 = pista_avion_recto/remate_izq/remate_der  -> HNDLR_PISTA_COCONAVE
;   11 = item_suelo_sin_confirmar                 -> HNDLR_ITEM_SUELO
;   12 = item_bola_de_poder                       -> HNDLR_BOLA_PODER
;   13 = item_hipopotamo                          -> HNDLR_HIPODOSO
;   14 = item_herramienta                         -> HNDLR_EXCAVATOFONO
;   15,16 = suelo_sin_bola_*/muro_ladrillo_suelto/loseta_solida_negra -> HNDLR_SUELO_SIN_BOLA (ya documentado)
;   17,18,19 = variantes de trampilla_transicion  -> HNDLR_TRAMPILLA_ABIERTA_DERECHA/HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA/HNDLR_TRAMPILLA_CERRADA
; ---
; --- HNDLR_SUELO_NORMAL (tipos 0, 8 y 9 -- pared/suelo normal y las 2
; losetas de "linea electrica" de la puerta de fantasmas, sin lógica
; propia): caso general, sin efecto de juego. Unico caso especial:
; si el parametro de entrada vale $09 salta a la cola compartida
; MODO_ESPECIAL_EXIT_TAIL (fin de modo especial, ver HNDLR_PISTA_COCONAVE mas abajo). ---
HNDLR_SUELO_NORMAL:
    CP 2                  ; A = modo especial actual (($2C2D)) al entrar a cualquier HANDLER_*
    JR NZ, HNDLR_SUELO_NORMAL_CONT             ; (ver "AND A / JP (IX)" en MOTOR_MOVIMIENTO_COLISION) -- aqui, modo==2 anula C
    LD C, $00
HNDLR_SUELO_NORMAL_CONT:
    LD B, $00
    CP 9                 ; modo especial == 9 (avion) -> cae en la cola de "fin de modo especial"
    JP Z, MODO_ESPECIAL_EXIT_TAIL            ; compartida con HNDLR_PISTA_COCONAVE (ver mas abajo)
    JP TICK_MODO_ESPECIAL                ; cualquier otro modo/ninguno -> vuelve al flujo principal sin efecto

; --- HNDLR_BOLITA_NORMAL (tipo 1, suelo_con_bola -- bolita normal): solo
; actua si NO hay modo especial "fuerte" en curso (modo actual < 2,
; es decir ninguno o bola de poder -- modos 2/3/8/9 desactivan por
; completo la recogida de bolitas) y, dentro de eso, si la fase de
; movimiento (D OR E) AND 3 = 2 (evita contar la misma loseta varias
; veces durante el desplazamiento sub-pixel). Cuando se cumple: marca
; evento EVENTO_SONIDO_PENDIENTE=0, sustituye la loseta por su version "comida"
; (($2BFF) OR $80, bit 7 = comida), suma 1 punto (DIBUJAR_MARCADOR_PUNTOS) e
; incrementa el contador de finalizacion de nivel ($2C08, ver
; VERIFICAR_FIN_NIVEL/FINDINGS.md). ---
HNDLR_BOLITA_NORMAL:
    PUSH BC
    PUSH AF
    CP 2                  ; modo especial actual >= 2 (hipopotamo/herramienta/tanque/avion)...
    JR NC, HNDLR_BOLITA_NORMAL_EXIT             ; ...-> no se recogen bolitas mientras dure ese modo
    LD A, D
    OR E
    AND $03
    CP 2                    ; fase de movimiento correcta (evita contar de mas)
    JR NZ, HNDLR_BOLITA_NORMAL_EXIT
    LD A, 15
    LD (CACHE_TIPO_LOSETA), A               ; actualiza a mano la cache de tipo de CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION a 15
                                 ; (suelo_sin_bola), el tipo que le corresponde ahora que se "come"
    NOP
    XOR A
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (HL)
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    OR $80
    CALL DIBUJAR_CAMBIO_LOSETA       ; $2E9F
    PUSH HL
    LD HL, $0001
    CALL DIBUJAR_MARCADOR_PUNTOS                ; JT_DIBUJAR_MARCADOR_PUNTOS
    LD HL, (CONTADOR_BOLAS_COMIDAS)
    INC HL
    LD (CONTADOR_BOLAS_COMIDAS), HL
    POP HL
HNDLR_BOLITA_NORMAL_EXIT:
    POP AF
    POP BC
    JP TICK_MODO_ESPECIAL

; --- HNDLR_BOLITA_CLAVADA (tipo 2, suelo_con_bola_clavada -- bola "fija"):
; SOLO actua si el modo especial actual es exactamente 3 (herramienta/
; obra) -- fuera de ese modo, entrar en esta loseta no hace nada. Con
; modo 3 activo y la fase de movimiento correcta ((D OR E) AND 3 = 2):
; marca evento EVENTO_SONIDO_PENDIENTE=1 y sustituye la loseta por (loseta_actual-3), es
; decir la convierte en la bola_normal equivalente 3 posiciones antes
; en el catalogo (48->45, 49->46, 50->47) -- el modo "herramienta"
; libera la bola fija convirtiendola en una normal; no suma puntos ni
; toca el contador de fin de nivel (eso lo hara luego HNDLR_BOLITA_NORMAL al
; volver a pasar por encima ya convertida). ---
HNDLR_BOLITA_CLAVADA:
    CP $03                  ; modo especial actual == 3 (herramienta)?
    PUSH AF
    JR NZ, HNDLR_BOLITA_CLAVADA_EXIT             ; cualquier otro modo (o ninguno) -> no hace nada
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_BOLITA_CLAVADA_EXIT
    LD A, $01
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (HL)
    SUB $03
    CALL DIBUJAR_CAMBIO_LOSETA      ; $2E9F
HNDLR_BOLITA_CLAVADA_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_AUTOCOCO_ARRIBA/2F50/2F88/2FC0 (tipos 3-6, flechas arriba/abajo/
; izquierda/derecha -- "fuerzan direccion"): igual que la bolita
; normal, solo actuan si el modo especial actual es < 2 (ninguno o
; bola de poder). Con la fase de movimiento correcta, cada una
; comprueba un bit distinto de B (mascara de direcciones ya
; bloqueadas: bit2=up, bit3=down, bit0=left, bit1=right); si esta
; LIBRE, marca evento EVENTO_SONIDO_PENDIENTE=2, sustituye la loseta, fija en $2C1A el
; flag de direccion forzada correspondiente ($08/$04/$02/$01), suma 2
; puntos e incrementa el contador de fin de nivel -- las flechas SI
; cuentan como "bolitas" para completar el nivel, ademas de forzar el
; giro. ---
HNDLR_AUTOCOCO_ARRIBA:
    PUSH AF
    CP $02                  ; modo especial actual >= 2 -> no actua (igual que la bolita normal)
    JR NC, HNDLR_AUTOCOCO_ARRIBA_EXIT
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_AUTOCOCO_ARRIBA_EXIT
    BIT 2, B                    ; bit2 de B = dirección "arriba" ya bloqueada?
    LD A, B
    LD B, $00
    JR NZ, HNDLR_AUTOCOCO_ARRIBA_EXIT                ; bloqueada -> no fuerza nada
    LD B, A
    LD A, $02
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA
    LD A, $08
    LD (DIRECCION_FORZADA), A
    PUSH HL
    LD HL, $0002
    CALL DIBUJAR_MARCADOR_PUNTOS
    LD HL, (CONTADOR_BOLAS_COMIDAS)
    INC HL
    LD (CONTADOR_BOLAS_COMIDAS), HL
    POP HL
HNDLR_AUTOCOCO_ARRIBA_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- (tipo 4, flecha_abajo -- ver comentario de HNDLR_AUTOCOCO_ARRIBA) ---
HNDLR_AUTOCOCO_ABAJO:
    PUSH AF
    CP $02
    JR NC, HNDLR_AUTOCOCO_ABAJO_EXIT
    LD A, D
    OR E
    AND $03
    CP $02
    JR NZ, HNDLR_AUTOCOCO_ABAJO_EXIT
    BIT 3, B                    ; bit3 de B = direccion "abajo" ya bloqueada?
    LD A, B
    LD B, $00
    JR NZ, HNDLR_AUTOCOCO_ABAJO_EXIT
    LD B, A
    LD A, $02
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA
    LD A, $04
    LD (DIRECCION_FORZADA), A
    PUSH HL
    LD HL, $0002
    CALL DIBUJAR_MARCADOR_PUNTOS
    LD HL, (CONTADOR_BOLAS_COMIDAS)
    INC HL
    LD (CONTADOR_BOLAS_COMIDAS), HL
    POP HL
HNDLR_AUTOCOCO_ABAJO_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- (tipo 5, flecha_izquierda -- ver comentario de HNDLR_AUTOCOCO_ARRIBA) ---
HNDLR_AUTOCOCO_IZQUIERDA:
    PUSH AF
    CP $02
    JR NC, HNDLR_AUTOCOCO_IZQUIERDA_EXIT
    LD A, D
    OR E
    AND $03
    CP $02
    JR NZ, HNDLR_AUTOCOCO_IZQUIERDA_EXIT
    LD A, B
    BIT 0, B                    ; bit0 de B = direccion "izquierda" ya bloqueada?
    LD B, $00
    JR NZ, HNDLR_AUTOCOCO_IZQUIERDA_EXIT
    LD B, A
    LD A, $02
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA
    LD A, $02
    LD (DIRECCION_FORZADA), A
    PUSH HL
    LD HL, $0002
    CALL DIBUJAR_MARCADOR_PUNTOS
    LD HL, (CONTADOR_BOLAS_COMIDAS)
    INC HL
    LD (CONTADOR_BOLAS_COMIDAS), HL
    POP HL
HNDLR_AUTOCOCO_IZQUIERDA_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- (tipo 6, flecha_derecha -- ver comentario de HNDLR_AUTOCOCO_ARRIBA) ---
HNDLR_AUTOCOCO_DERECHA:
    PUSH AF
    CP $02
    JR NC, HNDLR_AUTOCOCO_DERECHA_EXIT
    LD A, D
    OR E
    AND $03
    CP $02
    JR NZ, HNDLR_AUTOCOCO_DERECHA_EXIT
    LD A, B
    BIT 1, B                    ; bit1 de B = direccion "derecha" ya bloqueada?
    LD B, $00
    JR NZ, HNDLR_AUTOCOCO_DERECHA_EXIT
    LD B, A
    LD A, $02
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA
    LD A, $01
    LD (DIRECCION_FORZADA), A
    PUSH HL
    LD HL, $0002
    CALL DIBUJAR_MARCADOR_PUNTOS
    LD HL, (CONTADOR_BOLAS_COMIDAS)
    INC HL
    LD (CONTADOR_BOLAS_COMIDAS), HL
    POP HL
HNDLR_AUTOCOCO_DERECHA_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_PISTA_COCOTANQUE (tipo 7, pista_tanque_vertical -- CORREGIDO: el
; comentario antiguo decia "tipo trampilla", pero el cruce con
; TABLA_TIPOS_LOSETA confirma que es la loseta de la pista del tanque, no
; una trampilla real). Al activarse: marca evento EVENTO_SONIDO_PENDIENTE=3, guarda
; ($2C24) en ($2C18) (color/atributo previo), activa modo especial
; $2C2D=8 -- candidato a "modo tanque" (ver SPR23_PM_TANQUE_DER) --
; y de paso reutiliza REGISTRAR_PISTA_TANQUE_AVION (funcion generica de
; alternar una entrada de la tabla $2C2E, compartida con
; HNDLR_PISTA_COCONAVE/avion) para alternar alguna posicion asociada
; a la pista. ---
HNDLR_PISTA_COCOTANQUE:
    PUSH AF
    JR NZ, HNDLR_PISTA_COCOTANQUE_MODE_CHECK            ; ya hay un modo especial activo (Z del "AND A" del dispatcher) ->
                                ; comprueba cual es en vez de intentar activar uno nuevo
    BIT 3, B                    ; sin modo activo: bit3 de B como flag "ya procesado este frame"
    JR Z, HNDLR_PISTA_COCOTANQUE_ACTIVATE                 ; libre -> activa el modo tanque de verdad
    RES 3, B                       ; ya estaba marcado -> solo lo desarma (debounce) y no hace nada mas
    POP AF
    JP TICK_MODO_ESPECIAL
HNDLR_PISTA_COCOTANQUE_MODE_CHECK:
    CP $08                    ; modo especial == 8 (tanque, el que activa este mismo tipo de loseta)?
    JR Z, HNDLR_PISTA_COCOTANQUE_TAIL                ; si -> sigue con la cola comun (flip de pista)
    POP AF                          ; cualquier otro modo -> no interfiere, no hace nada
    JP TICK_MODO_ESPECIAL
HNDLR_PISTA_COCOTANQUE_ACTIVATE:
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (COLOR_ACTUAL)
    LD (COLOR_GUARDADO), A
    LD (TABLA_POSICIONES_HUD+18), A
    LD A, (REGISTRO_NIVEL_ICONO_HUD)
    LD (COLOR_ACTUAL), A
    LD A, 1
    LD (MODO_ESPECIAL_FLAG), A
    LD A, 8
    LD (MODO_ESPECIAL), A
HNDLR_PISTA_COCOTANQUE_TAIL:
    POP AF
    LD A, (DIRECCION_SIN_PROCESAR)             ; direccion cruda de este frame (guardada en MOTOR_MOVIMIENTO_COLISION)
    AND $02
    RRCA
    RRCA
    LD D, A
    LD A, (COPIA_FLAG_DIRECCION_NUEVA)               ; flag de "flanco de pulsacion" (ver MOTOR_MOVIMIENTO_COLISION, COPIAR_FLAG_DIRECCION)
    AND A
    CALL NZ, REGISTRAR_PISTA_TANQUE_AVION  ; $3043 -- solo en el flanco, alterna la tabla de pistas
    LD B, $04
    LD A, D
    OR $17
    JP PREPARAR_SCROLL                ; reentra en el bucle de subtabla por direccion (BUCLE_SUBTABLA_DIRECCION) con
                               ; B/D/A propios en vez de los que traia el dispatch normal

; --- REGISTRAR_PISTA_TANQUE_AVION (0x3043) -- itera la tabla de hasta 3
; posiciones de pista activas ($2C2E) y alterna su estado. ---
REGISTRAR_PISTA_TANQUE_AVION:
    LD B, $03
    LD HL, TABLA_PISTA_TANQUE_AVION
BUSCAR_HUECO_PISTA:
    LD A, (HL)
    AND A
    JR Z, FIJAR_PISTA              ; entrada libre (byte 0 = 0) -> la usa para la nueva pista
    INC HL
    INC HL
    DJNZ BUSCAR_HUECO_PISTA                 ; ocupada -> prueba la siguiente de las 3
    RET                            ; las 3 ocupadas -> no hace nada (tabla llena)
FIJAR_PISTA:
    BIT 0, D                    ; bit0 de D (viene de HNDLR_PISTA_COCOTANQUE/HNDLR_PISTA_COCOTANQUE_TAIL) selecciona el
    LD (HL), $68                  ; valor inicial de posicion segun la variante de pista
    JR NZ, GUARDAR_PISTA
    BIT 7, D
    LD (HL), $40
    JR NZ, GUARDAR_PISTA
    LD (HL), $40
GUARDAR_PISTA:
    INC HL
    LD (HL), D                  ; byte 1 = D (formato de posicion, ver bucle de pista en MOTOR_MOVIMIENTO_COLISION)
    LD A, $04
    LD (EVENTO_SONIDO_PENDIENTE), A
    RET

; --- HNDLR_PISTA_COCONAVE (tipo 10, pista_avion_recto/remate_izq/remate_der
; -- CORREGIDO: un comentario antiguo lo llamaba "tipo 9, bola de
; poder comida"; el cruce real con TABLA_TIPOS_LOSETA/TABLA_MANEJADORES_LOSETA
; confirma que es tipo 10 = la pista del avion, no la bola de poder
; -- ver HNDLR_BOLA_PODER mas abajo para la bola de poder real). Activa
; modo especial $2C2D=9 -- "modo avion" (ver SPR12_PM_AVION_ARRIBA y
; el "Disparo (modo avion)" del catalogo de sonidos) -- guarda
; ($2C24) en ($2C18), y recorre 12 posiciones (bucle de D/E
; incrementales) llamando a GESTIONAR_SCROLL/HNDLR_PELMAZOIDE/HNDLR_MARICOCO/
; HNDLR_REGPUNANTOSO/ACTUALIZAR_DESTELLO_ITEMS y, condicionalmente, MOTOR_ACTORES --
; probable re-sincronizacion del subsistema de items/actores a lo
; largo de toda la pista al entrar en modo avion. Termina cayendo en
; MODO_ESPECIAL_EXIT_TAIL (cola compartida con HNDLR_SUELO_NORMAL). ---
HNDLR_PISTA_COCONAVE:
    JR Z, HNDLR_PISTA_COCONAVE_ACTIVATE             ; sin modo especial activo (Z del dispatcher) -> intenta activarlo
    CP 9                        ; ya habia un modo -> es el propio modo avion (9)?
    JR Z, MODO_ESPECIAL_EXIT_TAIL                 ; si -> cae a la cola comun (fin/paso de modo)
    JP TICK_MODO_ESPECIAL                      ; cualquier otro modo -> no interfiere
HNDLR_PISTA_COCONAVE_ACTIVATE:
    LD A, E
    AND $03                  ; fase de movimiento
    LD A, $00
    JP NZ, TICK_MODO_ESPECIAL              ; fase incorrecta -> no activa nada todavia
    LD A, 9
    LD (MODO_ESPECIAL), A
    LD A, 1
    LD (MODO_ESPECIAL_FLAG), A
    LD A, (COLOR_ACTUAL)
    LD (COLOR_GUARDADO), A
    LD A, (REGISTRO_NIVEL_ICONO_HUD)
    LD (COLOR_ACTUAL), A
    LD BC, $1C18
    LD (POSICION_ACTUAL_CAMARA), BC
    LD B, $0C                ; 12 iteraciones -- recorre toda la pista del avion
    LD D, $38
    LD E, $40
HNDLR_PISTA_COCONAVE_LOOP:
    PUSH BC
    PUSH DE
    LD H, $08
    POP DE
    LD A, D
    ADD A, $04                  ; avanza D (fila/columna a lo largo de la pista) cada vuelta
    LD D, A
    LD B, $05
    XOR A
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    LD A, H
    CALL GESTIONAR_SCROLL               ; JT_GESTIONAR_SCROLL (disparo de scroll) -- mismo patron que DISPARAR_SCROLL_Y_ITEMS en MOTOR_MOVIMIENTO_COLISION
    LD A, (FLAG_ENTRADA_BLOQUEADA)
    AND A
    PUSH AF
    CALL Z, HNDLR_PELMAZOIDE
    POP AF
    PUSH AF
    CALL Z, HNDLR_MARICOCO
    POP AF
    CALL Z, HNDLR_REGPUNANTOSO
    CALL ACTUALIZAR_DESTELLO_ITEMS
    POP BC
    POP DE
    POP HL
    POP AF
    CALL Z, MOTOR_ACTORES            ; MOTOR_ACTORES
    CALL WAIT_VBLANK               ; WAIT_VBLANK -- una espera de frame por posicion (efecto barrido)
    POP BC
    DJNZ HNDLR_PISTA_COCONAVE_LOOP
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A

; --- MODO_ESPECIAL_EXIT_TAIL -- cola compartida (alcanzada por HNDLR_SUELO_NORMAL,
; HNDLR_PISTA_COCONAVE y por caida directa) ---
MODO_ESPECIAL_EXIT_TAIL:
    LD A, B
    AND $02
    RRCA
    RRCA
    LD D, A
    LD A, (COPIA_FLAG_DIRECCION_NUEVA)              ; flag de "flanco de pulsacion" (ver MOTOR_MOVIMIENTO_COLISION)
    AND A
    LD H, B
    JR Z, MODO_ESPECIAL_EXIT_REENTER                ; sin flanco -> no toca la tabla de pistas
    SET 0, D
    PUSH HL
    CALL REGISTRAR_PISTA_TANQUE_AVION   ; $3043 -- en el flanco, alterna una entrada
    POP HL
    RES 0, D
MODO_ESPECIAL_EXIT_REENTER:
    LD A, D
    LD B, $0C
    LD D, $68
    JP PREPARAR_LLAMADA_SCROLL                ; reentra en el bucle de subtabla por direccion (mismo patron
                               ; que HNDLR_PISTA_COCOTANQUE_TAIL en HNDLR_PISTA_COCOTANQUE)

; --- HNDLR_ITEM_SUELO (tipo 11, item_suelo_sin_confirmar): marca evento
; EVENTO_SONIDO_PENDIENTE=3, restaura ($2C24) desde ($2C18) y limpia los flags de modo
; ($2C0D)/($2C2D) -- mismo patron de "salir de modo especial" que
; HNDLR_SUELO_SIN_BOLA (tipos 15/16), y luego sustituye la loseta por
; (loseta_actual+$3B). Nombre del item sin confirmar del todo en el
; catalogo visual (ver graficos.html). ---
HNDLR_ITEM_SUELO:
    PUSH AF
    JR Z, HNDLR_ITEM_SUELO_EXIT            ; SIN modo especial activo -> no hace nada (esta loseta solo
                               ; actua para SALIR de un modo ya en curso, al reves que los
                               ; manejadores de activacion de mas abajo)
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_ITEM_SUELO_EXIT
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (COLOR_GUARDADO)
    LD (COLOR_ACTUAL), A
    XOR A
    LD (MODO_ESPECIAL_FLAG), A
    LD (MODO_ESPECIAL), A
    POP AF
    PUSH AF
    ADD A, $3B
    CALL DIBUJAR_CAMBIO_LOSETA      ; $2E9F
HNDLR_ITEM_SUELO_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_BOLA_PODER (tipo 12, item_bola_de_poder -- LA bola de poder
; real): marca evento EVENTO_SONIDO_PENDIENTE=3, activa el temporizador de modo
; especial ($2C0E desde ($2BFE), $2C0D=1), guarda ($2C24) en
; ($2C18), fija color $2C24=$30, activa modo especial $2C2D=1
; ("modo bola de poder" -- el que deberia volver vulnerables a los
; fantasmas), sustituye la loseta, suma 2 puntos e incrementa el
; contador de fin de nivel; termina marcando evento EVENTO_SONIDO_PENDIENTE=$0B (11,
; sobreescribe el EVENTO_SONIDO_PENDIENTE=3 de antes -- posible pista de que hay DOS
; sonidos distintos en la misma jugada: uno de "activar" y otro
; final). ---
HNDLR_BOLA_PODER:
    PUSH AF
    JR NZ, HNDLR_BOLA_PODER_EXIT            ; ya hay OTRO modo especial activo -> no interfiere
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_BOLA_PODER_EXIT
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, 1
    LD (MODO_ESPECIAL_FLAG), A
    LD A, (REGISTRO_NIVEL_DURACION_PARPADEO)
    LD (MODO_ESPECIAL_CUENTA_ATRAS), A
    LD A, (COLOR_ACTUAL)
    LD (COLOR_GUARDADO), A
    LD A, $30
    LD (COLOR_ACTUAL), A
    LD A, 1
    LD (MODO_ESPECIAL), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA      ; $2E9F
    PUSH HL
    LD HL, $0002
    CALL DIBUJAR_MARCADOR_PUNTOS
    LD A, $0B
    LD (EVENTO_SONIDO_PENDIENTE), A
    POP HL
HNDLR_BOLA_PODER_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_HIPODOSO (tipo 13, item_hipopotamo): mismo patron que
; HNDLR_BOLA_PODER (temporizador $2C0E, guarda color previo en $2C18,
; usa ($2C04) como nuevo color) pero activa modo especial $2C2D=2
; ("modo hipopotamo" -- el jugador pisa bolitas sin comerlas, ver
; catalogo de sonidos "Ruido de pisar bola"). Marca evento EVENTO_SONIDO_PENDIENTE=3 y
; sustituye la loseta; a diferencia de la bola de poder, NO suma
; puntos ni tiene un segundo marcador de evento al final. ---
HNDLR_HIPODOSO:
    PUSH AF
    JR NZ, HNDLR_HIPODOSO_EXIT            ; ya hay OTRO modo especial activo -> no interfiere
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_HIPODOSO_EXIT
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (REGISTRO_NIVEL_DURACION_PARPADEO)
    LD (MODO_ESPECIAL_CUENTA_ATRAS), A
    LD A, (COLOR_ACTUAL)
    LD (COLOR_GUARDADO), A
    LD A, (REGISTRO_NIVEL_ICONO_HUD)
    LD (COLOR_ACTUAL), A
    LD A, 2
    LD (MODO_ESPECIAL), A
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)
    CALL DIBUJAR_CAMBIO_LOSETA
HNDLR_HIPODOSO_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_EXCAVATOFONO (tipo 14, item_herramienta): mismo patron otra
; vez, guarda ($2C24) en ($2C18), fija color fijo $2C24=$68 (no
; ($2C04) como el hipopotamo), activa modo especial $2C2D=3 ("modo
; herramienta" -- candidato al "modo obra/saca-bolas" del catalogo
; de sonidos), marca evento EVENTO_SONIDO_PENDIENTE=3 y sustituye la loseta por
; (loseta_actual+$3B, mismo desplazamiento que HNDLR_ITEM_SUELO). ---
HNDLR_EXCAVATOFONO:
    PUSH AF
    JR NZ, HNDLR_EXCAVATOFONO_EXIT            ; ya hay OTRO modo especial activo -> no interfiere
    LD A, D
    OR E
    AND $03
    CP $02                    ; fase de movimiento correcta
    JR NZ, HNDLR_EXCAVATOFONO_EXIT
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (COLOR_ACTUAL)
    LD (COLOR_GUARDADO), A
    LD A, $68
    LD (COLOR_ACTUAL), A
    LD A, 3
    LD (MODO_ESPECIAL), A
    LD A, $3B
    CALL DIBUJAR_CAMBIO_LOSETA
HNDLR_EXCAVATOFONO_EXIT:
    POP AF
    JP TICK_MODO_ESPECIAL

; --- HNDLR_SUELO_SIN_BOLA -- termina en TEMPORIZADOR_DIRECCION_FORZADA_TICK, cola comun de limpieza
; de estado de "bucle" antes de volver al despacho principal.
; Entrada de TABLA_MANEJADORES_LOSETA para tipos de loseta 15 y 16 (ver
; TABLA_TIPOS_LOSETA en madmix1.asm): tipo 15 = suelo_sin_bola_1/2/3 (tiles
; 63/64/65) + muro_ladrillo_suelto (tile 70); tipo 16 =
; loseta_solida_negra (tile 66). La rama CP $08 resetea un modo
; especial temporal: restaura ($2C24) desde ($2C18), limpia los
; flags de modo ($2C2D)/($2C0D) y marca EVENTO_SONIDO_PENDIENTE=$03 (mismo "marcador de
; evento" que REGISTRAR_PISTA_TANQUE_AVION pone a $04 y AVISAR_PROXIMIDAD_PISTA a
; $07 -- candidato fuerte a ser el indice de efecto de sonido a
; disparar, ver tarea pendiente de separar TABLA_NOTAS_PSG). ---
HNDLR_SUELO_SIN_BOLA:
    PUSH BC
    PUSH AF
    JP Z, TEMPORIZADOR_DIRECCION_FORZADA_TICK            ; sin modo especial activo -> nada que "salir", solo la cola comun
    CP 8                       ; modo tanque activo -> lo termina (rama de abajo)
    JR NZ, HNDLR_SUELO_SIN_BOLA_PLANE_CHECK
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    LD A, (COLOR_GUARDADO)
    LD (COLOR_ACTUAL), A
    XOR A
    LD (MODO_ESPECIAL), A
    LD (MODO_ESPECIAL_FLAG), A
    CALL INICIALIZAR_PARCIAL_ITEMS_NIVEL          ; segundo punto de entrada a INICIALIZAR_ITEMS_NIVEL ($5885) que SOLO limpia las 3 entradas (6 bytes) de la tabla $2C2E (posiciones activas de pista, ver REGISTRAR_PISTA_TANQUE_AVION y AVISAR_PROXIMIDAD_PISTA) y RET -- no repite el reseteo de ($2C10)/($2C1A)/($2C1B)/($2C0C) ni de las 3 tablas de items, que el llamador ya hizo o no necesita aqui
    JR TEMPORIZADOR_DIRECCION_FORZADA_TICK
HNDLR_SUELO_SIN_BOLA_PLANE_CHECK:
    CP 9                      ; modo avion activo -> lo termina (resto de esta rama)
    JR NZ, TEMPORIZADOR_DIRECCION_FORZADA_TICK
    LD A, E
    AND $03                    ; fase de movimiento correcta
    JR NZ, TEMPORIZADOR_DIRECCION_FORZADA_TICK
    XOR A
    LD (MODO_ESPECIAL_FLAG), A
    LD B, $0C                 ; 12 iteraciones, recorriendo la pista en sentido inverso al
    LD D, $68                   ; de HNDLR_PISTA_COCONAVE (D decrece con ADD A,$FC = -4 en vez de +4)
    LD E, $40
HNDLR_SUELO_SIN_BOLA_PLANE_LOOP:
    PUSH BC
    PUSH DE
    LD H, $04
    POP DE
    LD A, D
    ADD A, $FC
    LD D, A
    LD B, $06
    XOR A
    PUSH AF
    PUSH HL
    PUSH DE
    PUSH BC
    LD A, H
    CALL GESTIONAR_SCROLL
    LD A, (FLAG_ENTRADA_BLOQUEADA)
    AND A
    PUSH AF
    CALL Z, HNDLR_PELMAZOIDE
    POP AF
    PUSH AF
    CALL Z, HNDLR_MARICOCO
    POP AF
    CALL Z, HNDLR_REGPUNANTOSO
    CALL ACTUALIZAR_DESTELLO_ITEMS
    POP BC
    POP DE
    POP HL
    POP AF
    CALL Z, MOTOR_ACTORES
    CALL WAIT_VBLANK               ; WAIT_VBLANK (madmix1.asm)
    POP BC
    DJNZ HNDLR_SUELO_SIN_BOLA_PLANE_LOOP
    CALL INICIALIZAR_PARCIAL_ITEMS_NIVEL
    LD A, $03
    LD (EVENTO_SONIDO_PENDIENTE), A
    XOR A
    LD (MODO_ESPECIAL), A
    LD A, (COLOR_GUARDADO)
    LD (COLOR_ACTUAL), A
    LD BC, $1018
    LD (POSICION_ACTUAL_CAMARA), BC
    JR TEMPORIZADOR_DIRECCION_FORZADA_TICK
; --- Cola comun de HNDLR_SUELO_SIN_BOLA (llegada tambien por caida directa
; sin modo activo): si ($2C1B) esta a cero limpia la direccion
; forzada ($2C1A) y ($2C1E); si no, simplemente lo decrementa --
; candidato a "cuenta atras de cuantos pasos mas dura la direccion
; forzada por una flecha" antes de volver a permitir giro libre. ---
TEMPORIZADOR_DIRECCION_FORZADA_TICK:
    PUSH HL
    LD HL, TEMPORIZADOR_DIRECCION_FORZADA
    LD A, (HL)
    AND A
    JR Z, LIMPIAR_DIRECCION_FORZADA              ; ya a cero -> limpia la direccion forzada de verdad
    DEC (HL)                     ; todavia quedan pasos -> solo decrementa
    JR FIN_TICK_DIRECCION_FORZADA
LIMPIAR_DIRECCION_FORZADA:
    LD (DIRECCION_FORZADA), A
    XOR A
    LD (LADO_APERTURA_TRAMPILLA), A
FIN_TICK_DIRECCION_FORZADA:
    POP HL
    POP AF
    POP BC
    JP TICK_MODO_ESPECIAL

; --- Entradas 17-19 de TABLA_MANEJADORES_LOSETA (0x3252-0x335C). Tipos
; reales confirmados cruzando TABLA_TIPOS_LOSETA: 17 = trampilla_a_abajo_
; derecha (loseta 68) -> HNDLR_TRAMPILLA_ABIERTA_DERECHA, 18 =
; trampilla_b_abajo_izquierda (loseta 73) -> HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA,
; 19 = trampilla_transicion_abajo_izquierda/derecha (losetas 78/79) ->
; HNDLR_TRAMPILLA_CERRADA (unica entrada de tabla para el cierre de
; AMBOS lados: internamente comprueba LADO_APERTURA_TRAMPILLA y salta a la
; variante HNDLR_TRAMPILLA_CERRADA_B cuando la apertura fue la de la
; derecha -- ver detalle alli, el reparto de que variante dibuja que
; lado NO seria el que cabria esperar por el nombre "_B"). Cada una
; redibuja un area 2x2 con las losetas intermedias de la animacion de
; apertura (indices $43-$4F del catalogo, familia "transicion") via
; REDIBUJAR_LOSETA_BUFFER_VRAM, y marca $2C1A/$2C1E (fase de animacion) y evento
; EVENTO_SONIDO_PENDIENTE=9 cuando coincide la fase (E AND 3 = 2).
HNDLR_TRAMPILLA_ABIERTA_DERECHA:
    PUSH AF
    LD A, $02
    LD (DIRECCION_FORZADA), A
    LD (LADO_APERTURA_TRAMPILLA), A
    LD A, E
    AND $03
    CP 2                    ; fase de movimiento correcta -> dibuja el fotograma de apertura
    JR NZ, FIN_ANIMACION_TRAMPILLA
    LD A, $09
    LD (EVENTO_SONIDO_PENDIENTE), A
    PUSH HL
    PUSH BC
    LD A, $4F
    LD (HL), A
    LD BC, $0405
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    DEC HL
    LD A, $4E
    LD BC, $0404
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    LD BC, $FFE0
    ADD HL, BC
    LD A, $4C
    LD (HL), A
    LD BC, $0304
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    INC HL
    LD A, $4D
    LD (HL), A
    LD BC, $0305
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    POP BC
    POP HL
FIN_ANIMACION_TRAMPILLA:
    POP AF
    JP TICK_MODO_ESPECIAL

HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA:
    PUSH AF
    LD A, (DIRECCION_FORZADA)
    AND A
    LD A, $01
    LD (DIRECCION_FORZADA), A
    LD (LADO_APERTURA_TRAMPILLA), A
    LD A, E
    AND $03
    CP 2                    ; fase de movimiento correcta -> dibuja el fotograma siguiente
    JR NZ, FIN_ANIMACION_TRAMPILLA
    LD A, $09
    LD (EVENTO_SONIDO_PENDIENTE), A
    PUSH HL
    LD A, $4E
    LD (HL), A
    LD BC, $0406
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    INC HL
    LD A, $4F
    LD BC, $0407
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    LD BC, $FFE0
    ADD HL, BC
    LD A, $4D
    LD (HL), A
    LD BC, $0307
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    DEC HL
    LD A, $4C
    LD (HL), A
    LD BC, $0306
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    POP HL
    LD B, $01
    JR FIN_ANIMACION_TRAMPILLA

HNDLR_TRAMPILLA_CERRADA:
    PUSH AF
    LD A, (LADO_APERTURA_TRAMPILLA)             ; variante de trampilla en curso (fijada por HNDLR_TRAMPILLA_ABIERTA_DERECHA/HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA)
    LD B, A
    LD A, E
    AND $03
    CP 2                    ; fase de movimiento correcta
    JR NZ, FIN_ANIMACION_TRAMPILLA
    LD A, 3
    LD (TEMPORIZADOR_DIRECCION_FORZADA), A
    LD A, B
    CP 2                    ; LADO_APERTURA_TRAMPILLA==2 -> se abrio con HNDLR_TRAMPILLA_ABIERTA_DERECHA ->
    JR Z, HNDLR_TRAMPILLA_CERRADA_B ; el cierre de esa apertura lo dibuja la variante _B (rama de abajo);
                              ; si NZ (fase 1, se abrio con HNDLR_TRAMPILLA_ABIERTA_IZQUIERDA), sigue
                              ; aqui mismo y dibuja el cierre del lado izquierdo
    PUSH HL
    LD A, $44
    LD BC, $0406
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    DEC HL
    LD A, $43
    LD BC, $0405
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    LD BC, $FFE0
    ADD HL, BC
    LD A, $4A
    LD (HL), A
    LD BC, $0305
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    INC HL
    LD A, $4B
    LD (HL), A
    LD BC, $0306
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    LD B, $01
    POP HL
    POP AF
    JP TICK_MODO_ESPECIAL

HNDLR_TRAMPILLA_CERRADA_B:
    PUSH HL
    LD A, $49
    LD BC, $0405
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    INC HL
    LD A, $45
    LD BC, $0406
    LD (HL), A
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    LD BC, $FFE0
    ADD HL, BC
    LD A, $48
    LD (HL), A
    LD BC, $0306
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    DEC HL
    LD A, $47
    LD (HL), A
    LD BC, $0305
    CALL REDIBUJAR_LOSETA_BUFFER_VRAM
    POP HL
    LD B, $02
    POP AF
    JP TICK_MODO_ESPECIAL

    ; $335C-$511C: datos crudos de los niveles (matrices de losetas)
    ; y sus cabeceras compartidas, identificados por los punteros
    ; campo0/campo2 de TABLA_NIVELES (ver mas abajo y FINDINGS.md).
    ; Los bloques resultaron ser PERFECTAMENTE CONTIGUOS entre si
    ; (cada uno empieza exactamente donde acaba el anterior), incluido
    ; el cuerpo del nivel 15 en $48BC-$4AFC (ver CUERPO_L15).
CUERPO_L01:                       ; niveles 0 y 1 (registro identico), 22 filas
    INCBIN "data/niveles/body_l01.bin"        ; $335C-$361C (0x2C0)
CUERPO_L2:                        ; nivel 2, 15 filas
    INCBIN "data/niveles/body_l2.bin"         ; $361C-$37FC (0x1E0)
CUERPO_L3:                        ; nivel 3, 16 filas
    INCBIN "data/niveles/body_l3.bin"         ; $37FC-$39FC (0x200)
CUERPO_L9:                        ; nivel 9, 18 filas
    INCBIN "data/niveles/body_l9.bin"         ; $39FC-$3C3C (0x240)
CUERPO_L5:                        ; nivel 5, 16 filas
    INCBIN "data/niveles/body_l5.bin"         ; $3C3C-$3E3C (0x200)
CUERPO_L6:                        ; nivel 6, 18 filas
    INCBIN "data/niveles/body_l6.bin"         ; $3E3C-$407C (0x240)
CUERPO_L4:                        ; nivel 4, 15 filas
    INCBIN "data/niveles/body_l4.bin"         ; $407C-$425C (0x1E0)
CUERPO_L8:                        ; nivel 8, 15 filas
    INCBIN "data/niveles/body_l8.bin"         ; $425C-$443C (0x1E0)
CUERPO_L7:                        ; nivel 7, 19 filas
    INCBIN "data/niveles/body_l7.bin"         ; $443C-$469C (0x260)
CUERPO_L10:                       ; nivel 10, 17 filas
    INCBIN "data/niveles/body_l10.bin"        ; $469C-$48BC (0x220)

    ; Cuerpo del NIVEL 15 (576 bytes, 18 filas x 32 columnas, mismo
    ; tamano que los niveles 6 y 9). Documentado primero como "nivel
    ; oculto/sin usar" (candidato a nivel adicional de desarrollo, sin
    ; registro que lo referenciara) -- RESUELTO: SI tiene registro
    ; real en TABLA_NIVELES (el registro 15, el ultimo, ver mas abajo) y
    ; SI se alcanza en partida normal completando los 14 niveles
    ; anteriores sin agotar el ciclo (ver CARGAR_NIVEL/VERIFICAR_FIN_NIVEL,
    ; FINDINGS.md). Confirmado visualmente (recursos/nivel_oculto.html)
    ; y jugado de verdad en openMSX.
CUERPO_L15:
    INCBIN "data/niveles/body_l15.bin" ; $48BC-$4AFC (0x240)

CABECERA_4AFC:                    ; cabecera compartida (niveles 4,5,7,12,13)
    INCBIN "data/niveles/header_4afc.bin"     ; $4AFC-$4B5C (0x60)
CABECERA_4B5C:                    ; cabecera compartida (nivel 8)
    INCBIN "data/niveles/header_4b5c.bin"     ; $4B5C-$4BBC (0x60)
CUERPO_L11:                       ; nivel 11, 21 filas
    INCBIN "data/niveles/body_l11.bin"        ; $4BBC-$4E5C (0x2A0)
CUERPO_L12:                       ; nivel 12, 19 filas
    INCBIN "data/niveles/body_l12.bin"        ; $4E5C-$50BC (0x260)
CABECERA_50BC:                    ; cabecera compartida (niveles 0,1,2,3,6,9,10,11,14)
    INCBIN "data/niveles/header_50bc.bin"     ; $50BC-$511C (0x60)

; ==============================================================
;  ZONA $511C-$545F: tabla de tipos de item + tablas auxiliares +
;  la rutina HNDLR_PELMAZOIDE (llamada desde el bucle principal) + los dos
;  helpers $5278/$53A2 que faltaban del subsistema de activacion
;  de items (llamados desde HNDLR_MARICOCO/HNDLR_REGPUNANTOSO e ACTUALIZAR_DESTELLO_ITEMS).
;  Desensamblado completo con Z80Dasm, sin desincronizar en ningun
;  punto desde HNDLR_PELMAZOIDE hasta el RET final en $545E (justo antes de
;  MAPEAR_COORDENADA_A_DIRECCION en $545F).
; ==============================================================

; --- TABLA_ITEMS_PELMAZOIDE: tabla activa de items TIPO 3 (8 entradas de
; 7 bytes -- estructura CONFIRMADA identica, cruzando MOTOR_MOVIMIENTO_ITEM/
; CALCULAR_POSICION_VRAM_ITEM/INICIALIZAR_ITEMS_NIVEL, a TABLA_ITEMS_MARICOCO/TABLA_ITEMS_REGPUNANTOSO mas abajo en
; este mismo fichero):
;   offset 0: posicion X (loseta entera)
;   offset 1: posicion Y (loseta entera)
;   offset 2: modo/comportamiento -- 0 = persiguiendo activamente
;             (UNICO valor real usado por items tipo 3, ver
;             TABLA_ANIMACION_PELMAZOIDE mas abajo); 1/2 = "plantado", solo
;             usados por TABLA_ITEMS_MARICOCO/TABLA_ITEMS_REGPUNANTOSO respectivamente,
;             NUNCA por esta tabla (INICIALIZAR_ITEMS_NIVEL no lo toca -- se queda
;             siempre a 0)
;   offset 3: codigo de direccion de movimiento en curso (1/2/3/4 =
;             derecha/izquierda/abajo/arriba, 0 = ninguna)
;   offset 4: subposicion X (parte fraccional del movimiento paso a paso)
;   offset 5: subposicion Y (parte fraccional)
;   offset 6: fase de animacion (0-3, rotativa -- incrementada cada vez
;             que HNDLR_PELMAZOIDE procesa esta entrada). CORRECCION de una
;             ronda anterior: esto NO es un "tipo de item 0-3", es
;             simplemente la fase de animacion inicial de cada
;             entrada (para que los 8 items no animen sincronizados)
; INICIALIZAR_ITEMS_NIVEL reinicializa cada nivel SOLO los offsets 0/1/4/5
; (posicion), dejando intactos modo/direccion/fase -- los valores de
; posicion de compilacion de abajo (X=$10 o $20, Y=$10 siempre) se
; sobrescriben siempre, sin efecto real. ---
TABLA_ITEMS_PELMAZOIDE:                ; $511C
    DB $20,$10,$00,$01,$00,$00,$01  ; X,Y=semilla(sobrescrita) modo=0 dir=1 subX,subY=0 fase=1
    DB $10,$10,$00,$01,$00,$00,$02  ; fase=2
    DB $10,$10,$00,$01,$00,$00,$03  ; fase=3
    DB $10,$10,$00,$01,$00,$00,$01  ; fase=1
    DB $10,$10,$00,$01,$00,$00,$02  ; fase=2
    DB $10,$10,$00,$01,$00,$00,$01  ; fase=1
    DB $10,$10,$00,$01,$00,$00,$00  ; fase=0
    DB $10,$10,$00,$01,$00,$00,$01  ; fase=1

; --- $5154-$51FD (170 bytes): 2 tablas auxiliares + un hueco sin
; explicar entre ambas, consultadas por MOTOR_MOVIMIENTO_ITEM/HNDLR_PELMAZOIDE al
; mover items tipo 3.
;
; TABLA_ANIMACION_PELMAZOIDE ($5154, 32 bytes): RESUELTA POR COMPLETO.
; HNDLR_PELMAZOIDE la indexa con "((IX+2) AND $0F)*2" (offset2 de
; TABLA_ITEMS_PELMAZOIDE es siempre 0 en la practica, unico valor real
; usado -- ver arriba), obtiene DE = palabra 0 = $5156 -- un puntero
; AUTORREFERENCIAL real, no un accidente: apunta 2 bytes mas adelante,
; DENTRO de esta misma tabla. Luego calcula
; direccion(1-4, codigo compacto que devuelve MOTOR_MOVIMIENTO_ITEM)*4+fase(0-3)
; y lo SUMA a DE para leer el sprite final. Es decir: esta tabla NO es
; "16 punteros, uno por modo" -- es UN puntero a si misma seguido de
; los datos reales de sprite (4 direcciones x 2 fotogramas), mismo
; mecanismo (confirmado identico) que usa TABLA_ANIMACION_MARICOCO de
; HNDLR_MARICOCO mas abajo (esa sin autorreferencia, tabla aparte).
;
; CONFIRMA EL VOLTEO HORIZONTAL (bit7) SIN TRAZADO EN VIVO: el grupo
; "izquierda" ($9B,$9C) es EXACTAMENTE el grupo "derecha" ($1B,$1C)
; con el bit7 puesto -- no existe sprite propio para la izquierda, se
; reutiliza el de la derecha reflejado (ver "AND $80" tras leer el
; byte, en HNDLR_PELMAZOIDE). Mismo fenomeno ya documentado para los
; sprites de personajes (antes "candidato, aparcado, requiere trazado
; en vivo") -- aqui queda confirmado por simple analisis estatico.
;
; IDENTIDAD CONFIRMADA: $1B/$1C/$1D/$1E/$1F/$20 = SPR27_FANTASMA_DER_1,
; SPR28_FANTASMA_DER_2, SPR29_FANTASMA_ABAJO_1, SPR30_FANTASMA_ABAJO_2,
; SPR31_FANTASMA_ARRIBA_1, SPR32_FANTASMA_ARRIBA_2 del catalogo ya
; identificado por el usuario (madmix1_body.asm) -- TABLA_ITEMS_PELMAZOIDE/
; HNDLR_PELMAZOIDE es la IA de movimiento de los fantasmas del juego.
;
; Cola de 20 bytes SIN CONSUMIDOR CONOCIDO: los ultimos 10 bytes de
; esta tabla (offset 22-31, direccion*4+fase nunca llega ahi -- maximo
; indice real es offset 21) mas los 10 bytes siguientes ($5174-$517D,
; `$A2,$A2,$23,$23,$24,$24,$1F,$1F,$20,$20`). Candidatos a DATOS DE
; SPRITE HUERFANOS, no a codigo: se probo desensamblar estos ultimos
; 10 bytes como Z80 (decodifican completos, sin instruccion a medias,
; en `AND D`/`AND D`/`INC HL`/`INC HL`/`INC H`/`INC H`/`RRA`/`RRA`/
; `JR NZ,+32`) pero la secuencia no tiene ningun sentido funcional
; (instrucciones duplicadas seguidas sin proposito, a diferencia del
; codigo muerto real ya confirmado en este proyecto). En cambio, SI
; encajan con la convencion de "pares de bytes repetidos = 2
; fotogramas" que usan `TABLA_ANIMACION_PELMAZOIDE`/`TABLA_ANIMACION_MARICOCO`/`TABLA_ANIMACION_REGPUNANTOSO` --
; y `$1F`/`$20` coinciden exactos con los sprites de "arriba" ya
; usados arriba, `$A2`=`$22` con bit7 (mismo patron de volteo
; horizontal). Ninguna referencia real encontrada en el codigo.
;
; TABLA_ELECCION_DIRECCION ($517E, 128 bytes = 16 bloques de 8): DATO
; puro (solo se lee con "LD A,(HL)", ningun JP/JR/CALL apunta aqui).
; Indexada por MOTOR_MOVIMIENTO_ITEM como
; "(bitmask de direcciones libres)<<3 | (prevdir)<<1 | (bit aleatorio)"
; -> devuelve el codigo de direccion final elegido (1/2/4/8, ver
; MOTOR_MOVIMIENTO_ITEM.ELEGIR_DIRECCION_ALEATORIA). ESTRUCTURA COMPLETA DECODIFICADA (correccion
; de una ronda anterior, que la daba por "gate binario de alineamiento"
; -- en realidad son 2 bits que codifican la direccion EN CURSO antes
; de decidir, via TABLA_CLASE_ALINEAMIENTO[(IX+3)]): cada uno de los 16
; bloques corresponde a una combinacion de "direcciones libres"
; (indice de bloque = bitmask $01/$02/$04/$08 = derecha/izquierda/
; abajo/arriba), y dentro de cada bloque los 8 bytes se agrupan en 4
; pares (2 bytes = mismo resultado, el bit aleatorio solo desempata):
; par0=si NO habia direccion previa o iba a la derecha, par1=si iba a
; la izquierda, par2=si iba abajo, par3=si iba arriba. Confirma que es
; una tabla de "mantener direccion si se puede, si no elegir otra de
; las libres" (sesgo de continuidad de movimiento) -- cuando solo hay
; una direccion libre, los 8 bytes del bloque son identicos (esa
; unica direccion) sea cual sea la direccion previa. ---
TABLA_ANIMACION_PELMAZOIDE:
    DB $56,$51                      ; offset 0-1: puntero autorreferencial = $5156 (offset 2 de aqui mismo)
    DB $1B,$1B,$1C,$1C               ; offset 2-5: NUNCA se lee (direccion nunca vale 0) -- duplica "derecha"
    DB $1B,$1B,$1C,$1C               ; offset 6-9: DERECHA (direccion=1) -- sprites $1B,$1C
    DB $9B,$9B,$9C,$9C               ; offset 10-13: IZQUIERDA (direccion=2) -- $1B,$1C con bit7 (volteo horizontal)
    DB $1D,$1D,$1E,$1E               ; offset 14-17: ABAJO (direccion=3) -- sprites $1D,$1E
    DB $1F,$1F,$20,$20               ; offset 18-21: ARRIBA (direccion=4) -- sprites $1F,$20 -- ULTIMO offset real alcanzable
    DB $21,$21,$22,$22               ; offset 22-25: cola sin usar, fuera de rango indexable
    DB $21,$21,$22,$22               ; offset 26-29: cola sin usar, repite el patron anterior
    DB $A1,$A1                       ; offset 30-31: cola sin usar ($21 con bit7)
    DB $A2,$A2,$23,$23,$24,$24,$1F,$1F,$20,$20                          ; $5174-$517D: candidato a sprite huerfano (dato, no codigo -- ver cabecera de seccion)
TABLA_ELECCION_DIRECCION:
    DB $01,$01,$01,$01,$01,$01,$01,$01  ; libres=ninguna (0000) -- sin libres, siempre intenta derecha por defecto
    DB $01,$01,$01,$01,$01,$01,$01,$01  ; libres=derecha (0001)
    DB $02,$02,$02,$02,$02,$02,$02,$02  ; libres=izquierda (0010)
    DB $01,$01,$02,$02,$01,$01,$01,$01  ; libres=derecha+izquierda (0011) -- prev.derecha->derecha, prev.izquierda->izquierda, resto->derecha
    DB $04,$04,$04,$04,$04,$04,$04,$04  ; libres=abajo (0100)
    DB $01,$01,$04,$04,$04,$04,$01,$01  ; libres=derecha+abajo (0101)
    DB $04,$04,$02,$02,$04,$04,$02,$02  ; libres=izquierda+abajo (0110)
    DB $01,$04,$02,$04,$01,$02,$01,$02  ; libres=derecha+izquierda+abajo (0111)
    DB $08,$08,$08,$08,$08,$08,$08,$08  ; libres=arriba (1000)
    DB $01,$01,$08,$08,$01,$01,$08,$08  ; libres=derecha+arriba (1001)
    DB $08,$08,$02,$02,$02,$02,$08,$08  ; libres=izquierda+arriba (1010)
    DB $01,$08,$02,$08,$01,$02,$08,$08  ; libres=derecha+izquierda+arriba (1011)
    DB $08,$04,$08,$04,$04,$04,$08,$08  ; libres=abajo+arriba (1100)
    DB $01,$01,$08,$04,$04,$01,$08,$01  ; libres=derecha+abajo+arriba (1101)
    DB $08,$04,$02,$02,$04,$02,$08,$02  ; libres=izquierda+abajo+arriba (1110)
    DB $01,$01,$02,$02,$04,$04,$08,$08  ; libres=derecha+izquierda+abajo+arriba (1111) -- mantiene la direccion previa en cada caso

; --- Rutina llamada desde el bucle principal (JT_GESTIONAR_SCROLL/scroll, ver
; FINDINGS.md main loop) como "HNDLR_PELMAZOIDE". Calcula una posicion relativa
; a la camara (+-8), la guarda en $2C1F, y si ($2BFB) (otro offset
; del registro de nivel en RAM de trabajo, candidato: contador de un
; tercer tipo de entidad) es distinto de cero, recorre esa cantidad
; de entradas de TABLA_ITEMS_PELMAZOIDE llamando a MOTOR_MOVIMIENTO_ITEM para
; cada una. ---
HNDLR_PELMAZOIDE:                         ; $51FE
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)             ; posicion de camara +8,+16 (mod 128) -> "punto de mira" guardado
    LD A, $10                    ; en ($2C1F), usado por MOTOR_MOVIMIENTO_ITEM para decidir "detras de camara"
    ADD A, H
    AND $7F
    LD H, A
    LD A, $18
    ADD A, L
    AND $7F
    LD L, A
    LD (PUNTO_REFERENCIA_CAMARA), HL
    LD A, (REGISTRO_NIVEL_CONTADOR_PELMAZOIDES)              ; offset del registro de nivel: cuantas entradas de
    AND A                        ; TABLA_ITEMS_PELMAZOIDE hay activas este nivel
    JP Z, FIN_PELMAZOIDE
    LD B, A
    LD IX, TABLA_ITEMS_PELMAZOIDE
BUCLE_PELMAZOIDE:
    PUSH BC
    CALL MOTOR_MOVIMIENTO_ITEM          ; valida posicion + calcula direccion de acercamiento (D)
    JR C, SIGUIENTE_PELMAZOIDE             ; no valida (fuera de rango/detras de camara) -> siguiente entrada
    PUSH DE
    LD A, (IX+2)
    AND $0F
    ADD A, A
    LD HL, TABLA_ANIMACION_PELMAZOIDE       ; tabla de 16 palabras (ver cabecera de seccion)
    ADD A, L
    LD L, A
    LD E, (HL)
    INC HL
    LD D, (HL)
    LD A, (MODO_ESPECIAL_FLAG)              ; modo especial de "camara invertida" activo (ver MOTOR_MOVIMIENTO_ITEM)?
    AND A
    JR Z, DIBUJAR_PELMAZOIDE
    LD A, (MODO_ESPECIAL_CUENTA_ATRAS)                ; temporizador de duracion del modo
    CP $32
    JR NC, AJUSTAR_SPRITE_MODO_ESPECIAL              ; todavia por encima de 50 -> ajuste siempre activo
    BIT 0, A                         ; por debajo de 50 -> solo en frames alternos (parpadeo)
    JR Z, DIBUJAR_PELMAZOIDE
AJUSTAR_SPRITE_MODO_ESPECIAL:
    EX DE, HL
    LD DE, $0014                  ; +20 bytes: usa la SEGUNDA mitad de cada grupo de la tabla
    ADD HL, DE                      ; (variante del sub-tipo mientras dura el modo especial)
    EX DE, HL
DIBUJAR_PELMAZOIDE:
    LD A, (IX+6)                ; indice rotativo 0-3 de esta entrada (fase de animacion)
    INC A
    AND $03
    LD (IX+6), A
    LD L, A
    LD A, C                        ; C = codigo compacto de direccion 1-4 (derecha/izquierda/
    ADD A, A                         ; abajo/arriba), devuelto por MOTOR_MOVIMIENTO_ITEM (ver su cabecera)
    ADD A, A
    ADD A, L
    LD L, A
    LD H, $00
    ADD HL, DE                  ; indice = direccion(1-4)*4 + fase(0-3) -> RESUELTO, ver
                                 ; TABLA_ANIMACION_PELMAZOIDE: offsets 6-9/10-13/14-17/18-21 (relativos
                                 ; a la tabla) son las 4 direcciones (offset 0-5 nunca se alcanza,
                                 ; la direccion nunca vale 0)
    LD A, (HL)
    LD D, A
    AND $7F
    LD B, A                       ; B = sprite/frame a dibujar
    LD A, D
    AND $80                         ; bit7 = volteo horizontal -- CONFIRMADO aqui (ver
                                     ; TABLA_ANIMACION_PELMAZOIDE: "izquierda" reutiliza el sprite
                                     ; de "derecha" con este bit puesto, nunca tiene sprite propio)
    POP DE
    PUSH IX
    CALL MOTOR_ACTORES                        ; MOTOR_ACTORES -- dibuja el actor en (IX+0/1)
    POP IX
    CALL ACTIVAR_EFECTO_ITEM              ; comprueba colision con el comecocos en esta posicion
SIGUIENTE_PELMAZOIDE:
    LD BC, $0007               ; 7 bytes por entrada de TABLA_ITEMS_PELMAZOIDE
    ADD IX, BC
    POP BC
    DEC B
    JP NZ, BUCLE_PELMAZOIDE
FIN_PELMAZOIDE:
    RET

; --- Helper $5278 (el que faltaba de ambos manejadores de items):
; comprueba si la posicion candidata (IX+0/1) esta "detras" de la
; camara segun la direccion actual, y si esta lo bastante lejos en
; el eje correspondiente. Devuelve con carry si NO es valida.
; Segundo punto de entrada en $53A2 (llamado directo desde
; ACTUALIZAR_DESTELLO_ITEMS): calcula una direccion de aproximacion (D/E) sin
; repetir las comprobaciones de arriba. ---
MOTOR_MOVIMIENTO_ITEM:                        ; $5278
    LD D, $00                 ; D = direccion de acercamiento hacia ($2C1F) (0 = ninguna
                                ; calculada); valores $01/$02/$04/$08 = derecha/izquierda/
                                ; abajo/arriba (convenio de CONSULTAR_LOSETA_LIBRE_DIRECCION/CONSULTAR_PROXIMA_LOSETA_EN_ESTA_DIRECCION,
                                ; DISTINTO del bit-indice que usan las flechas del despachador)
    LD C, (IX+0)               ; BC = posicion de este item (X,Y)
    LD B, (IX+1)
    LD HL, (PUNTO_REFERENCIA_CAMARA)              ; punto de referencia (camara+8,+16, ver HNDLR_PELMAZOIDE)
    LD A, (MODO_ESPECIAL_FLAG)
    AND A
    JR Z, .COMPROBAR_ESTADO_ITEM              ; sin modo especial "invertido" -> comprobaciones de abajo
    LD A, H                          ; con modo activo: usa el punto de referencia NEGADO
    NEG
    LD H, A
    LD A, L
    NEG
    LD L, A
    JR .CALCULAR_DIRECCION_ACERCAMIENTO                     ; y calcula la direccion igualmente, sin mas filtros
.COMPROBAR_ESTADO_ITEM:
    LD A, (IX+2)              ; flag propio de este item (candidato: "inactivo/congelado")
    AND A
    JR NZ, .COMPROBAR_ALINEAMIENTO_LOSETA           ; activo -> no calcula direccion (D se queda a 0)
    LD A, (MODO_ESPECIAL_ACTIVO)              ; temporizador de modo especial (ver MOTOR_MOVIMIENTO_COLISION)
    AND A
    JR NZ, .COMPROBAR_ALINEAMIENTO_LOSETA           ; modo especial en curso -> tampoco calcula direccion
.CALCULAR_DIRECCION_ACERCAMIENTO:
; --- Compara la posicion (BC) contra el punto de referencia (HL)
; alineados a multiplos de 4: si coinciden en columna, la direccion es
; vertical ($08=arriba o $04=abajo segun el signo de B-H); si no
; coinciden en columna pero si en fila, es horizontal ($02=izquierda o
; $01=derecha segun C-L); si no coincide ninguno de los dos ejes, D se
; queda a 0 (sin direccion clara). Convenio de valores CONFIRMADO
; cruzando con CONSULTAR_LOSETA_LIBRE_DIRECCION (mismo $01/$02/$04/$08 -> derecha/
; izquierda/abajo/arriba, ver su cabecera) -- OJO, es distinto del
; convenio de bit-INDICE que usan las flechas del despachador
; (BIT 0-3 de un byte de "direcciones bloqueadas", no confundir). ---
    LD A, L
    AND $FC
    LD L, A
    LD A, C
    AND $FC
    CP L
    JR NZ, .COMPROBAR_FILA            ; columna distinta -> prueba la fila
    LD A, B
    CP H
    LD D, $08                     ; misma columna: arriba si B>=H...
    JR NC, .COMPROBAR_ALINEAMIENTO_LOSETA
    LD D, $04                      ; ...abajo si B<H
    JR .COMPROBAR_ALINEAMIENTO_LOSETA
.COMPROBAR_FILA:
    LD A, H
    AND $FC
    LD H, A
    LD A, B
    AND $FC
    CP H
    JR NZ, .COMPROBAR_ALINEAMIENTO_LOSETA            ; tampoco coincide la fila -> D se queda a 0
    LD A, C
    CP L
    LD D, $02                     ; misma fila: izquierda si C>=L...
    JR NC, .COMPROBAR_ALINEAMIENTO_LOSETA
    LD D, $01                      ; ...derecha si C<L
.COMPROBAR_ALINEAMIENTO_LOSETA:
    LD A, (IX+0)              ; posicion sub-loseta (bits bajos de X/Y): 0 = tile-aligned
    OR (IX+1)
    AND $03
    LD A, (IX+3)                ; A = direccion/animacion ya en curso (frame anterior)
    JR NZ, .FIJAR_DIRECCION_Y_PASO              ; no alineado a loseta -> sigue con la misma sin recalcular
    LD B, D                          ; B = direccion de acercamiento deseada (calculada arriba)
    LD D, $00
    LD A, $01                          ; prueba las 4 direcciones con CONSULTAR_LOSETA_LIBRE_DIRECCION (¿hay loseta
    CALL CONSULTAR_LOSETA_LIBRE_DIRECCION                    ; libre un paso mas alla?) y acumula en D el bitmask de
    OR D                                  ; TODAS las direcciones libres desde aqui
    LD D, A
    LD A, $02
    CALL CONSULTAR_LOSETA_LIBRE_DIRECCION
    OR D
    LD D, A
    LD A, $04
    CALL CONSULTAR_LOSETA_LIBRE_DIRECCION
    OR D
    LD D, A
    LD A, $08
    CALL CONSULTAR_LOSETA_LIBRE_DIRECCION
    OR D
    LD D, A
    AND B                     ; ¿la direccion deseada (B) es una de las libres?
    JR Z, .ELEGIR_ENTRE_LIBRES             ; no lo es -> elige entre TODAS las libres (rama de abajo)
    LD A, (MODO_ESPECIAL_FLAG)
    AND A
    LD A, B
    JR NZ, .FIJAR_DIRECCION_Y_PASO              ; modo especial activo -> usa siempre la direccion deseada
    CALL GENERAR_ALEATORIO
    AND $01
    LD A, B
    JR Z, .FIJAR_DIRECCION_Y_PASO              ; 50% de las veces (tirada aleatoria) -> usa la deseada igualmente
.ELEGIR_ENTRE_LIBRES:
    LD A, D                  ; sin poder ir hacia el objetivo (o no tocaba per el azar):
    ADD A, A                    ; D<<3, prepara el bitmask de direcciones libres para indexar
    ADD A, A                      ; la tabla de eleccion aleatoria de mas abajo
    ADD A, A
    LD D, A
    LD A, (IX+2)              ; flag propio del item (mismo que arriba, "inactivo/congelado"?)
    AND A
    LD A, (IX+3)
    JR Z, .ELEGIR_DIRECCION_ALEATORIA             ; inactivo -> elige nueva direccion al azar entre las libres
    LD A, (IX+4)                  ; activo: CORREGIDO (comentario anterior decia lo contrario) --
    OR (IX+5)                       ; si la posicion fraccional (IX+4/5) tiene el bit alto puesto
    BIT 7, A                          ; (candidato: "ha llegado justo a un cruce") MANTIENE la
    LD A, (IX+3)                        ; direccion actual; solo elige al azar si el bit esta a 0
    JR NZ, .FIJAR_DIRECCION_Y_PASO
.ELEGIR_DIRECCION_ALEATORIA:
    LD HL, TABLA_CLASE_ALINEAMIENTO ; misma tabla de 16 bytes que en MOTOR_MOVIMIENTO_COLISION, aqui indexada por A=(IX+3)
                               ; (direccion previa: 0/1/2/4/8) para categorizarla en solo 4 grupos
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD A, (HL)
    SUB $01
    JR NC, .CONTINUAR_INDICE_DIRECCION_PREVIA
    XOR A
.CONTINUAR_INDICE_DIRECCION_PREVIA:
    ADD A, A                  ; E = 0/2/4/6 segun direccion previa (ninguna-o-derecha/izquierda/
    LD E, A                     ; abajo/arriba) -- bits 1-2 del indice final en TABLA_ELECCION_DIRECCION
    CALL GENERAR_ALEATORIO              ; tira un bit aleatorio mas para desempatar entre las libres
    AND $01
    OR E
    OR D
    LD HL, TABLA_ELECCION_DIRECCION       ; NO es TABLA_ANIMACION_MARICOCO (tabla distinta, ver cabecera de seccion)
    ADD A, L                            ; indexada por (direcciones libres, direccion previa,
    LD L, A                               ; bit aleatorio) -> devuelve la direccion final elegida
    LD A, H
    ADC A, $00
    LD H, A
    LD A, (HL)
.FIJAR_DIRECCION_Y_PASO:
    LD (IX+3), A
    LD C, A
    LD A, C
    AND $0F
    LD HL, TABLA_CLASE_ALINEAMIENTO
    ADD A, L
    LD L, A
    LD C, (HL)                ; CORREGIDO: NO es velocidad -- TABLA_CLASE_ALINEAMIENTO aqui convierte
                               ; la direccion bitmask ($01/$02/$04/$08) en un codigo COMPACTO
                               ; 1-4 (derecha/izquierda/abajo/arriba), reutilizado por el
                               ; llamador para indexar tablas de sprite (ver HNDLR_PELMAZOIDE/
                               ; HNDLR_MARICOCO/HNDLR_REGPUNANTOSO e TABLA_ANIMACION_PELMAZOIDE/
                               ; TABLA_ANIMACION_MARICOCO/TABLA_ANIMACION_REGPUNANTOSO)
    LD A, (IX+2)
    AND A
    LD A, C
    LD H, (IX+0)               ; HL = posicion:subposicion del eje X (IX+0:IX+4)
    LD L, (IX+4)
    LD DE, $0100              ; DE = incremento de movimiento (paso normal)...
    JR Z, .CONTINUAR_TRAS_ELEGIR_PASO
    LD DE, $0080                ; ...o mitad de paso si (IX+2) esta activo
.CONTINUAR_TRAS_ELEGIR_PASO:
    LD A, (MODO_ESPECIAL_FLAG)
    AND A
    JR Z, .CONTINUAR_TRAS_MODO_INVERTIDO
    LD DE, $0080                ; ...o mitad de paso con el modo especial "invertido" activo
.CONTINUAR_TRAS_MODO_INVERTIDO:
; --- Aplica el movimiento de eje X o Y segun el codigo de direccion
; final en C (los 4 valores comprobados aqui, sin confirmar si
; coinciden 1:1 con el bitmask 1/2/4/8 usado mas arriba para
; "direccion deseada"/CONSULTAR_LOSETA_LIBRE_DIRECCION o si es una codificacion secuencial
; propia de este tramo): dos valores mueven X (suma/resta), los otros
; dos mueven Y. ---
    LD A, C
    CP $01
    JR NZ, .COMPROBAR_CODIGO_IZQUIERDA
    LD (IX+5), $00
    ADD HL, DE                ; codigo 1: X += paso
.COMPROBAR_CODIGO_IZQUIERDA:
    CP $02
    JR NZ, .COMPROBAR_CODIGO_ABAJO
    LD (IX+5), $00
    SBC HL, DE                ; codigo 2: X -= paso
.COMPROBAR_CODIGO_ABAJO:
    LD (IX+4), L
    LD (IX+0), H
    LD H, (IX+1)               ; HL = posicion:subposicion del eje Y (IX+1:IX+5)
    LD L, (IX+5)
    CP $03
    JR NZ, .COMPROBAR_CODIGO_ARRIBA
    LD (IX+4), $00
    ADD HL, DE                ; codigo 3: Y += paso
.COMPROBAR_CODIGO_ARRIBA:
    CP $04
    JR NZ, .GUARDAR_POSICION_Y
    LD (IX+4), $00
    SBC HL, DE                ; codigo 4: Y -= paso
.GUARDAR_POSICION_Y:
    LD (IX+5), L
    LD (IX+1), H
; --- Segundo punto de entrada de MOTOR_MOVIMIENTO_ITEM, llamado directo desde
; ACTUALIZAR_DESTELLO_ITEMS (sin pasar por las comprobaciones de "detras de
; camara" de arriba): calcula la direccion VRAM (D/E) de la posicion
; (IX+0/1) relativa a la camara actual y la comprueba contra los
; limites visibles de pantalla (CP $2C / CP $38). Devuelve con carry
; si la posicion cae fuera de rango (nada que dibujar); sin carry y
; DE=direccion VRAM si es visible. ---
CALCULAR_POSICION_VRAM_ITEM:                        ; $53A2
    PUSH BC
    LD BC, $0000
    LD DE, (REGISTRO_NIVEL_POSICION_COMECOCOS)
    RES 7, E                     ; limpia el bit7 (flag de direccion de scroll en .H/.L, ver SCROLL_ARRIBA/SCROLL_ABAJO)
    RES 7, D                     ; -- aqui la posicion de camara se trata como coordenada pura, sin el flag
    LD A, E
    SUB 8                        ; 8 = offset de referencia respecto a la camara (mismo valor que PUNTO_REFERENCIA_CAMARA, restado en vez de sumado)
    RES 7, A
    CP 64                        ; 64 = mitad del rango de columna (limite de wrap)
    JR C, .CONTINUAR_AJUSTE_COLUMNA
    LD C, 64                     ; 64 = ajuste de wrap para la columna (tambien reutilizado mas abajo como sumando)
    SUB C
.CONTINUAR_AJUSTE_COLUMNA:
    LD E, A                      ; E = columna de camara ajustada, en rango 0-63
    LD A, D
    SUB 8                        ; mismo ajuste de -8 que arriba, mismo patron
    RES 7, A
    CP 64
    JR C, .CONTINUAR_AJUSTE_FILA
    LD B, 64                     ; 64 = ajuste de wrap para la fila (tambien reutilizado mas abajo como sumando)
    SUB B
.CONTINUAR_AJUSTE_FILA:
    LD D, A                      ; D = fila de camara ajustada, en rango 0-63
    LD A, (IX+1)                 ; A = posicion Y del item
    RES 7, A
    ADD A, B                     ; compensa el ajuste de wrap de la fila (B=0 o 64, segun arriba)
    RES 7, A
    SUB D                        ; delta = posicion Y del item - fila de camara ajustada
    RES 7, A
    JR C, .SALIR_FUERA_DE_RANGO             ; delta negativo -> fuera de la ventana visible
    CP 44                        ; 44 = limite superior de fila visible
    JR NC, .SALIR_FUERA_DE_RANGO
    SUB 8                        ; mismo ajuste de -8 de nuevo, sobre el delta de fila
    RES 7, A
    LD H, A                      ; H = delta de fila final (candidato a fila de tile 0-31)
    LD A, (IX+0)                 ; A = posicion X del item
    RES 7, A
    ADD A, C                     ; compensa el ajuste de wrap de la columna (C=0 o 64)
    RES 7, A
    SUB E                        ; delta = posicion X del item - columna de camara ajustada
    RES 7, A
    JR C, .SALIR_FUERA_DE_RANGO             ; delta negativo -> fuera de la ventana visible
    CP 56                        ; 56 = limite superior de columna visible
    JR NC, .SALIR_FUERA_DE_RANGO
    SUB 8                        ; mismo ajuste de -8 de nuevo, sobre el delta de columna
    RES 7, A
    LD L, A                      ; L = delta de columna final (candidato a columna de tile 0-31)
    ADD A, A                     ; x2: construye el byte bajo de la direccion VRAM final
    ADD A, 14                    ; +14 = offset base de la construccion de direccion (candidato, sin confirmar del todo)
    LD E, A
    LD A, H
    ADD A, A                     ; x4 (2 dobles): construye el byte alto de la direccion VRAM final
    ADD A, A
    ADD A, $F8                   ; $F8 = -8 (delta con signo), completa el calculo de direccion
    LD D, A
    LD A, (IX+4)                 ; bit de orientacion/animacion del item (candidato, ver cabecera de la seccion)
    RLCA
    LD A, E
    ADC A, $00                   ; propaga el acarreo del RLCA anterior al byte bajo
    LD E, A
    LD A, (IX+5)                 ; mismo patron con el otro bit, sobre el byte alto
    RLCA
    LD A, D
    ADC A, $00
    LD D, A
    POP BC
    AND A                        ; NC = posicion visible, DE = direccion VRAM final
    RET
.SALIR_FUERA_DE_RANGO:
    POP BC
    SCF                          ; C = posicion fuera de rango, nada que dibujar
    RET

; --- Helper local: calcula, para cada uno de los 4 bits de
; direccion (A=1/2/4/8), si la posicion (IX+0/1) tiene loseta libre
; un paso en esa direccion (via MAPEAR_COORDENADA_A_DIRECCION + CONSULTAR_TIPO_LOSETA).
; Llamado 4 veces seguidas desde MOTOR_MOVIMIENTO_ITEM (bitmask acumulado). ---
CONSULTAR_LOSETA_LIBRE_DIRECCION:                        ; $5414
    PUSH BC
    PUSH DE
    LD C, (IX+0)              ; BC = posicion de este item
    LD B, (IX+1)
    RRA                       ; bit0 de A (entrada, $01/$02/$04/$08) -> derecha
    JR NC, .COMPROBAR_IZQUIERDA
    INC C
    INC C
    INC C
    INC C                       ; +1 columna
    LD A, $01                  ; guarda el codigo de direccion "derecha" para el resultado (D mas abajo)
    JR .CONSULTAR_LOSETA_DESPLAZADA
.COMPROBAR_IZQUIERDA:
    RRA                       ; bit1 -> izquierda
    JR NC, .COMPROBAR_ABAJO
    DEC C                        ; -1 columna
    LD A, $02                  ; codigo de direccion "izquierda"
    JR .CONSULTAR_LOSETA_DESPLAZADA
.COMPROBAR_ABAJO:
    RRA                       ; bit2 -> abajo
    JR NC, .COMPROBAR_ARRIBA
    INC B
    INC B
    INC B
    INC B                       ; +1 fila
    LD A, $04                  ; codigo de direccion "abajo"
    JR .CONSULTAR_LOSETA_DESPLAZADA
.COMPROBAR_ARRIBA:
    RRA                       ; bit3 -> arriba
    JR NC, .CONSULTAR_LOSETA_DESPLAZADA
    DEC B                        ; -1 fila
    LD A, $08                  ; codigo de direccion "arriba"
.CONSULTAR_LOSETA_DESPLAZADA:
    LD D, A                  ; D = la direccion que se esta probando (para el resultado)
    CALL MAPEAR_COORDENADA_A_DIRECCION
    CALL CONSULTAR_TIPO_LOSETA                        ; CONSULTAR_TIPO_LOSETA: tipo de la loseta desplazada
; --- Tipos 0 (pared/suelo normal), 7 (pista tanque), 8 (linea
; electrica puerta fantasmas) y 10 (pista avion) se consideran NO
; transitables para este item -- cualquier otro tipo (bolita, bola
; clavada, flechas, items especiales, trampillas...) SI lo es. Nota:
; type 0 incluye tanto paredes como suelo normal sin distinguir, asi
; que este item en concreto solo puede moverse por losetas "con
; decoracion especial", nunca por pasillo llano -- coherente con ser
; una entidad ligada al subsistema de items, no el comecocos/fantasma
; normal. ---
    AND A
    JR Z, .LOSETA_BLOQUEADA             ; tipo 0 -> bloqueado
    CP 8
    JR Z, .LOSETA_BLOQUEADA               ; tipo 8 -> bloqueado
    CP 7
    JR Z, .LOSETA_BLOQUEADA                 ; tipo 7 -> bloqueado
    CP 10
    JR NZ, .LOSETA_LIBRE                  ; ningun otro tipo -> libre
.LOSETA_BLOQUEADA:
    XOR A
    SCF                       ; tipo 10 (cae aqui) o cualquiera de los de arriba -> carry=bloqueado
    JR .FIN_CONSULTA_LOSETA
.LOSETA_LIBRE:
    LD A, D                  ; libre: A=D (la direccion probada)
    AND A                       ; y carry=0 (AND siempre limpia el acarreo)
.FIN_CONSULTA_LOSETA:
    POP DE
    POP BC
    RET

; --- MAPEAR_COORDENADA_A_DIRECCION ($545F) -- CONFIRMADO: formula identica a
; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA del motor principal (fila*32+columna, base de
; buffer de nivel), aplicada aqui a BC en vez de a la posicion de
; camara. Va ANTES del cargador de nivel en memoria real
; (0x545F < 0x5904), por eso se transcribe aqui y no despues.
;
; BUG CORREGIDO (ver madmix1.asm MAPEAR_LOSETA_A_GRAFICO y FINDINGS.md): la
; v1.0 original tenia $FC60 aqui -- uno de los 5 sitios del bug del
; contador de bolitas del nivel 13. Fix de la v2.0 aplicado:
; $FC60 -> $FC50. ---
MAPEAR_COORDENADA_A_DIRECCION:
    LD A, B
    AND $7C
    RRCA
    RRCA
    LD B, A
    LD A, C
    AND $7C
    RLCA
    RR B
    RRA
    RR B
    RRA
    RR B
    RRA
    LD C, A
    LD HL, $FC50            ; BUG CORREGIDO: $FC60 en la v1.0 original, ver comentario arriba
    ADD HL, BC
    RET

; ==============================================================
;  SUBSISTEMA DE ACTIVACION DE ITEMS ESPECIALES (0x5478-0x5904)
;  Desensamblado completo con Z80Dasm (sin desincronizar en ningun
;  punto -- todo el rango es codigo+datos coherentes, conectados
;  por CALL/JP reales). Documentado primero en sesion anterior (ver
;  FINDINGS.md), transcrito aqui. Dos instancias casi identicas de
;  un manejador (una por tipo de item), cada una con: contador de
;  entradas leido de un offset del registro de nivel, tabla de
;  posiciones activas, tabla de frames de animacion, y la logica
;  de activacion (llama a MOTOR_ACTORES en $8440 al detectar
;  coincidencia de posicion).
; ==============================================================

GENERAR_ALEATORIO:                          ; $5478 -- generador pseudoaleatorio
    PUSH HL
    LD HL, (SEMILLA_ALEATORIA)
    LD A, R
    RRCA
    ADC A, L
    XOR (HL)
    LD L, A
    LD (SEMILLA_ALEATORIA), HL
    POP HL
    RET

; --- TABLA_ANIMACION_MARICOCO: 20 bytes, mismo mecanismo confirmado que
; TABLA_ANIMACION_PELMAZOIDE (indexada por HNDLR_MARICOCO como
; direccion(1-4)*4+fase(0-3)) pero SIN autorreferencia -- tabla
; directa, sin puntero previo. Offset 0-3 nunca se lee (direccion
; nunca vale 0). Un unico sprite fijo por direccion (sin animacion de
; 2 fotogramas como en TABLA_ANIMACION_PELMAZOIDE): derecha=$27,
; izquierda=$A7 ($27 con bit7, volteo horizontal -- mismo patron,
; reutiliza el sprite de la derecha), abajo=$25, arriba=$26. ---
TABLA_ANIMACION_MARICOCO:                 ; $5487
    DB $27,$27,$27,$27               ; offset 0-3: nunca se lee (direccion nunca vale 0)
    DB $27,$27,$27,$27               ; offset 4-7: DERECHA (direccion=1)
    DB $A7,$A7,$A7,$A7               ; offset 8-11: IZQUIERDA (direccion=2) -- $27 con bit7
    DB $25,$25,$25,$25               ; offset 12-15: ABAJO (direccion=3)
    DB $26,$26,$26,$26               ; offset 16-19: ARRIBA (direccion=4)

TABLA_ITEMS_MARICOCO:                      ; $549B -- tabla activa tipo 1 (2 entradas x 7 bytes,
    ; formato [X,Y,modo/plantado,dir,subX,subY,fase], mismo que
    ; TABLA_ITEMS_PELMAZOIDE/TABLA_ITEMS_REGPUNANTOSO -- valores de
    ; compilacion, se reinicializan en INICIALIZAR_ITEMS_NIVEL)
    DB 32,16,1,1,0,0,1  ; X,Y=semilla(sobrescrita) modo/plantado=1 dir=1 subX,subY=0 fase=1
    DB 32,16,1,1,0,0,1

; --- Manejador tipo 1 = MARIQUITA (CONFIRMADO: sprites $27/$25/$26 =
; SPR39_MARIQUITA_DER/SPR37_MARIQUITA_ABAJO/SPR38_MARIQUITA_ARRIBA del
; catalogo ya identificado por el usuario -- coincide con "mariquita
; reponia bolas" ya documentado). El contador de entradas (B) sale de
; ($2BFC) = offset 9 del registro de nivel copiado a RAM de trabajo
; (candidato fuerte: "numero de items tipo 1 en este nivel"). Por cada
; entrada activa: si su posicion y la de la camara estan ambas
; alineadas a loseta, comprueba si la loseta que hay debajo (tras
; limpiar el bit 7 "comida") es una de suelo_sin_bola_1/2/3 (indices
; 63-65 = bolita ya comida) -- candidato fuerte a "aparecer solo sobre
; huecos de bolitas ya comidas" (bonus tipo fruta de Pac-Man). Con
; MOTOR_MOVIMIENTO_ITEM valida la posicion/direccion, dibuja el item con
; MOTOR_ACTORES, y fija (IX+2)=1 -- lo que a partir de ahi hace que
; MOTOR_MOVIMIENTO_ITEM/CONSULTAR_LOSETA_LIBRE_DIRECCION dejen de recalcularle direccion (queda
; "plantado" en su sitio en vez de perseguir nada). Si el item esta
; visible en camara Y estaba sobre una loseta ya comida, decrementa el
; contador de fin de nivel ($2C08) y encola un efecto via APILAR_PETICION_REDIBUJADO. ---
HNDLR_MARICOCO:
    LD A, (REGISTRO_NIVEL_CONTADOR_MARICOCOS)
    AND A
    RET Z
    LD B, A
    LD IX, TABLA_ITEMS_MARICOCO
BUCLE_MARICOCO:
    PUSH BC
    LD C, (IX+0)
    LD B, (IX+1)
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)
    LD A, B
    OR C
    OR H
    OR L
    AND $03                  ; posicion del item Y de la camara alineadas a loseta (ambas)?
    JR NZ, .SIN_REGENERAR_MARICOCO
    CALL MAPEAR_COORDENADA_A_DIRECCION_LOCAL
    LD A, (HL)
    BIT 7, A                 ; bit7 = loseta ya "comida"
    JR Z, .SIN_REGENERAR_MARICOCO
    RES 7, A
    SUB $3F                  ; indice de loseta - $3F(63)...
    JR C, .SIN_REGENERAR_MARICOCO
    CP $03
    JR NC, .SIN_REGENERAR_MARICOCO             ; ...fuera de 63-65 (suelo_sin_bola) -> no cuenta
    ADD A, $2D                    ; dentro de rango -> valor a guardar en el scratch de mas abajo
    JR .GUARDAR_ESTADO_REGENERACION
.SIN_REGENERAR_MARICOCO:
    XOR A                    ; no cumple alineamiento o no es suelo_sin_bola -> valor 0
.GUARDAR_ESTADO_REGENERACION:
    LD (ESTADO_REGENERACION_MARICOCO), A             ; "esta entrada esta sobre un hueco de bolita comida"
    LD (VRAM_REGENERACION_MARICOCO), HL              ; direccion VRAM de esa posicion
    PUSH BC
    CALL MOTOR_MOVIMIENTO_ITEM                      ; ver cabecera mas abajo
    POP HL
    JR C, SIGUIENTE_MARICOCO               ; posicion no valida (fuera de rango) -> siguiente entrada
    PUSH HL
    PUSH DE
    LD DE, TABLA_ANIMACION_MARICOCO
    LD A, (IX+6)
    INC A
    AND $03
    LD (IX+6), A
    LD L, A
    LD A, C
    ADD A, A
    ADD A, A
    ADD A, L
    LD L, A
    LD H, $00
    ADD HL, DE
    LD A, (HL)
    LD D, A
    AND $7F
    LD B, A
    LD A, D
    AND $80                  ; bit7 = candidato a volteo horizontal (aparcado, ver MOTOR_ACTORES)
    POP DE
    PUSH IX
    CALL MOTOR_ACTORES                       ; MOTOR_ACTORES -- dibuja el item en su posicion
    POP IX
    LD (IX+2), $01              ; a partir de ahora "plantado" (ver cabecera de esta funcion)
    CALL ACTIVAR_EFECTO_ITEM           ; comprueba colision con el comecocos en esta posicion
    POP DE
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)
    RES 7, H
    RES 7, L
; --- Comprueba que la posicion cae dentro de la rejilla visible en
; pantalla (ancho $0C=12, alto $09=9 losetas); si es asi Y la loseta
; de debajo era suelo_sin_bola ((ESTADO_REGENERACION_MARICOCO)!=0, ver
; arriba): REGENERA la bolita -- escribe de vuelta el indice de
; suelo_con_bola (45-47) en la VRAM guardada en
; (VRAM_REGENERACION_MARICOCO), decrementa el contador de fin de nivel
; ($2C08, porque ahora vuelve a haber una bolita pendiente de comer) y
; encola el efecto (APILAR_PETICION_REDIBUJADO) con evento EVENTO_SONIDO_PENDIENTE=5. ---
    LD A, E
    SUB L
    AND $7C
    RRCA
    RRCA
    LD C, A
    CP $0C
    JR NC, SIGUIENTE_MARICOCO           ; fuera de la anchura visible -> no regenera
    LD A, D
    SUB H
    AND $7C
    RRCA
    RRCA
    LD B, A
    CP $09
    JR NC, SIGUIENTE_MARICOCO           ; fuera de la altura visible -> no regenera
    LD A, (ESTADO_REGENERACION_MARICOCO)
    AND A
    JR Z, SIGUIENTE_MARICOCO            ; no estaba sobre un hueco de bolita comida -> nada que regenerar
    LD HL, CONTADOR_BOLAS_COMIDAS
    DEC (HL)
    LD HL, (VRAM_REGENERACION_MARICOCO)
    LD (HL), A                 ; reescribe la loseta como suelo_con_bola (45-47)
    CALL APILAR_PETICION_REDIBUJADO                        ; APILAR_PETICION_REDIBUJADO (madmix1.asm, identificado)
    LD A, $05
    LD (EVENTO_SONIDO_PENDIENTE), A                      ; marcador de evento/sonido (indice 5)
SIGUIENTE_MARICOCO:
    LD BC, $0007
    ADD IX, BC
    POP BC
    DEC B
    JP NZ, BUCLE_MARICOCO
    RET

ESTADO_REGENERACION_MARICOCO:              ; scratch de la instancia 1, compila a cero
    DB 0
VRAM_REGENERACION_MARICOCO:
    DW 0

; --- Helper local identico en formula a MAPEAR_COORDENADA_A_DIRECCION ($545F), pero
; copia independiente (no lo reutiliza).
;
; BUG CORREGIDO (ver madmix1.asm MAPEAR_LOSETA_A_GRAFICO y FINDINGS.md): la
; v1.0 original tenia $FC60 aqui tambien -- otro de los 5 sitios del
; bug del contador de bolitas del nivel 13. Fix de la v2.0 aplicado:
; $FC60 -> $FC50. ---
MAPEAR_COORDENADA_A_DIRECCION_LOCAL:
    PUSH BC
    LD A, B
    AND $7C
    RRCA
    RRCA
    LD B, A
    LD A, C
    AND $7C
    RLCA
    RR B
    RRA
    RR B
    RRA
    RR B
    RRA
    LD C, A
    LD HL, $FC50            ; BUG CORREGIDO: $FC60 en la v1.0 original, ver comentario arriba
    ADD HL, BC
    POP BC
    RET

; --- TABLA_ANIMACION_REGPUNANTOSO: mismo mecanismo que TABLA_ANIMACION_MARICOCO
; (indexada por HNDLR_REGPUNANTOSO como direccion(1-4)*4+fase(0-3), sin
; autorreferencia). A diferencia de TABLA_ITEMS_MARICOCO/TABLA_ANIMACION_PELMAZOIDE
; (2 sprites repetidos por pareja), aqui cada direccion SI anima en
; ciclo de 4 fotogramas reales (fase 0,1,2,3 -> sprites distintos):
; derecha=$2F,$2E,$2D,$2E; izquierda=$AF,$AE,$AD,$AE (los mismos 3
; sprites de la derecha con bit7, volteo horizontal); abajo=$32,$31,
; $30,$31; arriba=$33,$34,$35,$34. ---
TABLA_ANIMACION_REGPUNANTOSO:                  ; $5574
    DB $2F,$2E,$2D,$2E               ; offset 0-3: nunca se lee (direccion nunca vale 0)
    DB $2F,$2E,$2D,$2E               ; offset 4-7: DERECHA (direccion=1), 4 fotogramas reales
    DB $AF,$AE,$AD,$AE               ; offset 8-11: IZQUIERDA (direccion=2) -- misma animacion con bit7
    DB $32,$31,$30,$31               ; offset 12-15: ABAJO (direccion=3)
    DB $33,$34,$35,$34               ; offset 16-19: ARRIBA (direccion=4)

TABLA_ITEMS_REGPUNANTOSO:                       ; $5588 -- tabla activa tipo 2 (8 entradas x 7 bytes,
    ; formato [X,Y,modo/plantado,dir,subX,subY,fase], mismo que
    ; TABLA_ITEMS_PELMAZOIDE/TABLA_ITEMS_MARICOCO -- valores de
    ; compilacion, se reinicializan en INICIALIZAR_ITEMS_NIVEL)
    DB 32,16,2,1,0,0,1  ; X,Y=semilla(sobrescrita) modo/plantado=2 dir=1 subX,subY=0 fase=1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1
    DB 32,16,2,1,0,0,1

; --- Manejador tipo 2 = "REPUGNANTOSO" (CONFIRMADO: sprites $2D-$2F/
; $30-$32/$33-$35 = SPR45-53_REPUGNANTE_DER/ABAJO/ARRIBA del catalogo
; ya identificado por el usuario -- coincide con "apisonadora, las
; aplastaba" ya documentado). El contador (B) sale de ($2BFD) = offset
; 10 del registro de nivel. Estructura identica a HNDLR_MARICOCO, pero
; con el efecto CONTRARIO sobre las losetas: mientras la mariquita
; regenera bolitas ya comidas (suelo_sin_bola 63-65 -> suelo_con_bola
; 45-47), el repugnantoso busca bolitas normales SIN comer (bit7
; limpio, indices 45-47) y las convierte en bolas CLAVADAS/fijas
; (indices 48-50) -- es el manejador que "planta" bolas clavadas
; nuevas en el mapa, en vez de liberar las existentes (eso lo hace el
; modo especial "herramienta", ver HNDLR_BOLITA_CLAVADA). Marca
; (IX+2)=2 nada mas entrar al bucle (no al final, a diferencia de la
; mariquita) y usa el marcador de evento EVENTO_SONIDO_PENDIENTE=6 en vez de $05. ---
HNDLR_REGPUNANTOSO:
    LD A, (REGISTRO_NIVEL_CONTADOR_REPUGNANTOSOS)
    AND A
    RET Z
    LD B, A
    LD IX, TABLA_ITEMS_REGPUNANTOSO
BUCLE_REGPUNANTOSO:
    PUSH BC
    LD (IX+2), $02
    LD C, (IX+0)
    LD B, (IX+1)
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)
    LD A, B
    OR C
    OR H
    OR L
    AND $03                  ; posicion del item Y de la camara alineadas a loseta (ambas)?
    JR NZ, .SIN_PLANTAR_REGPUNANTOSO
    CALL MAPEAR_COORDENADA_A_DIRECCION_LOCAL
    LD A, (HL)
    BIT 7, A                 ; bit7 = loseta ya "comida" -- aqui se exige LO CONTRARIO que en
    JR NZ, .SIN_PLANTAR_REGPUNANTOSO             ; la instancia 1: debe estar SIN comer
    SUB $2D                  ; indice de loseta - $2D(45)...
    JR C, .SIN_PLANTAR_REGPUNANTOSO
    CP $03
    JR NC, .SIN_PLANTAR_REGPUNANTOSO             ; ...fuera de 45-47 (suelo_con_bola) -> no cuenta
    ADD A, $30                    ; dentro de rango -> +$30 = 48-50 (suelo_con_bola_clavada)
    JR .GUARDAR_ESTADO_PLANTADO
.SIN_PLANTAR_REGPUNANTOSO:
    XOR A                    ; no cumple alineamiento o no es suelo_con_bola -> valor 0
.GUARDAR_ESTADO_PLANTADO:
    LD (ESTADO_PLANTADO_REGPUNANTOSO), A             ; "hay una bolita normal para clavar aqui"
    LD (VRAM_PLANTADO_REGPUNANTOSO), HL              ; direccion VRAM de esa posicion
    PUSH BC
    CALL MOTOR_MOVIMIENTO_ITEM                       ; mismo que la mariquita (HNDLR_MARICOCO)
    POP HL
    JR C, SIGUIENTE_REGPUNANTOSO
    PUSH HL
    PUSH DE
    LD DE, TABLA_ANIMACION_REGPUNANTOSO
    LD A, (IX+6)
    INC A
    AND $03
    LD (IX+6), A
    LD L, A
    LD A, C
    ADD A, A
    ADD A, A
    ADD A, L
    LD L, A
    LD H, $00
    ADD HL, DE
    LD A, (HL)
    LD D, A
    AND $7F
    LD B, A
    LD A, D
    AND $80
    POP DE
    PUSH IX
    CALL MOTOR_ACTORES                        ; MOTOR_ACTORES -- dibuja el item en su posicion
    POP IX
    CALL ACTIVAR_EFECTO_ITEM           ; comprueba colision con el comecocos en esta posicion
    POP DE
    LD HL, (REGISTRO_NIVEL_POSICION_COMECOCOS)
    RES 7, H
    RES 7, L
; --- Igual que la instancia 1: comprueba rejilla visible ($0C x $09
; losetas) y, si estaba sobre una bolita normal
; ((ESTADO_PLANTADO_REGPUNANTOSO)!=0), la
; convierte de verdad en bola clavada -- a diferencia de la instancia
; 1, aqui NO se toca ($2C08) (plantar una bola clavada no cambia
; cuantas bolitas quedan por comer, solo las "congela" hasta que se
; liberen con el modo herramienta). ---
    LD A, E
    SUB L
    AND $7C
    RRCA
    RRCA
    LD C, A
    CP $0C
    JR NC, SIGUIENTE_REGPUNANTOSO           ; fuera de la anchura visible -> no planta
    LD A, D
    SUB H
    AND $7C
    RRCA
    RRCA
    LD B, A
    CP $09
    JR NC, SIGUIENTE_REGPUNANTOSO           ; fuera de la altura visible -> no planta
    LD A, (ESTADO_PLANTADO_REGPUNANTOSO)
    AND A
    JR Z, SIGUIENTE_REGPUNANTOSO            ; no estaba sobre una bolita normal -> nada que plantar
    LD HL, (VRAM_PLANTADO_REGPUNANTOSO)
    LD (HL), A                 ; reescribe la loseta como suelo_con_bola_clavada (48-50)
    CALL APILAR_PETICION_REDIBUJADO                         ; APILAR_PETICION_REDIBUJADO (madmix1.asm, identificado, mismo que la instancia 1)
    LD A, $06
    LD (EVENTO_SONIDO_PENDIENTE), A                        ; marcador de evento/sonido (indice 6)
SIGUIENTE_REGPUNANTOSO:
    LD BC, $0007
    ADD IX, BC
    POP BC
    DEC B
    JP NZ, BUCLE_REGPUNANTOSO
    RET

ESTADO_PLANTADO_REGPUNANTOSO:               ; scratch de la instancia 2, compila a cero
    DB 0
VRAM_PLANTADO_REGPUNANTOSO:
    DW 0

; --- Manejador de "pista" (tanque/avion, ver graficos.html) --
; comprueba 3 entradas de una tabla en $2C2E (fuera de este fichero,
; RAM de trabajo) contra la posicion del comecocos con margenes
; asimetricos (+-4/+-12 filas, +-8/+-20 columnas segun un flag). Si
; coincide, llama a ARMAR_AVISO_DESTELLO con C=$4D y anota EVENTO_SONIDO_PENDIENTE=$07. --
AVISAR_PROXIMIDAD_PISTA:                 ; $566A
    PUSH IX
    PUSH DE
    EXX                       ; DE' = posicion del comecocos (pasada por el llamador en DE)
    POP DE
    EXX
    LD B, $03
    LD HL, TABLA_PISTA_TANQUE_AVION
.BUCLE_PISTA:
; --- Decodifica la entrada de $2C2E igual que el bucle de pista
; de MOTOR_MOVIMIENTO_COLISION (BUCLE_PISTA_TANQUE_AVION): byte0=activa, byte1 bit0/bit7 seleccionan
; el mismo formato de posicion de dos sub-tipos -- aqui solo para
; CALCULAR la posicion (D/E), no para dibujar nada todavia. ---
    PUSH BC
    LD A, (HL)
    AND A
    JR Z, .SIGUIENTE_PISTA              ; entrada vacia -> siguiente
    INC HL
    LD D, (HL)
    BIT 0, D
    JR Z, .FORMATO_B
    DEC HL
    SUB $10
    LD D, A
    LD E, $40
    JR NC, .COMPROBAR_MARGEN_PISTA
    JR .SIGUIENTE_PISTA                   ; fuera de rango -> siguiente (no borra la entrada, a
                                    ; diferencia del bucle de pista de dibujado)
.FORMATO_B:
    BIT 7, (HL)
    DEC HL
    JR Z, .FORMATO_B_POS
    SUB $08
    LD E, A
    JR .FILA_FIJA
.FORMATO_B_POS:
    ADD A, $08
    LD E, A
    JR .FILA_FIJA
.FILA_FIJA:
    LD E, A
    LD D, $38
.COMPROBAR_MARGEN_PISTA:
; --- Con la posicion de la pista (D,E) ya calculada, comprueba si el
; comecocos (BC, recuperado de DE') esta dentro de un margen
; ASIMETRICO alrededor de ella: columna en [-4,+12), fila en [-8,+20)
; -- una zona de "aviso" mas amplia que la propia loseta, para
; detectar la proximidad ANTES de pisarla de verdad. Si esta dentro,
; llama a ARMAR_AVISO_DESTELLO (arma un aviso/pista en TABLA_RANURAS_AVISO)
; y marca evento EVENTO_SONIDO_PENDIENTE=7. ---
    EXX
    PUSH DE
    EXX
    POP BC
    LD A, C
    ADD A, $FC
    CP E
    JR NC, .SIGUIENTE_PISTA           ; fuera del margen de columna por un lado
    ADD A, $0C
    CP E
    JR C, .SIGUIENTE_PISTA              ; fuera del margen de columna por el otro
    LD A, B
    ADD A, $F8
    CP D
    JR NC, .SIGUIENTE_PISTA           ; fuera del margen de fila por un lado
    ADD A, $14
    CP D
    JR C, .SIGUIENTE_PISTA              ; fuera del margen de fila por el otro
    PUSH HL
    LD C, EFECTOS_DESTELLO_SEQ_B_TAIL - ITEM_TABLE_EFECTOS_DESTELLO   ; solo el flash corto de cierre
    CALL ARMAR_AVISO_DESTELLO
    LD A, $07
    LD (EVENTO_SONIDO_PENDIENTE), A
    POP HL
.SIGUIENTE_PISTA:
    INC HL
    INC HL
    POP BC
    DJNZ .BUCLE_PISTA
    POP IX
    RET

; --- Helper compartido: limpia las 4 entradas de TABLA_RANURAS_AVISO (paso 2) y,
; si (HL) sigue vacio, guarda el marcador C (offset de entrada a
; ITEM_TABLE_EFECTOS_DESTELLO, ver su cabecera). CORREGIDO -- el bit7 de C estaba
; descrito al reves: bit7 PUESTO (solo en las 2 llamadas de ACTIVAR_EFECTO_ITEM.INICIAR_MODO_ESPECIAL,
; $AD/$A7 -- "activar modo especial") sale ya, SIN guardar posicion;
; bit7 LIMPIO (AVISAR_PROXIMIDAD_PISTA, ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO1, ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO2) SI continua y
; guarda la posicion actual (IX+0/1) en esta entrada, reubicando
; ademas (IX+0/1) a la posicion inicial del comecocos y reseteando
; $2C0C. Llamado desde AVISAR_PROXIMIDAD_PISTA y desde ACTIVAR_EFECTO_ITEM. ---
ARMAR_AVISO_DESTELLO:                 ; $56CA
    LD HL, TABLA_RANURAS_AVISO
    LD B, $04
.BUCLE_RANURA_AVISO:
    LD A, (HL)
    AND A
    JR NZ, .SIGUIENTE_RANURA_AVISO            ; entrada ocupada -> prueba la siguiente de las 4
    LD (HL), C                  ; entrada libre: guarda el marcador (C)
    BIT 7, C
    RET NZ                        ; bit7 puesto (ACTIVAR_EFECTO_ITEM.INICIAR_MODO_ESPECIAL) -> ya esta, sale sin guardar posicion
    INC HL                          ; bit7 limpio (AVISAR_PROXIMIDAD_PISTA/ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO1/.SUMAR_PUNTOS_MODO2): ademas guarda la
    LD A, (IX+0)                     ; posicion actual (IX+0/1) en esta entrada...
    LD (HL), A
    INC HL
    LD A, (IX+1)
    LD (HL), A
    LD HL, (REGISTRO_NIVEL_FILA_COLUMNA)                     ; ...y reubica (IX+0/1) a la posicion inicial del comecocos
    LD (IX+0), L                         ; ($2C00), reiniciando el temporizador de parpadeo ($2C0C)
    LD (IX+1), H
    XOR A
    LD (TEMPORIZADOR_PARPADEO_BOLA), A
    RET
.SIGUIENTE_RANURA_AVISO:
    INC HL
    INC HL
    INC HL
    DJNZ .BUCLE_RANURA_AVISO
    RET

; --- $56F5-$5772 (126 bytes): 3 secuencias de animacion "extra" para
; ACTUALIZAR_DESTELLO_ITEMS, cada una terminada en centinela $FF. Mecanismo
; RESUELTO: cada llamador de ARMAR_AVISO_DESTELLO pasa en C un valor
; cuyos 7 bits bajos (AND $7F) son el OFFSET DE ENTRADA dentro de esta
; tabla -- no un contador generico. Eso permite que cada evento entre
; en un punto distinto de la MISMA secuencia: bien desde el principio
; (animacion larga) o saltando directo a la cola comun de cierre
; (`$28,$28,$29,$29,$2A,$2B[,$2C]` -- esquinas/uniones de muro de
; ladrillo, losetas 40-44 del catalogo, compartidas por las 3
; secuencias) para un "flash" corto. ACTUALIZAR_DESTELLO_ITEMS dibuja con
; MOTOR_ACTORES (motor de sprites, no el sistema de losetas del mapa)
; la loseta en la posicion de entrada actual, y si la SIGUIENTE
; posicion es $FF, reinicia la entrada a offset 0.
;
; IDENTIDAD DE LAS LOSETAS (cruzadas contra data/tiles/*.til):
; secuencia A = flecha_derecha(54)+cierre+linea_electrica_puerta_
; fantasmas(56); secuencia B = (tramo sin descifrar)+ciclo pista_
; avion(58)/item_suelo(59)/bola_poder(60)/hipopotamo(61)+cierre;
; secuencia C = item_herramienta(62)+cierre+pista_tanque(55).
; HIPOTESIS FUERTE (no confirmada visualmente): parece un "flash" de
; celebracion que dibuja iconos reales del catalogo con el motor de
; sprites en vez de una animacion decorativa inventada -- la
; secuencia B en concreto cicla justo por los 4 iconos de item/power-
; up al activarse un modo especial (ver EFECTOS_DESTELLO_SEQ_B_MAIN, llamada
; desde ACTIVAR_EFECTO_ITEM.INICIAR_MODO_ESPECIAL).
;
; Puntos de entrada reales (valor de C en cada CALL ARMAR_AVISO_DESTELLO
; encontrado en el codigo, ver las etiquetas mas abajo):
;   $01 -> EFECTOS_DESTELLO_SEQ_A       (ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO2, secuencia A casi completa)
;   $17 -> EFECTOS_DESTELLO_SEQ_A_TAIL  (ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO1/.SUMAR_PUNTOS_MODO2, solo el cierre de A)
;   $A7 -> EFECTOS_DESTELLO_SEQ_B_ENTRY (ACTIVAR_EFECTO_ITEM.INICIAR_MODO_ESPECIAL, item=hipopotamo -- ver dualidad abajo)
;   $AD -> EFECTOS_DESTELLO_SEQ_B_MAIN  (ACTIVAR_EFECTO_ITEM.INICIAR_MODO_ESPECIAL, resto de items -- secuencia B desde el ciclo de iconos)
;   $4D -> EFECTOS_DESTELLO_SEQ_B_TAIL  (AVISAR_PROXIMIDAD_PISTA, solo el cierre de B -- el flash mas corto)
;   $55 -> EFECTOS_DESTELLO_SEQ_C       (ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO2, secuencia C completa)
;   $6D -> EFECTOS_DESTELLO_SEQ_C_TAIL  (ACTIVAR_EFECTO_ITEM.SUMAR_PUNTOS_MODO1/.SUMAR_PUNTOS_MODO2, solo el cierre de C)
;
; TRUCO DE AHORRO DE MEMORIA: el $FF que cierra la secuencia A
; (offset 39) se REUTILIZA a proposito como punto de entrada valido a
; la secuencia B (entrada $A7) -- funciona porque ACTUALIZAR_DESTELLO_ITEMS solo
; comprueba "es $FF" en el byte SIGUIENTE al que dibuja, nunca en el
; actual, asi que el mismo byte sirve de centinela de fin (si se llega
; por incremento normal) y de arranque legitimo (si se salta ahi
; directo). El tramo `$0F,$8D,$0E,$0D,$0F` justo despues (offset
; 40-44) sigue sin descifrar -- no encaja con el patron de "loseta
; repetida" del resto de la tabla. ---
ITEM_TABLE_EFECTOS_DESTELLO:
    DB $00                     ; offset 0: sin punto de entrada conocido
EFECTOS_DESTELLO_SEQ_A:              ; offset 1 -- entrada real ($01)
    DB $36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36,$36  ; flecha_derecha x22
EFECTOS_DESTELLO_SEQ_A_TAIL:         ; offset 23 -- entrada real ($17)
    DB $28,$28,$29,$29,$2A,$2B                        ; cierre comun (esquinas/uniones de muro de ladrillo)
    DB $38,$38,$38,$38,$38,$38,$38,$38,$38,$38         ; linea_electrica_puerta_fantasmas_a x10
EFECTOS_DESTELLO_SEQ_B_ENTRY:        ; offset 39 -- entrada real ($A7); TAMBIEN el $FF que cierra la
                               ; secuencia A (ver "truco de ahorro de memoria" arriba)
    DB $FF
    DB $0F,$8D,$0E,$0D,$0F      ; offset 40-44: sin descifrar, no encaja con el patron de loseta repetida
EFECTOS_DESTELLO_SEQ_B_MAIN:         ; offset 45 -- entrada real ($AD)
    DB $03,$00,$06,$80,$03,$00,$06,$80,$03,$00,$06,$80,$03,$00,$06,$80,$03,$00,$06,$80,$03,$00,$06,$80  ; patron repetido, sin descifrar
    DB $3A,$3A,$3B,$3B,$3C,$3C,$3D,$3D                 ; ciclo: pista_avion/item_suelo/bola_poder/hipopotamo
EFECTOS_DESTELLO_SEQ_B_TAIL:         ; offset 77 -- entrada real ($4D)
    DB $28,$28,$29,$29,$2A,$2B,$2C                      ; cierre comun (esquinas/uniones de muro de ladrillo)
    DB $FF                     ; fin real de la secuencia B
EFECTOS_DESTELLO_SEQ_C:              ; offset 85 -- entrada real ($55)
    DB $3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E  ; item_herramienta x24
EFECTOS_DESTELLO_SEQ_C_TAIL:         ; offset 109 -- entrada real ($6D)
    DB $28,$28,$29,$29,$2A,$2B                         ; cierre comun (esquinas/uniones de muro de ladrillo)
    DB $37,$37,$37,$37,$37,$37,$37,$37,$37,$37          ; pista_tanque_vertical x10
    DB $FF                     ; fin real de la secuencia C

    ; $5773-$5781: la zona de trabajo RAM ya conocida (compartida con
    ; MADMIX1.BIN, que la limpia tambien desde $58D9 de ese fichero).
    ; Compila a cero. Los primeros 8 bytes son TABLA_RANURAS_AVISO (4
    ; entradas x 2 bytes); los 7 restantes ($577B-$5781) no tienen
    ; consumidor confirmado dentro de este fichero.
TABLA_RANURAS_AVISO:
    DB 0,0,0,0,0,0,0,0
    DB 0,0,0,0,0,0,0

; --- Temporizador de items activos: recorre las 4 "entradas activas"
; de TABLA_RANURAS_AVISO (2 bytes/entrada, IX autoincrementado) y para cada una no
; vacia hace parpadear/reduce su cuenta, con un offset extra en la
; tabla $56F5 (via IX-1) para decidir la loseta segun $2C0F. ---
ACTUALIZAR_DESTELLO_ITEMS:                    ; $5782
    LD B, 4                      ; 4 entradas activas en TABLA_RANURAS_AVISO
    LD IX, TABLA_RANURAS_AVISO
.BUCLE_DESTELLO:
    PUSH BC
    LD A, (IX+0)             ; byte0 de la entrada: flag/marcador (0 = vacia)
    INC IX
    AND A
    JP Z, .SIGUIENTE_DESTELLO              ; entrada vacia -> siguiente
    INC (IX-1)                    ; byte1: cuenta/fase, se incrementa cada tick
    AND $7F                      ; descarta el bit7 (flag adicional aparte, ver .DIBUJAR_FRAME_DESTELLO)
    LD C, A
    LD A, (MODO_ESPECIAL_ACTIVO)              ; temporizador de modo especial activo?
    AND A
    JR Z, .CALCULAR_POSICION_DESTELLO
    BIT 7, (IX-1)                ; con modo activo, sub-formato segun bit7 del byte1
    LD D, 56                     ; posicion VRAM fija (fila/columna), centro exacto de la ventana
    LD E, 64                     ; que comprueba ACTIVAR_EFECTO_ITEM ([50,62)/[60,68))
    JR NZ, .DIBUJAR_FRAME_DESTELLO                ; ya tiene posicion fija (D/E) -> se salta CALCULAR_POSICION_VRAM_ITEM
.CALCULAR_POSICION_DESTELLO:
    CALL CALCULAR_POSICION_VRAM_ITEM                        ; calcula
    RR B                                ; direccion VRAM (D/E) y mete el carry (fuera de rango) en B
.DIBUJAR_FRAME_DESTELLO:
; --- Indexa ITEM_TABLE_EFECTOS_DESTELLO por la fase (C) para obtener el frame/
; loseta a dibujar (bit7 = flag adicional sin descifrar del todo,
; aparcado -- ver FINDINGS.md) y si termina en $FF (centinela de fin
; de secuencia para esta entrada) la desactiva. Dibuja con
; MOTOR_ACTORES solo si la posicion calculada arriba SI estaba en
; rango (NC). ---
    LD HL, ITEM_TABLE_EFECTOS_DESTELLO
    LD A, C
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD A, (HL)
    AND $80
    RL B
    LD B, (HL)
    RES 7, B
    PUSH IX
    CALL NC, MOTOR_ACTORES                     ; MOTOR_ACTORES (condicional a que la posicion sea valida)
    POP IX
    INC HL
    LD A, (HL)
    CP $FF                    ; centinela de fin de secuencia
    JR NZ, .SIGUIENTE_DESTELLO
    LD (IX-1), $00              ; fin de la secuencia -> reinicia la fase de esta entrada
.SIGUIENTE_DESTELLO:
    INC IX
    INC IX
    POP BC
    DJNZ .BUCLE_DESTELLO
    RET

; --- Efecto asociado a la activacion de un item (llamado desde
; ambos manejadores tras el CALL a MOTOR_ACTORES). Filtra por
; posicion (D/E) dentro de una ventana fija, y por el tipo de item
; leido de ($2C2D); dispara distintos sonidos/animaciones via
; ARMAR_AVISO_DESTELLO y $8D70, o via AVISAR_PROXIMIDAD_PISTA cuando el
; tipo es 3 (pista). ---
ACTIVAR_EFECTO_ITEM:                        ; $57D8
    LD A, (MODO_ESPECIAL_ACTIVO)             ; temporizador de modo especial ya activo -> no repite el
    AND A                       ; efecto (evita retrigger mientras dura)
    RET NZ
; --- Filtra por una ventana fija de posicion VRAM (D en [50,62),
; E en [60,68)) -- candidato a "solo procesa el item si esta cerca
; del centro de pantalla/comecocos"; fuera de rango cae en .DELEGAR_AVISO_PISTA
; (delega en AVISAR_PROXIMIDAD_PISTA en vez de no hacer nada). ---
    LD A, D
    CP 50                         ; ventana de fila [50,62)
    JP C, .DELEGAR_AVISO_PISTA
    CP 62
    JP NC, .DELEGAR_AVISO_PISTA
    LD A, E
    CP 60                         ; ventana de columna [60,68)
    JP C, .DELEGAR_AVISO_PISTA
    CP 68
    JP NC, .DELEGAR_AVISO_PISTA
    LD H, (IX+2)              ; H = flag propio del item, L = modo especial actual
    LD A, (MODO_ESPECIAL)
    LD L, A
    AND A
    JR NZ, .MODO_BOLA_PODER_ACTIVO               ; algun modo activo -> rama especifica de mas abajo
; --- Sin modo especial (o modo 3/herramienta, que reentra aqui via
; .MODO_HERRAMIENTA_ACTIVO): si el item ya estaba "consumido" (H==1) o hay un ciclo de
; demo en curso (($2C1E)/(INDICE_CICLO_NIVELES)), no hace nada. Si no, activa el modo
; especial correspondiente (L==3 -> duracion 40, secuencia B desde el
; ciclo de iconos; L==0 -> duracion 45, secuencia B completa/item=
; hipopotamo) via ($2C0F), arma el aviso (ARMAR_AVISO_DESTELLO), dispara
; evento EVENTO_SONIDO_PENDIENTE=8 y espera activamente a que el gestor de eventos lo
; consuma ((EVENTO_SONIDO_PENDIENTE) vuelve a $FF) antes de marcar el evento final 13. ---
.ACTIVAR_NUEVO_MODO_ESPECIAL:
    LD A, H
    CP 1                          ; H==1: item ya consumido
    JR Z, .DELEGAR_AVISO_PISTA                ; item ya consumido -> nada (AVISAR_PROXIMIDAD_PISTA de fallback)
    LD A, (LADO_APERTURA_TRAMPILLA)
    AND A
    JR NZ, .DELEGAR_AVISO_PISTA                ; ciclo de demo/trampilla en curso -> nada
    LD A, (INDICE_CICLO_NIVELES)
    AND A
    JR NZ, .DELEGAR_AVISO_PISTA                ; ciclador de niveles de muestra activo -> nada
    LD A, L
    CP 3                        ; distingue si venimos del contexto "modo 3" o "sin modo"...
    LD A, 40                     ; duracion del modo especial: 40 frames (contexto "modo 3"/herramienta)
    LD C, (EFECTOS_DESTELLO_SEQ_B_MAIN - ITEM_TABLE_EFECTOS_DESTELLO) | $80   ; secuencia B desde el ciclo de iconos
    JR NZ, .INICIAR_MODO_ESPECIAL
    LD A, 45                     ; duracion del modo especial: 45 frames (item=hipopotamo)
    LD C, (EFECTOS_DESTELLO_SEQ_B_ENTRY - ITEM_TABLE_EFECTOS_DESTELLO) | $80  ; secuencia B completa (item=hipopotamo)
.INICIAR_MODO_ESPECIAL:
    LD (MODO_ESPECIAL_ACTIVO), A              ; activa el temporizador de modo especial con la duracion elegida
    CALL ARMAR_AVISO_DESTELLO
    LD A, 8                      ; marcador de evento/sonido (indice 8: activar modo especial)
    LD (EVENTO_SONIDO_PENDIENTE), A               ; dispara el evento y espera activamente a que se consuma
.ESPERAR_EVENTO:
    LD A, (EVENTO_SONIDO_PENDIENTE)
    CP $FF
    JR NZ, .ESPERAR_EVENTO
    LD A, 13                     ; marcador de evento final (indice 13, ver tabla de comandos/eventos)
    LD (EVENTO_SONIDO_PENDIENTE), A               ; evento final tras el consumo
    RET
; --- Modo especial 1 (bola de poder) activo: si el item ya esta
; consumido (H>=2) no hace nada; si no, suma puntos ($8D70, HL=4
; o 6 segun H) y dispara evento EVENTO_SONIDO_PENDIENTE=7. ---
.MODO_BOLA_PODER_ACTIVO:
    CP 1                          ; modo especial == 1 (bola de poder)
    JR NZ, .MODO_HIPOPOTAMO_ACTIVO               ; modo distinto de 1 -> comprueba el 2
    LD A, H
    CP 2                          ; H>=2: item ya consumido
    JR NC, .DELEGAR_AVISO_PISTA                 ; item ya consumido -> nada
    CP 1                          ; H==1 o H==0: distingue la tabla de puntos a usar
    LD HL, 4                     ; indice/offset de puntos (candidato, ver DIBUJAR_MARCADOR_PUNTOS)
    LD C, EFECTOS_DESTELLO_SEQ_C_TAIL - ITEM_TABLE_EFECTOS_DESTELLO   ; solo el cierre de C
    JR NZ, .SUMAR_PUNTOS_MODO1
    LD HL, 6                     ; indice/offset de puntos (candidato, ver DIBUJAR_MARCADOR_PUNTOS)
    LD C, EFECTOS_DESTELLO_SEQ_A_TAIL - ITEM_TABLE_EFECTOS_DESTELLO   ; solo el cierre de A
.SUMAR_PUNTOS_MODO1:
    CALL DIBUJAR_MARCADOR_PUNTOS                 ; DIBUJAR_MARCADOR_PUNTOS (suma puntos)
    CALL ARMAR_AVISO_DESTELLO
    LD A, 7                      ; marcador de evento/sonido (indice 7: aviso/puntos)
    LD (EVENTO_SONIDO_PENDIENTE), A
    RET
; --- Modo especial 2 (hipopotamo) activo: mismo patron que el modo 1
; pero con su propia tabla de puntos/parametros segun H. ---
.MODO_HIPOPOTAMO_ACTIVO:
    CP 2                          ; modo especial == 2 (hipopotamo)
    JR NZ, .MODO_HERRAMIENTA_ACTIVO               ; modo distinto de 2 -> solo queda el 3 (rama de abajo)
    LD A, H
    CP 1                          ; H==1: variante corta
    LD HL, 6                     ; indice/offset de puntos (candidato, ver DIBUJAR_MARCADOR_PUNTOS)
    LD C, EFECTOS_DESTELLO_SEQ_A_TAIL - ITEM_TABLE_EFECTOS_DESTELLO   ; solo el cierre de A
    JR Z, .SUMAR_PUNTOS_MODO2
    LD C, EFECTOS_DESTELLO_SEQ_C - ITEM_TABLE_EFECTOS_DESTELLO        ; secuencia C completa
    LD HL, 4                     ; indice/offset de puntos (candidato, ver DIBUJAR_MARCADOR_PUNTOS)
    JR C, .SUMAR_PUNTOS_MODO2
    LD HL, 6                     ; indice/offset de puntos (candidato, ver DIBUJAR_MARCADOR_PUNTOS)
    LD C, EFECTOS_DESTELLO_SEQ_A - ITEM_TABLE_EFECTOS_DESTELLO        ; secuencia A casi completa
.SUMAR_PUNTOS_MODO2:
    CALL DIBUJAR_MARCADOR_PUNTOS                 ; DIBUJAR_MARCADOR_PUNTOS (suma puntos)
    CALL ARMAR_AVISO_DESTELLO
    LD A, 7                      ; marcador de evento/sonido (indice 7: aviso/puntos)
    LD (EVENTO_SONIDO_PENDIENTE), A
    RET
.MODO_HERRAMIENTA_ACTIVO:
    CP 3                       ; modo 3 (herramienta) -> reutiliza el mismo tratamiento
    JP Z, .ACTIVAR_NUEVO_MODO_ESPECIAL                ; que "sin modo especial" (.ACTIVAR_NUEVO_MODO_ESPECIAL, distingue por L)
.DELEGAR_AVISO_PISTA:
    CALL AVISAR_PROXIMIDAD_PISTA   ; fallback: ni hay efecto de item que aplicar, delega en la pista
    RET

; --- Reinicializa al empezar (o recargar) un nivel TODO el estado de
; los items interactivos y flags de movimiento asociados. Concretamente:
;   - TABLA_ITEMS_PELMAZOIDE (8 entradas, fantasmas), TABLA_ITEMS_MARICOCO
;     (2 entradas) e TABLA_ITEMS_REGPUNANTOSO (8 entradas): cada entrada
;     se coloca en la posicion de referencia inicial del nivel
;     (REGISTRO_NIVEL_FILA_COLUMNA) y se limpian sus campos de modo/fase
;     (offsets +4/+5 a 0) -- "vuelven a aparecer" en su sitio de salida.
;   - TABLA_RANURAS_AVISO (4 entradas, 2 bytes cada una): zona de trabajo de
;     ITEM_TABLE_EFECTOS_DESTELLO/ARMAR_AVISO_DESTELLO (secuencias de
;     "flash": aviso de pista, bola de poder, puntos) -- se pone a cero.
;   - DIRECCION_DE_MOVIMIENTO/DIRECCION_FORZADA/TEMPORIZADOR_DIRECCION_FORZADA/TEMPORIZADOR_PARPADEO_BOLA:
;     a 0, salvo que MODO_ESPECIAL=3 (modo "herramienta"), en cuyo caso
;     se fijan a 14.
;   - TABLA_PISTA_TANQUE_AVION (3 entradas, posiciones activas de pista):
;     se limpia tambien -- es lo UNICO que hace el segundo punto de
;     entrada INICIALIZAR_PARCIAL_ITEMS_NIVEL, usado por separado al salir de los modos
;     tanque/avion sin repetir el resto del reseteo.
; Llamada desde CARGAR_NIVEL (CALL $5885). ---
INICIALIZAR_ITEMS_NIVEL:                         ; $5885
    LD IX, TABLA_ITEMS_PELMAZOIDE
    LD BC, (REGISTRO_NIVEL_FILA_COLUMNA)
    LD DE, 7                     ; 7 bytes por entrada
    LD A, 8                      ; 8 entradas (fantasmas)
.BUCLE_RESET_PELMAZOIDE:
    LD (IX+0), C
    LD (IX+1), B
    LD (IX+4), $00
    LD (IX+5), $00
    ADD IX, DE
    DEC A
    JR NZ, .BUCLE_RESET_PELMAZOIDE
    LD IX, TABLA_ITEMS_MARICOCO
    LD A, 2                      ; 2 entradas (mariquita)
.BUCLE_RESET_MARICOCO:
    LD (IX+0), C
    LD (IX+1), B
    LD (IX+4), $00
    LD (IX+5), $00
    ADD IX, DE
    DEC A
    JR NZ, .BUCLE_RESET_MARICOCO
    LD IX, TABLA_ITEMS_REGPUNANTOSO
    LD A, 8                      ; 8 entradas (repugnantoso)
.BUCLE_RESET_REGPUNANTOSO:
    LD (IX+0), C
    LD (IX+1), B
    LD (IX+4), $00
    LD (IX+5), $00
    ADD IX, DE
    DEC A
    JR NZ, .BUCLE_RESET_REGPUNANTOSO
    LD B, 4                      ; 4 entradas de TABLA_RANURAS_AVISO a limpiar
    LD HL, TABLA_RANURAS_AVISO
.LOOP_LIMPIEZA_DESTELLO:
    LD (HL), $00
    INC HL
    INC HL
    DJNZ .LOOP_LIMPIEZA_DESTELLO
    LD A, (MODO_ESPECIAL)
    CP 3
    LD A, 14                     ; valor especial de arranque para el modo 3 (herramienta)
    JR Z, CONTINUAR_RESET_EXCAVATOFONO
    XOR A
CONTINUAR_RESET_EXCAVATOFONO:
    LD (DIRECCION_DE_MOVIMIENTO), A
    LD (DIRECCION_FORZADA), A
    LD (TEMPORIZADOR_DIRECCION_FORZADA), A
    LD (TEMPORIZADOR_PARPADEO_BOLA), A
INICIALIZAR_PARCIAL_ITEMS_NIVEL:                     ; $58F8 -- segundo punto de entrada a
                                    ; INICIALIZAR_ITEMS_NIVEL, llamado desde HNDLR_SUELO_SIN_BOLA
                                    ; (salida de modo tanque) y HNDLR_SUELO_SIN_BOLA_PLANE_LOOP
                                    ; (salida de modo avion) para limpiar solo la
                                    ; tabla $2C2E (ver comentarios en los CALL)
    LD B, 3                      ; 3 entradas de pista tanque/avion
    LD HL, TABLA_PISTA_TANQUE_AVION
.LOOP_LIMPIEZA:
    LD (HL), $00
    INC HL
    INC HL
    DJNZ .LOOP_LIMPIEZA
    RET

    DS $5904-$, $00

; --- Cargador de nivel -- CONFIRMADO por desensamblado, disparado
; desde INICIO (0x8F71+) via CALL $5904. Lee el registro de 20 bytes
; de TABLA_NIVELES segun el nivel actual ($2C07), copia la cabecera
; fija (3 filas) y el cuerpo (filas variables) al buffer de RAM
; $FC60, sustituyendo el tile comodin 0x3C por el valor del campo
; offset 12 del registro, y fija la posicion inicial del comecocos
; ($2C02) desde los offsets 15-16. Ver FINDINGS.md para el detalle
; completo de los 13 bytes de metadatos del registro. ---
CARGAR_NIVEL:
    LD A, (NIVEL_ACTUAL)          ; numero de nivel actual (1-15, el 0 esta muerto -- RESUELTO:
                                    ; el 15 SI se alcanza en partida normal, es el nivel oculto,
                                    ; ver el registro 15 de TABLA_NIVELES mas abajo)
    LD HL, TABLA_NIVELES
    LD BC, 20                    ; 20 bytes por registro
    AND A
    JR Z, .have_record
.mul_loop:
    ADD HL, BC
    DEC A
    JR NZ, .mul_loop
.have_record:
    LD DE, REGISTRO_NIVEL_CUERPO_PTR             ; copia el registro a RAM de trabajo
    LDIR
    LD DE, $FC50              ; DE = buffer de nivel activo -- BUG CORREGIDO: $FC60 en
                              ; la v1.0 original (bug del contador de bolitas del nivel
                              ; 13, fix de la v2.0 aplicado aqui, ver FINDINGS.md/madmix1.asm)
    LD HL, (REGISTRO_NIVEL_CABECERA_PTR)             ; offset 2: puntero a cabecera fija
    LD BC, 96                    ; 96 bytes (3 filas de 32)
    LDIR                          ; copia la cabecera ARRIBA del nivel
    LD A, (REGISTRO_NIVEL_FILAS)                  ; offset 6: filas variables
    LD L, A
    LD H, $00
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                       ; HL = filas * 32
    LD C, L
    LD B, H
    LD HL, (REGISTRO_NIVEL_CUERPO_PTR)                    ; offset 0: puntero al cuerpo del nivel
    LD A, (CONTADOR_VUELTAS_NIVELES)                      ; flag externo (no forma parte del registro)
    AND A
    EXX
    LD D, A
    LD E, $00
    EXX
    JR NZ, .with_wildcard
.plain_copy:
    RES 7, (HL)                         ; limpia el bit "comido"
    LDI
    LD A, B
    OR C
    JR NZ, .plain_copy
    JR .body_done
.with_wildcard:
    RES 7, (HL)
    LD A, (HL)
    LDI
    CP 60                                 ; 60 = tile comodin ($3C)
    JR NZ, .no_substitute
    EXX
    LD A, E
    AND $01
    INC E
    CP D
    EXX
    JR Z, .no_substitute
    LD A, (REGISTRO_NIVEL_LOSETA_COMODIN)                          ; offset 12: tile de sustitucion
    DEC DE
    LD (DE), A
    INC DE
.no_substitute:
    LD A, B
    OR C
    JR NZ, .with_wildcard
.body_done:
    LD HL, (REGISTRO_NIVEL_PIE_PTR)                          ; offset 4: mismo puntero de
                                              ; cabecera, SEGUNDA copia
    LD BC, 96                    ; 96 bytes (3 filas de 32), mismo tamano que la cabecera de arriba
    LDIR                                       ; cabecera ABAJO del nivel
    LD HL, 0
    LD (CONTADOR_BOLAS_COMIDAS), HL
    LD BC, (REGISTRO_NIVEL_FILA_COLUMNA)                              ; offsets 13-14: fila/columna
                                                  ; de referencia inicial
    DEC B
    CALL MAPEAR_COORDENADA_A_DIRECCION                            ; misma formula que
                                                    ; MAPEAR_LOSETA_RELATIVA_A_ABSOLUTA
    LD (POSICION_PARPADEO_BOLA), HL                                  ; guardado para la
                                                      ; animacion de la bola
    XOR A
    LD (MODO_ESPECIAL_ACTIVO), A
    LD (MODO_ESPECIAL), A
    LD (SELECTOR_SPRITE_COMECOCOS), A
    LD (MODO_ESPECIAL_CUENTA_ATRAS), A
    LD (MODO_ESPECIAL_FLAG), A
    LD A, $78
    LD (COLOR_ACTUAL), A
    LD (COLOR_GUARDADO), A
    LD (TABLA_POSICIONES_HUD+18), A
    LD A, (REGISTRO_NIVEL_ICONO_HUD)                                     ; offset 17: icono/digito HUD
    LD (TABLA_POSICIONES_HUD+17), A
    LD HL, $1018
    LD (POSICION_ACTUAL_CAMARA), HL
    CALL INICIALIZAR_ITEMS_NIVEL
    RET

FIN_CARGADOR_NIVEL:
    ; $59A8 (1 byte) - $59A9: cola/alineacion antes de la tabla, si
    ; la hubiera (normalmente 0 bytes, CARGAR_NIVEL deberia terminar
    ; justo en $59A9).
    DS $59A9-$, $00

TABLA_NIVELES:                          ; 320 bytes = exacto 0x59A9-0x5AE9 (16 registros de 20
                                       ; bytes; indice 0 = registro muerto, duplicado del
                                       ; nivel 1). RESUELTO: el juego real tiene 15 niveles,
                                       ; no 14 -- el registro 15 (indice 15, el ultimo) es
                                       ; el NIVEL 15 (CUERPO_L15), alcanzable en
                                       ; juego normal (ver CARGAR_NIVEL y el registro de
                                       ; nivel 15 mas abajo para el detalle completo).
                                       ; Reescrito como tabla de datos nativa (antes INCBIN
                                       ; de niveles_tabla.bin) para que los punteros de
                                       ; cuerpo/cabecera sean etiquetas reales en vez de hex
                                       ; suelto -- el propio ensamblador resuelve la
                                       ; direccion correcta. Ver FINDINGS.md, seccion del
                                       ; registro de nivel, para el detalle de cada campo.
                                       ; 0 diferencias verificado.
; --- nivel 0 (registro muerto, nunca alcanzado) ---
    DW CUERPO_L01, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 22, $00                         ; campo6=filas variables (total filas=3+22=25), campo7 sin identificar
    DB 5, 0, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $30, $34                          ; offsets 13-14: fila/columna de referencia inicial
    DB $18, $2C                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 114                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 1  ---
    DW CUERPO_L01, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 22, $00                         ; campo6=filas variables (total filas=3+22=25), campo7 sin identificar
    DB 5, 0, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $30, $34                          ; offsets 13-14: fila/columna de referencia inicial
    DB $18, $2C                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 114                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 2 ---
    DW CUERPO_L2, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 15, $01                         ; campo6=filas variables (total filas=3+15=18), campo7 sin identificar
    DB 4, 0, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $40                                ; offset 12: tile comodin
    DB $40, $3C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $00                          ; offsets 15-16: sin identificar
    DB $38                                ; offset 17: icono/digito HUD
    DW 147                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 3 ---
    DW CUERPO_L3, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 16, $00                         ; campo6=filas variables (total filas=3+16=19), campo7 sin identificar
    DB 4, 1, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $40, $28                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $08                          ; offsets 15-16: sin identificar
    DB $30                                ; offset 17: icono/digito HUD
    DW 120                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 4 ---
    DW CUERPO_L4, CABECERA_4AFC, CABECERA_4AFC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 15, $00                         ; campo6=filas variables (total filas=3+15=18), campo7 sin identificar
    DB 3, 1, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $3C, $3C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $18                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 79                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 5 ---
    DW CUERPO_L5, CABECERA_4AFC, CABECERA_4AFC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 16, $01                         ; campo6=filas variables (total filas=3+16=19), campo7 sin identificar
    DB 3, 0, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $3C, $3C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $24, $08                          ; offsets 15-16: sin identificar
    DB $38                                ; offset 17: icono/digito HUD
    DW 101                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 6 ---
    DW CUERPO_L6, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 18, $00                         ; campo6=filas variables (total filas=3+18=21), campo7 sin identificar
    DB 3, 0, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $40                                ; offset 12: tile comodin
    DB $40, $18                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $10                          ; offsets 15-16: sin identificar
    DB $38                                ; offset 17: icono/digito HUD
    DW 151                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 7 ---
    DW CUERPO_L7, CABECERA_4AFC, CABECERA_4AFC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 19, $00                         ; campo6=filas variables (total filas=3+19=22), campo7 sin identificar
    DB 3, 0, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 200                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $08, $4C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $F0, $34                          ; offsets 15-16: sin identificar
    DB $60                                ; offset 17: icono/digito HUD
    DW 126                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 8 ---
    DW CUERPO_L8, CABECERA_4B5C, CABECERA_4B5C   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 15, $00                         ; campo6=filas variables (total filas=3+15=18), campo7 sin identificar
    DB 3, 0, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $40, $40                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $18                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 90                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 9 ---
    DW CUERPO_L9, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 18, $00                         ; campo6=filas variables (total filas=3+18=21), campo7 sin identificar
    DB 3, 2, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $40                                ; offset 12: tile comodin
    DB $40, $2C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $24                          ; offsets 15-16: sin identificar
    DB $38                                ; offset 17: icono/digito HUD
    DW 168                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 10 ---
    DW CUERPO_L10, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 17, $00                         ; campo6=filas variables (total filas=3+17=20), campo7 sin identificar
    DB 3, 0, 2                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 50                                 ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $40, $30                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $18                          ; offsets 15-16: sin identificar
    DB $60                                ; offset 17: icono/digito HUD
    DW 116                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 11 ---
    DW CUERPO_L11, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 21, $00                         ; campo6=filas variables (total filas=3+21=24), campo7 sin identificar
    DB 3, 1, 0                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 255                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $40                                ; offset 12: tile comodin
    DB $64, $1C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $08, $28                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 287                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 12 ---
    DW CUERPO_L12, CABECERA_4AFC, CABECERA_4AFC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 19, $01                         ; campo6=filas variables (total filas=3+19=22), campo7 sin identificar
    DB 3, 1, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $41                                ; offset 12: tile comodin
    DB $44, $28                          ; offsets 13-14: fila/columna de referencia inicial
    DB $2C, $10                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 176                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 13 ---
    DW CUERPO_L13_CFA4, CABECERA_4AFC, CABECERA_4AFC   ; cuerpo, cabecera(arriba), cabecera(abajo) -- unificado: CUERPO_L13_CFA4 vive en madmix1_body.asm, resuelto por el propio ensamblador (antes hex literal, sin enlazador entre binarios separados)
    DB 21, $00                         ; campo6=filas variables (total filas=3+21=24), campo7 sin identificar
    DB 2, 0, 3                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 80                                 ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $40, $3C                          ; offsets 13-14: fila/columna de referencia inicial
    DB $28, $24                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 105                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 14 ---
    DW CUERPO_L14_D244, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo) -- unificado: CUERPO_L14_D244 vive en madmix1_body.asm, resuelto por el propio ensamblador (antes hex literal, sin enlazador entre binarios separados)
    DB 23, $01                         ; campo6=filas variables (total filas=3+23=26), campo7 sin identificar
    DB 2, 1, 2                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 250                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $44, $60                          ; offsets 13-14: fila/columna de referencia inicial
    DB $64, $50                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 267                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; --- nivel 15 (OCULTO -- RESUELTO): estos 20 bytes en $5AD5, justo
; despues del registro 14, se documentaban como "datos sin
; identificar". Decodificados con el MISMO formato de campo que el
; resto de registros: campo0/campo2/campo4 apuntan EXACTOS a
; CUERPO_L15/CABECERA_50BC/CABECERA_50BC -- es el registro real del
; nivel oculto (ver hallazgo del 15o laberinto, FINDINGS.md), nunca
; construido a mano, siempre estuvo en el binario original. Y es
; ALCANZABLE en partida normal: CARGAR_NIVEL calcula la direccion
; como TABLA_NIVELES+NIVEL_ACTUAL*20 (sin tope propio), y en VERIFICAR_FIN_NIVEL
; (madmix1_body.asm) el contador de nivel, al completar el 14, hace
; INC (14->15) y compara CP 16 -- como 15 != 16, NO resetea,
; asi que la siguiente carga de nivel usa NIVEL_ACTUAL=15 y lee
; este mismo registro. Solo se resetea a 1 la vez SIGUIENTE (cuando
; llega a 16). El comentario antiguo de CARGAR_NIVEL ("1-14, el 0
; esta muerto") era incompleto -- el rango real es 1-15. ---
    DW CUERPO_L15, CABECERA_50BC, CABECERA_50BC   ; cuerpo, cabecera(arriba), cabecera(abajo)
    DB 18, $01                         ; campo6=filas variables (total filas=3+18=21), campo7 sin identificar
    DB 3, 1, 1                          ; offsets 8/9/10: numero de items tipo 3/1/2
    DB 150                                ; offset 11: duracion del parpadeo de bola/pista especial (fotogramas)
    DB $3F                                ; offset 12: tile comodin
    DB $60, $30                          ; offsets 13-14: fila/columna de referencia inicial
    DB $48, $10                          ; offsets 15-16: sin identificar
    DB $70                                ; offset 17: icono/digito HUD
    DW 165                                ; offsets 18-19: objetivo de bolitas para completar el nivel

; ==============================================================
;  ZONA FINAL $5AE9-$6500: pantalla de REDEFINICION DE TECLAS +
;  CREDITOS + un ciclador de "niveles de muestra". Desensamblado
;  completo con Z80Dasm. Incluye codigo automodificable de verdad
;  (el juego escribe opcodes literales sobre direcciones de codigo
;  en tiempo de ejecucion) y una segunda rutina de reubicacion
;  gemela a la de MADMIX0.BIN. HALLAZGO: la tabla de creditos reales
;  del juego -- texto real, sin "corregir" ortografia: "POGRAMADO
;  BY: RAPHAEL GOMEZZZ..", "GRAPHICOS BY : ROBERTO P.ACEBES",
;  "MUSIC-A BY: COMILONAS", "TOPOSHOW -1988-" (ver TEXTO_CREDITOS_PROGRAMADO_POR
;  mas abajo para el detalle byte a byte).
; ==============================================================

; --- Bucle de introduccion: copia (a si misma, ver comentario) un
; bloque de VRAM/RAM en $4000 hasta 0x46 veces o hasta detectar
; pulsacion de tecla/joystick (COMPROBAR_PULSACION), luego dibuja portada,
; llama al gestor de recursos 3 veces (ids 0/1/2) y espera con timeout.
; RESUELTO: si la tecla es ESC (codigo $EB fila 7), activa un TRUCO
; OCULTO de vidas infinitas (ver .COMPROBAR_TRUCO_VIDAS_INFINITAS mas abajo), no un simple
; reinicio de sonido/pantalla. ---
GESTIONAR_INTRODUCCION:                          ; $5AE9
    CALL PROGRAMAR_APAGADO_PANTALLA               ; apaga pantalla mientras redibuja
    CALL DIBUJAR_CREDITOS
    CALL PROGRAMAR_ENCENDIDO_PANTALLA                  ; vuelve a encenderla
    LD B, 70                     ; 70 iteraciones del bucle de espera (antes de rendirse y mostrar la portada)
.BUCLE_ESPERA_INTRO:
    PUSH BC
    LD HL, $4000
    LD E, L
    LD D, H
    LD C, L
    LD B, H
    LDIR                          ; copia el bloque $4000 sobre si mismo (sin efecto real) -- solo quema tiempo
    POP BC
    XOR A
    CALL COMPROBAR_PULSACION
    JR NZ, .COMPROBAR_TRUCO_VIDAS_INFINITAS
    DJNZ .BUCLE_ESPERA_INTRO
    CALL DIBUJAR_PORTADA          ; = $1000 (reubicada, ver cabecera de DIBUJAR_PORTADA)
    CALL VACIAR_CANALES_SONIDO
    XOR A
    LD DE, GUION_MELODIA_CANAL_0
    CALL INSTALAR_RECURSO_SONIDO   ; indice A=0
    LD A, 1
    LD DE, GUION_MELODIA_CANAL_1
    CALL INSTALAR_RECURSO_SONIDO   ; indice A=1
    LD A, 2
    LD DE, GUION_MELODIA_CANAL_2
    CALL INSTALAR_RECURSO_SONIDO   ; indice A=2
    LD BC, 10000                  ; 10000 frames de timeout antes de volver a la intro
.BUCLE_ESPERA_TIMEOUT:
    PUSH BC
    CALL COMPROBAR_PULSACION
    POP BC
    JR NZ, .CONTINUAR_INTRO
    DEC BC
    EI
    HALT
    LD A, B
    OR C
    JR NZ, .BUCLE_ESPERA_TIMEOUT
; RESUELTO -- truco oculto de VIDAS INFINITAS. $909A es el byte
; operando literal de la instruccion "SUB $01" dentro de la rutina de
; perdida de vida en madmix1.asm (BUCLE_PRINCIPAL_JUEGO: "LD HL,$2C27 / LD A,(HL) /
; SUB $01 / LD (HL),A / JP NC,PREPARAR_INICIO_NIVEL"): escribir 0 ahi la
; convierte en "SUB $00", con lo que perder una vida ya no resta nada
; (ni siquiera activa el acarreo que dispara GAME OVER). El parpadeo
; de borde (color 6, espera, color 1) es solo la confirmacion visual
; de que el codigo se activo -- despues cae en .CONTINUAR_INTRO y el juego
; sigue con normalidad hasta el menu principal.
.COMPROBAR_TRUCO_VIDAS_INFINITAS:
    CP $EB                  ; tecla ESC...
    JR NZ, .CONTINUAR_INTRO
    LD A, C
    CP 7                     ; ...en la fila 7 de la matriz
    JR NZ, .CONTINUAR_INTRO
    XOR A
    LD ($909A), A             ; parchea "SUB $01" (BUCLE_PRINCIPAL_JUEGO) a "SUB $00"
    LD A, $06
    CALL FIJAR_COLOR_BORDE_VDP
    HALT
    HALT
    HALT
    HALT
    LD A, $01
    CALL FIJAR_COLOR_BORDE_VDP
.CONTINUAR_INTRO:
    CALL ESPERAR_TECLA_SOLTADA
    CALL DIBUJAR_MARCO_CARAMELO_VRAM
MOSTRAR_MENU_PRINCIPAL:                            ; segundo punto de entrada a .CONTINUAR_INTRO,
                                     ; saltandose ESPERAR_TECLA_SOLTADA/
                                     ; DIBUJAR_MARCO_CARAMELO_VRAM (no aplican al
                                     ; arranque real) -- llamado desde
                                     ; REINICIAR_PARTIDA en madmix1.asm para
                                     ; mostrar el menu principal al arrancar
                                     ; una partida real
    CALL VACIAR_CANALES_SONIDO
    CALL PROGRAMAR_APAGADO_PANTALLA              ; apaga pantalla mientras redibuja el menu
    CALL LIMPIAR_VRAM_AREA_JUEGO
    CALL APLICAR_COLOR_CICLO_NIVELES
REINICIAR_TIMEOUT_MENU:
    LD BC, $01F4
ACTUALIZAR_MENU_PRINCIPAL:
    LD ($6043), BC
    CALL DIBUJAR_MENU_PRINCIPAL
    CALL PROGRAMAR_ENCENDIDO_PANTALLA                 ; vuelve a encenderla
    CALL LEER_TECLAS_MENU_PRINCIPAL
    LD A, E
    PUSH AF
    LD HL, GESTIONAR_TIMEOUT_MENU.CONTINUAR_TRAS_OPCION
    PUSH HL
    BIT 0, A
    JR Z, DESPACHAR_ACCION_MENU
    POP HL
    POP AF
    CALL RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM
    XOR A
    LD (REGISTRO_NIVEL_ICONO_HUD), A
    LD (COLOR_ACTUAL), A
    CALL WAIT_VBLANK               ; WAIT_VBLANK (madmix1.asm)
    RET

; --- CORREGIDO: pese al nombre, esto NO toca la VRAM -- rellena con
; $FF, en RAM normal, 0x17 (23) de cada 0x20 (32) bytes por fila, en
; 0x90 (144) filas del buffer BUFFER_LOSETAS_TRABAJO (deja 8 bytes/fila sin tocar).
; Es la preparacion del "lienzo" de bitmap en RAM que luego vuelca a
; VRAM ACTUALIZAR_VRAM_FRAME -- ver hallazgo "el buffer BUFFER_LOSETAS_TRABAJO es un
; lienzo de pixeles, no un buffer de tipos de loseta" en FINDINGS.md:
; 144 filas = 9 filas de losetas visibles x 16px, 32 bytes/fila = 256px
; (ancho total de pantalla = 16 losetas), de las cuales 23+1=24 bytes
; (12 losetas) son el area jugable y 8 bytes (4 losetas) quedan bajo
; el marco de caramelo. Llamada solo desde LIMPIAR_VRAM_AREA_JUEGO, en el
; flujo de menu/demo -- este buffer se reutiliza entre menu y
; partida real, no es exclusivo del nivel activo. ---
RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM:                       ; $5B8C
    LD DE, BUFFER_LOSETAS_TRABAJO
    LD B, 144                    ; 144 filas del buffer
.BUCLE_RELLENAR_FILA:
    PUSH BC
    PUSH DE
    LD H, D
    LD L, E
    INC DE
    LD (HL), $FF                 ; byte de relleno solido
    LD BC, 23                    ; 23 de los 32 bytes/fila (area jugable, deja 8 sin tocar)
    LDIR
    POP HL
    LD BC, 32                    ; 32 bytes/fila (avanza a la siguiente fila)
    ADD HL, BC
    EX DE, HL
    POP BC
    DJNZ .BUCLE_RELLENAR_FILA
    RET

; --- Dispatch por bit de A (bits 1/3/4/5) hacia las 4 variantes del
; menu (pausa/disparo entre otras), guardado en pila desde GESTIONAR_INTRODUCCION. ---
DESPACHAR_ACCION_MENU:
    BIT 5, A
    JP NZ, SELECCIONAR_OPCION_DEMO
    BIT 1, A
    JP NZ, SELECCIONAR_OPCION_REDEFINIR_TECLAS
    BIT 3, A
    JP NZ, SELECCIONAR_OPCION_TECLADO
    BIT 4, A
    JP NZ, SELECCIONAR_OPCION_JOYSTICK
GESTIONAR_TIMEOUT_MENU:
    POP HL
.CONTINUAR_TRAS_OPCION:                ; direccion de retorno "trampa": los manejadores de opcion de menu
                                     ; que llegan aqui via RET (no CALL) saltan directo aqui,
                                     ; saltandose el POP HL de arriba (ver ACTUALIZAR_MENU_PRINCIPAL)
    POP AF
    AND A
    JR NZ, REINICIAR_TIMEOUT_MENU
    LD BC, ($6043)
    DEC BC
    LD A, B
    OR C
    JP Z, GESTIONAR_INTRODUCCION
    JR ACTUALIZAR_MENU_PRINCIPAL

; --- Dibuja el menu principal: las 5 lineas de texto de
; TEXTO_MENU_PRINCIPAL ("1 TECLADO", "2 JOYSTICK", "3 REDEFINE TECLAS",
; "4 DEMO", "0 JUGAR") via DIBUJAR_TEXTO_VRAM, direcciones y tamanos
; hardcoded (RENOMBRADO: se llamaba TAIL_KEYMENU_MAIN, nombre que
; confundia con el submenu real de redefinir teclas, TAIL_KEYMENU_
; DRAW mas abajo). ---
DIBUJAR_MENU_PRINCIPAL:                   ; $5BCC
    LD HL, $0548
    LD DE, TEXTO_OPCION_TECLADO
    CALL DIBUJAR_TEXTO_VRAM
    LD HL, $0748
    LD DE, TEXTO_OPCION_JOYSTICK
    CALL DIBUJAR_TEXTO_VRAM
    LD HL, $0B48
    LD DE, TEXTO_OPCION_REDEFINIR_TECLAS
    CALL DIBUJAR_TEXTO_VRAM
    LD HL, $0D48
    LD DE, TEXTO_OPCION_DEMO
    CALL DIBUJAR_TEXTO_VRAM
    LD HL, $1048
    LD DE, TEXTO_OPCION_JUGAR
    JP DIBUJAR_TEXTO_VRAM

    ; $5BF9-$5C39 (65 bytes): 5 registros de texto para
    ; DIBUJAR_MENU_PRINCIPAL: "1 TECLADO", "2 JOYSTICK",
    ; "3 REDEFINE TECLAS", "4 DEMO", "0 JUGAR". Los bytes de atributo
    ; de TEXTO_OPCION_TECLADO/TEXTO_OPCION_JOYSTICK (offset +1) son
    ; precisamente los que las rutinas de abajo automodifican
    ; (alternan $F1/$91) para resaltar la opcion seleccionada.
TEXTO_MENU_PRINCIPAL:
TEXTO_OPCION_TECLADO:
    DB $0B,$F1,"1 TECLADO  "
TEXTO_OPCION_JOYSTICK:
    DB $0C,$91,"2 JOYSTICK  "
TEXTO_OPCION_REDEFINIR_TECLAS:
    DB $11,$31,"3 REDEFINE TECLAS"
TEXTO_OPCION_DEMO:
    DB $06,$C1,"4 DEMO"
TEXTO_OPCION_JUGAR:
    DB $09,$B1,"0 JUGAR  "

; --- Las 4 rutinas de seleccion del menu principal (una por opcion
; alcanzada al mover el cursor), cada una automodifica los 2 bytes
; de atributo de TEXTO_OPCION_TECLADO/TEXTO_OPCION_JOYSTICK (offset +1)
; para resaltar la opcion actual antes de redibujar. ---
SELECCIONAR_OPCION_REDEFINIR_TECLAS:                             ; opcion 3 (redefine teclas)
    CALL DIBUJAR_MENU_REDEFINIR_TECLAS
    LD A, $F1
    LD (TEXTO_OPCION_TECLADO+1), A
    LD A, $91
    LD (TEXTO_OPCION_JOYSTICK+1), A
    LD A, $00
    LD (MODO_ENTRADA), A
    CALL LIMPIAR_VRAM_AREA_JUEGO
    CALL APLICAR_COLOR_CICLO_NIVELES
    RET
SELECCIONAR_OPCION_DEMO:                             ; opcion 4 (demo)
    CALL GESTIONAR_CICLO_NIVELES
    CALL VACIAR_CANALES_SONIDO
    CALL LIMPIAR_VRAM_AREA_JUEGO
    CALL APLICAR_COLOR_CICLO_NIVELES
    RET
SELECCIONAR_OPCION_TECLADO:                             ; opcion 1 (teclado)
    LD A, $01
    LD (MODO_ENTRADA), A
    LD A, $F1
    LD (TEXTO_OPCION_JOYSTICK+1), A
    LD A, $91
    LD (TEXTO_OPCION_TECLADO+1), A
    RET
SELECCIONAR_OPCION_JOYSTICK:                             ; opcion 2 (joystick)
    LD A, $00
    LD (MODO_ENTRADA), A
    LD A, $F1
    LD (TEXTO_OPCION_TECLADO+1), A
    LD A, $91
    LD (TEXTO_OPCION_JOYSTICK+1), A
    RET

; --- CORREGIDO (nombre historico "helper de fuente/patron" no
; encajaba): pone (ACUMULADOR_TECLAS_MENU) a 0 y llama a ESCANEAR_FILAS_TECLADO
; (madmix1_body.asm, $8E5A) con su propia tabla TABLA_TECLAS_MENU_PRINCIPAL (6
; parejas, todas fila $F0 -- 6 teclas de navegacion del menu
; principal), devolviendo en E el bitmask de esas 6 teclas. El
; llamador (REINICIAR_TIMEOUT_MENU/ACTUALIZAR_MENU_PRINCIPAL) comprueba bit a bit el resultado justo
; despues para mover el cursor del menu -- es el LECTOR DE TECLAS DEL
; MENU PRINCIPAL, no nada relacionado con fuentes. Candidato a
; renombrar (p.ej. LEER_TECLAS_MENU_PRINCIPAL) en una futura ronda. ---
LEER_TECLAS_MENU_PRINCIPAL:                   ; $5C80
    LD IX, TABLA_TECLAS_MENU_PRINCIPAL
    PUSH HL
    LD HL, ACUMULADOR_TECLAS_MENU
    LD (HL), $00
    LD E, $00
    LD B, $06
    CALL ESCANEAR_FILAS_TECLADO
    POP HL
    RET

    ; $5C93-$5C9E (12 bytes, tabla IX): 6 parejas fila/mascara para
    ; ESCANEAR_FILAS_TECLADO, todas fila $F0 -- las 6 teclas de
    ; seleccion del menu principal. Cada RL E desplaza los bits ya
    ; leidos (ver ESCANEAR_FILAS_TECLADO en madmix1_body.asm), asi que
    ; la PRIMERA pareja de esta tabla acaba en el bit MAS ALTO del
    ; resultado (E) y la ULTIMA en el bit 0 -- el orden de comprobacion
    ; en ACTUALIZAR_MENU_PRINCIPAL/DESPACHAR_ACCION_MENU va "al reves"
    ; del orden de la tabla. Las parejas 4 y 5 son IDENTICAS (misma
    ; fila/mascara) -- leen la misma tecla dos veces; el bit de la
    ; pareja 4 (bit 2 del resultado) no se comprueba en ningun sitio.
TABLA_TECLAS_MENU_PRINCIPAL:
    DB $F0,$10                 ; -> bit 5 del resultado: opcion 4 (demo)
    DB $F0,$02                 ; -> bit 4: opcion 2 (joystick)
    DB $F0,$04                 ; -> bit 3: opcion 1 (teclado)
    DB $F0,$08                 ; -> bit 2: sin uso (nunca comprobado)
    DB $F0,$08                 ; -> bit 1: opcion 3 (redefine teclas) -- misma tecla que la pareja anterior
    DB $F0,$01                 ; -> bit 0: "0 JUGAR" (reanuda la partida)

; --- Rutina suelta: limpia el area principal de VRAM (patrones,
; $2000-$37FF via FILVRM) tras rellenar el borde. Dos puntos de
; entrada: caida normal (NOP, no relleno) y LIMPIAR_VRAM_AREA_JUEGO ($5CA0,
; el que usan el resto de llamadas -- salta directo al CALL). El
; opcode de este NOP ($00) se reutiliza ademas como
; ACUMULADOR_TECLAS_MENU (byte de trabajo de LEER_TECLAS_MENU_PRINCIPAL,
; direccionado directamente, sin pasar nunca por aqui como codigo). ---
ACUMULADOR_TECLAS_MENU:                ; $5C9F
    NOP
LIMPIAR_VRAM_AREA_JUEGO:                      ; $5CA0
    CALL RELLENAR_SOLIDO_AREA_JUEGO_BUFFER_VRAM
    LD HL, $2000               ; tabla de patrones de VRAM (inicio)
    LD BC, 6144                 ; $2000-$37FF, tabla de patrones completa
    LD A, $01                 ; patron solido: bit 0 activo en cada byte (no es un contador)
    CALL FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    RET

; --- Escribe un patron de 8 filas (D) en VRAM, offset via A*8+$925B,
; con doble llamada a FILVRM/LDIRVM ($8931/$8942) para las dos mitades. ---
ESCRIBIR_PATRON_VRAM:              ; $5CAF
    PUSH BC
    PUSH HL
    LD L, A
    LD H, 0
    ADD HL, HL                 ; HL = A*8 (offset del patron dentro del bloque)
    ADD HL, HL
    ADD HL, HL
    LD DE, $925B
    ADD HL, DE
    POP DE
    LD BC, 8                    ; 8 bytes: mitad "forma" del patron
    CALL LDIRVM
    EX DE, HL
    SET 5, H                   ; HL += $2000: salta a la mitad "color/atributo" gemela del mismo bloque
    EX AF, AF'                 ; recupera en A el 2o byte de cabecera de DIBUJAR_TEXTO_VRAM (valor de relleno de color)
    PUSH AF
    LD BC, 8                    ; 8 bytes: mitad "color/atributo" del patron
    CALL FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    POP AF
    EX AF, AF'
    POP BC
    RET

; --- Motor de "descompresion"/dibujado de recursos: DE apunta a un
; registro [byte,byte,tabla de C bytes] -- C=numero de caracteres,
; 2o byte=valor de color/atributo (guardado en AF', usado por
; ESCRIBIR_PATRON_VRAM para la mitad "color" de cada patron) -- cada
; byte de la tabla (si >=$20) dibuja un patron via ESCRIBIR_PATRON_VRAM,
; avanzando HL 8 columnas cada vez; si es <$20, no es un caracter --
; es un contador de columnas en blanco a saltar (ver .SALTAR_COLUMNAS). ---
DIBUJAR_TEXTO_VRAM:                         ; $5CD1
    DI
    LD A, (DE)
    LD C, A                    ; C = numero de caracteres del registro
    INC DE
    EX AF, AF'
    LD A, (DE)                 ; 2o byte de cabecera: valor de color/atributo (queda en AF' para ESCRIBIR_PATRON_VRAM)
    EX AF, AF'
    INC DE
.BUCLE_CARACTER:
    LD A, (DE)
    CP $20                     ; <$20 -> no es codigo de patron, es contador de salto (ver .SALTAR_COLUMNAS)
    JR C, .SALTAR_COLUMNAS
    PUSH HL
    PUSH DE
    CALL ESCRIBIR_PATRON_VRAM
    POP DE
    POP HL
    LD A, 8                    ; avanza HL 8 columnas (ancho de un caracter)
    ADD A, L
    LD L, A
    LD A, H
    ADC A, 0
    LD H, A
.CONTINUAR_CARACTER:
    INC DE
    DEC C
    JR NZ, .BUCLE_CARACTER
    EI
    RET
.SALTAR_COLUMNAS:
    PUSH AF
    LD A, 8                    ; suma 8 columnas por cada unidad del contador de salto
    ADD A, L
    LD L, A
    POP AF
    DEC A
    JR NZ, .SALTAR_COLUMNAS
    JR .CONTINUAR_CARACTER

; --- Espera a que se pulse una tecla (via COMPROBAR_PULSACION). ---
ESPERAR_TECLA_PULSADA:                ; $5CFE
    CALL COMPROBAR_PULSACION
    JR Z, ESPERAR_TECLA_PULSADA
    RET
; --- Espera a que se suelte la tecla actual (via COMPROBAR_PULSACION). ---
ESPERAR_TECLA_SOLTADA:                     ; $5D04
    CALL COMPROBAR_PULSACION
    JR NZ, ESPERAR_TECLA_SOLTADA
    RET

; --- Lectura de teclado por matriz (puerto $AA selecciona fila,
; $A9 lee columnas), C = numero de fila (0-8), busca la primera
; tecla pulsada. Igual que el estandar del BIOS MSX. ---
COMPROBAR_PULSACION:                       ; $5D0A
    LD C, $00
.BUCLE_FILA:
    IN A, ($AA)
    AND $F0
    ADD A, C
    OUT ($AA), A
    IN A, ($A9)
    CP $FF
    RET NZ
    INC C
    LD A, $09
    CP C
    RET Z
    JR .BUCLE_FILA

; --- Dibuja el menu de redefinicion de teclas completo: 7 patrones
; fijos (tabla $0448 etc.) y, para las 6 acciones (pausa, fuego,
; arriba, abajo, izquierda, derecha), la tecla asignada actual (leida
; de CODIGO_TECLA_ACTUAL) resaltada si es la seleccionada. ---
DIBUJAR_MENU_REDEFINIR_TECLAS:                   ; $5D1F
    CALL LIMPIAR_VRAM_AREA_JUEGO
    CALL REINICIAR_TECLAS_USADAS
    LD HL, $0448
    LD DE, TEXTO_TECLA_FUEGO
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $04A8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .CONTINUAR_TECLA_2
    CALL ESCRIBIR_PATRON_VRAM
.CONTINUAR_TECLA_2:
    LD HL, $0648
    LD DE, TEXTO_TECLA_ARRIBA
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $06A8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .CONTINUAR_TECLA_3
    CALL ESCRIBIR_PATRON_VRAM
.CONTINUAR_TECLA_3:
    LD HL, $0848
    LD DE, TEXTO_TECLA_ABAJO
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $08A8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .CONTINUAR_TECLA_4
    CALL ESCRIBIR_PATRON_VRAM
.CONTINUAR_TECLA_4:
    LD HL, $0A48
    LD DE, TEXTO_TECLA_IZQUIERDA
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $0AA8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .CONTINUAR_TECLA_5
    CALL ESCRIBIR_PATRON_VRAM
.CONTINUAR_TECLA_5:
    LD HL, $0C48
    LD DE, TEXTO_TECLA_DERECHA
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $0CA8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .CONTINUAR_TECLA_6
    CALL ESCRIBIR_PATRON_VRAM
.CONTINUAR_TECLA_6:
    LD HL, $0E48
    LD DE, TEXTO_TECLA_PAUSA
    CALL DIBUJAR_TEXTO_VRAM
    CALL ESPERAR_TECLA_NUEVA
    LD A, $F1
    EX AF, AF'
    LD A, (CODIGO_TECLA_ACTUAL)
    LD HL, $0EA8
    CP $24
    PUSH AF
    CALL C, DIBUJAR_NOMBRE_TECLA_ASIGNADA
    POP AF
    JR C, .FIN_DIBUJAR_MENU
    CALL ESCRIBIR_PATRON_VRAM
.FIN_DIBUJAR_MENU:
    CALL ESPERAR_TECLA_SOLTADA
    JP ESPERAR_TECLA_PULSADA

; --- Busca en TABLA_NOMBRES_TECLA_ASIGNABLE (registros
; [longitud+2]) la entrada numero B (indice de tecla), devuelve su
; direccion en DE y salta a DIBUJAR_TEXTO_VRAM para dibujarla. ---
DIBUJAR_NOMBRE_TECLA_ASIGNADA:                 ; $5DF1
    LD D, $00
    PUSH HL
    LD B, A
    LD HL, TABLA_NOMBRES_TECLA_ASIGNABLE
.BUCLE_BUSCAR_NOMBRE:
    LD E, (HL)
    INC E
    INC E
    ADD HL, DE
    DJNZ .BUCLE_BUSCAR_NOMBRE
    EX DE, HL
    POP HL
    JP DIBUJAR_TEXTO_VRAM

    ; $5E03-$5ED9 (215 bytes): tabla de texto de las 6 acciones
    ; redefinibles (PAUSA, FUEGO, ARRIBA, ABAJO, IZQUIERDA, DERECHA)
    ; + los nombres de teclas asignables (ESPACIO, S.SHIFT, C.SHIFT,
    ; ENTER, SHIFT, CTRL, GRAPH, CAPS, F1-F5, ESCAPE, TAB, STOP, BS,
    ; SELECT, HOME, INS, DEL, simbolos...). Formato por registro:
    ; [longitud][atributo][longitud bytes de texto ASCII].
TEXTO_MENU_REDEFINIR_TECLAS:
TEXTO_TECLA_PAUSA:
    DB $05,$51,"PAUSA"
TEXTO_TECLA_FUEGO:
    DB $05,$61,"FUEGO"
TEXTO_TECLA_ARRIBA:
    DB $06,$21,"ARRIBA"
TEXTO_TECLA_ABAJO:
    DB $05,$21,"ABAJO"
TEXTO_TECLA_IZQUIERDA:
    DB $09,$21,"IZQUIERDA"
TEXTO_TECLA_DERECHA:
    DB $07,$21,"DERECHA"
TEXTO_TECLA_ESPACIO_1:                     ; sin referencias actuales
    DB $07,$F1,"ESPACIO"
TEXTO_TECLA_SSHIFT:                        ; sin referencias actuales
    DB $07,$F1,"S.SHIFT"
TEXTO_TECLA_CSHIFT:                        ; sin referencias actuales
    DB $07,$F1,"C.SHIFT"
TEXTO_TECLA_ENTER_1:                       ; sin referencias actuales
    DB $05,$F1,"ENTER"
TABLA_NOMBRES_TECLA_ASIGNABLE:             ; entrada 0: degenerada, nunca es el destino real (los codigos empiezan en 1)
    DB $01,$01,$01
TEXTO_TECLA_SHIFT:                         ; codigo especial 1
    DB $05,$F1,"SHIFT"
TEXTO_TECLA_CTRL:                          ; codigo especial 2
    DB $04,$F1,"CTRL"
TEXTO_TECLA_GRAPH:                         ; codigo especial 3
    DB $05,$F1,"GRAPH"
TEXTO_TECLA_CAPS:                          ; codigo especial 4
    DB $04,$F1,"CAPS"
TEXTO_TECLA_CODE:                          ; codigo especial 5 -- texto vacio (un solo espacio), posicion que le corresponde a CODE en la fila estandar SHIFT/CTRL/GRAPH/CAPS/CODE
    DB $01,$F1," "
TEXTO_TECLA_F1:                            ; codigo especial 6
    DB $03,$F1,"F 1"
TEXTO_TECLA_F2:                            ; codigo especial 7
    DB $03,$F1,"F 2"
TEXTO_TECLA_F3:                            ; codigo especial 8
    DB $03,$F1,"F 3"
TEXTO_TECLA_F4:                            ; codigo especial 9
    DB $03,$F1,"F 4"
TEXTO_TECLA_F5:                            ; codigo especial 10
    DB $03,$F1,"F 5"
TEXTO_TECLA_ESCAPE:                        ; codigo especial 11
    DB $06,$F1,"ESCAPE"
TEXTO_TECLA_TAB:                           ; codigo especial 12
    DB $03,$F1,"TAB"
TEXTO_TECLA_STOP:                          ; codigo especial 13
    DB $04,$F1,"STOP"
TEXTO_TECLA_BS:                            ; codigo especial 14
    DB $02,$F1,"BS"
TEXTO_TECLA_SELECT:                        ; codigo especial 15
    DB $06,$F1,"SELECT"
TEXTO_TECLA_ENTER_2:                       ; codigo especial 16 (duplicado de TEXTO_TECLA_ENTER_1)
    DB $05,$F1,"ENTER"
TEXTO_TECLA_ESPACIO_2:                     ; codigo especial 17 (duplicado de TEXTO_TECLA_ESPACIO_1)
    DB $07,$F1,"ESPACIO"
TEXTO_TECLA_HOME:                          ; codigo especial 18
    DB $04,$F1,"HOME"
TEXTO_TECLA_INS:                           ; codigo especial 19
    DB $03,$F1,"INS"
TEXTO_TECLA_DEL:                           ; codigo especial 20
    DB $03,$F1,"DEL"
TEXTO_TECLA_EXCLAMACION:                   ; codigo especial 21
    DB $01,$F1,"!"
TEXTO_TECLA_COMILLAS:                      ; codigo especial 22
    DB $01,$F1,$22
TEXTO_TECLA_ALMOHADILLA:                   ; codigo especial 23
    DB $01,$F1,"#"
TEXTO_TECLA_DOLAR:                         ; codigo especial 24
    DB $01,$F1,"$"


; --- CORREGIDO (el comentario historico "tabla de tipo de loseta
; compartida $8E88" era una hipotesis antigua equivocada -- no existe
; tal tabla en esa direccion): limpia (RES 7) las 72 posiciones de
; TABLA_CODIGOS_TECLA (bit 7 = marca "tecla usada" superpuesta a su
; contenido normal) y reinicia PUNTERO_ESCRITURA_TECLA al
; INICIO de TABLA_TECLAS_MSX (madmix1_body.asm) -- HALLAZGO: no es un
; buffer scratch, es el DESTINO REAL de la redefinicion: hay
; exactamente 6 acciones redefinibles = 6 pares fila/mascara = 12
; bytes = el tamano exacto de TABLA_TECLAS_MSX, asi que el submenu
; sobreescribe en caliente la tabla que usa LEER_TECLADO. ---
REINICIAR_TECLAS_USADAS:                     ; $5EDA
    LD HL, TABLA_TECLAS_MSX     ; puntero de escritura: el propio inicio de la tabla real de control
    LD (PUNTERO_ESCRITURA_TECLA), HL
    LD HL, TABLA_CODIGOS_TECLA  ; 72 entradas, bit 7 = "tecla usada"
    LD B, 72                    ; 72 entradas a limpiar
.BUCLE_LIMPIAR_MARCAS:
    RES 7, (HL)
    INC HL
    DJNZ .BUCLE_LIMPIAR_MARCAS
    RET

; --- Recorre el teclado (matriz $AA/$A9, filas $F0-$F8) buscando la
; primera tecla NUEVA pulsada (bit7 de su entrada en TABLA_CODIGOS_TECLA
; a 0): escribe el par fila/mascara real en TABLA_TECLAS_MSX (via
; PUNTERO_ESCRITURA_TECLA, ver REINICIAR_TECLAS_USADAS), marca la
; entrada como usada y guarda su valor (codigo de caracter o
; especial) en CODIGO_TECLA_ACTUAL. ---
ESPERAR_TECLA_NUEVA:                    ; $5EEB
    LD HL, (PUNTERO_ESCRITURA_TECLA)
    CALL ESPERAR_TECLA_SOLTADA
.REINICIAR_ESCANEO:
    LD DE, $F000
.BUCLE_FILA:
    LD A, D
    OUT ($AA), A
    IN A, ($A9)
    LD B, $08
.BUCLE_BIT:
    RRCA
    JR NC, .TECLA_DETECTADA
    INC E
    DJNZ .BUCLE_BIT
    INC D
    LD A, D
    CP $F9
    JR NZ, .BUCLE_FILA
    JR .REINICIAR_ESCANEO
.TECLA_DETECTADA:
    LD A, $00
    SCF
.BUCLE_CONSTRUIR_MASCARA:
    RRA
    DJNZ .BUCLE_CONSTRUIR_MASCARA
    LD (HL), D                 ; escribe fila en TABLA_TECLAS_MSX (via HL=PUNTERO_ESCRITURA_TECLA)
    INC HL
    LD (HL), A                 ; escribe mascara
    INC HL
    PUSH HL
    LD D, $00
    LD HL, TABLA_CODIGOS_TECLA  ; +E: entrada de esta tecla
    ADD HL, DE
    LD A, (HL)
    BIT 7, A
    JR Z, .TECLA_NUEVA
    POP HL
    JR ESPERAR_TECLA_NUEVA
.TECLA_NUEVA:
    LD (CODIGO_TECLA_ACTUAL), A
    SET 7, (HL)
    POP HL
    LD (PUNTERO_ESCRITURA_TECLA), HL
    RET

; --- CORREGIDO (no es una fuente/bitmap): mapa de 72 posiciones de
; escaneo de teclado (fila x8+bit, mismo orden que ESPERAR_TECLA_NUEVA)
; -> identidad de esa tecla. Filas $F0-$F5: glifo ASCII imprimible
; real, pasable tal cual a ESCRIBIR_PATRON_VRAM. Filas $F6-$F8: codigo
; especial 1-24, indice a TEXTO_MENU_REDEFINIR_TECLAS para teclas no
; imprimibles (de ahi el CP $24 de DIBUJAR_MENU_REDEFINIR_TECLAS). El
; bit 7 de cada entrada se reutiliza como marca "tecla usada" durante
; la redefinicion (ver REINICIAR_TECLAS_USADAS/ESPERAR_TECLA_NUEVA);
; los 3 bytes finales son relleno, nunca alcanzados (el escaneo real
; solo cubre 72 posiciones). ---
TABLA_CODIGOS_TECLA:
    DB "01234567"              ; fila $F0: digitos
    DB "89-=", $5C, "{};"      ; fila $F1
    DB ":", $20, ",./^AB"      ; fila $F2
    DB "CDEFGHIJ"              ; fila $F3
    DB "KLMNOPQR"              ; fila $F4
    DB "STUVWXYZ"              ; fila $F5
    DB 1,2,3,4,5,6,7,8          ; fila $F6: codigos especiales 1-8 (indices a TEXTO_MENU_REDEFINIR_TECLAS)
    DB 9,10,11,12,13,14,15,16   ; fila $F7: codigos especiales 9-16
    DB 17,18,19,20,21,22,23,24  ; fila $F8: codigos especiales 17-24
    ; CORREGIDO: estos 3 bytes NO son relleno inerte -- $5F74 (justo
    ; despues de las 72 entradas reales de la tabla, $5F2C-$5F73) es
    ; el puntero de escritura hacia TABLA_TECLAS_MSX y $5F76 el codigo
    ; de la tecla actual, ambos usados por REINICIAR_TECLAS_USADAS/
    ; ESPERAR_TECLA_NUEVA/DIBUJAR_MENU_REDEFINIR_TECLAS. Su valor
    ; inicial en el .BIN es 0 porque no se usan hasta entrar al
    ; submenu de redefinicion. Confirmado por aritmetica exacta:
    ; DIBUJAR_CREDITOS empieza en $5F77 = $5F74+3.
PUNTERO_ESCRITURA_TECLA:
    DW 0
CODIGO_TECLA_ACTUAL:
    DB 0

; --- Dibuja la pantalla de creditos: 8 registros de texto via
; DIBUJAR_TEXTO_VRAM (CORREGIDO: son 8, no 7 -- el comentario historico
; contaba mal antes de tener las 8 direcciones identificadas),
; direcciones/tamanos hardcoded (analogo a DIBUJAR_MENU_PRINCIPAL). ---
DIBUJAR_CREDITOS:                   ; $5F77
    CALL LIMPIAR_VRAM_AREA_JUEGO
    LD DE, TEXTO_CREDITOS_TITULO
    LD HL, $0248
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_PROGRAMADO_POR
    LD HL, $0520
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_NOMBRE_PROGRAMADOR
    LD HL, $0760
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_GRAFICOS_POR
    LD HL, $0920
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_NOMBRE_GRAFICOS
    LD HL, $0B60
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_MUSICA_POR
    LD HL, $0D20
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_NOMBRE_MUSICA
    LD HL, $0F60
    CALL DIBUJAR_TEXTO_VRAM
    LD DE, TEXTO_CREDITOS_TOPOSHOW
    LD HL, $1240
    JP DIBUJAR_TEXTO_VRAM

    ; $5FC2-$6044 (131 bytes): LOS CREDITOS REALES DEL JUEGO.
    ; Mismo formato [longitud][atributo][texto] que la tabla de
    ; teclas, pero aqui cada entrada se llama con una direccion
    ; LITERAL hardcoded desde DIBUJAR_CREDITOS (no en bucle
    ; secuencial), asi que puede haber bytes sueltos entre
    ; entradas que la rutina real nunca lee (no confirmado cuantos
    ; bytes de cada [longitud] llega a dibujar DIBUJAR_TEXTO_VRAM en la
    ; practica). CORREGIDO respecto a una nota narrativa anterior
    ; (basada en una lectura "idealizada", sin haber volcado los
    ; bytes reales todavia): el texto real, byte a byte, dice
    ; "POGRAMADO" (sin la primera R), "RAPHAEL GOMEZZZ" (con Z de
    ; mas -- puede ser un efecto de "desvanecido" deliberado tipo
    ; comic, o un fallo del original nunca corregido), "GRAPHICOS"
    ; (con PH, no "GRAFICOS") y "MUSIC-A" (con guion). Se transcribe
    ; tal cual, sin "corregir" la ortografia -- son los bytes reales
    ; del juego de 1987.
TEXTO_CREDITOS_PROGRAMADO_POR:
    DB $0F,$61,"POGRAMADO BY:   "
TEXTO_CREDITOS_NOMBRE_PROGRAMADOR:
    DB $0F,$F1,"RAPHAEL GOMEZZZ.. "
TEXTO_CREDITOS_GRAFICOS_POR:
    DB $0D,$61,"GRAPHICOS BY :  "
TEXTO_CREDITOS_NOMBRE_GRAFICOS:
    DB $11,$F1,"ROBERTO P.ACEBES"
TEXTO_CREDITOS_MUSICA_POR:
    DB $0B,$61,"MUSIC-A BY:"
TEXTO_CREDITOS_NOMBRE_MUSICA:
    DB $09,$F1,"COMILONAS"
TEXTO_CREDITOS_TOPOSHOW:
    DB $0F,$21,"TOPOSHOW -1988-"
    ; CORREGIDO: la nota historica de que "MAD$MIX GAME" no se
    ; alcanzaba desde ninguna de las 8 llamadas de DIBUJAR_CREDITOS
    ; era un error -- SI se alcanza: es la PRIMERA de las 8 llamadas
    ; (LD DE, TEXTO_CREDITOS_TITULO, HL=$0248, dibujada arriba del
    ; todo), pese a estar colocada la ULTIMA en el layout de datos
    ; (direcciones literales hardcoded, no bucle secuencial). El '$'
    ; dentro de "MAD$MIX" es literal (byte $24) -- podria ser un
    ; caracter decorativo de la fuente en vez de un simbolo de dolar
    ; real, sin confirmar.
TEXTO_CREDITOS_TITULO:
    DB $0C,$A1,"MAD$MIX GAME",$00,$00

; --- Motor de "ciclado de niveles de muestra": recorre una tabla de
; 4 entradas [nivel,puntero] en $60D0 (corregido: el bucle compara
; contra $04, no 6), fija $2C07 al nivel indicado y llama a
; CARGAR_NIVEL/INICIALIZAR_ITEMS_NIVEL/JT_REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM/JT_LEER_ENTRADA para dibujarlo, esperando
; entrada antes de pasar al siguiente (o volver al 0). Cada puntero
; apunta a uno de los 10 guiones de reproduccion automatica en
; madmix1.asm (DEMO_SCRIPT_NIVEL1/2/4/5, 0xD500 en adelante): pares
; [duracion en fotogramas, direccion simulada] terminados en
; direccion $FF -- .REPRODUCIR_GUION_DEMO/.COMPROBAR_FIN_GUION mas abajo son quienes leen y
; reproducen ese guion byte a byte. Los otros 6 guiones de esa tabla
; (DEMO_SCRIPT_SINREF_1..6) no estan referenciados por ningun
; puntero de aqui -- ver FINDINGS.md. ---
GESTIONAR_CICLO_NIVELES:                ; $6045
    XOR A
    LD (INDICE_CICLO_NIVELES), A
    LD ($FC01), A
    LD ($FC00), A
.BUCLE_NIVEL_DEMO:
    LD HL, INDICE_CICLO_NIVELES
    LD A, (HL)
    INC (HL)
    CP $04
    JP Z, .FIN_CICLO_NIVELES
    LD L, A
    ADD A, A
    ADD A, L
    LD HL, TABLA_CICLO_NIVELES
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD A, (HL)
    LD (NIVEL_ACTUAL), A
    INC HL
    LD C, (HL)
    INC HL
    LD B, (HL)
    LD (PUNTERO_GUION_DEMO), BC
    XOR A
    LD (VIDAS_RESTANTES), A
    LD (MODO_ESPECIAL_ACTIVO), A
    CALL CARGAR_NIVEL
    CALL INICIALIZAR_ITEMS_NIVEL
    CALL REDIBUJAR_PANTALLA_COMPLETA_BUFFER_VRAM
    CALL APLICAR_COLOR_PANTALLA
    XOR A
    LD (CONTADOR_FRAME_GUION_DEMO), A
.REPRODUCIR_GUION_DEMO:
    CALL LEER_ENTRADA
    XOR A
    LD (MODO_ESPECIAL_ACTIVO), A
    LD IX, (PUNTERO_GUION_DEMO)
    LD HL, CONTADOR_FRAME_GUION_DEMO
    INC (HL)
    LD A, (HL)
    CP (IX+0)
    LD A, (IX+1)
    JR C, .COMPROBAR_FIN_GUION
    INC IX
    INC IX
    LD (HL), $00
    LD A, (IX+1)
    LD (PUNTERO_GUION_DEMO), IX
.COMPROBAR_FIN_GUION:
    CP $FF
    JP Z, .BUCLE_NIVEL_DEMO
    AND $1F
    LD D, A
    CALL ENLACE_MOTOR_MOVIMIENTO_COLISION
    CALL WAIT_VBLANK               ; WAIT_VBLANK (madmix1.asm)
    CALL ACTUALIZAR_LOSETA_BOLA_ESPECIAL
    CALL COMPROBAR_PULSACION
    JR NZ, .FIN_CICLO_NIVELES
    JR .REPRODUCIR_GUION_DEMO
.FIN_CICLO_NIVELES:
    XOR A
    LD (INDICE_CICLO_NIVELES), A
    RET

    ; $60CA-$60CF: NO es cola inerte -- es el estado real del ciclador
    ; de niveles de muestra (compila con los valores de fabrica de
    ; abajo, se reinicializa en GESTIONAR_CICLO_NIVELES/.FIN_CICLO_NIVELES).
INDICE_CICLO_NIVELES:                  ; $60CA -- indice 0-3 del nivel de muestra en curso (0 = ciclador inactivo)
    DB $00
PUNTERO_GUION_DEMO:                    ; $60CB-$60CC -- cursor dentro del guion de demo activo
    DW $00
CONTADOR_FRAME_GUION_DEMO:             ; $60CD -- fotogramas transcurridos en la entrada actual del guion
    DB $01
    DB $00,$FC          ; $60CE-$60CF: cola/alineacion antes de la tabla, sin consumidor confirmado

    ; $60D0-$60DB (12 bytes): tabla de 4 entradas [nivel, puntero
    ; 2 bytes] para el ciclador de arriba. Los punteros caen dentro de
    ; MADMIX1.BIN -- son GUION_DEMO_NIVEL1 ($D524, el arranque real
    ; del guion, ver FINDINGS.md/madmix1_body.asm sobre $D500-$D524 --
    ; nunca fue guion, siempre cola del cuerpo del nivel 14),
    ; GUION_DEMO_NIVEL2 ($D564), GUION_DEMO_NIVEL4 ($D5D4) y
    ; GUION_DEMO_NIVEL5 ($D644) -- ver madmix1_body.asm y FINDINGS.md.
TABLA_CICLO_NIVELES:
    DB 1
    DW GUION_DEMO_NIVEL1
    DB 2
    DW GUION_DEMO_NIVEL2
    DB 4
    DW GUION_DEMO_NIVEL4
    DB 5
    DW GUION_DEMO_NIVEL5

; --- RESUELTO -- esta es la pieza que confirma que EVENTO_SONIDO_PENDIENTE es el
; INDICE DE EFECTO DE SONIDO (ver FINDINGS.md): llamada desde ENTRADA_INTERRUPCION_VBLANK
; en CADA VBLANK. Si EVENTO_SONIDO_PENDIENTE != $FF (hay un evento pendiente), lo marca
; consumido y lo usa como indice (x3) en TABLA_RECURSOS_SONIDO_EVENTO
; [canal, puntero] para instalar ese script en el reproductor PSG
; ($C4A0 = INSTALAR_RECURSO_SONIDO); en cualquier caso, SIEMPRE llama
; a $C4EB (TICK_REPRODUCTOR_PSG en madmix1.asm, el "tick" real del
; reproductor). ---
DESPACHAR_EFECTO_SONIDO:              ; $60DC
    LD HL, EVENTO_SONIDO_PENDIENTE
    LD A, (HL)
    CP $FF
    JR Z, .TICK_SIEMPRE             ; $FF = nada pendiente -- salta directo al tick
    LD (HL), $FF                ; marca el evento como consumido
    LD HL, TABLA_RECURSOS_SONIDO_EVENTO
    LD B, A
    ADD A, A
    ADD A, B
    ADD A, L
    LD L, A
    LD A, H
    ADC A, $00
    LD H, A
    LD A, (HL)
    INC HL
    LD E, (HL)
    INC HL
    LD D, (HL)
    CALL INSTALAR_RECURSO_SONIDO
.TICK_SIEMPRE:
    CALL TICK_REPRODUCTOR_PSG                ; TICK_REPRODUCTOR_PSG (madmix1.asm): tick del reproductor, siempre
    RET

    ; $60FE en adelante: tabla de recursos [id,puntero] indexada por
    ; el helper anterior, seguida de un bloque grande (~810 bytes)
    ; con forma de patron grafico (silueta monocroma al estilo de
    ; las losetas del juego) -- probablemente el logo/decoracion de
    ; estas pantallas. Verificado byte a byte, sin decodificar campo
    ; a campo.
TABLA_RECURSOS_SONIDO_EVENTO:
    DB $00,$E2,$CE,$00,$8B,$CE,$00,$62,$CF,$01,$70,$CF,$00,$72,$CE,$01
    DB $44,$CF,$01,$AC,$CE,$01,$7E,$CE,$00,$07,$CF,$00,$5A,$CE,$00,$F0
    DB $CE,$02,$9C,$CE,$00,$CB,$CD,$02,$27,$CF
    ; ultimo byte de la fila: NO es parte de la tabla (14 entradas x 3
    ; bytes = 42, terminan en el $CF de arriba) -- es EVENTO_SONIDO_PENDIENTE,
    ; el marcador de evento/indice de efecto de sonido a disparar,
    ; leido/escrito por DESPACHAR_EFECTO_SONIDO en cada VBLANK.
EVENTO_SONIDO_PENDIENTE:
    DB $00
; --- 0x6129-0x6429 (768 bytes): color real del marco de caramelo,
; extraido a data/img/marco_caramelo_color.img (ver FINDINGS.md --
; APLICAR_COLOR_PANTALLA lo traduce con OBTENER_COLOR_VDP y rellena la
; tabla de color de VRAM, verificado exacto contra un volcado de
; VRAM real). ---
TABLA_COLOR_MARCO_CARAMELO:
    INCBIN "data/img/marco_caramelo_color.img"

; --- CORREGIDO: el comentario anterior aqui describia en realidad
; APLICAR_COLOR_PANTALLA (el bloque de "TABLA_COLOR_MARCO_CARAMELO, id+8 bytes") y
; APLICAR_COLOR_CICLO_NIVELES ($647C, una funcion DISTINTA, no un
; segundo punto de entrada de esta). Lo que esta funcion hace de
; verdad: limpia la tabla de color de VRAM ($2000, FILVRM con $01) y
; luego descomprime TABLA_RLE_MARCO_CARAMELO (870 bytes, pares [valor,contador])
; volcando el resultado con FILVRM directo a la tabla de patrones de
; VRAM (destino arranca en 0) -- dibuja la FORMA del marco de
; caramelo. Su "hermana" es APLICAR_COLOR_PANTALLA, que aplica el COLOR de
; ese mismo marco leyendo TABLA_RECURSOS_SONIDO_EVENTO/TABLA_COLOR_MARCO_CARAMELO. ---
DIBUJAR_MARCO_CARAMELO_VRAM:              ; $6429
    DI
    LD HL, $2000
    LD BC, $17F8
    LD A, $01
    CALL FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    LD DE, $0000
    LD HL, TABLA_RLE_MARCO_CARAMELO
    LD BC, $0366
.BUCLE_DESCOMPRIMIR_MARCO:
    PUSH BC
    LD A, (HL)
    INC HL
    LD C, (HL)
    LD B, $00
    INC HL
    EX DE, HL
    PUSH BC
    CALL FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    POP BC
    ADD HL, BC
    EX DE, HL
    POP BC
    DEC BC
    LD A, B
    OR C
    JR NZ, .BUCLE_DESCOMPRIMIR_MARCO
    RET
; --- CONFIRMADO (ver FINDINGS.md): pese a su nombre, esta es la
; rutina que aplica el COLOR REAL del marco de caramelo (y del
; resto de la pantalla). Traduce cada uno de los 768 bytes de
; TABLA_RECURSOS_SONIDO_EVENTO (desde TABLA_COLOR_MARCO_CARAMELO) con OBTENER_COLOR_VDP y
; rellena con el resultado la tabla de color de VRAM ($2000, 768
; celdas x 8 bytes) via FILVRM. Verificado exacto contra un volcado
; de VRAM real: fila 0 = $E1,$E1,$E1,$F1,$F1,$E1,$6E(x20),$E1,$F1,
; $F1,$E1,$E1,$E1 -- las esquinas gris/blanco y el tramo recto rojo
; oscuro/gris del marco (TABLA_RLE_MARCO_CARAMELO, en madmix1.asm, da la
; FORMA; esta rutina da el COLOR). ---
APLICAR_COLOR_PANTALLA:                    ; $6454
    LD BC, $0300
APLICAR_COLOR_DESDE_TABLA:                            ; $6457 -- segundo punto de entrada
    LD DE, $2000                       ; (usado por APLICAR_COLOR_CICLO_NIVELES,
    LD HL, TABLA_COLOR_MARCO_CARAMELO                       ; que fija su propio BC antes de saltar aqui)
    XOR A
    LD (ULTIMO_ICONO_HUD_CACHEADO), A
.BUCLE_APLICAR_COLOR:
    PUSH BC
    LD A, (HL)
    CALL OBTENER_COLOR_VDP
    INC HL
    LD BC, $0008
    EX DE, HL
    PUSH BC
    CALL FILVRM              ; equivalente a la rutina FILVRM del BIOS de MSX
    POP BC
    ADD HL, BC
    EX DE, HL
    POP BC
    DEC BC
    LD A, B
    OR C
    JR NZ, .BUCLE_APLICAR_COLOR
    CALL PROGRAMAR_ENCENDIDO_PANTALLA                 ; vuelve a encender la pantalla
    RET
; --- Variante de APLICAR_COLOR_PANTALLA para el ciclador de niveles de
; muestra: apaga pantalla, fija BC=$02C0 (704 -- CORREGIDO: recorrido
; mas CORTO que el de creditos/HUD, $0300=768, no mas largo como decia
; el comentario anterior) y entra directo en APLICAR_COLOR_DESDE_TABLA -- mismo bucle
; de dibujado, con el numero de losetas a procesar (BC) como unica
; diferencia real entre los dos usos. ---
APLICAR_COLOR_CICLO_NIVELES:            ; $647C
    CALL PROGRAMAR_APAGADO_PANTALLA               ; la apaga antes de redibujar
    LD BC, $02C0
    JR APLICAR_COLOR_DESDE_TABLA

; --- Traduce un byte de entrada (A) a un byte de COLOR VDP (nibble
; alto = tinta, nibble bajo = fondo, formato de la tabla de color de
; SCREEN2) via la tabla ya conocida CONSULTAR_COLOR_VDP/TABLA_COLORES_VDP
; ($8978 en madmix1_body.asm), combinando nibble alto/bajo -- misma
; idea que CONSULTAR_COLOR_VDP pero componiendo dos consultas en vez
; de una. Uso
; confirmado en APLICAR_COLOR_PANTALLA (A = indice de loseta del
; laberinto) y en BUSCAR_COLUMNA_HUD (madmix1_body.asm; A = valor derivado de
; la columna objetivo, para el color del HUD/READY?). ---
OBTENER_COLOR_VDP:                    ; $6484
    PUSH HL
    PUSH BC
    LD B, A
    AND $07
    LD C, A
    LD A, B
    AND $78
    RRCA
    RRCA
    RRCA
    LD L, A
    AND $08
    OR C
    LD C, A
    LD A, L
    LD HL, TABLA_COLORES_VDP
    ADD A, L
    LD L, A
    LD B, (HL)
    LD HL, TABLA_COLORES_VDP
    LD A, C
    ADD A, L
    LD L, A
    LD A, (HL)
    RLCA
    RLCA
    RLCA
    RLCA
    OR B
    POP BC
    POP HL
    RET

; --- Segunda rutina de reubicacion, gemela a la de MADMIX0.BIN:
; conmuta slots (valor fijo $55/$50, no calculado como en
; MADMIX0.BIN), copia 0x54AB bytes desde $8400 (el motor ya
; cargado) a $1000, y lo ejecuta -- candidato fuerte a "volver al
; menu/reiniciar" en caliente desde dentro del juego. ---
REUBICADOR_REINICIO_JUEGO:                      ; $64AB
    DI
    LD A, $55
    OUT ($A8), A
    LD HL, START
    LD DE, DIBUJAR_PORTADA
    LD BC, $54AB
    LDIR
    CALL DIBUJAR_PORTADA
    LD A, $50
    OUT ($A8), A
    EI
    RET

    ; $64C4-$64FF: relleno final hasta el limite de los 0x5500 bytes
    ; reubicados. Patron "FF 00 00" repetido con alguna excepcion
    ; puntual -- verificado byte a byte, sin significado funcional
    ; aparente (misma pinta que el relleno de vectores RST sin usar
    ; visto en otras zonas del juego).
    DB $FF,$FF,$00,$00,$00,$FF,$00,$00,$FF,$00,$00,$FF,$00,$00,$FF,$00
    DB $00,$FF,$00,$00,$FF,$00,$00,$FF,$8C,$00,$FF,$00,$00,$FF,$00,$00
    DB $FF,$00,$00,$FF,$00,$00,$FF,$00,$D3,$FF,$00,$00,$FF,$00,$00,$FF
    DB $00,$00,$FF,$00,$00,$FF,$00,$00,$FF,$00,$00,$FF

FIN_FICHERO_SCR:
