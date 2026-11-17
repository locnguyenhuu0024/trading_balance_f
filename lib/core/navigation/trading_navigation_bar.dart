import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'navigation_destination_data.dart';

class TradingNavigationBar extends StatelessWidget {
  const TradingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
    this.destinations = navigationItems,
    this.bottomInset = 0,
  });

  static const barHeight = 76.0;
  static const crestHeight = 0.0;
  static const List<NavigationItemData> items = navigationItems;

  static double heightFor(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(11) * 1.4;
    return (24 + 4 + labelHeight + 24).clamp(barHeight, double.infinity);
  }

  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationItemData> destinations;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.forBrightness(isDark);
    final height = heightFor(context);
    return Semantics(
      container: true,
      label: 'Điều hướng chính',
      child: Container(
        key: const Key('navigation-bar-silhouette'),
        foregroundDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: Material(
          key: const Key('navigation-bar-surface'),
          color: palette.background,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              key: const Key('navigation-bar-layout'),
              height: height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width =
                      constraints.maxWidth < destinations.length * 48.0
                      ? destinations.length * 48.0
                      : constraints.maxWidth;
                  final row = SizedBox(
                    width: width,
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          Expanded(
                            child: Semantics(
                              selected: index == selectedIndex,
                              button: true,
                              label: destinations[index].label,
                              child: Tooltip(
                                message: destinations[index].label,
                                child: InkWell(
                                  key: Key('navigation-destination-$index'),
                                  excludeFromSemantics: true,
                                  onTap: () => onDestinationSelected(index),
                                  child: Container(
                                    key: Key('navigation-indicator-$index'),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: index == selectedIndex
                                          ? palette.surface
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          index == selectedIndex
                                              ? destinations[index].selectedIcon
                                              : destinations[index].icon,
                                          size: 24,
                                          color: index == selectedIndex
                                              ? palette.ink
                                              : palette.muted,
                                        ),
                                        const SizedBox(height: 4),
                                        ExcludeSemantics(
                                          child: Text(
                                            destinations[index].label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.4,
                                              color: index == selectedIndex
                                                  ? palette.ink
                                                  : palette.muted,
                                              fontWeight: index == selectedIndex
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  return width > constraints.maxWidth
                      ? SingleChildScrollView(
                          key: const Key('navigation-bar-horizontal-scroll'),
                          scrollDirection: Axis.horizontal,
                          child: row,
                        )
                      : row;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
