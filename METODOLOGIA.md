# Metodología del proyecto — cómo se ha hecho Mad Mix Game (ingeniería inversa)

*[Read this in English](METODOLOGIA.en.md)*

*Documentación del proceso: Rafael Eduardo Martín Candial (raemca@hotmail.com), con Claude (Anthropic) como asistente técnico*

## 0. Qué es este documento y qué NO es

Este proyecto ya tiene tres documentos que explican el **resultado**
técnico desde ángulos distintos:

- `src/FINDINGS.md` — el diario cronológico de descubrimientos, con
  todo el razonamiento, los callejones sin salida y las correcciones,
  en el orden en que ocurrieron.
- `src/FLUJO_PROGRAMA.md` — el mismo conocimiento reorganizado por
  flujo de ejecución, para leer el motor del juego de un tirón.
- `manuales/` — manuales de referencia por subsistema, pensados como
  material de formación, sin el proceso de investigación por medio.

Ninguno de los tres explica **el propio proceso**: cómo se ha
trabajado, con qué disciplina, en qué orden se ha ido abordando el
problema, qué herramientas se han construido y por qué, y qué errores
se han cometido y corregido por el camino. Ese es el objetivo de este
documento — un nivel de zoom distinto, el del *método* más que el del
*resultado*.

Vale la pena decirlo desde ahora: el propio método que describe este
documento — leer ensamblador Z80 con criterio propio, diseñar la
arquitectura de un proyecto de compilación completo, juzgar si una
hipótesis técnica se sostiene — exige un perfil técnico real:
conocimientos de desarrollo de software, de ensamblador Z80 y de la
arquitectura concreta del MSX (VDP, PSG, mapa de memoria,
interrupciones).

*(Ver también `REFLEXION_COLABORACION_IA.md` para el análisis, aparte,
de cómo ha funcionado en concreto la colaboración entre una persona y
un asistente de IA a lo largo de este proyecto — este documento se
centra en el proceso técnico en sí.)*

## 1. Punto de partida

El objetivo declarado desde el principio (ver cabecera de
`FINDINGS.md`) es reconstruir *Mad Mix Game* (Topo Soft, 1987/88,
MSX1) como **código fuente ensamblable real**, verificado byte a byte
contra los binarios originales — no un clon, no una reimplementación
libre, sino la reconstrucción del propio código fuente perdido,
incluyendo sus bugs, sus decisiones de diseño extrañas y su estilo de
programación real de la época.

El material de partida era mínimo: los ficheros de un disquete de
1987/88 (`AUTOEXEC.BAS`, `MADMIX.BAS`, `MADMIX0.BIN`, `MADMIX1.BIN`,
`MADMIX.SCR`) y, más tarde, una cinta de 1988 con una distribución
distinta de los mismos binarios. Sin código fuente original, sin
mapas de símbolos, sin documentación de Topo Soft — solo los binarios
compilados y el propio juego jugable en un emulador.

El trabajo empezó como una serie de sesiones de chat sueltas en
claude.ai (análisis estático con `z80dasm` e inspección manual byte a
byte, sin emulador ni depurador), y en algún punto se trasladó a
Claude Code, con `FINDINGS.md` funcionando desde entonces como
"puente de contexto" explícito entre sesiones — la primera línea del
propio fichero lo dice literalmente. El repositorio Git público es
mucho más reciente que el propio trabajo: se inicializó el 8 de
agosto de 2026 con un volcado del progreso ya alcanzado hasta ese
momento; el propio `FINDINGS.md` contiene referencias a fechas de
mediados de julio, así que el trabajo real llevaba ya semanas en
marcha antes de tener control de versiones.

### Del análisis estático al análisis en vivo

Durante las primeras sesiones todo el trabajo fue estático:
desensamblar con Z80Dasm y leer bytes a mano. Ese enfoque llegó muy
lejos (el arranque, la API del VDP, el mapa de memoria inicial), pero
se atascó con los niveles: durante varias sesiones se buscaron los 15
niveles en `MADMIX1.BIN` sin encontrarlos, y `FINDINGS.md` acabó
registrando la recomendación explícita de cambiar de método — *"el
camino más rápido desde aquí es EN VIVO, no estático"*.

El cambio fue pasar al depurador de openMSX. Un solo watchpoint de
escritura sobre el buffer de la loseta actual
(`debug set_watchpoint write_mem {0xfc60 0xfe5f}`) y arrancar el
nivel 1 bastó para que el primer *break* señalara el cargador de
niveles real, y con él que los niveles no estaban en `MADMIX1.BIN`
sino en `MADMIX.SCR` — el propio diario lo describe como *"el
hallazgo más importante de varias sesiones"*. A partir de ahí se
añadieron los volcados de RAM y VRAM en vivo
(`save_debuggable memory`/`save_debuggable VRAM`, guardados en
`dump_openmsx/`), que sirvieron después como referencia para
verificar, por ejemplo, el color real del marco de caramelo (Fase 4).

El reparto en esta parte también es claro: la IA proponía qué
watchpoint o qué volcado haría falta y por qué, y el técnico lo
ejecutaba en el emulador y traía el resultado. El análisis estático
no se abandonó — siguió siendo la herramienta principal —, pero desde
entonces, cuando una pregunta llevaba demasiado tiempo sin salir de
los bytes, la opción de mirarlo en vivo estaba siempre sobre la mesa.

## 2. El principio rector: verificación byte a byte como contrato de confianza

Si hay una sola idea que explica cómo se ha construido todo este
proyecto, es esta: **ninguna afirmación sobre el código se da por
buena hasta que se verifica contra los bytes reales del binario
original**. No "creo que esto es así", sino "compilo este bloque
aislado y comparo, byte a byte, contra el `.BIN`/`.dsk`/`.cas` real".

Esta disciplina aparece una y otra vez en `FINDINGS.md`, casi como un
estribillo: *"0 diferencias byte a byte"*, *"verificado compilando el
bloque aislado con `ORG $C4A0`"*, *"confirmado contra un volcado de
VRAM real"*. No es un detalle técnico secundario — es el mecanismo
que ha permitido que un proyecto con cientos de rondas de cambios,
renombrados y reorganizaciones **nunca se haya desviado silenciosamente**
del original sin que alguien se diera cuenta. Cada hipótesis (¿qué
hace esta rutina?, ¿qué formato tienen estos datos?) se trataba como
provisional hasta que había una comprobación objetiva que la
confirmara o la descartara.

Ejemplos concretos de esta disciplina aplicada en la práctica:

- El **mapa de memoria completo** (`0x8400`-`0xDDA0` de
  `MADMIX1.BIN`, y el equivalente para `MADMIX.SCR`) se declaró
  "completo" únicamente cuando la recompilación reproducía el binario
  original con 0 diferencias en cada tramo, tramo a tramo.
- Los **64 sprites de personajes** se localizaron primero por una
  pista estructural (una tabla de 64 punteros con paso fijo de 144
  bytes cayendo dentro de un hueco sin descifrar), pero **no se dieron
  por resueltos hasta que el propio técnico los identificó a simple
  vista** sobre un render crudo sin
  ninguna hipótesis de formato previa — combinando evidencia
  estructural (de la IA) con conocimiento vivido (del técnico).
- El **`.dsk`/`.cas` reconstruidos** no se consideran terminados
  porque "compilan sin errores" — se consideran terminados porque se
  generan desde cero (sin partir de una copia del original a
  parchear) y la comparación byte a byte contra los originales reales
  da una lista **cerrada y explicada** de diferencias (el bug
  deliberadamente corregido del nivel 13, y un puñado de bytes ajenos
  ya documentados) — nunca una lista abierta de "cosas raras sin
  explicar".
- El 10 de agosto de 2026, al corregir el formato real de los sprites (ver
  Fase 3 más abajo, y el caso completo en `REFLEXION_COLABORACION_IA.md`),
  la verificación fue empírica antes que teórica: se
  probaron tres hipótesis de reagrupado de los mismos bytes
  renderizándolas, y solo se adoptó la que no dejaba ningún artefacto
  visual sin explicar — no se aceptó "parece razonable", se exigió
  "se ve limpio en las 64 entradas".

## 3. Fases del trabajo, en orden

### Fase 0 — Arranque: los tres binarios del disco

Desensamblado manual de `MADMIX0.BIN` (58 bytes, el "relocador" —
resultó tener **dos puntos de entrada independientes**, no uno, un
hallazgo temprano que obligó a revisar la primera hipótesis) y
localización de la secuencia de arranque completa desde el propio
`.BAS` tokenizado (confirmando byte a byte, en el volcado crudo de
BASIC, la dirección exacta `&HFA2A` que arranca el motor real).

### Fase 1 — Arquitectura básica: memoria, interrupciones, VDP

Mapa de memoria inicial de `MADMIX1.BIN`, identificación del vector
de interrupción VBLANK parcheado en caliente, y reimplementación
propia (no BIOS) de las 3 rutinas clásicas de acceso a VRAM
(`FILVRM`/`LDIRVM`/`SETVRAM`) — confirmadas contiguas en memoria y
con pequeñas diferencias reales respecto a lo que se había asumido
inicialmente (bucles anidados en vez de resta de 16 bits, saltos
largos en vez de cortos, un retardo `EX (SP),HL` que exige el propio
VDP).

### Fase 2 — El sistema de losetas y el motor de colisión

Localización de la tabla de tipos de loseta (con un error de offset
y tamaño corregido leyendo el `.BIN` byte a byte) y, sobre todo, un
cambio de entendimiento importante: la tabla de "tipos" **no
distingue muro de suelo** como se asumía — esa distinción vive en
otro mecanismo (rango del índice gráfico crudo), y "tipo" codifica
más bien comportamientos especiales superpuestos. Aquí también se
documentó la mecánica de trampillas en L (3 estados, 12 losetas) a
partir de la explicación del técnico de cómo se juega esa mecánica en
la práctica.

### Fase 3 — El "hueco grande": sprites, fuente de texto, textos nunca vistos

La zona `0x8F74`-`0xB940` (~10.700 bytes) fue el tramo más difícil de
resolver, y se hizo **por capas sucesivas**, cada una desbloqueando la
siguiente: primero se confirmó que `INIT` nunca hace `RET` y cae en
el bucle principal (449 bytes); luego aparecieron textos de partida
nunca vistos hasta entonces (`"FASE 00"`, `"READY?"`, `"ESTAS
FRITO"`) junto con una tabla de 64 punteros de paso fijo; esa tabla
resultó ser la clave para localizar **los 64 sprites de personajes**
(9216 bytes, identificados a simple vista por el técnico); y los 600
bytes que quedaban resultaron ser la fuente de caracteres del juego,
confirmada por fórmula real de dirección de glifo. Solo entonces todo
el tramo `0x8400`-`0xD500` quedó a 0 diferencias.

### Fase 4 — El "marco de caramelo" y el color real de pantalla

Un hallazgo con una vuelta atrás incluida: un bloque de 768 bytes se
investigó y **se descartó** en una sesión como "textura/sombreado de
fondo" — y en una sesión posterior resultó ser exactamente lo que se
había descartado: el color real (rojo/blanco/gris) del marco de
caramelo del HUD, aplicado a la tabla de color de VRAM. Verificado
comparando la transformación real contra un volcado de VRAM en vivo.
Por separado, la propia *forma* del marco (no su color) se localizó
como una tabla RLE cuyas repeticiones sumaban exactamente el tamaño
de la tabla de patrones de pantalla completa — confirmado
renderizándola y comparando pixel a pixel contra una reconstrucción
real de pantalla.

### Fase 5 — El driver de sonido: un lenguaje de bytecode propio

Reconocido que el bloque `0xC4A0`-`0xD000`, que se creía un "gestor
de recursos genérico", es en realidad el **driver de sonido/música
del PSG AY-3-8910** — un intérprete de bytecode propio de Topo Soft,
con 15 comandos descifrados uno a uno. Sobre esa base se construyeron
dos herramientas (`tools/mmsnd_tool.py`, descompilador/compilador
verificado con *roundtrip* byte a byte; `tools/mmsnd_render.py`, un
renderizador a WAV) que se fueron afinando en **rondas sucesivas de
escucha real** por parte del técnico — cada ronda encontró un bug de
verdad en el renderizador (polaridad del mezclador invertida,
detección de fin de bucle rota, mapeo de campos del instrumento
equivocado), nunca "sonaba raro, lo dejamos así".

### Fase 6 — Subsistema de items especiales y la IA de los 3 tipos de entidad

Descifrado del subsistema que gestiona bola de poder, hipopótamo,
herramienta y las pistas de tanque/avión, y de la "IA" (sin
pathfinding real) de fantasmas, mariquita y "repugnantoso" — cada uno
con su propio efecto al llegar a su sitio (perseguir, regenerar
bolitas comidas, plantar bolas nuevas).

### Fase 7 — Los niveles, y el caso del "nivel oculto" que no lo era

Localización de los 15 niveles jugables (cuerpos + cabeceras
compartidas), incluido un 15º nivel que en un primer momento parecía
**contenido real pero sin ningún registro que lo referenciara** — una
sesión posterior encontró que sí tenía registro real en la tabla de
niveles (mal etiquetado como "20 bytes sin identificar") y que se
alcanza jugando con total normalidad al completar el nivel 14. Este
caso concreto se explica con más detalle en §5 (más abajo), porque se
repitió — con matices distintos — dos veces en la historia del
proyecto.

### Fase 8 — Unificación: de ficheros sueltos a un proyecto compilable de verdad

Una vez identificado el contenido, una fase entera se dedicó a la
**arquitectura del propio proyecto de reconstrucción**: unificar
`madmix1.asm`/`madmix_scr.asm` en una sola pasada de ensamblado
(`main.asm`, compartiendo espacio de símbolos para que las llamadas
cruzadas usaran etiquetas reales en vez de hex), reconstruir también
los cargadores de disco y cinta (`load_disk/`/`load_cas/`), y
construir los scripts que compilan y empaquetan **todo el proyecto de
un tirón** (`tools/build_all.py`, `tools/gen_disk_and_cas.py`) — con
el `.dsk` construido desde cero (FAT12 real, no una copia parcheada).

### Fase 9 — Refactorización sostenida: cientos de rondas pequeñas

La mayor parte del volumen de `FINDINGS.md` (aproximadamente 370
hitos y rondas registrados, la inmensa mayoría en un solo tramo
central del diario) no son grandes descubrimientos sino un trabajo de
fondo constante: sustituir direcciones hex sueltas por etiquetas
reales una vez que ya se conocía su nombre, traducir etiquetas en
inglés/crípticas a español descriptivo, convertir hex a decimal donde
tiene más sentido de lectura, añadir comentarios línea a línea,
extraer datos embebidos (tiles, sprites, sonido, niveles) a ficheros
individuales editables, y mantener sincronizados los visores HTML
cada vez que cambiaba algo. Ningún cambio de este tipo se dio por
bueno sin recompilar y comprobar que el binario seguía siendo
idéntico.

Cada ronda seguía el mismo ciclo, que se repite casi literal en las
entradas de `FINDINGS.md`:

1. **Encargo concreto** del técnico: reanalizar una tabla, renombrar
   una familia de etiquetas, sustituir unos `CALL` en hex.
2. **Análisis** del código que usa ese dato o esa rutina, cruzando
   todos sus consumidores antes de cambiar nada.
3. **Cambio** en el código fuente (o, en tandas grandes, primero una
   propuesta "sin aplicar" para que el técnico la revisara).
4. **Recompilación y comparación** contra los binarios originales: el
   resultado tiene que caer exactamente en la línea base de
   diferencias ya conocidas y explicadas, ni una más.
5. **Regeneración** de los entregables (`.dsk`, `.cas`, inventario de
   etiquetas, visores HTML).
6. **Registro** en `FINDINGS.md`: qué se hizo, qué se corrigió de
   rondas anteriores y el resultado de la verificación.

### Fase 10 — Documentación de referencia y publicación

Con el código ya completo y estable, se escribieron los manuales de
`manuales/` (uno por subsistema, sin el proceso de investigación por
medio) y se reescribió `FLUJO_PROGRAMA.md` desde cero (había quedado
congelado en una etapa muy temprana). Se creó el repositorio Git
público, con su aviso legal separando claramente qué es del juego
original (Topo Soft) y qué es del propio trabajo de ingeniería
inversa.

## 4. Herramientas construidas

Todas viven en `tools/`, todas se pueden invocar sueltas, y todas
tienen alguna forma de verificación de *roundtrip* (decodificar y
volver a codificar reproduce el binario original exacto):

| Herramienta | Qué hace |
|---|---|
| `build_all.py` | Compila todo el proyecto de un tirón (`sjasmplus main.asm`) |
| `gen_disk_and_cas.py` | Genera los 2 entregables finales (`.dsk`/`.cas`) desde cero |
| `gen_dsk_file.py` | Construye el `.dsk` completo (boot sector, FAT12, directorio, datos) sin partir de una copia |
| `gen_cas_bin.py`/`gen_cas_file.py` | Construyen el `.cas` real (sincronismo, cabeceras, bloques) |
| `mmsnd_tool.py` | Descompilador/compilador del bytecode de sonido, con *roundtrip* |
| `mmsnd_render.py` | Renderizador del bytecode de sonido a WAV, para poder escucharlo sin el juego |
| `mmlvl_tool.py` | Descompilador/compilador de las rejillas de nivel, con comprobación de objetivo de bolitas |
| `msxbasic_tool.py` | Detokenizador/tokenizador de BASIC MSX |
| `gen_inventory.py` | Genera el inventario buscable de todas las etiquetas del proyecto |
| `gen_flow_diagram.py` | Genera el grafo de llamadas reales entre funciones |

Y las herramientas externas de las que depende el proyecto:

| Herramienta | Versión | Para qué se ha usado |
|---|---|---|
| Z80Dasm (*Portable Z80 disassembler*, Marcel de Kogel) | 1996-1997 (sin número de versión) | Desensamblado de los binarios originales (`-begin`/`-offset` para cada tramo) |
| sjasmplus | 1.23.0 | Ensamblado de todo el proyecto (`main.asm`) |
| openMSX | 21.0 | Ejecución del juego, depurador (watchpoints, consola Tcl) y volcados de RAM/VRAM en vivo |
| Python | 3.13.14 | Todos los scripts de `tools/` |
| Claude (Anthropic) | claude.ai y Claude Code | Asistente técnico durante todo el proyecto |

## 5. Errores cometidos y cómo se corrigieron

Ser honesto sobre esto es parte del método, no una excepción a él.
Casos documentados de conclusiones que resultaron estar equivocadas,
y cómo se detectaron:

- **El "nivel oculto"**: documentado primero como contenido real pero
  sin conexión al resto del juego; corregido al encontrar su registro
  real en la tabla de niveles. Vuelto a corregir el 10 de agosto de
  2026, porque la documentación seguía usando la etiqueta
  "oculto" en varios sitios como si fuera el estado vigente en vez de
  una fase ya superada.
- **El formato de los 64 sprites de personajes**: se documentó
  primero como una única imagen de 24×48 píxeles por entrada, lectura
  que producía sprites reconocibles pero con rayas horizontales de
  fondo. Corregido el 10 de agosto de 2026 al comprobar empíricamente que son
  en realidad 24×24 con dos planos entrelazados fila a fila
  (máscara + patrón) — ver el caso completo en
  `REFLEXION_COLABORACION_IA.md`.
- **El crédito musical del juego**: una edición en GitHub cambió
  `"COMILONAS"` por `"GOMILONAS"` creyendo corregir una errata; la
  verificación contra el código fuente (`DB "COMILONAS"` en
  `madmix_scr_body.asm`) mantuvo el dato original — ver el caso en
  `REFLEXION_COLABORACION_IA.md`.
- **La tabla `TILE_TYPES`**: la hipótesis inicial de que codificaba
  muro/suelo se descartó explícitamente al encontrar que las 45
  losetas de muro comparten tipo con el suelo llano — el propio
  documento lo señala como "un cambio de entendimiento importante",
  sin intentar disimularlo.

## 6. Estado actual

- Los 3 binarios del disco (`MADMIX0.BIN`, `MADMIX1.BIN`,
  `MADMIX.SCR`) y los de la cinta (`LOAD.BIN`, `TEST.BIN`,
  `LOGOTOPO.CM`) están completos y compilan a 0 diferencias byte a
  byte contra los originales, salvo las desviaciones ya documentadas
  y explicadas (bug corregido del nivel 13, un puñado de bytes
  ajenos).
- El `.dsk` y el `.cas` reconstruidos cargan y funcionan en openMSX,
  confirmado en ambas versiones.
- Quedan puntos genuinamente abiertos y señalados como tales en cada
  manual y en `FINDINGS.md` — este proyecto no pretende tener el
  100% de cada byte explicado en su propósito, solo el 100% de los
  bytes reproducidos exactos, con lo que no se entiende del todo
  marcado explícitamente como pendiente en vez de disimulado.

## 7. Lecciones trasladables a otros proyectos

Lo que, a la vista de todo lo anterior, aplicaría desde el primer día
en otro juego, de esta o de otra máquina de 8 bits:

1. **Fijar un árbitro objetivo antes de empezar.** Aquí, recompilar y
   comparar byte a byte. Y mantener una línea base de diferencias
   conocidas y explicadas, para que cualquier diferencia nueva salte
   a la vista.
2. **Usar control de versiones desde el principio.** En este proyecto
   Git llegó semanas después de empezar; cada ronda debería haber sido
   un commit desde la primera.
3. **Llevar un diario que sirva de puente entre sesiones.** Un fichero
   como `FINDINGS.md`, que registre también los callejones sin salida
   y las correcciones, no solo los aciertos.
4. **Construir herramientas en vez de analizar a mano.** Cada formato
   de datos descifrado merece un script de decodificación y
   recodificación con *roundtrip* verificado.
5. **Combinar análisis estático y en vivo.** Cuando el desensamblado
   se atasca, un watchpoint en el emulador puede resolver en minutos
   lo que llevaba sesiones sin salir.
6. **Tratar toda hipótesis como provisional.** Marcarla como tal,
   aparcarla a propósito si no hay datos suficientes y volver a ella
   con más contexto.
7. **No confundir "reconocible" con "correcto".** Que un sprite se
   identifique o un sonido se parezca no prueba que el formato de
   datos sea el bueno.
8. **Meter la percepción humana en el bucle.** Renderizar a imagen o a
   sonido para que alguien que conoce el juego pueda mirar y escuchar
   es una forma de acotar bytes, no solo de dar el visto bueno al
   final.
9. **Proponer antes de aplicar los cambios masivos.** Un renombrado
   que se extiende por decenas de sitios se revisa mejor como
   propuesta que como cambio ya hecho.
10. **Avanzar en rondas pequeñas, verificadas una a una.** La mayor
    parte del trabajo es poco espectacular, y su valor está en que
    ninguna ronda deje un error sin detectar.
