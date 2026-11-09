import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/profile_overview.dart';

import 'support/accounts.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      fail
          ? 'failed sharing save preserves private profile and disables coaching sharing'
          : 'profile sharing requires a separate coaching choice and revoking clears both',
      (tester) async {
        var profile = Map<String, dynamic>.from(sampleProfile);
        final writes = <Map<String, dynamic>>[];
        final account = AccountController(
          store: MemorySessionStore('fixture-session'),
          api: AccountApi(
            client: MockClient((request) async {
              if (request.method == 'PUT') {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                writes.add(body);
                if (fail) {
                  return jsonResponse({
                    'message': 'Could not save sharing.',
                  }, 503);
                }
                profile = body;
                return jsonResponse({'profile': profile});
              }
              if (request.url.path.endsWith('/auth/me')) {
                return jsonResponse({'user': sampleUser, 'profile': profile});
              }
              return jsonResponse({'current': null});
            }),
          ),
        );
        addTearDown(account.dispose);
        await account.restore();
        await tester.pumpWidget(
          MaterialApp(
            theme: fitnessTheme(),
            home: Scaffold(
              body: ProfileOverview(account: account, onOpenPlans: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder toggle(String title) =>
            find.widgetWithText(SwitchListTile, title);
        Future<void> tap(String title) async {
          await tester.scrollUntilVisible(toggle(title), 150);
          await tester.ensureVisible(toggle(title));
          await tester.pumpAndSettle();
          await tester.tap(toggle(title));
          await tester.pumpAndSettle();
        }

        await tester.scrollUntilVisible(toggle('Coaching review sharing'), 150);
        expect(
          tester
              .widget<SwitchListTile>(toggle('Coaching review sharing'))
              .onChanged,
          isNull,
        );
        await tap('Profile sharing');
        expect(writes.single['shareWithTrainer'], isTrue);
        expect(writes.single['shareCoachingWithTrainer'], isFalse);
        expect(account.profile?['shareWithTrainer'], !fail);
        expect(account.profile?['shareCoachingWithTrainer'], isFalse);
        if (fail) {
          expect(
            tester.widget<SwitchListTile>(toggle('Profile sharing')).value,
            isFalse,
          );
          expect(
            tester
                .widget<SwitchListTile>(toggle('Coaching review sharing'))
                .onChanged,
            isNull,
          );
        } else {
          await tap('Coaching review sharing');
          expect(account.profile?['shareCoachingWithTrainer'], isTrue);
          await tap('Profile sharing');
          expect(writes.last['shareWithTrainer'], isFalse);
          expect(writes.last['shareCoachingWithTrainer'], isFalse);
          expect(account.profile?['shareCoachingWithTrainer'], isFalse);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
