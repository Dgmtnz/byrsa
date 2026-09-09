<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# onnxruntime_flutter: the Android module cannot be built in release any more

**Repository:** `github.com/gtbluesky/onnxruntime_flutter`
**Version examined:** 1.4.1 (from pub.dev)
**Status:** draft, ready to file

---

## Issue text

**Title:** `compileSdkVersion 33` breaks release builds against current AndroidX

`android/build.gradle` pins:

```groovy
compileSdkVersion 33
```

Any application on a recent Flutter — 3.47 here, with AGP 9 — fails its
**release** build with:

```
Execution failed for task ':onnxruntime:checkReleaseAarMetadata'.
> 15 issues were found when checking AAR metadata:
    1.  Dependency 'androidx.fragment:fragment:1.7.1' requires libraries and
        applications that depend on it to compile against version 34 or later
        of the Android APIs.

        :onnxruntime is currently compiled against android-33.
```

The debug build succeeds, which is what makes this unpleasant: the failure
appears the first time someone tries to ship.

`compileSdk` controls which APIs a library may call, not which devices it runs
on — `minSdkVersion 21` can stay exactly as it is — so raising it is a one-line
change with no compatibility cost:

```groovy
compileSdkVersion 36
```

Consumers can work around it from their own `android/build.gradle` by raising
the subproject's `compileSdkVersion` in an `afterEvaluate` block, and that is
what we do today, but every consumer having to know that is not a good place
for the ecosystem to be.

I am happy to send the pull request.

### A second thing, which may deserve its own issue

The package ships its own `libonnxruntime.so` in `android/src/main/jniLibs`.
An application that also depends on any plugin using the official
`com.microsoft.onnxruntime:onnxruntime-android` AAR — which is how most Android
OCR and vision plugins do it — then has two files with the same path, and
Gradle refuses:

```
Execution failed for task ':app:mergeReleaseNativeLibs'.
> 2 files found with path 'lib/arm64-v8a/libonnxruntime.so'
```

Again release-only. Consumers can add `pickFirsts`, but then one of the two
bindings is calling a binary it was not built against, which is a coin flip
dressed up as a build setting.

Consuming the official AAR instead of vendoring the `.so` would make the
package compose with the rest of the ecosystem. If that is too large a change,
documenting the collision and the `pickFirsts` workaround in the README would
already save people the afternoon it costs to find.

### Context

We are building an Apache-2.0 set of Flutter packages for on-device document
capture, rectification and OCR, aimed at F-Droid and other independent
distributions. `onnxruntime_flutter` is how the rectification model runs; the
OCR plugin alongside it uses the AAR, which is how the two met.
