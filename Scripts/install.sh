#!/usr/bin/env bash
# Install MacIPadDisplay on a Mac (macOS 14+). Run from the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"

echo "==> Building mac-ipad-display"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/mac-ipad-display"

echo "==> Installing to $BINDIR"
mkdir -p "$BINDIR"
cp "$BIN" "$BINDIR/mac-ipad-display"
chmod +x "$BINDIR/mac-ipad-display"

# Ensure ~/.local/bin is on PATH hint
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "NOTE: add $BINDIR to your PATH (e.g. in ~/.zshrc)" ;;
esac

if [[ ! -f "$HOME/Library/Application Support/MacIPadDisplay/config.json" ]]; then
  echo "==> Writing default config"
  "$BINDIR/mac-ipad-display" init-config
else
  echo "==> Config already exists — leaving it alone"
fi

echo "==> Installing LaunchAgent (menu bar + supervisor)"
"$BINDIR/mac-ipad-display" install-agent --menubar

echo "==> Installing loginwatcher notify hooks (optional scripts)"
"$ROOT/Scripts/install-hooks.sh" || true

cat <<EOF

Done.

Next steps:
  1. Edit config:  open "\$HOME/Library/Application Support/MacIPadDisplay/config.json"
     Set iPadName, ntfyURL (or barkURL), and options.
  2. Install ntfy or Bark on your iPhone and subscribe/test:
       mac-ipad-display notify-test
  3. Pair Sidecar once with a monitor attached, then enable auto-login
     (see docs/SETUP.md).
  4. Test: mac-ipad-display list && mac-ipad-display connect --wait 30

EOF
