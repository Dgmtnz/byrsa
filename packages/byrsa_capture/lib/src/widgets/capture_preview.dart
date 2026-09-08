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
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Texture(textureId: textureId),
            QuadOverlay(quad: detection?.quad, color: overlayColor),
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
