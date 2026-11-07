import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/main.dart';
import 'package:jbfitness/workout_pages.dart';
import 'package:jbfitness/app_theme.dart';

import 'support/accounts.dart';

const workoutId = '11111111-1111-4111-8111-111111111111';
const itemId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> detail({
  bool archived = false,
  String? date,
  Map<String, dynamic>? progress,
}) => {
  'workout': {
    'id': workoutId,
    'title': 'Test session',
    'date': date ?? dayString(DateTime.now()),
    'archived': archived,
    'source': 'development_fixture',
    'version': 1,
  },
  'items': [
    {
      'id': itemId,
      'exercise': {
        'id': 'test-exercise',
        'name': 'Test exercise',
        'instructions': ['Test instructions'],
      },
      'sets': 3,
      'repetitions': 10,
      'targetWeightKg': null,
      'restSeconds': 60,
    },
  ],
  'progress':
      progress ??
      {
        'status': 'not_started',
        'revision': 0,
        'exerciseLogs': [],
        'notes': '',
        'completedAt': null,
      },
  'today': dayString(DateTime.now()),
};
Map<String, dynamic> week() => {
  'plan': {
    'id': 'plan',
    'title': 'Sample routine',
    'version': 1,
    'source': 'development_fixture',
  },
  'workouts': [
    {
      'id': workoutId,
      'title': 'Test session',
      'date': dayString(DateTime.now()),
      'exerciseCount': 1,
      'status': 'not_started',
    },
  ],
};
Future<AccountController> accountFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  final account = AccountController(
    store: MemorySessionStore('session'),
    api: AccountApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/me/habits')) {
          return jsonResponse(habitFixture());
        }
        if (request.url.path.endsWith('/auth/me')) {
          return jsonResponse({'user': sampleUser, 'profile': sampleProfile});
        }
        return handler(request);
      }),
    ),
  );
  await account.restore();
  return account;
}

void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.byType(Scrollable).first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 150, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'weekly schedule opens exercise details with sets, reps and rest',
    (tester) async {
      final account = await accountFor(
        (r) async =>
            jsonResponse(r.url.path.endsWith(workoutId) ? detail() : week()),
      );
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WorkoutsPage(account: account)),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Test session'));
      expect(find.text('3 sets × 10 reps • 60 sec rest'), findsOneWidget);
      expect(find.text('• Test instructions'), findsOneWidget);
    },
  );
  testWidgets(
    'completion validates checkmarks, shows missing videos and saves feedback',
    (tester) async {
      Map<String, dynamic>? saved;
      final account = await accountFor((r) async {
        if (r.url.path.endsWith('/video')) {
          return jsonResponse({
            'available': false,
            'reason': 'video_not_supplied',
          });
        }
        if (r.method == 'PUT') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return jsonResponse({'revision': 1, 'duplicate': false});
        }
        return jsonResponse(detail());
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutDetailPage(account: account, workoutId: workoutId),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Complete workout'));
      expect(saved, isNull);
      expect(
        find.text(
          'Mark every exercise complete before completing the workout.',
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.byType(Checkbox).first);
      await tapVisible(tester, find.text('Watch demonstration'));
      expect(
        find.text('The demonstration video has not been supplied yet.'),
        findsOneWidget,
      );
      final notes = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Session feedback',
      );
      await reveal(tester, notes);
      await tester.enterText(notes, 'The final set felt difficult.');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Complete workout'));
      expect(saved?['status'], 'completed');
      expect(saved?['revision'], 0);
      expect(saved?['notes'], 'The final set felt difficult.');
      expect((saved?['exerciseLogs'] as List).first['completed'], isTrue);
      expect(find.text('Workout progress saved.'), findsOneWidget);
      await reveal(tester, find.text('Session completed'));
      expect(find.text('Session completed'), findsOneWidget);
    },
  );
  testWidgets('exercise logging fits a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    final account = await accountFor((request) async {
      if (request.method == 'PUT') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'revision': 1, 'duplicate': false});
      }
      if (request.url.path.endsWith('/video')) {
        return jsonResponse({'available': false});
      }
      return jsonResponse(detail());
    });
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 740),
            textScaler: TextScaler.linear(1.6),
          ),
          child: WorkoutDetailPage(account: account, workoutId: workoutId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Watch demonstration'));
    expect(
      find.text('The demonstration video has not been supplied yet.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Actual performance (optional)'));
    for (final entry in {
      'Sets done': '3',
      'Reps done': '10',
      'Weight (kg)': '12.5',
    }.entries) {
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == entry.key,
      );
      await reveal(tester, field);
      await tester.enterText(field, entry.value);
      await tester.pumpAndSettle();
    }
    await tapVisible(tester, find.text('Save progress'));
    expect(saved?['status'], 'in_progress');
    final log = (saved?['exerciseLogs'] as List).single as Map;
    expect(log['actualSets'], 3);
    expect(log['actualRepetitions'], 10);
    expect(log['actualWeightKg'], 12.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost save response reuses its request ID on retry', (
    tester,
  ) async {
    final bodies = <Map<String, dynamic>>[];
    final account = await accountFor((r) async {
      if (r.method == 'PUT') {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        if (bodies.length == 1) {
          throw http.ClientException('lost response');
        }
        return jsonResponse({'revision': 1, 'duplicate': true});
      }
      return jsonResponse(detail());
    });
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutDetailPage(account: account, workoutId: workoutId),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(Checkbox).first);
    await tapVisible(tester, find.text('Complete workout'));
    await tapVisible(tester, find.text('Complete workout'));
    expect(bodies.length, 2);
    expect(bodies[0]['requestId'], bodies[1]['requestId']);
    expect(find.text('Workout progress saved.'), findsOneWidget);
  });
  testWidgets('archived and future workouts cannot be changed', (tester) async {
    for (final sample in [detail(archived: true), detail(date: '2099-01-01')]) {
      final account = await accountFor((r) async => jsonResponse(sample));
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: WorkoutDetailPage(account: account, workoutId: workoutId),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await reveal(tester, find.text('Complete workout'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    }
  });
  testWidgets('membership error still allows access to saved history', (
    tester,
  ) async {
    final account = await accountFor(
      (r) async => r.url.path.endsWith('/history')
          ? jsonResponse({'workouts': []})
          : jsonResponse({'message': 'Membership needed'}, 403),
    );
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkoutsPage(account: account)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active membership needed'), findsOneWidget);
    await tapVisible(tester, find.text('History'));
    expect(find.text('Your saved workouts will appear here.'), findsOneWidget);
  });
  testWidgets('sign-out removes an open workout route', (tester) async {
    final account = await accountFor(
      (r) async =>
          jsonResponse(r.url.path.endsWith(workoutId) ? detail() : week()),
    );
    addTearDown(account.dispose);
    await tester.pumpWidget(JBFitnessApp(account: account));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Workouts'));
    await tapVisible(tester, find.text('Test session'));
    expect(find.text('Workout details'), findsOneWidget);
    await account.signOut(localOnly: true);
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsNothing);
    expect(find.text('Welcome back.'), findsOneWidget);
  });
}
