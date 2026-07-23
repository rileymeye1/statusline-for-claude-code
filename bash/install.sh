#!/usr/bin/env bash
# Installer for the Claude Code status line — macOS / Linux / Windows (Git Bash).
# Requires: jq. Safe to re-run; backs up any existing script and settings.json.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/statusline-command.sh"
CONF_SRC="$HERE/../statusline.conf.example"   # shared config lives at repo root
CLAUDE_DIR="$HOME/.claude"
SCRIPT_PATH="$CLAUDE_DIR/statusline-command.sh"
CONF_PATH="$CLAUDE_DIR/statusline.conf"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S)

echo "Installing Claude Code status line (bash)..."

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: 'jq' is required but not installed."
  echo "  macOS:  brew install jq"
  echo "  Debian: sudo apt-get install jq"
  echo "  (Windows users without jq: use install.ps1 in PowerShell instead.)"
  exit 1
fi
[ -f "$SRC" ] || { echo "ERROR: cannot find $SRC"; exit 1; }

mkdir -p "$CLAUDE_DIR"

if [ -f "$SCRIPT_PATH" ]; then
  cp "$SCRIPT_PATH" "$SCRIPT_PATH.bak-$STAMP"
  echo "  backed up existing script -> $SCRIPT_PATH.bak-$STAMP"
fi
cp "$SRC" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
echo "  installed script  -> $SCRIPT_PATH"

# Config: install only if absent, so we never clobber the user's edits.
if [ -f "$CONF_SRC" ]; then
  if [ -f "$CONF_PATH" ]; then
    echo "  config exists     -> $CONF_PATH (left as-is)"
  else
    cp "$CONF_SRC" "$CONF_PATH"
    echo "  installed config  -> $CONF_PATH"
  fi
fi

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
tmp=$(mktemp)
jq --arg cmd "bash $SCRIPT_PATH" \
   '.statusLine = {"type":"command","command":$cmd}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "  updated settings  -> $SETTINGS (backup: $SETTINGS.bak-$STAMP)"
echo
echo "Done. Restart Claude Code (or start a new session) to see the status line."
