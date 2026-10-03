import 'dart:async';

/// LAUNCH-P4 C6 — keeps this till's "sold out" flags in step with the branch:
/// polls `GET /device/sold-out` every [interval] while online, and once more
/// when the app comes back to the foreground ([onResume]). The ids are
/// written to the cached catalog ([apply]), which re-emits the menu, so a dish
/// switched off on another till, the handheld or the portal greys out here
/// within a minute. Never driven by stock (owner decision 4).
///
/// Failures are silent and retried on the next tick; nothing is applied
/// unless the fetch succeeded.
class SoldOutSync {
  SoldOutSync({
    required this.fetch,
    required this.apply,
    required this.online,
    this.interval = const Duration(seconds: 60),
  });

  final Future<Set<int>> Function() fetch;
  final Future<void> Function(Set<int> productIds) apply;
  final bool Function() online;
  final Duration interval;

  Timer? _timer;
  bool _inFlight = false;

  bool get running => _timer != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// The app returned to the foreground — refresh now.
  void onResume() => unawaited(poll());

  /// One poll; true when the server answered and the ids were applied.
  Future<bool> poll() async {
    if (_inFlight || !online()) return false;
    _inFlight = true;
    try {
      final ids = await fetch();
      await apply(ids);
      return true;
    } catch (_) {
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
