import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/watchlist_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/levels_provider.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/support_resistance_screen.dart';

void main() {
  test(
    'RED-30 ignores obsolete responses and isolates one coin failure',
    () async {
      final oldSpotRequest = Completer<SupportResistanceMarketSnapshot>();
      final controller = SupportResistanceLevelsController(
        loadLevels:
            ({required marketMode, required instrumentId, required timeframe}) {
              if (marketMode == SupportResistanceMarketMode.spot) {
                return oldSpotRequest.future;
              }
              if (instrumentId == 'BTC-USDT-SWAP') {
                return Future.value(
                  _snapshot(
                    marketMode,
                    instrumentId,
                    timeframe,
                    referencePrice: 0.0000000000000123,
                  ),
                );
              }
              return Future<SupportResistanceMarketSnapshot>.error(
                StateError('coin unavailable'),
              );
            },
      );
      addTearDown(controller.dispose);

      final obsolete = _key(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
      );
      final btc = _key(
        SupportResistanceMarketMode.perpetual,
        'BTC-USDT-SWAP',
        SupportResistanceTimeframe.d1,
      );
      final eth = _key(
        SupportResistanceMarketMode.perpetual,
        'ETH-USDT-SWAP',
        SupportResistanceTimeframe.d1,
      );

      controller.setActiveKeys(<SupportResistanceLevelsKey>[obsolete]);
      await Future<void>.delayed(Duration.zero);
      controller.setActiveKeys(<SupportResistanceLevelsKey>[btc, eth]);
      await controller.refresh();

      expect(
        controller.stateFor(btc)?.status,
        SupportResistanceLevelsStatus.available,
      );
      expect(
        controller.stateFor(eth)?.status,
        SupportResistanceLevelsStatus.unavailable,
      );
      expect(
        controller.stateFor(btc)?.snapshot?.referencePrice,
        0.0000000000000123,
      );

      oldSpotRequest.complete(
        _snapshot(
          SupportResistanceMarketMode.spot,
          'BTC-USDT',
          SupportResistanceTimeframe.h6,
          referencePrice: 999,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.stateFor(obsolete), isNull);
      expect(
        controller.stateFor(btc)?.snapshot?.referencePrice,
        0.0000000000000123,
      );
      expect(
        controller.stateFor(eth)?.status,
        SupportResistanceLevelsStatus.unavailable,
      );
    },
  );

  test(
    'coalesces same-key refreshes and keeps failed results marked stale',
    () async {
      final firstRequest = Completer<SupportResistanceMarketSnapshot>();
      var loadCount = 0;
      final key = _key(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
      );
      final controller = SupportResistanceLevelsController(
        loadLevels:
            ({required marketMode, required instrumentId, required timeframe}) {
              loadCount++;
              if (loadCount == 1) return firstRequest.future;
              return Future<SupportResistanceMarketSnapshot>.error(
                StateError('refresh failed'),
              );
            },
      );
      addTearDown(controller.dispose);

      controller.setActiveKeys(<SupportResistanceLevelsKey>[key]);
      await Future<void>.delayed(Duration.zero);
      final firstRefresh = controller.refresh();
      final secondRefresh = controller.refresh();
      expect(loadCount, 1);
      firstRequest.complete(
        _screenSnapshot(
          SupportResistanceMarketMode.spot,
          'BTC-USDT',
          SupportResistanceTimeframe.h6,
        ),
      );
      await Future.wait(<Future<void>>[firstRefresh, secondRefresh]);

      await controller.refresh();

      expect(loadCount, 2);
      expect(
        controller.stateFor(key)?.status,
        SupportResistanceLevelsStatus.unavailable,
      );
      expect(controller.stateFor(key)?.isStale, isTrue);
      expect(controller.stateFor(key)?.snapshot?.referencePrice, 100);
    },
  );

  test('adding a key preserves a retained key request', () async {
    final firstBtcRequest = Completer<SupportResistanceMarketSnapshot>();
    var btcCalls = 0;
    var ethCalls = 0;
    final btc = _key(
      SupportResistanceMarketMode.spot,
      'BTC-USDT',
      SupportResistanceTimeframe.h6,
    );
    final eth = _key(
      SupportResistanceMarketMode.spot,
      'ETH-USDT',
      SupportResistanceTimeframe.h6,
    );
    final controller = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) {
            if (instrumentId == 'BTC-USDT') {
              btcCalls++;
              if (btcCalls == 1) return firstBtcRequest.future;
              return Future.value(
                _snapshot(
                  marketMode,
                  instrumentId,
                  timeframe,
                  referencePrice: 222,
                ),
              );
            }
            ethCalls++;
            return Future.value(
              _snapshot(
                marketMode,
                instrumentId,
                timeframe,
                referencePrice: 300,
              ),
            );
          },
    );
    addTearDown(controller.dispose);

    controller.setActiveKeys(<SupportResistanceLevelsKey>[btc]);
    await Future<void>.delayed(Duration.zero);
    controller.setActiveKeys(<SupportResistanceLevelsKey>[btc, eth]);
    await Future<void>.delayed(Duration.zero);

    expect(btcCalls, 1);
    expect(ethCalls, 1);

    firstBtcRequest.complete(
      _snapshot(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
        referencePrice: 123,
      ),
    );
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(btcCalls, 1);
    expect(controller.stateFor(btc)?.snapshot?.referencePrice, 123);
  });

  test('removed in-flight response cannot replace a re-added key', () async {
    final removedBtcRequest = Completer<SupportResistanceMarketSnapshot>();
    var btcCalls = 0;
    final btc = _key(
      SupportResistanceMarketMode.spot,
      'BTC-USDT',
      SupportResistanceTimeframe.h6,
    );
    final controller = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) {
            btcCalls++;
            if (btcCalls == 1) return removedBtcRequest.future;
            return Future.value(
              _snapshot(
                marketMode,
                instrumentId,
                timeframe,
                referencePrice: 222,
              ),
            );
          },
    );
    addTearDown(controller.dispose);

    controller.setActiveKeys(<SupportResistanceLevelsKey>[btc]);
    await Future<void>.delayed(Duration.zero);
    controller.setActiveKeys(const <SupportResistanceLevelsKey>[]);
    controller.setActiveKeys(<SupportResistanceLevelsKey>[btc]);
    expect(btcCalls, 2);
    await controller.refresh();

    expect(controller.stateFor(btc)?.snapshot?.referencePrice, 222);

    removedBtcRequest.complete(
      _snapshot(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
        referencePrice: 999,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(btcCalls, 2);
    expect(controller.stateFor(btc)?.snapshot?.referencePrice, 222);
  });

  testWidgets('Support/Resistance refreshes only on entry and manual request', (
    tester,
  ) async {
    final instruments = _instruments();
    final watchlist = await _watchlistController(
      instruments: instruments,
      spotIds: const <String>['BTC-USDT'],
    );
    var loadCount = 0;
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({
            required marketMode,
            required instrumentId,
            required timeframe,
          }) async {
            loadCount++;
            if (loadCount > 1) throw StateError('refresh failed');
            return _screenSnapshot(
              marketMode,
              instrumentId,
              timeframe,
              candleCount: 25,
            );
          },
    );

    await tester.pumpWidget(_screenApp(watchlist, levels, instruments));
    await tester.pumpAndSettle();
    expect(loadCount, 1);
    expect(find.byKey(const Key('levels-sparse-BTC-USDT')), findsOneWidget);
    expect(find.byTooltip('Làm mới dữ liệu'), findsOneWidget);
    final refreshRect = tester.getRect(
      find.byKey(const Key('support-resistance-refresh')),
    );
    expect(refreshRect.width, greaterThanOrEqualTo(48));
    expect(refreshRect.height, greaterThanOrEqualTo(48));

    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(loadCount, 1);

    await tester.tap(find.byKey(const Key('support-resistance-refresh')));
    await tester.pumpAndSettle();
    expect(loadCount, 2);
    expect(find.text('Dữ liệu cũ · lần cập nhật thất bại'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('Dữ liệu cũ · lần cập nhật thất bại'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(loadCount, 2);
  });

  testWidgets('manual refresh disables while the level read is pending', (
    tester,
  ) async {
    final instruments = _instruments();
    final watchlist = await _watchlistController(
      instruments: instruments,
      spotIds: const <String>['BTC-USDT'],
    );
    final pending = Completer<SupportResistanceMarketSnapshot>();
    var loadCount = 0;
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) {
            loadCount++;
            if (loadCount == 1) {
              return Future.value(
                _screenSnapshot(marketMode, instrumentId, timeframe),
              );
            }
            return pending.future;
          },
    );
    await tester.pumpWidget(_screenApp(watchlist, levels, instruments));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('support-resistance-refresh')));
    await tester.pump();
    expect(loadCount, 2);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('support-resistance-refresh')),
          )
          .onPressed,
      isNull,
    );

    pending.complete(
      _screenSnapshot(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RED-30 a late market response cannot replace live coin cards', (
    tester,
  ) async {
    final instruments = _instruments();
    final watchlist = await _watchlistController(
      instruments: instruments,
      spotIds: const <String>['BTC-USDT', 'ETH-USDT'],
      perpetualIds: const <String>['BTC-USDT-SWAP', 'ETH-USDT-SWAP'],
    );
    final obsoleteSpotRequest = Completer<SupportResistanceMarketSnapshot>();
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({required marketMode, required instrumentId, required timeframe}) {
            if (marketMode == SupportResistanceMarketMode.spot &&
                instrumentId == 'BTC-USDT' &&
                timeframe == SupportResistanceTimeframe.h6) {
              return obsoleteSpotRequest.future;
            }
            if (marketMode == SupportResistanceMarketMode.spot) {
              return Future<SupportResistanceMarketSnapshot>.error(
                StateError('Spot coin unavailable.'),
              );
            }
            if (instrumentId == 'ETH-USDT-SWAP' &&
                timeframe == SupportResistanceTimeframe.d1) {
              return Future<SupportResistanceMarketSnapshot>.error(
                StateError('Perpetual coin unavailable.'),
              );
            }
            return Future.value(
              _screenSnapshot(
                marketMode,
                instrumentId,
                timeframe,
                referencePriceOverride:
                    timeframe == SupportResistanceTimeframe.d1 ? 210.0 : 200.0,
              ),
            );
          },
    );

    await tester.pumpWidget(_screenApp(watchlist, levels, instruments));
    await tester.pumpAndSettle();
    expect(find.text('Đang tải dữ liệu…'), findsOneWidget);
    expect(
      find.byKey(const Key('levels-unavailable-ETH-USDT')),
      findsOneWidget,
    );

    await tester.tap(find.text('Perpetual'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeframe-D1')));
    await tester.pumpAndSettle();
    expect(
      watchlist.snapshot.marketMode,
      SupportResistanceMarketMode.perpetual,
    );
    expect(watchlist.snapshot.timeframe, SupportResistanceTimeframe.d1);
    final currentKey = _key(
      SupportResistanceMarketMode.perpetual,
      'BTC-USDT-SWAP',
      SupportResistanceTimeframe.d1,
    );
    expect(
      levels.stateFor(currentKey)?.status,
      SupportResistanceLevelsStatus.available,
    );
    expect(levels.stateFor(currentKey)?.snapshot?.referencePrice, 210.0);
    expect(find.text('BTC-USDT-SWAP'), findsOneWidget);
    expect(find.textContaining('210.00'), findsOneWidget);
    expect(
      find.byKey(const Key('levels-unavailable-ETH-USDT-SWAP')),
      findsOneWidget,
    );

    obsoleteSpotRequest.complete(
      _screenSnapshot(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h6,
        referencePriceOverride: 999,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('210.00'), findsOneWidget);
    expect(find.textContaining('999.00'), findsNothing);
    expect(
      find.byKey(const Key('levels-unavailable-ETH-USDT-SWAP')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GREEN-30 selects two coins, switches keys, and refreshes', (
    tester,
  ) async {
    final instruments = _instruments();
    final watchlist = await _watchlistController(instruments: instruments);
    final calls = <String, int>{};
    final levels = SupportResistanceLevelsController(
      loadLevels:
          ({
            required marketMode,
            required instrumentId,
            required timeframe,
          }) async {
            final requestKey = _requestKey(marketMode, instrumentId, timeframe);
            calls.update(requestKey, (count) => count + 1, ifAbsent: () => 1);
            return _screenSnapshot(marketMode, instrumentId, timeframe);
          },
    );

    await tester.pumpWidget(_screenApp(watchlist, levels, instruments));
    await tester.pumpAndSettle();
    expect(find.text('Spot'), findsOneWidget);
    expect(find.text('H6'), findsOneWidget);
    expect(find.text('Chọn coin để bắt đầu'), findsOneWidget);

    await _addFromPicker(tester, 'BTC-USDT');
    await tester.enterText(
      find.byKey(const Key('support-resistance-coin-search')),
      'ETH',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instrument-option-ETH-USDT')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-resistance-picker-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('support-resistance-card-BTC-USDT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('support-resistance-card-ETH-USDT')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('support-level-BTC-USDT-0')), findsOneWidget);
    expect(find.byKey(const Key('support-level-BTC-USDT-4')), findsOneWidget);
    expect(find.byKey(const Key('support-level-BTC-USDT-5')), findsNothing);
    expect(
      find.byKey(const Key('resistance-level-BTC-USDT-4')),
      findsOneWidget,
    );
    expect(find.textContaining('1.23e-14'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('support-level-BTC-USDT-0')))
          .data,
      '99.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('support-level-BTC-USDT-1')))
          .data,
      '98.00',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('resistance-level-BTC-USDT-0')))
          .data,
      '101.00',
    );
    expect(find.textContaining('UTC'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('timeframe-H4')));
    await tester.pumpAndSettle();
    expect(
      calls[_requestKey(
        SupportResistanceMarketMode.spot,
        'BTC-USDT',
        SupportResistanceTimeframe.h4,
      )],
      1,
    );

    await tester.tap(find.text('Perpetual'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn coin để bắt đầu'), findsOneWidget);
    await _addFromPicker(tester, 'BTC-USDT-SWAP');
    await tester.enterText(
      find.byKey(const Key('support-resistance-coin-search')),
      'ETH',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instrument-option-ETH-USDT-SWAP')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-resistance-picker-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('support-resistance-card-BTC-USDT-SWAP')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('support-resistance-card-ETH-USDT-SWAP')),
      findsOneWidget,
    );
    final btcPerpetualKey = _requestKey(
      SupportResistanceMarketMode.perpetual,
      'BTC-USDT-SWAP',
      SupportResistanceTimeframe.h4,
    );
    final ethPerpetualKey = _requestKey(
      SupportResistanceMarketMode.perpetual,
      'ETH-USDT-SWAP',
      SupportResistanceTimeframe.h4,
    );
    final btcBeforeRefresh = calls[btcPerpetualKey];
    final ethBeforeRefresh = calls[ethPerpetualKey];
    await tester.tap(find.byKey(const Key('support-resistance-refresh')));
    await tester.pumpAndSettle();
    expect(calls[btcPerpetualKey], btcBeforeRefresh! + 1);
    expect(calls[ethPerpetualKey], ethBeforeRefresh! + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _screenApp(
  WatchlistController watchlist,
  SupportResistanceLevelsController levels,
  List<SupportResistanceInstrument> instruments,
) => ProviderScope(
  overrides: [
    supportResistanceWatchlistProvider.overrideWith((ref) => watchlist),
    supportResistanceLevelsProvider.overrideWith((ref) => levels),
    supportResistanceInstrumentsProvider.overrideWith(
      (ref, marketMode) async => instruments
          .where((instrument) => instrument.marketMode == marketMode)
          .toList(growable: false),
    ),
  ],
  child: const MaterialApp(home: SupportResistanceScreen()),
);

Future<void> _addFromPicker(WidgetTester tester, String instrumentId) async {
  await tester.tap(find.byKey(const Key('support-resistance-add')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('support-resistance-coin-search')),
    instrumentId.split('-').first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('instrument-option-$instrumentId')));
  await tester.pumpAndSettle();
}

Future<WatchlistController> _watchlistController({
  required List<SupportResistanceInstrument> instruments,
  List<String> spotIds = const <String>[],
  List<String> perpetualIds = const <String>[],
}) async {
  final controller = WatchlistController(
    store: WatchlistStore(storage: _MemoryWatchlistStorage()),
    loadActiveInstruments: (marketMode) async => instruments
        .where((instrument) => instrument.marketMode == marketMode)
        .toList(growable: false),
  );
  await controller.load();
  for (final instrumentId in spotIds) {
    await controller.addInstrument(instrumentId);
  }
  if (perpetualIds.isNotEmpty) {
    await controller.setMarketMode(SupportResistanceMarketMode.perpetual);
    for (final instrumentId in perpetualIds) {
      await controller.addInstrument(instrumentId);
    }
    await controller.setMarketMode(SupportResistanceMarketMode.spot);
  }
  return controller;
}

List<SupportResistanceInstrument> _instruments() =>
    <SupportResistanceInstrument>[
      _instrument(SupportResistanceMarketMode.spot, 'BTC-USDT'),
      _instrument(SupportResistanceMarketMode.spot, 'ETH-USDT'),
      _instrument(SupportResistanceMarketMode.perpetual, 'BTC-USDT-SWAP'),
      _instrument(SupportResistanceMarketMode.perpetual, 'ETH-USDT-SWAP'),
    ];

SupportResistanceInstrument _instrument(
  SupportResistanceMarketMode marketMode,
  String instrumentId,
) => SupportResistanceInstrument(
  marketMode: marketMode,
  instrumentId: instrumentId,
  baseCurrency: instrumentId.split('-').first,
);

SupportResistanceMarketSnapshot _screenSnapshot(
  SupportResistanceMarketMode marketMode,
  String instrumentId,
  SupportResistanceTimeframe timeframe, {
  double? referencePriceOverride,
  int candleCount = 300,
}) {
  final referencePrice =
      referencePriceOverride ??
      (instrumentId.startsWith('ETH')
          ? 0.0000000000000123
          : marketMode == SupportResistanceMarketMode.spot
          ? 100.0
          : 200.0);
  SupportResistanceLevel level(double price, int index) =>
      SupportResistanceLevel(
        price: price,
        firstTouchAt: DateTime.utc(2026, 9, 30).subtract(Duration(days: index)),
        lastTouchAt: DateTime.utc(2026, 9, 30).subtract(Duration(days: index)),
        touchCount: index + 1,
        side: price < referencePrice
            ? SupportResistanceLevelSide.support
            : SupportResistanceLevelSide.resistance,
      );
  final supports = List<SupportResistanceLevel>.generate(
    5,
    (index) => level(referencePrice * (1 - (index + 1) / 100), index),
  );
  final resistances = List<SupportResistanceLevel>.generate(
    5,
    (index) => level(referencePrice * (1 + (index + 1) / 100), index),
  );
  final candles = List<SupportResistanceCandle>.generate(
    candleCount,
    (index) => SupportResistanceCandle(
      timestamp: DateTime.utc(
        2026,
        9,
        30,
      ).subtract(timeframe.duration * (300 - index)),
      open: referencePrice,
      high: referencePrice * 1.01,
      low: referencePrice * 0.99,
      close: referencePrice,
      timeframe: timeframe,
      confirmed: true,
    ),
    growable: false,
  );

  return SupportResistanceMarketSnapshot(
    marketMode: marketMode,
    instrumentId: instrumentId,
    timeframe: timeframe,
    referencePrice: referencePrice,
    fetchedAt: DateTime.utc(2026, 9, 30, 12),
    candles: candles,
    analysis: SupportResistanceAnalysis(
      referencePrice: referencePrice,
      supports: supports,
      resistances: resistances,
    ),
  );
}

String _requestKey(
  SupportResistanceMarketMode marketMode,
  String instrumentId,
  SupportResistanceTimeframe timeframe,
) => '$marketMode|$instrumentId|${timeframe.label}';

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

SupportResistanceLevelsKey _key(
  SupportResistanceMarketMode marketMode,
  String instrumentId,
  SupportResistanceTimeframe timeframe,
) => SupportResistanceLevelsKey(
  marketMode: marketMode,
  instrumentId: instrumentId,
  timeframe: timeframe,
);

SupportResistanceMarketSnapshot _snapshot(
  SupportResistanceMarketMode marketMode,
  String instrumentId,
  SupportResistanceTimeframe timeframe, {
  required double referencePrice,
}) => SupportResistanceMarketSnapshot(
  marketMode: marketMode,
  instrumentId: instrumentId,
  timeframe: timeframe,
  referencePrice: referencePrice,
  fetchedAt: DateTime.utc(2026, 9, 30),
  candles: const <SupportResistanceCandle>[],
  analysis: SupportResistanceAnalysis(
    referencePrice: referencePrice,
    supports: const <SupportResistanceLevel>[],
    resistances: const <SupportResistanceLevel>[],
  ),
);
