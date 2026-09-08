// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture_result.dart';
import 'platform_interface.dart';
import 'quad.dart';
import 'stability.dart';

/// Drives a capture session: preview, live detection, auto-capture, and the
/// batch of pages collected so far.
///
/// A [ChangeNotifier] rather than anything cleverer, because the whole point of
/// this package is that it drops into whatever state management the host app
/// already uses.
class ByrsaCaptureController extends ChangeNotifier {
  ByrsaCaptureController({
    ByrsaCapturePlatform? platform,
    CaptureOptions options = const CaptureOptions(),
    QuadSmoother? smoother,
    StabilityTracker? stability,
    this.autoCapture = true,
  })  : _platform = platform ?? ByrsaCapturePlatform.instance,
        _options = options,
        _smoother = smoother ?? QuadSmoother(),
        _stability = stability ?? StabilityTracker();

  final ByrsaCapturePlatform _platform;
  final CaptureOptions _options;
  final QuadSmoother _smoother;

  /// Decides when the scene is worth capturing.
  ///
  /// This lives in Dart, not in the two native implementations. The platform
  /// side reports what it can see — a quad, a focus measure, a brightness —
  /// and every judgement made from that is taken once, here, where it is unit
  /// tested on a laptop and identical on both platforms.
  final StabilityTracker _stability;

  /// Whether the controller takes the picture by itself once the scene is
  /// steady, sharp and well lit.
  bool autoCapture;

  StreamSubscription<CaptureDetection>? _subscription;
  int? _textureId;
  CaptureDetection? _latest;
  bool _capturing = false;
  final List<CapturedPage> _pages = <CapturedPage>[];

  /// Texture to hand to a `Texture` widget. Null until [start] completes.
  int? get textureId => _textureId;

  /// The most recent detection, already smoothed.
  CaptureDetection? get latest => _latest;

  /// Pages captured in this session, in order.
  List<CapturedPage> get pages => List<CapturedPage>.unmodifiable(_pages);

  bool get isRunning => _textureId != null;

  Future<void> start() async {
    if (isRunning) return;
    _textureId = await _platform.start(_options);
    _subscription = _platform.detections.listen(_onDetection);
    notifyListeners();
  }

  void _onDetection(CaptureDetection detection) {
    final smoothed = _smoother.add(detection.quad);
    final verdict = _stability.update(
      quad: smoothed,
      frameInterval: _frameInterval,
      sharpness: detection.sharpness,
      brightness: detection.brightness,
    );

    _latest = CaptureDetection(
      quad: smoothed,
      hint: verdict.hint,
      sharpness: detection.sharpness,
      brightness: detection.brightness,
      stableFor: verdict.stableFor,
    );
    notifyListeners();

    if (autoCapture && verdict.hint == CaptureHint.ready && !_capturing) {
      unawaited(capture());
    }
  }

  Duration get _frameInterval => Duration(
        microseconds: (1000000 / _options.detectionsPerSecond).round(),
      );

  /// Takes a page and adds it to the batch.
  ///
  /// Re-entrant calls are dropped rather than queued: auto-capture and a
  /// shutter tap arriving together should produce one page, not two.
  Future<CapturedPage?> capture() async {
    if (_capturing) return null;
    _capturing = true;
    notifyListeners();
    try {
      final page = await _platform.capture();
      _pages.add(page);
      // Start the stability clock again, so a second page needs the scene to
      // settle again rather than firing immediately on the same frame.
      _smoother.reset();
      _stability.reset();
      return page;
    } finally {
      _capturing = false;
      notifyListeners();
    }
  }

  /// Replaces the corners of [index] and re-warps **from the original frame**.
  Future<void> adjustCorners(int index, CaptureQuad quad) async {
    final page = _pages[index];
    final rectified = await _platform.rectify(
      imagePath: page.originalPath,
      quad: quad,
    );
    _pages[index] = page.copyWith(quad: quad, rectifiedPath: rectified);
    notifyListeners();
  }

  void removePage(int index) {
    _pages.removeAt(index);
    notifyListeners();
  }

  void reorderPages(int oldIndex, int newIndex) {
    final page = _pages.removeAt(oldIndex);
    _pages.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, page);
    notifyListeners();
  }

  Future<void> setTorch({required bool on}) => _platform.setTorch(on: on);

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_textureId != null) {
      await _platform.stop();
      _textureId = null;
    }
    _smoother.reset();
    _stability.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
