import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

typedef Json = Map<String, dynamic>;

/// Scripted model of the pinned T4/T6 rules, not a mock returning expected
/// fixture outcomes. No fixture is read here. Pricing is deliberately limited
/// to the explicit seeded catalogue; the independent stack gate checks parity.
/// Sources: Open/CloseStaffTableSessionAction, ResolveStaffSeatingAction,
/// AppendStaffRoundAction, Move/JoinTableSessionAction, CancelStaffLineAction,
/// ClaimKitchenTicketAction; pos_api 3ea99241.
class FakeTableServer {
  DateTime now = DateTime.utc(2099, 9, 6, 12);
  final seats = <String, Json>{};
  final bills = <String, Json>{};
  final rounds = <int, Json>{};
  final journal = <TableShadowEvent>[];
  final tickets = <String, Json>{};
  final transcript = <Json>[];
  final acknowledgements = <String, Json>{};
  final cancellationReplay = <String, Json>{};
  final waste = <Json>[];
  final prices = <int, int>{10: 2000, 20: 1000};
  int _identity = 0, _round = 0, _reference = 0;

  String uuid() =>
      'ffffffff-ffff-4fff-8fff-${(++_identity).toString().padLeft(12, '0')}';
  String reference() => 'T-0906-${(++_reference).toString().padLeft(3, '0')}';
  bool live(Json? s) => s != null && ['open', 'billing'].contains(s['status']);
  Json? seatForTable(int table) =>
      seats.values.where((s) => s['table_id'] == table && live(s)).firstOrNull;
  Json? primary(Json? s) {
    if (s == null) return null;
    final winner = s['winner'] == null ? s : seats[s['winner']];
    return winner?['primary'] == null ? winner : seats[winner!['primary']];
  }

  Json? billFor(Json? s) => bills[primary(s)?['order_uuid']];
  int total(Json? s) => (billFor(s)?['total'] as int?) ?? 0;

  Json _seat(
    String key,
    int table, {
    String status = 'open',
    String? winner,
    String? reason,
    String? primaryKey,
  }) => seats[key] = {
    'uuid': uuid(),
    'key': key,
    'table_id': table,
    'status': status,
    'winner': winner,
    'primary': primaryKey,
    'reason': reason,
    'reference': status == 'open' && primaryKey == null ? reference() : null,
    'order_uuid': null,
  };

  void emit(Json s, String type, {int? device, Json payload = const {}}) {
    journal.add(
      TableShadowEvent(
        id: journal.length + 1,
        tableId: s['table_id'] as int,
        eventType: type,
        deviceId: device,
        payload: payload,
        orderUuid: primary(s)?['order_uuid'] as String?,
        createdAt: now,
      ),
    );
  }

  /// Setup operations are recorded separately from actual device batches.
  /// A replay runner must establish these states through authorized test data
  /// or QR flows before replaying subsequent device requests.
  String seedCustomer(int table, {int qty = 1, bool pending = true}) {
    final key = 'customer-${seats.length + 1}';
    final s = _seat(key, table);
    final bill = uuid();
    s['order_uuid'] = bill;
    bills[bill] = {
      'uuid': bill,
      'status': 'open',
      'total': pending ? 0 : qty * 2000,
    };
    final r = _makeRound(
      s,
      'customer-round',
      [
        {'product_id': 10, 'qty': qty, 'addon_ids': <int>[], 'notes': null},
      ],
      pending: pending,
      merged: false,
      printedAt: null,
    );
    emit(
      s,
      pending ? 'round_pending' : 'round_appended',
      payload: {'round_id': r['id']},
    );
    emit(
      s,
      'customer_order_arrived',
      payload: {
        'round_id': r['id'],
        'order_uuid': bill,
        'table_session_uuid': s['uuid'],
      },
    );
    transcript.add({
      'setup': 'customer',
      'table_id': table,
      'qty': qty,
      'pending': pending,
      'seating_key': key,
      'order_uuid': bill,
    });
    return key;
  }

  void retireSeed(String key) {
    final s = seats[key]!;
    s['status'] = 'closed';
    if (s['order_uuid'] != null) bills[s['order_uuid']]!['status'] = 'void';
    transcript.add({'setup': 'retire_seed', 'seating_key': key});
  }

  /// Explicit frozen server data for T6 §2.10.9, never client prices.
  void seedAccounting(String key) {
    final r = rounds.values.singleWhere((r) => r['head'] == key);
    r.addAll({
      'subtotal': 5000,
      'tax': 223,
      'total': 4673,
      'lines': <Json>[
        {
          'product_id': 10,
          'qty': 3,
          'addon_ids': <int>[],
          'notes': null,
          'unit_price_baisas': 1000,
          'line_discount_baisas': 300,
          'order_item_id': 101,
          'cancelled_qty': 0,
          'cancelled_discount_baisas': 0,
        },
        {
          'product_id': 20,
          'qty': 1,
          'addon_ids': <int>[],
          'notes': null,
          'unit_price_baisas': 2000,
          'line_discount_baisas': 0,
          'order_item_id': 102,
          'cancelled_qty': 0,
          'cancelled_discount_baisas': 0,
        },
      ],
    });
    refresh(seats[key]!);
    transcript.add({
      'setup': 'frozen_accounting',
      'seating_key': key,
      'round': jsonDecode(jsonEncode(r)),
    });
  }

  void seedDeadAlias(String key, int table) {
    final winner = seedCustomer(table, pending: false);
    _seat(key, table, status: 'merged', winner: winner, reason: 'merged');
    retireSeed(winner);
    transcript.add({
      'setup': 'merged_alias',
      'seating_key': key,
      'table_id': table,
      'winner_key': winner,
    });
  }

  Json result(String outcome, Json p, Json? s, {bool review = false}) {
    final head = primary(s);
    return {
      'outcome': outcome,
      'table_session_uuid': s?['uuid'],
      'winner_table_session_uuid': head != null && head != s
          ? head['uuid']
          : null,
      'order_uuid': head?['order_uuid'],
      'temp_reference': head?['reference'] ?? s?['reference'],
      'needs_review': review,
      'event_id': null,
      'seating_key': p['seating_key'],
      'table_id': p['table_id'],
    };
  }

  (String, Json) open(Json p, DateTime at, int device) {
    final key = p['seating_key'] as String;
    final existing = seats[key];
    if (existing != null) {
      return (
        ['closed', 'expired'].contains(existing['status'])
            ? 'already_closed'
            : 'replayed',
        existing,
      );
    }
    final occupied = seatForTable(p['table_id'] as int);
    if (occupied != null) {
      final offline =
          p['queued_offline'] == true || now.difference(at).inSeconds > 300;
      final outcome = offline ? 'merged' : 'attached';
      final s = _seat(
        key,
        p['table_id'] as int,
        status: 'merged',
        winner: occupied['key'] as String,
        reason: outcome,
      );
      emit(s, outcome, device: device);
      if (offline) emit(primary(s)!, 'needs_review', device: device);
      return (outcome, s);
    }
    final s = _seat(key, p['table_id'] as int);
    emit(s, 'opened', device: device);
    return ('opened', s);
  }

  Json _makeRound(
    Json head,
    String request,
    List<Json> lines, {
    required bool pending,
    required bool merged,
    required String? printedAt,
  }) {
    final priced = <Json>[];
    var subtotal = 0;
    for (final line in lines) {
      final price = prices[line['product_id']];
      if (price == null) {
        priced.add({...line, 'held_reason': 'product_missing'});
      } else {
        subtotal += price * (line['qty'] as int);
        priced.add({
          ...line,
          'unit_price_baisas': price,
          'line_discount_baisas': 0,
          'cancelled_qty': 0,
          'cancelled_discount_baisas': 0,
          'order_item_id': (_round + 1) * 100 + priced.length + 1,
        });
      }
    }
    final held = priced.any((l) => l.containsKey('held_reason'));
    final r = <String, dynamic>{
      'id': ++_round,
      'head': head['key'],
      'request': request,
      'order_uuid': head['order_uuid'],
      'round_no':
          rounds.values
              .where((r) => r['order_uuid'] == head['order_uuid'])
              .length +
          1,
      'status': pending || held ? 'pending_confirmation' : 'accepted',
      'merged': merged,
      'held': held,
      'lines': priced,
      'subtotal': subtotal,
      'tax': 0,
      'total': subtotal,
      'printed_at': printedAt,
    };
    rounds[_round] = r;
    return r;
  }

  void refresh(Json head) {
    final bill = bills[head['order_uuid']];
    if (bill == null) return;
    bill['total'] = rounds.values
        .where(
          (r) =>
              r['order_uuid'] == head['order_uuid'] &&
              r['status'] == 'accepted',
        )
        .fold<int>(0, (sum, r) => sum + (r['total'] as int));
  }

  Json roundResult(Json r) => {
    'round_id': r['id'],
    'round_no': r['round_no'],
    'round_status': r['status'],
    'total_baisas': r['total'],
    'accepted_seq': r['status'] == 'accepted' ? r['id'] : null,
    'print_pending': false,
    'review_reasons': [
      if (r['merged'] == true) 'merged',
      if (r['held'] == true) 'catalogue',
    ],
    'held_lines': [
      for (final (index, line) in (r['lines'] as List<Json>).indexed)
        if (line['held_reason'] != null)
          {
            'line_index': index,
            'product_id': line['product_id'],
            'addon_id': null,
            'reason': line['held_reason'],
          },
    ],
  };

  Json execute(Json event, int device) {
    final p = Map<String, dynamic>.from(event['payload'] as Map);
    final type = event['event_type'] as String;
    final at = DateTime.parse(event['client_timestamp'] as String);
    final s = seats[p['seating_key']];
    final head = primary(s);
    if (type == 'table.session.open') {
      final (outcome, row) = open(p, at, device);
      final answer = result(outcome, p, row, review: row['reason'] == 'merged');
      if (outcome != 'replayed' &&
          outcome != 'already_closed' &&
          answer['order_uuid'] == null) {
        answer['order_uuid'] = p['order_uuid'];
      }
      return answer;
    }
    if (type == 'table.session.round') {
      final created = s == null;
      final row =
          s ?? open({...p, 'opened_at': p['submitted_at']}, at, device).$2;
      final root = primary(row)!;
      final prior = rounds.values
          .where(
            (r) =>
                r['head'] == root['key'] &&
                r['request'] == p['client_request_id'],
          )
          .firstOrNull;
      if (prior != null) {
        return {
          ...result('replayed', p, row, review: prior['status'] != 'accepted'),
          ...roundResult(prior),
        };
      }
      if (!live(root) ||
          [
            'paid',
            'void',
            'refunded',
            'pending_verification',
          ].contains(billFor(row)?['status'])) {
        return result('bill_terminal', p, row, review: true);
      }
      if (root['status'] != 'open' ||
          (billFor(row) != null && billFor(row)!['status'] != 'open')) {
        return result('bill_unpaid', p, row);
      }
      if (root['order_uuid'] == null) {
        final proposal = p['order_uuid'] as String?;
        final bill = proposal != null && !bills.containsKey(proposal)
            ? proposal
            : uuid();
        root['order_uuid'] = bill;
        bills[bill] = {'uuid': bill, 'status': 'open', 'total': 0};
      }
      final merged = row['reason'] == 'merged';
      final r = _makeRound(
        root,
        p['client_request_id'] as String,
        (p['lines'] as List)
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList(),
        pending: merged,
        merged: merged,
        printedAt: p['printed_at'] as String?,
      );
      refresh(root);
      emit(
        root,
        r['status'] == 'accepted' ? 'round_appended' : 'round_pending',
        device: device,
      );
      final outcome = merged
          ? 'merged'
          : r['held'] == true
          ? 'held'
          : created
          ? 'seating_created'
          : 'appended';
      return {
        ...result(outcome, p, row, review: r['status'] != 'accepted'),
        ...roundResult(r),
      };
    }
    if (type == 'table.session.close') {
      if (s == null) {
        return result(
          'tombstoned',
          p,
          _seat(
            p['seating_key'] as String,
            p['table_id'] as int,
            status: 'closed',
          ),
        );
      }
      if (['closed', 'expired'].contains(s['status'])) {
        return result('already_closed', p, s);
      }
      if ((s['status'] == 'merged' && s['reason'] != 'attached') ||
          !live(head)) {
        return result('stale_generation', p, s);
      }
      if (billFor(s) != null &&
          ![
            'paid',
            'void',
            'refunded',
            'pending_verification',
          ].contains(billFor(s)!['status'])) {
        return result('bill_unpaid', p, s);
      }
      _closeFamily(head!);
      return result('closed', p, s);
    }
    if (type == 'table.session.move') {
      if (s == null) return result('unknown_seating', p, null);
      if (!live(head)) return result('stale_generation', p, s);
      if (head!['table_id'] == p['to_table_id']) {
        return result('replayed', p, s);
      }
      if (head['table_id'] != p['from_table_id']) {
        return result('stale_generation', p, s);
      }
      if (seatForTable(p['to_table_id'] as int) != null) {
        return result('target_occupied', p, s);
      }
      head['table_id'] = p['to_table_id'];
      return result('moved', p, s);
    }
    if (type == 'table.session.join') {
      if (s == null) return result('unknown_seating', p, null);
      if (!live(head)) return result('stale_generation', p, s);
      final joined = <int>[], refused = <int>[];
      var created = 0;
      for (final id in (p['join_table_ids'] as List).cast<int>().toSet()) {
        final occupied = seatForTable(id);
        final key = '${head!['key']}#$id';
        if (id == head['table_id'] || occupied?['primary'] == head['key']) {
          joined.add(id);
        } else if (occupied != null || seats.containsKey(key)) {
          refused.add(id);
        } else {
          _seat(key, id, primaryKey: head['key'] as String)['order_uuid'] =
              head['order_uuid'];
          joined.add(id);
          created++;
        }
      }
      return {
        ...result(
          created == 0 && refused.isEmpty ? 'replayed' : 'joined',
          p,
          s,
        ),
        'joined': joined,
        'refused': refused,
      };
    }
    if (type == 'table.session.cancel_line') return cancel(p, s);
    if (type == 'product.waste') {
      waste.add(p);
      return {'recorded': true};
    }
    if (type == 'order.pay' || type == 'order.void') {
      final bill = bills[p['order_uuid']];
      if (bill == null) throw StateError('order not found');
      if (type == 'order.pay') {
        final tender = (p['payments'] as List).cast<Map>().fold<int>(
          0,
          (sum, line) => sum + (line['amount_baisas'] as int),
        );
        if ((tender - (bill['total'] as int)).abs() > 1) {
          throw StateError(
            'payment total mismatch: tendered $tender baisas vs grand_total ${bill['total']}',
          );
        }
      }
      bill['status'] = type == 'order.pay' ? 'paid' : 'void';
      for (final root in seats.values.where(
        (r) =>
            r['order_uuid'] == p['order_uuid'] &&
            r['winner'] == null &&
            r['primary'] == null,
      )) {
        _closeFamily(root);
      }
      return {'order_uuid': p['order_uuid'], 'status': bill['status']};
    }
    throw UnsupportedError(type);
  }

  void _closeFamily(Json root) {
    for (final row in seats.values) {
      if (live(row) && (row == root || row['primary'] == root['key'])) {
        row['status'] = 'closed';
      }
    }
    for (final r in rounds.values) {
      if (r['head'] == root['key'] && r['status'] == 'pending_confirmation') {
        r['status'] = 'rejected';
      }
    }
  }

  /// Frozen arithmetic from T6 §2.10; no lookup in prices here.
  Json cancel(Json p, Json? s) {
    if (s == null) {
      return {
        ...result('unknown_seating', p, null),
        'cancelled_qty': 0,
        'unlinked_line_count': 0,
        'rounds': <Json>[],
      };
    }
    final head = primary(s)!;
    final replayKey = '${head['key']}:${p['client_request_id']}';
    final replay = cancellationReplay[replayKey];
    if (replay != null) return {...result('replayed', p, s), ...replay};
    if (billFor(s)?['status'] != 'open') {
      return {
        ...result('bill_terminal', p, s),
        'cancelled_qty': 0,
        'unlinked_line_count': 0,
        'grand_total_baisas': total(s),
        'rounds': <Json>[],
      };
    }
    var left = p['qty'] as int, unlinked = 0;
    final reductions = <Json>[];
    String notes(Object? v) => (v?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    String addons(Object? v) =>
        ((v as List? ?? []).cast<int>().toSet().toList()..sort()).join(',');
    for (final r in rounds.values.toList().reversed) {
      if (r['order_uuid'] != head['order_uuid'] ||
          r['status'] != 'accepted' ||
          left == 0) {
        continue;
      }
      final lines = r['lines'] as List<Json>;
      final subtotal = r['subtotal'] as int,
          tax = r['tax'] as int,
          grand = r['total'] as int;
      final ld = lines.fold<int>(
        0,
        (sum, l) =>
            sum +
            ((l['line_discount_baisas'] as int? ?? 0) -
                (l['cancelled_discount_baisas'] as int? ?? 0)),
      );
      final orderDiscount = subtotal + tax - grand - ld;
      var rawDelta = 0, discountDelta = 0;
      final changed = <Json>[];
      for (final (index, l) in lines.indexed.toList().reversed) {
        if (left == 0 ||
            l['held_reason'] != null ||
            l['product_id'] != p['product_id'] ||
            addons(l['addon_ids']) != addons(p['addon_ids']) ||
            notes(l['notes']) != notes(p['notes'])) {
          continue;
        }
        if (l['order_item_id'] == null) {
          unlinked++;
          continue;
        }
        final q = l['qty'] as int, cancelled = l['cancelled_qty'] as int;
        final remaining = q - cancelled;
        final k = remaining < left ? remaining : left;
        if (k == 0) continue;
        final discount = l['line_discount_baisas'] as int;
        final d = discount * remaining ~/ q - discount * (remaining - k) ~/ q;
        l['cancelled_qty'] = cancelled + k;
        l['cancelled_discount_baisas'] =
            (l['cancelled_discount_baisas'] as int) + d;
        rawDelta += (l['unit_price_baisas'] as int) * k;
        discountDelta += d;
        left -= k;
        changed.add({
          'round_id': r['id'],
          'line_index': index,
          'qty': k,
          'unit_price_baisas': l['unit_price_baisas'],
          'discount_baisas': d,
        });
      }
      if (changed.isEmpty) continue;
      final newS = subtotal - rawDelta, newLd = ld - discountDelta;
      final base = subtotal - ld, newBase = newS - newLd;
      final newO = base == 0 ? 0 : orderDiscount * newBase ~/ base;
      final taxed = subtotal - ld - orderDiscount,
          newTaxed = newS - newLd - newO;
      final newT = taxed == 0 ? 0 : (tax * newTaxed / taxed).round();
      r.addAll({'subtotal': newS, 'tax': newT, 'total': newTaxed + newT});
      reductions.addAll(
        changed.map(
          (l) => {
            ...l,
            'subtotal_baisas': newS,
            'tax_baisas': newT,
            'total_baisas': newTaxed + newT,
          },
        ),
      );
    }
    refresh(head);
    final values = {
      'cancelled_qty': (p['qty'] as int) - left,
      'unlinked_line_count': unlinked,
      'grand_total_baisas': total(s),
      'rounds': reductions,
    };
    if (left == p['qty']) {
      return {...result('nothing_to_cancel', p, s), ...values};
    }
    cancellationReplay[replayKey] = values;
    return {...result('cancelled', p, s), ...values};
  }

  Json ack(Json event, int device) {
    final key = '$device:${event['client_event_id']}';
    final prior = acknowledgements[key];
    if (prior != null) return prior; // processed SyncEvent is terminal
    try {
      final answer = {
        'client_event_id': event['client_event_id'],
        'status': 'processed',
        'result': execute(event, device),
      };
      acknowledgements[key] = answer;
      return answer;
    } on StateError catch (error) {
      return {
        'client_event_id': event['client_event_id'],
        'status': 'failed',
        'result': {'error': error.message},
      };
    }
  }

  Json boardRow(Json s) {
    final head = primary(s)!;
    final pending = rounds.values
        .where(
          (r) =>
              r['head'] == head['key'] && r['status'] == 'pending_confirmation',
        )
        .toList();
    return {
      'table_id': s['table_id'],
      'floor_id': 1,
      'table_label': 'Table ${s['table_id']}',
      'seating': {
        'uuid': s['uuid'],
        'status': s['status'],
        'temp_reference': head['reference'],
        'pending_rounds': [
          for (final r in pending)
            {'round_id': r['id'], 'priced_lines': r['lines']},
        ],
      },
      'bill': head['order_uuid'] == null
          ? null
          : {
              'order_uuid': head['order_uuid'],
              'grand_total_baisas': total(s),
              'pending_rounds': pending.length,
            },
    };
  }

  QrRoundEnvelope envelope(int id) {
    final r = rounds[id]!, head = seats[r['head']]!;
    return QrRoundEnvelope(
      round: QrDeviceRound(
        id: id,
        roundNo: r['round_no'] as int,
        status: r['status'] as String,
        subtotalBaisas: r['subtotal'] as int,
        taxBaisas: r['tax'] as int,
        totalBaisas: r['total'] as int,
        lines: (r['lines'] as List<Json>)
            .map(
              (l) => QrRoundDisplayLine.fromJson({
                ...l,
                'product_name': 'Product ${l['product_id']}',
              }),
            )
            .toList(),
      ),
      orderUuid: r['order_uuid'] as String,
      sessionUuid: '',
      tableLabel: 'Table ${head['table_id']}',
      tempReference: head['reference'] as String?,
      printedAt: DateTime.tryParse(r['printed_at']?.toString() ?? ''),
    );
  }
}

/// Network failures happen before a request, or after a complete server commit
/// but before delivery of the ACK. No durable row is reordered/edited here.
class FakeTableTransport implements HttpClientAdapter {
  FakeTableTransport(this.server, this.device);
  final FakeTableServer server;
  final int device;
  bool online = false;
  String? loseAckForType;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    DioException disconnected() => DioException(
      requestOptions: o,
      type: DioExceptionType.connectionError,
      error: 'scripted network interruption',
    );
    if (!online) throw disconnected();
    if (o.path.endsWith('/sync/push')) {
      final events = ((o.data as Map)['events'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final results = events.map((e) => server.ack(e, device)).toList();
      final lose = events.any((e) => e['event_type'] == loseAckForType);
      server.transcript.add({
        'device': device,
        'received_at': server.now.toIso8601String(),
        'events': jsonDecode(jsonEncode(events)),
        'results': jsonDecode(jsonEncode(results)),
        'ack_delivered': !lose,
      });
      if (lose) {
        loseAckForType = null;
        online = false;
        throw disconnected();
      }
      return _response({
        'data': {'results': results},
      }, 200);
    }
    if (o.path.endsWith('/kitchen/claim-print')) {
      final key = (o.data as Map)['ticket_key'] as String;
      final round = server.rounds[int.parse(key.split(':').last)]!;
      final existing = server.tickets[key];
      if (round['status'] != 'accepted' &&
          !(round['merged'] == true &&
              round['held'] == false &&
              round['printed_at'] != null)) {
        return _conflict(key, 'kitchen_round_not_printable');
      }
      if (existing != null &&
          existing['print_result'] != 'failed' &&
          existing['claimed_by_device_id'] != device) {
        return _conflict(key, 'kitchen_ticket_claimed');
      }
      final replay = existing != null && existing['print_result'] != 'failed';
      final ticket = replay
          ? existing
          : <String, dynamic>{
              'ticket_key': key,
              'round_id': round['id'],
              'order_uuid': round['order_uuid'],
              'claimed_by_device_id': device,
              'print_result': null,
              'printed_at': null,
            };
      server.tickets[key] = ticket;
      server.transcript.add({
        'device': device,
        'claim': key,
        'http_status': 201,
      });
      return _response({
        'data': {...ticket, 'replayed': replay, 'priced_lines': round['lines']},
      }, 201);
    }
    if (o.path.endsWith('/kitchen/print-result')) {
      final p = o.data as Map, key = p['ticket_key'] as String;
      final ticket = server.tickets[key]!;
      if (ticket['claimed_by_device_id'] != device) {
        return _conflict(key, 'kitchen_ticket_claimed');
      }
      ticket['print_result'] = p['print_result'];
      ticket['printed_at'] = p['printed_at'];
      // Printing time is wall-clock data from the real print controller, not
      // an outbox event. Only the result is part of deterministic replay.
      server.transcript.add({
        'device': device,
        'print_result': p['print_result'],
        'ticket_key': key,
      });
      return _response({'data': ticket}, 200);
    }
    throw UnsupportedError('Unexpected HTTP: ${o.method} ${o.path}');
  }

  ResponseBody _conflict(String key, String code) {
    server.transcript.add({
      'device': device,
      'claim': key,
      'http_status': 409,
      'code': code,
    });
    return _response({
      'error': {'code': code, 'message': code},
    }, 409);
  }

  ResponseBody _response(Json data, int status) => ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}
