import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PushPermission { notRequested, denied, granted, provisional }

class DeviceNotice {
  static const destinations = {
    'workouts',
    'nutrition',
    'progress',
    'coaching',
    'feedback',
    'sessions',
    'plans',
    'habits',
    'notifications',
  };
  final String destination;
  final bool opened;
  const DeviceNotice({required this.destination, required this.opened});
  factory DeviceNotice.fromData(
    Map<String, dynamic> data, {
    required bool opened,
  }) {
    final screen = data['screen'];
    return DeviceNotice(
      destination: destinations.contains(screen)
          ? screen as String
          : 'notifications',
      opened: opened,
    );
  }
}

abstract class DeviceGateway {
  bool get supported;
  Future<void> initialize();
  Future<PushPermission> permission({bool request = false});
  Future<String?> enablePush();
  Future<void> disablePush();
  bool get diagnosticsEnabled;
  Future<void> setDiagnostics(bool enabled);
  Future<void> sendDiagnosticTest();
  Stream<String> get tokenChanges;
  Stream<DeviceNotice> get notices;
  Future<DeviceNotice?> initialNotice();
  void dispose();
}

abstract class PushPreferenceStore {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class SecurePushPreferenceStore implements PushPreferenceStore {
  static const _key = 'jbfitness.push_opt_in.v1';
  final _storage = const FlutterSecureStorage();
  @override
  Future<bool> read() async => await _storage.read(key: _key) == 'true';
  @override
  Future<void> write(bool enabled) =>
      _storage.write(key: _key, value: '$enabled');
}

class UnavailableDeviceGateway implements DeviceGateway {
  @override
  bool get supported => false;
  @override
  bool get diagnosticsEnabled => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<PushPermission> permission({bool request = false}) async =>
      PushPermission.notRequested;
  @override
  Future<String?> enablePush() async => null;
  @override
  Future<void> disablePush() async {}
  @override
  Future<void> setDiagnostics(bool enabled) async {}
  @override
  Future<void> sendDiagnosticTest() async {}
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<DeviceNotice> get notices => const Stream.empty();
  @override
  Future<DeviceNotice?> initialNotice() async => null;
  @override
  void dispose() {}
}

class _NoPushPreference implements PushPreferenceStore {
  @override
  Future<bool> read() async => false;
  @override
  Future<void> write(bool enabled) async {}
}

/// Device transport only. Backend event delivery is a separate integration.
class DeviceServices extends ChangeNotifier {
  static final unavailable = DeviceServices(
    gateway: UnavailableDeviceGateway(),
    preferences: _NoPushPreference(),
  );
  final DeviceGateway gateway;
  final PushPreferenceStore preferences;
  DeviceServices({required this.gateway, required this.preferences});
  bool ready = false, busy = false, enabled = false, diagnostics = false;
  PushPermission permission = PushPermission.notRequested;
  String? token, error, _userId;
  DeviceNotice? _pendingInitial;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _tail = Future.value();
  StreamSubscription<String>? _tokens;
  StreamSubscription<DeviceNotice>? _notices;
  final _events = StreamController<DeviceNotice>.broadcast(sync: true);
  Stream<DeviceNotice> get events => _events.stream;
  bool get supported => gateway.supported;
  bool get signedIn => _userId != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _queue(Future<void> Function() action) {
    final result = _tail.then((_) async {
      if (_disposed) return;
      busy = true;
      error = null;
      _notify();
      try {
        await action();
      } catch (_) {
        error = 'Device services could not connect. Please retry.';
      } finally {
        busy = false;
        _notify();
      }
    });
    _tail = result;
    return result;
  }

  Future<T> _bounded<T>(Future<T> operation) =>
      operation.timeout(const Duration(seconds: 20));

  Future<void> start() => _queue(() async {
    if (!supported || ready) return;
    await _bounded(gateway.initialize());
    if (_disposed) return;
    permission = await _bounded(gateway.permission());
    enabled = await preferences.read();
    diagnostics = gateway.diagnosticsEnabled;
    await _bounded(gateway.disablePush());
    ready = true;
    _tokens = gateway.tokenChanges.listen((value) {
      // Ignore token callbacks during account changes and while transport is off.
      if (!_disposed && !busy && enabled && signedIn && token != null) {
        token = value;
        _notify();
      }
    }, onError: (_) {});
    _notices = gateway.notices.listen((notice) {
      if (!_disposed && enabled && signedIn && token != null) {
        _events.add(notice);
      }
    }, onError: (_) {});
    await _refreshToken();
    _pendingInitial = await _bounded(gateway.initialNotice());
    _emitInitial();
  });

  Future<void> bindAccount(String? userId) {
    if (_userId == userId) return _tail;
    if (_userId != null && _userId != userId) _pendingInitial = null;
    _userId = userId;
    _epoch++;
    token = null;
    _notify();
    return _queue(() async {
      if (!ready) return;
      await _bounded(gateway.disablePush());
      await _refreshToken();
      _emitInitial();
    });
  }

  void _emitInitial() {
    if (_pendingInitial != null &&
        !_disposed &&
        signedIn &&
        enabled &&
        token != null) {
      final initial = _pendingInitial!;
      _pendingInitial = null;
      _events.add(initial);
    }
  }

  Future<void> _refreshToken() async {
    token = null;
    if (!enabled || !signedIn || !_allowed(permission)) return;
    final epoch = _epoch;
    final value = await _bounded(gateway.enablePush());
    if (_disposed || epoch != _epoch || !signedIn || !enabled) return;
    token = value;
    if (value == null || value.isEmpty) error = 'This device is not ready for push notifications. Check device setup and retry.';
  }

  bool _allowed(PushPermission value) =>
      value == PushPermission.granted || value == PushPermission.provisional;

  Future<void> setNotifications(bool value) => _queue(() async {
    if (!ready || !signedIn) return;
    if (!value) {
      // Update state immediately; a network failure must not leave the UI opted in.
      enabled = false;
      token = null;
      _epoch++;
      _notify();
      await preferences.write(false);
      await _bounded(gateway.disablePush());
      return;
    }
    permission = await _bounded(gateway.permission(request: true));
    if (!_allowed(permission)) {
      enabled = false;
      token = null;
      await preferences.write(false);
      await _bounded(gateway.disablePush());
      error = 'Notifications are blocked. Allow them in your phone’s app settings, then retry.';
      return;
    }
    enabled = true;
    try {
      await _refreshToken();
      await preferences.write(true);
    } catch (_) {
      enabled = false;
      token = null;
      await gateway.disablePush().catchError((_) {});
      rethrow;
    }
  });
  Future<void> refresh() => _queue(() async {
    if (!ready) return;
    permission = await _bounded(gateway.permission());
    if (!_allowed(permission)) {
      token = null;
      await _bounded(gateway.disablePush());
    } else {
      await _refreshToken();
    }
  });
  Future<void> setDiagnostics(bool value) => _queue(() async {
    if (!ready) return;
    try {
      await _bounded(gateway.setDiagnostics(value));
    } finally {
      diagnostics = gateway.diagnosticsEnabled;
    }
  });
  Future<void> sendDiagnosticTest() => _queue(() async {
    if (ready && diagnostics) await _bounded(gateway.sendDiagnosticTest());
  });
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _tokens?.cancel();
    _notices?.cancel();
    _events.close();
    gateway.dispose();
    super.dispose();
  }
}

class DeviceServicesScope extends InheritedNotifier<DeviceServices> {
  final VoidCallback onOpenSettings;
  const DeviceServicesScope({
    super.key,
    required DeviceServices services,
    required this.onOpenSettings,
    required super.child,
  }) : super(notifier: services);
  static void openSettings(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DeviceServicesScope>();
    if (scope != null) {
      scope.onOpenSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Device notifications are unavailable in this preview.',
          ),
        ),
      );
    }
  }

  static DeviceServices of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DeviceServicesScope>()
          ?.notifier ??
      DeviceServices.unavailable;
}
