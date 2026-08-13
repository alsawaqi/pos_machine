# Phase 0 exit gate - EXIT-09 (dual concurrent stranded-event sweepers, test-only).
#
# Six eligible stranded `expense.log` events for device 900111 are seeded
# physically on the real PG (ack_status=received, server_received_at
# backdated 11 minutes - the runbook defines recovery purely over the
# `received` state). TWO php artisan sync:sweep-stranded-events processes then
# run genuinely concurrently (background jobs in ONE wsl bash call) against
# real Redis Cache::lock contention and PG row locks. Exactly-once settlement:
# 6 pos_expenses rows exactly (one per event), all 6 events processed, and the
# two sweep summaries report 6 processed / 0 failed combined.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $ces = @(); foreach ($n in 1..6) { $ces += ('c0900000-0000-4000-8000-{0:d12}' -f $n) }
  $inList = ($ces | ForEach-Object { "'$_'" }) -join ','
  $handled = "'order.create','order.hold','order.transfer','order.pay','order.deliver','order.void','shift.open','shift.close','expense.log','restock.request','donation.record','stock.count','product.waste','slider.display'"

  # Deterministic per invocation: purge this scenario's residue AND exit10's
  # (a prior invocation's still-`received` exit10 quarantine rows would be
  # eligible for this floor-0 sweep and corrupt the count).
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_expenses WHERE note LIKE 'P0EXIT09%';
DELETE FROM pos_sync_events WHERE client_event_id::text LIKE 'c0900000-%' OR client_event_id::text LIKE 'c1000000-%';
"@ | Out-Null

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  # Seed the six stranded rows (BACKDATED server receipt; payload shape per
  # ExpenseLogHandler / DeviceSyncExpenseRestockTest: category+amount_baisas(+staff)).
  $values = @()
  foreach ($n in 1..6) {
    $payload = '{"category":"utilities","amount_baisas":5000,"note":"P0EXIT09 #' + $n + '","staff_id":900120}'
    $values += "('$($ces[$n-1])', 900111, 'expense.log', '$payload'::jsonb, now() - interval '11 minutes', now() - interval '11 minutes', NULL, 'received', NULL)"
  }
  Invoke-Psql -Db $Db -Sql ("INSERT INTO pos_sync_events (client_event_id, device_id, event_type, payload_json, client_timestamp, server_received_at, processed_at, ack_status, result_json) VALUES `n" + ($values -join ",`n") + ';') | Out-Null

  # Guard: the floor-0 sweep must see EXACTLY our 6 eligible rows, or the
  # combined processed count below is meaningless (harness conflict, not product).
  $eligible = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_sync_events WHERE ack_status='received' AND server_received_at <= now() - interval '10 minutes' AND event_type IN ($handled)")[0])
  if ($eligible -ne 6) { throw "pre-sweep eligibility check found $eligible sweep-eligible received rows, expected exactly the 6 seeded (foreign stranded rows present - harness conflict)" }

  # TWO concurrent sweeps: background jobs in one wsl bash call (no bash
  # variables - the no-dollar-sign rule). Explicit floor + redis lock env.
  $sweep = "run --rm --no-deps -e SYNC_STRANDED_SWEEP_AFTER_ID=0 -e CACHE_STORE=redis -e REDIS_HOST=phase0-exit-redis api_runner php artisan sync:sweep-stranded-events"
  $bash = "mkdir -p /tmp/phase0exit; rm -f /tmp/phase0exit/e09a.out /tmp/phase0exit/e09b.out; ( $Dc $sweep >/tmp/phase0exit/e09a.out 2>&1 & $Dc $sweep >/tmp/phase0exit/e09b.out 2>&1 & wait ); echo ===SWEEP-A===; cat /tmp/phase0exit/e09a.out; echo ===SWEEP-B===; cat /tmp/phase0exit/e09b.out"
  $out = (wsl -e bash -lc $bash) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "concurrent sweep launch failed ($LASTEXITCODE): $out" }
  $out | Out-File -Encoding utf8 (Join-Path $Art 'exit09_sweeps.txt')

  $summaries = [regex]::Matches($out, 'processed=(\d+) failed=(\d+) skipped=(\d+)')
  if ($summaries.Count -ne 2) { throw "expected 2 sweep summary lines in the combined output, found $($summaries.Count) - see exit09_sweeps.txt" }
  $procSum = 0; $failSum = 0
  foreach ($m in $summaries) { $procSum += [int]$m.Groups[1].Value; $failSum += [int]$m.Groups[2].Value }
  if ($failSum -ne 0) { throw "combined sweeps report failed=$failSum, expected 0" }
  if ($procSum -ne 6) { throw "combined sweeps report processed=$procSum total, expected exactly 6 (each stranded event dispatched by exactly one sweeper)" }

  # --- authoritative DB state: all 6 processed, each producing ONE expense --
  $evOk = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_sync_events WHERE client_event_id IN ($inList) AND ack_status='processed' AND processed_at IS NOT NULL AND result_json ? 'expense_id'")[0])
  if ($evOk -ne 6) { throw "only $evOk of the 6 seeded events settled processed with an expense_id result" }
  $distinctExp = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(DISTINCT (result_json->>'expense_id')) FROM pos_sync_events WHERE client_event_id IN ($inList)")[0])
  if ($distinctExp -ne 6) { throw "the 6 events settled onto only $distinctExp distinct expense rows (shared settlement = double dispatch)" }

  $exp = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||count(DISTINCT note)||'|'||count(*) FILTER (WHERE amount = 5.000 AND company_id = 900100 AND branch_id = 900110 AND status = 'recorded') FROM pos_expenses WHERE note LIKE 'P0EXIT09%'")[0]) -split '\|'
  if ([int]$exp[0] -ne 6) { throw "expected exactly 6 pos_expenses rows, found $($exp[0]) (a 7th row = an event settled twice)" }
  if ([int]$exp[1] -ne 6) { throw "the 6 expense rows carry only $($exp[1]) distinct notes - some event settled twice" }
  if ([int]$exp[2] -ne 6) { throw "only $($exp[2]) of 6 expense rows carry the exact seeded amount/company/branch/status (5.000 OMR, 900100/900110, recorded)" }

  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ events_processed = 6; events_received = 0; events_failed = 0
    orders = 0; payments = 0; loyalty_ledger = 0; commission_rows = 0; local_donations = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit09_dual_sweeper' -Result 'PASS' `
    -Detail 'two genuinely concurrent sweeps settled 6 seeded stranded expense.log events exactly once each (6 expenses, 6 distinct settlements, combined processed=6 failed=0) under real Redis lock + PG row-lock contention' `
    -Before $before -After $after -ExpectedDelta $expected
}
