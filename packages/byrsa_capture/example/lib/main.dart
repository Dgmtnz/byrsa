// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter/material.dart';

void main() => runApp(const CaptureExampleApp());

class CaptureExampleApp extends StatelessWidget {
  const CaptureExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'byrsa_capture',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const CaptureScreen(),
      );
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ByrsaCaptureController _controller = ByrsaCaptureController();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller.start().catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('byrsa_capture')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$_error'))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('byrsa_capture'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              tooltip: 'Auto capture',
              icon: Icon(_controller.autoCapture
                  ? Icons.motion_photos_auto
                  : Icons.motion_photos_off),
              onPressed: () =>
                  setState(() => _controller.autoCapture = !_controller.autoCapture),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: CapturePreview(controller: _controller)),
          SizedBox(height: 120, child: _PageStrip(controller: _controller)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _controller.capture,
        child: const Icon(Icons.camera),
      ),
    );
  }
}

class _PageStrip extends StatelessWidget {
  const _PageStrip({required this.controller});

  final ByrsaCaptureController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final pages = controller.pages;
          if (pages.isEmpty) {
            return const Center(child: Text('No pages captured yet'));
          }
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final page = pages[index];
              final path = page.rectifiedPath ?? page.originalPath;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onLongPress: () => controller.removePage(index),
                  child: Image.file(File(path), fit: BoxFit.cover),
                ),
              );
            },
          );
        },
      );
}
