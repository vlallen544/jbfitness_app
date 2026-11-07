import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'meal_estimate_page.dart';
import 'workout_pages.dart' show requestId;

const nutrientLabels = {
  'calories': 'Energy (kcal)',
  'protein': 'Protein (g)',
  'carbs': 'Carbohydrates (g)',
  'fat': 'Fat (g)',
  'fiber': 'Fiber (g)',
  'sugar': 'Sugar (g)',
  'sodium': 'Sodium (mg)',
};
const mealLabels = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'snack': 'Snacks',
};
String nutritionNumber(num value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
String nutritionDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String nutritionError(Object error) => error is ApiFailure
    ? error.message
    : 'Could not connect. Refresh and try again.';

class NutritionPage extends StatefulWidget {
  final AccountController account;
  const NutritionPage({super.key, required this.account});
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data, _pending;
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_saving) {
      _load(_data?['date'] as String?);
    }
  }

  bool get _canEdit =>
      _data?['canEdit'] == true &&
      !_loading &&
      !_saving &&
      _pending == null &&
      _error == null;
  Future<void> _load([String? date]) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/nutrition${date == null ? '' : '?date=$date'}',
      );
      if (data['entries'] is! List || data['totals'] is! Map) {
        throw const ApiFailure(
          0,
          'Nutrition data is unavailable. Please refresh.',
        );
      }
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save([Map<String, dynamic>? action]) async {
    if (_saving) return;
    final next = action ?? _pending;
    if (next == null) return;
    setState(() {
      _pending = next;
      _saving = true;
      _error = null;
    });
    try {
      await widget.account.authenticatedRequest(
        next['path'] as String,
        method: next['method'] as String,
        body: next['body'] as Map<String, dynamic>,
      );
      if (mounted) setState(() => _pending = null);
      await _load(_data?['date'] as String?);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nutrition changes saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          if (error is ApiFailure && error.status > 0 && error.status < 500) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add(String meal) async {
    final food = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodPickerPage(account: widget.account),
      ),
    );
    if (food == null || !mounted) return;
    final portion = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PortionDialog(food: food, meal: meal),
    );
    if (portion != null && mounted) {
      await _save({
        'path': '/me/nutrition/entries',
        'method': 'POST',
        'body': {
          'foodId': food['id'],
          'date': _data!['date'],
          ...portion,
          'requestId': requestId(),
        },
      });
    }
  }

  Future<void> _estimateMeal() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MealEstimatePage(
          account: widget.account,
          date: _data!['date'] as String,
        ),
      ),
    );
    if (saved == true && mounted) await _load(_data?['date'] as String?);
  }

  Future<void> _edit(Map<String, dynamic> entry, {bool remove = false}) async {
    Map<String, dynamic>? body;
    if (remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove this food entry?'),
          content: Text('${entry['food']['name']} · ${entry['grams']} g'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep entry'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove entry'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      body = {'grams': entry['grams'], 'meal': entry['meal'], 'deleted': true};
    } else {
      body = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _PortionDialog(
          food: entry['food'] as Map<String, dynamic>,
          meal: entry['meal'] as String,
          grams: entry['grams'] as num,
        ),
      );
    }
    if (body != null && mounted) {
      await _save({
        'path': '/me/nutrition/entries/${entry['id']}',
        'method': 'PUT',
        'body': {
          ...body,
          'revision': entry['revision'],
          'requestId': requestId(),
        },
      });
    }
  }

  Future<void> _targets() async {
    final targets = _data?['targets'] as Map<String, dynamic>?;
    final nutrients = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NutrientDialog(
        targets: true,
        initial: targets?['nutrients'] as Map<String, dynamic>?,
      ),
    );
    if (nutrients != null && mounted) {
      await _save({
        'path': '/me/nutrition/targets',
        'method': 'PUT',
        'body': {
          'date': _data!['today'],
          'nutrients': nutrients,
          'revision': targets?['revision'] ?? 0,
          'requestId': requestId(),
        },
      });
    }
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_data!['date'] as String),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(_data!['today'] as String),
    );
    if (picked != null && mounted) await _load(nutritionDay(picked));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Food diary'),
      actions: [
        IconButton(
          tooltip: 'Refresh nutrition',
          onPressed: _saving ? null : () => _load(_data?['date'] as String?),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              'Make every meal count.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Log foods and their weight in grams. Match the food’s raw or cooked state.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_pending != null)
              TextButton(
                onPressed: _saving ? null : () => _save(),
                child: const Text('Retry nutrition save'),
              ),
            if (_data != null) ..._content(),
          ],
        ),
      ),
    ),
  );
  List<Widget> _content() {
    final data = _data!;
    final entries = (data['entries'] as List).cast<Map<String, dynamic>>();
    final totals = data['totals'] as Map<String, dynamic>;
    final targets = data['targets']?['nutrients'] as Map<String, dynamic>?;
    final energy = totals['calories']['known'] as num;
    return [
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: _loading || _saving ? null : _chooseDate,
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text(data['date'] as String),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DAILY ENERGY',
              style: TextStyle(
                color: lime,
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${nutritionNumber(energy)} kcal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              targets == null
                  ? 'No daily targets set'
                  : '${nutritionNumber(targets['calories'] as num)} kcal daily target',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (targets != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (energy / (targets['calories'] as num))
                      .clamp(0, 1)
                      .toDouble(),
                  color: lime,
                  backgroundColor: const Color(0xFF3D5350),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                energy > (targets['calories'] as num)
                    ? '${nutritionNumber(energy - (targets['calories'] as num))} kcal above your target'
                    : '${nutritionNumber((targets['calories'] as num) - energy)} kcal below your target',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            if ((data['estimatedEntryCount'] as num? ?? 0) > 0)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Includes AI estimates · totals are approximate',
                  style: TextStyle(color: lime, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _canEdit ? () => _add('breakfast') : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log a food'),
      ),
      OutlinedButton.icon(
        onPressed: _canEdit ? _estimateMeal : null,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Estimate from photo or text'),
      ),
      if (data['canEdit'] != true)
        const Text(
          'An active membership is required to add or change food logs. Your saved diary is still available.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      TextButton.icon(
        onPressed: _canEdit && data['date'] == data['today'] ? _targets : null,
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text('Set daily targets'),
      ),
      if (data['targets'] != null)
        Text(
          'Targets entered by you · effective ${data['targets']['effectiveFrom']}. Changes apply from today.',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 8,
          children: nutrientLabels.entries.where((entry) => entry.key != 'calories').map((
            entry,
          ) {
            final total = totals[entry.key] as Map<String, dynamic>;
            final value = total['known'] as num;
            final complete = total['complete'] == true;
            final target = targets?[entry.key] as num?;
            final width =
                constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(14) > 19
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return SizedBox(
              width: width,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${complete ? '' : 'At least '}${nutritionNumber(value)}',
                        style: const TextStyle(
                          color: ink,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (target != null)
                        Text(
                          'Target: ${nutritionNumber(target)}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      if (!complete)
                        Text(
                          '${total['missingEntries']} food entries have no value for this nutrient.',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      if (complete && target != null)
                        Text(
                          value > target
                              ? '${nutritionNumber(value - target)} above target'
                              : '${nutritionNumber(target - value)} below target',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Your meals',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
      ...mealLabels.entries.map(
        (meal) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    meal.value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add to ${meal.value.toLowerCase()}',
                  onPressed: _canEdit ? () => _add(meal.key) : null,
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: forest,
                  ),
                ),
              ],
            ),
            if (!entries.any((entry) => entry['meal'] == meal.key))
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Nothing logged yet.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ...entries
                .where((entry) => entry['meal'] == meal.key)
                .map(
                  (entry) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      title: Text(
                        entry['food']['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '${nutritionNumber(entry['grams'] as num)} g · ${nutritionNumber(entry['nutrients']['calories'] as num)} kcal\n${entry['food']['source']['label']}',
                        style: const TextStyle(
                          color: muted,
                          height: 1.5,
                          fontSize: 12,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Edit food entry',
                        enabled: _canEdit,
                        onSelected: (value) =>
                            _edit(entry, remove: value == 'remove'),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit entry'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove entry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_saving) const Text('Saving…', style: TextStyle(color: muted)),
      const Text(
        'Calendar: Asia/Kolkata. Totals depend on the food source and measured quantity. Unknown nutrients are not treated as zero.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.5),
      ),
      const SizedBox(height: 20),
    ];
  }
}

class FoodPickerPage extends StatefulWidget {
  final AccountController account;
  const FoodPickerPage({super.key, required this.account});
  @override
  State<FoodPickerPage> createState() => _FoodPickerPageState();
}

class _FoodPickerPageState extends State<FoodPickerPage> {
  final _query = TextEditingController();
  Map<String, dynamic>? _data, _pending;
  String? _error;
  bool _loading = false, _saving = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_saving) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.account.authenticatedRequest(
        '/me/nutrition/foods?q=${Uri.encodeQueryComponent(_query.text.trim())}',
      );
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = nutritionError(error);
        });
      }
    }
  }

  Future<void> _import(int id) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.account.authenticatedRequest(
        '/me/nutrition/foods/usda/$id',
        method: 'POST',
        body: {},
      );
      if (mounted) {
        Navigator.pop(context, result['food'] as Map<String, dynamic>);
      }
    } catch (error) {
      if (mounted) setState(() => _error = nutritionError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _label() async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _NutrientDialog(targets: false),
    );
    if (body != null && mounted) {
      _pending = {...body, 'requestId': requestId()};
      await _saveLabel();
    }
  }

  Future<void> _saveLabel() async {
    if (_saving || _pending == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.account.authenticatedRequest(
        '/me/nutrition/foods',
        method: 'POST',
        body: _pending,
      );
      if (mounted) {
        Navigator.pop(context, result['food'] as Map<String, dynamic>);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          if (error is ApiFailure && error.status > 0 && error.status < 500) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a food')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              'Find your food.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Match the exact food and preparation. Values are per 100 g; portion weight comes next.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _query,
              maxLength: 100,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Search foods',
                suffixIcon: IconButton(
                  tooltip: 'Search food database',
                  onPressed: _saving || _loading ? null : _search,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _saving || _pending != null ? null : _label,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Enter food label'),
            ),
            if (_loading || _saving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_pending != null)
              TextButton(
                onPressed: _saving ? null : _saveLabel,
                child: const Text('Retry saving food'),
              ),
            if (_data != null) ...[
              if (_data!['providerConfigured'] != true)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Food database search is not connected yet. Use a saved food or enter values from a label.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              if (_data!['notice'] != null)
                Text(
                  _data!['notice'] as String,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              const SizedBox(height: 16),
              const Text(
                'Your saved foods',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if ((_data!['foods'] as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No saved foods match. Add a food label to begin.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ),
              ...(_data!['foods'] as List).cast<Map<String, dynamic>>().map(
                (food) => Card(
                  child: ListTile(
                    title: Text(food['name'] as String),
                    subtitle: Text(
                      '${nutritionNumber(food['nutrients']['calories'] as num)} kcal / 100 g\n${food['source']['label']}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
                    onTap: _saving || _pending != null
                        ? null
                        : () => Navigator.pop(context, food),
                  ),
                ),
              ),
              if ((_data!['external'] as List).isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'USDA FoodData Central',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                ...(_data!['external'] as List).map(
                  (food) => Card(
                    child: ListTile(
                      title: Text(food['name'] as String),
                      subtitle: Text(food['dataType'] as String? ?? 'USDA'),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      onTap: _saving
                          ? null
                          : () => _import(food['fdcId'] as int),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

class _NutrientDialog extends StatefulWidget {
  final bool targets;
  final Map<String, dynamic>? initial;
  const _NutrientDialog({required this.targets, this.initial});
  @override
  State<_NutrientDialog> createState() => _NutrientDialogState();
}

class _NutrientDialogState extends State<_NutrientDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _source = TextEditingController();
  late final Map<String, TextEditingController> _fields;
  @override
  void initState() {
    super.initState();
    _fields = {
      for (final key in nutrientLabels.keys)
        key: TextEditingController(
          text: widget.initial?[key]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  num _max(String key) => widget.targets
      ? {
          'calories': 10000,
          'protein': 1000,
          'carbs': 2000,
          'fat': 1000,
          'fiber': 200,
          'sugar': 1000,
          'sodium': 100000,
        }[key]!
      : key == 'calories'
      ? 1000
      : key == 'sodium'
      ? 100000
      : 100;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.targets ? 'Daily targets' : 'Food label values'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.targets
                  ? 'Enter targets you already use. Changes start today; earlier days keep their previous targets.'
                  : 'Enter values per 100 g from your label or known recipe reference. These values are entered by you, not verified by the app.',
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (!widget.targets) ...[
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Food name'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter the food name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _source,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Label or recipe reference',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter where these values came from.'
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            ...nutrientLabels.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: _fields[entry.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: entry.value,
                    helperText: ['fiber', 'sugar', 'sodium'].contains(entry.key)
                        ? 'Optional · leave blank if unknown'
                        : 'Required',
                    helperMaxLines: 2,
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty &&
                        ['fiber', 'sugar', 'sodium'].contains(entry.key)) {
                      return null;
                    }
                    final number = num.tryParse(value ?? '');
                    final min = widget.targets && entry.key == 'calories'
                        ? 1
                        : 0;
                    return number == null ||
                            !number.isFinite ||
                            number < min ||
                            number > _max(entry.key)
                        ? 'Enter a number from $min to ${_max(entry.key)}.'
                        : null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          final nutrients = {
            for (final entry in _fields.entries)
              entry.key: entry.value.text.trim().isEmpty
                  ? null
                  : num.parse(entry.value.text),
          };
          Navigator.pop(
            context,
            widget.targets
                ? nutrients
                : {
                    'name': _name.text.trim(),
                    'sourceNote': _source.text.trim(),
                    'nutrients': nutrients,
                  },
          );
        },
        child: Text(widget.targets ? 'Save targets' : 'Use this food'),
      ),
    ],
  );
}

class _PortionDialog extends StatefulWidget {
  final Map<String, dynamic> food;
  final String meal;
  final num? grams;
  const _PortionDialog({required this.food, required this.meal, this.grams});
  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _grams;
  late String _meal;
  @override
  void initState() {
    super.initState();
    _grams = TextEditingController(text: widget.grams?.toString() ?? '100');
    _meal = widget.meal;
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grams = num.tryParse(_grams.text);
    return AlertDialog(
      scrollable: true,
      title: Text(widget.food['name'] as String),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.food['source']['label'] as String,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (widget.food['source']['note'] != null)
                Text(
                  widget.food['source']['note'] as String,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _grams,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Quantity (g)',
                  helperText: 'Up to 10,000 g · two decimal places',
                  helperMaxLines: 2,
                  errorMaxLines: 3,
                ),
                validator: (value) {
                  final n = num.tryParse(value ?? '');
                  return n == null ||
                          !n.isFinite ||
                          n <= 0 ||
                          n > 10000 ||
                          (n * 100 - (n * 100).round()).abs() > .000001
                      ? 'Enter grams above zero, with up to two decimal places.'
                      : null;
                },
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _meal,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Meal'),
                items: mealLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _meal = value);
                },
              ),
              const SizedBox(height: 18),
              if (grams != null &&
                  grams.isFinite &&
                  grams > 0 &&
                  grams <= 10000)
                Text(
                  '${nutritionNumber((widget.food['nutrients']['calories'] as num) * grams / 100)} kcal for ${nutritionNumber(grams)} g',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: forest,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, {
                'grams': num.parse(_grams.text),
                'meal': _meal,
              });
            }
          },
          child: Text(widget.grams == null ? 'Log food' : 'Save changes'),
        ),
      ],
    );
  }
}
