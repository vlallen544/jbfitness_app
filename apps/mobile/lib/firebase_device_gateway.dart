import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'device_services.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification payloads are presented by the OS. Do not log or persist message
  // content, tokens, account data or navigate from the background isolate.
}

class FirebaseDeviceGateway implements DeviceGateway {
  final _notices = StreamController<DeviceNotice>.broadcast();
  StreamSubscription<RemoteMessage>? _foreground, _opened;
  FlutterExceptionHandler? _previousFlutterError;
  bool Function(Object, StackTrace)? _previousPlatformError;
  FlutterExceptionHandler? _flutterHandler;
  bool Function(Object, StackTrace)? _platformHandler;
  bool _initialized = false, _disposed = false;
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  // Console test messages currently require the registration-token API, not FID.
  // ignore: deprecated_member_use
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Stream<DeviceNotice> get notices => _notices.stream;
  @override
  bool get diagnosticsEnabled =>
      FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (_disposed) return;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
    if (_disposed) return;
    _foreground = FirebaseMessaging.onMessage.listen((m) => _emit(m, false));
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _emit(m, true),
    );
    _previousFlutterError = FlutterError.onError;
    _previousPlatformError = PlatformDispatcher.instance.onError;
    _flutterHandler = (details) {
      _previousFlutterError?.call(details);
      if (diagnosticsEnabled) {
        unawaited(
          FirebaseCrashlytics.instance
              .recordError(
                StateError(
                  'Unhandled Flutter framework error (${details.exception.runtimeType})',
                ),
                details.stack ?? StackTrace.current,
                fatal: true,
              )
              .catchError((_) {}),
        );
      }
    };
    _platformHandler = (error, stack) {
      if (diagnosticsEnabled) {
        unawaited(
          FirebaseCrashlytics.instance
              .recordError(
                StateError(
                  'Unhandled application error (${error.runtimeType})',
                ),
                stack,
                fatal: true,
              )
              .catchError((_) {}),
        );
      }
      return _previousPlatformError?.call(error, stack) ?? false;
    };
    FlutterError.onError = _flutterHandler;
    PlatformDispatcher.instance.onError = _platformHandler;
    _initialized = true;
  }

  void _emit(RemoteMessage message, bool opened) {
    if (!_disposed) {
      _notices.add(DeviceNotice.fromData(message.data, opened: opened));
    }
  }

  @override
  Future<PushPermission> permission({bool request = false}) async {
    final settings = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => PushPermission.granted,
      AuthorizationStatus.provisional => PushPermission.provisional,
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notRequested,
    };
  }

  @override
  Future<String?> enablePush() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    // Registration-token compatibility for Firebase Console test messages.
    // ignore: deprecated_member_use
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Future<void> disablePush() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    // Revoke the same registration token returned by the console-test API.
    // ignore: deprecated_member_use
    await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Future<void> setDiagnostics(bool enabled) async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled) await FirebaseCrashlytics.instance.deleteUnsentReports();
  }

  @override
  Future<void> sendDiagnosticTest() => FirebaseCrashlytics.instance.recordError(
    StateError('JB Fitness diagnostic test'),
    StackTrace.current,
    fatal: false,
  );
  @override
  Future<DeviceNotice?> initialNotice() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null
        ? null
        : DeviceNotice.fromData(message.data, opened: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _foreground?.cancel();
    _opened?.cancel();
    _notices.close();
    if (FlutterError.onError == _flutterHandler) {
      FlutterError.onError = _previousFlutterError;
    }
    if (PlatformDispatcher.instance.onError == _platformHandler) {
      PlatformDispatcher.instance.onError = _previousPlatformError;
    }
  }
}
