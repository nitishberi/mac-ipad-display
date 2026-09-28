#!/bin/sh
# Example loginwatcher failure hook.
BIN="$HOME/.local/bin/mac-ipad-display"
[ -x "$BIN" ] || BIN="$(command -v mac-ipad-display)"
[ -x "$BIN" ] || exit 0
HOST="$(scutil --get ComputerName 2>/dev/null || hostname | tr -cd 'A-Za-z0-9._ -' | cut -c1-64)"
exec "$BIN" notify login_failure "Mac mini — unlock FAILED" "Host=$HOST method=${AUTH_METHOD:-unknown} failures=${TOTAL_FAILURES:-0}"
