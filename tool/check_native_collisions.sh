#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Reports native libraries that more than one dependency wants to provide.
#
# Byrsa ships two independent bindings to ONNX Runtime: mobile_ocr uses the
# Java AAR, byrsa_restore uses the Dart FFI package, and both put a file called
# libonnxruntime.so into jniLibs. Gradle merges them and keeps exactly one,
# silently, with no warning at build time — so the binary that ends up in the
# APK may not be the one either binding was built against, and the symptom is a
# crash on a device rather than an error here.
#
# This does not fix that. It makes it visible.
#
#   tool/check_native_collisions.sh path/to/app.apk

set -euo pipefail

apk="${1:?usage: check_native_collisions.sh <apk>}"
[ -f "$apk" ] || { echo "No such APK: $apk" >&2; exit 2; }

echo "Native libraries in $(basename "$apk"):"
unzip -l "$apk" | awk '$4 ~ /^lib\/.*\.so$/ { printf "  %10.1f KB  %s\n", $1/1024, $4 }' | sort -k3

echo
echo "Names appearing in more than one ABI directory is normal."
echo "What is not visible here, and needs a device to settle, is which build of"
echo "libonnxruntime.so Gradle kept when two dependencies offered one."
