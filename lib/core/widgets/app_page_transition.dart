import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppPageTransitions {
  static const destinationDuration = AppTokens.motionShort;
  static const routeDuration = AppTokens.motionStandard;

  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: AppFadePageTransitionsBuilder(),
      TargetPlatform.fuchsia: AppFadePageTransitionsBuilder(),
      TargetPlatform.iOS: AppCupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: AppFadePageTransitionsBuilder(),
      TargetPlatform.macOS: AppCupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: AppFadePageTransitionsBuilder(),
    },
  );

  static bool reduceMotion(MediaQueryData mediaQuery) =>
      mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;

  static Animation<double> settledAnimation(Animation<double> animation) =>
      switch (animation.status) {
        AnimationStatus.dismissed ||
        AnimationStatus.reverse => kAlwaysDismissedAnimation,
        AnimationStatus.forward ||
        AnimationStatus.completed => kAlwaysCompleteAnimation,
      };
}

/// Fades in only the current destination. A changed destination replaces and
/// disposes the old subtree immediately, so it cannot keep interactions or
/// late reads alive for the duration of the fade.
class AppDestinationTransition extends StatefulWidget {
  const AppDestinationTransition({
    super.key,
    required this.destinationId,
    required this.child,
  });

  final int destinationId;
  final Widget child;

  @override
  State<AppDestinationTransition> createState() =>
      _AppDestinationTransitionState();
}

class _AppDestinationTransitionState extends State<AppDestinationTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppPageTransitions.destinationDuration,
    value: 1,
  );
  late final Animation<double> _opacity = CurveTween(
    curve: Curves.easeOut,
  ).animate(_controller);
  var _transitionGeneration = 0;
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = AppPageTransitions.reduceMotion(
      MediaQuery.of(context),
    );
    if (_reduceMotion == reduceMotion) return;

    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _transitionGeneration++;
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AppDestinationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationId == widget.destinationId) return;

    final generation = ++_transitionGeneration;
    final reduceMotion = AppPageTransitions.reduceMotion(
      MediaQuery.of(context),
    );
    _controller.stop();
    _controller.value = reduceMotion ? 1 : 0;
    if (reduceMotion) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _transitionGeneration) return;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: const Key('app-destination-fade'),
      opacity: _opacity,
      child: widget.child,
    );
  }
}

class AppFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppPageTransitions.routeDuration;

  @override
  Duration get reverseTransitionDuration => AppPageTransitions.routeDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = AppPageTransitions.reduceMotion(
      MediaQuery.of(context),
    );

    final respectMotion = !reduceMotion || route.popGestureInProgress;
    final enteringAnimation = respectMotion
        ? animation
        : AppPageTransitions.settledAnimation(animation);
    final coveredAnimation = respectMotion
        ? secondaryAnimation
        : AppPageTransitions.settledAnimation(secondaryAnimation);
    final Animation<double> opacity = enteringAnimation.drive(
      CurveTween(curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([enteringAnimation, coveredAnimation]),
      child: FadeTransition(
        key: const Key('app-route-fade'),
        opacity: opacity,
        child: child,
      ),
      builder: (context, child) {
        final isCovered = coveredAnimation.status != AnimationStatus.dismissed;
        final isEntering =
            enteringAnimation.status == AnimationStatus.completed;
        final blockInteraction = isCovered || !isEntering;
        return IgnorePointer(
          key: const Key('app-route-ignore-pointer'),
          ignoring: blockInteraction,
          child: ExcludeSemantics(
            key: const Key('app-route-exclude-semantics'),
            excluding: blockInteraction,
            child: child,
          ),
        );
      },
    );
  }
}

class AppCupertinoPageTransitionsBuilder
    extends CupertinoPageTransitionsBuilder {
  const AppCupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion =
        AppPageTransitions.reduceMotion(MediaQuery.of(context)) &&
        !route.popGestureInProgress;
    return super.buildTransitions(
      route,
      context,
      reduceMotion ? AppPageTransitions.settledAnimation(animation) : animation,
      reduceMotion
          ? AppPageTransitions.settledAnimation(secondaryAnimation)
          : secondaryAnimation,
      child,
    );
  }
}
