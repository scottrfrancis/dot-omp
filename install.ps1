# install.ps1: Windows twin of install.sh. UNTESTED as of 2026-09-30 (written on the
# Linux side); run with -DryRun first.
#
#   .\install.ps1                  # copy models.yml, apply settings.conf + machines\<host>-windows.conf
#   .\install.ps1 -Link            # symlink models.yml instead (needs Developer Mode or admin)
#   .\install.ps1 -Machine NAME    # use machines\NAME.conf
#   .\install.ps1 -DryRun
param([switch]$Link, [switch]$DryRun, [string]$Machine = "")
$ErrorActionPreference = "Stop"

$Repo = $PSScriptRoot
$AgentDir = if ($env:OMP_AGENT_DIR) { $env:OMP_AGENT_DIR } else { Join-Path $HOME ".omp\agent" }
if (-not $Machine) { $Machine = ("{0}-windows" -f $env:COMPUTERNAME).ToLower() }
$MFile = Join-Path $Repo "machines\$Machine.conf"
if (-not (Get-Command omp -ErrorAction SilentlyContinue)) { throw "omp not found on PATH; install it first (see README)." }

Write-Host "dot-omp -> $AgentDir  (machine: $Machine)"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $AgentDir | Out-Null }

$dst = Join-Path $AgentDir "models.yml"
$src = Join-Path $Repo "models.yml"
if ((Test-Path $dst) -and -not ((Get-Item $dst).LinkType)) {
  $bak = "$dst.bak.$(Get-Date -Format yyyyMMdd-HHmmss)"
  if ($DryRun) { Write-Host "  would back up models.yml to $bak" } else { Move-Item $dst $bak; Write-Host "  backed up existing models.yml" }
}
if ($DryRun) { Write-Host "  would place models.yml ($(if ($Link) {'link'} else {'copy'}))" }
elseif ($Link) { New-Item -ItemType SymbolicLink -Force -Path $dst -Target $src | Out-Null }
else { Copy-Item -Force $src $dst }

function Apply-Conf($file) {
  foreach ($raw in Get-Content $file) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $key, $val = $line -split '\s+', 2
    if ($DryRun) { Write-Host "  would run: omp config set $key $val" }
    else { & omp config set $key $val | Out-Null; Write-Host "  set $key" }
  }
}
Apply-Conf (Join-Path $Repo "settings.conf")
if (Test-Path $MFile) { Apply-Conf $MFile } else { Write-Host "  NOTE: no machines\$Machine.conf; shared settings only." }
Write-Host "Done. Check with: omp config get modelRoles; omp config get edit.mode"
