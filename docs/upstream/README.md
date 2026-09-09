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
| [1](doclens-play-services.md) | `doclens` | Play Services is an unconditional dependency, which makes the plugin unusable for F-Droid. Two pull requests, the first of which removes a dependency without removing a feature | draft, to file |
| [2](mobile-ocr-pub-dev.md) | `mobile_ocr` | Not on pub.dev, so nothing that depends on it can be published there; and it applies the Kotlin Gradle Plugin, which Flutter will stop accepting | draft, to file |
| [3](onnxruntime-flutter-compilesdk.md) | `onnxruntime_flutter` | `compileSdkVersion 33` breaks every release build against current AndroidX, and its vendored `libonnxruntime.so` collides with the official AAR | draft, to file |

Neither is a blocker for Byrsa any more, and both are written that way on
purpose. `byrsa_capture` carries its own detector; `byrsa_ocr` keeps the git
dependency quarantined in a separate package. Asking from a position of not
needing the favour makes for a better patch and a better ask — and it means
neither milestone depends on a stranger's calendar.
