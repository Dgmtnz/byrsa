<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_restore

Turning a photograph of a page into something readable: flattening the light,
removing shadows, and — with a model the user opts into downloading —
un-curving the page.

Two tiers, and the package always tells you which one ran.

## Tier one: classical, and always available

Pure Dart. No model, no download, no native library, a few milliseconds.

```dart
final restored = const ClassicalRestore()(image);
```

Three steps: estimate the colour of the paper, divide it out, then equalise
what is left with contrast-limited adaptive histogram equalisation.

The paper estimate takes a local **maximum** before smoothing. A plain blur is
not enough — where text is dense it drags the estimate down and the letters
come back grey. That one detail is the difference between the pipeline helping
and hurting on a full page of body text.

This tier is the baseline the neural one has to beat. A 30 MB download has to
earn its place, and the repository's evaluation harness is what decides.

## Tier two: neural, and opt-in — **not implemented yet**

Page dewarping (UVDoc) and shadow removal (DocShadow) as quantised ONNX, landing
in milestone M3. What exists today is everything around the inference: the
model manifest, the download-and-verify store, and the pipeline that reports a
stage it could not run. The inference itself is not written, and this README
would rather say so than imply otherwise.

**Nothing is bundled and nothing is trusted.** `ModelStore` refuses to install
a model with no pinned SHA-256, and deletes a file whose digest does not match
rather than keeping it around to be retried into. The manifest with every URL,
digest, size and licence lives in `models.json` at the repository root, where a
reviewer can read it in one go and a diff shows when any of it changes.

```dart
final store = ModelStore(directory: cache, catalog: catalog);
store.downloadSizeFor(['uvdoc']);          // tell the user what it costs
await store.install('uvdoc', onProgress: ...);
```

## Stages that cannot run say so

```dart
final result = await RestorePipeline([
  const ClassicalStage(),
  // ...and the neural stages, once M3 lands. Adding one is implementing
  // RestoreStage; the pipeline needs no change.
]).run(image);

for (final outcome in result.outcomes) {
  print('${outcome.id}: ${outcome.ran ? outcome.duration : outcome.skipReason}');
}
```

A stage with no model downloaded, or on a platform that cannot run it, is
**recorded as skipped and the pipeline continues**. A stage that throws costs
its stage, not the capture: losing a shadow-removal pass is a worse scan;
losing the capture is a lost document.

That is what lets one code path serve an F-Droid install with no models, a slow
device, and a fully equipped one — and it is what lets the benchmark measure
"with and without each stage" without a special build.

## Honest limits

- Dewarping handles gentle and moderate page curvature. A tightly bound book
  under poor light is not solvable with the open models that exist, and the
  interface should say so rather than pretend.
- DocShadow-SD7K is **120 MB as exported in fp32** — four times UVDoc.
  Quantisation is not an optimisation here, it is the precondition for shipping
  it at all, and whether it survives quantisation is an open question this
  package will answer with measurements, not adjectives.
- No timing figures are published yet, on any platform. When they are, they
  will say which device produced them.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa).
