#!/usr/bin/env bash
# Wire loginwatcher (~/.login_success / ~/.login_failure) to mac-ipad-display notify.
set -euo pipefail

BIN="${BIN:-$HOME/.local/bin/mac-ipad-display}"
if [[ ! -x "$BIN" ]]; then
  BIN="$(command -v mac-ipad-display || true)"
fi
if [[ -z "${BIN}" || ! -x "$BIN" ]]; then
  echo "mac-ipad-display not found — build/install first" >&2
  exit 1
fi

CONFIG="${HOME}/Library/Application Support/MacIPadDisplay/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "Config missing — run: mac-ipad-display init-config" >&2
  exit 1
fi

# Read notifyAuthToken from config (python for reliable JSON; fallback to plutil/sed-less jq).
AUTH=""
if command -v python3 >/dev/null 2>&1; then
  AUTH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("notifyAuthToken") or "")' "$CONFIG")"
elif command -v jq >/dev/null 2>&1; then
  AUTH="$(jq -r '.notifyAuthToken // empty' "$CONFIG")"
fi
if [[ -z "$AUTH" ]]; then
  echo "notifyAuthToken missing — run: mac-ipad-display init-config" >&2
  exit 1
fi

HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cd 'A-Za-z0-9._ -' | cut -c1-64)"
BIN_SAFE="$BIN"
case "$BIN_SAFE" in
  *\'* | *\"* | *\$* | *\`* | *\\* | *$'\n'* )
    echo "Refusing to install hooks: binary path contains unsafe characters: $BIN_SAFE" >&2
    exit 1
    ;;
esac

ensure_hook() {
  local file="$1"
  local event="$2"
  local title="$3"
  local line
  # Auth token passed via env so it is not argv-visible to every `ps` reader on some systems
  # still appears in the script file — chmod 700 below.
  line="$(printf 'MAC_IPAD_DISPLAY_NOTIFY_AUTH=%q %q notify --auth %q %q %q "Host=%s method=${AUTH_METHOD:-unknown} failures=${TOTAL_FAILURES:-0}"' \
    "$AUTH" "$BIN_SAFE" "$AUTH" "$event" "$title" "$HOST_SAFE")"
  touch "$file"
  chmod 700 "$file"
  if grep -q 'mac-ipad-display notify' "$file" 2>/dev/null; then
    # Refresh existing hook lines so auth stays current
    grep -v 'mac-ipad-display notify' "$file" > "${file}.tmp" || true
    {
      cat "${file}.tmp"
      echo "# MacIPadDisplay safety notify"
      echo "$line"
    } > "$file"
    rm -f "${file}.tmp"
    chmod 700 "$file"
    echo "Updated hook in $file"
  else
    {
      echo ""
      echo "# MacIPadDisplay safety notify"
      echo "$line"
    } >> "$file"
    echo "Added hook to $file"
  fi
}

ensure_hook "$HOME/.login_success" "login_success" "Mac mini — unlocked"
ensure_hook "$HOME/.login_failure" "login_failure" "Mac mini — unlock FAILED"

cat <<EOF

If you have not installed loginwatcher yet:
  brew install ramana/tap/loginwatcher   # or follow https://github.com/RamanaRaj7/loginwatcher

loginwatcher runs ~/.login_success and ~/.login_failure for you.
Hooks require notifyAuthToken from config.json (chmod 600).

EOF
