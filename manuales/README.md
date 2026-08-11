# Manuales

*[Read this in English](README.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

Esta carpeta es distinta de `FINDINGS.md` (diario cronológico de
hallazgos) y de `FLUJO_PROGRAMA.md` (inventario por flujo de
ejecución). Ahí se documenta **cómo se descubrió** cada cosa, en el
orden en que se investigó, con toda la incertidumbre y los callejones
sin salida por el camino.

Aquí, en cambio, se documenta **cómo funciona** cada subsistema ya
entendido, de forma ordenada y pedagógica — como si fuera el manual
técnico que un programador de la época le habría dejado a un
compañero nuevo. Dos objetivos concretos:

1. **Formación**: que un programador que se incorpore al proyecto (o a
   cualquier ingeniería inversa parecida) pueda aprender el
   funcionamiento real de cada pieza sin tener que reconstruir el
   proceso de investigación completo.
2. **Preservación**: dejar constancia clara y legible de cómo está
   construida esta pieza de arqueología del software de 8 bits, más
   allá del propio código fuente reconstruido.

Cada manual asume que quien lo lee sabe ensamblador Z80 y programación
en general, pero **no** da por hecho nada específico de este proyecto
ni del hardware de sonido del MSX — eso se explica desde cero la
primera vez que hace falta.

## Índice

- [`manual_driver_sonido.md`](manual_driver_sonido.md) — el driver de
  sonido/música del PSG AY-3-8910 (`madmix1_body.asm`, región
  `$C4A0`-`$CF8D`): arquitectura, el lenguaje de bytecode de 15
  comandos, las tablas de datos, el mecanismo de disparo de efectos
  (`EVENTO_SONIDO_PENDIENTE`), y las herramientas para editar y
  escuchar los sonidos.
- [`manual_motor_colision_ia.md`](manual_motor_colision_ia.md) — el
  motor de movimiento/colisión (`madmix_scr_body.asm`), la tabla de
  despacho de 20 tipos de loseta, y la IA de los 3 tipos de item móvil
  (fantasmas, mariquita, "repugnantoso"): cómo deciden dirección, qué
  hace cada uno al llegar a su sitio, y los modos especiales
  (bola de poder/hipopótamo/herramienta) que dispara pisarlos.
- [`manual_subsistema_grafico.md`](manual_subsistema_grafico.md) — el
  VDP en `SCREEN 2`, la API de VRAM propia (no la BIOS), y por qué el
  motor de actores no usa nunca los sprites hardware del MSX: compone
  cada personaje a mano con máscaras AND/OR y desplazamiento sub-pixel,
  el mismo enfoque que un juego de ZX Spectrum. También el sistema de
  losetas del laberinto, el scroll por software (4px, `RLD`/`RRD`), y
  cómo se gestiona el color de pantalla.
- [`manual_niveles.md`](manual_niveles.md) — el formato de los 15
  niveles: el registro de 20 bytes, la tabla de 16 entradas (el
  registro 0 es un duplicado muerto), los 13 cuerpos + 3 cabeceras
  compartidas, el comodín `$3C`, cómo se detecta el fin de nivel, el
  modo demo del menú, y la herramienta `mmlvl_tool.py` para editarlos.

*(Se irán añadiendo más manuales aquí a medida que se decida qué otras
partes del sistema documentar de esta forma.)*
