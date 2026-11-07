import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/habits_page.dart';

import 'support/accounts.dart';

void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      maxScrolls: 100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'server-saved checklist survives widget recreation and failed saves do not fake completion',
    (tester) async {
      final checked = <String, bool>{};
      var fail = true;
      final account = AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/me')) {
              return jsonResponse({
                'user': sampleUser,
                'profile': sampleProfile,
              });
            }
            if (request.method == 'PUT') {
              if (fail) {
                return jsonResponse({'message': 'Save unavailable'}, 503);
              }
              checked['habit-1'] =
                  (jsonDecode(request.body) as Map)['completed'] == true;
              return jsonResponse({'saved': true});
            }
            return jsonResponse(habitFixture(checked: checked));
          }),
        ),
      );
      addTearDown(account.dispose);
      await account.restore();
      Widget screen(Key key) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HabitsPanel(key: key, account: account),
          ),
        ),
      );
      await tester.pumpWidget(screen(const ValueKey('first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Save unavailable'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, false);
      fail = false;
      await tester.tap(find.byTooltip('Refresh habits'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.pumpWidget(screen(const ValueKey('recreated')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, true);
    },
  );
  testWidgets(
    'monthly and weekly grids fit a narrow phone, lock future dates and retain membership history',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = habitFixture(canEdit: false);
      final account = AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(client: MockClient((_) async => jsonResponse(data))),
      );
      addTearDown(account.dispose);
      account.booting = false;
      account.token = 'session';
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HabitsPanel(account: account, compact: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 check-ins'), findsOneWidget);
      await reveal(tester, find.text('Monthly'));
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((box) => box.onChanged == null),
        true,
      );
      await reveal(tester, find.text('Weekly'));
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      expect(find.text('Days 1–7'), findsOneWidget);
      expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).length, 21);
      await reveal(tester, find.text('Add habit'));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new habit validates target and retries with the same creation reference',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      final account = AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              if (bodies.length == 1) {
                return jsonResponse({'message': 'Try again'}, 503);
              }
              return jsonResponse({'id': 'created'});
            }
            return jsonResponse(habitFixture());
          }),
        ),
      );
      addTearDown(account.dispose);
      account.booting = false;
      account.token = 'session';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: HabitsPanel(account: account)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Add habit'));
      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Habit name',
      );
      final target = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Monthly target (days)',
      );
      await tester.enterText(name, 'Take a walk');
      await tester.enterText(target, '32');
      await tester.tap(find.widgetWithText(FilledButton, 'Add habit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 1 to 31.'), findsOneWidget);
      await tester.enterText(target, '25');
      await tester.tap(find.widgetWithText(FilledButton, 'Add habit'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Retry adding habit'));
      await tester.tap(find.text('Retry adding habit'));
      await tester.pumpAndSettle();
      expect(bodies.length, 2);
      expect(bodies[0]['requestId'], bodies[1]['requestId']);
      expect(bodies[1]['targetDays'], 25);
      expect(tester.takeException(), isNull);
    },
  );
}
