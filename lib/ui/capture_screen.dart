import 'dart:async';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/capture_app_bar.dart';
import 'package:todo/ui/capture_draft.dart';
import 'package:todo/ui/capture_status.dart';
import 'package:todo/ui/capture_status_footer.dart';
import 'package:todo/ui/capture_sync_runner.dart';
import 'package:todo/ui/note_form.dart';
import 'package:todo/ui/notes_list_screen.dart';
import 'package:todo/ui/settings_screen.dart';

part 'capture_screen_sync.dart';
part 'capture_screen_widget.dart';

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  /// Single-flight guard so a launch sync and a background sync never overlap.
  bool _autoSyncing = false;

  /// Keeps an always-current Markdown backup on local disk and recovers from
  /// it on launch (third durability layer beside sync + Android Auto Backup).
  late final LocalBackup _localBackup;
  StreamSubscription<void>? _changesSub;

  /// Latest assembled text from the editor; persisted on change and re-saved
  /// when only priority/status change.

  /// Bumped on save to recreate the editor with a fresh, empty template.
  int _editorGeneration = 0;

  /// Id of the note currently being edited, or null before the first
  /// keystroke of a fresh draft.

  /// Time of the last local save, shown in the tiny save indicator. A notifier
  /// (not a `setState` field) so a keystroke updates only that one line of text
  /// instead of rebuilding the AppBar, dropdowns, and editor every character.

  /// Priority/status applied to the current draft. Chosen before or during
  /// typing; persisted on the first keystroke and on every later change.

  SyncSettings? _settings;
  bool _syncing = false;

  /// Outcome of the most recent sync attempt (manual or automatic), driving
  /// the tiny status line under the editor. Persisted so a failure that
  /// happened just before the app closed is still visible on next launch.
  /// The note being captured, and its write-through to storage.
  late final CaptureDraft _draft = CaptureDraft(widget.repository);

  final SyncStatusStore _syncStatus = SyncStatusStore();

  /// Runs sync passes and records their outcome; see [CaptureSyncRunner].
  late final CaptureSyncRunner _runner = CaptureSyncRunner(
    repository: widget.repository,
    status: _syncStatus,
    analytics: widget.analytics,
    httpClient: widget.httpClient,
    firebaseFactory: widget.firebaseFactory,
    stateStore: widget.stateStore,
  );

  /// Debounces focus-loss sync triggers so desktop alt-tab flicker doesn't
  /// hammer GitHub with a request per focus change.
  Timer? _autoSyncDebounce;

  /// When this session started, for the duration on the `app_close` event.
  final DateTime _sessionStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    _logEvent('app_open');
    WidgetsBinding.instance.addObserver(this);
    _localBackup = widget.localBackup ?? platformLocalBackup(widget.repository);
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
    _draft.dispose();
    _syncStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: widget.appSettings,
      builder: (context, settings, _) {
        final advanced = settings.advancedMode;
        return Scaffold(
          appBar: CaptureAppBar(
            repository: widget.repository,
            advanced: advanced,
            syncing: _syncing,
            onNewNote: _saveAndReset,
            onSync: _sync,
            onOpenList: _openList,
            onOpenSettings: _openSettings,
          ),
          body: _captureBody(advanced: advanced),
        );
      },
    );
  }

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
      final outcome = await _runner.run(
        settings: settings,
        appSettings: widget.appSettings.value,
        live: () => mounted,
      );
      if (outcome.ok) _adoptReconciledSettings(outcome.reconciled);
      _logEvent(
        'sync_result',
        params: {
          'ok': outcome.ok,
          'auto': false,
          if (outcome.ok) 'detail': outcome.detail,
        },
      );
      _showSnack(
        outcome.ok
            ? 'Synced: ${outcome.detail}'
            : 'Sync failed: ${outcome.detail}',
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// setState, reachable from this screen's `part` files.
  ///
  /// setState is protected to State subclasses, so an extension in a part
  /// cannot call it directly even though it is the same library.
  void _rebuild(VoidCallback change) => setState(change);
}
