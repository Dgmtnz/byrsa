// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:flutter/material.dart';

void main() {
  registerByrsaOcr();
  runApp(const OcrExampleApp());
}

class OcrExampleApp extends StatelessWidget {
  const OcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'byrsa_ocr',
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
        home: const OcrScreen(),
      );
}

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  static const ByrsaOcr _ocr = ByrsaOcr();

  OcrReadiness? _readiness;
  OcrResult? _result;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final readiness = await _ocr.readiness();
    if (mounted) setState(() => _readiness = readiness);
  }

  Future<void> _prepare() async {
    setState(() => _status = 'Downloading models…');
    try {
      await _ocr.prepare(
        onProgress: (received, total) => setState(
          () => _status = 'Downloading models… ${(received * 100 / total).round()}%',
        ),
      );
      setState(() => _status = null);
      await _refresh();
    } on Object catch (error) {
      setState(() => _status = '$error');
    }
  }

  Future<void> _recognise(String path) async {
    setState(() => _status = 'Recognising…');
    try {
      final result = await _ocr.recognise(imagePath: path);
      setState(() {
        _result = result;
        _status = '${result.engine} · ${result.duration.inMilliseconds} ms';
      });
    } on Object catch (error) {
      setState(() => _status = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    return Scaffold(
      appBar: AppBar(title: const Text('byrsa_ocr')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (readiness != null)
            Card(
              child: ListTile(
                title: Text('Engine: ${readiness.engine}'),
                subtitle: Text(readiness.ready
                    ? 'Ready'
                    : '${readiness.reason} '
                        '(${(readiness.missingBytes / 1024 / 1024).round()} MB)'),
                trailing: readiness.ready
                    ? const Icon(Icons.check_circle)
                    : FilledButton(onPressed: _prepare, child: const Text('Download')),
              ),
            ),
          if (_status != null) Padding(padding: const EdgeInsets.all(8), child: Text(_status!)),
          const SizedBox(height: 8),
          // Point this at a file the device already has. The package never
          // uploads anything: recognition happens where the file is.
          TextField(
            decoration: const InputDecoration(
              labelText: 'Image path on the device',
              border: OutlineInputBorder(),
            ),
            onSubmitted: _recognise,
          ),
          const SizedBox(height: 16),
          if (_result != null)
            for (final line in _result!.lines)
              ListTile(
                dense: true,
                title: Text(line.text),
                subtitle: Text('confidence ${line.confidence.toStringAsFixed(2)}'),
              ),
        ],
      ),
    );
  }
}
