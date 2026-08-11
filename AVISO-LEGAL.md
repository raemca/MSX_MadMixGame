# Aviso legal y de atribución

*[Read this in English](AVISO-LEGAL.en.md)*

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial (raemca@hotmail.com)*

## De quién es cada cosa

**El juego no es mío.** *Mad Mix Game* lo publicó **Topo Soft** (catalogado
de 1987; la propia pantalla de créditos del juego lo firma como
"TOPOSHOW -1988-"). El programa acredita su autoría, tal cual aparece en esa
pantalla, a **"RAPHAEL GOMEZZZ"** (programación), **"ROBERTO P.ACEBES"**
(gráficos) y **"COMILONAS"** (música) — pseudónimos o grafías de la época tal
como aparecen en el binario. La propiedad intelectual del juego original — código,
gráficos, sonido y diseño — sigue siendo de Topo Soft, de las personas detrás
de esos créditos, o de quien haya heredado esos derechos a día de hoy.

**Lo que sí es mío** son las herramientas de este repositorio, los
comentarios del código fuente reconstruido, el análisis y la documentación
(`FINDINGS.md`, `FLUJO_PROGRAMA.md`, `README.md` y los recursos HTML que los
acompañan). Eso se publica bajo la licencia que conste en `LICENSE`.

## Qué contiene este repositorio

Este proyecto **no tenía acceso al código fuente original** de *Mad Mix
Game* — no se conserva, o al menos no ha llegado a este trabajo. Lo que hay en
`src/` es una **reconstrucción por ingeniería inversa**: desensamblado línea a
línea de los binarios del disco y la cinta originales, reescrito como fuente
ensamblador (`SjASMPlus`) legible, con etiquetas descriptivas y comentarios que
explican qué hace cada rutina y por qué. Se acompaña de las herramientas
(`tools/`) que permiten recompilar esa fuente y regenerar, byte a byte, los
mismos `.dsk`/`.cas` que arrancan en un MSX real o en un emulador — la
verificación de que el análisis es correcto es, precisamente, que reproduce el
original con exactitud. Con este trabajo recupero lo más cercano posible al
código fuente perdido del juego, y la documentación que nunca se publicó junto
a él.

Este repositorio **no incluye** las imágenes originales de disco o cinta
(`.dsk`/`.cas`/`.rom`) tal como se volcaron del soporte físico, ni herramientas
de terceros usadas durante el análisis (por ejemplo, el desensamblador). Lo que
se distribuye es la fuente reconstruida, los datos del juego ya identificados y
documentados (mapas de nivel, tiles, sonido) necesarios para que esa fuente
compile a un binario idéntico, y las herramientas propias para generarlo — no
una copia del producto original.

Las imágenes de `dump_openmsx/` y `recursos/` no son capturas promocionales:
son volcados de memoria/VRAM y reconstrucciones generadas a partir del propio
análisis, usadas como evidencia de que el formato de los datos está bien
entendido.

## Si eres uno de los autores, Topo Soft, o su sucesor en derechos

Si trabajaste en *Mad Mix Game*, eres alguna de las personas acreditadas en su
pantalla de créditos ("RAPHAEL GOMEZZZ", "ROBERTO P.ACEBES", "COMILONAS"), o
representas a Topo Soft o a quien haya heredado sus derechos, y prefieres que
este material no esté publicado, **dilo y se retira sin
discusión**. Cualquier requerimiento legal, de quien corresponda, será
atendido. La intención de este trabajo es la contraria a perjudicar: es dejar
constancia de cómo estaba hecho un juego que forma parte de la historia del
software español, con fines educativos y de preservación de ese legado, antes
de que se pierda del todo.

## Sobre los créditos

Los nombres de la pantalla de créditos se han transcrito tal cual aparecen en
el binario del juego, incluyendo sus erratas originales (ver comentarios en
`src/madmix_scr_body.asm`), no de fuentes externas. No se afirma ninguna
identidad civil real detrás de esos pseudónimos: si alguien puede confirmarla,
se corrige encantados con cualquier dato mejor.
