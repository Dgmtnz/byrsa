<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_capture

Live document edge detection and perspective correction for Flutter, with **no
dependency on Google Play Services** — so what you build with it can ship on
F-Droid, on IzzyOnDroid, and on de-Googled devices.

CameraX on Android. AVFoundation and Vision on iOS. One symmetric Dart API.

## Why no Play Services

Every other Flutter document-scanner plugin we found pulls in ML Kit, and ML
Kit is delivered by Google Play Services. That is invisible from Dart — it is a
line in a Gradle file — and it is a hard blocker for a large class of Android
users, not an inconvenience.

So it is a test, not a promise:

```
tool/check_no_play_services.sh path/to/app.apk
```

It fails the build if a single `com.google.android.gms` class reaches the dex.
On the example application it reports zero, against 1717 `androidx.camera`
references.

## Frames stay native

Detection runs in the platform layer and **only four corners cross into Dart
per analysed frame**. Streaming camera frames into Dart is where a scanner's
battery and thermal budget go; this is the design decision that everything else
follows from.

## Usage

```dart
final controller = ByrsaCaptureController();
await controller.start();

// A Texture with the detected page outlined on top. No opinionated scanner
// screen: an opinionated full-screen scanner is the part nobody can reuse.
CapturePreview(controller: controller);

// Auto-capture fires when the page is steady, sharp, well lit and fully in
// frame. `controller.pages` is the batch.
await controller.capture();

// Corners corrected afterwards re-warp from the original frame, never from a
// previous warp.
await controller.adjustCorners(0, correctedQuad);
```

`QuadOverlay` with an `onChanged` callback gives you draggable corners.

## The interesting part is the geometry

A page photographed at an angle is a projection, so the ratio of the sides you
can see is **not** the ratio of the paper. Averaging the visible sides makes an
A4 sheet shot from 30° come out visibly squashed.

`CaptureQuad.projectiveAspectRatio` recovers the camera's focal length from the
four projected corners and the true ratio with it. It returns `null` for a shot
tilted about a single axis — where one pair of edges stays parallel in the
image and a whole family of pages projects to the same trapezoid, so the answer
is genuinely undetermined. `aspectRatioOrFallback` resolves that case with an
assumed phone focal length, which is a calibration constant you can override,
not a law.

All of that is pure Dart and unit-tested against a synthetic pinhole camera.

## What the Android detector does, and does not do

It scans inward from each edge of the frame, fits a line through the strongest
brightness step on each scan line, discards the scan lines that disagree, and
intersects the four lines.

That works when the page is the dominant bright region and roughly fills the
frame, which is what the capture guidance asks the user to do. It will miss a
small page on a busy desk, and it does not follow a curved edge. The ceiling is
written in the source with its upgrade path, and milestone M1's benchmark is
what decides whether the upgrade is worth its size.

## Platform status

| | Android | iOS |
|---|---|---|
| Written | yes | yes |
| Compiles | **verified** | not verified — no macOS machine |
| Measured | pending, on hardware | **no** |

No iOS number is claimed anywhere in this package, and none exists. See
`UNVERIFIED.md` in the repository root for the exact commands that would close
each row.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa).
