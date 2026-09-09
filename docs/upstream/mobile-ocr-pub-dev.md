<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# mobile_ocr: please publish to pub.dev

**Repository:** `github.com/ente-io/mobile_ocr`
**Status:** draft, ready to file

---

## Note on framing

This used to be a blocker for us. It is not any more: `byrsa_ocr` now keeps the
API and the logic, and a separate `byrsa_ocr_mobile_ocr` holds the git
dependency, so our publishable package stays publishable (repository decision
D-027).

That is deliberate in how the ask is written. Nobody should be asked to
rearrange their release process to unblock a stranger's milestone. What follows
is a request on behalf of the ecosystem, with an offer to do the work.

---

## Issue text

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

Concretely, publishing needs four small things:

- a `repository:` field in `pubspec.yaml` pointing at this repository —
  `homepage:` currently points at a personal fork;
- a `LICENSE` file at the package root; the README says MIT;
- a `CHANGELOG.md`;
- a short README note on the licensing of the PaddleOCR-derived models, which
  are downloaded rather than bundled and are worth stating explicitly for
  downstream auditors. We track them per-model and currently mark each one
  `UNAUDITED` until a human has read its model card, which is more caution than
  most people will apply.

**I would be glad to send a pull request with all four.** Say the word and it
will be open within the day.

### What I am building

An Apache-2.0 set of Flutter packages for document capture, rectification and
searchable-PDF export, targeting F-Droid, with a public benchmark of fifty real
documents. `mobile_ocr` is the OCR engine, credited as such in the README, the
package description and the funding application behind it. Any fix I make to it
comes back here as a patch, published or not.
