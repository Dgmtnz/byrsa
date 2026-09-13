<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Auditing a model's licence

Plan §9 requires the licence of every model to be audited separately, because a
permissive licence on the code that exports or runs a model says nothing about
the weights inside it. This is the method, written down after doing it properly
once, so the PaddleOCR models — still `UNAUDITED` in `models.json` — get the
same treatment rather than a glance.

## What has to be established

1. **The original research repository's licence**, quoted, not summarised.
2. **Whether the weights carry a licence of their own.** Usually they do not,
   and that absence is a finding, not a pass.
3. **Whether the repo-wide licence plausibly reaches the weights.** Check when
   the licence was added relative to when the weights were published.
4. **The training dataset's licence.** Weights trained on restricted data can
   inherit the restriction.
5. **What the redistributing repository actually licenses** — its conversion
   code, or the binaries it hosts.

## Two traps this project walked up to

Both were found while tracing DocShadow-SD7K, and both would have produced a
confident wrong answer.

**The project page's Creative Commons notice is not the dataset's licence.**
Academic project pages are overwhelmingly built from the Academic Project Page
Template, which ships with a CC BY-SA 4.0 footer *about the web page*. The
DocShadow page still carries the template's unedited lorem ipsum, which is the
tell. Reading that footer as the dataset licence is an easy mistake to make and
an expensive one to ship.

**The arXiv licence covers the PDF.** "arXiv.org perpetual non-exclusive
license" grants arXiv the right to distribute the paper. It licenses nothing
about code, weights or data.

## Worked example: DocShadow-SD7K

- Upstream `CXH-Research/DocShadow-SD7K`: plain MIT, "Copyright (c) 2023 Nick
  Chen", added in the initial commit on 2023-07-16 — five months before the
  weights were released on 2023-12-17. One licence file in the whole tree; no
  model card, no NOTICE, nothing under `models/`.
- No non-commercial or research-only clause in the licence, the README, either
  release body, or the paper. The README's citation request is a courtesy, not
  a condition.
- The weights release body reads, in full: "Pretrained weights of FSENet". So
  the MIT grant reaching the weights is an **inference**, and the record says
  inference.
- `fabio-sim/DocShadow-ONNX-TensorRT` is MIT over its repository tree; the
  `.onnx` files are release assets outside that tree, so its licence adds
  nothing to the weights it redistributes.
- **SD7K dataset licence: not found.** The OneDrive archives were not
  downloaded and OpenXLab's page is JavaScript-rendered, so this is unresolved
  rather than absent (`UNVERIFIED.md` U-37).

The artefact's identity was confirmed independently: the release asset hashes
to `8c09b932…d14b049` at 120,041,674 bytes, matching the pin.

None of this decides whether Byrsa ships the model — `DECISIONS.md` D-039
already rejected it on cost. It is written down because the method transfers
and the PaddleOCR audit still has to happen.
