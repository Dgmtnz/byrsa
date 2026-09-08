// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter/material.dart';

void main() => runApp(const RestoreExampleApp());

class RestoreExampleApp extends StatelessWidget {
  const RestoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'byrsa_restore',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const RestoreScreen(),
      );
}

/// Shows the classical pipeline working on a synthetic shadowed page, with the
/// timings the evaluation harness would record.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  ui.Image? _before;
  ui.Image? _after;
  RestoreResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final input = _shadowedPage(360, 480);
    final result = await const RestorePipeline(<RestoreStage>[ClassicalStage()]).run(input);
    final before = await _toImage(input);
    final after = await _toImage(result.image);
    if (!mounted) return;
    setState(() {
      _before = before;
      _after = after;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('byrsa_restore')),
        body: _before == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(child: RawImage(image: _before, fit: BoxFit.contain)),
                        Expanded(child: RawImage(image: _after, fit: BoxFit.contain)),
                      ],
                    ),
                  ),
                  for (final outcome in _result!.outcomes)
                    ListTile(
                      title: Text(outcome.id),
                      subtitle: Text(outcome.ran
                          ? '${outcome.duration.inMilliseconds} ms'
                          : 'skipped: ${outcome.skipReason!.name}'),
                    ),
                ],
              ),
      );

  static ImageBuffer _shadowedPage(int width, int height) {
    final data = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final text = (y % 20) < 7 && y > 30 && y < height - 30 && x > 30 && x < width - 30;
        final shade = 0.45 + 0.55 * (x / width);
        data[y * width + x] = ((text ? 45 : 246) * shade).round();
      }
    }
    return ImageBuffer.gray(width, height, data);
  }

  static Future<ui.Image> _toImage(ImageBuffer buffer) async {
    final rgba = Uint8List(buffer.pixelCount * 4);
    final luma = buffer.toLuma();
    for (var i = 0; i < buffer.pixelCount; i++) {
      rgba[i * 4] = buffer.isGray ? luma[i] : buffer.data[i * 3];
      rgba[i * 4 + 1] = buffer.isGray ? luma[i] : buffer.data[i * 3 + 1];
      rgba[i * 4 + 2] = buffer.isGray ? luma[i] : buffer.data[i * 3 + 2];
      rgba[i * 4 + 3] = 255;
    }
    final descriptor = ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(rgba),
      width: buffer.width,
      height: buffer.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  }
}
