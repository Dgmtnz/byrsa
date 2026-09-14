<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# onnxruntime_flutter: the Android module cannot be built in release any more

<!-- internal -->
**Repository:** `github.com/gtbluesky/onnxruntime_flutter`
**Version examined:** `onnxruntime` 1.4.1 on pub.dev — note the **package** is
`onnxruntime`, the repository is `onnxruntime_flutter`
**Status:** draft, ready to file — **expect no reply, and file it anyway**

> **Re-verified 2026-09-14.** `compileSdkVersion 33` is still there at `HEAD`,
> alongside `minSdkVersion 21`, so the claim stands exactly as written.
>
> What the re-check changed is the expectation, not the content. The project's
> **last commit was 2024-12-23** — twenty-one months ago — the last pub.dev
> release was **1.4.1 on 2024-03-27**, and there are **37 open issues**, several
> from 2026 with no maintainer reply. It is not archived, so filing is still the
> correct move, but it should be filed knowing it is **documentary rather than
> relational**: it puts an evidenced diagnosis and a one-line fix in the place
> the next person will look, and 37 open issues suggests there are a lot of next
> people.
>
> Searched before writing: **no existing issue mentions `compileSdk`**, so this
> is not a duplicate. Issue #28 concerns a `dlopen` failure, which is a different
> problem from the merge collision described in the second half below.
>
> Because a reply is unlikely, put the workaround consumers need in the issue
> body itself rather than leaving it for a follow-up comment — it is done below.

<!-- /internal -->
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
