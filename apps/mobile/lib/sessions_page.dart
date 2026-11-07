import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'workout_pages.dart' show requestId;

String sessionTime(String value) {
  final t = DateTime.parse(value)
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30));
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} IST';
}

class SessionsPage extends StatefulWidget {
  final AccountController account;
  const SessionsPage({super.key, required this.account});
  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  Map<String, dynamic>? _data, _pending;
  String? _error;
  bool _busy = false;
  final _elapsed = Stopwatch();
  DateTime get _now => _data == null
      ? DateTime.now().toUtc()
      : DateTime.parse(_data!['serverTime']).add(_elapsed.elapsed);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _elapsed.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.account.authenticatedRequest('/me/sessions');
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          _elapsed
            ..reset()
            ..start();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Could not load live coaching sessions.',
        );
      }
    }
  }

  Future<void> _save(String path, Map<String, dynamic> body) async {
    _pending ??= {
      'path': path,
      'body': {...body, 'requestId': requestId()},
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.account.authenticatedRequest(
        _pending!['path'],
        method: 'POST',
        body: Map<String, dynamic>.from(_pending!['body']),
      );
      if (!mounted) return;
      setState(() => _pending = null);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['status'] == 'booked'
                  ? 'Session reserved. One credit is held for this appointment.'
                  : result['consumed'] == true
                  ? 'Booking cancelled. One session was used under the saved cancellation rules.'
                  : 'Booking cancelled. Its held session was released.',
            ),
          ),
        );
      }
    } catch (e) {
      if (e is ApiFailure && e.status >= 400 && e.status < 500) {
        _pending = null;
        await _load();
      }
      if (mounted) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Could not confirm the booking change. Retry the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    List<Widget> content,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  List<Widget> _rules(Map<String, dynamic> p) => [
    Text('${p['durationMinutes']}-minute session'),
    const SizedBox(height: 8),
    Text(
      'Free cancellation with at least ${p['freeCancellationHours']} hours notice.',
    ),
    const SizedBox(height: 8),
    Text(
      p['chargeLateCancellation'] == true
          ? 'Late cancellation uses one session.'
          : 'Late cancellation releases the held session.',
    ),
    const SizedBox(height: 8),
    Text(
      p['chargeNoShow'] == true
          ? 'A recorded no-show uses one session.'
          : 'A recorded no-show releases the held session.',
    ),
  ];
  Future<void> _book(Map<String, dynamic> slot) async {
    final p = _data!['policy'] as Map<String, dynamic>;
    if (!await _confirm('Reserve this session?', [
      Text(slot['trainerName']),
      Text(sessionTime(slot['startsAt'])),
      const SizedBox(height: 12),
      ..._rules(p),
      const SizedBox(height: 12),
      const Text('Booking holds one session from your active membership.'),
    ], 'Confirm booking')) {
      return;
    }
    if (mounted) {
      await _save('/me/sessions', {
        'slotId': slot['id'],
        'slotRevision': slot['revision'],
        'policyRevision': _data!['revision'],
      });
    }
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    if (!await _confirm('Cancel this booking?', [
      Text(sessionTime(booking['startsAt'])),
      const SizedBox(height: 12),
      ..._rules(booking['policy'] as Map<String, dynamic>),
    ], 'Cancel booking')) {
      return;
    }
    if (mounted) {
      await _save('/me/sessions/${booking['id']}/cancel', {
        'revision': booking['revision'],
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = _data?['membership'] as Map<String, dynamic>?;
    final canBook =
        _data?['bookingEnabled'] == true &&
        membership != null &&
        (membership['videoSessionsRemaining'] as num) > 0 &&
        !_busy &&
        _pending == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live coaching sessions'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh coaching sessions',
            icon: const Icon(Icons.refresh),
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
                'Make time\nfor your coach.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Reserve a published time with an assigned trainer. Times below are shown in India time (IST).',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry sessions'),
                ),
              ],
              if (_data == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_data != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR SESSION ALLOWANCE',
                        style: TextStyle(
                          color: lime,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        membership == null
                            ? 'No active membership'
                            : '${membership['videoSessionsRemaining']} available · ${membership['videoSessionsReserved'] ?? 0} reserved',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 23,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (membership != null)
                        Text(
                          '${membership['videoSessionsUsed']} used of ${membership['videoSessionsTotal']} total',
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_data!['confirmed'] != true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Booking rules are awaiting owner confirmation.',
                    ),
                  ),
                if (_data!['providerConfigured'] != true)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'In-app video is not connected yet. New bookings are unavailable.',
                    ),
                  ),
                if (membership != null && membership['videoSessionsTotal'] == 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Your Normal plan has no live video sessions. Premium includes 10 and Premium Plus includes 25 per membership month.',
                    ),
                  ),
                if (_data!['policy'] != null)
                  ExpansionTile(
                    title: const Text('Current booking rules'),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _rules(_data!['policy']),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Text(
                  'Available times',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if ((_data!['slots'] as List).isEmpty)
                  const Text(
                    'No matching appointment times are available in your current membership period.',
                    style: TextStyle(color: muted),
                  ),
                for (final slot
                    in (_data!['slots'] as List).cast<Map<String, dynamic>>())
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            slot['trainerName'],
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(sessionTime(slot['startsAt'])),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: canBook ? () => _book(slot) : null,
                            child: const Text('Book this time'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Your bookings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if ((_data!['bookings'] as List).isEmpty)
                  const Text('Your saved appointments will appear here.'),
                for (final booking
                    in (_data!['bookings'] as List)
                        .cast<Map<String, dynamic>>())
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            booking['trainerName'],
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(sessionTime(booking['startsAt'])),
                          const SizedBox(height: 8),
                          Text(
                            booking['status'] == 'booked'
                                ? 'Reserved · one session held'
                                : '${(booking['status'] as String).replaceAll('_', ' ')} · ${booking['consumed'] == true ? 'one session used' : 'no session used'}',
                            style: const TextStyle(
                              color: forest,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (booking['attendanceNote'] != null) ...[
                            const SizedBox(height: 8),
                            Text(booking['attendanceNote']),
                          ],
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Saved cancellation rules'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _rules(booking['policy']),
                                ),
                              ),
                            ],
                          ),
                          if (booking['status'] == 'booked') ...[
                            if (_data!['providerConfigured'] != true)
                              const Text(
                                'Video joining is awaiting connection.',
                                style: TextStyle(color: muted),
                              ),
                            TextButton(
                              onPressed:
                                  _busy ||
                                      _pending != null ||
                                      !DateTime.parse(booking['startsAt'])
                                          .isAfter(_now)
                                  ? null
                                  : () => _cancel(booking),
                              child: const Text('Cancel this booking'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              if (_pending != null && !_busy) ...[
                const Text(
                  'This change is not confirmed. Retrying uses the same reference.',
                ),
                FilledButton(
                  onPressed: () => _save(
                    _pending!['path'],
                    Map<String, dynamic>.from(_pending!['body']),
                  ),
                  child: const Text('Retry same booking change'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
