/// Which view of the note the editor is currently showing.
///
/// Its own file so the chrome and the editor can both name it without either
/// importing the other. `note_editor.dart` re-exports it, so existing callers
/// (the detail screen, the tests) are unaffected.
library;

/// Which view of the note the editor is currently showing.
enum NoteEditorMode {
  /// Read-only rendered Markdown (headings, guidance, bullets).
  preview,

  /// Full-screen per-step view, one step per template section.
  guided,

  /// A single text field showing the assembled Markdown verbatim.
  raw,
}
