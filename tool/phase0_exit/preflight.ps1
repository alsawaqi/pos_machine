# Phase 0 exit gate — safety preflight (test-only)
# Aborts (exit 1) unless every resolved identity matches tool/phase0_exit/allowlist.json.
# A denylist match always wins. Prints sanitized identities only (never credentials).
param(
  [Parameter(Mandatory = $true)][string]$Database,
  [string]$CharityUrl = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$allow = Get-Content (Join-Path $here 'allowlist.json') -Raw | ConvertFrom-Json

function Fail([string]$msg) {
  Write-Host "PREFLIGHT ABORT: $msg" -ForegroundColor Red
  exit 1
}

# 1. Denylist screening (always first; a match here is terminal).
if ($allow.denylist.databases -contains $Database) { Fail "database '$Database' is denylisted" }
foreach ($g in $allow.denylist.hostsGlob) {
  if ($CharityUrl -and ($CharityUrl -like "*$($g.TrimStart('*'))*")) { Fail "endpoint '$CharityUrl' matches denylisted host pattern '$g'" }
}

# 2. Database name must match the disposable pattern.
if ($Database -notmatch $allow.postgres.databasePattern) {
  Fail "database '$Database' does not match allowlisted pattern $($allow.postgres.databasePattern)"
}

# 3. Endpoint allowlist (empty CharityUrl = charity leg disabled, which is allowed).
if ($CharityUrl) {
  $ok = $false
  foreach ($e in $allow.endpoints.allowed) { if ($CharityUrl.StartsWith($e)) { $ok = $true } }
  if (-not $ok) { Fail "endpoint '$CharityUrl' is not on the endpoint allowlist" }
}

# 4. The disposable containers must exist, carry the disposable label, and belong to project phase0exit.
foreach ($c in @($allow.postgres.containers + $allow.redis.containers)) {
  $label = (wsl -e bash -lc "docker inspect $c --format '{{index .Config.Labels \`"mithqal.phase0exit\`"}}' 2>/dev/null")
  if ($LASTEXITCODE -ne 0 -or -not $label) { Fail "container '$c' not running (start with: docker compose -p phase0exit -f docker-compose.phase0.yml up -d pg redis)" }
  if ($label.Trim() -ne 'disposable') { Fail "container '$c' lacks label mithqal.phase0exit=disposable" }
  $proj = (wsl -e bash -lc "docker inspect $c --format '{{index .Config.Labels \`"com.docker.compose.project\`"}}'").Trim()
  if ($proj -ne $allow.composeProject) { Fail "container '$c' belongs to compose project '$proj', expected '$($allow.composeProject)'" }
}

# 5. The PG server inside phase0-exit-pg must be OURS: verify the bootstrap marker DB + user.
$who = (wsl -e bash -lc "docker exec phase0-exit-pg psql -U phase0 -d phase0_exit_bootstrap -tAc 'select current_user' 2>/dev/null").Trim()
if ($who -ne $allow.postgres.user) { Fail "phase0-exit-pg identity check failed (current_user='$who')" }

# 6. Sanitized identity print (no credentials).
Write-Host "PREFLIGHT OK" -ForegroundColor Green
Write-Host "  compose project : $($allow.composeProject)"
Write-Host "  postgres        : container=phase0-exit-pg user=$($allow.postgres.user) database=$Database (disposable, tmpfs)"
Write-Host "  redis           : container=phase0-exit-redis"
Write-Host "  charity endpoint: $(if ($CharityUrl) { $CharityUrl } else { '(disabled)' })"
Write-Host "  APP_ENV         : testing (forced by compose runner env)"
exit 0
