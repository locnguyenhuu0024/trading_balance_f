import 'package:dio/dio.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_registry.dart';
import 'package:trading_balance_f/core/exchange/exchange_scope.dart';
import 'package:trading_balance_f/core/exchange/market_source.dart';
import 'package:trading_balance_f/core/network/request_coordinator.dart';
import 'package:trading_balance_f/core/timezone/app_time_zone.dart';
import 'package:trading_balance_f/exchanges/binance/binance_client.dart';
import 'package:trading_balance_f/exchanges/binance/binance_market.dart';
import 'package:trading_balance_f/exchanges/okx/okx_adapter.dart';
import '../../support/fake_exchange_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/features/fractal_tracker/presentation/providers/fractal_provider.dart';

void main() {
  test('Binance fixture klines compute BMAG quarters', () async {
    final client = _FractalFixtureClient();
    final container = _binanceContainer(client);
    addTearDown(container.dispose);
    final data = await container.read(fractalDataProvider.future);
    final month = data.firstWhere((item) => item.timeframeLabel == 'M1');
    expect(month.quarters[0].open, 10);
    expect(month.quarters[0].close, 12);
    expect(month.quarters[0].high, 15);
    expect(month.quarters[0].low, 8);
    expect(month.quarters[1].open, 20);
    expect(month.quarters[1].close, 22);
    expect(client.symbols, everyElement('BTCUSDT'));
  });

  test('Binance candle failure surfaces as a provider error', () async {
    final container = _binanceContainer(_FractalFixtureClient(fail: true));
    addTearDown(container.dispose);
    await expectLater(
      container.read(fractalDataProvider.future),
      throwsStateError,
    );
  });

  test('changing exchange scope resets the selected coin', () {
    final client = _FractalFixtureClient();
    final container = _binanceContainer(client);
    addTearDown(container.dispose);
    final subscription = container.listen(
      selectedCoinProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    container.read(selectedCoinProvider.notifier).state = 'ETH';
    container.read(selectedConnectionIdProvider.notifier).state = 'okx-default';
    expect(container.read(selectedCoinProvider), 'BTC');
  });

  test('candle transport failure surfaces as a provider error', () async {
    final container = ProviderContainer(
      overrides: [okxDataClientProvider.overrideWithValue(_FailingClient())],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(fractalDataProvider.future),
      throwsStateError,
    );
  });
  group('fractal tracker OKX candle alignment', () {
    test('uses UTC-aligned OKX bars for month and year sub-candles', () {
      expect(fractalBarForTimeframe('M1'), '1Dutc');
      expect(fractalBarForTimeframe('Y1'), '1Mutc');
    });

    test('labels UTC-aligned sub-candles by their UTC calendar date', () {
      final julyFirstUtc = DateTime.utc(2026, 7, 1).millisecondsSinceEpoch;
      final januaryUtc = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;

      expect(fractalSubCandleLabel('M1', julyFirstUtc), '1');
      expect(fractalSubCandleLabel('Y1', januaryUtc), '1');
    });

    test('labels the same instant in the selected time zone', () {
      final lateUtc = DateTime.utc(2026, 7, 1, 23, 30).millisecondsSinceEpoch;

      expect(fractalSubCandleLabel('M1', lateUtc), '1');
      expect(
        fractalSubCandleLabel('M1', lateUtc, timeZoneId: 'Asia/Ho_Chi_Minh'),
        '2',
      );
    });

    test('builds current day and week ranges in the selected time zone', () {
      final instant = DateTime.utc(2026, 7, 1, 16, 30);

      final day = fractalPeriodBounds(
        timeframe: 'D1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        instant: instant,
      );
      final week = fractalPeriodBounds(
        timeframe: 'W1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        instant: instant,
      );

      expect(day.isCurrentPeriod, isTrue);
      expect(day.startMs, DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch);
      expect(day.endMs, DateTime.utc(2026, 7, 1, 17).millisecondsSinceEpoch);
      expect(week.isCurrentPeriod, isTrue);
      expect(
        week.startMs,
        DateTime.utc(2026, 6, 28, 17).millisecondsSinceEpoch,
      );
      expect(week.endMs, DateTime.utc(2026, 7, 5, 17).millisecondsSinceEpoch);
    });

    test('builds selected month and year ranges in the chosen time zone', () {
      final month = fractalPeriodBounds(
        timeframe: 'M1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        targetDate: DateTime(2026, 7),
        instant: DateTime.utc(2026, 8, 1),
      );
      final year = fractalPeriodBounds(
        timeframe: 'Y1',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        targetDate: DateTime(2026),
        instant: DateTime.utc(2027, 1, 1),
      );

      expect(month.isCurrentPeriod, isFalse);
      expect(
        month.startMs,
        DateTime.utc(2026, 6, 30, 17).millisecondsSinceEpoch,
      );
      expect(month.endMs, DateTime.utc(2026, 7, 31, 17).millisecondsSinceEpoch);
      expect(year.isCurrentPeriod, isFalse);
      expect(
        year.startMs,
        DateTime.utc(2025, 12, 31, 17).millisecondsSinceEpoch,
      );
      expect(year.endMs, DateTime.utc(2026, 12, 31, 17).millisecondsSinceEpoch);
    });

    test(
      'assigns a year monthly candle to the quarter it mostly belongs to',
      () {
        final startMs = DateTime.utc(2026).millisecondsSinceEpoch;
        final endMs = DateTime.utc(2027).millisecondsSinceEpoch;
        final julyMonthlyCandleMs = DateTime.utc(
          2026,
          7,
        ).millisecondsSinceEpoch;

        expect(
          fractalQuarterIndex(
            timeframe: 'Y1',
            candleTimestampMs: julyMonthlyCandleMs,
            startMs: startMs,
            endMs: endMs,
          ),
          2,
        );
      },
    );
  });
}

class _FailingClient extends OkxDataClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async => throw StateError('transport failure');
}

ProviderContainer _binanceContainer(_FractalFixtureClient client) =>
    ProviderContainer(
      overrides: [
        exchangeRegistryProvider.overrideWith(
          (ref) => [
            const ExchangeRegistration(
              profile: ConnectionProfile(
                connectionId: 'okx-default',
                exchange: ExchangeId.okx,
                label: 'OKX',
              ),
              adapter: OkxAdapter(),
            ),
            ExchangeRegistration(
              profile: const ConnectionProfile(
                connectionId: 'binance',
                exchange: ExchangeId.binance,
                label: 'Binance',
              ),
              adapter: _BinanceAdapter(client),
            ),
          ],
        ),
        selectedConnectionIdProvider.overrideWith((ref) => 'binance'),
        selectedMonthProvider.overrideWith((ref) => DateTime(2024, 1)),
        selectedYearProvider.overrideWith((ref) => 2024),
        appTimeZoneProvider.overrideWith((ref) => 'UTC'),
      ],
    );

class _BinanceAdapter extends FakeExchangeAdapter {
  _BinanceAdapter(this.client);
  final BinanceClient client;
  @override
  MarketSource market(Ref ref) => BinanceMarket(client);
}

class _FractalFixtureClient extends BinanceClient {
  _FractalFixtureClient({this.fail = false})
    : super(coordinator: RequestCoordinator());
  final bool fail;
  final symbols = <String>[];
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic> queryParameters = const {},
  }) async {
    if (fail) throw StateError('transport failure');
    symbols.add(queryParameters['symbol'] as String);
    final rows =
        queryParameters['interval'] == '1d' ||
            queryParameters['interval'] == '1M'
        ? [
            [
              DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
              '10',
              '15',
              '8',
              '12',
              '99',
            ],
            [
              DateTime.utc(2024, 1, 10).millisecondsSinceEpoch,
              '20',
              '25',
              '18',
              '22',
              '99',
            ],
          ]
        : <List<dynamic>>[];
    return Response(
      requestOptions: RequestOptions(path: path),
      data: rows,
    );
  }
}
