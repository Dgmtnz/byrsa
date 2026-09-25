<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Auditoría de cumplimiento — 16 de septiembre de 2026

Encargo: comprobar que el proyecto cumple lo que su propio plan exige y que no
hay código cerrado que rompa su filosofía.

Siete frentes se auditaron en paralelo. **Cuatro terminaron; tres se quedaron a
medias** por límite de sesión y están nombrados al final como pendientes, no
omitidos. Todo hallazgo grave fue **verificado a mano** antes de tocar nada; los
comandos están en cada fila.

---

## El veredicto en tres líneas

**El proyecto no usa código cerrado que rompa su filosofía, pero afirmaba
varias cosas sobre sí mismo que eran falsas, y su propio guardia no las veía.**
Se encontraron dos bloqueantes, ambos arreglados el mismo día: el APK de release
declaraba un servicio de Google Play Services, y **no** declaraba el permiso de
INTERNET que sus descargas necesitan. Lo más incómodo es de proceso: **CI no ha
corrido nunca** —el repositorio no tiene remoto— y el README decía que sí.

---

## Lo arreglado en esta auditoría

| # | Hallazgo | Verificación | Estado |
|---|---|---|---|
| 1 | El manifiesto del **release** declaraba `com.google.android.gms.metadata.ModuleDependencies`, inyectado por `image_picker_android` | `unzip -p …release.apk AndroidManifest.xml \| strings -e l \| grep gms` → 2 coincidencias | **Arreglado**: `tools:node="remove"` (D-049) |
| 2 | `tool/check_no_play_services.sh` daba **PASS sobre ese mismo APK**: sólo miraba `classes*.dex`, nunca el manifiesto | ejecutado sobre el fichero con el fallo → `PASS` | **Arreglado**: ahora mira las dos cosas, y añade Play Core a la lista |
| 3 | **`INTERNET` no estaba declarado en release.** Flutter la inyecta sólo en debug, así que los dos botones de descarga estaban muertos en cualquier APK que un usuario instalara | presente en el debug, ausente en el release | **Arreglado** (D-050) |
| 4 | `reuse lint` **fallaba**: 12 ficheros de `demo/` sin información de licencia, y el README afirmaba conformidad | `reuse` 6.2.0 instalado en un venv fuera del repo | **Arreglado**: 605/605 ficheros conformes |
| 5 | El README decía **163 tests**; la cifra real es 205, y tres documentos daban tres números | `dart test` + `flutter test` | **Corregido** |
| 6 | El README decía que iOS «se mantiene compilando en CI» | ningún Swift se ha compilado nunca | **Corregido** |
| 7 | El README decía «estos corren en CI en cada push» | `git remote` vacío | **Corregido** |
| 8 | La regla 2 del guardia exigía que la plataforma precediera a la métrica, así que el orden inverso —el más común al escribirlo en inglés— pasaba limpio | leída la expresión regular | **Arreglado**: cubre los dos órdenes |
| 9 | La regla 3 contaba columnas, cosa que toda fila cumplía por construcción | al endurecerla cazó 5 filas reales sin acción | **Arreglado**, y las 5 filas corregidas |
| 10 | El README citaba 48 MB; la medición vigente es 48,8 MB | `docs/measurements.md` | **Corregido** |

Y una regla nueva, la 5: **nada puede decir que CI lo verifica mientras CI no
haya corrido.** El guardia lo comprueba mirando si hay remoto git.

---

## Código cerrado: la respuesta a lo que se preguntó

**No hay ninguna dependencia propietaria en el producto.** Lo que llega al
dispositivo:

| Componente | Licencia | ¿Fuente pública? | Notas |
|---|---|---|---|
| Flutter y Dart | BSD-3-Clause | Sí | De Google, pero libre. El plan rechaza Play Services (§0.1), no todo lo que Google escriba |
| CameraX (`androidx.camera`) | Apache-2.0 | Sí | Igual |
| ONNX Runtime (`libonnxruntime.so`) | MIT | Sí | Binario precompilado en el APK; la fuente está publicada pero **no se compila aquí**, lo que para F-Droid es un asunto distinto de la licencia |
| Modelos PP-OCR (det, rec, cls, dict) | Apache-2.0 | Sí | Auditados el 14-sep (D-044). Los datos de entrenamiento **no** están publicados |
| UVDoc (dewarp) | pendiente de auditar | — | **Contradicción abierta**: el plan dice MIT, `models.json` dice Apache-2.0. Ver abajo |
| `image_picker` | BSD-3-Clause | Sí | Traía el gancho a Play Services, ya eliminado |
| `mobile_ocr` | MIT | Sí | Dependencia **git**, fijada al commit `0c68f88f` desde el 2026-09-25 (antes, `ref: main`) |

**Ninguna licencia restrictiva. Ningún binario sin fuente pública.** Los dos
matices que sí importan están en la lista de lo que falta.

---

## Lo que falta, por orden de lo que pesa

1. **Subir el repositorio y hacer que CI corra una vez.** Hasta entonces, todo
   lo que dice «verificado en CI» es local. Es también el hueco nº4 del §13 —el
   historial visible— y no cuesta nada.
2. **La contradicción de la licencia de UVDoc.** El plan y `models.json` no
   coinciden, y es el único modelo neuronal que el producto envía. El método
   está escrito en `docs/model-licence-audit.md` y ya se aplicó dos veces.
3. **El Anexo A del plan sigue describiendo el proyecto sobre `doclens` y
   `opencv_dart`**, ambos rechazados por decisiones registradas en ese mismo
   fichero (D-017, D-020, D-022). El §0.3 dice que el plan se corrige primero.
   Es el texto que se convierte en la solicitud.
4. ~~**Fijar `mobile_ocr` a un commit** en vez de a `main`.~~ Hecho el 2026-09-25:
   `ref: 0c68f88f…`, el commit al que ya resolvía `pubspec.lock`. El destino de la
   única petición de red de la aplicación ya no lo controla una rama ajena.
5. **La obligación §4(a) de Apache-2.0**: acompañar el texto de la licencia de
   los modelos y atribuir a PaddleOCR. La auditoría de licencias la identificó
   como «la obligación real» y no está implementada ni anotada.
6. **`demo/` no tiene fichero de licencia** y el repositorio no tiene `LICENSE`
   en la raíz.

---

## Lo que esta auditoría no pudo comprobar

Tres frentes se quedaron sin ejecutar por límite de sesión. **No están
aprobados; están sin mirar**, que es distinto:

- **`closed-source`** — el inventario exhaustivo de binarios y licencias. Lo de
  arriba se reconstruyó de los otros frentes y de comprobación manual, así que
  cubre lo que llega al dispositivo, pero no se recorrió fichero a fichero.
- **`plan-requirements`** — el repaso requisito por requisito del plan. Sin él,
  el cumplimiento del §6 (hitos) y del §7 (alcance) no está tabulado.
- **`fdroid-readiness`** — si F-Droid podría construir y enviar esto hoy.

Se cierran relanzando el mismo workflow, cuyo guion queda en el historial de la
sesión. La pregunta de F-Droid depende además de U-13, que sólo contesta un
tercero.

---

## Lo que esta auditoría dice del proyecto

Los diez hallazgos de arriba estaban todos en un repositorio con 205 tests en
verde, tres guardias automáticos y una disciplina de afirmaciones escrita. Nueve
fallos más habían aparecido los dos días anteriores en cuanto hubo hardware y un
segundo compilador.

La conclusión no es que la disciplina no sirva: es que **un guardia sólo
comprueba lo que se le enseñó a mirar.** El de Play Services leía el código y no
el manifiesto, y la integración era declarativa. El de afirmaciones exigía
columnas y no acciones. Ambos daban verde sobre un fallo real.

Eso es material directo para el campo de retos técnicos de la solicitud, y es
más honesto —y más interesante— que decir que todo estaba bien.
