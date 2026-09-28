#!/usr/bin/env bash
# Build MacIPadDisplay.app from the Swift package (run on macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacIPadDisplay"
BIN_NAME="mac-ipad-display"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building release binary"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$BIN_NAME"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/$BIN_NAME"
chmod +x "$MACOS/$BIN_NAME"

# Launcher so double-click / open -a starts menu bar mode
cat > "$MACOS/$APP_NAME" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/mac-ipad-display" --menubar
EOF
chmod +x "$MACOS/$APP_NAME"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/config.example.json" "$RESOURCES/config.example.json"
cp "$ROOT/README.md" "$RESOURCES/README.md" 2>/dev/null || true

# Ad-hoc sign so Gatekeeper is less noisy on personal machines
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" || true
fi

echo "App bundle: $APP"
