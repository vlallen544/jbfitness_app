import 'package:flutter/material.dart';

import 'app_theme.dart';

const stitchBlue = Color(0xFFE5EEFF);
const stitchShadow = Color(0x0C0B1C30);

class StitchBrandHeader extends StatelessWidget {
  final String section;
  final VoidCallback? onProfile, onRefresh;
  const StitchBrandHeader(
    this.section, {
    super.key,
    this.onProfile,
    this.onRefresh,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: brandRed,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: FittedBox(
              child: Text(
                'JB',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'JB FITNESS',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
              Text(
                section,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        if (onRefresh != null)
          IconButton(
            tooltip: 'Refresh $section',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notifications are not available yet.'),
            ),
          ),
          icon: const Icon(Icons.notifications_none_rounded, size: 23),
        ),
        if (onProfile != null)
          IconButton.filled(
            tooltip: 'Open profile',
            style: IconButton.styleFrom(
              backgroundColor: brandRed,
              foregroundColor: Colors.white,
            ),
            onPressed: onProfile,
            icon: const Icon(Icons.person_outline_rounded, size: 21),
          ),
      ],
    ),
  );
}

class StitchCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const StitchCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border.withValues(alpha: .7)),
      boxShadow: const [
        BoxShadow(color: stitchShadow, blurRadius: 12, offset: Offset(0, 3)),
      ],
    ),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class StitchPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool red;
  const StitchPill(this.label, {super.key, this.icon, this.red = true});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: red ? softRed : stitchBlue,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: red ? brandRed : ink),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: red ? brandRed : ink,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class StitchActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool red;
  const StitchActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.red = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 40,
              decoration: BoxDecoration(
                color: red ? softRed : stitchBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: red ? brandRed : ink, size: 23),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: muted),
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

class StitchFuelCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final VoidCallback? onOpen;
  const StitchFuelCard({super.key, this.data, this.onOpen});
  num? _value(String key) => (data?['totals']?[key]?['known']) as num?;
  @override
  Widget build(BuildContext context) {
    final target = data?['targets']?['nutrients'] as Map<String, dynamic>?;
    final calories = _value('calories');
    final energyTarget = target?['calories'] as num?;
    final entries = data?['entries'] as List? ?? [];
    final meals = entries.map((e) => e['meal']).toSet().length;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Fuel',
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data == null
                          ? 'Your food diary at a glance'
                          : '$meals ${meals == 1 ? 'meal' : 'meals'} logged today',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              if (energyTarget != null)
                Flexible(
                  child: StitchPill(
                    'Goal: ${energyTarget.round()} kcal',
                    red: false,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value:
                            calories != null &&
                                energyTarget != null &&
                                energyTarget > 0
                            ? (calories / energyTarget).clamp(0, 1).toDouble()
                            : 0,
                        strokeWidth: 7,
                        backgroundColor: stitchBlue,
                        color: brandRed,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          children: [
                            Text(
                              calories == null ? '—' : '${calories.round()}',
                              style: const TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              'KCAL IN',
                              style: TextStyle(fontSize: 8, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    for (final item in [
                      ('protein', 'Protein'),
                      ('carbs', 'Carbs'),
                      ('fat', 'Fats'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                                Text(
                                  _value(item.$1) == null
                                      ? '—'
                                      : '${_value(item.$1)!.round()}${target?[item.$1] == null ? '' : '/${(target![item.$1] as num).round()}'}g',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value:
                                    _value(item.$1) != null &&
                                        target?[item.$1] is num &&
                                        (target![item.$1] as num) > 0
                                    ? (_value(item.$1)! /
                                              (target[item.$1] as num))
                                          .clamp(0, 1)
                                          .toDouble()
                                    : 0,
                                minHeight: 4,
                                backgroundColor: stitchBlue,
                                color: brandRed,
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
          const SizedBox(height: 12),
          if (data != null &&
              data!['totals']?['calories']?['complete'] == false)
            const Text(
              'Some nutrient values are missing; totals include known values.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          if (target == null)
            const Text(
              'Daily targets have not been set.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          if (onOpen != null) ...[
            const Divider(height: 26),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.restaurant_menu_rounded, size: 17),
              label: const Text('Open food diary'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The temporary identity used on entry screens until final artwork is supplied.
class StitchIdentity extends StatelessWidget {
  final String section;
  const StitchIdentity(this.section, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: brandRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'JB',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            fontSize: 19,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'JB FITNESS',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(section, style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ),
      ),
    ],
  );
}

class StitchPageHeading extends StatelessWidget {
  final String title, eyebrow;
  const StitchPageHeading({
    super.key,
    required this.title,
    required this.eyebrow,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StitchPill(eyebrow.toUpperCase(), icon: Icons.bolt_outlined),
      const SizedBox(height: 12),
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
    ],
  );
}

class StitchStatusPage extends StatelessWidget {
  final String title, description;
  final bool loading;
  final List<Widget> actions;
  const StitchStatusPage({
    super.key,
    required this.title,
    required this.description,
    this.loading = false,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const StitchIdentity('Your fitness companion'),
                const SizedBox(height: 24),
                StitchCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: softRed,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: loading
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const Icon(
                                  Icons.wifi_off_rounded,
                                  color: brandRed,
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      if (actions.isNotEmpty) const SizedBox(height: 20),
                      ...actions,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
