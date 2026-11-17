import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_page_transition.dart';

typedef AppStartupInitializer<T> = Future<T> Function();
typedef AppStartupBuilder<T> = Widget Function(BuildContext context, T value);

/// Keeps the application tree behind a real startup state until restoration is
/// complete. Initialization starts after the first frame so this state is
/// visible even when setup begins with synchronous work.
class AppStartup<T> extends StatefulWidget {
  const AppStartup({
    super.key,
    required this.initialize,
    required this.builder,
  });

  final AppStartupInitializer<T> initialize;
  final AppStartupBuilder<T> builder;

  @override
  State<AppStartup<T>> createState() => _AppStartupState<T>();
}

class _AppStartupState<T> extends State<AppStartup<T>> {
  T? _value;
  var _hasValue = false;
  var _isLoading = true;
  var _attempt = 0;

  @override
  void initState() {
    super.initState();
    _scheduleInitialization();
  }

  void _scheduleInitialization() {
    final attempt = ++_attempt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && attempt == _attempt) {
        _initialize(attempt);
      }
    });
  }

  Future<void> _initialize(int attempt) async {
    try {
      final value = await widget.initialize();
      if (!mounted || attempt != _attempt) return;

      setState(() {
        _value = value;
        _hasValue = true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;

      setState(() {
        _hasValue = false;
        _isLoading = false;
      });
    }
  }

  void _retry() {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    _scheduleInitialization();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQueryData.fromView(View.of(context));
    final reduce = data.disableAnimations || data.accessibleNavigation;
    return AnimatedSwitcher(
      key: const Key('app-startup-handoff'),
      duration: reduce ? Duration.zero : AppTokens.motionMedium,
      switchInCurve: AppTokens.motionEnter,
      switchOutCurve: AppTokens.motionExit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: _hasValue
          ? KeyedSubtree(
              key: const ValueKey('app'),
              child: widget.builder(context, _value as T),
            )
          : KeyedSubtree(
              key: const ValueKey('startup'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.system,
                home: AppStartupStatusView(
                  isLoading: _isLoading,
                  onRetry: _retry,
                ),
              ),
            ),
    );
  }
}

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget bar(double height) => Container(
      width: size * 0.11,
      height: size * height,
      decoration: BoxDecoration(
        color: palette.onStrong,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.ink,
          borderRadius: BorderRadius.circular(AppTokens.radiusLarge),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bar(0.22),
              SizedBox(width: size * 0.08),
              bar(0.36),
              SizedBox(width: size * 0.08),
              bar(0.5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accessible status UI shared by startup and biometric checks.
class AppStartupStatusView extends StatefulWidget {
  const AppStartupStatusView({
    super.key,
    required this.isLoading,
    this.onRetry,
  });

  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  State<AppStartupStatusView> createState() => _AppStartupStatusViewState();
}

class _AppStartupStatusViewState extends State<AppStartupStatusView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markAnimation;
  late final Animation<double> _textAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.motionLong,
    )..forward();
    _markAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppTokens.motionEnter,
    );
    _textAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1.0, curve: AppTokens.motionEnter),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppPageTransitions.reduceMotion(MediaQuery.of(context))) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final reduceMotion = AppPageTransitions.reduceMotion(
      MediaQuery.of(context),
    );
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _markAnimation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.92,
                        end: 1,
                      ).animate(_markAnimation),
                      child: const AppBrandMark(
                        key: Key('app-startup-brand-mark'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _textAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Crypto Portfolio',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (widget.isLoading)
                          Text(
                            'Đang khởi tạo ứng dụng…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.muted,
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 20,
                                color: palette.warning,
                              ),
                              const SizedBox(width: AppTokens.space2),
                              Flexible(
                                child: Text(
                                  'Chưa thể khởi tạo ứng dụng.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (widget.isLoading) ...[
                          if (!reduceMotion) const SizedBox(height: 16),
                          Semantics(
                            key: const Key('app-startup-progress-semantics'),
                            label: 'Đang khởi tạo ứng dụng',
                            liveRegion: true,
                            child: ExcludeSemantics(
                              child: reduceMotion
                                  ? const SizedBox.shrink()
                                  : SizedBox(
                                      width: 120,
                                      height: 2,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(1),
                                        child: LinearProgressIndicator(
                                          color: palette.ink,
                                          backgroundColor: palette.border,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: AppTokens.space2),
                          Text(
                            'Vui lòng thử lại.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.muted),
                          ),
                          const SizedBox(height: AppTokens.space4),
                          FilledButton(
                            onPressed: widget.onRetry,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
