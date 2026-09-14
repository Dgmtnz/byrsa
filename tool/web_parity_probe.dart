// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// Restores deterministic pages and prints a checksum of every result.
//
// Run on the Dart VM, then compiled through dart2js and run again: the two
// outputs have to match line for line. They did not. `>>` on a negative int is
// an arithmetic shift on the VM and an unsigned 32-bit one on the web, so
// `math.max(0, position >> 8)` clamped nothing there and every bilinear blend
// inverted the sign of its own difference.
//
// Driven by tool/check_web_parity.sh, which is what CI runs.
//
// `print` rather than `stdout.writeln`, which is the idiom everywhere else in
// tool/: `stdout` comes from `dart:io`, and this is the one program in the
// repository that has to compile for a platform which does not have it. That is
// the entire point of it.

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore_core.dart';

void main() {
  for (final size in <List<int>>[
    <int>[64, 48],
    <int>[512, 384],
    <int>[1240, 1158],
  ]) {
    final width = size[0];
    final height = size[1];
    final data = Uint8List(width * height * 3);
    for (var i = 0; i < data.length; i++) {
      data[i] = (i * 7 + (i ~/ (width * 3)) * 3) % 256;
    }

    for (final filter in PageFilter.values) {
      try {
        final out = ClassicalRestore(filter: filter)(ImageBuffer(
          width: width,
          height: height,
          channels: 3,
          data: data,
        ));
        var checksum = 0;
        for (final byte in out.data) {
          checksum = (checksum * 31 + byte) & 0xFFFFFF;
        }
        print('${width}x$height ${filter.name.padRight(13)} '
            'checksum=$checksum bytes=${out.data.length}');
      } on Object catch (error) {
        print('${width}x$height ${filter.name.padRight(13)} FAILED :: $error');
      }
    }
  }
}
