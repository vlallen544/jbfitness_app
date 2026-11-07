import 'dart:async';

import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';

class MembershipPage extends StatefulWidget {
  final AccountController account;
  const MembershipPage({super.key, required this.account});
  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage>
    with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _data;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refresh());
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      return await Future.wait([
        widget.account.api.request('/plans'),
        widget.account.api.request(
          '/me/membership',
          token: widget.account.token,
        ),
      ]);
    } on ApiFailure catch (error) {
      if (error.status == 401) {
        await widget.account.signOut(localOnly: true);
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    final next = _load();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {
      /* The page displays the request failure. */
    }
  }

  String _date(dynamic value) {
    final date = DateTime.parse(value as String).toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _price(dynamic value) {
    final digits = ((value as num).toInt() ~/ 100).toString();
    if (digits.length <= 3) {
      return '₹$digits';
    }
    return '₹${digits.substring(0, digits.length - 3)},${digits.substring(digits.length - 3)}';
  }

  Widget _notice(String title, String description) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: Colors.black54, height: 1.5),
          ),
        ],
      ),
    ),
  );
  Widget _period(Map<String, dynamic> period, {bool queued = false}) => Card(
    color: queued ? Colors.white : ink,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            queued ? 'NEXT MEMBERSHIP' : 'ACTIVE MEMBERSHIP',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: queued ? forest : lime,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            period['planName'] as String,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: queued ? ink : Colors.white,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_date(period['startsAt'])} – ${_date(period['endsAt'])}',
            style: TextStyle(
              color: queued ? muted : const Color(0xFFC6D6D0),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${period['videoSessionsRemaining']} of ${period['videoSessionsTotal']} video sessions remaining',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: queued ? ink : Colors.white,
            ),
          ),
          if ((period['videoSessionsTotal'] as num) > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value:
                    ((period['videoSessionsRemaining'] as num) /
                            (period['videoSessionsTotal'] as num))
                        .clamp(0, 1)
                        .toDouble(),
                minHeight: 6,
                color: queued ? forest : lime,
                backgroundColor: queued
                    ? const Color(0xFFE3E9E3)
                    : const Color(0xFF3D5350),
                semanticsLabel: 'Live video sessions remaining',
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${period['videoSessionsReserved'] ?? 0} sessions reserved. Available balance excludes reservations and sessions already used.',
            style: TextStyle(
              fontSize: 12,
              color: queued ? muted : const Color(0xFFC6D6D0),
            ),
          ),
          if (period['environment'] == 'development') ...[
            const SizedBox(height: 14),
            Text(
              'Development test membership • no payment collected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: queued ? forest : lime,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _plan(Map<String, dynamic> plan) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan['name'] as String,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF2E8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  color: forest,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _price(plan['priceInPaise']),
            style: const TextStyle(
              fontSize: 34,
              letterSpacing: -1,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const Text(
            'for one month',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const Divider(height: 32),
          Text(
            '${plan['videoSessions']} live video sessions total',
            style: const TextStyle(fontWeight: FontWeight.w700, color: forest),
          ),
          const SizedBox(height: 14),
          ...(plan['features'] as List).map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, size: 18, color: forest),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      feature as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: null,
              child: Text('Checkout not connected'),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'JB FITNESS',
                style: TextStyle(
                  color: Color(0xFF245E48),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh membership',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'SUPPORT THAT FITS YOUR ROUTINE',
          style: TextStyle(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your membership',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'View your plan, membership dates and video-session balance.',
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  _notice(
                    'Membership could not load',
                    'Check your connection and try again. Your membership status has not been changed.',
                  ),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final catalogue = snapshot.data![0];
            final summary = snapshot.data![1];
            final current = summary['current'] as Map<String, dynamic>?;
            final next = summary['next'] as Map<String, dynamic>?;
            final history = (summary['history'] as List)
                .cast<Map<String, dynamic>>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current != null)
                  _period(current)
                else
                  _notice(
                    summary['status'] == 'expired'
                        ? 'Your membership has expired'
                        : 'No active membership',
                    summary['status'] == 'expired'
                        ? 'Your previous membership is listed below. A new verified purchase will be needed to reactivate paid features.'
                        : 'Compare the available plans below. Checkout has not been connected yet.',
                  ),
                if (next != null) _period(next, queued: true),
                const SizedBox(height: 20),
                const Text(
                  'Membership plans',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Higher plans include all lower-plan features. Session allowances are totals for the month.',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Saved habits and food-label logging are available. AI coaching and live call booking are still being built.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 12),
                ...(catalogue['plans'] as List)
                    .cast<Map<String, dynamic>>()
                    .map(_plan),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Text(
                    'Membership history',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  ...history.map(
                    (period) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${period['planName']} • ${period['status']}',
                      ),
                      subtitle: Text(
                        '${_date(period['startsAt'])} – ${_date(period['endsAt'])}${period['environment'] == 'development' ? '\nDevelopment test • unpaid' : ''}',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Development expiry and renewal rules are provisional. Checkout, automatic charging and call booking are not enabled. Audio calls are deferred.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.6,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
