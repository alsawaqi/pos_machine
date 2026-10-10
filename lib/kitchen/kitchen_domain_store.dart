import 'package:mithqal_kitchen_core/mithqal_kitchen_core.dart';
import '../data/order_sync_repository.dart';

final class TillKitchenDomainStore implements KitchenDomainIntake {
  final OrderSyncRepository repository;
  TillKitchenDomainStore(this.repository);
  @override
  Future<List<Json>> pendingKitchen() => repository.pendingKitchen();
  @override
  Future<void> acknowledgeKitchen(String id, Json receipt) =>
      repository.acknowledgeKitchen(id, receipt);
  @override
  Future<void> persist(String id, String originalJson) =>
      repository.persistKitchenDomain(id, originalJson);
  @override
  Future<DomainEvidence> evidence(String id, String originalHash) =>
      repository.kitchenDomainEvidence(id, originalHash);
}
