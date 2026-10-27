import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/exchange/binance_exchange_reader.dart';
import 'package:trading_balance_f/core/exchange/binance_history_scan.dart';
import 'package:trading_balance_f/core/exchange/binance_read_routes.dart';
import 'package:trading_balance_f/core/exchange/exchange_models.dart';
import 'package:trading_balance_f/core/exchange/exchange_readers.dart';
import 'package:trading_balance_f/core/exchange/okx_exchange_reader.dart';
import 'package:trading_balance_f/core/network/binance_data_client.dart';
import 'package:trading_balance_f/core/network/binance_request_coordinator.dart';
import 'package:trading_balance_f/core/network/okx_data_client.dart';
import 'package:trading_balance_f/core/security/secure_storage_helper.dart';
import 'package:trading_balance_f/features/orders/data/okx_order_model.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';
import 'package:trading_balance_f/features/orders/data/order_repository.dart';
import 'package:trading_balance_f/features/portfolio/data/portfolio_repository.dart';

void main() {
  group('RED-120 Spot order price validation', () {
    test('a zero Spot MARKET price is unavailable', () async {
      final data = _newBinance((call) async {
        switch (call.path) {
          case '/api/v3/exchangeInfo':
            return <String, Object?>{
              'symbols': <Object?>[_spotCatalogRow('BTCUSDT', 'BTC', 'USDT')],
            };
          case '/api/v3/openOrders':
            return <Object?>[
              <String, Object?>{
                'symbol': 'BTCUSDT',
                'orderId': 1,
                'side': 'buy',
                'type': 'MARKET',
                'status': 'NEW',
                'origQty': '1',
                'executedQty': '0',
                'cummulativeQuoteQty': '0',
                'price': '0.00000000',
                'time': 10,
              },
              <String, Object?>{
                'symbol': 'BTCUSDT',
                'orderId': 2,
                'side': 'buy',
                'type': 'LIMIT',
                'status': 'NEW',
                'origQty': '1',
                'executedQty': '0',
                'cummulativeQuoteQty': '0',
                'price': '100.25',
                'time': 11,
              },
            ];
          default:
            throw StateError('Unexpected endpoint: ${call.path}');
        }
      });
      addTearDown(data.dispose);

      final orders = await data.reader.getSpotOpenOrders();
      final market = orders.singleWhere((order) => order.nativeId == '1');
      final limit = orders.singleWhere((order) => order.nativeId == '2');

      expect(market.price?.isAvailable, isFalse);
      expect(limit.price?.value?.amount.text, '100.25');
      expect(limit.price?.value?.currency, 'USDT');
    });
  });

  group('RED-117', () {
    test(
      'Spot catalog captures non-USDT pairs and unions in-generation symbols',
      () async {
        final data = _newBinance((call) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return <String, Object?>{
              'symbols': <Object?>[
                _spotCatalogRow('BTCUSDT', 'BTC', 'USDT'),
                _spotCatalogRow('ETHBTC', 'ETH', 'BTC'),
                _spotCatalogRow(
                  'IGNOREDUSDT',
                  'IGNORED',
                  'USDT',
                  enabled: false,
                ),
                _spotCatalogRow('BROKENBTC', '', 'BTC'),
              ],
            };
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(data.dispose);

        final catalog = await data.reader.getSpotCatalog(
          knownSymbols: const <String>['DELISTEDBTC'],
        );

        expect(
          catalog.instruments.map((instrument) => instrument.symbol),
          <String>['BROKENBTC', 'BTCUSDT', 'DELISTEDBTC', 'ETHBTC'],
        );
        expect(catalog.instruments.first.baseAsset.isAvailable, isFalse);
        expect(catalog.catalogComplete, isFalse);
        expect(
          catalog.instruments
              .singleWhere((instrument) => instrument.symbol == 'DELISTEDBTC')
              .quoteAsset
              .isAvailable,
          isFalse,
        );
      },
    );

    test(
      'invalid balance text remains unavailable instead of becoming zero',
      () async {
        final data = _newBinance((call) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return <String, Object?>{'symbols': <Object?>[]};
          }
          if (call.path == '/api/v3/account') {
            return <String, Object?>{
              'balances': <Object?>[
                <String, Object?>{
                  'asset': 'BTC',
                  'free': 'bad',
                  'locked': '0.1250',
                },
              ],
            };
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(data.dispose);

        final account = await data.reader.getSpotAccount();
        final balance = account.balances.single;

        expect(balance.free.isAvailable, isFalse);
        expect(balance.locked.value?.text, '0.1250');
        expect(balance.availableTotal.isAvailable, isFalse);
        expect(account.positions, isEmpty);
        expect(account.issues, hasLength(1));
      },
    );

    test(
      'conditional linkage requires positive actualOrderId and same instrument',
      () {
        final ordinary = _futuresOrder(
          id: '11',
          symbol: 'BTCUSDT',
          kind: ExchangeOrderKind.ordinary,
          executed: '2',
          quote: '200',
        );
        final matchingParent = _futuresOrder(
          id: '900',
          symbol: 'BTCUSDT',
          kind: ExchangeOrderKind.conditional,
          actualOrderId: '11',
          status: 'TRIGGERED',
          createdAt: 42,
          nativeRecord: <String, Object?>{
            'algoId': '900',
            'actualOrderId': '11',
            'algoStatus': 'TRIGGERED',
            'createTime': 42,
          },
        );
        final otherSymbolParent = _futuresOrder(
          id: '901',
          symbol: 'ETHUSDT',
          kind: ExchangeOrderKind.conditional,
          actualOrderId: '11',
        );
        final zeroIdParent = _futuresOrder(
          id: '902',
          symbol: 'BTCUSDT',
          kind: ExchangeOrderKind.conditional,
          actualOrderId: '0',
        );

        final linked = linkConditionalExecutions(<ExchangeOrder>[
          ordinary,
          matchingParent,
          otherSymbolParent,
          zeroIdParent,
        ]);

        expect(linked, hasLength(3));
        final execution = linked.singleWhere(
          (row) => row.kind == ExchangeOrderKind.ordinary,
        );
        expect(execution.conditionalParentId, '900');
        expect(execution.conditionalParent?.actualOrderId, '11');
        expect(execution.conditionalParent?.status, 'TRIGGERED');
        expect(execution.conditionalParent?.createdAtMilliseconds, 42);
        expect(
          (execution.conditionalParent?.nativeRecord as Map)['algoId'],
          '900',
        );
        expect(execution.executedQuantity.value?.text, '2');
        final unlinked = linked.where(
          (row) => row.kind == ExchangeOrderKind.conditional,
        );
        expect(unlinked, hasLength(2));
        expect(
          unlinked.every((row) => row.countsTowardExecution == false),
          isTrue,
        );
        expect(
          unlinked.every((row) => row.executedQuantity.isAvailable == false),
          isTrue,
        );
        expect(
          unlinked.every((row) => row.quoteAmount.isAvailable == false),
          isTrue,
        );
      },
    );

    test(
      'unknown Futures product or side stays unknown and non-USDT rows are excluded',
      () async {
        final data = _newBinance((call) async {
          switch (call.path) {
            case '/fapi/v1/exchangeInfo':
              return <String, Object?>{'symbols': <Object?>[]};
            case '/fapi/v3/positionRisk':
              return <Object?>[
                <String, Object?>{
                  'symbol': 'UNKNOWNUSDT',
                  'positionAmt': '1',
                  'marginAsset': 'USDT',
                },
                <String, Object?>{
                  'symbol': 'UNSUPPORTEDBUSD',
                  'positionAmt': '2',
                  'marginAsset': 'BUSD',
                  'positionSide': 'BOTH',
                },
              ];
            case '/fapi/v1/symbolConfig':
              return <Object?>[];
            default:
              throw StateError('Unexpected endpoint: ' + call.path);
          }
        });
        addTearDown(data.dispose);

        final issues = <ExchangeReadIssue>[];
        final positions = await data.reader.getFuturesPositions(issues: issues);

        expect(positions, hasLength(1));
        expect(positions.single.product, isNull);
        expect(positions.single.side, ExchangePositionSide.unknown);
        expect(positions.single.effectiveDirection, isNull);
        expect(
          issues.map((issue) => issue.code),
          containsAll(<String>[
            'binance_symbol_config_unavailable',
            'binance_position_metadata_unknown',
            'binance_non_usdt_or_unknown_position',
          ]),
        );
      },
    );

    test(
      'open-order symbols join the current credential generation catalog',
      () async {
        final data = _newBinance((call) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return <String, Object?>{
              'symbols': <Object?>[_spotCatalogRow('BTCUSDT', 'BTC', 'USDT')],
            };
          }
          if (call.path == '/api/v3/openOrders') {
            return <Object?>[
              <String, Object?>{
                'symbol': 'LTCBTC',
                'orderId': 17,
                'side': 'buy',
                'status': 'NEW',
                'origQty': '2',
                'executedQty': '0',
                'cummulativeQuoteQty': '0',
                'price': '0.01',
                'time': 100,
              },
            ];
          }
          throw StateError('Unexpected endpoint: ' + call.path);
        });
        addTearDown(data.dispose);

        final orders = await data.reader.getSpotOpenOrders();
        final catalog = await data.reader.getSpotCatalog();

        expect(orders.single.symbol, 'LTCBTC');
        expect(
          catalog.instruments.map((instrument) => instrument.symbol),
          containsAll(<String>['BTCUSDT', 'LTCBTC']),
        );
        expect(
          catalog.instruments
              .singleWhere((instrument) => instrument.symbol == 'LTCBTC')
              .quoteAsset
              .isAvailable,
          isFalse,
        );
      },
    );

    test(
      'unknown Futures open-order metadata stays unknown and marks coverage',
      () async {
        final data = _newBinance((call) async {
          switch (call.path) {
            case '/fapi/v1/exchangeInfo':
              return <String, Object?>{'symbols': <Object?>[]};
            case '/fapi/v1/openOrders':
              return <Object?>[
                <String, Object?>{
                  'symbol': 'ODDUSDT',
                  'orderId': 27,
                  'side': 'buy',
                  'type': 'LIMIT',
                  'status': 'NEW',
                  'origQty': '1',
                  'executedQty': '0',
                  'cumQuote': '0',
                  'price': '100',
                  'avgPrice': '0',
                  'time': 10,
                },
              ];
            case '/fapi/v1/openAlgoOrders':
              return const <Object?>[];
            default:
              throw StateError('Unexpected endpoint: ' + call.path);
          }
        });
        addTearDown(data.dispose);

        final orders = await data.reader.getFuturesOpenOrders();
        final catalog = await data.reader.getFuturesCatalog();

        expect(orders.single.product, isNull);
        expect(orders.single.price?.isAvailable, isFalse);
        expect(
          catalog.instruments.map((instrument) => instrument.symbol),
          isNot(contains('ODDUSDT')),
        );
        expect(
          catalog.issues.any(
            (issue) =>
                issue.code ==
                    'binance_futures_known_symbol_metadata_unavailable' &&
                issue.instrument == 'ODDUSDT',
          ),
          isTrue,
        );
      },
    );
  });

  group('GREEN-117', () {
    test('Spot reader preserves exact native free and locked units', () async {
      final data = _newBinance((call) async {
        if (call.path == '/api/v3/exchangeInfo') {
          return <String, Object?>{'symbols': <Object?>[]};
        }
        if (call.path == '/api/v3/account') {
          return <String, Object?>{
            'balances': <Object?>[
              <String, Object?>{
                'asset': 'ETH',
                'free': '2.000',
                'locked': '0.500',
              },
            ],
          };
        }
        throw StateError('Unexpected endpoint: ' + call.path);
      });
      addTearDown(data.dispose);

      final account = await data.reader.getSpotAccount();

      expect(account.balances.single.free.value?.text, '2.000');
      expect(account.balances.single.locked.value?.text, '0.500');
      expect(account.balances.single.availableTotal.value?.text, '2.5');
      expect(account.reportedEquity.isAvailable, isFalse);
      expect(data.client.calls.take(2).map((call) => call.path), <String>[
        '/api/v3/exchangeInfo',
        '/api/v3/account',
      ]);
    });

    test(
      'Futures reader keeps native equity denomination and nonzero hedge rows',
      () async {
        final data = _newBinance((call) async {
          switch (call.path) {
            case '/fapi/v1/multiAssetsMargin':
              return <String, Object?>{'multiAssetsMargin': true};
            case '/fapi/v3/account':
              return <String, Object?>{
                'totalMarginBalance': '45.00',
                'totalUnrealizedProfit': '5.00',
                'assets': <Object?>[
                  <String, Object?>{
                    'asset': 'USDT',
                    'walletBalance': '40.00',
                    'availableBalance': '35.00',
                  },
                ],
              };
            case '/fapi/v1/exchangeInfo':
              return <String, Object?>{
                'symbols': <Object?>[
                  _futuresCatalogRow('BTCUSDT', 'PERPETUAL'),
                ],
              };
            case '/fapi/v3/positionRisk':
              return <Object?>[
                _positionRow('BTCUSDT', '1.000', 'LONG'),
                _positionRow('BTCUSDT', '-2.000', 'SHORT'),
                _positionRow('BTCUSDT', '0', 'BOTH'),
              ];
            case '/fapi/v1/symbolConfig':
              return <Object?>[
                <String, Object?>{
                  'symbol': 'BTCUSDT',
                  'marginType': 'cross',
                  'leverage': '10',
                },
              ];
            default:
              throw StateError('Unexpected endpoint: ' + call.path);
          }
        });
        addTearDown(data.dispose);

        final account = await data.reader.getFuturesAccount();

        expect(account.reportedEquity.value?.toString(), '45.00 USD');
        expect(account.unrealizedPnl.value?.toString(), '5.00 USD');
        expect(account.equityIncludesUnrealizedPnl, isTrue);
        expect(account.positions, hasLength(2));
        expect(
          account.positions.map((position) => position.side).toSet(),
          <ExchangePositionSide>{
            ExchangePositionSide.long,
            ExchangePositionSide.short,
          },
        );
        expect(
          account.positions.every(
            (position) => position.product == ExchangeProduct.swap,
          ),
          isTrue,
        );
        expect(
          account.positions.every(
            (position) => position.marginMode.value == 'cross',
          ),
          isTrue,
        );
        expect(
          account.positions.every(
            (position) => position.leverage.value?.text == '10',
          ),
          isTrue,
        );
        expect(account.issues, isEmpty);
        expect(data.client.calls.first.path, '/fapi/v1/exchangeInfo');
      },
    );

    test(
      'Futures order prices prefer native price and avoid a fabricated zero',
      () async {
        final data = _newBinance((call) async {
          switch (call.path) {
            case '/fapi/v1/exchangeInfo':
              return <String, Object?>{
                'symbols': <Object?>[
                  _futuresCatalogRow('BTCUSDT', 'PERPETUAL'),
                ],
              };
            case '/fapi/v1/openOrders':
              return <Object?>[
                <String, Object?>{
                  'symbol': 'BTCUSDT',
                  'orderId': 1,
                  'side': 'buy',
                  'type': 'LIMIT',
                  'status': 'NEW',
                  'origQty': '1',
                  'executedQty': '0',
                  'cumQuote': '0',
                  'price': '100',
                  'avgPrice': '0',
                  'time': 10,
                },
                <String, Object?>{
                  'symbol': 'BTCUSDT',
                  'orderId': 2,
                  'side': 'buy',
                  'type': 'MARKET',
                  'status': 'FILLED',
                  'origQty': '2',
                  'executedQty': '2',
                  'cumQuote': '220',
                  'price': '0',
                  'avgPrice': '110',
                  'time': 20,
                },
                <String, Object?>{
                  'symbol': 'BTCUSDT',
                  'orderId': 3,
                  'side': 'buy',
                  'type': 'MARKET',
                  'status': 'NEW',
                  'origQty': '1',
                  'executedQty': '0',
                  'cumQuote': '0',
                  'price': '0',
                  'avgPrice': '0',
                  'time': 30,
                },
              ];
            case '/fapi/v1/openAlgoOrders':
              return const <Object?>[];
            default:
              throw StateError('Unexpected endpoint: ' + call.path);
          }
        });
        addTearDown(data.dispose);

        final orders = await data.reader.getFuturesOpenOrders();
        final byId = <String, ExchangeOrder>{
          for (final order in orders) order.nativeId: order,
        };

        expect(byId['1']!.price?.value?.toString(), '100 USDT');
        expect(byId['1']!.nativeRecord, isA<Map>());
        expect(byId['2']!.price?.value?.toString(), '110 USDT');
        expect(byId['3']!.price?.isAvailable, isFalse);
      },
    );

    test('retains native Futures equity when a positions read fails', () async {
      final data = _newBinance((call) async {
        switch (call.path) {
          case '/fapi/v1/exchangeInfo':
            return <String, Object?>{'symbols': <Object?>[]};
          case '/fapi/v1/multiAssetsMargin':
            return <String, Object?>{'multiAssetsMargin': false};
          case '/fapi/v3/account':
            return <String, Object?>{
              'totalMarginBalance': '45',
              'totalUnrealizedProfit': '5',
              'assets': <Object?>[],
            };
          case '/fapi/v3/positionRisk':
            return const BinanceDataException(
              code: 'binance_authentication_failed',
              message: 'Binance rejected the API credentials.',
            );
          default:
            throw StateError('Unexpected endpoint: ' + call.path);
        }
      });
      addTearDown(data.dispose);

      final account = await data.reader.getFuturesAccount();

      expect(account.reportedEquity.value?.toString(), '45 USDT');
      expect(account.unrealizedPnl.value?.toString(), '5 USDT');
      expect(account.positions, isEmpty);
      expect(
        account.issues.map((issue) => issue.code),
        contains('binance_futures_positions_unavailable'),
      );
    });

    test(
      'cancellation while Futures risk or config is pending is not partial success',
      () async {
        for (final pendingPath in <String>[
          '/fapi/v3/positionRisk',
          '/fapi/v1/symbolConfig',
        ]) {
          final started = Completer<void>();
          final release = Completer<Object?>();
          final data = _newBinance((call) async {
            switch (call.path) {
              case '/fapi/v1/exchangeInfo':
                return <String, Object?>{
                  'symbols': <Object?>[
                    _futuresCatalogRow('BTCUSDT', 'PERPETUAL'),
                  ],
                };
              case '/fapi/v1/multiAssetsMargin':
                return <String, Object?>{'multiAssetsMargin': false};
              case '/fapi/v3/account':
                return <String, Object?>{
                  'totalMarginBalance': '45',
                  'totalUnrealizedProfit': '5',
                  'assets': <Object?>[],
                };
              case '/fapi/v3/positionRisk':
                if (pendingPath == call.path) {
                  started.complete();
                  return release.future;
                }
                return <Object?>[_positionRow('BTCUSDT', '1', 'BOTH')];
              case '/fapi/v1/symbolConfig':
                if (pendingPath == call.path) {
                  started.complete();
                  return release.future;
                }
                return <Object?>[
                  <String, Object?>{
                    'symbol': 'BTCUSDT',
                    'leverage': '3',
                    'marginType': 'cross',
                  },
                ];
              default:
                throw StateError('Unexpected endpoint: ' + call.path);
            }
          });
          addTearDown(data.dispose);
          final cancelToken = CancelToken();
          final accountFuture = data.reader.getFuturesAccount(
            cancelToken: cancelToken,
          );

          await started.future;
          cancelToken.cancel('fixture cancellation');
          release.complete(
            pendingPath.endsWith('positionRisk')
                ? <Object?>[_positionRow('BTCUSDT', '1', 'BOTH')]
                : <Object?>[
                    <String, Object?>{
                      'symbol': 'BTCUSDT',
                      'leverage': '3',
                      'marginType': 'cross',
                    },
                  ],
          );

          await expectLater(
            accountFuture,
            throwsA(
              isA<ExchangeReadException>().having(
                (error) => error.code,
                'code',
                'request_cancelled',
              ),
            ),
          );
        }
      },
    );

    test(
      'OKX adapter retains the original action DTO on neutral rows',
      () async {
        final client = _FakeOkxDataClient((path, query) async {
          if (path == '/api/v5/trade/orders-pending') {
            return <String, Object?>{
              'code': '0',
              'data': <Object?>[
                <String, Object?>{
                  'instId': 'BTC-USDT',
                  'instType': 'SPOT',
                  'ordId': '7',
                  'side': 'buy',
                  'state': 'live',
                  'sz': '1.00',
                  'accFillSz': '0',
                  'fillNotionalUsd': '0',
                  'px': '100',
                  'cTime': '10',
                },
              ],
            };
          }
          throw StateError('Unexpected endpoint: ' + path);
        });
        addTearDown(client.dispose);
        final reader = OkxExchangeReader(
          portfolioRepository: PortfolioRepository(client),
          orderRepository: OrderRepository(client),
        );

        final rows = await reader.getPendingOrders(instType: 'SPOT');

        expect(rows.single.source, ExchangeSource.okx);
        expect(rows.single.nativeRecord, isA<OkxOrder>());
        expect(rows.single.okxActionDto, same(rows.single.nativeRecord));
        expect(rows.single.product, ExchangeProduct.spot);
      },
    );

    test(
      'unknown OKX product and position side remain explicitly unknown',
      () async {
        final client = _FakeOkxDataClient((path, query) async {
          if (path == '/api/v5/account/positions') {
            return <String, Object?>{
              'code': '0',
              'data': <Object?>[
                <String, Object?>{
                  'instId': 'CUSTOM-PAIR',
                  'instType': 'CUSTOM',
                  'posSide': 'unexpected',
                  'pos': '1',
                  'avgPx': '10',
                  'markPx': '11',
                  'lever': '2',
                  'upl': '1',
                  'mgnMode': 'cross',
                  'marginCurrency': 'USDT',
                  'positionId': 'position-7',
                },
              ],
            };
          }
          throw StateError('Unexpected endpoint: ' + path);
        });
        addTearDown(client.dispose);
        final reader = OkxExchangeReader(
          portfolioRepository: PortfolioRepository(client),
          orderRepository: OrderRepository(client),
        );

        final positions = await reader.getOpenPositions();

        expect(positions, hasLength(1));
        expect(positions.single.product, isNull);
        expect(positions.single.side, ExchangePositionSide.unknown);
        expect(positions.single.effectiveDirection, isNull);
        expect(positions.single.nativeRecord, isA<OkxPosition>());
      },
    );
  });

  group('GREEN-120 Binance Spot catalog and order behavior', () {
    test(
      'portfolio catalog reuse expires after 60 minutes and fences generations',
      () async {
        var now = DateTime.utc(2026, 10, 27);
        final data = _newBinance((call) async {
          if (call.path == '/api/v3/exchangeInfo') {
            return <String, Object?>{
              'symbols': <Object?>[_spotCatalogRow('BTCUSDT', 'BTC', 'USDT')],
            };
          }
          throw StateError('Unexpected endpoint: ${call.path}');
        }, clock: () => now);
        addTearDown(data.dispose);
        final generationOne = data.credentialState.value;

        await data.reader.getSpotCatalog(
          expectedGeneration: generationOne,
          reuseForPortfolio: true,
        );
        await data.reader.getSpotCatalog(
          expectedGeneration: generationOne,
          reuseForPortfolio: true,
        );
        expect(
          data.client.calls.where(
            (call) => call.path == '/api/v3/exchangeInfo',
          ),
          hasLength(1),
        );

        await data.reader.getSpotCatalog(expectedGeneration: generationOne);
        await data.reader.getSpotCatalog(
          expectedGeneration: generationOne,
          knownSymbols: const <String>['DELISTEDBTC'],
          reuseForPortfolio: true,
        );
        expect(
          data.client.calls.where(
            (call) => call.path == '/api/v3/exchangeInfo',
          ),
          hasLength(3),
        );

        now = now.add(const Duration(minutes: 61));
        await data.reader.getSpotCatalog(
          expectedGeneration: generationOne,
          reuseForPortfolio: true,
        );
        expect(
          data.client.calls.where(
            (call) => call.path == '/api/v3/exchangeInfo',
          ),
          hasLength(4),
        );

        final generationTwo = BinanceCredentialSnapshot(
          generation: generationOne.generation + 1,
          rotating: false,
          privateReadsEnabled: true,
        );
        data.credentialState.value = generationTwo;
        await data.reader.getSpotCatalog(
          expectedGeneration: generationTwo,
          reuseForPortfolio: true,
        );
        expect(
          data.client.calls.where(
            (call) => call.path == '/api/v3/exchangeInfo',
          ),
          hasLength(5),
        );
      },
    );

    test('a Spot history scan still fetches its own fresh catalog', () async {
      final data = _newBinance((call) async {
        switch (call.path) {
          case '/api/v3/exchangeInfo':
            return <String, Object?>{
              'symbols': <Object?>[_spotCatalogRow('BTCUSDT', 'BTC', 'USDT')],
            };
          case '/api/v3/allOrders':
            return <Object?>[];
          default:
            throw StateError('Unexpected endpoint: ${call.path}');
        }
      });
      addTearDown(data.dispose);
      final history = BinanceHistoryScanService(
        reader: data.reader,
        requestCoordinator: data.requestCoordinator,
      );
      addTearDown(history.dispose);

      await data.reader.getSpotCatalog(reuseForPortfolio: true);
      final progress = await history.startSpotScan().run();

      expect(progress.state, BinanceHistoryScanState.complete);
      expect(
        data.client.calls.where((call) => call.path == '/api/v3/exchangeInfo'),
        hasLength(2),
      );
      expect(
        data.client.calls.where((call) => call.path == '/api/v3/allOrders'),
        hasLength(1),
      );
    });

    test(
      'Spot prices require a positive native amount and a known quote asset',
      () async {
        final data = _newBinance((call) async {
          switch (call.path) {
            case '/api/v3/exchangeInfo':
              return <String, Object?>{
                'symbols': <Object?>[_spotCatalogRow('BTCUSDT', 'BTC', 'USDT')],
              };
            case '/api/v3/openOrders':
              return <Object?>[
                _spotOrderRow('1', 'BTCUSDT', 'MARKET', '0.00000000'),
                _spotOrderRow('2', 'BTCUSDT', 'LIMIT', '100.25'),
                _spotOrderRow('3', 'UNKNOWNPAIR', 'LIMIT', '100.25'),
              ];
            default:
              throw StateError('Unexpected endpoint: ${call.path}');
          }
        });
        addTearDown(data.dispose);

        final orders = await data.reader.getSpotOpenOrders();
        final market = orders.singleWhere((order) => order.nativeId == '1');
        final limit = orders.singleWhere((order) => order.nativeId == '2');
        final unknownQuote = orders.singleWhere(
          (order) => order.nativeId == '3',
        );

        expect(market.price?.isAvailable, isFalse);
        expect(market.price?.reason, isNotEmpty);
        expect(limit.price?.value?.amount.text, '100.25');
        expect(limit.price?.value?.currency, 'USDT');
        expect(unknownQuote.price?.isAvailable, isFalse);
        expect(unknownQuote.price?.reason, isNotEmpty);
      },
    );
  });
}

Map<String, Object?> _spotOrderRow(
  String id,
  String symbol,
  String type,
  String price,
) => <String, Object?>{
  'symbol': symbol,
  'orderId': id,
  'side': 'buy',
  'type': type,
  'status': 'NEW',
  'origQty': '1',
  'executedQty': '0',
  'cummulativeQuoteQty': '0',
  'price': price,
  'time': 10,
};

class _BinanceCall {
  const _BinanceCall({
    required this.path,
    required this.query,
    required this.priority,
    this.cancelToken,
  });

  final String path;
  final Map<String, dynamic> query;
  final BinanceRequestPriority priority;
  final CancelToken? cancelToken;
}

typedef _BinanceHandler = Future<Object?> Function(_BinanceCall call);

class _FakeBinanceDataClient extends BinanceDataClient {
  _FakeBinanceDataClient(this.handler) : super();

  final _BinanceHandler handler;
  final List<_BinanceCall> calls = <_BinanceCall>[];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    BinanceRequestPriority priority = BinanceRequestPriority.interactive,
  }) async {
    final call = _BinanceCall(
      path: path,
      query: Map<String, dynamic>.of(
        queryParameters ?? const <String, dynamic>{},
      ),
      priority: priority,
      cancelToken: cancelToken,
    );
    calls.add(call);
    final result = await handler(call);
    if (result is BinanceDataException) throw result;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: result,
      statusCode: 200,
    );
  }
}

class _BinanceFixture {
  _BinanceFixture(
    this.client,
    this.reader,
    this.credentialState,
    this.requestCoordinator,
  );

  final _FakeBinanceDataClient client;
  final BinanceExchangeReader reader;
  final ValueNotifier<BinanceCredentialSnapshot> credentialState;
  final BinanceRequestCoordinator requestCoordinator;

  void dispose() {
    reader.dispose();
    client.dispose();
    credentialState.dispose();
  }
}

_BinanceFixture _newBinance(
  _BinanceHandler handler, {
  BinanceExchangeReaderClock? clock,
}) {
  final credentialState = ValueNotifier(
    const BinanceCredentialSnapshot(
      generation: 1,
      rotating: false,
      privateReadsEnabled: true,
    ),
  );
  final client = _FakeBinanceDataClient(handler);
  final requestCoordinator = BinanceRequestCoordinator(
    minimumSpacing: Duration.zero,
    delay: (_) async {},
  );
  final reader = BinanceExchangeReader(
    client: client,
    credentialState: credentialState,
    requestCoordinator: requestCoordinator,
    clock: clock,
  );
  return _BinanceFixture(client, reader, credentialState, requestCoordinator);
}

class _FakeOkxDataClient extends OkxDataClient {
  _FakeOkxDataClient(this.handler) : super();

  final Future<Object?> Function(String path, Map<String, dynamic> query)
  handler;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    data: await handler(
      path,
      Map<String, dynamic>.of(queryParameters ?? const <String, dynamic>{}),
    ),
    statusCode: 200,
  );
}

Map<String, Object?> _spotCatalogRow(
  String symbol,
  String base,
  String quote, {
  bool enabled = true,
}) => <String, Object?>{
  'symbol': symbol,
  'baseAsset': base,
  'quoteAsset': quote,
  'status': 'TRADING',
  'isSpotTradingAllowed': enabled,
};

Map<String, Object?> _futuresCatalogRow(String symbol, String contractType) =>
    <String, Object?>{
      'symbol': symbol,
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'marginAsset': 'USDT',
      'contractType': contractType,
      'status': 'TRADING',
    };

Map<String, Object?> _positionRow(String symbol, String amount, String side) =>
    <String, Object?>{
      'symbol': symbol,
      'positionAmt': amount,
      'positionSide': side,
      'entryPrice': '100',
      'markPrice': '105',
      'unRealizedProfit': '5',
      'marginAsset': 'USDT',
    };

ExchangeOrder _futuresOrder({
  required String id,
  required String symbol,
  required ExchangeOrderKind kind,
  String? actualOrderId,
  String executed = '',
  String quote = '',
  String status = 'NEW',
  int? createdAt = 1,
  Object? nativeRecord,
}) => ExchangeOrder(
  source: ExchangeSource.binance,
  product: ExchangeProduct.futures,
  kind: kind,
  symbol: symbol,
  nativeId: id,
  side: 'buy',
  status: status,
  quantity: const ExchangeValue.unavailable('not set'),
  executedQuantity: executed.isEmpty
      ? const ExchangeValue.unavailable('parent is not an execution')
      : ExchangeValue.available(ExchangeAmount.tryParse(executed)!),
  quoteAmount: quote.isEmpty
      ? const ExchangeValue.unavailable('parent is not an execution')
      : ExchangeValue.available(
          ExchangeMoney(
            amount: ExchangeAmount.tryParse(quote)!,
            currency: 'USDT',
          ),
        ),
  createdAtMilliseconds: createdAt,
  actualOrderId: actualOrderId,
  countsTowardExecution: kind == ExchangeOrderKind.ordinary,
  nativeRecord: nativeRecord,
);
