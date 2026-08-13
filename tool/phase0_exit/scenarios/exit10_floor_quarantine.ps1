# Phase 0 exit gate - EXIT-10 (quarantine floor permanence under concurrency, test-only).
#
# Three identically-eligible stranded `expense.log` rows are seeded for device
# 900111; the sweep floor (SYNC_STRANDED_SWEEP_AFTER_ID) is set to the MIDDLE
# row's id. Two full sweeps plus one --limit=1 sweep run concurrently. The
# at/below-floor rows (ids <= floor) must remain BYTE-UNTOUCHED (`received`,
# processed_at NULL, result_json NULL, payload + receipt timestamp identical),
# while the single above-floor row settles exactly once.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $ces = @(); foreach ($n in 1..3) { $ces += ('c1000000-0000-4000-8000-{0:d12}' -f $n) }
  $inList = ($ces | ForEach-Object { "'$_'" }) -join ','
  $handled = "'order.create','order.hold','order.transfer','order.pay','order.deliver','order.void','shift.open','shift.close','expense.log','restock.request','donation.record','stock.count','product.waste','slider.display'"

  # Deterministic per invocation: purge only THIS scenario's residue.
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_expenses WHERE note LIKE 'P0EXIT10%';
DELETE FROM pos_sync_events WHERE client_event_id::text LIKE 'c1000000-%';
"@ | Out-Null

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  $values = @()
  foreach ($n in 1..3) {
    $payload = '{"category":"utilities","amount_baisas":7000,"note":"P0EXIT10 #' + $n + '","staff_id":900120}'
    $values += "('$($ces[$n-1])', 900111, 'expense.log', '$payload'::jsonb, now() - interval '11 minutes', now() - interval '11 minutes', NULL, 'received', NULL)"
  }
  Invoke-Psql -Db $Db -Sql ("INSERT INTO pos_sync_events (client_event_id, device_id, event_type, payload_json, client_timestamp, server_received_at, processed_at, ack_status, result_json) VALUES `n" + ($values -join ",`n") + ';') | Out-Null

  # Floor = MIDDLE id, queried after seeding (ids are engine-assigned).
  $ids = Invoke-Psql -Db $Db -Sql "SELECT id FROM pos_sync_events WHERE client_event_id IN ($inList) ORDER BY id"
  if ($ids.Count -ne 3) { throw "seeded 3 quarantine rows but found $($ids.Count)" }
  $floor = [int]$ids[1]

  # Guards: exactly 1 eligible row above the floor, none foreign.
  $aboveEligible = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_sync_events WHERE id > $floor AND ack_status='received' AND server_received_at <= now() - interval '10 minutes' AND event_type IN ($handled)")[0])
  if ($aboveEligible -ne 1) { throw "pre-sweep check found $aboveEligible eligible rows above floor $floor, expected exactly 1 (foreign stranded rows present - harness conflict)" }

  # Byte-level snapshot of the at/below-floor rows before the sweeps.
  $snapshotSql = "SELECT id||'|'||ack_status||'|'||coalesce(processed_at::text,'NULL')||'|'||coalesce(result_json::text,'NULL')||'|'||md5(payload_json::text)||'|'||server_received_at::text||'|'||client_timestamp::text FROM pos_sync_events WHERE client_event_id IN ($inList) AND id <= $floor ORDER BY id"
  $preSnap = Invoke-Psql -Db $Db -Sql $snapshotSql
  if ($preSnap.Count -ne 2) { throw "expected 2 at/below-floor rows in the pre-sweep snapshot, found $($preSnap.Count)" }
  foreach ($row in $preSnap) {
    if ($row -notlike '*|received|NULL|NULL|*') { throw "seeded at/below-floor row is not in the pristine received state: $row" }
  }

  # Two full sweeps + one --limit=1 sweep, all concurrent, all honoring the floor.
  $base = "run --rm --no-deps -e SYNC_STRANDED_SWEEP_AFTER_ID=$floor -e CACHE_STORE=redis -e REDIS_HOST=phase0-exit-redis api_runner php artisan sync:sweep-stranded-events"
  $bash = "mkdir -p /tmp/phase0exit; rm -f /tmp/phase0exit/e10a.out /tmp/phase0exit/e10b.out /tmp/phase0exit/e10c.out; ( $Dc $base >/tmp/phase0exit/e10a.out 2>&1 & $Dc $base >/tmp/phase0exit/e10b.out 2>&1 & $Dc $base --limit=1 >/tmp/phase0exit/e10c.out 2>&1 & wait ); echo ===SWEEP-A===; cat /tmp/phase0exit/e10a.out; echo ===SWEEP-B===; cat /tmp/phase0exit/e10b.out; echo ===SWEEP-C-limit1===; cat /tmp/phase0exit/e10c.out"
  $out = (wsl -e bash -lc $bash) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "concurrent sweep launch failed ($LASTEXITCODE): $out" }
  $out | Out-File -Encoding utf8 (Join-Path $Art 'exit10_sweeps.txt')

  $summaries = [regex]::Matches($out, 'processed=(\d+) failed=(\d+) skipped=(\d+)')
  if ($summaries.Count -ne 3) { throw "expected 3 sweep summary lines in the combined output, found $($summaries.Count) - see exit10_sweeps.txt" }
  $procSum = 0; $failSum = 0
  foreach ($m in $summaries) { $procSum += [int]$m.Groups[1].Value; $failSum += [int]$m.Groups[2].Value }
  if ($failSum -ne 0) { throw "combined sweeps report failed=$failSum, expected 0" }
  if ($procSum -ne 1) { throw "combined sweeps report processed=$procSum total, expected exactly 1 (only the single above-floor row is sweepable)" }

  # --- at/below-floor rows byte-untouched -----------------------------------
  $postSnap = Invoke-Psql -Db $Db -Sql $snapshotSql
  if ($postSnap.Count -ne 2) { throw "at/below-floor rows changed cardinality: $($postSnap.Count)" }
  for ($i = 0; $i -lt 2; $i++) {
    if ($postSnap[$i] -cne $preSnap[$i]) { throw "quarantined at/below-floor row MUTATED across the sweeps.`n  before: $($preSnap[$i])`n  after : $($postSnap[$i])" }
  }

  # --- above-floor row processed exactly once -------------------------------
  $aboveId = [int]$ids[2]
  $ev = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(ack_status),'-') FROM pos_sync_events WHERE id = $aboveId")[0]) -split '\|'
  if ([int]$ev[0] -ne 1 -or $ev[1] -ne 'processed') { throw "above-floor row $aboveId expected settled processed, found count=$($ev[0]) status=$($ev[1])" }
  $exp = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_expenses WHERE note LIKE 'P0EXIT10%'")[0])
  if ($exp -ne 1) { throw "expected exactly 1 pos_expenses row from the above-floor event, found $exp" }

  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ events_processed = 1; events_received = 2; events_failed = 0
    orders = 0; payments = 0; loyalty_ledger = 0; commission_rows = 0; local_donations = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit10_floor_quarantine' -Result 'PASS' `
    -Detail "floor=$floor honored under 2 full + 1 limited concurrent sweeps: both at/below-floor rows byte-untouched (received/NULL/NULL, payload+timestamps identical), the single above-floor row settled exactly once (1 expense, combined processed=1 failed=0)" `
    -Before $before -After $after -ExpectedDelta $expected
}
