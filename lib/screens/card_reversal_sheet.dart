import 'package:flutter/material.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import '../state/card_reversal_controller.dart';
import '../strings/softpos_strings.dart';

Future<String?> promptManagerPin(BuildContext context) async {
  final pin = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(softposText(context, 'managerPin')),
        content: TextField(
          controller: pin,
          obscureText: true,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          onSubmitted: (value) {
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(softposText(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (pin.text.isNotEmpty) Navigator.pop(context, pin.text);
            },
            child: Text(softposText(context, 'continue')),
          ),
        ],
      ),
    );
  } finally {
    pin.dispose();
  }
}

class CardReversalScreen extends StatefulWidget {
  const CardReversalScreen({
    super.key,
    required this.controller,
    this.orderUuid,
    this.voidReasons = const [],
    this.operatorName = '',
  });
  final CardReversalController controller;
  final String? orderUuid;
  final List<Map<String, dynamic>> voidReasons;
  final String operatorName;
  @override
  State<CardReversalScreen> createState() => _CardReversalScreenState();
}

class _CardReversalScreenState extends State<CardReversalScreen> {
  final _amount = TextEditingController();
  final Map<int, TextEditingController> _quantities = {};
  Map<String, dynamic>? _payment;
  int? _reason;
  String _kind = 'refund';
  String? _error;
  bool _loading = true;
  CardReversalController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.orderUuid != null) {
        await c.load(widget.orderUuid!);
      } else {
        await c.recover();
      }
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    for (final field in _quantities.values) {
      field.dispose();
    }
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => PopScope(
      canPop: !c.busy,
      child: Scaffold(
        appBar: AppBar(title: Text(softposText(context, 'title'))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(softposText(context, 'online')),
                  if (_error != null || c.error != null)
                    Text(
                      _error ?? c.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (widget.orderUuid == null) ...[
                    Text(softposText(context, 'recovery')),
                    for (final reversal in c.pending)
                      Card(
                        child: ListTile(
                          title: Text(
                            reversal['description']?.toString() ??
                                reversal['reversal_uuid'].toString(),
                          ),
                          subtitle: Text(
                            baisasToOmr(reversal['amount_baisas'] as int),
                          ),
                          trailing: TextButton(
                            onPressed: c.busy
                                ? null
                                : () => _observed(reversal),
                            child: Text(softposText(context, 'report')),
                          ),
                        ),
                      ),
                  ] else ...[
                    if (c.payments.isEmpty)
                      Text(softposText(context, 'noPayments')),
                    DropdownButtonFormField<String>(
                      initialValue: _payment?['payment_uuid'] as String?,
                      decoration: InputDecoration(
                        labelText: softposText(context, 'payment'),
                      ),
                      items: [
                        for (final payment in c.payments)
                          DropdownMenuItem(
                            value: payment['payment_uuid'] as String,
                            child: Text(
                              '${payment['payment_uuid']} · ${baisasToOmr(payment['amount_baisas'] as int)}',
                            ),
                          ),
                      ],
                      onChanged: c.busy || c.reservation != null
                          ? null
                          : (uuid) => setState(() {
                              _payment = c.payments.firstWhere(
                                (p) => p['payment_uuid'] == uuid,
                              );
                              for (final field in _quantities.values) {
                                field.dispose();
                              }
                              _quantities.clear();
                            }),
                    ),
                    if (_payment != null) ...[
                      if (_payment!['unavailable_reason'] != null)
                        Text(
                          softposText(
                            context,
                            _payment!['unavailable_reason'].toString(),
                          ),
                        ),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'void',
                            label: Text(softposText(context, 'void')),
                            enabled:
                                _payment!['can_void'] == true &&
                                !c.busy &&
                                c.reservation == null,
                          ),
                          ButtonSegment(
                            value: 'refund',
                            label: Text(softposText(context, 'refund')),
                            enabled:
                                _payment!['can_refund'] == true &&
                                !c.busy &&
                                c.reservation == null,
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (value) =>
                            setState(() => _kind = value.first),
                      ),
                      if (_kind == 'void')
                        DropdownButtonFormField<int>(
                          initialValue: _reason,
                          decoration: InputDecoration(
                            labelText: softposText(context, 'reason'),
                          ),
                          items: [
                            for (final reason in widget.voidReasons)
                              DropdownMenuItem(
                                value: reason['id'] as int,
                                child: Text(reason['name'].toString()),
                              ),
                          ],
                          onChanged: c.busy
                              ? null
                              : (value) => setState(() => _reason = value),
                        ),
                      if (_kind == 'refund') ...[
                        TextField(
                          controller: _amount,
                          enabled: !c.busy && c.reservation == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: softposText(context, 'custom'),
                          ),
                        ),
                        Text(softposText(context, 'lines')),
                        for (final line
                            in ((_payment!['refundable_lines'] as List?) ??
                                    const [])
                                .whereType<Map>())
                          TextField(
                            controller: _quantities.putIfAbsent(
                              line['order_item_id'] as int,
                              TextEditingController.new,
                            ),
                            enabled: !c.busy && c.reservation == null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  '${line['order_item_id']} · ${softposText(context, 'remaining')}: ${line['remaining_qty']}',
                            ),
                          ),
                      ],
                      FilledButton(
                        onPressed:
                            c.busy ||
                                c.reservation != null ||
                                c.needsRecovery ||
                                _payment![_kind == 'void'
                                        ? 'can_void'
                                        : 'can_refund'] !=
                                    true
                            ? null
                            : _execute,
                        child: Text(softposText(context, 'continue')),
                      ),
                    ],
                  ],
                  if (c.reservation != null)
                    Text(
                      '${baisasToOmr(c.reservation!['amount_baisas'] as int)} ${c.reservation!['currency']}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  if (c.busy) ...[
                    const LinearProgressIndicator(),
                    Text(softposText(context, 'progress')),
                  ],
                  if (c.result != null)
                    Text(softposText(context, c.result!['status'].toString())),
                  if (c.needsRecovery) ...[
                    Text(softposText(context, 'recovery')),
                    TextButton(
                      onPressed: c.busy ? null : () => _safe(c.retryReport),
                      child: Text(softposText(context, 'retryReport')),
                    ),
                  ],
                  if (c.printFailed) Text(softposText(context, 'printFailed')),
                  if (c.slip.isNotEmpty)
                    TextButton(
                      onPressed: c.busy ? null : () => _safe(c.reprint),
                      child: Text(softposText(context, 'reprint')),
                    ),
                ],
              ),
      ),
    ),
  );
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _execute() async {
    final pin = await promptManagerPin(context);
    if (pin == null || !mounted) return;
    await _safe(
      () => c.execute(
        payment: _payment!,
        kind: _kind,
        managerPin: pin,
        voidReasonId: _reason,
        customAmountBaisas: _kind == 'refund' && _amount.text.trim().isNotEmpty
            ? omrToBaisas(_amount.text.trim())
            : null,
        lines: _kind != 'refund'
            ? null
            : [
                for (final entry in _quantities.entries)
                  if (entry.value.text.trim().isNotEmpty)
                    {
                      'order_item_id': entry.key,
                      'qty': entry.value.text.trim(),
                    },
              ],
        confirmAmount: (baisas, currency) async {
          if (!mounted) return false;
          return await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: Text(softposText(context, 'confirm')),
                  content: Text(
                    '${baisasToOmr(baisas)} ${currency == '0512' ? 'OMR' : currency}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(softposText(context, 'cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(softposText(context, 'continue')),
                    ),
                  ],
                ),
              ) ??
              false;
        },
      ),
    );
  }

  Future<void> _observed(Map<String, dynamic> reserved) async {
    final code = TextEditingController(), rrn = TextEditingController();
    final auth = TextEditingController(), description = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(softposText(context, 'report')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(softposText(context, 'recovery')),
                TextField(
                  controller: code,
                  decoration: InputDecoration(
                    labelText: softposText(context, 'responseCode'),
                  ),
                ),
                TextField(
                  controller: rrn,
                  decoration: InputDecoration(
                    labelText: softposText(context, 'rrn'),
                  ),
                ),
                TextField(
                  controller: auth,
                  decoration: InputDecoration(
                    labelText: softposText(context, 'authCode'),
                  ),
                ),
                TextField(
                  controller: description,
                  decoration: InputDecoration(
                    labelText: softposText(context, 'report'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(softposText(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(softposText(context, 'report')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _safe(
        () => c.reportObserved(
          reserved,
          SoftPosOutcome.fromPayload({
            'stage': reserved['kind'],
            'responseCode': code.text.trim(),
            'resultCode': -1,
            'rrn': rrn.text.trim(),
            'authCode': auth.text.trim(),
            'description': description.text.trim(),
            'operator_observed': true,
          }),
          operatorName: widget.operatorName,
        ),
      );
    } finally {
      code.dispose();
      rrn.dispose();
      auth.dispose();
      description.dispose();
    }
  }
}

/// Reads pending work once at startup. Opening recovery never invokes the bank.
class CardReversalRecoveryGate extends StatefulWidget {
  const CardReversalRecoveryGate({
    super.key,
    required this.child,
    required this.createController,
    this.operatorName = '',
  });
  final Widget child;
  final CardReversalController Function() createController;
  final String operatorName;
  @override
  State<CardReversalRecoveryGate> createState() =>
      _CardReversalRecoveryGateState();
}

class _CardReversalRecoveryGateState extends State<CardReversalRecoveryGate> {
  late final CardReversalController _controller;
  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
    _controller
        .recover()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_controller.pending.isNotEmpty)
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              title: Text(softposText(context, 'progress')),
              trailing: TextButton(
                child: Text(softposText(context, 'report')),
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CardReversalScreen(
                        controller: widget.createController(),
                        operatorName: widget.operatorName,
                      ),
                    ),
                  );
                  await _controller.recover();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
        ),
      Expanded(child: widget.child),
    ],
  );
}

class SoftposTerminalPanel extends StatefulWidget {
  const SoftposTerminalPanel({
    super.key,
    required this.profile,
    required this.check,
    this.reason,
  });
  final SoftPosProfile profile;
  final Future<SoftPosOutcome> Function() check;
  final String? reason;
  @override
  State<SoftposTerminalPanel> createState() => _SoftposTerminalPanelState();
}

class _SoftposTerminalPanelState extends State<SoftposTerminalPanel> {
  bool _busy = false;
  String? _result;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${softposText(context, 'terminal')}: ${widget.profile.bankName} · ${widget.profile.package}',
      ),
      if (widget.reason != null) Text(softposText(context, widget.reason!)),
      if (widget.profile.requiresManualFirstLaunch)
        Text(softposText(context, 'firstLaunch')),
      TextButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  final result = await widget.check();
                  if (mounted) {
                    setState(
                      () => _result =
                          result.description ??
                          result.payload['code']?.toString() ??
                          softposText(context, result.verdict.name),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: Text(softposText(context, 'checkTerminal')),
      ),
      if (_result != null) Text(_result!),
    ],
  );
}
