// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerByrsaCapture();
  registerByrsaOcr();
  runApp(const ProviderScope(child: ByrsaApp()));
}
