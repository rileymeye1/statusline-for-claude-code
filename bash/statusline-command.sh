#!/usr/bin/env bash
# Claude Code status line (bash) — macOS / Linux / Git Bash.
# Row 1: Starship prompt (if available) or a built-in native prompt.
# Row 2: Model · Context bar · Plan · Session(5h) · Week(all).
# Config: ~/.claude/statusline.conf   (see statusline.conf.example)

input=$(cat)

# ===================== defaults (overridden by config) =====================
ROW1_SOURCE=auto
USE_NERD_FONT=auto
MODULES="directory git_branch git_status git_state nodejs python golang rust ruby java package aws sfdx time"
DIR_TRUNCATE=3
TIME_FORMAT=%T
SEPARATOR=" "
RIGHT_ALIGN=false      # true = flush-right Starship right_format (best-effort, may truncate)
RIGHT_MARGIN=3         # columns of slack reserved when RIGHT_ALIGN=true
BAR_WIDTH=10
CTX_YELLOW=70; CTX_RED=90
RL_YELLOW=70;  RL_RED=90
USAGE_TYPE_OVERRIDE=""

# Load config as data (KEY=VALUE), NOT by sourcing it — so a config that was
# copied/shared or written by another tool can never execute code on render.
# Only the known keys below are honored; everything else is ignored.
CONF="$HOME/.claude/statusline.conf"
if [ -f "$CONF" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    _line="${_line#"${_line%%[![:space:]]*}"}"                 # ltrim
    case "$_line" in ''|'#'*) continue ;; esac                 # skip blank/comment
    case "$_line" in *'='*) : ;; *) continue ;; esac           # need a '='
    _key="${_line%%=*}"; _val="${_line#*=}"
    _key="${_key%"${_key##*[![:space:]]}"}"; _key="${_key#"${_key%%[![:space:]]*}"}"  # trim key
    _val="${_val#"${_val%%[![:space:]]*}"}"; _val="${_val%"${_val##*[![:space:]]}"}"  # trim val
    case "$_val" in
      \"*\") _val="${_val%\"}"; _val="${_val#\"}" ;;            # strip "double quotes"
      \'*\') _val="${_val%\'}"; _val="${_val#\'}" ;;            # strip 'single quotes'
      *) _val="${_val%%#*}"; _val="${_val%"${_val##*[![:space:]]}"}" ;;  # strip inline comment
    esac
    case " ROW1_SOURCE USE_NERD_FONT MODULES DIR_TRUNCATE TIME_FORMAT SEPARATOR RIGHT_ALIGN RIGHT_MARGIN BAR_WIDTH CTX_YELLOW CTX_RED RL_YELLOW RL_RED USAGE_TYPE_OVERRIDE " in
      *" $_key "*) printf -v "$_key" '%s' "$_val" ;;
    esac
  done < "$CONF"
  unset _line _key _val
fi

# ===================== parse Claude Code JSON (stdin) ======================
cwd=$(echo "$input"       | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input"     | jq -r '.model.display_name // ""')
used_pct=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')
used_tok=$(echo "$input"  | jq -r '.context_window.total_input_tokens // empty')
win_size=$(echo "$input"  | jq -r '.context_window.context_window_size // empty')
five_hr=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# ===================== helpers =============================================
# c <ansi-code> <text> -> text wrapped in that SGR code + reset (real ESC bytes)
c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

# pct_code <pct> <yellow-threshold> <red-threshold> -> 32|33|31
pct_code() {
  if   [ "$1" -ge "$3" ]; then echo 31
  elif [ "$1" -ge "$2" ]; then echo 33
  else echo 32; fi
}

# fmt_tokens 704200 -> 704.2k ; 1000000 -> 1.0M
fmt_tokens() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then printf "%d.%dM" $((n/1000000)) $(((n%1000000)/100000))
  elif [ "$n" -ge 1000 ];    then printf "%d.%dk" $((n/1000))    $(((n%1000)/100))
  else printf "%d" "$n"; fi
}

# strip_wrappers: remove Starship's shell prompt-escape wrappers (%{ %} / \[ \])
strip_wrappers() {
  local s="$1"; s="${s//%\{/}"; s="${s//%\}/}"; s="${s//\\[/}"; s="${s//\\]/}"
  printf '%s' "$s"
}

# vlen: visible width of a string (strip ANSI SGR, count characters)
vlen() {
  local s; s=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
  printf '%s' "${#s}"
}

# term_cols: terminal width (COLUMNS, then tput, then 80)
term_cols() {
  local c="$COLUMNS"
  case "$c" in ''|*[!0-9]*) c=$(tput cols 2>/dev/null) ;; esac
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  printf '%s' "$c"
}

# has_files <name-or-glob>... -> 0 if any exists in $cwd
has_files() {
  local f
  for f in "$@"; do
    if [[ "$f" == *"*"* ]]; then
      compgen -G "$cwd/$f" >/dev/null 2>&1 && return 0
    else
      [ -e "$cwd/$f" ] && return 0
    fi
  done
  return 1
}

# ===================== Nerd Font detection (cached) ========================
detect_nerd() {
  local cache="$HOME/.claude/.statusline-nerdfont"
  if [ -f "$cache" ]; then cat "$cache"; return; fi
  local found=0 d
  if command -v fc-list >/dev/null 2>&1; then
    fc-list 2>/dev/null | grep -qi "nerd font" && found=1
  fi
  if [ "$found" = 0 ]; then
    for d in "$HOME/Library/Fonts" /Library/Fonts "$HOME/.local/share/fonts" \
             /usr/share/fonts /usr/local/share/fonts; do
      [ -d "$d" ] || continue
      if find "$d" -iname '*nerd*' -print -quit 2>/dev/null | grep -q .; then found=1; break; fi
    done
  fi
  local res=false; [ "$found" = 1 ] && res=true
  echo "$res" > "$cache" 2>/dev/null
  echo "$res"
}

NF=0
case "$USE_NERD_FONT" in
  true)  NF=1 ;;
  false) NF=0 ;;
  *)     [ "$(detect_nerd)" = true ] && NF=1 ;;
esac

# glyph <nerd> <ascii> -> whichever is active
glyph() { if [ "$NF" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# ===================== native prompt modules ===============================
# Each echoes a styled segment, or nothing if not applicable. Colors follow
# Starship-ish defaults; edit the codes here to taste.

mod_directory() {
  local p="$cwd"; [ -z "$p" ] && return
  case "$p" in
    "$HOME")   p="~" ;;
    # shellcheck disable=SC2088  # ~ is a literal for display here, not an expansion
    "$HOME"/*) p="~/${p#"$HOME"/}" ;;
  esac
  if [ "${DIR_TRUNCATE:-0}" -gt 0 ]; then
    local IFS='/'; read -ra segs <<< "$p"; unset IFS
    local n=${#segs[@]}
    if [ "$n" -gt "$DIR_TRUNCATE" ]; then
      local i out=""
      for ((i=n-DIR_TRUNCATE; i<n; i++)); do out+="/${segs[i]}"; done
      p="…${out}"
    fi
  fi
  local ro=""; [ -e "$cwd" ] && [ ! -w "$cwd" ] && ro=" $(glyph ' ' '[ro]')"
  c "1;36" "${p}${ro}"
}

mod_git_branch() {
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return
  local b
  b=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null) \
    || b=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  [ -z "$b" ] && return
  c "1;35" "$(glyph ' ' '')${b}"
}

mod_git_status() {
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return
  local out; out=$(git -C "$cwd" status --porcelain=v1 --branch 2>/dev/null) || return
  local ahead=0 behind=0 dirty=0 untracked=0 line
  while IFS= read -r line; do
    case "$line" in
      '## '*)
        [[ "$line" =~ ahead\ ([0-9]+)  ]] && ahead=${BASH_REMATCH[1]}
        [[ "$line" =~ behind\ ([0-9]+) ]] && behind=${BASH_REMATCH[1]}
        ;;
      '??'*) untracked=$((untracked+1)) ;;
      ?*)    dirty=$((dirty+1)) ;;
    esac
  done <<< "$out"
  local s=""
  [ "$behind"    -gt 0 ] && s+="$(glyph '⇣' 'v')${behind}"
  [ "$ahead"     -gt 0 ] && s+="$(glyph '⇡' '^')${ahead}"
  [ "$dirty"     -gt 0 ] && s+="$(glyph '✚' '!')"
  [ "$untracked" -gt 0 ] && s+="?"
  [ -z "$s" ] && return
  c "1;31" "$s"
}

mod_git_state() {
  local gd; gd=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null) || return
  [ -z "$gd" ] && return
  case "$gd" in /*) : ;; *) gd="$cwd/$gd" ;; esac
  local st=""
  { [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && st="REBASING"
  [ -f "$gd/MERGE_HEAD" ]       && st="MERGING"
  [ -f "$gd/CHERRY_PICK_HEAD" ] && st="CHERRY-PICKING"
  [ -f "$gd/REVERT_HEAD" ]      && st="REVERTING"
  [ -f "$gd/BISECT_LOG" ]       && st="BISECTING"
  [ -z "$st" ] && return
  c "1;33" "($st)"
}

mod_nodejs() {
  command -v node >/dev/null 2>&1 || return
  has_files package.json .nvmrc .node-version "*.js" "*.mjs" "*.cjs" "*.ts" || return
  local v; v=$(node --version 2>/dev/null); v=${v#v}
  [ -z "$v" ] && return
  c "1;32" "$(glyph ' ' 'node ')v${v}"
}

mod_python() {
  local bin=""
  if command -v python3 >/dev/null 2>&1; then bin=python3
  elif command -v python >/dev/null 2>&1; then bin=python; fi
  [ -z "$bin" ] && return
  has_files requirements.txt pyproject.toml Pipfile setup.py .python-version tox.ini "*.py" || return
  local v; v=$("$bin" --version 2>&1); v=${v#Python }
  [ -z "$v" ] && return
  c "1;33" "$(glyph ' ' 'py ')v${v}"
}

mod_golang() {
  command -v go >/dev/null 2>&1 || return
  has_files go.mod go.sum .go-version "*.go" || return
  local v; v=$(go version 2>/dev/null); v=${v#go version go}; v=${v%% *}
  [ -z "$v" ] && return
  c "1;36" "$(glyph ' ' 'go ')v${v}"
}

mod_rust() {
  command -v rustc >/dev/null 2>&1 || return
  has_files Cargo.toml "*.rs" || return
  local v; v=$(rustc --version 2>/dev/null | awk '{print $2}')
  [ -z "$v" ] && return
  c "1;31" "$(glyph ' ' 'rust ')v${v}"
}

mod_ruby() {
  command -v ruby >/dev/null 2>&1 || return
  has_files Gemfile .ruby-version "*.rb" || return
  local v; v=$(ruby --version 2>/dev/null | awk '{print $2}')
  [ -z "$v" ] && return
  c "1;31" "$(glyph ' ' 'rb ')v${v}"
}

mod_java() {
  command -v java >/dev/null 2>&1 || return
  has_files pom.xml build.gradle build.gradle.kts .sdkmanrc "*.java" "*.jar" "*.class" || return
  local v; v=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9._]+)".*/\1/')
  [ -z "$v" ] && return
  c "1;31" "$(glyph ' ' 'java ')v${v}"
}

mod_package() {
  local v=""
  if [ -f "$cwd/package.json" ]; then
    v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cwd/package.json" | head -1)
  elif [ -f "$cwd/Cargo.toml" ]; then
    v=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cwd/Cargo.toml" | head -1)
  elif [ -f "$cwd/pyproject.toml" ]; then
    v=$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cwd/pyproject.toml" | head -1)
  fi
  [ -z "$v" ] && return
  c "38;5;208" "$(glyph ' ' 'pkg ')v${v}"
}

mod_aws() {
  local prof="${AWS_VAULT:-${AWS_PROFILE:-}}" region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  [ -z "$prof" ] && [ -z "$region" ] && return
  local txt="$prof"; [ -n "$region" ] && txt="${txt:+$txt }($region)"
  c "1;33" "$(glyph ' ' 'aws ')${txt}"
}

mod_sfdx() {
  [ -f "$cwd/sfdx-project.json" ] || return
  local org="" cf
  for cf in "$cwd/.sf/config.json" "$cwd/.sfdx/sfdx-config.json"; do
    [ -f "$cf" ] || continue
    org=$(sed -n 's/.*"\(target-org\|defaultusername\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' "$cf" | head -1)
    [ -n "$org" ] && break
  done
  [ -z "$org" ] && return
  c "1;34" "with org $(glyph '  ' 'sf ')${org}"
}

mod_time() { c "0" "$(date +"$TIME_FORMAT")"; }

build_native_row1() {
  local out="" seg m
  for m in $MODULES; do
    # filesystem-reading modules need a real cwd; skip them if it's empty
    # (a malformed payload) so we never inspect the process working directory.
    case "$m" in
      directory|git_branch|git_status|git_state|nodejs|python|golang|rust|ruby|java|package|sfdx)
        [ -n "$cwd" ] || continue ;;
    esac
    case "$m" in
      directory)  seg=$(mod_directory) ;;
      git_branch) seg=$(mod_git_branch) ;;
      git_status) seg=$(mod_git_status) ;;
      git_state)  seg=$(mod_git_state) ;;
      nodejs)     seg=$(mod_nodejs) ;;
      python)     seg=$(mod_python) ;;
      golang)     seg=$(mod_golang) ;;
      rust)       seg=$(mod_rust) ;;
      ruby)       seg=$(mod_ruby) ;;
      java)       seg=$(mod_java) ;;
      package)    seg=$(mod_package) ;;
      aws)        seg=$(mod_aws) ;;
      sfdx)       seg=$(mod_sfdx) ;;
      time)       seg=$(mod_time) ;;
      *)          seg="" ;;
    esac
    [ -n "$seg" ] && { [ -n "$out" ] && out+="$SEPARATOR"; out+="$seg"; }
  done
  printf '%s' "$out"
}

# ===================== Row 1: choose Starship or native ====================
STARSHIP_BIN=$(command -v starship 2>/dev/null)
if [ -z "$STARSHIP_BIN" ]; then
  for p in /opt/homebrew/bin/starship /usr/local/bin/starship /usr/bin/starship "$HOME/.cargo/bin/starship"; do
    [ -x "$p" ] && STARSHIP_BIN="$p" && break
  done
fi

use_starship=0
case "$ROW1_SOURCE" in
  native)   use_starship=0 ;;
  starship) [ -n "$STARSHIP_BIN" ] && use_starship=1 ;;
  *)        [ -n "$STARSHIP_BIN" ] && use_starship=1 ;;   # auto
esac

row1=""
if [ "$use_starship" = 1 ] && [ -n "$cwd" ]; then
  row1=$(strip_wrappers "$("$STARSHIP_BIN" prompt --path "$cwd" 2>/dev/null | tr -d '\n')")
  row1="${row1%❯*}"           # drop trailing prompt character module
  # Starship's right_format (e.g. the clock) -> right-align it to the terminal width.
  rightp=$(strip_wrappers "$("$STARSHIP_BIN" prompt --right --path "$cwd" 2>/dev/null | tr -d '\n')")
  rightp=$(printf '%s' "$rightp" | sed 's/[[:space:]]*$//')   # trim trailing space
  if [ -n "$rightp" ]; then
    reset=$(printf '\033[0m')
    if [ "$RIGHT_ALIGN" = true ]; then
      # Best-effort flush-right. Claude Code does not expose the status line's
      # true render width (it's narrower than $COLUMNS) and Nerd Font glyphs
      # occupy 2 cells but count as 1, so RIGHT_MARGIN leaves slack to avoid
      # truncation. Increase it if the right side gets cut off.
      pad=$(( $(term_cols) - ${RIGHT_MARGIN:-3} - $(vlen "$row1") - $(vlen "$rightp") ))
      [ "$pad" -lt 1 ] && pad=1
      printf -v gap '%*s' "$pad" ''
      row1="${row1}${reset}${gap}${rightp}"
    else
      # Inline: always fully visible (recommended).
      row1="${row1}${reset}${SEPARATOR}${rightp}"
    fi
  fi
fi
[ -z "$row1" ] && row1=$(build_native_row1)

# ===================== Row 2: Claude info ==================================
# plan / usage type (auto-detected from ~/.claude.json oauthAccount.seatTier)
usageType="$USAGE_TYPE_OVERRIDE"
if [ -z "$usageType" ] && [ -f "$HOME/.claude.json" ]; then
  seat=$(jq -r '.oauthAccount.seatTier // empty' "$HOME/.claude.json" 2>/dev/null)
  org=$(jq -r '.oauthAccount.organizationType // empty' "$HOME/.claude.json" 2>/dev/null)
  case "$seat" in
    free*)        usageType="Free" ;;
    pro*)         usageType="Pro" ;;
    max_20x*)     usageType="Max 20x" ;;
    max_5x*)      usageType="Max 5x" ;;
    max*)         usageType="Max" ;;
    team*)        usageType="Team" ;;
    enterprise*)  usageType="Enterprise" ;;
    ?*)           usageType="$seat" ;;
    *) case "$org" in
         claude_team*)       usageType="Team" ;;
         claude_enterprise*) usageType="Enterprise" ;;
         claude_max*)        usageType="Max" ;;
         claude_pro*)        usageType="Pro" ;;
       esac ;;
  esac
fi

row2=""
# r2add: space-join a segment (skips empties, so no stray leading space)
r2add() { [ -n "$1" ] && row2="${row2:+$row2 }$1"; }
# r2dot: join with a "·" separator, or start the row if nothing precedes it
r2dot() { [ -z "$1" ] && return; if [ -n "$row2" ]; then row2="$row2 $(c 90 '·') $1"; else row2="$1"; fi; }

[ -n "$model" ] && r2add "$(c 35 "$model")"

if [ -n "$used_pct" ]; then
  up=${used_pct%.*}; [ -z "$up" ] && up=0
  filled=$(( up * BAR_WIDTH / 100 ))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  [ "$filled" -lt 0 ] && filled=0
  bar=""; for ((i=0; i<BAR_WIDTH; i++)); do [ "$i" -lt "$filled" ] && bar+="█" || bar+="░"; done
  code=$(pct_code "$up" "$CTX_YELLOW" "$CTX_RED")
  label=""; [ -n "$used_tok" ] && [ -n "$win_size" ] && label=" $(fmt_tokens "$used_tok") / $(fmt_tokens "$win_size")"
  r2add "$(c "$code" "${bar} ${up}%${label}")"
fi

[ -n "$usageType" ] && r2dot "$(c 35 "$usageType")"
if [ -n "$five_hr" ]; then
  fh=${five_hr%.*}; [ -z "$fh" ] && fh=0
  r2dot "$(c "$(pct_code "$fh" "$RL_YELLOW" "$RL_RED")" "Session(5h) ${fh}%")"
fi
if [ -n "$seven_day" ]; then
  wd=${seven_day%.*}; [ -z "$wd" ] && wd=0
  r2dot "$(c "$(pct_code "$wd" "$RL_YELLOW" "$RL_RED")" "Week(all) ${wd}%")"
fi

# ===================== output: row 1 then row 2 ============================
printf '%s\033[0m\n' "$row1"
printf '%s'          "$row2"
