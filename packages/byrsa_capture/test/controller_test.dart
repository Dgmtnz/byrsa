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

/// A page filling most of the frame, not touching its edges.
CaptureQuad page({double dx = 0}) => CaptureQuad(
      CapturePoint(0.15 + dx, 0.15),
      CapturePoint(0.85 + dx, 0.15),
      CapturePoint(0.85 + dx, 0.85),
      CapturePoint(0.15 + dx, 0.85),
    );

/// What the platform side actually sends: geometry and measurements, and a
/// hint it is not qualified to decide. Everything else is worked out in Dart.
CaptureDetection detection(
  CaptureQuad? quad, {
  double sharpness = 1,
  double brightness = 1,
}) =>
    CaptureDetection(
      quad: quad,
      hint: quad == null ? CaptureHint.noDocument : CaptureHint.moving,
      sharpness: sharpness,
      brightness: brightness,
      stableFor: Duration.zero,
    );

/// Feeds [frames] identical detections and lets the stream drain.
Future<void> hold(
  FakeCapturePlatform platform,
  CaptureDetection event, {
  int frames = 12,
}) async {
  for (var i = 0; i < frames; i++) {
    platform.emit(event);
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

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

  test('decides readiness itself rather than trusting the platform hint',
      () async {
    // The native side reports "moving" for every frame it sees a page in; it
    // has no business deciding when to fire. If the controller passed that
    // hint through, auto-capture would never happen at all.
    final controller = ByrsaCaptureController(autoCapture: false);
    await controller.start();

    platform.emit(detection(page()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.latest!.hint, CaptureHint.moving,
        reason: 'not settled yet');

    await hold(platform, detection(page()));
    expect(controller.latest!.hint, CaptureHint.ready);
  });

  test('fires auto-capture once the scene has settled', () async {
    final controller = ByrsaCaptureController();
    await controller.start();

    await hold(platform, detection(page()));
    expect(platform.captureCount, 1);
  });

  test('does not auto-capture while the scene keeps moving', () async {
    final controller = ByrsaCaptureController();
    await controller.start();

    for (var i = 0; i < 20; i++) {
      platform.emit(detection(page(dx: i.isEven ? 0 : 0.12)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(platform.captureCount, 0);
    expect(controller.latest!.hint, CaptureHint.moving);
  });

  test('does not auto-capture a steady but blurred scene', () async {
    final controller = ByrsaCaptureController();
    await controller.start();

    await hold(platform, detection(page(), sharpness: 0.02));
    expect(platform.captureCount, 0);
    expect(controller.latest!.hint, CaptureHint.blurry);
  });

  test('needs the scene to settle again before a second page', () async {
    final controller = ByrsaCaptureController();
    await controller.start();

    await hold(platform, detection(page()));
    expect(platform.captureCount, 1);

    // One more frame of the same scene must not fire again immediately.
    platform.emit(detection(page()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.captureCount, 1);
  });

  test('takes one page when auto-capture and a tap arrive together', () async {
    // Both paths firing at once is the normal case, not a rare race: the user
    // taps exactly when the scene settles.
    final controller = ByrsaCaptureController();
    await controller.start();
    platform.captureDelay = const Duration(milliseconds: 40);

    platform.emit(detection(page()));
    unawaited(hold(platform, detection(page())));
    await controller.capture();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(platform.captureCount, 1);
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
