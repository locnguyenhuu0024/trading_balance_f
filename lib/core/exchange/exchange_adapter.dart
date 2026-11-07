import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'exchange_models.dart';

abstract class ExchangeAdapter {
  ExchangeId get id;
  ExchangeCapabilities get capabilities;
  Future<AccountSnapshot> readAccount(Ref ref, ExchangeScope scope);
  Future<List<ExchangePosition>> readPositions(Ref ref, ExchangeScope scope);
  Future<List<ExchangeOrder>> readOrders(Ref ref, ExchangeScope scope);
  void invalidateAccount(void Function(ProviderOrFamily) invalidate);
  void invalidatePositions(void Function(ProviderOrFamily) invalidate);
  void invalidateOrders(void Function(ProviderOrFamily) invalidate);
  ExchangeFailure classify(Object error);
}
