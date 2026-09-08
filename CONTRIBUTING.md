<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Contributing to Byrsa

## Licensing of contributions

- Anything under `packages/` and `harness/` is **Apache-2.0**.
- Anything under `app/` is **GPL-3.0-or-later**.
- Documentation is **CC-BY-4.0**; trivial config and data files are **CC0-1.0**.

Every file needs an SPDX header, or an entry in `REUSE.toml` when the format has no
comment syntax. `reuse lint` runs in CI and is not advisory.

## Claims discipline

This is the rule that matters most in a research project.

1. **Never state a result you have not measured on the platform you name.**
2. Anything unmeasured goes in [`UNVERIFIED.md`](UNVERIFIED.md), with the machine
   required and the exact command that would settle it.
3. Benchmarks publish unfavourable results too. A benchmark that only ever looks good
   is not a benchmark.

## Commit hygiene

- Conventional-ish subject lines: `capture: `, `restore: `, `ocr: `, `pdf: `, `app: `,
  `harness: `, `docs: `, `ci: `.
- One logical change per commit.
- No precompiled binaries in the repository — F-Droid requires builds from source, and
  so do we. ONNX models are downloaded at runtime or bundled by a separate build
  flavour, never committed.
