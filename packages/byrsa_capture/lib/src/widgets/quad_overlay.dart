// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../quad.dart';

/// Draws the detected page outline, and optionally lets the user drag its
/// corners.
///
/// Manual corner adjustment is not a power-user extra. Detection fails on
/// low-contrast paper and cluttered desks, and without a way to fix it by hand
/// the only recovery is to retake the photograph.
class QuadOverlay extends StatefulWidget {
  const QuadOverlay({
    required this.quad,
    super.key,
    this.onChanged,
    this.color,
    this.handleRadius = 22,
  });

  final CaptureQuad? quad;

  /// When non-null, corners become draggable and every move calls this.
  final ValueChanged<CaptureQuad>? onChanged;

  final Color? color;

  /// Touch radius of a corner handle, in logical pixels.
  ///
  /// Deliberately larger than the drawn handle: a 22-pixel target is roughly
  /// the smallest a thumb hits reliably, and the drawn circle would look clumsy
  /// at that size.
  final double handleRadius;

  @override
  State<QuadOverlay> createState() => _QuadOverlayState();
}

class _QuadOverlayState extends State<QuadOverlay> {
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final quad = widget.quad;
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    if (quad == null) return const SizedBox.expand();

    final painter = CustomPaint(
      painter: _QuadPainter(
        quad: quad,
        color: color,
        showHandles: widget.onChanged != null,
        activeCorner: _dragging,
      ),
      child: const SizedBox.expand(),
    );

    if (widget.onChanged == null) return painter;

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) => setState(() => _dragging =
            _nearestCorner(quad, details.localPosition, constraints)),
        onPanUpdate: (details) {
          final index = _dragging;
          if (index == null) return;
          widget.onChanged!(quad.withCorner(
            index,
            CapturePoint(
              (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
              (details.localPosition.dy / constraints.maxHeight)
                  .clamp(0.0, 1.0),
            ),
          ));
        },
        onPanEnd: (_) => setState(() => _dragging = null),
        onPanCancel: () => setState(() => _dragging = null),
        child: painter,
      ),
    );
  }

  int? _nearestCorner(
      CaptureQuad quad, Offset position, BoxConstraints constraints) {
    var best = widget.handleRadius;
    int? found;
    for (var i = 0; i < 4; i++) {
      final corner = Offset(
        quad.corners[i].x * constraints.maxWidth,
        quad.corners[i].y * constraints.maxHeight,
      );
      final distance = (corner - position).distance;
      if (distance < best) {
        best = distance;
        found = i;
      }
    }
    return found;
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.quad,
    required this.color,
    required this.showHandles,
    this.activeCorner,
  });

  final CaptureQuad quad;
  final Color color;
  final bool showHandles;
  final int? activeCorner;

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad.corners
        .map((c) => Offset(c.x * size.width, c.y * size.height))
        .toList();

    final path = Path()..addPolygon(points, true);
    canvas
      ..drawPath(path, Paint()..color = color.withValues(alpha: 0.18))
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );

    if (!showHandles) return;
    for (var i = 0; i < points.length; i++) {
      final active = i == activeCorner;
      canvas
        ..drawCircle(points[i], active ? 14 : 10, Paint()..color = Colors.white)
        ..drawCircle(
          points[i],
          active ? 14 : 10,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.quad != quad ||
      old.activeCorner != activeCorner ||
      old.color != color;
}
