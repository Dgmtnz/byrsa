#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Turns a draft in docs/upstream/ into the body that goes in someone else's
# issue tracker, and prints the `gh` command that would post it.
#
#     tool/upstream_ready.sh                 # write all of them to out/
#     tool/upstream_ready.sh --show doclens  # print one to stdout
#
# The drafts carry two audiences in one file. A maintainer needs the evidence
# and the proposal; this repository needs to know which version was examined,
# when it was last re-verified, and which UNVERIFIED row it answers. The second
# audience's notes are wrapped in `<!-- internal -->` and stripped here, so
# there is one source and no second copy to drift — the same rule that
# `models.json` is a symlink for.
#
# It stops at printing the command. Filing these is a person's decision: they
# go out under a name, into somebody else's project, and whoever's account
# sends them is the one who has to answer the reply.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/upstream/out
mkdir -p "$OUT"

render() {
  # Drop the licence header, the internal blocks, and the leading title (the
  # title goes in `gh --title`, not in the body).
  awk '
    /^<!--$/            { in_comment = 1 }
    in_comment          { if ($0 ~ /-->/) in_comment = 0; next }
    /<!-- internal -->/ { in_internal = 1; next }
    /<!-- \/internal -->/ { in_internal = 0; next }
    in_internal         { next }
    { print }
  ' "$1" | sed '/^---$/{x;/./d;x;h};/./{x;s/.*//;x}' | cat -s
}

declare -A REPOS=(
  [doclens-play-services]=govindmaheshwari2/doclens
  [mobile-ocr-pub-dev]=ente-io/mobile_ocr
  [onnxruntime-flutter-compilesdk]=gtbluesky/onnxruntime_flutter
)

if [ "${1:-}" = "--show" ]; then
  render "docs/upstream/${2}"*.md
  exit 0
fi

for draft in docs/upstream/*.md; do
  base=$(basename "$draft" .md)
  [ "$base" = "README" ] && continue
  [ -n "${REPOS[$base]:-}" ] || continue
  render "$draft" > "$OUT/$base.md"
  echo "$OUT/$base.md  →  ${REPOS[$base]}"
done

cat <<'NOTE'

Ready. Each file is the issue body, with this repository's own notes removed.

To file one, from this directory, with your own GitHub account:

  gh issue create --repo <owner/repo> --title "<title>" --body-file <path>

The title of each is the line marked **Title:** inside the draft. The order to
file them in is in docs/upstream/README.md, and it matters: doclens first.

Nothing above sends anything. That step is yours.
NOTE
