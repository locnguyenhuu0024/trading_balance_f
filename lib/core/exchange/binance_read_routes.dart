enum BinanceHost {
  spot('api.binance.com'),
  futures('fapi.binance.com');

  const BinanceHost(this.domain);

  final String domain;

  String get origin => 'https://$domain';
}

/// Exact public and signed read routes shared by the Binance transport and
/// host-level scheduler.
class BinanceReadRoute {
  const BinanceReadRoute({
    required this.host,
    required this.path,
    required this.weight,
    required this.signed,
    this.bootstrap = false,
  });

  final BinanceHost host;
  final String path;
  final int weight;
  final bool signed;
  final bool bootstrap;

  int weightFor(Map<String, dynamic> query) {
    if (path == '/api/v3/ticker/24hr') return 2;
    if (path == '/fapi/v1/ticker/24hr') {
      return query.containsKey('symbol') ? 1 : 40;
    }
    if (path == '/api/v3/openOrders') {
      return query.containsKey('symbol') ? 6 : 80;
    }
    if (path == '/fapi/v1/openOrders' || path == '/fapi/v1/openAlgoOrders') {
      return query.containsKey('symbol') ? 1 : 40;
    }
    return weight;
  }

  /// Query policies intentionally exclude caller-provided signing fields.
  bool acceptsQuery(Map<String, dynamic> query) {
    if (query.values.any((value) => value == null)) return false;
    if (path.endsWith('/time') || path.endsWith('/exchangeInfo')) {
      return query.isEmpty;
    }
    if (path == '/api/v3/ticker/24hr') {
      if (query.length != 1) return false;
      if (query['symbol'] case final String symbol) {
        return symbol.trim().isNotEmpty;
      }
      final symbols = query['symbols'];
      return symbols is List &&
          symbols.isNotEmpty &&
          symbols.length <= 20 &&
          symbols.every((value) => value is String && value.trim().isNotEmpty);
    }
    if (path == '/fapi/v1/ticker/24hr') {
      return query.isEmpty ||
          (query.length == 1 &&
              query['symbol'] is String &&
              (query['symbol'] as String).trim().isNotEmpty);
    }
    if (path == '/api/v3/openOrders' ||
        path == '/fapi/v1/openOrders' ||
        path == '/fapi/v1/openAlgoOrders') {
      return _optionalSymbol(query);
    }
    if (path == '/api/v3/allOrders' ||
        path == '/fapi/v1/allOrders' ||
        path == '/fapi/v1/allAlgoOrders') {
      return _requiredSymbolWithRecentLimit(query);
    }
    // Private account and configuration snapshots take only the internally
    // generated timestamp and recvWindow parameters.
    return signed && query.isEmpty;
  }

  bool _optionalSymbol(Map<String, dynamic> query) =>
      query.isEmpty ||
      (query.length == 1 &&
          query['symbol'] is String &&
          (query['symbol'] as String).trim().isNotEmpty);

  bool _requiredSymbolWithRecentLimit(Map<String, dynamic> query) {
    if (!query.containsKey('symbol') ||
        query['symbol'] is! String ||
        (query['symbol'] as String).trim().isEmpty) {
      return false;
    }
    if (query.keys.any((key) => key != 'symbol' && key != 'limit')) {
      return false;
    }
    final limit = query['limit'];
    return limit != null && limit.toString() == '500';
  }
}

class BinanceReadRoutes {
  static const List<BinanceReadRoute> all = <BinanceReadRoute>[
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/time',
      weight: 1,
      signed: false,
      bootstrap: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/exchangeInfo',
      weight: 20,
      signed: false,
      bootstrap: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/ticker/24hr',
      weight: 2,
      signed: false,
    ),
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/account',
      weight: 20,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/openOrders',
      weight: 80,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.spot,
      path: '/api/v3/allOrders',
      weight: 20,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/time',
      weight: 1,
      signed: false,
      bootstrap: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/exchangeInfo',
      weight: 1,
      signed: false,
      bootstrap: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/ticker/24hr',
      weight: 40,
      signed: false,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v3/account',
      weight: 5,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v3/positionRisk',
      weight: 5,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/symbolConfig',
      weight: 5,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/multiAssetsMargin',
      weight: 30,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/openOrders',
      weight: 40,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/openAlgoOrders',
      weight: 40,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/allOrders',
      weight: 5,
      signed: true,
    ),
    BinanceReadRoute(
      host: BinanceHost.futures,
      path: '/fapi/v1/allAlgoOrders',
      weight: 5,
      signed: true,
    ),
  ];

  static final Map<String, BinanceReadRoute> _byPath =
      <String, BinanceReadRoute>{for (final route in all) route.path: route};

  static BinanceReadRoute? forPath(String path) => _byPath[path];
}
