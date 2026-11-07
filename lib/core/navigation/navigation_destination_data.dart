import 'package:flutter/material.dart';

class NavigationItemData {
  const NavigationItemData({
    required this.id,
    required this.screenIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final int screenIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const navigationHomeId = 'home';
const navigationOrdersId = 'orders';
const navigationMarketId = 'market';
const navigationToolsId = 'tools';
const navigationStrategyId = 'strategy';

const _homeItem = NavigationItemData(
  id: navigationHomeId,
  screenIndex: 0,
  label: 'Tài sản',
  icon: Icons.account_balance_wallet_outlined,
  selectedIcon: Icons.account_balance_wallet,
);

const _ordersItem = NavigationItemData(
  id: navigationOrdersId,
  screenIndex: 2,
  label: 'Lệnh',
  icon: Icons.receipt_long_outlined,
  selectedIcon: Icons.receipt_long,
);

const _marketItem = NavigationItemData(
  id: navigationMarketId,
  screenIndex: 3,
  label: 'Thị trường',
  icon: Icons.insights_outlined,
  selectedIcon: Icons.insights,
);

const _toolsItem = NavigationItemData(
  id: navigationToolsId,
  screenIndex: 8,
  label: 'Thêm',
  icon: Icons.grid_view_outlined,
  selectedIcon: Icons.grid_view,
);

const _strategyItem = NavigationItemData(
  id: navigationStrategyId,
  screenIndex: 7,
  label: 'Chiến thuật',
  icon: Icons.account_tree_outlined,
  selectedIcon: Icons.account_tree,
);

const navigationItems = <NavigationItemData>[
  _homeItem,
  _ordersItem,
  _marketItem,
  _toolsItem,
];

const navigationItemsWithStrategy = <NavigationItemData>[
  _homeItem,
  _ordersItem,
  _strategyItem,
  _marketItem,
  _toolsItem,
];

List<NavigationItemData> navigationItemsForBackendFeatures(bool enabled) =>
    enabled ? navigationItemsWithStrategy : navigationItems;
