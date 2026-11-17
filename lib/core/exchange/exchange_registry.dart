import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../exchanges/okx/okx_adapter.dart';
import '../../exchanges/binance/binance_adapter.dart';
import 'exchange_adapter.dart';
import 'exchange_models.dart';

class ExchangeRegistration {
  const ExchangeRegistration({required this.profile, required this.adapter});
  final ConnectionProfile profile;
  final ExchangeAdapter adapter;
}

final exchangeRegistryProvider = Provider<List<ExchangeRegistration>>(
  (ref) => [
    const ExchangeRegistration(
      profile: ConnectionProfile(
        connectionId: 'okx-default',
        exchange: ExchangeId.okx,
        label: 'OKX',
      ),
      adapter: OkxAdapter(),
    ),
    const ExchangeRegistration(
      profile: ConnectionProfile(
        connectionId: 'binance-default',
        exchange: ExchangeId.binance,
        label: 'Binance',
      ),
      adapter: BinanceAdapter(),
    ),
  ],
);
