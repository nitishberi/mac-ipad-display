#!/bin/sh
# Example loginwatcher success hook (installed via Scripts/install-hooks.sh).
BIN="$HOME/.local/bin/mac-ipad-display"
[ -x "$BIN" ] || BIN="$(command -v mac-ipad-display)"
[ -x "$BIN" ] || exit 0
HOST="$(scutil --get ComputerName 2>/dev/null || hostname | tr -cd 'A-Za-z0-9._ -' | cut -c1-64)"
exec "$BIN" notify login_success "Mac mini — unlocked" "Host=$HOST method=${AUTH_METHOD:-unknown}"
