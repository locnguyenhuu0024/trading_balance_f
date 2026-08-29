# Portfolio USDT + VND Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILLS: Use `superpowers:executing-plans` and `superpowers:test-driven-development` while implementing this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not dispatch subagents, commit, or push unless the user separately requests those actions.

**Goal:** Add a persisted **USDT + VND** display option that shows both values on the Portfolio/home screen for total balance, original capital, unrealized P&L, and every asset row.

**Architecture:** Keep the existing string-based `currencyProvider` and `CURRENCY` storage key so current USD and VNĐ preferences remain compatible. Add a small core definition for supported currency modes and a focused Portfolio amount formatter/widget that renders one or two lines; Settings selects and persists the new mode, while Portfolio supplies USDT amounts and the existing CoinGecko-backed VND rate.

**Tech Stack:** Flutter, Dart `^3.11.5`, Riverpod `2.5.1`, `intl 0.20.2`, `flutter_test`.

## Global Constraints

- Scope is limited to `PortfolioScreen`; Market, Orders, P&L History, and Fractal Tracker must not change.
- Preserve existing USD-only and VNĐ-only behavior.
- Persist the dual option as `USDT_VND` through the existing `CURRENCY` preference on mobile and web.
- In dual mode, render USDT as the primary line and VND as the secondary line.
- Apply dual rendering to total balance, original capital, unrealized P&L, and every visible asset row.
- Hidden-balance mode must obscure both monetary lines.
- Continue using `vndExchangeRateProvider`; retain its current `25,400` VND fallback when CoinGecko is unavailable.
- Do not add dependencies or modify generated files, build output, or unrelated screens.
- Do not modify source code until the user explicitly says “execute tasks”, “proceed with coding”, or equivalent.
- Do not commit or push unless the user explicitly requests it.

## File Map

- Create `lib/core/currency/currency_display_mode.dart`: canonical stored values, labels, supported options, and VND-mode checks.
- Create `lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart`: deterministic formatting and reusable one/two-line amount rendering.
- Modify `lib/features/settings/presentation/settings_screen.dart`: add the third dropdown option and show the exchange-rate subtitle for VND-capable modes.
- Modify `lib/features/portfolio/presentation/portfolio_screen.dart`: use the reusable renderer for summary and asset values.
- Create `test/core/currency/currency_display_mode_test.dart`: validate option values, labels, and conversion-mode predicates.
- Create `test/features/portfolio/portfolio_currency_amount_test.dart`: validate formatting, negative/positive P&L signs, hiding, and widget line rendering.

---

### Task 1: Define compatible currency display modes

**Files:**

- Create: `lib/core/currency/currency_display_mode.dart`
- Test: `test/core/currency/currency_display_mode_test.dart`

**Interfaces:**

- Consumes: Existing persisted strings `USD` and `VNĐ`.
- Produces: `CurrencyDisplayMode.usd`, `CurrencyDisplayMode.vnd`, `CurrencyDisplayMode.usdtVnd`, `CurrencyDisplayMode.options`, `CurrencyDisplayMode.includesVnd(String)`, and `CurrencyDisplayMode.labelFor(String)`.

- [ ] **Step 1: Write the failing mode-definition test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';

void main() {
  test('exposes backward-compatible currency values and the dual option', () {
    expect(CurrencyDisplayMode.options.map((option) => option.value), [
      'USD',
      'VNĐ',
      'USDT_VND',
    ]);
    expect(CurrencyDisplayMode.labelFor('USDT_VND'), 'USDT + VND');
  });

  test('identifies modes that require the VND exchange rate', () {
    expect(CurrencyDisplayMode.includesVnd('USD'), isFalse);
    expect(CurrencyDisplayMode.includesVnd('VNĐ'), isTrue);
    expect(CurrencyDisplayMode.includesVnd('USDT_VND'), isTrue);
  });
}
```

- [ ] **Step 2: Run the focused test and confirm the expected failure**

Run:

```powershell
flutter test test/core/currency/currency_display_mode_test.dart
```

Expected: FAIL because `currency_display_mode.dart` does not exist.

- [ ] **Step 3: Add the minimal mode definition**

```dart
class CurrencyDisplayOption {
  const CurrencyDisplayOption({required this.value, required this.label});

  final String value;
  final String label;
}

abstract final class CurrencyDisplayMode {
  static const String usd = 'USD';
  static const String vnd = 'VNĐ';
  static const String usdtVnd = 'USDT_VND';

  static const List<CurrencyDisplayOption> options = [
    CurrencyDisplayOption(value: usd, label: 'USD'),
    CurrencyDisplayOption(value: vnd, label: 'VNĐ'),
    CurrencyDisplayOption(value: usdtVnd, label: 'USDT + VND'),
  ];

  static bool includesVnd(String value) => value == vnd || value == usdtVnd;

  static String labelFor(String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return options.first.label;
  }
}
```

- [ ] **Step 4: Run the focused test again**

Run:

```powershell
flutter test test/core/currency/currency_display_mode_test.dart
```

Expected: PASS with two passing tests.

### Task 2: Build and test the Portfolio currency renderer

**Files:**

- Create: `lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart`
- Test: `test/features/portfolio/portfolio_currency_amount_test.dart`

**Interfaces:**

- Consumes: Currency values from `CurrencyDisplayMode`, USDT-denominated `double` amounts, the VND rate, hidden state, and optional positive-sign behavior.
- Produces: `PortfolioCurrencyLines`, `formatPortfolioCurrencyLines(...)`, and `PortfolioCurrencyAmount`.

- [ ] **Step 1: Write failing formatter tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/portfolio_currency_amount.dart';

void main() {
  const rate = 25400.0;

  test('formats USD and VNĐ as single-line values', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.usd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(primary: r'$1,234.50'),
    );
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.vnd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(primary: '31.356.300 đ'),
    );
  });

  test('formats USDT above VND in dual mode', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 1234.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
      ),
      const PortfolioCurrencyLines(
        primary: '1,234.50 USDT',
        secondary: '≈ 31.356.300 đ',
      ),
    );
  });

  test('preserves P&L sign on both lines and hides both lines', () {
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: -12.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
        showPositiveSign: true,
      ),
      const PortfolioCurrencyLines(
        primary: '-12.50 USDT',
        secondary: '≈ -317.500 đ',
      ),
    );
    expect(
      formatPortfolioCurrencyLines(
        usdtAmount: 12.5,
        currencyMode: CurrencyDisplayMode.usdtVnd,
        vndRate: rate,
        hidden: true,
      ),
      const PortfolioCurrencyLines(primary: '******', secondary: '******'),
    );
  });

  testWidgets('renders dual values as two text lines', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PortfolioCurrencyAmount(
            usdtAmount: 10,
            currencyMode: CurrencyDisplayMode.usdtVnd,
            vndRate: rate,
          ),
        ),
      ),
    );

    expect(find.text('10.00 USDT'), findsOneWidget);
    expect(find.text('≈ 254.000 đ'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the focused tests and confirm the expected failure**

Run:

```powershell
flutter test test/features/portfolio/portfolio_currency_amount_test.dart
```

Expected: FAIL because the renderer file and interfaces do not exist.

- [ ] **Step 3: Implement the formatter and reusable widget**

Create `portfolio_currency_amount.dart` with the complete implementation below:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';

@immutable
class PortfolioCurrencyLines {
  const PortfolioCurrencyLines({required this.primary, this.secondary});

  final String primary;
  final String? secondary;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PortfolioCurrencyLines &&
            other.primary == primary &&
            other.secondary == secondary;
  }

  @override
  int get hashCode => Object.hash(primary, secondary);
}

PortfolioCurrencyLines formatPortfolioCurrencyLines({
  required double usdtAmount,
  required String currencyMode,
  required double vndRate,
  bool hidden = false,
  bool showPositiveSign = false,
}) {
  if (hidden) {
    return PortfolioCurrencyLines(
      primary: '******',
      secondary: currencyMode == CurrencyDisplayMode.usdtVnd
          ? '******'
          : null,
    );
  }

  final absoluteAmount = usdtAmount.abs();
  final sign = usdtAmount < 0
      ? '-'
      : (showPositiveSign && usdtAmount > 0 ? '+' : '');
  final usdt = NumberFormat('#,##0.00', 'en_US').format(absoluteAmount);
  final vnd = NumberFormat('#,##0', 'vi_VN').format(absoluteAmount * vndRate);

  if (currencyMode == CurrencyDisplayMode.vnd) {
    return PortfolioCurrencyLines(primary: '$sign$vnd đ');
  }
  if (currencyMode == CurrencyDisplayMode.usdtVnd) {
    return PortfolioCurrencyLines(
      primary: '$sign$usdt USDT',
      secondary: '≈ $sign$vnd đ',
    );
  }
  return PortfolioCurrencyLines(primary: '$sign\$$usdt');
}

class PortfolioCurrencyAmount extends StatelessWidget {
  const PortfolioCurrencyAmount({
    super.key,
    required this.usdtAmount,
    required this.currencyMode,
    required this.vndRate,
    this.hidden = false,
    this.showPositiveSign = false,
    this.primaryStyle,
    this.secondaryStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.textAlign = TextAlign.left,
    this.primaryPrefix = '',
  });

  final double usdtAmount;
  final String currencyMode;
  final double vndRate;
  final bool hidden;
  final bool showPositiveSign;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;
  final String primaryPrefix;

  @override
  Widget build(BuildContext context) {
    final lines = formatPortfolioCurrencyLines(
      usdtAmount: usdtAmount,
      currencyMode: currencyMode,
      vndRate: vndRate,
      hidden: hidden,
      showPositiveSign: showPositiveSign,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          '$primaryPrefix${lines.primary}',
          textAlign: textAlign,
          style: primaryStyle,
        ),
        if (lines.secondary != null) ...[
          const SizedBox(height: 2),
          Text(
            lines.secondary!,
            textAlign: textAlign,
            style: secondaryStyle,
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run the formatter/widget tests again**

Run:

```powershell
flutter test test/features/portfolio/portfolio_currency_amount_test.dart
```

Expected: PASS with four passing tests.

### Task 3: Add and persist the Settings option

**Files:**

- Modify: `lib/features/settings/presentation/settings_screen.dart:1-225`
- Test: `test/core/currency/currency_display_mode_test.dart`

**Interfaces:**

- Consumes: `CurrencyDisplayMode.options` and `CurrencyDisplayMode.includesVnd` from Task 1.
- Produces: A third dropdown entry whose stored value is `USDT_VND`; existing `_saveAllPreferences()` writes it through `saveAppPreferences` without storage-schema changes.

- [ ] **Step 1: Replace literal dropdown options with canonical options**

Import `core/currency/currency_display_mode.dart` and build the dropdown items with:

```dart
items: CurrencyDisplayMode.options
    .map(
      (option) => DropdownMenuItem<String>(
        value: option.value,
        child: Text(option.label),
      ),
    )
    .toList(),
```

- [ ] **Step 2: Show the rate subtitle for both VND-capable modes**

Change the subtitle condition from the VNĐ-only comparison to:

```dart
subtitle: CurrencyDisplayMode.includesVnd(currency)
    ? exchangeRateAsync.when(
        data: (rate) => Text(
          '1 USDT ≈ ${NumberFormat("#,##0", "en_US").format(rate)} đ',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        loading: () => Text(
          'Đang cập nhật tỷ giá...',
          style: TextStyle(color: sectionTitleColor, fontSize: 11),
        ),
        error: (_, __) => const Text(
          'Lỗi tải tỷ giá (Dùng giá chuẩn)',
          style: TextStyle(color: Colors.redAccent, fontSize: 11),
        ),
      )
    : null,
```

- [ ] **Step 3: Verify persistence compatibility by inspection and focused tests**

Confirm that `_saveAllPreferences()` still passes `ref.read(currencyProvider)` to `SecureStorageHelper.saveAppPreferences`, and that both `SecureStorageHelper.getCurrency()` and `WebStorageHelper.getCurrency()` return arbitrary stored strings. No storage migration is required.

Run:

```powershell
flutter test test/core/currency/currency_display_mode_test.dart
```

Expected: PASS.

### Task 4: Render both currencies throughout Portfolio

**Files:**

- Modify: `lib/features/portfolio/presentation/portfolio_screen.dart:1-322`
- Test: `test/features/portfolio/portfolio_currency_amount_test.dart`

**Interfaces:**

- Consumes: `PortfolioCurrencyAmount`, `CurrencyDisplayMode.labelFor`, existing USDT-equivalent calculations, `vndExchangeRateProvider`, and the existing `25,400` fallback.
- Produces: Dual-currency summary and asset-row presentation without changing portfolio data fetching or calculations.

- [ ] **Step 1: Import the new mode and renderer files**

```dart
import '../../../core/currency/currency_display_mode.dart';
import 'widgets/portfolio_currency_amount.dart';
```

- [ ] **Step 2: Replace the total-equity text with the reusable renderer**

Keep `dynamicTotalEquity` in USDT and render:

```dart
Text(
  'Tổng tài sản (${CurrencyDisplayMode.labelFor(currency)})',
  style: TextStyle(
    color: Colors.grey.shade400,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  ),
),
const SizedBox(height: 8),
PortfolioCurrencyAmount(
  usdtAmount: dynamicTotalEquity,
  currencyMode: currency,
  vndRate: exchangeRate,
  hidden: isHidden,
  primaryStyle: const TextStyle(
    color: Colors.white,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  ),
  secondaryStyle: TextStyle(
    color: Colors.grey.shade400,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
),
```

- [ ] **Step 3: Render original capital and unrealized P&L in both currencies**

Replace the original-capital `Text` with:

```dart
PortfolioCurrencyAmount(
  usdtAmount: baseEquity,
  currencyMode: currency,
  vndRate: exchangeRate,
  hidden: isHidden,
  primaryPrefix: 'Vốn gốc: ',
  crossAxisAlignment: CrossAxisAlignment.center,
  textAlign: TextAlign.center,
  primaryStyle: TextStyle(
    color: Colors.grey.shade500,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  ),
  secondaryStyle: TextStyle(
    color: Colors.grey.shade500,
    fontSize: 10,
    fontWeight: FontWeight.w500,
  ),
),
```

Inside the existing P&L container `Row`, replace the monetary `Text` with this widget and retain the percentage `Text` after it:

```dart
PortfolioCurrencyAmount(
  usdtAmount: totalUnrealizedPnl,
  currencyMode: currency,
  vndRate: exchangeRate,
  hidden: isHidden,
  showPositiveSign: true,
  primaryStyle: TextStyle(
    color: isHidden ? Colors.grey : pnlColor,
    fontWeight: FontWeight.bold,
    fontSize: 12,
  ),
  secondaryStyle: TextStyle(
    color: isHidden ? Colors.grey : pnlColor,
    fontWeight: FontWeight.w600,
    fontSize: 10,
  ),
),
const SizedBox(width: 4),
Text(
  _obfuscate(
    '(${totalUnrealizedPnl >= 0 ? '+' : ''}${pnlRatio.toStringAsFixed(2)}%)',
    isHidden,
  ),
  style: TextStyle(
    color: isHidden ? Colors.grey : pnlColor,
    fontWeight: FontWeight.w600,
    fontSize: 10,
  ),
),
```

- [ ] **Step 4: Render each asset value as a right-aligned one/two-line amount**

Replace the trailing `Text` with:

```dart
trailing: PortfolioCurrencyAmount(
  usdtAmount: currentUsdValue,
  currencyMode: currency,
  vndRate: exchangeRate,
  hidden: isHidden,
  crossAxisAlignment: CrossAxisAlignment.end,
  textAlign: TextAlign.right,
  primaryStyle: TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: textColor,
  ),
  secondaryStyle: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 10,
    color: subtitleColor,
  ),
),
```

Keep quantity, live unit price, dust filtering, WebSocket updates, refresh behavior, and portfolio calculations unchanged.

- [ ] **Step 5: Remove obsolete local currency formatting only after all call sites migrate**

Delete `_formatCurrency`, `curSymbol`, and the preformatted `pnlFormatted`, `equityFormatted`, and `baseEquityFormatted` variables after verifying there are no remaining references. Retain `_obfuscate` because the quantity line still uses it.

- [ ] **Step 6: Run Portfolio tests**

Run:

```powershell
flutter test test/features/portfolio/portfolio_currency_amount_test.dart
```

Expected: PASS with four passing tests.

### Task 5: Full verification and manual acceptance

**Files:**

- Verify: all files listed in the File Map

**Interfaces:**

- Consumes: Completed Tasks 1-4.
- Produces: Analyzer-clean, test-passing behavior ready for user review.

- [ ] **Step 1: Format changed Dart files**

Run:

```powershell
dart format lib/core/currency/currency_display_mode.dart lib/features/settings/presentation/settings_screen.dart lib/features/portfolio/presentation/portfolio_screen.dart lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart test/core/currency/currency_display_mode_test.dart test/features/portfolio/portfolio_currency_amount_test.dart
```

Expected: Command exits successfully and reports the formatted files.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: Exit code `0`, with no new analyzer errors or warnings caused by this feature.

- [ ] **Step 3: Run the complete test suite**

Run:

```powershell
flutter test
```

Expected: Exit code `0`; all existing and new tests pass.

- [ ] **Step 4: Manually verify the three setting modes**

Run the app and confirm:

1. USD renders one USD line exactly as before.
2. VNĐ renders one converted VND line exactly as before.
3. USDT + VND renders USDT above VND for total balance, original capital, unrealized P&L, and every visible asset row.
4. Toggling balance visibility hides and restores both lines.
5. Reloading/restarting preserves `USDT + VND` on web and mobile storage paths.
6. Market, Orders, P&L History, and Fractal Tracker remain unchanged.

- [ ] **Step 5: Report verification evidence without committing or pushing**

Provide the exact analyzer/test results and any manual-test limitations to the user. Do not run `git commit` or `git push` unless separately instructed.
