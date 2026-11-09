import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/device_services.dart';
import 'package:jbfitness/notification_settings_page.dart';
import 'package:jbfitness/main.dart';
import 'package:jbfitness/intro_store.dart';

import 'support/accounts.dart';

class MemoryPushPreference implements PushPreferenceStore {
  bool value;
  MemoryPushPreference([this.value = false]);
  @override
  Future<bool> read() async => value;
  @override
  Future<void> write(bool enabled) async {
    value = enabled;
  }
}

class FakeDeviceGateway implements DeviceGateway {
  @override
  bool supported = true;
  PushPermission currentPermission = PushPermission.notRequested;
  bool failInitialization = false, failToken = false, failDiagnostics = false;
  @override
  bool diagnosticsEnabled = false;
  int permissionPrompts = 0,
      registrations = 0,
      revocations = 0,
      diagnosticTests = 0;
  Completer<String?>? pendingToken;
  DeviceNotice? launchNotice;
  final tokens = StreamController<String>.broadcast(sync: true);
  final messages = StreamController<DeviceNotice>.broadcast(sync: true);
  @override
  Stream<String> get tokenChanges => tokens.stream;
  @override
  Stream<DeviceNotice> get notices => messages.stream;
  @override
  Future<void> initialize() async {
    if (failInitialization) throw StateError('offline');
  }

  @override
  Future<PushPermission> permission({bool request = false}) async {
    if (request) permissionPrompts++;
    return currentPermission;
  }

  @override
  Future<String?> enablePush() async {
    registrations++;
    if (failToken) throw StateError('registration failed');
    return pendingToken == null
        ? 'registration-$registrations'
        : pendingToken!.future;
  }

  @override
  Future<void> disablePush() async {
    revocations++;
  }

  @override
  Future<void> setDiagnostics(bool enabled) async {
    if (failDiagnostics) throw StateError('save failed');
    diagnosticsEnabled = enabled;
  }

  @override
  Future<void> sendDiagnosticTest() async {
    diagnosticTests++;
  }

  @override
  Future<DeviceNotice?> initialNotice() async => launchNotice;
  @override
  void dispose() {
    tokens.close();
    messages.close();
  }
}

void main() {
  late FakeDeviceGateway gateway;
  late MemoryPushPreference preferences;
  late DeviceServices services;
  setUp(() {
    gateway = FakeDeviceGateway();
    preferences = MemoryPushPreference();
    services = DeviceServices(gateway: gateway, preferences: preferences);
  });
  tearDown(() => services.dispose());
  test(
    'startup never prompts or enables push without an explicit choice',
    () async {
      await services.bindAccount('customer-a');
      await services.start();
      expect(services.ready, isTrue);
      expect(services.enabled, isFalse);
      expect(services.diagnostics, isFalse);
      expect(gateway.permissionPrompts, 0);
      expect(gateway.registrations, 0);
      expect(services.token, isNull);
    },
  );
  test(
    'permission denial and failed registration do not fake an enabled token',
    () async {
      await services.bindAccount('customer-a');
      await services.start();
      gateway.currentPermission = PushPermission.denied;
      await services.setNotifications(true);
      expect(services.enabled, isFalse);
      expect(preferences.value, isFalse);
      expect(gateway.registrations, 0);
      expect(services.error, contains('blocked'));
      gateway.currentPermission = PushPermission.granted;
      gateway.failToken = true;
      await services.setNotifications(true);
      expect(services.enabled, isFalse);
      expect(services.token, isNull);
      expect(preferences.value, isFalse);
      expect(services.error, isNotNull);
    },
  );
  test('logout clears the token immediately and rejects late registration/refresh events', () async {
    await services.bindAccount('customer-a');
    await services.start();
    gateway.currentPermission = PushPermission.granted;
    gateway.pendingToken = Completer<String?>();
    final enable = services.setNotifications(true);
    await Future<void>.delayed(Duration.zero);
    final logout = services.bindAccount(null);
    expect(services.token, isNull);
    gateway.pendingToken!.complete('previous-account-token');
    await enable;
    await logout;
    gateway.tokens.add('late-previous-account-token');
    expect(services.token, isNull);
    expect(services.signedIn, isFalse);
    expect(gateway.revocations, greaterThanOrEqualTo(2));
  });
  test('cold-start notification waits for account restore and is emitted only once', () async {
    preferences.value = true;
    gateway.currentPermission = PushPermission.granted;
    gateway.launchNotice = const DeviceNotice(
      destination: 'sessions',
      opened: true,
    );
    final events = <DeviceNotice>[];
    final subscription = services.events.listen(events.add);
    addTearDown(subscription.cancel);
    await services.start();
    expect(events, isEmpty);
    await services.bindAccount('customer-a');
    expect(events.single.destination, 'sessions');
    await services.refresh();
    expect(events, hasLength(1));
    await services.bindAccount(null);
    gateway.messages.add(
      const DeviceNotice(destination: 'sessions', opened: true),
    );
    expect(events, hasLength(1));
  });
  test('disabling push revokes delivery and crash reporting remains an independent choice', () async {
    await services.bindAccount('customer-a');
    await services.start();
    gateway.currentPermission = PushPermission.granted;
    await services.setNotifications(true);
    expect(services.token, isNotNull);
    await services.setNotifications(false);
    expect(services.token, isNull);
    expect(preferences.value, isFalse);
    await services.sendDiagnosticTest();
    expect(gateway.diagnosticTests, 0);
    gateway.failDiagnostics = true;
    await services.setDiagnostics(true);
    expect(services.diagnostics, isFalse);
    gateway.failDiagnostics = false;
    await services.setDiagnostics(true);
    expect(services.diagnostics, isTrue);
    await services.sendDiagnosticTest();
    expect(gateway.diagnosticTests, 1);
    expect(services.enabled, isFalse);
  });
  test(
    'Firebase failures can retry without throwing into the account flow',
    () async {
      gateway.failInitialization = true;
      await services.start();
      expect(services.ready, isFalse);
      expect(services.error, isNotNull);
      gateway.failInitialization = false;
      await services.start();
      expect(services.ready, isTrue);
      expect(services.error, isNull);
    },
  );
  test('notification destinations never accept external URLs or record identifiers', () {
    for (final value in [
      'https://attacker.test',
      '/me/progress/photos/private-id',
      'customer-a',
      null,
    ]) {
      expect(
        DeviceNotice.fromData({'screen': value}, opened: true).destination,
        'notifications',
      );
    }
    expect(
      DeviceNotice.fromData({'screen': 'nutrition'}, opened: true).destination,
      'nutrition',
    );
  });
  testWidgets(
    'cold-start notification opens settings and logout clears its device state',
    (tester) async {
      final account = await signedInAccount();
      addTearDown(account.dispose);
      final device = FakeDeviceGateway()
        ..currentPermission = PushPermission.granted
        ..launchNotice = const DeviceNotice(
          destination: 'notifications',
          opened: true,
        );
      final rootServices = DeviceServices(
        gateway: device,
        preferences: MemoryPushPreference(true),
      );
      await tester.pumpWidget(
        JBFitnessApp(
          account: account,
          deviceServices: rootServices,
          introStore: MemoryIntroStore(seen: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications & diagnostics'), findsOneWidget);
      expect(rootServices.token, isNotNull);
      await account.signOut(localOnly: true);
      await tester.pumpAndSettle();
      expect(rootServices.token, isNull);
      expect(find.text('Welcome back.'), findsOneWidget);
      device.messages.add(
        const DeviceNotice(destination: 'notifications', opened: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications & diagnostics'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('device-service failure does not replace the signed-in app', (
    tester,
  ) async {
    final account = await signedInAccount();
    addTearDown(account.dispose);
    final device = FakeDeviceGateway()..failInitialization = true;
    final rootServices = DeviceServices(
      gateway: device,
      preferences: MemoryPushPreference(),
    );
    await tester.pumpWidget(
      JBFitnessApp(
        account: account,
        deviceServices: rootServices,
        introStore: MemoryIntroStore(seen: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello, Test.'), findsOneWidget);
    expect(rootServices.ready, isFalse);
    expect(rootServices.error, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('notification settings fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await services.bindAccount('customer-a');
      await services.start();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: NotificationSettingsPage(services: services),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Share crash reports'), 150);
    await tester.scrollUntilVisible(find.text('Show device token'), 150);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Show device token'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
