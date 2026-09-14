<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: GPL-3.0-or-later
-->

# The browser demo

Byrsa's restoration, running entirely in a browser. Not a reimplementation: it
imports `package:byrsa_restore` and calls the same `ClassicalRestore` the
Android application calls.

```
cd demo
flutter build web --release --no-web-resources-cdn
```

Then serve `build/web` from anywhere static — GitHub Pages, a plain directory.

**`--no-web-resources-cdn` is not optional.** Without it Flutter fetches
CanvasKit from `gstatic.com`, and a page whose whole argument is that nothing
leaves your tab cannot begin by asking Google for seven megabytes. With it, a
load plus a full restoration makes **zero external requests** — instrumented,
not assumed.

## What it shows, and what it cannot

Six sample pages from `harness/dataset/synthetic`, each damaged a different way,
plus the three page filters. Before and after, with a handle you drag across.

It does **not** do OCR, and says so on the page: the recogniser is native code
on Android and iOS, so a browser has nothing to run.

## Why this directory earned its place

It found a bug that 200 tests could not. `byrsa_restore` was silently wrong on
the web, because `>>` on a negative int is an arithmetic shift on the Dart VM
and an unsigned 32-bit one under dart2js. See `DECISIONS.md` D-046, and
`tool/check_web_parity.sh`, which is now the guard.
