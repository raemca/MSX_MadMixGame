# Reflexión: colaborar con IA en un proyecto técnico de largo aliento

*[Read this in English](REFLEXION_COLABORACION_IA.en.md)*

*Rafael Eduardo Martín Candial (raemca@hotmail.com), con Claude (Anthropic) como asistente*

## Por qué este documento

`METODOLOGIA.md` cuenta *qué* se ha hecho y en qué orden. Este
documento es distinto: es una reflexión sobre *cómo* ha sido trabajar
así — una persona con perfil técnico real (desarrollo de software,
ensamblador Z80, arquitectura del propio MSX) y un asistente de IA
sin memoria entre sesiones propia, apoyándose en un fichero de texto
(`FINDINGS.md`) como puente. No es una pieza de marketing sobre lo
bien que funciona la IA, ni una queja sobre sus límites — es un
intento honesto de describir la dinámica real, con sus aciertos y sus
fricciones, usando este proyecto concreto como caso de estudio.

Ese perfil técnico importa desde ya: nada de lo que sigue — leer
ensamblador Z80, diseñar la arquitectura de un proyecto de
reconstrucción, evaluar si una hipótesis técnica se sostiene — es
alcanzable sin experiencia real de desarrollo de software y
conocimiento de la arquitectura del MSX.

## El patrón de fondo: verificar, no confiar

Lo primero que hay que decir es que esta colaboración **no se ha
sostenido sobre la confianza ciega en ninguna de las dos partes**. Ni
"la IA lo ha dicho, será verdad" ni "el técnico recuerda el juego,
será verdad". Se ha sostenido sobre un tercer elemento, neutral:
**los bytes reales del binario original**, contra los que se
verificaba cada afirmación antes de darla por buena.

Esto cambia la naturaleza de la colaboración de una forma importante.
Cuando el árbitro final es "recompila y compara", las discrepancias
entre persona e IA dejan de ser un pulso de autoridad y pasan a ser
un problema técnico resoluble. Un ejemplo claro, de esta misma
sesión: el técnico editó directamente en GitHub el nombre del músico
acreditado en los créditos del juego, creyendo corregir una errata
(`"COMILONAS"` → `"GOMILONAS"`). Al fusionar esa rama, en vez de
aceptar sin más el cambio del técnico (es su proyecto, su edición,
hecha con buena intención) ni descartarlo sin más (podría tener razón
— el técnico jugó el juego de verdad), la comprobación fue mecánica:
buscar el byte literal en el código fuente ya verificado
(`DB "COMILONAS"`, extraído directamente de la ROM). El dato ganó, no
la persona ni la IA. Eso se le explicó al técnico con la evidencia
delante, y el propio técnico lo aceptó sin fricción — porque no era
una opinión contra otra, era un hecho verificable.

## Quién aporta qué

A lo largo del proyecto se ve un reparto de papeles bastante nítido,
y vale la pena nombrarlo con precisión porque no es "la IA hace el
trabajo duro y la persona supervisa", ni al revés:

**Lo que aporta la persona — conocimiento que ningún análisis de
bytes puede reconstruir por sí solo:**

- Identificar los 64 sprites de personajes a simple vista sobre un
  render crudo, sin ninguna pista de nombres — reconocer "esto es el
  comecocos con la boca a medio abrir", "esto es el fantasma
  vulnerable" es reconocimiento visual entrenado por haber jugado el
  juego de verdad, no algo que se deduzca de la estructura de los
  datos.
- Explicar mecánicas de juego que no son evidentes desde el código
  (la trampilla en L que se voltea, el orden real de la secuencia de
  animación de muerte del comecocos — "58→59→60→61→40→41→42→43→44",
  que NO es el orden de los índices en la tabla y que nadie habría
  adivinado mirando solo bytes).
- La sospecha inicial que desencadenó la corrección más importante de
  esta sesión (§siguiente): "esto tiene rayas raras, ¿no serán datos
  de dos patrones mezclados, como en la versión de Spectrum?" — una
  intuición basada en conocer *otra* versión del mismo juego, algo
  completamente fuera del alcance de analizar un solo binario MSX.

Y por debajo de estos tres puntos hay una cuarta cosa, distinta de
"conocimiento del juego": criterio técnico de fondo — entender
ensamblador Z80, la arquitectura real del MSX (VDP, PSG, mapa de
memoria) y el propio oficio de desarrollo de software lo bastante
como para juzgar si una propuesta de la IA tiene sentido, o para
decidir la arquitectura del propio proyecto de reconstrucción.

**Lo que aporta la IA — capacidad de proceso sistemático a escala:**

- Comparar binarios byte a byte, una y otra vez, sin fatiga ni
  atajos — la disciplina de verificación descrita en `METODOLOGIA.md`
  solo es sostenible a este volumen si el coste marginal de "vuelve a
  comprobar" es prácticamente cero.
- Sostener cientos de rondas de renombrado/limpieza consistentes sin
  perder de vista las convenciones ya establecidas (nombres en
  español, decimal donde ayuda a leer, etiquetas locales con punto
  para marcas internas de salto).
- Probar hipótesis alternativas rápido cuando hace falta — en la
  corrección del formato de sprites, generar y comparar tres lecturas
  distintas de los mismos bytes en minutos, en vez de razonar en
  abstracto sobre cuál "suena más plausible".

Ninguno de los dos papeles sustituye al otro. La sospecha del técnico
sobre los sprites no habría llegado a ninguna parte sin la
comprobación empírica inmediata; y la comprobación empírica no habría
empezado sin la sospecha, porque el renderizado "oficial" llevaba ya
tiempo dándose por bueno.

## La dirección de la investigación: navegar, no solo validar

Hay una parte del trabajo del técnico que las dos secciones
anteriores dejan fuera, y que en volumen es tan grande como cualquier
otra: **decidir por dónde seguir**. No siempre el siguiente paso lo
proponía la IA con un plan ya armado — muchas veces era una
indicación corta y directa: "revisemos ahora estas variables a ver
qué hacen", "saltemos a esa tabla, puede estar relacionada con esta
función", "intenta relacionar este bloque de datos con tal
estructura". Es un papel de navegación, distinto de aportar
conocimiento del juego (§anterior) y distinto de verificar un
resultado ya obtenido (§siguiente): es decidir *dónde mirar a
continuación* cuando el mapa todavía no está completo.

Ese papel se ve con especial claridad en los tramos donde el propio
`FINDINGS.md` documenta un hilo que se abre, se deja aparcado sin
resolver, y se retoma sesiones después. La zona reutilizada en
`$DC00` es un ejemplo real: se identificó como tabla estática dentro
de un hueco todavía sin descifrar, se dejó **explícitamente marcada
como pendiente** durante un tiempo, y solo se resolvió del todo en
una sesión posterior al conectarla con el mecanismo de máscaras de
recorte de actores — la propia entrada de "hueco grande" resuelto lo
señala como "resuelve la Zona 0xDC00 que quedaba sin descifrar en un
hallazgo de una sesión anterior". Lo mismo pasó con `RM_TABLE_CFA4`:
etiquetada primero como candidata a "tabla de envolvente/percusión de
sonido" solo por estar cerca de las tablas de sonido reales —una
hipótesis débil, dejada así a propósito en vez de forzar una
conclusión— y corregida sesiones más tarde, cuando con el driver de
sonido ya desensamblado por completo quedó claro que ninguna rutina
de sonido la leía, y que en realidad era la cabeza del cuerpo del
nivel 13.

Ese patrón de **aparcar una vía a propósito y volver a ella cuando
hay más contexto**, en vez de forzar una respuesta con lo que se
sabe en ese momento, es una decisión de investigación, no un hallazgo
técnico — y es una decisión que ha tomado sobre todo el técnico,
marcando qué hilos merecía la pena perseguir ya y cuáles convenía
dejar madurar.

## Percepción humana y datos, en bucle: el oído, el ojo y acotar bytes

Hay un tercer patrón de trabajo, distinto de "la persona valida al
final" y de "la persona dirige dónde mirar": la persona y la IA
**acotando el mismo rango de bytes a la vez**, alternando entre
renderizar/generar y percibir. No es un proceso de una sola pasada
(decodificar → escuchar/mirar → aprobar), es un bucle corto que se
repite varias veces sobre el mismo tramo de datos hasta que encaja.

El caso más documentado es el del driver de sonido. Construido el
renderizador (`mmsnd_render.py`), el propio `FINDINGS.md` registra
**rondas sucesivas de escucha real** por parte del técnico, cada una
encontrando algo que sonaba mal y acotando qué comando o qué campo
del instrumento era responsable — hasta encontrar, por ejemplo, que
la polaridad de `SET_MIXER` estaba invertida, o que la detección de
fin de bucle de un script concreto estaba rota y por eso un `.wav`
"no sonaba completo". El oído del técnico no solo confirmaba un
resultado ya cerrado — **acotaba la búsqueda**: "esto no suena bien
en el segundo compás" apuntaba directamente a qué bytes revisar a
continuación, de una forma que ningún análisis puramente estructural
del bytecode podría haber sugerido por sí solo. Un caso concreto
queda incluso confirmado por nombre en el propio catálogo de
sonidos: el efecto asociado al índice 4 se identificó de oído, en
vivo, como "disparo (modo avión)" — un dato que no estaba en ningún
sitio del código, solo en la memoria del técnico al escuchar el
sonido renderizado.

El mismo bucle se repite con las imágenes, con el ojo en vez del
oído. El marco de caramelo del HUD es el ejemplo más claro: un
bloque de 768 bytes se probó a renderizar de una forma, no se
reconoció nada con sentido, y se archivó como "textura/sombreado de
fondo" — una conclusión razonable en su momento, pero equivocada.
Sesiones después, al volver a mirarlo con otra hipótesis de formato
(color, no patrón) y comparar el render resultante contra un volcado
real de VRAM, apareció exactamente lo que se esperaba: rayas
rojiblancas, esquinas redondeadas, el motivo de brillo. El propio
proceso de "generar una imagen candidata, mirarla, decidir si tiene
pinta de ser lo correcto o hay que probar otra interpretación" es
igual de mecánico que el bucle de escucha del sonido, solo que con
percepción visual en vez de auditiva — y es el mismo bucle que,
meses después, destapó el error del formato de los sprites (visto en
detalle en la sección siguiente).

## El caso completo: cuando la IA se equivoca y el técnico lo nota

Vale la pena reconstruir este caso entero porque resume bien la
dinámica. En una sesión anterior, se localizaron los 64 sprites de
personajes y se decodificaron como 144 bytes por entrada, reagrupados
en 48 filas de 24 píxeles de ancho — un formato que producía sprites
**reconocibles**, y que el propio técnico había confirmado
identificando cada uno a simple vista. Con esa validación por delante,
el formato se dio por "confirmado visualmente" y se usó así, sin más
revisión, en varias páginas del proyecto (el catálogo de sprites, el
póster/dossier visual) durante bastante tiempo.

El problema es que "reconocible" no es lo mismo que "correcto". El
técnico, mirando el catálogo ya publicado, notó algo que no encajaba:
un fondo con rayas horizontales blancas y negras, y una proporción
"alargada" que no cuadraba con lo que recordaba del juego original —
y lo conectó con un dato externo, que en la versión de ZX Spectrum
del mismo juego los sprites son de 24×24 con dos patrones, no de
24×48 con uno solo.

En vez de defender el formato ya "confirmado" (que además llevaba una
validación previa del propio técnico), la respuesta fue ponerlo a
prueba de verdad: generar las tres interpretaciones posibles de los
mismos 144 bytes por separado — 48 filas seguidas (la vieja lectura),
dos bloques de 24 filas apilados, y filas entrelazadas par/impar — y
mirarlas. Solo la tercera no tenía rayas. Encajaba, además, con algo
que ya estaba documentado sin conectar: el algoritmo de dibujado de
actores usa una máscara AND seguida de un patrón OR, un blitting
clásico que necesita exactamente dos planos del mismo tamaño — la
pieza que faltaba llevaba semanas descrita en otro documento
(`manual_subsistema_grafico.md`) sin que nadie hubiera unido los dos
hilos.

La lección no es "la IA se equivocó" ni "el técnico tenía razón" —es
que **una validación visual pasada ("se reconoce el personaje") no
prueba que el modelo de datos sea correcto**, solo que es
suficientemente parecido para el ojo humano. Hicieron falta dos cosas
para encontrar el error: que alguien con el contexto adecuado (haber
jugado la versión de Spectrum) notara que algo no encajaba del todo,
y que hubiera un mecanismo barato para comprobarlo de verdad en vez
de discutirlo en abstracto.

## Decisiones sin respuesta en los bytes: nombrar y comentar

No todo en este proyecto se resolvía comparando binarios. Hay una
categoría entera de decisiones —qué nombre le queda mejor a una
función, qué comentario explica de verdad por qué existe una tabla,
qué merece una etiqueta propia y qué se queda como interna— donde
**no existe un byte que arbitre quién tiene razón**, porque no es una
pregunta sobre el binario, es una pregunta sobre cómo se lee mejor el
resultado. Ahí la dinámica cambia: unas veces ha pesado más el
criterio del técnico (cómo prefiere llamarse algo, qué terminología
propia usar en español en vez de una traducción literal del inglés),
y otras veces ha pesado más una conclusión de la IA respaldada en
datos de uso real del código — no una preferencia estética, sino
"este nombre ya no describe lo que hace, y aquí está el motivo".

El ejemplo más claro de lo segundo es un renombrado que se corrigió a
sí mismo: una variable se llamó primero
`SELECTOR_DIRECCION_SCROLL_FINO`, un nombre razonable dado dónde
vivía y cómo se usaba en una primera lectura. Analizando con más
detalle el código que la consume, quedó claro que ese valor no
controla ningún desplazamiento de scroll — es el **frame de
animación real del comecocos** (boca abierta/cerrada, orientación).
El propio `FINDINGS.md` lo registra como "corrección importante" y
la renombra a `SELECTOR_SPRITE_COMECOCOS`. Nadie "tenía razón" en el
nombre original — era la mejor hipótesis disponible con lo que se
sabía entonces, y se corrigió en cuanto el análisis del código real
la contradijo, exactamente igual que se corregiría un error de
formato de datos.

También hay un patrón visible de **proponer antes de aplicar**: para
tandas grandes de renombrado (por ejemplo, toda la familia de
etiquetas internas del motor de actores, o las del motor de
movimiento de items) el proceso habitual no era renombrar
directamente, sino dejar primero un "estudio, sin aplicar" con la
propuesta completa de nombres en español, y solo convertirlo en
cambios reales en una ronda posterior. Ese paso intermedio es,
literalmente, el espacio para que el técnico esté de acuerdo o pida
otro nombre antes de que el cambio se extienda por decenas de sitios
del código — una decisión editorial deliberada, no una verificación
técnica.

## Fricciones reales, no solo aciertos

Sería deshonesto describir solo lo que ha ido bien. Algunas cosas no:

- **Confusión repetida con el flujo de commits de Git.** Dos veces en
  la misma sesión el técnico se quedó bloqueado pensando que "el
  commit no funciona", cuando en realidad `git commit` sin mensaje
  había abierto un editor esperando texto — no un fallo técnico, sino
  una interfaz (la de VS Code more que la de git en sí) que no
  comunicaba bien lo que estaba pasando. Diagnosticarlo fue rápido,
  pero que ocurriera dos veces sugiere que la explicación la primera
  vez no dejó un modelo mental claro de por qué pasaba, solo
  resolvió el síntoma puntual.
- **Configuración contaminada por sesiones sueltas.** Con el tiempo,
  los ficheros de permisos de la propia herramienta (`.claude/settings.json`
  y `settings.local.json`) habían acumulado decenas de reglas que
  apuntaban a carpetas temporales de sesiones ya cerradas — literalmente
  inservibles incluso en la misma máquina, porque cada sesión nueva
  genera una carpeta distinta. Nadie las había estado limpiando
  activamente; se acumularon como residuo hasta que hizo falta un
  repaso explícito para "hacer portable la configuración" y darse
  cuenta de que gran parte de esas reglas nunca habían sido
  reutilizables, ni siquiera localmente.
- **El límite real de "hacerlo todo en una sesión".** El encargo de
  traducir todo el proyecto al inglés incluía `FINDINGS.md`, un
  diario de ~17.700 líneas. Trocearlo y traducirlo con el mismo
  cuidado que el resto habría llevado varias decenas de tandas de
  lectura/escritura solo para ese fichero — técnicamente posible,
  pero poco realista en una sola sesión sin degradar la atención. La
  decisión correcta ahí no fue "seguir a toda costa" ni "reducir la
  calidad para ir más rápido", sino pararse a media tarea, ser
  explícito sobre el ritmo real, y dejar que el técnico decidiera
  cómo seguir en vez de asumirlo.

## El ritmo real: cientos de pasos pequeños, no saltos grandes

Algo que se pierde fácilmente si solo se mira el resultado final es
lo poco espectacular que es, paso a paso, la mayor parte del trabajo.
De los cerca de 370 hitos y rondas registrados en `FINDINGS.md`, la
inmensa mayoría no son descubrimientos — son cosas como "sustituir un
`CALL $86BB` suelto por su etiqueta real", "renombrar 8 palabras de
terminología propia del técnico en las etiquetas de código", "pasar
un campo de hexadecimal a decimal porque se lee mejor". Ninguno de
esos pasos es interesante por separado. Lo que los hace valiosos es
la consistencia sostenida durante cientos de rondas sin que se cuele
un error — y eso es, otra vez, el tipo de trabajo donde un proceso
sistemático (comprobar, aplicar, recompilar, comprobar otra vez) rinde
mucho más que la inspiración puntual.

## Reflexión final

Si hay una conclusión de fondo, es que este proyecto no ha funcionado
solo por tener "una IA muy potente" ni solo por tener "un técnico con
criterio propio" — los dos hacían falta, pero ninguno de los dos
bastaba por sí solo. Ha funcionado por tener, además, un método que
no dependía de que ninguna de las dos partes tuviera siempre razón.
La verificación byte
a byte no es solo rigor técnico: es lo que ha permitido que un
desacuerdo (¿es esto un nivel oculto o uno normal?, ¿es "COMILONAS" o
"GOMILONAS"?, ¿son 48 filas o 24 entrelazadas?) se resolviera siempre
mirando el dato, no discutiendo quién tenía más autoridad para
decidir. En un proyecto de ingeniería inversa eso es casi obligado,
porque hay una respuesta objetiva esperando a ser encontrada.

Pero reducirlo todo a "verificar contra los bytes" dejaría fuera la
mitad del trabajo real. Antes de poder verificar nada hace falta
decidir *qué* mirar —el papel de dirección e intuición del
técnico, aparcando y retomando hilos—; muchas veces la propia
verificación es un bucle de percepción compartido, no un veredicto
de una sola vez —el oído acotando qué bytes de sonido revisar, el
ojo acotando qué bytes de imagen probar de otra forma—; y hay una
categoría entera de decisiones, nombrar y comentar, donde no hay
ningún byte que pueda arbitrar y el criterio compartido —a veces del
técnico, a veces de la IA con datos de uso del código detrás— es lo
único que hay. La reflexión que vale la pena llevarse no es solo
"tener siempre un árbitro externo al que apelar cuando existe uno
disponible", sino que ese árbitro no sustituye la necesidad de
decidir juntos por dónde mirar, cómo llamar a lo que se encuentra, y
cuándo dejar una vía a medias para retomarla después con más
contexto — eso último no lo resuelve ningún dato, es criterio
compartido, construido sesión a sesión.
