#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Runs the application's own OCR over the synthetic corpus on a connected
# Android phone, and pulls the recognised text back off it.
#
#     tool/ocr_on_device.sh [count]        # default: 5 documents
#
# Why a script rather than tapping through it once: a character error rate from
# one page is noise. The project's headline number needs many pages, and doing
# that by hand is how a measurement stops being repeatable.
#
# What it cannot do is skip the photo picker. The application has only a
# MAIN/LAUNCHER intent filter, so an image cannot be handed to it directly; the
# import goes through the system picker and this drives it by coordinate. That
# is the fragile part, and it is fragile on purpose rather than hidden: if the
# picker's layout differs on another phone, the taps are the first thing to fix.

set -euo pipefail
cd "$(dirname "$0")/.."

PKG=dev.byrsa.byrsa
CORPUS=harness/dataset/synthetic
COUNT="${1:-5}"
OUT=harness/out/device-ocr

# The device check comes first, and nothing that talks to adb runs above it:
# under `set -o pipefail` a failing `adb shell` in a pipeline kills the script
# before it can say why, which is exactly the unhelpful failure this guards.
if ! adb devices | sed -n '2p' | grep -q 'device$'; then
  echo "No device attached." >&2
  echo "  Plug the phone in, enable USB debugging, and accept the prompt on" >&2
  echo "  its screen. 'adb devices' should list it as 'device', not" >&2
  echo "  'unauthorized' or 'offline'." >&2
  exit 1
fi

SCREEN_W=$(adb shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1 | cut -dx -f1)
: "${SCREEN_W:=1080}"
echo "Device: $(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r') " \
     "· Android $(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')" \
     "· battery $(adb shell dumpsys battery 2>/dev/null | awk '/^  level/{print $2}')%"

# Recognition on, without tapping: the preference lives in the database the
# application already has open, so it is set before the application starts.
echo "Turning on automatic recognition…"
adb shell am force-stop "$PKG"
adb shell "run-as $PKG sh -c 'command -v sqlite3 >/dev/null && \
  sqlite3 files/library.db \"INSERT INTO settings(key,value) VALUES(\\\"autoOcr\\\",\\\"true\\\") \
  ON CONFLICT(key) DO UPDATE SET value=excluded.value;\"'" 2>/dev/null \
  || echo "  (no sqlite3 on the device; turn 'Recognise text automatically' on by hand)"

mkdir -p "$OUT"
mapfile -t DOCS < <(python3 - "$CORPUS" "$COUNT" <<'PY'
import json, sys
docs = json.load(open(f'{sys.argv[1]}/manifest.json'))['documents']
# Clean pages first: a recogniser that cannot read an undamaged page tells us
# more, sooner, than one that cannot read a page with a hand across it.
docs.sort(key=lambda d: len([c for c in d['conditions'] if c != 'dense-text']))
for d in docs[:int(sys.argv[2])]:
    print(d['id'])
PY
)

for id in "${DOCS[@]}"; do
  echo "--- $id"
  adb shell rm -f /sdcard/Pictures/byrsa-probe.jpg
  adb push -q "$CORPUS/images/$id.jpg" /sdcard/Pictures/byrsa-probe.jpg >/dev/null
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d file:///sdcard/Pictures/byrsa-probe.jpg >/dev/null 2>&1
  adb shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
  sleep 4
  # Import: the photo button, then the newest item in the picker.
  adb shell input tap $((SCREEN_W * 91 / 100)) $((SCREEN_W * 192 / 100))
  sleep 4
  adb shell input tap $((SCREEN_W * 16 / 100)) $((SCREEN_W * 30 / 100))
  echo "    waiting for restoration and recognition…"
  sleep 25
done

echo "Pulling the library…"
adb shell "run-as $PKG cat files/library.db" > "$OUT/library.db" 2>/dev/null
if [ ! -s "$OUT/library.db" ]; then
  echo "Could not read the database. Is this a debug build?" >&2
  exit 1
fi

python3 - "$OUT" "$CORPUS" <<'PY'
import json, sqlite3, sys, pathlib
out, corpus = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
db = sqlite3.connect(out / 'library.db')
rows = db.execute(
    'SELECT id, original_path, restored, text, words FROM pages ORDER BY id').fetchall()
print(f'\n{len(rows)} page(s) in the library')
recognised = 0
for pid, path, restored, text, words in rows:
    has = bool((text or '').strip())
    recognised += has
    print(f'  page {pid}: restored={bool(restored)} text={len(text or "")} chars '
          f'words={"yes" if words else "no"}')
    if has:
        print('    ' + (text or '')[:160].replace('\n', ' | '))
(out / 'pages.json').write_text(json.dumps(
    [{'id': r[0], 'path': r[1], 'restored': bool(r[2]), 'text': r[3]} for r in rows],
    ensure_ascii=False, indent=1), encoding='utf-8')
print(f'\n{recognised}/{len(rows)} page(s) carry recognised text -> {out}/pages.json')
if recognised == 0:
    print('\nNo text at all. That is a result: it means the OCR never ran, or ran '
          'and returned nothing. Check logcat for the ONNX session opening.')
PY
