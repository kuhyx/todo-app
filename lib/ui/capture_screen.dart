import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/note.dart';
import '../data/note_repository.dart';
import '../sync/github_client.dart';
import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';
import 'notes_list_screen.dart';
import 'settings_screen.dart';

/// The landing screen: an always-focused text box for jotting an idea.
///
/// Per the product goal "no interruptions, immediate", text is persisted
/// to local storage on *every* keystroke. A note row is created lazily on
/// the first character typed, then updated in place. The explicit "Save"
/// action finalises the current idea and clears the field for the next
/// one (remote sync will hook in here later).
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({required this.repository, super.key});

  final NoteRepository repository;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  static const _uuid = Uuid();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Id of the note currently being edited, or null before the first
  /// keystroke of a fresh draft.
  String? _draftId;
  DateTime? _draftCreatedAt;
  DateTime? _lastSavedAt;

  final SyncService _syncService = const SyncService();
  SyncSettings? _settings;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    SyncSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Opens the settings screen and adopts any saved configuration.
  Future<void> _openSettings() async {
    final current = _settings ?? await SyncSettings.load();
    if (!mounted) return;
    final result = await Navigator.of(context).push<SyncSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initial: current),
      ),
    );
    if (result != null && mounted) setState(() => _settings = result);
  }

  void _openList() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotesListScreen(repository: widget.repository),
      ),
    );
  }

  /// Runs a full sync, routing to settings first if not yet configured.
  Future<void> _sync() async {
    final settings = _settings ?? await SyncSettings.load();
    if (!settings.isConfigured) {
      _showSnack('Add a GitHub token in settings to enable sync');
      await _openSettings();
      return;
    }
    setState(() => _syncing = true);
    final client = GitHubClient(
      owner: settings.owner,
      repo: settings.repo,
      token: settings.token,
    );
    try {
      final result = await _syncService.sync(widget.repository, client);
      _showSnack('Synced: merged ${result.mergedDevices} device(s)');
    } catch (e) {
      _showSnack('Sync failed: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Persists the current text on every change. Creates the note row on
  /// the first non-empty keystroke so empty drafts never hit storage.
  Future<void> _onChanged(String text) async {
    if (_draftId == null) {
      if (text.isEmpty) return;
      _draftId = _uuid.v4();
      _draftCreatedAt = DateTime.now();
    }
    final now = DateTime.now();
    await widget.repository.upsert(
      Note(
        id: _draftId!,
        text: text,
        priority: Priority.none,
        createdAt: _draftCreatedAt!,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() => _lastSavedAt = now);
  }

  /// Finalises the current idea and resets the field for the next one.
  void _saveAndReset() {
    final hadText = _controller.text.trim().isNotEmpty;
    setState(() {
      _controller.clear();
      _draftId = null;
      _draftCreatedAt = null;
      _lastSavedAt = null;
    });
    _focusNode.requestFocus();
    if (hadText) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Idea saved locally'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture'),
        actions: [
          // Live count of stored notes, proving local persistence.
          StreamBuilder<List<Note>>(
            stream: widget.repository.watchNotes(),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(child: Text('$count saved')),
              );
            },
          ),
          IconButton(
            tooltip: 'Sync',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Notes',
            onPressed: _openList,
            icon: const Icon(Icons.list),
          ),
          IconButton(
            tooltip: 'Sync settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write your idea…',
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastSavedAt == null
                  ? 'Autosaves as you type'
                  : 'Saved locally at ${_formatTime(_lastSavedAt!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveAndReset,
        icon: const Icon(Icons.check),
        label: const Text('Save'),
      ),
    );
  }

  /// Formats a timestamp as zero-padded HH:mm:ss for the save indicator.
  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
