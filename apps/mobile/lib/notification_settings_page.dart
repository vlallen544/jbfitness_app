import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'device_services.dart';
import 'stitch_ui.dart';

class NotificationSettingsPage extends StatefulWidget {
  final DeviceServices services;
  const NotificationSettingsPage({super.key, required this.services});
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  bool _showToken = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.services.refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications & diagnostics')),
    body: ListenableBuilder(
      listenable: widget.services,
      builder: (context, _) {
        final service = widget.services;
        final allowed =
            service.permission == PushPermission.granted ||
            service.permission == PushPermission.provisional;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const StitchPageHeading(
                  title: 'Stay in the loop.',
                  eyebrow: 'Your preferences',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose whether this phone receives updates and helps improve app reliability.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 24),
                if (!service.supported) ...[
                  const StitchCard(
                    child: Text(
                      'Device notifications and crash reporting are not configured for this platform or preview yet.',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (service.busy) const LinearProgressIndicator(),
                if (service.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      service.error!,
                      style: const TextStyle(color: brandRed),
                    ),
                  ),
                if (service.supported && !service.ready)
                  OutlinedButton.icon(
                    onPressed: service.busy ? null : service.start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry device setup'),
                  ),
                StitchCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(
                          Icons.notifications_outlined,
                          color: brandRed,
                        ),
                        title: const Text('Push notifications'),
                        subtitle: Text(
                          !service.signedIn
                              ? 'Sign in to enable notifications on this phone.'
                              : service.enabled && allowed
                              ? (service.token == null
                                    ? 'Waiting for device registration.'
                                    : 'Enabled on this phone.')
                              : 'Enable updates on this phone.',
                        ),
                        value: service.enabled && allowed,
                        onChanged:
                            service.ready && service.signedIn && !service.busy
                            ? service.setNotifications
                            : null,
                      ),
                      const Divider(height: 28),
                      const Text(
                        'Scheduled reminders',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Workout, food and habit reminder schedules are coming soon.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                StitchCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(
                          Icons.bug_report_outlined,
                          color: brandRed,
                        ),
                        title: const Text('Share crash reports'),
                        subtitle: const Text(
                          'Optional technical crash reports help us fix app errors.',
                        ),
                        value: service.diagnostics,
                        onChanged: service.ready && !service.busy
                            ? service.setDiagnostics
                            : null,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We do not attach your profile, photos, food logs, chat messages or notification token to crash reports.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                if (kDebugMode && service.supported) ...[
                  const SizedBox(height: 18),
                  StitchCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const StitchPill('DEMO TEST TOOLS', red: false),
                        const SizedBox(height: 12),
                        const Text(
                          'Firebase test notification',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enable push notifications, then copy this device’s token into Firebase Console → Messaging → Send test message. Automated trainer and membership alerts are not connected yet.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: service.token == null || service.busy
                              ? null
                              : () => setState(() => _showToken = !_showToken),
                          icon: const Icon(Icons.key_outlined),
                          label: Text(
                            _showToken
                                ? 'Hide device token'
                                : 'Show device token',
                          ),
                        ),
                        if (_showToken && service.token != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            service.token!,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: service.token!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Device token copied.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 17),
                            label: const Text('Copy device token'),
                          ),
                        ],
                        TextButton.icon(
                          onPressed: service.ready && !service.busy
                              ? service.refresh
                              : null,
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('Refresh device status'),
                        ),
                        TextButton.icon(
                          onPressed:
                              service.ready &&
                                  service.diagnostics &&
                                  !service.busy
                              ? () async {
                                  await service.sendDiagnosticTest();
                                  if (context.mounted &&
                                      service.error == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Diagnostic test recorded. Reports appear after the device syncs.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.bug_report_outlined, size: 17),
                          label: const Text('Record diagnostic test'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    ),
  );
}
