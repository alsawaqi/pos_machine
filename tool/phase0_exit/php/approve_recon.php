<?php

declare(strict_types=1);

/**
 * Phase 0 exit gate - reconciliation approval driver (TEST-ONLY, disposable).
 *
 * Runs inside the admin_runner container (pos_admin app at /var/www/html)
 * against the phase0_exit_<runid> disposable database only. Seeds NOTHING
 * except the minimal platform actor row, then drives the SAME approval
 * pathway pos_admin's PendingReconciliationTest exercises: it invokes
 * ApprovePendingReconciliationAction directly (bypassing HTTP session auth -
 * the race under test is DB-level, not HTTP-level), one handle() call per
 * order so the per-order transactions interleave naturally with concurrent
 * device order.void pushes on the shared PG.
 *
 * Actor: pos_users id 900190 (user_type platform_admin) - the action itself
 * performs no permission check (that lives in the HTTP layer); the row only
 * has to exist for reconciled_by_admin_id / audit actor attribution.
 *
 * Barrier (optional): when env PHASE0_BARRIER=<prefix> is set, the caller has
 * created two bare tables <prefix>_ready and <prefix>_go in the disposable DB.
 * After resolving every order this script INSERTs a row into <prefix>_ready,
 * then polls <prefix>_go (50ms, 30s bound) before approving - so the harness
 * can release the racing void volley and this approval sweep together.
 *
 * Usage: php approve_recon.php <order-uuid> [<order-uuid> ...]
 * Output: one JSON line per order uuid, in argv order:
 *   {"uuid":..., "flipped":N, "error":null|msg, "approved":N,
 *    "commissions":N, "forwarded":N}
 */

use App\Actions\Admin\Reconciliation\ApprovePendingReconciliationAction;
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

$uuids = array_values(array_filter(array_slice($argv, 1), static function ($a): bool {
    return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', (string) $a) === 1;
}));
if ($uuids === []) {
    fwrite(STDERR, "usage: approve_recon.php <order-uuid> [...]\n");
    exit(1);
}

// ---- minimal platform actor (fixture id 900190) ----------------------------
$userTable = (new App\Models\User)->getTable();
DB::table($userTable)->updateOrInsert(['id' => 900190], [
    'name' => 'P0 Exit Admin',
    'email' => 'phase0-exit-admin@example.test',
    'password' => Hash::make('phase0-exit-local'),
    'user_type' => 'platform_admin',
    'status' => 'active',
    'created_at' => now(), 'updated_at' => now(),
]);
$actor = App\Models\User::query()->find(900190);

// ---- resolve ids up front (the race is over APPROVAL, not lookup) ----------
$idsByUuid = DB::table('pos_orders')->whereIn('uuid', $uuids)->pluck('id', 'uuid');

// ---- optional ready/go barrier over disposable-DB tables -------------------
$barrier = (string) (getenv('PHASE0_BARRIER') ?: '');
if ($barrier !== '') {
    if (preg_match('/^[a-z0-9_]{1,40}$/', $barrier) !== 1) {
        fwrite(STDERR, "REFUSED: invalid PHASE0_BARRIER prefix\n");
        exit(1);
    }
    DB::statement("INSERT INTO {$barrier}_ready VALUES (1)");
    $released = false;
    for ($i = 0; $i < 600; $i++) { // 600 x 50ms = 30s bound
        $go = DB::selectOne("SELECT count(*) AS n FROM {$barrier}_go");
        if ((int) $go->n > 0) {
            $released = true;
            break;
        }
        usleep(50_000);
    }
    if (! $released) {
        foreach ($uuids as $uuid) {
            echo json_encode(['uuid' => $uuid, 'flipped' => 0, 'error' => 'barrier go signal never arrived (30s)']), "\n";
        }
        exit(1);
    }
}

// ---- drive the real approval action, one call per order --------------------
$action = $app->make(ApprovePendingReconciliationAction::class);
$hadError = false;
foreach ($uuids as $uuid) {
    $orderId = $idsByUuid[$uuid] ?? null;
    if ($orderId === null) {
        $hadError = true;
        echo json_encode(['uuid' => $uuid, 'flipped' => 0, 'error' => 'order not found']), "\n";
        continue;
    }
    try {
        $res = $action->handle([(int) $orderId], $actor);
        echo json_encode([
            'uuid' => $uuid,
            'flipped' => (int) $res['payments_reconciled'],
            'error' => null,
            'approved' => (int) $res['orders_approved'],
            'commissions' => (int) $res['effects']['commissions_recorded'],
            'forwarded' => (int) $res['effects']['donations_forwarded'],
        ]), "\n";
    } catch (Throwable $e) {
        $hadError = true;
        echo json_encode(['uuid' => $uuid, 'flipped' => 0, 'error' => $e->getMessage()]), "\n";
    }
}

exit($hadError ? 2 : 0);
