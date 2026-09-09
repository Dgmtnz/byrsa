<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Decisiones

Registro de decisiones de diseño del proyecto Byrsa. Formato ADR ligero: una decisión
por entrada, con su porqué y su coste. Este es el fichero que pide §12/S1 del plan
(`plan-escaner-open-source-flutter.md`) y el `Decisiones.md` del encargo: es el mismo
documento, en el nombre que el plan ya había fijado.

Estado: `firme` (viene del plan, no se re-litiga) · `ratificar` (tomada durante el
desarrollo, pendiente de revisión definitiva) · `abierta` (falta un dato para cerrarla).

---

## D-001 · ML Kit queda descartado; sin Google Play Services
**Fecha:** 2026-09-08 · **Estado:** firme · **Origen:** plan §0.1

La decisión previa del mismo día de usar ML Kit Document Scanner como camino único de
captura queda revertida. La captura es `doclens` (MIT) más pipeline propio.

**Por qué:** el entregable son cuatro paquetes que otros deben poder adoptar. Un paquete
que arrastra Play Services no lo adopta nadie en el ecosistema al que va dirigido, y
difícilmente lo financia un fondo cuyo criterio es la soberanía tecnológica europea.

**Coste aceptado:** semanas de ingeniería de cámara que ML Kit regalaba.
**Consecuencia:** F-Droid es requisito desde el commit uno, no un extra.

---

## D-002 · iOS se escribe completo aunque no se pueda compilar
**Fecha:** 2026-09-08 · **Estado:** firme · **Origen:** plan §0.2

No hay Mac. Aun así se escribe la implementación Swift/AVFoundation completa, la carpeta
`ios/` completa y APIs Dart simétricas. CI tiene job de iOS aunque falle. Prohibido
afirmar resultados de iOS sin medirlos. Todo lo no verificado va a `UNVERIFIED.md`.

**Por qué:** un job rojo es información; un job ausente es deuda invisible. Y la API
simétrica es exactamente lo que convierte el plan B de Core ML (§4.6) en un cambio de
implementación y no en un rediseño.

---

## D-003 · Monorepo con *pub workspaces*, sin Melos
**Fecha:** 2026-09-08 · **Estado:** ratificar

Seis paquetes en un repositorio, resueltos con `workspace:` nativo de Dart 3.6+ y
`resolution: workspace` en cada `pubspec.yaml`. Sin Melos.

**Por qué:** Melos es una dependencia y un fichero de configuración más para hacer lo que
el gestor de paquetes ya hace desde que existen los workspaces. Menos superficie que
mantener durante doce meses, y un `dart pub get` en la raíz resuelve todo el árbol.

**Cuándo reconsiderarlo:** si hiciera falta versionado y publicación coordinada de los
cuatro paquetes a la vez (`melos publish`). Publicar cuatro paquetes a mano cuatro veces
al año es más barato que mantener Melos todo el año.

---

## D-004 · El dominio vive dentro de `app/`, no es un quinto paquete
**Fecha:** 2026-09-08 · **Estado:** ratificar

`app/lib/src/domain/` es Dart puro, sin ningún `import 'package:flutter/...'`, y hay un
test que lo comprueba de forma automática.

**Por qué:** el plan §3 dibuja el dominio como capa de la app, no como entregable. Un
quinto paquete publicado sin usuarios externos es mantenimiento sin beneficio. La
propiedad que importa —testeable en CI de Linux sin dispositivo— la da la pureza del
código, no el `pubspec.yaml`.

**Cuándo reconsiderarlo:** si alguien externo pidiera el modelo de dominio suelto.
Extraerlo entonces es mover una carpeta.

---

## D-005 · Idiomas: repo en inglés, bitácora interna en español
**Fecha:** 2026-09-08 · **Estado:** ratificar

README, CONTRIBUTING, código, comentarios, dartdoc y mensajes de commit en inglés.
`DECISIONS.md` y las notas de trabajo, en español.

**Por qué:** la adopción por terceros es el criterio de éxito del proyecto y el idioma del
ecosistema Dart es el inglés. La bitácora de decisiones la escribes y la defiendes tú, y
se escribe mejor en tu idioma. La solicitud a NLnet va en inglés igualmente.

---

## D-006 · Flutter SDK instalado en `~/.local/share/flutter`
**Fecha:** 2026-09-08 · **Estado:** ratificar

La máquina no tenía ni `flutter` ni `dart`. Se instaló el SDK estable 3.47.2 en el
directorio del usuario, sin `sudo` y sin tocar el sistema.

**Por qué:** sin SDK no hay forma de comprobar nada, y "código sin su comprobación está sin
terminar". Se evita `pacman` a propósito: la versión de la distribución avanza sola y CI
tiene que poder fijar la misma versión exacta que la máquina de desarrollo.

**Para deshacerlo:** `rm -rf ~/.local/share/flutter`.

---

## D-007 · La versión de Flutter se fija en `.fvmrc` y CI lee de ahí
**Fecha:** 2026-09-08 · **Estado:** ratificar

Un único sitio con la versión (`.fvmrc`), del que leen tanto CI como quien use FVM.

**Por qué:** una build reproducible —requisito de F-Droid y de M6— empieza por que nadie
pueda contestar "¿con qué versión?" con "con la que tuviera puesta". No se añade FVM como
dependencia obligatoria: el fichero es sólo un dato, y funciona igual con `flutter` global.

---

## D-008 · `dart_searchable_pdf` no depende de ningún paquete PDF
**Fecha:** 2026-09-08 · **Estado:** ratificar

Escribe los objetos COS del PDF por sí mismo. Cero dependencias fuera de `meta`.

**Por qué:** el plan (§2, tabla del §3) barajaba `pdf_cos`/`pdf_document` para el nivel bajo.
Pero el entregable T4 es precisamente la pieza que no existe en Dart, y lo que hace que
un paquete de infraestructura se adopte es que no arrastre árbol de dependencias. Un
escritor de PDF 1.7 mínimo —cabecera, objetos, `xref`, `trailer`— son unos cientos de
líneas bien acotadas, y las trampas reales (métrica de fuente, `Tz` por palabra,
codificación WinAnsi) hay que resolverlas igual con dependencia o sin ella.

**Coste aceptado:** mantener nosotros la serialización COS.
**Límite marcado:** sin cifrado, sin *incremental update*, sin *linearization*. Están
anotados como `TODO:` en el código, con su camino de ampliación.

---

## D-009 · Las métricas de fuente de las 14 fuentes estándar se calculan, no se empaquetan
**Fecha:** 2026-09-08 · **Estado:** ratificar

Se incluyen las tablas de anchos de Helvetica (y las variantes que se usen) como datos
Dart generados, no como ficheros AFM leídos en tiempo de ejecución.

**Por qué:** son 4 KB de constantes. Un asset que hay que declarar en `pubspec.yaml`,
cargar de forma asíncrona y manejar cuando falla es más código y más fallos que una tabla
`const`. Y el paquete tiene que poder usarse en Dart puro, sin `rootBundle`.

**Cuándo reconsiderarlo:** al soportar fuentes TrueType incrustadas para escrituras no
latinas. Ahí sí hay que parsear métricas de verdad, y es otro problema.

---

## D-010 · La capa invisible se ajusta con `Tz` por palabra, no por carácter
**Fecha:** 2026-09-08 · **Estado:** ratificar · **Origen:** plan §4.5, concretado

Cada palabra reconocida se dibuja como un `Tj` propio con su `Tz` (escala horizontal)
calculado para que el ancho renderizado coincida con el ancho de su *bounding box*.

**Por qué:** es la granularidad a la que trabaja el OCR. Por línea desalinea el
copiar-pegar dentro de la línea; por carácter multiplica el tamaño del *content stream*
sin que ningún visor lo aproveche, porque la selección se resuelve por palabra.

**Límite conocido:** si el OCR devuelve una caja mal, la palabra queda mal. Se prefiere
respetar la caja del OCR a inventar una.

---

## D-011 · La línea base clásica (§4.3) se implementa antes que cualquier red
**Fecha:** 2026-09-08 · **Estado:** firme · **Origen:** plan §4.3 y §12/S3

CLAHE + división por fondo estimado se implementa primero y es la línea base contra la
que se mide DocShadow en M2/M3.

**Por qué:** es una tarde de trabajo, mejora todos los escaneos, no necesita descargar
nada, y sin ella no hay forma honesta de decir cuánto aporta la red. Además da a
`byrsa_restore` un camino útil y sin modelos para dispositivos flojos.

---

## D-012 · El harness es un CLI de Dart, no un script de Python
**Fecha:** 2026-09-08 · **Estado:** ratificar

`harness/` es un paquete Dart ejecutable con `dart run harness`.

**Por qué:** reproducibilidad por terceros. Con Dart, quien clone el repo ya tiene el
único toolchain necesario; con Python haría falta un segundo entorno y su fichero de
versiones. Y el cálculo de CER (Levenshtein sobre caracteres) es idéntico de escribir en
los dos idiomas.

**Coste aceptado:** nada de `numpy`/`matplotlib`. El informe sale en Markdown, CSV y JSON,
y quien quiera gráficas los abre donde quiera.

---

## D-013 · Los modelos ONNX se descargan; el repositorio no contiene binarios
**Fecha:** 2026-09-08 · **Estado:** firme · **Origen:** plan §4.4 y §4.8

Descarga bajo demanda desde URL fijada, verificación SHA-256, caché en disco, opt-in
explícito del usuario la primera vez que pide OCR o rectificación.

**Consecuencia declarada, no escondida:** la app declara permiso `INTERNET`. La frase
correcta —y la única que se usa en README y solicitud— es la de §4.8: *ningún documento
sale nunca del dispositivo; el único tráfico posible es una descarga de modelos que el
usuario inicia*.

**Riesgo abierto:** criterio de F-Droid sobre blobs descargados en runtime (U-13). Salida
prevista: *flavor* de build con los modelos cuantizados empaquetados.

---

## D-014 · El manifiesto de modelos es un fichero versionado, no constantes en el código
**Fecha:** 2026-09-08 · **Estado:** ratificar

`models.json` en la raíz, con nombre, URL, SHA-256, tamaño y **licencia** de cada modelo.
Los paquetes lo leen; el harness y el auditor de licencias también.

**Por qué:** U-14 obliga a auditar la licencia de cada modelo PaddleOCR por separado. Una
tabla que un revisor puede leer de un vistazo, y un diff que se ve cuando una URL o un
hash cambian, valen más que las mismas constantes repartidas por tres paquetes.

---

## D-015 · Sin cifrado en la v1 del esquema de base de datos, pero con la puerta puesta
**Fecha:** 2026-09-08 · **Estado:** ratificar

El esquema drift nace sin SQLCipher. El cifrado opcional (§3, §7) entra como migración
posterior, y los ficheros en disco se referencian por ruta relativa a un directorio raíz
configurable para que cambiar a un almacén cifrado no toque el esquema.

**Por qué:** SQLCipher condiciona la build de Android desde el minuto uno y no aporta nada
hasta que hay una UI de contraseña. Está dentro del alcance del año (§7), no de la semana
uno.

---

## D-016 · La app no bloquea el pipeline: cada etapa es opcional y degrada
**Fecha:** 2026-09-08 · **Estado:** ratificar

`Pipeline` ejecuta etapas en orden y cada una puede declararse no disponible (modelo no
descargado, plataforma sin soporte). Se salta y se registra en el resultado, no lanza.

**Por qué:** es la única forma de que la app funcione en un F-Droid sin modelos
descargados, en un dispositivo flojo y en un iPhone sin ONNX (§4.6) con el mismo código.
Y hace que el harness pueda medir "con y sin cada etapa" sin ramas especiales, que es
justo lo que M2 necesita.

---

## D-017 · `byrsa_capture` no depende de `doclens`; se escribe el detector propio
**Fecha:** 2026-09-08 · **Estado:** ratificar
**Contradice al plan §4.1, y con motivo verificable**

El plan dice "no lo reimplementes, forkea `doclens`". Al leer `doclens` 0.0.9 aparece
esto en `android/build.gradle.kts`:

```kotlin
implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
```

Son dependencias **incondicionales**. Gradle las resuelve siempre, así que cualquier app
que añada `doclens` mete Play Services en su APK aunque no llame nunca a esos caminos.
Solo tres ficheros los usan (`NativeUIScanner.kt`, `TextRecognizer.kt`,
`TextOrientationDetector.kt`); el núcleo —`QuadDetector`, `ImageWarper`, la sesión
CameraX— no los toca.

**Por qué gana §0.1:** la regla cerrada dice sin Play Services, y §0 gana sobre cualquier
otra sección del plan. Depender de `doclens` hoy rompería el requisito en el commit uno.

**Qué se hace en su lugar:** `byrsa_capture` lleva su propio plugin —CameraX y
AVFoundation— con detector clásico propio, y se abre el issue upstream proponiendo un
*flavor* de Gradle que haga ML Kit opcional
(`docs/upstream/doclens-play-services.md`). Si se acepta, volver a depender de `doclens`
es cambiar un `pubspec.yaml`.

**Coste aceptado:** exactamente las "semanas de ingeniería de cámara" que §0.1 ya decía
que se pagaban a conciencia.

**Verificado, no supuesto:** `tool/check_no_play_services.sh` sobre el APK del ejemplo da
0 clases `com.google.android.gms` frente a 1717 referencias `androidx.camera`. Corre en
CI. Es el séptimo reto técnico de §13.5 y el PR upstream de §12/S6.

---

## D-018 · Una sola fuente (Helvetica) en la capa invisible
**Fecha:** 2026-09-08 · **Estado:** ratificar

La capa invisible usa Helvetica y nada más. Sin negritas ni cursivas.

**Por qué:** el texto es invisible; el peso tipográfico no se ve. Lo único que importa es
que el ancho renderizado coincida con la caja, y eso lo resuelve `Tz` con cualquier
fuente. Cuatro tablas de métricas para un resultado idéntico es peso muerto.

**Lo que sí se añade, porque cuesta una línea y vale mucho:** `debugVisibleText`, que
pinta la capa en rojo. El fallo típico de esta técnica es invisible por construcción, y
poder mirarlo es la diferencia entre depurarlo en un minuto o en una tarde.

---

## D-019 · El harness separa ejecutar de puntuar
**Fecha:** 2026-09-08 · **Estado:** ratificar

El dispositivo ejecuta el pipeline y escribe `run.json`; el harness puntúa ese fichero.
Nunca ejecuta nada él.

**Por qué:** la aritmética del CER tiene que existir una sola vez y correr en CI de Linux
hoy, sin dispositivo. Y la app ya emite los tiempos por etapa exactamente en ese formato
(`PageResult.toHarnessJson`), así que una tirada real en un móvil real produce un fichero
que el benchmark publicado puntúa sin conversión.

---

## D-020 · La restauración clásica es Dart puro; `opencv_dart` se aplaza
**Fecha:** 2026-09-08 · **Estado:** ratificar

CLAHE, estimación de fondo y división se implementan a mano sobre `Uint8List`.
`opencv_dart` (→ `dartcv4`) no entra todavía.

**Por qué:** son unas 200 líneas de aritmética que se testean en un portátil sin
dispositivo, y evitan ~30 MB de biblioteca nativa por ABI en el camino que tiene que
funcionar en el móvil más flojo y en una build de F-Droid sin descargas. El riesgo de
"tamaño de app > 150 MB" de §11 se paga aquí.

**Cuándo reconsiderarlo:** `cv.inpaint` (Telea) para los dedos en el borde (§4.3) sí es
difícil de escribir a mano. Cuando toque esa etapa, se evalúa con el tamaño medido
delante.

---

## D-021 · `byrsa_ocr` delega en `mobile_ocr`; no es un plugin nativo
**Fecha:** 2026-09-08 · **Estado:** ratificar

`byrsa_ocr` no lleva Kotlin ni Swift. Es una capa Dart sobre `mobile_ocr` (MIT), que ya
hace Vision en iOS y PP-OCRv5 por ONNX en Android, con descarga y verificación propias y
sin Play Services.

**Por qué:** es literalmente lo que dice el plan (§2, "Base: `ente-io/mobile_ocr`") y lo
que dice el escalón de reutilizar antes que escribir. Reimplementar PP-OCR —DB
post-processing, CTC, diccionario— son meses y deja al ecosistema con dos copias a medio
mantener.

**Bloqueo conocido y declarado:** pub.dev rechaza paquetes con dependencias git, y
`mobile_ocr` no está en pub.dev. Luego `byrsa_ocr` **no se puede publicar todavía**. Está
escrito en el `pubspec.yaml`, no escondido. La salida es pedirlo upstream
(`docs/upstream/mobile-ocr-pub-dev.md`), no reimplementar.

**Lo que sí aporta la capa:** API estable, orden de lectura idéntico en las dos
plataformas y testeado en Linux, política de confianza en un sitio, cajas por palabra
—las dos plataformas devuelven un polígono por bloque, y un PDF buscable necesita una
caja por palabra— y un tipo de resultado sin `dart:ui`, que es lo que permite pasárselo
directo a `dart_searchable_pdf`.

---

## D-022 · SQL a mano sobre `sqlite3`, sin drift ni `build_runner`
**Fecha:** 2026-09-08 · **Estado:** ratificar
**Se aparta de la tabla de stack del plan §3**

**Por qué:** FTS5 hay que escribirlo en SQL de todas formas; el esquema son cuatro
tablas; y un paso de generación que reescribe ficheros del repositorio es justo lo que no
quiere una build reproducible de F-Droid (M6). Sin `build_runner` no hay ficheros `.g.dart`
en el repo ni un paso más en CI.

**Lo que se pierde:** consultas comprobadas en compilación y streams reactivos gratis. Se
sustituye por un contador de revisión en Riverpod, que son cinco líneas para una
biblioteca de este tamaño.

**Detalle que sí importa y está testeado:** el índice FTS es *external content*, así que
página e índice no pueden discrepar; la búsqueda ignora acentos (`remove_diacritics 2`)
porque nadie escribe tildes en un buscador; y un `"` o un `*` sueltos devuelven cero
resultados en vez de un error de sintaxis de FTS5 que el usuario tendría que entender.

---

## D-023 · Borrar una carpeta no borra sus documentos
**Fecha:** 2026-09-08 · **Estado:** ratificar

`folder_id` es `ON DELETE SET NULL`: al borrar una carpeta, sus documentos vuelven a la
raíz. Las subcarpetas sí caen en cascada.

**Por qué:** perder una carpeta es un accidente; perder los escaneos de dentro es un
desastre. Y un escáner de documentos guarda cosas que no se pueden volver a hacer.

---

## D-024 · Los modelos se fijan descargándolos, no copiando hashes
**Fecha:** 2026-09-08 · **Estado:** ratificar

`models.json` tiene los cinco modelos con su SHA-256 real, calculado el 8 de septiembre
de 2026 con `tool/pin_models.dart`. `--verify` los vuelve a comprobar.

**Por qué:** un hash que nadie ha calculado es un hash que nadie puede defender. Y
`--verify` es cómo el proyecto se entera de que una URL "estable" ha empezado a servir
otra cosa.

**Hallazgo del proceso, que cambia el plan:** DocShadow-SD7K exportado a ONNX pesa
**120.041.674 bytes**, cuatro veces UVDoc. La cuantización no es una optimización de T2,
es la condición para que se pueda usar. Va a `UNVERIFIED.md` como medición pendiente y a
los retos técnicos de la solicitud.

**Pendiente:** la licencia de los tres modelos PP-OCRv5 está como `UNAUDITED` a propósito
(U-14). Poner "Apache-2.0" sin haber leído cada model card sería exactamente el tipo de
afirmación que este proyecto no hace.

---

## D-025 · La decisión de disparar la toma se toma en Dart, no en el nativo
**Fecha:** 2026-09-08 · **Estado:** ratificar

El lado nativo publica lo que ve —quad, nitidez, brillo— y nada más. Quién decide
que la escena está lista es `StabilityTracker`, en Dart.

**Por qué:** es una decisión con umbrales que hay que afinar, y tenerla dos veces
(Kotlin y Swift) garantiza que las dos plataformas se comporten distinto y que nadie
pueda testearla sin un móvil. En Dart se testea en un portátil y es idéntica en las dos.

**Bug real que esto destapó y que ya está cubierto por test:** el controlador reenviaba
el `hint` del nativo, y el nativo solo emite `noDocument` o `moving` — nunca `ready`. El
auto-disparo no habría saltado jamás. El test `decides readiness itself rather than
trusting the platform hint` existe exactamente para que no vuelva a pasar.

---

## D-026 · Splits por ABI desde el principio, no como optimización tardía
**Fecha:** 2026-09-08 · **Estado:** firme · **Medido** · **Origen:** plan §11

`flutter build apk --release --split-per-abi` sobre la app completa:

| ABI | Tamaño |
|---|---|
| `armeabi-v7a` | 37,4 MB |
| `arm64-v8a` | **48,0 MB** |
| `x86_64` | 55,4 MB |

Eso es la app entera —captura, restauración, OCR con ONNX Runtime y escritor de PDF—
**antes de descargar ningún modelo**, y el APK de arm64 sigue sin una sola clase de Play
Services después del shrinking de R8.

**Consecuencia para el plan:** §11 daba "tamaño > 150 MB" como riesgo de probabilidad
alta. Con splits no está ni cerca. El término dominante es la biblioteca nativa de ONNX
Runtime, ~28 MB en arm64, que es el precio de hacer inferencia sin Play Services y
conviene decirlo así en la solicitud en vez de esconderlo.

---

## D-027 · La dependencia se invierte: `byrsa_ocr` es la API, el motor va aparte
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Sustituye al bloqueo declarado en D-021**

`byrsa_ocr` pasa a ser **Dart puro**: sin Flutter, sin canales de plataforma, sin motor.
Dependencias: `meta` y `plugin_platform_interface`, las dos minúsculas y las dos Dart
puro. El adaptador sobre `mobile_ocr` se va a un paquete propio,
`byrsa_ocr_mobile_ocr`, que es el único que declara la dependencia git.

```
byrsa_ocr                 API + orden de lectura + tipos       PUBLICABLE
byrsa_ocr_mobile_ocr      Vision (iOS) + PP-OCR ONNX (Android) no publicable, y da igual
```

**Por qué:** D-021 dejaba T3 bloqueado esperando a que Ente publicara `mobile_ocr`, es
decir, dependiendo de la agenda de un tercero para cumplir un hito. Esto lo desbloquea
sin pedirle nada a nadie, y de paso el paquete queda mejor: se puede usar en un servidor,
en un CLI o en un test, y cualquiera puede enchufar su propio motor extendiendo
`ByrsaOcrPlatform`. El coste de la restricción de pub.dev pasa de "el paquete que la
gente quiere adoptar" a "un paquete de pegamento que a nadie le importa".

**Verificado:** `dart pub publish --dry-run` sobre `byrsa_ocr` pasa sin avisos, y corre
en CI para que un cambio no devuelva la dependencia git a su sitio en silencio.

**Lo que no cambia:** la petición upstream a Ente sigue en pie, pero ahora es un regalo
al ecosistema y no una condición para nuestro hito. Se pide mejor desde ahí.

---

## D-028 · Con `doclens` no se forkea: se contribuye, y decide el benchmark
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Completa D-017, que se queda como está**

Tres decisiones en una:

**1. No se forkea.** §1 del plan dice que la enfermedad del ecosistema es que cada
intento vive aislado. Forkear un paquete MIT por dos líneas de Gradle es exactamente esa
enfermedad. Además un fork es rebase para siempre, y publicarlo en pub.dev con otro
nombre fragmenta lo que este proyecto dice querer unir.

**2. La propuesta upstream son dos PRs, y uno es un regalo.** Al releer los tres
ficheros que usan ML Kit, no son equivalentes:

| Fichero | Qué hace | Salida |
|---|---|---|
| `TextOrientationDetector` | orientación de la página en `AutoOrientation.auto` | **Se sustituye por CV clásica** (perfiles de proyección o histograma de gradientes). Le quitas una dependencia sin quitarle una función |
| `TextRecognizer` | helper de OCR | Sobra en un plugin de captura; es scope de otro paquete |
| `NativeUIScanner` | UI nativa de Google | *Es* Play Services. `compileOnly` + guarda por `Class.forName` y regla `-dontwarn` |

Descartadas: el *flavor* de Gradle obliga a `missingDimensionStrategy` en cada consumidor
y en la receta de F-Droid, frágil; el paquete companion es el límite más limpio pero
mucha rotación para los usuarios actuales; y stubs vacíos de GMS con `exclude group:`
para no forkear funciona, existe en el mundo real, y es justo lo que un revisor de
F-Droid mira con lupa — no.

**3. Qué detector usamos: lo decide el número, no la preferencia.** Hoy `byrsa_capture`
lleva el suyo (D-017). No sé si el de `doclens` es mejor: hice grep, no leí
`QuadDetector.kt`. El harness convierte eso en una pregunta barata. **Criterio de corte:
se miden los dos sobre los 50 documentos en M1/M2.** Si gana `doclens` con claridad, el
movimiento correcto es depender de él con el PR ya mergeado; si no, nos quedamos con el
nuestro y el PR sigue siendo una contribución que vale por sí sola. En ningún escenario
se forkea.

**Pendiente antes de tocar nada:** verificar el fichero `LICENSE` de `doclens` — el plan
dice MIT y no lo he comprobado — y si el lado iOS usa Vision/VisionKit en vez de ML Kit,
que es lo probable pero tampoco está verificado (U-27, U-28).
