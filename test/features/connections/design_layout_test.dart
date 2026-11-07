import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import 'package:trading_balance_f/features/connections/binance_connection_form.dart';
import 'package:trading_balance_f/features/connections/connection_catalog_screen.dart';
import 'package:trading_balance_f/features/connections/connections_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/fractal_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';
import 'package:trading_balance_f/features/market/presentation/market_screen.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/levels_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/watchlist_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/support_resistance_screen.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

class _EmptyWatchlistStorage implements WatchlistStorage {
  @override
  Future<String?> readSnapshot() async => null;
  @override
  Future<bool> writeSnapshot(String encodedSnapshot) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final screens = <String, Widget>{
    'market': const MarketScreen(),
    'fractal': const FractalScreen(),
    'support resistance': const SupportResistanceScreen(),
    'settings': const SettingsScreen(),
    'connections': const ConnectionsScreen(),
    'catalog': const ConnectionCatalogScreen(),
    'Binance form': const BinanceConnectionForm(),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} fits narrow width at maximum text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final watchlist = WatchlistController(
        store: WatchlistStore(storage: _EmptyWatchlistStorage()),
        loadActiveInstruments: (_) async =>
            const <SupportResistanceInstrument>[],
      );
      await watchlist.load();
      final levels = SupportResistanceLevelsController(
        loadLevels:
            ({
              required marketMode,
              required instrumentId,
              required timeframe,
            }) => Future<SupportResistanceMarketSnapshot>.error(
              StateError('empty watchlist'),
            ),
      );
      const registration = ExchangeRegistration(
        profile: ConnectionProfile(
          connectionId: 'okx-default',
          exchange: ExchangeId.okx,
          label: 'Tài khoản có nhãn rất dài để kiểm tra bố cục',
        ),
        adapter: OkxAdapter(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(
              WebStorageHelper(preferences),
            ),
            exchangeRegistryProvider.overrideWith((ref) => [registration]),
            configuredConnectionsProvider.overrideWith(
              (ref) async => [registration],
            ),
            marketListProvider.overrideWith((ref) async => <MarketTicker>[]),
            fractalDataProvider.overrideWith(
              (ref, scope) async => <FractalData>[],
            ),
            supportResistanceWatchlistProvider.overrideWith((ref) => watchlist),
            supportResistanceLevelsProvider.overrideWith((ref) => levels),
            vndExchangeRateProvider.overrideWith((ref) async => 25400),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: entry.value,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
