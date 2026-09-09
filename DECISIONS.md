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

**Comprobado el 2026-09-09 (cierra U-27 y U-28):** `doclens` es MIT, © 2026 Govind
Maheshwari. Y su lado iOS **no usa ML Kit en absoluto** — importa Vision y VisionKit,
las de Apple. El problema es exclusivamente de Android, lo que hace la petición upstream
más fácil de defender: iOS ya hace lo correcto.

**Qué hace realmente su detector, ahora que está leído (373 líneas):** umbral sobre la
luma media con *polaridad* —papel claro sobre fondo oscuro, o DNI oscuro sobre mesa
clara, o automático—, mayor componente conexa, y recorrido del contorno aproximado a
cuatro esquinas con Douglas-Peucker sobre la envolvente convexa. Su propia cabecera dice
*"v0.1 deliberately avoids OpenCV and ML Kit"*, lo cual convierte la dependencia
incondicional del Gradle en un descuido y no en una decisión de diseño — y es
exactamente el argumento del PR.

**Hipótesis falsable para M1/M2, que es lo que hace útil la medición:** son enfoques
complementarios, no uno mejor que otro.

| Condición | Quién debería ganar | Por qué |
|---|---|---|
| Documento que no llena el encuadre | `doclens` | la componente conexa lo encuentra en cualquier parte; el nuestro escanea desde los bordes hacia dentro |
| Documento oscuro sobre fondo claro | `doclens` | tiene polaridad; el nuestro asume papel claro |
| Sombra fuerte cruzando la página | el nuestro | un umbral global parte la componente en dos; el ajuste por lado es local |
| Mesa desordenada con papeles claros alrededor | el nuestro | la componente conexa se los traga |

Si la tabla se confirma, la conclusión probable no es "elige uno" sino contribuir la
polaridad y el umbral local al mismo sitio. Eso también es upstream.

---

## D-029 · El análisis se hace en pequeño; solo la corrección toca la imagen entera
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Corrige un defecto medido, no una preferencia**

La primera versión de `ClassicalRestore` analizaba la imagen a resolución completa y
tardaba **55,9 s en una foto de 12 MP**, que es exactamente lo que produce la cámara de
un móvil. Los 19 tests pasaban: usan fixtures de 240×320, donde el coste que importaba
era invisible.

La causa no era un bucle lento sino una pregunta mal planteada. El campo de color del
papel y los mapas de ecualización son **de baja frecuencia por construcción** —el fondo
se suaviza a propósito con un radio de varios por ciento de la imagen, y los mapas
describen una rejilla gruesa de teselas—. Ninguno de los dos contiene detalle que
merezca calcularse a 12 MP.

Ahora todo se mide sobre una imagen reducida a `analysisWidth` (512 por defecto) y solo
la corrección se aplica a tamaño completo, en **una sola pasada fusionada** con
aritmética entera y sin una división por píxel.

| | Antes | Ahora |
|---|---|---|
| 12 MP gris | 55.921 ms | **608 ms** |
| 3 MP gris | 2.336 ms | 228 ms |
| 12 MP color | — | 907 ms |

Y el coste pasa a ser lineal en píxeles: antes crecía con el radio del desenfoque, y el
radio crecía con la imagen, así que 15× píxeles costaban 52× tiempo.

**Tests que impiden la recaída:** uno con una imagen 1600×1200 —la primera que ejerce el
camino de reducción, porque los fixtures antiguos no lo tocan—, otro que comprueba que
cambiar `analysisWidth` mueve el resultado menos de 6 niveles de gris de media (si lo
moviera, el ajuste sería de calidad y se vende como de rendimiento), y otro que asserta
que 4× píxeles no cuesta más de 12× tiempo, que es la forma barata de detectar una vuelta
al comportamiento cuadrático.

**Lección, más útil que el arreglo:** un test de comportamiento dice que la salida es
correcta; no dice que llegue. `tool/bench_restore.dart` existe por eso.

---

## D-030 · El permiso de cámara se pide en `start()`, y las dos negativas se distinguen
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Arregla un fallo que rompía la app en el primer arranque de cualquier dispositivo**

No se pedía el permiso de cámara en ningún sitio. Estaba declarado en el manifiesto, que
no basta desde Android 6; y en iOS faltaba además `NSCameraUsageDescription`, sin la cual
el sistema **mata la app** al tocar la cámara. Es el fallo que nunca aparece en el móvil
del que desarrolla —donde el permiso se concedió hace semanas— y le pasa a todo el mundo
la primera vez.

`start()` es quien lo pide, en las dos plataformas, porque es lo que quiere cualquier
consumidor. Y devuelve **dos códigos distintos**: `permission-denied` y
`permission-denied-permanently`. Dart los convierte en `CameraPermissionDenied` con un
flag, y la app enseña una explicación con "Reintentar" en el primer caso y un texto que
manda a los ajustes en el segundo. Una interfaz que ofrece "reintentar" después de una
negativa permanente simplemente parece rota.

También hay `permissionStatus()` sin efectos secundarios, para poder explicarse **antes**
de que salga el diálogo del sistema — que es la diferencia entre un permiso que la gente
concede y uno que rechaza.

---

## D-031 · La restauración se aplica sola, en segundo plano, después de enseñar la página
**Fecha:** 2026-09-09 · **Estado:** ratificar

`DocumentPipeline` existía, estaba testeado y **no lo llamaba nadie**: la captura
guardaba la página en la base de datos sin restaurar nada.

Ahora la captura da la página rectificada al instante —que es lo que hay que ver al
tocar el botón— y al abrir el documento se restauran en segundo plano las páginas que
falten. La página aparece y luego mejora a la vista. La columna `restored` de la BD es lo
que permite terminar un trabajo empezado sin repetir el ya hecho, y volver a marcarlo
pendiente si se corrigen las esquinas.

**Decodificar con `dart:ui`, no con un códec Dart.** Medido: decodificar un JPEG de 12 MP
en Dart puro cuesta 1.154 ms; el decodificador de la plataforma es una fracción de eso y
además reescala de camino, que es como se aplica `maxDimension` sin materializar nunca la
imagen completa.

**Restaurar y codificar en un isolate.** Juntos son ~1,7 s en un portátil para una página
de 6,8 MP y varios segundos en un móvil. Eso es una barra de progreso, no una interfaz
congelada — una diferencia invisible en un benchmark y muy visible en la mano.

**Tope de 3000 px en el lado largo** (~255 ppp en A4). Los sensores de móvil son ya de
48 MP de forma rutinaria y nada en un escaneo se beneficia de eso.

**Coste que queda y su salida:** el codificador JPEG de Dart puro es ahora el término
mayor (904 ms de los 1.659 ms). Codificar nativamente lo bajaría a ~100 ms. No se hace
todavía porque metería un códec en un paquete que no le corresponde, o glue nativo sin
probar en la app; queda anotado con su número en `docs/measurements.md` en vez de
arreglado a medias.

---

## D-032 · Tres filtros de página, y salen gratis
**Fecha:** 2026-09-09 · **Estado:** ratificar

Color, escala de grises y blanco y negro. Son de rigor en un escáner, y aquí además
cuestan cero: la curva de contraste del modo blanco y negro se **compone dentro de las
tablas de ecualización**, que el pipeline iba a consultar una vez por píxel de todas
formas.

Es una curva y no un umbral duro a propósito. Un umbral queda decidido en una captura de
pantalla y se come el borde suavizado de cada letra, que es justo el detalle que lee el
OCR. La transición se mantiene unos cuantos niveles de ancho, y hay un test que lo
comprueba.

**Medido, 6,8 MP:** color 1.383 ms, gris 1.051 ms, blanco y negro 1.043 ms.

**Hallazgo por el camino:** pasarle al codificador de `package:image` un búfer de un solo
canal produce igualmente un JPEG de **tres componentes** y un fichero del **doble de
tamaño** (691 KB frente a 349 KB con los mismos píxeles). Así que el gris se expande a
RGB antes de codificar: una pasada más, croma plano, y JPEG lo comprime a casi nada.

---

## D-033 · La corrección manual de esquinas no es un extra
**Fecha:** 2026-09-09 · **Estado:** ratificar · **Origen:** plan T1, ahora implementado

La detección falla con papel de poco contraste, mesas desordenadas y mala luz. Sin una
forma de arreglarlo a mano, la única salida es repetir la foto — que suele fallar igual
por el mismo motivo.

Ahora cada página tiene su acción de ajustar esquinas, se guarda el cuadrilátero usado
(columna `quad`), y el reencuadre se hace **siempre desde el fotograma original**. Volver
a deformar una imagen ya deformada es corregir una corrección. Y al reencuadrar se marca
`restored = 0`, así que la restauración vuelve a pasar sola sobre el recorte nuevo.

---

## D-034 · Exportar sin compartir es mentira
**Fecha:** 2026-09-09 · **Estado:** ratificar

El export escribía el PDF en un directorio del sandbox al que el usuario no llega en
ninguna de las dos plataformas. Ahora se ofrece al share sheet del sistema
(`share_plus`), y además se deja en disco para los gestores de ficheros que existan.

Es la única dependencia nueva de la app aparte de `image`, y hace la diferencia entre una
función que existe y una que sirve.

---

## D-035 · Los escaneos se copian fuera de la caché al guardarlos
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Arregla una pérdida de datos silenciosa**

`byrsa_capture` escribe sus resultados en el directorio de **caché** de la plataforma
—`context.cacheDir` en Android, `NSTemporaryDirectory()` en iOS—. Eso está bien: una
captura que el usuario descarta no debería sobrevivir.

Lo que estaba mal era que la app guardaba **esas mismas rutas** en la base de datos. El
sistema operativo puede vaciar esos directorios cuando le falte espacio, así que los
documentos del usuario desaparecían solos, semanas después, sin ningún error en ningún
sitio. El mismo problema con `image_picker`, que también devuelve una copia en caché.

La regla queda escrita en `ScanStorage`: **el plugin produce ficheros temporales y todo lo
que la app decide conservar se copia primero.** Y al borrar un documento se borran sus
imágenes, porque si no el único síntoma es un móvil que se va llenando de documentos que
el usuario ya borró.

Seis tests, uno de los cuales borra el directorio de caché entero después de guardar y
comprueba que el fichero sigue ahí. Es el fallo entero en una aserción.

---

## D-036 · Las preferencias viven en la base de datos que ya está abierta
**Fecha:** 2026-09-09 · **Estado:** ratificar

Filtro, captura automática y reconocimiento automático se guardan en una tabla
`settings` de clave-valor en la base de datos de la biblioteca, no en
`shared_preferences`.

**Por qué:** la base de datos ya está abierta, ya viaja con los documentos en una copia de
seguridad, y una tabla de dos columnas es menos maquinaria que otra dependencia. Un filtro
que vuelve a "Color" cada vez que sales de la pantalla no es una preferencia, es una
molestia.

**El reconocimiento automático viene desactivado a propósito.** En Android la primera
ejecución descarga modelos, y un escáner que va a la red sin que se lo pidan es justo lo
que este proyecto existe para no ser.

---

## D-037 · Spike de ONNX en Android: el export de imagen se descarta, y dos runtimes chocan
**Fecha:** 2026-09-09 · **Estado:** ratificar
**Todo lo de aquí está medido, no supuesto**

Tres resultados, y los tres cambian el plan.

### 1. El export de UVDoc que traía el plan no sirve para móvil

`PaddlePaddle/UVDoc_onnx` acepta `[N,3,H,W]` con las dimensiones espaciales dinámicas y
devuelve `[N,3,H',W']` — **tres canales, o sea una imagen rectificada**. Esa era justo la
ambigüedad que anunciaba §4.2 ("según el export devuelve imagen rectificada o grid").

Ejecutado con onnxruntime en CPU, cuatro hilos:

| Entrada | Tiempo | RSS pico |
|---|---|---|
| 712×488 (0,3 MP) | 188 ms | 144 MB |
| 1600×1200 (1,9 MP) | 258 ms | 209 MB |
| 2000×1500 (3,0 MP) | 312 ms | 289 MB |
| 3000×2250 (6,8 MP) | 487 ms | **477 MB** |

El tiempo casi no crece —la red reduce internamente, exactamente como decía el plan— pero
**la memoria sí**, porque la salida es una imagen del tamaño de la entrada. Y como solo
puede darte una página tan grande como el tensor que le metas, una página a resolución
completa exige 477 MB de pico. Eso en un móvil de gama media no es lento, es que el
sistema mata la app.

### 2. El export de grid sí sirve, y es el que hay que usar

`fredcallagan/uvdoc-grid-onnx` (Apache-2.0, 31,8 MB en dos ficheros): entrada fija
`[1,3,720,496]`, salida `[1,2,45,31]` en [-1,1]. **173 ms y 127 MB**, y la resolución del
resultado se decide después, en Dart, con código que sí está testeado.

El remapeo va en `dewarp.dart`, en Dart puro, con diez tests. La convención está anclada
al código de los autores originales (`bilinear_unwarping` en `tanguymagne/UVDoc` usa
`align_corners=True` tanto en `F.interpolate` como en `F.grid_sample`), no adivinada — y
de paso el `example.py` del propio export **diverge** de ella al reescalar el grid con
`cv2.resize`, que aplana media celda en cada borde. Se sigue a los autores.

### 3. Dos ONNX Runtime en la misma app chocan, y solo se nota en release

`mobile_ocr` trae el AAR de Java (`onnxruntime-android` 1.27.0, 28 MB por ABI);
`byrsa_restore` trae el paquete Dart de FFI (su propio build, 14 MB). Los dos ponen un
fichero llamado `libonnxruntime.so`.

```
Execution failed for task ':app:mergeReleaseNativeLibs'.
> 2 files found with path 'lib/arm64-v8a/libonnxruntime.so'
```

**El build de debug los empaqueta sin rechistar y el de release falla.** Es decir: el
fallo aparece justo cuando vas a publicar.

**Y el apaño obvio es una trampa.** `pickFirsts` hace que compile, y medido, se queda la
biblioteca de 14,2 MB del paquete Dart y descarta la de 28 MB del AAR:

| | Antes del spike | Con `pickFirsts` |
|---|---|---|
| `arm64-v8a` release | 48,0 MB | 35,0 MB |

La app adelgaza 13 MB, que parece una victoria y es la alarma: el shim JNI de
`mobile_ocr`, compilado contra la 1.27.0, se queda emparejado con otra biblioteca más
antigua. Un APK que ha encogido es exactamente la forma en que eso se publica.

Así que la elección se hace **determinista**: se excluye la copia del paquete Dart en su
propio subproyecto y solo sobrevive la del AAR. Verificado descomprimiendo el APK de
release: la que queda es la de 27.985.944 bytes, junto al shim que se compiló contra
ella.

Cuál de los dos emparejamientos es el seguro es un juicio, y conviene decirlo: la API de C
de ONNX Runtime está versionada y es retrocompatible, así que un binding de FFI generado
contra una cabecera vieja llamando a una biblioteca nueva es la dirección que sobrevive.
Un shim JNI compilado para 1.27.0 buscando símbolos en un build anterior, no. Sigue sin
verificarse en dispositivo (U-33).

Los dos arreglos de verdad, para cuando haya móvil que lo decida:

1. **Un solo runtime.** Que `byrsa_restore` llame a ONNX por la API de Java a través de un
   canal, reutilizando el AAR que `mobile_ocr` ya trae. Robusto; el precio es código
   nativo en un paquete que hoy es Dart puro (contradice D-020 y habría que re-litigarlo).
2. **Alinear versiones upstream**, para que los dos `.so` sean el mismo build. Depende de
   dos terceros y no lo controlamos.

`tool/check_native_collisions.sh` existe para que esto se vea, no para arreglarlo.

### 4. Y el paquete Dart de ONNX Runtime ya no compila en release

Detrás de la colisión aparece otra:

```
:onnxruntime:checkReleaseAarMetadata
> Dependency 'androidx.fragment:fragment:1.7.1' requires ... version 34 or later.
  :onnxruntime is currently compiled against android-33.
```

`onnxruntime_flutter` 1.4.1 fija `compileSdkVersion 33`, y AndroidX actual exige 34 o
más. **Otra vez solo en release.** Desbloqueado subiendo el `compileSdk` del subproyecto
desde el `build.gradle.kts` de la app, que es el apaño estándar para un plugin que se ha
quedado atrás y es seguro —`compileSdk` decide a qué APIs puede llamar la biblioteca, no
en qué dispositivos corre, y su `minSdkVersion 21` no se toca—. El arreglo de verdad es
una línea en el plugin: `docs/upstream/onnxruntime-flutter-compilesdk.md`.

**Lectura conjunta de 3 y 4:** las dos pegas vienen del mismo sitio. El paquete Dart de
FFI vendoriza su propio `.so` y va por detrás del toolchain; el AAR oficial que ya trae
`mobile_ocr` no tiene ninguno de los dos problemas.

Y aun así **no se cambia al AAR**, por una razón que vale la pena escribir porque es la
que decide: el AAR es de Java y solo existe en Android. En iOS `mobile_ocr` usa Vision, no
ONNX. Pasar la rectificación a la API de Java significaría **quedarse sin aplanado en
iOS**, que es exactamente el riesgo de §4.6 pero autoinfligido. El paquete de FFI es hoy
el único camino que da las dos plataformas, así que los apaños son el precio y quedan
anotados con su riesgo (U-33), no escondidos.

Si el spike en dispositivo dice que `pickFirsts` no es seguro, la salida es la API de Java
**como respaldo solo de Android**, no como sustitución.
