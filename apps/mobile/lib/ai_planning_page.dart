import 'dart:async';

import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'workout_pages.dart' show requestId;

class AiPlanningPage extends StatefulWidget {
  final AccountController account;
  const AiPlanningPage({super.key, required this.account});
  @override
  State<AiPlanningPage> createState() => _AiPlanningPageState();
}

class _AiPlanningPageState extends State<AiPlanningPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _status, _run;
  String? _error, _request;
  bool _busy = false;
  Timer? _poll;
  int _loadRevision = 0;
  final _stages = {
    'queued': 'Waiting to start',
    'routine_review': 'Reviewing your routine',
    'drafting': 'Building your workout',
    'validation': 'Checking the schedule and exercises',
    'plan_review': 'Reviewing the workout draft',
    'revision': 'Adjusting the workout',
    'revision_review': 'Reviewing the revision',
    'published': 'Plan published',
    'trainer_published': 'Trainer plan published',
    'review_needed': 'Trainer review needed',
    'interrupted': 'Planning interrupted',
    'failed': 'Planning did not finish',
    'stale': 'Refresh needed',
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _pending => ['queued', 'running'].contains(_run?['status']);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    } else {
      _poll?.cancel();
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (_pending &&
        mounted &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
      _poll = Timer(const Duration(seconds: 3), _load);
    }
  }

  Future<void> _load() async {
    _poll?.cancel();
    final revision = ++_loadRevision;
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/ai-planning/status',
      );
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _status = data;
        _run = data['latest'] as Map<String, dynamic>?;
        _error = null;
        if (_run != null && _run!['requestId'] == _request) {
          _request = null;
        }
      });
    } catch (e) {
      if (mounted && revision == _loadRevision) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Planning status could not load.',
        );
      }
    }
    _schedule();
  }

  bool get _ready =>
      _status?['configured'] == true &&
      _status?['entitled'] == true &&
      _status?['profileReady'] == true &&
      (_status?['eligibleExerciseCount'] as num? ?? 0) > 0 &&
      ((_status?['remainingToday'] as num? ?? 0) > 0 || _request != null) &&
      !_pending;
  Future<void> _generate() async {
    _request ??= requestId();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/ai-planning',
        method: 'POST',
        body: {'requestId': _request},
      );
      if (!mounted) return;
      setState(() {
        _run = data;
        _request = null;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Could not confirm the request. Refresh before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _run?['routineReview'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI workout planning'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh planning status',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'A routine built\naround you.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your saved goals, routine, equipment and training days guide a plan for the next seven days, starting tomorrow.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REVIEW → PLAN → CHECK → PUBLISH',
                      style: TextStyle(
                        color: accentRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'AI reviews your routine, drafts your workouts and reviews the result. The app checks the dates, exercises and session limits. A draft can be revised once before a trainer review is needed.',
                      style: TextStyle(color: Colors.white, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'When a plan passes, it replaces your current schedule. Saved workout logs stay in your history. Only approved exercises are used. Starting weights are left unset for you to choose during training. Requesting a plan sends your saved fitness profile and recent workout notes to the AI service. Progress photos are not included.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              if (_status == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: brandRed)),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh status'),
                ),
              ],
              if (_status != null) ...[
                if (_status!['configured'] != true)
                  const Text(
                    'AI workout planning is not connected yet. Your existing workouts remain available.',
                  ),
                if (_status!['entitled'] != true)
                  const Text(
                    'An active membership is required to generate a workout plan.',
                  ),
                if (_status!['profileReady'] != true)
                  const Text(
                    'Complete your fitness profile before requesting a plan.',
                  ),
                if (_status!['profileReady'] == true &&
                    (_status!['eligibleExerciseCount'] as num? ?? 0) == 0)
                  const Text(
                    'Approved exercises matching your equipment have not been supplied yet.',
                  ),
                const SizedBox(height: 10),
                Text(
                  '${_status!['remainingToday']} of ${_status!['dailyLimit']} planning requests left today',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _ready && !_busy ? _generate : null,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    _busy
                        ? 'Submitting…'
                        : _request != null
                        ? 'Retry same planning request'
                        : _run == null
                        ? 'Generate my workout plan'
                        : 'Generate a new plan',
                  ),
                ),
              ],
              if (_run != null) ...[
                const SizedBox(height: 24),
                Text(
                  _run!['trainerReview']?['status'] == 'resolved' &&
                          _run!['status'] != 'published'
                      ? 'Trainer review complete'
                      : _stages[_run!['stage']] ?? 'Planning status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (_pending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                Text(
                  _run!['trainerReview']?['status'] == 'resolved' &&
                          _run!['status'] != 'published'
                      ? _run!['trainerReview']['feedback'] ??
                            'Your trainer completed this review.'
                      : _run!['message'] ?? '',
                ),
                if (_pending)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'You can close this screen and return to check the result. Refreshing never starts another generation.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                if (review != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Your routine review',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(review['summary'] ?? ''),
                  for (final note in review['notes'] as List? ?? [])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('• $note'),
                    ),
                ],
                if (_run!['status'] == 'published') ...[
                  const SizedBox(height: 16),
                  Text(
                    'Training dates: ${_run!['startDate']} to ${_run!['through']}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _run!['startDate'] as String),
                    child: const Text('View published workouts'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
