import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'stitch_ui.dart';

class FitnessIntro extends StatefulWidget {
  final VoidCallback onFinished;
  const FitnessIntro({super.key, required this.onFinished});

  @override
  State<FitnessIntro> createState() => _FitnessIntroState();
}

class _Feature {
  final String category, title, description, semantics;
  const _Feature(this.category, this.title, this.description, this.semantics);
}

const _features = [
  _Feature(
    'TODAY · YOUR TRAINING',
    'Your plan, ready\nwhen you are.',
    'See today’s session, exercise instructions and demonstration videos together. Your routine uses your goals, schedule and available equipment.',
    'Example Today dashboard with a weekly date strip, workout card and quick actions.',
  ),
  _Feature(
    'SNAP FOOD · PHOTO OR TEXT',
    'Snap it. Review.\nLog it.',
    'Share a food photo or type a dish and portion. Review estimated calories and nutrients, correct the serving, then choose whether to save it.',
    'Example meal estimate with a scan preview, calorie ring and editable portion review.',
  ),
  _Feature(
    'HABITS · BODY PROGRESS',
    'Small check-ins.\nA clearer picture.',
    'Use a monthly habit grid, record measurements and compare progress photos by date. Review your own history over time.',
    'Example monthly habit grid and check-in history. Illustrative records, not promised results.',
  ),
  _Feature(
    'AI COACH · TRAINER SUPPORT',
    'Good guidance,\nall in one place.',
    'Ask general fitness questions, read trainer feedback and manage your membership in the app. Live sessions depend on your plan and provider setup.',
    'Example AI chat, trainer feedback and plan-dependent coaching access.',
  ),
];

class _FitnessIntroState extends State<FitnessIntro>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _motion;
  int _page = 0;
  bool _started = false, _reduceMotion = false, _finished = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!_started || reduced != _reduceMotion) {
      _started = true;
      _reduceMotion = reduced;
      _play();
    }
  }

  void _play() {
    if (_reduceMotion) {
      _motion.stop();
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  void _go(int page) {
    if (_reduceMotion) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _motion.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _pages.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: canvas,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(child: StitchIdentity('Explore the app')),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _finish,
                        child: const Text(
                          'Skip intro',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _features.length,
                onPageChanged: (page) {
                  setState(() => _page = page);
                  _play();
                },
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  return LayoutBuilder(
                    builder: (context, bounds) => SingleChildScrollView(
                      key: PageStorageKey('feature-$index'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: math.min(
                              320,
                              math.max(300, bounds.maxHeight * .54),
                            ),
                            child: Semantics(
                              image: true,
                              label: feature.semantics,
                              child: ExcludeSemantics(
                                child: AnimatedBuilder(
                                  animation: _motion,
                                  builder: (context, _) => _FeatureScene(
                                    index: index,
                                    progress: index == _page
                                        ? _motion.value
                                        : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '${(index + 1).toString().padLeft(2, '0')} / ${feature.category}',
                            style: const TextStyle(
                              color: brandRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            feature.title,
                            style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 30,
                              height: 1.08,
                              letterSpacing: -.7,
                              color: ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            feature.description,
                            style: const TextStyle(
                              color: muted,
                              fontSize: 14,
                              height: 1.65,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: 'Feature ${_page + 1} of ${_features.length}',
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                _features.length,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(right: 7),
                                  child: AnimatedContainer(
                                    duration: Duration(
                                      milliseconds: _reduceMotion ? 0 : 200,
                                    ),
                                    height: 5,
                                    width: index == _page ? 28 : 7,
                                    decoration: BoxDecoration(
                                      color: index == _page ? brandRed : border,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_page > 0)
                        TextButton(
                          onPressed: () => _go(_page - 1),
                          child: const Text('Back'),
                        ),
                      Text(
                        '${_page + 1} / ${_features.length}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _page == _features.length - 1
                          ? _finish
                          : () => _go(_page + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _page == _features.length - 1
                                    ? 'Continue to login'
                                    : 'Next',
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_page != _features.length - 1)
                    TextButton(
                      onPressed: _finish,
                      child: const Text(
                        'Already have an account? Log in',
                        style: TextStyle(fontSize: 11),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 12),
                      child: Text(
                        'Create an account or sign in to start.',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FeatureScene extends StatelessWidget {
  final int index;
  final double progress;
  const _FeatureScene({required this.index, required this.progress});

  double stage(double start, [double duration = .28]) => Curves.easeOutCubic
      .transform(((progress - start) / duration).clamp(0.0, 1.0));

  Widget reveal(double start, Widget child) {
    final value = stage(start);
    return Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 18),
        child: Transform.scale(scale: .96 + value * .04, child: child),
      ),
    );
  }

  Widget label(String text, {Color color = muted, double size = 9}) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Inter',
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w500,
    ),
  );
  Widget title(String text, {double size = 14, Color color = ink}) => Text(
    text,
    maxLines: 2,
    style: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w700,
    ),
  );
  Widget card(Widget child, {Color color = Colors.white}) =>
      StitchCard(color: color, padding: const EdgeInsets.all(14), child: child);
  Widget icon(IconData data, {bool red = false}) => Container(
    width: 30,
    height: 32,
    decoration: BoxDecoration(
      color: red ? softRed : stitchBlue,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(data, size: 17, color: red ? brandRed : ink),
  );

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 340,
        height: 340,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1,
          maxScaleFactor: 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 12,
                      color: brandRed,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: label(
                        'FEATURE PREVIEW · EXAMPLE DATA',
                        color: brandRed,
                        size: 8,
                      ),
                    ),
                    label('0${index + 1}', color: brandRed),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: switch (index) {
                    0 => _workout(),
                    1 => _nutrition(),
                    2 => _habits(),
                    _ => _coaching(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _workout() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      reveal(
        0,
        card(
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label('TODAY · MON, NOV 12', color: brandRed, size: 8),
                    const SizedBox(height: 4),
                    title('Ready to train?', size: 17),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: stitchBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: brandRed,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      reveal(
        .12,
        card(
          Row(
            children: List.generate(
              7,
              (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 6 ? 0 : 4),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: i == 0 ? brandRed : neutralSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      label(
                        ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                        color: i == 0 ? Colors.white : muted,
                        size: 8,
                      ),
                      const SizedBox(height: 3),
                      title(
                        '${12 + i}',
                        size: 11,
                        color: i == 0 ? Colors.white : ink,
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        i == 0 || i == 2 || i == 5
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 4,
                        color: i == 0 ? Colors.white : brandRed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: reveal(
          .26,
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon(Icons.fitness_center_rounded, red: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label('TODAY’S WORKOUT', color: brandRed, size: 8),
                          const SizedBox(height: 3),
                          title('Full-body session', size: 15),
                        ],
                      ),
                    ),
                    label('30 min', color: muted, size: 8),
                  ],
                ),
                const SizedBox(height: 7),
                for (final row in [
                  ('Bodyweight squat', '3 × 12'),
                  ('Incline push-up', '3 × 8'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: stitchBlue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 15,
                            color: stage(.45) > .5 ? brandRed : ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: label(row.$1, color: ink, size: 9)),
                        label(row.$2, size: 8),
                      ],
                    ),
                  ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    label('Progress', size: 8),
                    const Spacer(),
                    label(
                      '${(stage(.4, .35) * 100).round()}% started',
                      color: ink,
                      size: 8,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: stage(.42, .35),
                    color: brandRed,
                    backgroundColor: stitchBlue,
                    minHeight: 4,
                  ),
                ),
                const Spacer(),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: brandRed,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      label('START WORKOUT', color: Colors.white, size: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      reveal(
        .72,
        Row(
          children: [
            Expanded(
              child: _quickTile(Icons.camera_alt_outlined, 'Snap food', true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickTile(Icons.checklist_rounded, 'Daily habits', false),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _quickTile(IconData data, String text, bool red) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(data, size: 14, color: red ? brandRed : ink),
        const SizedBox(width: 5),
        Flexible(child: label(text, color: ink, size: 8)),
      ],
    ),
  );

  Widget _nutrition() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      reveal(
        0,
        card(
          Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: stitchBlue,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.rice_bowl_outlined,
                        color: ink,
                        size: 36,
                      ),
                    ),
                    Positioned(
                      top: 8 + stage(0, .45) * 54,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: brandRed,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Container(
                        width: 23,
                        height: 23,
                        decoration: const BoxDecoration(
                          color: brandRed,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StitchPill('PHOTO OR TEXT'),
                    const SizedBox(height: 8),
                    title('Rice & dal', size: 18),
                    const SizedBox(height: 4),
                    label('250 g · sample portion'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: reveal(
          .3,
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: label(
                        'ESTIMATED NUTRIENTS',
                        color: brandRed,
                        size: 8,
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: muted, size: 13),
                    const SizedBox(width: 3),
                    label('Review', size: 8),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 83,
                        height: 83,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: stage(.3, .45) * .7,
                                color: brandRed,
                                backgroundColor: stitchBlue,
                                strokeWidth: 6,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: FittedBox(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    title(
                                      '≈ ${(stage(.3, .4) * 420 / 10).round() * 10}',
                                      size: 23,
                                    ),
                                    label('KCAL · ESTIMATE', size: 7),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final macro in [
                              ('Protein', '14 g'),
                              ('Carbs', '68 g'),
                              ('Fats', '10 g'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: label(macro.$1, color: ink),
                                        ),
                                        label(macro.$2),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                      value: stage(.4, .4) * .55,
                                      color: brandRed,
                                      backgroundColor: stitchBlue,
                                      minHeight: 3,
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
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      reveal(
        .72,
        Center(
          child: label(
            'Review portions and ingredients before saving',
            color: brandRed,
            size: 9,
          ),
        ),
      ),
    ],
  );

  Widget _habits() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 6,
        child: reveal(
          0,
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: title('Your habits, at a glance', size: 15),
                    ),
                    label('4 / 7 DAYS', color: brandRed, size: 8),
                  ],
                ),
                const SizedBox(height: 4),
                label('NOVEMBER · WEEK 1', size: 8),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(width: 68, child: label('DAILY HABITS', size: 7)),
                    ...List.generate(
                      7,
                      (i) => Expanded(
                        child: Center(child: label('${i + 1}', size: 8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                for (final row in [
                  ('Workout', [true, true, false, true, false, false, false]),
                  ('Walk', [true, false, true, true, false, false, false]),
                  ('Read', [false, true, true, false, true, false, false]),
                ]) ...[
                  Container(height: 1, color: border),
                  SizedBox(
                    height: 31,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 68,
                          child: label(row.$1, color: ink, size: 8),
                        ),
                        ...List.generate(7, (i) {
                          final checked =
                              row.$2[i] && stage(.12 + i * .045, .22) > .5;
                          return Expanded(
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 17,
                                height: 17,
                                decoration: BoxDecoration(
                                  color: checked ? brandRed : stitchBlue,
                                  border: Border.all(
                                    color: checked ? brandRed : border,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: checked
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 12,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 9),
      Expanded(
        flex: 4,
        child: reveal(
          .3,
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: label(
                        'BODY PROGRESS · EXAMPLE',
                        color: brandRed,
                        size: 8,
                      ),
                    ),
                    const Icon(
                      Icons.photo_library_outlined,
                      color: ink,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    label('Compare dates', size: 8),
                  ],
                ),
                const SizedBox(height: 9),
                Expanded(
                  child: CustomPaint(
                    painter: _CheckInPainter(progress: stage(.35, .5)),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    label('WEEK 1', size: 8),
                    label('WEEK 6', size: 8),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _coaching() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: reveal(
          0,
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon(Icons.auto_awesome_outlined, red: true),
                    const SizedBox(width: 9),
                    Expanded(child: title('Your coaching space')),
                  ],
                ),
                const SizedBox(height: 12),
                reveal(
                  .12,
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: stitchBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: label(
                        'Can I train at home?',
                        color: ink,
                        size: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: reveal(
                    .35,
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: neutralSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 250,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              label(
                                'FITNESS ASSISTANT',
                                color: brandRed,
                                size: 8,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Let’s work with your space, equipment and training days.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      reveal(
        .68,
        card(
          Row(
            children: [
              icon(Icons.support_agent_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title('Trainer feedback & memberships', size: 11),
                    const SizedBox(height: 4),
                    label('Live sessions depend on your plan', size: 9),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: brandRed,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _CheckInPainter extends CustomPainter {
  final double progress;
  const _CheckInPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    const values = [.42, .7, .54, .83, .62, .9];
    final gap = size.width * .035;
    final barWidth = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final reveal = (progress * values.length - i).clamp(0.0, 1.0);
      final height = size.height * values[i] * reveal;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * (barWidth + gap),
          size.height - height,
          barWidth,
          height,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i == values.length - 1 ? brandRed : stitchBlue,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckInPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
