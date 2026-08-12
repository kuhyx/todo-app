import 'dart:async';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/frame_stats.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/local_backup_factory.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/note_editor.dart';
import 'package:todo/ui/notes_list_screen.dart';
import 'package:todo/ui/settings_screen.dart';
import 'package:uuid/uuid.dart';

/// The landing screen: an always-focused text box for jotting an idea.
///
/// Per the product goal "no interruptions, immediate", text is persisted
/// to local storage on *every* keystroke. A note row is created lazily on
/// the first character typed, then updated in place. The "new note" action
/// finalises the current idea and clears the field for the next one.
class CaptureScreen extends StatefulWidget {
  /// Creates a [CaptureScreen] backed by [repository].
  const CaptureScreen({
    required this.repository,
    required this.appSettings,
    this.analytics,
    this.httpClient,
    this.localBackup,
    this.firebaseFactory,
    this.stateStore,
    super.key,
  });

  /// The store the captured note is persisted to on every keystroke.
  final NoteRepository repository;

  /// App-wide preferences, currently just `advancedMode`: whether the
  /// priority/status row and the routine save/sync status line are shown.
  /// A sync failure is always surfaced regardless of this flag.
  final ValueNotifier<AppSettings> appSettings;

  /// Interaction-only usage analytics (taps, navigation, sync outcomes —
  /// never note text). Null in tests that don't exercise it, so the prefs
  /// round-trip `logEvent` does on every call never has to be awaited by a
  /// test that didn't ask for it.
  final AnalyticsService? analytics;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

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

  /// When this session started, for the duration on the `app_close` event.
  final DateTime _sessionStart = DateTime.now();

  /// Logs an interaction event without blocking the caller on the prefs
  /// round-trip `AnalyticsService.logEvent` does. A no-op when
  /// [CaptureScreen.analytics] is null (tests that don't exercise it).
  void _logEvent(String name, {Map<String, Object?> params = const {}}) {
    final analytics = widget.analytics;
    if (analytics == null) return;
    unawaited(
      analytics.logEvent(
        AnalyticsEvent(name: name, timestamp: DateTime.now(), params: params),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _logEvent('app_open');
    WidgetsBinding.instance.addObserver(this);
    _localBackup =
        widget.localBackup ?? _platformLocalBackup(widget.repository);
    // Recover from the local backup first (covers an empty DB after a wipe),
    // then keep the backup current as notes change. The change tick is O(1) per
    // write; the backup pulls the notes itself only when its debounce fires.
    unawaited(_recoverFromBackup());
    _changesSub = widget.repository.changes.listen(
      (_) => _localBackup.schedule(),
    );
    // Also refresh the on-disk backup once on launch (the change tick only
    // fires on writes), so a deleted/stale BACKLOG.md is regenerated even if
    // the user makes no edits this session.
    _localBackup.schedule();
    unawaited(_restoreSyncStatus());
    unawaited(
      SyncSettings.load().then((s) {
        if (!mounted) return;
        setState(() => _settings = s);
        // Pull on launch so a reinstalled device recovers its notes.
        unawaited(_autoSync());
      }),
    );
  }

  @override
  void dispose() {
    _logEvent(
      'app_close',
      params: {
        'durationMs': DateTime.now().difference(_sessionStart).inMilliseconds,
      },
    );
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncDebounce?.cancel();
    unawaited(_changesSub?.cancel());
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
  ///
  /// Firebase-vs-GitHub-only is called out too, and first, because it used
  /// to read identically either way: "Synced ... merged N device(s))" while
  /// disconnected from Firebase looked exactly like success, which is
  /// precisely how a desktop stuck syncing over the GitHub mirror alone
  /// went unnoticed for days.
  static String _describe(SyncResult result) {
    final skipped = result.skippedFiles.length;
    final backend = result.firebaseConnected
        ? ''
        : 'GitHub-only (Firebase not connected) — ';
    return '$backend'
        'merged ${result.mergedDevices} device(s)'
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
  static LocalBackup _platformLocalBackup(NoteRepository repository) =>
      createLocalBackup(repository);
  // coverage:ignore-end

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Push on background so the remote (the durable store) stays near-current.
    if (state == AppLifecycleState.paused) {
      // The realistic "user left the app" signal on Android: the process may
      // be killed right after, so dispose() is not guaranteed to run.
      _logEvent(
        'app_close',
        params: {
          'durationMs': DateTime.now().difference(_sessionStart).inMilliseconds,
        },
      );
      // Immediate: Android may kill the app before a debounce timer fires.
      _autoSyncDebounce?.cancel();
      unawaited(_autoSync());
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
    if (_autoSyncing || settings == null) return;
    // Either backend counts. `isConfigured` means "has a GitHub token", so
    // gating on it alone silently skips every sync on a device connected
    // only to Firebase -- and once the mirror is retired that is every
    // device.
    if (!settings.isConfigured && await openFirebase() == null) return;
    _autoSyncing = true;
    try {
      final run = await runSync(
        widget.repository,
        settings,
        appSettings: widget.appSettings.value,
        analytics: widget.analytics,
        httpClient: widget.httpClient,
        firebaseFactory: widget.firebaseFactory,
        stateStore: widget.stateStore,
      );
      _adoptReconciledSettings(run.appSettings);
      final detail = _describe(run.syncResult);
      await _recordSyncStatus(ok: true, detail: detail);
      _logEvent(
        'sync_result',
        params: {'ok': true, 'auto': true, 'detail': detail},
      );
    } on Exception catch (e) {
      // Offline or a transient GitHub error: still no snackbar (this path
      // must never interrupt capture), but the status line shows it.
      await _recordSyncStatus(ok: false, detail: '$e');
      _logEvent('sync_result', params: {'ok': false, 'auto': true});
    } finally {
      _autoSyncing = false;
    }
  }

  /// Applies a settings snapshot reconciled during a sync pass, when it is
  /// newer than what this screen already holds (the toggle in Settings may
  /// have written a newer value locally in between, which must win).
  void _adoptReconciledSettings(AppSettings? reconciled) {
    if (!mounted) return;
    widget.appSettings.value = widget.appSettings.value.adopt(reconciled);
  }

  /// Opens the settings screen and adopts any saved configuration.
  Future<void> _openSettings() async {
    _logEvent('screen_view', params: {'screen': 'settings'});
    final current = _settings ?? await SyncSettings.load();
    if (!mounted) return;
    await Navigator.of(context).push<SyncSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: current,
          repository: widget.repository,
          appSettings: widget.appSettings,
          analytics: widget.analytics,
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
    _logEvent('screen_view', params: {'screen': 'notes_list'});
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => NotesListScreen(repository: widget.repository),
        ),
      ),
    );
  }

  /// Runs a full sync, routing to settings first if not yet configured.
  Future<void> _sync() async {
    final settings = _settings ?? await SyncSettings.load();
    if (!settings.isConfigured && await openFirebase() == null) {
      _showSnack('Connect Firebase (or add a GitHub token) in settings');
      await _openSettings();
      return;
    }
    setState(() => _syncing = true);
    try {
      final run = await runSync(
        widget.repository,
        settings,
        appSettings: widget.appSettings.value,
        analytics: widget.analytics,
        httpClient: widget.httpClient,
        firebaseFactory: widget.firebaseFactory,
        stateStore: widget.stateStore,
      );
      _adoptReconciledSettings(run.appSettings);
      final detail = _describe(run.syncResult);
      await _recordSyncStatus(ok: true, detail: detail);
      _logEvent(
        'sync_result',
        params: {'ok': true, 'auto': false, 'detail': detail},
      );
      _showSnack('Synced: $detail');
    } on Exception catch (e) {
      await _recordSyncStatus(ok: false, detail: '$e');
      _logEvent('sync_result', params: {'ok': false, 'auto': false});
      _showSnack('Sync failed: $e');
    } finally {
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
      _logEvent('note_created');
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
    _logEvent(
      'priority_changed',
      params: {'from': _draftPriority.name, 'to': priority.name},
    );
    setState(() => _draftPriority = priority);
    await _persistDraftMeta();
  }

  /// Applies a new status to the draft, persisting immediately if a note
  /// row already exists.
  Future<void> _setStatus(Status status) async {
    _logEvent(
      'status_changed',
      params: {'from': _draftStatus.name, 'to': status.name},
    );
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
  /// The field going blank is the only feedback needed — autosave already
  /// persisted every keystroke, so there is nothing left to confirm.
  void _saveAndReset() {
    _logEvent('new_note_reset');
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: widget.appSettings,
      builder: (context, settings, _) {
        final advanced = settings.advancedMode;
        return Scaffold(
          appBar: AppBar(
            actions: [
              // TEMPORARY: forces continuous frame production so raster cost
              // can be sampled at each window size. Armed by
              // TODO_FRAME_STATS=1, which is never set under the test
              // runner, so the branch is unreachable.
              // coverage:ignore-start
              if (frameStatsEnabled)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              // coverage:ignore-end
              // Live count of stored notes, proving local persistence.
              StreamBuilder<int>(
                stream: widget.repository.watchCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.list_alt_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text('$count'),
                        ],
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'New note',
                onPressed: _saveAndReset,
                icon: const Icon(Icons.add),
              ),
              if (advanced)
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
                tooltip: 'Settings',
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
                // Hidden together with the editor's own chrome while the
                // bare guided stepper or its entry wizard is up, so the top
                // of the screen stays free of noise. Also hidden outright
                // when advanced mode is off.
                if (advanced && _chromeVisible) ...[
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
                  // The key lives on this Expanded, not on NoteEditor itself:
                  // the Row above is conditionally present, which shifts
                  // this Expanded's position in the Column whenever
                  // advancedMode changes at runtime. A key one level too
                  // deep (previously on NoteEditor) doesn't survive that
                  // reposition — Flutter can't match it at the new index,
                  // so it tears down and remounts NoteEditor with an empty
                  // draft, discarding whatever the user was typing.
                  key: ValueKey(_editorGeneration),
                  child: NoteEditor(
                    initialTemplate: NoteTemplate.defaultTemplate,
                    initialMode: NoteEditorMode.raw,
                    advancedMode: advanced,
                    priority: _draftPriority,
                    onPriorityChanged: _setPriority,
                    onChromeVisibleChanged: (visible) =>
                        setState(() => _chromeVisible = visible),
                    autofocus: true,
                    onChanged: _onChanged,
                  ),
                ),
                // Sync is automatic; routine "saved"/"synced" chatter is not
                // worth showing. Only a sync failure is surfaced, since that
                // is the one state the user might need to act on.
                ValueListenableBuilder<SyncStatus?>(
                  valueListenable: _lastSync,
                  builder: (context, status, _) {
                    if (status == null || status.ok) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Sync failed at ${_formatTime(status.time)} · '
                        '${status.detail}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
                if (advanced)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ValueListenableBuilder<DateTime?>(
                      valueListenable: _lastSavedAt,
                      builder: (context, savedAt, _) => Text(
                        savedAt == null
                            ? 'Autosaves as you type'
                            : 'Saved locally at ${_formatTime(savedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
  /// Creates a [SyncStatus] from a completed sync attempt's outcome.
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
