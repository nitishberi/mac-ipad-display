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

HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"

ensure_hook() {
  local file="$1"
  local event="$2"
  local title="$3"
  local line="$BIN notify $event \"$title\" \"Host=$HOST method=\${AUTH_METHOD:-unknown} failures=\${TOTAL_FAILURES:-0}\""
  touch "$file"
  chmod +x "$file"
  if grep -q 'mac-ipad-display notify' "$file" 2>/dev/null; then
    echo "Hook already present in $file"
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

EOF
