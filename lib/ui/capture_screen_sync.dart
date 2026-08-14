/// The capture screen's sync and navigation behaviour: the lifecycle hook
/// that triggers a background push, the manual and automatic sync paths, and
/// the two screens this one opens.
///
/// A `part` of `capture_screen.dart` because every method here reads private
/// state (`_settings`, `_syncing`, `_runner`) that Dart scopes to the library.
/// The work itself lives in [CaptureSyncRunner]; what stays here is when to
/// run it and what the user is shown.
part of 'capture_screen.dart';

extension _CaptureSyncBehaviour on _CaptureScreenState {
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
      // Offline or a transient GitHub error is reported the same way as
      // success here: no snackbar (this path must never interrupt capture),
      // just the status line the runner has already written.
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
          'auto': true,
          if (outcome.ok) 'detail': outcome.detail,
        },
      );
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Reloads the persisted last-sync outcome so the status line survives a
  /// restart. Skipped when the screen went away while the read was in
  /// flight -- the notifier must not be written after dispose.
  Future<void> _restoreSyncStatus() async {
    await _syncStatus.restore(stillLive: () => mounted);
  }

  /// Restores notes from the local backup file, but only into an empty DB so a
  /// stale backup never clobbers existing notes (merge-by-id stays safe too).
  Future<void> _recoverFromBackup() async {
    final existing = await widget.repository.listNotes();
    if (existing.isNotEmpty) return;
    final recovered = await _localBackup.recover();
    if (recovered.isNotEmpty) await widget.repository.importNotes(recovered);
  }

  /// The composer column: metadata row, editor, and status footer.
  Widget _captureBody({required bool advanced}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hidden together with the editor's own chrome while the
          // bare guided stepper or its entry wizard is up, so the top
          // of the screen stays free of noise. Also hidden outright
          // when advanced mode is off.
          if (advanced && _chromeVisible) ...[
            CaptureMetaRow(
              priority: _draft.priority,
              status: _draft.status,
              onPriorityChanged: _setPriority,
              onStatusChanged: _setStatus,
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
              priority: _draft.priority,
              onPriorityChanged: _setPriority,
              onChromeVisibleChanged: _setChromeVisible,
              autofocus: true,
              onChanged: _onChanged,
            ),
          ),
          CaptureStatusFooter(
            syncStatus: _syncStatus.latest,
            lastSavedAt: _draft.lastSavedAt,
            showSavedAt: advanced,
          ),
        ],
      ),
    );
  }

  /// Persists the current text on every change. The note row is created on
  /// the first non-empty keystroke, which is the one worth logging.
  Future<void> _onChanged(String text) async {
    final created = await _draft.write(text, live: () => mounted);
    if (created) _logEvent('note_created');
  }

  /// Applies a new priority to the draft, persisting immediately if a note
  /// row already exists (otherwise it is applied on the first keystroke).
  Future<void> _setPriority(Priority priority) async {
    _logEvent(
      'priority_changed',
      params: {'from': _draft.priority.name, 'to': priority.name},
    );
    _rebuild(() => _draft.priority = priority);
    await _draft.persistMetadata(live: () => mounted);
  }

  /// Applies a new status to the draft, persisting immediately if a note
  /// row already exists.
  Future<void> _setStatus(Status status) async {
    _logEvent(
      'status_changed',
      params: {'from': _draft.status.name, 'to': status.name},
    );
    _rebuild(() => _draft.status = status);
    await _draft.persistMetadata(live: () => mounted);
  }

  /// Finalises the current idea and resets the field to a fresh template.
  /// The field going blank is the only feedback needed — autosave already
  /// persisted every keystroke, so there is nothing left to confirm.
  void _saveAndReset() {
    _logEvent('new_note_reset');
    _rebuild(() {
      _editorGeneration++; // recreate the editor with a fresh template
      _draft.reset();
      _chromeVisible = true;
    });
  }

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
}
