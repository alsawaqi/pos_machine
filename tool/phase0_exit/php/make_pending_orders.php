<?php

declare(strict_types=1);

/**
 * Phase 0 exit gate - pending-reconciliation order factory (TEST-ONLY, disposable).
 *
 * Runs inside the admin_runner OR api_runner container (whichever app is at
 * /var/www/html) against the phase0_exit_<runid> disposable database only.
 *
 * Creates N card orders in the exact P-F7 "force-recorded Soft POS" arrangement
 * the pos_admin PendingReconciliationTest seeds (read-only template:
 * tests/Feature/Admin/PendingReconciliationTest.php - pendingReconSeedOrder /
 * pendingReconSeedDonation), but pinned to the Phase 0 fixture tenant:
 *   company 900100 / branch 900110 ('P0 Main') / device 900111.
 *
 * Per order i (deterministic uuids under the caller-supplied 8-hex tag):
 *   pos_orders            <tag>-0000-4000-8000-a%011d  status=paid, grand 5.000
 *   pos_payments          <tag>-0000-4000-8000-b%011d  card 5.000,
 *                         status=pending_reconciliation, pending_reconciliation=true
 *   pos_roundup_donations <tag>-0000-4000-8000-d%011d  amount 0.200,
 *                         status=<argv3, default success>, forwarded_at NULL,
 *                         commission_profile_id=1 (charity 'P0 Split' mirror)
 *
 * Re-running with the same tag PURGES that tag's residue first (children before
 * parents, including <tag>-% sync-event ledger rows a scenario's void pushes
 * left behind) so every invocation converges on a pristine arrangement.
 *
 * Usage: php make_pending_orders.php <count> <tag8hex> [donation_status]
 * Output: one JSON object {database, tag, count, orders:[{i, order_uuid,
 *         order_id, payment_id, donation_id, donation_uuid}]}.
 */

use Illuminate\Support\Facades\DB;

require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$dbName = (string) DB::connection()->getDatabaseName();
if ($dbName === 'charity_db' || preg_match('/^phase0_exit_[a-z0-9_]+$/', $dbName) !== 1) {
    fwrite(STDERR, "REFUSED: '$dbName' is not a phase0_exit_* disposable database\n");
    exit(1);
}

$count = isset($argv[1]) ? (int) $argv[1] : 0;
$tag = isset($argv[2]) ? strtolower((string) $argv[2]) : '';
$donationStatus = isset($argv[3]) ? (string) $argv[3] : 'success';
if ($count < 1 || $count > 100) {
    fwrite(STDERR, "usage: make_pending_orders.php <count 1..100> <tag8hex> [donation_status]\n");
    exit(1);
}
if (preg_match('/^[0-9a-f]{8}$/', $tag) !== 1) {
    fwrite(STDERR, "REFUSED: tag '$tag' must be exactly 8 lowercase hex chars\n");
    exit(1);
}
if (! in_array($donationStatus, ['success', 'pending'], true)) {
    fwrite(STDERR, "REFUSED: donation_status must be success|pending\n");
    exit(1);
}

$uuidLike = $tag.'-0000-4000-8000-%';

// ---- purge this tag's residue (children first; FK-safe) --------------------
$orderIds = DB::table('pos_orders')->where('uuid', 'like', $uuidLike)->pluck('id')->all();
if ($orderIds !== []) {
    DB::table('pos_sale_commissions')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_roundup_donations')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_payments')->whereIn('order_id', $orderIds)->delete();
    $itemIds = DB::table('pos_order_items')->whereIn('order_id', $orderIds)->pluck('id')->all();
    if ($itemIds !== []) {
        DB::table('pos_order_item_addons')->whereIn('order_item_id', $itemIds)->delete();
    }
    DB::table('pos_order_items')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_order_discounts')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_order_comps')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_order_tables')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_loyalty_transactions')->whereIn('order_id', $orderIds)->delete();
    DB::table('pos_orders')->whereIn('id', $orderIds)->delete();
}
// Ledger rows a prior invocation's scenario pushes (e.g. order.void) parked
// under this tag - uuid column needs the ::text cast for LIKE on Postgres.
DB::table('pos_sync_events')->whereRaw('client_event_id::text LIKE ?', [$uuidLike])->delete();

// ---- create the N pending-reconciliation arrangements ----------------------
$now = now();
$rows = [];
for ($i = 1; $i <= $count; $i++) {
    $orderUuid = sprintf('%s-0000-4000-8000-a%011d', $tag, $i);
    $payUuid = sprintf('%s-0000-4000-8000-b%011d', $tag, $i);
    $donUuid = sprintf('%s-0000-4000-8000-d%011d', $tag, $i);

    $orderId = (int) DB::table('pos_orders')->insertGetId([
        'uuid' => $orderUuid,
        'company_id' => 900100, 'branch_id' => 900110, 'device_id' => 900111,
        'order_type' => 'quick', 'status' => 'paid', 'source' => 'main_pos',
        'subtotal' => '5.000', 'discount_total' => 0, 'tax_total' => 0, 'grand_total' => '5.000',
        'opened_at' => $now, 'closed_at' => $now, 'created_at' => $now, 'updated_at' => $now,
    ]);

    $paymentId = (int) DB::table('pos_payments')->insertGetId([
        'uuid' => $payUuid, 'order_id' => $orderId, 'method' => 'card',
        'amount' => '5.000', 'status' => 'pending_reconciliation', 'pending_reconciliation' => true,
        'softpos_reference' => 'P0-NFC-'.$tag.'-'.$i, 'softpos_auth_code' => 'A77',
        'bank_response' => json_encode(['status' => 'timeout']),
        'device_id' => 900111, 'terminal_id' => 'P0-TERM-900111',
        'captured_at' => $now, 'created_at' => $now, 'updated_at' => $now,
    ]);

    $donationId = (int) DB::table('pos_roundup_donations')->insertGetId([
        'uuid' => $donUuid,
        'company_id' => 900100, 'branch_id' => 900110,
        'device_id' => 900111, 'order_id' => $orderId, 'payment_id' => $paymentId,
        'terminal_id' => 'P0-TERM-900111',
        'amount' => '0.200', 'bank_response' => json_encode(['status' => 'timeout']),
        'bank_id' => null,
        'commission_profile_id' => 1,
        'organization_id' => null,
        'branch_name' => 'P0 Main',
        'country_id' => null, 'region_id' => null, 'district_id' => null, 'city_id' => null,
        'latitude' => null, 'longitude' => null,
        'status' => $donationStatus, 'source' => 'pos_roundup',
        'occurred_at' => $now, 'forwarded_at' => null,
        'created_at' => $now, 'updated_at' => $now,
    ]);

    $rows[] = [
        'i' => $i,
        'order_uuid' => $orderUuid,
        'order_id' => $orderId,
        'payment_id' => $paymentId,
        'donation_id' => $donationId,
        'donation_uuid' => $donUuid,
    ];
}

echo json_encode([
    'database' => $dbName,
    'tag' => $tag,
    'count' => $count,
    'donation_status' => $donationStatus,
    'orders' => $rows,
], JSON_UNESCAPED_SLASHES), "\n";
