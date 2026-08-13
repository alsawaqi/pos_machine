# Phase 0 exit gate - EXIT-11 (admin approval vs device void, test-only).
#
# Adjudicates docs/phase0_failures/FAIL-EXIT-11 on real PG. The SQLite
# in-process interleave showed ApprovePendingReconciliationAction minting
# commissions on an order voided after candidate hydration; on PG the action
# now takes SELECT ... FOR UPDATE on the order (the same serialization root
# order.void locks), so the claim to adjudicate is whether ANY interleaving
# still lets a voided sale keep commissions / a success tender / a forwarded
# donation.
#
# (a) deterministic legs on fixture orders (make_pending_orders.php, tag
#     c1100000, orders 1-2):
#       leg1  void (device 900111 order.void via real HTTP push) THEN approve
#             => zero commissions, no tender flip, no charity forward;
#       leg2  approve THEN void => the void unwinds (commissions deleted,
#             donation voided; the already-settled external charity_transaction
#             is documented as out of scope and deliberately kept).
# (b) concurrent barrage on orders 3-12: approve_recon.php approves all 10
#     inside admin_runner behind a ready/go barrier (bare tables phase0_e11_*
#     in the disposable DB) while 10 order.void pushes fire at the
#     Invoke-ParallelPosts gate. Afterwards EVERY order must satisfy the
#     terminal-void invariant: never (status=void AND commission rows present
#     AND tender success AND donation forwarded_at set) - asserted here in the
#     STRONGER form commissions==0 on every voided order, because a nonzero
#     residue is exactly FAIL-EXIT-11's phantom-commission defect.
#
# PASS refutes FAIL-EXIT-11's interleaving on PG; an invariant breach throws
# (candidate product finding: FAIL-EXIT-11 confirmed live).

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $token = 'phase0-mdev-machine-a1'
  $tag = 'c1100000'
  $orderUuid = @{}; $donKey = @{}
  foreach ($i in 1..12) {
    $orderUuid[$i] = ('{0}-0000-4000-8000-a{1:d11}' -f $tag, $i)
    $donKey[$i] = ('pos_roundup:{0}-0000-4000-8000-d{1:d11}' -f $tag, $i)
  }

  # Harness precondition: the charity receiver must be up (leg2/barrage
  # approvals forward donations through it). Self-heal first - a crashed
  # earlier run may have left the receiver absent - then fail loudly.
  $charityUp = $false
  foreach ($i in 1..3) {
    try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:58001/up' -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { $charityUp = $true; break } } catch { Start-Sleep -Milliseconds 300 }
  }
  if (-not $charityUp) {
    wsl -e bash -lc "$Dc up -d charity_server 2>&1" | Out-Null
    foreach ($i in 1..30) {
      try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:58001/up' -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { $charityUp = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
  }
  if (-not $charityUp) { throw 'harness precondition failed: charity receiver (127.0.0.1:58001) is not up (self-heal attempted) - cannot adjudicate the forward leg' }

  # Deterministic per invocation: purge prior-run charity residue for this
  # tag's stable donation uuids (shares first - FK).
  Invoke-Psql -Db $CharityDb -Sql @"
DELETE FROM charity_transaction_shares WHERE charity_transaction_id IN (SELECT id FROM charity_transactions WHERE idempotency_key LIKE 'pos_roundup:$tag-%');
DELETE FROM charity_transactions WHERE idempotency_key LIKE 'pos_roundup:$tag-%';
"@ | Out-Null
  # ...and the POS-side residue BEFORE the effect baseline (make_pending's own
  # purge runs after $before, which would net every re-run delta to zero).
  $orderSel = "SELECT id FROM pos_orders WHERE uuid::text LIKE '$tag-%'"
  Invoke-Psql -Db $Db -Sql @"
DELETE FROM pos_sale_commissions WHERE order_id IN ($orderSel);
DELETE FROM pos_roundup_donations WHERE order_id IN ($orderSel);
DELETE FROM pos_payments WHERE order_id IN ($orderSel);
DELETE FROM pos_order_item_addons WHERE order_item_id IN (SELECT id FROM pos_order_items WHERE order_id IN ($orderSel));
DELETE FROM pos_order_items WHERE order_id IN ($orderSel);
DELETE FROM pos_order_discounts WHERE order_id IN ($orderSel);
DELETE FROM pos_order_comps WHERE order_id IN ($orderSel);
DELETE FROM pos_order_tables WHERE order_id IN ($orderSel);
DELETE FROM pos_loyalty_transactions WHERE order_id IN ($orderSel);
DELETE FROM pos_orders WHERE uuid::text LIKE '$tag-%';
DELETE FROM pos_sync_events WHERE client_event_id::text LIKE '$tag-%';
"@ | Out-Null

  $before = Get-EffectCounts -Db $Db -CharityDb $CharityDb

  # 12 pending-reconciliation arrangements (purges its own tag residue first).
  $mkOut = Invoke-AdminRunner -Dc $Dc -Cmd 'php /phase0tool/make_pending_orders.php 12 c1100000'
  $mkJson = @($mkOut | Where-Object { $_ -like '{*' })
  if ($mkJson.Count -lt 1) { throw "make_pending_orders.php produced no JSON: $($mkOut -join ' / ')" }
  $mk = $mkJson[-1] | ConvertFrom-Json
  if ([int]$mk.count -ne 12) { throw "make_pending_orders.php created $($mk.count) orders, expected 12" }

  $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  function New-VoidBatch([string]$OrderUuid, [string]$Ce, [string]$At) {
    return @{ events = @(
        @{ client_event_id = $Ce; event_type = 'order.void'; client_timestamp = $At; payload = @{
            order_uuid = $OrderUuid; voided_at = $At; reason = 'P0EXIT11 race probe'
          }
        }
      ) }
  }

  # ---- leg1: void FIRST, then approve -------------------------------------
  $ce1 = ('{0}-0000-4000-8000-e{1:d11}' -f $tag, 1)
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -Body (New-VoidBatch $orderUuid[1] $ce1 $nowIso) -DeviceToken $token
  if ($r.status -ne 200) { throw "leg1 void push returned HTTP $($r.status): $($r.raw)" }
  $ack = $r.body.data.results[0]
  if ($ack.status -ne 'processed') { throw "leg1 void settled '$($ack.status)', expected processed: $($ack.result | ConvertTo-Json -Compress)" }

  $apOut = Invoke-AdminRunner -Dc $Dc -Cmd "php /phase0tool/approve_recon.php $($orderUuid[1])" -AllowFail
  $ap1 = @($apOut | Where-Object { $_ -like '{*' })
  if ($ap1.Count -ne 1) { throw "leg1 approve_recon produced $($ap1.Count) JSON lines, expected 1: $($apOut -join ' / ')" }
  $ap1 = $ap1[0] | ConvertFrom-Json
  if ($null -ne $ap1.error) { throw "leg1 approve errored: $($ap1.error)" }
  if ([int]$ap1.flipped -ne 0) { throw "leg1 approve AFTER void flipped $($ap1.flipped) tenders, expected 0 (void must be terminal)" }

  $row = ((Invoke-Psql -Db $Db -Sql @"
SELECT o.status||'|'||(SELECT count(*) FROM pos_sale_commissions WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_payments WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_roundup_donations WHERE order_id=o.id)
  ||'|'||(SELECT CASE WHEN min(forwarded_at) IS NULL THEN 'null' ELSE 'set' END FROM pos_roundup_donations WHERE order_id=o.id)
FROM pos_orders o WHERE o.uuid='$($orderUuid[1])'
"@)[0]) -split '\|'
  if ($row[0] -ne 'void') { throw "leg1 order status '$($row[0])', expected void" }
  if ([int]$row[1] -ne 0) { throw "leg1 (void-then-approve) minted $($row[1]) commission rows on a VOID order - FAIL-EXIT-11 phantom commissions CONFIRMED on PG" }
  if ($row[2] -ne 'pending_reconciliation') { throw "leg1 tender status '$($row[2])', expected still pending_reconciliation (no flip after void)" }
  if ($row[3] -ne 'void') { throw "leg1 donation status '$($row[3])', expected void" }
  if ($row[4] -ne 'null') { throw "leg1 donation forwarded_at is SET - a voided sale's round-up was forwarded" }
  $c = [int]((Invoke-Psql -Db $CharityDb -Sql "SELECT count(*) FROM charity_transactions WHERE idempotency_key='$($donKey[1])'")[0])
  if ($c -ne 0) { throw "leg1 charity receiver recorded $c transaction(s) for the voided order's round-up, expected 0" }

  # ---- leg2: approve FIRST, then void -------------------------------------
  $apOut = Invoke-AdminRunner -Dc $Dc -Cmd "php /phase0tool/approve_recon.php $($orderUuid[2])" -AllowFail
  $ap2 = @($apOut | Where-Object { $_ -like '{*' })
  if ($ap2.Count -ne 1) { throw "leg2 approve_recon produced $($ap2.Count) JSON lines, expected 1: $($apOut -join ' / ')" }
  $ap2 = $ap2[0] | ConvertFrom-Json
  if ($null -ne $ap2.error) { throw "leg2 approve errored: $($ap2.error)" }
  if ([int]$ap2.flipped -ne 1) { throw "leg2 approve flipped $($ap2.flipped) tenders, expected 1" }
  if ([int]$ap2.commissions -ne 1) { throw "leg2 approve recorded commissions for $($ap2.commissions) orders, expected 1" }
  if ([int]$ap2.forwarded -ne 1) { throw "leg2 approve forwarded $($ap2.forwarded) donations, expected 1 (charity receiver is up)" }
  $cc = [int]((Invoke-Psql -Db $Db -Sql "SELECT count(*) FROM pos_sale_commissions WHERE order_id IN (SELECT id FROM pos_orders WHERE uuid='$($orderUuid[2])')")[0])
  if ($cc -ne 3) { throw "leg2 post-approve commission rows = $cc, expected 3 (platform/bank/merchant)" }

  $ce2 = ('{0}-0000-4000-8000-e{1:d11}' -f $tag, 2)
  $r = Invoke-ApiPost -Path '/api/v1/device/sync/push' -Body (New-VoidBatch $orderUuid[2] $ce2 $nowIso) -DeviceToken $token
  if ($r.status -ne 200) { throw "leg2 void push returned HTTP $($r.status): $($r.raw)" }
  $ack = $r.body.data.results[0]
  if ($ack.status -ne 'processed') { throw "leg2 void settled '$($ack.status)', expected processed: $($ack.result | ConvertTo-Json -Compress)" }
  if ([int]$ack.result.commission_removed -ne 3) { throw "leg2 void removed $($ack.result.commission_removed) commission rows, expected 3" }
  if ([int]$ack.result.roundup_voided -ne 1) { throw "leg2 void flipped $($ack.result.roundup_voided) donations, expected 1" }

  $row = ((Invoke-Psql -Db $Db -Sql @"
SELECT o.status||'|'||(SELECT count(*) FROM pos_sale_commissions WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_payments WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_roundup_donations WHERE order_id=o.id)
FROM pos_orders o WHERE o.uuid='$($orderUuid[2])'
"@)[0]) -split '\|'
  if ($row[0] -ne 'void') { throw "leg2 order status '$($row[0])', expected void" }
  if ([int]$row[1] -ne 0) { throw "leg2 (approve-then-void) left $($row[1]) commission rows after the void unwind, expected 0" }
  if ($row[3] -ne 'void') { throw "leg2 donation status '$($row[3])', expected void after the unwind" }
  # Documented product scope: the already-forwarded external charity_transaction
  # stays (VoidOrderHandler: refunding a settled external record is manual).
  $c = [int]((Invoke-Psql -Db $CharityDb -Sql "SELECT count(*) FROM charity_transactions WHERE idempotency_key='$($donKey[2])'")[0])
  if ($c -ne 1) { throw "leg2 expected exactly 1 charity transaction from the pre-void forward, found $c" }

  # ---- (b) concurrent barrage: approve sweep vs 10 void pushes -------------
  # client_min_messages: the IF EXISTS NOTICE otherwise lands on stderr, which
  # a redirecting caller (2>&1) would wrap into a terminating NativeCommandError.
  Invoke-Psql -Db $Db -Sql @"
SET client_min_messages TO WARNING;
DROP TABLE IF EXISTS phase0_e11_ready;
DROP TABLE IF EXISTS phase0_e11_go;
CREATE TABLE phase0_e11_ready(x int);
CREATE TABLE phase0_e11_go(x int);
"@ | Out-Null

  $barrageUuids = @(); foreach ($i in 3..12) { $barrageUuids += $orderUuid[$i] }
  $uuidArgs = $barrageUuids -join ' '
  $cidOut = @(wsl -e bash -lc "$Dc run -d --no-deps -e PHASE0_BARRIER=phase0_e11 admin_runner php /phase0tool/approve_recon.php $uuidArgs 2>&1")
  if ($LASTEXITCODE -ne 0) { throw "failed to launch detached approve_recon container: $($cidOut -join ' / ')" }
  $cid = @($cidOut | Where-Object { $_ -match '^[0-9a-f]{12,64}$' })
  if ($cid.Count -lt 1) { throw "could not identify approve container id from: $($cidOut -join ' / ')" }
  $cid = $cid[-1]

  try {
    # Wait (bounded 60s) for the approver to boot + resolve + arm.
    $ready = $false
    foreach ($i in 1..120) {
      if ([int]((Invoke-Psql -Db $Db -Sql 'SELECT count(*) FROM phase0_e11_ready')[0]) -gt 0) { $ready = $true; break }
      Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'approve_recon never signalled ready within 60s (see docker logs)' }

    # Release: go row first (approver polls at 50ms), then the void volley
    # through the genuine runspace gate - both sides overlap on the shared PG.
    Invoke-Psql -Db $Db -Sql 'INSERT INTO phase0_e11_go VALUES (1)' | Out-Null
    $voidReqs = @()
    foreach ($i in 3..12) {
      $ce = ('{0}-0000-4000-8000-e{1:d11}' -f $tag, $i)
      $voidReqs += @{ Path = '/api/v1/device/sync/push'; Body = (New-VoidBatch $orderUuid[$i] $ce $nowIso); Token = $token }
    }
    $voidResults = Invoke-ParallelPosts -Requests $voidReqs

    $waitOut = (wsl -e bash -lc "docker wait $cid").Trim()
    $apLogs = (wsl -e bash -lc "docker logs $cid 2>&1") -join "`n"
  } finally {
    wsl -e bash -lc "docker rm -f $cid >/dev/null 2>&1" | Out-Null
  }
  $apLogs | Out-File -Encoding utf8 (Join-Path $Art 'exit11_approve.txt')
  ($voidResults | ForEach-Object { $_.raw }) -join "`n" | Out-File -Encoding utf8 (Join-Path $Art 'exit11_voids.txt')

  if ($waitOut -ne '0') { throw "barrage approve_recon exited $waitOut - an approval threw mid-race: $apLogs" }
  $apLines = @($apLogs -split "`n" | Where-Object { $_ -like '{*' } | ForEach-Object { $_ | ConvertFrom-Json })
  if ($apLines.Count -ne 10) { throw "barrage approve_recon reported $($apLines.Count) orders, expected 10" }
  foreach ($l in $apLines) { if ($null -ne $l.error) { throw "barrage approval for $($l.uuid) errored: $($l.error)" } }

  for ($i = 0; $i -lt 10; $i++) {
    $r = $voidResults[$i]
    if ($r.status -ne 200) { throw "barrage void #$i returned HTTP $($r.status): $($r.raw)" }
    $ack = $r.body.data.results[0]
    if ($ack.status -ne 'processed') { throw "barrage void #$i settled '$($ack.status)', expected processed (a void racing an approval must still land): $($ack.result | ConvertTo-Json -Compress)" }
  }

  # ---- terminal-void invariant over EVERY order (all 12) -------------------
  $stateRows = Invoke-Psql -Db $Db -Sql @"
SELECT o.uuid||'|'||o.status
  ||'|'||(SELECT count(*) FROM pos_sale_commissions WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_payments WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_roundup_donations WHERE order_id=o.id)
  ||'|'||(SELECT CASE WHEN min(forwarded_at) IS NULL THEN 'null' ELSE 'set' END FROM pos_roundup_donations WHERE order_id=o.id)
FROM pos_orders o WHERE o.uuid::text LIKE '$tag-0000-4000-8000-a%' ORDER BY o.uuid
"@
  if ($stateRows.Count -ne 12) { throw "post-race state query returned $($stateRows.Count) orders, expected 12" }
  $approveWon = 0; $voidWon = 0; $forwardedCnt = 0
  foreach ($s in $stateRows) {
    $p = $s -split '\|'
    $st = $p[1]; $comm = [int]$p[2]; $pay = $p[3]; $don = $p[4]; $fwd = $p[5]
    if ($st -ne 'void') { throw "order $($p[0]) final status '$st', expected void (every order received a void)" }
    if ($st -eq 'void' -and $comm -gt 0 -and $pay -eq 'success' -and $fwd -eq 'set') {
      throw "TERMINAL-VOID INVARIANT BROKEN on $($p[0]): void order with $comm commission rows + success tender + forwarded donation - FAIL-EXIT-11 CONFIRMED LIVE ON PG"
    }
    if ($comm -ne 0) { throw "order $($p[0]) is VOID yet retains $comm commission rows - FAIL-EXIT-11 phantom commissions CONFIRMED on PG" }
    if ($don -ne 'void') { throw "order $($p[0]) donation status '$don', expected void" }
    if ($pay -eq 'success') { $approveWon++ } elseif ($pay -eq 'pending_reconciliation') { $voidWon++ } else { throw "order $($p[0]) tender in unexpected status '$pay'" }
    if ($fwd -eq 'set') { $forwardedCnt++ }
  }

  # ---- effect deltas (all 12 end void: commissions net 0, no paid residue) -
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 12; orders_paid = 0; payments = 12; local_donations = 12; commission_rows = 0
    events_processed = 12; events_received = 0; events_failed = 0; loyalty_ledger = 0; stock_movements = 0 }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit11_void_vs_approval' -Result 'PASS' `
    -Detail ("FAIL-EXIT-11's SQLite interleaving is REFUTED on PG: deterministic legs correct (void-then-approve: 0 commissions/no flip/no forward; approve-then-void: 3 commissions deleted, donation voided, external charity row kept by design) and the 10-order concurrent barrage held the terminal-void invariant on every order (all void, 0 commission rows). Barrage distribution: approve-won-flip=$approveWon (tender success), void-first=$voidWon (tender still pending), donations forwarded before their void=$forwardedCnt.") `
    -Before $before -After $after -ExpectedDelta $expected
}

