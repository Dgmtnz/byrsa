<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

## 0.1.0 — unreleased

- Live edge detection and perspective correction on CameraX and AVFoundation,
  with no dependency on Google Play Services — asserted in CI against the built
  APK, not promised.
- Projective aspect-ratio recovery, so a page shot at an angle does not come
  out squashed, and an honest `null` for the tilt case that does not determine
  the answer.
- Batch capture, draggable corner correction that re-warps from the original
  frame, and auto-capture that refuses a blurred frame.

Android compiles and is untested on hardware. iOS is written in full and has
never been compiled: there is no macOS machine in the project, and no iOS claim
is made anywhere.
