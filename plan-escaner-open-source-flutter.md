# Byrsa — plan de desarrollo y solicitud Restack

**Un stack libre de captura, rectificación y OCR de documentos en el dispositivo, para Flutter (Android + iOS).**

Versión 3 · 8 de septiembre de 2026
Documento único: es a la vez el plan técnico y la fuente de la solicitud a NLnet / Restack Fund.
**Deadline de la solicitud: 3 de noviembre de 2026, 12:00 CET. Quedan 8 semanas exactas.**

> **Qué cambia respecto a la v2.** La v2 ya reorientó los entregables de "una app" a "cuatro paquetes reutilizables". La v3 no cambia esa arquitectura: cierra las ambigüedades que quedaban (§0), incorpora la solicitud como anexo para que plan y formulario no puedan divergir (Anexo A), y sustituye "los primeros diez días" por un calendario real contra el deadline (§12).

---

## 0.5 Adenda de medición — 8 de septiembre de 2026, tarde

Esta sección la exige §0.3: si un número cambia al tocar el código, cambia aquí primero.
El repositorio ya existe, y estas cinco cosas se midieron o se comprobaron el mismo día.
Detalle completo con los comandos en `docs/measurements.md`; el impacto sobre la
solicitud, en `docs/application-notes.md`.

| Lo que decía el plan | Lo que se ha medido | Dónde |
|---|---|---|
| §4.1: "no lo reimplementes, forkea `doclens`" | `doclens` 0.0.9 declara `play-services-mlkit-*` como dependencia Gradle **incondicional**. Cualquier app que lo use mete Play Services en el APK. Gana §0.1: `byrsa_capture` lleva detector propio, y el arreglo se propone upstream | D-017 |
| §11: "tamaño de app > 150 MB", probabilidad alta | **48,0 MB** en `arm64-v8a` release con splits por ABI, app completa, antes de descargar ningún modelo. Con 0 clases de Play Services tras R8 | D-026 |
| §4.3: "DocShadow-SD7K ONNX" | **120.041.674 bytes** en fp32. La cuantización no es una optimización de T2, es la condición para poder usarlo | D-024 |
| §2/§4.4: "faltan idiomas y medición" sobre `mobile_ocr` | Además: no está en pub.dev, y pub.dev rechaza dependencias git. Resuelto invirtiendo la dependencia: `byrsa_ocr` es la API en Dart puro y **se publica hoy**; el motor vive en `byrsa_ocr_mobile_ocr`, que es el único que carga con el git | D-021, D-027 |
| §3, tabla de stack: `drift`, `opencv_dart` | Ninguno de los dos entra por ahora: SQL a mano sobre `sqlite3` (FTS5 hay que escribirlo igual, y `build_runner` estorba a una build reproducible) y restauración clásica en Dart puro | D-022, D-020 |

Ninguno de los dos problemas bloquea ya un hito: `byrsa_capture` lleva detector propio y
`byrsa_ocr` es publicable. Se contribuyen upstream desde esa posición, que es la que
produce mejores parches y no ata M1 ni M5 al calendario de un tercero (D-028, D-027).

**El séptimo reto técnico de §13.5 ya no hace falta inventarlo.** Es el primero de esa
tabla, es un hallazgo propio, y el evaluador lo puede reproducir en un comando.

---

## 0. Reglas cerradas — no se re-litigan

Estas cuatro no son propuestas. Son decisiones tomadas. Si algo más abajo en este documento parece contradecirlas, gana esta sección.

### 0.1 Sin Google Play Services. ML Kit está descartado.

Hubo una decisión previa, el mismo 8 de septiembre, de usar ML Kit Document Scanner como único camino de captura y aceptar la pérdida de F-Droid a cambio de velocidad. **Queda revertida.** La captura es `doclens` (MIT) y el pipeline propio.

**Por qué:** el proyecto se presenta a Restack, y el entregable son cuatro paquetes que otros deben poder adoptar. Un paquete que arrastra Play Services no lo adopta nadie en el ecosistema al que va dirigido, y difícilmente lo financia un fondo cuyo criterio es la soberanía tecnológica europea. El coste — semanas de ingeniería de cámara que ML Kit regalaba — se paga a conciencia.

**Consecuencia:** F-Droid vuelve a ser requisito desde el commit uno (§9), no un extra.

### 0.2 iOS: hoy no hay build, pero todo se escribe iOS-ready

El desarrollo es en Linux (CachyOS). No hay Mac, luego **no hay build ni medición de iOS**. Pero el proyecto **no es Android-only**: en cualquier momento puede ponerse un agente a trabajar sobre este mismo repositorio desde un Mac, y debe encontrarlo listo.

Doctrina operativa, sin excepciones:

- **Se escribe el lado iOS igual que el de Android.** Plugins con su implementación Swift/AVFoundation completa, carpeta `ios/` completa, APIs Dart simétricas. Nada de "ya lo haremos".
- **CI tiene job de iOS** aunque falle o quede en `continue-on-error`. Un job rojo es información; un job ausente es deuda invisible.
- **Prohibido afirmar resultados de iOS.** Ni cifras, ni "funciona", ni paridad, sin haberlo medido en hardware. Ni en el README, ni en la solicitud, ni en un commit.
- **Todo lo no verificado se registra en `UNVERIFIED.md`**, con qué máquina hace falta y qué comando exacto lo comprobaría. Ese fichero es el encargo del futuro agente con Mac.

Esto afecta a la solicitud: el spike de ONNX en iOS (§4.6) **no se puede correr antes del 3 de noviembre**. La respuesta correcta en el formulario no es inventarlo ni esconderlo, sino declararlo como riesgo abierto con plan B. Ver §11 y Anexo A / *Technical challenges*.

Lo mismo aplica a la validación de PDF (§4.5): Poppler, Chrome y pdf.js se verifican en Linux; **Acrobat y Preview van a `UNVERIFIED.md`**.

### 0.3 Este documento es la fuente de verdad

Lo que se escriba en la solicitud sale de aquí. Si un número cambia en un spike, cambia aquí primero y se propaga al Anexo A. Nunca al revés.

### 0.4 Punto de partida real: cero

A 8 de septiembre de 2026 no existe repositorio, ni código, ni set de prueba. Existe este documento. Cualquier plan que asuma otra cosa está mintiendo, y §12 está calculado desde cero.

---

## 1. Por qué existe el hueco

Ninguna app libre cubre las features de Adobe Scan. Pero el diagnóstico útil no es ese, sino este:

**Cada escáner libre que existe es un monolito en una tecnología distinta.** OSS Document Scanner es NativeScript. MakeACopy es Kotlin nativo. FairScan y Open Note Scanner, Android nativo. Ninguno puede reutilizar el trabajo duro del otro. Cada intento nuevo empieza en un repositorio vacío.

La consecuencia se ve en el mercado: en Android hay media docena de opciones libres imperfectas; en iOS, prácticamente ninguna.

Y hay dos capacidades que **no existen en ningún sitio del ecosistema libre**, pese a que los modelos y los formatos son abiertos y están disponibles:

1. **Rectificación geométrica y eliminación de sombras en el dispositivo.** Es lo que separa una foto de un papel de un escaneo legible. UVDoc y DocShadow existen como modelos abiertos y corren en móvil en ~300 ms. Nadie los ha empaquetado.
2. **Un escritor de capa de texto invisible en PDF en Dart puro.** Es lo que hace que un escaneo sea buscable, copiable y accesible a lectores de pantalla. No hay nada equivalente en el ecosistema Dart.

Esas dos son el núcleo de la propuesta. Lo demás es integración.

---

## 2. Los cuatro entregables, y cómo se corresponden con la solicitud

Esta tabla es la que evita que plan, hitos y formulario se desincronicen. Si tocas una columna, tocas la fila entera.

| Paquete | Tarea (solicitud) | Hito | Qué hace | Estado del arte hoy |
|---|---|---|---|---|
| `byrsa_capture` | T1 | M1 | Detección de bordes en vivo y corrección de perspectiva, sin Play Services | Parcial: `doclens` (MIT) resuelve la base; faltan lotes, ajuste manual de esquinas y API estable |
| `byrsa_restore` | T2 | M3 | Rectificación (UVDoc) y eliminación de sombras (DocShadow) como ONNX cuantizado | **No existe** |
| `byrsa_ocr` | T3 | M5 | OCR en dispositivo tras una API Dart única: Vision en iOS, PP-OCR ONNX en Android | Base: `ente-io/mobile_ocr` (MIT); faltan idiomas y medición |
| `dart_searchable_pdf` | T4 | M4 | Capa de texto invisible (render mode 3) con métrica de fuente correcta | **No existe en Dart** |
| **Byrsa** (app) | T5 | M6 | Implementación de referencia: biblioteca, carpetas, FTS, export, i18n, accesibilidad | — |
| Harness de evaluación | T6 | M2 (línea base) + M6 (informe) | 50 documentos reales + script de CER, tiempo y memoria | **No existe para este dominio** |

Un desarrollador que solo necesite PDFs buscables se lleva `dart_searchable_pdf` e ignora el resto. Ese es el punto, y es lo que se financia.

---

## 3. Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│  Byrsa (app de referencia)                              │
│  Flutter · Riverpod · go_router · Material 3/Cupertino  │
├─────────────────────────────────────────────────────────┤
│  Dominio (Dart puro, testeable sin Flutter)             │
│  Scan · Page · Document · Folder · Pipeline             │
├────────────┬────────────┬────────────┬──────────────────┤
│byrsa_capture│byrsa_restore│ byrsa_ocr │dart_searchable_  │
│            │            │            │pdf               │
│ CameraX /  │ ONNX RT    │ Vision(iOS)│ pdf_cos          │
│ AVFoundation│ UVDoc      │ PP-OCR(And)│ render mode 3    │
│ doclens    │ DocShadow  │            │                  │
├────────────┴────────────┴────────────┴──────────────────┤
│  SQLite (drift) + FTS5 · ficheros en disco              │
│  Cifrado opcional: SQLCipher + AES-GCM                  │
└─────────────────────────────────────────────────────────┘
```

El dominio es Dart puro a propósito: es lo que permite testear el pipeline entero en CI de Linux sin dispositivo ni simulador, que es la única forma de tener cobertura real bajo la restricción de §0.2.

### Stack, con licencias verificadas

| Capa | Paquete / modelo | Licencia |
|---|---|---|
| Estado / rutas | `riverpod`, `go_router` | MIT, BSD-3 |
| BD + búsqueda | `drift`, `sqlite3_flutter_libs` (FTS5) | MIT |
| Captura | `doclens` | MIT |
| Visión | `opencv_dart` (→ `dartcv4`) | Apache-2.0 |
| Inferencia | `onnxruntime` (Dart) | MIT |
| OCR | `ente-io/mobile_ocr` | MIT (modelos: licencia PaddleOCR — **verificar por modelo**, §9) |
| PDF bajo nivel | `pdf_cos`, `pdf_document` | ver repo |
| PDF alto nivel | `pdf` (DavBfr) | Apache-2.0 |
| Códigos | `mobile_scanner` | BSD-3 |
| Sync | `webdav_client` | MIT |
| Rectificación | UVDoc ONNX (~31 MB) | MIT |
| Sombras | DocShadow-SD7K ONNX | ver repo |

**Licencia del proyecto:** GPLv3 para la app, **Apache-2.0 para los cuatro paquetes**. Un paquete Apache-2.0 se adopta; uno GPLv3 no lo toca nadie. La adopción es exactamente lo que Restack financia.

`REUSE.toml` y cabeceras SPDX desde el primer commit.

---

## 4. Los ocho problemas duros

### 4.1 Detección de bordes fluida
No lo reimplementes. `doclens` ya expone el quad de cuatro esquinas a Dart por frame, con Apple Vision en iOS y CameraX en Android. Forkéalo el día uno.

**Trampa:** el `Texture` de Flutter más el stream de frames a Dart es donde se va la batería. Mantén la detección en la capa nativa y pasa solo el quad. Un día entero de perfilado con DevTools antes de dar la captura por buena.

### 4.2 Rectificación de páginas curvas
UVDoc en ONNX. Hace su propio downscale interno a 712×488 y reescala el grid; **no le hagas resize tú antes**. Detecta el shape de salida en runtime, porque según el export devuelve imagen rectificada o grid de muestreo.

**Límite honesto:** curvatura suave y moderada, sí. Lomo cerrado con luz mala, no. Dilo en la UI. Y mídelo: parte de la tarea es establecer dónde está la frontera real y publicarlo.

### 4.3 Eliminación de sombras y suciedad
Tres problemas que Adobe vende como uno:
- **Sombras** → DocShadow-SD7K ONNX. Es el 80% del efecto percibido.
- **Manchas y arrugas** → normalización de iluminación local (CLAHE + división por fondo estimado con blur gaussiano grande). Clásico, barato, mejora todos los escaneos. **Empieza por aquí: es una tarde, y es la línea base contra la que se mide todo lo demás en M2.**
- **Dedos en el borde** → máscara HSV de piel + `cv.inpaint` (Telea). Llega sorprendentemente lejos sin red neuronal.

### 4.4 OCR en dos plataformas
Apple Vision en iOS, PP-OCR ONNX en Android, misma API Dart. Vision es de sistema y no pesa; en Android no hay equivalente sin Play Services, que rompería F-Droid (§0.1).

**Decisión de diseño:** los modelos ONNX **no van en el binario**. Descarga bajo demanda desde una URL fijada, con verificación SHA-256 y caché en disco. El usuario opta explícitamente la primera vez que pide OCR.

### 4.5 Capa de texto invisible
Dibujar cada palabra reconocida en su bounding box con **render mode 3**. Idéntico visualmente, seleccionable y buscable.

**Trampa:** el ancho de la caja invisible tiene que coincidir con el ancho del texto renderizado o el copiar-pegar sale desalineado. Se ajusta con `Tz` por palabra. Un PDF que parece buscable y se comporta mal es peor que no hacerlo.

**Validación obligatoria:** Poppler (`pdftotext -layout`), Chrome y pdf.js **se verifican en Linux desde el primer día**. Acrobat y Preview van a `UNVERIFIED.md` hasta que haya máquina (§0.2). Declarar los cuatro como verificados sin haberlo hecho es exactamente el tipo de afirmación que hunde una solicitud.

### 4.6 ONNX en iOS — riesgo abierto, no medible antes del deadline
El riesgo mayor del plan. ONNX Runtime vía FFI en iOS está menos rodado que en Android: tamaño de binario, techos de memoria y revisión de App Store son riesgos reales.

**Y no se puede cerrar antes del 3 de noviembre**, porque no hay Mac (§0.2). Esto se declara tal cual en la solicitud: riesgo identificado, plan B definido, medición pendiente de hardware. Un riesgo declarado con mitigación puntúa; uno escondido que el evaluador detecta, descarta.

**Plan B:** convertir a Core ML en iOS y mantener ONNX en Android tras la misma API Dart. La API Dart simétrica de §0.2 es precisamente lo que hace que este plan B sea un cambio de implementación y no un rediseño.

### 4.7 Medir sin engañarse
Afirmar que igualas a un escáner comercial no significa nada sin evidencia. El harness de evaluación es entregable de primera clase, no una tarea de limpieza. §5.

### 4.8 La contradicción "cero red" — resuélvela ahora, no en el formulario

§4.4 descarga modelos bajo demanda. Eso obliga a declarar el permiso `INTERNET` en Android, que es de instalación y no se pide en runtime. Por tanto **la frase "la build no pide permiso de red" es falsa** y no puede aparecer en la solicitud ni en el README.

La formulación correcta, que además es más fuerte porque es verificable:

> Ningún documento sale nunca del dispositivo. El único tráfico de red que la aplicación puede generar es una descarga de modelos que el usuario inicia explícitamente, desde una URL fijada y con verificación SHA-256.

**Riesgo asociado, real:** F-Droid mira con lupa las apps que descargan blobs en tiempo de ejecución, y puede etiquetarlas. Hay que confirmar el criterio exacto antes de M5 y, si hace falta, ofrecer un *flavor* con los modelos cuantizados empaquetados. Va a §11.

---

## 5. El harness de evaluación

Es lo que convierte el proyecto en I+D en lugar de en desarrollo de producto, y es el criterio que Restack evalúa.

**Set de prueba:** **50 documentos** reales fotografiados por ti — recibos arrugados, facturas, páginas de libro, DNI, pizarras, luz mala, sombra de mano. Publicado con licencia abierta si los documentos lo permiten, o sintético equivalente si no. Cuidado con los datos personales: el DNI y las facturas propias se fotografían, se anotan y **no se publican**; para esas categorías se publica un equivalente sintético o anonimizado, y el script funciona igual.

**Script:** corre el pipeline completo sobre los 50 y reporta CER (character error rate), tiempo por etapa, memoria pico y tamaño de salida. Un comando, resultado reproducible por terceros.

**Compromiso:** publicar los resultados desfavorables también. Un benchmark que solo sale bien no es un benchmark.

**El número 50 es fijo** y aparece igual en el plan, en M2 y en el formulario. No lo dejes como `[N]` en ningún sitio.

Este set es tu activo más valioso del proyecto. Fotografíalo en la semana uno — es lo único de la lista que no depende de que nada compile.

---

## 6. Hitos

NLnet paga contra hitos. Esta es la estructura que propondrías en el MoU si te seleccionan.

| Hito | Tarea | Entregable verificable |
|---|---|---|
| **M1** | T1 | `byrsa_capture` publicado en pub.dev. Captura y perspectiva funcionando **medidas en Android**, implementación iOS completa y compilable en CI, sin Play Services. Demo compilable. |
| **M2** | T6 | Set de 50 documentos + harness público. Línea base medida con el pipeline clásico (§4.3). |
| **M3** | T2 | `byrsa_restore` publicado. UVDoc y DocShadow cuantizados en gama media, con benchmark de tiempo y memoria y límites documentados. |
| **M4** | T4 | `dart_searchable_pdf` publicado. PDFs validados en Poppler, Chrome, pdf.js y — con la máquina disponible — Acrobat y Preview. |
| **M5** | T3 | `byrsa_ocr` publicado, con cobertura y CER medidos para español, inglés, francés, alemán, italiano y portugués. |
| **M6** | T5 | App Byrsa v1.0: biblioteca, carpetas, FTS, export, i18n, accesibilidad. Build reproducible, REUSE compliant, publicada en F-Droid y GitHub Releases. Informe final de evaluación. |

Cada hito es autocontenido: si el proyecto se parara en M3, lo entregado hasta ahí sigue siendo útil para terceros. Ese es el criterio.

**Regla de honestidad en los hitos:** cada uno declara en qué plataforma está medido. Un hito "verde en Android, compilado pero no medido en iOS" se escribe así, no se redondea.

---

## 7. Alcance: dentro y fuera

Recortar es lo que hace creíble una propuesta de doce meses.

**Dentro del año subvencionado:**
captura · perspectiva · filtros · multipágina · lotes · rectificación · sombras · OCR · PDF buscable · biblioteca · carpetas · búsqueda FTS · export PDF/JPEG/TXT · cifrado con contraseña · i18n · accesibilidad · builds reproducibles

**Fuera, backlog explícito:**
firma y relleno de formularios · anotaciones · modo DNI · tarjetas de visita a contactos · QR · export DOCX/XLSX · sincronización WebDAV y Paperless-ngx · desktop · resumen con LLM

Decláralo así en la propuesta. Un alcance recortado y consciente puntúa mejor que uno maximalista.

---

---

## 9. Distribución

**Verificación obligatoria de desarrollador de Google.** Desde el 30 de septiembre de 2026 se aplica en Brasil, Indonesia, Singapur y Tailandia: los Android certificados bloquean la instalación de apps de desarrolladores no verificados, venga de Play, de F-Droid o de descarga directa. Despliegue global previsto en 2027.

- Regístrate en la Android Developer Console aunque solo pienses distribuir por F-Droid. ID gubernamental y ~25 $.
- No apuestes toda la distribución a un canal. F-Droid lo ha calificado de amenaza existencial.
- iOS: 99 €/año de Apple Developer Program. **No lo pagues todavía** — sin Mac no hay nada que subir, y la cuota corre desde que la pagas. Va en el presupuesto, se contrata cuando haya máquina.

Canales: F-Droid · IzzyOnDroid · GitHub Releases · Play · App Store · Accrescent.

Requisitos F-Droid desde el commit uno, no retrofiteados: build reproducible, sin binarios precompilados en el repo, sin Play Services en la build principal. **Pendiente de confirmar antes de M5:** el criterio exacto de F-Droid sobre descarga de modelos en runtime (§4.8) y la licencia concreta de cada modelo PaddleOCR que se distribuya.

---

## 10. Después de la ayuda

Doce meses de financiación no son un modelo de negocio. Opciones honestas, en orden:

- **App de pago en Play y App Store** (3-6 €, una vez), gratis en F-Droid y GitHub. Modelo de KeePassDX, Organic Maps, Syncthing-Fork.
- **Licencia dual** de los paquetes: Apache-2.0 para todos, licencia comercial para quien quiera integrarlos en producto cerrado sin atribución. Aquí está el dinero real.
- **GitHub Sponsors / Open Collective.** Un proyecto financiado por la Comisión Europea atrae patrocinio de una forma que uno anónimo no.
- **Segunda ayuda de Restack:** hasta 150.000 € en propuestas posteriores, tope vitalicio de 500.000 €. El programa va hasta 2030.

Lo que no: freemium con features de pago dentro del binario GPL.

---

## 11. Riesgos

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| **Sin Mac, iOS no se mide ni antes ni durante** | **Alta** | **Alto** | Escribir iOS-ready (§0.2); declararlo en la solicitud como riesgo abierto; presupuestar máquina o runner macOS; `UNVERIFIED.md` como encargo listo |
| ONNX en iOS falla por tamaño o revisión | Media | Alto | Plan B: Core ML tras la misma API Dart. No verificable hasta tener máquina |
| F-Droid rechaza o etiqueta la descarga de modelos | Media | Medio | Confirmar criterio antes de M5; *flavor* con modelos empaquetados como salida |
| Rectificación por debajo de lo prometido | Media | Medio | Publicar límites medidos, no prometer más |
| Tamaño de app > 150 MB | Alta | Medio | Modelos por descarga, splits ABI, treeshake de dartcv4 |
| Verificación de Google bloquea F-Droid | Alta | Medio | Registrarse; múltiples canales |
| **Scope creep** | **Alta** | **Alto** | §7 congelado. Backlog explícito y público |
| **Llegar al 3 de noviembre sin spikes ni repo** | **Media** | **Alto** | §12 con fechas; criterio de corte semanal; enviar el 2, no el 3 |
| Datos personales en el set de 50 | Media | Medio | Anotar en privado, publicar sintético para DNI y facturas (§5) |
| No conseguir la ayuda | Alta (~86%) | Medio | El repo, los spikes y el benchmark sobreviven al rechazo y sirven para la siguiente ronda |

---

## 12. Calendario hasta el 3 de noviembre

8 semanas exactas. El orden está elegido para que lo que más pesa en la solicitud (§13) esté hecho antes de sentarse a redactar.

**S1 · 8-14 sep — que exista el proyecto**
1. Repo público. GPLv3 app / Apache-2.0 paquetes, `REUSE.toml`, cabeceras SPDX.
2. CI con job Android **y job iOS** (§0.2). `CONTRIBUTING.md`, política de IA en el README, `.gitmessage` (§8.3).
3. Estructura de capas del §3 cableada y vacía. `UNVERIFIED.md` y `DECISIONS.md` creados vacíos, con la primera entrada: la reversión de ML Kit (§0.1).
4. **Fotografiar los 50 documentos.** No depende de que nada compile: hazlo aunque el resto se atasque.

**S2 · 15-21 sep — Spike A: captura**
`doclens` corriendo en un Android de gama media. fps, consumo, calidad del quad, números anotados. Implementación iOS escrita y compilando en CI, marcada como no medida.

**S3 · 22-28 sep — línea base y Spike B**
Pipeline clásico (CLAHE + división por fondo, §4.3) sobre los 50 documentos: es la línea base de M2 y se consigue en una tarde. Luego UVDoc en `onnxruntime` Dart sobre Android: tiempo y RAM.

**S4 · 29 sep-5 oct — Spike D: PDF**
Capa invisible con render mode 3. Ctrl+F verificado en Poppler, Chrome y pdf.js; Acrobat y Preview a `UNVERIFIED.md`.
**30 sep: Office Hour de NLnet.** Ve, y lleva dos preguntas concretas: tarifa horaria aceptable para un individuo en España, y si la falta de hardware iOS es un problema para ellos. Preguntarlo vale más que adivinarlo.

**S5 · 6-12 oct — Spike C: OCR**
`mobile_ocr` sobre 10 fotos reales en español. CER anotado a mano. Es el número que hace creíble T3.

**S6 · 13-19 oct — upstream**
Un issue o PR **real** en `doclens` o `mobile_ocr`, con los datos de los spikes. No es cortesía: es la frase más fuerte que puedes poner en la solicitud. `DECISIONS.md` al día.

**S7 · 20-26 oct — redactar**
Rellenar el Anexo A con los números reales. Empezar por los dos campos que deciden: experiencia y retos técnicos. Generar la clave PGP.

**S8 · 27 oct-2 nov — cerrar**
Revisión completa, cuadrar cifras entre §6, §13 y Anexo A, montar el log de IA (§8.1). **Enviar el 2 de noviembre.** Nunca el mismo día del deadline.

**Criterio de continuación:** si los spikes B o D fallan, replantea antes de invertir meses. Un fallo en S3 o S4 todavía deja tiempo de reorientar la propuesta; uno descubierto en enero, no.

---

## 13. Los seis huecos que deciden la solicitud

Por orden de impacto. Nada de lo demás compensa uno de estos vacío.

1. **El campo de experiencia** (Anexo A). Vacío o genérico = descarte. Solo lo puedes escribir tú.
2. **Los números de los spikes** en retos técnicos. Sin ellos la propuesta es una intención.
3. **Un PR o issue real** en `doclens` o `mobile_ocr`, enlazado en la comparación.
4. **El repo con historial visible.** Seis semanas de commits reales valen más que cualquier frase del formulario.
5. **El séptimo reto técnico**, el que solo sabes tú porque has tocado el código.
6. **La tarifa**, justificada en una frase que puedas sostener en voz alta.

---

# Anexo A — Borrador de la solicitud

Formulario: `nlnet.nl/propose` · Fondo: **Restack** · Deadline: **3 nov 2026, 12:00 CET**

Todo lo que va entre `[CORCHETES]` solo lo puedes escribir tú, y es lo que más pesa. Lo demás es andamio: reescríbelo en tu voz. Si un párrafo no lo defenderías en voz alta ante un evaluador, bórralo. Los límites de caracteres son duros.

## Proposal title

```
Byrsa: an on-device document capture, rectification and OCR stack for Flutter
```

## Project website(s) / repositories

```
[URL DEL REPO]
[URL DE LA LANDING, si llega a tiempo]
```

## Summary (max. 1000 characters)

```
Scanning paper with a phone is an everyday need, but the free software
ecosystem has no reusable building blocks for it. The existing FOSS
scanners are each a self-contained application written in a different
technology, so none of their work can be reused by anyone else, and iOS
users have almost no free option at all.

Byrsa splits the problem into four reusable Dart/Flutter packages: live
edge detection and perspective correction; geometric rectification and
shadow removal, running as quantised ONNX models on the device; a
pure-Dart writer for PDF invisible text layers, which is what makes a
scan searchable and accessible to screen readers; and a reference
application that ties them together and proves the stack works end to
end.

Everything runs locally. No document ever leaves the device: the only
network request the application can make is a model download the user
starts explicitly. The packages are the deliverable; the application is
the proof.
```

*≈ 960 caracteres. Última frase corregida respecto al borrador previo: ver §4.8.*

## How much money do you request?

```
[IMPORTE]
```

## Budget breakdown (max. 4000 characters)

```
I am applying as an individual and would work on this [full time /
alongside X] for twelve months.

RATE
I have used [X] EUR per hour for all development work. [UNA FRASE
JUSTIFICÁNDOLO: por debajo de tu tarifa habitual de contratación en
España, y cubre costes de autónomo. Concreto, y sin disculparte.]

TASKS

T1 - Capture pipeline. [X] hours.
Live edge detection and perspective correction on both platforms,
released as the package `byrsa_capture`. Builds on the existing
MIT-licensed doclens plugin, extended with batch capture, manual corner
adjustment and a stable Dart API. No dependency on Google Play Services,
so the output is usable in F-Droid and other independent distributions.

T2 - Geometric rectification and shadow removal. [X] hours.
Packaging UVDoc (page dewarping) and DocShadow (shadow removal) as
quantised ONNX models that run on mid-range phones, released as
`byrsa_restore`. This is the part no free scanner currently has, and the
part that decides whether a photograph of a page is actually readable.
Includes quantisation, memory profiling and a reproducible benchmark.

T3 - OCR integration. [X] hours.
Integrating on-device text recognition across both platforms behind one
Dart API, using Apple Vision on iOS and PP-OCR ONNX models on Android.
Language coverage and quality measurement for European languages.

T4 - Searchable PDF writer. [X] hours.
A pure-Dart implementation of PDF invisible text layers (text render
mode 3), released as `dart_searchable_pdf`. Correct font metrics and
per-word horizontal scaling so that selection and search align with the
underlying image. Nothing equivalent exists in the Dart ecosystem today.

T5 - Reference application. [X] hours.
The Byrsa application itself: library, folders, full-text search,
export, internationalisation and accessibility. This is what makes the
packages credible and gives the work real users.

T6 - Evaluation harness, documentation and release. [X] hours.
A public benchmark of 50 real documents with a script that reports
character error rate and timing for every change, so quality claims can
be checked by anyone. Reproducible builds, REUSE/SPDX compliance,
packaging and release to F-Droid, Play and the App Store.

Total: [X] hours = [X] EUR

EXPENSES
- Test devices (one mid-range Android and one older iPhone; these are
  where the real problems appear): [X] EUR
- macOS build machine or hosted macOS CI. I develop on Linux, so iOS
  builds and measurements currently depend on this. [X] EUR
- Apple Developer Program: 99 EUR/year
- Android Developer Console registration: approx. 25 USD

Total requested: [X] EUR
```

*Deja que sume una cifra irregular: 45.522 € con aritmética que se puede seguir transmite que has pensado el proyecto; 50.000 € clavados, que has pensado el techo.*

**Ejemplo de aritmética, solo como plantilla — sustituye por tus horas reales:**
T1 210 h · T2 300 h · T3 170 h · T4 190 h · T5 250 h · T6 150 h = **1.270 h**.
1.270 × 35 €/h = 44.450 €. Gastos: 600 (dispositivos) + 350 (CI macOS) + 99 (Apple) + 23 (Google) = 1.072 €. **Total 45.522 €.**

**La partida de macOS es nueva y es deliberada.** Es la traducción presupuestaria del riesgo de §0.2: pedir explícitamente lo que hace falta para cumplir la promesa de iOS es más creíble que prometer iOS y callar que no tienes con qué compilarlo.

## Comparison with other efforts (max. 4000 characters)

```
There are four free scanner applications worth comparing against.

OSS Document Scanner (Akylas) is the most complete. It is written in
NativeScript, ships on Android and iOS, and does edge detection, OCR
with Tesseract, searchable PDF and WebDAV sync. It has no neural
rectification or shadow removal, no office export, and its iOS build is
clearly secondary to the Android one.

MakeACopy is technically the closest to what I want to build. It runs
PaddleOCR through ONNX entirely offline, produces searchable PDFs and
indexes text with SQLite FTS5. It is Android-only, native Kotlin.

FairScan and Open Note Scanner cover the basic capture-and-crop case and
little beyond it. Both Android-only.

WHAT IS DIFFERENT HERE

The gap is not that these applications are bad. It is that each of them
is a monolith in a different technology, so none of the hard work inside
them can be reused by anyone else. There is no shared pipeline. Every
new attempt starts from an empty repository, and the consequence is
visible: on iOS there is effectively no free document scanner at all.

Byrsa is structured the other way round. The deliverables are four
independent packages with their own tests and documentation; the
application is the reference implementation that proves they compose. A
developer who only needs invisible-text-layer PDFs takes T4 and ignores
the rest.

Two capabilities do not exist anywhere in the free ecosystem today:
on-device page rectification and shadow removal (T2), and a pure-Dart
searchable PDF writer (T4). Both have open models and open formats
available; nobody has packaged them for mobile.

HAVE I CONSIDERED CONTRIBUTING TO THE OTHERS?

Yes, and it does not work for the goal. Contributing rectification to
MakeACopy would help MakeACopy's Android users and nobody else, because
the code would be Kotlin inside an application. The same for OSS
Document Scanner in NativeScript. Neither can produce a reusable Flutter
package, and Flutter is where the cross-platform leverage is: it is the
only realistic path to one codebase covering Android, iOS and desktop
with a shared privacy guarantee.

Where contributing does make sense, I intend to do it: I am building on
doclens and on Ente's mobile_ocr plugin rather than reimplementing them,
and improvements I make to either will go upstream as patches.

[SI EN EL SPIKE HAS ABIERTO ALGÚN ISSUE O PR EN ESOS REPOS, DILO AQUÍ
CON ENLACE. ES LA FRASE MÁS FUERTE DE TODO EL CAMPO — §12/S6.]
```

## Technical challenges (max. 4000 characters)

Este campo evalúa si sabes dónde están los cadáveres. Si escribes que no esperas problemas, te descartan.

```
1. ONNX on iOS, and a hardware gap I should be upfront about. The
rectification and shadow models are the riskiest part of the plan. ONNX
Runtime through Dart FFI on iOS is less well travelled than on Android,
and binary size, memory ceilings and App Store review are all real
risks. I develop on Linux and do not currently have a macOS machine, so
I can state plainly that this risk is identified but not yet measured:
the iOS side of every plugin is written and kept compiling in CI, and
the Dart APIs are symmetric by design, but no iOS numbers exist yet and
I will not claim any. Acquiring a build machine or hosted macOS CI is a
budgeted item for exactly this reason. Fallback if ONNX proves
unworkable on iOS: convert to Core ML and keep ONNX on Android behind
the same Dart API — which the symmetric API makes an implementation
change rather than a redesign.

2. Model size versus application size. UVDoc alone is around 31 MB
unquantised. Shipping several models inside the binary is not viable, so
models are downloaded on demand from a pinned URL with SHA-256
verification and cached. The application therefore declares network
access, and I would rather state the precise guarantee than an
attractive but false one: no document ever leaves the device, and the
only request the application can make is a model download the user
starts explicitly. A build flavour with quantised models bundled is the
fallback if runtime downloads prove incompatible with F-Droid policy.

3. Rectification has honest limits. Dewarping works on gentle and
moderate page curvature. A tightly bound book under poor light is not
solvable with current open models, and I would rather say so in the
interface than pretend otherwise. Part of T2 is establishing where the
boundary actually is and reporting it.

4. Invisible text layer alignment. Getting text to be selectable is
easy; getting the selection to line up with the image requires matching
the width of each rendered word to its bounding box, which means correct
font metrics and per-word horizontal scaling. Getting this wrong
produces a PDF that looks searchable and behaves badly, which is worse
than not doing it. Validation against Poppler, Chrome and pdf.js is part
of the task from the first release; Acrobat and Preview are validated
once the corresponding machines are available, and until then they are
listed as unverified rather than assumed.

5. Real-time capture cost. Streaming camera frames into Dart for edge
detection is where battery and thermal problems live. [NÚMEROS DEL
SPIKE A: fps, temperatura, % de batería en 10 min.] Mitigation is to
keep detection in the platform layer and pass only the quad to Dart.

6. Measuring quality honestly. Claiming to match a commercial scanner is
meaningless without evidence. The evaluation harness in T6 exists so
that every claim about accuracy is reproducible by a third party on a
published set of 50 documents. I expect some results to be unfavourable
and intend to publish them anyway. Documents containing personal data
are annotated privately and published as synthetic equivalents.

7. [AÑADE EL SÉPTIMO TÚ, DESDE LOS SPIKES. UNO SOLO, QUE NO ESTÉ EN
NINGÚN SITIO. ES LO QUE DEMUESTRA QUE HAS TOCADO EL CÓDIGO.]
```

**Candidato para el 7 si ningún spike da nada mejor** — pero prefiere siempre un hallazgo tuyo: la fricción entre la política de F-Droid sobre blobs descargados en runtime, la verificación obligatoria de desarrollador de Google desde el 30 de septiembre de 2026, y la necesidad de auditar la licencia de cada modelo PaddleOCR por separado. Es un problema de distribución real que casi nadie plantea al pedir financiación, y encaja con el criterio de soberanía de Restack.

## Ecosystem (max. 2000 characters)

```
DEPENDENCIES
The project builds on existing free software rather than replacing it:
doclens (MIT) for native capture, Ente's mobile_ocr plugin (MIT) for
cross-platform text recognition, opencv_dart (Apache-2.0) for image
processing, ONNX Runtime for inference, and the UVDoc and PaddleOCR
model families. Fixes and improvements go upstream. The four packages
are Apache-2.0 so that anyone can adopt them; the application is GPLv3.

USERS
Three groups, in order of how directly they are served.

First, anyone who scans identity documents, contracts, payslips or
medical records with a phone. Today the convenient options upload those
documents to servers outside the EU and require an account. That is an
ordinary, daily sovereignty problem and it has no free answer on iOS.

Second, the self-hosting community. Paperless-ngx users currently have
no good free capture front-end; a scanner that exports straight into a
Paperless instance has an immediate and vocal user base.

Third, other developers. Anyone building a Flutter application that
needs to turn a photograph into a readable, searchable document, which
today means either a proprietary SDK or several weeks of work.

ENGAGEMENT
Packages published to pub.dev with documentation from the first release,
not at the end. Application distributed through F-Droid, IzzyOnDroid,
GitHub Releases, Play and the App Store, so that it survives changes in
any single channel. [AÑADE CUALQUIER COMUNIDAD CONCRETA CON LA QUE YA
HABLES, O A LA QUE VAYAS A ESCRIBIR ANTES DE NOVIEMBRE.]
```

## What makes you the right person? (max. 2000 characters)

Este campo no lo puede escribir nadie más, y es de los dos que más pesan. Contesta a estas tres preguntas y redáctalo tú:

1. **¿Qué has construido tú, con nombre y enlace**, que demuestre que puedes terminar algo de esta complejidad? Elige los dos proyectos que más se parezcan técnicamente, no los que más te gusten.
2. **¿Qué experiencia concreta tienes en las tres áreas duras** — Flutter multiplataforma, visión por computador / ONNX, y formatos de documento?
3. **¿Qué has hecho ya en *este* proyecto?** Resultados de los spikes, con fechas y commits.

NLnet valora contribuciones a proyectos de otros. Si has hecho alguna, aunque sea pequeña, ponla. Si no, tienes hasta la semana 6 (§12) para hacer una de verdad en `doclens` o en `mobile_ocr`.

## Other funding sources (max. 1000 characters)

```
None. This project has no other funding, past or present, and is not
part of any company. [SI MONTAS ALGO O TIENES INGRESOS RELACIONADOS,
DILO — LA OMISIÓN SE CASTIGA MÁS QUE EL HECHO.]
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

**Paquetes**
- `pub.dev/packages/doclens`
- `github.com/ente-io/mobile_ocr`
- `pub.dev/packages/opencv_dart`
- `pub.dev/packages/dart_pdf_editor`

**Modelos**
- UVDoc ONNX — HuggingFace `PaddlePaddle/UVDoc_onnx`
- DocShadow-SD7K ONNX
- PP-OCRv5/v6 — `models.ente.io/PP-OCRv5/`

**Financiación**
- Restack: `nlnet.nl/restack`
- Formulario: `nlnet.nl/propose`
- Office Hour 30 sep 2026: `nlnet.nl/events/20260930/office-hour/`
