/// The settings screen's actions: Markdown export/import, sync now, and the
/// routes to the two sync screens.
///
/// A `part` of `settings_screen.dart` because they read the screen's
/// private state; split out for file size.
part of 'settings_screen.dart';

extension _SettingsActions on _SettingsScreenState {
  /// Exports every note to a single Markdown file. On mobile this opens the
  /// system share sheet; on desktop it writes the canonical `~/src/todo/
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

  /// Retries the sync after a passphrase is entered; the lock tile follows
  /// [e2eLocked], which the run updates.
  Future<void> _syncNow() async {
    try {
      await runSync(
        widget.repository,
        widget.initial,
        httpClient: widget.httpClient,
        firebaseFactory: widget.firebaseFactory,
        stateStore: widget.stateStore,
      );
    } on Exception {
      // The capture screen's status line reports sync failures.
    }
  }

  Future<void> _openSyncSettings() async {
    await Navigator.of(context).push<void>(
      appRoute(
        context,
        (_) => SyncSettingsScreen(
          accountLoader: widget.accountLoader ?? loadAccount,
          accountSaver: widget.accountSaver ?? saveAccount,
          accountClearer: widget.accountClearer ?? clearAccount,
          sessionProbe: widget.sessionProbe ?? isFirebaseConfigured,
          firebaseFactory: widget.firebaseFactory ?? openFirebase,
          googleFirebaseFactory:
              widget.googleFirebaseFactory ?? openFirebaseWithGoogle,
          googleAvailable: widget.googleAvailable ?? googleSignInSupported,
          backup: BackupSlot(label: 'notes', export: _export, import: _import),
        ),
        name: '/settings/sync',
      ),
    );
  }

  Future<void> _openGitHubMirror() async {
    await Navigator.of(context).push<SyncSettings>(
      appRoute(
        context,
        (_) => GitHubMirrorScreen(
          initial: widget.initial,
          repository: widget.repository,
          appSettings: widget.appSettings,
          analytics: widget.analytics,
          httpClient: widget.httpClient,
          firebaseFactory: widget.firebaseFactory,
          stateStore: widget.stateStore,
        ),
        name: '/settings/github',
      ),
    );
  }
}
