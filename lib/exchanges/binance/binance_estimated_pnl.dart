import '../../core/exchange/exchange_models.dart';
import 'binance_cost_basis.dart';
import 'binance_trade_history.dart';

class EstimatedPnlRow {
  const EstimatedPnlRow(this.estimate, this.message, {this.capital, this.stale = false});
  final CostEstimate? estimate;
  final String? message;
  final double? capital;
  final bool stale;
  double? get percentage => estimate == null || capital == null
      ? null
      : estimate!.profit / capital! * 100;
}

class EstimatedPnlSummary {
  const EstimatedPnlSummary(
    this.profit,
    this.cost,
    this.covered,
    this.eligible, {
    this.capitalComplete = true,
  });
  final double profit, cost;
  final int covered, eligible;
  final bool capitalComplete;
  double? get percentage => capitalComplete && cost.isFinite && cost > 0
      ? profit / cost * 100
      : null;
}

double? _number(String? value) => double.tryParse(value ?? '');

EstimatedPnlRow? _row(
  BinanceCostView view,
  bool finished,
  String? key,
  double? holding,
  double? mark,
  double interest, {
  bool isolated = false,
  double? quoteNet,
}) {
  if (!view.available) return null;
  final entry = key == null ? null : view.symbols[key];
  if (entry == null) {
    return finished && !view.loading
        ? const EstimatedPnlRow(null, 'Chưa tính')
        : null;
  }
  final result = holding == null || mark == null
      ? null
      : estimate(entry.cost, holding, mark, interest);
  final usable = result != null && result.ratio >= 0.01 ? result : null;
  final capital = usable == null
      ? null
      : isolated
      ? (quoteNet == null ? null : holding! * mark! + quoteNet - usable.profit)
      : usable.coveredQuantity * usable.average;
  return EstimatedPnlRow(
    usable,
    !entry.completed
        ? 'Đang tải lịch sử'
        : usable == null
        ? 'Chưa đủ dữ liệu giá vốn'
        : null,
    capital: capital != null && capital.isFinite && capital > 0 ? capital : null,
    stale: entry.stale,
  );
}

EstimatedPnlRow? estimatedBalance(
  BinanceCostView view,
  bool finished,
  AssetBalance balance,
) {
  if (balance.asset == 'USDT' ||
      (balance.wallet != 'Spot' && balance.wallet != 'Cross Margin'))
    return null;
  final amount = _number(
    balance.wallet == 'Spot' ? balance.total : balance.net,
  );
  final value = _number(balance.valueUsdt);
  final mark = amount != null && amount != 0 && value != null && value != 0
      ? value / amount
      : null;
  return _row(
    view,
    finished,
    '${balance.wallet}:${balance.asset}USDT',
    amount,
    mark,
    balance.wallet == 'Cross Margin' ? (_number(balance.interest) ?? 0) : 0,
  );
}

EstimatedPnlRow? estimatedMargin(
  BinanceCostView view,
  bool finished,
  MarginAccountRow row,
  AccountSnapshot account,
) {
  final key = row.key;
  if (key != null) {
    if (key.base == 'USDT') return null;
    final mark = _number(row.indexPrice);
    final interest =
        (_number(row.baseInterest) ?? 0) +
        (mark != null && mark > 0
            ? (_number(row.quoteInterest) ?? 0) / mark
            : 0);
    return _row(
      view,
      finished,
      key.quote == 'USDT' ? 'Isolated Margin:${key.nativeId}' : null,
      _number(row.baseNet),
      mark,
      interest,
      isolated: true,
      quoteNet: _number(row.quoteNet),
    );
  }
  if (row.asset == null || row.asset == 'USDT') return null;
  AssetBalance? balance;
  for (final item in account.balances) {
    if (item.wallet == 'Cross Margin' && item.asset == row.asset) {
      balance = item;
      break;
    }
  }
  final amount = _number(row.net);
  final value = _number(balance?.valueUsdt);
  final balanceAmount = _number(balance?.net);
  final mark =
      balanceAmount != null && balanceAmount != 0 && value != null && value != 0
      ? value / balanceAmount
      : null;
  return _row(
    view,
    finished,
    'Cross Margin:${row.asset}USDT',
    amount,
    mark,
    _number(row.interest) ?? 0,
  );
}

EstimatedPnlSummary estimatedSummary(
  BinanceCostView view,
  bool finished,
  AccountSnapshot account,
) {
  var eligible = 0, covered = 0;
  var profit = 0.0, cost = 0.0;
  var capitalComplete = true;
  void add(EstimatedPnlRow? row) {
    eligible++;
    final estimate = row?.estimate;
    if (estimate != null) {
      covered++;
      profit += estimate.profit;
      final capital = row!.capital;
      if (capital == null) {
        capitalComplete = false;
      } else {
        cost += capital;
      }
    }
  }

  for (final balance in account.balances) {
    if ((balance.wallet == 'Spot' || balance.wallet == 'Cross Margin') &&
        balance.asset != 'USDT' &&
        (_number(balance.wallet == 'Spot' ? balance.total : balance.net) ??
                0) !=
            0)
      add(estimatedBalance(view, finished, balance));
  }
  for (final row in account.marginRows) {
    if (row.key != null &&
        row.key!.base != 'USDT' &&
        (_number(row.baseNet) ?? 0) != 0)
      add(estimatedMargin(view, finished, row, account));
  }
  return EstimatedPnlSummary(
    profit, cost, covered, eligible, capitalComplete: capitalComplete,
  );
}

String estimatedPnlText(
  EstimatedPnlRow row, {
  double rate = 1,
  String unit = 'USDT',
}) {
  final e = row.estimate;
  final parts = <String>[];
  if (e != null) {
    String signed(double n) => '${n >= 0 ? '+' : ''}${n.toStringAsFixed(2)}';
    final percentage = row.capital == null ? null : e.profit / row.capital! * 100;
    parts.add(
      'Giá vốn TB ${(e.average * rate).toStringAsFixed(2)} · Ước tính ${signed(e.profit * rate)} $unit${percentage == null ? '' : ' (${signed(percentage)}%)'}',
    );
    if (e.ratio < 0.999999)
      parts.add('tính trên ${(e.ratio * 100).toStringAsFixed(0)}% lượng');
  }
  if (row.message != null) parts.add(row.message!);
  if (row.stale && e != null) parts.add('chưa cập nhật');
  return parts.join(' · ');
}
