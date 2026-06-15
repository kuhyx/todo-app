import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  const CaptureScreen({required this.repository, this.httpClient, super.key});

  final NoteRepository repository;

  /// Injectable HTTP client for the sync path. Production leaves this null
  /// (the GitHubClient creates its own); tests pass a mock so the configured
  /// sync flow can be exercised without real network access.
  final http.Client? httpClient;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  static const _uuid = Uuid();

  /// Placeholder for the note's title line; selected on reset so the first
  /// keystroke replaces it.
  static const _titlePlaceholder = '<imperative title>';

  /// The structured scaffold pre-filled into every new note (see the
  /// `<work_backlog>` format). Pre-filling beats a hint because the em-dashes
  /// and labels are tedious to type on mobile — the user just fills the gaps.
  static const _template =
      '$_titlePlaceholder\n'
      '\n'
      'what — \n'
      'where — \n'
      'must —\n'
      '- \n'
      'nice —\n'
      '- \n'
      'out —\n'
      '- \n'
      'done — \n'
      'depends — \n'
      'estimate — \n'
      'refs — ';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Id of the note currently being edited, or null before the first
  /// keystroke of a fresh draft.
  String? _draftId;
  DateTime? _draftCreatedAt;
  DateTime? _lastSavedAt;

  /// Priority/status applied to the current draft. Chosen before or during
  /// typing; persisted on the first keystroke and on every later change.
  Priority _draftPriority = Priority.defaultValue;
  Status _draftStatus = Status.todo;

  final SyncService _syncService = const SyncService();
  SyncSettings? _settings;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _resetToTemplate();
    SyncSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  /// Loads the blank template into the field with the title placeholder
  /// selected, so typing immediately overwrites it. Setting the controller
  /// value programmatically does not fire [_onChanged], so this never
  /// persists a note on its own — only a real edit does.
  void _resetToTemplate() {
    _controller.value = const TextEditingValue(
      text: _template,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: _titlePlaceholder.length,
      ),
    );
  }

  /// Whether [text] is still the untouched scaffold (nothing worth saving).
  bool _isPristine(String text) => text.trim() == _template.trim();

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
        builder: (_) => SettingsScreen(
          initial: current,
          repository: widget.repository,
          httpClient: widget.httpClient,
        ),
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
      httpClient: widget.httpClient,
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
      // Don't persist an empty field or the untouched template scaffold —
      // a note is only created once the user actually fills something in.
      if (text.isEmpty || _isPristine(text)) return;
      _draftId = _uuid.v4();
      _draftCreatedAt = DateTime.now();
    }
    final now = DateTime.now();
    await widget.repository.upsert(
      Note(
        id: _draftId!,
        text: text,
        priority: _draftPriority,
        status: _draftStatus,
        createdAt: _draftCreatedAt!,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() => _lastSavedAt = now);
  }

  /// Applies a new priority to the draft, persisting immediately if a note
  /// row already exists (otherwise it is applied on the first keystroke).
  Future<void> _setPriority(Priority priority) async {
    setState(() => _draftPriority = priority);
    await _persistDraftMeta();
  }

  /// Applies a new status to the draft, persisting immediately if a note
  /// row already exists.
  Future<void> _setStatus(Status status) async {
    setState(() => _draftStatus = status);
    await _persistDraftMeta();
  }

  /// Re-saves the draft's metadata when only priority/status changed.
  Future<void> _persistDraftMeta() async {
    if (_draftId == null) return;
    final now = DateTime.now();
    await widget.repository.upsert(
      Note(
        id: _draftId!,
        text: _controller.text,
        priority: _draftPriority,
        status: _draftStatus,
        createdAt: _draftCreatedAt!,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() => _lastSavedAt = now);
  }

  /// Finalises the current idea and resets the field to a fresh template.
  void _saveAndReset() {
    // A note was actually persisted only if a draft row was created.
    final saved = _draftId != null;
    setState(() {
      _resetToTemplate();
      _draftId = null;
      _draftCreatedAt = null;
      _lastSavedAt = null;
      _draftPriority = Priority.defaultValue;
      _draftStatus = Status.todo;
    });
    _focusNode.requestFocus();
    if (saved) {
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
          StreamBuilder<int>(
            stream: widget.repository.watchCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
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
            // Pickers sit above the editor so the bottom-right Save FAB
            // never overlaps them.
            Row(
              children: [
                Expanded(
                  child: _MetaDropdown<Priority>(
                    label: 'Priority',
                    value: _draftPriority,
                    values: Priority.values,
                    labelOf: (p) => p.label,
                    onChanged: _setPriority,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetaDropdown<Status>(
                    label: 'Status',
                    value: _draftStatus,
                    values: Status.values,
                    labelOf: (s) => s.label,
                    onChanged: _setStatus,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            // Leave room so the Save FAB doesn't cover the save indicator.
            Padding(
              padding: const EdgeInsets.only(right: 96),
              child: Text(
                _lastSavedAt == null
                    ? 'Autosaves as you type'
                    : 'Saved locally at ${_formatTime(_lastSavedAt!)}',
                style: theme.textTheme.bodySmall,
              ),
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

/// A compact labelled dropdown for picking an enum value (priority/status).
///
/// Generic over the enum type [T] so the same control drives both pickers
/// without duplication; [labelOf] maps a value to its display string.
class _MetaDropdown<T> extends StatelessWidget {
  const _MetaDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final v in values)
              DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
