import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/main.dart';
import 'package:jbfitness/account_screens.dart';
import 'package:jbfitness/app_theme.dart';

import 'support/accounts.dart';

void main() {
  testWidgets(
    'narrow profile saves measurements and trainer sharing with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      final account = AccountController(
        store: MemorySessionStore('fixture-session'),
        api: AccountApi(
          client: MockClient((request) async {
            if (request.method == 'PUT') {
              saved = jsonDecode(request.body) as Map<String, dynamic>;
              return jsonResponse({'profile': saved});
            }
            return jsonResponse({'user': sampleUser, 'profile': sampleProfile});
          }),
        ),
      );
      addTearDown(account.dispose);
      await account.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(body: FitnessProfilePage(account: account)),
        ),
      );
      await tester.pumpAndSettle();
      final weight = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Weight (kg)',
      );
      await tester.scrollUntilVisible(
        weight,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(weight);
      await tester.pumpAndSettle();
      await tester.enterText(weight, '77.5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final sharing = find.widgetWithText(
        CheckboxListTile,
        'Allow my assigned trainer to review my fitness profile.',
      );
      await tester.scrollUntilVisible(
        sharing.hitTestable(),
        300,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(sharing);
      await tester.scrollUntilVisible(
        find.text('Save profile').hitTestable(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(saved?['weightKg'], 77.5);
      expect(saved?['healthDataConsent'], true);
      expect(saved?['shareWithTrainer'], true);
      expect(saved?['workoutDays'], [0, 2, 4]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('register, fill onboarding, save, restore and edit profile', (
    tester,
  ) async {
    Map<String, dynamic>? savedProfile;
    final store = MemorySessionStore();
    AccountController createAccount() => AccountController(
      store: store,
      api: AccountApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/register')) {
            final input = jsonDecode(request.body);
            expect(input['email'], 'customer@example.test');
            return jsonResponse({
              'token': 'new-session',
              'user': sampleUser,
              'profile': null,
            }, 201);
          }
          if (request.method == 'PUT') {
            expect(request.headers['Authorization'], 'Bearer new-session');
            savedProfile = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({'profile': savedProfile});
          }
          return jsonResponse({'user': sampleUser, 'profile': savedProfile});
        }),
      ),
    );
    final account = createAccount();
    addTearDown(account.dispose);
    await account.restore();
    await tester.pumpWidget(JBFitnessApp(account: account));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    Future<void> fill(String label, String value) async {
      await tester.ensureVisible(field(label));
      await tester.pumpAndSettle();
      await tester.enterText(field(label), value);
      await tester.pumpAndSettle();
    }

    await fill('Your name', 'Test Customer');
    await fill('Email address', 'customer@example.test');
    await fill('Password', 'A-test-password-42!');
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Let’s build\nyour fitness profile.'), findsOneWidget);
    await fill('Age', '28');
    await fill('Height (cm)', '175');
    await fill('Weight (kg)', '80');
    await fill('Minutes available per session', '40');
    await tester.ensureVisible(find.text('Mon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    final consent = find.widgetWithText(
      CheckboxListTile,
      'I agree to save my fitness information for personalized coaching.',
    );
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save and continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();
    expect(savedProfile?['age'], 28);
    expect(savedProfile?['workoutDays'], [0]);
    expect(savedProfile?['shareWithTrainer'], isFalse);
    expect(find.text('Today'), findsOneWidget);
    expect(store.value, 'new-session');
    final restored = createAccount();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.profile?['heightCm'], 175);
    await tester.pumpWidget(
      JBFitnessApp(key: const ValueKey('restarted-app'), account: restored),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('Age')).controller?.text, '28');
    await fill('Weight (kg)', '79');
    await tester.ensureVisible(find.text('Save profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(savedProfile?['weightKg'], 79);
    expect(find.text('Your fitness profile is saved.'), findsOneWidget);
  });
}
