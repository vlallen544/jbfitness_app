import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/meal_estimate_page.dart';

import 'support/accounts.dart';

Map<String, dynamic> mealDraft({bool unclear = false}) => {
  'id': 'estimate-fixture',
  'status': unclear ? 'unclear' : 'estimated',
  'uncertainty': 'high',
  'clarification': unclear
      ? 'Describe the dish or choose another photo.'
      : null,
  'assumptions': ['Assumed 150 g cooked rice and uncertain cooking oil.'],
  'items': unclear
      ? []
      : [
          {
            'name': 'Cooked rice (estimated fixture)',
            'grams': 150,
            'nutrients': {
              'calories': 130,
              'protein': 2.7,
              'carbs': 28,
              'fat': .3,
              'fiber': null,
              'sugar': null,
              'sodium': 0,
            },
          },
        ],
};
void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        finder,
        150,
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

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<AccountController> account(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final result = AccountController(
      store: MemorySessionStore('session'),
      api: AccountApi(client: MockClient(handler)),
    );
    result.booting = false;
    result.token = 'session';
    return result;
  }

  testWidgets(
    'text estimate needs review, portion edits recalculate totals and saving is explicit',
    (tester) async {
      Map<String, dynamic>? saved;
      var calls = 0;
      bool? returned;
      final controller = await account((request) async {
        if (request.url.path.endsWith('/status')) {
          return jsonResponse({
            'configured': true,
            'entitled': true,
            'remainingToday': 10,
            'dailyLimit': 10,
          });
        }
        if (request.url.path.endsWith('/save')) {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({
            'entryIds': ['entry-fixture'],
          });
        }
        calls++;
        expect(
          request.headers['Content-Type'],
          startsWith('multipart/form-data'),
        );
        expect(request.body, contains('Rice and dal'));
        return jsonResponse(mealDraft());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  returned = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MealEstimatePage(
                        account: controller,
                        date: '2026-11-07',
                        pickPhoto: (_) async => null,
                      ),
                    ),
                  );
                },
                child: const Text('Open estimate'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Open estimate'));
      await tester.enterText(field('Describe your dish'), 'Rice and dal');
      await tap(tester, find.text('Estimate meal'));
      expect(calls, 1);
      expect(saved, isNull);
      await reveal(tester, find.text('Approx. 195 kcal'));
      expect(find.text('Approx. 195 kcal'), findsOneWidget);
      await reveal(tester, field('Estimated portion (g)'));
      await tester.enterText(field('Estimated portion (g)'), '200');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Approx. 260 kcal'));
      expect(find.text('Approx. 260 kcal'), findsOneWidget);
      await tap(tester, find.text('Save estimate to diary'));
      expect(saved?['items'][0]['grams'], 200);
      expect(saved?['date'], '2026-11-07');
      expect(saved?['items'][0]['nutrients']['fiber'], isNull);
      expect(returned, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'upload photo sends no image until requested; unclear results cannot be saved',
    (tester) async {
      var calls = 0;
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final controller = await account((request) async {
        if (request.url.path.endsWith('/status')) {
          return jsonResponse({
            'configured': true,
            'entitled': true,
            'remainingToday': 10,
            'dailyLimit': 10,
          });
        }
        calls++;
        expect(
          latin1.decode(request.bodyBytes),
          contains('filename="meal-photo"'),
        );
        return jsonResponse(mealDraft(unclear: true));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: MealEstimatePage(
            account: controller,
            date: '2026-11-07',
            pickPhoto: (_) async => bytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Upload photo'));
      expect(calls, 0);
      await reveal(tester, find.text('Remove photo'));
      expect(find.text('Remove photo'), findsOneWidget);
      await tap(tester, find.text('Estimate meal'));
      expect(calls, 1);
      await reveal(
        tester,
        find.text('Describe the dish or choose another photo.'),
      );
      expect(find.text('Save estimate to diary'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unconfigured AI is honest and does not send a request', (
    tester,
  ) async {
    var calls = 0;
    final controller = await account((request) async {
      if (!request.url.path.endsWith('/status')) calls++;
      return jsonResponse({
        'configured': false,
        'entitled': true,
        'remainingToday': 10,
        'dailyLimit': 10,
      });
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: MealEstimatePage(
          account: controller,
          date: '2026-11-07',
          pickPhoto: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Estimate meal'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Estimate meal'),
          )
          .onPressed,
      isNull,
    );
    expect(calls, 0);
    expect(
      find.text(
        'Meal estimation is not connected yet. Food-label entry and saved foods remain available.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'review controls fit a narrow phone with enlarged text and preserve retry references',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bodies = <Map<String, dynamic>>[];
      final controller = await account((request) async {
        if (request.url.path.endsWith('/status')) {
          return jsonResponse({
            'configured': true,
            'entitled': true,
            'remainingToday': 10,
            'dailyLimit': 10,
          });
        }
        if (request.url.path.endsWith('/save')) {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonResponse({'message': 'Save temporarily unavailable'}, 503);
        }
        return jsonResponse(mealDraft());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: MealEstimatePage(
            account: controller,
            date: '2026-11-07',
            pickPhoto: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, field('Describe your dish'));
      await tester.enterText(field('Describe your dish'), 'A bowl of rice');
      await tap(tester, find.text('Estimate meal'));
      await tap(tester, find.text('Save estimate to diary'));
      await tap(tester, find.text('Retry diary save'));
      expect(bodies.length, 2);
      expect(bodies[0]['requestId'], bodies[1]['requestId']);
      expect(tester.takeException(), isNull);
    },
  );
}
