import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class IntroStore {
  Future<bool> hasCompleted();
  Future<void> complete();
}

class SecureIntroStore implements IntroStore {
  static const _key = 'jbfitness.feature_walkthrough.v2';
  final _storage = const FlutterSecureStorage();
  @override
  Future<bool> hasCompleted() async => await _storage.read(key: _key) == 'true';
  @override
  Future<void> complete() => _storage.write(key: _key, value: 'true');
}

class MemoryIntroStore implements IntroStore {
  bool seen;
  MemoryIntroStore({this.seen = false});
  @override
  Future<bool> hasCompleted() async => seen;
  @override
  Future<void> complete() async {
    seen = true;
  }
}
