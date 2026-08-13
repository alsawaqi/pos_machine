# Phase 0 exit gate - EXIT-16 (machine + handheld parallel sale streams behind
# a real barrier, shared PG state, test-only).
#
# Thin wrapper over TWO Dart integrated drivers built in parallel lanes:
#   machine  C:\src\projects\pos_machine\test\phase0_exit\integrated\exit16_machine_stream_test.dart
#   handheld C:\src\projects\pos_handheld\test\phase0_exit\integrated\exit16_handheld_stream_test.dart
#
# Contract (fixed): each driver runs `flutter test <file> --reporter expanded`
# with PHASE0_INTEGRATED=1, PHASE0_BASE_URL=http://127.0.0.1:58000/api/v1,
# its own PHASE0_DEVICE_TOKEN (machine-a1 / handheld-a1) and PHASE0_STAFF_ID
# (900120 / 900121), shared PHASE0_SALES_N=5, PHASE0_PRODUCT_ID=900141,
# PHASE0_CUSTOMER_ID=900130. Barrier: each driver writes PHASE0_READY_FILE
# then polls PHASE0_GO_FILE; this wrapper creates the go file once BOTH ready
# files exist (30s bound), so the two 5-sale streams genuinely overlap.
#
# Post-run authoritative psql assertions (id floors captured pre-launch):
#   - exactly 10 new orders (5 per device), all company 900100/branch 900110,
#     all paid, each with exactly 1 payment (10 payments total);
#   - per-client-event exactly-once: every new ledger row for the two devices
#     settled processed (0 failed), 10 order.create + 10 order.pay, no
#     (device_id, client_event_id) settled twice;
#   - unit stock for product 900141: the branch shelf (pos_branch_product,
#     the balance device sales move - ConsumeInventoryAction.moveProductStock)
#     decremented by EXACTLY the total qty sold, the product movement ledger
#     (pos_product_stock_movements, branch rows) sums to exactly -qty, the
#     CENTRAL pos_product_stock balance is untouched by design (its invariant
#     sums branch_id-NULL rows only), and no balance ever goes negative.
#
# While either Dart driver is missing this wrapper reports NOT-READY.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $machineRepo = 'C:\src\projects\pos_machine'
  $handheldRepo = 'C:\src\projects\pos_handheld'
  $machineTest = Join-Path $machineRepo 'test\phase0_exit\integrated\exit16_machine_stream_test.dart'
  $handheldTest = Join-Path $handheldRepo 'test\phase0_exit\integrated\exit16_handheld_stream_test.dart'
  $missing = @()
  if (-not (Test-Path $machineTest)) { $missing += $machineTest }
  if (-not (Test-Path $handheldTest)) { $missing += $handheldTest }
  if ($missing.Count -gt 0) {
    return New-ScenarioResult -Id 'exit16_two_device_barrier' -Result 'NOT-READY' `
      -Detail ("Dart integrated driver(s) not present yet: " + ($missing -join ' ; ') + ' (built in parallel lanes; wrapper is armed and will run them as-is)') `
      -Before (Get-EffectCounts -Db $Db -CharityDb $CharityDb) -After $null -ExpectedDelta $null
  }
  if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter CLI not found on PATH - cannot run the Dart integrated drivers'
  }

  # Barrier files (fresh per invocation).
  $readyM = Join-Path $Art 'exit16_machine.ready'
  $readyH = Join-Path $Art 'exit16_handheld.ready'
  $goFile = Join-Path $Art 'exit16.go'
  foreach ($f in @($readyM, $readyH, $goFile)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  # Pre-launch floors + stock snapshot (authoritative windows for "new" rows).
  $maxOrder = [long]((Invoke-Psql -Db $Db -Sql 'SELECT coalesce(max(id),0) FROM pos_orders')[0])
  $maxEvent = [long]((Invoke-Psql -Db $Db -Sql 'SELECT coalesce(max(id),0) FROM pos_sync_events')[0])
  $maxMove = [long]((Invoke-Psql -Db $Db -Sql 'SELECT coalesce(max(id),0) FROM pos_product_stock_movements')[0])
  $shelfBefore = [double]((Invoke-Psql -Db $Db -Sql 'SELECT stock_qty FROM pos_branch_product WHERE branch_id=900110 AND product_id=900141')[0])
  $centralBefore = [double]((Invoke-Psql -Db $Db -Sql 'SELECT quantity FROM pos_product_stock WHERE company_id=900100 AND product_id=900141')[0])

  $shared = @{
    PHASE0_INTEGRATED = '1'
    PHASE0_BASE_URL = 'http://127.0.0.1:58000/api/v1'
    PHASE0_GO_FILE = $goFile
    PHASE0_SALES_N = '5'
    PHASE0_PRODUCT_ID = '900141'
    PHASE0_CUSTOMER_ID = '900130'
  }
  $perDriver = @(
    @{ Name = 'machine'; Repo = $machineRepo; Test = $machineTest; Token = 'phase0-mdev-machine-a1'; Staff = '900120'; Ready = $readyM },
    @{ Name = 'handheld'; Repo = $handheldRepo; Test = $handheldTest; Token = 'phase0-mdev-handheld-a1'; Staff = '900121'; Ready = $readyH }
  )

  $allKeys = @($shared.Keys) + @('PHASE0_DEVICE_TOKEN', 'PHASE0_STAFF_ID', 'PHASE0_READY_FILE')
  $saved = @{}
  foreach ($k in $allKeys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  $procs = @()
  try {
    foreach ($d in $perDriver) {
      foreach ($k in $shared.Keys) { [Environment]::SetEnvironmentVariable($k, $shared[$k]) }
      [Environment]::SetEnvironmentVariable('PHASE0_DEVICE_TOKEN', $d.Token)
      [Environment]::SetEnvironmentVariable('PHASE0_STAFF_ID', $d.Staff)
      [Environment]::SetEnvironmentVariable('PHASE0_READY_FILE', $d.Ready)
      $out = Join-Path $Art ('exit16_' + $d.Name + '.txt')
      $err = Join-Path $Art ('exit16_' + $d.Name + '_err.txt')
      $p = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList '/d', '/c', 'flutter', 'test', $d.Test, '--reporter', 'expanded' `
        -WorkingDirectory $d.Repo -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
      # PS 5.1: without touching .Handle before exit, ExitCode stays $null.
      $null = $p.Handle
      $procs += @{ Name = $d.Name; P = $p; Out = $out }
    }

    # Barrier: both drivers must write their ready files within 30s.
    $deadline = (Get-Date).AddSeconds(30)
    while (-not ((Test-Path $readyM) -and (Test-Path $readyH))) {
      if ((Get-Date) -gt $deadline) {
        $state = "machineReady=$(Test-Path $readyM) handheldReady=$(Test-Path $readyH)"
        throw "exit16 barrier timeout: both drivers did not arm within 30s ($state)"
      }
      foreach ($j in $procs) { if ($j.P.HasExited -and $j.P.ExitCode -ne 0) { throw "exit16 $($j.Name) driver died before arming (exit $($j.P.ExitCode)) - see $($j.Out)" } }
      Start-Sleep -Milliseconds 250
    }
    Set-Content -Path $goFile -Value 'go' -Encoding Ascii

    # Bounded wait for both streams to finish.
    $deadline = (Get-Date).AddSeconds(300)
    foreach ($j in $procs) {
      while (-not $j.P.HasExited) {
        if ((Get-Date) -gt $deadline) { throw "exit16 $($j.Name) driver exceeded the 300s bound - killed (see $($j.Out))" }
        Start-Sleep -Milliseconds 500
      }
    }
  } catch {
    foreach ($j in $procs) { if ($j -and -not $j.P.HasExited) { try { $j.P.Kill() } catch {} } }
    throw
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  foreach ($j in $procs) {
    if ($j.P.ExitCode -ne 0) {
      $tail = (@(Get-Content $j.Out -ErrorAction SilentlyContinue | Select-Object -Last 8) -join ' // ')
      throw "exit16 $($j.Name) driver exited $($j.P.ExitCode). Tail: $tail (full output: $($j.Out))"
    }
  }

  # ---- authoritative shared-PG state ---------------------------------------
  $o = ((Invoke-Psql -Db $Db -Sql @"
SELECT count(*)
  ||'|'||count(*) FILTER (WHERE company_id=900100 AND branch_id=900110)
  ||'|'||count(*) FILTER (WHERE status='paid')
  ||'|'||count(*) FILTER (WHERE device_id=900111)
  ||'|'||count(*) FILTER (WHERE device_id=900112)
FROM pos_orders WHERE id > $maxOrder
"@)[0]) -split '\|'
  if ([int]$o[0] -ne 10) { throw "expected exactly 10 new orders from the two 5-sale streams, found $($o[0])" }
  if ([int]$o[1] -ne 10) { throw "only $($o[1]) of the 10 new orders are company 900100/branch 900110" }
  if ([int]$o[2] -ne 10) { throw "only $($o[2]) of the 10 new orders settled paid" }
  if ([int]$o[3] -ne 5 -or [int]$o[4] -ne 5) { throw "per-device split is machine=$($o[3]) handheld=$($o[4]), expected 5/5" }

  $pay = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||count(DISTINCT order_id) FROM pos_payments WHERE order_id IN (SELECT id FROM pos_orders WHERE id > $maxOrder)")[0]) -split '\|'
  if ([int]$pay[0] -ne 10 -or [int]$pay[1] -ne 10) { throw "expected exactly 10 payments across 10 distinct new orders, found payments=$($pay[0]) orders=$($pay[1])" }

  $ev = ((Invoke-Psql -Db $Db -Sql @"
SELECT count(*)
  ||'|'||count(*) FILTER (WHERE ack_status='processed')
  ||'|'||count(*) FILTER (WHERE ack_status='failed')
  ||'|'||count(*) FILTER (WHERE event_type='order.create')
  ||'|'||count(*) FILTER (WHERE event_type='order.pay')
  ||'|'||count(DISTINCT device_id::text||':'||client_event_id::text)
FROM pos_sync_events WHERE id > $maxEvent AND device_id IN (900111, 900112)
"@)[0]) -split '\|'
  if ([int]$ev[2] -ne 0) { throw "$($ev[2]) new sync events FAILED during the parallel streams" }
  if ([int]$ev[1] -ne [int]$ev[0]) { throw "only $($ev[1]) of $($ev[0]) new sync events settled processed" }
  if ([int]$ev[3] -ne 10) { throw "expected exactly 10 order.create ledger rows, found $($ev[3])" }
  if ([int]$ev[4] -ne 10) { throw "expected exactly 10 order.pay ledger rows, found $($ev[4])" }
  if ([int]$ev[5] -ne [int]$ev[0]) { throw "per-client-event exactly-once broken: $($ev[0]) ledger rows over $($ev[5]) distinct (device, client_event_id) identities" }

  # ---- unit stock: shelf decrement + movement ledger consistency -----------
  $qtySold = [double]((Invoke-Psql -Db $Db -Sql "SELECT coalesce(sum(qty),0) FROM pos_order_items WHERE order_id IN (SELECT id FROM pos_orders WHERE id > $maxOrder) AND product_id=900141")[0])
  if ($qtySold -le 0) { throw 'no qty of the tracked product 900141 was sold across the streams - the drivers did not exercise unit stock' }
  $shelfAfter = [double]((Invoke-Psql -Db $Db -Sql 'SELECT stock_qty FROM pos_branch_product WHERE branch_id=900110 AND product_id=900141')[0])
  $centralAfter = [double]((Invoke-Psql -Db $Db -Sql 'SELECT quantity FROM pos_product_stock WHERE company_id=900100 AND product_id=900141')[0])
  $moveSum = [double]((Invoke-Psql -Db $Db -Sql "SELECT coalesce(sum(quantity),0) FROM pos_product_stock_movements WHERE id > $maxMove AND product_id=900141 AND branch_id=900110")[0])

  if ([math]::Abs(($shelfBefore - $shelfAfter) - $qtySold) -gt 0.0005) { throw "branch shelf for 900141 moved $shelfBefore -> $shelfAfter but total qty sold is $qtySold - decrement is not exact" }
  if ([math]::Abs($moveSum + $qtySold) -gt 0.0005) { throw "product movement ledger sums to $moveSum for the window, expected exactly -$qtySold (ledger/balance drift)" }
  if ([math]::Abs($centralAfter - $centralBefore) -gt 0.0005) { throw "CENTRAL pos_product_stock moved $centralBefore -> $centralAfter - device sales must only move the branch shelf (D1 design)" }
  if ($shelfAfter -lt 0) { throw "branch shelf went NEGATIVE: $shelfAfter" }

  # ---- effect deltas (only the driver-independent keys are pinned) ---------
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 10; orders_paid = 10; payments = 10; events_failed = 0; events_received = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit16_two_device_barrier' -Result 'PASS' `
    -Detail ("both Dart streams green behind a real ready/go barrier: 10 orders (5 machine / 5 handheld, all paid, company 900100/branch 900110), 10 payments, every ledger row processed exactly once (10 create + 10 pay, 0 failed), shelf for 900141 decremented by exactly $qtySold with the movement ledger summing to -$qtySold, central pool untouched, never negative.") `
    -Before $before -After $after -ExpectedDelta $expected
}
