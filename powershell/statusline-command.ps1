# Claude Code status line (PowerShell) — Windows.
# Row 1: Starship prompt (if available) or a built-in native prompt.
# Row 2: Model · Context bar · Plan · Session(5h) · Week(all).
# Config: ~/.claude/statusline.conf   (see statusline.conf.example)
# No external dependencies (uses built-in ConvertFrom-Json).

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ESC = [char]27
function Ansi($code, $text) { '{0}[{1}m{2}{0}[0m' -f $ESC, $code, $text }

# ===================== read stdin JSON =====================================
$raw = [Console]::In.ReadToEnd()
$data = $null
try { if ($raw) { $data = $raw | ConvertFrom-Json } } catch { $data = $null }

$cwd      = if ($data.workspace.current_dir) { $data.workspace.current_dir } else { $data.cwd }
$model    = $data.model.display_name
$usedPct  = $data.context_window.used_percentage
$usedTok  = $data.context_window.total_input_tokens
$winSize  = $data.context_window.context_window_size
$fiveHr   = $data.rate_limits.five_hour.used_percentage
$sevenDay = $data.rate_limits.seven_day.used_percentage

# ===================== load config (KEY=VALUE) =============================
function Load-Conf($path) {
  $h = @{}
  if (Test-Path $path) {
    foreach ($line in (Get-Content $path)) {
      $t = $line.Trim()
      if ($t -eq '' -or $t.StartsWith('#')) { continue }
      $i = $t.IndexOf('=')
      if ($i -lt 1) { continue }
      $k = $t.Substring(0, $i).Trim()
      $v = $t.Substring($i + 1).Trim()
      $quoted = $false
      if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
        $v = $v.Substring(1, $v.Length - 2); $quoted = $true
      }
      if (-not $quoted) { $v = ($v -replace '\s*#.*$', '').Trim() }   # strip inline comment
      $h[$k] = $v
    }
  }
  return $h
}
$conf = Load-Conf (Join-Path $HOME '.claude/statusline.conf')
function Cfg($k, $def) { if ($conf.ContainsKey($k) -and $null -ne $conf[$k]) { $conf[$k] } else { $def } }

$ROW1_SOURCE   = Cfg 'ROW1_SOURCE' 'auto'
$USE_NERD_FONT = Cfg 'USE_NERD_FONT' 'auto'
$MODULES       = (Cfg 'MODULES' 'directory git_branch git_status git_state nodejs python golang rust ruby java package aws sfdx time') -split '\s+' | Where-Object { $_ -ne '' }
$DIR_TRUNCATE  = [int](Cfg 'DIR_TRUNCATE' 3)
$TIME_FORMAT   = Cfg 'TIME_FORMAT' '%T'
$SEPARATOR     = Cfg 'SEPARATOR' ' '
$RIGHT_ALIGN   = ((Cfg 'RIGHT_ALIGN' 'false') -eq 'true')
$RIGHT_MARGIN  = [int](Cfg 'RIGHT_MARGIN' 3)
$BAR_WIDTH     = [int](Cfg 'BAR_WIDTH' 10)
$CTX_YELLOW    = [int](Cfg 'CTX_YELLOW' 70); $CTX_RED = [int](Cfg 'CTX_RED' 90)
$RL_YELLOW     = [int](Cfg 'RL_YELLOW' 70);  $RL_RED  = [int](Cfg 'RL_RED' 90)
$USAGE_TYPE_OVERRIDE = Cfg 'USAGE_TYPE_OVERRIDE' ''

# ===================== helpers =============================================
function PctCode($p, $y, $r) { if ($p -ge $r) { '31' } elseif ($p -ge $y) { '33' } else { '32' } }

function Format-Tokens($n) {
  $n = [double]$n
  if ($n -ge 1000000) { return ('{0}.{1}M' -f [math]::Floor($n / 1000000), [math]::Floor(($n % 1000000) / 100000)) }
  if ($n -ge 1000)    { return ('{0}.{1}k' -f [math]::Floor($n / 1000),    [math]::Floor(($n % 1000) / 100)) }
  return "$([int]$n)"
}

function Has-Files([string[]]$pats) {
  foreach ($f in $pats) {
    if ($f.Contains('*')) {
      if (Get-ChildItem -Path $cwd -Filter $f -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
    } elseif (Test-Path (Join-Path $cwd $f)) { return $true }
  }
  return $false
}

function Cmd-Exists($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Run-Ver($exe, [string[]]$a) { try { return ((& $exe @a 2>&1 | Out-String).Trim()) } catch { return '' } }
function Git-Out([string[]]$a) {
  try { $o = & git -C $cwd @a 2>$null; if ($LASTEXITCODE -eq 0) { return ($o | Out-String).Trim() } } catch {}
  return $null
}

function Strip-Wrappers($s) { $s -replace '%\{', '' -replace '%\}', '' -replace '\\\[', '' -replace '\\\]', '' }
function Strip-Ansi($s) { $s -replace ('{0}\[[0-9;]*m' -f $ESC), '' }
function Term-Cols {
  if ($env:COLUMNS -and ($env:COLUMNS -match '^\d+$')) { return [int]$env:COLUMNS }
  try { $w = [Console]::WindowWidth; if ($w -gt 0) { return $w } } catch {}
  return 80
}

function Convert-TimeFmt($f) {
  # Map common strftime specifiers to .NET format. Uses case-SENSITIVE replace
  # (-creplace) so %m (month) and %M (minute), %y and %Y, etc. don't collide.
  $map = [ordered]@{
    '%Y' = 'yyyy'; '%y' = 'yy'; '%m' = 'MM'; '%d' = 'dd'; '%e' = 'd'
    '%T' = 'HH:mm:ss'; '%R' = 'HH:mm'; '%H' = 'HH'; '%M' = 'mm'; '%S' = 'ss'
    '%I' = 'hh'; '%p' = 'tt'
  }
  $out = $f
  foreach ($k in $map.Keys) { $out = $out -creplace [regex]::Escape($k), $map[$k] }
  if (-not $out) { $out = 'HH:mm:ss' }
  return $out
}

# ===================== Nerd Font detection (cached) ========================
function Detect-Nerd {
  $cache = Join-Path $HOME '.claude/.statusline-nerdfont'
  if (Test-Path $cache) { return (Get-Content -Raw $cache).Trim() }
  $found = $false
  $dirs = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Fonts'),
    'C:/Windows/Fonts',
    (Join-Path $HOME '.local/share/fonts'),
    (Join-Path $HOME 'Library/Fonts'),
    '/Library/Fonts', '/usr/share/fonts', '/usr/local/share/fonts'
  )
  foreach ($d in $dirs) {
    if ($d -and (Test-Path $d)) {
      if (Get-ChildItem -Path $d -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'nerd' } | Select-Object -First 1) { $found = $true; break }
    }
  }
  $res = if ($found) { 'true' } else { 'false' }
  try { Set-Content -Path $cache -Value $res -NoNewline } catch {}
  return $res
}
switch ($USE_NERD_FONT) {
  'true'  { $NF = $true }
  'false' { $NF = $false }
  default { $NF = ((Detect-Nerd) -eq 'true') }
}
function Glyph($n, $a) { if ($NF) { $n } else { $a } }

# ===================== native prompt modules ===============================
function Mod-Directory {
  $p = ($cwd -replace '\\', '/'); if (-not $p) { return $null }
  $h = ($HOME -replace '\\', '/')
  if ($p -eq $h) { $p = '~' } elseif ($p.StartsWith($h)) { $p = '~' + $p.Substring($h.Length) }
  if ($DIR_TRUNCATE -gt 0) {
    $segs = $p.Split('/') | Where-Object { $_ -ne '' }
    if ($segs.Count -gt $DIR_TRUNCATE) {
      $tail = $segs[($segs.Count - $DIR_TRUNCATE)..($segs.Count - 1)]
      $p = '…/' + ($tail -join '/')
    }
  }
  Ansi '1;36' $p
}

function Mod-GitBranch {
  if (-not (Git-Out @('rev-parse', '--git-dir'))) { return $null }
  $b = Git-Out @('symbolic-ref', '--short', 'HEAD')
  if (-not $b) { $b = Git-Out @('rev-parse', '--short', 'HEAD') }
  if (-not $b) { return $null }
  Ansi '1;35' ((Glyph ' ' '') + $b)
}

function Mod-GitStatus {
  if (-not (Git-Out @('rev-parse', '--git-dir'))) { return $null }
  $out = Git-Out @('status', '--porcelain=v1', '--branch')
  if ($null -eq $out) { return $null }
  $ahead = 0; $behind = 0; $dirty = 0; $untracked = 0
  foreach ($line in ($out -split "`n")) {
    if ($line.StartsWith('## ')) {
      if ($line -match 'ahead (\d+)')  { $ahead = [int]$Matches[1] }
      if ($line -match 'behind (\d+)') { $behind = [int]$Matches[1] }
    } elseif ($line.StartsWith('??')) { $untracked++ }
    elseif ($line.Trim() -ne '')      { $dirty++ }
  }
  $s = ''
  if ($behind -gt 0)    { $s += (Glyph '⇣' 'v') + $behind }
  if ($ahead -gt 0)     { $s += (Glyph '⇡' '^') + $ahead }
  if ($dirty -gt 0)     { $s += (Glyph '✚' '!') }
  if ($untracked -gt 0) { $s += '?' }
  if ($s -eq '') { return $null }
  Ansi '1;31' $s
}

function Mod-GitState {
  $gd = Git-Out @('rev-parse', '--git-dir')
  if (-not $gd) { return $null }
  if ($gd -notmatch '^([A-Za-z]:)?[\\/]') { $gd = Join-Path $cwd $gd }
  $st = ''
  if ((Test-Path (Join-Path $gd 'rebase-merge')) -or (Test-Path (Join-Path $gd 'rebase-apply'))) { $st = 'REBASING' }
  if (Test-Path (Join-Path $gd 'MERGE_HEAD'))       { $st = 'MERGING' }
  if (Test-Path (Join-Path $gd 'CHERRY_PICK_HEAD')) { $st = 'CHERRY-PICKING' }
  if (Test-Path (Join-Path $gd 'REVERT_HEAD'))      { $st = 'REVERTING' }
  if (Test-Path (Join-Path $gd 'BISECT_LOG'))       { $st = 'BISECTING' }
  if ($st -eq '') { return $null }
  Ansi '1;33' "($st)"
}

function Mod-Nodejs {
  if (-not (Cmd-Exists 'node')) { return $null }
  if (-not (Has-Files @('package.json', '.nvmrc', '.node-version', '*.js', '*.mjs', '*.cjs', '*.ts'))) { return $null }
  $v = (Run-Ver 'node' @('--version')) -replace '^v', ''
  if (-not $v) { return $null }
  Ansi '1;32' ((Glyph ' ' 'node ') + 'v' + $v)
}

function Mod-Python {
  $bin = if (Cmd-Exists 'python3') { 'python3' } elseif (Cmd-Exists 'python') { 'python' } else { '' }
  if (-not $bin) { return $null }
  if (-not (Has-Files @('requirements.txt', 'pyproject.toml', 'Pipfile', 'setup.py', '.python-version', 'tox.ini', '*.py'))) { return $null }
  $v = (Run-Ver $bin @('--version')) -replace '^Python ', ''
  if (-not $v) { return $null }
  Ansi '1;33' ((Glyph ' ' 'py ') + 'v' + $v)
}

function Mod-Golang {
  if (-not (Cmd-Exists 'go')) { return $null }
  if (-not (Has-Files @('go.mod', 'go.sum', '.go-version', '*.go'))) { return $null }
  $v = (Run-Ver 'go' @('version')) -replace '^go version go', ''
  $v = ($v -split '\s+')[0]
  if (-not $v) { return $null }
  Ansi '1;36' ((Glyph ' ' 'go ') + 'v' + $v)
}

function Mod-Rust {
  if (-not (Cmd-Exists 'rustc')) { return $null }
  if (-not (Has-Files @('Cargo.toml', '*.rs'))) { return $null }
  $v = ((Run-Ver 'rustc' @('--version')) -split '\s+')[1]
  if (-not $v) { return $null }
  Ansi '1;31' ((Glyph ' ' 'rust ') + 'v' + $v)
}

function Mod-Ruby {
  if (-not (Cmd-Exists 'ruby')) { return $null }
  if (-not (Has-Files @('Gemfile', '.ruby-version', '*.rb'))) { return $null }
  $v = ((Run-Ver 'ruby' @('--version')) -split '\s+')[1]
  if (-not $v) { return $null }
  Ansi '1;31' ((Glyph ' ' 'rb ') + 'v' + $v)
}

function Mod-Java {
  if (-not (Cmd-Exists 'java')) { return $null }
  if (-not (Has-Files @('pom.xml', 'build.gradle', 'build.gradle.kts', '.sdkmanrc', '*.java', '*.jar', '*.class'))) { return $null }
  $out = (Run-Ver 'java' @('-version'))
  $v = ''
  if ($out -match '"([0-9._]+)"') { $v = $Matches[1] }
  if (-not $v) { return $null }
  Ansi '1;31' ((Glyph ' ' 'java ') + 'v' + $v)
}

function Mod-Package {
  $v = ''
  $pj = Join-Path $cwd 'package.json'; $cargo = Join-Path $cwd 'Cargo.toml'; $pyp = Join-Path $cwd 'pyproject.toml'
  if (Test-Path $pj) { try { $v = (Get-Content -Raw $pj | ConvertFrom-Json).version } catch {} }
  elseif (Test-Path $cargo) { $m = Select-String -Path $cargo -Pattern '^version\s*=\s*"([^"]+)"' | Select-Object -First 1; if ($m) { $v = $m.Matches[0].Groups[1].Value } }
  elseif (Test-Path $pyp)   { $m = Select-String -Path $pyp   -Pattern '^version\s*=\s*"([^"]+)"' | Select-Object -First 1; if ($m) { $v = $m.Matches[0].Groups[1].Value } }
  if (-not $v) { return $null }
  Ansi '38;5;208' ((Glyph ' ' 'pkg ') + 'v' + $v)
}

function Mod-Aws {
  $prof = if ($env:AWS_VAULT) { $env:AWS_VAULT } elseif ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { '' }
  $region = if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { '' }
  if (-not $prof -and -not $region) { return $null }
  $txt = $prof
  if ($region) { if ($txt) { $txt = "$txt ($region)" } else { $txt = "($region)" } }
  Ansi '1;33' ((Glyph ' ' 'aws ') + $txt)
}

function Mod-Sfdx {
  if (-not (Test-Path (Join-Path $cwd 'sfdx-project.json'))) { return $null }
  $org = ''
  foreach ($cf in @((Join-Path $cwd '.sf/config.json'), (Join-Path $cwd '.sfdx/sfdx-config.json'))) {
    if (Test-Path $cf) {
      try {
        $j = Get-Content -Raw $cf | ConvertFrom-Json
        if ($j.'target-org') { $org = $j.'target-org' } elseif ($j.defaultusername) { $org = $j.defaultusername }
      } catch {}
      if ($org) { break }
    }
  }
  if (-not $org) { return $null }
  Ansi '1;34' ('with org ' + (Glyph '  ' 'sf ') + $org)
}

function Mod-Time { Ansi '0' ((Get-Date).ToString((Convert-TimeFmt $TIME_FORMAT))) }

function Build-NativeRow1 {
  $parts = @()
  $fsModules = @('directory', 'git_branch', 'git_status', 'git_state', 'nodejs', 'python', 'golang', 'rust', 'ruby', 'java', 'package', 'sfdx')
  foreach ($m in $MODULES) {
    if (($m -in $fsModules) -and -not $cwd) { continue }   # need a real cwd
    $seg = switch ($m) {
      'directory'  { Mod-Directory }
      'git_branch' { Mod-GitBranch }
      'git_status' { Mod-GitStatus }
      'git_state'  { Mod-GitState }
      'nodejs'     { Mod-Nodejs }
      'python'     { Mod-Python }
      'golang'     { Mod-Golang }
      'rust'       { Mod-Rust }
      'ruby'       { Mod-Ruby }
      'java'       { Mod-Java }
      'package'    { Mod-Package }
      'aws'        { Mod-Aws }
      'sfdx'       { Mod-Sfdx }
      'time'       { Mod-Time }
      default      { $null }
    }
    if ($seg) { $parts += $seg }
  }
  return ($parts -join $SEPARATOR)
}

# ===================== Row 1: choose Starship or native ====================
$starship = Get-Command starship -ErrorAction SilentlyContinue
$useStar = $false
switch ($ROW1_SOURCE) {
  'native'   { $useStar = $false }
  'starship' { if ($starship) { $useStar = $true } }
  default    { if ($starship) { $useStar = $true } }
}

$row1 = ''
if ($useStar -and $cwd) {
  try {
    $row1 = Strip-Wrappers ((& starship prompt --path $cwd 2>$null | Out-String) -replace "`r", '' -replace "`n", '')
    $ix = $row1.LastIndexOf([char]0x276F)   # ❯
    if ($ix -ge 0) { $row1 = $row1.Substring(0, $ix) }
    # Starship's right_format (e.g. the clock) -> right-align it to the terminal width.
    $right = Strip-Wrappers ((& starship prompt --right --path $cwd 2>$null | Out-String) -replace "`r", '' -replace "`n", '')
    $right = $right -replace '\s+$', ''
    if ($right) {
      $reset = '{0}[0m' -f $ESC
      if ($RIGHT_ALIGN) {
        # Best-effort flush-right; RIGHT_MARGIN leaves slack (true render width
        # isn't exposed, and Nerd Font glyphs count as 1 char but 2 cells).
        $pad = (Term-Cols) - $RIGHT_MARGIN - (Strip-Ansi $row1).Length - (Strip-Ansi $right).Length
        if ($pad -lt 1) { $pad = 1 }
        $row1 = $row1 + $reset + (' ' * $pad) + $right
      } else {
        $row1 = $row1 + $reset + $SEPARATOR + $right   # inline: always visible
      }
    }
  } catch { $row1 = '' }
}
if (-not $row1) { $row1 = Build-NativeRow1 }

# ===================== Row 2: Claude info ==================================
$usageType = $USAGE_TYPE_OVERRIDE
if (-not $usageType) {
  $acctPath = Join-Path $HOME '.claude.json'
  if (Test-Path $acctPath) {
    try {
      $acct = (Get-Content -Raw $acctPath | ConvertFrom-Json).oauthAccount
      $seat = [string]$acct.seatTier; $org = [string]$acct.organizationType
      switch -Regex ($seat) {
        '^free'       { $usageType = 'Free'; break }
        '^pro'        { $usageType = 'Pro'; break }
        '^max_20x'    { $usageType = 'Max 20x'; break }
        '^max_5x'     { $usageType = 'Max 5x'; break }
        '^max'        { $usageType = 'Max'; break }
        '^team'       { $usageType = 'Team'; break }
        '^enterprise' { $usageType = 'Enterprise'; break }
        default {
          if     ($seat)                            { $usageType = $seat }
          elseif ($org -match '^claude_team')       { $usageType = 'Team' }
          elseif ($org -match '^claude_enterprise') { $usageType = 'Enterprise' }
          elseif ($org -match '^claude_max')        { $usageType = 'Max' }
          elseif ($org -match '^claude_pro')        { $usageType = 'Pro' }
        }
      }
    } catch {}
  }
}

$row2 = ''
$dot = Ansi '90' '·'
# Add-Space: space-join a segment (skips empties, so no stray leading space)
function Add-Space($s) { if ($s) { if ($script:row2) { $script:row2 += ' ' + $s } else { $script:row2 = $s } } }
# Add-Dot: join with a "·" separator, or start the row if nothing precedes it
function Add-Dot($s) { if ($s) { if ($script:row2) { $script:row2 += ' ' + $script:dot + ' ' + $s } else { $script:row2 = $s } } }

if ($model) { Add-Space (Ansi '35' $model) }

if ($null -ne $usedPct -and "$usedPct" -ne '') {
  $up = [int][math]::Truncate([double]$usedPct)
  $filled = [int][math]::Floor($up * $BAR_WIDTH / 100)
  if ($filled -gt $BAR_WIDTH) { $filled = $BAR_WIDTH }
  if ($filled -lt 0) { $filled = 0 }
  $bar = ('█' * $filled) + ('░' * ($BAR_WIDTH - $filled))
  $label = ''
  if ($null -ne $usedTok -and $null -ne $winSize) { $label = " $(Format-Tokens $usedTok) / $(Format-Tokens $winSize)" }
  Add-Space (Ansi (PctCode $up $CTX_YELLOW $CTX_RED) "$bar $up%$label")
}

if ($usageType) { Add-Dot (Ansi '35' $usageType) }
if ($null -ne $fiveHr -and "$fiveHr" -ne '') {
  $fh = [int][math]::Truncate([double]$fiveHr)
  Add-Dot (Ansi (PctCode $fh $RL_YELLOW $RL_RED) "Session(5h) $fh%")
}
if ($null -ne $sevenDay -and "$sevenDay" -ne '') {
  $wd = [int][math]::Truncate([double]$sevenDay)
  Add-Dot (Ansi (PctCode $wd $RL_YELLOW $RL_RED) "Week(all) $wd%")
}

# ===================== output: row 1 then row 2 ============================
[Console]::Out.Write($row1 + ('{0}[0m' -f $ESC) + "`n" + $row2)
