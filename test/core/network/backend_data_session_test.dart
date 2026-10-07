import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/network/backend_data_session.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';

void main() {
  TradeSession session(String token, {String account = 'account'}) =>
      TradeSession(
        bearerToken: token,
        accountIdentifier: account,
        expiresAt: DateTime.utc(2099),
      );

  test('only semantic session changes advance and synchronously notify', () {
    final first = session('first');
    final shared = BackendDataSession(initialSession: first);
    final events = <int>[];
    shared.changes.listen((_) => events.add(shared.generation));
    final generation = shared.generation;

    shared.update(session('first'));
    expect(shared.generation, generation);
    expect(events, isEmpty);

    shared.update(session('second'));
    expect(shared.generation, generation + 1);
    expect(events, [generation + 1]);
    expect(shared.current?.bearerToken, 'second');

    shared.update(null);
    expect(shared.current, isNull);
    expect(events, [generation + 1, generation + 2]);
    shared.dispose();
  });

  test('dispose advances generation and permanently rejects old results', () {
    final current = session('short-lived');
    final shared = BackendDataSession(initialSession: current);
    final generation = shared.generation;

    shared.dispose();

    expect(shared.generation, generation + 1);
    expect(shared.current, isNull);
    expect(shared.matches(generation, current), isFalse);
    shared.update(session('ignored'));
    expect(shared.current, isNull);
    expect(shared.generation, generation + 1);
  });

  test('expired sessions are inactive and never become current', () {
    final shared = BackendDataSession(
      initialSession: TradeSession(
        bearerToken: 'expired',
        accountIdentifier: 'account',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );

    expect(shared.current, isNull);
    shared.dispose();
  });
}
