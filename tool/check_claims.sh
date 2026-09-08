#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
# SPDX-License-Identifier: Apache-2.0
#
# Guards the claims discipline in CONTRIBUTING.md.
#
# The project's most valuable property is that nothing it says has been made
# up, and the way that property dies is one convenient sentence at a time. So
# the rules are enforced by a script rather than by remembering them.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { echo "FAIL: $1" >&2; fail=1; }

# 1. The network guarantee must be stated the true way, never the attractive
#    false way (plan §4.8).
# The filter lets through lines that are *about* not making the claim, which
# is how the README and this script explain the rule.
if grep -rniE 'no (network|internet) permission|asks for no network|zero network' \
      --include='*.md' --include='*.dart' --include='*.arb' . 2>/dev/null \
      | grep -viE 'would be false|do not say|never say|must not|check_claims'; then
  note "found a 'no network permission' claim. The build declares INTERNET for
      model downloads; the true and stronger sentence is in README.md."
fi

# 2. No iOS performance or parity claims, since no iOS hardware exists here.
if grep -rniE '(on iOS|iPhone)[^.]{0,80}(ms|milliseconds|fps|benchmark|parity|as fast)' \
      --include='*.md' . 2>/dev/null | grep -v UNVERIFIED.md; then
  note "found an iOS performance claim. Measure it on hardware first, or put
      it in UNVERIFIED.md."
fi

# 3. Every unverified row has to name the command that would settle it.
missing=$(awk -F'|' '/^\| U-[0-9]/ { if (NF < 5) print $0 }' UNVERIFIED.md || true)
if [ -n "$missing" ]; then
  note "an UNVERIFIED.md row has no command that would close it:
$missing"
fi

# 4. The 50-document figure is fixed and must not drift between documents.
if grep -rnE '\[N\] documents|\[N\] documentos' --include='*.md' . 2>/dev/null; then
  note "a placeholder document count survived. The number is 50, everywhere."
fi

[ "$fail" -eq 0 ] && echo "PASS: claims discipline holds."
exit "$fail"
