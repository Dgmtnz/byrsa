// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeCapturePlatform extends ByrsaCapturePlatform
    with MockPlatformInterfaceMixin {
  final StreamController<CaptureDetection> _controller =
      StreamController<CaptureDetection>.broadcast();

  int captureCount = 0;
  int rectifyCount = 0;
  Duration captureDelay = Duration.zero;

  void emit(CaptureDetection detection) => _controller.add(detection);

  @override
  Stream<CaptureDetection> get detections => _controller.stream;

  @override
  Future<int> start(CaptureOptions options) async => 7;

  @override
  Future<void> stop() async {}

  @override
  Future<CapturedPage> capture() async {
    captureCount++;
    if (captureDelay > Duration.zero) await Future<void>.delayed(captureDelay);
    return CapturedPage(
      originalPath: '/tmp/page-$captureCount.jpg',
      quad: CaptureQuad.full,
    );
  }

  @override
  Future<String> rectify({
    required String imagePath,
    required CaptureQuad quad,
    double? targetAspectRatio,
  }) async {
    rectifyCount++;
    return '$imagePath.rectified.jpg';
  }

  @override
  Future<void> setTorch({required bool on}) async {}

  @override
  Future<bool> isSupported() async => true;
}

CaptureDetection detection(CaptureHint hint) => CaptureDetection(
      quad: CaptureQuad.full,
      hint: hint,
      sharpness: 1,
      brightness: 1,
      stableFor: const Duration(seconds: 1),
    );

void main() {
  late FakeCapturePlatform platform;

  setUp(() {
    platform = FakeCapturePlatform();
    ByrsaCapturePlatform.instance = platform;
  });

  test('exposes the texture once started', () async {
    final controller = ByrsaCaptureController(autoCapture: false);
    expect(controller.isRunning, isFalse);
    await controller.start();
    expect(controller.textureId, 7);
  });

  test('collects pages into a batch, in order', () async {
    final controller = ByrsaCaptureController(autoCapture: false);
    await controller.start();
    await controller.capture();
    await controller.capture();
    expect(controller.pages.map((p) => p.originalPath),
        <String>['/tmp/page-1.jpg', '/tmp/page-2.jpg']);
  });

  test('takes one page when auto-capture and a tap arrive together', () async {
    // Both paths firing at once is the normal case, not a rare race: the user
    // taps exactly when the scene settles.
    final controller = ByrsaCaptureController();
    await controller.start();
    platform.captureDelay = const Duration(milliseconds: 20);

    platform.emit(detection(CaptureHint.ready));
    await Future<void>.delayed(Duration.zero);
    await controller.capture();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(platform.captureCount, 1);
  });

  test('does not auto-capture while the scene is still moving', () async {
    final controller = ByrsaCaptureController();
    await controller.start();
    platform.emit(detection(CaptureHint.moving));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(platform.captureCount, 0);
  });

  test('re-warps from the original frame when corners are corrected', () async {
    // Warping an already warped image is how a corrected page ends up soft.
    final controller = ByrsaCaptureController(autoCapture: false);
    await controller.start();
    await controller.capture();

    await controller.adjustCorners(0, CaptureQuad.full);
    expect(
        controller.pages.first.rectifiedPath, '/tmp/page-1.jpg.rectified.jpg');
    expect(platform.rectifyCount, 1);
  });

  test('reorders and removes pages', () async {
    final controller = ByrsaCaptureController(autoCapture: false);
    await controller.start();
    await controller.capture();
    await controller.capture();
    await controller.capture();

    controller.reorderPages(0, 3);
    expect(controller.pages.map((p) => p.originalPath).toList(),
        <String>['/tmp/page-2.jpg', '/tmp/page-3.jpg', '/tmp/page-1.jpg']);

    controller.removePage(1);
    expect(controller.pages.length, 2);
  });

  test('smooths the detections it publishes', () async {
    final controller = ByrsaCaptureController(
      autoCapture: false,
      smoother: QuadSmoother(smoothing: 0.5, jumpThreshold: 10),
    );
    await controller.start();

    const first = CaptureQuad(
      CapturePoint(0, 0),
      CapturePoint(1, 0),
      CapturePoint(1, 1),
      CapturePoint(0, 1),
    );
    const second = CaptureQuad(
      CapturePoint(0.2, 0.2),
      CapturePoint(1, 0),
      CapturePoint(1, 1),
      CapturePoint(0, 1),
    );
    platform
      ..emit(CaptureDetection(
          quad: first,
          hint: CaptureHint.moving,
          sharpness: 1,
          brightness: 1,
          stableFor: Duration.zero))
      ..emit(CaptureDetection(
          quad: second,
          hint: CaptureHint.moving,
          sharpness: 1,
          brightness: 1,
          stableFor: Duration.zero));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.latest!.quad!.topLeft.x, closeTo(0.1, 1e-9));
  });
}
