import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/note.dart';
import '../data/note_repository.dart';
import '../data/note_template.dart';
import 'package:crdt_sync/crdt_sync.dart';
import '../sync/local_backup.dart';
import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';
import 'note_editor.dart';
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
  const CaptureScreen({
    required this.repository,
    this.httpClient,
    this.localBackup,
    super.key,
  });

  final NoteRepository repository;

  /// Injectable HTTP client for the sync path. Production leaves this null
  /// (the GitHubClient creates its own); tests pass a mock so the configured
  /// sync flow can be exercised without real network access.
  final http.Client? httpClient;

  /// Injectable local-disk backup. Production leaves this null (a platform
  /// file-backed instance is created); tests pass a fake with in-memory IO.
  final LocalBackup? localBackup;

  /// How long focus must stay lost before a background sync fires. Public so
  /// tests can pump exactly past it.
  static const autoSyncDebounce = Duration(seconds: 5);

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();

  /// Single-flight guard so a launch sync and a background sync never overlap.
  bool _autoSyncing = false;

  /// Keeps an always-current Markdown backup on local disk and recovers from
  /// it on launch (third durability layer beside sync + Android Auto Backup).
  late final LocalBackup _localBackup;
  StreamSubscription<void>? _changesSub;

  /// Latest assembled text from the editor; persisted on change and re-saved
  /// when only priority/status change.
  String _draftText = '';

  /// Bumped on save to recreate the editor with a fresh, empty template.
  int _editorGeneration = 0;

  /// Id of the note currently being edited, or null before the first
  /// keystroke of a fresh draft.
  String? _draftId;
  DateTime? _draftCreatedAt;

  /// Time of the last local save, shown in the tiny save indicator. A notifier
  /// (not a `setState` field) so a keystroke updates only that one line of text
  /// instead of rebuilding the AppBar, dropdowns, and editor every character.
  final ValueNotifier<DateTime?> _lastSavedAt = ValueNotifier<DateTime?>(null);

  /// Priority/status applied to the current draft. Chosen before or during
  /// typing; persisted on the first keystroke and on every later change.
  Priority _draftPriority = Priority.defaultValue;
  Status _draftStatus = Status.todo;

  final SyncService _syncService = const SyncService();
  SyncSettings? _settings;
  bool _syncing = false;

  /// Outcome of the most recent sync attempt (manual or automatic), driving
  /// the tiny status line under the editor. Persisted so a failure that
  /// happened just before the app closed is still visible on next launch.
  final ValueNotifier<SyncStatus?> _lastSync = ValueNotifier<SyncStatus?>(null);

  /// Debounces focus-loss sync triggers so desktop alt-tab flicker doesn't
  /// hammer GitHub with a request per focus change.
  Timer? _autoSyncDebounce;

  static const _kLastSyncTime = 'sync.lastTime';
  static const _kLastSyncOk = 'sync.lastOk';
  static const _kLastSyncDetail = 'sync.lastDetail';

  /// Hides the Priority/Status row while the editor's own bare-guided chrome
  /// (template/mode selectors) is also hidden, so the two stay in lockstep.
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localBackup =
        widget.localBackup ?? _platformLocalBackup(widget.repository);
    // Recover from the local backup first (covers an empty DB after a wipe),
    // then keep the backup current as notes change. The change tick is O(1) per
    // write; the backup pulls the notes itself only when its debounce fires.
    _recoverFromBackup();
    _changesSub = widget.repository.changes.listen(
      (_) => _localBackup.schedule(),
    );
    // Also refresh the on-disk backup once on launch (the change tick only
    // fires on writes), so a deleted/stale BACKLOG.md is regenerated even if
    // the user makes no edits this session.
    _localBackup.schedule();
    _restoreSyncStatus();
    SyncSettings.load().then((s) {
      if (!mounted) return;
      setState(() => _settings = s);
      _autoSync(); // pull on launch so a reinstalled device recovers its notes
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncDebounce?.cancel();
    _changesSub?.cancel();
    _localBackup.dispose();
    _lastSavedAt.dispose();
    _lastSync.dispose();
    super.dispose();
  }

  /// Reloads the persisted last-sync outcome so the status line survives a
  /// restart (a failure just before closing must not disappear).
  Future<void> _restoreSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final time = DateTime.tryParse(prefs.getString(_kLastSyncTime) ?? '');
    if (!mounted || time == null || _lastSync.value != null) return;
    _lastSync.value = SyncStatus(
      time: time,
      ok: prefs.getBool(_kLastSyncOk) ?? true,
      detail: prefs.getString(_kLastSyncDetail) ?? '',
    );
  }

  /// Records a sync outcome in the UI notifier and persists it.
  Future<void> _recordSyncStatus({
    required bool ok,
    required String detail,
  }) async {
    final status = SyncStatus(time: DateTime.now(), ok: ok, detail: detail);
    if (mounted) _lastSync.value = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSyncTime, status.time.toIso8601String());
    await prefs.setBool(_kLastSyncOk, ok);
    await prefs.setString(_kLastSyncDetail, detail);
  }

  /// Human-readable one-liner for a sync outcome, shared by the snackbar and
  /// the status line. Skipped files are called out so a peer device silently
  /// dropping out of the merge is visible.
  static String _describe(SyncResult result) {
    final skipped = result.skippedFiles.length;
    return 'merged ${result.mergedDevices} device(s)'
        '${skipped == 0 ? '' : ', skipped $skipped unreadable file(s)'}';
  }

  /// Restores notes from the local backup file, but only into an empty DB so a
  /// stale backup never clobbers existing notes (merge-by-id stays safe too).
  Future<void> _recoverFromBackup() async {
    final existing = await widget.repository.listNotes();
    if (existing.isNotEmpty) return;
    final recovered = await _localBackup.recover();
    if (recovered.isNotEmpty) await widget.repository.importNotes(recovered);
  }

  // coverage:ignore-start
  // Platform file IO for the local backup: BACKLOG.md under ~/todo on desktop
  // (the path the user's workflow already reads), or the app documents dir on
  // mobile (which Android Auto Backup includes). Exercised by running the app;
  // tests inject an in-memory LocalBackup instead.
  static LocalBackup _platformLocalBackup(NoteRepository repository) {
    Future<File> backupFile() async {
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        return File('${dir.path}/todo-backlog.md');
      }
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final dir = Directory('$home/todo')..createSync(recursive: true);
      return File('${dir.path}/BACKLOG.md');
    }

    return LocalBackup(
      fetch: repository.listNotes,
      reader: () async {
        final file = await backupFile();
        return file.existsSync() ? file.readAsString() : null;
      },
      writer: (markdown) async => (await backupFile()).writeAsString(markdown),
    );
  }
  // coverage:ignore-end

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Push on background so the remote (the durable store) stays near-current.
    if (state == AppLifecycleState.paused) {
      // Immediate: Android may kill the app before a debounce timer fires.
      _autoSyncDebounce?.cancel();
      _autoSync();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Focus loss — the only background signal Flutter Linux delivers
      // reliably (`paused` rarely arrives on desktop). Debounced so alt-tab
      // flicker doesn't fire a request per focus change.
      _autoSyncDebounce?.cancel();
      _autoSyncDebounce = Timer(CaptureScreen.autoSyncDebounce, _autoSync);
    }
  }

  /// Best-effort background sync: no snackbar, skips when unconfigured, and
  /// never overlaps itself. Failures are not swallowed silently — the outcome
  /// lands in the status line so drift can't go unnoticed for days.
  Future<void> _autoSync() async {
    final settings = _settings;
    if (_autoSyncing || settings == null || !settings.isConfigured) return;
    _autoSyncing = true;
    final client = GitHubClient(
      owner: settings.owner,
      repo: settings.repo,
      token: settings.token,
      httpClient: widget.httpClient,
    );
    try {
      final result = await _syncService.sync(widget.repository, client);
      await _recordSyncStatus(ok: true, detail: _describe(result));
    } catch (e) {
      // Offline or a transient GitHub error: still no snackbar (this path
      // must never interrupt capture), but the status line shows it.
      await _recordSyncStatus(ok: false, detail: '$e');
    } finally {
      client.close();
      _autoSyncing = false;
    }
  }

  /// Opens the settings screen and adopts any saved configuration.
  Future<void> _openSettings() async {
    final current = _settings ?? await SyncSettings.load();
    if (!mounted) return;
    await Navigator.of(context).push<SyncSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: current,
          repository: widget.repository,
          httpClient: widget.httpClient,
        ),
      ),
    );
    if (!mounted) return;
    // Always reload from storage: a device-flow "Connect" saves the token
    // without popping a result, so relying on the pop value would miss it and
    // leave us syncing with stale (token-less) settings.
    final fresh = await SyncSettings.load();
    setState(() => _settings = fresh);
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
      final detail = _describe(result);
      await _recordSyncStatus(ok: true, detail: detail);
      _showSnack('Synced: $detail');
    } catch (e) {
      await _recordSyncStatus(ok: false, detail: '$e');
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
    _draftText = text;
    if (_draftId == null) {
      // A note is only created once the user actually fills something in, so
      // an empty template (no section typed yet) never hits storage.
      if (text.trim().isEmpty) return;
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
    if (mounted) _lastSavedAt.value = now;
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
        text: _draftText,
        priority: _draftPriority,
        status: _draftStatus,
        createdAt: _draftCreatedAt!,
        updatedAt: now,
      ),
    );
    if (mounted) _lastSavedAt.value = now;
  }

  /// Finalises the current idea and resets the field to a fresh template.
  void _saveAndReset() {
    // A note was actually persisted only if a draft row was created.
    final saved = _draftId != null;
    setState(() {
      _editorGeneration++; // recreate the editor with a fresh template
      _draftText = '';
      _draftId = null;
      _draftCreatedAt = null;
      _draftPriority = Priority.defaultValue;
      _draftStatus = Status.todo;
      _chromeVisible = true;
    });
    _lastSavedAt.value = null;
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
            // never overlaps them. Hidden together with the editor's own
            // chrome while the bare guided stepper or its entry wizard is up,
            // so the top of the screen stays free of noise.
            if (_chromeVisible) ...[
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
            ],
            Expanded(
              child: NoteEditor(
                key: ValueKey(_editorGeneration),
                initialTemplate: NoteTemplate.defaultTemplate,
                initialMode: NoteEditorMode.raw,
                priority: _draftPriority,
                onPriorityChanged: _setPriority,
                onChromeVisibleChanged: (visible) =>
                    setState(() => _chromeVisible = visible),
                autofocus: true,
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 8),
            // Leave room so the Save FAB doesn't cover the indicators.
            Padding(
              padding: const EdgeInsets.only(right: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: _lastSavedAt,
                    builder: (context, savedAt, _) => Text(
                      savedAt == null
                          ? 'Autosaves as you type'
                          : 'Saved locally at ${_formatTime(savedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  ValueListenableBuilder<SyncStatus?>(
                    valueListenable: _lastSync,
                    builder: (context, status, _) {
                      if (status == null) return const SizedBox.shrink();
                      return Text(
                        '${status.ok ? 'Synced' : 'Sync failed'} at '
                        '${_formatTime(status.time)} · ${status.detail}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: status.ok ? null : theme.colorScheme.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _chromeVisible
          ? FloatingActionButton.extended(
              onPressed: _saveAndReset,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            )
          : null,
    );
  }

  /// Formats a timestamp as zero-padded HH:mm:ss for the save indicator.
  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// Outcome of a sync attempt, shown in the capture screen's status line.
class SyncStatus {
  const SyncStatus({
    required this.time,
    required this.ok,
    required this.detail,
  });

  /// When the attempt finished.
  final DateTime time;

  /// Whether the sync succeeded.
  final bool ok;

  /// One-line summary: merged/skipped counts on success, the error otherwise.
  final String detail;
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
