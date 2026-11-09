import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/membership_page.dart';

import 'support/accounts.dart';

import 'package:jbfitness/app_theme.dart';

const catalogue = {
  'plans': [
    {
      'id': 'normal',
      'name': 'Normal',
      'priceInPaise': 300000,
      'videoSessions': 0,
      'features': ['Stored exercise demonstrations'],
    },
    {
      'id': 'premium',
      'name': 'Premium',
      'priceInPaise': 1000000,
      'videoSessions': 10,
      'features': ['All Normal features'],
    },
    {
      'id': 'premium-plus',
      'name': 'Premium Plus',
      'priceInPaise': 2000000,
      'videoSessions': 25,
      'features': ['All lower-plan features'],
    },
  ],
};
Map<String, dynamic> period({int remaining = 7, String status = 'active'}) => {
  'id': 'membership-fixture',
  'planId': 'premium',
  'planName': 'Premium',
  'startsAt': '2026-11-05T10:00:00.000Z',
  'endsAt': '2026-12-05T10:00:00.000Z',
  'status': status,
  'videoSessionsTotal': 10,
  'videoSessionsUsed': 10 - remaining,
  'videoSessionsRemaining': remaining,
  'environment': 'development',
};
Map<String, dynamic> summary({
  String status = 'none',
  Map<String, dynamic>? current,
  List<Map<String, dynamic>> history = const [],
}) => {
  'status': status,
  'current': current,
  'next': null,
  'history': history,
  'billing': {'checkoutEnabled': false},
};

void main() {
  Future<AccountController> mount(
    WidgetTester tester,
    Future<Map<String, dynamic>> Function() load, {
    bool narrow = false,
  }) async {
    final account = AccountController(
      store: MemorySessionStore('fixture-session'),
      api: AccountApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/me')) {
            return jsonResponse({'user': sampleUser, 'profile': sampleProfile});
          }
          if (request.url.path.endsWith('/plans')) {
            return jsonResponse(catalogue);
          }
          try {
            return jsonResponse(await load());
          } on ApiFailure catch (error) {
            return jsonResponse({'message': error.message}, error.status);
          }
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
              .copyWith(textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
          child: child!,
        ),
        home: Scaffold(body: MembershipPage(account: account)),
      ),
    );
    await tester.pumpAndSettle();
    return account;
  }

  testWidgets('no membership shows confirmed prices and disabled checkout', (
    tester,
  ) async {
    await mount(tester, () async => summary());
    expect(find.text('No active membership'), findsOneWidget);
    for (final price in ['₹3,000', '₹10,000', '₹20,000']) {
      expect(find.text(price), findsOneWidget);
    }
    expect(
      tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
  });
  testWidgets(
    'narrow membership view distinguishes queued sessions and zero allowance',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = summary(
        status: 'active',
        current: {
          ...period(),
          'planId': 'normal',
          'planName': 'Normal',
          'videoSessionsTotal': 0,
          'videoSessionsUsed': 0,
          'videoSessionsRemaining': 0,
        },
      );
      data['next'] = period(status: 'scheduled');
      await mount(tester, () async => data, narrow: true);
      expect(find.text('0 of 0 video sessions remaining'), findsOneWidget);
      expect(find.text('NEXT MEMBERSHIP'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('₹20,000'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('25 live video sessions total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'active membership shows balance, unpaid test label and refreshed count',
    (tester) async {
      var remaining = 7;
      await mount(
        tester,
        () async => summary(
          status: 'active',
          current: period(remaining: remaining),
        ),
      );
      expect(find.text('7 of 10 video sessions remaining'), findsOneWidget);
      expect(
        find.text('Development test membership • no payment collected'),
        findsOneWidget,
      );
      remaining = 6;
      await tester.tap(find.byTooltip('Refresh Plans'));
      await tester.pumpAndSettle();
      expect(find.text('6 of 10 video sessions remaining'), findsOneWidget);
      remaining = 5;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('5 of 10 video sessions remaining'), findsOneWidget);
    },
  );
  testWidgets(
    'expired membership preserves history without showing an active plan',
    (tester) async {
      await mount(
        tester,
        () async => summary(
          status: 'expired',
          history: [period(status: 'expired')],
        ),
      );
      expect(find.text('Your membership has expired'), findsOneWidget);
      expect(find.text('Premium • expired'), findsOneWidget);
      expect(find.text('ACTIVE MEMBERSHIP'), findsNothing);
    },
  );
  testWidgets(
    'network failure is not mistaken for an inactive membership and can retry',
    (tester) async {
      var unavailable = true;
      await mount(tester, () async {
        if (unavailable) {
          throw const ApiFailure(503, 'Unavailable');
        }
        return summary();
      });
      expect(find.text('Membership could not load'), findsOneWidget);
      expect(find.text('No active membership'), findsNothing);
      unavailable = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No active membership'), findsOneWidget);
    },
  );
  testWidgets('expired authentication clears the stored session', (
    tester,
  ) async {
    final account = await mount(
      tester,
      () async => throw const ApiFailure(401, 'Session expired'),
    );
    expect(account.user, isNull);
    expect(await account.store.read(), isNull);
  });
}
