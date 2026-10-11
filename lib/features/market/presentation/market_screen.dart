// File Name: market_screen.dart
// File Path: lib/features/market/presentation/market_screen.dart
// Note: Màn hình hiển thị Top 50 các đồng coin giao dịch SPOT có Volume lớn nhất

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:trading_balance_f/core/network/backend_data_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import '../../../core/session/connection_scope.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Lấy trạng thái Dark Mode
import '../../connections/presentation/providers/multi_user_provider.dart';

// --- Model dữ liệu nội bộ cho Market ---
class MarketTicker {
  final String instId;
  final double last;
  final double open24h;
  final double vol24h;
  final DateTime? asOf;

  MarketTicker({
    required this.instId,
    required this.last,
    required this.open24h,
    required this.vol24h,
    this.asOf,
  });

  factory MarketTicker.fromJson(Map<String, dynamic> json) {
    return MarketTicker(
      instId: json['instId'] ?? '',
      last: double.tryParse(json['last'] ?? '0') ?? 0,
      open24h: double.tryParse(json['sodUtc0'] ?? '0') ?? 0,
      vol24h:
          double.tryParse(json['volCcy24h'] ?? '0') ?? 0, // Volume quy ra USD
      asOf: _parseOkxTimestamp(json['ts']),
    );
  }

  // Công thức tính % biến động 24h
  double get changePercent =>
      open24h > 0 ? ((last - open24h) / open24h) * 100 : 0.0;
  String get coinSymbol => instId.split('-').first;
}

DateTime? _parseOkxTimestamp(Object? value) {
  if (value == null) return null;
  final raw = value.toString();
  final epochMillis = int.tryParse(raw);
  if (epochMillis != null &&
      epochMillis >= 0 &&
      epochMillis <= 253402300799999) {
    return DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);
  }
  return DateTime.tryParse(raw)?.toUtc();
}

// --- Provider lấy dữ liệu từ API Public của OKX ---
Future<List<MarketTicker>> _loadOkxSpotTickers(
  BackendDataClient client, {
  CancelToken? cancelToken,
}) async {
  final response = await client.get(
    '/api/v5/market/tickers',
    queryParameters: {'instType': 'SPOT'},
    cancelToken: cancelToken,
  );
  if (response.data['code'] == '0') {
    final List<dynamic> data = response.data['data'];
    final tickers = data
        .where(
          (json) => (json['instId'] as String).endsWith('-USDT'),
        ) // Chỉ lấy cặp USDT
        .map((json) => MarketTicker.fromJson(json))
        .where(
          (t) => t.vol24h > 5000000,
        ) // Lọc các coin thanh khoản cao (Volume > 5 triệu USD)
        .toList();

    // Sắp xếp theo volume giảm dần
    tickers.sort((a, b) => b.vol24h.compareTo(a.vol24h));

    return tickers.take(50).toList(); // Lấy Top 50
  } else {
    throw Exception(response.data['msg']);
  }
}

final marketListProvider = FutureProvider.autoDispose<List<MarketTicker>>((
  ref,
) async {
  final isForeground = ref.watch(
    multiUserAppForegroundProvider.select((state) => state.isForeground),
  );
  if (!isForeground) {
    throw const BackendDataException(
      code: 'request_cancelled',
      message: 'Đã tạm dừng cập nhật giá khi ứng dụng ở nền.',
    );
  }
  final cancellation = CancelToken();
  ref.onDispose(() => cancellation.cancel('App entered background.'));
  final result = await _loadOkxSpotTickers(
    ref.watch(backendDataClientProvider),
    cancelToken: cancellation,
  );
  if (!ref.read(multiUserAppForegroundProvider).isForeground) {
    throw const BackendDataException(
      code: 'request_cancelled',
      message: 'Đã tạm dừng cập nhật giá khi ứng dụng ở nền.',
    );
  }
  return result;
});

final scopedMarketListProvider = FutureProvider.autoDispose
    .family<List<MarketTicker>, ConnectionScope>((ref, scope) async {
      final isForeground = ref.watch(
        multiUserAppForegroundProvider.select((state) => state.isForeground),
      );
      if (!isForeground) {
        throw const BackendDataException(
          code: 'request_cancelled',
          message: 'Đã tạm dừng cập nhật giá khi ứng dụng ở nền.',
        );
      }
      final scopes = ref.watch(connectionScopeStoreProvider);
      if (scope.exchange != 'OKX' ||
          scope.product != 'SPOT' ||
          !scopes.matches(scope.generation, scope)) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Nguồn giá không khớp tài khoản đang chọn.',
          statusCode: 409,
        );
      }
      final cancellation = CancelToken();
      ref.onDispose(() => cancellation.cancel('App entered background.'));
      final tickers = await _loadOkxSpotTickers(
        ref.watch(backendDataClientProvider),
        cancelToken: cancellation,
      );
      if (!ref.read(multiUserAppForegroundProvider).isForeground ||
          !scopes.matches(scope.generation, scope)) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Nguồn giá đã đổi theo tài khoản đang chọn.',
          statusCode: 409,
        );
      }
      return tickers;
    });

// --- Giao diện hiển thị (Screen) ---
class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen>
    with WidgetsBindingObserver {
  bool _refreshInFlight = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isForeground) _resumePolling();
  }

  bool get _isForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumePolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _resumePolling() {
    _pollTimer?.cancel();
    if (!_isForeground) {
      _pollTimer = null;
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _refreshInFlight) return;
      final scope = ref.read(connectionScopeStoreProvider).current;
      if (scope != null) {
        if (ref.read(scopedMarketListProvider(scope)).isLoading) return;
        ref.invalidate(scopedMarketListProvider(scope));
      } else {
        if (ref.read(marketListProvider).isLoading) return;
        ref.invalidate(marketListProvider);
      }
    });
  }

  Future<void> _refreshMarket() async {
    if (_refreshInFlight) return;
    setState(() => _refreshInFlight = true);
    try {
      final scope = ref.read(connectionScopeStoreProvider).current;
      if (scope != null) {
        ref.invalidate(scopedMarketListProvider(scope));
        await ref.read(scopedMarketListProvider(scope).future);
      } else {
        ref.invalidate(marketListProvider);
        await ref.read(marketListProvider.future);
      }
    } catch (_) {
      // The watched provider renders the read error.
    } finally {
      if (mounted) setState(() => _refreshInFlight = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(isDarkModeProvider);
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    if (scope != null && (scope.exchange != 'OKX' || scope.product != 'SPOT')) {
      return _UnavailableMarketScope(scope: scope);
    }
    final marketAsync = scope == null
        ? ref.watch(marketListProvider)
        : ref.watch(scopedMarketListProvider(scope));

    final palette = AppPalette.forBrightness(isDark);
    final bgColor = palette.background;
    final textColor = palette.ink;
    final cardColor = palette.raised;
    final borderColor = palette.border;
    final iconBgColor = palette.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Thị trường (Top 50)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        actions: [
          ManualRefreshButton(
            buttonKey: const Key('market-manual-refresh'),
            onRefresh: _refreshMarket,
            isBusy: _refreshInFlight || marketAsync.isLoading,
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: RefreshIndicator(
          color: palette.ink,
          backgroundColor: palette.raised,
          onRefresh: _refreshMarket,
          child: marketAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: textColor)),
            error: (err, stack) => Center(
              child: Text(
                'Lỗi tải dữ liệu:\n$err',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.negative),
              ),
            ),
            data: (tickers) {
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.space4,
                  vertical: AppTokens.space2,
                ),
                itemCount: tickers.length,
                itemBuilder: (context, index) {
                  final t = tickers[index];
                  final currentPrice = t.last;

                  // Tính toán lại % biến động dựa trên giá Live mới nhất
                  final double currentChangePercent = t.open24h > 0
                      ? ((currentPrice - t.open24h) / t.open24h) * 100
                      : 0.0;

                  final isPositive = currentChangePercent >= 0;
                  final changeColor = isPositive
                      ? palette.positive
                      : palette.negative;
                  final changeSign = isPositive ? '+' : '';
                  final volFormatted =
                      '\$${(t.vol24h / 1000000).toStringAsFixed(2)}M';
                  final quoteAge = t.asOf == null
                      ? null
                      : DateTime.now().toUtc().difference(t.asOf!);
                  final quoteAgeLabel = quoteAge == null
                      ? 'Thiếu thời điểm báo giá'
                      : quoteAge.isNegative
                      ? 'Thời điểm báo giá chưa hợp lệ'
                      : quoteAge <= const Duration(seconds: 15)
                      ? 'Cập nhật ${quoteAge.inSeconds} giây trước'
                      : 'Báo giá cũ · ${quoteAge.inSeconds} giây';
                  final quoteFresh =
                      quoteAge != null &&
                      !quoteAge.isNegative &&
                      quoteAge <= const Duration(seconds: 15);

                  // Thông minh hiển thị giá: Nếu coin rác (< $1) thì hiện nhiều số thập phân
                  String priceFormatted;
                  if (currentPrice < 1) {
                    priceFormatted = NumberFormat(
                      "#,##0.00####",
                      "en_US",
                    ).format(currentPrice);
                  } else {
                    priceFormatted = NumberFormat(
                      "#,##0.00",
                      "en_US",
                    ).format(currentPrice);
                  }

                  return Card(
                    elevation: 0,
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: AppTokens.space2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTokens.radiusMedium,
                      ),
                      side: BorderSide(color: borderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space3,
                        vertical: AppTokens.space3,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final coinIdentity = Row(
                            children: [
                              CryptoIcon(
                                symbol: t.coinSymbol,
                                size: 36,
                                backgroundColor: iconBgColor,
                                textColor: textColor,
                                textSize: 14,
                              ),
                              const SizedBox(width: AppTokens.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.coinSymbol,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: AppTokens.space1),
                                    Text(
                                      quoteFresh
                                          ? 'OKX SPOT · Vol 24h: $volFormatted'
                                          : 'OKX SPOT · Khối lượng chưa khả dụng',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      quoteAgeLabel,
                                      key: Key('market-quote-age-${t.instId}'),
                                      style: TextStyle(
                                        color: quoteFresh
                                            ? palette.muted
                                            : palette.warning,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                          final quote = Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                quoteFresh
                                    ? '\$$priceFormatted'
                                    : 'Giá chưa khả dụng',
                                key: Key('market-quote-value-${t.instId}'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: quoteFresh
                                      ? textColor
                                      : palette.warning,
                                ),
                              ),
                              if (quoteFresh) ...[
                                const SizedBox(height: AppTokens.space2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.space2,
                                    vertical: AppTokens.space1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: changeColor,
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.radiusSmall,
                                    ),
                                  ),
                                  child: Text(
                                    '$changeSign${currentChangePercent.toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      color: palette.onStrong,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );

                          if (constraints.maxWidth < 400) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                coinIdentity,
                                const SizedBox(height: AppTokens.space2),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: quote,
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: coinIdentity),
                              const SizedBox(width: AppTokens.space3),
                              quote,
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UnavailableMarketScope extends StatelessWidget {
  const _UnavailableMarketScope({required this.scope});

  final ConnectionScope scope;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thị trường')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space4),
        child: Text(
          scope.exchange == 'BINANCE'
              ? 'Bảng giá công khai hiện được xác minh cho OKX SPOT. Dữ liệu Binance chưa khả dụng cho kết nối ${scope.environment} ${scope.product} này.'
              : 'Bảng giá công khai này chỉ hỗ trợ OKX SPOT. Sản phẩm ${scope.product} của kết nối hiện tại không được trộn với báo giá SPOT.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
