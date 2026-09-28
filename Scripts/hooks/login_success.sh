#!/bin/sh
# Example loginwatcher success hook (prefer Scripts/install-hooks.sh to generate).
BIN="$HOME/.local/bin/mac-ipad-display"
[ -x "$BIN" ] || BIN="$(command -v mac-ipad-display)"
[ -x "$BIN" ] || exit 0
CONFIG="$HOME/Library/Application Support/MacIPadDisplay/config.json"
AUTH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("notifyAuthToken") or "")' "$CONFIG" 2>/dev/null || true)"
[ -n "$AUTH" ] || exit 0
HOST="$(scutil --get ComputerName 2>/dev/null || hostname | tr -cd 'A-Za-z0-9._ -' | cut -c1-64)"
exec "$BIN" notify --auth "$AUTH" login_success "Mac mini — unlocked" "Host=$HOST method=${AUTH_METHOD:-unknown}"
