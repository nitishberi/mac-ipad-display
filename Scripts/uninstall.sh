#!/usr/bin/env bash
# Remove LaunchAgent, hooks, and binary. Keeps config/logs unless --purge.
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

if [[ -x "$BINDIR/mac-ipad-display" ]]; then
  "$BINDIR/mac-ipad-display" uninstall-agent || true
fi

rm -f "$BINDIR/mac-ipad-display"
rm -f "$HOME/.login_success.mac-ipad-display" "$HOME/.login_failure.mac-ipad-display"

# Remove our hook lines from loginwatcher scripts if present
for f in "$HOME/.login_success" "$HOME/.login_failure"; do
  if [[ -f "$f" ]]; then
    grep -v 'mac-ipad-display notify' "$f" > "$f.tmp" || true
    mv "$f.tmp" "$f"
    chmod +x "$f" 2>/dev/null || true
  fi
done

if [[ "$PURGE" -eq 1 ]]; then
  rm -rf "$HOME/Library/Application Support/MacIPadDisplay"
  rm -rf "$HOME/Library/Logs/MacIPadDisplay"
  echo "Purged config and logs."
fi

echo "Uninstalled mac-ipad-display."
