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
ORDER="${2:-clean}"   # clean | damaged
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
  sqlite3 app_flutter/library.db \"INSERT INTO settings(key,value) VALUES(\\\"autoOcr\\\",\\\"true\\\") \
  ON CONFLICT(key) DO UPDATE SET value=excluded.value;\"'" 2>/dev/null \
  || echo "  (no sqlite3 on the device; turn 'Recognise text automatically' on by hand)"

mkdir -p "$OUT"
mapfile -t DOCS < <(python3 - "$CORPUS" "$COUNT" "$ORDER" <<'PY'
import json, sys
docs = json.load(open(f'{sys.argv[1]}/manifest.json'))['documents']
damage = lambda d: len([c for c in d['conditions'] if c != 'dense-text'])
# Clean pages first by default: a recogniser that cannot read an undamaged page
# tells us more, sooner, than one that cannot read a page with a hand across it.
# `damaged` reverses it, and that is the half that decides whether any of this is
# worth shipping -- so every published figure has to say which order produced it.
docs.sort(key=damage, reverse=sys.argv[3] == 'damaged')
for d in docs[:int(sys.argv[2])]:
    print(d['id'])
PY
)

for id in "${DOCS[@]}"; do
  echo "--- $id"
  # A NEW FILE NAME EVERY TIME, and this is not tidiness. Pushing each page to
  # one reused path gave MediaStore a single row to update, and the picker kept
  # handing back the bytes of the first page imported — five documents went
  # through the pipeline and produced five copies of one result, all exactly 236
  # characters. A harness that silently measures the same thing N times is worse
  # than one that fails, because it produces a number.
  target="/sdcard/Pictures/byrsa-$id.jpg"
  adb shell rm -f "$target"
  adb push -q "$CORPUS/images/$id.jpg" "$target" >/dev/null
  # `adb push` keeps the source file's timestamp, which would file the page
  # somewhere in the middle of whoever's gallery this is. Dated now, it is
  # always the first tile in the picker — so the script taps our page and never
  # goes looking through anybody's photographs.
  adb shell touch "$target"
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file://$target" >/dev/null 2>&1
  sleep 3
  adb shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
  sleep 4
  # Import: the photo button, the newest tile, then Add. One page per pass and
  # never a multi-select: the picker shows whoever's gallery this is, and the
  # only tile this script is entitled to touch is the one it just put there.
  adb shell input tap $((SCREEN_W * 91 / 100)) $((SCREEN_W * 192 / 100))
  sleep 5
  adb shell input tap $((SCREEN_W * 12 / 100)) $((SCREEN_W * 64 / 100))
  sleep 2
  adb shell input tap $((SCREEN_W * 82 / 100)) $((SCREEN_W * 206 / 100))
  sleep 6

  # Restoration and recognition run when the document is opened, not when it is
  # imported, so the newest row in the library has to be tapped as well.
  adb shell input tap $((SCREEN_W * 46 / 100)) $((SCREEN_W * 42 / 100))
  echo "    waiting for restoration and recognition…"
  sleep 40
  adb shell input keyevent KEYCODE_BACK
  sleep 2
done

echo "Pulling the library…"
adb shell "run-as $PKG cat app_flutter/library.db" > "$OUT/library.db" 2>/dev/null
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
