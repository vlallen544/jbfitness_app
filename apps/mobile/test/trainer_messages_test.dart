import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/trainer_messages_page.dart';

import 'support/accounts.dart';

void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 180, maxScrolls: 30, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sharing is explicit; failed delivery retries the same reference and history reloads',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      var saved = false;
      final account = AccountController(
        store: MemorySessionStore(),
        api: AccountApi(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              sent.add(jsonDecode(request.body) as Map<String, dynamic>);
              if (sent.length == 1) {
                return jsonResponse({'message': 'Connection lost'}, 503);
              }
              saved = true;
              return jsonResponse({
                'message': {'id': 'one'},
              });
            }
            if (request.url.path.endsWith('/trainer-messages')) {
              return jsonResponse({
                'conversations': [
                  {'id': 'trainer', 'name': 'Sam', 'assigned': true},
                ],
                'truncated': false,
              });
            }
            return jsonResponse({
              'peer': {'id': 'trainer', 'name': 'Sam'},
              'assigned': true,
              'canSend': true,
              'nextBefore': null,
              'messages': saved
                  ? [
                      {
                        'id': 'one',
                        'sequence': '1',
                        'senderId': sampleUser['id'],
                        'text': sent.last['text'],
                        'createdAt': '2026-11-09T10:00:00Z',
                      },
                    ]
                  : [],
            });
          }),
        ),
      );
      account.token = 'session';
      account.user = Map<String, dynamic>.from(sampleUser);
      account.booting = false;
      addTearDown(account.dispose);
      Widget screen(Key key) => MaterialApp(
        theme: fitnessTheme(),
        home: TrainerMessagesPage(key: key, account: account),
      );
      await tester.pumpWidget(screen(const ValueKey('first')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Sam'));
      await tester.tap(find.text('Sam'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Send message'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send message'),
            )
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Can we check my squat?');
      await reveal(tester, find.text('Send message'));
      await tester.tap(find.text('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Connection lost'), findsOneWidget);
      await reveal(tester, find.text('Retry same message'));
      await tester.tap(find.text('Retry same message'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(sent[0]['shareWithTrainer'], true);
      expect(find.text('Can we check my squat?'), findsOneWidget);
      await tester.pumpWidget(screen(const ValueKey('reopen')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Sam'));
      await tester.tap(find.text('Sam'));
      await tester.pumpAndSettle();
      expect(find.text('Can we check my squat?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired membership retains history, clears only after confirmation and fits enlarged narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deleted = 0;
      final account = AccountController(
        store: MemorySessionStore(),
        api: AccountApi(
          client: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleted++;
              return jsonResponse({'cleared': true});
            }
            if (request.url.path.endsWith('/trainer-messages')) {
              return jsonResponse({
                'conversations': [
                  {'id': 'trainer', 'name': 'Sam', 'assigned': true},
                ],
              });
            }
            return jsonResponse({
              'peer': {'id': 'trainer', 'name': 'Sam'},
              'assigned': true,
              'canSend': false,
              'nextBefore': null,
              'messages': [
                {
                  'id': 'one',
                  'sequence': '1',
                  'senderId': 'trainer',
                  'text': 'Your saved reply.',
                  'createdAt': '2026-11-09T10:00:00Z',
                },
              ],
            });
          }),
        ),
      );
      account.token = 'session';
      account.user = Map<String, dynamic>.from(sampleUser);
      account.booting = false;
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: TrainerMessagesPage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Sam'));
      await tester.tap(find.text('Sam'));
      await tester.pumpAndSettle();
      expect(find.text('Your saved reply.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await reveal(tester, find.textContaining('An active membership'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Clear trainer conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, 0);
      await tester.tap(find.byTooltip('Clear trainer conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear messages'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
    },
  );

  testWidgets('unassigned customer gets an honest empty state', (tester) async {
    final account = AccountController(
      store: MemorySessionStore(),
      api: AccountApi(
        client: MockClient((_) async => jsonResponse({'conversations': []})),
      ),
    );
    account.token = 'session';
    account.booting = false;
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TrainerMessagesPage(account: account)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No trainer assigned yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
