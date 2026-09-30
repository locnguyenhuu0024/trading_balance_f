import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/navigation/main_navigation_shell.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences.dart';
import 'package:trading_balance_f/core/navigation/navigation_preferences_provider.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/core/navigation/trading_navigation_bar.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/levels_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/watchlist_provider.dart';

class _FakeOkxWebsocketService extends OkxWebsocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void subscribeToTickers(List<String> coinSymbols) {}
}

class _MemoryNavigationStorage extends SecureStorageHelper {
  _MemoryNavigationStorage() : super(const FlutterSecureStorage());

  NavigationPreferences? savedPreferences;

  @override
  Future<void> saveNavigationPreferences(
    NavigationPreferences preferences,
  ) async {
    savedPreferences = preferences;
  }
}

void main() {
  testWidgets('shows all primary destinations and switches selected content', (
    tester,
  ) async {
    final watchlist = WatchlistController(
      store: WatchlistStore(storage: _MemoryWatchlistStorage()),
      loadActiveInstruments: (marketMode) async =>
          const <SupportResistanceInstrument>[],
    );
    await watchlist.load();
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) =>
              Future<SupportResistanceMarketSnapshot>.error(
                StateError(
                  'No market request expected for an empty watchlist.',
                ),
              ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioFutureProvider.overrideWith(
            (ref) async => const OkxAccountData(),
          ),
          livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
          okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
          fractalDataProvider.overrideWith((ref) async => <FractalData>[]),
          positionsFutureProvider.overrideWith((ref) async => <OkxPosition>[]),
          ordersFutureProvider.overrideWith((ref) async => <OkxOrder>[]),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
          supportResistanceWatchlistProvider.overrideWith((ref) => watchlist),
          supportResistanceLevelsProvider.overrideWith((ref) => levels),
        ],
        child: const MaterialApp(home: MainNavigationShell()),
      ),
    );
    await tester.pump();

    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('BMAG'), findsNothing);
    expect(find.text('Lệnh'), findsNothing);
    expect(find.text('Thị trường'), findsNothing);
    expect(find.text('Cài đặt'), findsNothing);
    expect(TradingNavigationBar.items, hasLength(7));
    expect(find.byKey(const Key('navigation-destination-5')), findsOneWidget);
    expect(find.byKey(const Key('navigation-destination-6')), findsOneWidget);
    for (var index = 0; index < TradingNavigationBar.items.length; index++) {
      expect(find.byKey(Key('navigation-destination-$index')), findsOneWidget);
    }
    expect(find.text('Nhật ký'), findsNothing);
    expect(find.text('Ghi PnL'), findsNothing);
    expect(find.byTooltip('BMAG Matrix'), findsNothing);
    expect(find.byTooltip('Nhật ký PnL'), findsNothing);
    expect(find.byTooltip('Quản lý Lệnh'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byKey(const Key('navigation-destination-1')));
    await tester.pump();
    expect(find.text('BMAG Tracker (BTC)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pump();
    expect(find.text('Quản lý Giao dịch'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-5')));
    await tester.pump();
    expect(find.text('Trang tổng quan rủi ro'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);

    await tester.tap(find.byKey(const Key('navigation-destination-6')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Hỗ trợ và kháng cự'), findsOneWidget);
    expect(find.text('Chọn coin để bắt đầu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('seventh destination stays reachable at narrow widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final mode in <NavigationDisplayMode>[
      NavigationDisplayMode.bar,
      NavigationDisplayMode.floating,
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            navigationPreferencesInitialProvider.overrideWithValue(
              NavigationPreferences.defaults.copyWith(displayMode: mode),
            ),
          ],
          child: MaterialApp(
            home: MainNavigationShell(
              destinationBuilder: (context, index) =>
                  Center(child: Text('Destination $index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final isFixed = mode == NavigationDisplayMode.bar;
      final scrollKey = isFixed
          ? const Key('navigation-bar-horizontal-scroll')
          : const Key('floating-navigation-horizontal-scroll');
      final destinationKey = isFixed
          ? const Key('navigation-destination-6')
          : const Key('floating-navigation-destination-6');

      expect(find.byKey(scrollKey), findsOneWidget);
      await tester.drag(find.byKey(scrollKey), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(destinationKey)).width,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(destinationKey));
      await tester.pumpAndSettle();
      expect(find.text('Destination 6'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('filters hidden pages and maps visible slots in both modes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;

    for (final mode in [
      NavigationDisplayMode.bar,
      NavigationDisplayMode.floating,
    ]) {
      final storage = _MemoryNavigationStorage();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          navigationPreferencesInitialProvider.overrideWithValue(
            NavigationPreferences.defaults.copyWith(
              displayMode: mode,
              enabledDestinationIds: ['home', 'bmag', 'orders', 'settings'],
            ),
          ),
          themeModeProvider.overrideWith((ref) => ThemeMode.light),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MainNavigationShell(
              destinationBuilder: (context, index) => Text('Screen $index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final keyPrefix = mode == NavigationDisplayMode.bar
          ? 'navigation-destination-'
          : 'floating-navigation-destination-';
      expect(find.byTooltip('BMAG'), findsOneWidget);
      await tester.tap(find.byKey(Key('${keyPrefix}1')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 1'), findsOneWidget);

      await container
          .read(navigationPreferencesProvider.notifier)
          .setEnabledDestinationIds(['home', 'orders', 'settings']);
      await tester.pumpAndSettle();
      expect(find.text('Screen 0'), findsOneWidget);
      expect(find.byTooltip('BMAG'), findsNothing);
      expect(find.byKey(Key('${keyPrefix}3')), findsNothing);

      await tester.tap(find.byKey(Key('${keyPrefix}1')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 2'), findsOneWidget);

      await container
          .read(navigationPreferencesProvider.notifier)
          .setEnabledDestinationIds(['home', 'bmag', 'orders', 'settings']);
      await tester.pumpAndSettle();
      expect(find.byTooltip('BMAG'), findsOneWidget);
      await tester.tap(find.byKey(Key('${keyPrefix}1')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 1'), findsOneWidget);

      await container
          .read(navigationPreferencesProvider.notifier)
          .setEnabledDestinationIds(['orders', 'settings']);
      await tester.pumpAndSettle();
      expect(find.text('Screen 4'), findsOneWidget);
      expect(find.byTooltip('BMAG'), findsNothing);
      await tester.tap(find.byKey(Key('${keyPrefix}0')));
      await tester.pumpAndSettle();
      expect(find.text('Screen 2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets('seventh destination opens the support and resistance screen', (
    tester,
  ) async {
    final watchlist = WatchlistController(
      store: WatchlistStore(storage: _MemoryWatchlistStorage()),
      loadActiveInstruments: (marketMode) async =>
          const <SupportResistanceInstrument>[],
    );
    await watchlist.load();
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) =>
              Future<SupportResistanceMarketSnapshot>.error(
                StateError(
                  'No market request expected for an empty watchlist.',
                ),
              ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supportResistanceWatchlistProvider.overrideWith((ref) => watchlist),
          supportResistanceLevelsProvider.overrideWith((ref) => levels),
        ],
        child: const MaterialApp(home: MainNavigationShell()),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('navigation-destination-6')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Hỗ trợ và kháng cự'), findsOneWidget);
    expect(find.text('Chọn coin để bắt đầu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MemoryWatchlistStorage implements WatchlistStorage {
  String? _snapshot;

  @override
  Future<String?> readSnapshot() async => _snapshot;

  @override
  Future<bool> writeSnapshot(String encodedSnapshot) async {
    _snapshot = encodedSnapshot;
    return true;
  }
}
