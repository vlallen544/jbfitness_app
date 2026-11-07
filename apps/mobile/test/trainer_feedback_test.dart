import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/account_screens.dart';
import 'package:jbfitness/ai_planning_page.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/trainer_feedback_page.dart';

import 'support/accounts.dart';

AccountController account(
  Future<http.Response> Function(http.Request) handler,
) =>
    AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(client: MockClient(handler)),
      )
      ..booting = false
      ..token = 'session'
      ..profile = Map<String, dynamic>.from(sampleProfile)
      ..user = Map<String, dynamic>.from(sampleUser);
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      target,
      180,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'coaching sharing requires separate opt-in beyond profile sharing',
    (tester) async {
      Map<String, dynamic>? saved;
      final controller = account((r) async {
        saved = jsonDecode(r.body);
        return jsonResponse({'profile': saved});
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: Scaffold(body: FitnessProfilePage(account: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final profile = find.widgetWithText(
            CheckboxListTile,
            'Allow my assigned trainer to review my fitness profile.',
          ),
          coaching = find.widgetWithText(
            CheckboxListTile,
            'Also allow my assigned trainer to review AI coaching requests and recent tracking summaries.',
          );
      await reveal(tester, coaching);
      expect(tester.widget<CheckboxListTile>(coaching).value, false);
      expect(tester.widget<CheckboxListTile>(coaching).onChanged, isNull);
      await tap(tester, profile);
      expect(tester.widget<CheckboxListTile>(coaching).value, false);
      await tap(tester, coaching);
      await tap(tester, find.text('Save profile'));
      expect(saved?['shareWithTrainer'], true);
      expect(saved?['shareCoachingWithTrainer'], true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'trainer feedback is labelled and accessible and opens the reviewed training week',
    (tester) async {
      String? requestedFrom;
      final controller = account((r) async {
        if (r.url.path.endsWith('/trainer-feedback')) {
          return jsonResponse({
            'feedback': [
              {
                'id': 'feedback',
                'trainer': 'Coach Sam',
                'kind': 'planning',
                'decision': 'publish_plan',
                'feedback': 'Use this reviewed routine for your next sessions.',
                'createdAt': '2026-11-07T10:00:00Z',
                'result': {'planId': 'plan', 'startDate': '2026-11-16'},
              },
            ],
          });
        }
        requestedFrom = r.url.queryParameters['from'];
        return jsonResponse({
          'from': requestedFrom,
          'through': '2026-11-22',
          'plan': {
            'id': 'plan',
            'title': 'Reviewed training week',
            'version': 2,
            'source': 'trainer',
          },
          'workouts': [],
        });
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: TrainerFeedbackPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coach Sam'), findsOneWidget);
      expect(find.text('AI COACH'), findsNothing);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'Use this reviewed routine for your next sessions.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await tap(tester, find.text('Open reviewed workouts'));
      expect(requestedFrom, '2026-11-16');
      expect(find.text('Trainer-reviewed workout plan.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved feedback fits a narrow phone with enlarged text and supports empty history',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var empty = false;
      final controller = account(
        (r) async => jsonResponse({
          'feedback': empty
              ? []
              : [
                  {
                    'id': 'note',
                    'trainer': 'Coach Sam',
                    'kind': 'coaching',
                    'decision': 'follow_up',
                    'feedback': 'Keep the next session manageable and check in if your availability changes.',
                    'createdAt': '2026-11-07T10:00:00Z',
                    'result': {},
                  },
                ],
        }),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: TrainerFeedbackPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Follow-up note'));
      expect(tester.takeException(), isNull);
      empty = true;
      await tester.tap(find.byTooltip('Refresh trainer feedback'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No trainer feedback yet. You can manage assigned-trainer sharing in your profile.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'resolved planning reviews show the trainer outcome instead of an open escalation',
    (tester) async {
      final controller = account(
        (r) async => jsonResponse({
          'configured': false,
          'entitled': true,
          'profileReady': true,
          'eligibleExerciseCount': 1,
          'remainingToday': 1,
          'dailyLimit': 2,
          'latest': {
            'id': 'run',
            'status': 'review_needed',
            'stage': 'review_needed',
            'message': 'Old escalation reason',
            'trainerReview': {
              'status': 'resolved',
              'feedback': 'Your trainer completed this review.',
            },
            'routineReview': null,
          },
        }),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: AiPlanningPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Trainer review complete'));
      expect(find.text('Your trainer completed this review.'), findsOneWidget);
      expect(find.text('Old escalation reason'), findsNothing);
      expect(find.text('View published workouts'), findsNothing);
    },
  );
}
