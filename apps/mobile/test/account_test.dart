import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';

import 'support/accounts.dart';

void main() {
  for (final registration in [false, true]) {
    testWidgets(
      '${registration ? 'registration' : 'login'} waits through a slow first connection without resubmitting',
      (tester) async {
        final response = Completer<http.Response>();
        var requests = 0;
        String? requestedPath;
        final store = MemorySessionStore();
        final account = AccountController(
          store: store,
          api: AccountApi(
            baseUrl: 'https://test.example/api/v1',
            client: MockClient((request) {
              requests++;
              requestedPath = request.url.path;
              return response.future;
            }),
          ),
        );
        addTearDown(account.dispose);
        var finished = false;
        final pending = account
            .authenticate(
              email: 'customer@example.test',
              password: 'test-password-123',
              displayName: registration ? 'Test customer' : null,
            )
            .then((_) => finished = true);
        await tester.pump();
        await tester.pump(const Duration(seconds: 45));
        expect(finished, isFalse);
        expect(requests, 1);
        expect(
          requestedPath,
          registration ? '/api/v1/auth/register' : '/api/v1/auth/login',
        );
        expect(store.value, isNull);
        response.complete(
          jsonResponse({
            'token': 'new-session',
            'user': sampleUser,
            'profile': sampleProfile,
          }),
        );
        await tester.pump();
        await pending;
        expect(finished, isTrue);
        expect(store.value, 'new-session');
        expect(requests, 1);
      },
    );
  }

  testWidgets(
    'a timed-out session check keeps the saved token and can be retried',
    (tester) async {
      final response = Completer<http.Response>();
      final store = MemorySessionStore('saved-session');
      var requests = 0;
      final account = AccountController(
        store: store,
        api: AccountApi(
          client: MockClient((_) {
            requests++;
            return requests == 1
                ? response.future
                : Future.value(
                    jsonResponse({
                      'user': sampleUser,
                      'profile': sampleProfile,
                    }),
                  );
          }),
        ),
      );
      addTearDown(account.dispose);
      final restoring = account.restore();
      await tester.pump();
      await tester.pump(const Duration(seconds: 76));
      await restoring;
      expect(store.value, 'saved-session');
      expect(account.bootError, contains('saved session has been kept'));
      expect(requests, 1);
      response.complete(
        jsonResponse({'user': sampleUser, 'profile': sampleProfile}),
      );
      await tester.pump();
      expect(account.user, isNull);
      await account.restore();
      expect(account.user?['id'], sampleUser['id']);
      expect(account.bootError, isNull);
    },
  );

  testWidgets(
    'registration timeout gives recovery advice and never retries the POST automatically',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      final store = MemorySessionStore();
      final account = AccountController(
        store: store,
        api: AccountApi(
          client: MockClient((_) {
            requests++;
            return response.future;
          }),
        ),
      );
      addTearDown(account.dispose);
      final pending = expectLater(
        account.authenticate(
          email: 'customer@example.test',
          password: 'test-password-123',
          displayName: 'Test customer',
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'recovery advice',
            contains('try signing in with the same email'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 76));
      await pending;
      expect(requests, 1);
      expect(store.value, isNull);
      response.complete(
        jsonResponse({
          'token': 'late-session',
          'user': sampleUser,
          'profile': sampleProfile,
        }),
      );
      await tester.pump();
      expect(account.user, isNull);
    },
  );

  test('expired session is removed from secure storage', () async {
    final store = MemorySessionStore('expired');
    final account = AccountController(
      store: store,
      api: AccountApi(
        client: MockClient(
          (_) async => jsonResponse({'message': 'Expired'}, 401),
        ),
      ),
    );
    addTearDown(account.dispose);
    await account.restore();
    expect(store.value, isNull);
    expect(account.user, isNull);
    expect(account.booting, isFalse);
    expect(account.bootError, isNull);
  });
  test('connection failure preserves session for retry', () async {
    final store = MemorySessionStore('saved-session');
    final account = AccountController(
      store: store,
      api: AccountApi(
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
    );
    addTearDown(account.dispose);
    await account.restore();
    expect(store.value, 'saved-session');
    expect(account.bootError, isNotNull);
    expect(account.user, isNull);
  });
  test('failed login does not create a local session', () async {
    final store = MemorySessionStore();
    final account = AccountController(
      store: store,
      api: AccountApi(
        client: MockClient(
          (_) async =>
              jsonResponse({'message': 'Email or password is incorrect.'}, 401),
        ),
      ),
    );
    addTearDown(account.dispose);
    await expectLater(
      account.authenticate(
        email: 'customer@example.test',
        password: 'incorrect',
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(store.value, isNull);
    expect(account.user, isNull);
  });
  test(
    'logout sends authorization, removes local session, and clears profile',
    () async {
      final store = MemorySessionStore('saved-session');
      bool revoked = false;
      final account = AccountController(
        store: store,
        api: AccountApi(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/logout')) {
              expect(request.headers['Authorization'], 'Bearer saved-session');
              revoked = true;
              return jsonResponse({'signedOut': true});
            }
            return jsonResponse({'user': sampleUser, 'profile': sampleProfile});
          }),
        ),
      );
      addTearDown(account.dispose);
      await account.restore();
      await account.signOut();
      expect(revoked, isTrue);
      expect(store.value, isNull);
      expect(account.profile, isNull);
      expect(account.user, isNull);
    },
  );
}
