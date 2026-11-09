import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'stitch_ui.dart';
import 'habits_page.dart';
import 'nutrition_page.dart';
import 'meal_estimate_page.dart';
import 'progress_page.dart';
import 'coaching_page.dart';
import 'trainer_feedback_page.dart';
import 'sessions_page.dart';
import 'workout_pages.dart';

class TodayPage extends StatefulWidget {
  final AccountController account;
  final VoidCallback onOpenWorkouts;
  final VoidCallback? onOpenProfile, onOpenPlans;
  const TodayPage({
    super.key,
    required this.account,
    required this.onOpenWorkouts,
    this.onOpenProfile,
    this.onOpenPlans,
  });
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  Map<String, dynamic>? _membership, _schedule, _nutrition, _feedback;
  int _day = DateTime.now().weekday - 1, _refreshRevision = 0;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>?> _read(String path) async {
    try {
      return await widget.account.authenticatedRequest(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final user = widget.account.user?['id'];
    if (mounted) setState(() => _loading = true);
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final results = await Future.wait([
      _read('/me/membership'),
      _read('/me/workouts?from=${dayString(monday)}'),
      _read('/me/nutrition'),
      _read('/me/trainer-feedback'),
    ]);
    if (!mounted || widget.account.user?['id'] != user) return;
    setState(() {
      _membership = results[0];
      _schedule = results[1]?['workouts'] is List ? results[1] : null;
      _nutrition = results[2]?['totals'] is Map ? results[2] : null;
      _feedback = results[3]?['feedback'] is List ? results[3] : null;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshRevision++);
    await _load();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _load();
  }

  void _diary() => _open(NutritionPage(account: widget.account));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final selected = monday.add(Duration(days: _day));
    final name = (widget.account.user?['displayName'] as String? ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    final current = _membership?['current'] as Map<String, dynamic>?;
    final workouts = (_schedule?['workouts'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final workout = workouts
        .where((w) => w['date'] == dayString(selected))
        .firstOrNull;
    final minutes = widget.account.profile?['sessionMinutes'];
    final days = widget.account.profile?['workoutDays'] as List?;
    final feedback = (_feedback?['feedback'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              StitchBrandHeader(
                'Today',
                onProfile: widget.onOpenProfile,
                onRefresh: _refresh,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: widget.onOpenPlans,
                        borderRadius: BorderRadius.circular(20),
                        child: StitchPill(
                          current == null
                              ? (_membership?['status'] == 'expired'
                                    ? 'MEMBERSHIP EXPIRED'
                                    : 'VIEW MEMBERSHIP')
                              : '${current['planName'].toString().toUpperCase()} · ${current['videoSessionsRemaining']} SESSIONS LEFT',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_months[now.month - 1]} ${now.day}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Ready to train?',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Hello there.' : 'Hello, $name.',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Open AI coach',
                    onPressed: () =>
                        _open(CoachingPage(account: widget.account)),
                    style: IconButton.styleFrom(backgroundColor: stitchBlue),
                    icon: const Icon(Icons.bolt_outlined, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              StitchCard(
                padding: const EdgeInsets.all(8),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Row(
                    children: List.generate(7, (i) {
                      final date = monday.add(Duration(days: i));
                      final active = _day == i;
                      final done = workouts.any(
                        (w) =>
                            w['date'] == dayString(date) &&
                            w['status'] == 'completed',
                      );
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 6 ? 0 : 4),
                          child: Semantics(
                            selected: active,
                            label:
                                '${dayString(date)}${done ? ', workout completed' : ''}',
                            button: true,
                            child: InkWell(
                              onTap: () => setState(() => _day = i),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: active ? brandRed : canvas,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _days[i],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: active ? Colors.white : muted,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: active ? Colors.white : ink,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Icon(
                                      done
                                          ? Icons.check_circle_rounded
                                          : Icons.circle,
                                      size: done ? 12 : 4,
                                      color: active
                                          ? Colors.white
                                          : done
                                          ? brandRed
                                          : border,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _workoutCard(workout, minutes, days),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, bounds) {
                  final width = MediaQuery.textScalerOf(context).scale(14) > 19
                      ? bounds.maxWidth
                      : (bounds.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: width,
                        child: StitchActionTile(
                          icon: Icons.add_circle_outline_rounded,
                          title: 'Log Meal',
                          subtitle: '+ Macros',
                          onTap: _diary,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: StitchActionTile(
                          icon: Icons.photo_camera_outlined,
                          title: 'Snap Food',
                          subtitle: 'Photo or text estimate',
                          red: true,
                          onTap: () => _open(
                            MealEstimatePage(
                              account: widget.account,
                              date: dayString(now),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: StitchActionTile(
                          icon: Icons.monitor_weight_outlined,
                          title: 'Bodyweight',
                          subtitle: widget.account.profile?['weightKg'] == null
                              ? 'Record your progress'
                              : '${widget.account.profile!['weightKg']} kg · profile',
                          onTap: () =>
                              _open(ProgressPage(account: widget.account)),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: StitchActionTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Chat Coach',
                          subtitle: 'Your coaching space',
                          onTap: () =>
                              _open(CoachingPage(account: widget.account)),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              StitchFuelCard(data: _nutrition, onOpen: _diary),
              const SizedBox(height: 24),
              HabitsPanel(
                key: ValueKey(_refreshRevision),
                account: widget.account,
              ),
              const SizedBox(height: 20),
              StitchCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.support_agent_rounded,
                          color: brandRed,
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your coaching',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      feedback.isEmpty
                          ? 'Read your trainer’s feedback and keep your next step in view.'
                          : (feedback.first['feedback']?.toString() ??
                                'Read the latest trainer feedback.'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.6,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _open(TrainerFeedbackPage(account: widget.account)),
                      icon: const Icon(Icons.mark_chat_read_outlined, size: 17),
                      label: const Text('Trainer feedback'),
                    ),
                    const Divider(height: 20),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _open(SessionsPage(account: widget.account)),
                      icon: const Icon(Icons.video_call_outlined, size: 18),
                      label: const Text('Live coaching sessions'),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Updating your daily overview…',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workoutCard(
    Map<String, dynamic>? workout,
    dynamic minutes,
    List? days,
  ) {
    final completed = workout?['status'] == 'completed';
    void details() {
      if (workout?['id'] is String) {
        _open(
          WorkoutDetailPage(
            account: widget.account,
            workoutId: workout!['id'] as String,
          ),
        );
      } else {
        widget.onOpenWorkouts();
      }
    }

    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StitchPill(
                    workout == null
                        ? 'YOUR TRAINING'
                        : completed
                        ? 'Completed'
                        : workout['status'] == 'in_progress'
                        ? 'In progress'
                        : 'Scheduled',
                    icon: Icons.schedule_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                workout == null
                    ? 'Your routine'
                    : '${workout['exerciseCount']} exercises',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 72,
                decoration: BoxDecoration(
                  color: stitchBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  size: 32,
                  color: ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout?['title']?.toString() ??
                          'A routine built around you',
                      style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      [
                        if (minutes != null) '$minutes min / session',
                        if (days != null) '${days.length} days / week',
                      ].join('  ·  '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Progress',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
              Expanded(
                child: Text(
                  workout == null
                      ? 'Open your schedule'
                      : completed
                      ? '100% completed'
                      : workout['status'] == 'in_progress'
                      ? 'In progress'
                      : '0% started',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: completed ? 1 : 0,
              minHeight: 6,
              color: brandRed,
              backgroundColor: stitchBlue,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, bounds) {
              final large = MediaQuery.textScalerOf(context).scale(14) > 19;
              final primary = FilledButton.icon(
                onPressed: workout == null ? widget.onOpenWorkouts : details,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  workout == null
                      ? 'Open workouts'
                      : completed
                      ? 'Review workout'
                      : 'Start Workout',
                ),
              );
              final secondary = FilledButton(
                onPressed: details,
                style: FilledButton.styleFrom(
                  backgroundColor: stitchBlue,
                  foregroundColor: ink,
                ),
                child: const Text('Details'),
              );
              return large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [primary, const SizedBox(height: 8), secondary],
                    )
                  : Row(
                      children: [
                        Expanded(child: primary),
                        const SizedBox(width: 8),
                        secondary,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}
