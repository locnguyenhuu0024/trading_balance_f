import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'navigation_destination_data.dart';

/// Full-width fixed navigation with a raised, tangent-continuous selection.
class TradingNavigationBar extends StatefulWidget {
  const TradingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
    this.bottomInset = 0,
  });

  static const barHeight = 60.0;
  static const crestHeight = 16.0;
  static const _animationDuration = Duration(milliseconds: 220);

  /// Kept as a compatibility entry point for existing callers and tests.
  static const List<NavigationItemData> items = navigationItems;

  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;
  final double bottomInset;

  @override
  State<TradingNavigationBar> createState() => _TradingNavigationBarState();
}

class _TradingNavigationBarState extends State<TradingNavigationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.selectedIndex;
    _selectionController = AnimationController(
      vsync: this,
      duration: TradingNavigationBar._animationDuration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant TradingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;

    _previousIndex = oldWidget.selectedIndex;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _selectionController.value = 1;
    } else {
      _selectionController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = widget.isDark ? Colors.white : Colors.black;
    final contentColor = widget.isDark ? Colors.black : Colors.white;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final duration = disableAnimations
        ? Duration.zero
        : TradingNavigationBar._animationDuration;

    if (disableAnimations && _selectionController.value != 1) {
      _selectionController.value = 1;
    }

    return Semantics(
      container: true,
      label: 'Điều hướng chính',
      child: RepaintBoundary(
        child: SizedBox(
          height:
              TradingNavigationBar.crestHeight +
              TradingNavigationBar.barHeight +
              widget.bottomInset,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const barTop = TradingNavigationBar.crestHeight;
              final cellWidth =
                  constraints.maxWidth / TradingNavigationBar.items.length;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _selectionController,
                        builder: (context, _) {
                          return CustomPaint(
                            key: const Key('navigation-bar-silhouette'),
                            painter: _NavigationSurfacePainter(
                              color: surfaceColor,
                              barTop: barTop,
                              barHeight: TradingNavigationBar.barHeight,
                              selectedIndex: widget.selectedIndex,
                              previousIndex: _previousIndex,
                              destinationCount:
                                  TradingNavigationBar.items.length,
                              progress: Curves.easeOutCubic.transform(
                                disableAnimations
                                    ? 1
                                    : _selectionController.value,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: barTop,
                    left: 0,
                    right: 0,
                    height: TradingNavigationBar.barHeight,
                    child: Material(
                      key: const Key('navigation-bar-surface'),
                      color: surfaceColor,
                      child: const SizedBox(key: Key('navigation-bar-layout')),
                    ),
                  ),
                  for (
                    var index = 0;
                    index < TradingNavigationBar.items.length;
                    index++
                  )
                    _DestinationControl(
                      index: index,
                      item: TradingNavigationBar.items[index],
                      isSelected: index == widget.selectedIndex,
                      cellLeft: cellWidth * index,
                      cellWidth: cellWidth,
                      surfaceColor: surfaceColor,
                      contentColor: contentColor,
                      duration: duration,
                      onTap: () => widget.onDestinationSelected(index),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DestinationControl extends StatelessWidget {
  const _DestinationControl({
    required this.index,
    required this.item,
    required this.isSelected,
    required this.cellLeft,
    required this.cellWidth,
    required this.surfaceColor,
    required this.contentColor,
    required this.duration,
    required this.onTap,
  });

  static const _targetSize = 52.0;
  static const _indicatorSize = 46.0;

  final int index;
  final NavigationItemData item;
  final bool isSelected;
  final double cellLeft;
  final double cellWidth;
  final Color surfaceColor;
  final Color contentColor;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final centeredLeft = cellLeft + (cellWidth - _targetSize) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: duration,
          curve: Curves.easeOutCubic,
          left: centeredLeft,
          top: isSelected ? 0 : 20,
          width: _targetSize,
          height: _targetSize,
          child: Semantics(
            selected: isSelected,
            button: true,
            label: item.label,
            child: Tooltip(
              message: item.label,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  key: Key('navigation-destination-$index'),
                  excludeFromSemantics: true,
                  containedInkWell: true,
                  highlightShape: BoxShape.circle,
                  radius: _targetSize / 2,
                  onTap: onTap,
                  child: SizedBox(
                    width: _targetSize,
                    height: _targetSize,
                    child: AnimatedAlign(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      alignment: isSelected
                          ? Alignment.topCenter
                          : Alignment.center,
                      child: AnimatedContainer(
                        key: Key('navigation-indicator-$index'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width: _indicatorSize,
                        height: _indicatorSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? surfaceColor : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected
                              ? contentColor
                              : contentColor.withValues(alpha: 0.7),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 48,
          left: cellLeft,
          width: cellWidth,
          height: 22,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: isSelected
                    ? ExcludeSemantics(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavigationSurfacePainter extends CustomPainter {
  const _NavigationSurfacePainter({
    required this.color,
    required this.barTop,
    required this.barHeight,
    required this.selectedIndex,
    required this.previousIndex,
    required this.destinationCount,
    required this.progress,
  });

  final Color color;
  final double barTop;
  final double barHeight;
  final int selectedIndex;
  final int previousIndex;
  final int destinationCount;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    // The rectangle and contour caps deliberately use the same paint so there
    // is no outline or differently coloured seam between them.
    canvas.drawRect(Rect.fromLTWH(0, barTop, size.width, barHeight), paint);

    if (previousIndex == selectedIndex || progress >= 1) {
      _drawContour(canvas, size, selectedIndex, 1, paint);
      return;
    }

    _drawContour(canvas, size, previousIndex, 1 - progress, paint);
    _drawContour(canvas, size, selectedIndex, progress, paint);
  }

  void _drawContour(
    Canvas canvas,
    Size size,
    int index,
    double value,
    Paint paint,
  ) {
    if (value <= 0 || index < 0 || index >= destinationCount) return;

    const radius = 23.0;
    const desiredShoulderReach = 12.0;
    const maxShoulderAngle = 0.7;
    final crestRise = TradingNavigationBar.crestHeight * value;
    final centerX = size.width * (index + 0.5) / destinationCount;
    final centerY = barTop + radius - crestRise;
    final angularSpread = maxShoulderAngle * value;
    final leftAngle = math.pi * 1.5 - angularSpread;
    final rightAngle = math.pi * 1.5 + angularSpread;
    final leftJoin = Offset(
      centerX + radius * math.cos(leftAngle),
      centerY + radius * math.sin(leftAngle),
    );
    final rightJoin = Offset(
      centerX + radius * math.cos(rightAngle),
      centerY + radius * math.sin(rightAngle),
    );
    final reachableShoulder = math.max(
      0,
      math.min(leftJoin.dx, size.width - rightJoin.dx),
    );
    final shoulderReach = math.min(
      desiredShoulderReach * value,
      reachableShoulder,
    );
    final leftStart = Offset(leftJoin.dx - shoulderReach, barTop);
    final rightEnd = Offset(rightJoin.dx + shoulderReach, barTop);
    final sweepAngle = rightAngle - leftAngle;
    final leftTangent = Offset(-math.sin(leftAngle), math.cos(leftAngle));
    final rightTangent = Offset(-math.sin(rightAngle), math.cos(rightAngle));
    final tangentLength = 10 * value;

    final path = Path()
      ..moveTo(leftStart.dx, leftStart.dy)
      ..cubicTo(
        leftStart.dx + shoulderReach * 0.5,
        leftStart.dy,
        leftJoin.dx - leftTangent.dx * tangentLength,
        leftJoin.dy - leftTangent.dy * tangentLength,
        leftJoin.dx,
        leftJoin.dy,
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
        leftAngle,
        sweepAngle,
        false,
      )
      ..cubicTo(
        rightJoin.dx + rightTangent.dx * tangentLength,
        rightJoin.dy + rightTangent.dy * tangentLength,
        rightEnd.dx - shoulderReach * 0.5,
        rightEnd.dy,
        rightEnd.dx,
        rightEnd.dy,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NavigationSurfacePainter oldDelegate) {
    return color != oldDelegate.color ||
        barTop != oldDelegate.barTop ||
        barHeight != oldDelegate.barHeight ||
        selectedIndex != oldDelegate.selectedIndex ||
        previousIndex != oldDelegate.previousIndex ||
        destinationCount != oldDelegate.destinationCount ||
        progress != oldDelegate.progress;
  }
}
