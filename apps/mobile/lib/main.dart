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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JBFitnessApp());
}

class JBFitnessApp extends StatefulWidget {
  final AccountController? account;
  final bool preview;
  final IntroStore? introStore;
  const JBFitnessApp({
    super.key,
    this.account,
    this.preview = false,
    this.introStore,
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
    }
  }

  void _finishIntro() {
    setState(() => _introFinished = true);
    unawaited(_rememberIntro());
  }

  Future<void> _rememberIntro() async {
    try {
      await _introStore.complete();
    } catch (_) {
      // Continue to login even if the device cannot persist this preference.
    }
  }

  void _identityChanged() {
    final next = account.user?['id'] as String?;
    if (next == _userId) {
      return;
    }
    _userId = next;
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
    _userId = account.user?['id'] as String?;
    account.addListener(_identityChanged);
    if (widget.account == null) {
      unawaited(account.restore());
    }
  }

  @override
  void dispose() {
    account.removeListener(_identityChanged);
    if (widget.account == null) {
      account.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
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
