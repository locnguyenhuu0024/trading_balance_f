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

    return Semantics(
      container: true,
      label: 'Điều hướng chính',
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final islandWidth = constraints.maxWidth;

              return Center(
                child: SizedBox(
                  width: islandWidth,
                  height: 76,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 16,
                        right: 0,
                        bottom: 0,
                        left: 0,
                        child: Material(
                          key: const Key('navigation-bar-surface'),
                          color: surfaceColor,
                        ),
                      ),
                      Row(
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
                                  borderRadius: BorderRadius.circular(30),
                                  onTap: () => onDestinationSelected(index),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        left: 0,
                                        child: AnimatedSlide(
                                          duration: _animationDuration,
                                          curve: Curves.easeOutCubic,
                                          offset: Offset(
                                            0,
                                            isSelected ? 0 : 0.5,
                                          ),
                                          child: Center(
                                            child: AnimatedContainer(
                                              key: Key(
                                                'navigation-indicator-$index',
                                              ),
                                              duration: _animationDuration,
                                              curve: Curves.easeOutCubic,
                                              width: 46,
                                              height: 46,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? surfaceColor
                                                    : Colors.transparent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isSelected
                                                    ? item.selectedIcon
                                                    : item.icon,
                                                color: isSelected
                                                    ? contentColor
                                                    : contentColor.withValues(
                                                        alpha: 0.7,
                                                      ),
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 7,
                                            left: 2,
                                            right: 2,
                                          ),
                                          child: AnimatedSize(
                                            duration: _animationDuration,
                                            curve: Curves.easeOutCubic,
                                            child: isSelected
                                                ? Text(
                                                    item.label,
                                                    style: TextStyle(
                                                      color: contentColor,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
