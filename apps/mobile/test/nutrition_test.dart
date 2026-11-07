import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/nutrition_page.dart';

import 'support/accounts.dart';

const nutritionValues = {
  'calories': 120,
  'protein': 5,
  'carbs': 20,
  'fat': 2,
  'fiber': null,
  'sugar': null,
  'sodium': 200,
};
const labelFood = {
  'id': 'food-fixture',
  'name': 'Label fixture',
  'nutrients': nutritionValues,
  'source': {
    'type': 'label',
    'label': 'Values entered by you',
    'note': 'Technical fixture only',
  },
};
Map<String, dynamic> nutritionFixture({
  List<Map<String, dynamic>> entries = const [],
  bool canEdit = true,
  Map<String, dynamic>? targets,
}) {
  final today = habitFixture()['today'];
  return {
    'date': today,
    'today': today,
    'timezone': 'Asia/Kolkata',
    'canEdit': canEdit,
    'entries': entries,
    'targets': targets,
    'totals': {
      for (final key in nutritionValues.keys)
        key: {
          'known': entries.fold<num>(
            0,
            (sum, entry) => sum + (entry['nutrients'][key] as num? ?? 0),
          ),
          'complete': entries.every((entry) => entry['nutrients'][key] != null),
          'missingEntries': entries
              .where((entry) => entry['nutrients'][key] == null)
              .length,
        },
    },
  };
}

Map<String, dynamic> foodEntry(
  num grams, {
  int revision = 1,
  String meal = 'breakfast',
}) => {
  'id': 'entry-fixture',
  'grams': grams,
  'meal': meal,
  'revision': revision,
  'food': labelFood,
  'nutrients': {
    for (final entry in nutritionValues.entries)
      entry.key: entry.value == null
          ? null
          : (entry.value as num) * grams / 100,
  },
};
Future<AccountController> nutritionAccount(
  Future<http.Response> Function(http.Request) handler,
) async {
  final account = AccountController(
    store: MemorySessionStore('fixture-session'),
    api: AccountApi(
      client: MockClient(
        (request) async => request.url.path.endsWith('/auth/me')
            ? jsonResponse({'user': sampleUser, 'profile': sampleProfile})
            : handler(request),
      ),
    ),
  );
  await account.restore();
  return account;
}

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
  Future<void> fill(WidgetTester tester, String label, String value) async {
    await reveal(tester, field(label));
    await tester.enterText(field(label), value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'log grams, edit quantity and remove food through saved responses',
    (tester) async {
      var entries = <Map<String, dynamic>>[];
      final requests = <Map<String, dynamic>>[];
      final account = await nutritionAccount((request) async {
        if (request.url.path.endsWith('/foods')) {
          return jsonResponse({
            'foods': [labelFood],
            'external': [],
            'providerConfigured': false,
            'notice': null,
          });
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          entries = [
            foodEntry(body['grams'] as num, meal: body['meal'] as String),
          ];
          return jsonResponse({'id': 'entry-fixture'});
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          entries = body['deleted'] == true
              ? []
              : [
                  foodEntry(
                    body['grams'] as num,
                    revision: 2,
                    meal: body['meal'] as String,
                  ),
                ];
          return jsonResponse({'revision': 2});
        }
        return jsonResponse(nutritionFixture(entries: entries));
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: NutritionPage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 kcal'), findsOneWidget);
      await tap(tester, find.text('Log a food'));
      await tap(tester, find.text('Label fixture'));
      await fill(tester, 'Quantity (g)', '150');
      expect(find.text('180 kcal for 150 g'), findsOneWidget);
      await tap(tester, find.text('Log food'));
      expect(requests.single['grams'], 150);
      expect(requests.single['meal'], 'breakfast');
      await reveal(tester, find.text('180 kcal'));
      expect(find.text('180 kcal'), findsOneWidget);
      await tap(tester, find.byTooltip('Edit food entry'));
      await tap(tester, find.text('Edit entry'));
      await fill(tester, 'Quantity (g)', '200');
      await tap(tester, find.text('Save changes'));
      expect(requests.last['revision'], 1);
      expect(entries.single['grams'], 200);
      await tap(tester, find.byTooltip('Edit food entry'));
      await tap(tester, find.text('Remove entry'));
      await tap(tester, find.text('Remove entry'));
      expect(entries, isEmpty);
      expect(requests.last['deleted'], true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'food label requires its source and leaves unknown optional nutrients null',
    (tester) async {
      Map<String, dynamic>? saved;
      final account = await nutritionAccount((request) async {
        if (request.method == 'POST') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({'food': labelFood});
        }
        return jsonResponse({
          'foods': [],
          'external': [],
          'providerConfigured': false,
          'notice': null,
        });
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: FoodPickerPage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Enter food label'));
      await tap(tester, find.text('Use this food'));
      expect(find.text('Enter where these values came from.'), findsOneWidget);
      for (final entry in {
        'Food name': 'Technical label',
        'Label or recipe reference': 'Label fixture',
        'Energy (kcal)': '120',
        'Protein (g)': '5',
        'Carbohydrates (g)': '20',
        'Fat (g)': '2',
      }.entries) {
        await fill(tester, entry.key, entry.value);
      }
      await tap(tester, find.text('Use this food'));
      expect(saved?['sourceNote'], 'Label fixture');
      expect(saved?['nutrients']['fiber'], isNull);
      expect(saved?['nutrients']['sodium'], isNull);
      expect(saved?['nutrients']['calories'], 120);
    },
  );
  testWidgets(
    'narrow diary preserves unknown totals and expired membership is read-only',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = await nutritionAccount(
        (_) async => jsonResponse(
          nutritionFixture(entries: [foodEntry(100)], canEdit: false),
        ),
      );
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: NutritionPage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Fiber (g)'));
      expect(find.text('At least 0'), findsNWidgets(2));
      await reveal(tester, find.byTooltip('Add to breakfast'));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Add to breakfast',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('target save retries preserve reference and effective date', (
    tester,
  ) async {
    final today = habitFixture()['today'];
    var targets = <String, dynamic>{
      'effectiveFrom': today,
      'revision': 1,
      'nutrients': {...nutritionValues, 'calories': 2000},
    };
    final requests = <Map<String, dynamic>>[];
    final account = await nutritionAccount((request) async {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        if (requests.length == 1) {
          return jsonResponse({'message': 'Save unavailable'}, 503);
        }
        targets = {
          'effectiveFrom': today,
          'revision': 2,
          'nutrients': body['nutrients'],
        };
        return jsonResponse({'revision': 2});
      }
      return jsonResponse(nutritionFixture(targets: targets));
    });
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: NutritionPage(account: account),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Set daily targets'));
    await fill(tester, 'Energy (kcal)', '2500');
    await tap(tester, find.text('Save targets'));
    await tap(tester, find.text('Retry nutrition save'));
    expect(requests.length, 2);
    expect(requests[0]['requestId'], requests[1]['requestId']);
    expect(requests[1]['date'], today);
    expect(requests[1]['revision'], 1);
    expect(targets['nutrients']['calories'], 2500);
    expect(tester.takeException(), isNull);
  });
}
