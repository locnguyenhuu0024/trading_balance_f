import 'package:flutter/material.dart';

class NavigationItemData {
  const NavigationItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class TradingNavigationBar extends StatelessWidget {
  const TradingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.isDark,
    required this.onDestinationSelected,
  });

  static const _animationDuration = Duration(milliseconds: 220);

  static const items = <NavigationItemData>[
    NavigationItemData(
      label: 'Trang chủ',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    NavigationItemData(
      label: 'BMAG',
      icon: Icons.donut_small_outlined,
      selectedIcon: Icons.donut_small,
    ),
    NavigationItemData(
      label: 'Lệnh',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    NavigationItemData(
      label: 'Thị trường',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
    NavigationItemData(
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = isDark ? Colors.white : Colors.black;
    final contentColor = isDark ? Colors.black : Colors.white;
    final indicatorColor = isDark ? Colors.black : Colors.white;
    final indicatorContentColor = isDark ? Colors.white : Colors.black;

    return Semantics(
      container: true,
      label: 'Điều hướng chính',
      child: Material(
        color: surfaceColor,
        child: SafeArea(
          top: false,
          child: Container(
            key: const Key('navigation-bar-surface'),
            height: 72,
            color: surfaceColor,
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == selectedIndex;

                return Expanded(
                  child: Semantics(
                    selected: isSelected,
                    button: true,
                    label: item.label,
                    child: Tooltip(
                      message: item.label,
                      child: InkWell(
                        key: Key('navigation-destination-$index'),
                        excludeFromSemantics: true,
                        onTap: () => onDestinationSelected(index),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSlide(
                                duration: _animationDuration,
                                curve: Curves.easeOutCubic,
                                offset: Offset(0, isSelected ? -0.2 : 0),
                                child: AnimatedContainer(
                                  key: Key('navigation-indicator-$index'),
                                  duration: _animationDuration,
                                  curve: Curves.easeOutCubic,
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? indicatorColor
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSelected ? item.selectedIcon : item.icon,
                                    color: isSelected
                                        ? indicatorContentColor
                                        : contentColor.withValues(alpha: 0.7),
                                    size: 22,
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: _animationDuration,
                                curve: Curves.easeOutCubic,
                                child: isSelected
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Text(
                                          item.label,
                                          style: TextStyle(
                                            color: contentColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
