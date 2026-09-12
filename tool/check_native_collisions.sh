#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Asserts that the ONNX Runtime inside an APK is the one both bindings can use.
#
# Byrsa ships two independent bindings to ONNX Runtime, and both offer a file
# called libonnxruntime.so:
#
#   * mobile_ocr, through the official Java AAR   (onnxruntime-android 1.27.0)
#   * byrsa_restore, through the Dart FFI package (its own build, 1.15.1)
#
# Exactly one survives the merge, and which one is not cosmetic. mobile_ocr's
# JNI shim is compiled against the AAR's version; pair it with the older
# library and OCR breaks at run time. The root build.gradle.kts drops the Dart
# package's copy at source so the AAR's always wins (DECISIONS.md D-037).
#
# The reason this check exists rather than a comment: when the wrong one wins,
# the APK gets 13 MB SMALLER. Nothing looks wrong. A build that improved a
# number is exactly how that ships.
#
#   tool/check_native_collisions.sh path/to/app.apk [expected-version]
#
# Must be run against a RELEASE APK. Debug packages both libraries without
# complaint, so the whole failure mode is invisible there.

set -euo pipefail

apk="${1:?usage: check_native_collisions.sh <apk> [expected-version]}"
expected="${2:-1.27.0}"

[ -f "$apk" ] || { echo "No such APK: $apk" >&2; exit 2; }
command -v strings >/dev/null || {
  echo "FAIL: 'strings' is not installed, so this check cannot run." >&2
  echo "      Install binutils. A check that silently passes is worse than none." >&2
  exit 2
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

mapfile -t libraries < <(unzip -Z1 "$apk" 'lib/*/libonnxruntime.so' 2>/dev/null || true)

if [ "${#libraries[@]}" -eq 0 ]; then
  echo "FAIL: $(basename "$apk") contains no libonnxruntime.so." >&2
  echo "      Both the OCR engine and page flattening need it. If ONNX was" >&2
  echo "      deliberately dropped, delete this check with the same commit." >&2
  exit 1
fi

status=0
for entry in "${libraries[@]}"; do
  unzip -p "$apk" "$entry" > "$workdir/lib.so"
  version="$(strings -a "$workdir/lib.so" | grep -oE '^1\.[0-9]{1,2}\.[0-9]+$' | sort -u | head -1)"
  size="$(stat -c%s "$workdir/lib.so")"

  # Byte counts, not megabytes: the shell's printf parses floats through the
  # locale, and this ran on a machine where the decimal separator is a comma.
  if [ "$version" = "$expected" ]; then
    printf '  ok    %-34s %-8s %10d bytes\n' "$entry" "$version" "$size"
  else
    status=1
    printf '  WRONG %-34s %-8s %10d bytes\n' "$entry" "${version:-unreadable}" "$size" >&2
  fi
done

if [ "$status" -ne 0 ]; then
  cat >&2 <<MESSAGE

FAIL: the APK carries ONNX Runtime $expected somewhere it should not, or the
      wrong build won the jniLibs merge.

      Expected every lib/*/libonnxruntime.so to report $expected — the version
      mobile_ocr's JNI shim was compiled against.

      If mobile_ocr has bumped its AAR, this failing is the check doing its
      job: someone has to confirm the Dart FFI package still works against the
      new runtime, then pass the new version here and in
      app/android/build.gradle.kts.

      If the version reads 1.15.1, the Dart package's vendored copy won. The
      exclusion in app/android/build.gradle.kts stopped being applied — most
      likely because the afterEvaluate now registers after Flutter's
      evaluationDependsOn(":app"), which is too late to run at all.
MESSAGE
  exit 1
fi

echo "PASS: one ONNX Runtime $expected in $(basename "$apk"), shared by both bindings."
