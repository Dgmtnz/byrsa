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

## A 404 can be your query, not the resource

The most useful thing this audit produced was a correction to itself. The first
pass reported the SD7K dataset licence as "not found", having tried the
publisher's API and received a 404. An adversarial check found that the same
endpoint returns HTTP 200 when the slug's slash is percent-encoded:

```
https://openxlab.org.cn/datasets/api/v2/datasets/lkljty/ShadowDocument7K    → 404
https://openxlab.org.cn/datasets/api/v2/datasets/lkljty%2FShadowDocument7K → 200
```

And the record says, verbatim, `"license":[{"name":{"en":"MIT"}}]`, publisher
"Department of Computer and Information Science, University of Macau".

So the licence was declared all along, on the page the project's own README
designates as the download. "Not found" had become "does not exist" somewhere
between the tool and the conclusion, and it would have gone into the record as
an unresolved risk.

**Rule: a negative result about a licence needs the same scepticism as a
positive one.** Before writing "not found", check that the thing doing the
looking worked.

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
  Chen", added in the initial commit on 2023-07-16 and never modified since —
  months before the weights were released on 2023-12-17. One licence file in
  the whole tree; no model card, no NOTICE, nothing under `models/`.
- No non-commercial or research-only clause in the licence, the README, either
  release body, or the paper. The README's citation request is a courtesy, not
  a condition.
- The weights release body reads, in full: "Pretrained weights of FSENet". So
  the MIT grant reaching the weights is an **inference**, and the record says
  inference.
- `fabio-sim/DocShadow-ONNX-TensorRT` is MIT over its repository tree; the
  `.onnx` files are release assets outside that tree, so its licence adds
  nothing to the weights it redistributes.
- **SD7K dataset: MIT**, declared by the publisher on the OpenXLab listing the
  README designates as the download. Established only after the first pass
  reported it missing — see above.

The artefact's identity was confirmed independently: the release asset hashes
to `8c09b932…d14b049` at 120,041,674 bytes, matching the pin.

None of this decides whether Byrsa ships the model — `DECISIONS.md` D-039
already rejected it on cost. It is written down because the method transfers
and the PaddleOCR audit still has to happen.
