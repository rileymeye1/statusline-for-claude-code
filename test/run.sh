#!/usr/bin/env bash
# Smoke tests for the status line. Feeds fixture payloads through the script(s)
# and asserts on the ANSI-stripped output. Runs the bash implementation always,
# and the PowerShell one too if `pwsh` is on PATH — so parity drift surfaces.
#
# Usage:  bash test/run.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BASH_SL="$ROOT/bash/statusline-command.sh"
PS_SL="$ROOT/powershell/statusline-command.ps1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME/.claude"
printf '{"oauthAccount":{"seatTier":"team_standard"}}\n' > "$HOME/.claude.json"

# Deterministic config: native prompt, ASCII, a small module set.
cat > "$HOME/.claude/statusline.conf" <<'CONF'
ROW1_SOURCE=native
USE_NERD_FONT=false
MODULES="directory git_branch nodejs package time"
SEPARATOR=" "
CONF

# A sample project that triggers the git / node / package modules.
PROJ="$WORK/proj"; mkdir -p "$PROJ"
( cd "$PROJ"
  git init -q && git config user.email t@t.co && git config user.name t
  printf '{"name":"demo","version":"9.9.9"}\n' > package.json
  echo 'console.log(1)' > index.js
  git add -A && git commit -qm init ) >/dev/null 2>&1

pass=0; fail=0
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# render <engine> <json> -> ANSI-stripped output
render() {
  case "$1" in
    bash) printf '%s' "$2" | bash "$BASH_SL" | strip ;;
    pwsh) printf '%s' "$2" | pwsh -NoProfile -File "$PS_SL" | strip ;;
  esac
}

check() { # check <desc> <cond 0/1>
  if [ "$2" = 0 ]; then echo "  ok   $1"; pass=$((pass+1))
  else echo "  FAIL $1"; fail=$((fail+1)); fi
}

run_suite() {
  local engine="$1" out
  echo "== $engine =="

  # 1) Native project render: dir + branch + node + package versions present.
  out=$(render "$engine" '{"workspace":{"current_dir":"'"$PROJ"'"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":50,"total_input_tokens":500000,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":5}}}')
  case "$out" in *"proj"*)   check "row1 shows directory" 0 ;; *) check "row1 shows directory" 1 ;; esac
  case "$out" in *"v9.9.9"*) check "package version shown" 0 ;; *) check "package version shown" 1 ;; esac
  case "$out" in *"50%"*)    check "context percent shown" 0 ;; *) check "context percent shown" 1 ;; esac
  case "$out" in *"Team"*)   check "plan detected"        0 ;; *) check "plan detected"        1 ;; esac
  case "$out" in *"Session(5h) 10%"*) check "session shown" 0 ;; *) check "session shown" 1 ;; esac

  # 2) Row 2 has no stray leading space (no model, no context -> plan first).
  out=$(render "$engine" '{"context_window":{"used_percentage":40,"total_input_tokens":4000,"context_window_size":1000000}}' | tail -1)
  case "$out" in " "*) check "row2 no leading space" 1 ;; *) check "row2 no leading space" 0 ;; esac

  # 3) Empty payload doesn't crash and doesn't leak a git branch from the CWD.
  out=$(render "$engine" '{}')
  case "$out" in *"git:"*|*"master"*|*"main"*) check "empty payload: no git leak" 1 ;; *) check "empty payload: no git leak" 0 ;; esac
}

# Config-parse safety (bash only): a config must never execute code.
echo "== bash: config safety =="
MARKER="$WORK/EXECUTED"
cat > "$HOME/.claude/statusline.conf" <<CONF
ROW1_SOURCE=native
USE_NERD_FONT=false
MODULES="time"
USAGE_TYPE_OVERRIDE=\$(touch "$MARKER")
CONF
printf '{"model":{"display_name":"M"}}' | bash "$BASH_SL" >/dev/null 2>&1
if [ -e "$MARKER" ]; then check "config is not executed" 1; else check "config is not executed" 0; fi
# restore the deterministic config for the suites
cat > "$HOME/.claude/statusline.conf" <<'CONF'
ROW1_SOURCE=native
USE_NERD_FONT=false
MODULES="directory git_branch nodejs package time"
SEPARATOR=" "
CONF

run_suite bash
if command -v pwsh >/dev/null 2>&1; then run_suite pwsh; else echo "== pwsh: SKIPPED (not installed) =="; fi

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
