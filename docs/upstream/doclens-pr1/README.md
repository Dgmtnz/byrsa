<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# doclens PR 1 — a classical text-orientation detector

The code for the first pull request promised in
[`../doclens-play-services.md`](../doclens-play-services.md) and in
[doclens#20](https://github.com/govindmaheshwari2/doclens/issues/20). Kept here
so it is versioned alongside the reasoning that produced it, and so it survives
a temporary checkout.

It replaces `TextOrientationDetector`, which asks Play-services ML Kit to read
the page at each of four rotations, with one that measures where ink sits. Same
public signature, same conservative bias, one fewer thing that can be
unavailable.

| File | |
|---|---|
| `TextOrientationScorer.kt` | The arithmetic. Pure Kotlin, **no Android types at all** |
| `TextOrientationDetector.kt` | The Bitmap wrapper. Unchanged public API |
| `TextOrientationScorerTest.kt` | 14 tests, all on the JVM |
| `build.gradle.kts.diff` | Declares Mockito, which their test source set already imports |

## Verified

`./gradlew :doclens:testDebugUnitTest` from `example/android`, against doclens
at `e1fe7d7`: **14 cases, 0 failures.** The suite's remaining red is
`DoclensPluginTest`, and it is not ours — see below.

## How it works

Two profiles, four rotations. Ink is summed along rows and along columns once.
A quarter turn turns columns into rows; a half turn reads the same profile
backwards — and that reversal is exactly what flips the ascender/descender
asymmetry which separates upright from upside-down. No image is ever rotated.

The decision is the product of three things, and any of them being zero means
"leave the page alone":

- **It alternates.** Text crosses its own mean twice per line. A gradient
  crosses once.
- **It is peaky.** Variance, scaled by `m(1-m)` so a dense contract and a sparse
  note read the same.
- **It leans the right way.** More ink above each dense band than below it,
  because ascenders and capitals outnumber descenders.

## Three things only measurement found

**Otsu's threshold is inclusive.** It returns the top of the dark class, so
comparing with `<` excludes the ink itself — zero pixels detected on a page full
of text.

**The limit is pixels per text line, not line count.** Sweeping 5 to 50 lines:
the decision holds to about 19 px per line and collapses by 16, whatever the
count. The analysis resolution was going to be dropped to 640 on the reasoning
that glyphs need not be legible; a fifty-line page at 640 gives 13 px per line,
the wrong side of that edge. Left at 1000, now for a reason with a number.

**A gradient was being rotated.** A photograph lit from one corner produces a
clean ramp, which scores 0.52 on peakiness — higher than any real page of text
here — and, read backwards, perfect apparent asymmetry. The alternation test
above is what separates them, and it exists only because a test asserted that a
photograph must never be rotated.

## Two things in doclens that are not ours to fix

Both found while trying to run the tests, both present on a clean checkout of
`e1fe7d7`:

1. **The test source set does not compile.** `DoclensPluginTest` imports
   `org.mockito.Mockito`; nothing declares it. `testDebugUnitTest` fails at
   compilation. Fixed in the diff here, because otherwise these tests cannot be
   run at all — one line.
2. **`DoclensPluginTest` then fails on its own merits.** It asserts
   `result.success("Android …")` for `getPlatformVersion`, and `DoclensPlugin`
   answers that call with `notImplemented()`. The test outlived the method.
   Left untouched: deleting or rewriting someone's test is their call, and it is
   mentioned in the pull request rather than quietly fixed.
