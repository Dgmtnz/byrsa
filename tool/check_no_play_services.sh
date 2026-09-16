#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Fails if a built APK contains Google Play Services or ML Kit.
#
# This is the one claim the whole distribution strategy rests on (plan §0.1),
# and it is the kind of claim that quietly stops being true when a transitive
# dependency changes. So it is a test, not a promise.
#
#   tool/check_no_play_services.sh path/to/app.apk
#
# It checks the MANIFEST as well as the code, and that is not belt and braces.
# Until 2026-09-16 it read `classes*.dex` only, and printed PASS on a release
# APK whose merged manifest declared
# `com.google.android.gms.metadata.ModuleDependencies` — a service injected by
# `image_picker_android` whose sole purpose is to ask Play services for a
# module. An integration can be entirely declarative; grepping the code for it
# finds nothing.

set -euo pipefail

apk="${1:?usage: check_no_play_services.sh <apk>}"
[ -f "$apk" ] || { echo "No such APK: $apk" >&2; exit 2; }

# `com.google.android.play` is Play Core, which is proprietary too and which a
# distribution's scanner also looks for.
forbidden='com/google/android/gms|com/google/mlkit|com/google/firebase|com/google/android/play'
# Dots rather than slashes: a manifest names classes the Java way.
forbidden_manifest='com\.google\.android\.gms|com\.google\.mlkit|com\.google\.firebase|com\.google\.android\.play'

failed=0

hits=$(unzip -p "$apk" 'classes*.dex' | strings | grep -E "$forbidden" | sort -u | head -20 || true)
if [ -n "$hits" ]; then
  echo "FAIL: Play Services / ML Kit classes found in the code of $apk:" >&2
  echo "$hits" >&2
  failed=1
fi

# The manifest is stored as binary XML, so the strings live as UTF-16.
manifest=$(unzip -p "$apk" AndroidManifest.xml 2>/dev/null \
  | strings -e l | grep -E "$forbidden_manifest" | sort -u | head -20 || true)
if [ -n "$manifest" ]; then
  echo "FAIL: Play Services referenced in the MANIFEST of $apk:" >&2
  echo "$manifest" >&2
  echo >&2
  echo "A plugin has injected a manifest entry. Find which with:" >&2
  echo "  grep -n '<the class name>' app/build/app/outputs/logs/manifest-merger-*-report.txt" >&2
  echo "and remove it with tools:node=\"remove\" in the application's manifest." >&2
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  echo >&2
  echo "For a code-level dependency, find it with:" >&2
  echo "  ./gradlew :app:dependencies --configuration releaseRuntimeClasspath" >&2
  exit 1
fi

camera=$(unzip -p "$apk" 'classes*.dex' | strings | grep -c 'androidx/camera' || true)
echo "PASS: no Play Services in the code or the manifest of $apk"
# Reported, not asserted. R8 renames what it keeps, so this count collapses on a
# release build — 1720 in a debug APK against 60 in the release one — and a
# threshold on it would be a threshold on how hard the optimiser worked.
echo "      (androidx.camera references: $camera)"
