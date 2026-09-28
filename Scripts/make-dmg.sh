#!/usr/bin/env bash
# Create a distributable DMG containing MacIPadDisplay.app (run on macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(grep -E 'programVersion\s*=' Sources/MacIPadDisplay/main.swift | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/')}"
APP_NAME="MacIPadDisplay"
VOL_NAME="MacIPadDisplay $VERSION"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG="$DIST/MacIPadDisplay-$VERSION.dmg"
APP="$DIST/$APP_NAME.app"

chmod +x "$ROOT/Scripts/make-app.sh"
"$ROOT/Scripts/make-app.sh"

echo "==> Staging DMG contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Optional: drop a short install note on the disk image
cat > "$STAGE/README.txt" <<EOF
MacIPadDisplay $VERSION
=======================

1. Drag MacIPadDisplay.app to Applications.
2. Open it once (right-click → Open if Gatekeeper warns — ad-hoc signed).
3. Menu bar → Open Config… and set iPadName + ntfyURL (or barkURL).
4. Menu bar → Send Test Notification.
5. See in-app Resources/README or https://github.com/nitishberi/mac-ipad-display for SETUP (auto-login).

CLI (optional):
  /Applications/MacIPadDisplay.app/Contents/MacOS/mac-ipad-display install-agent --menubar
EOF

echo "==> Creating DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"
ls -lh "$DMG"
echo "DMG: $DMG"
