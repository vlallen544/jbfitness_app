import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'fitness_intro.dart';

class SignInPage extends StatefulWidget {
  final AccountController account;
  const SignInPage({super.key, required this.account});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.authenticate(
        email: _email.text,
        password: _password.text,
        displayName: _register ? _name.text : null,
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : 'Could not complete sign-in. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 20),
              const Text(
                'JB FITNESS',
                style: TextStyle(
                  color: brandRed,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.fitness_center_rounded,
                          color: accentRed,
                          size: 30,
                        ),
                        Spacer(),
                        Text(
                          'TRAIN. TRACK. TRANSFORM.',
                          style: TextStyle(
                            color: accentRed,
                            fontSize: 9,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 26),
                    Text(
                      'Built around\nyour better days.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -.8,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Your workouts. Your routine. Your pace.',
                      style: TextStyle(color: onDarkMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text(
                _register ? 'Your next chapter\nstarts here.' : 'Welcome back.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                _register
                    ? 'Create your account, then tell us about your goals and routine.'
                    : 'Sign in to access your saved fitness profile.',
                style: const TextStyle(color: Colors.black54, height: 1.6),
              ),
              const SizedBox(height: 30),
              Form(
                key: _form,
                child: Column(
                  children: [
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 80,
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch((value ?? '').trim())
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _register ? 'Use 12–128 characters.' : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final size = (value ?? '').length;
                        return size > 128 || size < (_register ? 12 : 1)
                            ? (_register
                                  ? 'Use 12–128 characters.'
                                  : 'Enter your password.')
                            : null;
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            _busy
                                ? 'Please wait…'
                                : _register
                                ? 'Create account'
                                : 'Sign in',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _error = null;
                              _form.currentState?.reset();
                            }),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (tourContext) => FitnessIntro(
                            onFinished: () => Navigator.of(tourContext).pop(),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text('Explore app features'),
              ),
              const Text(
                'Development environment • use test details. Email verification and password recovery will be connected before public launch.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FitnessProfilePage extends StatefulWidget {
  final AccountController account;
  final bool onboarding;
  const FitnessProfilePage({
    super.key,
    required this.account,
    this.onboarding = false,
  });
  @override
  State<FitnessProfilePage> createState() => _FitnessProfilePageState();
}

class _FitnessProfilePageState extends State<FitnessProfilePage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _age,
      _height,
      _weight,
      _minutes,
      _equipment,
      _routine,
      _foodNotes,
      _limitations;
  late String _goal, _experience, _diet;
  late Set<int> _days;
  bool _consent = false, _share = false, _shareCoaching = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final p = widget.account.profile ?? <String, dynamic>{};
    _age = TextEditingController(text: p['age']?.toString() ?? '');
    _height = TextEditingController(text: p['heightCm']?.toString() ?? '');
    _weight = TextEditingController(text: p['weightKg']?.toString() ?? '');
    _minutes = TextEditingController(
      text: p['sessionMinutes']?.toString() ?? '',
    );
    _equipment = TextEditingController(
      text: (p['equipment'] as List?)?.join(', ') ?? '',
    );
    _routine = TextEditingController(
      text: p['currentRoutine'] as String? ?? '',
    );
    _limitations = TextEditingController(
      text: p['limitations'] as String? ?? '',
    );
    _foodNotes = TextEditingController(text: p['foodNotes'] as String? ?? '');
    _goal = p['goal'] as String? ?? 'general_fitness';
    _experience = p['experience'] as String? ?? 'beginner';
    _diet = p['dietaryPreference'] as String? ?? 'vegetarian';
    _days = Set<int>.from(p['workoutDays'] as List? ?? []);
    _consent = p['healthDataConsent'] == true;
    _share = p['shareWithTrainer'] == true;
    _shareCoaching = p['shareCoachingWithTrainer'] == true;
  }

  @override
  void dispose() {
    for (final controller in [
      _age,
      _height,
      _weight,
      _minutes,
      _equipment,
      _routine,
      _foodNotes,
      _limitations,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _number(
    TextEditingController controller,
    String label,
    num min,
    num max, {
    bool integer = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(labelText: label, errorMaxLines: 3),
    validator: (value) {
      final parsed = num.tryParse(value ?? '');
      return parsed == null ||
              !parsed.isFinite ||
              parsed < min ||
              parsed > max ||
              (integer && parsed != parsed.roundToDouble())
          ? 'Enter ${integer ? 'a whole number' : 'a number'} from $min to $max.'
          : null;
    },
  );
  Widget _choice(
    String label,
    String current,
    Map<String, String> options,
    void Function(String) update,
  ) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: current,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: _busy
        ? null
        : (value) {
            if (value != null) {
              setState(() => update(value));
            }
          },
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    if (_days.isEmpty || !_consent) {
      setState(
        () => _error = 'Choose at least one workout day and agree to save your fitness information.',
      );
      return;
    }
    final equipment = _equipment.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (equipment.length > 20 || equipment.any((item) => item.length > 80)) {
      setState(
        () =>
            _error = 'Use up to 20 equipment items, each under 80 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.saveProfile({
        'age': num.parse(_age.text).toInt(),
        'heightCm': num.parse(_height.text),
        'weightKg': num.parse(_weight.text),
        'goal': _goal,
        'experience': _experience,
        'dietaryPreference': _diet,
        'equipment': equipment,
        'workoutDays': _days.toList()..sort(),
        'sessionMinutes': num.parse(_minutes.text).toInt(),
        'currentRoutine': _routine.text,
        'limitations': _limitations.text,
        'foodNotes': _foodNotes.text,
        'healthDataConsent': _consent,
        'shareWithTrainer': _share,
        'shareCoachingWithTrainer': _share && _shareCoaching,
      });
      if (mounted && !widget.onboarding) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your fitness profile is saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : 'Could not save your profile. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'JB FITNESS',
                    style: TextStyle(
                      color: brandRed,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            await widget.account.signOut();
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => _error = 'Could not clear the saved session. Try again.',
                              );
                            }
                          }
                        },
                  child: const Text('Sign out'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              widget.onboarding
                  ? 'Let’s build\nyour fitness profile.'
                  : 'Your fitness profile',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    color: accentRed,
                    size: 30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.account.user?['displayName'] as String? ??
                        'Your account',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.account.user?['email'] as String? ?? '',
                    style: const TextStyle(color: onDarkMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'YOUR ROUTINE STARTS WITH YOU',
                    style: TextStyle(
                      color: accentRed,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tell us about your routine. These details will be used for personalized coaching when AI features are connected.',
              style: TextStyle(color: Colors.black54, height: 1.6),
            ),
            const SizedBox(height: 26),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ProfileSectionHeading(
                    Icons.straighten_rounded,
                    'Your starting point',
                    'Keep your basic details up to date.',
                  ),
                  _number(_age, 'Age', 1, 120, integer: true),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 14,
                      runSpacing: 18,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 340
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 14) / 2,
                          child: _number(_height, 'Height (cm)', 50, 275),
                        ),
                        SizedBox(
                          width: constraints.maxWidth < 340
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 14) / 2,
                          child: _number(_weight, 'Weight (kg)', 10, 500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _ProfileSectionHeading(
                    Icons.flag_outlined,
                    'What you’re working towards',
                    'Choose your goal and training experience.',
                  ),
                  _choice('Fitness goal', _goal, {
                    'lose_fat': 'Lose fat',
                    'build_muscle': 'Build muscle',
                    'get_stronger': 'Get stronger',
                    'general_fitness': 'General fitness',
                  }, (v) => _goal = v),
                  const SizedBox(height: 18),
                  _choice('Experience', _experience, {
                    'beginner': 'Beginner',
                    'intermediate': 'Intermediate',
                    'advanced': 'Advanced',
                  }, (v) => _experience = v),
                  const SizedBox(height: 18),
                  const _ProfileSectionHeading(
                    Icons.restaurant_outlined,
                    'Food preferences',
                    'Include any allergies or foods to avoid.',
                  ),
                  _choice('Dietary preference', _diet, {
                    'vegetarian': 'Vegetarian',
                    'vegan': 'Vegan',
                    'non_vegetarian': 'Non-vegetarian',
                    'eggetarian': 'Eggetarian',
                    'other': 'Other',
                  }, (v) => _diet = v),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _foodNotes,
                    enabled: !_busy,
                    maxLength: 2000,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Food allergies or foods to avoid',
                      helperText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _ProfileSectionHeading(
                    Icons.fitness_center_rounded,
                    'Make training fit your life',
                    'Set your equipment, days and session length.',
                  ),
                  TextFormField(
                    controller: _equipment,
                    enabled: !_busy,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Available equipment',
                      helperText: 'Separate items with commas. Leave blank for bodyweight.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Available workout days',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: List.generate(
                      7,
                      (index) => FilterChip(
                        label: Text(
                          [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ][index],
                        ),
                        selected: _days.contains(index),
                        onSelected: _busy
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _days.add(index);
                                } else {
                                  _days.remove(index);
                                }
                              }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _number(
                    _minutes,
                    'Minutes available per session',
                    5,
                    180,
                    integer: true,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _routine,
                    enabled: !_busy,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Your current routine',
                      hintText: 'For example, walking three times a week',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _limitations,
                    enabled: !_busy,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Injuries or exercise limitations (optional)',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _ProfileSectionHeading(
                    Icons.shield_outlined,
                    'Your information, your choice',
                    'Trainer sharing is optional and separate from saving your profile.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _consent = v ?? false),
                    title: const Text(
                      'I agree to save my fitness information for personalized coaching.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _share,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _share = v ?? false),
                    title: const Text(
                      'Allow my assigned trainer to review my fitness profile.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _share && _shareCoaching,
                    onChanged: _busy || !_share
                        ? null
                        : (v) => setState(() => _shareCoaching = v ?? false),
                    title: const Text(
                      'Also allow my assigned trainer to review AI coaching requests and recent tracking summaries.',
                    ),
                    subtitle: const Text(
                      'Progress photos stay private. You can turn sharing off at any time.',
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
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _busy
                            ? 'Saving…'
                            : widget.onboarding
                            ? 'Save and continue'
                            : 'Save profile',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return widget.onboarding
        ? Scaffold(body: SafeArea(child: content))
        : content;
  }
}

class _ProfileSectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _ProfileSectionHeading(this.icon, this.title, this.description);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: brandRed, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
}
