import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/sessions_page.dart';

import 'support/accounts.dart';

const policy = {
  'durationMinutes': 30,
  'bookingLeadHours': 0,
  'horizonDays': 14,
  'freeCancellationHours': 12,
  'chargeLateCancellation': true,
  'chargeNoShow': true,
};
Map<String, dynamic> fixture({bool enabled = true, int total = 10}) => {
  'serverTime': '2026-11-08T08:00:00Z',
  'confirmed': enabled,
  'providerConfigured': enabled,
  'bookingEnabled': enabled,
  'policy': enabled ? policy : null,
  'revision': 3,
  'membership': {
    'videoSessionsRemaining': total,
    'videoSessionsReserved': 0,
    'videoSessionsUsed': 0,
    'videoSessionsTotal': total,
  },
  'slots': total == 0
      ? []
      : [
          {
            'id': 'slot',
            'revision': 2,
            'trainerName': 'Coach Sam',
            'startsAt': '2026-11-09T08:00:00Z',
          },
        ],
  'bookings': [],
};
AccountController account(
  Future<http.Response> Function(http.Request) handler,
) =>
    AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(client: MockClient(handler)),
      )
      ..booting = false
      ..token = 'session'
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
      160,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> show(WidgetTester tester, AccountController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fitnessTheme(),
      home: SessionsPage(account: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('calendar times use IST across UTC day boundaries', () {
    expect(sessionTime('2026-11-08T22:00:00Z'), '2026-11-09 03:30 IST');
  });
  testWidgets(
    'unconfigured booking shows its status and disables new reservations',
    (tester) async {
      final controller = account(
        (r) async => jsonResponse(fixture(enabled: false)),
      );
      addTearDown(controller.dispose);
      await show(tester, controller);
      await reveal(tester, find.text('Book this time'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Book this time'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Booking rules are awaiting owner confirmation.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Normal membership explains its zero live-session allowance', (
    tester,
  ) async {
    final controller = account((r) async => jsonResponse(fixture(total: 0)));
    addTearDown(controller.dispose);
    await show(tester, controller);
    expect(find.text('0 available · 0 reserved'), findsOneWidget);
    expect(
      find.textContaining('Your Normal plan has no live video sessions.'),
      findsOneWidget,
    );
    expect(find.text('Book this time'), findsNothing);
  });
  testWidgets(
    'booking requires confirmation, sends revisions, and retains reference after uncertain failure',
    (tester) async {
      final posts = <Map<String, dynamic>>[];
      final data = fixture();
      final controller = account((r) async {
        if (r.method == 'POST') {
          posts.add(jsonDecode(r.body));
          if (posts.length == 1) {
            return jsonResponse({
              'message': 'Booking confirmation delayed.',
            }, 503);
          }
          data['membership']['videoSessionsRemaining'] = 9;
          data['membership']['videoSessionsReserved'] = 1;
          data['slots'] = [];
          return jsonResponse({'id': 'booking', 'status': 'booked'});
        }
        return jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await show(tester, controller);
      await tap(tester, 'Book this time');
      expect(posts, isEmpty);
      expect(
        find.text('Booking holds one session from your active membership.'),
        findsOneWidget,
      );
      await tap(tester, 'Confirm booking');
      expect(posts.single['slotRevision'], 2);
      expect(posts.single['policyRevision'], 3);
      expect(posts.single['slotId'], 'slot');
      await tap(tester, 'Retry same booking change');
      expect(posts.length, 2);
      expect(posts[0], posts[1]);
      await reveal(tester, find.text('9 available · 1 reserved'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancellation displays saved terms and reports actual credit usage',
    (tester) async {
      final data = fixture();
      data['slots'] = [];
      data['policy'] = {...policy, 'chargeLateCancellation': false};
      data['bookings'] = [
        {
          'id': 'booking',
          'trainerName': 'Coach Sam',
          'startsAt': '2026-11-08T10:00:00Z',
          'revision': 7,
          'status': 'booked',
          'consumed': false,
          'policy': policy,
        },
      ];
      Map<String, dynamic>? sent;
      final controller = account((r) async {
        if (r.method == 'POST') {
          expect(r.url.path.endsWith('/me/sessions/booking/cancel'), true);
          sent = jsonDecode(r.body);
          data['bookings'][0]['status'] = 'cancelled';
          data['bookings'][0]['consumed'] = true;
          return jsonResponse({'status': 'cancelled', 'consumed': true});
        }
        return jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await show(tester, controller);
      await tap(tester, 'Cancel this booking');
      expect(sent, isNull);
      expect(find.text('Late cancellation uses one session.'), findsOneWidget);
      await tap(tester, 'Cancel booking');
      expect(sent?['revision'], 7);
      expect(
        find.text(
          'Booking cancelled. One session was used under the saved cancellation rules.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'session rules and saved appointments fit a narrow phone with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = fixture();
      data['bookings'] = [
        {
          'id': 'booking',
          'trainerName': 'Coach Sam',
          'startsAt': '2026-11-07T10:00:00Z',
          'revision': 2,
          'status': 'completed',
          'consumed': true,
          'policy': policy,
          'attendanceNote': 'The scheduled session was completed.',
        },
      ];
      final controller = account((r) async => jsonResponse(data));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: SessionsPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Saved cancellation rules');
      await reveal(
        tester,
        find.text('A recorded no-show uses one session.').last,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
