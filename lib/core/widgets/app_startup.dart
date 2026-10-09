import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    if (_hasValue) {
      return widget.builder(context, _value as T);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: AppStartupStatusView(isLoading: _isLoading, onRetry: _retry),
    );
  }
}

/// Monochrome, accessible status UI shared by pending and recoverable startup
/// failure states. It never displays an initialization exception.
class AppStartupStatusView extends StatelessWidget {
  const AppStartupStatusView({
    super.key,
    required this.isLoading,
    this.onRetry,
  });

  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion =
        mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;

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
                  if (isLoading)
                    Semantics(
                      key: const Key('app-startup-progress-semantics'),
                      label: 'Đang khởi tạo ứng dụng',
                      liveRegion: true,
                      child: ExcludeSemantics(
                        child: SizedBox.square(
                          dimension: 32,
                          child: reduceMotion
                              ? Icon(Icons.hourglass_empty, color: palette.ink)
                              : CircularProgressIndicator(
                                  color: palette.ink,
                                  strokeWidth: 2,
                                ),
                        ),
                      ),
                    )
                  else
                    Icon(Icons.error_outline, size: 32, color: palette.warning),
                  const SizedBox(height: AppTokens.space3),
                  Text(
                    isLoading
                        ? 'Đang khởi tạo ứng dụng…'
                        : 'Chưa thể khởi tạo ứng dụng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isLoading) ...[
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      'Vui lòng thử lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.muted),
                    ),
                    const SizedBox(height: AppTokens.space4),
                    FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
