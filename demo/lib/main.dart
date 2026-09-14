// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

/// Byrsa's restoration, running in a browser.
///
/// This is not a reimplementation for the web. It imports
/// `package:byrsa_restore` and calls the same `ClassicalRestore` the Android
/// application calls, on the same `ImageBuffer` — the package is pure Dart, so
/// the arithmetic that runs on a phone runs here unchanged.
///
/// What is deliberately NOT here, because it cannot be: text recognition. The
/// OCR engine is native code on Android and iOS, so a browser has nothing to
/// run. Saying so on the page matters more than hiding it.
library;

import 'dart:async';

import 'package:byrsa_restore/byrsa_restore_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

void main() => runApp(const ByrsaDemo());

const _samples = <String, String>{
  'adversarial-02.jpg': 'Contrato · sombra de mano y poca luz',
  'invoice-02.jpg': 'Factura · sombra de mano',
  'receipt-02.jpg': 'Tique · arrugado',
  'book-page-02.jpg': 'Página de libro · curvada',
  'whiteboard-02.jpg': 'Pizarra · reflejo',
  'form-05.jpg': 'Formulario (DE) · sombra de mano',
};

class ByrsaDemo extends StatelessWidget {
  const ByrsaDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Byrsa — restauración en el navegador',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8A5A2B),
            brightness: Brightness.dark,
          ),
        ),
        home: const _Home(),
      );
}

/// One restoration, with what it cost.
@immutable
class _Restored {
  const _Restored({
    required this.before,
    required this.after,
    required this.width,
    required this.height,
    required this.decodeMs,
    required this.restoreMs,
    required this.encodeMs,
  });

  final Uint8List before;
  final Uint8List after;
  final int width;
  final int height;
  final int decodeMs;
  final int restoreMs;
  final int encodeMs;

  double get megapixels => width * height / 1e6;
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  PageFilter _filter = PageFilter.colour;
  int _analysisWidth = 512;
  String? _sample = 'adversarial-02.jpg';
  Uint8List? _pickedBytes;
  _Restored? _result;
  bool _busy = false;
  String? _error;
  double _split = 0.5;

  @override
  void initState() {
    super.initState();
    unawaited(_runSample('adversarial-02.jpg'));
  }

  Future<void> _runSample(String name) async {
    final data = await rootBundle.load('assets/samples/$name');
    setState(() {
      _sample = name;
      _pickedBytes = null;
    });
    await _restore(data.buffer.asUint8List());
  }

  /// Decodes, restores and re-encodes, timing each step separately.
  ///
  /// The three are reported apart because the interesting number is the middle
  /// one: on a desktop the restoration is the cheapest of the three stages, and
  /// a single total would hide that behind the codec.
  Future<void> _restore(Uint8List jpeg) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Yield once so the spinner paints: this runs on the main isolate, because
    // the web has no worker to hand it to without shipping a second entry point.
    await Future<void>.delayed(Duration.zero);
    try {
      final watch = Stopwatch()..start();
      final decoded = img.decodeImage(jpeg);
      if (decoded == null) throw const FormatException('No se pudo leer la imagen.');
      final rgb = decoded.convert(numChannels: 3);
      final decodeMs = watch.elapsedMilliseconds;

      watch.reset();
      final restored = ClassicalRestore(
        filter: _filter,
        analysisWidth: _analysisWidth,
      )(ImageBuffer(
        width: rgb.width,
        height: rgb.height,
        channels: 3,
        data: rgb.toUint8List(),
      ));
      final restoreMs = watch.elapsedMilliseconds;

      watch.reset();
      final out = img.Image.fromBytes(
        width: restored.width,
        height: restored.height,
        bytes: restored.data.buffer,
        numChannels: restored.channels,
      );
      final after = img.encodeJpg(out, quality: 90);
      final encodeMs = watch.elapsedMilliseconds;

      setState(() {
        _result = _Restored(
          before: jpeg,
          after: after,
          width: rgb.width,
          height: rgb.height,
          decodeMs: decodeMs,
          restoreMs: restoreMs,
          encodeMs: encodeMs,
        );
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                const _Header(),
                const SizedBox(height: 20),
                _Controls(
                  samples: _samples,
                  selected: _sample,
                  filter: _filter,
                  analysisWidth: _analysisWidth,
                  busy: _busy,
                  onSample: _runSample,
                  onFilter: (value) {
                    setState(() => _filter = value);
                    final bytes = _pickedBytes ?? _result?.before;
                    if (bytes != null) unawaited(_restore(bytes));
                  },
                  onAnalysisWidth: (value) {
                    setState(() => _analysisWidth = value);
                    final bytes = _pickedBytes ?? _result?.before;
                    if (bytes != null) unawaited(_restore(bytes));
                  },
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  _Banner(text: _error!)
                else if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_result != null)
                  _Comparison(
                    result: _result!,
                    split: _split,
                    wide: wide,
                    onSplit: (value) => setState(() => _split = value),
                  ),
                const SizedBox(height: 28),
                const _Honesty(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Byrsa', style: theme.textTheme.displaySmall),
        const SizedBox(height: 6),
        Text(
          'Restauración de documentos, ejecutándose entera en tu navegador.',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Este es el mismo código Dart que corre en el teléfono: el paquete '
          'byrsa_restore es Dart puro, así que la aritmética no cambia al '
          'compilarse para web. Tu imagen no sale de esta pestaña.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.samples,
    required this.selected,
    required this.filter,
    required this.analysisWidth,
    required this.busy,
    required this.onSample,
    required this.onFilter,
    required this.onAnalysisWidth,
  });

  final Map<String, String> samples;
  final String? selected;
  final PageFilter filter;
  final int analysisWidth;
  final bool busy;
  final ValueChanged<String> onSample;
  final ValueChanged<PageFilter> onFilter;
  final ValueChanged<int> onAnalysisWidth;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final entry in samples.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: selected == entry.key,
            onSelected: busy ? null : (_) => onSample(entry.key),
          ),
        const SizedBox(width: 24),
        SegmentedButton<PageFilter>(
          segments: const <ButtonSegment<PageFilter>>[
            ButtonSegment(value: PageFilter.colour, label: Text('Color')),
            ButtonSegment(value: PageFilter.grayscale, label: Text('Gris')),
            ButtonSegment(
                value: PageFilter.blackAndWhite, label: Text('Blanco y negro')),
          ],
          selected: <PageFilter>{filter},
          onSelectionChanged:
              busy ? null : (value) => onFilter(value.first),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text),
      );
}

/// Before and after, with a handle you drag across the seam.
class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.result,
    required this.split,
    required this.wide,
    required this.onSplit,
  });

  final _Restored result;
  final double split;
  final bool wide;
  final ValueChanged<double> onSplit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = width * result.height / result.width;
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: <Widget>[
                  Image.memory(result.before,
                      width: width, height: height, fit: BoxFit.fill),
                  ClipRect(
                    clipper: _LeftClipper(split),
                    child: Image.memory(result.after,
                        width: width, height: height, fit: BoxFit.fill),
                  ),
                  Positioned(
                    left: width * split - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.white70),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) => onSplit(
                        (details.localPosition.dx / width).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _Tag(
                        text: 'restaurado', color: theme.colorScheme.primary),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _Tag(
                        text: 'original',
                        color: theme.colorScheme.surfaceContainerHighest),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text('Arrastra sobre la imagen para mover la separación.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        _Timings(result: result),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.split);

  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.split != split;
}

class _Timings extends StatelessWidget {
  const _Timings({required this.result});

  final _Restored result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 28,
      runSpacing: 8,
      children: <Widget>[
        _Stat(
            label: 'Restauración',
            value: '${result.restoreMs} ms',
            emphasis: true),
        _Stat(label: 'Descodificar', value: '${result.decodeMs} ms'),
        _Stat(label: 'Codificar', value: '${result.encodeMs} ms'),
        _Stat(
            label: 'Página',
            value: '${result.width}x${result.height} '
                '(${result.megapixels.toStringAsFixed(1)} MP)'),
        _Stat(
          label: 'Dónde',
          value: kIsWeb ? 'en tu navegador' : 'nativo',
        ),
        const SizedBox(width: 1, child: SizedBox()),
        Text(
          'Medido aquí, en tu máquina y tu navegador. No es un número '
          'transferible a un teléfono.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: emphasis
              ? theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.primary)
              : theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

/// What this page is not. It goes at the bottom and it does not get softened.
class _Honesty extends StatelessWidget {
  const _Honesty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Qué enseña esto, y qué no',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _Point(
            'No hay servidor.',
            'La imagen se descodifica, se restaura y se vuelve a codificar en '
                'esta pestaña. No se sube a ninguna parte, y puedes comprobarlo '
                'desconectando la red antes de pulsar.',
          ),
          _Point(
            'No hay OCR aquí.',
            'El reconocimiento de texto es código nativo en Android e iOS, así '
                'que un navegador no tiene qué ejecutar. Esta página restaura '
                'la imagen y nada más.',
          ),
          _Point(
            'Estas páginas son sintéticas.',
            'Están generadas con daños modelados —sombra de mano con luz '
                'ambiente, arrugas, reflejo, curvatura— para poder medir contra '
                'un original conocido. No sustituyen a fotografías reales.',
          ),
          _Point(
            'El tiempo que ves es el de tu máquina.',
            'Un portátil no es un teléfono de gama media. Las cifras del '
                'repositorio se anotan siempre con la máquina que las midió.',
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: <InlineSpan>[
            TextSpan(
                text: '$title ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text: body,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
