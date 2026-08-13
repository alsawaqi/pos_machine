# Phase 0 exit gate - EXIT-04 (concurrent loyalty over-redemption clamp, test-only).
#
# Adjudicates matrix F-6 (the clamp lock): two paid sales race to redeem 100
# points each from customer 900130's single account holding exactly 30 points.
# Both sales MUST settle paid; the account row lock must serialise the clamps
# so the ledger debits AT MOST the 30 points that exist (expected: one redeem
# of -30, a second clamp applying 0), the balance never goes negative, and the
# two zero-delta ADJUST markers carry the exact applied/shortfall arithmetic
# (applied 30+0, shortfall 70+100). Any double debit or negative balance FAILS.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $token = 'phase0-mdev-machine-a1'
  $u1 = 'c0400000-0000-4000-8000-000000000001'
  $u2 = 'c0400000-0000-4000-8000-000000000002'
  $ceC1 = 'c0400000-0000-4000-8000-0000000000a1'
  $ceC2 = 'c0400000-0000-4000-8000-0000000000a2'
  $ceP1 = 'c0400000-0000-4000-8000-0000000000b1'
  $ceP2 = 'c0400000-0000-4000-8000-0000000000b2'
  $acctSel = "SELECT id FROM pos_loyalty_accounts WHERE customer_id=900130 AND loyalty_rule_id=900150"

  # Deterministic per invocation: purge prior-invocation residue for these
  # fixed uuids, wipe the fixture account's ledger and FORCE the contract
  # balance (30 points / 0 stamps) so the clamp arithmetic is exact.
  $orderSel = "SELECT id FROM pos_orders WHERE uuid IN ('$u1','$u2')"
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_sale_commissions WHERE order_id IN ($orderSel);
DELETE FROM pos_payments WHERE order_id IN ($orderSel);
DELETE FROM pos_order_item_addons WHERE order_item_id IN (SELECT id FROM pos_order_items WHERE order_id IN ($orderSel));
DELETE FROM pos_order_items WHERE order_id IN ($orderSel);
DELETE FROM pos_order_discounts WHERE order_id IN ($orderSel);
DELETE FROM pos_order_comps WHERE order_id IN ($orderSel);
DELETE FROM pos_order_tables WHERE order_id IN ($orderSel);
DELETE FROM pos_loyalty_transactions WHERE loyalty_account_id IN ($acctSel);
UPDATE pos_loyalty_accounts SET point_balance=30, stamp_count=0 WHERE customer_id=900130 AND loyalty_rule_id=900150;
DELETE FROM pos_orders WHERE uuid IN ('$u1','$u2');
DELETE FROM pos_sync_events WHERE client_event_id IN ('$ceC1','$ceC2','$ceP1','$ceP2');
"@ | Out-Null

  $bal = [int]((Invoke-Psql -Db $Db -Sql "SELECT coalesce((SELECT point_balance FROM pos_loyalty_accounts WHERE customer_id=900130 AND loyalty_rule_id=900150), -1)")[0])
  if ($bal -ne 30) { throw "precondition failed: fixture loyalty account balance is $bal, expected exactly 30 (run -Setup to seed fixtures)" }

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

  # --- two orders created SEQUENTIALLY (grand 3.000 OMR each, customer 900130)
  foreach ($pair in @(@($ceC1, $u1), @($ceC2, $u2))) {
    $ce = $pair[0]; $uuid = $pair[1]
    $createBody = @{ events = @(
        @{ client_event_id = $ce; event_type = 'order.create'; client_timestamp = $nowIso; payload = @{
            order = @{ uuid = $uuid; order_type = 'quick'; source = 'main_pos'; staff_id = 900120; customer_id = 900130
              subtotal_baisas = 3000; discount_total_baisas = 0; tax_total_baisas = 0; grand_total_baisas = 3000
              opened_at = $nowIso
              lines = @(@{ product_id = 900140; qty = 1; unit_price_baisas = 3000; line_total_baisas = 3000 })
            }
          }
        }
      ) }
    $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -Body $createBody -DeviceToken $token
    if ($r.status -ne 200) { throw "order.create for $uuid returned HTTP $($r.status): $($r.raw)" }
    $ack = $r.body.data.results[0]
    if ($ack.status -ne 'processed') { throw "order.create for $uuid settled '$($ack.status)' (expected processed): $($ack.result | ConvertTo-Json -Compress)" }
  }

  # --- TWO pays racing at the barrier, each redeeming 100 points ------------
  $payBody1 = @{ events = @(
      @{ client_event_id = $ceP1; event_type = 'order.pay'; client_timestamp = $nowIso; payload = @{
          order_uuid = $u1; paid_at = $nowIso
          payments = @(@{ method = 'cash'; amount_baisas = 3000; status = 'success' })
          loyalty_redeem = @{ rule_id = 900150; points = 100; stamps = 0 }
        }
      }
    ) }
  $payBody2 = @{ events = @(
      @{ client_event_id = $ceP2; event_type = 'order.pay'; client_timestamp = $nowIso; payload = @{
          order_uuid = $u2; paid_at = $nowIso
          payments = @(@{ method = 'cash'; amount_baisas = 3000; status = 'success' })
          loyalty_redeem = @{ rule_id = 900150; points = 100; stamps = 0 }
        }
      }
    ) }

  $responses = Invoke-ParallelPosts -Requests @(
    @{ Path = '/api/v1/device/sync/push'; Body = $payBody1; Token = $token },
    @{ Path = '/api/v1/device/sync/push'; Body = $payBody2; Token = $token }
  )

  for ($i = 0; $i -lt 2; $i++) {
    $r = $responses[$i]
    if ($r.status -ne 200) { throw "racing pay #$i returned HTTP $($r.status): $($r.raw)" }
    $ack = $r.body.data.results[0]
    if ($ack.status -ne 'processed') { throw "racing pay #$i settled '$($ack.status)' - the sale MUST settle despite the redemption shortfall: $($ack.result | ConvertTo-Json -Compress)" }
  }

  # --- both sales settled paid, one tender each -----------------------------
  foreach ($uuid in @($u1, $u2)) {
    $row = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(status),'-') FROM pos_orders WHERE uuid='$uuid'")[0]) -split '\|'
    if ([int]$row[0] -ne 1 -or $row[1] -ne 'paid') { throw "order $uuid expected exactly 1 row in status paid, found count=$($row[0]) status=$($row[1])" }
    $pc = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_payments p JOIN pos_orders o ON o.id=p.order_id WHERE o.uuid='$uuid'")[0])
    if ($pc -ne 1) { throw "order $uuid has $pc payment rows, expected exactly 1" }
  }

  # --- the clamp: ledger + balance ------------------------------------------
  $ledger = Invoke-Psql -Db $Db -Sql "SELECT type||'|'||points_delta||'|'||balance_after_points||'|'||coalesce(reason,'') FROM pos_loyalty_transactions WHERE loyalty_account_id IN ($acctSel) ORDER BY id"
  $redeems = @($ledger | Where-Object { $_ -like 'redeem|*' })
  $adjusts = @($ledger | Where-Object { $_ -like 'adjust|*' })
  if ($ledger.Count -ne ($redeems.Count + $adjusts.Count)) { throw "unexpected extra loyalty ledger rows for the fixture account: $($ledger -join ' // ')" }

  $debited = 0
  foreach ($r in $redeems) {
    $delta = [int](($r -split '\|')[1])
    if ($delta -ge 0) { throw "redeem ledger row with non-negative points_delta ${delta}: $r" }
    $debited += (-$delta)
  }
  if ($debited -gt 30) { throw "total points debited across ledger is $debited, exceeding the 30 that existed (double debit)" }
  if ($debited -ne 30) { throw "total points debited is $debited, expected the full available 30 to be clamp-applied" }
  if ($redeems.Count -ne 1) { throw "expected exactly 1 clamped redeem row (-30), found $($redeems.Count): $($redeems -join ' // ')" }

  if ($adjusts.Count -ne 2) { throw "expected exactly 2 zero-delta ADJUST shortfall markers, found $($adjusts.Count): $($adjusts -join ' // ')" }
  $appliedVals = @(); $shortfallVals = @()
  foreach ($a in $adjusts) {
    $parts = $a -split '\|', 4
    if ([int]$parts[1] -ne 0) { throw "ADJUST marker moved points (delta $($parts[1])) - markers must be zero-delta: $a" }
    if ($parts[3] -notlike '`[LOYALTY_REDEMPTION_SHORTFALL`]`[REVIEW_REQUIRED`]*') { throw "ADJUST marker lacks the stable review flag: $a" }
    $m = [regex]::Match($parts[3], 'requested points=(\d+) stamps=\d+; applied points=(\d+) stamps=\d+; shortfall points=(\d+)')
    if (-not $m.Success) { throw "ADJUST marker reason not parseable for exact arithmetic: $a" }
    if ([int]$m.Groups[1].Value -ne 100) { throw "ADJUST marker requested=$($m.Groups[1].Value), expected 100: $a" }
    $appliedVals += [int]$m.Groups[2].Value
    $shortfallVals += [int]$m.Groups[3].Value
  }
  $appliedSorted = ($appliedVals | Sort-Object) -join ','
  $shortfallSorted = ($shortfallVals | Sort-Object) -join ','
  if ($appliedSorted -ne '0,30') { throw "ADJUST applied points across the two clamps = [$appliedSorted], expected exactly [0,30] (sum 30)" }
  if ($shortfallSorted -ne '70,100') { throw "ADJUST shortfall points across the two clamps = [$shortfallSorted], expected exactly [70,100]" }

  $negAfter = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_loyalty_transactions WHERE loyalty_account_id IN ($acctSel) AND balance_after_points < 0")[0])
  if ($negAfter -ne 0) { throw "$negAfter ledger rows snapshot a NEGATIVE balance_after_points" }
  $finalBal = [int]((Invoke-Psql -Db $Db -Sql "SELECT point_balance FROM pos_loyalty_accounts WHERE customer_id=900130 AND loyalty_rule_id=900150")[0])
  if ($finalBal -lt 0) { throw "account balance went NEGATIVE: $finalBal" }
  if ($finalBal -ne 0) { throw "account balance is $finalBal after both clamps, expected exactly 0" }

  # --- effect deltas (2 cash sales x 3 commission rows; ledger = 1 redeem + 2 adjusts)
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 2; orders_paid = 2; payments = 2; loyalty_ledger = 3; events_processed = 4
    events_received = 0; events_failed = 0; commission_rows = 6; local_donations = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit04_concurrent_clamp' -Result 'PASS' `
    -Detail 'F-6 clamp lock adjudicated: both racing pays settled paid; ledger debited exactly the 30 available points (one -30 redeem, no double debit), balance 0 (never negative), two ADJUST markers with exact applied [0,30] / shortfall [70,100] arithmetic' `
    -Before $before -After $after -ExpectedDelta $expected
}
