# Phase 0 exit gate - EXIT-15 (tenant-scoped event identity under real HTTP races, test-only).
#
# Integrated twin of pos_api W-A5 (tests/Feature/Phase0Exit/TenantScopedEventIdentityTest)
# on real PG with barrier-released concurrent pushes:
#
# (a) SAME company, DIFFERENT devices (900111 + 900113) push ONE identical
#     client_event_id (expense.log) through the runspace gate. Idempotency is
#     keyed (device_id, client_event_id): the result must be TWO independent
#     ledger rows and TWO pos_expenses (each device's own amount), never a
#     cross-device dedupe swallow.
# (b) CROSS tenant: devices 900111 (company 900100) and 900211 (company
#     900200) race order.create with the SAME order uuid at the gate. Exactly
#     one pos_orders row may exist afterwards, owned by the winner's tenant;
#     the loser's event FAILS in its own ledger row (either the deterministic
#     'order uuid already exists outside the device tenant' guard or its side
#     of the uuid unique-index race) and a replay of the loser stays a parked
#     failure. Any second row, or a surviving row whose company/branch was
#     adopted or mutated cross-tenant, throws (candidate product finding).
#
# Scenario-local fixture: company-B needs its own product for the in-tenant
# reference guard, seeded idempotently here as pos_products id 900240
# (company 900200) - same column set the fixture seeder uses.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $tokenA1 = 'phase0-mdev-machine-a1'   # device 900111, company 900100/branch 900110
  $tokenA3 = 'phase0-mdev-spare-a1'     # device 900113, same company/branch
  $tokenB = 'phase0-mdev-machine-b1'    # device 900211, company 900200/branch 900210
  $tag = 'c1500000'
  $sharedCe = "$tag-0000-4000-8000-0000000000aa"
  $orderUuid = "$tag-0000-4000-8000-00000000000b"
  $ceA = "$tag-0000-4000-8000-0000000000b1"
  $ceB = "$tag-0000-4000-8000-0000000000b2"

  # Deterministic per invocation: purge this tag's residue + seed the
  # scenario-local company-B product (fixed id 900240, idempotent).
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_expenses WHERE note LIKE 'P0EXIT15%';
DELETE FROM pos_order_item_addons WHERE order_item_id IN (SELECT id FROM pos_order_items WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid='$orderUuid'));
DELETE FROM pos_order_items WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid='$orderUuid');
DELETE FROM pos_orders WHERE uuid='$orderUuid';
DELETE FROM pos_sync_events WHERE client_event_id::text LIKE '$tag-%';
INSERT INTO pos_products (id, uuid, company_id, name, base_price, stock_mode, status, created_at, updated_at)
VALUES (900240, 'f0000000-0000-4000-8000-000000900240', 900200, 'P0 B Untracked', 2.500, 'untracked', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
"@ | Out-Null

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

  # ---- (a) same-company different-device shared client_event_id -----------
  function New-ExpenseBatch([string]$Ce, [int]$AmountBaisas, [string]$At) {
    return @{ events = @(
        @{ client_event_id = $Ce; event_type = 'expense.log'; client_timestamp = $At; payload = @{
            category = 'utilities'; amount_baisas = $AmountBaisas; note = 'P0EXIT15 shared-id probe'; staff_id = 900120
          }
        }
      ) }
  }

  $pair = Invoke-ParallelPosts -Requests @(
    @{ Path = '/api/v1/device/sync/push'; Body = (New-ExpenseBatch $sharedCe 5000 $nowIso); Token = $tokenA1 },
    @{ Path = '/api/v1/device/sync/push'; Body = (New-ExpenseBatch $sharedCe 7000 $nowIso); Token = $tokenA3 }
  )
  $eventIds = @(); $expenseIds = @()
  for ($i = 0; $i -lt 2; $i++) {
    $r = $pair[$i]
    if ($r.status -ne 200) { throw "shared-id push #$i returned HTTP $($r.status): $($r.raw)" }
    $ack = $r.body.data.results[0]
    if ($ack.duplicate) { throw "shared-id push #$i was answered as DUPLICATE - a different device's reuse of the client_event_id was swallowed cross-device" }
    if ($ack.status -ne 'processed') { throw "shared-id push #$i settled '$($ack.status)', expected processed: $($ack.result | ConvertTo-Json -Compress)" }
    $eventIds += [int]$ack.event_id
    $expenseIds += [int]$ack.result.expense_id
  }
  if ($eventIds[0] -eq $eventIds[1]) { throw "both devices' ACKs point at the SAME ledger row $($eventIds[0]) - idempotency is not (device_id, client_event_id) scoped" }
  if ($expenseIds[0] -eq $expenseIds[1]) { throw "both devices' ACKs point at the SAME expense $($expenseIds[0]) - one financial effect swallowed" }

  $led = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||count(*) FILTER (WHERE ack_status='processed')||'|'||count(DISTINCT device_id) FROM pos_sync_events WHERE client_event_id='$sharedCe'")[0]) -split '\|'
  if ([int]$led[0] -ne 2 -or [int]$led[1] -ne 2 -or [int]$led[2] -ne 2) { throw "shared client_event_id ledger expected 2 processed rows across 2 devices, found count=$($led[0]) processed=$($led[1]) devices=$($led[2])" }
  $exp = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(string_agg(amount::text, ',' ORDER BY amount),'') FROM pos_expenses WHERE note LIKE 'P0EXIT15%'")[0]) -split '\|'
  if ([int]$exp[0] -ne 2) { throw "expected exactly 2 pos_expenses from the shared-id race, found $($exp[0])" }
  if ($exp[1] -ne '5.000,7.000') { throw "the two expenses carry amounts [$($exp[1])], expected each device's own [5.000,7.000]" }

  # ---- (b) cross-tenant same order uuid race -------------------------------
  function New-CreateBatch([string]$Ce, [string]$Uuid, [int]$ProductId, [object]$StaffId, [int]$Baisas, [string]$At) {
    $order = @{ uuid = $Uuid; order_type = 'quick'; source = 'main_pos'
      subtotal_baisas = $Baisas; discount_total_baisas = 0; tax_total_baisas = 0; grand_total_baisas = $Baisas
      opened_at = $At
      lines = @(@{ product_id = $ProductId; qty = 1; unit_price_baisas = $Baisas; line_total_baisas = $Baisas })
    }
    if ($null -ne $StaffId) { $order.staff_id = $StaffId }
    return @{ events = @(@{ client_event_id = $Ce; event_type = 'order.create'; client_timestamp = $At; payload = @{ order = $order } }) }
  }

  $batchA = New-CreateBatch $ceA $orderUuid 900140 900120 2500 $nowIso
  $batchB = New-CreateBatch $ceB $orderUuid 900240 $null 3000 $nowIso
  $race = Invoke-ParallelPosts -Requests @(
    @{ Path = '/api/v1/device/sync/push'; Body = $batchA; Token = $tokenA1 },
    @{ Path = '/api/v1/device/sync/push'; Body = $batchB; Token = $tokenB }
  )
  ($race | ForEach-Object { $_.raw }) -join "`n" | Out-File -Encoding utf8 (Join-Path $Art 'exit15_race.txt')

  $acks = @()
  for ($i = 0; $i -lt 2; $i++) {
    $r = $race[$i]
    if ($r.status -ne 200) { throw "cross-tenant push #$i returned HTTP $($r.status): $($r.raw)" }
    $acks += $r.body.data.results[0]
  }
  $procIdx = @(); $failIdx = @()
  for ($i = 0; $i -lt 2; $i++) {
    if ($acks[$i].status -eq 'processed') { $procIdx += $i }
    elseif ($acks[$i].status -eq 'failed') { $failIdx += $i }
    else { throw "cross-tenant push #$i settled unexpected status '$($acks[$i].status)'" }
  }
  if ($procIdx.Count -eq 2) { throw "BOTH tenants' order.create settled processed for one uuid - cross-tenant adoption/merge (candidate product finding)" }
  if ($procIdx.Count -ne 1 -or $failIdx.Count -ne 1) { throw "expected exactly one processed + one failed ACK, got processed=$($procIdx.Count) failed=$($failIdx.Count)" }
  $winnerIdx = $procIdx[0]; $loserIdx = $failIdx[0]
  $winnerCompany = if ($winnerIdx -eq 0) { 900100 } else { 900200 }
  $winnerBranch = if ($winnerIdx -eq 0) { 900110 } else { 900210 }
  $winnerTotal = if ($winnerIdx -eq 0) { '2.500' } else { '3.000' }
  $loserErr = [string]$acks[$loserIdx].result.error
  $loserTenantGuard = $loserErr -like '*order uuid already exists outside the device tenant*'
  $loserUniqueRace = ($loserErr -match '(?i)unique|duplicate|23505')
  if (-not ($loserTenantGuard -or $loserUniqueRace)) { throw "loser failed with an unexpected error (neither the tenant guard nor its side of the uuid unique race): $loserErr" }

  # Authoritative DB state: one row, winner-owned, never mutated cross-tenant.
  $row = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(company_id)::text,'-')||'|'||coalesce(min(branch_id)::text,'-')||'|'||coalesce(min(grand_total)::text,'-')||'|'||coalesce(min(status),'-') FROM pos_orders WHERE uuid='$orderUuid'")[0]) -split '\|'
  if ([int]$row[0] -ne 1) { throw "expected exactly 1 pos_orders row for the colliding uuid, found $($row[0]) (cross-tenant duplicate)" }
  if ([int]$row[1] -ne $winnerCompany -or [int]$row[2] -ne $winnerBranch) { throw "surviving order is owned by company=$($row[1])/branch=$($row[2]) but the WINNER device belongs to $winnerCompany/$winnerBranch - cross-tenant adoption (candidate product finding)" }
  if ($row[3] -ne $winnerTotal) { throw "surviving order grand_total=$($row[3]), expected the winner's $winnerTotal - loser money leaked into the foreign row" }

  # The loser's rejection is parked in ITS OWN ledger row, and a replay stays
  # a deterministic parked failure (never worn down into an adoption).
  $loserCe = if ($loserIdx -eq 0) { $ceA } else { $ceB }
  $loserToken = if ($loserIdx -eq 0) { $tokenA1 } else { $tokenB }
  $loserBatch = if ($loserIdx -eq 0) { $batchA } else { $batchB }
  $lrow = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||coalesce(min(ack_status),'-') FROM pos_sync_events WHERE client_event_id='$loserCe'")[0]) -split '\|'
  if ([int]$lrow[0] -ne 1 -or $lrow[1] -ne 'failed') { throw "loser ledger row expected exactly 1 failed row, found count=$($lrow[0]) status=$($lrow[1])" }

  $replay = Invoke-ApiPost -Path '/api/v1/device/sync/push' -Body $loserBatch -DeviceToken $loserToken
  if ($replay.status -ne 200) { throw "loser replay returned HTTP $($replay.status): $($replay.raw)" }
  $rAck = $replay.body.data.results[0]
  if (-not $rAck.duplicate) { throw "loser replay was NOT answered as a duplicate - the parked failure was reprocessed" }
  if ($rAck.status -ne 'failed') { throw "loser replay settled '$($rAck.status)', expected the parked failed" }
  $row2 = ((Invoke-Psql -Db $Db -Sql "SELECT count(*)||'|'||min(company_id)::text FROM pos_orders WHERE uuid='$orderUuid'")[0]) -split '\|'
  if ([int]$row2[0] -ne 1 -or [int]$row2[1] -ne $winnerCompany) { throw "after the loser replay: count=$($row2[0]) company=$($row2[1]) - the collision was worn down into an adoption" }

  # ---- effect deltas (1 surviving open order; 2+1 processed, 1 failed) -----
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 1; orders_paid = 0; payments = 0; events_processed = 3; events_failed = 1; events_received = 0
    loyalty_ledger = 0; commission_rows = 0; local_donations = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  $loserMode = if ($loserTenantGuard) { 'deterministic tenant guard' } else { 'uuid unique-index race' }
  $winnerName = if ($winnerIdx -eq 0) { 'tenant A (900100/900110)' } else { 'tenant B (900200/900210)' }
  return New-ScenarioResult -Id 'exit15_tenant_collision' -Result 'PASS' `
    -Detail ("(a) shared client_event_id across two same-company devices settled as 2 independent ledger rows + 2 expenses (5.000/7.000), no cross-device swallow; (b) cross-tenant uuid race: winner=$winnerName owns the single surviving row (company/branch/total byte-faithful), loser failed via $loserMode ('$loserErr') and its replay stayed a parked duplicate failure - no adoption, no mutation.") `
    -Before $before -After $after -ExpectedDelta $expected
}
