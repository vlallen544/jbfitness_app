import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';

import 'support/accounts.dart';

void main() {
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
