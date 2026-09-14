<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Auditing a model's licence

Plan §9 requires the licence of every model to be audited separately, because a
permissive licence on the code that exports or runs a model says nothing about
the weights inside it. This is the method, written down after doing it properly
once so that the next model gets the same treatment rather than a glance. Two
models have now been through it: DocShadow-SD7K and the PaddleOCR set.

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
already rejected it on cost. It is written down because the method transfers,
and the next section is where it transferred to.

## Worked example: the three PaddleOCR models — done 2026-09-14

The audit this document was written to enable. Each numbered step is the one
above, in order.

**1 · The upstream repository's licence, quoted.** `PaddlePaddle/PaddleOCR` is
Apache-2.0: "Apache License / Version 2.0, January 2004", with "Copyright (c)
2016 PaddlePaddle Authors. All Rights Reserved." No commercial or research-only
clause anywhere in the text.

**2 · The weights carry a licence of their own — and here the chain is stronger
than DocShadow's.** PaddlePaddle publishes official model cards on Hugging Face
whose YAML front matter reads `license: apache-2.0`:

| Model card | Declared | Created |
|---|---|---|
| `PaddlePaddle/PP-OCRv5_mobile_det` | `apache-2.0` | 2025-06-04 |
| `PaddlePaddle/PP-OCRv5_mobile_rec` | `apache-2.0` | 2025-06-04 |
| `PaddlePaddle/PP-LCNet_x1_0_doc_ori` | `apache-2.0` | 2025-06-06 |
| `PaddlePaddle/PP-LCNet_x0_25_textline_ori` | `apache-2.0` | 2025-06-12 |

For DocShadow, MIT reaching the weights was an *inference* from a repo-wide
licence. Here the publisher attaches the licence **to the weights**, so det and
rec rest on a quoted grant rather than an inference. That is a materially better
position and the record should say which of the two it is.

No card exists under `PaddlePaddle` for a two-class angle classifier, so the
model Byrsa ships as `cls.onnx` does **not** get this upgrade — see step 5.

**3 · Does the licence reach the weights, on timing?** Yes, as strongly as this
test can come out. The `LICENSE` file was added in PaddleOCR's **initial commit,
`bc93c549f`, 2020-05-08** — before any PP-OCR weights existed. It has been
touched twice since, and both diffs were read rather than assumed: `2608df32a`
(2022-11-30) added the copyright line and filled in the appendix placeholder,
and `b9da97bea` (2025-05-20) removed the duplicate line from the top. **Neither
changed a term.** A licence that predates every release, unmodified in substance,
is the best answer step 3 can produce.

**4 · The training data — and this is the step that does not close.**
PP-OCRv5's training data is **not disclosed**. The model card says nothing about
data at all. The PP-OCRv5 paper describes a "bootstrap recognition model" trained
on "an initial 44M-sample dataset" and a final 22.6M-sample set "strategically
assembled", but names no corpus and identifies no source as public or in-house.

Apply this document's own rule and do not round that off. An undisclosed corpus
is not a clean corpus; it is an unanswerable question. Nobody outside Baidu can
rule out an inherited restriction, and the record has to say so rather than
report step 4 as passed.

**5 · What the redistributor actually licenses.** `ente-io/mobile_ocr` is MIT,
"Copyright (c) 2025 Laurens Priem". A recursive listing of its git tree returns
**no `.onnx` file at all** — the models are served from `models.ente.io`, outside
the tree its LICENSE governs. Structurally identical to
`fabio-sim/DocShadow-ONNX-TensorRT`: the redistributor's licence covers its own
code and adds nothing to the weights it points at.

What the repository does supply is corroboration of identity.
`android/src/main/kotlin/io/ente/mobile_ocr/ModelManager.kt` pins the same three
digests Byrsa pins, and names a fourth asset, `ppocrv5_dict.txt`, that Byrsa's
manifest was missing.

### What Byrsa must actually do

Apache-2.0 obligations, resolved against what was measured rather than recited:

- **§4(a), include the licence.** Ship the Apache-2.0 text alongside the models
  and attribute PaddleOCR. This is the real obligation.
- **§4(b), state changes.** Byrsa does not modify the weights, so nothing to
  state. If a model is ever quantised, this clause activates.
- **§4(c), retain notices.** The artefacts were checked: no `producer_name`, no
  `metadata_props`, no embedded copyright string. There are no notices to retain.
- **§4(d), NOTICE propagation.** PaddleOCR's tree carries **no root `NOTICE`
  file** — only `deploy/ios_demo/NOTICE`, which governs a demo Byrsa does not
  use. This clause does not activate.

### A third trap, added by this audit

**A version string is not a provenance claim.** `mobile_ocr` labels its download
set `pp-ocrv5-202410`, dated October 2024 — eight months before PaddlePaddle
published the PP-OCRv5 model cards in June 2025. The label is Ente's own
versioning and proves nothing either way, but it is exactly the kind of string
that gets quoted as a date. It is recorded as an open question, not as evidence.

And the sharper lesson, which cost nothing and found the most:
**fingerprint the artefact before you research it.** Walking the three ONNX files
took minutes and revealed that one of them does not match its own description in
`models.json` — a discrepancy no amount of reading model cards would have
surfaced, because the reading would have been about the wrong model.
