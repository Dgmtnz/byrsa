<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

## 0.1.0 — unreleased

- One Dart API over Apple Vision and PP-OCR ONNX, delegating the
  platform-specific half to Ente's MIT `mobile_ocr`.
- Reading-order reconstruction in Dart, identical on both platforms and
  unit-tested.
- Word boxes rather than block polygons, so a searchable PDF's selection lines
  up with the image.

Not publishable to pub.dev until `mobile_ocr` is published there; see the
pubspec and `docs/upstream/mobile-ocr-pub-dev.md`. No accuracy figure is
claimed until the benchmark has run on hardware.
