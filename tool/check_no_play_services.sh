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

set -euo pipefail

apk="${1:?usage: check_no_play_services.sh <apk>}"
[ -f "$apk" ] || { echo "No such APK: $apk" >&2; exit 2; }

forbidden='com/google/android/gms|com/google/mlkit|com/google/firebase'

hits=$(unzip -p "$apk" 'classes*.dex' | strings | grep -E "$forbidden" | sort -u | head -20 || true)

if [ -n "$hits" ]; then
  echo "FAIL: Play Services / ML Kit classes found in $apk:" >&2
  echo "$hits" >&2
  echo >&2
  echo "Something added a transitive dependency on Play Services. Find it with:" >&2
  echo "  ./gradlew :app:dependencies --configuration releaseRuntimeClasspath" >&2
  exit 1
fi

camera=$(unzip -p "$apk" 'classes*.dex' | strings | grep -c 'androidx/camera' || true)
echo "PASS: no Play Services in $apk (androidx.camera references: $camera)"
