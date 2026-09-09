<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

## 0.1.0 — unreleased

- Split out of `byrsa_ocr`, so that the API package stays free of the git
  dependency pub.dev refuses.
- Blocks split into words, from character boxes where available and by
  proportion where not.

Android compiles. iOS has never been compiled — there is no macOS machine in
the project — and no recognition figure is claimed on either.
