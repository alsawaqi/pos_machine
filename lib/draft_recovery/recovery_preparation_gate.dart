/// Covers already-started cashier callbacks before their first outbox call
/// (for example GPS/customer lookup after tender). Admission is read-only and
/// refuses until those callbacks have finished their durable preparation.
class RecoveryPreparationGate {
  int _pending = 0;
  int get pending => _pending;
  Future<T> run<T>(Future<T> Function() operation) async {
    _pending++;
    try {
      return await operation();
    } finally {
      _pending--;
    }
  }

  void assertIdle() {
    if (_pending != 0) {
      throw StateError('An existing sale or transfer is still being saved.');
    }
  }
}
