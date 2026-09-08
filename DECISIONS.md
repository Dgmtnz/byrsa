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
