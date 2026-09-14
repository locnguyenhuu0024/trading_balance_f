import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trading_balance_f/features/portfolio/domain/risk/risk_events.dart';
import 'package:trading_balance_f/features/portfolio/domain/risk/risk_models.dart';
import 'package:trading_balance_f/features/portfolio/presentation/risk_vietnamese_formatter.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_history_view.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_market_card.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_price_map.dart';
import 'package:trading_balance_f/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart';

void main() {
  test('RED-004 Vietnamese Risk Dashboard', () {
    expect(riskViSeverity(RiskSeverity.critical), 'NGHIÊM TRỌNG');
    expect(riskViQuality(const RiskQuality.partial()), 'Đánh giá một phần');
  });

  test(
    'RED-004 Vietnamese Risk Dashboard formats generated and legacy copy',
    () {
      expect(
        riskViGenerated('Effective leverage is 2.0000x'),
        'Đòn bẩy hiệu quả là 2.0000x',
      );
      expect(
        riskViGenerated('Risk changed since last observation'),
        'Rủi ro đã thay đổi từ lần quan sát trước',
      );
      expect(
        riskViGenerated('True Exit is 1.25% above mark'),
        'True Exit cao hơn giá đánh dấu 1.25%',
      );
      expect(
        riskViGenerated('Scenario True Exit is 2.50% above price'),
        'Kịch bản True Exit cao hơn giá 2.50%',
      );
      expect(
        riskViEvent('New confirmed risk factor: funding-123'),
        'Yếu tố rủi ro mới đã xác nhận: funding-123',
      );
      expect(
        riskViEvent('user-authored event note'),
        'user-authored event note',
      );
      expect(
        riskViError('unrecognized upstream English', source: 'OKX'),
        contains('OKX'),
      );
    },
  );

  testWidgets(
    'RED-004 Vietnamese Risk Dashboard formats generated Price Map labels',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiskPriceMap(
              currentPrice: 100,
              levels: const <RiskPriceMapLevel>[
                RiskPriceMapLevel(
                  price: 90,
                  labels: <String>[
                    'Current',
                    'Entry',
                    'Liquidation',
                    'True Exit',
                    'Buffer 5.00%',
                    'Support',
                    'Resistance',
                    'Custom price',
                    '-10% scenario',
                    'user zone',
                    'Vendor label',
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Hiện tại'), findsWidgets);
      expect(find.text('Điểm vào'), findsOneWidget);
      expect(find.text('Thanh lý'), findsOneWidget);
      expect(find.text('True Exit'), findsOneWidget);
      expect(find.text('Biên 5.00%'), findsOneWidget);
      expect(find.text('Hỗ trợ'), findsOneWidget);
      expect(find.text('Kháng cự'), findsOneWidget);
      expect(find.text('Giá tùy chỉnh'), findsOneWidget);
      expect(find.text('-10% kịch bản'), findsOneWidget);
      expect(find.text('user zone'), findsOneWidget);
      expect(find.text('Vendor label'), findsOneWidget);
    },
  );

  testWidgets(
    'RED-004 Vietnamese Risk Dashboard translates current events privacy safely',
    (tester) async {
      final observedAt = DateTime.utc(2026, 1, 2, 3, 4);
      final event = RiskEvent(
        id: 'event-1',
        episodeKey: 'episode-1',
        kind: RiskEventKind.factorEntry,
        message: 'New confirmed risk factor: funding-rate',
        factorId: 'funding-rate',
        source: 'OKX',
        previousValue: 1.2,
        currentValue: 3.4,
        createdAt: observedAt,
        observedAt: observedAt,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiskHistoryView(events: <RiskEvent>[event], hideValues: true),
          ),
        ),
      );
      expect(
        find.text('Yếu tố rủi ro mới đã xác nhận: funding-rate'),
        findsOneWidget,
      );
      expect(find.textContaining('funding-rate'), findsWidgets);
      expect(find.textContaining('1.20'), findsNothing);
      expect(find.textContaining('3.40'), findsNothing);
      expect(find.textContaining('OKX'), findsOneWidget);
    },
  );

  test(
    'RED-004 Vietnamese Risk Dashboard translates current event templates',
    () {
      expect(
        riskViEvent('Market risk worsened from normal to critical'),
        'Thị trường xấu đi từ BÌNH THƯỜNG đến NGHIÊM TRỌNG',
      );
      expect(
        riskViEvent('Recovery risk improvement confirmed from high to watch'),
        'Phục hồi đã xác nhận cải thiện từ CAO đến THEO DÕI',
      );
      expect(
        riskViEvent('effective leverage crossed 5.0'),
        'Đòn bẩy hiệu quả đã vượt 5.0',
      );
      expect(
        riskViEvent('Market risk improvement confirmed'),
        'Đã xác nhận cải thiện rủi ro Thị trường',
      );
      expect(riskViEvent('BTC crossed 25000'), 'BTC đã vượt 25000');
      expect(
        riskViEvent('user-authored event note'),
        'user-authored event note',
      );
    },
  );

  test(
    'RED-004 Vietnamese Risk Dashboard error fallback preserves safe metadata',
    () {
      const unknown =
          'Unexpected English upstream failure [HTTP 429] from OKX';
      final fallback = riskViError(unknown);
      expect(
        fallback,
        'Không thể tải dữ liệu rủi ro · HTTP 429 · nguồn OKX',
      );
      expect(fallback, isNot(contains('Unexpected English upstream failure')));
      expect(
        riskViError('Unknown English failure', source: 'Binance'),
        'Không thể tải dữ liệu rủi ro · nguồn Binance',
      );
      expect(
        riskViError('Unknown English failure HTTP 429', source: 'OKX'),
        'Không thể tải dữ liệu rủi ro · HTTP 429 · nguồn OKX',
      );
    },
  );

  test(
    'RED-004 Vietnamese Risk Dashboard catalog covers every riskVi call site',
    () {
      const files = <String>[
        'lib/features/portfolio/presentation/risk_dashboard_screen.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_history_view.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_market_card.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_overview.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_plan_editor.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_price_map.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_settings_sheet.dart',
        'lib/features/portfolio/presentation/widgets/risk/risk_stress_view.dart',
      ];
      final call = RegExp(r"riskVi\('([^']+)'\)");
      for (final path in files) {
        final source = File(path).readAsStringSync();
        for (final match in call.allMatches(source)) {
          final key = match.group(1)!;
          expect(
            riskVi(key),
            isNot(key),
            reason: '$path uses an uncatalogued riskVi key: $key',
          );
        }
      }
    },
  );

  testWidgets(
    'RED-004 Vietnamese Risk Dashboard renders the True Exit price heading',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RiskRecoveryView(evaluation: null)),
        ),
      );
      expect(find.text('Giá True Exit'), findsOneWidget);
    },
  );

  testWidgets(
    'GREEN-004 Vietnamese Risk Dashboard renders representative copy',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RiskMarketCard(evaluation: null)),
        ),
      );
      expect(find.text('Rủi ro thị trường'), findsOneWidget);
      expect(find.text('Bằng chứng thị trường'), findsNothing);
    },
  );

  test('GREEN-004 Vietnamese Risk Dashboard source audit uses explicit allowlist', () {
    const files = <String>[
      'lib/features/portfolio/presentation/risk_dashboard_screen.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_history_view.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_market_card.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_overview.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_plan_editor.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_price_map.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_settings_sheet.dart',
      'lib/features/portfolio/presentation/widgets/risk/risk_stress_view.dart',
    ];
    const allowedEnglishCopy = <String>{
      'Asset',
      'BTC',
      'LONG',
      'SHORT',
      'ISOLATED',
      'MARGIN',
      'OKX',
      'OI',
      'True Exit',
      'USDT',
    };
    final violations = <String>[];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final context = lines
            .sublist(index > 2 ? index - 2 : 0, index + 1)
            .join('\n');
        if (!_userFacingContext.hasMatch(context)) continue;
        if (lines[index].contains('Key(') || lines[index].contains('ValueKey(')) {
          continue;
        }
        final copyLine = _stripInterpolation(lines[index]);
        for (final match in _quotedLiteral.allMatches(copyLine)) {
          final literal = match.group(2)!;
          if (_looksNonEnglish(literal) || _isInternalKey(literal)) continue;
          if (allowedEnglishCopy.contains(literal.trim())) continue;
          violations.add('$path:${index + 1}: $literal');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Unapproved English user-facing literals: $violations',
    );
  });
}

final _userFacingContext = RegExp(
  r'(?:\b(?:Text|TextButton|TextField|InputDecoration|ListTile|SnackBar|_Notice|_HistoryCard|_SummaryMetric|_MetricSheetRow|_CheckValue|_Answer|_EmptyPanel)\s*\(|\b(?:tooltip|semanticLabel|label|title|message|description|helperText|hintText|errorText)\s*:)',
);

final _quotedLiteral = RegExp(
  r'''(['"])([^'"]*[A-Za-z][^'"]*)\1''',
);

bool _looksNonEnglish(String value) => RegExp(r'[^\x00-\x7F]').hasMatch(value);

bool _isInternalKey(String value) =>
    RegExp(r'^[a-z][A-Za-z0-9_]*$').hasMatch(value);

String _stripInterpolation(String line) => line.replaceAll(
  RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*'),
  '',
);
