import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/github_client.dart';
import '../sync/github_device_auth.dart';
import '../sync/sync_settings.dart';

/// Settings screen for GitHub sync configuration.
///
/// Primary path: the "Connect GitHub" button runs the OAuth **device flow**
/// (authorize in a browser, no token pasting). The manual token field
/// remains as a fallback.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.initial, super.key});

  final SyncSettings initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _owner =
      TextEditingController(text: widget.initial.owner);
  late final TextEditingController _repo =
      TextEditingController(text: widget.initial.repo);
  late final TextEditingController _token =
      TextEditingController(text: widget.initial.token);
  late final TextEditingController _clientId =
      TextEditingController(text: widget.initial.clientId);

  bool _testing = false;
  String? _status;

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _token.dispose();
    _clientId.dispose();
    super.dispose();
  }

  SyncSettings get _current => SyncSettings(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        token: _token.text.trim(),
        clientId: _clientId.text.trim(),
      );

  /// Runs the OAuth device flow and, on success, fills in the token field.
  Future<void> _connectGitHub() async {
    final clientId = _clientId.text.trim();
    if (clientId.isEmpty) {
      setState(() => _status = 'Enter the OAuth App client id first.');
      return;
    }
    final auth = GitHubDeviceAuth(clientId: clientId);
    try {
      final device = await auth.requestDeviceCode();
      if (!mounted) return;
      final token = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeviceCodeDialog(device: device, auth: auth),
      );
      if (token != null && token.isNotEmpty) {
        setState(() {
          _token.text = token;
          _status = 'Connected via GitHub. Token saved on Save.';
        });
        await _current.save();
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not start device flow: $e');
    } finally {
      auth.close();
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final s = _current;
    final client = GitHubClient(owner: s.owner, repo: s.repo, token: s.token);
    try {
      final ok = await client.canAccessRepo();
      setState(() => _status = ok
          ? 'Connected — repo is reachable.'
          : 'Could not access ${s.owner}/${s.repo}. Check token scope.');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final s = _current;
    await s.save();
    if (mounted) Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _owner,
            decoration: const InputDecoration(
              labelText: 'GitHub owner',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repo,
            decoration: const InputDecoration(
              labelText: 'Repository name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Connect with GitHub',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(
              labelText: 'OAuth App client id',
              helperText: 'From your GitHub OAuth App (device flow enabled)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _connectGitHub,
            icon: const Icon(Icons.login),
            label: const Text('Connect GitHub'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Or paste a token (fallback)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Access token (fine-grained PAT)',
              helperText: 'Contents: read/write on the sync repo only',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Test connection'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Dialog shown during the device flow: displays the user code, opens the
/// verification page, and polls until authorized — popping the token (or
/// null if cancelled / failed).
class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({required this.device, required this.auth});

  final DeviceCodeResponse device;
  final GitHubDeviceAuth auth;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    try {
      final token = await widget.auth.pollForToken(widget.device);
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _openPage() async {
    await Clipboard.setData(ClipboardData(text: widget.device.userCode));
    await launchUrl(
      Uri.parse(widget.device.verificationUri),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Authorize on GitHub'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter this code on GitHub:'),
          const SizedBox(height: 8),
          SelectableText(
            widget.device.userCode,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (_error == null)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Waiting for authorization…')),
              ],
            )
          else
            Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _openPage,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open GitHub & copy code'),
        ),
      ],
    );
  }
}
