# Phase 0 exit gate - EXIT-03 (integrated replay race, test-only).
#
# One create+pay batch with DETERMINISTIC uuids is pushed TWICE by device
# 900111 through a genuine runspace barrier (Invoke-ParallelPosts): the two
# identical HTTP pushes race each other into /api/v1/device/sync/push.
# The exactly-once contract must hold: one pos_orders row, one pos_payments
# row, each of the two client_event_ids settled `processed` exactly once,
# and every ACK envelope internally consistent (accepted+duplicates==total,
# exactly one non-duplicate ACK per event across both responses).

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $token = 'phase0-mdev-machine-a1'
  $orderUuid = 'c0300000-0000-4000-8000-000000000001'
  $ceCreate = 'c0300000-0000-4000-8000-0000000000aa'
  $cePay = 'c0300000-0000-4000-8000-0000000000bb'

  # Deterministic per invocation: purge residue a PRIOR gate invocation left
  # under these fixed uuids in this same disposable DB (children first).
  $orderSel = "SELECT id FROM pos_orders WHERE uuid='$orderUuid'"
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_sale_commissions WHERE order_id IN ($orderSel);
DELETE FROM pos_payments WHERE order_id IN ($orderSel);
DELETE FROM pos_order_item_addons WHERE order_item_id IN (SELECT id FROM pos_order_items WHERE order_id IN ($orderSel));
DELETE FROM pos_order_items WHERE order_id IN ($orderSel);
DELETE FROM pos_order_discounts WHERE order_id IN ($orderSel);
DELETE FROM pos_order_comps WHERE order_id IN ($orderSel);
DELETE FROM pos_order_tables WHERE order_id IN ($orderSel);
DELETE FROM pos_loyalty_transactions WHERE order_id IN ($orderSel);
DELETE FROM pos_orders WHERE uuid='$orderUuid';
DELETE FROM pos_sync_events WHERE client_event_id IN ('$ceCreate','$cePay');
"@ | Out-Null

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $batch = @{ events = @(
      @{ client_event_id = $ceCreate; event_type = 'order.create'; client_timestamp = $nowIso; payload = @{
          order = @{ uuid = $orderUuid; order_type = 'quick'; source = 'main_pos'; staff_id = 900120
            subtotal_baisas = 2500; discount_total_baisas = 0; tax_total_baisas = 0; grand_total_baisas = 2500
            opened_at = $nowIso
            lines = @(@{ product_id = 900140; qty = 1; unit_price_baisas = 2500; line_total_baisas = 2500 })
          }
        }
      },
      @{ client_event_id = $cePay; event_type = 'order.pay'; client_timestamp = $nowIso; payload = @{
          order_uuid = $orderUuid; paid_at = $nowIso
          payments = @(@{ method = 'cash'; amount_baisas = 2500; status = 'success' })
        }
      }
    ) }

  $responses = Invoke-ParallelPosts -Requests @(
    @{ Path = '/api/v1/device/sync/push'; Body = $batch; Token = $token },
    @{ Path = '/api/v1/device/sync/push'; Body = $batch; Token = $token }
  )

  # --- ACK consistency across the two racing responses ----------------------
  $nonDupCreate = 0; $nonDupPay = 0
  for ($i = 0; $i -lt 2; $i++) {
    $r = $responses[$i]
    if ($r.status -ne 200) { throw "push #$i returned HTTP $($r.status), expected 200: $($r.raw)" }
    $s = $r.body.data.summary
    if ([int]$s.total -ne 2) { throw "push #$i ACK summary.total=$($s.total), expected 2" }
    if (([int]$s.accepted + [int]$s.duplicates) -ne 2) { throw "push #$i ACK accepted($($s.accepted))+duplicates($($s.duplicates)) != total(2)" }
    foreach ($ack in $r.body.data.results) {
      if ($ack.client_event_id -eq $ceCreate -and -not $ack.duplicate) { $nonDupCreate++ }
      if ($ack.client_event_id -eq $cePay -and -not $ack.duplicate) { $nonDupPay++ }
    }
  }
  if ($nonDupCreate -ne 1) { throw "order.create received $nonDupCreate non-duplicate ACKs across the two racing pushes, expected exactly 1" }
  if ($nonDupPay -ne 1) { throw "order.pay received $nonDupPay non-duplicate ACKs across the two racing pushes, expected exactly 1" }

  # --- authoritative DB state ----------------------------------------------
  $row = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(status),'-') FROM pos_orders WHERE uuid='$orderUuid'")[0]) -split '\|'
  if ([int]$row[0] -ne 1) { throw "expected exactly 1 pos_orders row for uuid $orderUuid, found $($row[0])" }
  if ($row[1] -ne 'paid') { throw "order $orderUuid settled status '$($row[1])', expected 'paid'" }

  $payCount = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_payments p JOIN pos_orders o ON o.id = p.order_id WHERE o.uuid='$orderUuid'")[0])
  if ($payCount -ne 1) { throw "expected exactly 1 pos_payments row for order $orderUuid, found $payCount (double-settlement)" }

  foreach ($ce in @($ceCreate, $cePay)) {
    $ev = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(ack_status),'-') FROM pos_sync_events WHERE client_event_id='$ce'")[0]) -split '\|'
    if ([int]$ev[0] -ne 1) { throw "client_event_id $ce has $($ev[0]) ledger rows, expected exactly 1" }
    if ($ev[1] -ne 'processed') { throw "client_event_id $ce final ack_status '$($ev[1])', expected 'processed'" }
  }

  # --- effect deltas (cash sale: platform cash_bank + bank card@0 + merchant residual = 3 commission rows)
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 1; orders_paid = 1; payments = 1; events_processed = 2; events_received = 0; events_failed = 0
    loyalty_ledger = 0; commission_rows = 3; local_donations = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit03_replay_race' -Result 'PASS' `
    -Detail 'identical create+pay batch raced by two barrier-released pushes settled exactly once: 1 order (paid), 1 payment, both events processed once, ACK sums consistent, exactly one non-duplicate ACK per event' `
    -Before $before -After $after -ExpectedDelta $expected
}
