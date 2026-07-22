import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/backlog_export.dart';
import 'package:todo/sync/github_device_auth.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings screen for GitHub sync configuration and note backup.
///
/// Primary sync path: the "Connect GitHub" button runs the OAuth **device
/// flow** (authorize in a browser, no token pasting). The manual token field
/// remains as a fallback. The Backup section exports/imports all notes as a
/// single Markdown file (see [NotesMarkdown]).
class SettingsScreen extends StatefulWidget {
  /// Creates a [SettingsScreen] pre-filled with [initial] settings.
  const SettingsScreen({
    required this.initial,
    required this.repository,
    this.httpClient,
    super.key,
  });

  /// The sync settings loaded when this screen was opened.
  final SyncSettings initial;

  /// The store backup export/import reads from and writes to.
  final NoteRepository repository;

  /// Optional HTTP client for the GitHub calls (test-connection and device
  /// flow). Injected by tests; production uses each client's default.
  final http.Client? httpClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
        builder: (_) => _DeviceCodeDialog(device: device, auth: auth),
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
    final client = GitHubClient(
      owner: s.owner,
      repo: s.repo,
      token: s.token,
      httpClient: widget.httpClient,
    );
    try {
      final result = await const SyncService().sync(widget.repository, client);
      if (mounted) {
        setState(
          () => _status =
              'Connected and synced (merged ${result.mergedDevices} '
              'device(s)). Your notes are up to date.',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Connected, but sync failed: $e');
    } finally {
      client.close();
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

  /// Exports every note to a single Markdown file. On mobile this opens the
  /// system share sheet; on desktop it writes the canonical `~/todo/
  /// BACKLOG.md` so a future tool/agent has a stable path to read.
  Future<void> _export() async {
    try {
      final notes = await widget.repository.listNotes();
      final markdown = NotesMarkdown.export(notes);

      final outcome = await exportBacklog(markdown, notes.length);
      if (mounted) setState(() => _status = outcome);
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Export failed: $e');
    }
  }

  /// Imports notes from a user-picked Markdown file, merging by id so a
  /// stale backup never clobbers a newer local edit (see
  /// [NoteRepository.importNotes]).
  Future<void> _import() async {
    try {
      const group = XTypeGroup(
        label: 'Markdown',
        extensions: ['md', 'markdown', 'txt'],
        // UTIs/MIME so the picker accepts the file on iOS/Android too.
        uniformTypeIdentifiers: ['net.daringfireball.markdown', 'public.text'],
        mimeTypes: ['text/markdown', 'text/plain'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return; // user cancelled
      final content = await file.readAsString();

      final notes = NotesMarkdown.parse(content);
      final outcome = await widget.repository.importNotes(notes);
      if (mounted) {
        setState(
          () => _status =
              'Imported ${outcome.total}: ${outcome.added} new, '
              '${outcome.updated} updated, ${outcome.skipped} unchanged',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connect to GitHub',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Authorize in your browser — no token to paste. Syncs to '
            'kuhyx/syncs by default.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _connectGitHub,
            icon: const Icon(Icons.login),
            label: const Text('Connect GitHub'),
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
          const SizedBox(height: 8),
          // Manual escape hatches — most users never open this.
          ExpansionTile(
            title: const Text('Advanced'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              TextField(
                controller: _clientId,
                decoration: const InputDecoration(
                  labelText: 'OAuth App client id',
                  helperText:
                      'Leave as the baked-in default unless self-hosting',
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
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
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
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Backup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Export all notes to a single Markdown file, or import/merge a '
            'file back (matching ids are merged, never duplicated).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.upload_file),
                label: const Text('Export notes'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.download),
                label: const Text('Import notes'),
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
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      final token = await widget.auth.pollForToken(widget.device);
      if (mounted) Navigator.of(context).pop(token);
    } on Exception catch (e) {
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
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
