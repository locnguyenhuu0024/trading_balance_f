// File Name: portfolio_screen.dart
// File Path: lib/features/portfolio/presentation/portfolio_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/currency/currency_display_mode.dart';
import '../../../core/exchange/exchange_account_providers.dart';
import '../../../core/exchange/exchange_models.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/platform_brightness_provider.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/exchange_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/okx_balance_model.dart';
import 'widgets/portfolio_currency_amount.dart';

final hideBalanceProvider = StateProvider<bool>((ref) => false);

final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.dark) return true;
  if (mode == ThemeMode.light) return false;
  return ref.watch(
    platformBrightnessProvider.select((observer) => observer.isDark),
  );
});

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  bool _portfolioRefreshInFlight = false;
  bool _pageRefreshInFlight = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshPortfolio(automatic: true));
    });
  }

  Future<void> _refreshPortfolio({bool automatic = false}) async {
    if (!mounted || _portfolioRefreshInFlight) {
      return;
    }
    _portfolioRefreshInFlight = true;
    invalidateCombinedPortfolioSources(ref, force: !automatic);
    if (mounted) _portfolioRefreshInFlight = false;
  }

  Future<void> _refreshPortfolioAndRate() async {
    if (!mounted || _portfolioRefreshInFlight || _pageRefreshInFlight) {
      return;
    }
    setState(() => _pageRefreshInFlight = true);
    final refreshRate = () async {
      try {
        final rate = ref.read(vndExchangeRateProvider);
        if (rate.isLoading) {
          await ref.read(vndExchangeRateProvider.future);
        } else {
          ref.invalidate(vndExchangeRateProvider);
          await ref.read(vndExchangeRateProvider.future);
        }
      } catch (_) {
        // The exchange-rate provider keeps its local fallback available.
      }
    };
    final rateRefresh = refreshRate();
    try {
      await _refreshPortfolio();
      await rateRefresh;
    } finally {
      if (mounted) setState(() => _pageRefreshInFlight = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(combinedExchangePortfolioProvider);

    final isBalanceHidden = ref.watch(hideBalanceProvider);
    final isDark = ref.watch(isDarkModeProvider);
    final currency = ref.watch(currencyProvider);

    final exchangeRateAsync = ref.watch(vndExchangeRateProvider);
    final exchangeRate = exchangeRateAsync.value ?? 25400.0;

    final palette = AppPalette.of(context);
    final bgColor = palette.background;
    final textColor = palette.ink;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          ManualRefreshButton(
            buttonKey: const Key('portfolio-manual-refresh'),
            onRefresh: _refreshPortfolioAndRate,
            isBusy: _pageRefreshInFlight || _portfolioRefreshInFlight,
          ),
          IconButton(
            icon: Icon(
              isBalanceHidden ? Icons.visibility_off : Icons.visibility,
              size: 22,
            ),
            tooltip: isBalanceHidden ? 'Hiện số dư' : 'Ẩn số dư',
            onPressed: () {
              ref.read(hideBalanceProvider.notifier).state = !isBalanceHidden;
            },
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: RefreshIndicator(
          color: palette.ink,
          backgroundColor: palette.raised,
          onRefresh: _refreshPortfolioAndRate,
          child: _buildCombinedPortfolioData(
            portfolio,
            isHidden: isBalanceHidden,
            isDark: isDark,
            currency: currency,
            exchangeRate: exchangeRate,
          ),
        ),
      ),
    );
  }

  String _obfuscate(String value, bool isHidden) {
    return isHidden ? '******' : value;
  }

  Widget _buildCombinedPortfolioData(
    CombinedExchangePortfolio portfolio, {
    required bool isHidden,
    required bool isDark,
    required String currency,
    required double exchangeRate,
  }) {
    final palette = AppPalette.forBrightness(isDark);
    final total = portfolio.totalEquity.value?.finiteDouble;
    final rows = portfolio.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCombinedSummary(
          portfolio,
          total: total,
          isHidden: isHidden,
          currency: currency,
          exchangeRate: exchangeRate,
          palette: palette,
        ),
        Divider(height: 1, indent: 16, endIndent: 16, color: palette.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Tài sản chi tiết',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: palette.ink,
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: portfolio.isLoading
                      ? CircularProgressIndicator(color: palette.ink)
                      : Text(
                          portfolio.sources.every(
                                (source) => !source.isAvailable,
                              )
                              ? 'Không có dữ liệu tài khoản. Kiểm tra khóa API đã lưu rồi thử làm mới.'
                              : 'Không có tài sản nào.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                )
              : ListView.builder(
                  key: const Key('combined-portfolio-assets'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final balance = row.balance;
                    final amount = row.totalAmount.value;
                    final valuation = row.valuation.value;
                    final sourceLabel = _portfolioSourceLabel(balance);
                    final amountLabel = amount == null
                        ? 'Số dư chưa có dữ liệu'
                        : 'Số dư ${_obfuscate('${amount.text} ${balance.asset}', isHidden)}';
                    final free = balance.free.value?.text ?? '--';
                    final locked = balance.locked.value?.text ?? '--';
                    final iconBackground = palette.surface;
                    return Card(
                      key: ValueKey(
                        '${balance.source.name}|${balance.product?.name ?? 'unified'}|${balance.wallet}|${balance.asset}',
                      ),
                      elevation: 0,
                      color: palette.raised,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusMedium,
                        ),
                        side: BorderSide(color: palette.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 42,
                              height: 38,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CryptoIcon(
                                    symbol: balance.asset,
                                    size: 32,
                                    backgroundColor: iconBackground,
                                    textColor: palette.ink,
                                    textSize: 12,
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: ExchangeIcon(
                                      source: balance.source,
                                      size: 17,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    balance.asset,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: palette.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sourceLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    amountLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _obfuscate(
                                      'Free $free · Locked $locked',
                                      isHidden,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (row.quote != null)
                                    Text(
                                      'Giá ${row.quote!.price.text} ${row.quote!.quoteCurrency} · ${balance.source.name.toUpperCase()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 116,
                              child: Align(
                                alignment: AlignmentDirectional.topEnd,
                                child:
                                    valuation == null ||
                                        valuation.amount.finiteDouble == null
                                    ? Text(
                                        isHidden ? '******' : '--',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      )
                                    : PortfolioCurrencyAmount(
                                        usdtAmount:
                                            valuation.amount.finiteDouble!,
                                        currencyMode: currency,
                                        vndRate: exchangeRate,
                                        hidden: isHidden,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        textAlign: TextAlign.right,
                                        primaryStyle: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: palette.ink,
                                        ),
                                        secondaryStyle: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: palette.muted,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCombinedSummary(
    CombinedExchangePortfolio portfolio, {
    required double? total,
    required bool isHidden,
    required String currency,
    required double exchangeRate,
    required AppPalette palette,
  }) {
    final amount = total;
    final okxBreakdown = _okxBreakdown(portfolio);
    return Padding(
      key: const Key('portfolio-asset-summary'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng tài sản (${CurrencyDisplayMode.labelFor(currency)})',
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (amount == null)
            Text(
              isHidden ? '******' : (portfolio.isLoading ? 'Loading…' : '--'),
              style: TextStyle(
                color: palette.ink,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            PortfolioCurrencyAmount(
              usdtAmount: amount,
              currencyMode: currency,
              vndRate: exchangeRate,
              hidden: isHidden,
              primaryStyle: TextStyle(
                color: palette.ink,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              secondaryStyle: TextStyle(
                color: palette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 8),
          if (portfolio.isPartial)
            Semantics(
              liveRegion: true,
              child: Text(
                'Tổng chưa đầy đủ. Một số tài khoản hoặc giá định giá chưa có dữ liệu.',
                key: const Key('portfolio-partial-warning'),
                style: TextStyle(color: palette.warning, fontSize: 12),
              ),
            )
          else
            Text(
              'Dữ liệu tài khoản và định giá đã tải đầy đủ.',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          for (final warning in portfolio.warnings.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final source in portfolio.sources)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExchangeIcon(source: source.source, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      '${_accountSourceLabel(source)} · ${source.isAvailable ? (source.isComplete ? 'OK' : 'Partial') : 'Unavailable'}',
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          if (okxBreakdown != null)
            _buildOkxPerformanceSummary(
              capital: okxBreakdown.capital,
              pnl: okxBreakdown.pnl,
              pnlRatio: okxBreakdown.pnlRatio,
              isHidden: isHidden,
              currency: currency,
              exchangeRate: exchangeRate,
              palette: palette,
            ),
        ],
      ),
    );
  }

  ({double capital, double pnl, double pnlRatio})? _okxBreakdown(
    CombinedExchangePortfolio portfolio,
  ) {
    ExchangeAccountSnapshot? account;
    for (final source in portfolio.sources) {
      if (source.source == ExchangeSource.okx && source.account != null) {
        account = source.account;
        break;
      }
    }
    if (account == null) return null;

    final equity = account.reportedEquity.value;
    if (equity == null ||
        !{'USD', 'USDT'}.contains(equity.currency.toUpperCase())) {
      return null;
    }
    final totalEquity = equity.amount.finiteDouble;
    if (totalEquity == null) return null;

    double? pnl = account.unrealizedPnl.value?.amount.finiteDouble;
    final accountPnl = account.unrealizedPnl.value;
    if (accountPnl != null &&
        !{'USD', 'USDT'}.contains(accountPnl.currency.toUpperCase())) {
      pnl = null;
    }
    if (pnl == null) {
      var sum = 0.0;
      var foundNativePnl = false;
      for (final row in portfolio.rows) {
        if (row.balance.source != ExchangeSource.okx) continue;
        final detail = row.balance.nativeRecord;
        final units = row.totalAmount.value?.finiteDouble;
        final valuation = row.valuation.value?.amount.finiteDouble;
        final nativePnl = detail is OkxCoinDetail
            ? double.tryParse(detail.upl)
            : null;
        if (detail is! OkxCoinDetail ||
            nativePnl == null ||
            units == null ||
            valuation == null) {
          return null;
        }
        if (units == 0) {
          if (nativePnl == 0) continue;
          return null;
        }
        sum += nativePnl * valuation / units;
        foundNativePnl = true;
      }
      if (foundNativePnl) pnl = sum;
    }
    if (pnl == null || !pnl.isFinite) return null;

    final capital = account.equityIncludesUnrealizedPnl
        ? totalEquity - pnl
        : totalEquity;
    final pnlRatio = capital > 0 ? pnl / capital * 100 : 0.0;
    if (!capital.isFinite || !pnlRatio.isFinite) return null;
    return (capital: capital, pnl: pnl, pnlRatio: pnlRatio);
  }

  Widget _buildOkxPerformanceSummary({
    required double capital,
    required double pnl,
    required double pnlRatio,
    required bool isHidden,
    required String currency,
    required double exchangeRate,
    required AppPalette palette,
  }) {
    final pnlColor = resolvePnlColor(pnl, palette, hidden: isHidden);
    final ratioColor = resolvePnlColor(pnlRatio, palette, hidden: isHidden);
    final pnlSign = pnl >= 0 ? '+' : '';
    return Container(
      key: const Key('portfolio-okx-pnl-summary'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExchangeIcon(source: ExchangeSource.okx, size: 16),
              const SizedBox(width: 5),
              Text(
                'OKX Unified',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vốn gốc',
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                    const SizedBox(height: 3),
                    PortfolioCurrencyAmount(
                      usdtAmount: capital,
                      currencyMode: currency,
                      vndRate: exchangeRate,
                      hidden: isHidden,
                      primaryStyle: TextStyle(
                        color: palette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      secondaryStyle: TextStyle(
                        color: palette.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lãi / lỗ chưa thực hiện',
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                    const SizedBox(height: 3),
                    PortfolioCurrencyAmount(
                      usdtAmount: pnl,
                      currencyMode: currency,
                      vndRate: exchangeRate,
                      hidden: isHidden,
                      showPositiveSign: true,
                      primaryStyle: TextStyle(
                        color: pnlColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      secondaryStyle: TextStyle(
                        color: pnlColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _obfuscate(
                        '($pnlSign${pnlRatio.toStringAsFixed(2)}%)',
                        isHidden,
                      ),
                      style: TextStyle(
                        color: ratioColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _accountSourceLabel(ExchangeAccountResult source) {
    if (source.source == ExchangeSource.okx) return 'OKX Unified';
    return source.product == ExchangeProduct.spot
        ? 'Binance Spot'
        : 'Binance Futures';
  }

  String _portfolioSourceLabel(ExchangeBalance balance) {
    if (balance.source == ExchangeSource.okx) {
      return 'OKX · ${balance.wallet}';
    }
    final product = switch (balance.product) {
      ExchangeProduct.spot => 'Spot',
      ExchangeProduct.swap || ExchangeProduct.futures => 'USDT-M Futures',
      ExchangeProduct.margin => 'Margin',
      null => balance.wallet,
    };
    return 'Binance · $product · ${balance.wallet}';
  }



}
