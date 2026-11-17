import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import 'app_page_transition.dart';

class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key = const Key('app-skeleton'),
    this.itemCount = 6,
    this.itemHeight = 72,
    this.caption = 'Đang tải dữ liệu…',
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
  });

  final int itemCount;
  final double itemHeight;
  final String caption;
  final EdgeInsetsGeometry padding;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppPageTransitions.reduceMotion(MediaQuery.of(context));
    if (_reduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
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
    Widget bar(double fraction, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: fraction,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.border,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
    final placeholders = Column(
      children: [
        for (var i = 0; i < widget.itemCount; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Container(
            key: ValueKey('app-skeleton-placeholder-$i'),
            height: widget.itemHeight,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.border,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      bar(.6, 10),
                      const SizedBox(height: 8),
                      bar(.35, 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            widget.caption,
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: _reduced
              ? placeholders
              : AnimatedBuilder(
                  animation: _controller,
                  child: placeholders,
                  builder: (context, child) => ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        Colors.transparent,
                        palette.raised.withValues(alpha: .55),
                        Colors.transparent,
                      ],
                      stops: const [.35, .5, .65],
                      transform: _ShimmerTransform(_controller.value),
                    ).createShader(bounds),
                    child: child,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ShimmerTransform extends GradientTransform {
  const _ShimmerTransform(this.value);
  final double value;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues((value * 2 - 1) * bounds.width, 0, 0);
}

class AppEntranceScope extends StatefulWidget {
  const AppEntranceScope({super.key, required this.child});
  final Widget child;

  static bool canAnimate(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AppEntranceScopeData>();
    return scope != null &&
        SchedulerBinding.instance.currentFrameTimeStamp - scope.startFrame <=
            scope.window;
  }

  @override
  State<AppEntranceScope> createState() => _AppEntranceScopeState();
}

class _AppEntranceScopeState extends State<AppEntranceScope> {
  Duration? _startFrame;
  @override
  Widget build(BuildContext context) => _AppEntranceScopeData(
    startFrame: _startFrame ??= SchedulerBinding.instance.currentFrameTimeStamp,
    window: AppTokens.motionLong + AppTokens.motionStagger * 8,
    child: widget.child,
  );
}

class _AppEntranceScopeData extends InheritedWidget {
  const _AppEntranceScopeData({
    required this.startFrame,
    required this.window,
    required super.child,
  });
  final Duration startFrame;
  final Duration window;
  @override
  bool updateShouldNotify(_AppEntranceScopeData oldWidget) =>
      startFrame != oldWidget.startFrame || window != oldWidget.window;
}

class AppEntrance extends StatefulWidget {
  const AppEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;
  bool _decided = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.index < 8 &&
        AppEntranceScope.canAnimate(context) &&
        !AppPageTransitions.reduceMotion(MediaQuery.of(context))) {
      final delay = AppTokens.motionStagger * widget.index;
      final total = AppTokens.motionMedium + delay;
      _controller = AnimationController(vsync: this, duration: total);
      _animation = CurvedAnimation(
        parent: _controller!,
        curve: Interval(
          delay.inMicroseconds / total.inMicroseconds,
          1,
          curve: AppTokens.motionEnter,
        ),
      );
      _controller!.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _animation;
    if (animation == null) return widget.child;
    return FadeTransition(
      opacity: animation,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: animation,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            0,
            AppTokens.motionEntranceOffset * (1 - animation.value),
          ),
          child: child,
        ),
      ),
    );
  }
}
