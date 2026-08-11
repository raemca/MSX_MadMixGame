# Política de seguridad

## Alcance de este proyecto

`MSX_MadMixGame` es un proyecto de ingeniería inversa, documentación y
preservación — no un servicio en producción. No hay servidor, no hay
cuentas de usuario, no hay base de datos, y no se procesa ningún dato
personal. El contenido del repositorio son tres tipos de cosas:

- **Código fuente ensamblador Z80** (`src/*.asm`), pensado para
  compilarse con `sjasmplus` y ejecutarse en un emulador MSX (o MSX
  real) — nunca en el propio ordenador que lo compila.
- **Herramientas en Python** (`tools/*.py`) que leen/generan ficheros
  binarios locales (`.bin`, `.dsk`, `.cas`, `.wav`) a partir de otros
  ficheros locales del propio repositorio.
- **Páginas HTML autocontenidas** (`recursos/*.html`) que se abren
  directamente en el navegador, sin backend ni llamadas de red — todos
  los datos que muestran están embebidos en el propio fichero.

Dado este alcance, no aplican la mayoría de categorías clásicas de
vulnerabilidad web (inyección SQL, XSS con datos remotos, gestión de
sesiones, etc.). Lo que sí tiene sentido reportar:

- Un script de `tools/` que, al procesar un fichero de entrada
  manipulado a propósito (un `.dsk`/`.cas`/`.bin` corrupto o
  malicioso), escriba fuera del directorio esperado, sobrescriba
  ficheros arbitrarios, o tenga cualquier otro comportamiento inseguro
  más allá de fallar con un error controlado.
- Cualquier fichero HTML de `recursos/` que, en contra de su diseño
  actual (autocontenido, sin red), termine cargando o ejecutando
  contenido de una fuente externa no confiable.
- Cualquier credencial, token o dato sensible que aparezca por error
  en el historial del repositorio.

## Lo que NO es una vulnerabilidad de este proyecto

Por el propio objetivo del proyecto (reconstrucción byte a byte del
binario original de 1987/88, ver `METODOLOGIA.md`), el código
ensamblador reproduce **deliberadamente** el comportamiento original
del juego, incluidos sus bugs históricos — con la única excepción
documentada y explícita del contador de bolitas del nivel 13 (ver
`FINDINGS.md`). Un comportamiento "raro" del juego reconstruido que
coincide con el original **no es un fallo de seguridad**, es fidelidad
histórica. Si tienes dudas sobre si algo encaja en esta categoría,
repórtalo igualmente y se aclarará.

## Versión soportada

No hay versiones publicadas ni releases con soporte diferenciado: solo
se mantiene la rama `main`, siempre con el estado más reciente.

| Rama | Soportada |
| --- | --- |
| `main` | :white_check_mark: |
| cualquier fork/rama antigua | :x: |

## Cómo reportar un problema

- **Para la mayoría de casos** (el escenario más probable: un bug en
  un script de `tools/`): abre un
  [Issue](https://github.com/raemca/MSX_MadMixGame/issues) normal,
  igual que cualquier otro error — no hace falta tratarlo como algo
  especial, aquí no hay usuarios en riesgo.
- **Si de verdad prefieres reportarlo en privado** (por ejemplo, si
  encontraras una credencial filtrada en el historial), escribe a
  <raemca@hotmail.com> con el detalle.

Este es un proyecto personal mantenido por una sola persona en su
tiempo libre: no hay SLA ni programa de recompensas, pero todo reporte
se revisa y se agradece — especialmente viniendo de quien se ha
tomado la molestia de mirar el código con cuidado.
