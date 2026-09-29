import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/support_resistance/data/watchlist_store.dart';
import 'package:trading_balance_f/features/support_resistance/domain/models.dart';
import 'package:trading_balance_f/features/support_resistance/presentation/providers/watchlist_provider.dart';

void main() {
  group('RED-29 persisted corruption and failure boundaries', () {
    test('sanitizes corrupt lists and falls back from invalid enums', () async {
      final storage = _MemoryWatchlistStorage(
        initial: jsonEncode(<String, Object>{
          'version': WatchlistStore.schemaVersion,
          'marketMode': 'cash',
          'timeframe': '6H',
          'spotInstrumentIds': <Object?>[
            'BTC-USDT',
            'BTC-USDT',
            'DELISTED-USDT',
            'wrong-market-USDT-SWAP',
            'ETH-USDT',
            'XRP-USDT',
            'SOL-USDT',
            'ADA-USDT',
            'DOGE-USDT',
            'BNB-USDT',
            'TON-USDT',
            'AVAX-USDT',
            'LINK-USDT',
            42,
          ],
          'perpetualInstrumentIds': <Object?>[
            'ETH-USDT-SWAP',
            'ETH-USDT-SWAP',
            'invalid-USDT',
          ],
        }),
      );
      final controller = _controller(storage);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.snapshot.marketMode, SupportResistanceMarketMode.spot);
      expect(controller.snapshot.timeframe, SupportResistanceTimeframe.h6);
      expect(controller.snapshot.spotInstrumentIds, <String>[
        'BTC-USDT',
        'DELISTED-USDT',
        'ETH-USDT',
        'XRP-USDT',
        'SOL-USDT',
        'ADA-USDT',
        'DOGE-USDT',
        'BNB-USDT',
        'TON-USDT',
        'AVAX-USDT',
      ]);
      expect(controller.snapshot.perpetualInstrumentIds, <String>[
        'ETH-USDT-SWAP',
      ]);

      final removeResult = await controller.removeInstrument('DELISTED-USDT');
      expect(removeResult, WatchlistMutationResult.changed);
      expect(
        controller.snapshot.spotInstrumentIds,
        isNot(contains('DELISTED-USDT')),
      );
    });

    test(
      'rejects duplicates, inactive instruments, and an eleventh coin',
      () async {
        final ids = <String>[
          'BTC-USDT',
          'ETH-USDT',
          'XRP-USDT',
          'SOL-USDT',
          'ADA-USDT',
          'DOGE-USDT',
          'BNB-USDT',
          'TON-USDT',
          'AVAX-USDT',
        ];
        final storage = _MemoryWatchlistStorage(
          initial: jsonEncode(<String, Object>{
            'version': WatchlistStore.schemaVersion,
            'marketMode': SupportResistanceMarketMode.spot.name,
            'timeframe': SupportResistanceTimeframe.h6.name,
            'spotInstrumentIds': ids,
            'perpetualInstrumentIds': const <String>[],
          }),
        );
        final controller = _controller(
          storage,
          active: <SupportResistanceInstrument>[
            _instrument(SupportResistanceMarketMode.spot, 'BTC-USDT'),
            _instrument(SupportResistanceMarketMode.spot, 'LINK-USDT'),
          ],
        );
        addTearDown(controller.dispose);
        await controller.load();

        expect(
          await controller.addInstrument('BTC-USDT'),
          WatchlistMutationResult.duplicate,
        );
        expect(
          await controller.addInstrument('INACTIVE-USDT'),
          WatchlistMutationResult.instrumentUnavailable,
        );
        expect(
          await controller.addInstrument('LINK-USDT'),
          WatchlistMutationResult.changed,
        );
        expect(
          await controller.addInstrument('ELEVENTH-USDT'),
          WatchlistMutationResult.limitReached,
        );
        expect(controller.snapshot.spotInstrumentIds, <String>[
          ...ids,
          'LINK-USDT',
        ]);
        expect(storage.writeCount, 1);
      },
    );

    test(
      'failed persistence rolls back and exposes a recoverable save error',
      () async {
        final storage = _MemoryWatchlistStorage()..failWrites = true;
        final controller = _controller(
          storage,
          active: <SupportResistanceInstrument>[
            _instrument(SupportResistanceMarketMode.spot, 'BTC-USDT'),
          ],
        );
        addTearDown(controller.dispose);
        await controller.load();

        expect(
          await controller.addInstrument('BTC-USDT'),
          WatchlistMutationResult.persistenceFailed,
        );
        expect(controller.snapshot.spotInstrumentIds, isEmpty);
        expect(controller.saveError, isNotNull);

        storage.failWrites = false;
        expect(
          await controller.addInstrument('BTC-USDT'),
          WatchlistMutationResult.changed,
        );
        expect(controller.snapshot.spotInstrumentIds, <String>['BTC-USDT']);
        expect(controller.saveError, isNull);
      },
    );
  });

  group('GREEN-29 persisted watchlist behavior', () {
    test(
      'restores separate ordered mode lists and the last timeframe',
      () async {
        final storage = _MemoryWatchlistStorage();
        final active = <SupportResistanceInstrument>[
          _instrument(SupportResistanceMarketMode.spot, 'ETH-USDT'),
          _instrument(SupportResistanceMarketMode.spot, 'BTC-USDT'),
          _instrument(SupportResistanceMarketMode.perpetual, 'ETH-USDT-SWAP'),
          _instrument(SupportResistanceMarketMode.perpetual, 'BTC-USDT-SWAP'),
        ];
        final first = _controller(storage, active: active);
        await first.load();
        expect(first.snapshot.marketMode, SupportResistanceMarketMode.spot);
        expect(first.snapshot.timeframe, SupportResistanceTimeframe.h6);
        expect(
          await first.addInstrument('ETH-USDT'),
          WatchlistMutationResult.changed,
        );
        expect(
          await first.addInstrument('BTC-USDT'),
          WatchlistMutationResult.changed,
        );
        expect(
          await first.setMarketMode(SupportResistanceMarketMode.perpetual),
          WatchlistMutationResult.changed,
        );
        expect(
          await first.addInstrument('BTC-USDT-SWAP'),
          WatchlistMutationResult.changed,
        );
        expect(
          await first.addInstrument('ETH-USDT-SWAP'),
          WatchlistMutationResult.changed,
        );
        expect(
          await first.setTimeframe(SupportResistanceTimeframe.d1),
          WatchlistMutationResult.changed,
        );
        first.dispose();

        final restored = _controller(storage, active: active);
        addTearDown(restored.dispose);
        await restored.load();

        expect(restored.snapshot.spotInstrumentIds, <String>[
          'ETH-USDT',
          'BTC-USDT',
        ]);
        expect(restored.snapshot.perpetualInstrumentIds, <String>[
          'BTC-USDT-SWAP',
          'ETH-USDT-SWAP',
        ]);
        expect(
          restored.snapshot.marketMode,
          SupportResistanceMarketMode.perpetual,
        );
        expect(restored.snapshot.timeframe, SupportResistanceTimeframe.d1);
      },
    );

    test('serializes concurrent updates into complete snapshots', () async {
      final storage = _MemoryWatchlistStorage()..blockWrites = true;
      final controller = _controller(storage);
      addTearDown(controller.dispose);
      await controller.load();

      final modeUpdate = controller.setMarketMode(
        SupportResistanceMarketMode.perpetual,
      );
      await storage.firstWriteStarted.future;
      final timeframeUpdate = controller.setTimeframe(
        SupportResistanceTimeframe.d1,
      );
      await Future<void>.delayed(Duration.zero);
      expect(storage.writeCount, 1);

      storage.releaseWrites.complete();
      expect(await modeUpdate, WatchlistMutationResult.changed);
      expect(await timeframeUpdate, WatchlistMutationResult.changed);
      expect(storage.writeCount, 2);

      final restored = _controller(storage);
      addTearDown(restored.dispose);
      await restored.load();
      expect(
        restored.snapshot.marketMode,
        SupportResistanceMarketMode.perpetual,
      );
      expect(restored.snapshot.timeframe, SupportResistanceTimeframe.d1);
    });
  });
}

WatchlistController _controller(
  _MemoryWatchlistStorage storage, {
  List<SupportResistanceInstrument> active =
      const <SupportResistanceInstrument>[],
}) => WatchlistController(
  store: WatchlistStore(storage: storage),
  loadActiveInstruments: (marketMode) async => active
      .where((instrument) => instrument.marketMode == marketMode)
      .toList(growable: false),
);

SupportResistanceInstrument _instrument(
  SupportResistanceMarketMode mode,
  String instrumentId,
) => SupportResistanceInstrument(
  marketMode: mode,
  instrumentId: instrumentId,
  baseCurrency: instrumentId.split('-').first,
);

class _MemoryWatchlistStorage implements WatchlistStorage {
  _MemoryWatchlistStorage({this.initial});

  String? initial;
  bool failWrites = false;
  bool blockWrites = false;
  int writeCount = 0;
  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> releaseWrites = Completer<void>();

  @override
  Future<String?> readSnapshot() async => initial;

  @override
  Future<bool> writeSnapshot(String encodedSnapshot) async {
    writeCount++;
    if (!firstWriteStarted.isCompleted) firstWriteStarted.complete();
    if (blockWrites) await releaseWrites.future;
    if (failWrites) return false;
    initial = encodedSnapshot;
    return true;
  }
}
