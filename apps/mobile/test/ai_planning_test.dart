import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/ai_planning_page.dart';

import 'support/accounts.dart';

Map<String, dynamic> run({
  String status = 'published',
  String stage = 'published',
  String ref = 'known-request',
}) => {
  'id': 'run',
  'requestId': ref,
  'status': status,
  'stage': stage,
  'message': status == 'published'
      ? 'Your reviewed plan is available.'
      : 'Your current schedule is unchanged.',
  'routineReview': {
    'summary': 'Short sessions fit your saved routine.',
    'notes': ['Use the saved recovery days.'],
  },
  'startDate': '2026-11-09',
  'through': '2026-11-13',
};
Map<String, dynamic> state({
  bool configured = true,
  Map<String, dynamic>? latest,
  int remaining = 2,
}) => {
  'configured': configured,
  'entitled': true,
  'profileReady': true,
  'eligibleExerciseCount': 3,
  'dailyLimit': 2,
  'remainingToday': remaining,
  'latest': latest,
};
AccountController account(
  Future<http.Response> Function(http.Request) handler,
) =>
    AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(client: MockClient(handler)),
      )
      ..booting = false
      ..token = 'session';
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      180,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unconfigured planning is clearly unavailable and cannot submit',
    (tester) async {
      var submits = 0;
      final controller = account((r) async {
        if (r.method == 'POST') submits++;
        return jsonResponse(state(configured: false));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: AiPlanningPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Generate my workout plan'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Generate my workout plan'),
            )
            .onPressed,
        isNull,
      );
      expect(submits, 0);
      expect(
        find.text(
          'AI workout planning is not connected yet. Your existing workouts remain available.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'only a request reference is submitted; published plans return their date to the workouts screen',
    (tester) async {
      Map<String, dynamic>? body;
      String? returned;
      final controller = account((r) async {
        if (r.method == 'POST') {
          body = jsonDecode(r.body);
          return jsonResponse(run(ref: body!['requestId']), 201);
        }
        return jsonResponse(
          state(
            latest: body == null ? null : run(ref: body!['requestId']),
            remaining: body == null ? 2 : 1,
          ),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  returned = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AiPlanningPage(account: controller),
                    ),
                  );
                },
                child: const Text('Open planner'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Open planner'));
      await tap(tester, find.text('Generate my workout plan'));
      expect(body!.keys, ['requestId']);
      await reveal(tester, find.text('Your routine review'));
      expect(find.text('Your routine review'), findsOneWidget);
      await tap(tester, find.text('View published workouts'));
      expect(returned, '2026-11-09');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending jobs poll status without submitting again and stop polling once complete',
    (tester) async {
      var reads = 0, submits = 0;
      var latest = run(status: 'running', stage: 'routine_review');
      final controller = account((r) async {
        if (r.method == 'POST') submits++;
        reads++;
        return jsonResponse(state(latest: latest));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: AiPlanningPage(account: controller),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(reads, 1);
      await reveal(tester, find.byType(LinearProgressIndicator));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      latest = run();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(submits, 0);
      await tester.pump(const Duration(seconds: 6));
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'an uncertain submit keeps its reference even after refreshing an older completed job',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      final controller = account((r) async {
        if (r.method == 'POST') {
          bodies.add(jsonDecode(r.body));
          return jsonResponse({'message': 'Could not confirm request'}, 503);
        }
        return jsonResponse(state(latest: run(ref: 'older-request')));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: AiPlanningPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Generate a new plan'));
      await tap(tester, find.text('Refresh status'));
      await tap(tester, find.text('Retry same planning request'));
      expect(bodies.length, 2);
      expect(bodies.first, bodies.last);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'review-needed state fits narrow enlarged text and does not offer unpublished workouts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = account(
        (r) async => jsonResponse(
          state(
            latest: run(status: 'review_needed', stage: 'review_needed'),
            remaining: 0,
          ),
        ),
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
          home: AiPlanningPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Trainer review needed'));
      expect(find.text('Your current schedule is unchanged.'), findsOneWidget);
      expect(find.text('View published workouts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
