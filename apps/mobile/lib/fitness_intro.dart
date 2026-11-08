import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

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
    'TRAIN WITH A PLAN',
    'A routine that\nfits your life.',
    'Start with your goals, training days and equipment. Follow a personal routine with clear sets, reps and exercise demonstrations.',
    'Example workout: training preferences become a three-exercise routine.',
  ),
  _Feature(
    'MAKE SENSE OF YOUR MEALS',
    'Your plate.\nA clearer picture.',
    'Share a food photo or describe your meal. Review estimated calories and nutrients, adjust the portions, then save your food log.',
    'Example meal: rice and dal with an estimate of 420 calories. Portions and estimates must be reviewed.',
  ),
  _Feature(
    'SEE THE SMALL WINS',
    'Build habits.\nWatch your progress.',
    'Check off daily habits, record your measurements and compare progress photos. See your journey over weeks, not just one day.',
    'Example habit checklist and weight trend across six weeks. This is illustrative progress, not a promised result.',
  ),
  _Feature(
    'KEEP YOUR SUPPORT CLOSE',
    'Guidance, when\nyou need direction.',
    'Ask fitness questions, read your trainer’s feedback and manage your membership in one place. Live coaching sessions depend on your plan.',
    'Example coaching conversation, trainer feedback and membership tools.',
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
      duration: const Duration(seconds: 4),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brandRed,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const FittedBox(
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: Text(
                          'JB',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            fontSize: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'JB FITNESS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                  Flexible(
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text(
                        'Skip intro',
                        style: TextStyle(fontSize: 12),
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
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
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
                              fontSize: 33,
                              height: 1.08,
                              letterSpacing: -1.3,
                              color: ink,
                              fontWeight: FontWeight.w900,
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
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
  double stage(double from, [double length = .22]) => Curves.easeOutCubic
      .transform(((progress - from) / length).clamp(0.0, 1.0));

  Widget reveal(double from, Widget child) {
    final t = stage(from);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.contain,
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: 340, height: 340),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: softRed,
            borderRadius: BorderRadius.circular(26),
          ),
          padding: const EdgeInsets.all(18),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            maxScaleFactor: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 12,
                      color: brandRed,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'FEATURE PREVIEW · EXAMPLE DATA',
                      style: TextStyle(
                        color: brandRed,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: switch (index) {
                    0 => _workout(),
                    1 => _nutrition(),
                    2 => _progress(),
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

  Widget card(
    Widget child, {
    bool dark = false,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) => Container(
    decoration: BoxDecoration(
      color: dark ? ink : Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: dark ? ink : border),
    ),
    padding: padding,
    child: child,
  );

  Widget label(String value, {Color color = muted}) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color,
      fontSize: 8,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
    ),
  );
  Widget caption(String value, {Color color = ink, double size = 12}) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700),
  );

  Widget _workout() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      reveal(
        0,
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('YOUR GOAL → YOUR ROUTINE', color: accentRed),
              const SizedBox(height: 7),
              caption(
                'Build strength. Three days a week.',
                color: Colors.white,
                size: 12,
              ),
            ],
          ),
          dark: true,
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: caption('Monday · Full body')),
                  label('30 MIN'),
                ],
              ),
              const SizedBox(height: 10),
              for (final row in [
                (Icons.fitness_center, 'Bodyweight squat', '3 sets × 12 reps'),
                (Icons.sports_gymnastics, 'Incline push-up', '3 sets × 8 reps'),
                (
                  Icons.directions_walk,
                  'March in place',
                  '3 sets × 30 seconds',
                ),
              ])
                Expanded(
                  child: reveal(
                    .14 +
                        [
                              'Bodyweight squat',
                              'Incline push-up',
                              'March in place',
                            ].indexOf(row.$2) *
                            .18,
                    Row(
                      children: [
                        Container(
                          width: 29,
                          height: 29,
                          decoration: BoxDecoration(
                            color: softRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(row.$1, size: 15, color: brandRed),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              caption(row.$2, size: 10),
                              const SizedBox(height: 3),
                              Text(
                                row.$3,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: brandRed,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _nutrition() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: card(
          Row(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: softRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: border, width: 5),
                      ),
                      child: const Icon(
                        Icons.rice_bowl_rounded,
                        size: 46,
                        color: brandRed,
                      ),
                    ),
                    if (progress < .45)
                      Positioned(
                        top: 10 + stage(0, .45) * 74,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          color: brandRed.withValues(alpha: .6),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    label('PHOTO OR TEXT'),
                    const SizedBox(height: 8),
                    caption('Rice & dal', size: 16),
                    const SizedBox(height: 6),
                    const Text(
                      '250 g · example portion',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      reveal(
        .32,
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label('ESTIMATED NUTRITION', color: accentRed),
                  ),
                  caption(
                    '≈ ${((stage(.32, .35) * 420) / 10).round() * 10} kcal',
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final macro in [
                    ('PROTEIN', '14 g'),
                    ('CARBS', '68 g'),
                    ('FAT', '10 g'),
                  ])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label(macro.$1, color: onDarkSubtle),
                        const SizedBox(height: 6),
                        caption(macro.$2, color: Colors.white),
                      ],
                    ),
                ],
              ),
            ],
          ),
          dark: true,
        ),
      ),
      const SizedBox(height: 10),
      reveal(
        .7,
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune_rounded, color: brandRed, size: 13),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Review portions before saving',
                style: TextStyle(
                  color: brandRed,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _progress() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: caption('Small wins, every day.')),
                label('${(stage(.1, .65) * 5).round()} / 7'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final checked = stage(.12 + i * .075, .12) > .5 && i < 5;
                return Column(
                  children: [
                    Text(
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                      style: const TextStyle(fontSize: 8, color: muted),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: checked ? brandRed : neutralSurface,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: checked
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 15,
                            )
                          : null,
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label('WEIGHT TREND · EXAMPLE', color: onDarkSubtle),
                  ),
                  caption('74.8 kg', color: Colors.white),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CustomPaint(
                  painter: _TrendPainter(progress: stage(.32, .65)),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  label('WEEK 1', color: onDarkSubtle),
                  label('WEEK 6', color: onDarkSubtle),
                ],
              ),
            ],
          ),
          dark: true,
        ),
      ),
    ],
  );

  Widget _coaching() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: softRed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: brandRed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  caption('Your coaching space'),
                ],
              ),
              const SizedBox(height: 14),
              reveal(
                .06,
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: brandRed,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Text(
                      'Can I train at home?',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: reveal(
                  .28,
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: neutralSurface,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        label('FITNESS ASSISTANT'),
                        const SizedBox(height: 6),
                        const Text(
                          'Let’s work with your space, available equipment and training days.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      reveal(
        .62,
        card(
          Row(
            children: [
              const Icon(
                Icons.support_agent_rounded,
                size: 23,
                color: accentRed,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caption(
                      'Trainer feedback & memberships',
                      color: Colors.white,
                      size: 10,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Live sessions depend on your plan',
                      style: TextStyle(fontSize: 9, color: onDarkMuted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
          dark: true,
        ),
      ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  final double progress;
  const _TrendPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final points = [
      Offset(0, size.height * .12),
      Offset(size.width * .2, size.height * .3),
      Offset(size.width * .4, size.height * .23),
      Offset(size.width * .6, size.height * .55),
      Offset(size.width * .8, size.height * .62),
      Offset(size.width, size.height * .85),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = accentRed
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    if (progress > 0) {
      final position = metric
          .getTangentForOffset(metric.length * progress)
          ?.position;
      if (position != null) {
        canvas.drawCircle(position, 4, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
