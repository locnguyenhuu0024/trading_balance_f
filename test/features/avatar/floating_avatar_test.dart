import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_colors.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_model.dart';
import 'package:trading_balance_f/features/avatar/domain/avatar_mood.dart';
import 'package:trading_balance_f/features/avatar/presentation/avatar_renderer.dart';
import 'package:trading_balance_f/features/avatar/presentation/floating_avatar.dart';

const avatarFakeKey = Key('avatar-fake');
const _frameKey = Key('avatar-frame');

void main() {
  test('RED rejects malformed or unknown bridge events', () {
    for (final value in [
      '{"v":2}',
      'not JSON',
      '[]',
      {'v': 1, 'type': 'unknown'},
      {'v': 1, 'type': 'ready'},
      {'v': 1, 'type': 'interaction', 'kind': 'unknown'},
      {'v': 1, 'type': 'error', 'code': 'load', 'message': 42},
    ]) {
      expect(decodeAvatarEvent(value), isNull, reason: '$value');
    }
  });

  testWidgets('RED errors remove the view for the lifetime of the host', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    await _mount(tester, renderer);
    final avatar = find.byKey(avatarFakeKey);
    expect(avatar, findsOneWidget);

    renderer.emit(const AvatarError('load', 'model unavailable'));
    await tester.pump();
    expect(avatar, findsNothing);
    renderer.emit(const AvatarModelLoaded());
    await tester.pump();
    expect(avatar, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(renderer.disposed, isTrue);
  });

  test(
    'GREEN codec encodes the envelope and decodes both transport shapes',
    () {
      expect(
        jsonDecode(encodeAvatarMessage({'type': 'setPaused', 'paused': true})),
        {'v': 1, 'type': 'setPaused', 'paused': true},
      );
      expect(
        decodeAvatarEvent('{"v":1,"type":"ready","version":1}'),
        isA<AvatarReady>(),
      );
      expect(
        decodeAvatarEvent({'v': 1, 'type': 'modelLoaded'}),
        isA<AvatarModelLoaded>(),
      );
      expect(
        decodeAvatarEvent(
          '{"v":1,"type":"error","code":"load","message":"bad"}',
        ),
        isA<AvatarError>()
            .having((event) => event.code, 'code', 'load')
            .having((event) => event.message, 'message', 'bad'),
      );
      expect(
        decodeAvatarEvent({'v': 1, 'type': 'interaction', 'kind': 'pat'}),
        isA<AvatarInteraction>().having((event) => event.kind, 'kind', 'pat'),
      );
    },
  );

  testWidgets(
    'GREEN pauses for the lifecycle and delivers interaction haptic',
    (tester) async {
      final renderer = FakeAvatarRenderer();
      final calls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await _mount(tester, renderer);

      renderer.pauses.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(renderer.pauses, [true, false]);

      renderer.emit(const AvatarInteraction('pat'));
      await tester.pump();
      expect(
        calls
            .where((call) => call.method == 'HapticFeedback.vibrate')
            .single
            .arguments,
        'HapticFeedbackType.lightImpact',
      );
    },
  );

  testWidgets('RED-156 an outfit error leaves the avatar and bridge active', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    await _mount(tester, renderer);
    renderer.emit(const AvatarModelLoaded());
    await tester.pumpAndSettle();

    renderer.emit(const AvatarError('outfit', 'Donor unavailable'));
    await tester.pumpAndSettle();
    expect(find.byKey(avatarFakeKey), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );

    renderer.emit(const AvatarError('load', 'Model unavailable'));
    await tester.pumpAndSettle();
    expect(find.byKey(avatarFakeKey), findsNothing);
  });

  testWidgets('GREEN-152 floating view keeps the renderer on colour changes', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    final model = avatarModelById(null);
    final custom = AvatarColors.empty.withPart(
      AvatarPart.top,
      const Color(0xff2859b0),
    );

    Future<void> show(AvatarColors colors) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          avatarRendererFactoryProvider.overrideWithValue((_) => renderer),
        ],
        child: MaterialApp(
          home: FloatingAvatar(
            model: model,
            mood: AvatarMood.neutral,
            colors: colors,
          ),
        ),
      ),
    );

    await show(AvatarColors.empty);
    renderer.emit(const AvatarModelLoaded());
    await tester.pump();
    await show(custom);
    await show(
      AvatarColors.empty.withPart(AvatarPart.top, const Color(0xff2859b0)),
    );

    expect(renderer.colors, [AvatarColors.empty, custom]);
    expect(renderer.moods, [AvatarMood.neutral]);
    expect(renderer.disposed, isFalse);
    expect(find.byKey(avatarFakeKey), findsOneWidget);
  });

  testWidgets(
    'GREEN-156 floating view sends outfits on init and real changes',
    (tester) async {
      final renderer = FakeAvatarRenderer();
      const outfit = ['donut-chan:outfit'];

      Future<void> show(List<String> items) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            avatarRendererFactoryProvider.overrideWithValue((_) => renderer),
          ],
          child: MaterialApp(
            home: FloatingAvatar(
              model: avatarModelById(null),
              mood: AvatarMood.neutral,
              outfit: items,
            ),
          ),
        ),
      );

      await show(outfit);
      expect(renderer.outfits, [outfit]);
      await show([...outfit]);
      expect(renderer.outfits, [outfit]);
      await show([]);
      expect(renderer.outfits, [outfit, <String>[]]);
      expect(renderer.disposed, isFalse);
    },
  );

  testWidgets('GREEN scales on a narrow viewport and clamps long-press drag', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    await _mount(tester, renderer, width: 320, reducedMotion: true);
    final avatar = find.byKey(avatarFakeKey);
    final frame = tester.getRect(find.byKey(_frameKey));
    expect(renderer.motion, [true]);
    renderer.emit(const AvatarModelLoaded());
    await tester.pump();
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: avatar, matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 1);
    expect(opacity.duration, Duration.zero);
    final initial = tester.getRect(avatar);
    expect(initial.size, const Size(128, 176));
    expect(initial.bottomRight, frame.bottomRight - const Offset(16, 16));

    final gesture = await tester.startGesture(initial.center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(-5000, -5000));
    await gesture.up();
    await tester.pump();
    final dragged = tester.getRect(avatar);
    expect(dragged.topLeft, frame.topLeft);
    expect(dragged.size, initial.size);
    expect(renderer.pointers.map((sample) => sample.phase), ['down', 'cancel']);
  });

  testWidgets('GREEN forwards local pointer coordinates and throttles moves', (
    tester,
  ) async {
    final renderer = FakeAvatarRenderer();
    await _mount(tester, renderer);
    renderer.emit(const AvatarModelLoaded());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final origin = tester.getTopLeft(find.byKey(avatarFakeKey));

    await tester.tapAt(origin + const Offset(20, 30));
    expect(renderer.pointers.map((sample) => sample.phase), ['down', 'up']);
    expect(renderer.pointers.first.position, const Offset(20, 30));

    renderer.pointers.clear();
    final gesture = await tester.startGesture(origin + const Offset(20, 30));
    await gesture.moveBy(
      const Offset(21, 0),
      timeStamp: const Duration(milliseconds: 10),
    );
    await gesture.moveBy(
      const Offset(4, 0),
      timeStamp: const Duration(milliseconds: 30),
    );
    await gesture.moveBy(
      const Offset(5, 0),
      timeStamp: const Duration(milliseconds: 43),
    );
    await gesture.cancel(timeStamp: const Duration(milliseconds: 44));
    expect(renderer.pointers.map((sample) => sample.phase), [
      'down',
      'move',
      'move',
      'cancel',
    ]);
    expect(renderer.pointers[2].position, const Offset(50, 30));
    expect(renderer.pointers[2].timeMs, 43);
  });
}

Future<void> _mount(
  WidgetTester tester,
  FakeAvatarRenderer renderer, {
  double width = 400,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        avatarRendererFactoryProvider.overrideWithValue((_) => renderer),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: Scaffold(
              body: SizedBox.expand(
                key: _frameKey,
                child: Stack(
                  children: [
                    FloatingAvatar(
                      model: avatarModelById(null),
                      mood: AvatarMood.neutral,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class FakeAvatarRenderer implements AvatarRenderer {
  final _events = StreamController<AvatarEvent>();
  final moods = <AvatarMood>[];
  final colors = <AvatarColors>[];
  final outfits = <List<String>>[];
  final pauses = <bool>[];
  final motion = <bool>[];
  final pointers = <({String phase, Offset position, int timeMs})>[];
  bool disposed = false;

  void emit(AvatarEvent event) => _events.add(event);

  @override
  Widget buildView() => const SizedBox(key: avatarFakeKey);

  @override
  Stream<AvatarEvent> get events => _events.stream;

  @override
  void setMood(AvatarMood mood) => moods.add(mood);

  @override
  void setColors(AvatarColors value) => colors.add(value);

  @override
  void setOutfit(List<String> itemIds) => outfits.add(List.of(itemIds));

  @override
  void setPaused(bool paused) => pauses.add(paused);

  @override
  void setReducedMotion(bool reducedMotion) => motion.add(reducedMotion);

  @override
  void sendPointer(String phase, double x, double y, int tMs) =>
      pointers.add((phase: phase, position: Offset(x, y), timeMs: tMs));

  @override
  void dispose() {
    disposed = true;
    unawaited(_events.close());
  }
}
