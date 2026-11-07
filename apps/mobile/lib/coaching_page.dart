import 'dart:async';

import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'workout_pages.dart' show requestId;

String coachNumber(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

class CoachingPage extends StatefulWidget {
  final AccountController account;
  const CoachingPage({super.key, required this.account});
  @override
  State<CoachingPage> createState() => _CoachingPageState();
}

class _CoachingPageState extends State<CoachingPage>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  Map<String, dynamic>? _state, _facts, _pendingPayload;
  List<Map<String, dynamic>> _turns = [];
  String? _error, _nextBefore;
  bool _busy = false, _loadingEarlier = false;
  int _revision = 0, _historyEpoch = 0;
  Timer? _poll;
  bool get _pending => _turns.any((r) => r['status'] == 'pending');
  bool get _canSend =>
      _state?['configured'] == true &&
      _state?['canSend'] == true &&
      !_busy &&
      !_pending &&
      _pendingPayload == null;
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
    _text.dispose();
    super.dispose();
  }

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
    if (mounted &&
        (_pending || _pendingPayload != null) &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
      _poll = Timer(const Duration(seconds: 3), _load);
    }
  }

  Future<void> _load() async {
    _poll?.cancel();
    final revision = ++_revision;
    try {
      final values = await Future.wait([
        widget.account.authenticatedRequest('/me/coaching'),
        widget.account.authenticatedRequest('/me/coaching/facts'),
      ]);
      if (!mounted || revision != _revision) return;
      final data = values[0],
          rows = (data['turns'] as List).cast<Map<String, dynamic>>();
      setState(() {
        final merged = {
          if (data['nextBefore'] != null)
            for (final r in _turns) r['id']: r,
          for (final r in rows) r['id']: r,
        };
        _turns = merged.values.toList()
          ..sort(
            (a, b) => '${a['createdAt']}${a['id']}'.compareTo(
              '${b['createdAt']}${b['id']}',
            ),
          );
        _state = data;
        _facts = values[1]['facts'];
        _error = null;
        if (_turns.length <= rows.length) _nextBefore = data['nextBefore'];
        if (_pendingPayload != null &&
            rows.any((r) => r['requestId'] == _pendingPayload!['requestId'])) {
          if (_pendingPayload!['kind'] == 'chat') _text.clear();
          _pendingPayload = null;
        }
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Could not load your coach.',
        );
      }
    }
    _schedule();
  }

  Future<void> _earlier() async {
    if (_nextBefore == null) return;
    final epoch = _historyEpoch;
    setState(() => _loadingEarlier = true);
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/coaching?before=$_nextBefore',
      );
      if (mounted && epoch == _historyEpoch) {
        setState(() {
          final merged = {
            for (final r
                in (data['turns'] as List).cast<Map<String, dynamic>>())
              r['id']: r,
            for (final r in _turns) r['id']: r,
          };
          _turns = merged.values.toList()
            ..sort(
              (a, b) => '${a['createdAt']}${a['id']}'.compareTo(
                '${b['createdAt']}${b['id']}',
              ),
            );
          _nextBefore = data['nextBefore'];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Earlier messages could not load.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  Future<void> _send(String kind) async {
    if (_pendingPayload == null) {
      final message = kind == 'chat' ? _text.text.trim() : '';
      if (kind == 'chat' && message.isEmpty) return;
      _pendingPayload = {
        'kind': kind,
        'message': message,
        'requestId': requestId(),
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.authenticatedRequest(
        '/me/coaching',
        method: 'POST',
        body: _pendingPayload,
        timeout: const Duration(seconds: 65),
      );
      await _load();
    } catch (e) {
      if (e is ApiFailure && e.status >= 400 && e.status < 500) {
        _pendingPayload = null;
        await _load();
      }
      if (mounted) {
        setState(
          () => _error = e is ApiFailure ? e.message : 'Could not confirm the coaching request. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear coaching history?'),
        content: const Text(
          'Remove saved messages, AI summaries and related trainer feedback. Your workouts, food diary and body progress stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _poll?.cancel();
    _historyEpoch++;
    _revision++;
    setState(() => _busy = true);
    try {
      await widget.account.authenticatedRequest(
        '/me/coaching',
        method: 'DELETE',
      );
      if (!mounted) return;
      setState(() {
        _turns = [];
        _pendingPayload = null;
        _nextBefore = null;
        _text.clear();
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Could not clear coaching history.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI coach'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Refresh coaching',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _busy ? null : _clear,
          tooltip: 'Clear coaching history',
          icon: const Icon(Icons.delete_outline),
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
              'A little guidance.\nA clearer next step.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ask about your routine or get practical food ideas. AI uses your saved fitness and dietary preferences, recent records and the last six chat exchanges. Photos are not included.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (_facts != null) CoachingFacts(facts: _facts!),
            const SizedBox(height: 18),
            if (_state == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Refresh conversation'),
              ),
            ],
            if (_state != null) ...[
              if (_state!['configured'] != true)
                const Text(
                  'AI coaching is not connected yet. You can still review your recorded week.',
                ),
              if (_state!['canSend'] != true)
                const Text(
                  'An active membership is needed for new replies and summaries. Saved history remains available.',
                ),
              const SizedBox(height: 10),
              Text(
                '${_state!['remaining']['chat']} messages · ${_state!['remaining']['summary']} summaries left today',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    _canSend && (_state!['remaining']['summary'] as num) > 0
                    ? () => _send('summary')
                    : null,
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('Summarize my last 7 days'),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'Your conversation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_nextBefore != null)
              TextButton(
                onPressed: _loadingEarlier ? null : _earlier,
                child: Text(
                  _loadingEarlier ? 'Loading…' : 'Load earlier messages',
                ),
              ),
            if (_turns.isEmpty)
              const Text(
                'Try “How can I make my routine more consistent?” or ask for a meal idea using your dietary preferences.',
                style: TextStyle(color: muted),
              ),
            for (final turn in _turns) ...[
              _turn(turn),
              const SizedBox(height: 16),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (_pendingPayload != null && !_busy) ...[
              const Text(
                'The request has not been confirmed. Retry uses the same reference.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => _send(_pendingPayload!['kind']),
                child: const Text('Retry same coaching request'),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: _canSend,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Ask your AI coach',
                hintText: 'What should I focus on this week?',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _canSend && (_state!['remaining']['chat'] as num) > 0
                  ? () => _send('chat')
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send to AI coach'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Replies are AI-generated general fitness guidance. A conversation does not update your workouts, food diary or nutrition targets.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _turn(Map<String, dynamic> turn) {
    final response = turn['response'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE6EDDF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              turn['kind'] == 'summary'
                  ? 'Summarize my last 7 days'
                  : turn['input'] ?? '',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI COACH',
                style: TextStyle(
                  color: lime,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (turn['status'] == 'pending')
                const Text(
                  'Preparing your response. You can return later to check it.',
                  style: TextStyle(color: Colors.white),
                )
              else if (turn['status'] == 'failed')
                const Text(
                  'This request did not finish. No AI reply was saved. You can send a new request within your daily allowance.',
                  style: TextStyle(color: Colors.white),
                )
              else if (response != null) ...[
                Semantics(
                  container: true,
                  label: response['reply'],
                  child: ExcludeSemantics(
                    child: SelectableText(
                      response['reply'],
                      style: const TextStyle(color: Colors.white, height: 1.5),
                    ),
                  ),
                ),
                for (final suggestion in response['suggestions'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '• $suggestion',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                if (response['needsTrainerReview'] == true) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Trainer review needed',
                    style: TextStyle(color: lime, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    response['reviewReason'] ?? '',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (turn['kind'] == 'summary' && turn['facts'] != null) ...[
          const SizedBox(height: 8),
          CoachingFacts(facts: turn['facts'], snapshot: true),
        ],
      ],
    );
  }
}

class CoachingFacts extends StatelessWidget {
  final Map<String, dynamic> facts;
  final bool snapshot;
  const CoachingFacts({super.key, required this.facts, this.snapshot = false});
  @override
  Widget build(BuildContext context) {
    final workouts = facts['workouts'],
        nutrition = facts['nutrition'],
        habits = facts['habits'],
        weight = facts['weight'];
    final readings = weight['readings'] as List;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E7DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            snapshot ? 'Recorded summary snapshot' : 'Your recorded week',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '${facts['from']} → ${facts['through']}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            '${workouts['completed']} completed workouts · ${workouts['skipped']} skipped',
          ),
          const SizedBox(height: 8),
          Text(
            '${workouts['scheduledInCurrentPlan']} scheduled sessions in the current plan during this period',
          ),
          const SizedBox(height: 8),
          Text(
            'Food logged on ${nutrition['loggedDays']} of 7 days · ${nutrition['entries']} entries',
          ),
          if ((nutrition['estimatedEntries'] as num) > 0)
            Text(
              '${nutrition['estimatedEntries']} food entries include AI estimates',
              style: const TextStyle(color: muted),
            ),
          const SizedBox(height: 8),
          Text(
            '${habits['completedCheckIns']} habit check-ins across ${habits['habitsWithCheckIns']} habits',
          ),
          const SizedBox(height: 8),
          if (readings.isEmpty)
            const Text('No weight recorded in this period.')
          else if (readings.length == 1)
            Text(
              'Weight: ${coachNumber(readings.first['kg'])} kg on ${readings.first['date']}. A second reading is needed for comparison.',
            )
          else
            Text(
              'Weight: ${coachNumber(readings.first['kg'])} → ${coachNumber(readings.last['kg'])} kg (${(weight['changeKg'] as num) > 0 ? '+' : ''}${coachNumber(weight['changeKg'])} kg), ${readings.first['date']} → ${readings.last['date']}',
            ),
          const SizedBox(height: 8),
          const Text(
            'Calculated from saved records. Unlogged days and missing measurements stay unknown.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('View logged nutrition'),
              children: [
                for (final day in nutrition['days'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        day['totals'] == null
                            ? '${day['date']}: no food logged'
                            : '${day['date']}: ${coachNumber(day['totals']['calories']['known'])} kcal logged${day['totals']['calories']['complete'] == true ? '' : ' (partial values)'}${day['estimatedEntries'] > 0 ? ' · includes AI estimates' : ''}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
