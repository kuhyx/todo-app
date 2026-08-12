import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sync_settings_ui/sync_settings_ui.dart';
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/backlog_export.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/google_sign_in_backend.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/github_mirror_screen.dart';

/// Settings screen: the "Enable advanced" toggle plus links to the two sync
/// surfaces.
///
/// "Sync settings" is the shared `sync_settings_ui` package (Firebase +
/// notes backup, identical in shape to every other kuhy app's Sync settings
/// screen). "Advanced sync (GitHub)" stays app-local
/// ([GitHubMirrorScreen]) because connecting it also triggers a real note
/// sync, which the shared package does not do.
class SettingsScreen extends StatefulWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({
    required this.initial,
    required this.repository,
    required this.appSettings,
    this.analytics,
    this.httpClient,
    this.firebaseFactory,
    this.googleFirebaseFactory,
    this.googleAvailable,
    this.stateStore,
    this.accountLoader,
    this.accountSaver,
    this.accountClearer,
    this.sessionProbe,
    super.key,
  });

  /// The GitHub sync settings loaded when this screen was opened.
  final SyncSettings initial;

  /// The store backup export/import and post-connect sync read from and
  /// write to.
  final NoteRepository repository;

  /// App-wide preferences, currently just `advancedMode`. The "Enable
  /// advanced" switch on this screen reads and writes it directly.
  final ValueNotifier<AppSettings> appSettings;

  /// Interaction-only usage analytics. Null in tests that don't exercise it.
  final AnalyticsService? analytics;

  /// Optional HTTP client for the GitHub calls (test-connection and device
  /// flow) on the linked [GitHubMirrorScreen]. Injected by tests; production
  /// uses each client's default.
  final http.Client? httpClient;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Builds the Firebase backend via Google sign-in. Separate from
  /// [firebaseFactory] because it reaches the Google plugin's platform
  /// channel, which `flutter test` has no binding for.
  final Future<FirebaseRestClient?> Function()? googleFirebaseFactory;

  /// Whether to offer the Google button. Defaults to what the platform
  /// actually supports; injected by tests, which run on a host where the
  /// plugin reports unsupported.
  final bool? googleAvailable;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Keystore accessors for the Firebase account. Injected as a group so the
  /// connect/disconnect flows are testable without a platform channel —
  /// `flutter test` has no binding for one, and the real keystore is the only
  /// thing standing between these branches and full coverage.
  final Future<FirebaseAccount?> Function()? accountLoader;

  /// Persists the account. See [accountLoader].
  final Future<void> Function(FirebaseAccount)? accountSaver;

  /// Forgets the account and any cached session. See [accountLoader].
  final Future<void> Function()? accountClearer;

  /// Whether a Firebase session is stored. See [accountLoader].
  final Future<bool> Function()? sessionProbe;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Persists the "Enable advanced" toggle locally and, when a Firebase
  /// session is available, best-effort mirrors it so the choice follows the
  /// user to their other devices.
  ///
  /// The local write always lands — a signed-in-as-wrong-account device
  /// throwing [FirebaseAuthError] out of `openFirebase()` must not take the
  /// toggle down with it, so opening the client has its own try/catch,
  /// separate from (and preceding) the try that guards the local write and
  /// mirror push.
  Future<void> _setAdvancedMode(bool value) async {
    final analytics = widget.analytics;
    if (analytics != null) {
      unawaited(
        analytics.logEvent(
          AnalyticsEvent(
            name: 'settings_toggle',
            timestamp: DateTime.now(),
            params: {'key': 'advancedMode', 'value': value},
          ),
        ),
      );
    }
    FirebaseRestClient? client;
    try {
      client = await (widget.firebaseFactory ?? openFirebase)();
    } on Exception {
      client = null;
    }
    try {
      final updated = await widget.appSettings.value.withAdvancedMode(
        value: value,
        client: client,
      );
      if (mounted) widget.appSettings.value = updated;
    } finally {
      client?.close();
    }
  }

  /// Exports every note to a single Markdown file. On mobile this opens the
  /// system share sheet; on desktop it writes the canonical `~/todo/
  /// BACKLOG.md` so a future tool/agent has a stable path to read.
  Future<void> _export() async {
    final notes = await widget.repository.listNotes();
    final markdown = NotesMarkdown.export(notes);
    await exportBacklog(markdown, notes.length);
  }

  /// Imports notes from a user-picked Markdown file, merging by id so a
  /// stale backup never clobbers a newer local edit (see
  /// [NoteRepository.importNotes]).
  Future<void> _import() async {
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
    await widget.repository.importNotes(notes);
  }

  Future<void> _openSyncSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SyncSettingsScreen(
          accountLoader: widget.accountLoader ?? loadAccount,
          accountSaver: widget.accountSaver ?? saveAccount,
          accountClearer: widget.accountClearer ?? clearAccount,
          sessionProbe: widget.sessionProbe ?? isFirebaseConfigured,
          firebaseFactory: widget.firebaseFactory ?? openFirebase,
          googleFirebaseFactory:
              widget.googleFirebaseFactory ?? openFirebaseWithGoogle,
          googleAvailable: widget.googleAvailable ?? googleSignInSupported,
          backup: BackupSlot(
            label: 'notes',
            export: _export,
            import: _import,
          ),
        ),
      ),
    );
  }

  Future<void> _openGitHubMirror() async {
    await Navigator.of(context).push<SyncSettings>(
      MaterialPageRoute(
        builder: (_) => GitHubMirrorScreen(
          initial: widget.initial,
          repository: widget.repository,
          appSettings: widget.appSettings,
          analytics: widget.analytics,
          httpClient: widget.httpClient,
          firebaseFactory: widget.firebaseFactory,
          stateStore: widget.stateStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<AppSettings>(
            valueListenable: widget.appSettings,
            builder: (context, settings, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable advanced'),
              subtitle: const Text(
                'Priority/status, templates, view modes, and sync details '
                'in the capture screen',
              ),
              value: settings.advancedMode,
              onChanged: (value) => unawaited(_setAdvancedMode(value)),
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sync settings'),
            subtitle: const Text('Firebase sync and notes backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_openSyncSettings()),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced sync (GitHub)'),
            subtitle: const Text('Cutover mirror — not recommended'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_openGitHubMirror()),
          ),
        ],
      ),
    );
  }
}
