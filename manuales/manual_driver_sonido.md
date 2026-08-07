# Manual del driver de sonido — Mad Mix Game (MSX1, PSG AY-3-8910)

*Ingeniería inversa, análisis y documentación: Rafael Eduardo Martín Candial*

> Fuente: `madmix1.asm`, región `$C4A0`-`$CF8D` (2912 bytes: código +
> datos). Crédito real encontrado en los créditos del juego:
> **"MUSIC-A BY: COMILONAS"**. Para la crónica de cómo se descubrió
> cada pieza, ver `FINDINGS.md`; este documento asume que ya está todo
> resuelto y explica el resultado final de forma ordenada.

## 1. Qué es esto y qué NO es

Este driver **no es** un estándar de MSX ni algo que provea la BASIC
o la BIOS de la máquina — es un intérprete de bytecode escrito a
medida, propio de Topo Soft, para este juego. El MSX-BASIC tiene su
propia instrucción `PLAY` para reproducir música, con su propio
formato de texto ("MML"); este driver no tiene absolutamente nada que
ver con eso, ni con ningún formato de tracker conocido de la época. Es
una implementación 100% original, pensada y optimizada para las
necesidades concretas de este juego.

Tampoco es "un gestor de recursos genérico", que fue la primera
hipótesis de trabajo en sesiones anteriores de este proyecto (de ahí
que algunas etiquetas se llamaran en su día `LOAD_RESOURCE_SLOT_ALLOC`
/ `LOAD_RESOURCE_SLOT_EMPTY`, hoy `INSTALAR_RECURSO_SONIDO` /
`VACIAR_CANALES_SONIDO`) — es, específicamente, el reproductor de
sonido y música.

## 2. El hardware que hay detrás: el PSG AY-3-8910

Antes de entrar en el driver hace falta entender qué puede hacer -- y
qué NO puede hacer -- el chip de sonido real, porque el diseño entero
del driver es una respuesta a esas limitaciones.

El AY-3-8910 (el "PSG", *Programmable Sound Generator*) tiene **3
canales de tono independientes**, cada uno con:

- Un **periodo de tono** (12 bits): un número entero que controla la
  frecuencia de una onda cuadrada. La relación es
  `frecuencia = reloj_del_chip / (16 × periodo)` — cuanto más pequeño
  el periodo, más aguda la nota. El chip no entiende "notas", "Do",
  "La440" ni nada parecido: solo periodos, números enteros.
- Un **volumen** (4 bits, 0-15).
- Un **generador de ruido** compartido entre los 3 canales (útil para
  percusión/efectos, no para tono) — con su propio **periodo de
  ruido** (registro 6), también compartido.
- Un **generador de envolvente por hardware** (periodo + forma), que
  puede sustituir al volumen fijo de un canal por una rampa
  automática — mecanismo real del chip. Este driver **no lo usa**
  directamente: en su lugar implementa sus propias envolventes por
  software (§6.7 y §8), incluyendo una de ruido que también escribe
  el periodo del registro 6 por software, tic a tic.

Todo esto se controla escribiendo en registros del chip por dos
puertos de E/S (`$A0`=número de registro, `$A1`=valor) — ver
`VOLCAR_REGISTROS_PSG` (§4), el volcado final de cada tic.

**El problema real que resuelve este driver**: el Z80 no tiene
multiplicación ni división por hardware. Calcular "qué periodo le
corresponde a un Do4" en tiempo real, 50 veces por segundo, sería
carísimo. La solución de toda la época de 8 bits (y la que se usa
aquí) es **precalcular** esa correspondencia nota→periodo una sola vez
y guardarla en una tabla — el Z80 en tiempo de ejecución solo necesita
un salto indexado, nada de aritmética cara. Esa idea aparece una y
otra vez en este driver: tablas precalculadas en vez de cálculo en
vivo.

## 3. Arquitectura general

```
$C4A0 ─┬─ INSTALAR_RECURSO_SONIDO / INSTALAR_RECURSO_SONIDO_EN_A -- instalar un script en un canal
       ├─ TICK_REPRODUCTOR_PSG / PROCESAR_CANAL_PSG          -- el "tick" del reproductor (una vez por VBLANK)
       ├─ DESPACHAR_COMANDO_PSG / ARMAR_NOTA / CERRAR_NOTA   -- el interprete del bytecode (una nota o comando)
       ├─ APLICAR_ENVOLVENTES_CANAL                          -- aplica un paso de envolvente de volumen/tono POR CANAL
       ├─ APLICAR_ENVOLVENTE_RUIDO / REINICIAR_ENVOLVENTE_RUIDO -- envolvente de RUIDO, COMPARTIDA entre los 3 canales (§8, resuelto)
       ├─ ACTUALIZAR_MEZCLADOR_CANAL                         -- activar/desactivar tono y ruido por canal
       ├─ MULTIPLICAR_8X16 / DIVIDIR_16X16 / LEER_PALABRA_INDEXADA -- utilidades: aritmetica y lookup de tabla
       └─ VOLCAR_REGISTROS_PSG                                -- vuelca la sombra de registros al chip real
$C8DE ─┬─ TABLA_NOTAS_PSG                          -- tabla de periodos (nota -> periodo PSG)
       ├─ TABLA_COMANDOS_PSG                       -- salto de los 15 comandos del bytecode
       ├─ AREA_TRABAJO_PSG                         -- 151 bytes de estado en reposo (en la v2.0 CAS/ROM aqui va el parche del bug del nivel 13, ver FINDINGS.md)
       ├─ TABLA_ENVOLVENTE_RUIDO_PSG               -- envolvente de ruido compartida: ESTADO EN VIVO (§8)
       ├─ TABLA_RETORNO_SUBPATRONES_PSG            -- retorno de CALL_SUBPATTERN por canal
       ├─ TABLA_TRANSPOSICION_PSG                  -- transposicion en vivo por canal
       ├─ TABLA_INSTRUMENTOS_PSG                   -- 16 instrumentos x 15 bytes
       ├─ TABLA_ENVOLVENTES_PSG                    -- 4 formas de envolvente PLANTILLA x 6 bytes
       ├─ TABLA_SUBPATRONES_PSG                    -- punteros a los 13 subpatrones compartidos
       └─ SUBPATRON_00_CB9C .. SUBPATRON_12_CBB0   -- el bytecode de esos 13 subpatrones, cada uno con etiqueta propia, data/sound/spt/*.spt
$CDCB ─── GUION_MELODIA_CANAL_0/1/2 + 13 scripts de evento (GUION_EVTxx_..._CExx) -- los 16 "scripts" de recurso reales (música + efectos, data/sound/snd/*.snd)
$CF8B ─── VACIAR_CANALES_SONIDO               -- vacía los 3 canales (usado al cambiar de pantalla/nivel)
```

Todo lo de `$C8DE` en adelante es **dato**, no código — el código real
del driver está completo entre `$C4A0` y `$C8C9`. Ver
`madmix1.asm` (buscar cada etiqueta de arriba) para el desensamblado
completo, ya con comentarios línea a línea.

## 4. El bucle de reproducción (el "tick")

Cada **VBLANK** (interrupción de fin de fotograma de vídeo, 50 veces
por segundo en PAL), `DESPACHAR_EFECTO_SONIDO` (`$60DC`,
`madmix_scr.asm`) hace dos cosas:

1. Comprueba `(EVENTO_SONIDO_PENDIENTE)`: si no es `$FF`, hay un
   efecto de sonido pendiente de disparar (ver §7).
2. Llama SIEMPRE a `TICK_REPRODUCTOR_PSG` (`$C4EB`) — el "tick" real
   del reproductor.

`TICK_REPRODUCTOR_PSG` prepara punteros (tabla de canales en `$C9C9`,
sombra de registros del PSG en `$C9BE`) y entra en `PROCESAR_CANAL_PSG`,
un bucle que recorre los **3 canales** (46 bytes cada uno, ver §5) y
para cada uno:

1. **¿Queda tiempo en la nota actual?** (`(IX+$04)`/`(IX+$05)` ≠ 0):
   si sí, salta directo a `APLICAR_ENVOLVENTES_CANAL` — decrementa el
   contador y aplica un paso de las envolventes de volumen/tono del
   canal — no toca el bytecode.
2. **¿Se acabó la nota?**: silencia brevemente el canal
   (`ACTUALIZAR_MEZCLADOR_CANAL` con `A=0`, evita clics), y entra en
   `DESPACHAR_COMANDO_PSG`: lee bytes del script uno a uno. Cada byte
   es o bien una **nota** (`< $80`, resuelve el periodo y termina el
   lote) o un **comando** (`≥ $80`, lo ejecuta y sigue leyendo el
   siguiente byte inmediatamente, sin consumir tic).

Al terminar el recorrido de los 3 canales, el flujo cae (sin salto,
directamente) en `APLICAR_ENVOLVENTE_RUIDO` — la tercera envolvente,
compartida entre los 3 canales, ver §8 — y esta a su vez termina en
`VOLCAR_REGISTROS_PSG`, que vuelca la sombra de los 11 registros del
PSG al chip real.

**Detalle importante para quien quiera reimplementar esto en un
emulador/renderizador**: cuando se resuelve una nota nueva
(`DESPACHAR_COMANDO_PSG`→`ARMAR_NOTA`→`CERRAR_NOTA`→cae directo en
`APLICAR_ENVOLVENTES_CANAL`, sin salto de por medio), el PRIMER tic de
esa nota **ya** decrementa el contador y aplica un paso de envolvente
— no se espera al tic siguiente. Es un detalle fácil de pasar por alto
(se descubrió como bug real al construir el renderizador, ver
`FINDINGS.md`).

## 5. La ranura de canal (46 bytes)

Hay 3 ranuras, una por canal del PSG, en `$C9C9` (`$C9C9`, `$C9C9+46`,
`$C9C9+92`). Campos (offset relativo a `IX`, el puntero a la ranura):

| Offset | Campo | Notas |
|---|---|---|
| `+$00/$01` | Puntero de script ORIGINAL | usado por `LOOP` para volver al principio |
| `+$02/$03` | Puntero de LECTURA actual | avanza byte a byte por el script |
| `+$04/$05` | Tics restantes de la nota en curso | cuando llega a 0, se lee el siguiente lote de comandos |
| `+$06/$07` | Duración en tics | fijada por `SET_DURATION`/`SET_DURATION_MULTI`; se copia a `+$04/$05` en cada nota nueva |
| `+$08` | Máscara de mezclador | bit0=tono activo, bit3=ruido activo (ver `SET_MIXER`, §6) |
| `+$09` | Volumen base | fijado por `SET_VOLUME` |
| `+$0A/$0B` | Periodo de tono BASE ya resuelto | nota + transposición, vía `TABLA_NOTAS_PSG` |
| `+$0C/$0D` | Envolvente de VOLUMEN: cuenta atrás de retardo, fase 1/2 | |
| `+$0E/$0F` | Envolvente de VOLUMEN: repeticiones restantes, fase 1/2 | |
| `+$10/$11/$12` | Envolvente de TONO: cuenta atrás de retardo, fase 1/2/3 | |
| `+$13/$14/$15` | Envolvente de TONO: repeticiones restantes, fase 1/2/3 | |
| `+$1B/$1C` | Envolvente de VOLUMEN: delta por paso, fase 1/2 | sin signo |
| `+$1D/$1E/$1F` | Envolvente de TONO: delta por paso, fase 1/2/3 | **con signo** |
| `+$20/$21` | Envolvente de VOLUMEN: valor de recarga del retardo, fase 1/2 | |
| `+$22/$23/$24` | Envolvente de TONO: valor de recarga del retardo, fase 1/2/3 | |
| `+$2A` | Acumulador EN VIVO de la envolvente de volumen | se suma al volumen base al escribir el registro del PSG |
| `+$2B/$2C` | Acumulador EN VIVO de la envolvente de tono (16 bits, con signo) | se suma al periodo base |
| `+$2D` | Flags varios | probados para decidir si "relatch" un canal compañero |

Todos estos campos salen de copiar el **instrumento activo** (§6.7)
cuando se ejecuta `SET_INSTRUMENT`, salvo `+$00` a `+$09` (los fija
directamente el bytecode) y `+$2A`-`+$2D` (acumuladores en vivo, se
recalculan tic a tic).

## 6. El lenguaje de bytecode (15 comandos + nota)

Cada "script" de sonido (ver §9, `data/sound/snd/*.snd`) o subpatrón
compartido (`data/sound/spt/*.spt`, mismo lenguaje) es una secuencia
de bytes que se lee comando a comando:

- **Byte `< $80`** → es una **NOTA**: el valor (0-95) se suma a la
  transposición del canal (`TABLA_TRANSPOSICION_PSG`) y el resultado
  indexa `TABLA_NOTAS_PSG` para obtener el periodo de tono real.
- **Byte `≥ $80`** → es un **COMANDO** (`$80` + número de comando,
  `TABLA_COMANDOS_PSG` hace el salto indexado).

### Tabla completa de comandos

| # | Byte | Parámetros | Nombre | Efecto |
|---|---|---|---|---|
| 0 | `$80` | 1 byte | **SET_VOLUME** | fija el volumen base (`+$09`) |
| 1 | `$81` | 1 byte | **SET_MIXER** | `AND $09`, fija la máscara de mezclador (`+$08`); **un bit a 1 ACTIVA** ese generador (bit0=tono, bit3=ruido) |
| 2 | `$82` | 0 | **LOOP** | vuelve el puntero de lectura al principio del script (`+$00/$01` → `+$02/$03`) |
| 3 | `$83` | 1 byte | **SET_DURATION** | el valor × el multiplicador de tempo actual (`($C9BD)`) → duración en tics (`+$06/$07`) |
| 4 | `$84` | 0 | **HOLD** ("tie") | repite la duración actual sin resolver una nota nueva ni relanzar envolventes — salta directo a `CERRAR_NOTA` (actualiza el puntero de lectura y recarga el contador de tics, saltándose la resolución de tono y el relatch de envolvente) |
| 5 | `$85` | 1 byte | **SET_TEMPO** | `valor × 16`, luego `$0BB8 ÷ eso` (`DIVIDIR_16X16`, cociente) → nuevo multiplicador de tempo (`($C9BD)`), usado por `SET_DURATION`/`SET_DURATION_MULTI` |
| 6 | `$86` | 1 byte de cuenta + N bytes | **SET_DURATION_MULTI** | suma N valores × el multiplicador de tempo → duración en tics (variante acumulativa de `SET_DURATION`, longitud variable) |
| 7 | `$87` | 1 byte | **SET_INSTRUMENT** | copia los 15 bytes del instrumento indicado (`TABLA_INSTRUMENTOS_PSG`, ver §6.7) a los campos de envolvente del canal, y pone a cero los acumuladores en vivo |
| 8 | `$88` | 1 byte | **SET_ENVELOPE** | `AND $1F` (0-31) → base de la envolvente de ruido compartida (`$CA5E`) y relatch vía `REINICIAR_ENVOLVENTE_RUIDO` (§8) |
| 9 | `$89` | 1 byte | **SET_ENVELOPE_SHAPE** | copia una de las 4 formas de `TABLA_ENVOLVENTES_PSG` a `TABLA_ENVOLVENTE_RUIDO_PSG+4`, resetea el acumulador (`$CA5F`) y marca el canal actual como "dueño" (`$CA60`) |
| 10 | `$8A` | 1 byte | **SET_FLAGS** | `OR` con los flags del canal (`+$2D`) y con unos flags globares (`$CA5D`) |
| 11 | `$8B` | 0 | **RESET_SHARED_ENVELOPE** | **borra siempre los 46 bytes completos de la ranura del canal actual**; SOLO si además el canal es el "dueño" (`$CA60`) de la envolvente de ruido compartida, borra también sus 10 bytes (`TABLA_ENVOLVENTE_RUIDO_PSG`) |
| 12 | `$8C` | 1 byte | **CALL_SUBPATTERN** | guarda la dirección de retorno (`TABLA_RETORNO_SUBPATRONES_PSG`) y salta a uno de los subpatrones compartidos (`TABLA_SUBPATRONES_PSG`, ver §6.8) |
| 13 | `$8D` | 0 | **RETURN_SUBPATTERN** | recupera la dirección guardada por `CALL_SUBPATTERN` y vuelve ahí |
| 14 | `$8E` | 1 byte | **SET_CHANNEL_STATE** | escribe el valor tal cual en `TABLA_TRANSPOSICION_PSG` del canal actual — transposición en vivo |

**Confianza**: la mecánica (qué bytes lee, qué campos toca, a qué
tabla indexa) está verificada al 100% contra el desensamblado real,
incluida la envolvente de ruido compartida (§8, ver más abajo). Los
**nombres** son interpretación razonada a partir de esa mecánica.

### 6.7 El instrumento (16 entradas × 15 bytes, `TABLA_INSTRUMENTOS_PSG`)

```
b[0]/b[1]   = repeticiones fase 1/fase 2 de la envolvente de VOLUMEN
b[2..4]     = repeticiones fase 1/2/3 de la envolvente de TONO
b[5]/b[6]   = delta fase 1/fase 2 de VOLUMEN (sin signo)
b[7..9]     = delta fase 1/2/3 de TONO (CON SIGNO)
b[10]/b[11] = retardo entre pasos, fase 1/fase 2 de VOLUMEN
b[12..14]   = retardo entre pasos, fase 1/2/3 de TONO
```

**Cómo se procesa una envolvente (volumen: 2 fases; tono: 3 fases),
cada tic**: se recorren las fases EN ORDEN, deteniéndose en la primera
que siga "activa":

1. Si a la fase le queda retardo (`> 0`): se decrementa el retardo y
   ya está, no pasa nada más este tic.
2. Si no le queda retardo pero SÍ le quedan repeticiones (`> 0`): se
   decrementa las repeticiones, se suma el delta al acumulador en
   vivo, y se recarga el retardo desde el valor de recarga (`b[10..]`).
3. Si a la fase no le queda ni retardo ni repeticiones: está agotada,
   se prueba la siguiente fase (mismo tic).

Es decir: una fase = "espera `retardo` tics, luego aplica `delta` al
acumulador, repite `repeticiones` veces — luego pasa a la fase
siguiente". El acumulador de volumen (`+$2A`) se suma al volumen base
al escribir el registro real del PSG, con `AND $0F` (el registro de
volumen del chip es de 4 bits — si la suma pasa de 15, **da la vuelta
a 0**, silencio real; esto es un comportamiento verificado del propio
driver original, no un invento del renderizador). El acumulador de
tono (`+$2B/$2C`, 16 bits con signo) se suma al periodo base.

Esta MISMA mecánica de fases (retardo/repeticiones/delta/recarga) se
reutiliza tal cual, una tercera vez, para la envolvente de ruido
compartida — ver §8.

### 6.8 Subpatrones (comandos 12/13)

`CALL_SUBPATTERN`/`RETURN_SUBPATTERN` implementan una **llamada a
subrutina dentro del propio bytecode**. El parámetro de
`CALL_SUBPATTERN` indexa `TABLA_SUBPATRONES_PSG` (42 bytes, 21
punteros de 16 bits — las entradas 13 a 20 repiten el puntero de la
entrada 0), que apunta a uno de los **13 subpatrones únicos**
compartidos (`$CB9C`-`$CDCB`, justo antes de que empiece el primer
script de recurso real) — cada uno con etiqueta global propia
(`SUBPATRON_00_CB9C` a `SUBPATRON_12_CBB0`, numerados por su índice de
entrada en `TABLA_SUBPATRONES_PSG`, no por orden de memoria). La
dirección de retorno se guarda en `TABLA_RETORNO_SUBPATRONES_PSG` (2
bytes por canal) y se recupera con `RETURN_SUBPATTERN`.

Cada uno de los 13 tiene su propio fichero en `data/sound/spt/`
(extensión `.spt`, mismo bytecode y misma herramienta que los `.snd`
de evento) y su propio `.wav` de referencia en `build/sound_preview/`
(`mmsnd_render.py`, que ya soportaba `CALL_SUBPATTERN`/
`RETURN_SUBPATTERN` para reproducir la música de arranque, también
sabe reproducirlos SUELTOS gracias a que un `RETURN_SUBPATTERN` sin
llamada previa ya se interpreta como fin de reproducción).

Este mecanismo se usa MUCHO en la música real (17-20 llamadas por
script en los 3 canales de arranque) — es la forma de no repetir
fragmentos musicales idénticos una y otra vez dentro de cada script.

## 7. Cómo se disparan los efectos: `EVENTO_SONIDO_PENDIENTE` y `TABLA_RECURSOS_SONIDO_EVENTO`

El resto del juego (fuera del driver) nunca instala un script de
sonido directamente — escribe un **índice de efecto** en la variable
global `EVENTO_SONIDO_PENDIENTE` (`$6128`). `DESPACHAR_EFECTO_SONIDO`
(`$60DC`, `madmix_scr.asm`), llamada cada VBLANK, hace lo siguiente:

1. Lee `(EVENTO_SONIDO_PENDIENTE)`. Si es `$FF`, no hay nada
   pendiente, no hace nada más (aparte del tic normal del reproductor,
   §4).
2. Si no es `$FF`, lo usa como índice (× 3) en
   `TABLA_RECURSOS_SONIDO_EVENTO` (`$60FE`, 14 entradas de 3 bytes:
   `[canal, puntero_bajo, puntero_alto]`), instala el script
   correspondiente en ese canal vía `INSTALAR_RECURSO_SONIDO`
   (`$C4A0`), y marca el evento como consumido
   (`EVENTO_SONIDO_PENDIENTE = $FF`).
3. Llama SIEMPRE a `TICK_REPRODUCTOR_PSG` (el tic normal).

Los 14 índices conocidos, y a qué evento de juego corresponden
(candidato de catálogo entre paréntesis donde hay uno sólido — ver
`FINDINGS.md` para el detalle y el nivel de confianza de cada uno):

| índice | canal | script | disparado por | candidato |
|---|---|---|---|---|
| 0 | 0 | `GUION_EVT00_BOLITA_CEE2` (`$CEE2`) | comer bolita normal (`HNDLR_BOLITA_NORMAL`) | "ruido de comer bola" |
| 1 | 0 | `GUION_EVT01_BOLA_CLAVADA_CE8B` (`$CE8B`) | liberar bola clavada, modo herramienta (`HNDLR_BOLITA_CLAVADA`) | "ruido de sacar bola" |
| 2 | 0 | `GUION_EVT02_FLECHA_CF62` (`$CF62`) | pasar por loseta de flecha (`HNDLR_AUTOCOCO_*`) | "loseta de dirección única" |
| 3 | 1 | `GUION_EVT03_MODO_ESPECIAL_CF70` (`$CF70`) | activar/salir modo especial | genérico "cambio de modo" |
| 4 | 0 | `GUION_EVT04_DISPARO_AVION_CE72` (`$CE72`) | `REGISTRAR_PISTA_TANQUE_AVION` (pista tanque/avión) | "Disparo (modo avión)" — CONFIRMADO por el usuario (jugador original) |
| 5 | 1 | `GUION_EVT05_MARIQUITA_REPONE_CF44` (`$CF44`) | reponer bolita comida (`HNDLR_MARICOCO`) | "reponer bola" |
| 6 | 1 | `GUION_EVT06_PLANTA_CLAVADA_CEAC` (`$CEAC`) | plantar bola clavada (`HNDLR_REGPUNANTOSO`) | sin match directo |
| 7 | 1 | `GUION_EVT07_PISTA_CE7E` (`$CE7E`) | aviso de pista (`AVISAR_PROXIMIDAD_PISTA`) + colas de efecto | ambiguo, dos usos |
| 8 | 0 | `GUION_EVT08_ARMA_MODO_CF07` (`$CF07`) | arma el temporizador de modo especial (`ACTIVAR_EFECTO_ITEM`) | genérico "activar modo" |
| 9 | 0 | `GUION_EVT09_TRAMPILLA_TRANSICION_CE5A` (`$CE5A`) | transición de trampilla (`HNDLR_TRAMPILLA_ABIERTA_*`) | relacionado con trampillas |
| 10 | 2 | `GUION_EVT10_INICIO_NIVEL_CEF0` (`$CEF0`) | **llamado directo** desde `MOSTRAR_READY_Y_ARRANCAR_NIVEL`, no vía `EVENTO_SONIDO_PENDIENTE` | "soniquete de inicio de nivel" |
| 11 | 2 | `GUION_EVT11_BOLA_PODER_CE9C` (`$CE9C`) | bola de poder (evento final) | relacionado |
| 12 | 0 | `GUION_MELODIA_CANAL_0` (`$CDCB`) | sin sitio de escritura encontrado (reutiliza el script de música) | "música principal" |
| 13 | 2 | `GUION_EVT13_FIN_MODO_CF27` (`$CF27`) | evento final tras modo especial | genérico "fin de modo" |

**Caso especial — el soniquete de inicio de nivel (índice 10)**:
`MOSTRAR_READY_Y_ARRANCAR_NIVEL` instala el MISMO bloque de 23 bytes
en los **3 canales a la vez**, cada uno empezando 7 bytes más adentro
que el anterior (offsets 0/+7/+14) — es un acorde de 3 voces, no una
melodía lineal. Cualquier intento de reproducirlo como un solo canal
sonará incompleto por diseño.

## 8. La envolvente compartida, resuelta: es la envolvente de RUIDO (registro 6 del PSG)

Este mecanismo estuvo sin trazar durante buena parte del proyecto —
hoy está completamente identificado.

`SET_ENVELOPE` (comando 8), `SET_ENVELOPE_SHAPE` (comando 9) y
`RESET_SHARED_ENVELOPE` (comando 11, con matiz — ver arriba) leen y
escriben una tabla **compartida entre los 3 canales**,
`TABLA_ENVOLVENTE_RUIDO_PSG` (`$CA53`, 10 bytes), con un "dueño"
registrado aparte (`$CA60`). Tras el bucle de los 3 canales,
`TICK_REPRODUCTOR_PSG` cae (sin salto, directamente) en
`APLICAR_ENVOLVENTE_RUIDO`: una **tercera envolvente**, con la MISMA
estructura de fases que las de volumen/tono (§6.7) — cuenta atrás de
retardo, repeticiones, delta, recarga — pero de UNA sola fase (no 2 ni
3), operando sobre `TABLA_ENVOLVENTE_RUIDO_PSG` en vez de sobre una
ranura de canal. El resultado (`($CA5E)` base + `($CA5F)` acumulador)
se escribe en `$C9C4` — la sombra del **registro 6 del PSG (periodo de
ruido)** — y de ahí `VOLCAR_REGISTROS_PSG` lo vuelca al chip real.
`REINICIAR_ENVOLVENTE_RUIDO` es su relatch (misma función que
`REINICIAR_ENVOLVENTE_VOLUMEN`/`_TONO` pero sobre la tabla fija en vez
de por canal), llamado desde `SET_ENVELOPE` y, si se agota del todo,
desde la propia `APLICAR_ENVOLVENTE_RUIDO`.

Tiene sentido que sea compartida y no por canal: el AY-3-8910 solo
tiene **un** generador de ruido (y un único periodo de ruido, registro
6) para los 3 canales — a diferencia del tono y el volumen, que sí son
independientes por canal en el chip real.

**El "dueño" (`$CA60`)**: cualquier canal que ejecute
`SET_ENVELOPE_SHAPE` se convierte en el dueño de la envolvente
compartida. Eso importa para `RESET_SHARED_ENVELOPE` (comando 11):
SIEMPRE borra los 46 bytes completos de la ranura del canal que lo
ejecuta, pero solo borra además la tabla compartida de 10 bytes si ese
canal resulta ser el dueño actual — evita que un canal cualquiera
pisotee un efecto de ruido que "pertenece" a otro.

**Consecuencia práctica ya resuelta**: el script
`05_evt07_pista_ce7e.snd` no contiene ninguna nota — usa solo
`SET_MIXER` (ruido puro), `SET_ENVELOPE`/`SET_ENVELOPE_SHAPE`/
`RESET_SHARED_ENVELOPE` y `SET_DURATION`. Con el mecanismo ya
modelado, `mmsnd_render.py` (§10) puede reproducir este efecto en vez
de dejarlo en silencio, siempre que incorpore esta tercera envolvente
en su bucle de emulación (ver el propio script para el estado actual
de esa implementación).

## 9. Los 16 "scripts" de recurso reales

Viven en `data/sound/snd/*.snd` (el binario que se compila con `INCBIN`,
byte a byte idéntico al original) con un `.txt` gemelo (el formato de
texto de este manual, un mnemónico por línea, ver §10):

| Fichero | Etiqueta | Dirección | Uso |
|---|---|---|---|
| `00_script_cdcb` | `GUION_MELODIA_CANAL_0` | `$CDCB` | música, canal 0 |
| `01_script_cdff` | `GUION_MELODIA_CANAL_1` | `$CDFF` | música, canal 1 |
| `02_boot_ch2_ce0c` | `GUION_MELODIA_CANAL_2` | `$CE0C` | música, canal 2 (percusión) |
| `03` a `15` | `GUION_EVTxx_..._CExx` | `$CE5A`-`$CF70` | 13 efectos de sonido individuales, uno por índice de `EVENTO_SONIDO_PENDIENTE` (§7) |

> ⚠️ **Límite real de edición**: cada `.snd` se compila con `INCBIN` a
> una dirección FIJA. Cambiar el VALOR de una instrucción ya existente
> es 100% seguro. **Añadir/quitar instrucciones, o cambiar la cuenta
> de un `SET_DURATION_MULTI`, NO lo es**: cambiaría el tamaño total, y
> todo lo que va detrás en `madmix1.asm` se desplazaría de dirección
> — `TABLA_RECURSOS_SONIDO_EVENTO` seguiría apuntando a la dirección
> VIEJA. El juego compilaría sin ningún error pero saltaría a sitios
> incorrectos en tiempo de ejecución.

## 10. Herramientas

### `tools/mmsnd_tool.py` — descompilador/compilador del bytecode

```
py tools/mmsnd_tool.py disasm fichero.snd fichero.txt   # binario -> texto editable
py tools/mmsnd_tool.py asm fichero.txt fichero.snd      # texto -> binario (para recompilar el juego)
py tools/mmsnd_tool.py roundtrip fichero.snd            # verifica que disasm+asm da el mismo binario
py tools/mmsnd_tool.py roundtrip-all carpeta/           # lo mismo para todos los .snd de una carpeta
```

El formato de texto: un mnemónico por línea (`SET_VOLUME 0x09`,
`NOTE 0x3C`, etc., exactamente los nombres de la tabla de §6),
comentarios con `;`. Cada fichero generado lleva un aviso repitiendo
la advertencia de tamaño fijo de §9.

**Flujo de trabajo real para editar un sonido**: editar el `.txt` →
`py tools/mmsnd_tool.py asm fichero.txt fichero.snd` → recompilar el
juego (`sjasmplus madmix1.asm`) → verificar que sigue dando el mismo
número de bytes que antes.

### `tools/mmsnd_render.py` — renderizador a WAV

Emula el PSG (onda cuadrada + ruido LFSR simplificado + tabla de
volumen logarítmica de 16 pasos) y el intérprete de bytecode completo,
para poder ESCUCHAR un `.snd` sin necesidad de openMSX ni del juego
completo:

```
py tools/mmsnd_render.py render fichero.snd salida.wav [--max-ticks N]
py tools/mmsnd_render.py render-all carpeta/ carpeta_salida/
py tools/mmsnd_render.py render-chord fichero.snd salida.wav 0,7,14   # mezcla varias voces (ver §7, acorde de inicio de nivel)
```

**Advertencia de fidelidad**: la mecánica (qué hace cada comando, qué
tabla consulta) está verificada contra el código real, incluida la
envolvente de ruido de §8. Lo que sigue siendo una **reconstrucción
razonada, no una emulación certificada** es el detalle fino de timbre
del generador de ruido real del chip. Sirve para juzgar de oído si la
lectura del bytecode tiene sentido musical — ritmo, qué nota, cuándo
calla —, no como referencia perfecta de sonido. Herramienta y
limitaciones afinadas de forma iterativa escuchando contra el juego
real (ver `FINDINGS.md` para el historial completo de correcciones
encontradas así: mapeo de campos del instrumento, polaridad de
`SET_MIXER`, offset DC durante silencio, detección del fin de un
`LOOP`, entre otras).

## 11. Para seguir profundizando

- `FINDINGS.md` — todas las secciones relacionadas con sonido, en
  orden cronológico, con el razonamiento completo de cada
  descubrimiento (útil cuando esta versión resumida no basta;
  búsquese "envolvente de ruido" para el hallazgo de §8).
- `data/sound/_engine_tables.bin` — copia de trabajo de toda la zona
  `$C8DE`-`$CDCB` para que `mmsnd_render.py` tenga datos reales sin
  depender de compilar el juego primero.
- Único hueco real que queda: el detalle de timbre exacto del
  generador de ruido del AY-3-8910 emulado en `mmsnd_render.py` (§10)
  — la mecánica del driver en sí (qué escribe, cuándo, con qué
  fuente) ya no tiene puntos abiertos conocidos.
