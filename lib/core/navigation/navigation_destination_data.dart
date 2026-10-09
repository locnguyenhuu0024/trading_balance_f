import 'package:flutter/material.dart';

/// A destination shared by every in-app navigation presentation.
class NavigationItemData {
  const NavigationItemData({
    required this.id,
    required this.screenIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Stable persisted identity, independent of the destination's visible slot.
  final String id;

  /// Original screen identity used by the navigation shell.
  final int screenIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const navigationHomeId = 'home';
const navigationBmagId = 'bmag';
const navigationOrdersId = 'orders';
const navigationMarketId = 'market';
const navigationSettingsId = 'settings';
const navigationSupportId = 'support';
const navigationStrategyId = 'strategy';

/// Canonical preference ordering for the stable navigation identities.
const navigationDestinationIds = <String>[
  navigationHomeId,
  navigationBmagId,
  navigationOrdersId,
  navigationMarketId,
  navigationSettingsId,
  navigationSupportId,
  navigationStrategyId,
];

const navigationItems = <NavigationItemData>[
  NavigationItemData(
    id: navigationHomeId,
    screenIndex: 0,
    label: 'Trang chủ',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  NavigationItemData(
    id: navigationBmagId,
    screenIndex: 1,
    label: 'BMAG',
    icon: Icons.donut_small_outlined,
    selectedIcon: Icons.donut_small,
  ),
  NavigationItemData(
    id: navigationOrdersId,
    screenIndex: 2,
    label: 'Lệnh',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  NavigationItemData(
    id: navigationMarketId,
    screenIndex: 3,
    label: 'Thị trường',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  ),
  NavigationItemData(
    id: navigationSettingsId,
    screenIndex: 4,
    label: 'Cài đặt',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  NavigationItemData(
    id: navigationSupportId,
    screenIndex: 6,
    label: 'Hỗ trợ',
    icon: Icons.stacked_line_chart_outlined,
    selectedIcon: Icons.stacked_line_chart,
  ),
  NavigationItemData(
    id: navigationStrategyId,
    screenIndex: 7,
    label: 'Chiến Thuật',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
  ),
];
