import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'workout_pages.dart' show requestId;

String habitDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class HabitsPanel extends StatefulWidget {
  final AccountController account;
  final bool compact;
  const HabitsPanel({super.key, required this.account, this.compact = true});
  @override
  State<HabitsPanel> createState() => _HabitsPanelState();
}

class _HabitsPanelState extends State<HabitsPanel> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _pendingCreate;
  bool _loading = true, _busy = false, _monthly = true;
  int _week = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _load(widget.compact ? null : _data?['month'] as String?);
    }
  }

  Future<void> _load([String? month]) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/habits${month == null ? '' : '?month=$month'}',
      );
      if (data['habits'] is! List || data['entries'] is! List) {
        throw const ApiFailure(0, 'Habit data is unavailable. Please refresh.');
      }
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiFailure
              ? error.message
              : 'Habits could not load. Please refresh.';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _habits =>
      (_data?['habits'] as List? ?? []).cast<Map<String, dynamic>>();
  bool get _canEdit =>
      _data?['canEdit'] == true && !_busy && !_loading && _error == null;
  bool _checked(String id, String day) =>
      (_data?['entries'] as List? ?? []).any(
        (entry) =>
            entry['habitId'] == id &&
            entry['date'] == day &&
            entry['completed'] == true,
      );
  bool _eligible(Map<String, dynamic> habit, String day) =>
      day.compareTo(habit['startsOn'] as String) >= 0 &&
      (habit['archivedOn'] == null ||
          day.compareTo(habit['archivedOn'] as String) <= 0);
  Future<bool> _write(
    String path,
    Map<String, dynamic> body, {
    String method = 'PUT',
  }) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.authenticatedRequest(
        path,
        method: method,
        body: body,
      );
      await _load(
        widget.compact || method == 'POST' ? null : _data?['month'] as String?,
      );
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure ? error.message : 'Could not save. Refresh to check the latest saved state, then retry.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final target = TextEditingController(text: '20');
    final form = GlobalKey<FormState>();
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a daily habit'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'For example: Take a walk. Your monthly goal counts the days you complete this habit.',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Habit name'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a habit name.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monthly target (days)',
                    helperText:
                        '1–31; shortened to eligible days in the month.',
                    helperMaxLines: 3,
                  ),
                  validator: (value) {
                    final n = int.tryParse(value ?? '');
                    return n == null || n < 1 || n > 31
                        ? 'Enter a whole number from 1 to 31.'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'targetDays': int.parse(target.text),
                  'requestId': requestId(),
                });
              }
            },
            child: const Text('Add habit'),
          ),
        ],
      ),
    );
    // Wait until the dialog's closing animation no longer uses the controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    target.dispose();
    if (body == null || !mounted) return;
    setState(() => _pendingCreate = body);
    await _retryCreate();
  }

  Future<void> _retryCreate() async {
    final body = _pendingCreate;
    if (body != null &&
        await _write('/me/habits', body, method: 'POST') &&
        mounted) {
      setState(() => _pendingCreate = null);
    }
  }

  Future<void> _details(Map<String, dynamic> habit) async {
    final archive = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(habit['name'] as String),
        content: Text(
          '${habit['completed']} completed days / ${habit['goal']} target days this month.\n\n${habit['archivedOn'] == null ? 'Targets are set when a habit is created. Archiving keeps past checkmarks and makes the habit read-only.' : 'Archived on ${habit['archivedOn']}. Past records are kept read-only.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (_canEdit && habit['archivedOn'] == null)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive habit'),
            ),
        ],
      ),
    );
    if (archive == true && mounted) {
      await _write('/me/habits/${habit['id']}/archive', {});
    }
  }

  void _moveMonth(int delta) {
    final current = DateTime.parse('${_data!['month']}-01');
    final next = DateTime(current.year, current.month + delta);
    if (next.year < 2020 || next.year > 2100) return;
    _week = 0;
    _load(habitDay(next).substring(0, 7));
  }

  Future<void> _openTracking() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Habit tracking')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: HabitsPanel(account: widget.account, compact: false),
            ),
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = _data?['today'] as String?;
    final active = _habits
        .where(
          (habit) =>
              habit['archivedOn'] == null &&
              today != null &&
              _eligible(habit, today),
        )
        .toList();
    final done = today == null
        ? 0
        : active
              .where((habit) => _checked(habit['id'] as String, today))
              .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.compact
                    ? 'Small wins, every day'
                    : 'Build your consistency',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 8),
            if (_data != null && widget.compact)
              Text(
                '$done / ${active.length}',
                style: const TextStyle(
                  color: brandRed,
                  fontWeight: FontWeight.w800,
                ),
              ),
            IconButton(
              tooltip: 'Refresh habits',
              onPressed: _busy
                  ? null
                  : () => _load(
                      widget.compact ? null : _data?['month'] as String?,
                    ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.compact ? 'Daily check-ins saved to your account.' : 'Check a day to record a habit. Tap a habit name for its details.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_pendingCreate != null)
          TextButton(
            onPressed: _busy ? null : _retryCreate,
            child: const Text('Retry adding habit'),
          ),
        if (_data != null) ...[
          if (_data!['canEdit'] != true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'An active membership is required to add or update habits. Your saved history is still available.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          if (widget.compact) ...[
            const SizedBox(height: 12),
            if (active.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Start with one small habit. Add a name and a monthly completion target.',
                  ),
                ),
              ),
            ...active.map(
              (habit) => Card(
                child: CheckboxListTile(
                  value: _checked(habit['id'] as String, today!),
                  onChanged: _canEdit
                      ? (value) => _write(
                          '/me/habits/${habit['id']}/days/$today',
                          {'completed': value ?? false},
                        )
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    habit['name'] as String,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${habit['completed']} / ${habit['goal']} target days this month',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ),
            ),
          ] else
            ..._tracking(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: _canEdit && _pendingCreate == null ? _create : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add habit'),
              ),
              if (widget.compact)
                TextButton(
                  onPressed: _openTracking,
                  child: const Text('View tracking'),
                ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Saving…',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Calendar: Asia/Kolkata · Checkmarks are personal habit logs; they do not complete workouts or log meals.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.5),
          ),
        ],
      ],
    );
  }

  List<Widget> _tracking() {
    final month = _data!['month'] as String;
    final days = (_data!['days'] as List).cast<Map<String, dynamic>>();
    final shown = _monthly ? days : days.skip(_week * 7).take(7).toList();
    final summary = _data!['summary'] as Map<String, dynamic>;
    return [
      const SizedBox(height: 20),
      Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: _busy || _loading ? null : () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              month,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: _busy || _loading ? null : () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      Card(
        color: ink,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MONTHLY HABIT PROGRESS',
                style: TextStyle(
                  color: accentRed,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${summary['completed']} check-ins',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${((summary['progress'] as num) * 100).round()}% of habit targets · ${summary['goal']} target days combined',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (summary['progress'] as num).toDouble(),
                  color: accentRed,
                  backgroundColor: darkTrack,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Daily check-ins',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: days.map((day) {
            final eligible = day['eligible'] as num;
            final completed = day['completed'] as num;
            return Expanded(
              child: Semantics(
                label: '${day['date']}: $completed of $eligible habits',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            heightFactor: eligible == 0
                                ? .03
                                : (completed / eligible).toDouble().clamp(
                                    .03,
                                    1,
                                  ),
                            child: ColoredBox(
                              color: completed > 0 ? brandRed : border,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [1, 8, 15, 22, 29].contains(
                              int.parse((day['date'] as String).substring(8)),
                            )
                            ? (day['date'] as String).substring(8)
                            : '',
                        style: const TextStyle(fontSize: 8, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 10,
        children: [
          ChoiceChip(
            label: const Text('Weekly'),
            selected: !_monthly,
            onSelected: (_) => setState(() => _monthly = false),
          ),
          ChoiceChip(
            label: const Text('Monthly'),
            selected: _monthly,
            onSelected: (_) => setState(() => _monthly = true),
          ),
        ],
      ),
      if (!_monthly)
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: !_busy && !_loading && _week > 0
                  ? () => setState(() => _week--)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                'Days ${_week * 7 + 1}–${(_week * 7 + 7).clamp(1, days.length)}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: !_busy && !_loading && (_week + 1) * 7 < days.length
                  ? () => setState(() => _week++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      const SizedBox(height: 12),
      if (_habits.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No habits were active in this month. Add a habit to begin tracking from today.',
            ),
          ),
        )
      else
        _grid(shown),
      const SizedBox(height: 10),
      const Text(
        'Swipe the dates horizontally. Monthly targets are capped to the days a habit exists in that month. Future dates and archived habits are read-only.',
        style: TextStyle(color: muted, fontSize: 11),
      ),
    ];
  }

  Widget _grid(List<Map<String, dynamic>> days) {
    final rowHeight = MediaQuery.textScalerOf(context).scale(14) > 19
        ? 116.0
        : 88.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 126,
          child: Column(
            children: [
              const SizedBox(
                height: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HABIT / TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              ..._habits.map(
                (habit) => SizedBox(
                  height: rowHeight,
                  child: TextButton(
                    onPressed: () => _details(habit),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(right: 10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit['name'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${habit['completed']} / ${habit['goal']} days${habit['archivedOn'] != null ? ' · archived' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: days
                      .map(
                        (day) => SizedBox(
                          width: 44,
                          height: 56,
                          child: Center(
                            child: Text(
                              (day['date'] as String).substring(8),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                ..._habits.map(
                  (habit) => Row(
                    children: days.map((day) {
                      final date = day['date'] as String;
                      final editable =
                          _canEdit &&
                          habit['archivedOn'] == null &&
                          _eligible(habit, date) &&
                          date.compareTo(_data!['today'] as String) <= 0;
                      final checked = _checked(habit['id'] as String, date);
                      return SizedBox(
                        width: 44,
                        height: rowHeight,
                        child: Semantics(
                          label: '${habit['name']}, $date',
                          child: Checkbox(
                            value: checked,
                            onChanged: editable
                                ? (value) => _write(
                                    '/me/habits/${habit['id']}/days/$date',
                                    {'completed': value ?? false},
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
