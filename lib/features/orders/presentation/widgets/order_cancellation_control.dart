import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/okx_order_model.dart';
import '../providers/order_cancellation_flow_provider.dart';
import '../providers/position_action_flow_provider.dart';
import '../providers/trade_session_provider.dart';

class OrderCancellationControl extends ConsumerWidget {
  const OrderCancellationControl({super.key, required this.order});

  final OkxOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isActiveLimitOrder(order)) return const SizedBox.shrink();

    final api = ref.watch(tradeApiProvider);
    final sessionState = ref.watch(tradeSessionProvider);
    final session = sessionState.session;
    final flowStates = ref.watch(orderCancellationFlowProvider);
    final positionFlows = ref.watch(positionActionFlowsProvider);
    final accountIdentifier =
        session?.accountIdentifier ?? sessionState.operationAccountIdentifier;
    final flowKey = orderCancellationFlowKey(
      orderCancellationTargetIdentity(order),
      accountIdentifier,
    );
    final flow = flowStates[flowKey];
    final ownFlowIsBusy =
        flow?.isBusy == true && identical(flow?.sessionOwner, session);
    final accountLockActive =
        accountIdentifier != null &&
        ref
            .read(positionActionFlowsProvider.notifier)
            .isAccountActionActive(accountIdentifier);
    final positionFlowActive = positionFlows.values.any(
      (candidate) =>
          candidate.isBusy && candidate.accountIdentifier == accountIdentifier,
    );
    final canCancel =
        api.isConfigured &&
        sessionState.isAuthenticated &&
        session != null &&
        session.isActive &&
        hasCompleteOrderCancellationIdentity(order) &&
        sessionState.pendingOperations.isEmpty &&
        !accountLockActive &&
        !positionFlowActive &&
        !ownFlowIsBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            key: Key('order-cancel-${order.ordId}'),
            tooltip: 'Hủy lệnh limit',
            onPressed: canCancel
                ? () => ref
                      .read(orderCancellationFlowProvider.notifier)
                      .cancelOrder(
                        order: order,
                        navigator: Navigator.of(context),
                        ownerRoute: ModalRoute.of(context),
                      )
                : null,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.cancel_outlined),
          ),
        ),
        if (flow != null &&
            identical(flow.sessionOwner, session) &&
            flow.statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                flow.statusMessage!,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
