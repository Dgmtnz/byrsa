// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Lets the user drag the four corners of a page onto the paper, over the
/// original frame.
///
/// This is not a power-user extra. Edge detection fails on low-contrast paper,
/// on cluttered desks and in bad light, and without a way to fix it by hand the
/// only recovery is to retake the photograph — which usually fails the same way
/// for the same reason.
///
/// It always works on the **original** frame, never on a warped one: correcting
/// corners on an already-rectified image would be correcting a correction.
class CornerEditorScreen extends StatefulWidget {
  const CornerEditorScreen({
    required this.imagePath,
    required this.initialQuad,
    super.key,
  });

  final String imagePath;
  final CaptureQuad initialQuad;

  @override
  State<CornerEditorScreen> createState() => _CornerEditorScreenState();
}

class _CornerEditorScreenState extends State<CornerEditorScreen> {
  late CaptureQuad _quad = widget.initialQuad;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adjustCorners),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.reset,
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() => _quad = CaptureQuad.full),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_quad),
            child: Text(l10n.save),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              // The overlay works in normalised coordinates, so it has to sit
              // exactly on the image and not on the letterboxed box around it.
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.fill,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 64),
                    ),
                    QuadOverlay(
                      quad: _quad,
                      onChanged: (quad) => setState(() => _quad = quad),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.adjustCornersHelp,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
