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

El release vuelve a **48,8 MB en arm64**. No se puede atribuir la diferencia con los
48,0 MB del día anterior al binding de ONNX, porque entre medias entraron también
`image`, `image_picker` y `share_plus`. Lo que sí se puede decir mirando el contenido del
APK en vez de restando: el segundo binding **no aporta ninguna biblioteca nativa propia**,
porque su copia se excluye y comparte la que ya traía el motor de OCR.

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

---

## D-038 · Codificar el JPEG lo hace la plataforma, con respaldo en Dart
**Fecha:** 2026-09-09 · **Estado:** ratificar

Codificar una página de 6,8 MP en Dart puro cuesta ~900 ms, y era el término mayor de lo
que tarda un escaneo desde que se captura hasta que se ve bien. El codificador de la
plataforma —`Bitmap.compress` en Android, `UIImage.jpegData` en iOS— ya está en todos los
dispositivos.

**Dónde vive:** en la app, como canal propio (`dev.byrsa/codec`), no en un paquete. Un
plugin de captura no tiene por qué llevar un códec de imagen; `byrsa_restore` es Dart puro
a propósito (D-020, y D-037 es lo que pasa cuando un paquete se trae lo suyo); y un
paquete de ochenta líneas con un solo consumidor es un paquete que no ha pedido nadie. Si
aparece un segundo consumidor, es mover un fichero.

**El respaldo no es decorativo.** Si el canal no está —plataforma sin implementar, isolate
sin messenger, el codificador se niega— se usa el de Dart. Un fallo aquí cuesta velocidad,
nunca el escaneo. Y **cuál de los dos corrió se registra en la etapa** (`encode:native` o
`encode:dart`), porque un benchmark que no dice cuál se usó no está diciendo gran cosa.

**Detalle que hay que saber:** un isolate de fondo no tiene canal de plataforma hasta que
se le pasa el `RootIsolateToken` del isolate raíz y se llama a
`BackgroundIsolateBinaryMessenger.ensureInitialized`. Sin eso el camino nativo es
sencillamente inalcanzable y corre el de Dart — correcto, y lento.

**Sin medir todavía:** el tiempo real del codificador nativo. Necesita dispositivo (U-35).
Lo único que se afirma aquí es lo que cuesta el de Dart, que sí está medido.

---

## D-039 · DocShadow-SD7K queda descartado por coste, y la calidad no se puede decidir sin las 50 fotos
**Fecha:** 2026-09-12 · **Estado:** ratificar
**Cierra la otra mitad de T2, y no como esperaba el plan**

§4.3 dice que las sombras son "el 80% del efecto percibido" y nombra DocShadow-SD7K.
Medido, no sirve — y el motivo no es la calidad sino la aritmética.

### El contrato

Entrada `image` `[batch, 3, height, width]`, espacial dinámica. Salida `result`
`[batch, 3, height, width]`: **una imagen del tamaño de la entrada**. Mismo patrón que
hizo inservible el export de imagen de UVDoc (D-037), y **10.612 nodos** frente a los 259
del grid de UVDoc.

### El coste, en CPU de sobremesa con cuatro hilos

| Entrada | Tiempo | RSS pico |
|---|---|---|
| cargar la sesión | 2.606 ms | 338 MB |
| 256×256 (0,07 MP) | 251 ms | 344 MB |
| 384×512 (0,20 MP) | 689 ms | 368 MB |
| 576×768 (0,44 MP) | 1.854 ms | 430 MB |
| 768×1024 (0,79 MP) | **3.566 ms** | 534 MB |

La app procesa 6,8 MP. Extrapolando: decenas de segundos aquí y **minutos** en un móvil,
más 120 MB de descarga. La cuantización no cierra un hueco de ese tamaño; reduce el peso
del modelo, no el número de operaciones.

### La idea que sí funciona, y que no basta

Quitar sombras es una corrección de **baja frecuencia**, igual que el fondo de D-029. Si
el modelo corre en pequeño y de ahí se saca un **campo de ganancia** —el cociente entre
salida y entrada— que se reescala y se aplica a resolución completa, el coste cae 5× y la
salida se parece a la directa: **27,0 dB** con análisis a 384×512, 697 ms frente a
3.597 ms.

Es buena arquitectura y está anotada para cualquier modelo de iluminación futuro. Pero
hereda la calidad del modelo, y ahí está el problema.

### Contra la línea base clásica

Página sintética 768×1024, PSNR contra el original sin sombra, dos modelos físicos de
sombra distintos:

| | multiplicativa | física (atenuación + ambiente aditivo + tinte) |
|---|---|---|
| sin tocar | 11,0 dB | 9,5 dB |
| **clásico (ya escrito)** | **25,7 dB** · 128 ms | **24,4 dB** · 124 ms |
| DocShadow directo | 17,0 dB · 3.445 ms | 18,5 dB · 3.165 ms |
| DocShadow campo de ganancia | 16,6 dB · 664 ms | 20,7 dB · 670 ms |
| ganancia + clásico encima | 20,5 dB · 792 ms | 23,0 dB · 794 ms |

El segundo escenario está construido a propósito para **romper** la suposición del método
clásico: la sombra no es multiplicativa, lleva luz ambiente aditiva, tinte azul y una
penumbra ancha, que es justo lo que dividir por el fondo no invierte. Aun así el clásico
gana por 5,9 dB a 1/25 del coste.

### Lo que esto NO demuestra

Honestidad sobre el límite de la prueba, porque es grande:

- **Las dos páginas son sintéticas.** DocShadow se entrenó con fotografías reales (SD7K).
  Un modelo puede puntuar mal con datos sintéticos y bien con reales.
- Mi página tiene papel blanco plano y texto negro puro: un objetivo irrealmente fácil
  para la división por el fondo.
- La métrica es PSNR contra un original limpio, que las 50 fotos reales **no tendrán**.
  El benchmark de verdad usa CER, como dice el plan.

Por eso la decisión se parte en dos:

**Decidido, y no se re-litiga:** DocShadow-SD7K no se envía. Es aritmética de arquitectura,
no de datos, y ningún matiz de sintético-contra-real la toca.

**Sin decidir, y bloqueado:** si alguna red de sombras merece los 120 MB. Eso solo lo
contestan las 50 fotografías reales medidas por CER (U-36). Es la primera vez que el set
de evaluación bloquea una decisión de ingeniería en vez de una afirmación de marketing.

**Consecuencia para §4.3 del plan:** la frase "DocShadow-SD7K → es el 80% del efecto
percibido" no se sostiene con lo medido y hay que reescribirla antes de que llegue al
formulario. Lo que sí se sostiene, y con números, es la otra mitad del párrafo: la
normalización clásica de iluminación es barata y buena.

---

## D-040 · `byrsa_restore` vuelve a ser Dart puro, y la etapa ONNX se va aparte
**Fecha:** 2026-09-13 · **Estado:** ratificar
**Misma forma que D-027, y esta vez bloqueaba un hito**

Al ir a construir el corredor del harness apareció el problema: `byrsa_restore` dependía
de Flutter, así que **un CLI de Dart puro no podía ejecutar el pipeline clásico** — la
línea base de M2, justamente lo que el harness existe para medir.

Al mirar qué lo ataba, la respuesta fue vergonzosamente pequeña: **un solo fichero**.
`uvdoc_stage.dart` importaba `onnxruntime`, que es un plugin de Flutter. Todo lo demás
—`ImageBuffer`, `ClassicalRestore`, el remapeo, `ModelCatalog`, `ModelStore`— solo usa
`crypto`, `meta` y `path`. Y `flutter`, `path_provider` y `plugin_platform_interface`
estaban en el pubspec **sin que nadie los importara**.

```
byrsa_restore        imagen, filtros, dewarp, catálogo   Dart puro · dart test · publicable
byrsa_restore_onnx   UvdocStage + onnxruntime            Flutter, y solo por eso
```

**Por qué importa más de lo que parece:** ONNX Runtime no llega solo. Trae Flutter, un
plugin nativo y —según D-037— una colisión de bibliotecas que únicamente falla en release.
Que todo eso viajara con el procesamiento de imagen era contagio, no diseño.

**Y el harness usa el mismo código que la app, no una reimplementación.** Una segunda
copia de la aritmética se separa de la primera y el número deja de describir el producto
en silencio. Es la razón entera por la que este paquete tiene que quedarse en Dart puro.

Resultado: 42 tests de `byrsa_restore` corren con `dart test`, tres dependencias sin usar
desaparecen, y el paquete pasa a ser publicable como `byrsa_ocr` tras D-027.

---

## D-041 · El harness ejecuta el pipeline, y hay un corpus sintético para poder hacerlo hoy
**Fecha:** 2026-09-13 · **Estado:** ratificar

El harness era **solo un puntuador**: consumía un `run.json` que debía producir un
dispositivo. No había forma de producir uno, así que el pipeline nunca se había ejecutado
sobre un corpus y M2 no tenía manera de medirse.

Ahora `harness run` ejecuta la restauración real sobre un dataset y escribe el run que
`score` lee. `harness synth` genera páginas con **original limpio conocido**.

**El corpus sintético no sustituye a las 50 fotos, y no puede.** Las capturas reales
tienen grano de papel, desenfoque de lente, ruido de sensor y luz que ninguna fórmula
reproduce, y la métrica de la serie real es CER, que necesita motor de OCR y glifos de
verdad. Los ficheros de verdad-terreno textual de las páginas sintéticas se dejan
**vacíos a propósito**: no se renderiza ninguna fuente, así que no hay texto que un OCR
pudiera recuperar, y rellenarlos sería un test imposible de aprobar honestamente.

Para lo que sirve es para lo que faltaba: que la tubería se ejecute hoy, que cada cambio
en la restauración tenga guardia numérica, y que cuando lleguen las fotografías la
herramienta ya esté depurada en vez de depurarse en el peor momento.

**Dos modelos de sombra, y el segundo por una razón medida.** Una sombra puramente
multiplicativa es justo lo que la división por el fondo invierte, así que medir solo
contra eso adula al pipeline clásico (D-039). El modelo físico añade luz ambiente aditiva
y tinte, que no invierte.

**Se registran los dos extremos del PSNR, no solo el final.** CLAHE aleja la imagen del
original limpio a propósito —oscurece el texto y blanquea el papel más de lo que la página
fue nunca—, así que cuesta PSNR mientras mejora la legibilidad. El número absoluto no
significa nada; la distancia recorrida sí.

### Primera línea base medida del proyecto

Seis páginas sintéticas de 1024×1400, en este portátil, con `harness run`:

| Filtro | PSNR entrada | PSNR salida | Ganancia | ms/página | KB/página |
|---|---|---|---|---|---|
| color | 8,1 dB | 17,5 dB | **+9,4** | 544 | 367 |
| gris | 8,1 dB | 17,7 dB | **+9,6** | 526 | 355 |
| blanco y negro | 8,1 dB | 17,7 dB | **+9,6** | 476 | **127** |

Blanco y negro da la misma ganancia en ficheros **tres veces más pequeños**. Es la
primera vez que el proyecto compara sus propios filtros con números en vez de con
intuición.

---

## D-042 · Quitar lo que sujeta la página: por objeto fuera de sitio, no por color de piel
**Fecha:** 2026-09-13 · **Estado:** ratificar
**Completa el tercer punto de §4.3, y se aparta de lo que proponía**

El plan dice: "Dedos en el borde → máscara HSV de piel + `cv.inpaint` (Telea)". No se hace
así, y el motivo no es técnico sino de a quién le funciona.

**Los umbrales de piel en HSV o YCbCr salen de datos mayoritariamente de piel clara.** Un
escáner construido sobre ellos funciona mejor para unos usuarios que para otros, en una
función que se dispara o no se dispara sobre la foto de la mano de alguien. Eso no es un
detalle de calidad, es el tipo de sesgo que no se arregla luego.

Así que la pregunta no es "¿esto es piel?" sino **"¿esto no es papel, y está agarrado al
borde del encuadre?"**:

1. Estimar el papel por un percentil alto del brillo de la página.
2. Marcar lo que **se aparta** del papel, en cualquier dirección.
3. Quedarse solo con lo conectado al borde de la imagen.
4. Quedarse solo con lo **grueso** — un dedo sobrevive a una erosión, una línea de texto no.
5. Descartar lo que toca dos bordes opuestos. Una mano entra por un lado; no cruza la página.

Es agnóstico al tono por construcción, y de paso caza cosas que un detector de piel no
vería: una mano con guante, un bolígrafo, el borde oscuro de la mesa.

**El punto 2 dice "se aparta", no "es más oscuro", y el test es quien lo enseñó.** La
primera versión buscaba más-oscuro-que-el-papel, y su propio test lo cazó: un pulgar
fotografiado con buena luz da unos 190 sobre papel de 242 y **no se detectaba**, mientras
que una mano más oscura se detectaba siempre. Es el mismo sesgo con otra ropa. La
distancia al papel no tiene esa preferencia.

**El punto 5 tampoco estaba, y lo destapó un falso positivo del 14%.** Al depurarlo
apareció algo más importante que la propia función: **la normalización de iluminación deja
un halo en un borde de sombra duro.** Dividir por un fondo construido con filtro de máximo
sobreestima en el lado oscuro de un escalón brusco, y sobrevive una raya oscura donde
estaba el borde. Esa raya es gruesa, se aparta del papel y toca el borde — pasaba las
cuatro primeras reglas. Lo que no hace es lo que hace una mano: recorre la página entera.

**Ese halo es un límite medido del método clásico y queda anotado como tal.** Es
exactamente donde una red de sombras podría ganarse los 120 MB que D-039 le negó, y
refuerza por qué esa decisión necesita las 50 fotos y no más síntesis.

**Se ejecuta después de la iluminación, no antes.** Sobre una captura cruda la estimación
del papel la arrastra la propia sombra.

**Y no se activa por defecto.** El fallo es destructivo y silencioso: un falso positivo
borra parte del documento de alguien. La etapa existe, está probada con 22 tests, y si se
enciende lo deciden las 50 fotografías — igual que D-039.

---

## D-043 · Una tesela plana sin ecualizar: medido, neutro, revertido
**Fecha:** 2026-09-13 · **Estado:** ratificar

Al perseguir el falso positivo de D-042 supuse que la culpa era de CLAHE amplificando el
grano en los márgenes vacíos, y añadí una mezcla hacia la identidad para las teselas sin
contraste.

**El harness dijo que no:** 17,5 dB antes y después, mismo tamaño de fichero, 13 ms más
lento. La hipótesis era falsa —el artefacto era el halo— y el código no compraba nada, así
que se revierte.

Queda anotado porque saber que algo no funciona vale lo mismo que saber que sí, y porque
si las 50 fotos enseñan moteado en márgenes en blanco, esto es lo primero que hay que
volver a probar. Es también el primer cambio que el harness ha rechazado, que era
justamente para lo que se construyó.

---

## D-044 · Los modelos de PaddleOCR son Apache-2.0, y el clasificador no es el que decíamos
**Fecha:** 2026-09-14 · **Estado:** ratificar

Los tres modelos PP-OCR llevaban `UNAUDITED` en `models.json` desde el 8 de septiembre.
Auditados con el método de `docs/model-licence-audit.md`, que se escribió precisamente
para esto y terminaba diciendo que esta auditoría seguía pendiente.

**Conclusión: Apache-2.0, los cuatro artefactos.** Y para `det` y `rec` no es una
inferencia: los model cards oficiales de PaddlePaddle en Hugging Face declaran
`license: apache-2.0` en su propio *front matter*, de modo que la concesión está atada a
los pesos. Es una posición mejor que la de DocShadow, donde MIT llegando a los pesos se
dedujo de la licencia del repositorio. La distinción se anota porque importa: una es una
cita y la otra es un razonamiento.

El `LICENSE` de PaddleOCR entró en el commit inicial `bc93c549f` (2020-05-08), anterior a
cualquier peso que hayan publicado. Se tocó dos veces desde entonces y **los dos diffs se
leyeron** en vez de suponerlos: ninguno cambió un término.

**Lo que no cierra, y se dice en vez de redondearlo.** Los datos de entrenamiento de
PP-OCRv5 no están publicados. El paper habla de 44M de muestras iniciales y 22,6M finales
sin nombrar un solo corpus. Nadie fuera de Baidu puede descartar una restricción heredada,
así que el paso 4 del método queda abierto y U-14 queda NARROWED, no cerrada.

**Y la auditoría contradijo al propio manifiesto.** Antes de leer nada en la web se midió
el artefacto, y `cls.onnx` resultó no ser de la misma generación que los otros dos: opset
11 contra 14, IR 6 contra 7, prefijo `p2o.` de paddle2onnx, 35 BatchNorm sin plegar donde
los otros tienen cero, y salida de **2 clases** cuando el clasificador propio de v5 es
PP-LCNet y da cuatro. `models.json` lo describía como "PP-OCRv5 orientation classifier" y
el fichero no sostiene esa frase. Que sea el heredado `ch_ppocr_mobile_v2.0_cls` es
inferencia, y se etiqueta como inferencia (U-38).

La licencia no cambia por ello —PaddleOCR es Apache-2.0 desde antes que cualquiera de sus
modelos— pero sí cambia el apoyo: `cls` no tiene model card que le ate una concesión, así
que descansa en la inferencia del repositorio, igual que DocShadow.

**Tres cosas más que salieron de medir antes de buscar:**

1. `mobile_ocr` descarga un cuarto artefacto obligatorio, `ppocrv5_dict.txt`, que este
   manifiesto no listaba. Se añade: `rec.onnx` no funciona sin él, y sus 18.385 clases de
   salida son exactamente las 18.383 entradas del diccionario más el blanco CTC más el
   espacio. La aritmética confirma que son pareja.
2. `ente-io/mobile_ocr` es MIT © 2025 Laurens Priem y **no contiene ni un `.onnx`** en su
   árbol: los binarios viven en `models.ente.io`, fuera de lo que esa licencia gobierna.
   Idéntico en estructura a `fabio-sim/DocShadow-ONNX-TensorRT`, y con la misma
   consecuencia: no aporta nada a los pesos.
3. PaddleOCR no tiene `NOTICE` en la raíz, y los artefactos no llevan dentro ningún aviso
   —ni `producer_name`, ni `metadata_props`, ni cadena de copyright—. Así que la
   obligación de Apache-2.0 se reduce a acompañar el texto de la licencia y atribuir a
   PaddleOCR. §4(b), §4(c) y §4(d) no se activan. Si algún día se cuantiza un modelo,
   §4(b) sí.

**Regla que se lleva el método:** medir el artefacto antes de investigarlo. Costó minutos
y encontró lo que ninguna cantidad de leer model cards habría encontrado, porque se habrían
leído los del modelo equivocado.

---

## D-045 · Un corpus sintético con texto de verdad, y por qué no sustituye a las fotos
**Fecha:** 2026-09-14 · **Estado:** ratificar

El corpus sintético que había (D-041) escribía ficheros de verdad-terreno **vacíos a
propósito**: dibujaba barras grises simulando renglones, no letras, así que permitía medir
PSNR pero no CER. El CER es la métrica principal del proyecto y nunca ha tenido un valor.

Ahora hay 50 documentos con **78.578 caracteres de texto exacto**, en ocho categorías y
seis idiomas, 25 dañados y 25 limpios.

**El renderizador es Python, no Dart, y la razón es medible.** Las fuentes bitmap que trae
`package:image` son sólo ASCII: pedirle `Ñandú, cigüeña, äöü — ¿cuánto? ¡Sí!` dibuja
` and , cig e a, cu nto? S !`. Una verdad-terreno con caracteres que el renderizador no
sabe dibujar produce un CER que culpa al OCR de un agujero del propio corpus. Pillow con
las tipografías Liberation cubre Latin-1 y Latin Extended-A, que es todo lo que necesitan
los seis idiomas. `tool/gen_font_metrics.py` ya había sentado el precedente de que una
herramienta de assets puede ser Python. El renderizador además **comprueba cada carácter
contra la fuente antes de escribir** y avisa de lo que no puede dibujar.

**Los 25 limpios no son relleno.** Son el guardia de regresión que no existía: hoy un
cambio que estropee una foto buena pasaría todos los tests del repositorio. Pasan igual por
desenfoque, ruido y JPEG, porque una foto limpia no es un escaneo.

**Las degradaciones modelan física, no ruido decorativo.** La sombra de mano lleva
atenuación *más* luz ambiente *más* tinte azul, deliberadamente no multiplicativa pura:
dividir por un fondo estimado invierte exactamente una sombra multiplicativa, que es el
sesgo que D-039 documentó. El dedo se dibuja en **seis tonos de piel muy distintos a
propósito**, porque D-042 quita intrusiones buscando un objeto fuera de sitio y
explícitamente no por color de piel — un detector que hubiera aprendido un tono debe fallar
aquí.

**Lo que este corpus NO hace, y está escrito en su README en grande.** No sustituye a las
50 fotografías. No tiene grano de papel, ni óptica, ni sensor, ni la luz de una habitación
real. **D-039 y D-042 siguen bloqueadas** esperando páginas reales medidas por CER, y la
solicitud no puede citar un CER de aquí como si viniera de capturas reales.

**Lo que sí desbloquea:** la verdad-terreno exacta es justo lo que las 50 fotos nunca
tendrán sin que alguien las transcriba a mano. Con esto el CER es medible automáticamente
en cada commit, en cuanto haya un móvil que ejecute el OCR (U-40).

**Y al puntuarlo salió un fallo de informe que había que arreglar.** La primera puntuación
dio **100,00% de CER en las ocho categorías**. No es un resultado: `harness run` no tiene
motor de OCR, así que toda hipótesis está vacía por diseño y una hipótesis vacía contra una
referencia real da exactamente 100% por aritmética. Publicado tal cual se habría leído como
una catástrofe medida en vez de como una medición que no ocurrió. Se aplica la misma regla
que `psnr` ya seguía —null en vez de infinito, porque «un infinito en un informe es un
error que parece un triunfo»—: un resultado que existe pero sin texto queda **sin medir**.
Un documento que la ejecución nunca produjo sigue contando como fallo completo, que es otra
cosa, y ambos casos tienen ahora su test.

Es reproducible: `content.json` más `tool/make_corpus.py` regeneran los mismos bytes.

---

## D-046 · La demo web existe, y encontró que `byrsa_restore` estaba mal en web
**Fecha:** 2026-09-14 · **Estado:** ratificar

La pregunta era si una demo web valdría lo mismo que el móvil, razonando que Dart y
Flutter deben funcionar igual en las dos plataformas. **No funcionan igual**, y la demo lo
demostró de la peor manera posible: reventando.

**Qué corre en navegador y qué no.** El pipeline entero de restauración —clásico, dewarp,
intrusiones, buffer— importa sólo `dart:math`, `dart:typed_data` y `package:meta`. Es
portable. Lo que no: la cámara (CameraX/AVFoundation), el motor de OCR (nativo en ambas
plataformas) y la etapa ONNX. Es decir, **el centro del pipeline sí, las dos puntas no** —
y las puntas son las que producen el CER.

Como `model_store.dart` necesita `dart:io` y su `install()` devuelve un `File`, no se puede
simular honestamente en web. Así que el paquete gana una segunda entrada,
`byrsa_restore_core.dart`, con todo lo portable. La división es por capacidad, no por
gusto.

**Y entonces apareció el fallo de verdad.** En la VM, `>>` sobre un entero negativo es un
desplazamiento aritmético; en dart2js el receptor se trata como un entero **sin signo de 32
bits**. `-1 >> 8` vale `-1` en una y `4294967295` en la otra.

Dos consecuencias, y la segunda es peor:

1. **El guardia no guardaba.** `math.max(0, position >> 8)` estaba escrito justo para
   atrapar el caso negativo. En web el valor ya llega positivo y enorme, así que el clamp
   no hace nada y el índice se sale del array: 2³⁵ sobre una lista de 48. Tres sitios.
2. **Las interpolaciones daban píxeles mal, en silencio.** Toda mezcla bilineal hacía
   `a + (((b - a) * weight) >> 8)`. Con `b < a` la diferencia es negativa, y en web ese
   desplazamiento producía un positivo gigante. Ni error ni aviso: resultado incorrecto.
   Siete sitios, uno de ellos en `intrusion.dart`.

**Arreglado sin ayudante y sin rama en el bucle caliente**: los guardias recortan antes de
desplazar, y las mezclas se reescriben como media ponderada `(a * (256 - w) + b * w) >> 8`,
que es algebraicamente idéntica para muestras no negativas y nunca resta.

**Verificado por checksum de los bytes restaurados en las dos plataformas**, tres tamaños y
los tres filtros: antes reventaba en los nueve casos, ahora salen idénticos byte por byte
en los nueve. `tool/check_web_parity.sh` es esa comparación con código de salida, y entra
en CI. Los tests de la VM no cambian, que es la otra mitad de la afirmación.

**Ninguno de los 200 tests podía encontrarlo.** Todos corren en la VM, donde el código
siempre estuvo bien. El fallo necesitaba una segunda plataforma para existir.

**La demo se construye sin CDN.** `--no-web-resources-cdn` sirve CanvasKit desde el mismo
origen en vez de `gstatic.com`: una página cuyo argumento es que nada sale de tu pestaña no
puede empezar pidiéndole siete megas a Google. Instrumentado en Chrome: **cero peticiones
externas**.

**Lo que la demo no hace, y se dice en la propia página:** no hay OCR. El reconocimiento es
código nativo, así que un navegador no tiene qué ejecutar. La página restaura y nada más.

**Respuesta a la pregunta que la originó:** la web y el móvil no demuestran lo mismo. La web
demuestra que la restauración es real y que funciona sin servidor, y la puede probar un
evaluador en treinta segundos sin instalar nada. El móvil demuestra que el conjunto
funciona y da el CER. Son complementarias, y hoy cada una encontró fallos que la otra no
podía ver.

---

## D-047 · El OCR corre en un teléfono, y las dos cosas que lo impedían
**Fecha:** 2026-09-14 · **Estado:** ratificar

El reconocimiento de texto nunca se había ejecutado. Hoy sí, y para llegar hubo que
arreglar dos fallos que **ningún test podía alcanzar**, porque los dos sólo existen
cuando hay un APK y un teléfono.

**Uno: `models.json` no viajaba dentro del APK.** `app/pubspec.yaml` lo declaraba como
`../models.json`, una ruta fuera del paquete. Flutter no empaqueta eso y no avisa. La
consecuencia no era una fila de ajustes vacía: el catálogo se lee por `rootBundle`, la
pantalla del documento pregunta al catálogo si el modelo de dewarp está instalado *antes*
de restaurar, y esa excepción abortaba el bucle — llevándose el OCR por delante, porque el
reconocimiento va después del realce **en el mismo bucle**. Una línea de un manifiesto, y
todo el camino restaurar-y-reconocer estaba muerto en hardware mientras 200 tests pasaban.

Arreglado con un enlace simbólico en `app/assets/models.json`, para que siga habiendo **un
solo manifiesto** y ninguna copia que se desvíe — que es lo que pedía el comentario
original, ahora con un mecanismo que funciona.

**Dos: un uso-después-de-liberar que mataba la aplicación entera.** Con el asset
arreglado, abrir una página tumbaba el proceso cada vez, sin excepción de Dart que capturar:

```
Fatal signal 11 (SIGSEGV), fault addr 0x20, tid io.worker.1
Cause: null pointer dereference — 5 marcos, todos en libflutter.so
```

`ImageIo.decode` liberaba el `ImageDescriptor` justo después de instanciar el códec y
**antes** de leer el fotograma. El descriptor posee los bytes codificados que el códec aún
no ha leído. El `ImmutableBuffer` no se liberaba nunca. Ahora se sueltan los dos juntos y
sólo cuando los píxeles ya están fuera.

**El resultado.** `whiteboard-01`, una de las páginas sin dañar del corpus, importada y
reconocida en un Mi 9T Pro:

| | |
|---|---|
| **CER** | **0,41%** — 1 error en 242 caracteres |
| WER | 5,41% |
| Cajas de palabra | 36 |

El único fallo es un espacio que falta en `-Añadir`. Todos los diacríticos sobrevivieron.

**Lo que este número es y lo que no.** Es una página sintética, renderizada de una fuente,
sin daño, en español: la entrada más fácil que este proyecto va a presentarle nunca a un
OCR. Se lee como «el camino funciona de extremo a extremo», no como una medida de calidad.
El CER sobre la mitad dañada del corpus, y sobre fotografías reales, sigue debiéndose.

Sí cierra o estrecha tres filas: la sesión ONNX abre en un dispositivo (U-34), el binding
FFI compilado para 1.15.1 corre contra el 1.27.0 que se envía (U-33, en debug), y la
métrica principal tiene por fin un valor (U-40).

**La lección que se lleva el proyecto.** Cuatro fallos han aparecido hoy en cuanto hubo
hardware o un segundo compilador: dos de geometría de cámara, uno de aritmética en web, y
estos dos. Ninguno era alcanzable desde los 200 tests, porque ninguno vive en la lógica que
los tests ejecutan. Eso no es un argumento contra los tests; es el argumento a favor de las
cincuenta fotografías y del hardware, hecho concreto y por cuadruplicado.
