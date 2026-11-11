import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:github_device_auth/github_device_auth.dart';
import 'package:http/http.dart' as http;
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/status_cue.dart';

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
  StatusCue? _status;

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
      return _show(
        const StatusCue(
          Icons.key_off,
          'Enter the OAuth App client id first.',
          error: true,
        ),
      );
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
          _status = const StatusCue(Icons.sync, 'Connected — syncing…');
        });
        await _current.save();
        await _syncAfterConnect();
      }
    } on Exception catch (e) {
      _show(StatusCue.failed('Could not start device flow: $e'));
    } finally {
      auth.close();
    }
  }

  /// Syncs right after connecting so notes download at once, with a cue.
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
      _show(
        StatusCue.ok(
          'Connected and synced (merged '
          '${run.syncResult.mergedDevices} device(s)). Your notes are '
          'up to date.',
        ),
      );
    } on Exception catch (e) {
      _show(
        StatusCue(
          Icons.sync_problem,
          'Connected, but sync failed: $e',
          error: true,
        ),
      );
    }
  }

  /// Shows [cue] as the screen's latest result, if still mounted.
  void _show(StatusCue cue) {
    if (mounted) setState(() => _status = cue);
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
      _show(
        ok
            ? const StatusCue.ok('Connected — repo is reachable.')
            : StatusCue(
                Icons.lock,
                'Could not access ${s.owner}/${s.repo}. Check token scope.',
                error: true,
              ),
      );
    } on Exception catch (e) {
      _show(StatusCue.failed('Error: $e'));
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
      appBar: AppBar(
        title: const Icon(
          Icons.cloud_sync,
          semanticLabel: 'Advanced sync (GitHub)',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.filled(
              onPressed: _connectGitHub,
              icon: const Icon(Icons.login, semanticLabel: 'Connect GitHub'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _owner,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person, semanticLabel: 'GitHub owner'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repo,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.folder, semanticLabel: 'Repository name'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.key, semanticLabel: 'OAuth App client id'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.vpn_key,
                semanticLabel: 'Access token (fallback)',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.wifi_tethering,
                        semanticLabel: 'Test connection',
                      ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _save,
                icon: const Icon(Icons.save, semanticLabel: 'Save'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            StatusCueView(_status!),
          ],
        ],
      ),
    );
  }
}
