#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Asserts that `byrsa_restore` produces the SAME BYTES on the Dart VM and
# through dart2js.
#
# This exists because it did not, and nothing would have caught it. On the VM
# `>>` on a negative int is an arithmetic shift; under dart2js it treats the
# receiver as unsigned 32-bit, so `-1 >> 8` is `-1` in one and `4294967295` in
# the other. The package guarded the negative case with
# `math.max(0, position >> 8)`, which clamps nothing when the value has already
# become huge and positive — an index of 2^35 into a list of 48. Worse, the
# bilinear interpolations subtracted one sample from another and shifted the
# difference, so on the web they silently produced wrong pixels rather than
# failing.
#
# `byrsa_restore` is published as pure Dart that runs anywhere. That claim is
# only worth making if something checks it, so this runs in CI.

set -euo pipefail
cd "$(dirname "$0")/.."

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "Compiling the parity probe with dart2js…"
dart compile js tool/web_parity_probe.dart -o "$out/probe.js" >/dev/null

dart run tool/web_parity_probe.dart > "$out/vm.txt"
node "$out/probe.js" > "$out/js.txt"

if diff -u "$out/vm.txt" "$out/js.txt"; then
  echo "PASS: the VM and dart2js restore identically, byte for byte."
else
  echo "FAIL: restoration differs between the Dart VM and the web." >&2
  echo "      Look for '>>' applied to a value that can be negative: the two" >&2
  echo "      platforms do not agree on what that means." >&2
  exit 1
fi
