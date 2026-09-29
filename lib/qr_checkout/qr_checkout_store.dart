import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'qr_checkout_models.dart';

abstract interface class CheckoutReceiptJournal {
  Future<List<CheckoutAttempt>> endedWithoutReceipt();
}

abstract interface class CheckoutStore {
  Future<CheckoutAttempt?> active();
  Future<void> create(CheckoutAttempt attempt);
  Future<void> replace(CheckoutAttempt previous, CheckoutAttempt next);
}

/// A separate QR payment journal: no changes to sales/outbox/table DB schemas.
/// One unresolved attempt per device scope. No background tender or deletion.
class SqliteCheckoutStore implements CheckoutStore, CheckoutReceiptJournal {
  SqliteCheckoutStore(this.db, this.scope);
  final Database db;
  final String scope;
  static Future<SqliteCheckoutStore> open(String scope) async {
    final directory = await getDatabasesPath();
    final db = await openBusinessDatabase(
      '$directory/qr_checkout_attempts.db',
      version: 1,
      onCreate: (db, _) => createSchema(db),
    );
    return SqliteCheckoutStore(db, scope);
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''CREATE TABLE qr_checkout_attempts (
      id TEXT PRIMARY KEY, scope TEXT NOT NULL, state TEXT NOT NULL,
      payload TEXT NOT NULL)''');
    await db.execute('''CREATE UNIQUE INDEX qr_checkout_one_active
      ON qr_checkout_attempts(scope)
      WHERE state NOT IN ('paid', 'released', 'managed')''');
  }

  @override
  Future<List<CheckoutAttempt>> endedWithoutReceipt() async {
    final rows = await db.query(
      'qr_checkout_attempts',
      where: "scope = ?",
      whereArgs: [scope],
    );
    final attempts = rows.map((row) {
      final attempt = CheckoutAttempt.decode(row['payload'] as String);
      if (attempt.id != row['id'] || attempt.state != row['state']) {
        throw const FormatException('Checkout journal columns disagree');
      }
      return attempt;
    }).toList();
    return attempts
        .where(
          (attempt) =>
              const {
                'refused',
                'released',
                'managed',
              }.contains(attempt.state) &&
              !attempts.any(
                (other) =>
                    other.id != attempt.id &&
                    other.orderUuid == attempt.orderUuid &&
                    !other.terminal &&
                    other.state != 'refused',
              ),
        )
        .toList();
  }

  @override
  Future<CheckoutAttempt?> active() async {
    final rows = await db.query(
      'qr_checkout_attempts',
      where: "scope = ? AND state NOT IN ('paid', 'released', 'managed')",
      whereArgs: [scope],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final attempt = CheckoutAttempt.decode(row['payload'] as String);
    if (attempt.id != row['id'] || attempt.state != row['state']) {
      throw const FormatException('Checkout journal columns disagree');
    }
    return attempt;
  }

  @override
  Future<void> create(CheckoutAttempt attempt) async {
    // Only a brand-new intent can establish that tender has not started.
    // Never retrofit this assertion onto an older reservation.
    if (attempt.tenderMayHaveStarted == false &&
        (attempt.state != 'claiming' || attempt.claim != null)) {
      throw StateError('No-tender evidence requires a new checkout intent');
    }
    await db.insert('qr_checkout_attempts', {
      'id': attempt.id,
      'scope': scope,
      'state': attempt.state,
      'payload': jsonEncode(attempt.json),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> replace(CheckoutAttempt previous, CheckoutAttempt next) async {
    if ((next.tenderMayHaveStarted == false &&
            previous.tenderMayHaveStarted != false) ||
        (previous.tenderMayHaveStarted != null &&
            next.tenderMayHaveStarted == null)) {
      throw StateError('Cannot erase or invent checkout tender evidence');
    }
    if (previous.id != next.id ||
        previous.orderUuid != next.orderUuid ||
        previous.terminal ||
        (previous.event != null &&
            (jsonEncode(previous.event) != jsonEncode(next.event) ||
                previous.paymentContract != next.paymentContract))) {
      throw StateError(
        'Cannot replace a payment identity or a terminal journal row',
      );
    }
    final count = await db.update(
      'qr_checkout_attempts',
      {'state': next.state, 'payload': jsonEncode(next.json)},
      where: 'scope = ? AND id = ? AND payload = ?',
      whereArgs: [scope, previous.id, jsonEncode(previous.json)],
    );
    if (count != 1) throw StateError('Checkout changed on another screen');
  }
}
