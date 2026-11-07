import 'dart:convert';

import 'package:http/http.dart' as http;

import '../account.dart';

const previewUser = {
  'id': 'offline-preview',
  'displayName': 'Alex Preview',
  'email': 'preview@example.test',
  'role': 'customer',
};
const previewProfile = {
  'age': 28,
  'heightCm': 175,
  'weightKg': 80,
  'goal': 'general_fitness',
  'experience': 'beginner',
  'dietaryPreference': 'vegetarian',
  'equipment': ['Dumbbells'],
  'workoutDays': [0, 2, 4],
  'sessionMinutes': 30,
  'currentRoutine': 'Sample profile for reviewing the app.',
  'limitations': '',
  'foodNotes': '',
  'healthDataConsent': true,
  'shareWithTrainer': false,
  'shareCoachingWithTrainer': false,
};

class PreviewSessionStore implements SessionStore {
  String? _value = 'offline-preview';
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String token) async {
    _value = token;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

AccountController createPreviewAccount() =>
    AccountController(
        api: AccountApi(
          client: PreviewClient(),
          baseUrl: 'https://offline-preview.invalid',
        ),
        store: PreviewSessionStore(),
      )
      ..booting = false
      ..token = 'offline-preview'
      ..user = Map<String, dynamic>.from(previewUser)
      ..profile = Map<String, dynamic>.from(previewProfile);

// This client has no socket/network delegate. Unsupported actions explicitly fail.
// Only habit checks, workout logs and profile edits are simulated in memory.
class PreviewClient extends http.BaseClient {
  final _checks = <String, bool>{};
  final _logs = <String, Map<String, dynamic>>{};
  Map<String, dynamic> _profile = Map<String, dynamic>.from(previewProfile);
  String _day(DateTime t) => t.toIso8601String().substring(0, 10);
  DateTime get _now =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  String get today => _day(_now);
  Map<String, dynamic> _progress(String id) =>
      _logs[id] ??
      {
        'status': 'not_started',
        'revision': 0,
        'notes': '',
        'exerciseLogs': [],
        'completedAt': null,
      };
  Map<String, dynamic> get _membership => {
    'id': 'sample-membership',
    'planId': 'premium',
    'planName': 'Premium',
    'startsAt': DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 5))
        .toIso8601String(),
    'endsAt': DateTime.now()
        .toUtc()
        .add(const Duration(days: 25))
        .toIso8601String(),
    'videoSessionsTotal': 10,
    'videoSessionsUsed': 2,
    'videoSessionsReserved': 0,
    'videoSessionsRemaining': 8,
    'environment': 'development',
  };
  List<Map<String, dynamic>> get _workouts => [
    {
      'id': 'sample-strength',
      'title': 'Sample full-body session',
      'date': today,
      'exerciseCount': 2,
      'status': _progress('sample-strength')['status'],
    },
    {
      'id': 'sample-mobility',
      'title': 'Sample mobility session',
      'date': _day(_now.add(const Duration(days: 2))),
      'exerciseCount': 2,
      'status': _progress('sample-mobility')['status'],
    },
  ];
  Map<String, dynamic> _habits(String? selectedMonth) {
    final month = selectedMonth ?? today.substring(0, 7);
    final start = DateTime.parse('$month-01');
    final total = DateTime(start.year, start.month + 1, 0).day;
    final habits = ['Complete my workout', 'Log my meals', 'Take a walk']
        .indexed
        .map((e) {
          final id = 'sample-habit-${e.$1}';
          final count = _checks.entries
              .where((c) => c.key.startsWith('$id|$month') && c.value)
              .length;
          return {
            'id': id,
            'name': e.$2,
            'targetDays': 20,
            'goal': 20,
            'startsOn': '$month-01',
            'archivedOn': null,
            'completed': count,
            'progress': count / 20,
          };
        })
        .toList();
    final entries = _checks.entries
        .where((e) => e.key.split('|')[1].startsWith(month))
        .map(
          (e) => {
            'habitId': e.key.split('|')[0],
            'date': e.key.split('|')[1],
            'completed': e.value,
          },
        )
        .toList();
    final completed = entries.where((e) => e['completed'] == true).length;
    return {
      'month': month,
      'today': today,
      'timezone': 'Asia/Kolkata',
      'canEdit': true,
      'habits': habits,
      'entries': entries,
      'days': List.generate(total, (i) {
        final date = _day(DateTime(start.year, start.month, i + 1));
        return {
          'date': date,
          'completed': entries
              .where((e) => e['date'] == date && e['completed'] == true)
              .length,
          'eligible': date.compareTo(today) <= 0 ? habits.length : 0,
        };
      }),
      'summary': {
        'completed': completed,
        'goal': 60,
        'progress': completed / 60,
      },
    };
  }

  Map<String, dynamic> _nutrition(String date) {
    final values = {
      'calories': 280,
      'protein': 12,
      'carbs': 40,
      'fat': 8,
      'fiber': 6,
      'sugar': null,
      'sodium': null,
    };
    final entries = date == today
        ? [
            {
              'id': 'sample-meal',
              'revision': 1,
              'meal': 'breakfast',
              'grams': 100,
              'food': {
                'id': 'sample-food',
                'name': 'Sample breakfast bowl',
                'nutrients': values,
                'source': {
                  'type': 'label',
                  'label': 'Illustrative sample values',
                },
              },
              'nutrients': values,
            },
          ]
        : [];
    return {
      'date': date,
      'today': today,
      'canEdit': false,
      'timezone': 'Asia/Kolkata',
      'entries': entries,
      'targets': null,
      'totals': {
        for (final e in values.entries)
          e.key: {
            'known': entries.isEmpty ? 0 : (e.value ?? 0),
            'complete': entries.isEmpty || e.value != null,
            'missingEntries': entries.isNotEmpty && e.value == null ? 1 : 0,
          },
      },
    };
  }

  Map<String, dynamic> _route(
    String path,
    String method,
    Map<String, dynamic> body,
    Uri uri,
  ) {
    if (path == '/auth/me' ||
        path == '/auth/login' ||
        path == '/auth/register') {
      return {
        'user': previewUser,
        'profile': _profile,
        'token': 'offline-preview',
      };
    }
    if (path == '/auth/logout') return {'signedOut': true};
    if (path == '/me/profile' && method == 'PUT') {
      _profile = Map<String, dynamic>.from(body);
      return {'profile': _profile};
    }
    if (path == '/plans') {
      return {
        'plans': [
          {
            'id': 'normal',
            'name': 'Normal',
            'priceInPaise': 300000,
            'videoSessions': 0,
            'durationMonths': 1,
            'features': [
              'Stored exercise demonstrations',
              'AI workout planning and coaching',
              'Nutrition, habits and progress tracking',
            ],
          },
          {
            'id': 'premium',
            'name': 'Premium',
            'priceInPaise': 1000000,
            'videoSessions': 10,
            'durationMonths': 1,
            'features': [
              'All Normal features',
              '10 live video coaching sessions',
            ],
          },
          {
            'id': 'premium-plus',
            'name': 'Premium Plus',
            'priceInPaise': 2000000,
            'videoSessions': 25,
            'durationMonths': 1,
            'features': [
              'All lower-plan features',
              '25 live video coaching sessions in total',
            ],
          },
        ],
      };
    }
    if (path == '/me/membership') {
      return {
        'status': 'active',
        'current': _membership,
        'next': null,
        'history': [],
        'billing': {'checkoutEnabled': false},
      };
    }
    if (path == '/me/habits' && method == 'GET') {
      return _habits(uri.queryParameters['month']);
    }
    if (RegExp(r'^/me/habits/[^/]+/days/[^/]+$').hasMatch(path) &&
        method == 'PUT') {
      final parts = path.split('/');
      _checks['${parts[3]}|${parts[5]}'] = body['completed'] == true;
      return {'saved': true};
    }
    if (path == '/me/workouts/history') {
      return {
        'workouts': [
          for (final w in _workouts)
            if (_logs.containsKey(w['id']))
              {...w, 'notes': _logs[w['id']]!['notes']},
        ],
      };
    }
    if (path == '/me/workouts') {
      final from = uri.queryParameters['from'] ?? today;
      final through = _day(DateTime.parse(from).add(const Duration(days: 6)));
      return {
        'from': from,
        'through': through,
        'plan': {
          'id': 'sample-plan',
          'title': 'Sample weekly routine',
          'version': 1,
          'source': 'development_fixture',
        },
        'workouts': _workouts
            .where(
              (w) =>
                  (w['date'] as String).compareTo(from) >= 0 &&
                  (w['date'] as String).compareTo(through) <= 0,
            )
            .toList(),
      };
    }
    if (path.endsWith('/video')) return {'available': false};
    if (path.startsWith('/me/workouts/') && method == 'GET') {
      final id = path.split('/').last;
      final w = _workouts.firstWhere((w) => w['id'] == id);
      return {
        'workout': {
          ...w,
          'archived': false,
          'source': 'development_fixture',
          'version': 1,
        },
        'today': today,
        'progress': _progress(id),
        'items': ['Bodyweight squat', 'Standing calf raise'].indexed
            .map(
              (e) => {
                'id': 'sample-item-${e.$1}',
                'exercise': {
                  'id': 'sample-exercise-${e.$1}',
                  'name': e.$2,
                  'instructions': [
                    'Illustrative exercise entry for reviewing the workout screen.',
                  ],
                },
                'sets': 2,
                'repetitions': 10,
                'targetWeightKg': null,
                'restSeconds': 60,
              },
            )
            .toList(),
      };
    }
    if (RegExp(r'^/me/workouts/[^/]+/progress$').hasMatch(path) &&
        method == 'PUT') {
      final id = path.split('/')[3],
          revision = (_progress(id)['revision'] as int) + 1;
      _logs[id] = {
        ...body,
        'revision': revision,
        'completedAt': body['status'] == 'completed'
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      };
      return {'revision': revision, 'duplicate': false};
    }
    if (path == '/me/nutrition' && method == 'GET') {
      return _nutrition(uri.queryParameters['date'] ?? today);
    }
    if (path == '/me/progress' && method == 'GET') {
      return {
        'today': today,
        'canEdit': false,
        'timezone': 'Asia/Kolkata',
        'records': [
          for (final e in [0, 7, 14].indexed)
            {
              'id': 'sample-progress-${e.$1}',
              'date': _day(_now.subtract(Duration(days: e.$2))),
              'revision': 1,
              'photos': [],
              'measurements': {
                'weight': 79.2 + e.$1 * .6,
                'waist': null,
                'chest': null,
                'arms': null,
                'thighs': null,
              },
            },
        ],
      };
    }
    if (path == '/me/trainer-feedback') {
      return {
        'feedback': [
          {
            'id': 'sample-feedback',
            'trainer': 'Sample coach',
            'kind': 'coaching',
            'decision': 'follow_up',
            'feedback': 'Sample trainer note: this is where saved feedback will appear.',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'result': {},
          },
        ],
      };
    }
    if (path == '/me/ai-planning/status') {
      return {
        'configured': false,
        'entitled': true,
        'profileReady': true,
        'eligibleExerciseCount': 0,
        'dailyLimit': 2,
        'remainingToday': 2,
        'latest': null,
      };
    }
    if (path == '/me/meal-estimates/status') {
      return {'configured': false, 'remainingToday': 0, 'dailyLimit': 0};
    }
    if (path == '/me/coaching/facts') return {'facts': null};
    if (path == '/me/coaching' && method == 'GET') {
      return {
        'configured': false,
        'canSend': false,
        'turns': [],
        'nextBefore': null,
        'limits': {'chat': 0, 'summary': 0},
        'remaining': {'chat': 0, 'summary': 0},
      };
    }
    if (path == '/me/sessions' && method == 'GET') {
      return {
        'confirmed': false,
        'policy': null,
        'revision': 0,
        'bookingEnabled': false,
        'providerConfigured': false,
        'membership': _membership,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'timezone': 'Asia/Kolkata',
        'slots': [],
        'bookings': [
          {
            'id': 'sample-booking',
            'trainerName': 'Sample coach',
            'startsAt': DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 2))
                .toIso8601String(),
            'endsAt': DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 2))
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'status': 'completed',
            'consumed': true,
            'revision': 2,
            'attendanceNote': 'Illustrative completed appointment.',
            'policy': {
              'durationMinutes': 30,
              'freeCancellationHours': 12,
              'chargeLateCancellation': true,
              'chargeNoShow': true,
            },
          },
        ],
      };
    }
    throw const ApiFailure(
      501,
      'This action needs the connected app. This offline demo uses sample data.',
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    int status = 200;
    Map<String, dynamic> data;
    try {
      final bytes = await request.finalize().toBytes();
      final body =
          request.headers['content-type']?.startsWith('application/json') ==
                  true &&
              bytes.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)))
          : <String, dynamic>{};
      data = _route(request.url.path, request.method, body, request.url);
    } on ApiFailure catch (e) {
      status = e.status;
      data = {'message': e.message};
    } catch (_) {
      status = 501;
      data = {'message': 'This action is unavailable in the offline preview.'};
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(data))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}
