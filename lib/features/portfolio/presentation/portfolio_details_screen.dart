import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/currency/currency_display_mode.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/widgets/crypto_icon.dart';
import '../../market/presentation/providers/market_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(portfolioFutureProvider);
    final isDark = ref.watch(isDarkModeProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final currency = ref.watch(currencyProvider);
    final rate = ref.watch(vndExchangeRateProvider).value ?? 25400.0;
    final background = isDark ? const Color(0xFF121212) : Colors.white;
    final foreground = isDark ? Colors.white : Colors.black;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        title: const Text('Portfolio details'),
        actions: [
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
            onPressed: () =>
                ref.read(hideBalanceProvider.notifier).state = !hidden,
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: async.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: foreground)),
          error: (error, _) => _DetailsState(
            message: 'Unable to load portfolio details: $error',
          ),
          data: (account) => _DetailsContent(
            account: account,
            livePrices: ref.watch(livePriceProvider),
            currency: currency,
            exchangeRate: rate,
            hidden: hidden,
            pnlRevealed: _pnlRevealed,
            onRevealPnl: () => setState(() => _pnlRevealed = true),
            isDark: isDark,
          ),
        ),
      ),
    );
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
    required this.isDark,
  });

  final OkxAccountData account;
  final Map<String, String> livePrices;
  final String currency;
  final double exchangeRate;
  final bool hidden;
  final bool pnlRevealed;
  final VoidCallback onRevealPnl;
  final bool isDark;

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
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitle = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    return RefreshIndicator(
      onRefresh: () async => refetchPortfolio(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Card(
            key: const Key('portfolio-details-summary'),
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
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
                      fontSize: 11,
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
                      isDark: isDark,
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
                isDark: isDark,
              ),
        ],
      ),
    );
  }

  Future<void> refetchPortfolio(BuildContext context) async {
    // A refresh is a provider invalidation, keeping the details screen on the
    // same account namespace without adding any new API semantics.
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(portfolioFutureProvider);
    await Future<void>.delayed(Duration.zero);
  }
}

class _PnlBlock extends StatelessWidget {
  const _PnlBlock({
    required this.pnl,
    required this.ratio,
    required this.currency,
    required this.exchangeRate,
    required this.hidden,
    required this.isDark,
  });

  final double pnl;
  final double? ratio;
  final String currency;
  final double exchangeRate;
  final bool hidden;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = pnl >= 0 ? Colors.green : Colors.redAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unrealized PnL',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
            color: hidden ? Colors.grey : color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          secondaryStyle: TextStyle(
            color: hidden ? Colors.grey : color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hidden || ratio == null
              ? '******'
              : '(${ratio! >= 0 ? '+' : ''}${(ratio! * 100).toStringAsFixed(2)}%)',
          style: TextStyle(color: hidden ? Colors.grey : color, fontSize: 11),
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
    required this.isDark,
  });

  final OkxCoinDetail coin;
  final double? value;
  final String currency;
  final double exchangeRate;
  final bool hidden;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final subtitle = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final color = isDark ? Colors.white : Colors.black;
    final eq = double.tryParse(coin.eq);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: CryptoIcon(
          symbol: coin.ccy,
          size: 32,
          backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
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
          style: TextStyle(color: subtitle, fontSize: 11),
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
                secondaryStyle: TextStyle(color: subtitle, fontSize: 10),
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
