import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/widgets/pouch_motion.dart';
import 'package:pouch/widgets/pouch_coin.dart';

Widget motionApp(VoidCallback onTap, {bool reducedMotion = false}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: PouchMotion(child: child!),
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                onTap();
                PouchMotion.celebrate(context);
              },
              child: const Text('Record income'),
            ),
          ),
        ),
      ),
    );

Widget coinApp({bool reducedMotion = false, bool tickersEnabled = true}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: TickerMode(
        enabled: tickersEnabled,
        child: const Center(child: PouchCoin()),
      ),
    );

void main() {
  final burst = find.byKey(const ValueKey('pouch-coin-burst'));

  testWidgets('Coins finish, allow taps and leave no scheduled animation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(motionApp(() => taps++));
    expect(burst, findsNothing);
    await tester.tap(find.text('Record income'));
    await tester.pump();
    expect(burst, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Record income'));
    await tester.pump();
    expect(taps, 2);
    expect(burst, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 721));
    await tester.pumpAndSettle();
    expect(burst, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion prevents coins and cancels a running burst', (
    tester,
  ) async {
    await tester.pumpWidget(motionApp(() {}));
    await tester.tap(find.text('Record income'));
    await tester.pump();
    expect(burst, findsOneWidget);
    await tester.pumpWidget(motionApp(() {}, reducedMotion: true));
    await tester.pumpAndSettle();
    expect(burst, findsNothing);
    await tester.tap(find.text('Record income'));
    await tester.pump();
    expect(burst, findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Removing a running burst disposes its ticker', (tester) async {
    await tester.pumpWidget(motionApp(() {}));
    await tester.tap(find.text('Record income'));
    await tester.pump();
    expect(burst, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Brand coin rotates without rebuilding its widget', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            builds++;
            return const Center(child: PouchCoin());
          },
        ),
      ),
    );
    final coin = find.byType(PouchCoin);
    final drawing = find.descendant(
      of: coin,
      matching: find.byType(CustomPaint),
    );
    final painter =
        tester.widget<CustomPaint>(drawing).painter! as PouchCoinPainter;
    final start = painter.rotation.value;
    final initialBuilds = builds;
    await tester.pump(const Duration(milliseconds: 250));
    expect(painter.rotation.value, isNot(start));
    expect(builds, initialBuilds);
    expect(tester.getSize(coin), const Size(28, 28));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Brand coin respects reduced motion and hidden ticker mode', (
    tester,
  ) async {
    await tester.pumpWidget(coinApp());
    final drawing = find.descendant(
      of: find.byType(PouchCoin),
      matching: find.byType(CustomPaint),
    );
    PouchCoinPainter painter() =>
        tester.widget<CustomPaint>(drawing).painter! as PouchCoinPainter;
    await tester.pumpWidget(coinApp(reducedMotion: true));
    await tester.pumpAndSettle();
    final still = painter().rotation.value;
    await tester.pump(const Duration(seconds: 1));
    expect(painter().rotation.value, still);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(coinApp());
    await tester.pump(const Duration(milliseconds: 250));
    expect(painter().rotation.value, isNot(still));
    await tester.pumpWidget(coinApp(tickersEnabled: false));
    final hidden = painter().rotation.value;
    await tester.pump(const Duration(seconds: 1));
    expect(painter().rotation.value, hidden);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Brand coin pauses in background and resumes safely', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(coinApp());
    final drawing = find.descendant(
      of: find.byType(PouchCoin),
      matching: find.byType(CustomPaint),
    );
    final painter =
        tester.widget<CustomPaint>(drawing).painter! as PouchCoinPainter;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = painter.rotation.value;
    await tester.pump(const Duration(seconds: 1));
    expect(painter.rotation.value, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(painter.rotation.value, isNot(paused));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
