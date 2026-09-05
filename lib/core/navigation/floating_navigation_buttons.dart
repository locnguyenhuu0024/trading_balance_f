import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'navigation_destination_data.dart';
import 'navigation_preferences.dart';

/// Five independent navigation buttons anchored to one physical screen edge.
/// Decorative gaps intentionally have no hit-testable widget above the page.
class FloatingNavigationButtons extends StatelessWidget {
  const FloatingNavigationButtons({
    super.key,
    required this.edge,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
  });

  static const _targetSize = 52.0;
  static const _labelHeight = 16.0;
  static const _edgeGap = 12.0;

  final NavigationEdge edge;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.viewInsets.bottom,
    );
    final topOffset = mediaQuery.viewPadding.top + kToolbarHeight + _edgeGap;
    final bottomOffset = bottomInset + _edgeGap;
    final surfaceColor = isDark ? Colors.white : Colors.black;
    final contentColor = isDark ? Colors.black : Colors.white;
    final duration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    Widget buttonBuilder(int index, bool horizontal) {
      return _FloatingDestinationButton(
        index: index,
        item: navigationItems[index],
        isSelected: index == selectedIndex,
        horizontal: horizontal,
        labelPlacement: horizontal && edge == NavigationEdge.bottom
            ? _LabelPlacement.before
            : _LabelPlacement.after,
        surfaceColor: surfaceColor,
        contentColor: contentColor,
        duration: duration,
        onTap: () => onDestinationSelected(index),
      );
    }

    return switch (edge) {
      NavigationEdge.top => Positioned(
        key: const Key('floating-navigation-group'),
        top: topOffset,
        left: mediaQuery.viewPadding.left + _edgeGap,
        right: mediaQuery.viewPadding.right + _edgeGap,
        child: _HorizontalNavigationGroup(
          buttonBuilder: (index) => buttonBuilder(index, true),
        ),
      ),
      NavigationEdge.bottom => Positioned(
        key: const Key('floating-navigation-group'),
        bottom: bottomOffset,
        left: mediaQuery.viewPadding.left + _edgeGap,
        right: mediaQuery.viewPadding.right + _edgeGap,
        child: _HorizontalNavigationGroup(
          buttonBuilder: (index) => buttonBuilder(index, true),
        ),
      ),
      NavigationEdge.left => Positioned(
        key: const Key('floating-navigation-group'),
        top: topOffset,
        bottom: bottomOffset,
        left: mediaQuery.viewPadding.left + _edgeGap,
        child: _VerticalNavigationGroup(
          buttonBuilder: (index) => buttonBuilder(index, false),
        ),
      ),
      NavigationEdge.right => Positioned(
        key: const Key('floating-navigation-group'),
        top: topOffset,
        bottom: bottomOffset,
        right: mediaQuery.viewPadding.right + _edgeGap,
        child: _VerticalNavigationGroup(
          buttonBuilder: (index) => buttonBuilder(index, false),
        ),
      ),
    };
  }
}

class _HorizontalNavigationGroup extends StatelessWidget {
  const _HorizontalNavigationGroup({required this.buttonBuilder});

  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          FloatingNavigationButtons._targetSize +
          FloatingNavigationButtons._labelHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          const minimumGap = 4.0;
          const maxGap = 8.0;
          final buttonWidth =
              FloatingNavigationButtons._targetSize * navigationItems.length;
          final gap = math.min(
            maxGap,
            math.max(
              minimumGap,
              (availableWidth - buttonWidth) / (navigationItems.length - 1),
            ),
          );
          final requiredWidth =
              buttonWidth + gap * (navigationItems.length - 1);
          final group = _HorizontalButtons(
            gap: gap,
            buttonBuilder: buttonBuilder,
          );

          if (requiredWidth <= availableWidth) {
            return Center(child: group);
          }

          return SingleChildScrollView(
            key: const Key('floating-navigation-horizontal-scroll'),
            scrollDirection: Axis.horizontal,
            child: group,
          );
        },
      ),
    );
  }
}

class _HorizontalButtons extends StatelessWidget {
  const _HorizontalButtons({required this.gap, required this.buttonBuilder});

  final double gap;
  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < navigationItems.length; index++) ...[
          buttonBuilder(index),
          if (index < navigationItems.length - 1) SizedBox(width: gap),
        ],
      ],
    );
  }
}

class _VerticalNavigationGroup extends StatelessWidget {
  const _VerticalNavigationGroup({required this.buttonBuilder});

  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          const minimumGap = 4.0;
          const maxGap = 8.0;
          const itemHeight =
              FloatingNavigationButtons._targetSize +
              FloatingNavigationButtons._labelHeight;
          final buttonHeight = itemHeight * navigationItems.length;
          final gap = math.min(
            maxGap,
            math.max(
              minimumGap,
              (availableHeight - buttonHeight) / (navigationItems.length - 1),
            ),
          );
          final requiredHeight =
              buttonHeight + gap * (navigationItems.length - 1);
          final group = _VerticalButtons(
            gap: gap,
            buttonBuilder: buttonBuilder,
          );

          if (requiredHeight <= availableHeight) {
            return Center(child: group);
          }

          return SingleChildScrollView(
            key: const Key('floating-navigation-vertical-scroll'),
            child: group,
          );
        },
      ),
    );
  }
}

class _VerticalButtons extends StatelessWidget {
  const _VerticalButtons({required this.gap, required this.buttonBuilder});

  final double gap;
  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < navigationItems.length; index++) ...[
          buttonBuilder(index),
          if (index < navigationItems.length - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}

enum _LabelPlacement { before, after }

class _FloatingDestinationButton extends StatelessWidget {
  const _FloatingDestinationButton({
    required this.index,
    required this.item,
    required this.isSelected,
    required this.horizontal,
    required this.labelPlacement,
    required this.surfaceColor,
    required this.contentColor,
    required this.duration,
    required this.onTap,
  });

  final int index;
  final NavigationItemData item;
  final bool isSelected;
  final bool horizontal;
  final _LabelPlacement labelPlacement;
  final Color surfaceColor;
  final Color contentColor;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final slotWidth = horizontal ? FloatingNavigationButtons._targetSize : 76.0;
    final label = SizedBox(
      height: FloatingNavigationButtons._labelHeight,
      width: slotWidth,
      child: AnimatedSwitcher(
        duration: duration,
        child: isSelected
            ? ExcludeSemantics(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          key: Key('floating-navigation-label-$index'),
                          maxLines: 1,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );

    return Semantics(
      selected: isSelected,
      button: true,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: SizedBox(
          width: slotWidth,
          height:
              FloatingNavigationButtons._targetSize +
              FloatingNavigationButtons._labelHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (labelPlacement == _LabelPlacement.before) label,
              Material(
                color: Colors.transparent,
                child: InkResponse(
                  key: Key('floating-navigation-destination-$index'),
                  excludeFromSemantics: true,
                  containedInkWell: true,
                  highlightShape: BoxShape.circle,
                  radius: FloatingNavigationButtons._targetSize / 2,
                  onTap: onTap,
                  child: SizedBox(
                    width: FloatingNavigationButtons._targetSize,
                    height: FloatingNavigationButtons._targetSize,
                    child: Center(
                      child: AnimatedContainer(
                        key: Key('floating-navigation-indicator-$index'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width: isSelected
                            ? FloatingNavigationButtons._targetSize
                            : 44,
                        height: isSelected
                            ? FloatingNavigationButtons._targetSize
                            : 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected
                              ? contentColor
                              : contentColor.withValues(alpha: 0.72),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (labelPlacement == _LabelPlacement.after) label,
            ],
          ),
        ),
      ),
    );
  }
}
