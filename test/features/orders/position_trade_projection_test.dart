import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/data/okx_position_model.dart';

void main() {
  group('positionFromTradeJson', () {
    test('projects authenticated API display metrics into position cards', () {
      final position = positionFromTradeJson({
        'instrumentId': 'BTC-USDT-SWAP',
        'instrumentType': 'SWAP',
        'positionSide': 'net',
        'size': '2',
        'avgPx': '61000.1',
        'markPx': '61111.2',
        'liqPx': '40000',
        'upl': '-12.5',
        'uplRatio': '-0.05',
        'notionalUsd': '122222.4',
        'lever': '10',
        'marginMode': 'isolated',
        'identity': {'instrumentType': 'SWAP', 'instrumentId': 'BTC-USDT-SWAP'},
        'eligibleActions': {
          'closePosition': {'eligible': true, 'reason': null},
        },
      });

      expect(position.avgPx, '61000.1');
      expect(position.markPx, '61111.2');
      expect(position.liqPx, '40000');
      expect(position.upl, '-12.5');
      expect(position.uplRatio, '-0.05');
      expect(position.notionalUsd, '122222.4');
      expect(position.lever, '10');
      expect(position.identity['instrumentId'], 'BTC-USDT-SWAP');
      expect(position.eligibleActions['closePosition']['eligible'], isTrue);
    });

    test(
      'leaves missing display metrics empty instead of inventing values',
      () {
        final position = positionFromTradeJson({
          'instrumentId': 'BTC-USDT-SWAP',
          'size': '2',
        });

        expect(position.avgPx, isEmpty);
        expect(position.markPx, isEmpty);
        expect(position.liqPx, isEmpty);
        expect(position.upl, isEmpty);
        expect(position.uplRatio, isEmpty);
        expect(position.notionalUsd, isEmpty);
        expect(position.lever, isEmpty);
      },
    );
  });
}
