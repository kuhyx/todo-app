/// The notes list's multi-select wiring: the app-bar toggle, taps, and the
/// bottom action bar.
///
/// A `part` of `notes_list_screen.dart` because it reads the screen's
/// private selection and repository; split out for file size.
part of 'notes_list_screen.dart';

extension _Selecting on _NotesListScreenState {
  /// App-bar toggle into and out of selection mode (tinted while on).
  Widget _selectButton() => IconButton(
    key: const ValueKey('select-mode'),
    isSelected: _selection.active,
    onPressed: _selection.toggleMode,
    icon: const Icon(Icons.checklist, semanticLabel: 'Select'),
  );

  /// A tap on [note] of [notes]: selects in the mode or with Shift/Ctrl,
  /// else opens it.
  void _tap(Note note, List<Note> notes) {
    if (_selection.handleTap(note, notes)) return;
    unawaited(openNote(context, note, widget.repository, widget.appSettings));
  }

  /// A long-press: toggles in the mode, else the per-note sheet.
  void _longPress(Note note) {
    if (_selection.active) return _selection.toggle(note.id);
    unawaited(openNoteActions(context, note, widget.repository));
  }

  /// The bar, only while something is selected. Status and priority are
  /// ONE store write for the whole selection ([NoteRepository.bulkUpdate]).
  Widget? _selectionBar() {
    if (_selection.ids.isEmpty) return null;
    final repo = widget.repository;
    return NotesSelectionBar(
      onStatus: (s) => unawaited(repo.bulkUpdate(_selection.ids, status: s)),
      onPriority: (p) =>
          unawaited(repo.bulkUpdate(_selection.ids, priority: p)),
      onAssign: () => assignSelection(context, repo, _selection),
      onClear: _selection.clear,
    );
  }
}
