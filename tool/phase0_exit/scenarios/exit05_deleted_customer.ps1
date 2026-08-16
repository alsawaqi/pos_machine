# EXIT-05 (integrated, real PG FKs) - customer deleted before queued replay.
# Added 2026-08-16 during IMP-2 verification: proves the production
# nullOnDelete FK behavior + the IMP-2 earn-attribution guard end to end,
# which sqlite :memory: structurally cannot (its test schema has no FKs).
# Legs: (A) hard-delete -> pay with earn context FAILS visibly, parkable,
# zero effects, replay dedupes; (B) genuine walk-in control still settles
# with no earn row; (C) soft-deleted customer control settles WITH earn.
# ASCII ONLY. Uses fixture device 900111 / product 900140 / rule 900150 and
# scenario-local customers 900930/900931 (purged before the baseline).

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $token = 'phase0-mdev-machine-a1'
  $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

  # Deterministic scenario-local ids (e05/d05 prefixes).
  $ordA = 'e0500000-0000-4000-8000-000000000001'
  $ordB = 'e0500000-0000-4000-8000-000000000002'
  $ordC = 'e0500000-0000-4000-8000-000000000003'
  $ceA1 = 'd0500000-0000-4000-8000-000000000011'; $ceA2 = 'd0500000-0000-4000-8000-000000000012'
  $ceB1 = 'd0500000-0000-4000-8000-000000000021'; $ceB2 = 'd0500000-0000-4000-8000-000000000022'
  $ceC1 = 'd0500000-0000-4000-8000-000000000031'; $ceC2 = 'd0500000-0000-4000-8000-000000000032'

  # Purge residue BEFORE the baseline snapshot (re-run safety).
  $null = Invoke-Psql -Db $Db -Sql @"
SET client_min_messages = warning;
DELETE FROM pos_loyalty_transactions WHERE loyalty_account_id IN (SELECT id FROM pos_loyalty_accounts WHERE customer_id IN (900930, 900931));
DELETE FROM pos_sale_commissions WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid::text LIKE 'e0500000-%');
DELETE FROM pos_payments WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid::text LIKE 'e0500000-%');
DELETE FROM pos_order_items WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid::text LIKE 'e0500000-%');
DELETE FROM pos_orders WHERE uuid::text LIKE 'e0500000-%';
DELETE FROM pos_sync_events WHERE client_event_id::text LIKE 'd0500000-%';
DELETE FROM pos_loyalty_accounts WHERE customer_id IN (900930, 900931);
DELETE FROM pos_customers WHERE id IN (900930, 900931);
"@

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  # Seed the two scenario customers.
  $null = Invoke-Psql -Db $Db -Sql @"
INSERT INTO pos_customers (id, uuid, company_id, name, phone, created_at, updated_at)
VALUES (900930, 'f0500000-0000-4000-8000-000000900930', 900100, 'P0 HardDelete', '90093000', now(), now()),
       (900931, 'f0500000-0000-4000-8000-000000900931', 900100, 'P0 SoftDelete', '90093100', now(), now());
"@

  function New-CreateEvent([string]$ce, [string]$uuid, $customerId) {
    $order = [ordered]@{
      uuid = $uuid; order_type = 'quick'; source = 'main_pos'
      subtotal_baisas = 2500; discount_total_baisas = 0; tax_total_baisas = 0
      grand_total_baisas = 2500; opened_at = $now
      lines = @(@{ product_id = 900140; qty = 1; unit_price_baisas = 2500; line_total_baisas = 2500 })
    }
    if ($null -ne $customerId) { $order.customer_id = $customerId }
    return @{ client_event_id = $ce; event_type = 'order.create'; client_timestamp = $now; payload = @{ order = $order } }
  }
  function New-PayEvent([string]$ce, [string]$uuid) {
    return @{ client_event_id = $ce; event_type = 'order.pay'; client_timestamp = $now
      payload = @{ order_uuid = $uuid; paid_at = $now
        payments = @(@{ method = 'cash'; amount_baisas = 2500; status = 'success' })
        loyalty_rule_ids = @(900150) } }
  }
  function Get-Ack($resp, [string]$ce) {
    return @($resp.body.data.results) | Where-Object { $_.client_event_id -eq $ce } | Select-Object -First 1
  }

  # ---- Leg A: attributed order, then HARD delete, then pay with earn -------
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-CreateEvent $ceA1 $ordA 900930) }
  $ack = Get-Ack $r $ceA1
  if ($ack.status -ne 'processed') { throw "legA create not processed: $($ack | ConvertTo-Json -Depth 6)" }
  $cust = (Invoke-Psql -Db $Db -Sql "SELECT customer_id FROM pos_orders WHERE uuid = '$ordA'")[0]
  if ($cust -ne '900930') { throw "legA order not attributed (customer_id=$cust)" }

  $null = Invoke-Psql -Db $Db -Sql "SET client_min_messages = warning; DELETE FROM pos_customers WHERE id = 900930;"
  $custAfter = (Invoke-Psql -Db $Db -Sql "SELECT COALESCE(customer_id::text, 'NULL') FROM pos_orders WHERE uuid = '$ordA'")[0]
  if ($custAfter -ne 'NULL') { throw "production FK did not null customer_id (got $custAfter)" }

  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-PayEvent $ceA2 $ordA) }
  $ack = Get-Ack $r $ceA2
  if ($ack.status -ne 'failed') { throw "legA pay did not fail (status=$($ack.status))" }
  $err = [string]$ack.result.error
  if ($err -ne 'cannot earn loyalty without a customer on the order') { throw "legA wrong error: '$err'" }
  $st = (Invoke-Psql -Db $Db -Sql "SELECT status FROM pos_orders WHERE uuid = '$ordA'")[0]
  if ($st -ne 'open') { throw "legA order not open after failed pay (status=$st)" }
  $pays = [int](Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_payments p JOIN pos_orders o ON o.id = p.order_id WHERE o.uuid = '$ordA'")[0]
  if ($pays -ne 0) { throw "legA payment row survived the rollback ($pays)" }

  # Replay the identical failed pay: the ledger re-dispatches and fails
  # identically; no duplicate ledger row, still zero effects.
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-PayEvent $ceA2 $ordA) }
  $ack = Get-Ack $r $ceA2
  if ($ack.status -ne 'failed') { throw "legA replay not failed (status=$($ack.status))" }
  $rows = [int](Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_sync_events WHERE client_event_id = '$ceA2'")[0]
  if ($rows -ne 1) { throw "legA replay duplicated the ledger row ($rows)" }
  $pays = [int](Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_payments p JOIN pos_orders o ON o.id = p.order_id WHERE o.uuid = '$ordA'")[0]
  if ($pays -ne 0) { throw "legA replay created a payment ($pays)" }

  # ---- Leg B: genuine walk-in control (no customer ever) -------------------
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-CreateEvent $ceB1 $ordB $null) }
  $ack = Get-Ack $r $ceB1
  if ($ack.status -ne 'processed') { throw "legB create not processed" }
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-PayEvent $ceB2 $ordB) }
  $ack = Get-Ack $r $ceB2
  if ($ack.status -ne 'processed') { throw "legB walk-in pay refused: $($ack.result.error)" }
  $st = (Invoke-Psql -Db $Db -Sql "SELECT status FROM pos_orders WHERE uuid = '$ordB'")[0]
  if ($st -eq 'open') { throw 'legB walk-in did not settle' }
  $earnB = [int](Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_loyalty_transactions t JOIN pos_orders o ON o.id = t.order_id WHERE o.uuid = '$ordB'")[0]
  if ($earnB -ne 0) { throw "legB walk-in wrote a loyalty row ($earnB)" }

  # ---- Leg C: soft-deleted customer control (stays attributable) -----------
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-CreateEvent $ceC1 $ordC 900931) }
  $ack = Get-Ack $r $ceC1
  if ($ack.status -ne 'processed') { throw "legC create not processed" }
  $null = Invoke-Psql -Db $Db -Sql "UPDATE pos_customers SET deleted_at = now() WHERE id = 900931;"
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -DeviceToken $token -Body @{ events = @(New-PayEvent $ceC2 $ordC) }
  $ack = Get-Ack $r $ceC2
  if ($ack.status -ne 'processed') { throw "legC soft-delete pay refused: $($ack.result.error)" }
  $earnC = [int](Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_loyalty_transactions t JOIN pos_loyalty_accounts a ON a.id = t.loyalty_account_id WHERE a.customer_id = 900931")[0]
  if ($earnC -ne 1) { throw "legC expected exactly 1 attributed earn row, got $earnC" }

  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  Assert-Delta -Before $before -After $after -Expected @{
    orders = 3; orders_paid = 2; payments = 2; commission_rows = 6
    loyalty_ledger = 1; loyalty_reviews = 0; stock_movements = 0
    local_donations = 0; events_processed = 5; events_failed = 1
  }

  return New-ScenarioResult -Id 'exit05_deleted_customer' -Result 'PASS' -Detail (
    'legA: production FK nulled customer_id on hard delete (verified); pay with earn context FAILED visibly ' +
    "with the exact IMP-2 guard error; order stayed open, zero payment/effect rows; replay deduped (1 ledger row). " +
    'legB walk-in control settled paid with zero earn rows. legC soft-deleted customer settled with exactly one ' +
    'attributed earn row. Deltas exact: orders+3 (2 paid, 1 parked-open), payments+2, commission+6, earn+1, failed+1.'
  ) -Before $before -After $after -ExpectedDelta @{ orders = 3; payments = 2; commission_rows = 6; loyalty_ledger = 1; events_failed = 1 }
}
