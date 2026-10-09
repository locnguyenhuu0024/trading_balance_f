import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/core/widgets/responsive_form_content.dart';

void main() {
  testWidgets(
    'busy button reserves its label layout on narrow scaled screens',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Scaffold(body: Center(child: _ButtonHarness())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('responsive-form-submit'));
      final idleSize = tester.getSize(button);
      tester
          .state<_ButtonHarnessState>(find.byType(_ButtonHarness))
          .setBusy(true);
      await tester.pump();

      expect(tester.getSize(button), idleSize);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending forms use a static mark when motion is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: Scaffold(
            body: Column(
              children: [
                FormPendingStatus(label: 'Đang tải cài đặt…'),
                AsyncFormButton(
                  label: 'Lưu',
                  busyLabel: 'Đang lưu cài đặt…',
                  isBusy: true,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsWidgets);
    expect(find.text('Đang tải cài đặt…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ButtonHarness extends StatefulWidget {
  const _ButtonHarness();

  @override
  State<_ButtonHarness> createState() => _ButtonHarnessState();
}

class _ButtonHarnessState extends State<_ButtonHarness> {
  bool _busy = false;

  void setBusy(bool value) => setState(() => _busy = value);

  @override
  Widget build(BuildContext context) => AsyncFormButton(
    key: const Key('responsive-form-submit'),
    label: 'Gửi lệnh',
    busyLabel: 'Đang gửi lệnh đã chọn…',
    isBusy: _busy,
    onPressed: () {},
  );
}
