import 'package:pos_machine/tenancy/business_identity.dart';
import '../tenancy/tenant_sqlite.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'recovery_admission.dart';

/// Local archive, not a fabricated server release/payment acknowledgement.
class CheckoutRecovery {
  CheckoutRecovery(this.db, this.currentScope);
  final Database db;
  final String Function() currentScope;

  Future<List<Map<String, Object?>>> rows() async {
    final rows = await db.query(
      'qr_checkout_attempts',
      columns: ['id', 'scope', 'state', 'payload'],
    );
    return rows.where((row) {
      final attempt = recoveryCheckoutAttempt(row);
      return !attempt.terminal || checkoutMoneyUncertain(attempt);
    }).toList();
  }

  Future<bool> retire(
    Map<String, Object?> original, {
    required int staffId,
    required Future<bool> Function() authorize,
  }) async {
    final scope = currentScope();
    if (staffId < 1 || !foreignReleaseCanRetire(original, scope)) return false;
    if (!await authorize()) return false;
    if (currentScope() != scope) throw StateError('Device scope changed');
    return db.transaction((txn) async {
      final found = await txn.query(
        'qr_checkout_attempts',
        where: 'id = ?',
        whereArgs: [original['id']],
      );
      if (currentScope() != scope ||
          found.length != 1 ||
          const JsonEncoder().convert(found.single) !=
              const JsonEncoder().convert(original) ||
          !foreignReleaseCanRetire(found.single, scope)) {
        throw StateError('Saved checkout changed; review again');
      }
      await txn.execute(
        '''CREATE TABLE IF NOT EXISTS qr_checkout_recovery_archive (
        attempt_id TEXT PRIMARY KEY, original_row TEXT NOT NULL,
        retired_at TEXT NOT NULL, current_scope TEXT NOT NULL,
        requested_by_staff_id INTEGER NOT NULL, authority TEXT NOT NULL,
        reason TEXT NOT NULL)''',
      );
      if (BusinessBoundary.initialized)
        await ensureBusinessTable(txn, 'qr_checkout_recovery_archive');
      await txn.insert('qr_checkout_recovery_archive', {
        'attempt_id': original['id'],
        'original_row': jsonEncode(original),
        'retired_at': DateTime.now().toUtc().toIso8601String(),
        'current_scope': scope,
        'requested_by_staff_id': staffId,
        'authority': 'existing_manager_approval',
        'reason':
            'Owner confirmed retired foreign server; no tender evidence; local retirement only',
      });
      final attempt = recoveryCheckoutAttempt(original);
      final count = await txn.update(
        'qr_checkout_attempts',
        {
          'state': 'managed',
          'payload': jsonEncode(attempt.copy(state: 'managed').json),
        },
        where: 'id = ? AND scope = ? AND payload = ?',
        whereArgs: [original['id'], original['scope'], original['payload']],
      );
      if (count != 1) throw StateError('Saved checkout changed');
      return true;
    });
  }
}
