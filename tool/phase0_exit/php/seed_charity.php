<?php

declare(strict_types=1);

/**
 * Phase 0 exit gate — CHARITY receiver fixture seeder (TEST-ONLY, disposable).
 *
 * Runs inside the charity_runner container (charity app root at /var/www/html)
 * against the phase0_exit_<runid>_charity disposable database. Seeds the
 * commission profile the POS round-up forward resolves:
 *   commission_profiles id 1 'P0 Split' (active)
 *   commission_profile_shares: 70% 'Org A' + 30% 'Org B' (organization_id NULL)
 *
 * Refuses to run against any database not named phase0_exit_* — the live
 * charity_db is structurally unreachable from this seeder.
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

$now = now();

DB::table('commission_profiles')->updateOrInsert(['id' => 1], [
    'name' => 'P0 Split',
    'description' => 'phase0 exit disposable split profile',
    'is_active' => true,
    'created_at' => $now, 'updated_at' => $now,
]);

DB::table('commission_profile_shares')->updateOrInsert(['id' => 1], [
    'commission_profile_id' => 1, 'label' => 'Org A', 'percentage' => '70.000',
    'organization_id' => null, 'sort_order' => 0,
    'created_at' => $now, 'updated_at' => $now,
]);
DB::table('commission_profile_shares')->updateOrInsert(['id' => 2], [
    'commission_profile_id' => 1, 'label' => 'Org B', 'percentage' => '30.000',
    'organization_id' => null, 'sort_order' => 1,
    'created_at' => $now, 'updated_at' => $now,
]);

$summary = [
    'seeder' => 'seed_charity.php',
    'database' => $dbName,
    'commission_profiles' => DB::table('commission_profiles')->where('id', 1)->where('is_active', true)->count(),
    'commission_profile_shares' => DB::table('commission_profile_shares')->whereIn('id', [1, 2])->count(),
    'share_percent_sum' => (string) DB::table('commission_profile_shares')->where('commission_profile_id', 1)->sum('percentage'),
];

echo json_encode($summary, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";

if ($summary['commission_profiles'] !== 1 || $summary['commission_profile_shares'] !== 2 || (float) $summary['share_percent_sum'] !== 100.0) {
    fwrite(STDERR, "SEED VERIFY FAILED: charity split profile incomplete\n");
    exit(1);
}
echo "SEED OK\n";
