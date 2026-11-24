import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/currency/currency_display_mode.dart';
import 'package:trading_balance_f/core/network/okx_websocket_service.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_mood.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_outfit.dart';
import 'package:trading_balance_f/features/avatar/presentation/avatar_renderer.dart';
import 'package:trading_balance_f/features/market/presentation/providers/market_provider.dart';
import 'package:trading_balance_f/features/orders/data/trade_api_client.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/trade_session_provider.dart';
import 'package:trading_balance_f/features/portfolio/data/okx_balance_model.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart';
import 'package:trading_balance_f/features/portfolio/presentation/providers/portfolio_provider.dart';
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart';

import '../avatar/floating_avatar_test.dart'
    show FakeAvatarRenderer, avatarFakeKey;

const _sixPercent = OkxAccountData(
  totalEq: '106',
  details: [OkxCoinDetail(ccy: 'USDT', eq: '106', eqUsd: '106', upl: '6')],
);

void main() {
  testWidgets('GREEN-156 home filters stale outfits and restricts colours', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    const item = 'donut-chan:outfit';
    final dress = AvatarColors.empty.withPart(
      AvatarPart.dress,
      const Color(0xff552299),
    );
    final colors = dress.withPart(AvatarPart.top, const Color(0xff667788));
    final container = await _mountPortfolio(
      tester,
      load: () async => _sixPercent,
      factory: (_) => renderer,
      outfits: const {
        'pixiv-sample': ['obsolete', item, item],
      },
      colors: {'pixiv-sample': colors},
    );
    expect(renderer.outfits, [
      [item],
    ]);
    expect(renderer.colors, [dress]);

    container.read(avatarOutfitsProvider.notifier).state = const {
      'pixiv-sample': ['obsolete', item, 'another-obsolete-item'],
    };
    await tester.pump();
    expect(renderer.outfits, [
      [item],
    ]);
    expect(renderer.colors, [dress]);

    container.read(avatarOutfitsProvider.notifier).state = const {};
    await tester.pump();
    expect(renderer.outfits, [
      [item],
      <String>[],
    ]);
    expect(renderer.colors, [
      dress,
      colors.restrictTo([AvatarPart.top]),
    ]);
  });

  testWidgets('GREEN-152 home sends selected model colours only on change', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    const blue = Color(0xff223399);
    const red = Color(0xff992233);
    final hair = AvatarColors.empty.withPart(AvatarPart.hair, blue);
    final container = await _mountPortfolio(
      tester,
      load: () async => _sixPercent,
      factory: (_) => renderer,
      colors: {'pixiv-sample': hair.withPart(AvatarPart.accessory, red)},
    );
    expect(renderer.colors, [hair]);

    final colors = container.read(avatarColorsProvider.notifier);
    colors.state = {
      'pixiv-sample': AvatarColors.empty.withPart(AvatarPart.hair, blue),
      'donut-chan': AvatarColors.empty.withPart(AvatarPart.eyes, red),
    };
    await tester.pump();
    expect(renderer.colors, [hair]);

    final changed = hair.withPart(AvatarPart.hair, red);
    colors.state = {...colors.state, 'pixiv-sample': changed};
    await tester.pump();
    expect(renderer.colors, [hair, changed]);

    colors.state = const {};
    await tester.pump();
    expect(renderer.colors, [hair, changed, AvatarColors.empty]);
  });

  testWidgets('GREEN-150 switching models replaces the loading renderer', (
    tester,
  ) async {
    final createdModels = <AvatarModel>[];
    final renderers = <FakeAvatarRenderer>[];
    final container = await _mountPortfolio(
      tester,
      load: () async => _sixPercent,
      factory: (model) {
        createdModels.add(model);
        final renderer = FakeAvatarRenderer();
        renderers.add(renderer);
        return renderer;
      },
    );
    expect(createdModels.single.id, 'pixiv-sample');
    expect(
      find.byKey(const ValueKey('home-avatar-pixiv-sample')),
      findsOneWidget,
    );

    container.read(avatarModelIdProvider.notifier).state = 'donut-chan';
    await tester.pump();

    expect(createdModels.map((model) => model.id), [
      'pixiv-sample',
      'donut-chan',
    ]);
    expect(createdModels.last.file, 'donut-chan.vrm');
    expect(renderers.first.disposed, isTrue);
    expect(renderers.last.disposed, isFalse);
    expect(
      find.byKey(const ValueKey('home-avatar-pixiv-sample')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-avatar-donut-chan')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RED setting off creates no renderer', (tester) async {
    var creations = 0;
    await _mountPortfolio(
      tester,
      enabled: false,
      load: () async => _sixPercent,
      factory: (_) {
        creations++;
        return FakeAvatarRenderer();
      },
    );
    expect(creations, 0);
    expect(find.byKey(avatarFakeKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RED initial loading and error both keep mood neutral', (
    tester,
  ) async {
    final pending = Completer<OkxAccountData>();
    final renderer = FakeAvatarRenderer();
    await _mountPortfolio(
      tester,
      load: () => pending.future,
      factory: (_) => renderer,
    );
    expect(renderer.moods, [AvatarMood.neutral]);

    pending.completeError(StateError('Fixture account load failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Không thể tải dữ liệu'), findsOneWidget);
    expect(renderer.moods, [AvatarMood.neutral]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RED 6% with hidden balance stays neutral', (tester) async {
    final renderer = FakeAvatarRenderer();
    await _mountPortfolio(
      tester,
      hidden: true,
      load: () async => _sixPercent,
      factory: (_) => renderer,
    );
    expect(find.byKey(const Key('portfolio-asset-summary')), findsOneWidget);
    expect(renderer.moods, [AvatarMood.neutral]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RED refresh error neutralizes a previously strong mood', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    final refresh = Completer<OkxAccountData>();
    var reads = 0;
    await _mountPortfolio(
      tester,
      load: () {
        reads++;
        return reads == 1 ? Future.value(_sixPercent) : refresh.future;
      },
      factory: (_) => renderer,
    );
    expect(renderer.moods.last, AvatarMood.strongHappy);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(reads, 2);
    refresh.completeError(StateError('Fixture refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(renderer.moods.last, AvatarMood.neutral);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'RED three refresh ticks reuse the host and skip redundant mood updates',
    (tester) async {
      final renderer = FakeAvatarRenderer();
      var creations = 0;
      var reads = 0;
      await _mountPortfolio(
        tester,
        load: () async {
          reads++;
          return _sixPercent;
        },
        factory: (_) {
          creations++;
          return renderer;
        },
      );
      final initialMoods = List<AvatarMood>.of(renderer.moods);
      expect(initialMoods.last, AvatarMood.strongHappy);
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        await tester.pump();
      }

      expect(reads, 4);
      expect(creations, 1);
      expect(renderer.moods, initialMoods);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'GREEN 6% reaches the host once and hiding the balance neutralizes it',
    (tester) async {
      final renderer = FakeAvatarRenderer();
      final container = await _mountPortfolio(
        tester,
        enabled: false,
        load: () async => _sixPercent,
        factory: (_) => renderer,
      );

      container.read(avatarEnabledProvider.notifier).state = true;
      await tester.pump();
      expect(find.byKey(avatarFakeKey), findsOneWidget);
      expect(renderer.moods, [AvatarMood.strongHappy]);

      await tester.tap(find.byTooltip('Ẩn số dư'));
      await tester.pump();
      expect(renderer.moods, [AvatarMood.strongHappy, AvatarMood.neutral]);

      container.read(avatarEnabledProvider.notifier).state = false;
      await tester.pump();
      expect(find.byKey(avatarFakeKey), findsNothing);
      expect(renderer.disposed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<ProviderContainer> _mountPortfolio(
  WidgetTester tester, {
  required Future<OkxAccountData> Function() load,
  required AvatarRendererFactory factory,
  bool enabled = true,
  bool hidden = false,
  Map<String, AvatarColors> colors = const {},
  Map<String, List<String>> outfits = const {},
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = TradeApiClient(baseUrl: 'https://trade.example');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tradeApiProvider.overrideWithValue(api),
        tradeSessionProvider.overrideWith((ref) => TradeSessionController(api)),
        portfolioFutureProvider.overrideWith((ref) => load()),
        livePriceProvider.overrideWith((ref) => LivePriceNotifier()),
        okxWebsocketProvider.overrideWithValue(_FakeOkxWebsocketService()),
        currencyProvider.overrideWith((ref) => CurrencyDisplayMode.usd),
        vndExchangeRateProvider.overrideWith((ref) async => 25400),
        themeModeProvider.overrideWith((ref) => ThemeMode.light),
        hideBalanceProvider.overrideWith((ref) => hidden),
        avatarEnabledProvider.overrideWith((ref) => enabled),
        avatarColorsProvider.overrideWith((ref) => colors),
        avatarOutfitsProvider.overrideWith((ref) => outfits),
        avatarRendererFactoryProvider.overrideWithValue(factory),
      ],
      child: const MaterialApp(home: PortfolioScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(PortfolioScreen)),
  );
}

class _FakeOkxWebsocketService extends OkxWebsocketService {
  @override
  Stream<dynamic> get stream => const Stream.empty();

  @override
  void connect() {}

  @override
  void subscribeToTickers(List<String> coinSymbols) {}

  @override
  void disconnect() {}
}
