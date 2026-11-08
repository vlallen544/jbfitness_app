import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'workout_pages.dart' show requestId;

import 'account.dart';
import 'app_theme.dart';

const progressMetrics = {
  'weight': 'Weight (kg)',
  'waist': 'Waist (cm)',
  'chest': 'Chest (cm)',
  'arms': 'Arm (cm)',
  'thighs': 'Thigh (cm)',
};
String progressNumber(num n) => n == n.roundToDouble()
    ? n.toInt().toString()
    : n.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
String progressError(Object e) =>
    e is ApiFailure ? e.message : 'Could not load progress. Please retry.';
typedef ProgressPhotoPicker = Future<Uint8List?> Function(ImageSource source);

class ProgressPage extends StatefulWidget {
  final AccountController account;
  final ProgressPhotoPicker? pickPhoto;
  const ProgressPage({super.key, required this.account, this.pickPhoto});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  Map<String, dynamic>? _data;
  String? _error, _older, _newer;
  String _metric = 'weight', _angle = 'front';
  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _records =>
      (_data?['records'] as List? ?? []).cast<Map<String, dynamic>>();
  Future<void> _load() async {
    try {
      final data = await widget.account.authenticatedRequest('/me/progress');
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        final ids = _records.map((r) => r['id']).toSet();
        if (!ids.contains(_older)) {
          _older = _records.isEmpty ? null : _records.last['id'];
        }
        if (!ids.contains(_newer)) {
          _newer = _records.isEmpty ? null : _records.first['id'];
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = progressError(e));
    }
  }

  Future<void> _edit([Map<String, dynamic>? record]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProgressEditor(
          account: widget.account,
          record: record,
          today: _data!['today'],
          canEdit: _data!['canEdit'] == true,
          pickPhoto: widget.pickPhoto,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final points = records.reversed
        .where((r) => r['measurements'][_metric] != null)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Body progress'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh progress',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'Your progress,\nat your pace.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              const Text(
                'Record measurements and compare private photos. Changes are shown from your records, without appearance scores.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: brandRed)),
                TextButton(
                  onPressed: _load,
                  child: const Text('Retry progress'),
                ),
              ],
              if (_data == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_data != null) ...[
                if (_data!['canEdit'] != true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'An active membership is needed to add or edit progress. Your history and deletion controls remain available.',
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _data!['canEdit'] == true ? () => _edit() : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add progress record'),
                ),
                const SizedBox(height: 22),
                DropdownButtonFormField<String>(
                  initialValue: _metric,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Chart measurement',
                  ),
                  items: progressMetrics.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _metric = v!),
                ),
                const SizedBox(height: 18),
                if (points.isEmpty)
                  const Text('No values recorded for this measurement yet.')
                else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${progressNumber(points.last['measurements'][_metric])} ${_metric == 'weight' ? 'kg' : 'cm'}',
                          style: const TextStyle(
                            fontSize: 30,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Latest recorded · ${points.last['date']}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        if (points.length < 2)
                          const Text(
                            'Add another dated value to see a trend.',
                            style: TextStyle(color: accentRed),
                          )
                        else
                          Semantics(
                            label:
                                '${progressMetrics[_metric]} over time. ${points.length} recorded values. From ${points.first['date']} to ${points.last['date']}. Values are listed in history.',
                            child: SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _ProgressChart(points, _metric),
                              ),
                            ),
                          ),
                        if (points.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(
                              spacing: 18,
                              children: [
                                Text(
                                  points.first['date'],
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  points.last['date'],
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (records.length > 1) ...[
                  Text(
                    'Compare two dates',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _dateSelect(
                    'First date',
                    _older!,
                    (v) => setState(() => _older = v),
                  ),
                  const SizedBox(height: 12),
                  _dateSelect(
                    'Second date',
                    _newer!,
                    (v) => setState(() => _newer = v),
                  ),
                  const SizedBox(height: 14),
                  ..._comparison(),
                  const SizedBox(height: 24),
                ],
                Text(
                  'Progress history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Your first record starts the story. Add measurements, photos, or both.',
                    ),
                  ),
                for (final record in records)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(record['date']),
                      subtitle: Text(
                        [
                          for (final metric in progressMetrics.entries)
                            if (record['measurements'][metric.key] != null)
                              '${metric.value}: ${progressNumber(record['measurements'][metric.key])}',
                          '${(record['photos'] as List).length} private photos',
                        ].join('\n'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _edit(record),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateSelect(
    String label,
    String value,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: _records
        .map(
          (r) =>
              DropdownMenuItem<String>(value: r['id'], child: Text(r['date'])),
        )
        .toList(),
    onChanged: changed,
  );
  List<Widget> _comparison() {
    final a = _records.firstWhere((r) => r['id'] == _older),
        b = _records.firstWhere((r) => r['id'] == _newer);
    return [
      const Text(
        'Change = second date minus first date. A decrease or increase is not automatically better.',
        style: TextStyle(color: muted),
      ),
      for (final m in progressMetrics.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(() {
            final x = a['measurements'][m.key] as num?,
                y = b['measurements'][m.key] as num?;
            if (x == null || y == null) {
              return '${m.value}: not recorded on both dates';
            }
            final d = y - x;
            return '${m.value}: ${progressNumber(x)} → ${progressNumber(y)} (${d > 0 ? '+' : ''}${progressNumber(d)})';
          }()),
        ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _angle,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Photo angle to compare'),
        items: [
          'front',
          'side',
          'back',
        ].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
        onChanged: (v) => setState(() => _angle = v!),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in [a, b])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    Text(r['date']),
                    const SizedBox(height: 8),
                    _comparePhoto(r),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _comparePhoto(Map<String, dynamic> record) {
    final photos = (record['photos'] as List).where(
      (p) => p['angle'] == _angle,
    );
    if (photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No photo for this angle'),
      );
    }
    return PrivateProgressPhoto(
      key: ValueKey(photos.first['id']),
      account: widget.account,
      id: photos.first['id'],
    );
  }
}

class _ProgressChart extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final String metric;
  _ProgressChart(this.points, this.metric);
  @override
  void paint(Canvas canvas, Size size) {
    final values = points
        .map((p) => (p['measurements'][metric] as num).toDouble())
        .toList();
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final spread = math.max(high - low, 1.0),
        minY = low - spread * .15,
        maxY = high + spread * .15;
    final first = DateTime.parse(points.first['date']).millisecondsSinceEpoch;
    final duration = math.max(
      1,
      DateTime.parse(points.last['date']).millisecondsSinceEpoch - first,
    );
    final path = Path();
    final locations = <Offset>[];
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 10 + (size.height - 20) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: progressNumber(maxY - (maxY - minY) * i / 2),
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 10));
    }
    for (var i = 0; i < points.length; i++) {
      final x =
          36 +
          (size.width - 44) *
              (DateTime.parse(points[i]['date']).millisecondsSinceEpoch -
                  first) /
              duration;
      final y = 10 + (size.height - 20) * (maxY - values[i]) / (maxY - minY);
      locations.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accentRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final p in locations) {
      canvas.drawCircle(p, 3.5, Paint()..color = accentRed);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressChart old) => true;
}

class PrivateProgressPhoto extends StatefulWidget {
  final AccountController account;
  final String id;
  const PrivateProgressPhoto({
    super.key,
    required this.account,
    required this.id,
  });
  @override
  State<PrivateProgressPhoto> createState() => _PrivateProgressPhotoState();
}

class _PrivateProgressPhotoState extends State<PrivateProgressPhoto> {
  late Future<Uint8List> _bytes;
  @override
  void initState() {
    super.initState();
    _bytes = widget.account.progressPhoto(widget.id);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () =>
              setState(() => _bytes = widget.account.progressPhoto(widget.id)),
          child: const Text('Retry photo'),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 130,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final bytes = snapshot.data!;
      return Semantics(
        label: 'Private progress photo. Tap to enlarge.',
        button: true,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: InteractiveViewer(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('Photo could not be displayed'),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close photo'),
                  ),
                ],
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Text('Photo could not be displayed'),
            ),
          ),
        ),
      );
    },
  );
}

class ProgressEditor extends StatefulWidget {
  final AccountController account;
  final Map<String, dynamic>? record;
  final String today;
  final bool canEdit;
  final ProgressPhotoPicker? pickPhoto;
  const ProgressEditor({
    super.key,
    required this.account,
    this.record,
    required this.today,
    required this.canEdit,
    this.pickPhoto,
  });
  @override
  State<ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<ProgressEditor> {
  final _form = GlobalKey<FormState>();
  late Map<String, TextEditingController> _fields;
  late String _date;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _pending;
  late List<Map<String, dynamic>> _photos;
  Uint8List? _photo;
  String _angle = 'front';
  String? _photoRef;
  bool _photoPending = false;
  @override
  void initState() {
    super.initState();
    _date = widget.record?['date'] ?? widget.today;
    _fields = {
      for (final k in progressMetrics.keys)
        k: TextEditingController(
          text: widget.record?['measurements'][k]?.toString() ?? '',
        ),
    };
    _photos = (widget.record?['photos'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .toList();
    if (widget.pickPhoto == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _recoverPhoto();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _recoverPhoto() async {
    try {
      final result = await ImagePicker().retrieveLostData();
      if (!mounted || result.files == null || widget.record == null) return;
      final bytes = await result.files!.first.readAsBytes();
      if (mounted) _selectPhoto(bytes);
    } catch (_) {
      /* The user can select the photo again. */
    }
  }

  void _selectPhoto(Uint8List bytes) {
    setState(() {
      if (bytes.length > 4 * 1024 * 1024) {
        _error = 'Choose a photo smaller than 4 MB.';
      } else {
        _photo = bytes;
        _photoRef = requestId();
        _photoPending = false;
        _error = null;
      }
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!(source);
      } else {
        final file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        );
        bytes = await file?.readAsBytes();
      }
      if (mounted && bytes != null) _selectPhoto(bytes);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open photos. Check photo/camera access and try again.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      _pending = {
        'requestId': requestId(),
        'measurements': {
          for (final e in _fields.entries)
            e.key: e.value.text.trim().isEmpty
                ? null
                : double.parse(e.value.text.trim()),
        },
        if (widget.record == null)
          'date': _date
        else
          'revision': widget.record!['revision'],
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.authenticatedRequest(
        '/me/progress${widget.record == null ? '' : '/${widget.record!['id']}'}',
        method: widget.record == null ? 'POST' : 'PUT',
        body: _pending,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = progressError(e);
          if (e is ApiFailure &&
              e.status >= 400 &&
              e.status < 500 &&
              e.status != 409) {
            _pending = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _deleteRecord() async {
    if (!await _confirm(
      'Delete this record?',
      'This removes the measurements and all photos for $_date.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.account.authenticatedRequest(
        '/me/progress/${widget.record!['id']}/delete',
        method: 'PUT',
        body: {'revision': widget.record!['revision']},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = progressError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _photoPending = true;
      _error = null;
    });
    try {
      await widget.account.uploadProgressPhoto(widget.record!['id'], {
        'angle': _angle,
        'requestId': _photoRef!,
      }, _photo!);
      final data = await widget.account.authenticatedRequest('/me/progress');
      final records = (data['records'] as List).where(
        (r) => r['id'] == widget.record!['id'],
      );
      if (mounted) {
        setState(() {
          _photos = records.isEmpty
              ? []
              : (records.first['photos'] as List).cast<Map<String, dynamic>>();
          _photo = null;
          _photoRef = null;
          _photoPending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = progressError(e);
          if (e is ApiFailure && e.status >= 400 && e.status < 500) {
            _photoPending = false;
            _photoRef = requestId();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    if (!await _confirm(
      'Delete this photo?',
      'The ${photo['angle']} photo will be removed from this record.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.account.authenticatedRequest(
        '/me/progress/photos/${photo['id']}',
        method: 'DELETE',
      );
      if (mounted) {
        setState(() => _photos.removeWhere((p) => p['id'] == photo['id']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = progressError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChange =
        widget.canEdit && !_busy && _pending == null && !_photoPending;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? 'Add progress' : 'Progress record'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _date,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  if (widget.record == null)
                    OutlinedButton.icon(
                      onPressed: canChange
                          ? () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.parse(_date),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.parse(widget.today),
                              );
                              if (date != null && mounted) {
                                setState(
                                  () => _date = date
                                      .toIso8601String()
                                      .substring(0, 10),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Choose record date'),
                    ),
                  const Text(
                    'All measurements are optional. Use the same measuring method and side each time. Saving a record does not change your profile weight.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 18),
                  for (final m in progressMetrics.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: _fields[m.key],
                        enabled: canChange,
                        decoration: InputDecoration(labelText: m.value),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final text = value!.trim();
                          if (text.isEmpty) return null;
                          final n = double.tryParse(text),
                              max = m.key == 'weight'
                                  ? 500
                                  : m.key == 'arms'
                                  ? 200
                                  : m.key == 'thighs'
                                  ? 250
                                  : 400;
                          if (n == null ||
                              !n.isFinite ||
                              n <= 0 ||
                              n > max ||
                              !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
                            return 'Use a value above 0 and up to $max, with at most 2 decimals.';
                          }
                          return null;
                        },
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: brandRed),
                      ),
                    ),
                  if (widget.canEdit)
                    FilledButton(
                      onPressed: _busy || _photoPending ? null : _save,
                      child: Text(
                        _busy
                            ? 'Saving…'
                            : _pending == null
                            ? 'Save measurements'
                            : 'Retry measurement save',
                      ),
                    ),
                  if (_pending != null)
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Close and refresh'),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Private progress photos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only you can view these photos in this version. They are stored privately and are not sent to AI. Front, side and back are optional.',
                    style: TextStyle(color: muted),
                  ),
                  if (widget.record == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Save the dated record first, then open it from history to add photos.',
                      ),
                    ),
                  for (final p in _photos)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${p['angle']} · $_date'),
                          const SizedBox(height: 8),
                          PrivateProgressPhoto(
                            key: ValueKey(p['id']),
                            account: widget.account,
                            id: p['id'],
                          ),
                          TextButton.icon(
                            onPressed:
                                _busy || _pending != null || _photoPending
                                ? null
                                : () => _deletePhoto(p),
                            icon: const Icon(Icons.delete_outline),
                            label: Text('Delete ${p['angle']} photo'),
                          ),
                        ],
                      ),
                    ),
                  if (widget.record != null &&
                      widget.canEdit &&
                      _photos.length < 3) ...[
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: _angle,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Photo angle',
                      ),
                      items: ['front', 'side', 'back']
                          .map(
                            (a) => DropdownMenuItem(value: a, child: Text(a)),
                          )
                          .toList(),
                      onChanged: canChange
                          ? (v) => setState(() {
                              _angle = v!;
                              if (_photo != null) _photoRef = requestId();
                            })
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: canChange
                          ? () => _pick(ImageSource.gallery)
                          : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose progress photo'),
                    ),
                    if (!kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS))
                      OutlinedButton.icon(
                        onPressed: canChange
                            ? () => _pick(ImageSource.camera)
                            : null,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Take progress photo'),
                      ),
                    if (_photo != null) ...[
                      const SizedBox(height: 10),
                      Image.memory(
                        _photo!,
                        height: 200,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text(
                          'Photo preview unavailable. Choose a JPEG, PNG or WebP photo.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _busy || _pending != null ? null : _upload,
                        child: Text(
                          _photoPending
                              ? 'Retry photo upload'
                              : 'Save private photo',
                        ),
                      ),
                      if (!_photoPending)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _photo = null),
                          child: const Text('Remove selected photo'),
                        ),
                    ],
                  ],
                  if (widget.record != null) ...[
                    const SizedBox(height: 28),
                    TextButton.icon(
                      onPressed: _busy || _pending != null || _photoPending
                          ? null
                          : _deleteRecord,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete progress record'),
                    ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
