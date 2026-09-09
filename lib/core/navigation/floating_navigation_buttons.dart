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
    this.buttonScale = 1,
    this.buttonOpacity = 0.5,
  });

  static const _targetSize = 52.0;
  static const _labelHeight = 16.0;
  static const _edgeGap = 12.0;

  final NavigationEdge edge;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;
  final double buttonScale;
  final double buttonOpacity;

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
    final buttonScale = _normalizeScale(this.buttonScale);
    final buttonOpacity = _normalizeOpacity(this.buttonOpacity);
    final targetSize = math.max(48.0, _targetSize * buttonScale).toDouble();
    final labelHeight = _labelHeight * buttonScale;
    final verticalSlotWidth = math
        .max(76.0, targetSize + 24 * buttonScale)
        .toDouble();

    Widget buttonBuilder(int index, bool horizontal) {
      return _FloatingDestinationButton(
        index: index,
        item: navigationItems[index],
        isSelected: index == selectedIndex,
        labelPlacement: horizontal && edge == NavigationEdge.bottom
            ? _LabelPlacement.before
            : _LabelPlacement.after,
        surfaceColor: surfaceColor,
        contentColor: contentColor,
        buttonScale: buttonScale,
        buttonOpacity: buttonOpacity,
        targetSize: targetSize,
        labelHeight: labelHeight,
        slotWidth: horizontal ? targetSize : verticalSlotWidth,
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
          targetSize: targetSize,
          labelHeight: labelHeight,
          buttonBuilder: (index) => buttonBuilder(index, true),
        ),
      ),
      NavigationEdge.bottom => Positioned(
        key: const Key('floating-navigation-group'),
        bottom: bottomOffset,
        left: mediaQuery.viewPadding.left + _edgeGap,
        right: mediaQuery.viewPadding.right + _edgeGap,
        child: _HorizontalNavigationGroup(
          targetSize: targetSize,
          labelHeight: labelHeight,
          buttonBuilder: (index) => buttonBuilder(index, true),
        ),
      ),
      NavigationEdge.left => Positioned(
        key: const Key('floating-navigation-group'),
        top: topOffset,
        bottom: bottomOffset,
        left: mediaQuery.viewPadding.left + _edgeGap,
        child: _VerticalNavigationGroup(
          targetSize: targetSize,
          labelHeight: labelHeight,
          slotWidth: verticalSlotWidth,
          buttonBuilder: (index) => buttonBuilder(index, false),
        ),
      ),
      NavigationEdge.right => Positioned(
        key: const Key('floating-navigation-group'),
        top: topOffset,
        bottom: bottomOffset,
        right: mediaQuery.viewPadding.right + _edgeGap,
        child: _VerticalNavigationGroup(
          targetSize: targetSize,
          labelHeight: labelHeight,
          slotWidth: verticalSlotWidth,
          buttonBuilder: (index) => buttonBuilder(index, false),
        ),
      ),
    };
  }

  static double _normalizeScale(double value) {
    if (!value.isFinite) return 1;
    return value.clamp(0.9, 1.1).toDouble();
  }

  static double _normalizeOpacity(double value) {
    if (!value.isFinite) return 0.5;
    return value.clamp(0.35, 1.0).toDouble();
  }
}

class _HorizontalNavigationGroup extends StatelessWidget {
  const _HorizontalNavigationGroup({
    required this.targetSize,
    required this.labelHeight,
    required this.buttonBuilder,
  });

  final double targetSize;
  final double labelHeight;
  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: targetSize + labelHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          const minimumGap = 4.0;
          final maxGap = 8.0 * targetSize / 52.0;
          final buttonWidth = targetSize * navigationItems.length;
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
  const _VerticalNavigationGroup({
    required this.targetSize,
    required this.labelHeight,
    required this.slotWidth,
    required this.buttonBuilder,
  });

  final double targetSize;
  final double labelHeight;
  final double slotWidth;
  final Widget Function(int index) buttonBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: slotWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          const minimumGap = 4.0;
          final maxGap = 8.0 * targetSize / 52.0;
          final itemHeight = targetSize + labelHeight;
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
    required this.labelPlacement,
    required this.surfaceColor,
    required this.contentColor,
    required this.buttonScale,
    required this.buttonOpacity,
    required this.targetSize,
    required this.labelHeight,
    required this.slotWidth,
    required this.duration,
    required this.onTap,
  });

  final int index;
  final NavigationItemData item;
  final bool isSelected;
  final _LabelPlacement labelPlacement;
  final Color surfaceColor;
  final Color contentColor;
  final double buttonScale;
  final double buttonOpacity;
  final double targetSize;
  final double labelHeight;
  final double slotWidth;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = SizedBox(
      height: labelHeight,
      width: slotWidth,
      child: AnimatedSwitcher(
        duration: duration,
        child: isSelected
            ? ExcludeSemantics(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surfaceColor.withValues(alpha: buttonOpacity),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4 * buttonScale,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          key: Key('floating-navigation-label-$index'),
                          maxLines: 1,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 10 * buttonScale,
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
          height: targetSize + labelHeight,
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
                  radius: targetSize / 2,
                  onTap: onTap,
                  child: SizedBox(
                    width: targetSize,
                    height: targetSize,
                    child: Center(
                      child: AnimatedContainer(
                        key: Key('floating-navigation-indicator-$index'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width: isSelected ? targetSize : 44 * buttonScale,
                        height: isSelected ? targetSize : 44 * buttonScale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: surfaceColor.withValues(alpha: buttonOpacity),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: 0.22 * buttonOpacity,
                              ),
                              blurRadius: 8 * buttonScale,
                              offset: Offset(0, 3 * buttonScale),
                            ),
                          ],
                        ),
                        child: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected
                              ? contentColor
                              : contentColor.withValues(alpha: 0.72),
                          size: 22 * buttonScale,
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
