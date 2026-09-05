import 'package:flutter/material.dart';

/// A destination shared by every in-app navigation presentation.
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

const navigationItems = <NavigationItemData>[
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
