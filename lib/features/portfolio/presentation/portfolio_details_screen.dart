import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/currency/currency_display_mode.dart';
import '../../../core/exchange/exchange_account_providers.dart';
import '../../../core/exchange/exchange_models.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pnl_color.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../../core/widgets/exchange_icon.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/okx_balance_model.dart';
import '../presentation/widgets/portfolio_currency_amount.dart';
import 'providers/portfolio_provider.dart';
import 'portfolio_screen.dart';

/// Opt-in balance view. Portfolio Home intentionally does not render PnL;
/// this screen is the explicit place where a user can reveal it for the
/// current visit.
class PortfolioDetailsScreen extends ConsumerStatefulWidget {
  const PortfolioDetailsScreen({super.key});

  @override
  ConsumerState<PortfolioDetailsScreen> createState() =>
      _PortfolioDetailsScreenState();
}

class _PortfolioDetailsScreenState
    extends ConsumerState<PortfolioDetailsScreen> {
  bool _pnlRevealed = false;
  bool _isRefreshInFlight = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      invalidateCombinedPortfolioSources(ref);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPortfolio() async {
    if (!mounted || _isRefreshInFlight) return;
    setState(() => _isRefreshInFlight = true);
    invalidateCombinedPortfolioSources(ref, force: true);
    if (mounted) setState(() => _isRefreshInFlight = false);
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(combinedExchangePortfolioProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final currency = ref.watch(currencyProvider);
    final rate = ref.watch(vndExchangeRateProvider).value ?? 25400.0;
    final palette = AppPalette.of(context);
    final background = palette.background;
    final foreground = palette.ink;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        title: const Text('Portfolio details'),
        actions: [
          ManualRefreshButton(
            buttonKey: const Key('portfolio-details-manual-refresh'),
            onRefresh: _refreshPortfolio,
            isBusy: _isRefreshInFlight,
          ),
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
            onPressed: () =>
                ref.read(hideBalanceProvider.notifier).state = !hidden,
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: _CombinedDetailsContent(
          portfolio: portfolio,
          currency: currency,
          exchangeRate: rate,
          hidden: hidden,
          pnlRevealed: _pnlRevealed,
          onRevealPnl: () => setState(() => _pnlRevealed = true),
          onRefresh: _refreshPortfolio,
        ),
      ),
    );
  }
}

class _CombinedDetailsContent extends StatelessWidget {
  const _CombinedDetailsContent({
    required this.portfolio,
    required this.currency,
    required this.exchangeRate,
    required this.hidden,
    required this.pnlRevealed,
    required this.onRevealPnl,
    required this.onRefresh,
  });

  final CombinedExchangePortfolio portfolio;
  final String currency;
  final double exchangeRate;
  final bool hidden;
  final bool pnlRevealed;
  final VoidCallback onRevealPnl;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final total = portfolio.totalEquity.value?.finiteDouble;
    return RefreshIndicator(
      color: palette.ink,
      backgroundColor: palette.raised,
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('combined-portfolio-details-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Card(
                key: const Key('portfolio-details-summary'),
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                  side: BorderSide(color: palette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balances · OKX + Binance',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Total assets (${CurrencyDisplayMode.labelFor(currency)})',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (total == null)
                        Text(
                          hidden
                              ? '******'
                              : (portfolio.isLoading ? 'Loading…' : '--'),
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else
                        PortfolioCurrencyAmount(
                          usdtAmount: total,
                          currencyMode: currency,
                          vndRate: exchangeRate,
                          hidden: hidden,
                          primaryStyle: TextStyle(
                            color: palette.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                          secondaryStyle: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (portfolio.isPartial) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'This total is incomplete because some account data or source-specific valuation is unavailable.',
                            key: const Key('portfolio-details-partial-warning'),
                            style: TextStyle(
                              color: palette.warning,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (portfolio.isLoading) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(
                          key: Key('portfolio-details-source-loading'),
                          minHeight: 2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Account PnL by source',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('portfolio-details-reveal-pnl'),
                    onPressed: pnlRevealed ? null : onRevealPnl,
                    child: Text(pnlRevealed ? 'PnL shown' : 'Show PnL'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList.builder(
              itemCount: portfolio.sources.length,
              itemBuilder: (context, index) {
                final source = portfolio.sources[index];
                final pnl = source.account?.unrealizedPnl.value;
                final pnlAmount = pnl?.amount.finiteDouble;
                final accountEquity =
                    source.account?.reportedEquity.value?.amount.finiteDouble;
                final pnlRatio = pnlAmount == null || accountEquity == null
                    ? null
                    : accountEquity - pnlAmount == 0
                    ? null
                    : pnlAmount / (accountEquity - pnlAmount) * 100;
                final pnlColor = resolvePnlColor(pnlAmount, palette);
                final label = _detailsSourceLabel(source);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
                    side: BorderSide(color: palette.border),
                  ),
                  child: ListTile(
                    leading: ExchangeIcon(source: source.source, size: 20),
                    title: Text(label),
                    subtitle: Text(
                      source.error ??
                          (source.isLoading
                              ? 'Loading this account source…'
                              : source.account == null
                              ? 'Account data unavailable.'
                              : source.account!.issues.isEmpty
                              ? 'Account data loaded.'
                              : 'Some account fields are unavailable.'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          !pnlRevealed
                              ? 'Hidden'
                              : pnlAmount == null
                              ? '—'
                              : hidden
                              ? '******'
                              : '${pnlAmount > 0 ? '+' : ''}${pnlAmount.toStringAsFixed(2)} ${pnl!.currency}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: pnlRevealed ? pnlColor : palette.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (pnlRevealed && pnlRatio != null)
                          Text(
                            hidden
                                ? '******'
                                : '(${pnlRatio > 0 ? '+' : ''}${pnlRatio.toStringAsFixed(2)}%)',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: hidden
                                  ? palette.muted
                                  : resolvePnlColor(pnlRatio, palette),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Asset details',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (portfolio.rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  portfolio.isLoading
                      ? 'Account data is still loading.'
                      : portfolio.isPartial
                      ? 'Some account sources are unavailable; an empty asset list is not complete.'
                      : 'No account assets are available.',
                  style: TextStyle(color: palette.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: portfolio.rows.length,
                itemBuilder: (context, index) {
                  final row = portfolio.rows[index];
                  final balance = row.balance;
                  final amount = row.totalAmount.value;
                  final value = row.valuation.value;
                  final sourceLabel = _detailsBalanceLabel(balance);
                  return Card(
                    key: ValueKey(
                      'details:${balance.source.name}:${balance.product?.name}:${balance.wallet}:${balance.asset}',
                    ),
                    elevation: 0,
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
                        children: [
                          CryptoIcon(
                            symbol: balance.asset,
                            size: 30,
                            backgroundColor: palette.surface,
                            textColor: palette.ink,
                            textSize: 12,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  balance.asset,
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Row(
                                  children: [
                                    ExchangeIcon(
                                      source: balance.source,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        sourceLabel,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _detailsAmountLabel(
                                    row.totalAmount,
                                    balance.asset,
                                  ),
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: value?.amount.finiteDouble == null
                                ? Text(
                                    hidden ? '******' : '--',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(color: palette.muted),
                                  )
                                : PortfolioCurrencyAmount(
                                    usdtAmount: value!.amount.finiteDouble!,
                                    currencyMode: currency,
                                    vndRate: exchangeRate,
                                    hidden: hidden,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    textAlign: TextAlign.right,
                                    primaryStyle: TextStyle(
                                      color: palette.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                    secondaryStyle: TextStyle(
                                      color: palette.muted,
                                      fontSize: 10,
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
      ),
    );
  }

  String _detailsSourceLabel(ExchangeAccountResult source) {
    if (source.source == ExchangeSource.okx) return 'OKX Unified';
    return source.product == ExchangeProduct.spot
        ? 'Binance Spot'
        : 'Binance Futures';
  }

  String _detailsBalanceLabel(ExchangeBalance balance) {
    if (balance.source == ExchangeSource.okx) return 'OKX · ${balance.wallet}';
    final product = balance.product == ExchangeProduct.spot
        ? 'Spot'
        : 'USDT-M Futures';
    return 'Binance · $product · ${balance.wallet}';
  }

  String _detailsAmountLabel(
    ExchangeValue<ExchangeAmount>? amount,
    String asset,
  ) {
    if (amount?.value == null) return 'Balance unavailable';
    return hidden ? '******' : '${amount!.value!.text} $asset';
  }
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.account,
    required this.livePrices,
    required this.currency,
    required this.exchangeRate,
    required this.hidden,
    required this.pnlRevealed,
    required this.onRevealPnl,
    required this.onRefresh,
  });

  final OkxAccountData account;
  final Map<String, String> livePrices;
  final String currency;
  final double exchangeRate;
  final bool hidden;
  final bool pnlRevealed;
  final VoidCallback onRevealPnl;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    var pnl = 0.0;
    final values = <OkxCoinDetail, double>{};
    for (final coin in account.details) {
      final eq = double.tryParse(coin.eq);
      final live = double.tryParse(livePrices[coin.ccy] ?? '');
      final reportedValue = double.tryParse(coin.eqUsd);
      final fallbackPrice = eq != null && eq > 0 && reportedValue != null
          ? reportedValue / eq
          : null;
      final value = live != null && eq != null
          ? eq * live
          : reportedValue ?? double.nan;
      if (value.isFinite) {
        values[coin] = value;
        total += value;
        final upl = double.tryParse(coin.upl);
        if (upl != null && upl.isFinite) {
          pnl += upl * (live ?? fallbackPrice ?? 1);
        }
      }
    }
    final base = total - pnl;
    final ratio = base > 0 ? pnl / base : null;
    final palette = AppPalette.of(context);
    final textColor = palette.ink;
    final subtitle = palette.muted;
    return RefreshIndicator(
      color: palette.ink,
      backgroundColor: palette.raised,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Card(
            key: const Key('portfolio-details-summary'),
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
              side: BorderSide(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balances',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Total assets (${CurrencyDisplayMode.labelFor(currency)})',
                    style: TextStyle(
                      color: subtitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  PortfolioCurrencyAmount(
                    usdtAmount: total,
                    currencyMode: currency,
                    vndRate: exchangeRate,
                    hidden: hidden,
                    primaryStyle: TextStyle(
                      color: textColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                    secondaryStyle: TextStyle(
                      color: subtitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Principal / base capital',
                    style: TextStyle(
                      color: subtitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PortfolioCurrencyAmount(
                    key: const Key('portfolio-principal-base'),
                    usdtAmount: base,
                    currencyMode: currency,
                    vndRate: exchangeRate,
                    hidden: hidden,
                    primaryStyle: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    secondaryStyle: TextStyle(
                      color: subtitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!pnlRevealed)
                    OutlinedButton.icon(
                      key: const Key('portfolio-reveal-pnl'),
                      onPressed: onRevealPnl,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Reveal PnL for this visit'),
                    )
                  else
                    _PnlBlock(
                      pnl: pnl,
                      ratio: ratio,
                      currency: currency,
                      exchangeRate: exchangeRate,
                      hidden: hidden,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Asset balances',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (account.details.isEmpty)
            const _DetailsState(message: 'No balances available.')
          else
            for (final coin in account.details)
              _BalanceTile(
                coin: coin,
                value: values[coin],
                currency: currency,
                exchangeRate: exchangeRate,
                hidden: hidden,
              ),
        ],
      ),
    );
  }
}

class _PnlBlock extends StatelessWidget {
  const _PnlBlock({
    required this.pnl,
    required this.ratio,
    required this.currency,
    required this.exchangeRate,
    required this.hidden,
  });

  final double pnl;
  final double? ratio;
  final String currency;
  final double exchangeRate;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = resolvePnlColor(pnl, palette, hidden: hidden);
    final ratioColor = resolvePnlColor(
      ratio == null ? null : ratio! * 100,
      palette,
      hidden: hidden,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unrealized PnL',
          style: TextStyle(
            color: palette.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        PortfolioCurrencyAmount(
          usdtAmount: pnl,
          currencyMode: currency,
          vndRate: exchangeRate,
          hidden: hidden,
          showPositiveSign: true,
          primaryStyle: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          secondaryStyle: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hidden || ratio == null
              ? '******'
              : '(${ratio! >= 0 ? '+' : ''}${(ratio! * 100).toStringAsFixed(2)}%)',
          style: TextStyle(color: ratioColor, fontSize: 12),
        ),
      ],
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.coin,
    required this.value,
    required this.currency,
    required this.exchangeRate,
    required this.hidden,
  });

  final OkxCoinDetail coin;
  final double? value;
  final String currency;
  final double exchangeRate;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final subtitle = palette.muted;
    final color = palette.ink;
    final eq = double.tryParse(coin.eq);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: palette.border),
      ),
      child: ListTile(
        leading: CryptoIcon(
          symbol: coin.ccy,
          size: 32,
          backgroundColor: palette.surface,
          textColor: color,
          textSize: 13,
        ),
        title: Text(
          coin.ccy,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          hidden
              ? '******'
              : 'Qty ${NumberFormat('#,##0.########', 'en_US').format(eq ?? 0)}',
          style: TextStyle(color: subtitle, fontSize: 12),
        ),
        trailing: value == null
            ? const Text('-')
            : PortfolioCurrencyAmount(
                usdtAmount: value!,
                currencyMode: currency,
                vndRate: exchangeRate,
                hidden: hidden,
                crossAxisAlignment: CrossAxisAlignment.end,
                primaryStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
                secondaryStyle: TextStyle(color: subtitle, fontSize: 12),
              ),
      ),
    );
  }
}

class _DetailsState extends StatelessWidget {
  const _DetailsState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
