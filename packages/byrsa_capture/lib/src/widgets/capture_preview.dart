// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../capture_result.dart';
import '../controller.dart';
import 'quad_overlay.dart';

/// Camera preview with the detected page outlined on top of it.
///
/// Everything about how it looks is yours: this is a `Texture` plus an overlay,
/// not a screen. The package ships no scanner UI on purpose — an opinionated
/// full-screen scanner is exactly the thing nobody can reuse.
class CapturePreview extends StatelessWidget {
  const CapturePreview({
    required this.controller,
    super.key,
    this.overlayColor,
    this.showHint = true,
    this.hintBuilder,
  });

  final ByrsaCaptureController controller;
  final Color? overlayColor;

  /// Whether to show the guidance line under the preview.
  final bool showHint;

  /// Replaces the default guidance text — the place to put your own wording
  /// and your own translations.
  final String Function(BuildContext, CaptureHint)? hintBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final textureId = controller.textureId;
        if (textureId == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final detection = controller.latest;
        final geometry = controller.previewGeometry;

        // The camera's buffer is neither upright nor the shape of the box it is
        // given. Rotating and letterboxing it is what puts the image into the
        // same coordinate system as the detected corners, which the platform
        // side already reports upright — and the first run on a device is what
        // showed the cost of not doing it: a stretched preview with an outline
        // that looked mirrored.
        //
        // `contain`, never `cover`: cropping to fill the screen would move the
        // corners off the page they outline, and an outline that does not sit
        // on the document is worse than a letterbox.
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: _sized(
                geometry,
                Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _rotated(geometry, Texture(textureId: textureId)),
                    QuadOverlay(quad: detection?.quad, color: overlayColor),
                  ],
                ),
              ),
            ),
            if (showHint && detection != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      (hintBuilder ?? _defaultHint)(context, detection.hint),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Constrains the preview to the camera's real shape, once it is known.
  ///
  /// Before the first frame's geometry arrives there is nothing to constrain
  /// it to, and guessing would produce exactly the wrong-shaped preview this
  /// exists to prevent.
  static Widget _sized(CapturePreviewGeometry? geometry, Widget child) =>
      geometry == null
          ? child
          : AspectRatio(aspectRatio: geometry.displayAspectRatio, child: child);

  static Widget _rotated(CapturePreviewGeometry? geometry, Widget child) =>
      geometry == null || geometry.quarterTurns == 0
          ? child
          : RotatedBox(quarterTurns: geometry.quarterTurns, child: child);

  /// English fallback wording.
  ///
  /// Deliberately short and actionable: it says what to do, not what failed.
  /// Translate it by passing [hintBuilder]; the package carries no `.arb` files
  /// so that it does not force a localisation setup on its users.
  static String _defaultHint(BuildContext context, CaptureHint hint) =>
      switch (hint) {
        CaptureHint.noDocument => 'Point at a document',
        CaptureHint.tooFar => 'Move closer',
        CaptureHint.cropped => 'Fit the whole page in the frame',
        CaptureHint.moving => 'Hold still',
        CaptureHint.blurry => 'Hold still — still focusing',
        CaptureHint.tooDark => 'Not enough light',
        CaptureHint.ready => 'Ready',
      };
}
