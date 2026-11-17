import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/fractal_tracker/data/fractal_model.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/fractal_screen.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';
import 'package:trading_balance_f/features/connections/connections_screen.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/levels_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/watchlist_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/support_resistance_screen.dart';
import 'package:trading_balance_f/features/tools/tools_screen.dart';
import 'package:trading_balance_f/main.dart' show WebStorageHelper;

class _EmptyWatchlistStorage implements WatchlistStorage {
  @override
  Future<String?> readSnapshot() async => null;

  @override
  Future<bool> writeSnapshot(String encodedSnapshot) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all four tool cards open their destination', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final watchlist = WatchlistController(
      store: WatchlistStore(storage: _EmptyWatchlistStorage()),
      loadActiveInstruments: (marketMode) async =>
          const <SupportResistanceInstrument>[],
    );
    await watchlist.load();
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) =>
              Future<SupportResistanceMarketSnapshot>.error(
                StateError('No levels should load for an empty watchlist.'),
              ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(
            WebStorageHelper(preferences),
          ),
          fractalDataProvider.overrideWith(
            (ref, scope) async => <FractalData>[],
          ),
          supportResistanceWatchlistProvider.overrideWith((ref) => watchlist),
          supportResistanceLevelsProvider.overrideWith((ref) => levels),
          vndExchangeRateProvider.overrideWith((ref) async => 25400),
        ],
        child: const MaterialApp(home: ToolsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fractal theo nguồn giá của sàn'), findsOneWidget);
    expect(find.text('Coin theo dõi riêng theo sàn'), findsOneWidget);
    expect(find.text('Thêm, đổi hoặc quản lý kết nối'), findsOneWidget);
    expect(find.text('Hiển thị, tiền tệ, múi giờ'), findsOneWidget);
    expect(find.text('BMAG'), findsOneWidget);
    expect(find.text('Hỗ trợ / kháng cự'), findsOneWidget);
    expect(find.text('Sàn & tài khoản'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);

    await tester.tap(find.text('BMAG'));
    await tester.pumpAndSettle();
    expect(find.byType(FractalScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(FractalScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hỗ trợ / kháng cự'));
    await tester.pumpAndSettle();
    expect(find.byType(SupportResistanceScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SupportResistanceScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sàn & tài khoản'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ConnectionsScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
