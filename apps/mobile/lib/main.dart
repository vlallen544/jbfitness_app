import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'account_screens.dart';
import 'membership_page.dart';
import 'workout_pages.dart';
import 'app_theme.dart';
import 'today_page.dart' as dashboard;
import 'fitness_intro.dart';
import 'intro_store.dart';
import 'profile_overview.dart';
import 'stitch_ui.dart';
import 'device_services.dart';
import 'firebase_device_gateway.dart';
import 'notification_settings_page.dart';
import 'nutrition_page.dart';
import 'progress_page.dart';
import 'coaching_page.dart';
import 'trainer_feedback_page.dart';
import 'sessions_page.dart';
import 'habits_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    JBFitnessApp(
      deviceServices: DeviceServices(
        gateway: FirebaseDeviceGateway(),
        preferences: SecurePushPreferenceStore(),
      ),
    ),
  );
}

class JBFitnessApp extends StatefulWidget {
  final AccountController? account;
  final bool preview;
  final IntroStore? introStore;
  final DeviceServices? deviceServices;
  const JBFitnessApp({
    super.key,
    this.account,
    this.preview = false,
    this.introStore,
    this.deviceServices,
  });
  @override
  State<JBFitnessApp> createState() => _JBFitnessAppState();
}

class _JBFitnessAppState extends State<JBFitnessApp> {
  late final AccountController account;
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _userId;
  bool _introFinished = false;
  bool _introReady = false;
  late final IntroStore _introStore;
  late final DeviceServices devices;
  StreamSubscription<DeviceNotice>? _deviceEvents;
  String? _pendingDestination;

  Future<void> _restoreIntro() async {
    var seen = false;
    try {
      seen = await _introStore.hasCompleted();
    } catch (_) {
      // An unavailable nonessential preference must not block account access.
    }
    if (mounted) {
      setState(() {
        _introFinished = seen;
        _introReady = true;
      });
      _flushNotification();
    }
  }

  void _finishIntro() {
    setState(() => _introFinished = true);
    _flushNotification();
    unawaited(_rememberIntro());
  }

  Future<void> _rememberIntro() async {
    try {
      await _introStore.complete();
    } catch (_) {
      // Continue to login even if the device cannot persist this preference.
    }
  }

  void _openDeviceSettings() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationSettingsPage(services: devices),
      ),
    );
  }

  void _onDeviceNotice(DeviceNotice notice) {
    if (!mounted || account.user == null) return;
    if (notice.opened) {
      _pendingDestination = notice.destination;
      _flushNotification();
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You have a new JB Fitness update.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              _pendingDestination = notice.destination;
              _flushNotification();
            },
          ),
        ),
      );
    }
  }

  void _flushNotification() {
    if (!mounted ||
        !_introFinished ||
        account.user == null ||
        account.profile == null ||
        _pendingDestination == null) {
      return;
    }
    final destination = _pendingDestination!;
    final owner = _userId;
    _pendingDestination = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || account.user == null || account.user?['id'] != owner) {
        return;
      }
      final page = switch (destination) {
        'workouts' => WorkoutsPage(account: account),
        'nutrition' => NutritionPage(account: account),
        'progress' => ProgressPage(account: account),
        'coaching' => CoachingPage(account: account),
        'feedback' => TrainerFeedbackPage(account: account),
        'sessions' => SessionsPage(account: account),
        'plans' => Scaffold(
          appBar: AppBar(title: const Text('Membership')),
          body: MembershipPage(account: account),
        ),
        'habits' => Scaffold(
          appBar: AppBar(title: const Text('Habits')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HabitsPanel(account: account, compact: false),
          ),
        ),
        _ => NotificationSettingsPage(services: devices),
      };
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    });
  }

  void _identityChanged() {
    final next = account.user?['id'] as String?;
    if (next == _userId) {
      _flushNotification();
      return;
    }
    _userId = next;
    _pendingDestination = null;
    unawaited(devices.bindAccount(next));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && account.user?['id'] == next) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    registerFitnessFontLicenses();
    _introStore = widget.introStore ?? SecureIntroStore();
    unawaited(_restoreIntro());
    account =
        widget.account ??
        AccountController(api: AccountApi(), store: SecureSessionStore());
    devices = widget.deviceServices ?? DeviceServices.unavailable;
    _deviceEvents = devices.events.listen(_onDeviceNotice);
    unawaited(devices.bindAccount(account.user?['id'] as String?));
    if (widget.deviceServices != null) unawaited(devices.start());
    _userId = account.user?['id'] as String?;
    account.addListener(_identityChanged);
    if (widget.account == null) {
      unawaited(account.restore());
    }
  }

  @override
  void dispose() {
    _deviceEvents?.cancel();
    if (widget.deviceServices != null) devices.dispose();
    account.removeListener(_identityChanged);
    if (widget.account == null) {
      account.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DeviceServicesScope(
    services: devices,
    onOpenSettings: _openDeviceSettings,
    child: MaterialApp(
      title: 'JB Fitness',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: fitnessTheme(),
      themeMode: ThemeMode.light,
      builder: widget.preview
          ? (context, child) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle.dark.copyWith(
                    systemNavigationBarColor: canvas,
                    systemNavigationBarIconBrightness: Brightness.dark,
                  ),
                  child: Material(
                    color: softRed,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'OFFLINE DEMO · Sample data · Resets on restart',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: brandRed, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            )
          : null,
      home: ListenableBuilder(
        listenable: account,
        builder: (context, _) {
          if (!_introReady) {
            return const StitchStatusPage(
              title: 'Loading your fitness space…',
              description: 'Getting the app ready.',
              loading: true,
            );
          }
          if (!_introFinished) {
            return FitnessIntro(onFinished: _finishIntro);
          }
          if (account.booting) {
            return const StitchStatusPage(
              title: 'Connecting to your account…',
              description: 'The first connection may take up to a minute.',
              loading: true,
            );
          }
          if (account.bootError != null) {
            return StitchStatusPage(
              title: 'Let’s reconnect.',
              description: account.bootError!,
              actions: [
                FilledButton(
                  onPressed: account.restore,
                  child: const Text('Retry connection'),
                ),
                TextButton(
                  onPressed: () => account.signOut(localOnly: true),
                  child: const Text('Sign out on this device'),
                ),
              ],
            );
          }
          if (account.user == null) {
            return SignInPage(account: account);
          }
          if (account.profile == null) {
            return FitnessProfilePage(account: account, onboarding: true);
          }
          return AppShell(key: ValueKey(account.user!['id']), account: account);
        },
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  final AccountController account;
  const AppShell({super.key, required this.account});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  final visited = <int>{0};
  void _select(int value) {
    setState(() {
      index = value;
      visited.add(value);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: index,
        children: [
          dashboard.TodayPage(
            account: widget.account,
            onOpenWorkouts: () => _select(1),
            onOpenProfile: () => _select(3),
            onOpenPlans: () => _select(2),
          ),
          if (visited.contains(1))
            WorkoutsPage(account: widget.account)
          else
            const SizedBox.shrink(),
          if (visited.contains(2))
            MembershipPage(account: widget.account)
          else
            const SizedBox.shrink(),
          if (visited.contains(3))
            ProfileOverview(
              account: widget.account,
              onOpenPlans: () => _select(2),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: _select,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today_rounded),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.fitness_center),
          label: 'Workouts',
        ),
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment_rounded),
          label: 'Plans',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    ),
  );
}
