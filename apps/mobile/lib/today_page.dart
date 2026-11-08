import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'habits_page.dart';
import 'nutrition_page.dart';
import 'progress_page.dart';
import 'coaching_page.dart';
import 'trainer_feedback_page.dart';
import 'sessions_page.dart';

class TodayPage extends StatefulWidget {
  final AccountController account;
  final VoidCallback onOpenWorkouts;
  const TodayPage({
    super.key,
    required this.account,
    required this.onOpenWorkouts,
  });
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final name = (widget.account.user?['displayName'] as String? ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    final minutes = widget.account.profile?['sessionMinutes'];
    final workoutDays = widget.account.profile?['workoutDays'] as List?;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'JB',
                      style: TextStyle(
                        color: accentRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'JB FITNESS',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'YOUR DAILY RESET',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${now.day} ${_months[now.month - 1]}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              name.isEmpty ? 'Hello there.' : 'Hello, $name.',
              style: const TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              'Make time\nfor yourself.',
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontSize: 36),
            ),
            const SizedBox(height: 20),
            Semantics(
              label:
                  'This week. Today is ${now.year}-${now.month}-${now.day}. Other days do not show completion history.',
              child: ExcludeSemantics(
                child: Row(
                  children: List.generate(7, (i) {
                    final date = monday.add(Duration(days: i));
                    final selected = i == now.weekday - 1;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 6 ? 0 : 6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? ink : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? ink : border),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _days[i],
                              style: TextStyle(
                                fontSize: 10,
                                color: selected ? Colors.white70 : muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: selected ? Colors.white : ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: selected
                                    ? accentRed
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: brandRed,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'YOUR TRAINING',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.fitness_center_rounded,
                        color: accentRed,
                        size: 25,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'One session.\nA stronger you.',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.12,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    [
                      if (minutes != null) '$minutes min / session',
                      if (workoutDays != null)
                        '${workoutDays.length} days / week',
                    ].join('  ·  '),
                    style: const TextStyle(color: onDarkMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Based on your profile preferences',
                    style: TextStyle(color: onDarkSubtle, fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: brandRed,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: widget.onOpenWorkouts,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('Open workouts')),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NutritionPage(account: widget.account),
                ),
              ),
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Open food diary'),
            ),
            const SizedBox(height: 22),
            HabitsPanel(account: widget.account),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionsPage(account: widget.account),
                ),
              ),
              icon: const Icon(Icons.video_call_outlined),
              label: const Text('Live coaching sessions'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainerFeedbackPage(account: widget.account),
                ),
              ),
              icon: const Icon(Icons.mark_chat_read_outlined),
              label: const Text('Trainer feedback'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CoachingPage(account: widget.account),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Open AI coach'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProgressPage(account: widget.account),
                ),
              ),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('View body progress'),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: softRed,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_outlined, color: brandRed),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A little guidance goes a long way.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Open AI coach for questions and weekly summaries, or Workouts for routine review and planning when the services are available.',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
