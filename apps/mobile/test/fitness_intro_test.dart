import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/fitness_intro.dart';
import 'package:jbfitness/intro_store.dart';
import 'package:jbfitness/main.dart';

import 'support/accounts.dart';

void main() {
  testWidgets('feature walkthrough never auto-dismisses or advances', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: FitnessIntro(onFinished: () => finished++),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('A routine that\nfits your life.'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(finished, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'next, back and swipe explain all features before finishing once',
    (tester) async {
      var finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: FitnessIntro(onFinished: () => finished++),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 4'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('4 / 4'), findsOneWidget);
      expect(finished, 0);
      await tester.tap(find.text('Continue to login'));
      expect(finished, 1);
      await tester.tap(find.text('Skip intro'));
      expect(finished, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('skip is available without waiting for scene animation', (
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

  testWidgets(
    'all four reduced-motion pages fit a narrow phone with large text',
    (tester) async {
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
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        expect(find.text('${i + 1} / 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (i < 3) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      expect(finished, isFalse);
      await tester.tap(find.text('Continue to login'));
      expect(finished, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completion opens real login and is remembered on the next app launch',
    (tester) async {
      final account = AccountController(
        api: AccountApi(
          client: MockClient(
            (_) async => throw StateError('No request expected before login'),
          ),
        ),
        store: MemorySessionStore(),
      );
      addTearDown(account.dispose);
      await account.restore();
      final intro = MemoryIntroStore();
      await tester.pumpWidget(
        JBFitnessApp(account: account, introStore: intro),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FitnessIntro), findsOneWidget);
      await tester.tap(find.text('Already have an account? Log in'));
      await tester.pumpAndSettle();
      expect(intro.seen, isTrue);
      expect(find.text('Welcome back.'), findsOneWidget);
      await tester.pumpWidget(
        JBFitnessApp(
          key: const ValueKey('relaunch'),
          account: account,
          introStore: intro,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FitnessIntro), findsNothing);
      expect(find.text('Welcome back.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Explore app features'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore app features'));
      await tester.pumpAndSettle();
      expect(find.byType(FitnessIntro), findsOneWidget);
      await tester.tap(find.text('Skip intro'));
      await tester.pumpAndSettle();
      expect(find.byType(FitnessIntro), findsNothing);
      expect(intro.seen, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
