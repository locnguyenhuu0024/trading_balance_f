import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'
    show isDarkModeProvider;
import 'package:trading_balance_f/features/settings/presentation/settings_screen.dart'
    show themeModeProvider;
import 'package:trading_balance_f/main.dart' show TradingBalanceApp;
import 'package:trading_balance_f/core/theme/app_theme.dart';
import 'package:trading_balance_f/core/theme/platform_brightness_provider.dart';

void main() {
  group('AppTheme', () {
    test('provides neutral light and dark color schemes', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.colorScheme.brightness, theme.brightness);
        expect(
          theme.colorScheme.primary,
          AppPalette.forBrightness(theme.brightness == Brightness.dark).ink,
        );
        expect(theme.cardTheme.elevation, 0);
        for (final color in _schemeColors(theme.colorScheme)) {
          expect(color.red, color.green);
          expect(color.green, color.blue);
        }
      }

      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('body and secondary text meet WCAG AA contrast on their surfaces', () {
      for (final dark in [false, true]) {
        final palette = AppPalette.forBrightness(dark);
        expect(
          _contrast(palette.ink, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.muted, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.muted, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.negative, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.warning, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.onStrong, palette.ink),
          greaterThanOrEqualTo(4.5),
        );
        for (final semanticText in [
          palette.positive,
          palette.negative,
          palette.warning,
        ]) {
          final chipSurface = Color.alphaBlend(
            semanticText.withValues(alpha: 0.12),
            palette.raised,
          );
          expect(
            _contrast(semanticText, chipSurface),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    });

    test('primary controls keep a 48 pixel minimum target', () {
      expect(
        AppTheme.light.elevatedButtonTheme.style!.minimumSize!.resolve({}),
        const Size(AppTokens.minimumTouchTarget, AppTokens.minimumTouchTarget),
      );
      expect(
        AppTheme.dark.iconButtonTheme.style!.minimumSize!.resolve({}),
        const Size(AppTokens.minimumTouchTarget, AppTokens.minimumTouchTarget),
      );
    });

    test('disabled controls use distinct readable grayscale states', () {
      final light = AppTheme.light;
      final dark = AppTheme.dark;
      final disabledSelected = {WidgetState.selected, WidgetState.disabled};
      final disabled = {WidgetState.disabled};

      final lightCheckboxFill = light.checkboxTheme.fillColor!.resolve(
        disabledSelected,
      )!;
      final lightCheckboxCheck = light.checkboxTheme.checkColor!.resolve(
        disabledSelected,
      )!;
      expect(lightCheckboxFill, const Color(0xFFE0E0E0));
      expect(
        light.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
        light.colorScheme.primary,
      );
      expect(
        _contrast(lightCheckboxCheck, lightCheckboxFill),
        greaterThanOrEqualTo(4.5),
      );

      final lightRadioDisabled = light.radioTheme.fillColor!.resolve(disabled)!;
      final lightRadioEnabled = light.radioTheme.fillColor!.resolve({})!;
      expect(lightRadioDisabled, const Color(0xFF707070));
      expect(lightRadioDisabled, isNot(lightRadioEnabled));
      expect(
        _contrast(lightRadioDisabled, AppPalette.light.surface),
        greaterThanOrEqualTo(4.5),
      );

      final lightSwitchTrack = light.switchTheme.trackColor!.resolve(disabled)!;
      expect(lightSwitchTrack, const Color(0xFFE0E0E0));
      expect(
        lightSwitchTrack,
        isNot(light.switchTheme.trackColor!.resolve({WidgetState.selected})),
      );

      final darkRadioDisabled = dark.radioTheme.fillColor!.resolve(disabled)!;
      expect(darkRadioDisabled, const Color(0xFF929292));
      expect(darkRadioDisabled, isNot(dark.radioTheme.fillColor!.resolve({})!));
    });
  });

  testWidgets('platform brightness provider updates when system mode changes', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final observer = container.read(platformBrightnessProvider);
    final originalBrightness =
        tester.binding.platformDispatcher.platformBrightness;
    final targetBrightness = originalBrightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        targetBrightness;
    await tester.pump();

    expect(observer.brightness, targetBrightness);
    expect(observer.isDark, targetBrightness == Brightness.dark);

    await tester.pumpAndSettle();
  });

  testWidgets('explicit dark mode wins while the platform is light', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(_rootProbe(ThemeMode.dark));

    expect(find.text('dark|dark'), findsOneWidget);
  });

  testWidgets('explicit light mode wins while the platform is dark', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpWidget(_rootProbe(ThemeMode.light));

    expect(find.text('light|light'), findsOneWidget);
  });

  testWidgets('system mode updates root and legacy brightness together', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(_rootProbe(ThemeMode.system));
    expect(find.text('light|light'), findsOneWidget);

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();

    expect(find.text('dark|dark'), findsOneWidget);
  });

  testWidgets('selecting a user mode updates the root immediately', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(_rootProbe(ThemeMode.system));
    expect(find.text('light|light'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-dark-theme')));
    await tester.pumpAndSettle();

    expect(find.text('dark|dark'), findsOneWidget);
  });
}

Widget _rootProbe(ThemeMode mode) => ProviderScope(
  overrides: [themeModeProvider.overrideWith((ref) => mode)],
  child: const TradingBalanceApp(
    requireBiometrics: false,
    home: _BrightnessProbe(),
  ),
);

class _BrightnessProbe extends ConsumerWidget {
  const _BrightnessProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness.name;
    final legacyMode = ref.watch(isDarkModeProvider) ? 'dark' : 'light';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$brightness|$legacyMode'),
        TextButton(
          key: const Key('select-dark-theme'),
          onPressed: () =>
              ref.read(themeModeProvider.notifier).state = ThemeMode.dark,
          child: const Text('Dark'),
        ),
      ],
    );
  }
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

List<Color> _schemeColors(ColorScheme scheme) => [
  scheme.primary,
  scheme.onPrimary,
  scheme.primaryContainer,
  scheme.onPrimaryContainer,
  scheme.primaryFixed,
  scheme.primaryFixedDim,
  scheme.onPrimaryFixed,
  scheme.onPrimaryFixedVariant,
  scheme.secondary,
  scheme.onSecondary,
  scheme.secondaryContainer,
  scheme.onSecondaryContainer,
  scheme.secondaryFixed,
  scheme.secondaryFixedDim,
  scheme.onSecondaryFixed,
  scheme.onSecondaryFixedVariant,
  scheme.tertiary,
  scheme.onTertiary,
  scheme.tertiaryContainer,
  scheme.onTertiaryContainer,
  scheme.tertiaryFixed,
  scheme.tertiaryFixedDim,
  scheme.onTertiaryFixed,
  scheme.onTertiaryFixedVariant,
  scheme.error,
  scheme.onError,
  scheme.errorContainer,
  scheme.onErrorContainer,
  scheme.surface,
  scheme.onSurface,
  scheme.surfaceDim,
  scheme.surfaceBright,
  scheme.surfaceContainerLowest,
  scheme.surfaceContainerLow,
  scheme.surfaceContainer,
  scheme.surfaceContainerHigh,
  scheme.surfaceContainerHighest,
  scheme.onSurfaceVariant,
  scheme.outline,
  scheme.outlineVariant,
  scheme.shadow,
  scheme.scrim,
  scheme.inverseSurface,
  scheme.onInverseSurface,
  scheme.inversePrimary,
  scheme.surfaceTint,
];
