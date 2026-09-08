// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'ui/capture_screen.dart';
import 'ui/document_screen.dart';
import 'ui/library_screen.dart';
import 'ui/settings_screen.dart';

final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
    GoRoute(
      path: '/folder/:id',
      builder: (_, state) =>
          LibraryScreen(folderId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/document/:id',
      builder: (_, state) =>
          DocumentScreen(documentId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(path: '/capture', builder: (_, __) => const CaptureScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
  ],
);

class ByrsaApp extends StatelessWidget {
  const ByrsaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        routerConfig: router,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF7A4E2D), useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF7A4E2D),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
      );
}
