<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# mobile_ocr: please publish to pub.dev

<!-- internal -->
**Repository:** `github.com/ente-io/mobile_ocr`
**Version examined:** `1.0.0` at `HEAD`, re-verified 2026-09-14
**Status:** draft, ready to file

> **Re-verified 2026-09-14, and one of the four asks was wrong.** The first
> draft listed "a `LICENSE` file at the package root" as missing. It is not
> missing — MIT, © 2025 Laurens Priem, at the root. Removed. The README also
> already says something about model licensing, so that ask changed shape too:
> from "please add a note" to "here is the audit that lets the note be specific".
> Two asks survive unchanged: no `repository:` field, and no `CHANGELOG.md`.
>
> This file now leads with something to give rather than something to ask.

<!-- /internal -->
---

## Note on framing

This used to be a blocker for us. It is not any more: `byrsa_ocr` now keeps the
API and the logic, and a separate `byrsa_ocr_mobile_ocr` holds the git
dependency, so our publishable package stays publishable.

That is deliberate in how the ask is written. Nobody should be asked to
rearrange their release process to unblock a stranger's milestone. What follows
is a request on behalf of the ecosystem, with an offer to do the work.

---

## Issue 1 — the licence trace, and one thing that looks off

**Title:** Licence audit of the three PP-OCR models, and a question about `cls.onnx`

*File this one first. It gives before it asks, and the second question is
plausibly a real defect in what you serve.*

We ship your plugin, so we had to answer "what licence are these weights under?"
for our own distribution. Rather than assume, we traced it. The result is yours
to use; the method is written up at
https://github.com/dgmtnz/byrsa/blob/main/docs/model-licence-audit.md

**The chain, for `det.onnx`, `rec.onnx`, `cls.onnx` and `ppocrv5_dict.txt`:**

- Upstream `PaddlePaddle/PaddleOCR` is **Apache-2.0** — "Copyright (c) 2016
  PaddlePaddle Authors" — added in the initial commit `bc93c549f` on 2020-05-08,
  before any PP-OCR weights existed. Touched twice since; we read both diffs, and
  neither changed a term.
- For detection and recognition this is **not an inference**: PaddlePaddle's own
  Hugging Face model cards (`PP-OCRv5_mobile_det`, `PP-OCRv5_mobile_rec`) declare
  `license: apache-2.0` in their front matter, so the grant attaches to the
  weights themselves.
- **No root `NOTICE`** in PaddleOCR, and we checked the artefacts: no
  `producer_name`, no `metadata_props`, no embedded copyright string. So the
  Apache-2.0 obligation reduces to shipping the licence text and attributing
  PaddleOCR. §4(b), §4(c) and §4(d) do not activate unless someone modifies the
  weights — quantising them would activate §4(b).
- **What does not close, and we say so rather than rounding it off:** PP-OCRv5's
  training data is undisclosed. The paper describes a 44M-sample bootstrap set
  and a 22.6M-sample final set without naming a corpus. Nobody outside Baidu can
  rule out an inherited restriction.

So your README's "derived from PaddleOCR and follow their licensing terms" can
become "Apache-2.0", which is a much better sentence for anyone auditing a
downstream app. Happy to send that as a patch.

### The question: `cls.onnx` does not look like it belongs with the other two

Before reading anything on the web we fingerprinted the three files you serve
from `models.ente.io/PP-OCRv5/` (ONNX is protobuf, so the identity fields read
without a library). `cls.onnx` differs from its siblings on every axis that
tracks the export toolchain:

| | `det.onnx` | `cls.onnx` | `rec.onnx` |
|---|---|---|---|
| IR version | 7 | **6** | 7 |
| Opset | 14 | **11** | 14 |
| Graph name | `PaddlePaddle Graph in PIR mode` | **`Model from PaddlePaddle.`** | `PaddlePaddle Graph in PIR mode` |
| Dim naming | `DynamicDimension.N` | **`p2o.DynamicDimension.N`** | `DynamicDimension.N` |
| Output name | `fetch_name_0` | **`softmax_0.tmp_0`** | `fetch_name_0` |
| BatchNorm layers | 0 (folded) | **35 (unfolded)** | 0 (folded) |
| Output shape | `[N,1,H,W]` | **`[N,2]`** | `[N,T,18385]` |

`det` and `rec` are PaddlePaddle 3.x PIR-mode exports. `cls` is a legacy
paddle2onnx export (`p2o.` is that tool's own namespace) with unfolded BatchNorm
and fluid-era variable naming — and it emits **two** classes, where PP-OCRv5's
own orientation model is PP-LCNet-based and emits four.

Our reading is that `cls.onnx` is the older `ch_ppocr_mobile_v2.0_cls` angle
classifier, which PaddleOCR still carries and reuses across versions. **We have
labelled that as inference, not fact** — we have not exported the upstream
checkpoint to compare.

Two reasons it is worth your time:

1. If it is the v2.0 classifier, serving it under a `PP-OCRv5/` path with
   `MODEL_VERSION = "pp-ocrv5-202410"` sends downstream auditors to the wrong
   model card. We had to trace it separately once we noticed.
2. If it is *meant* to be a v5-era model, then something in the export pipeline
   picked up a stale checkpoint, which is worth knowing.

**Could you say which checkpoint it was exported from?** One sentence from you
closes a row that would otherwise cost us an afternoon of paddle2onnx.

(For completeness: your `ModelManager.kt` pins `d7fe3ea7…`, `bf66820f…`,
`f4bb5370…` and `d1979e9f…`. We independently hashed all four from
`models.ente.io` and every one matches. And `rec.onnx`'s 18,385 output classes
are exactly `ppocrv5_dict.txt`'s 18,383 entries plus the CTC blank plus the
appended space — the pair is internally consistent.)

---

## Issue 2 — publishing

**Title:** Publish `mobile_ocr` to pub.dev

`mobile_ocr` is, as far as I can tell, the only maintained Flutter plugin that
does on-device OCR on both platforms **without Google Play Services** — Apple
Vision on iOS, PP-OCRv5 through ONNX Runtime on Android, models downloaded and
checksum-verified at runtime. For anyone shipping through F-Droid or onto
de-Googled devices that combination is currently unique, and the usual
alternative, ML Kit, is not an alternative at all.

It is not on pub.dev, and that has a consequence beyond convenience: **pub.dev
rejects packages that declare git dependencies**. So the plugin can be used by
applications, but nothing built on top of it can itself be published. Anyone who
wants to offer, say, a reusable searchable-PDF pipeline over it ends up either
vendoring your code or shipping something nobody can `pub add`. Both outcomes
are worse for you than the alternative.

Concretely, publishing needs three small things — checked against `HEAD` on
2026-09-14, not against memory:

- a **`repository:`** field in `pubspec.yaml` pointing here. `homepage:`
  currently points at `laurenspriem/mobile_ocr`, so pub.dev would send everyone
  to a personal fork rather than to `ente-io`;
- a **`CHANGELOG.md`**, which the package does not yet have;
- a **specific licence sentence for the models.** The README currently says the
  ONNX models "are derived from PaddleOCR and follow their licensing terms",
  which is true but leaves every downstream auditor to redo the trace. Issue 1
  above does that work: it is Apache-2.0, and for det and rec that is a grant
  quoted off PaddlePaddle's own model cards rather than an inference. The honest
  version of the sentence also names the one thing that does not close — the
  training corpus is undisclosed.

**I would be glad to send a pull request with all three.** Say the word and it
will be open within the day.

### A separate heads-up, worth its own issue

Building an application that depends on `mobile_ocr` with Flutter 3.47 prints:

```
Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): mobile_ocr
Future versions of Flutter will fail to build if your app uses plugins that
apply KGP.
```

Today it is a warning. When it becomes an error, every application depending on
`mobile_ocr` stops building at once, and the fix is in the plugin rather than in
any of them. Flutter's migration guide for plugin authors is
[here](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).
Happy to send that patch too.

### What I am building

An Apache-2.0 set of Flutter packages for document capture, rectification and
searchable-PDF export, targeting F-Droid, with a public benchmark of fifty real
documents. `mobile_ocr` is the OCR engine, credited as such in the README, the
package description and the funding application behind it. Any fix I make to it
comes back here as a patch, published or not.
