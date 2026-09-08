// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// Levenshtein distance between two sequences, in O(min(a,b)) memory.
int levenshtein(List<Object?> a, List<Object?> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  // Keep the shorter sequence in the row so memory follows the smaller side.
  if (a.length < b.length) {
    final swap = a;
    a = b;
    b = swap;
  }

  var previous = List<int>.generate(b.length + 1, (i) => i, growable: false);
  var current = List<int>.filled(b.length + 1, 0, growable: false);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    final ai = a[i - 1];
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (ai == b[j - 1] ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      var best = substitution;
      if (deletion < best) best = deletion;
      if (insertion < best) best = insertion;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Collapses runs of whitespace and trims, so that a difference in line breaks
/// is not counted as a recognition error.
///
/// Every number the harness publishes says which normalisation produced it.
String normalizeWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// An error rate, with the counts it came from, so it can be aggregated.
class ErrorRate {
  const ErrorRate(this.errors, this.referenceLength);

  final int errors;
  final int referenceLength;

  /// Errors per reference unit. 0 is perfect; values above 1 are possible when
  /// the engine hallucinates more than it reads.
  double get rate =>
      referenceLength == 0 ? (errors == 0 ? 0 : 1) : errors / referenceLength;

  ErrorRate operator +(ErrorRate other) =>
      ErrorRate(errors + other.errors, referenceLength + other.referenceLength);

  static const ErrorRate zero = ErrorRate(0, 0);

  @override
  String toString() => '${(rate * 100).toStringAsFixed(2)}%';
}

/// Character error rate of [hypothesis] against [reference].
ErrorRate characterErrorRate(
  String reference,
  String hypothesis, {
  bool strict = false,
}) {
  final ref = strict ? reference : normalizeWhitespace(reference);
  final hyp = strict ? hypothesis : normalizeWhitespace(hypothesis);
  return ErrorRate(
    levenshtein(ref.runes.toList(), hyp.runes.toList()),
    ref.runes.length,
  );
}

/// Word error rate of [hypothesis] against [reference].
ErrorRate wordErrorRate(
  String reference,
  String hypothesis, {
  bool strict = false,
}) {
  List<String> words(String s) => (strict ? s : normalizeWhitespace(s))
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  final ref = words(reference);
  return ErrorRate(levenshtein(ref, words(hypothesis)), ref.length);
}
