<?php

declare(strict_types=1);

/**
 * Phase 0 exit gate — POS fixture seeder (TEST-ONLY, disposable stack).
 *
 * Runs inside the api_runner container (pos_api app root at /var/www/html)
 * against the phase0_exit_<runid> disposable database. Idempotently
 * force-creates the fixture rows defined in tool/phase0_exit/fixtures.json:
 * re-running always converges on the exact contract values (including
 * FORCE-RESETTING the loyalty account balance to 30 points / 0 stamps).
 *
 * Only DB::table updateOrInsert is used — the three pos_api factories are
 * deliberately not relied on. Refuses to run against any database whose name
 * does not match ^phase0_exit_[a-z0-9_]+$ (charity_db is thereby impossible).
 */

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$dbName = (string) DB::connection()->getDatabaseName();
if ($dbName === 'charity_db' || preg_match('/^phase0_exit_[a-z0-9_]+$/', $dbName) !== 1) {
    fwrite(STDERR, "REFUSED: '$dbName' is not a phase0_exit_* disposable database\n");
    exit(1);
}

$now = now();
$past = now()->subDays(30);

/** Deterministic fixture uuid for a fixture id (hex-only, valid v4 shape). */
function p0uuid(int $n): string
{
    return sprintf('f0000000-0000-4000-8000-%012d', $n);
}

function upsert(string $table, array $key, array $row): void
{
    DB::table($table)->updateOrInsert($key, $row);
}

// ---- companies -------------------------------------------------------------
upsert('pos_companies', ['id' => 900100], [
    'uuid' => p0uuid(900100), 'name' => 'P0 Company A', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
upsert('pos_companies', ['id' => 900200], [
    'uuid' => p0uuid(900200), 'name' => 'P0 Company B', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);

// ---- branches --------------------------------------------------------------
upsert('pos_branches', ['id' => 900110], [
    'uuid' => p0uuid(900110), 'company_id' => 900100, 'name' => 'P0 Main', 'code' => 'P0MAIN',
    'latitude' => null, 'longitude' => null, 'geofence_radius_m' => 500,
    'status' => 'active', 'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
upsert('pos_branches', ['id' => 900115], [
    'uuid' => p0uuid(900115), 'company_id' => 900100, 'name' => 'P0 Fenced', 'code' => 'P0FENCE',
    'latitude' => 23.5880000, 'longitude' => 58.3829000, 'geofence_radius_m' => 500,
    'status' => 'active', 'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
upsert('pos_branches', ['id' => 900210], [
    'uuid' => p0uuid(900210), 'company_id' => 900200, 'name' => 'P0 B Main', 'code' => 'P0BMAIN',
    'latitude' => null, 'longitude' => null, 'geofence_radius_m' => 500,
    'status' => 'active', 'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);

// ---- charity commission profile STUB (pos-side mirror) ---------------------
// pos_devices.commission_profile_id FKs the local `commission_profiles` stub
// table in the disposable DB; row id=1 mirrors the charity DB 'P0 Split'
// profile so device rows can carry the id the round-up forward payload sends.
upsert('commission_profiles', ['id' => 1], [
    'name' => 'P0 Split', 'description' => 'phase0 exit disposable stub', 'is_active' => true,
    'created_at' => $now, 'updated_at' => $now,
]);

// ---- devices (status active, PLAINTEXT device_token) -----------------------
$devices = [
    [900111, 900100, 900110, 'fixed_pos', 'phase0-mdev-machine-a1', 'P0 Machine A1'],
    [900112, 900100, 900110, 'handheld', 'phase0-mdev-handheld-a1', 'P0 Handheld A1'],
    [900113, 900100, 900110, 'fixed_pos', 'phase0-mdev-spare-a1', 'P0 Spare A1'],
    [900116, 900100, 900115, 'fixed_pos', 'phase0-mdev-machine-fenced', 'P0 Machine Fenced'],
    [900211, 900200, 900210, 'fixed_pos', 'phase0-mdev-machine-b1', 'P0 Machine B1'],
];
foreach ($devices as [$id, $companyId, $branchId, $type, $token, $name]) {
    upsert('pos_devices', ['id' => $id], [
        'uuid' => p0uuid($id),
        'serial_number' => 'P0-SN-'.$id,
        'kiosk_id' => 'P0-KIOSK-'.$id,
        'terminal_id' => 'P0-TERM-'.$id,
        'commission_profile_id' => 1,
        'bank_id' => null,
        'name' => $name,
        'device_type' => $type,
        'company_id' => $companyId,
        'branch_id' => $branchId,
        'status' => 'active',
        // Well in the past so the stranded-event sweeper's attribution check
        // (assigned_at < server_received_at) passes for backdated seeds.
        'assigned_at' => $past,
        'device_token' => $token,
        'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
    ]);
}

// ---- catalog category (the device POS grid renders by category; uncategorized
// products with zero categories appear nowhere — T7 session finding) ----------
upsert('pos_product_categories', ['id' => 900145], [
    'uuid' => p0uuid(900145), 'company_id' => 900100, 'name' => 'P0 Menu',
    'display_order' => 0, 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
DB::table('pos_products')->whereIn('id', [900140, 900141])->update(['category_id' => 900145]);

// ---- physical smoke devices (T7) -------------------------------------------
// Unpaired rows + one-time activation codes for the REAL Sunmi T3 and handheld.
// The operator enters the plaintext code on the device; ActivateDeviceAction
// then mints the real device_token. Re-seeding RE-ARMS the codes (used_at
// cleared, expiry pushed out) so a smoke session can be repeated. terminal_id
// is a placeholder — update to the bank TEST terminal id at session time.
$physical = [
    [900117, 'fixed_pos', 'P0 Sunmi T3 physical', 'PHASE0-ACT-SUNMI-2026'],
    [900118, 'handheld', 'P0 Handheld physical', 'PHASE0-ACT-HH-2026'],
];
foreach ($physical as [$id, $type, $name, $code]) {
    upsert('pos_devices', ['id' => $id], [
        'uuid' => p0uuid($id),
        'serial_number' => 'P0-SN-'.$id,
        'kiosk_id' => 'P0-KIOSK-'.$id,
        'terminal_id' => 'PHASE0-TEST-TERM-'.$id,
        'terminal_pin' => '1321',
        'commission_profile_id' => 1,
        'bank_id' => null,
        'name' => $name,
        'device_type' => $type,
        'company_id' => 900100,
        'branch_id' => 900110,
        'status' => 'active',
        'assigned_at' => $past,
        'device_token' => null,
        'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
    ]);
    upsert('pos_device_activation_tokens', ['device_id' => $id], [
        'token_hash' => hash('sha256', $code),
        'created_by_user_id' => null,
        'expires_at' => now()->addDays(7),
        'used_at' => null,
        'revoked_at' => null,
        'created_at' => $now, 'updated_at' => $now,
    ]);
}

// ---- staff -----------------------------------------------------------------
upsert('pos_staff', ['id' => 900120], [
    'uuid' => p0uuid(900120), 'company_id' => 900100, 'branch_id' => 900110,
    'name' => 'P0 Cashier', 'pin_hash' => Hash::make('123456'),
    'position' => 'cashier', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
upsert('pos_staff', ['id' => 900121], [
    'uuid' => p0uuid(900121), 'company_id' => 900100, 'branch_id' => 900110,
    'name' => 'P0 Manager', 'pin_hash' => Hash::make('654321'),
    'position' => 'manager', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);

// ---- customer --------------------------------------------------------------
upsert('pos_customers', ['id' => 900130], [
    'uuid' => p0uuid(900130), 'company_id' => 900100,
    'name' => 'P0 Customer', 'phone' => '+968 90000130',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);

// ---- products --------------------------------------------------------------
upsert('pos_products', ['id' => 900140], [
    'uuid' => p0uuid(900140), 'company_id' => 900100, 'name' => 'P0 Untracked',
    'base_price' => '2.500', 'stock_mode' => 'untracked', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
upsert('pos_products', ['id' => 900141], [
    'uuid' => p0uuid(900141), 'company_id' => 900100, 'name' => 'P0 Tracked',
    'base_price' => '2.500', 'stock_mode' => 'unit', 'status' => 'active',
    'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);

// Unit stock: central pool row + branch shelf row, both 100.000.
upsert('pos_product_stock', ['company_id' => 900100, 'product_id' => 900141], [
    'quantity' => '100.000', 'last_movement_at' => $now,
    'created_at' => $now, 'updated_at' => $now,
]);
upsert('pos_branch_product', ['branch_id' => 900110, 'product_id' => 900141], [
    'stock_qty' => '100.000', 'created_at' => $now, 'updated_at' => $now,
]);

// ---- loyalty (points redemption rule + account holding 30 pts) -------------
upsert('pos_loyalty_rules', ['id' => 900150], [
    'uuid' => p0uuid(900150), 'company_id' => 900100, 'name' => 'P0 Points',
    'type' => 'spend_based',
    'config_json' => json_encode([
        'points_per_omr' => 1, 'redemption_points' => 100,
        'redemption_value' => 1, 'min_redemption_points' => 1,
    ]),
    'status' => 'active', 'created_at' => $now, 'updated_at' => $now, 'deleted_at' => null,
]);
// FORCE-RESET on every seed: the contract balance is exactly 30 / 0.
upsert('pos_loyalty_accounts', ['customer_id' => 900130, 'loyalty_rule_id' => 900150], [
    'uuid' => p0uuid(900151), 'company_id' => 900100,
    'point_balance' => 30, 'stamp_count' => 0, 'last_activity_at' => null,
    'created_at' => $now, 'updated_at' => $now,
]);

// ---- merchant commission profile (platform 2% + bank 3% card-only) ---------
upsert('pos_commission_profiles', ['id' => 900160], [
    'uuid' => p0uuid(900160), 'company_id' => 900100,
    'is_active' => true, 'merchant_percent' => '95.00',
    'created_at' => $now, 'updated_at' => $now,
]);
upsert('pos_commission_shares', ['id' => 900161], [
    'commission_profile_id' => 900160, 'party_type' => 'platform', 'label' => 'Platform',
    'percent' => '2.00', 'applies_to' => 'all', 'sort_order' => 0,
    'created_at' => $now, 'updated_at' => $now,
]);
upsert('pos_commission_shares', ['id' => 900162], [
    'commission_profile_id' => 900160, 'party_type' => 'bank', 'label' => 'Bank',
    'percent' => '3.00', 'applies_to' => 'card', 'sort_order' => 1,
    'created_at' => $now, 'updated_at' => $now,
]);

// ---- summary ---------------------------------------------------------------
$summary = [
    'seeder' => 'seed_fixtures.php',
    'database' => $dbName,
    'companies' => DB::table('pos_companies')->whereIn('id', [900100, 900200])->count(),
    'branches' => DB::table('pos_branches')->whereIn('id', [900110, 900115, 900210])->count(),
    'devices' => DB::table('pos_devices')->whereIn('id', [900111, 900112, 900113, 900116, 900211])->count(),
    'staff' => DB::table('pos_staff')->whereIn('id', [900120, 900121])->count(),
    'customers' => DB::table('pos_customers')->where('id', 900130)->count(),
    'products' => DB::table('pos_products')->whereIn('id', [900140, 900141])->count(),
    'central_stock_qty' => (string) DB::table('pos_product_stock')->where('company_id', 900100)->where('product_id', 900141)->value('quantity'),
    'branch_stock_qty' => (string) DB::table('pos_branch_product')->where('branch_id', 900110)->where('product_id', 900141)->value('stock_qty'),
    'loyalty_rules' => DB::table('pos_loyalty_rules')->where('id', 900150)->count(),
    'loyalty_point_balance' => (int) DB::table('pos_loyalty_accounts')->where('customer_id', 900130)->where('loyalty_rule_id', 900150)->value('point_balance'),
    'commission_profiles' => DB::table('pos_commission_profiles')->where('id', 900160)->count(),
    'commission_shares' => DB::table('pos_commission_shares')->whereIn('id', [900161, 900162])->count(),
    'charity_stub_profiles' => DB::table('commission_profiles')->where('id', 1)->count(),
];

echo json_encode($summary, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";

$expected = ['companies' => 2, 'branches' => 3, 'devices' => 5, 'staff' => 2, 'customers' => 1,
    'products' => 2, 'loyalty_rules' => 1, 'loyalty_point_balance' => 30,
    'commission_profiles' => 1, 'commission_shares' => 2, 'charity_stub_profiles' => 1];
foreach ($expected as $k => $v) {
    if ($summary[$k] !== $v) {
        fwrite(STDERR, "SEED VERIFY FAILED: $k expected $v got {$summary[$k]}\n");
        exit(1);
    }
}
echo "SEED OK\n";
