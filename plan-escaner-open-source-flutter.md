# Byrsa — plan de desarrollo y solicitud Restack

**Un stack libre y modelos abiertos de captura, rectificación y OCR de documentos en el dispositivo, para Flutter (Android, iOS, Web y macOS) — sin dependencias de Google.**

Versión 4 · Octubre de 2026
Documento único: es a la vez el plan técnico actualizado con las mediciones del repositorio y la fuente de la solicitud a NLnet / Restack Fund.
**Deadline de la solicitud: 3 de noviembre de 2026, 12:00 CET.**

> **Qué cambia respecto a la v3.** Entre el 8 y el 20 de septiembre de 2026 se construyó el repositorio completo, se probó de extremo a extremo en un teléfono Android real (Xiaomi Mi 9T Pro) y en navegador (Chrome headless), y se registraron 56 decisiones de ingeniería (`DECISIONS.md`) y 232 tests automatizados. Esta versión incorpora todos los hallazgos medidos (`ESTADO.md`, `docs/measurements.md`), amplía el alcance a **Web** (sin servidor ni CDN, partiendo de `demo/`) y **macOS** (junto con la verificación de iOS mediante el Mac presupuestado), añade la **destilación y entrenamiento de modelos abiertos de escaneo** motivada por el precipicio de CER medido cuando se solapan dos defectos, y ajusta el presupuesto detallado dentro del tope de 50.000 € de Restack.

---

## 0.5 Estado medido del repositorio — septiembre de 2026

Esta sección la exige §0.3: nada se afirma sin medirlo, y si un número cambia al tocar el código, cambia aquí primero y se propaga al Anexo A. Detalle completo con fechas, máquinas y comandos en [`ESTADO.md`](ESTADO.md) y [`docs/measurements.md`](docs/measurements.md).

### Lo que ya existe y corre hoy

| Pieza | Líneas | Qué es | Estado actual |
|---|---|---|---|
| `byrsa_restore` | 2.011 | Restauración de imagen: iluminación, filtros, intrusiones, remapeo de grid | Dart puro · **publicable** · paridad byte a byte entre VM y Web (`tool/check_web_parity.sh`) |
| `dart_searchable_pdf` | 1.316 | Escritor de capa de texto invisible en PDF (render mode 3, `Tz` por palabra) | Dart puro · **publicable** · verificado con Poppler en Linux y con PDFs exportados desde móvil |
| `byrsa_capture` | 1.503 | Cámara, detección de bordes en vivo y corrección de perspectiva | Flutter · implementación propia sobre CameraX (Android) y AVFoundation (iOS, 977 líneas de Swift) |
| `byrsa_ocr` | 421 | API de OCR, modelo de páginas/palabras y reconstrucción de orden de lectura | Dart puro · **publicable** |
| `byrsa_ocr_mobile_ocr` | 339 | Motor nativo de OCR: Apple Vision (iOS) / PP-OCRv5 ONNX (Android) | Paquete puente no publicado para aislar la dependencia git de `mobile_ocr` (D-027) |
| `byrsa_restore_onnx` | 206 | `UvdocStage` sobre ONNX Runtime, separado para mantener puro `byrsa_restore` | Flutter · fijado a `uvdoc-grid-onnx` (Apache-2.0) |
| `app/` | 3.890 | **Byrsa**, aplicación de referencia (biblioteca, carpetas, SQLite FTS5, export) | GPLv3 · **48,8 MB** en APK release `arm64-v8a` con 0 clases ni servicios de Google Play Services |
| `harness/` | 1.382 | Generador sintético, ejecutor de corpus y puntuador de CER/WER/PSNR | Dart puro |
| `demo/` | 695 | Restauración interactiva en el navegador (`--no-web-resources-cdn`) | 304 ms en 1,4 MP en Chrome headless · **cero peticiones externas** |

**56 decisiones documentadas (`DECISIONS.md`) · 232 tests en verde · `flutter analyze` limpio · 100% REUSE/SPDX.**

### Correcciones al plan original forzadas por las mediciones

| Lo que asumía el plan inicial | Lo que demostró el código y las mediciones | Decisión |
|---|---|---|
| §4.1: "no lo reimplementes, forkea `doclens`" | `doclens` (incluso en 0.0.12) declara `play-services-mlkit-*` como dependencia Gradle **incondicional**, metiendo Play Services en cualquier APK. Además, `image_picker_android` inyectaba en silencio un `<service>` de `com.google.android.gms.metadata.ModuleDependencies` en `AndroidManifest.xml` sin dejar rastro en `classes.dex`. `byrsa_capture` se escribió desde cero sobre CameraX/AVFoundation y `tool/check_no_play_services.sh` inspecciona tanto el bytecode DEX como el manifiesto binario XML. | D-017 |
| §3: `opencv_dart` y `drift` en el stack | Ninguno de los dos entra: el pipeline clásico en Dart puro (con análisis submuestreado y pase entero fusionado, D-029) procesa 12 MP en **608 ms** en escritorio (92× más rápido que la primera versión) y corre idéntico en navegador sin arrastrar binarios C++; SQLite + FTS5 se escribe directo sobre `sqlite3` sin `build_runner` para proteger la build reproducible. | D-020, D-022, D-029 |
| §4.2: `PaddlePaddle/UVDoc_onnx` directo | El export que devuelve una imagen rectificada consume **477 MB de RSS pico** a 6,8 MP (OOM en gama media). Sustituido por `fredcallagan/uvdoc-grid-onnx` (Apache-2.0), que devuelve el grid `[1,2,45,31]` en **173 ms y 127 MB de RSS pico** independientemente de la resolución de salida, aplicando `remapThroughGrid` en Dart. | D-037 |
| §4.3: "DocShadow-SD7K ONNX es el 80% del efecto percibido" | **Descartado con números.** 120.041.674 bytes en fp32 y 10.612 nodos; a solo 0,79 MP cuesta **3.566 ms y 534 MB de RSS pico**, y el estimador clásico le gana por 5,9–8,7 dB a 1/25 del coste. | D-024, D-039 |
| Comportamiento del pipeline ante daños reales (CER en dispositivo) | En un Xiaomi Mi 9T Pro (Android 16, arm64), el CER es **1,00%** en 5 páginas limpias y **0,39%–2,56%** con un solo daño (movimiento, inclinación, reflejo, luz mixta), sube a **29,09%** en página curvada, y **se desploma a 42,85% y 63,90% cuando se solapan dos daños** (`hand-shadow + low-light` y `skewed + motion-blur`). Esto redefine T2: lo clásico basta para un defecto aislado, pero el solapamiento de defectos y la curvatura severa exigen **entrenar/destilar modelos abiertos compactos** que estimen campos de ganancia y grids de baja resolución. | D-048 |

---

## 0. Reglas cerradas — no se re-litigan

Estas cuatro reglas gobiernan todo el repositorio y la solicitud a NLnet.

### 0.1 Cero dependencias de Google (ni en código, ni en manifiesto, ni en CDN web)

El proyecto se presenta a Restack como infraestructura libre europea, alternativa soberana a Google ML Kit Document Scanner y Apple VisionKit. Un paquete que arrastre servicios propietarios de Google queda descalificado para F-Droid y para cualquier distribución independiente.

- **En Android:** cero referencias a `com.google.android.gms`, `com.google.mlkit`, `com.google.firebase` o `com.google.android.play` tanto en `classes*.dex` como en el `AndroidManifest.xml` compilado, verificado automáticamente por `tool/check_no_play_services.sh`.
- **En Web:** compilación con `--no-web-resources-cdn` para servir CanvasKit y todos los activos desde el mismo origen, con **cero peticiones externas**.
- **En modelos:** destilación y publicación de pesos abiertos bajo licencia **Apache-2.0** con scripts de entrenamiento reproducibles.

### 0.2 iOS y macOS: código escrito hoy, verificación y soporte macOS presupuestados

El desarrollo actual se realiza en Linux (CachyOS). Hoy no hay Mac, luego **no se afirma ninguna cifra ni compilación de iOS o macOS no medida**. Pero la arquitectura es multiplataforma desde el primer día:

- El lado nativo de Apple (`AVFoundation` y `Vision`, 977 líneas de Swift) está escrito y expuesto tras las mismas APIs Dart simétricas.
- **Prohibido afirmar resultados no medidos en iOS.** `tool/check_claims.sh` bloquea cualquier afirmación de rendimiento o paridad en iOS en los documentos del repositorio.
- Todo lo pendiente de verificar en hardware de Apple (o en las 50 fotografías reales) figura en [`UNVERIFIED.md`](UNVERIFIED.md) (54 filas, cada una con el comando exacto que la cierra).
- **El presupuesto de la solicitud incluye explícitamente un equipo Mac de compilación** para: (1) verificar y perfilar iOS, (2) llevar `byrsa_capture`, `byrsa_ocr` y la aplicación de referencia a **macOS**, y (3) validar el Plan B sobre Core ML si ONNX Runtime FFI en iOS presenta problemas de memoria o de revisión en App Store.

### 0.3 Este documento y `docs/measurements.md` son la fuente de verdad

Todo lo que se escribe en el Anexo A sale de mediciones reales registradas en `docs/measurements.md` o se declara explícitamente como tarea financiada / punto abierto en `UNVERIFIED.md`.

### 0.4 Punto de partida real: cadena completa funcionando en Android y demostrador en Web

A diferencia de una propuesta sobre papel, Byrsa llega a la convocatoria del 3 de noviembre con un repositorio público, 6 paquetes modulares, aplicación Android funcionando de extremo a extremo en hardware real, demostrador web sin servidor, banco de pruebas con CER medido y tres auditorías/parches enviados upstream (`docs/upstream/`). La subvención financia el salto de este prototipo verificado a un stack de producción completo en **Android, iOS, Web y macOS**, junto con el corpus de 50 fotografías reales y los **modelos abiertos compactos de escaneo**.

---

## 1. Por qué existe el hueco

Digitalizar documentos en papel desde el móvil, el navegador o el escritorio es una necesidad cotidiana (documentos de identidad, contratos, nóminas, facturas, informes médicos). Sin embargo, el ecosistema actual sufre tres fracturas estructurales:

1. **Dependencia de stacks propietarios cerrados.** La vía fácil para cualquier desarrollador móvil hoy es invocar Google ML Kit Document Scanner en Android o Apple VisionKit en iOS, o subir las imágenes a una API en la nube fuera de la UE. Ninguna de esas opciones es auditable, reutilizable en la web o compatible con F-Droid y sistemas des-googlizados.
2. **Cada escáner libre existente es un monolito aislado.** OSS Document Scanner está escrito en NativeScript; MakeACopy en Kotlin nativo; FairScan y Open Note Scanner son aplicaciones Android cerradas sobre sí mismas. Ninguno expone paquetes reutilizables para que otros desarrolladores construyan encima, y ninguno cubre conjuntamente **Android, iOS, Web y escritorio (macOS)**.
3. **El vacío de los modelos abiertos de restauración y rectificación para dispositivos reales.** Nuestras mediciones en el repositorio demuestran por qué ningún escáner libre ha resuelto aún las páginas curvas o con defectos combinados:
   - Los modelos académicos publicados como `DocShadow-SD7K` (120 MB en fp32, 10.612 nodos) devuelven una imagen a resolución completa y consumen **534 MB de RAM pico y 3.566 ms** en apenas 0,79 MP, provocando cierres por falta de memoria (OOM) en teléfonos de gama media.
   - Los métodos clásicos puros (como el implementado hoy en `byrsa_restore`) son rapidísimos (608 ms a 12 MP en escritorio, 304 ms en navegador) y logran un CER excelente en páginas limpias (**1,00%**) o con un solo defecto (**0,39%–2,56%**), pero **colapsan cuando el papel está curvado (29,09% CER) o cuando se solapan dos defectos como sombra de mano + baja luz o inclinación + desenfoque (42,85% y 63,90% CER)**.

El núcleo de Byrsa es cerrar esas tres fracturas a la vez:
- **Cuatro paquetes Dart/Flutter reutilizables (Apache-2.0)** y una aplicación de referencia (GPLv3) para **Android, iOS, Web y macOS**, con cero dependencias de Google.
- **Modelos abiertos compactos (Apache-2.0) y su corpus de entrenamiento/evaluación**, diseñados específicamente para predecir **grids de rectificación 2D y campos de ganancia de iluminación de baja frecuencia** (en lugar de bitmaps pesados a resolución completa), cerrando el precipicio de CER de los dos daños con menos de 150 MB de RAM pico.
- **Un escritor en Dart puro de capas de texto invisible para PDF (`dart_searchable_pdf`)**, con alineación exacta por palabra (`Tz`) y salida determinista byte a byte.

---

## 2. Los entregables y cómo se corresponden con la solicitud

Esta tabla mantiene sincronizados los paquetes del repositorio, las tareas del presupuesto (T1–T6) y los hitos de NLnet (M1–M6).

| Entregable | Tarea | Hito | Qué hace y en qué plataformas corre | Estado actual en el repo |
|---|---|---|---|---|
| `byrsa_capture` | T1 | M1 | Captura nativa (CameraX en Android, AVFoundation en iOS y macOS) y captura en navegador (Web), detección de bordes en vivo, corrección de perspectiva homográfica, ajuste manual de esquinas y modo por lotes. Cero Play Services. | Funcional en Android real; 977 líneas de Swift escritas para Apple; 39 tests en verde. Falta compilar/medir en iOS/macOS y completar el flujo de cámara Web. |
| `byrsa_restore` + `byrsa_restore_onnx` + **Modelos abiertos** | T2 | M3 | Pipeline clásico en Dart puro (iluminación, filtros, eliminación de intrusiones, paridad VM/Web) + **destilación y entrenamiento de modelos ONNX abiertos (Apache-2.0)** para segmentación de página, rectificación geométrica por grid y restauración ante múltiples defectos solapados. | Clásico publicado y verificado en móvil y Web; `UvdocStage` integrado con `uvdoc-grid-onnx` (173 ms, 127 MB RSS en escritorio). Falta entrenar/destilar los modelos ligeros propios para cerrar el precipicio del 29,09% / 42,85%–63,90% de CER. |
| `byrsa_ocr` (+ `byrsa_ocr_mobile_ocr`) | T3 | M5 | API unificada de OCR en dispositivo y reconstrucción de orden de lectura: PP-OCRv5 ONNX en Android y Web, Apple Vision en iOS y macOS. Descarga de modelos bajo demanda verificada con SHA-256. | Publicable en pub.dev (`byrsa_ocr`); OCR funcionando de extremo a extremo en Android real con diacríticos intactos (`0,41%–1,00%` CER en páginas limpias). Falta soporte Web/macOS y evaluación multilingüe completa. |
| `dart_searchable_pdf` | T4 | M4 | Escritor en Dart puro de capa de texto invisible en PDF (render mode 3, escalado horizontal `Tz` por palabra, WinAnsi/Unicode, bytes reproducibles). Corre en móvil, escritorio y Web. | Publicable en pub.dev; 34 tests incluyendo verificación con `pdftotext -layout` y bytes crudos exportados desde un teléfono real. Falta soporte de fuentes CJK/no-latinas embebidas y validación en Acrobat/Preview. |
| **Byrsa** (app de referencia) | T5 | M6 | Aplicación completa en **Android, iOS, Web (sin servidor ni CDN) y macOS**: biblioteca, carpetas, búsqueda SQLite FTS5, cifrado opcional (SQLCipher + AES-GCM), exportación PDF/JPEG/TXT, i18n, accesibilidad. | Funcional de extremo a extremo en Android (3.890 líneas) y demostrador de restauración en navegador (`demo/`, 695 líneas). Falta llevar la app completa a Web y macOS, cifrado en disco y pulido de producción. |
| Harness de evaluación y corpus | T6 | M2 + M6 | `harness/` + corpus público de **50 documentos reales** fotografiados (incluyendo ≥10 con dos defectos solapados) + corpus sintético reproducible + empaquetado F-Droid y builds reproducibles. | `harness/` operativo (1.382 líneas) con corpus sintético y puntuación en dispositivo (`score_device.dart`). Faltan las 50 fotografías reales y la telemetría de etapas en la app. |

---

## 3. Arquitectura

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Byrsa (aplicación de referencia — GPLv3)                                │
│  Android · iOS · Web (--no-web-resources-cdn) · macOS                    │
│  Flutter · Riverpod · Material 3 / Cupertino                             │
├──────────────────────────────────────────────────────────────────────────┤
│  Dominio y telemetría (Dart puro, testeable en CI sin emulador)          │
│  Scan · ScanPage · Folder · RestorePipeline · StageOutcome · ModelCatalog│
├─────────────────┬────────────────────┬───────────────┬───────────────────┤
│ byrsa_capture   │ byrsa_restore      │ byrsa_ocr     │dart_searchable_pdf│
│                 │ + byrsa_restore_   │ + byrsa_ocr_  │                   │
│ CameraX (And)   │   onnx             │   mobile_ocr  │ Escritor PDF en   │
│ AVFound. (iOS/  │ Clásico Dart puro  │ PP-OCRv5 ONNX │ Dart puro         │
│   macOS)        │ (VM + Web idéntico)│ (And + Web)   │ Render mode 3     │
│ Web MediaStream │ + Modelos abiertos │ Apple Vision  │ Escalado Tz exacto│
│ Cero Play Serv. │   ONNX (grid/gain) │ (iOS + macOS) │ Bytes determinist.│
├─────────────────┴────────────────────┴───────────────┴───────────────────┤
│  Almacenamiento local: SQLite + FTS5 (sin build_runner) · Archivos       │
│  Cifrado opcional: SQLCipher + AES-GCM                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### Decisiones de stack verificadas en el repositorio

| Capa | Elección actual | Licencia | Por qué (decisión registrada) |
|---|---|---|---|
| Estado | `flutter_riverpod` | MIT | Sin generación de código para no entorpecer builds reproducibles |
| Base de datos y FTS | `sqlite3` + `sqlite3_flutter_libs` (SQL directo + FTS5) | MIT | `drift` y `build_runner` se descartaron (D-022): FTS5 requiere SQL manual de todos modos |
| Captura | Propia en `byrsa_capture` (CameraX / AVFoundation / Web) | Apache-2.0 | `doclens` se descartó al auditar su Gradle y hallar `play-services-mlkit-*` incondicional (D-017; reportado en `doclens#20`) |
| Visión e iluminación | Dart puro en `byrsa_restore` | Apache-2.0 | `opencv_dart` se descartó para la ruta clásica (D-020): el pase entero fusionado en Dart puro tarda 608 ms a 12 MP y compila a JS/Wasm con paridad exacta de bytes |
| Inferencia neuronal | `onnxruntime` (FFI) / ONNX Runtime Web / Core ML (Plan B Apple) | MIT | En Android comparte determinísticamente `libonnxruntime.so` 1.27.0 con el motor de OCR, verificado en CI por `tool/check_native_collisions.sh` |
| Modelos de restauración | `uvdoc-grid-onnx` + **modelos abiertos propios (T2)** | Apache-2.0 | El export por grid (`[1,2,45,31]`) usa 127 MB de RSS frente a los 477 MB del export de imagen (D-037) y los 534 MB de DocShadow (D-039) |
| OCR | `byrsa_ocr` (Dart puro) + `byrsa_ocr_mobile_ocr` (`ente-io/mobile_ocr`) | Apache-2.0 / MIT | Separar interfaz y motor permite publicar `byrsa_ocr` en pub.dev hoy mientras la dependencia git queda aislada (D-027; reportado en `mobile_ocr#26`) |
| PDF buscable | `dart_searchable_pdf` (Dart puro, sin dependencias externas de PDF) | Apache-2.0 | Escritor propio con soporte WinAnsi, métricas Helvetica y escalado horizontal `Tz` por palabra |

**Licencia del proyecto:** **Apache-2.0** para todos los paquetes reutilizables y para los modelos abiertos entrenados; **GPLv3** para la aplicación de referencia Byrsa. `REUSE.toml` y cabeceras SPDX verificadas con `reuse lint` en cada commit.

---

## 4. Los ocho problemas técnicos duros (y lo que ya hemos medido en ellos)

### 4.1 Detección de bordes fluida y sistemas de coordenadas de cámara
Al descartar ML Kit y `doclens` por arrastrar Google Play Services (D-017), `byrsa_capture` implementa su propio detector de cuadriláteros en el hilo de análisis nativo de CameraX (Android) y AVFoundation (iOS/macOS), enviando a Dart únicamente las cuatro esquinas normalizadas.

**Lección medida en hardware real:** al probar la cámara en el Xiaomi Mi 9T Pro, los 194 tests en verde no impidieron dos fallos visuales graves: la textura de previsualización aparecía estirada y el contorno del documento salía girado 90°. Causa: `CaptureSession.analyse` rotaba las esquinas según `imageInfo.rotationDegrees` (espacio de pantalla), mientras que el `Preview` de CameraX entregaba el buffer en espacio del sensor (4:3). Se resolvió leyendo `SurfaceRequest.setTransformationInfoListener` en nativo y aplicando `RotatedBox` + `AspectRatio` (`contain`) compartido entre textura y overlay en Dart.

### 4.2 Rectificación de páginas curvas: por qué el export de grid cambia las reglas
`PaddlePaddle/UVDoc_onnx` devuelve un tensor de 3 canales del tamaño de la imagen de entrada: a 6,8 MP consume **487 ms y 477 MB de RSS pico**, matando por OOM un móvil de gama media. En cambio, el export de grid (`fredcallagan/uvdoc-grid-onnx`, Apache-2.0) recibe `[1,3,720,496]` y devuelve un grid de muestreo `[1,2,45,31]` en **173 ms y 127 MB de RSS pico** constantes, dejando que `remapThroughGrid` reconstruya la imagen a resolución completa en Dart siguiendo la convención `align_corners=True` de los autores originales (D-037).

**Frontera medida:** en el teléfono real, la página curvada del corpus (`book-page-02`, 3.335 caracteres) arroja un **CER del 29,09%**, frente al 0,39%–2,56% de cualquier otro defecto aislado. Además, descubrimos que la aplicación descartaba los `StageOutcome` devueltos por `RestorePipeline.run`, impidiendo distinguir en la base de datos si `UvdocStage` se ejecutó o se omitió (U-34). Persistir esa telemetría y mejorar el modelo de rectificación son parte central de T2 y T6.

### 4.3 El precipicio de los dos daños y el coste real de las redes de sombras
Tres problemas que los escáneres comerciales venden como uno:
- **Por qué se descartó DocShadow-SD7K ONNX (D-039):** pesa 120.041.674 bytes en fp32, tiene 10.612 nodos (frente a 259 del grid de UVDoc) y a solo 0,79 MP consume **3.566 ms y 534 MB de RSS pico**. Además, en nuestras pruebas con sombras sintéticas multiplicativas y físicas (con luz ambiente azulada y penumbra ancha), el estimador clásico en Dart puro le ganó por **5,9 a 8,7 dB de PSNR** en 124 ms (1/25 del tiempo).
- **Dónde falla lo clásico (el hallazgo del 14 de septiembre, D-048):** al pasar 11 páginas por el pipeline completo en el Xiaomi Mi 9T Pro, las 5 páginas sin daño dieron **1,00% de CER** y las 4 páginas con un único daño (desenfoque de movimiento, inclinación, reflejo, luz mixta) dieron entre **0,39% y 2,56% de CER**. Pero las 2 páginas con **dos daños simultáneos** (`hand-shadow + low-light` y `skewed + motion-blur`) se desplomaron a **42,85% y 63,90% de CER**.
- **La solución arquitectónica en T2:** el método clásico estima un único campo de color de papel y un juego de mapas locales; cuando dos distorsiones se solapan, corrige dos veces el campo equivocado. La solución no es una red imagen-a-imagen de 120 MB, sino **entrenar/destilar un modelo abierto ligero que prediga un campo de ganancia de iluminación de baja resolución** (a 384×512 el truco de campo de ganancia reduce el coste 5× manteniendo 27,0 dB, §docs/measurements.md) acoplado al grid geométrico.

### 4.4 OCR multiplataforma (Android, iOS, macOS y Web) y auditoría de modelos
Apple Vision en iOS y macOS; PP-OCRv5 en ONNX Runtime en Android y Web, detrás de la API en Dart puro de `byrsa_ocr`.
- **Aislamiento de dependencias git (D-027):** `ente-io/mobile_ocr` no está publicado en pub.dev y pub.dev prohíbe dependencias git. Separar `byrsa_ocr` (publicable hoy con cero avisos) de `byrsa_ocr_mobile_ocr` desbloqueó el hito sin hacer un fork privado.
- **Hallazgo en la auditoría de artefactos ONNX (`docs/measurements.md`, 14-sep):** al inspeccionar sin librerías externas las cabeceras protobuf de los tres modelos (`det.onnx`, `cls.onnx`, `rec.onnx`) y el diccionario `ppocrv5_dict.txt` (18.383 entradas + 2 tokens CTC = 18.385 clases de salida en `rec.onnx`), demostramos que `cls.onnx` (opset 11, 2 clases, BatchNorm sin plegar, espacio de nombres `p2o.`) no es un clasificador PP-OCRv5 de 4 ángulos sino un export heredado de `ch_ppocr_mobile_v2.0_cls`. Documentado y enviado upstream en `mobile_ocr#26`.

### 4.5 Capa de texto invisible en PDF y validación a nivel de bytes
`dart_searchable_pdf` dibuja cada palabra reconocida sobre su caja con **render mode 3** (invisible) y ajusta el ancho exacto mediante el operador `Tz` por palabra para que la selección y el copiar-pegar coincidan píxel a píxel con la imagen escaneada.

**Trampa descubierta al exportar desde el teléfono (16-sep):** los tests de ida y vuelta con `pdftotext -layout` pasaban, pero el título del PDF exportado en el móvil aparecía corrupto (`Importado\2402026\25509...`). `_winAnsiFromRune` mapeaba el espacio (`U+0020`) a `0xA0` (espacio de no separación) y el guion (`U+002D`) a `0xAD` (guion blando). Ningún test basado en Poppler lo detectaba porque **`pdftotext` normaliza ambos bytes a ASCII al extraer el texto**. Se corrigió la tabla WinAnsi y se añadieron tests que inspeccionan directamente los bytes generados del PDF.

### 4.6 ONNX en iOS/macOS y colisiones nativas en Android Release
- **En Android (resuelto y vigilado en CI):** al compilar el APK en modo *release* (en *debug* no falla), Gradle abortaba porque `mobile_ocr` empaqueta `libonnxruntime.so` 1.27.0 (28 MB en arm64) y `onnxruntime_flutter` empaqueta su propia copia 1.15.1 (14 MB). Usar `pickFirsts` reducía el APK en 13 MB pero emparejaba en silencio el shim JNI de 1.27.0 con la librería antigua de 1.15.1. Se resolvió excluyendo determinísticamente la copia del paquete FFI para que ambos usen la versión 1.27.0, y `tool/check_native_collisions.sh` verifica la cadena de versión dentro del `.so` en cada build release. Además se parcheó el `compileSdkVersion 33` roto de `onnxruntime_flutter` (enviado upstream en `onnxruntime_flutter#55`).
- **En iOS y macOS (riesgo abierto hasta disponer del Mac presupuestado):** ONNX Runtime vía FFI en iOS tiene techos estrictos de memoria por proceso. Cuando se adquiera el Mac mini del presupuesto, se medirá en hardware real; si ONNX FFI resulta inviable en iOS, el **Plan B** es convertir los modelos de rectificación/restauración a Core ML en iOS y macOS manteniendo la misma API Dart de `byrsa_restore`.

### 4.7 Medir sin engañarse: lo que 205 tests en verde no ven
Entre el 14 y el 16 de septiembre, llevar el código con más de 200 tests en verde a un teléfono Android real y a un segundo compilador (`dart2js` en Chrome headless) destapó **nueve fallos reales** inalcanzables desde los tests en la VM de Dart: desde el desplazamiento de bits con signo (`-1 >> 8` da `-1` en Dart VM pero `4294967295` en `dart2js`, rompiendo la interpolación bilineal en Web hasta que se blindó con `tool/check_web_parity.sh`) hasta un *use-after-free* nativo (`SIGSEGV`) en `ImageIo.decode` al liberar `ImageDescriptor` antes de decodificar el frame, o un script de evaluación que reutilizaba la ruta en `MediaStore` y medía cinco veces la primera página. Por eso el harness de evaluación (`harness/`) y las pruebas en dispositivos físicos y navegador real son entregables de primera clase.

### 4.8 La garantía de red verificable (móvil, escritorio y Web)
- **En Android, iOS y macOS:** los modelos ONNX (31,7 MB para UVDoc grid; 21,8 MB para PP-OCRv5) se descargan bajo demanda con consentimiento explícito del usuario desde URLs fijadas en `models.json` y se verifican con SHA-256 antes de guardarse en caché. Por tanto, el binario declara el permiso `INTERNET` y la garantía se formula siempre de forma exacta y verificable (vigilada por `tool/check_claims.sh`):
  > Ningún documento sale nunca del dispositivo. El único tráfico de red que la aplicación puede generar es una descarga de modelos que el usuario inicia explícitamente, desde una URL fijada y con verificación SHA-256.
- **En Web (`demo/` y la futura app Web de T5):** compilada con `--no-web-resources-cdn`, sirve todos sus recursos desde el propio origen sin tocar servidores de Google (`gstatic.com`) y procesa el documento íntegramente en la pestaña del navegador con **cero peticiones externas**.
- **Para F-Droid:** si la política de F-Droid etiqueta como * Anti-Feature* la descarga opcional de pesos abiertos, se publicará un *flavor* de build con los modelos compactos cuantizados ya empaquetados en el APK.

---

## 5. El harness de evaluación (`harness/`)

Es lo que convierte el proyecto en I+D verificable por terceros:

1. **Corpus sintético reproducible (ya construido):** genera páginas en varios idiomas europeos con tipografías Liberation (Latin-1 y Latin Extended-A) y aplica degradaciones controladas (sombra multiplicativa, sombra física con penumbra azulada, curvatura, inclinación, desenfoque, luz mixta y combinaciones adversarias de dos daños). Permite detectar regresiones en segundos desde CI.
2. **Corpus de 50 fotografías reales (entregable de M2):** 50 documentos reales fotografiados (recibos arrugados, facturas, páginas de libro curvadas, pizarras, documentos con sombra de mano). Siguiendo el hallazgo del 14 de septiembre (`harness/dataset/README.md`), **al menos 10 de las 50 fotografías deben combinar dos dificultades a la vez** (p. ej., sombra sobre página torcida o poca luz con intrusión de dedos), que es exactamente donde se mide el precipicio del método clásico. Los documentos con datos personales (DNI, facturas reales) se evalúan en privado y se publican como equivalentes sintéticos/anonimizados.
3. **Métricas y telemetría:** `harness` y `score_device.dart` reportan CER (Character Error Rate), WER, PSNR, tiempo por etapa (`StageOutcome`), memoria pico y tamaño de archivo. Se publican todos los resultados, incluidos los desfavorables.

---

## 6. Hitos (12 meses)

NLnet paga contra hitos verificables. Esta es la estructura alineada con T1–T6 y con el presupuesto del Anexo A:

| Hito | Tarea | Entregable verificable |
|---|---|---|
| **M1** | T1 | `byrsa_capture` publicado en pub.dev. Captura, detección de bordes en vivo, ajuste manual de esquinas y modo por lotes funcionando y medidos en Android, iOS y macOS (con el Mac presupuestado), más soporte de captura en navegador Web. Cero Google Play Services verificado en CI. |
| **M2** | T6 | Corpus público de 50 documentos reales (incluyendo ≥10 con dos defectos solapados) + `harness` con telemetría completa de `StageOutcome` en dispositivo. Línea base de CER, tiempo y RAM publicada en Android, iOS, macOS y Web. |
| **M3** | T2 | `byrsa_restore` y `byrsa_restore_onnx` publicados junto con la primera versión de los **modelos abiertos compactos de escaneo (Apache-2.0)** y sus scripts/datos de entrenamiento: rectificación geométrica por grid y restauración por campo de ganancia para cerrar el precipicio de CER en páginas curvas y con doble daño (<150 MB RAM pico). |
| **M4** | T4 | `dart_searchable_pdf` v1.0 en pub.dev con soporte completo Unicode/fuentes embebidas, alineación `Tz` por palabra y bytes reproducibles. Validado automáticamente en Poppler, Chrome y pdf.js, y verificado en Adobe Acrobat y macOS Preview. |
| **M5** | T3 | `byrsa_ocr` v1.0 en pub.dev con soporte unificado en Android (PP-OCRv5 ONNX), iOS y macOS (Apple Vision) y Web (ONNX Runtime Web). Cobertura y CER medidos sobre el corpus de 50 documentos en español, inglés, francés, alemán, italiano y portugués. |
| **M6** | T5 + T6 | Aplicación **Byrsa v1.0** en Android, iOS, Web (sin servidor ni CDN) y macOS: biblioteca, carpetas, búsqueda SQLite FTS5, cifrado opcional (SQLCipher + AES-GCM), i18n y accesibilidad. Build reproducible, 100% REUSE/SPDX, publicada en F-Droid, GitHub Releases, Web estática, Play y App Store, con informe final de evaluación. |

---

## 7. Alcance: dentro y fuera

**Dentro del año subvencionado:**
- Los cuatro paquetes Apache-2.0 (`byrsa_capture`, `byrsa_restore` + `byrsa_restore_onnx`, `byrsa_ocr`, `dart_searchable_pdf`).
- Aplicación de referencia **Byrsa** (GPLv3) en **Android, iOS, Web (cero servidor/CDN) y macOS**.
- **Entrenamiento y destilación de modelos abiertos compactos (Apache-2.0)** para detección de cuadrilátero/bordes, rectificación geométrica por grid 2D y restauración de iluminación/sombras ante defectos combinados, con scripts de entrenamiento reproducibles y dataset abierto.
- Captura multipágina y por lotes · perspectiva homográfica · filtros (color, gris, B/N) · OCR en dispositivo · PDF buscable · biblioteca · carpetas · búsqueda FTS5 · exportación PDF/JPEG/TXT · cifrado local con contraseña · i18n · accesibilidad · builds reproducibles.

**Fuera, backlog explícito para después del proyecto:**
- Firma criptográfica y relleno de formularios PDF · anotaciones a mano alzada · tarjetas de visita a contactos · lectura de códigos QR · exportación a DOCX/XLSX · sincronización WebDAV y subida directa a Paperless-ngx · resúmenes con LLM.

---

## 8. Modelos abiertos de escaneo y extensión a Web y macOS

Las mediciones de septiembre de 2026 demostraron dos hechos que definen la parte más innovadora de la propuesta:

1. **Por qué hacen falta modelos abiertos propios (Apache-2.0):**
   En el ecosistema libre actual, o bien se usan heurísticas clásicas puras (que en nuestro banco de pruebas logran 0,39%–2,56% de CER con un defecto pero saltan a **29,09% en páginas curvas** y a **42,85%–63,90% cuando se solapan dos defectos**), o bien se intentan empaquetar modelos académicos como `DocShadow-SD7K` (que a 0,79 MP exige **534 MB de RAM pico y 3,57 s**, inviable en un teléfono o en un navegador).
   Sin embargo, nuestros experimentos de arquitectura (§docs/measurements.md, 9 y 12 de septiembre) probaron que la salida de una red de escaneo **no debe ser una imagen a resolución completa**, sino un tensor geométrico o fotométrico de baja frecuencia:
   - Un **grid de deformación 2D** (como `[1,2,45,31]`) permite rectificar cualquier resolución de cámara en ~173 ms y 127 MB de RAM aplicando el remapeo bilineal en Dart (`remapThroughGrid`).
   - Un **campo de ganancia de iluminación** calculado a baja resolución (p. ej. 384×512) y aplicado en un único pase entero fusionado sobre la imagen original reduce por 5× el tiempo y la memoria respecto a una red imagen-a-imagen.

   Dentro de **T2**, se entrenarán y destilarán modelos abiertos compactos en formato ONNX (int8/fp16, publicados en HuggingFace y GitHub bajo **Apache-2.0** con todo el código de generación de datos sintéticos + aumentación fotométrica real y scripts de entrenamiento en PyTorch) para:
   - **Detección robusta de bordes/cuadrilátero y máscara de página** bajo sombras intensas o fondos con poco contraste (donde el detector de gradientes clásico duda).
   - **Rectificación geométrica (dewarping) y campo de ganancia conjunto** entrenado explícitamente sobre pares con **múltiples defectos solapados** (sombra de mano + inclinación, curvatura de lomo + iluminación desigual), atacando de raíz el precipicio de CER medido en D-048.

2. **Por qué Web y macOS multiplican el impacto con coste marginal bajo:**
   - **Web sin servidor (`demo/` → app completa):** gracias a mantener `byrsa_restore`, `byrsa_ocr` y `dart_searchable_pdf` en Dart puro (con paridad byte a byte entre la VM y `dart2js`/` dart2wasm` verificada en CI por `tool/check_web_parity.sh`), cualquier usuario u organización puede abrir una URL estática (o alojarla en su intranet) y escanear, restaurar, pasar OCR con ONNX Runtime Web y descargar un PDF buscable sin instalar nada y con **cero peticiones de red externas**.
   - **macOS e iOS:** la capa nativa en Swift (`AVFoundation` para cámara y `Vision` para OCR de sistema sin peso adicional en el binario) se comparte entre iOS y macOS. El Mac mini presupuestado desbloquea simultáneamente la verificación en iOS y la entrega en escritorio macOS.

---

## 9. Distribución y soberanía

**Verificación obligatoria de desarrollador de Google.** Desde septiembre de 2026 Google despliega progresivamente el bloqueo de instalación de APKs de desarrolladores no registrados en dispositivos Android certificados, incluso fuera de Google Play.
- El presupuesto incluye el registro en Android Developer Console (~25 USD) y en Apple Developer Program (99 EUR/año) además de la distribución libre prioritaria en **F-Droid**, **IzzyOnDroid**, **GitHub Releases**, **Accrescent** y el **despliegue Web estático autoalojable**.
- Los paquetes Dart se publican en **pub.dev** bajo Apache-2.0 (`dart pub publish --dry-run` ya corre en CI con 0 warnings para `byrsa_restore`, `byrsa_ocr` y `dart_searchable_pdf`).
- Los modelos abiertos entrenados y el corpus de 50 documentos se publican bajo licencia abierta (Apache-2.0 / CC-BY-4.0) con hashes SHA-256 fijados en `models.json`.

---

## 10. Sostenibilidad después de la ayuda

Opciones honestas y compatibles con el software libre una vez completados los 12 meses:

- **Aplicación de pago único en Google Play y App Store** (3–6 € por conveniencia de instalación y actualizaciones automáticas), siendo **100% gratuita y reproducible en F-Droid, GitHub Releases y Web**. Es el modelo probado por proyectos libres como KeePassDX, Organic Maps o Syncthing-Fork.
- **Contratos de integración y soporte** sobre los cuatro paquetes Apache-2.0 para empresas europeas que necesiten escaneo y OCR en el dispositivo sin enviar documentos a nubes de terceros ni depender de Google Play Services.
- **GitHub Sponsors / Open Collective** y elegibilidad para rondas de continuación de NLnet / NGI (hasta 2030) para funcionalidades del backlog (sincronización nativa con Paperless-ngx y Nextcloud, firma criptográfica de PDFs).

---

## 11. Riesgos y mitigaciones

| Riesgo | Estado / Prob. | Impacto | Mitigación (medida o presupuestada) |
|---|---|---|---|
| **Sin Mac hoy, iOS y macOS no están medidos antes del envío** | **Abierto (declarado)** | **Alto** | Código Swift escrito (977 líneas), APIs Dart simétricas, 54 ítems trazados en `UNVERIFIED.md`, y **Mac mini presupuestado en Expenses (750 €)** para compilar y medir desde el mes 1. |
| **ONNX Runtime en iOS falla por techo de memoria o revisión** | Media | Alto | **Plan B listo por diseño:** convertir los modelos abiertos a Core ML en iOS/macOS detrás de la misma interfaz Dart de `byrsa_restore`. |
| **Colisión de `libonnxruntime.so` en Android release** | **Cerrado (D-037)** | Alto | Resuelto excluyendo la copia de `onnxruntime_flutter` y fijando la 1.27.0; vigilado en CI por `tool/check_native_collisions.sh`. |
| **Inyección oculta de Play Services por plugins transitivos** | **Cerrado (D-017)** | Alto | `tool/check_no_play_services.sh` inspecciona tanto `classes*.dex` como `AndroidManifest.xml` (cazó el servicio oculto de `image_picker_android`). |
| **Tamaño de app > 150 MB** | **Cerrado (D-026)** | Medio | Medido: **48,8 MB** en `arm64-v8a` release con splits por ABI antes de descargar modelos. |
| **Precipicio de CER (42,85%–63,90%) cuando se solapan dos daños** | **Medido (D-048)** | Alto | Capturar ≥10 fotos reales con doble defecto en M2 y entrenar/destilar en T2 modelos compactos de campo de ganancia + grid sobre pares con defectos combinados. |
| **Divergencia numérica entre Dart VM y compilador Web (`dart2js`/`wasm`)** | **Cerrado en clásico** | Medio | Cazado el bug de `>>` sobre negativos en `dart2js`; `tool/check_web_parity.sh` exige identidad byte a byte entre VM y Web en cada commit. |
| **F-Droid etiqueta la descarga opcional de modelos** | Media | Medio | Si F-Droid objeta la descarga bajo demanda verificada con SHA-256, se publica un *flavor* de F-Droid con los modelos compactos cuantizados incluidos en el APK. |

---

## 12. Lo construido en septiembre y lista de cierre antes del 3 de noviembre

Todo el trabajo técnico previsto originalmente para las semanas S1–S6 se ejecutó de forma intensiva en septiembre de 2026:

1. **Hecho y verificado en el repositorio:**
   - Repositorio estructurado con los 6 paquetes (`byrsa_capture`, `byrsa_restore`, `byrsa_restore_onnx`, `byrsa_ocr`, `byrsa_ocr_mobile_ocr`, `dart_searchable_pdf`), `app/`, `harness/` y `demo/`.
   - 232 tests en verde, 100% REUSE/SPDX (`reuse lint`), 3 guardias en CI (`check_claims.sh`, `check_web_parity.sh`, `check_no_play_services.sh`).
   - Cadena completa verificada en un Xiaomi Mi 9T Pro (Android 16, arm64) y demostrador Web medido en Chrome headless con cero peticiones externas.
   - Tres issues/parches técnicos publicados upstream el 14 de septiembre: [`govindmaheshwari2/doclens#20`](https://github.com/govindmaheshwari2/doclens/issues/20), [`ente-io/mobile_ocr#26`](https://github.com/ente-io/mobile_ocr/issues/26) y [`gtbluesky/onnxruntime_flutter#55`](https://github.com/gtbluesky/onnxruntime_flutter/issues/55) (`docs/upstream/`).
2. **Checklist final para el envío en `nlnet.nl/propose` (antes del 3 de noviembre de 2026, 12:00 CET):**
   - Copiar cada bloque del **Anexo A** en el formulario de Restack (todos los bloques están ya por debajo del límite estricto de caracteres de NLnet).
   - Completar los datos personales de contacto (email, teléfono, huella PGP) y los enlaces a proyectos previos en *What makes you the right person?*.

---

## 13. Los seis puntos fuertes que sostienen la solicitud

1. **Evidencia empírica antes de pedir un euro:** la propuesta no promete que "hará un escáner"; presenta un repositorio con 232 tests, APK de 48,8 MB sin Play Services, PDFs buscables verificados byte a byte desde un móvil real y un demostrador Web funcionando sin servidor.
2. **Honestidad radical en las mediciones (`tool/check_claims.sh`):** se declara abiertamente que iOS/macOS no están medidos por desarrollar en Linux (54 ítems con su comando en `UNVERIFIED.md`) y que el CER es sobre el corpus sintético mientras se fotografían las 50 páginas reales.
3. **El hallazgo del precipicio de los dos daños (0,39%–2,56% → 42,85%–63,90% CER):** justifica con números propios por qué hace falta I+D en modelos abiertos compactos de restauración/rectificación en lugar de quedarse solo con filtros clásicos o con redes académicas de 120 MB que matan el teléfono por memoria.
4. **Los nueve fallos reales que 205 tests en verde no vieron:** demuestra experiencia real de ingeniería móvil y multi-compilador (`dart2js` vs VM, `SIGSEGV` en `ImageDescriptor`, coordenadas de `SurfaceRequest` en CameraX, manifest merger de Gradle).
5. **Contribuciones upstream reales ya enviadas (`doclens#20`, `mobile_ocr#26`, `onnxruntime_flutter#55`):** demuestra que el proyecto audita y mejora el ecosistema libre existente desde el primer día.
6. **Presupuesto contenido y trazable (36.872 €):** 1.320 horas a una tarifa modesta de recuperación de costes de 25 €/h (33.000 €) más 3.872 € en hardware de compilación/pruebas (Mac mini, iPad, iPhone y móviles Android) y cómputo GPU para entrenar los modelos abiertos.

---

# Anexo A — Borrador de la solicitud

Formulario: `nlnet.nl/propose` · Fondo: **Restack** · Deadline: **3 nov 2026, 12:00 CET**

Todos los bloques delimitados por triple acento grave (```` ``` ````) respetan estrictamente los límites máximos de caracteres del formulario de NLnet.

## Proposal title

```
Byrsa: an open on-device document scanning, restoration and OCR stack for Flutter
```

## Project website(s) / repositories

```
https://github.com/dgmtnz/byrsa
```

## Summary (max. 1000 characters)

```
Scanning documents is an everyday need, yet apps still rely on proprietary stacks like Google ML Kit and Apple Vision, while existing FOSS scanners are single-app monoliths whose code cannot be reused.

Byrsa is a sovereign open-source alternative built as four Apache-2.0 Dart/Flutter packages plus a GPLv3 reference app across Android, iOS/iPadOS, Web and macOS:
1. byrsa_capture: CameraX, AVFoundation and Web capture with live quad detection and zero Google Play Services.
2. byrsa_restore: pure-Dart restoration plus compact Apache-2.0 ONNX models for page dewarping and multi-defect restoration.
3. byrsa_ocr: unified on-device OCR (PP-OCRv5 ONNX and Apple Vision) with reading-order recovery.
4. dart_searchable_pdf: pure-Dart writer for PDF invisible text layers (render mode 3).

No document ever leaves the device or browser: the only network call is an explicit SHA-256-verified model download.
```

## How much money do you request?

```
36872 EUR
```

## Budget breakdown (max. 4000 characters)

```
I apply as an individual developer in Spain to work on Byrsa over 12 months. A prototype with 232 automated tests already runs end to end on Android hardware and in the browser; this grant brings the four packages, open scanning models and reference app to production on Android, iOS/iPadOS, Web and macOS.

RATE
25 EUR/hour for all engineering and research work (modest cost-recovery rate for an independent developer in Spain, covering self-employment taxes and social security).

TASKS
- T1: Cross-platform capture pipeline (byrsa_capture, Apache-2.0) - 210 h = 5,250 EUR. CameraX (Android), AVFoundation (iOS, iPadOS, macOS) and browser MediaStream (Web) with zero Google Play Services: live quad detection, homography perspective correction, manual corner edit, auto-shutter and batch capture. Includes iOS/iPadOS/macOS verification on the budgeted Mac and test devices.
- T2: Restoration engine and compact open scanning models (byrsa_restore + byrsa_restore_onnx, Apache-2.0) - 340 h = 8,500 EUR. Pure-Dart classical illumination, CLAHE and finger-intrusion pipeline (byte-identical on Dart VM and Web) plus training and distilling compact Apache-2.0 ONNX models for page segmentation, 2D grid dewarping and low-resolution illumination gain fields. Targets our measured CER cliff where classical restoration scores 0.39%-2.56% CER on single defects but jumps to 29.09% on curved pages and 42.85%-63.90% when two defects overlap (hand shadow + low light), staying under 150 MB peak RAM on mid-range phones and WebAssembly. Includes reproducible PyTorch training scripts and open training data.
- T3: Unified on-device OCR (byrsa_ocr, Apache-2.0) - 180 h = 4,500 EUR. Pure-Dart OCR API and reading-order recovery backed by PP-OCRv5 ONNX on Android and Web (ONNX Runtime Web) and Apple Vision on iOS, iPadOS and macOS. Explicit SHA-256-verified model downloads, provenance auditing and CER evaluation for ES, EN, FR, DE, IT and PT.
- T4: Pure-Dart searchable PDF writer (dart_searchable_pdf, Apache-2.0) - 160 h = 4,000 EUR. PDF invisible text layers (render mode 3) with exact per-word horizontal scaling (Tz), Unicode/font subsetting for European scripts, and deterministic byte output across mobile, tablet, desktop and Web. Validated in Poppler, Chrome, pdf.js, Acrobat and macOS Preview.
- T5: Reference app for Android, iOS/iPadOS, Web and macOS (Byrsa, GPLv3) - 270 h = 6,750 EUR. Production app on phones, tablets, macOS and static Web (--no-web-resources-cdn, zero external requests): library, folders, SQLite FTS5 search, optional SQLCipher + AES-GCM encryption, batch export (PDF/JPEG/TXT), localisation and accessibility.
- T6: Evaluation harness, 50-document benchmark and release - 160 h = 4,000 EUR. Public benchmark of 50 photographed documents (>=10 overlapping-defect pages), synthetic generator, StageOutcome telemetry, reproducible builds, REUSE/SPDX compliance and packaging for F-Droid, pub.dev, GitHub Releases, Play and App Store.

Subtotal labour: 1,320 hours x 25 EUR/h = 33,000 EUR

EXPENSES
- Mac mini M4 for iOS, iPadOS and macOS builds, Core ML fallback and Preview validation: 750 EUR
- Test devices (iPad, iPhone and two Android phones for memory, thermal and camera profiling): 1,550 EUR
- Cloud GPU compute for training and distilling the Apache-2.0 dewarping and restoration models: 1,450 EUR
- Apple Developer Program (99 EUR/yr) + Android Developer Console (23 EUR): 122 EUR
Subtotal expenses: 3,872 EUR

Total requested: 36,872 EUR
```

## Comparison with other efforts (max. 4000 characters)

```
PROPRIETARY BASELINES AND EXISTING FOSS SCANNERS

On mobile, most apps delegate scanning to Google ML Kit Document Scanner or Apple VisionKit. Both are closed, OS-locked, unavailable on the Web, and on Android require Google Play Services, ruling out F-Droid and de-Googled devices.

Among free apps, four are relevant:
- OSS Document Scanner (Akylas): NativeScript for Android and iOS, with Tesseract OCR and searchable PDF export. No neural dewarping or multi-defect shadow restoration, and no Web or desktop support.
- MakeACopy: native Kotlin (Android-only). Runs PaddleOCR via ONNX offline, writes searchable PDFs and indexes with SQLite FTS5, but cannot run on iOS, Web or macOS, nor be used as a library.
- FairScan and Open Note Scanner: Android-only apps focused on basic capture and perspective crop.

WHAT IS DIFFERENT HERE

1. Modular architecture and platform reach. Existing FOSS scanners are single-app monoliths in incompatible stacks (NativeScript, Kotlin, Java), so every new project starts from scratch. Byrsa delivers four independent Apache-2.0 Dart/Flutter packages (byrsa_capture, byrsa_restore, byrsa_ocr, dart_searchable_pdf) plus a GPLv3 reference app across Android, iOS/iPadOS, Web (client-side, zero external requests) and macOS. A developer who only needs searchable PDFs in a Dart server, Flutter app or browser tab imports dart_searchable_pdf alone.

2. Open-weights restoration models built for real device limits. No free scanner solves curved book pages or overlapping lighting defects. In our measurements, academic shadow networks like DocShadow-SD7K (120 MB fp32, 10,612 nodes) take 3,566 ms and 534 MB peak RSS at 0.79 MP--an out-of-memory kill on mid-range phones. Conversely, our pure-Dart classical pipeline runs in 608 ms at 12 MP on desktop and scores 1.00% CER on clean pages and 0.39%-2.56% CER on single defects on a Xiaomi Mi 9T Pro, but jumps to 29.09% CER on curved pages and 42.85%-63.90% CER when two defects overlap (hand shadow + low light, skew + motion blur). Byrsa pairs fast pure-Dart restoration with compact Apache-2.0 ONNX models that output low-resolution 2D dewarping grids (uvdoc-grid-onnx runs in 173 ms and 127 MB RSS) and illumination gain fields rather than full-size bitmaps.

3. Pure-Dart searchable PDF writer (dart_searchable_pdf) with exact per-word Tz width matching and deterministic byte output, which did not exist in Dart.

UPSTREAM CONTRIBUTIONS ALREADY FILED (docs/upstream/)

Adding dewarping inside MakeACopy (Kotlin) or OSS Document Scanner (NativeScript) cannot produce reusable Flutter/Dart packages or a browser engine. Where upstream patches help the wider ecosystem, I have already filed them during our September 2026 spikes:
1. govindmaheshwari2/doclens#20: audited its Gradle build, found unconditional com.google.android.gms:play-services-mlkit-* dependencies that inject Play Services into every APK, wrote byrsa_capture directly on CameraX/AVFoundation, and filed the upstream issue and modularisation patch.
2. ente-io/mobile_ocr#26: audited the ONNX protobuf headers of its bundled PP-OCR models, proving rec.onnx matches ppocrv5_dict.txt (18,385 classes) while cls.onnx is an older opset-11 2-class export, and isolated its git dependency so byrsa_ocr is publishable on pub.dev today.
3. gtbluesky/onnxruntime_flutter#55: documented and patched the compileSdkVersion 33 release build failure and native libonnxruntime.so collision.
```

## Technical challenges (max. 4000 characters)

```
1. iOS/iPadOS/macOS hardware gap and native ONNX collisions. I develop on Linux, so while 977 lines of Swift/AVFoundation/Vision code are written behind symmetric Dart APIs, zero iOS or macOS runtime numbers exist yet (tool/check_claims.sh enforces this in CI, and UNVERIFIED.md lists all 54 verification commands). The budgeted Mac mini and iPad/iPhone close this gap. On Android, combining mobile_ocr (onnxruntime-android 1.27.0, 28 MB) and onnxruntime_flutter (1.15.1, 14 MB) caused a release-only duplicate libonnxruntime.so failure; Gradle pickFirsts shrank the APK by 13 MB by pairing the 1.27.0 JNI shim with the 1.15.1 library. We resolved it deterministically and enforce 1.27.0 via tool/check_native_collisions.sh. Fallback on Apple platforms if ONNX FFI hits memory/review limits: Core ML behind the same Dart API.

2. Model size, provenance and network guarantees. Shipping 50+ MB of weights inside the binary hurts adoption, so models are fetched only on explicit user action from pinned URLs with SHA-256 verification (with a bundled-weights flavour if F-Droid flags runtime downloads). On the Web, --no-web-resources-cdn bundles CanvasKit locally with zero external requests.

3. Dewarping memory ceilings vs. curved-page accuracy. PaddlePaddle/UVDoc_onnx outputs a full-resolution 3-channel image and takes 487 ms and 477 MB peak RSS at 6.8 MP (OOM on mid-range phones). Switching to uvdoc-grid-onnx ([1,2,45,31] sampling grid) cut cost to 173 ms and 127 MB RSS at any resolution, but on our Xiaomi Mi 9T Pro a curved book page still scores 29.09% CER, motivating distillation of a sharper grid model in T2.

4. Invisible text layer alignment and byte-level PDF validity. Matching selection width to scanned glyphs requires per-word Tz scaling. On a real phone export, we also found _winAnsiFromRune mapped U+0020 and U+002D to 0xA0/0xAD; Poppler's pdftotext normalises both back to ASCII on extraction, hiding the bug until we asserted raw PDF bytes.

5. Real-time capture coordinate spaces. Keeping quad detection in native CameraX/AVFoundation avoids Dart frame-streaming overhead, but on the Mi 9T Pro the preview stretched and the quad overlay rotated 90 degrees because Preview stayed in 4:3 sensor space while ImageAnalysis rotated corners to display space. Fixed via SurfaceRequest.setTransformationInfoListener.

6. Honest benchmarking. Claims are gated by our 50-document corpus and harness/. Sensitive personal documents are evaluated privately and published as synthetic equivalents.

7. Three findings from our codebase that 205 green unit tests could not see:
- Two-defect CER cliff: on the Mi 9T Pro, our classical pipeline scores 1.00% CER on clean pages and 0.39%-2.56% on single defects, but jumps to 42.85% and 63.90% when two defects overlap (hand-shadow + low-light, skewed + motion-blur), while DocShadow-SD7K ONNX takes 3,566 ms and 534 MB RSS at 0.79 MP--proving T2 must distil compact gain-field (27.0 dB at 5x lower cost) and grid networks rather than image-to-image models.
- Nine end-to-end bugs only appeared on hardware or a second compiler: dart2js treating >> on negative ints as unsigned (-1 >> 8 == 4294967295, breaking browser interpolation until locked by check_web_parity.sh), ../models.json omitted from the APK, a native SIGSEGV use-after-free in ImageIo.decode, dropped PDF word boxes, MediaStore path reuse in ocr_on_device.sh, and discarded StageOutcome telemetry.
- check_no_play_services.sh caught image_picker_android injecting com.google.android.gms.metadata.ModuleDependencies into AndroidManifest.xml with zero classes.dex references.
```

## Ecosystem (max. 2000 characters)

```
BUILDING BLOCKS AND UPSTREAM CONTRIBUTIONS
Byrsa builds on CameraX, AVFoundation, Apple Vision, SQLite FTS5 (sqlite3 without codegen for reproducible builds), ONNX Runtime, uvdoc-grid-onnx (Apache-2.0) and PP-OCRv5. Where existing Flutter plugins had blockers, I audited them and filed upstream patches (docs/upstream/): govindmaheshwari2/doclens#20 (removing unconditional Play Services dependencies), ente-io/mobile_ocr#26 (ONNX protobuf provenance audit of cls.onnx/rec.onnx and pub.dev readiness), and gtbluesky/onnxruntime_flutter#55 (Android SDK 34 release build fix). All four Byrsa packages (byrsa_capture, byrsa_restore, byrsa_ocr, dart_searchable_pdf) and our distilled scanning models and training scripts are Apache-2.0; the reference app is GPLv3.

USERS AND COMMUNITIES
1. End users across Android, iOS/iPadOS, Web and macOS who scan identity documents, contracts, receipts or medical records and need a sovereign European alternative that never uploads documents to clouds or requires Google Play Services.
2. Self-hosters (Paperless-ngx, Nextcloud): a mobile, tablet, desktop and zero-server Web scanner producing standards-compliant searchable PDFs with clean reading order.
3. Dart and Flutter developers needing camera quad capture, pure-Dart image restoration, on-device OCR or searchable PDF generation without proprietary SDKs.

DISTRIBUTION
Packages published on pub.dev (dart pub publish --dry-run already passes with zero warnings for our pure-Dart packages). Open model weights, synthetic generator and the 50-document benchmark published on HuggingFace and GitHub with SHA-256 manifests. App distributed via F-Droid, IzzyOnDroid, GitHub Releases, static Web bundle, Google Play and App Store.
```

## What makes you the right person? (max. 2000 characters)

Este campo combina tu experiencia profesional previa en Android (OS y apps) con la evidencia verificable de lo que ya has construido y medido en este repositorio:

```
I work professionally as a software developer in Spain and have extensive prior experience with Android--both at the operating-system level (AOSP/ROMs, native libraries, Gradle/JNI build chains and Play-Services-free environments) and in building production Android and cross-platform Flutter applications.

For Byrsa specifically, I did not wait for funding to test whether the hard parts work. In September 2026 I built the complete modular workspace (byrsa_capture, byrsa_restore, byrsa_restore_onnx, byrsa_ocr, byrsa_ocr_mobile_ocr, dart_searchable_pdf, the Byrsa reference app, harness/ and the browser demo/--over 11,700 lines of code, 56 documented engineering decisions in DECISIONS.md, and 232 automated tests):
- Built a Play-Services-free APK (48.8 MB arm64 release) verified end to end on a Xiaomi Mi 9T Pro (Android 16): camera preview, quad overlay, restoration, PP-OCRv5 recognition and searchable PDF export verified byte-for-byte with Poppler.
- Optimised the pure-Dart classical restoration pipeline 92x (from 55.9 s to 608 ms on a 12 MP page), fixed unsigned bit-shift divergences in dart2js, and shipped a zero-request browser demo (304 ms on 1.4 MP) guarded by tool/check_web_parity.sh.
- Benchmarked UVDoc (cutting peak RSS from 477 MB to 127 MB via grid export) and DocShadow-SD7K (proving why its 534 MB RSS at 0.79 MP requires a gain-field distillation approach), and measured the two-defect CER cliff (1.00% clean -> 42.85%-63.90% on overlapping defects).
- Filed three upstream audits/patches (doclens#20, mobile_ocr#26, onnxruntime_flutter#55) and enforced claims, manifest and native-library discipline in CI (check_claims.sh, check_no_play_services.sh, check_native_collisions.sh).
```

## Other funding sources (max. 1000 characters)

```
None. This project has no other funding, past or present, and is developed independently without corporate backing.
```

## AI disclosure

`No`

## Contact information

| Campo | Valor |
|---|---|
| Name | Diego Martínez Fernández |
| Email | [ ] |
| OpenPGP key | Genera una: `gpg --full-generate-key` y sube la pública. Cinco minutos, y en NLnet se lee como señal |
| Phone | +34 … |
| Type of applicant | Individual |
| Name of organisation | (vacío) |
| Country | Spain |

---

# Anexo B — Enlaces

**Referencia OSS**
- OSS Document Scanner: `github.com/Akylas/OSS-DocumentScanner`
- MakeACopy: `github.com/egdels/makeacopy`
- ClearPDF Local: `github.com/jeiel85/clear-pdf-local` (integración UVDoc en Android)

**Paquetes y contribuciones upstream enviadas (`docs/upstream/`)**
- `github.com/govindmaheshwari2/doclens/issues/20` (auditoría de dependencia incondicional de Play Services)
- `github.com/ente-io/mobile_ocr/issues/26` (auditoría de licencias y huellas protobuf de modelos PP-OCR y `cls.onnx`)
- `github.com/gtbluesky/onnxruntime_flutter/issues/55` (fallo de `compileSdkVersion 33` en builds release y colisión de `libonnxruntime.so`)

**Modelos**
- UVDoc Grid ONNX (Apache-2.0) — HuggingFace `fredcallagan/uvdoc-grid-onnx`
- UVDoc ONNX — HuggingFace `PaddlePaddle/UVDoc_onnx`
- DocShadow-SD7K ONNX (evaluado y descartado en D-039)
- PP-OCRv5 — `models.ente.io/PP-OCRv5/`

**Financiación**
- Restack: `nlnet.nl/restack`
- Formulario: `nlnet.nl/propose`
- Office Hour 30 sep 2026: `nlnet.nl/events/20260930/office-hour/`
