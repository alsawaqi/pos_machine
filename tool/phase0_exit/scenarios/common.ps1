# Phase 0 exit gate — shared scenario helpers (test-only). Dot-sourced by phase0_exit.ps1.
# Every helper targets ONLY the phase0exit disposable stack; preflight has already run.

$script:Phase0Api = 'http://127.0.0.1:58000'

function Invoke-Psql {
  # Runs SQL against the disposable PG (container phase0-exit-pg) and returns trimmed stdout lines.
  param([string]$Sql, [string]$Db)
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
  $out = wsl -e bash -lc "echo $b64 | base64 -d | docker exec -i phase0-exit-pg psql -U phase0 -d $Db -tA -v ON_ERROR_STOP=1 -f -"
  if ($LASTEXITCODE -ne 0) { throw "psql failed against $Db : $out" }
  # The leading comma is LOAD-BEARING: without it a single result line is
  # unrolled to a bare string on return, and callers indexing [0] get a CHAR
  # (T2 shakedown finding: [int]'6' is 54, not 6). CONTRACT: this helper
  # ALWAYS emits one array object - callers must NOT re-wrap it in @(...)
  # (that would collect the array into a single-element array).
  return , @($out | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() })
}

function Get-EnvFlags([hashtable]$ExtraEnv) {
  if (-not $ExtraEnv) { return '' }
  return (($ExtraEnv.Keys | ForEach-Object { "-e $_='$($ExtraEnv[$_])'" }) -join ' ')
}

function Invoke-ApiRunner {
  # One-off php process inside the api_runner service (disposable env; PHASE0_* interpolated by $dc).
  param([string]$Dc, [string]$Cmd, [hashtable]$ExtraEnv, [switch]$AllowFail)
  $flags = Get-EnvFlags $ExtraEnv
  $out = wsl -e bash -lc "$Dc run --rm --no-deps $flags api_runner $Cmd 2>&1"
  if ($LASTEXITCODE -ne 0 -and -not $AllowFail) { throw "api_runner failed: $Cmd`n$out" }
  return $out
}

function Invoke-AdminRunner {
  param([string]$Dc, [string]$Cmd, [hashtable]$ExtraEnv, [switch]$AllowFail)
  $flags = Get-EnvFlags $ExtraEnv
  $out = wsl -e bash -lc "$Dc run --rm --no-deps $flags admin_runner $Cmd 2>&1"
  if ($LASTEXITCODE -ne 0 -and -not $AllowFail) { throw "admin_runner failed: $Cmd`n$out" }
  return $out
}

function Invoke-ApiPost {
  # HTTP POST to the harness API with a device token. Returns the parsed JSON response.
  param([string]$Path, [hashtable]$Body, [string]$DeviceToken, [int]$TimeoutSec = 30)
  $json = $Body | ConvertTo-Json -Depth 24
  $headers = @{ Authorization = "Bearer $DeviceToken"; Accept = 'application/json' }
  try {
    $r = Invoke-WebRequest -Uri ($script:Phase0Api + $Path) -Method Post -Body $json -ContentType 'application/json' -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec
    return @{ status = [int]$r.StatusCode; body = ($r.Content | ConvertFrom-Json) }
  } catch {
    $resp = $_.Exception.Response
    if ($resp -and $resp.GetResponseStream) {
      $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $content = $sr.ReadToEnd()
      $parsed = $null; try { $parsed = $content | ConvertFrom-Json } catch {}
      return @{ status = [int]$resp.StatusCode; body = $parsed; raw = $content }
    }
    throw
  }
}

function Invoke-ParallelPosts {
  # Fires N HTTP POSTs at a genuine barrier (runspaces armed, then released together).
  # Each item: @{ Path=..; Body=..; Token=.. }. Returns results in submission order.
  param([object[]]$Requests)
  $pool = [runspacefactory]::CreateRunspacePool(1, $Requests.Count); $pool.Open()
  $gate = New-Object System.Threading.ManualResetEventSlim($false)
  $jobs = @()
  foreach ($req in $Requests) {
    $ps = [powershell]::Create(); $ps.RunspacePool = $pool
    [void]$ps.AddScript({
      param($Uri, $Json, $Token, $Gate)
      $Gate.Wait()
      $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
      try {
        $r = Invoke-WebRequest -Uri $Uri -Method Post -Body $Json -ContentType 'application/json' -Headers $headers -UseBasicParsing -TimeoutSec 60
        @{ status = [int]$r.StatusCode; content = $r.Content }
      } catch {
        $resp = $_.Exception.Response
        if ($resp) { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); @{ status = [int]$resp.StatusCode; content = $sr.ReadToEnd() } }
        else { @{ status = -1; content = $_.Exception.Message } }
      }
    }).AddArgument($script:Phase0Api + $req.Path).AddArgument(($req.Body | ConvertTo-Json -Depth 24)).AddArgument($req.Token).AddArgument($gate)
    $jobs += @{ ps = $ps; h = $ps.BeginInvoke() }
  }
  Start-Sleep -Milliseconds 300   # let every runspace reach the gate (arming, not race timing)
  $gate.Set()
  $results = @()
  foreach ($j in $jobs) { $results += $j.ps.EndInvoke($j.h)[0]; $j.ps.Dispose() }
  $pool.Close()
  return $results | ForEach-Object { @{ status = $_.status; body = ($(try { $_.content | ConvertFrom-Json } catch { $null })); raw = $_.content } }
}

function Get-EffectCounts {
  # Authoritative effect snapshot over the disposable DB (per handoff §13 table).
  param([string]$Db, [string]$CharityDb = '')
  $sql = @"
SELECT 'orders', count(*) FROM pos_orders
UNION ALL SELECT 'orders_paid', count(*) FROM pos_orders WHERE status IN ('paid','closed','completed')
UNION ALL SELECT 'payments', count(*) FROM pos_payments
UNION ALL SELECT 'stock_movements', (SELECT count(*) FROM pos_stock_movements) + (SELECT count(*) FROM pos_product_stock_movements)
UNION ALL SELECT 'loyalty_ledger', count(*) FROM pos_loyalty_transactions
UNION ALL SELECT 'loyalty_reviews', count(*) FROM pos_loyalty_shortfall_reviews
UNION ALL SELECT 'commission_rows', count(*) FROM pos_sale_commissions
UNION ALL SELECT 'local_donations', count(*) FROM pos_roundup_donations
UNION ALL SELECT 'events_received', count(*) FROM pos_sync_events WHERE ack_status='received'
UNION ALL SELECT 'events_processed', count(*) FROM pos_sync_events WHERE ack_status='processed'
UNION ALL SELECT 'events_failed', count(*) FROM pos_sync_events WHERE ack_status='failed'
"@
  $counts = [ordered]@{}
  foreach ($line in (Invoke-Psql -Sql $sql -Db $Db)) {
    $parts = $line -split '\|'; $counts[$parts[0]] = [int]$parts[1]
  }
  if ($CharityDb) {
    foreach ($line in (Invoke-Psql -Sql "SELECT 'receiver_transactions', count(*) FROM charity_transactions UNION ALL SELECT 'receiver_shares', count(*) FROM charity_transaction_shares" -Db $CharityDb)) {
      $parts = $line -split '\|'; $counts[$parts[0]] = [int]$parts[1]
    }
  }
  return $counts
}

function New-ScenarioResult {
  param([string]$Id, [string]$Result, [string]$Detail, [object]$Before, [object]$After, [object]$ExpectedDelta)
  $actual = [ordered]@{}
  if ($Before -and $After) { foreach ($k in $After.Keys) { $actual[$k] = $After[$k] - $(if ($Before.Contains($k)) { $Before[$k] } else { 0 }) } }
  return [ordered]@{
    id = $Id; result = $Result; detail = $Detail
    startedUtc = $script:ScenarioStartUtc; endedUtc = (Get-Date).ToUniversalTime().ToString('o')
    expectedDelta = $ExpectedDelta; actualDelta = $actual; before = $Before; after = $After
  }
}

function Assert-Delta {
  # Compares expected effect deltas (only the keys named) against actual; throws with a precise message.
  param([hashtable]$Expected, [object]$Before, [object]$After)
  $bad = @()
  foreach ($k in $Expected.Keys) {
    $b = if ($Before.Contains($k)) { $Before[$k] } else { 0 }
    $a = if ($After.Contains($k)) { $After[$k] } else { 0 }
    if (($a - $b) -ne $Expected[$k]) { $bad += "$k expected +$($Expected[$k]) actual +$($a - $b)" }
  }
  if ($bad.Count) { throw ('effect-delta mismatch: ' + ($bad -join '; ')) }
}
