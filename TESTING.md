# Testing & Verification

A manual checklist to confirm the status line works and to exercise each config
option. You **don't** need to restart Claude Code to test — you can pipe sample
JSON straight into the script and read the output.

- **Config changes** (edits to `~/.claude/statusline.conf`) take effect on the
  next render — either restart Claude Code, or just re-run the commands below,
  which read the config fresh each time.
- Commands assume the script is installed at `~/.claude/statusline-command.sh`
  (macOS/Linux) or `~/.claude/statusline-command.ps1` (Windows).

---

## Automated smoke tests

A quick harness feeds fixture payloads through the script(s) and asserts on the output:

```bash
bash test/run.sh
```

It always exercises the **bash** implementation and, if `pwsh` is on `PATH`, the **PowerShell** one too — so bash⇄PowerShell parity drift surfaces. It exits non-zero if any check fails (usable in CI). The manual checklist below remains the way to eyeball colors, glyphs, and layout.

---

## 0. Test harness

Save a reusable sample payload once:

**bash (macOS / Linux / Git Bash)**
```bash
SL=~/.claude/statusline-command.sh
JSON='{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.8 (1M context)"},"context_window":{"used_percentage":45,"total_input_tokens":452000,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30},"seven_day":{"used_percentage":12}}}'

# Render (with colors):
echo "$JSON" | bash "$SL"; echo
# Render (ANSI stripped, easier to read/diff):
echo "$JSON" | bash "$SL" | sed 's/\x1b\[[0-9;]*m//g'; echo
```

**PowerShell (Windows)**
```powershell
$SL = "$HOME\.claude\statusline-command.ps1"
$JSON = '{"workspace":{"current_dir":"' + ($PWD.Path -replace '\\','/') + '"},"model":{"display_name":"Opus 4.8 (1M context)"},"context_window":{"used_percentage":45,"total_input_tokens":452000,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30},"seven_day":{"used_percentage":12}}}'

# Render (with colors):
$JSON | powershell -NoProfile -File $SL; ""
# Render (ANSI stripped):
($JSON | powershell -NoProfile -File $SL) -replace "$([char]27)\[[0-9;]*m",''
```

Expected shape (two rows):
```
<your prompt>
Opus 4.8 (1M context) ████░░░░░░ 45% 452.0k / 1.0M · Team · Session(5h) 30% · Week(all) 12%
```

---

## 1. Prerequisites

- [ ] `git --version` works (needed for git modules / native prompt).
- [ ] **bash only:** `jq --version` works.
- [ ] Optional: `starship --version` works (row 1 uses it when present).
- [ ] The status-line command is wired up: `statusLine` exists in
      `~/.claude/settings.json` and points at the installed script.

---

## 2. Row 2 — Claude info

Vary the payload and confirm each piece.

- [ ] **Model** — `model.display_name` shows at the start of row 2.
- [ ] **Context bar + tokens** — bar length tracks `used_percentage`; label reads
      `used / limit` (e.g. `452.0k / 1.0M`).
- [ ] **Context window size adapts** — set `context_window_size` to `200000`;
      label should read `.../ 200.0k` and the bar should fill against 200k.
- [ ] **Context color thresholds** — with defaults (yellow 70 / red 90):
  - `used_percentage: 50` → **green**
  - `used_percentage: 75` → **yellow**
  - `used_percentage: 95` → **red**
- [ ] **Plan** — auto-detected label (Team/Pro/Max/Enterprise/Free) from
      `~/.claude.json`. Absent file → no plan shown (no crash).
- [ ] **Session(5h) / Week(all)** — show `rate_limits.*.used_percentage`, each
      colored independently by the same thresholds. Omit `rate_limits` → both
      hidden gracefully.

Quick color sweep (bash):
```bash
for p in 50 75 95; do
  echo "{\"model\":{\"display_name\":\"M\"},\"context_window\":{\"used_percentage\":$p,\"total_input_tokens\":$((p*10000)),\"context_window_size\":1000000}}" \
  | bash ~/.claude/statusline-command.sh | sed 's/\x1b\[[0-9;]*m//g'; echo " <- $p%"
done
```

---

## 3. Row 1 — prompt source (`ROW1_SOURCE`)

Edit `~/.claude/statusline.conf`, set the value, re-run the harness.

- [ ] `ROW1_SOURCE=starship` (Starship installed) → row 1 matches your terminal prompt.
- [ ] `ROW1_SOURCE=native` → row 1 is the built-in prompt (see §5).
- [ ] `ROW1_SOURCE=auto` → Starship if installed, else native.
- [ ] **Fallback:** with `auto` and Starship *not* installed (or temporarily rename it),
      row 1 falls back to the native prompt with no error.
- [ ] **Starship `right_format`** (e.g. a `[time]` clock) shows. Default
      `RIGHT_ALIGN=false` → inline, right after the prompt (always fully visible).
- [ ] **`RIGHT_ALIGN=true`** → best-effort flush-right. Claude Code doesn't expose
      the status line's true render width (it's narrower than `$COLUMNS`) and Nerd
      Font glyphs count as 1 char but occupy 2 cells, so the right side **may get
      truncated** — increase `RIGHT_MARGIN` until it fits. Inline is the reliable choice.

---

## 4. Nerd Font toggle (`USE_NERD_FONT`)

- [ ] `USE_NERD_FONT=false` → native prompt uses ASCII labels (`node`, `git:`, `!?`).
- [ ] `USE_NERD_FONT=true` → native prompt uses Nerd Font glyphs (need a Nerd Font
      in your terminal, or you'll see boxes — that's expected).
- [ ] `USE_NERD_FONT=auto` → glyphs only if a Nerd Font is installed.
  - Check the cache: `cat ~/.claude/.statusline-nerdfont` → `true` or `false`.
  - Re-detect: `rm ~/.claude/.statusline-nerdfont` then re-run.

---

## 5. Native prompt modules (`MODULES`)

Set `ROW1_SOURCE=native`, then test in relevant directories. A module shows only
when its trigger files exist, so `cd` into a matching project first.

- [ ] **directory** — shows current dir; honors `DIR_TRUNCATE` (see §6).
- [ ] **git_branch** — in a git repo, shows the branch.
- [ ] **git_status** — make an edit + an untracked file → dirty/untracked markers
      (`!` / `?`, or `✚`/`?` with glyphs); commit ahead of upstream → `^N` / `⇡N`.
- [ ] **git_state** — start a merge/rebase → shows `(MERGING)` / `(REBASING)`.
- [ ] **nodejs** — dir with `package.json` → `node vX.Y.Z`.
- [ ] **python** — dir with `pyproject.toml`/`*.py` → `py vX.Y.Z`.
- [ ] **golang** — dir with `go.mod`/`*.go` → `go vX`.
- [ ] **rust** — dir with `Cargo.toml` → `rust vX`.
- [ ] **ruby** — dir with `Gemfile`/`*.rb` → `rb vX`.
- [ ] **java** — dir with `pom.xml`/`*.java` → `java vX`.
- [ ] **package** — dir with `package.json`/`Cargo.toml`/`pyproject.toml` → `pkg vX`.
- [ ] **aws** — set `AWS_PROFILE`/`AWS_REGION` → shows profile/region.
- [ ] **sfdx** — dir with `sfdx-project.json` + `.sf/config.json` → `with org <name>`.
- [ ] **time** — shows the clock (format from `TIME_FORMAT`).
- [ ] **Toggle off = faster** — remove a name from `MODULES`; confirm it disappears.

Scaffold a quick multi-module test dir (bash):
```bash
d=$(mktemp -d); cd "$d"
git init -q && git config user.email t@t.co && git config user.name t
printf '{"name":"demo","version":"1.2.3"}' > package.json
echo "x" > index.js && git add -A && git commit -qm init && echo untracked > new.txt
echo "$JSON" | sed "s#$PWD#$d#" | bash ~/.claude/statusline-command.sh | sed 's/\x1b\[[0-9;]*m//g'; echo
```

---

## 6. Other config knobs

- [ ] `DIR_TRUNCATE=1` → directory shows only the last segment; `0` → full path.
- [ ] `TIME_FORMAT=%R` → clock shows `HH:MM` instead of `HH:MM:SS`.
- [ ] `SEPARATOR=" | "` → row-1 modules separated by ` | `.
- [ ] `BAR_WIDTH=20` → context bar is wider.
- [ ] `CTX_YELLOW` / `CTX_RED` / `RL_YELLOW` / `RL_RED` → thresholds change colors.
- [ ] `USAGE_TYPE_OVERRIDE=Team` → forces the plan label regardless of detection.

---

## 7. Edge cases (should never crash)

- [ ] Empty input: `echo '{}' | bash ~/.claude/statusline-command.sh` → prints
      something minimal, no errors.
- [ ] Non-git directory → git modules simply omit.
- [ ] Missing `~/.claude.json` → plan label omitted.
- [ ] Very deep path → directory truncates cleanly with a leading `…`.

---

## 8. Cross-platform sanity

- [ ] **macOS/Linux/Git Bash:** `bash bash/install.sh` completes; a new session shows both rows.
- [ ] **Windows:** `.\powershell\install.ps1` completes; a new session shows both rows.
- [ ] Block characters `█ ░` and `·` render (not boxes) — needs a modern terminal font.
- [ ] Re-running an installer preserves an existing `statusline.conf` and other
      `settings.json` keys, and writes a `*.bak-<timestamp>`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `.ps1` won't run on Windows (`UnauthorizedAccess`) | Run `powershell -ExecutionPolicy Bypass -File .\powershell\install.ps1`, or right-click → *Run with PowerShell* |
| Row 1 empty or wrong on Windows | PowerShell path — confirm `statusLine.command` uses `powershell -NoProfile -File ...` |
| Boxes instead of icons | No Nerd Font active in the terminal → set `USE_NERD_FONT=false` |
| Native prompt feels slow | Trim `MODULES` (language version checks are the cost) |
| `jq: command not found` (bash) | Install jq, or use the PowerShell version |
| Plan label wrong/stale | It reflects `~/.claude.json`'s last profile fetch; set `USAGE_TYPE_OVERRIDE` |
| Colors show as `[0m` literals | Terminal not interpreting ANSI (rare); check terminal settings |
