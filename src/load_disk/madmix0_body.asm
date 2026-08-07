; ============================================================
;  MADMIX0.BIN (Topo Soft, 1987) - MSX1
;  El "relocador" -- 58 bytes, desensamblado completo y verificado
;  directamente con Z80Dasm (offset de cabecera correcto), sin
;  ambiguedad. Confirma y AMPLIA lo que decia FINDINGS.md: tiene
;  DOS puntos de entrada, no uno.
;
;  - 0xFA00 (RELOCATOR, la direccion "exec" de su propia cabecera
;    BLOAD): guarda la configuracion de slot primario (puerto
;    $A8) en $FFFD, la retuerce (SRL x4 + OR con el valor original)
;    y guarda ESE resultado en $FFFE tambien, conmuta a RAM en la
;    pagina 0, hace el LDIR de 0x5500 bytes desde 0x8800 (donde
;    acaba de aterrizar MADMIX.SCR) a 0x1000, llama a 0x1000
;    (arranca el dibujado de portada -- ver madmix_scr_body.asm,
;    DIBUJAR_PORTADA), restaura el slot desde $FFFD, EI, RET. Es el
;    que se ejecuta automaticamente via "BLOAD MADMIX0.BIN,R"
;    justo despues de cargar MADMIX.SCR.
;
;  - 0xFA2A (JUMP_TO_ENGINE): un SEGUNDO punto de entrada,
;    independiente del primero (no se llega aqui por caida, el RET
;    de arriba ya ha devuelto el control antes). Restaura la OTRA
;    configuracion de slot guardada (desde $FFFE, no $FFFD) y salta
;    directo a 0x8400 (JT_INICIO de MADMIX1.BIN). Candidato fuerte a
;    ser invocado por un CALL/USR explicito desde el BASIC
;    orquestador, DESPUES de haber cargado tambien MADMIX1.BIN (que
;    en su propio BLOAD no lleva ",R" -- alguien tiene que arrancarlo
;    a mano, y esta es la pieza que falta para ese hilo).
; Ingeniería inversa, herramientas y documentación de este proyecto: Rafael Eduardo Martín Candial
; ============================================================

RELOCATOR:
    DI
    IN A, ($A8)          ; lee configuracion de slot primario
    LD B, A
    LD ($FFFD), A         ; guarda config actual (para restaurarla luego)
    SRL A
    SRL A
    SRL A
    SRL A
    OR B
    LD ($FFFE), A          ; guarda una SEGUNDA config (retorcida), para
                            ; el otro punto de entrada de mas abajo
    OUT ($A8), A            ; conmuta slots (RAM en pagina 0)
    LD HL, $8800
    LD DE, $1000
    LD BC, $5500
    LDIR                      ; copia 0x5500 bytes de 0x8800 a 0x1000
    CALL DIBUJAR_PORTADA          ; ejecuta el bloque reubicado (portada)
    LD A, ($FFFD)
    OUT ($A8), A                ; restaura slots
    EI
    RET

JUMP_TO_ENGINE:
    DI
    LD A, ($FFFE)
    OUT ($A8), A                ; restaura la OTRA configuracion de slot
    JP START                     ; salta directo a JT_INICIO (MADMIX1.BIN)

END_OF_FILE_M0:
