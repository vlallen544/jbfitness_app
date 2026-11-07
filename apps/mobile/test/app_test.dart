import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jbfitness/main.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/today_page.dart';

import 'support/accounts.dart';

void main() {
  testWidgets(
    'Today fits a narrow phone with enlarged text and opens workouts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = await signedInAccount();
      addTearDown(account.dispose);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 740),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: TodayPage(
                account: account,
                onOpenWorkouts: () => opened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello, Test.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Open workouts'), 100);
      await tester.ensureVisible(find.text('Open workouts'));
      await tester.pumpAndSettle();
      expect(find.text('40 min / session  ·  3 days / week'), findsOneWidget);
      await tester.tap(find.text('Open workouts'));
      expect(opened, isTrue);
      await tester.scrollUntilVisible(find.text('Take a walk'), 100);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('today checklist toggles and profile navigation works', (
    tester,
  ) async {
    final account = await signedInAccount();
    addTearDown(account.dispose);
    await tester.pumpWidget(JBFitnessApp(account: account));
    await tester.scrollUntilVisible(
      find.text('0 / 3'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0 / 3'), findsOneWidget);
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Your fitness profile'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
