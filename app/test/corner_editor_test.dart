// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa/l10n/app_localizations.dart';
import 'package:byrsa/src/ui/corner_editor_screen.dart';
import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the editor. The returned list receives whatever the screen pops, so a
/// test can tap Save and then read what came back.
Future<List<CaptureQuad?>> open(
  WidgetTester tester,
  CaptureQuad initial, {
  Locale locale = const Locale('en'),
}) async {
  final result = <CaptureQuad?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.add(await Navigator.of(context).push<CaptureQuad>(
              MaterialPageRoute<CaptureQuad>(
                builder: (_) => CornerEditorScreen(
                  imagePath: '/does/not/exist.jpg',
                  initialQuad: initial,
                ),
              ),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  const skewed = CaptureQuad(
    CapturePoint(0.2, 0.1),
    CapturePoint(0.7, 0.15),
    CapturePoint(0.75, 0.8),
    CapturePoint(0.15, 0.85),
  );

  testWidgets('renders even when the image cannot be read', (tester) async {
    // The editor is the recovery path for a bad scan. It must not be the thing
    // that crashes when a file has gone missing.
    await open(tester, skewed);
    expect(find.byType(QuadOverlay), findsOneWidget);
    expect(find.text('Adjust corners'), findsOneWidget);
  });

  testWidgets('returns the corners unchanged when nothing is dragged',
      (tester) async {
    final popped = await open(tester, skewed);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(CornerEditorScreen), findsNothing);
    expect(popped.single, skewed);
  });

  testWidgets('returns nothing when the user backs out', (tester) async {
    // Leaving without saving must not silently re-warp the page.
    final popped = await open(tester, skewed);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(popped.single, isNull);
  });

  testWidgets('returns the dragged corners, which is the whole point',
      (tester) async {
    final popped = await open(tester, skewed);

    final box = tester.getRect(find.byType(QuadOverlay));
    await tester.dragFrom(
      Offset(
        box.left + skewed.topLeft.x * box.width,
        box.top + skewed.topLeft.y * box.height,
      ),
      const Offset(24, 24),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped.single, isNotNull);
    expect(popped.single!.topLeft.x, greaterThan(skewed.topLeft.x));
    expect(popped.single!.topRight, skewed.topRight);
  });

  testWidgets('reset offers the whole frame, which is the useful fallback',
      (tester) async {
    await open(tester, skewed);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();

    final overlay = tester.widget<QuadOverlay>(find.byType(QuadOverlay));
    expect(overlay.quad, CaptureQuad.full);
  });

  testWidgets('dragging a corner moves that corner and no other',
      (tester) async {
    await open(tester, skewed);

    final box = tester.getRect(find.byType(QuadOverlay));
    final topLeft = Offset(
      box.left + skewed.topLeft.x * box.width,
      box.top + skewed.topLeft.y * box.height,
    );
    await tester.dragFrom(topLeft, const Offset(20, 20));
    await tester.pump();

    final overlay = tester.widget<QuadOverlay>(find.byType(QuadOverlay));
    expect(overlay.quad!.topLeft, isNot(skewed.topLeft));
    expect(overlay.quad!.bottomRight, skewed.bottomRight);
    expect(overlay.quad!.topRight, skewed.topRight);
  });

  testWidgets('is translated, not hard-coded English', (tester) async {
    await open(tester, skewed, locale: const Locale('es'));
    expect(find.text('Ajustar esquinas'), findsOneWidget);
  });
}
