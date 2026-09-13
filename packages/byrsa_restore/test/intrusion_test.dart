// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:test/test.dart';

const int _width = 480;
const int _height = 640;

/// A page of text on paper, optionally with something intruding from an edge.
ImageBuffer page({
  bool finger = false,
  bool stampInMiddle = false,
  int fingerValue = 92,
  int channels = 1,
}) {
  final data = Uint8List(_width * _height * channels);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      // Lines of text: thin, dark, and nowhere near the margins.
      final onLine = (y % 22) < 5 && y > 60 && y < _height - 60;
      final inColumn = x > 70 && x < _width - 70;
      var value = (onLine && inColumn) ? 46 : 242;

      // A thumb reaching in from the right edge, well clear of the text.
      if (finger) {
        final dx = x - (_width + 10);
        final dy = y - _height ~/ 2;
        if (dx * dx / 6400 + dy * dy / 10000 < 1) value = fingerValue;
      }
      // A dark stamp that touches nothing.
      if (stampInMiddle) {
        final dx = x - _width ~/ 2;
        final dy = y - _height ~/ 2;
        if (dx * dx + dy * dy < 55 * 55) value = 70;
      }
      for (var c = 0; c < channels; c++) {
        data[(y * _width + x) * channels + c] = value;
      }
    }
  }
  return channels == 1
      ? ImageBuffer.gray(_width, _height, data)
      : ImageBuffer(
          width: _width, height: _height, channels: channels, data: data);
}

/// Mean brightness of a patch, for asking "is the thumb still there".
double patch(ImageBuffer image, int x0, int y0, int x1, int y1) {
  var total = 0;
  var count = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      total += image.data[(y * image.width + x) * image.channels];
      count++;
    }
  }
  return total / count;
}

void main() {
  group('detection', () {
    test('finds a thumb reaching in from the edge', () {
      final found = const BorderIntrusion().detect(page(finger: true));
      expect(found.areaFraction, greaterThan(0.01));
    });

    test('finds nothing on a clean page', () {
      // The expensive failure is a false positive: erasing part of someone's
      // document because the detector was nervous.
      expect(const BorderIntrusion().detect(page()).areaFraction, 0);
    });

    test('leaves a stamp in the middle of the page alone', () {
      // Dark, thick, and nothing to do with a hand. The border test is what
      // separates them, and it is the reason this does not look for skin.
      final found = const BorderIntrusion().detect(page(stampInMiddle: true));
      expect(found.areaFraction, 0);
    });

    test('does not mistake lines of text for an object', () {
      // Text is dark and reaches a long way, but it is thin. The erosion is
      // the whole discriminator.
      final found = const BorderIntrusion().detect(page());
      expect(found.mask.where((v) => v != 0), isEmpty);
    });

    test('refuses to erase half the page', () {
      // A mask that large means the paper estimate failed. Leaving a thumb in
      // the corner is far better than deleting someone's document.
      final dark = Uint8List(_width * _height)
        ..fillRange(0, _width * _height, 40);
      final found = const BorderIntrusion().detect(
        ImageBuffer.gray(_width, _height, dark),
      );
      expect(found.areaFraction, 0);
    });
  });

  group('detection is not a skin detector', () {
    // The point of the design: the decision must not depend on how light or
    // dark the intruding object is, because in practice that means whose hand
    // it is.
    for (final value in <int>[40, 92, 150, 190]) {
      test('a thumb of brightness $value is found just the same', () {
        final found = const BorderIntrusion()
            .detect(page(finger: true, fingerValue: value));
        expect(
          found.areaFraction,
          greaterThan(0.01),
          reason: 'brightness $value was treated differently',
        );
      });
    }
  });

  group('removal', () {
    test('replaces the thumb with something close to paper', () {
      final before = page(finger: true);
      final after = const BorderIntrusion()(before);

      final wasFinger = patch(before, _width - 60, 290, _width - 10, 350);
      final nowThere = patch(after, _width - 60, 290, _width - 10, 350);
      final paper = patch(before, 10, 290, 60, 350);

      expect(wasFinger, lessThan(150), reason: 'the fixture is wrong');
      expect((nowThere - paper).abs(), lessThan(28),
          reason: 'the hole should read as paper, not as a grey patch');
    });

    test('leaves the text alone', () {
      final before = page(finger: true);
      final after = const BorderIntrusion()(before);
      // A line of text in the middle of the column, far from the edge.
      expect(
        patch(after, 100, 200, 300, 205),
        closeTo(patch(before, 100, 200, 300, 205), 3),
      );
    });

    test('returns the image untouched when there is nothing to remove', () {
      final clean = page();
      final after = const BorderIntrusion()(clean);
      expect(identical(after, clean), isTrue,
          reason: 'no work means no copy, and no risk of changing anything');
    });

    test('carries every channel of a colour page', () {
      final after = const BorderIntrusion()(page(finger: true, channels: 3));
      expect(after.channels, 3);
      expect(after.data.length, _width * _height * 3);
    });

    test('costs little, because it works on a downscaled copy', () {
      final big = page(finger: true);
      final watch = Stopwatch()..start();
      const BorderIntrusion()(big);
      expect(watch.elapsedMilliseconds, lessThan(3000),
          reason: 'a full-resolution fill would be far slower than this');
    });
  });

  group('order in the pipeline', () {
    /// The same page, lit unevenly — a hard shadow across one side.
    ImageBuffer shadowed() {
      final flat = page();
      final data = Uint8List(_width * _height);
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          final t = ((x - _width * 0.55) / (_width * 0.05)).clamp(-1.0, 1.0);
          final shade = 1.0 - 0.5 * (0.5 - 0.5 * t);
          data[y * _width + x] =
              (flat.data[y * _width + x] * shade).round().clamp(0, 255);
        }
      }
      return ImageBuffer.gray(_width, _height, data);
    }

    test('a raw shadowed capture is spared', () {
      // On a raw capture the paper estimate is dragged towards the shadow and
      // half the page is flagged — but that half reaches the top edge and the
      // bottom edge, so rule 5 drops it. Same rule, same reason, as the halo.
      expect(const BorderIntrusion().detect(shadowed()).areaFraction, 0);
    });

    test('rule 5 is what does it: a page-spanning region is never an object',
        () {
      // Isolated from any pipeline, so the rule is pinned rather than inferred
      // from a happy outcome somewhere downstream.
      Uint8List stripe({required bool fullHeight}) {
        final data = Uint8List(_width * _height)
          ..fillRange(0, _width * _height, 242);
        final top = fullHeight ? 0 : _height ~/ 3;
        final bottom = fullHeight ? _height : _height ~/ 3 + 80;
        for (var y = top; y < bottom; y++) {
          for (var x = _width - 70; x < _width; x++) {
            data[y * _width + x] = 90;
          }
        }
        return data;
      }

      expect(
        const BorderIntrusion()
            .detect(ImageBuffer.gray(_width, _height, stripe(fullHeight: true)))
            .areaFraction,
        0,
        reason: 'top to bottom is a stripe, not a hand',
      );
      expect(
        const BorderIntrusion()
            .detect(
                ImageBuffer.gray(_width, _height, stripe(fullHeight: false)))
            .areaFraction,
        greaterThan(0.01),
        reason: 'the same shape, not spanning the page, is an object',
      );
    });

    test('the halo at a hard shadow edge is not mistaken for a hand', () async {
      // Dividing by a background built from a local maximum overestimates on
      // the dark side of a sharp illumination step, so a dark stripe survives
      // where the edge was. It is thick, it differs from the paper and it
      // touches the border — it passed every test until the one that says a
      // hand does not reach two opposite edges of the page.
      final flattened = await RestorePipeline(const <RestoreStage>[
        ClassicalStage(),
      ]).run(shadowed());

      expect(
        const BorderIntrusion().detect(flattened.image).areaFraction,
        0,
        reason: 'a full-height stripe is an artefact, not an object',
      );
    });

    test('a real thumb survives the flattening and is still found', () async {
      // The other half: flattening must not erase the thing we do want.
      final flattened = await RestorePipeline(const <RestoreStage>[
        ClassicalStage(),
      ]).run(page(finger: true));

      expect(
        const BorderIntrusion().detect(flattened.image).areaFraction,
        greaterThan(0.01),
      );
    });
  });

  group('as a pipeline stage', () {
    test('runs, and reports itself as having run', () async {
      final result = await RestorePipeline(const <RestoreStage>[
        IntrusionStage(),
        ClassicalStage(),
      ]).run(page(finger: true));

      expect(result.outcomes.first.id, 'intrusion');
      expect(result.outcomes.first.ran, isTrue);
      expect(result.image.width, _width);
    });
  });
}
