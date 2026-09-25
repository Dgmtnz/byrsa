<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Estado del proyecto — 16 de septiembre de 2026

Lo que hay, lo que funciona, lo que está medido y lo que no. Escrito para que
alguien que no ha visto el proyecto pueda saber en diez minutos dónde está y qué
se puede afirmar de él.

**La regla que gobierna este documento y todo el repositorio: nada se afirma sin
medirlo.** Si una cifra aparece aquí, está en
[`docs/measurements.md`](docs/measurements.md) con la fecha y la máquina. Si algo
no se ha comprobado, está en [`UNVERIFIED.md`](UNVERIFIED.md) con el comando
exacto que lo cerraría, no omitido.

---

## En una frase

Un escáner de documentos para Flutter **sin Google Play Services**, cuya cadena
completa —capturar, enderezar, restaurar, reconocer texto y exportar un PDF
buscable— **funciona de extremo a extremo en un teléfono Android real**, con un
corpus de evaluación propio y un error de carácter medido.

---

## Lo que existe

| Pieza | Líneas | Qué es | Estado |
|---|---|---|---|
| `byrsa_restore` | 2.011 | Restauración de imagen: iluminación, filtros, dewarp | Dart puro · **publicable** · corre también en navegador |
| `dart_searchable_pdf` | 1.316 | Capa de texto invisible en PDF | Dart puro · **publicable** |
| `byrsa_capture` | 1.503 | Cámara, detección de bordes, perspectiva | Flutter · CameraX / AVFoundation |
| `byrsa_ocr` | 421 | API de OCR y orden de lectura | Dart puro · **publicable** |
| `byrsa_ocr_mobile_ocr` | 339 | El motor: Vision (iOS) / PP-OCR (Android) | No publicable a propósito (aísla una dependencia git) |
| `byrsa_restore_onnx` | 206 | `UvdocStage`, separado porque ONNX es un plugin | Flutter |
| `app/` | 3.890 | Byrsa, la implementación de referencia | GPLv3 |
| `harness/` | 1.382 | Corpus, ejecución y puntuación | Dart puro |
| `demo/` | 695 | La restauración en un navegador | Sin servidor, sin CDN |

**56 decisiones · 232 tests en verde · analyze limpio.**

Tres guardias corren antes de cada commit y en CI: `tool/check_claims.sh`
(disciplina de afirmaciones), `tool/check_web_parity.sh` (VM y dart2js dan los
mismos bytes) y `tool/check_no_play_services.sh`.

---

## Lo que está medido

Todo con su fecha y su máquina en [`docs/measurements.md`](docs/measurements.md).

### En un teléfono real (Xiaomi Mi 9T Pro, Android 16, arm64)

| | |
|---|---|
| La aplicación instala, arranca y renderiza | Sí |
| Cámara: las tres etapas de CameraX enlazadas | Sí |
| Permiso de cámara, camino de concesión | Funciona (**denegación sin probar**) |
| Descarga de modelos | 4 artefactos, tamaños idénticos a los del manifiesto |
| **OCR** | Funciona |
| **PDF buscable exportado y verificado con Poppler** | Funciona, acentos intactos |

### Error de carácter, 12 páginas del corpus sintético

| Conjunto | CER |
|---|---|
| 5 páginas sin dañar | **1,00%** |
| Un solo daño (movido, torcido, reflejo, luz mezclada) | 0,39% – 2,56% |
| **Curvada** | **29,09%** |
| **Dos daños a la vez** | **42,85% y 63,90%** |

Medido el 14 y el 16 de septiembre, con el estimador del papel anterior a D-054 y, en la
página curvada, con el encuadre del dewarp anterior a D-053 si la etapa llegó a correr (U-34).
No se ha vuelto a medir.

**El hallazgo no es la media, es la forma.** Un daño casi no se nota; dos a la
vez no degradan, rompen. Entre 2,56% y 42,85% no hay escalones. La causa parece
arquitectónica: el pipeline clásico estima un campo de color de papel y un juego
de mapas, y cada corrección supone que los demás problemas no están (D-048).

### En escritorio

| | |
|---|---|
| Restauración, 12 MP | 0,61 s |
| Pipeline sobre 50 páginas | mediana 448 ms, p90 578 ms |
| Restauración en navegador, 1,4 MP | 304 ms, **cero peticiones externas** |

Las tres filas son de antes del estimador de D-054 y sin la etapa de intrusiones de D-055, que
va apagada por defecto y cuyo coste está en esa entrada. No se han vuelto a medir.

---

## Lo que NO está medido, y por tanto no se afirma

- **Nada de iOS.** 983 líneas de Swift jamás compiladas. No hay Mac.
- **Ninguna fotografía real.** Todo el CER es sobre páginas sintéticas
  renderizadas de una fuente. Es la entrada más fácil que este proyecto le dará
  nunca a un OCR.
- **Si el dewarp neuronal llega a ejecutarse.** La aplicación descarta los
  `StageOutcome` que su propio pipeline devuelve, así que nada distingue que la
  etapa corriera de que se saltara (U-34).
- **Tiempos en el teléfono.** Ni restauración, ni OCR, ni el codificador nativo.
- **El camino de denegación del permiso de cámara.**

Las 54 filas de [`UNVERIFIED.md`](UNVERIFIED.md) llevan cada una su comando.

---

## Las dificultades, ordenadas por lo que cuestan

### 1. Las cincuenta fotografías — sólo las puede hacer Diego

Bloquean D-039 (¿merece alguna red de sombras sus 120 MB?) y D-042 (¿se activa
el quitado de intrusiones? Desde D-055 la etapa está conectada, con interruptor y
apagada por defecto, porque sobre el corpus sintético borra texto bajo una sombra de
mano diagonal), y son lo único que convierte el CER en una afirmación sobre el
producto.

**La instrucción cambió el 14 de septiembre** y está en
[`harness/dataset/README.md`](harness/dataset/README.md): hacen falta al menos
diez páginas con **dos dificultades a la vez** —una sombra sobre una página
torcida, poca luz con la mano en el encuadre— porque ahí es donde se mide que el
producto se rompe. La lista de tomas anterior habría producido un corpus que se
saltaba justo ese borde.

### 2. iOS, que no se puede ni compilar

El riesgo mayor del plan (§4.6): que ONNX no funcione en iOS no es medible sin un
Mac. Plan B documentado: Core ML tras la misma API.

### 3. El precipicio de los dos daños

Medido, sin explicación cerrada y sin arreglo. Es la pregunta técnica más
interesante que tiene el proyecto y la que mejor se defiende ante un evaluador,
porque afina «¿es suficiente lo clásico?» en «lo clásico basta hasta que dos
problemas se solapan, y ése es el caso que una red tendría que comprar».

### 4. Instrumentación que no existe

La aplicación no registra qué etapas corrieron ni cuánto tardaron, aunque el
pipeline se lo entrega. Sin eso no hay medición de campo posible de ninguna
etapa, ni del dewarp ni del codificador nativo.

### 5. Lo que no está construido

Cifrado (aplazado en D-015), empaquetado F-Droid y build reproducible, rehacer
página, saltar al resultado de búsqueda, icono y marca.

---

## La lección del 14 al 16 de septiembre

En tres días aparecieron **nueve fallos reales**. Ninguno era alcanzable desde
los 205 tests:

| Fallo | Sólo visible con… |
|---|---|
| Previsualización estirada | un móvil y un ojo humano |
| Contorno en otro sistema de coordenadas | lo mismo |
| Siete frases en español en una interfaz inglesa | lo mismo |
| `>>` sobre negativos difiere en dart2js | un segundo compilador |
| `models.json` fuera del APK | un APK de verdad |
| Uso-después-de-liberar → SIGSEGV | un teléfono |
| PDF exportado sin capa de texto | exportar uno de verdad |
| Espacio y guion mal codificados en WinAnsi | mirar los **bytes**, no el texto |
| El banco midiendo cinco veces la misma página | mirar los hashes, no los resultados |

Los tests siguen valiendo lo que valían. Lo que esto dice es otra cosa: **un
proyecto puede tener doscientas pruebas en verde y estar roto de extremo a
extremo justo en el sitio donde el usuario lo usa.** Es, literalmente, el séptimo
reto técnico que el plan (§13) dice que sólo puede escribir quien haya tocado el
código — y ahora se puede contar con nueve ejemplos fechados.

---

## Qué mirar después de esto

1. [`plan-escaner-open-source-flutter.md`](plan-escaner-open-source-flutter.md) —
   el plan y el borrador de la solicitud.
2. [`DECISIONS.md`](DECISIONS.md) — las 56 decisiones, con sus números.
3. [`UNVERIFIED.md`](UNVERIFIED.md) — 54 filas, cada una con su comando.
4. [`docs/measurements.md`](docs/measurements.md) — todo lo medido.
5. [`docs/AUDITORIA.md`](docs/AUDITORIA.md) — cumplimiento y licencias.
