# MITHQAL Phase 0 exit gate orchestrator (test-only; v1 infrastructure stage)
# Stages implemented: preflight, infra up, disposable DB create, migrate, API server boot,
# smoke check, teardown. Scenario execution arrives with the scenario-runner iteration and
# FAILS LOUDLY until then — a run of this script is never evidence of a green gate.
#
# Usage:
#   .\phase0_exit.ps1 -RunId run1 -Setup          # preflight + infra + db + migrate + serve
#   .\phase0_exit.ps1 -RunId run1 -Scenarios      # (not yet implemented — exits 2)
#   .\phase0_exit.ps1 -RunId run1 -Teardown       # drop THIS run's db; -Down also removes containers
param(
  [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9_]+$')][string]$RunId,
  [switch]$Setup,
  [switch]$Scenarios,
  [switch]$Teardown,
  [switch]$Down,
  [string]$PosApiRoot = '/home/abdallah644/projects/my-projects/pos/pos_api',
  [string]$PosAdminRoot = '/home/abdallah644/projects/my-projects/pos/pos_admin',
  [string]$CharityRoot = '/home/abdallah644/projects/my-projects/charity/charity-laravel-api'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeWsl = (wsl -e wslpath -a ($here + '\phase0_exit\docker-compose.phase0.yml').Replace('\', '/')).Trim()
$db = "phase0_exit_$RunId"
$art = Join-Path (Split-Path -Parent $here) "build\phase0_exit\$RunId"
New-Item -ItemType Directory -Force $art | Out-Null

function Invoke-Wsl([string]$cmd) {
  wsl -e bash -lc $cmd
  if ($LASTEXITCODE -ne 0) { throw "WSL command failed ($LASTEXITCODE): $cmd" }
}

# Environment for compose interpolation (repo roots parameterized, throwaway key per run).
$bytes = New-Object byte[] 32; (New-Object Random).NextBytes($bytes)
$appKey = 'base64:' + [Convert]::ToBase64String($bytes)
$envPrefix = "POS_API_ROOT='$PosApiRoot' POS_ADMIN_ROOT='$PosAdminRoot' CHARITY_ROOT='$CharityRoot' PHASE0_DB='$db' PHASE0_APP_KEY='$appKey' PHASE0_SWEEP_FLOOR='0'"
$dc = "$envPrefix docker compose -p phase0exit -f '$composeWsl'"

if ($Teardown) {
  # Remove ONLY positively-identified disposable resources: our labeled pg container's db, our compose project.
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $db
  if ($LASTEXITCODE -ne 0) { Write-Host 'Teardown refused: preflight failed (cannot positively identify disposable target)'; exit 1 }
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -c 'DROP DATABASE IF EXISTS $db'"
  Write-Host "Dropped disposable database $db"
  if ($Down) { Invoke-Wsl "$dc down -v --remove-orphans"; Write-Host 'phase0exit project removed (containers + anonymous volumes)' }
  exit 0
}

if ($Setup) {
  # 1. Infra up (pg + redis only; runners/server are profile-gated).
  Invoke-Wsl "$dc up -d pg redis"
  Invoke-Wsl "docker exec phase0-exit-pg sh -c 'until pg_isready -U phase0 >/dev/null 2>&1; do sleep 0.5; done'"

  # 2. Preflight AFTER infra exists (verifies labels, project, identity) — abort on failure.
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $db
  if ($LASTEXITCODE -ne 0) { exit 1 }

  # 3. Create this run's disposable database (idempotent).
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -tAc `"SELECT 1 FROM pg_database WHERE datname='$db'`" | grep -q 1 || docker exec phase0-exit-pg createdb -U phase0 $db"

  # 4. Schema: pos_admin owns every pos_* migration (architecture rule). Charity-side base
  #    tables come first if admin migrations depend on them (shared-DB model) — the runner
  #    reports and we iterate if ordering issues surface.
  Invoke-Wsl "$dc run --rm --no-deps admin_runner php artisan migrate --force"
  Write-Host 'pos_admin migrations applied to disposable DB'

  # 5. Boot the harness API server and smoke it.
  Invoke-Wsl "$dc up -d api_server"
  $ok = $false
  foreach ($i in 1..30) {
    try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:58000/up' -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { $ok = $true; break } } catch { Start-Sleep -Milliseconds 500 }
  }
  if (-not $ok) { throw 'harness API server failed its smoke check (http://127.0.0.1:58000/up)' }
  Write-Host "Setup complete: db=$db api=http://127.0.0.1:58000 artifacts=$art"
  exit 0
}

if ($Scenarios) {
  Write-Host 'SCENARIOS NOT IMPLEMENTED YET — the scenario-runner iteration of T2 adds them. Failing loudly.' -ForegroundColor Red
  exit 2
}

Write-Host 'Nothing to do: pass -Setup, -Scenarios or -Teardown.'
exit 2
