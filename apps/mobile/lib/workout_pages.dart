import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'account.dart';
import 'exercise_video.dart';
import 'app_theme.dart';
import 'ai_planning_page.dart';

String dayString(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String requestId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class WorkoutsPage extends StatefulWidget {
  final AccountController account;
  final String? initialFrom;
  const WorkoutsPage({super.key, required this.account, this.initialFrom});
  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  late DateTime _week;
  late Future<Map<String, dynamic>> _data;
  @override
  void initState() {
    super.initState();
    final now = widget.initialFrom == null
        ? DateTime.now()
        : DateTime.parse(widget.initialFrom!);
    _week = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    _data = _load();
  }

  Future<Map<String, dynamic>> _load() => widget.account.authenticatedRequest(
    '/me/workouts?from=${dayString(_week)}',
  );
  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    final next = _load();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  void _move(int days) {
    setState(() {
      _week = _week.add(Duration(days: days));
      _data = _load();
    });
  }

  Future<void> _planning() async {
    final start = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AiPlanningPage(account: widget.account),
      ),
    );
    if (!mounted) return;
    if (start != null) {
      final date = DateTime.parse(start);
      _week = date.subtract(Duration(days: date.weekday - 1));
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Text(
              'JB FITNESS',
              style: TextStyle(
                color: brandRed,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkoutHistoryPage(account: widget.account),
                ),
              ),
              child: const Text('History'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'TRAIN WITH INTENTION',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        Text('Your workouts', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 10),
        const Text(
          'Follow your schedule, review demonstrations and record how each session went.',
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _planning,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Plan with AI'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () => _move(-7),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${dayString(_week)} – ${dayString(_week.add(const Duration(days: 6)))}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () => _move(7),
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Refresh workouts',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return _notice(
                error is ApiFailure && error.status == 403
                    ? 'Active membership needed'
                    : 'Workouts could not load',
                error is ApiFailure && error.status == 403
                    ? 'Workout schedules and demonstrations are included from the Normal plan. Your saved workout history is still available.'
                    : 'Please check your connection and retry.',
                action: TextButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final data = snapshot.data!;
            final plan = data['plan'] as Map<String, dynamic>?;
            final workouts = (data['workouts'] as List)
                .cast<Map<String, dynamic>>();
            if (plan == null) {
              return _notice(
                'Your routine is being prepared',
                'Request a plan with AI, or return when your trainer has published a schedule. AI planning requires a connected service and approved exercise content.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${plan['title']} • v${plan['version']}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (plan['source'] == 'development_fixture')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Development sample • awaiting trainer-reviewed content.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                if (plan['source'] == 'ai')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'AI-generated plan · application checks and AI review completed.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (plan['source'] == 'trainer')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Trainer-reviewed workout plan.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (workouts.isEmpty)
                  _notice(
                    'No sessions this week',
                    'Use the week controls to review another part of your schedule.',
                  ),
                ...workouts.map(
                  (workout) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      title: Text(
                        workout['title'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${workout['date']}\n${workout['exerciseCount']} exercises • ${(workout['status'] as String).replaceAll('_', ' ')}',
                        style: const TextStyle(height: 1.7),
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: workout['status'] == 'completed'
                              ? brandRed
                              : softRed,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          workout['status'] == 'completed'
                              ? Icons.check_rounded
                              : Icons.fitness_center_rounded,
                          color: workout['status'] == 'completed'
                              ? Colors.white
                              : brandRed,
                          size: 20,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkoutDetailPage(
                              account: widget.account,
                              workoutId: workout['id'] as String,
                            ),
                          ),
                        );
                        if (mounted) {
                          await _refresh();
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

Widget _notice(String title, String body, {Widget? action}) => Card(
  child: Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(color: Colors.black54, height: 1.5)),
        ?action,
      ],
    ),
  ),
);

class WorkoutDetailPage extends StatefulWidget {
  final AccountController account;
  final String workoutId;
  const WorkoutDetailPage({
    super.key,
    required this.account,
    required this.workoutId,
  });
  @override
  State<WorkoutDetailPage> createState() => _WorkoutDetailPageState();
}

class _WorkoutDetailPageState extends State<WorkoutDetailPage> {
  Map<String, dynamic>? _data;
  final _notes = TextEditingController();
  final _logs = <String, Map<String, dynamic>>{};
  final _fields = <String, List<TextEditingController>>{};
  final _videos = <String>{};
  bool _loading = true, _saving = false;
  String? _error;
  int _revision = 0;
  String _status = 'not_started';
  String? _pendingJson, _pendingId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _clearFields() {
    for (final controllers in _fields.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    _fields.clear();
    _logs.clear();
  }

  @override
  void dispose() {
    _clearFields();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/workouts/${widget.workoutId}',
      );
      if (!mounted) {
        return;
      }
      _clearFields();
      final progress = data['progress'] as Map<String, dynamic>;
      _revision = progress['revision'] as int;
      _status = progress['status'] as String;
      _notes.text = progress['notes'] as String;
      for (final item in (data['items'] as List).cast<Map<String, dynamic>>()) {
        final itemId = item['id'] as String;
        final previous = (progress['exerciseLogs'] as List)
            .cast<Map<String, dynamic>>()
            .where((log) => log['itemId'] == itemId)
            .firstOrNull;
        _logs[itemId] = {
          'itemId': itemId,
          'completed': previous?['completed'] == true,
          'difficulty': previous?['difficulty'],
        };
        _fields[itemId] =
            ['actualSets', 'actualRepetitions', 'actualWeightKg', 'notes']
                .map(
                  (key) => TextEditingController(
                    text: previous?[key]?.toString() ?? '',
                  ),
                )
                .toList();
      }
      setState(() {
        _data = data;
        _loading = false;
        _pendingId = null;
        _pendingJson = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiFailure
              ? error.message
              : 'Could not load this workout.';
        });
      }
    }
  }

  num? _number(TextEditingController field, num max, {bool integer = false}) {
    if (field.text.trim().isEmpty) {
      return null;
    }
    final value = num.tryParse(field.text.trim());
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > max ||
        (integer && value != value.roundToDouble())) {
      throw const FormatException(
        'Check actual sets, repetitions and weight. Use non-negative numbers within the displayed limits.',
      );
    }
    return integer ? value.toInt() : value;
  }

  Future<void> _save(String status) async {
    if (_saving) {
      return;
    }
    try {
      final logs = _logs.entries.map((entry) {
        final fields = _fields[entry.key]!;
        return {
          ...entry.value,
          'actualSets': _number(fields[0], 30, integer: true),
          'actualRepetitions': _number(fields[1], 500, integer: true),
          'actualWeightKg': _number(fields[2], 1000),
          'notes': fields[3].text,
        };
      }).toList();
      if (status == 'completed' &&
          logs.any((log) => log['completed'] != true)) {
        setState(
          () => _error =
              'Mark every exercise complete before completing the workout.',
        );
        return;
      }
      final body = {
        'revision': _revision,
        'status': status,
        'notes': _notes.text,
        'exerciseLogs': logs,
      };
      final encoded = jsonEncode(body);
      if (_pendingJson != encoded) {
        _pendingJson = encoded;
        _pendingId = requestId();
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      final result = await widget.account.authenticatedRequest(
        '/me/workouts/${widget.workoutId}/progress',
        method: 'PUT',
        body: {...body, 'requestId': _pendingId},
      );
      if (mounted) {
        setState(() {
          _revision = result['revision'] as int;
          _status = status;
          _pendingId = null;
          _pendingJson = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout progress saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : error is FormatException
              ? error.message
              : 'Could not save. Your edits are still on this screen.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workout = _data?['workout'] as Map<String, dynamic>?;
    final archived = workout?['archived'] == true;
    final future =
        workout != null &&
        workout['date'].toString().compareTo(_data!['today'] as String) > 0;
    final readOnly = _saving || archived || future;
    final items = (_data?['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final checked = _logs.values
        .where((log) => log['completed'] == true)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: _notice(
                'Workout unavailable',
                _error ?? 'Please retry.',
                action: TextButton(
                  onPressed: _load,
                  child: const Text('Reload workout'),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR SESSION',
                        style: TextStyle(
                          color: accentRed,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        workout!['title'] as String,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${workout['date']} • ${_status.replaceAll('_', ' ')}',
                        style: const TextStyle(
                          color: onDarkMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 22),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: items.isEmpty ? 0 : checked / items.length,
                          minHeight: 6,
                          backgroundColor: darkTrack,
                          color: accentRed,
                          semanticsLabel: 'Exercises checked on this screen',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$checked / ${items.length} exercises checked',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Save progress to keep your changes.',
                        style: TextStyle(color: onDarkSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_status == 'completed')
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: _SessionSavedNotice(),
                  ),
                if (workout['source'] == 'development_fixture')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Development sample • content awaits trainer review.',
                    ),
                  ),
                if (archived)
                  const Text('Archived plan • progress is read-only.'),
                if (future)
                  const Text(
                    'You can log this workout on its scheduled day or later.',
                  ),
                const SizedBox(height: 14),
                const SizedBox(height: 10),
                Text(
                  'Your exercises',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                ...items.indexed.map((entry) {
                  final item = entry.$2;
                  final itemId = item['id'] as String;
                  final exercise = item['exercise'] as Map<String, dynamic>;
                  final fields = _fields[itemId]!;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXERCISE ${(entry.$1 + 1).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _logs[itemId]!['completed'] as bool,
                            onChanged: readOnly
                                ? null
                                : (value) => setState(
                                    () => _logs[itemId]!['completed'] =
                                        value ?? false,
                                  ),
                            title: Text(
                              exercise['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 19,
                              ),
                            ),
                          ),
                          Text(
                            '${item['sets']} sets × ${item['repetitions']} reps • ${item['restSeconds']} sec rest',
                            style: const TextStyle(
                              color: brandRed,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item['targetWeightKg'] != null)
                            Text(
                              'Suggested load: ${item['targetWeightKg']} kg',
                            ),
                          const SizedBox(height: 12),
                          const Divider(height: 20),
                          const Text(
                            'How to perform',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...(exercise['instructions'] as List).map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('• $step'),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              backgroundColor: softRed,
                              foregroundColor: brandRed,
                            ),
                            onPressed: () =>
                                setState(() => _videos.add(itemId)),
                            icon: const Icon(Icons.play_circle_outline),
                            label: const Text('Watch demonstration'),
                          ),
                          if (_videos.contains(itemId))
                            ExerciseVideo(
                              key: ValueKey(itemId),
                              account: widget.account,
                              exerciseId: exercise['id'] as String,
                            ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Actual performance (optional)'),
                            subtitle: const Text(
                              'Record what you did and how it felt.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) => Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: List.generate(
                                    3,
                                    (index) => SizedBox(
                                      width: constraints.maxWidth < 360
                                          ? constraints.maxWidth
                                          : (constraints.maxWidth - 24) / 3,
                                      child: TextField(
                                        controller: fields[index],
                                        enabled: !readOnly,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: [
                                            'Sets done',
                                            'Reps done',
                                            'Weight (kg)',
                                          ][index],
                                          helperText: [
                                            '0–30',
                                            '0–500',
                                            '0–1000',
                                          ][index],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue:
                                    (_logs[itemId]!['difficulty'] as String?) ??
                                    'not_set',
                                decoration: const InputDecoration(
                                  labelText: 'Difficulty',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'not_set',
                                    child: Text('Not recorded'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'easy',
                                    child: Text('Easy'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'moderate',
                                    child: Text('Moderate'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hard',
                                    child: Text('Hard'),
                                  ),
                                ],
                                onChanged: readOnly
                                    ? null
                                    : (value) => _logs[itemId]!['difficulty'] =
                                          value == 'not_set' ? null : value,
                              ),
                              TextField(
                                controller: fields[3],
                                enabled: !readOnly,
                                maxLength: 500,
                                decoration: const InputDecoration(
                                  labelText: 'Exercise feedback',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 14),
                Text(
                  'Finish your session',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Add any feedback, then save your progress or complete the workout.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _notes,
                  enabled: !readOnly,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Session feedback',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: readOnly ? null : () => _save('completed'),
                  child: Text(_saving ? 'Saving…' : 'Complete workout'),
                ),
                OutlinedButton(
                  onPressed: readOnly
                      ? null
                      : () => _save(
                          _status == 'completed' &&
                                  _logs.values.every(
                                    (log) => log['completed'] == true,
                                  )
                              ? 'completed'
                              : 'in_progress',
                        ),
                  child: const Text('Save progress'),
                ),
                TextButton(
                  onPressed: readOnly ? null : () => _save('skipped'),
                  child: const Text('Skip workout'),
                ),
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: const Text('Reload saved workout'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SessionSavedNotice extends StatelessWidget {
  const _SessionSavedNotice();
  @override
  Widget build(BuildContext context) => Card(
    color: softRed,
    child: const Padding(
      padding: EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: brandRed),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session completed',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  'Your completion is saved. Save again if you update your feedback.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class WorkoutHistoryPage extends StatefulWidget {
  final AccountController account;
  const WorkoutHistoryPage({super.key, required this.account});
  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  late Future<Map<String, dynamic>> _data;
  @override
  void initState() {
    super.initState();
    _data = widget.account.authenticatedRequest('/me/workouts/history');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Workout history')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _notice(
              'History could not load',
              'Please retry.',
              action: TextButton(
                onPressed: () => setState(() {
                  _data = widget.account.authenticatedRequest(
                    '/me/workouts/history',
                  );
                }),
                child: const Text('Try again'),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = (snapshot.data!['workouts'] as List)
            .cast<Map<String, dynamic>>();
        if (rows.isEmpty) {
          return const Center(
            child: Text('Your saved workouts will appear here.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your most recent 50 saved sessions',
              style: TextStyle(color: Colors.black54),
            ),
            ...rows.map(
              (row) => Card(
                child: ListTile(
                  title: Text(row['title'] as String),
                  subtitle: Text(
                    '${row['date']} • ${(row['status'] as String).replaceAll('_', ' ')}\n${row['notes']}',
                    style: const TextStyle(height: 1.7),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
