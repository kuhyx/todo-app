import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/github_device_auth.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/device_code_dialog.dart';

part 'github_mirror_screen_widget.dart';

class _GitHubMirrorScreenState extends State<GitHubMirrorScreen> {
  late final TextEditingController _owner = TextEditingController(
    text: widget.initial.owner,
  );
  late final TextEditingController _repo = TextEditingController(
    text: widget.initial.repo,
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.initial.token,
  );
  late final TextEditingController _clientId = TextEditingController(
    text: widget.initial.clientId,
  );

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
    final auth = GitHubDeviceAuth(
      clientId: clientId,
      httpClient: widget.httpClient,
    );
    try {
      final device = await auth.requestDeviceCode();
      if (!mounted) return;
      final token = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeviceCodeDialog(device: device, auth: auth),
      );
      if (token != null && token.isNotEmpty) {
        setState(() {
          _token.text = token;
          _status = 'Connected — syncing…';
        });
        await _current.save();
        await _syncAfterConnect();
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Could not start device flow: $e');
    } finally {
      auth.close();
    }
  }

  /// Runs a sync right after connecting so the user's notes download
  /// immediately and they get clear confirmation it worked.
  Future<void> _syncAfterConnect() async {
    final s = _current;
    try {
      final run = await runSync(
        widget.repository,
        s,
        appSettings: widget.appSettings.value,
        analytics: widget.analytics,
        httpClient: widget.httpClient,
        firebaseFactory: widget.firebaseFactory,
        stateStore: widget.stateStore,
      );
      widget.appSettings.value = widget.appSettings.value.adopt(
        run.appSettings,
      );
      if (mounted) {
        setState(
          () => _status =
              'Connected and synced (merged '
              '${run.syncResult.mergedDevices} device(s)). Your notes are '
              'up to date.',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Connected, but sync failed: $e');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final s = _current;
    final client = GitHubClient(
      owner: s.owner,
      repo: s.repo,
      token: s.token,
      httpClient: widget.httpClient,
    );
    try {
      final ok = await client.canAccessRepo();
      setState(
        () => _status = ok
            ? 'Connected — repo is reachable.'
            : 'Could not access ${s.owner}/${s.repo}. Check token scope.',
      );
    } on Exception catch (e) {
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
      appBar: AppBar(title: const Text('Advanced sync (GitHub)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Authorize in your browser — no token to paste. Syncs to '
            'kuhyx/syncs by default.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _connectGitHub,
              icon: const Icon(Icons.login),
              label: const Text('Connect GitHub'),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(
              labelText: 'OAuth App client id',
              helperText: 'Leave as the baked-in default unless self-hosting',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Access token (fallback)',
              helperText: 'Contents: read/write on the sync repo only',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
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
              const SizedBox(width: 12),
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
