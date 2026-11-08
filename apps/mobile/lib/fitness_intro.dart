import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// A short, skippable launch sequence. Account restoration runs underneath it.
class FitnessIntro extends StatefulWidget {
  final VoidCallback onFinished;
  const FitnessIntro({super.key, required this.onFinished});

  @override
  State<FitnessIntro> createState() => _FitnessIntroState();
}

class _FitnessIntroState extends State<FitnessIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _started = false;
  bool _finished = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _motion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2800),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      if (_reduceMotion) {
        _motion.duration = const Duration(milliseconds: 300);
      }
      _motion.forward();
    } else if (_reduceMotion && _motion.isAnimating) {
      // Stop movement immediately if the accessibility setting changes.
      _motion.animateTo(1, duration: const Duration(milliseconds: 100));
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _motion.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
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
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: brandRed,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: FittedBox(
                                  child: Text(
                                    'JB',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Flexible(
                              child: Text(
                                'JB FITNESS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: .4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: _finish,
                          child: const Text('Skip intro'),
                        ),
                      ],
                    ),
                    SizedBox(height: bounds.maxHeight > 700 ? 35 : 10),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: AspectRatio(
                          aspectRatio: 1.08,
                          child: Semantics(
                            label:
                                'Athlete performing a controlled barbell squat',
                            image: true,
                            child: ExcludeSemantics(
                              child: AnimatedBuilder(
                                animation: _motion,
                                builder: (context, _) => CustomPaint(
                                  painter: _AthletePainter(
                                    progress: _reduceMotion ? 0 : _motion.value,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Container(width: 20, height: 3, color: brandRed),
                        const SizedBox(width: 9),
                        const Flexible(
                          child: Text(
                            'YOUR NEXT CHAPTER',
                            style: TextStyle(
                              color: brandRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Every rep.\nA new beginning.',
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 38,
                        letterSpacing: -1.6,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Build your strength. Find your rhythm.\nMake progress that feels like you.',
                      style: TextStyle(color: muted, fontSize: 13, height: 1.7),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _finish,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(child: Text("Let's move")),
                              SizedBox(width: 12),
                              Icon(Icons.arrow_forward_rounded, size: 19),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _motion,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _motion.value,
                          minHeight: 3,
                          backgroundColor: border,
                          color: brandRed,
                          semanticsLabel: 'Intro duration',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'TRAIN. TRACK. TRANSFORM.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Original vector artwork, animated from joint positions rather than video.
class _AthletePainter extends CustomPainter {
  final double progress;
  const _AthletePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 340, size.height / 315);
    final squat = (1 - math.cos(progress * math.pi * 4)) / 2;
    final drop = squat * 35;
    final shift = squat * 12;
    final center = const Offset(170, 146);
    canvas.drawCircle(center, 130, Paint()..color = softRed);
    canvas.drawCircle(
      center,
      110,
      Paint()
        ..color = brandRed.withValues(alpha: .12)
        ..style = PaintingStyle.stroke,
    );
    final arc = Paint()
      ..color = brandRed
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 130),
      -1.5,
      .6,
      false,
      arc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 130),
      1.65,
      .4,
      false,
      arc,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(175, 287), width: 140, height: 10),
      Paint()..color = ink.withValues(alpha: .07),
    );
    final limb = Paint()
      ..color = ink
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    void jointPath(List<Offset> points, {Color? color, double? width}) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color ?? limb.color
          ..strokeWidth = width ?? limb.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    final hip = Offset(173 - shift, 199 + drop);
    jointPath([
      hip,
      Offset(201 + squat * 15, 237 + drop * .18),
      const Offset(190, 279),
    ]);
    jointPath([
      Offset(hip.dx - 8, hip.dy),
      Offset(142 - squat * 18, 238 + drop * .18),
      const Offset(147, 279),
    ], color: const Color(0xFF414141));
    jointPath([const Offset(138, 280), const Offset(155, 280)], width: 12);
    jointPath([const Offset(184, 280), const Offset(203, 280)], width: 12);
    final shoulder = Offset(169 + shift * .3, 122 + drop);
    final shirt = Path()
      ..moveTo(shoulder.dx - 21, shoulder.dy - 4)
      ..quadraticBezierTo(
        shoulder.dx,
        shoulder.dy - 12,
        shoulder.dx + 23,
        shoulder.dy,
      )
      ..lineTo(hip.dx + 16, hip.dy + 1)
      ..lineTo(hip.dx - 18, hip.dy + 1)
      ..close();
    canvas.drawPath(shirt, Paint()..color = brandRed);
    jointPath(
      [
        Offset(shoulder.dx - 16, shoulder.dy + 4),
        Offset(137, 153 + drop),
        Offset(119, 113 + drop),
      ],
      color: ink,
      width: 11,
    );
    jointPath(
      [
        Offset(shoulder.dx + 18, shoulder.dy + 4),
        Offset(204, 151 + drop),
        Offset(221, 113 + drop),
      ],
      color: ink,
      width: 11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(shoulder.dx - 5, 104 + drop, 13, 22),
        const Radius.circular(6),
      ),
      Paint()..color = ink,
    );
    canvas.drawCircle(
      Offset(shoulder.dx + 1, 88 + drop),
      18,
      Paint()..color = ink,
    );
    // Barbell follows the shoulders throughout the squat.
    jointPath(
      [Offset(74, 113 + drop), Offset(266, 113 + drop)],
      width: 6,
      color: const Color(0xFF414141),
    );
    for (final x in [87.0, 239.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 88 + drop, 14, 50),
          const Radius.circular(4),
        ),
        Paint()..color = ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 9, 97 + drop, 7, 32),
          const Radius.circular(3),
        ),
        Paint()..color = brandRed,
      );
    }
    canvas.drawCircle(const Offset(58, 82), 4, Paint()..color = brandRed);
    final plus = Paint()
      ..color = brandRed
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(278, 215), const Offset(292, 215), plus);
    canvas.drawLine(const Offset(285, 208), const Offset(285, 222), plus);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AthletePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
