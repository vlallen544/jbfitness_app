import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/fitness_intro.dart';

void main() {
  testWidgets('intro completes once and releases its animation', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: FitnessIntro(onFinished: () => finished++),
      ),
    );
    expect(find.text('Every rep.\nA new beginning.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(finished, 1);
    await tester.tap(find.text('Skip intro'));
    expect(finished, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip finishes immediately without waiting for the animation', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: FitnessIntro(onFinished: () => finished = true),
      ),
    );
    await tester.tap(find.text('Skip intro'));
    expect(finished, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and large text fit a narrow device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            disableAnimations: true,
            textScaler: TextScaler.linear(1.8),
          ),
          child: FitnessIntro(onFinished: () => finished = true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
