import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';

class MemorySessionStore implements SessionStore {
  String? value;
  MemorySessionStore([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

const sampleUser = {
  'id': 'customer-fixture',
  'email': 'customer@example.test',
  'displayName': 'Test Customer',
  'role': 'customer',
};
const sampleProfile = {
  'age': 28,
  'heightCm': 175,
  'weightKg': 80,
  'goal': 'general_fitness',
  'experience': 'beginner',
  'dietaryPreference': 'vegetarian',
  'equipment': ['Dumbbells'],
  'workoutDays': [0, 2, 4],
  'sessionMinutes': 40,
  'currentRoutine': 'Walking',
  'limitations': '',
  'healthDataConsent': true,
  'shareWithTrainer': false,
  'shareCoachingWithTrainer': false,
};
http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<AccountController> signedInAccount() async {
  final checked = <String, bool>{};
  final account = AccountController(
    store: MemorySessionStore('fixture-session'),
    api: AccountApi(
      client: MockClient((request) async {
        if (request.url.path.contains('/me/habits')) {
          if (request.method == 'PUT') {
            checked[request.url.pathSegments[request.url.pathSegments.indexOf(
                      'habits',
                    ) +
                    1]] =
                (jsonDecode(request.body) as Map)['completed'] == true;
            return jsonResponse({'saved': true});
          }
          return jsonResponse(habitFixture(checked: checked));
        }
        return jsonResponse({'user': sampleUser, 'profile': sampleProfile});
      }),
    ),
  );
  await account.restore();
  return account;
}

Map<String, dynamic> habitFixture({
  Map<String, bool> checked = const {},
  bool canEdit = true,
}) {
  final now = DateTime.now();
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final today = '$month-${now.day.toString().padLeft(2, '0')}';
  final total = DateTime(now.year, now.month + 1, 0).day;
  final done = checked.values.where((value) => value).length;
  return {
    'month': month,
    'today': today,
    'timezone': 'Asia/Kolkata',
    'canEdit': canEdit,
    'habits': ['Complete my workout', 'Log my meals', 'Take a walk'].indexed
        .map(
          (entry) => {
            'id': 'habit-${entry.$1 + 1}',
            'name': entry.$2,
            'targetDays': 20,
            'goal': 20,
            'startsOn': '$month-01',
            'archivedOn': null,
            'completed': checked['habit-${entry.$1 + 1}'] == true ? 1 : 0,
            'progress': checked['habit-${entry.$1 + 1}'] == true ? .05 : 0,
          },
        )
        .toList(),
    'entries': checked.entries
        .where((entry) => entry.value)
        .map(
          (entry) => {'habitId': entry.key, 'date': today, 'completed': true},
        )
        .toList(),
    'days': List.generate(
      total,
      (index) => {
        'date': '$month-${(index + 1).toString().padLeft(2, '0')}',
        'completed': index + 1 == now.day ? done : 0,
        'eligible': index + 1 <= now.day ? 3 : 0,
      },
    ),
    'summary': {'completed': done, 'goal': 60, 'progress': done / 60},
  };
}
