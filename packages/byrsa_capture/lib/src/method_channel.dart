// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';

import 'capture_result.dart';
import 'platform_interface.dart';
import 'quad.dart';

/// Method-channel implementation, shared by Android and iOS.
///
/// One channel, one wire format, two native implementations. Anything that
/// differs between the platforms differs *behind* this class, never in it.
class MethodChannelByrsaCapture extends ByrsaCapturePlatform {
  final MethodChannel _methods = const MethodChannel('dev.byrsa/capture');
  final EventChannel _events =
      const EventChannel('dev.byrsa/capture/detections');

  Stream<CaptureDetection>? _detections;

  @override
  Future<int> start(CaptureOptions options) async {
    final int? textureId;
    try {
      textureId = await _methods.invokeMethod<int>('start', options.toJson());
    } on PlatformException catch (error) {
      // Turn the two refusals into one typed exception the interface can act
      // on. A raw PlatformException reaches the user as a stack trace.
      if (error.code == 'permission-denied') {
        throw const CameraPermissionDenied(permanently: false);
      }
      if (error.code == 'permission-denied-permanently') {
        throw const CameraPermissionDenied(permanently: true);
      }
      rethrow;
    }
    if (textureId == null) {
      throw PlatformException(
        code: 'no-texture',
        message: 'The camera started but returned no texture to display.',
      );
    }
    return textureId;
  }

  @override
  Future<CameraPermission> permissionStatus() async {
    final name = await _methods.invokeMethod<String>('permissionStatus');
    return CameraPermission.values.firstWhere(
      (value) => value.name == name,
      orElse: () => CameraPermission.notAsked,
    );
  }

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Stream<CaptureDetection> get detections =>
      _detections ??= _events.receiveBroadcastStream().map(_toDetection);

  static CaptureDetection _toDetection(Object? event) {
    final map = event! as Map<Object?, Object?>;
    final corners = map['quad'] as List<Object?>?;
    return CaptureDetection(
      quad: corners == null ? null : CaptureQuad.fromJson(corners),
      hint: CaptureHint.values.byName(map['hint'] as String? ?? 'noDocument'),
      sharpness: (map['sharpness'] as num?)?.toDouble() ?? 0,
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0,
      stableFor:
          Duration(milliseconds: (map['stableForMs'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  Future<CapturedPage> capture() async {
    final result =
        await _methods.invokeMethod<Map<Object?, Object?>>('capture');
    if (result == null) {
      throw PlatformException(
          code: 'no-capture', message: 'Capture returned nothing.');
    }
    return CapturedPage.fromJson(result);
  }

  @override
  Future<String> rectify({
    required String imagePath,
    required CaptureQuad quad,
    double? targetAspectRatio,
  }) async {
    final path =
        await _methods.invokeMethod<String>('rectify', <String, Object?>{
      'imagePath': imagePath,
      'quad': quad.toJson(),
      'targetAspectRatio': targetAspectRatio,
    });
    if (path == null) {
      throw PlatformException(
          code: 'no-output', message: 'Rectify produced no file.');
    }
    return path;
  }

  @override
  Future<void> setTorch({required bool on}) =>
      _methods.invokeMethod<void>('setTorch', <String, Object?>{'on': on});

  @override
  Future<bool> isSupported() async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;
}
