# Phase 0 exit gate - EXIT-12 (full pos_admin -> charity receiver loop, test-only).
#
# (a) OUTAGE: with the charity receiver container REMOVED (verified absent),
#     approving a pending-reconciliation order carrying a round-up donation
#     settles LOCALLY (tender success + 3 commission rows) while the forward's
#     ConnectionException is swallowed: donation status success, forwarded_at
#     NULL, zero receiver rows. The receiver is restarted in a finally block
#     so a mid-leg failure can never strand later scenarios.
# (b) RETRY: after the receiver is back (/up answers) and the donation is
#     backdated past the 10-minute grace, admin_runner
#     `php artisan donations:retry-roundup-forwarding` forwards it exactly
#     once: forwarded_at set, EXACTLY one charity_transactions row
#     (idempotency_key pos_roundup:<donation uuid>) + its 2 profile shares
#     (70/30 of 0.200). A second sweep run changes nothing.
# (c) 23505 RACE: two identical barrier-released POSTs with a FRESH
#     pos_reference hit /api/donations-pos-roundup directly. Exactly one
#     transactions row + one 2-row share set must exist afterwards in every
#     attempt; a genuine race answers one 201 + one idempotent 2xx ('POS
#     round-up already recorded (idempotent).'); if both serialized through
#     the pre-check replay path (two 201s, one row) the barrier retries up to
#     5 times and the outcome that occurred is reported either way.

function Invoke-Scenario {
  param($Dc, $Db, $Art, $CharityDb)

  $tag = 'c1200000'
  $orderUuid = ('{0}-0000-4000-8000-a{1:d11}' -f $tag, 1)
  $donUuid = ('{0}-0000-4000-8000-d{1:d11}' -f $tag, 1)
  $donKey = "pos_roundup:$donUuid"

  # Deterministic per invocation: purge prior-run receiver residue for every
  # stable reference under this tag (shares first - FK).
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

  # One pending-reconciliation arrangement (order + pending card tender +
  # success/unforwarded donation riding it).
  $mkOut = Invoke-AdminRunner -Dc $Dc -Cmd 'php /phase0tool/make_pending_orders.php 1 c1200000'
  $mkJson = @($mkOut | Where-Object { $_ -like '{*' })
  if ($mkJson.Count -lt 1) { throw "make_pending_orders.php produced no JSON: $($mkOut -join ' / ')" }

  # ---- (a) approve during a receiver outage --------------------------------
  try {
    wsl -e bash -lc 'docker rm -f phase0-exit-charity >/dev/null 2>&1; true' | Out-Null
    $gone = (wsl -e bash -lc "docker ps -a --filter name=phase0-exit-charity --format '{{.Names}}'") -join ''
    if ($gone.Trim() -ne '') { throw "charity receiver container still present after removal: '$gone'" }

    $apOut = Invoke-AdminRunner -Dc $Dc -Cmd "php /phase0tool/approve_recon.php $orderUuid" -AllowFail
    $ap = @($apOut | Where-Object { $_ -like '{*' })
    if ($ap.Count -ne 1) { throw "approve_recon produced $($ap.Count) JSON lines, expected 1: $($apOut -join ' / ')" }
    $ap = $ap[0] | ConvertFrom-Json
    if ($null -ne $ap.error) { throw "approve during outage errored (the ConnectionException must be swallowed): $($ap.error)" }
    if ([int]$ap.flipped -ne 1) { throw "approve during outage flipped $($ap.flipped) tenders, expected 1 (local settlement must not depend on charity availability)" }
    if ([int]$ap.commissions -ne 1) { throw "approve during outage recorded commissions for $($ap.commissions) orders, expected 1" }
    if ([int]$ap.forwarded -ne 0) { throw "approve during outage claims $($ap.forwarded) donations forwarded while the receiver was ABSENT" }

    $row = ((Invoke-Psql -Db $Db -Sql @"
SELECT (SELECT min(status) FROM pos_payments WHERE order_id=o.id)
  ||'|'||(SELECT count(*) FROM pos_sale_commissions WHERE order_id=o.id)
  ||'|'||(SELECT min(status) FROM pos_roundup_donations WHERE order_id=o.id)
  ||'|'||(SELECT CASE WHEN min(forwarded_at) IS NULL THEN 'null' ELSE 'set' END FROM pos_roundup_donations WHERE order_id=o.id)
FROM pos_orders o WHERE o.uuid='$orderUuid'
"@)[0]) -split '\|'
    if ($row[0] -ne 'success') { throw "outage-leg tender status '$($row[0])', expected success" }
    if ([int]$row[1] -ne 3) { throw "outage-leg commission rows = $($row[1]), expected 3" }
    if ($row[2] -ne 'success') { throw "outage-leg donation status '$($row[2])', expected success (durably settled before the failed forward)" }
    if ($row[3] -ne 'null') { throw "outage-leg donation forwarded_at is SET despite the receiver being absent" }
  } finally {
    # ALWAYS bring the receiver back (later scenarios + leg b depend on it).
    # 2>&1 INSIDE bash: compose writes progress to stderr, which a redirecting
    # caller would otherwise wrap into a terminating NativeCommandError.
    wsl -e bash -lc "$Dc up -d charity_server 2>&1" | Out-Null
  }

  $upOk = $false
  foreach ($i in 1..30) {
    try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:58001/up' -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -eq 200) { $upOk = $true; break } } catch { Start-Sleep -Milliseconds 500 }
  }
  if (-not $upOk) { throw 'charity receiver failed to come back up on 127.0.0.1:58001 after the outage leg' }
  $c = [int]((Invoke-Psql -Db $CharityDb -Sql "SELECT count(*) FROM charity_transactions WHERE idempotency_key='$donKey'")[0])
  if ($c -ne 0) { throw "receiver already holds $c transaction(s) for $donKey before the retry sweep - outage leg leaked a forward" }

  # ---- (b) hourly retry sweep forwards exactly once ------------------------
  Invoke-Psql -Db $Db -Sql "UPDATE pos_roundup_donations SET created_at = now() - interval '11 minutes' WHERE uuid='$donUuid'" | Out-Null

  $sw1 = (Invoke-AdminRunner -Dc $Dc -Cmd 'php artisan donations:retry-roundup-forwarding') -join "`n"
  $sw1 | Out-File -Encoding utf8 (Join-Path $Art 'exit12_sweep1.txt')
  $m = [regex]::Match($sw1, 'attempted=(\d+) forwarded=(\d+)')
  if (-not $m.Success) { throw "retry sweep #1 printed no attempted/forwarded summary: $sw1" }
  if ([int]$m.Groups[1].Value -ne 1 -or [int]$m.Groups[2].Value -ne 1) { throw "retry sweep #1 reported attempted=$($m.Groups[1].Value) forwarded=$($m.Groups[2].Value), expected 1/1" }

  $fwd = ((Invoke-Psql -Db $Db -Sql "SELECT status||'|'||CASE WHEN forwarded_at IS NULL THEN 'null' ELSE 'set' END FROM pos_roundup_donations WHERE uuid='$donUuid'")[0]) -split '\|'
  if ($fwd[0] -ne 'success' -or $fwd[1] -ne 'set') { throw "post-sweep donation is status=$($fwd[0]) forwarded_at=$($fwd[1]), expected success/set" }

  $rx = ((Invoke-Psql -Db $CharityDb -Sql @"
SELECT (SELECT count(*) FROM charity_transactions WHERE idempotency_key='$donKey')
  ||'|'||(SELECT count(*) FROM charity_transaction_shares WHERE charity_transaction_id IN (SELECT id FROM charity_transactions WHERE idempotency_key='$donKey'))
"@)[0]) -split '\|'
  if ([int]$rx[0] -ne 1) { throw "receiver holds $($rx[0]) transactions for $donKey after the sweep, expected exactly 1" }
  if ([int]$rx[1] -ne 2) { throw "receiver holds $($rx[1]) share rows for $donKey, expected exactly 2 (70/30 split)" }

  $sw2 = (Invoke-AdminRunner -Dc $Dc -Cmd 'php artisan donations:retry-roundup-forwarding') -join "`n"
  $sw2 | Out-File -Encoding utf8 (Join-Path $Art 'exit12_sweep2.txt')
  $rx2 = ((Invoke-Psql -Db $CharityDb -Sql @"
SELECT (SELECT count(*) FROM charity_transactions WHERE idempotency_key='$donKey')
  ||'|'||(SELECT count(*) FROM charity_transaction_shares WHERE charity_transaction_id IN (SELECT id FROM charity_transactions WHERE idempotency_key='$donKey'))
"@)[0]) -split '\|'
  if ($rx2[0] -ne '1' -or $rx2[1] -ne '2') { throw "second sweep changed the receiver rows for ${donKey}: tx=$($rx2[0]) shares=$($rx2[1]), expected still 1/2" }

  # ---- (c) 23505 race straight into the receiver ---------------------------
  # Invoke-ParallelPosts targets $script:Phase0Api; swap it to the receiver
  # for the volley and ALWAYS restore.
  $raceOutcome = ''; $attempts = 0; $savedApi = $script:Phase0Api
  try {
    $script:Phase0Api = 'http://127.0.0.1:58001'
    for ($attempt = 1; $attempt -le 5; $attempt++) {
      $attempts = $attempt
      $ref = ('{0}-0000-4000-8000-c{1:d11}' -f $tag, $attempt)
      $refKey = "pos_roundup:$ref"
      $body = @{
        pos_device_id = 900111; pos_branch_id = 900110; pos_branch_name = 'P0 Main'
        commission_profile_id = 1; amount = '0.300'; status = 'success'
        terminal_id = 'P0-TERM-900111'; pos_reference = $ref
      }
      $pair = Invoke-ParallelPosts -Requests @(
        @{ Path = '/api/donations-pos-roundup'; Body = $body; Token = 'phase0-dummy-token' },
        @{ Path = '/api/donations-pos-roundup'; Body = $body; Token = 'phase0-dummy-token' }
      )

      $statuses = @($pair | ForEach-Object { [int]$_.status }) | Sort-Object
      foreach ($p in $pair) {
        if ($p.status -lt 200 -or $p.status -ge 300) { throw "race attempt ${attempt}: non-2xx response $($p.status): $($p.raw)" }
      }
      # DB-uniqueness must hold on EVERY attempt, race or not.
      $rr = ((Invoke-Psql -Db $CharityDb -Sql @"
SELECT (SELECT count(*) FROM charity_transactions WHERE idempotency_key='$refKey')
  ||'|'||(SELECT count(*) FROM charity_transaction_shares WHERE charity_transaction_id IN (SELECT id FROM charity_transactions WHERE idempotency_key='$refKey'))
"@)[0]) -split '\|'
      if ([int]$rr[0] -ne 1) { throw "race attempt ${attempt}: receiver holds $($rr[0]) transactions for $refKey, expected exactly 1 (unique index breached or lost)" }
      if ([int]$rr[1] -ne 2) { throw "race attempt ${attempt}: receiver holds $($rr[1]) share rows for $refKey, expected exactly one 2-row set" }

      $idem = @($pair | Where-Object { $_.raw -like '*already recorded (idempotent)*' })
      if ($idem.Count -ge 1) {
        if (($statuses -join ',') -ne '200,201') { throw "race attempt ${attempt}: idempotent loser present but statuses were [$($statuses -join ',')], expected one 201 + one 200" }
        $raceOutcome = "genuine 23505 race landed on attempt $attempt (one 201 winner + one 200 'already recorded (idempotent)' loser)"
        break
      }
      if (($statuses -join ',') -ne '201,201') { throw "race attempt ${attempt}: no idempotent marker yet statuses were [$($statuses -join ',')], expected two 201s on the serialized path" }
      $raceOutcome = "both requests serialized through the pre-check replay path (two 201s, single row) on all $attempt attempt(s) - no 23505 loser observed"
    }
  } finally {
    $script:Phase0Api = $savedApi
  }

  # ---- effect deltas -------------------------------------------------------
  $after = Get-EffectCounts -Db $Db -CharityDb $CharityDb
  $expected = @{ orders = 1; orders_paid = 1; payments = 1; commission_rows = 3; local_donations = 1
    events_processed = 0; events_received = 0; events_failed = 0; loyalty_ledger = 0; stock_movements = 0
    receiver_transactions = (1 + $attempts); receiver_shares = (2 + (2 * $attempts)) }
  Assert-Delta -Expected $expected -Before $before -After $after

  return New-ScenarioResult -Id 'exit12_charity_loop' -Result 'PASS' `
    -Detail ("outage leg settled locally (tender success, 3 commissions, donation success/unforwarded, receiver verified absent + zero rows); retry sweep forwarded exactly once (attempted=1 forwarded=1, 1 tx '$donKey' + 2 shares, second sweep a no-op); 23505 leg: $raceOutcome; DB uniqueness (1 tx + one 2-row share set per reference) held on every attempt.") `
    -Before $before -After $after -ExpectedDelta $expected
}

