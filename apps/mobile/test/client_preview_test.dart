import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jbfitness/main.dart';
import 'package:jbfitness/preview/preview_account.dart';
import 'package:jbfitness/nutrition_page.dart';
import 'package:jbfitness/progress_page.dart';
import 'package:jbfitness/coaching_page.dart';
import 'package:jbfitness/ai_planning_page.dart';
import 'package:jbfitness/sessions_page.dart';
import 'package:jbfitness/trainer_feedback_page.dart';
import 'package:jbfitness/app_theme.dart';

void main() {
  test(
    'offline edits are temporary and unsupported actions fail explicitly',
    () async {
      final account = createPreviewAccount();
      addTearDown(account.dispose);
      final habits = await account.authenticatedRequest('/me/habits');
      final day = habits['today'];
      await account.authenticatedRequest(
        '/me/habits/sample-habit-0/days/$day',
        method: 'PUT',
        body: {'completed': true},
      );
      expect(
        (await account.authenticatedRequest(
          '/me/habits',
        ))['summary']['completed'],
        1,
      );
      final fresh = createPreviewAccount();
      addTearDown(fresh.dispose);
      expect(
        (await fresh.authenticatedRequest(
          '/me/habits',
        ))['summary']['completed'],
        0,
      );
      await expectLater(
        account.authenticatedRequest('/billing/checkout', method: 'POST'),
        throwsA(isA<Exception>()),
      );
      expect(
        (await account.authenticatedRequest('/me/sessions'))['bookingEnabled'],
        false,
      );
    },
  );
  testWidgets(
    'client preview opens without login and all primary tabs load sample data',
    (tester) async {
      final account = createPreviewAccount();
      addTearDown(account.dispose);
      await tester.pumpWidget(JBFitnessApp(account: account, preview: true));
      await tester.pumpAndSettle();
      expect(
        find.text('OFFLINE DEMO · Sample data · Resets on restart'),
        findsOneWidget,
      );
      expect(find.text('Hello, Alex.'), findsOneWidget);
      for (final label in ['Workouts', 'Plans', 'Profile', 'Today']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'sample tracking and unavailable service screens render without a backend',
    (tester) async {
      final account = createPreviewAccount();
      addTearDown(account.dispose);
      final pages = <Widget>[
        NutritionPage(account: account),
        ProgressPage(account: account),
        CoachingPage(account: account),
        AiPlanningPage(account: account),
        SessionsPage(account: account),
        TrainerFeedbackPage(account: account),
      ];
      for (final page in pages) {
        await tester.pumpWidget(
          MaterialApp(key: UniqueKey(), theme: fitnessTheme(), home: page),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
    },
  );
}
