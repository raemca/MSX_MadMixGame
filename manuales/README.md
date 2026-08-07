# Manuales

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial*

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
  (`$6128`), y las herramientas para editar y escuchar los sonidos.

*(Se irán añadiendo más manuales aquí a medida que se decida qué otras
partes del sistema documentar de esta forma.)*
