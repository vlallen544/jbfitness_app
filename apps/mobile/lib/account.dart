import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiFailure implements Exception {
  final int status;
  final String message;
  const ApiFailure(this.status, this.message);
  @override
  String toString() => message;
}

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'jbfitness.session.v1';
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class AccountApi {
  final http.Client client;
  final String baseUrl;
  AccountApi({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3001/api/v1',
    ),
  }) : client = client ?? http.Client();
  Future<Uint8List> progressPhoto(String id, String? token) async {
    try {
      final response = await client
          .get(
            Uri.parse('$baseUrl/me/progress/photos/$id'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        throw ApiFailure(
          response.statusCode,
          'This progress photo could not be loaded.',
        );
      }
      return response.bodyBytes;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(0, 'Could not load the photo. Please retry.');
    }
  }

  Future<void> uploadProgressPhoto(
    String id,
    Map<String, String> fields,
    Uint8List photo,
    String? token,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/me/progress/$id/photos'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photo,
          filename: 'progress-photo',
        ),
      );
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw ApiFailure(
          response.statusCode,
          data['message'] is String
              ? data['message']
              : 'Could not save the progress photo.',
        );
      }
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        0,
        'Could not confirm the upload. Retry to check the same photo.',
      );
    }
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'));
      request.headers['Content-Type'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) request.body = jsonEncode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        var message = data['message'] is String
            ? data['message'] as String
            : 'The request could not be completed.';
        final issues = data['issues'];
        if (issues is List && issues.isNotEmpty) {
          message =
              '$message ${issues.first['field']}: ${issues.first['message']}';
        }
        throw ApiFailure(response.statusCode, message);
      }
      return data;
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(0, 'The connection timed out. Please try again.');
    } catch (_) {
      throw const ApiFailure(
        0,
        'Could not connect. Check your connection and try again.',
      );
    }
  }

  Future<Map<String, dynamic>> mealEstimate(
    Map<String, String> fields,
    Uint8List? photo,
    String? token,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/me/meal-estimates'),
      );
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      if (photo != null) {
        request.files.add(
          http.MultipartFile.fromBytes('photo', photo, filename: 'meal-photo'),
        );
      }
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 65));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiFailure(
          response.statusCode,
          body['message'] is String
              ? body['message'] as String
              : 'The meal estimate could not complete.',
        );
      }
      return body;
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(
        0,
        'The estimate is taking longer than expected. Retry the same input to check its result.',
      );
    } catch (_) {
      throw const ApiFailure(
        0,
        'Could not connect. Your diary has not changed.',
      );
    }
  }
}

class AccountController extends ChangeNotifier {
  final AccountApi api;
  final SessionStore store;
  AccountController({required this.api, required this.store});
  bool booting = true;
  String? bootError;
  String? token;
  Map<String, dynamic>? user;
  Map<String, dynamic>? profile;

  Future<void> restore() async {
    booting = true;
    bootError = null;
    notifyListeners();
    try {
      final saved = await store.read();
      if (saved != null) {
        final data = await api.request('/auth/me', token: saved);
        token = saved;
        user = data['user'] as Map<String, dynamic>;
        profile = data['profile'] as Map<String, dynamic>?;
      }
    } on ApiFailure catch (error) {
      if (error.status == 401) {
        await store.clear();
        token = null;
        user = null;
        profile = null;
      } else {
        bootError = error.message;
      }
    } catch (_) {
      bootError = 'Could not restore your saved session. Try again or sign out on this device.';
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> authenticate({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final data = await api.request(
      displayName == null ? '/auth/login' : '/auth/register',
      method: 'POST',
      body: {
        'email': email.trim(),
        'password': password,
        if (displayName != null) 'displayName': displayName.trim(),
      },
    );
    final newToken = data['token'] as String;
    try {
      await store.write(newToken);
    } catch (_) {
      try {
        await api.request('/auth/logout', method: 'POST', token: newToken);
      } catch (_) {}
      throw const ApiFailure(
        0,
        'Could not securely save your session on this device. Please try again.',
      );
    }
    token = newToken;
    user = data['user'] as Map<String, dynamic>;
    profile = data['profile'] as Map<String, dynamic>?;
    bootError = null;
    notifyListeners();
  }

  Future<void> saveProfile(Map<String, dynamic> value) async {
    try {
      final data = await api.request(
        '/me/profile',
        method: 'PUT',
        body: value,
        token: token,
      );
      profile = data['profile'] as Map<String, dynamic>;
      notifyListeners();
    } on ApiFailure catch (error) {
      if (error.status == 401) {
        await signOut(localOnly: true);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> authenticatedRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await api.request(
        path,
        method: method,
        body: body,
        token: token,
        timeout: timeout,
      );
    } on ApiFailure catch (error) {
      if (error.status == 401) {
        await signOut(localOnly: true);
      }
      rethrow;
    }
  }

  Future<Uint8List> progressPhoto(String id) async {
    try {
      return await api.progressPhoto(id, token);
    } on ApiFailure catch (error) {
      if (error.status == 401) await signOut(localOnly: true);
      rethrow;
    }
  }

  Future<void> uploadProgressPhoto(
    String id,
    Map<String, String> fields,
    Uint8List bytes,
  ) async {
    try {
      await api.uploadProgressPhoto(id, fields, bytes, token);
    } on ApiFailure catch (error) {
      if (error.status == 401) await signOut(localOnly: true);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> estimateMeal(
    Map<String, String> fields,
    Uint8List? photo,
  ) async {
    try {
      return await api.mealEstimate(fields, photo, token);
    } on ApiFailure catch (error) {
      if (error.status == 401) await signOut(localOnly: true);
      rethrow;
    }
  }

  Future<void> signOut({bool localOnly = false}) async {
    if (!localOnly && token != null) {
      try {
        await api.request('/auth/logout', method: 'POST', token: token);
      } catch (_) {
        /* Local sign-out still applies; server sessions expire after seven days. */
      }
    }
    await store.clear();
    token = null;
    user = null;
    profile = null;
    bootError = null;
    booting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    api.client.close();
    super.dispose();
  }
}
