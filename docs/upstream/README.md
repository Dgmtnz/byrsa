<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Upstream

Byrsa is built on other people's free software, and the standing rule is that a
problem we find in a dependency goes back to that dependency rather than into a
private fork. A fork solves it for us; a patch solves it for everyone who ever
tries the same thing.

Each file here is an issue or pull request written out in full, with the
evidence attached, ready to post. They are drafted here first so that the
reasoning is versioned alongside the code that depends on it.

| # | Project | What | Status |
|---|---|---|---|
| [1](doclens-play-services.md) | `doclens` | Play Services is an unconditional dependency, which makes the plugin unusable for F-Droid | draft, to file |
| [2](mobile-ocr-pub-dev.md) | `mobile_ocr` | Not on pub.dev, so nothing that depends on it can be published there | draft, to file |
