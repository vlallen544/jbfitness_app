import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'workout_pages.dart';

class TrainerFeedbackPage extends StatefulWidget {
  final AccountController account;
  const TrainerFeedbackPage({super.key, required this.account});
  @override
  State<TrainerFeedbackPage> createState() => _TrainerFeedbackPageState();
}

class _TrainerFeedbackPageState extends State<TrainerFeedbackPage> {
  List<Map<String, dynamic>>? _feedback;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/trainer-feedback',
      );
      if (mounted) {
        setState(() {
          _feedback = (data['feedback'] as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = e is ApiFailure ? e.message : 'Feedback could not load.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trainer feedback'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Refresh trainer feedback',
          icon: const Icon(Icons.refresh),
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
              'A personal\nnext step.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Read your trainer’s saved feedback and open a reviewed workout when one is available.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              TextButton(onPressed: _load, child: const Text('Retry feedback')),
            ],
            if (_feedback == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_feedback?.isEmpty == true)
              const Text(
                'No trainer feedback yet. You can manage assigned-trainer sharing in your profile.',
              ),
            for (final item in _feedback ?? <Map<String, dynamic>>[])
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE0E7DF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item['trainer'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${dayString(DateTime.parse(item['createdAt']).toLocal())} · ${item['kind'] == 'planning' ? 'Workout review' : 'Coaching review'}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      container: true,
                      label: item['feedback'],
                      child: ExcludeSemantics(
                        child: SelectableText(item['feedback']),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item['decision'] == 'follow_up'
                          ? 'Follow-up note'
                          : item['decision'] == 'publish_plan'
                          ? 'Reviewed workout published'
                          : 'Review completed',
                      style: const TextStyle(
                        color: forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item['result']?['planId'] != null) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: const Text('Reviewed workouts'),
                              ),
                              body: WorkoutsPage(
                                account: widget.account,
                                initialFrom: item['result']['startDate'],
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Open reviewed workouts'),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
