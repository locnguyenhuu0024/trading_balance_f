import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/orders/presentation/providers/order_provider.dart';

void main() {
  testWidgets('keeps an explicit transaction type across reads and rebuilds', (
    tester,
  ) async {
    late StateSetter rebuildParent;

    await tester.pumpWidget(
      ProviderScope(
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuildParent = setState;
            return const _OrderFilterText();
          },
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_OrderFilterText)),
    );
    container.read(orderFilterProvider.notifier).state = 'SWAP';
    await tester.pump();
    expect(container.read(orderFilterProvider), 'SWAP');
    expect(find.text('SWAP'), findsOneWidget);

    rebuildParent(() {});
    await tester.pump();
    expect(container.read(orderFilterProvider), 'SWAP');
    expect(find.text('SWAP'), findsOneWidget);
  });

  testWidgets('starts a fresh scope at ALL with Positions selected', (
    tester,
  ) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const _OrderFilterText();
          },
        ),
      ),
    );

    expect(find.text('ALL'), findsOneWidget);
    expect(container.read(orderFilterProvider), 'ALL');
    expect(container.read(orderTabProvider), OrderTab.positions);
  });
}

class _OrderFilterText extends ConsumerWidget {
  const _OrderFilterText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(body: Text(ref.watch(orderFilterProvider))),
    );
  }
}
