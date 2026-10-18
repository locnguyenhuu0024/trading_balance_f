// File Name: order_provider.dart
// File Path: lib/features/orders/presentation/providers/order_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/okx_read_scope.dart';
import '../../data/order_repository.dart';
import '../../data/okx_order_model.dart';
import '../../data/okx_position_model.dart';

/// Local display filters are independent of backend trade-session state.
final orderFilterProvider = StateProvider<String>((ref) => 'ALL');

enum OrderTab { positions, pending, history }

final orderTabProvider = StateProvider<OrderTab>((ref) => OrderTab.positions);

/// Direct authenticated OKX orders for the selected display tab.
final ordersFutureProvider = FutureProvider.autoDispose<List<OkxOrder>>((
  ref,
) async {
  final currentFilter = ref.watch(orderFilterProvider);
  final currentTab = ref.watch(orderTabProvider);
  if (currentTab == OrderTab.positions) return const <OkxOrder>[];

  final repository = ref.read(orderRepositoryProvider);
  final requestType = currentTab == OrderTab.pending ? 'pending' : 'history';
  return runOkxPrivateRead<List<OkxOrder>>(
    ref: ref,
    requestKey: 'orders/$requestType/$currentFilter',
    load: (cancelToken) => currentTab == OrderTab.pending
        ? repository.getPendingOrders(
            instType: currentFilter,
            cancelToken: cancelToken,
          )
        : repository.getOrdersHistory(
            instType: currentFilter,
            cancelToken: cancelToken,
          ),
  );
});

/// Direct native positions used for visible display cards. Trading actions
/// continue to use the separately loaded authoritative backend snapshot.
final positionsFutureProvider = FutureProvider.autoDispose<List<OkxPosition>>((
  ref,
) async {
  final currentFilter = ref.watch(orderFilterProvider);
  if (currentFilter == 'SPOT') return const <OkxPosition>[];

  final repository = ref.read(orderRepositoryProvider);
  return runOkxPrivateRead<List<OkxPosition>>(
    ref: ref,
    requestKey: 'orders/positions/display/$currentFilter',
    load: (cancelToken) => repository.getOpenPositions(
      instType: currentFilter,
      cancelToken: cancelToken,
    ),
  );
});
