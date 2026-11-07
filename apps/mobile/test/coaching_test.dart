import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/coaching_page.dart';

import 'support/accounts.dart';

Map<String, dynamic> facts() => {
  'from': '2026-11-01',
  'through': '2026-11-07',
  'workouts': {'completed': 2, 'skipped': 1, 'scheduledInCurrentPlan': 3},
  'nutrition': {
    'loggedDays': 1,
    'entries': 1,
    'estimatedEntries': 1,
    'days': [
      {
        'date': '2026-11-07',
        'entries': 1,
        'estimatedEntries': 1,
        'totals': {
          'calories': {'known': 195, 'complete': true},
        },
      },
      {
        'date': '2026-11-06',
        'entries': 0,
        'estimatedEntries': 0,
        'totals': null,
      },
    ],
  },
  'habits': {'completedCheckIns': 4, 'habitsWithCheckIns': 2},
  'weight': {'readings': [], 'changeKg': null},
};
Map<String, dynamic> turn({
  String kind = 'chat',
  String status = 'completed',
  String ref = 'request',
  bool review = false,
}) => {
  'id': 'turn',
  'requestId': ref,
  'kind': kind,
  'status': status,
  'input': 'Help me stay consistent',
  'source': 'ai',
  'createdAt': '2026-11-07T10:00:00Z',
  'facts': kind == 'summary' ? facts() : null,
  'response': status == 'completed'
      ? {
          'reply': 'Keep the next session manageable.',
          'suggestions': ['Use your saved training days.'],
          'needsTrainerReview': review,
          'reviewReason': review
              ? 'A trainer should review your limitations.'
              : null,
        }
      : null,
};
Map<String, dynamic> history(
  List<Map<String, dynamic>> turns, {
  bool configured = true,
  bool canSend = true,
}) => {
  'turns': turns,
  'nextBefore': null,
  'configured': configured,
  'canSend': canSend,
  'limits': {'chat': 20, 'summary': 2},
  'remaining': {'chat': 20 - turns.length, 'summary': 2},
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
Finder field() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Ask your AI coach',
);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      180,
      maxScrolls: 100,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a rejected request preserves editable text without polling an uncertain submission',
    (tester) async {
      var posts = 0;
      final controller = account((r) async {
        if (r.method == 'POST') {
          posts++;
          return jsonResponse({'message': 'Check the submitted message.'}, 400);
        }
        return jsonResponse(
          r.url.path.endsWith('/facts') ? {'facts': facts()} : history([]),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, field());
      await tester.enterText(field(), 'Help me stay consistent');
      await tap(tester, find.text('Send to AI coach'));
      await reveal(tester, field());
      expect(tester.widget<TextField>(field()).enabled, true);
      expect(
        tester.widget<TextField>(field()).controller!.text,
        'Help me stay consistent',
      );
      expect(find.text('Retry same coaching request'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unconfigured coach keeps recorded facts available and disables paid actions',
    (tester) async {
      var posts = 0;
      final controller = account((r) async {
        if (r.method == 'POST') posts++;
        return jsonResponse(
          r.url.path.endsWith('/facts')
              ? {'facts': facts()}
              : history([], configured: false),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 completed workouts · 1 skipped'), findsOneWidget);
      await reveal(tester, find.text('Send to AI coach'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send to AI coach'),
            )
            .onPressed,
        isNull,
      );
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chat sends a message and reference only, labels AI output and preserves review flags',
    (tester) async {
      Map<String, dynamic>? sent;
      final rows = <Map<String, dynamic>>[];
      final controller = account((r) async {
        if (r.method == 'POST') {
          sent = jsonDecode(r.body);
          rows.add(turn(ref: sent!['requestId'], review: true));
          return jsonResponse({'turn': rows.last}, 201);
        }
        return jsonResponse(
          r.url.path.endsWith('/facts') ? {'facts': facts()} : history(rows),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, field());
      await tester.enterText(field(), 'Help me stay consistent');
      await tap(tester, find.text('Send to AI coach'));
      expect(sent!.keys.toSet(), {'kind', 'message', 'requestId'});
      expect(sent!['kind'], 'chat');
      await reveal(tester, find.text('AI COACH'));
      expect(find.text('Trainer review needed'), findsOneWidget);
      expect(find.text('Keep the next session manageable.'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Keep the next session manageable.'),
        findsOneWidget,
      );
      semantics.dispose();
      await reveal(tester, field());
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'summary creates a saved snapshot and unknown food days do not show zero calories',
    (tester) async {
      final rows = <Map<String, dynamic>>[];
      final controller = account((r) async {
        if (r.method == 'POST') {
          final sent = jsonDecode(r.body);
          expect(sent['kind'], 'summary');
          expect(sent['message'], '');
          rows.add(turn(kind: 'summary', ref: sent['requestId']));
          return jsonResponse({'turn': rows.last}, 201);
        }
        return jsonResponse(
          r.url.path.endsWith('/facts') ? {'facts': facts()} : history(rows),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Summarize my last 7 days'));
      await reveal(tester, find.text('Recorded summary snapshot'));
      expect(find.text('Recorded summary snapshot'), findsOneWidget);
      final expansions = find.text('View logged nutrition');
      await reveal(tester, expansions.last);
      await tester.tap(expansions.last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('2026-11-06: no food logged').last);
      expect(find.text('2026-11-06: 0 kcal logged'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain requests retain message and request reference until the server confirms them',
    (tester) async {
      final bodies = <Map<String, dynamic>>[], rows = <Map<String, dynamic>>[];
      final controller = account((r) async {
        if (r.method == 'POST') {
          bodies.add(jsonDecode(r.body));
          if (bodies.length == 1) {
            return jsonResponse({'message': 'Temporary network fixture'}, 503);
          }
          rows.add(turn(ref: bodies.last['requestId']));
          return jsonResponse({'turn': rows.last}, 201);
        }
        return jsonResponse(
          r.url.path.endsWith('/facts') ? {'facts': facts()} : history(rows),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, field());
      await tester.enterText(field(), 'Help me stay consistent');
      await tap(tester, find.text('Send to AI coach'));
      await tap(tester, find.text('Retry same coaching request'));
      expect(bodies.length, 2);
      expect(bodies.first, bodies.last);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending messages poll without resending and update when a reply finishes',
    (tester) async {
      var latest = turn(status: 'pending'), posts = 0, reads = 0;
      final controller = account((r) async {
        if (r.method == 'POST') posts++;
        if (r.url.path.endsWith('/facts')) {
          return jsonResponse({'facts': facts()});
        }
        reads++;
        return jsonResponse(history([latest]));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      latest = turn();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Keep the next session manageable.'));
      expect(posts, 0);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'expired customers can clear their coaching history with confirmation',
    (tester) async {
      var rows = [turn()], deleted = false;
      final controller = account((r) async {
        if (r.method == 'DELETE') {
          deleted = true;
          rows = [];
          return jsonResponse({'cleared': true});
        }
        return jsonResponse(
          r.url.path.endsWith('/facts')
              ? {'facts': facts()}
              : history(rows, canSend: false),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear coaching history'));
      await tester.pumpAndSettle();
      expect(deleted, false);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(deleted, true);
      expect(find.text('AI COACH'), findsNothing);
      expect(find.text('2 completed workouts · 1 skipped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'recorded week and review response fit a narrow screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = account(
        (r) async => jsonResponse(
          r.url.path.endsWith('/facts')
              ? {'facts': facts()}
              : history([turn(review: true)]),
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
          home: CoachingPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Trainer review needed'));
      await reveal(tester, field());
      expect(tester.takeException(), isNull);
    },
  );
}
