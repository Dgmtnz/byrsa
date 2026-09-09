<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

## 0.1.0 — unreleased

- A stable API for on-device OCR, with no engine and no Flutter in it. Engines
  are registered by the application; `byrsa_ocr_mobile_ocr` is the one Byrsa
  ships.
- Reading-order reconstruction, identical whatever the engine returned and in
  whatever order, unit-tested.
- Types with no `dart:ui` in them, so results feed a pure-Dart PDF writer.

No accuracy figure is claimed until the benchmark has run on hardware.
