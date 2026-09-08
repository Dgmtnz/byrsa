<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# dart_searchable_pdf

Turn a scanned image plus OCR output into a PDF whose text can be **selected,
searched and read aloud**, while the page still looks exactly like the scan.

Pure Dart. No dependencies beyond `meta`. No platform channels, no native code,
no image codec — so it runs in a Flutter app, on a server, and in `dart test`.

Nothing equivalent existed in the Dart ecosystem when this was written.

## How it works

The page paints the scan, then draws every recognised word on top of it in
**text render mode 3**: glyphs that fill nothing and stroke nothing. They put no
pixel on the page, but they are real text to a viewer, to `Ctrl+F`, to
copy-paste and to a screen reader.

The part that is easy to get wrong is alignment. A word drawn at its box's
position but in the wrong width makes selection drift across the line — a PDF
that looks searchable and behaves badly, which is worse than not doing it at
all. So each word is drawn with its own horizontal scale (`Tz`), solved against
Adobe's Helvetica metrics so the rendered advance equals the width of the box
the OCR engine reported. There is a test that asserts exactly that, and a
`debugVisibleText` flag that paints the layer in red so you can look at it.

## Usage

```dart
import 'dart:io';
import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';

final pdf = SearchablePdf(title: 'Invoice 2026-0042')
  ..addPage(SearchablePage(
    image: PdfImage.decode(File('scan.jpg').readAsBytesSync()),
    // Boxes in image pixels, origin top-left — what every OCR engine gives you.
    words: [
      PdfWord('Invoice', PdfRect(120, 240, 310, 288)),
      PdfWord('2026-0042', PdfRect(322, 240, 560, 288)),
    ],
    dpi: 300,
  ));

File('scan.pdf').writeAsBytesSync(pdf.build());
```

Run `dart run example/searchable_pdf_example.dart` for a complete file you can
open, and `pdftotext -layout out.pdf -` to see the text come back out.

## Images

JPEG and PNG are embedded **without re-encoding**: a JPEG becomes a `DCTDecode`
stream and a PNG's `IDAT` payload becomes a `FlateDecode` stream with a PNG
predictor, which is the same compression PDF already speaks. Your scan never
loses a generation of quality, and this package needs no image codec.

Rejected with an explicit reason, rather than silently mangled: palette PNGs,
PNGs with an alpha channel, interlaced PNGs, CMYK JPEGs.

## What it does not do

Stated plainly, because a document format is full of things a library can
pretend to support:

- **One font, Helvetica, WinAnsi-encoded.** That covers Spanish, English,
  French, German, Italian and Portuguese. Greek, Cyrillic, Arabic and CJK need
  an embedded TrueType font with `Identity-H`; unencodable characters become
  `?` and are reported through `onWarning`, never dropped in silence.
- No encryption, no incremental update, no linearisation, no tagged-PDF
  structure tree. Marked in the source with the upgrade path.
- No layout analysis. It writes the boxes you give it, faithfully.

## Verification status

| Viewer | Status |
|---|---|
| Poppler (`pdftotext -layout`) | verified, in CI, on every commit |
| Chrome / pdf.js | **not verified yet** — planned for week 4, see the repository plan |
| Adobe Acrobat | **not verified** — see `UNVERIFIED.md` in the repository |
| macOS Preview | **not verified** — no macOS machine in the project |

We do not claim viewers we have not run.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa), an on-device
document capture, rectification and OCR stack for Flutter.
