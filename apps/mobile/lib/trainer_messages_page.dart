import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'stitch_ui.dart';
import 'workout_pages.dart' show requestId;

class TrainerMessagesPage extends StatefulWidget {
  final AccountController account;
  const TrainerMessagesPage({super.key, required this.account});
  @override
  State<TrainerMessagesPage> createState() => _TrainerMessagesPageState();
}

class _TrainerMessagesPageState extends State<TrainerMessagesPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _conversations;
  Map<String, dynamic>? _thread, _pending;
  final _text = TextEditingController();
  String? _peerId, _error;
  bool _busy = false, _sharing = false;
  int _version = 0;
  late final String? _session;

  @override
  void initState() {
    super.initState();
    _session = widget.account.token;
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _version++;
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  bool get _sameAccount => mounted && widget.account.token == _session;
  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => widget.account.api.request(
    '/me/trainer-messages$path',
    token: _session,
    method: method,
    body: body,
  );

  Future<void> _load({bool older = false}) async {
    if (_busy || !_sameAccount) return;
    final version = ++_version;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final peer = _peerId;
      final before = older ? (_thread?['nextBefore']) : null;
      final data = await _request(
        peer == null ? '' : '/$peer${before == null ? '' : '?before=$before'}',
      );
      if (!_sameAccount || version != _version) return;
      setState(() {
        if (peer == null) {
          _conversations = (data['conversations'] as List)
              .cast<Map<String, dynamic>>();
        } else {
          if (older) {
            data['messages'] = [
              ...data['messages'],
              ...(_thread?['messages'] as List? ?? []),
            ];
          }
          _thread = data;
        }
      });
    } catch (e) {
      if (_sameAccount && version == _version) {
        setState(() {
          _error = e is ApiFailure
              ? e.message
              : 'Messages could not load. Please retry.';
        });
      }
    } finally {
      if (_sameAccount && version == _version) setState(() => _busy = false);
    }
  }

  void _open(String? id) {
    if (_busy) return;
    setState(() {
      _peerId = id;
      _thread = null;
      _pending = null;
      _sharing = false;
      _text.clear();
      _error = null;
    });
    _load();
  }

  Future<void> _send() async {
    if (_busy || !_sameAccount || _peerId == null) return;
    final body =
        _pending ??
        {
          'text': _text.text.trim(),
          'requestId': requestId(),
          'shareWithTrainer': true,
        };
    if ((body['text'] as String).isEmpty || !_sharing) return;
    setState(() {
      _busy = true;
      _error = null;
      _pending = body;
    });
    var saved = false;
    try {
      await _request('/$_peerId', method: 'POST', body: body);
      if (!_sameAccount) return;
      setState(() {
        _pending = null;
        _text.clear();
      });
      saved = true;
    } catch (e) {
      if (_sameAccount) {
        setState(() {
          _error = e is ApiFailure
              ? e.message
              : 'Delivery was not confirmed. Retry the same message.';
        });
      }
    } finally {
      if (_sameAccount) setState(() => _busy = false);
    }
    if (saved) await _load();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'This removes its saved messages for you and this trainer. Your AI chat and workout records stay saved. Sending a new message starts a new conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear messages'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_sameAccount || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var cleared = false;
    try {
      await _request('/$_peerId', method: 'DELETE');
      if (!_sameAccount) return;
      setState(() {
        _thread = null;
        _pending = null;
        _sharing = false;
        _text.clear();
        _peerId = null;
      });
      cleared = true;
    } catch (e) {
      if (_sameAccount) {
        setState(() {
          _error = e is ApiFailure
              ? e.message
              : 'Messages could not be cleared.';
        });
      }
    } finally {
      if (_sameAccount) setState(() => _busy = false);
    }
    if (cleared) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Message your trainer'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Refresh trainer messages',
          icon: const Icon(Icons.refresh),
        ),
        if (_peerId != null)
          IconButton(
            onPressed: _busy || _pending != null ? null : _clear,
            tooltip: 'Clear trainer conversation',
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const StitchPageHeading(
                title: 'A question for\nyour trainer.',
                eyebrow: 'Personal support',
              ),
              const SizedBox(height: 12),
              const Text(
                'For questions that need a person. Your trainer replies when available. Tap refresh for new replies.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              if (_peerId != null)
                TextButton.icon(
                  onPressed: _busy || _pending != null
                      ? null
                      : () => _open(null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('All conversations'),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: brandRed)),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Reload messages'),
                ),
              ],
              if (_peerId == null && _conversations?.isEmpty == true)
                const StitchCard(
                  child: Text(
                    'No trainer assigned yet. The owner can assign a trainer to your account.',
                  ),
                ),
              if (_peerId == null) ...[
                for (final conversation
                    in _conversations ?? <Map<String, dynamic>>[])
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: StitchCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.support_agent_rounded,
                          color: brandRed,
                        ),
                        title: Text(conversation['name'] as String),
                        subtitle: Text(
                          conversation['assigned'] == true
                              ? 'Assigned trainer'
                              : 'Previous trainer · history only',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy
                            ? null
                            : () => _open(conversation['id'] as String),
                      ),
                    ),
                  ),
              ],
              if (_thread != null) ...[
                Text(
                  _thread!['peer']['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (_thread!['nextBefore'] != null)
                  TextButton(
                    onPressed: _busy ? null : () => _load(older: true),
                    child: const Text('Load older messages'),
                  ),
                if ((_thread!['messages'] as List).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Start with a question, such as “Can you check my squat technique at our next session?”',
                    ),
                  ),
                for (final message in _thread!['messages'] as List)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: message['senderId'] == widget.account.user?['id']
                          ? brandRed.withValues(alpha: .06)
                          : Colors.white,
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['senderId'] == widget.account.user?['id']
                              ? 'You'
                              : 'Trainer',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: brandRed,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(message['text'] as String),
                        const SizedBox(height: 8),
                        Text(
                          DateTime.parse(message['createdAt'] as String)
                              .toLocal()
                              .toString()
                              .substring(0, 16),
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                if (_thread!['canSend'] != true)
                  Text(
                    _thread!['assigned'] != true
                        ? 'This trainer is no longer assigned. Your saved conversation is read-only.'
                        : 'An active membership is required to send messages. Your history is still available.',
                    style: const TextStyle(color: muted),
                  ),
                if (_thread!['canSend'] == true) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sharing,
                    onChanged: _busy || _pending != null
                        ? null
                        : (v) => setState(() => _sharing = v ?? false),
                    title: const Text('Share messages with this trainer'),
                    subtitle: const Text(
                      'Only this conversation is shared. Your profile and AI chat keep their separate sharing settings.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  TextField(
                    controller: _text,
                    enabled: !_busy && _pending == null,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Your message',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy || !_sharing ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      _pending == null ? 'Send message' : 'Retry same message',
                    ),
                  ),
                  if (_pending != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Delivery has not been confirmed. Retry keeps the same reference to avoid a duplicate.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
