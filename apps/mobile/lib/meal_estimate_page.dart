import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'account.dart';
import 'app_theme.dart';
import 'nutrition_page.dart'
    show nutrientLabels, mealLabels, nutritionNumber, nutritionError;
import 'workout_pages.dart' show requestId;

class MealEstimatePage extends StatefulWidget {
  final AccountController account;
  final String date;
  final Future<Uint8List?> Function(ImageSource)? pickPhoto;
  const MealEstimatePage({
    super.key,
    required this.account,
    required this.date,
    this.pickPhoto,
  });
  @override
  State<MealEstimatePage> createState() => _MealEstimatePageState();
}

class _MealEstimatePageState extends State<MealEstimatePage> {
  final _description = TextEditingController();
  final _review = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _items = <_EstimateFields>[];
  Uint8List? _photo;
  Map<String, dynamic>? _status, _draft, _pendingSave;
  String? _requestId, _error;
  String _meal = 'breakfast';
  bool _busy = false, _statusLoading = true;
  int _photoGeneration = 0;
  @override
  void initState() {
    super.initState();
    _loadStatus();
    _recoverPhoto();
  }

  @override
  void dispose() {
    _photoGeneration++;
    _description.dispose();
    _clearItems();
    super.dispose();
  }

  void _clearItems() {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await widget.account.authenticatedRequest(
        '/me/meal-estimates/status',
      );
      if (mounted) {
        setState(() {
          _status = status;
          _statusLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          _statusLoading = false;
        });
      }
    }
  }

  Future<void> _recoverPhoto() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        widget.pickPhoto != null) {
      return;
    }
    final generation = _photoGeneration;
    try {
      final lost = await _picker.retrieveLostData();
      final file = lost.files?.firstOrNull;
      if (file != null &&
          mounted &&
          generation == _photoGeneration &&
          _photo == null) {
        final bytes = await _readFile(file);
        if (mounted && generation == _photoGeneration) {
          setState(() {
            _photo = bytes;
            _requestId = null;
            _error = 'Recovered a meal photo. Review it, then tap Estimate meal when ready.';
          });
        }
      }
    } catch (_) {
      /* A new photo can still be selected if recovery is unavailable. */
    }
  }

  Future<Uint8List> _readFile(XFile file) async {
    if (await file.length() > 4 * 1024 * 1024) {
      throw const ApiFailure(400, 'Choose a photo up to 4 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw const ApiFailure(400, 'Choose a photo up to 4 MB.');
    }
    return bytes;
  }

  Future<void> _pick(ImageSource source) async {
    final generation = ++_photoGeneration;
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!(source);
      } else {
        final file = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        );
        if (file != null) bytes = await _readFile(file);
      }
      if (bytes == null || !mounted || generation != _photoGeneration) return;
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
        throw const ApiFailure(400, 'Choose a photo up to 4 MB.');
      }
      setState(() {
        _photo = bytes;
        _requestId = null;
        _draft = null;
        _clearItems();
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure ? error.message : 'Could not open the photo. Check photo/camera access or choose another image.',
        );
      }
    }
  }

  bool get _canEstimate =>
      !_busy &&
      !_statusLoading &&
      _status?['configured'] == true &&
      _status?['entitled'] == true &&
      ((_status?['remainingToday'] as num? ?? 0) > 0 || _requestId != null) &&
      _draft?['status'] != 'estimated' &&
      _pendingSave == null;
  Future<void> _estimate() async {
    if (_busy) return;
    if (_photo == null && _description.text.trim().isEmpty) {
      setState(() => _error = 'Describe a dish or upload a meal photo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _requestId ??= requestId();
    });
    try {
      final result = await widget.account.estimateMeal({
        'description': _description.text.trim(),
        'requestId': _requestId!,
      }, _photo);
      if (!mounted) return;
      _clearItems();
      for (final item
          in (result['items'] as List).cast<Map<String, dynamic>>()) {
        _items.add(_EstimateFields(item));
      }
      setState(() => _draft = result);
      await _loadStatus();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          if (error is ApiFailure && error.status >= 500) _requestId = null;
        });
        await _loadStatus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool retry = false}) async {
    if (_busy || _draft == null) return;
    if (!retry && !_review.currentState!.validate()) return;
    final body = retry
        ? _pendingSave!
        : {
            'date': widget.date,
            'meal': _meal,
            'items': _items.map((item) => item.value()).toList(),
            'requestId': requestId(),
          };
    setState(() {
      _busy = true;
      _pendingSave = body;
      _error = null;
    });
    try {
      await widget.account.authenticatedRequest(
        '/me/meal-estimates/${_draft!['id']}/save',
        method: 'POST',
        body: body,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = nutritionError(error);
          if (error is ApiFailure && error.status > 0 && error.status < 500) {
            _pendingSave = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  num _total(String key) => _items.fold<num>(0, (sum, item) {
    final grams = num.tryParse(item.grams.text);
    final density = num.tryParse(item.nutrients[key]!.text);
    if (grams == null ||
        density == null ||
        !grams.isFinite ||
        !density.isFinite ||
        grams < 0 ||
        grams > 10000 ||
        density < 0 ||
        density >
            (key == 'calories'
                ? 1000
                : key == 'sodium'
                ? 100000
                : 100)) {
      return sum;
    }
    return sum + grams * density / 100;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Estimate a meal')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              'Photo or text.\nA useful estimate.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Share a meal photo, describe a dish, or use both. We’ll assume reasonable portions and cooking oil when details are missing.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _description,
              enabled: !_busy && _pendingSave == null,
              maxLength: 1500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Describe your dish',
                hintText: 'Two chapatis, dal and a bowl of rice',
                helperText: 'Optional when you upload a photo.',
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                if (_draft != null || _requestId != null) {
                  setState(() {
                    _requestId = null;
                    _draft = null;
                    _clearItems();
                  });
                }
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || _pendingSave != null
                      ? null
                      : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Upload photo'),
                ),
                if (!kIsWeb &&
                    [
                      TargetPlatform.android,
                      TargetPlatform.iOS,
                    ].contains(defaultTargetPlatform))
                  OutlinedButton.icon(
                    onPressed: _busy || _pendingSave != null
                        ? null
                        : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
              ],
            ),
            if (_photo != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  _photo!,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 100,
                    child: Center(
                      child: Text(
                        'Photo selected. Choose a JPG, PNG or WebP if it cannot be read.',
                      ),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy || _pendingSave != null
                    ? null
                    : () => setState(() {
                        _photoGeneration++;
                        _photo = null;
                        _requestId = null;
                        _draft = null;
                        _clearItems();
                      }),
                child: const Text('Remove photo'),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Your text/photo is sent to the AI provider when you request an estimate. The photo is not saved in your diary. Nutrition and portions are approximate.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.5),
            ),
            if (_statusLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              if (_status!['configured'] != true)
                const Text(
                  'Meal estimation is not connected yet. Food-label entry and saved foods remain available.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              if (_status!['entitled'] != true)
                const Text(
                  'An active membership is required for meal estimates.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              if (_status!['configured'] == true &&
                  _status!['entitled'] == true)
                Text(
                  '${_status!['remainingToday']} of ${_status!['dailyLimit']} estimates left today',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _canEstimate ? _estimate : null,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _busy
                    ? 'Working…'
                    : _draft?['status'] == 'estimated'
                    ? 'Estimate ready'
                    : _requestId == null
                    ? 'Estimate meal'
                    : 'Retry estimate',
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
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
            if (_requestId != null && _error != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _requestId = null;
                        _draft = null;
                        _clearItems();
                        _error = null;
                      }),
                child: const Text('Start a new estimate'),
              ),
            if (_status == null && !_statusLoading)
              TextButton(
                onPressed: _busy ? null : _loadStatus,
                child: const Text('Retry connection'),
              ),
            if (_draft?['status'] == 'unclear')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_draft!['clarification'] as String),
                ),
              ),
            if (_draft?['status'] == 'estimated') ..._reviewContent(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  List<Widget> _reviewContent() => [
    Form(
      key: _review,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI ESTIMATE · REVIEW BEFORE SAVING',
                  style: TextStyle(
                    color: lime,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Approx. ${_total('calories').round()} kcal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Protein ${nutritionNumber(_total('protein'))} g · Carbs ${nutritionNumber(_total('carbs'))} g · Fat ${nutritionNumber(_total('fat'))} g',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  'Uncertainty: ${_draft!['uncertainty']}. Portions and hidden ingredients can change these values.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Assumptions used',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          ...(_draft!['assumptions'] as List).map(
            (text) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '• $text',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Adjust foods and portions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Column(
            children: _items
                .map(
                  (item) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: item.name,
                            enabled: !_busy && _pendingSave == null,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Estimated food',
                            ),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Enter a food name.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: item.grams,
                            enabled: !_busy && _pendingSave == null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Estimated portion (g)',
                              errorMaxLines: 3,
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              final n = num.tryParse(value ?? '');
                              return n == null ||
                                      !n.isFinite ||
                                      n <= 0 ||
                                      n > 10000 ||
                                      (n * 100 - (n * 100).round()).abs() >
                                          .000001
                                  ? 'Enter grams above zero, up to 10,000, with at most two decimals.'
                                  : null;
                            },
                          ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            maintainState: true,
                            title: const Text('Edit estimated nutrients'),
                            subtitle: const Text(
                              'Values per 100 g',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            children: nutrientLabels.entries
                                .map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: TextFormField(
                                      controller: item.nutrients[entry.key],
                                      enabled: !_busy && _pendingSave == null,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: entry.value,
                                        helperText:
                                            [
                                              'fiber',
                                              'sugar',
                                              'sodium',
                                            ].contains(entry.key)
                                            ? 'Leave blank if unknown'
                                            : 'Required',
                                        errorMaxLines: 3,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                      validator: (value) {
                                        if ((value ?? '').trim().isEmpty &&
                                            [
                                              'fiber',
                                              'sugar',
                                              'sodium',
                                            ].contains(entry.key)) {
                                          return null;
                                        }
                                        final n = num.tryParse(value ?? '');
                                        final max = entry.key == 'calories'
                                            ? 1000
                                            : entry.key == 'sodium'
                                            ? 100000
                                            : 100;
                                        return n == null ||
                                                !n.isFinite ||
                                                n < 0 ||
                                                n > max
                                            ? 'Enter a value from 0 to $max.'
                                            : null;
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          TextButton(
                            onPressed:
                                _busy ||
                                    _pendingSave != null ||
                                    _items.length == 1
                                ? null
                                : () {
                                    setState(() => _items.remove(item));
                                    item.dispose();
                                  },
                            child: const Text('Remove this food'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _meal,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Save under meal'),
            items: mealLabels.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: _busy || _pendingSave != null
                ? null
                : (value) {
                    if (value != null) setState(() => _meal = value);
                  },
          ),
          const SizedBox(height: 12),
          Text(
            'Save to ${widget.date}. This remains labelled AI estimate after editing. Unsaved drafts expire after 24 hours.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _pendingSave != null ? null : () => _save(),
            child: const Text('Save estimate to diary'),
          ),
          if (_pendingSave != null)
            TextButton(
              onPressed: _busy ? null : () => _save(retry: true),
              child: const Text('Retry diary save'),
            ),
        ],
      ),
    ),
  ];
}

class _EstimateFields {
  final TextEditingController name, grams;
  final Map<String, TextEditingController> nutrients;
  _EstimateFields(Map<String, dynamic> item)
    : name = TextEditingController(text: item['name'] as String),
      grams = TextEditingController(text: item['grams'].toString()),
      nutrients = {
        for (final key in nutrientLabels.keys)
          key: TextEditingController(
            text: item['nutrients'][key]?.toString() ?? '',
          ),
      };
  Map<String, dynamic> value() => {
    'name': name.text.trim(),
    'grams': num.parse(grams.text),
    'nutrients': {
      for (final entry in nutrients.entries)
        entry.key: entry.value.text.trim().isEmpty
            ? null
            : num.parse(entry.value.text),
    },
  };
  void dispose() {
    name.dispose();
    grams.dispose();
    for (final controller in nutrients.values) {
      controller.dispose();
    }
  }
}
