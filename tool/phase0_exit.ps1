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
# Charity receiver disposable DB rides the same naming contract (allowlist
# pattern ^phase0_exit_[a-z0-9_]+$ still matches; charity_db stays denylisted).
$charityDb = if ($env:PHASE0_CHARITY_DB) { $env:PHASE0_CHARITY_DB } else { "${db}_charity" }
$art = Join-Path (Split-Path -Parent $here) "build\phase0_exit\$RunId"
New-Item -ItemType Directory -Force $art | Out-Null

function Invoke-Wsl([string]$cmd) {
  wsl -e bash -lc $cmd
  if ($LASTEXITCODE -ne 0) { throw "WSL command failed ($LASTEXITCODE): $cmd" }
}

# Environment for compose interpolation (repo roots parameterized, throwaway key per run).
$bytes = New-Object byte[] 32; (New-Object Random).NextBytes($bytes)
$appKey = 'base64:' + [Convert]::ToBase64String($bytes)
# Stage the php helpers into a NATIVE WSL directory. Mounting them from
# /mnt/c routes through Docker Desktop's file-sharing bind cache, which can
# serve stale/empty content after a Docker crash recovery (run8c-run10c
# finding: admin_runner saw an empty /phase0tool while the raw path worked).
# WSL-native paths mount into containers directly, bypassing that layer.
$phpSrcWsl = (wsl -e wslpath -a ($here + '\phase0_exit\php').Replace('\', '/')).Trim()
$phpDirWsl = '/home/abdallah644/.phase0_php'
wsl -e bash -lc "mkdir -p $phpDirWsl && cp -f $phpSrcWsl/*.php $phpDirWsl/ && ls $phpDirWsl" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'failed to stage php helpers into WSL-native dir' }
$sweepFloor = if ($env:PHASE0_SWEEP_FLOOR) { $env:PHASE0_SWEEP_FLOOR } else { '0' }
# BASE url only — verified read-only in both repos: pos_api ForwardCharityDonationAction
# and pos_admin Actions\Admin\Reconciliation\ForwardCharityDonationAction both read
# config('services.charity.url') (env CHARITY_API_URL) and append
# '/api/donations-pos-roundup' themselves. The compose env maps
# PHASE0_CHARITY_URL -> CHARITY_API_URL for api_runner/api_server/admin_runner.
$charityUrl = if ($env:PHASE0_CHARITY_URL) { $env:PHASE0_CHARITY_URL } else { 'http://phase0-exit-charity:8000' }
$envPrefix = "POS_API_ROOT='$PosApiRoot' POS_ADMIN_ROOT='$PosAdminRoot' CHARITY_ROOT='$CharityRoot' PHASE0_DB='$db' PHASE0_CHARITY_DB='$charityDb' PHASE0_APP_KEY='$appKey' PHASE0_SWEEP_FLOOR='$sweepFloor' PHASE0_PHP_DIR='$phpDirWsl' PHASE0_CHARITY_URL='$charityUrl'"
$dc = "$envPrefix docker compose -p phase0exit -f '$composeWsl'"

if ($Teardown) {
  # Remove ONLY positively-identified disposable resources: our labeled pg container's db, our compose project.
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $db -CharityUrl $charityUrl
  if ($LASTEXITCODE -ne 0) { Write-Host 'Teardown refused: preflight failed (cannot positively identify disposable target)'; exit 1 }
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $charityDb -CharityUrl $charityUrl
  if ($LASTEXITCODE -ne 0) { Write-Host 'Teardown refused: charity db preflight failed'; exit 1 }
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -c 'DROP DATABASE IF EXISTS $db'"
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -c 'DROP DATABASE IF EXISTS $charityDb'"
  Write-Host "Dropped disposable databases $db + $charityDb"
  if ($Down) { Invoke-Wsl "$dc down -v --remove-orphans"; Write-Host 'phase0exit project removed (containers + anonymous volumes)' }
  exit 0
}

if ($Setup) {
  # 1. Infra up (pg + redis only; runners/server are profile-gated).
  Invoke-Wsl "$dc up -d pg redis"
  Invoke-Wsl "docker exec phase0-exit-pg sh -c 'until pg_isready -U phase0 >/dev/null 2>&1; do sleep 0.5; done'"

  # 2. Preflight AFTER infra exists (verifies labels, project, identity) — abort on failure.
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $db -CharityUrl $charityUrl
  if ($LASTEXITCODE -ne 0) { exit 1 }
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $charityDb -CharityUrl $charityUrl
  if ($LASTEXITCODE -ne 0) { exit 1 }

  # 3. Create this run's disposable databases (idempotent): pos + charity receiver.
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -tAc `"SELECT 1 FROM pg_database WHERE datname='$db'`" | grep -q 1 || docker exec phase0-exit-pg createdb -U phase0 $db"
  Invoke-Wsl "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -tAc `"SELECT 1 FROM pg_database WHERE datname='$charityDb'`" | grep -q 1 || docker exec phase0-exit-pg createdb -U phase0 $charityDb"

  # 4. Schema: pos_admin owns every pos_* migration (architecture rule). Charity-side base
  #    tables come first if admin migrations depend on them (shared-DB model) — the runner
  #    reports and we iterate if ordering issues surface.
  Invoke-Wsl "$dc run --rm --no-deps admin_runner php artisan migrate --force"
  Write-Host 'pos_admin migrations applied to disposable DB'
  Invoke-Wsl "$dc run --rm --no-deps charity_runner php artisan migrate --force"
  Write-Host 'charity migrations applied to disposable charity DB'

  # 5. Deterministic fixtures (tool/phase0_exit/fixtures.json contract).
  Invoke-Wsl "$dc run --rm --no-deps api_runner php /phase0tool/seed_fixtures.php"
  Invoke-Wsl "$dc run --rm --no-deps charity_runner php /phase0tool/seed_charity.php"
  Write-Host 'fixtures seeded (pos + charity)'

  # 6. Boot the harness API server + charity receiver and smoke both.
  Invoke-Wsl "$dc up -d api_server charity_server"
  foreach ($probe in @(@{ Url = 'http://127.0.0.1:58000/up'; Name = 'harness API server' },
                       @{ Url = 'http://127.0.0.1:58001/up'; Name = 'charity receiver server' })) {
    $ok = $false
    foreach ($i in 1..30) {
      try { $r = Invoke-WebRequest -Uri $probe.Url -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { $ok = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ok) { throw "$($probe.Name) failed its smoke check ($($probe.Url))" }
  }
  Write-Host "Setup complete: db=$db charityDb=$charityDb api=http://127.0.0.1:58000 charity=http://127.0.0.1:58001 artifacts=$art"
  exit 0
}

if ($Scenarios) {
  # Scenario engine: run every scenarios/exit*.ps1 in order, continue on failure,
  # collect authoritative effect counts, write artifacts, exit non-zero on any failure.
  & (Join-Path $here 'phase0_exit\preflight.ps1') -Database $db -CharityUrl $charityUrl
  if ($LASTEXITCODE -ne 0) { exit 1 }
  . (Join-Path $here 'phase0_exit\scenarios\common.ps1')

  $scenarioFiles = Get-ChildItem (Join-Path $here 'phase0_exit\scenarios') -Filter 'exit*.ps1' | Sort-Object Name
  if (-not $scenarioFiles) { Write-Host 'No scenario files found — nothing to run.' -ForegroundColor Red; exit 2 }

  $allResults = @(); $failed = 0
  $gateStart = (Get-Date).ToUniversalTime().ToString('o')
  foreach ($f in $scenarioFiles) {
    $script:ScenarioStartUtc = (Get-Date).ToUniversalTime().ToString('o')
    $before = Get-EffectCounts -Db $db -CharityDb $charityDb
    Write-Host ">> $($f.BaseName)" -ForegroundColor Cyan
    try {
      # Each scenario file defines Invoke-Scenario -Dc -Db -Art [-CharityDb] and returns a result object via New-ScenarioResult.
      . $f.FullName
      $res = Invoke-Scenario -Dc $dc -Db $db -Art $art -CharityDb $charityDb
    } catch {
      $after = Get-EffectCounts -Db $db -CharityDb $charityDb
      $res = New-ScenarioResult -Id $f.BaseName -Result 'FAIL' -Detail ($_.Exception.Message) -Before $before -After $after -ExpectedDelta $null
    }
    if (-not $res.before) { $res.before = $before }
    if ($res.result -ne 'PASS') { $failed++; Write-Host "   $($res.result): $($res.detail)" -ForegroundColor Red }
    else { Write-Host "   PASS" -ForegroundColor Green }
    $allResults += $res
    Remove-Item Function:\Invoke-Scenario -ErrorAction SilentlyContinue
  }

  $summary = [ordered]@{
    runId = $RunId; database = $db; charityDatabase = $charityDb
    startedUtc = $gateStart; endedUtc = (Get-Date).ToUniversalTime().ToString('o')
    scenarios = $allResults.Count; passed = ($allResults.Count - $failed); failed = $failed
    results = $allResults
  }
  $summary | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 (Join-Path $art 'scenario-results.json')
  (Get-EffectCounts -Db $db -CharityDb $charityDb) | ConvertTo-Json | Out-File -Encoding utf8 (Join-Path $art 'effect-counts.json')
  Write-Host ""
  Write-Host "Gate: $($allResults.Count - $failed)/$($allResults.Count) scenarios passed. Artifacts: $art" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
  exit $(if ($failed) { 1 } else { 0 })
}

Write-Host 'Nothing to do: pass -Setup, -Scenarios or -Teardown.'
exit 2
