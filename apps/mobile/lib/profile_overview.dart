import 'package:flutter/material.dart';

import 'account.dart';
import 'account_screens.dart';
import 'app_theme.dart';
import 'stitch_ui.dart';
import 'fitness_intro.dart';
import 'sessions_page.dart';
import 'trainer_feedback_page.dart';
import 'progress_page.dart';
import 'notification_settings_page.dart';
import 'device_services.dart';

class ProfileOverview extends StatefulWidget {
  final AccountController account;
  final VoidCallback onOpenPlans;
  const ProfileOverview({
    super.key,
    required this.account,
    required this.onOpenPlans,
  });
  @override
  State<ProfileOverview> createState() => _ProfileOverviewState();
}

class _ProfileOverviewState extends State<ProfileOverview> {
  Map<String, dynamic>? _membership;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.account.authenticatedRequest('/me/membership');
      if (mounted) {
        setState(() {
          _membership = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Membership details could not load. Pull down to retry.',
        );
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Future<void> _share(String field, bool value) async {
    if (_saving || widget.account.profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.account.saveProfile({
        ...widget.account.profile!,
        field: value,
        if (field == 'shareWithTrainer' && !value)
          'shareCoachingWithTrainer': false,
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : 'Your sharing choice could not be saved. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '—' : '${date.day}/${date.month}/${date.year}';
  }

  Widget _heading(String small, String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(small, style: const TextStyle(color: muted, fontSize: 10)),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Icon(icon, color: brandRed, size: 22),
      ],
    ),
  );
  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: stitchBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: ink, size: 21),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: muted, fontSize: 10, height: 1.6),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 21),
    onTap: onTap,
  );
  void _unavailable(String feature) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$feature is not available yet.')));

  @override
  Widget build(BuildContext context) {
    final user = widget.account.user ?? {};
    final profile = widget.account.profile ?? {};
    final current = _membership?['current'] as Map<String, dynamic>?;
    final total = (current?['videoSessionsTotal'] as num?)?.toInt() ?? 0;
    final remaining =
        (current?['videoSessionsRemaining'] as num?)?.toInt() ?? 0;
    final name = user['displayName']?.toString() ?? 'Your profile';
    final initial = name.trim().isEmpty
        ? 'JB'
        : name.trim().substring(0, 1).toUpperCase();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          StitchBrandHeader('Profile', onRefresh: _load),
          const SizedBox(height: 22),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: stitchBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 5),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: StitchPill(
              current == null
                  ? 'YOUR FITNESS ACCOUNT'
                  : '${current['planName'].toString().toUpperCase()} MEMBER',
              icon: Icons.workspace_premium_outlined,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 5),
          Text(
            user['email']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 18),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: brandRed, fontSize: 12),
              ),
            ),
          if (current != null)
            StitchCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StitchPill(
                    'Active until ${_date(current['endsAt'])}',
                    red: false,
                    icon: Icons.event_available_outlined,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: total == 0
                          ? 0
                          : (remaining / total).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      color: brandRed,
                      backgroundColor: stitchBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total == 0
                        ? 'Stored demonstrations included · no live sessions'
                        : '$remaining of $total live sessions remaining',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          _heading(
            'Tier management',
            'Membership & coaching',
            Icons.workspace_premium_outlined,
          ),
          StitchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'CURRENT MEMBERSHIP',
                  style: TextStyle(
                    color: brandRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  current?['planName']?.toString() ??
                      (_membership?['status'] == 'expired'
                          ? 'Membership expired'
                          : 'Choose your support'),
                  style: const TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your plan, dates and coaching-session balance in one place.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onOpenPlans,
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  label: const Text('Compare membership plans'),
                ),
              ],
            ),
          ),
          _heading(
            'Your support',
            'Coaching space',
            Icons.support_agent_rounded,
          ),
          StitchCard(
            child: Column(
              children: [
                _tile(
                  Icons.mark_chat_read_outlined,
                  'Trainer feedback',
                  'Read feedback shared with your account',
                  () => _open(TrainerFeedbackPage(account: widget.account)),
                ),
                const Divider(height: 16),
                _tile(
                  Icons.calendar_month_outlined,
                  'Live coaching sessions',
                  'Availability and credits depend on your membership',
                  () => _open(SessionsPage(account: widget.account)),
                ),
              ],
            ),
          ),
          _heading(
            'Preferences',
            'Settings & data sharing',
            Icons.tune_rounded,
          ),
          StitchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tile(
                  Icons.fitness_center_rounded,
                  'Your fitness profile',
                  'Equipment, training days, measurements and food preferences',
                  () => _open(
                    Scaffold(
                      appBar: AppBar(title: const Text('Fitness profile')),
                      body: SafeArea(
                        child: FitnessProfilePage(account: widget.account),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 20),
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: brandRed, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Trainer data sharing',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Profile sharing',
                    style: TextStyle(fontSize: 12),
                  ),
                  subtitle: const Text(
                    'Allow your assigned trainer to review your profile.',
                    style: TextStyle(fontSize: 10),
                  ),
                  value: profile['shareWithTrainer'] == true,
                  onChanged: _saving
                      ? null
                      : (v) => _share('shareWithTrainer', v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Coaching review sharing',
                    style: TextStyle(fontSize: 12),
                  ),
                  subtitle: const Text(
                    'Enable profile sharing first, then choose whether to share coaching questions and summaries.',
                    style: TextStyle(fontSize: 10),
                  ),
                  value:
                      profile['shareWithTrainer'] == true &&
                      profile['shareCoachingWithTrainer'] == true,
                  onChanged: _saving || profile['shareWithTrainer'] != true
                      ? null
                      : (v) => _share('shareCoachingWithTrainer', v),
                ),
                if (_saving) const LinearProgressIndicator(),
                _tile(
                  Icons.lock_outline_rounded,
                  'Progress photos',
                  'Private to your account',
                  () => _open(ProgressPage(account: widget.account)),
                ),
                const Divider(height: 20),
                _tile(
                  Icons.medication_outlined,
                  'Supplement store',
                  'Coming soon',
                  () => _unavailable('The supplement store'),
                ),
                _tile(
                  Icons.notifications_active_outlined,
                  'Notifications & reminders',
                  'Device updates and optional crash reports',
                  () => _open(
                    NotificationSettingsPage(
                      services: DeviceServicesScope.of(context),
                    ),
                  ),
                ),
                _tile(
                  Icons.play_circle_outline_rounded,
                  'Replay app walkthrough',
                  'Explore workouts, meals, progress and coaching',
                  () => _open(
                    Builder(
                      builder: (tourContext) => FitnessIntro(
                        onFinished: () => Navigator.of(tourContext).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _heading(
            'Your account',
            'Account management',
            Icons.person_outline_rounded,
          ),
          StitchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : () => widget.account.signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                ),
                const Divider(),
                const Text(
                  'Data export and account-deletion requests will be available before public launch.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
