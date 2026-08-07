; ============================================================
;  Mad Mix Game (Topo Soft, 1987) - MSX1
;  main.asm -- pasada UNICA de ensamblado que unifica madmix1_body.asm
;  y madmix_scr_body.asm en un solo espacio de simbolos, para que las
;  llamadas/punteros cruzados entre ambos usen etiquetas reales en vez
;  de direcciones hex literales. Genera:
;   - build/disk/MADMIX1.BIN y build/cas/MADMIX1.BIN (motor del
;     juego): dos copias IDENTICAS del mismo SAVEBIN -- es EXACTAMENTE
;     el mismo binario en ambas ediciones (verificado, ver
;     FINDINGS.md), pero cada carpeta se mantiene autocontenida (todo
;     lo que hace falta para generar su .dsk/.cas vive dentro de ella,
;     sin tener que ir a buscar nada a build/ a secas).
;   - build/disk/MADMIX.SCR, build/disk/MADMIX0.BIN -- especificos de
;     la version de disco.
;   - build/cas/madmix_cas_scr.bin (contenido logico de MADMIX.SCR,
;     SIN cabecera BLOAD -- la cinta carga esto directo en $1000, sin
;     el paso de reubicacion que si hace el disco), build/cas/TEST.BIN,
;     build/cas/LOAD.BIN -- especificos de la version de cinta.
;  load_disk/madmix0_body.asm (el "relocador" de disco, 58 bytes) y
;  load_cas/*_body.asm (cargador de cinta) se incluyen mas abajo,
;  compartiendo este mismo espacio de simbolos -- pueden referenciar
;  DIBUJAR_PORTADA/START en vez de $1000/$8400 literales.
;  Ver FINDINGS.md para el detalle completo de esta unificacion.
; Ingeniería inversa, herramientas y documentación de este proyecto: Rafael Eduardo Martín Candial
; ============================================================

    DEVICE NOSLOT64K

; --- MADMIX1.BIN: direcciones estaticas $8400+, igual que siempre ---
    ORG $83F9
    DB $FE                     ; cabecera de fichero .BIN de MSX
    DW START, END_OF_FILE_M1-1, START

    INCLUDE "madmix1_body.asm"

    SAVEBIN "build/disk/MADMIX1.BIN", START, END_OF_FILE_M1-START
    SAVEBIN "build/cas/MADMIX1.BIN", START, END_OF_FILE_M1-START

; --- MADMIX.SCR: fisicamente en $8800, logicamente reubicado a $1000
; (PHASE/DEPHASE, igual que siempre) ---
    ORG $8800
    DB $FE                     ; cabecera de fichero .BIN de MSX
    DW $8800, $DD00, $8800

SCR_BODY_START_PHYS:          ; posicion FISICA real donde SAVEBIN puede
                               ; recuperar el cuerpo (dentro de PHASE, "$"
                               ; es la direccion LOGICA simulada -- SAVEBIN
                               ; necesita la posicion fisica real de salida)
    PHASE $1000
    INCLUDE "madmix_scr_body.asm"
    DEPHASE

    ; El ultimo byte del fichero real ($DD00) NO forma parte de los
    ; 0x5500 bytes que reubica MADMIX0.BIN (0x8800+0x5500=0xDD00,
    ; exclusivo) -- es un byte suelto fuera de la zona reubicada,
    ; contenido desconocido.
    DB $00

END_OF_FILE_SCR_DISK:

    SAVEBIN "build/disk/MADMIX.SCR", $8800, END_OF_FILE_SCR_DISK-$8800

; --- Fichero para la version .cas: mismo contenido logico ya
; ensamblado arriba (DIBUJAR_PORTADA en adelante), SIN cabecera BLOAD y
; SIN el offset fisico $8800 -- la cinta carga esto directo en $1000,
; sin paso de reubicacion. build/MADMIX1.BIN (arriba) sirve tal cual
; como la pieza "motor" de la version de cinta -- identico en ambas
; ediciones, no hace falta un SAVEBIN aparte para eso. Tamano = el
; fisico total menos cabecera (7) y menos el byte suelto final (1). ---
    SAVEBIN "build/cas/madmix_cas_scr.bin", SCR_BODY_START_PHYS, (END_OF_FILE_SCR_DISK-1)-SCR_BODY_START_PHYS

; --- MADMIX0.BIN: el "relocador" de disco, 58 bytes. Este bloque va
; DESPUES del de MADMIX1.BIN (arriba) a proposito: su SAVEBIN ya
; capturo el contenido real del driver de sonido en $C350 antes de
; que un futuro bloque de TEST.BIN (cinta) reutilice esa misma
; direccion fisica -- verificado con una prueba minima que SAVEBIN
; recupera una foto del buffer en el momento de su propia llamada,
; en orden de fuente, no "el ultimo que escribe gana". ---
    ORG $FA00
MADMIX0_HEADER_START:
    DB $FE                     ; cabecera de fichero .BIN de MSX
    ; Constantes literales (no etiquetas): la cabecera BLOAD declara la
    ; direccion de carga REAL en la maquina, que NO incluye los 7 bytes
    ; de la propia cabecera -- BLOAD los descarta antes de situar los
    ; datos en RAM. En nuestro ensamblado, en cambio, la cabecera SI
    ; ocupa espacio fisico antes de RELOCATOR (que por eso cae en $FA07,
    ; no en $FA00). Usar la etiqueta aqui produciria valores erroneos.
    DW $FA00, $FA32, $FA00

    INCLUDE "load_disk/madmix0_body.asm"

    ; A diferencia de MADMIX1.BIN/MADMIX.SCR (que excluyen su propia
    ; cabecera BLOAD del SAVEBIN), MADMIX0.BIN la incluye -- misma
    ; convencion que ya usaba el madmix0.asm original (asimetria ya
    ; documentada en FINDINGS.md, no es un error).
    SAVEBIN "build/disk/MADMIX0.BIN", MADMIX0_HEADER_START, END_OF_FILE_M0-MADMIX0_HEADER_START

; --- TEST.BIN (version de cinta): motor de deteccion de RAM/slots,
; 253 bytes. Vive en $C350, direccion ya usada arriba por
; madmix1_body.asm (driver de sonido) -- ver comentario del bloque
; MADMIX0.BIN. Sin cabecera BLOAD: los bloques de cinta llevan su
; propia cabecera de 6 bytes (start/end/exec) en el framing del
; .cas, fuera del fichero en si. ---
    ORG $C350

    INCLUDE "load_cas/test_bin_body.asm"

    SAVEBIN "build/cas/TEST.BIN", DETECTAR_SLOTS_RAM, END_OF_FILE_TESTBIN-DETECTAR_SLOTS_RAM

; --- LOAD.BIN (version de cinta): el orquestador real de la carga
; por cinta, 299 bytes. Vive en $DDA0, direccion que SOLO se ha
; visto documentada antes como "manejador de interrupcion, residuo
; de RAM en vivo" (ver FINDINGS.md) -- NO forma parte de los bytes
; reales de MADMIX1.BIN (que termina justo antes), asi que no hay
; conflicto real con madmix1_body.asm. ---
    ORG $DDA0

    INCLUDE "load_cas/load_bin_body.asm"

    SAVEBIN "build/cas/LOAD.BIN", ORQUESTADOR_CARGA_CINTA, END_OF_FILE_LOADBIN-ORQUESTADOR_CARGA_CINTA

; --- LOGOTOPO.CM (version de cinta): el logo de Topo Soft, 4253
; bytes. Vive en $9470, direccion que coincide con el rango ESTATICO
; de MADMIX1.BIN (fuente de caracteres/sprites, $92E3-$B93B) -- mismo
; patron ya verificado con TEST.BIN/$C350 (driver de sonido, ver
; arriba): SAVEBIN toma una foto del buffer en su propio momento, en
; orden de fuente, asi que no hay conflicto real mientras este bloque
; vaya DESPUES del de MADMIX1.BIN. EN PROGRESO -- transcripcion
; parcial, ver logotopo_cm_body.asm. ---
    ORG $9470

    INCLUDE "load_cas/logotopo_cm_body.asm"

    SAVEBIN "build/cas/LOGOTOPO.CM", ENTRADA_LOGOTOPO, END_OF_FILE_LOGOTOPO-ENTRADA_LOGOTOPO
