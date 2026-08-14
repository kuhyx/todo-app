/// The [NoteEditor] widget's public surface: its parameters and their
/// contracts. The state that drives them lives in `note_editor.dart`.
///
/// A `part` rather than a separate library because the widget and its State
/// are genuinely one unit -- `createState` returns a private class, so they
/// cannot be split across libraries without making that class public.
part of 'note_editor.dart';

/// A guided editor for a note's text, shared by the capture and detail
/// screens.
///
/// It is a *view* over plain text: it parses [initialText] into template
/// sections and reports the re-assembled text through [onChanged] on every
/// edit. Storage stays plain text, so sync and markdown export are unaffected.
///
/// Modes (see [NoteEditorMode]):
///   * **Preview** — the note rendered as Markdown, read-only.
///   * **Guided** — a full-screen per-step view, one step per template
///     section, with guidance on what to write and why the LLM needs it.
///   * **Raw** — a single text field showing the assembled text verbatim.
///
/// Non-conforming or freeform text never enters the guided stepper (we never
/// force it into the template), so for such text Guided is unavailable and the
/// editable source stays the raw body, preserving the user's content.
///
/// Entering Guided on an empty draft first runs a two-step wizard (priority,
/// then template) via [onPriorityChanged], since those choices only make
/// sense once, before there's anything to guide. Guided itself — wizard or
/// bare step page — hides the template/mode chrome entirely (just a back arrow
/// to return to Raw); [onChromeVisibleChanged] tells the parent screen to
/// hide its own priority/status row in sync.
class NoteEditor extends StatefulWidget {
  /// Creates a [NoteEditor] with the given callbacks and initial state.
  const NoteEditor({
    required this.onChanged,
    required this.priority,
    required this.onPriorityChanged,
    required this.onChromeVisibleChanged,
    this.initialText = '',
    this.initialTemplate,
    this.initialMode = NoteEditorMode.guided,
    this.autofocus = false,
    this.advancedMode = true,
    super.key,
  });

  /// Called with the freshly assembled note text on every edit.
  final ValueChanged<String> onChanged;

  /// The note's current priority, shown as the wizard's starting selection.
  final Priority priority;

  /// Called when the priority wizard step is confirmed (Guided "Start").
  final ValueChanged<Priority> onPriorityChanged;

  /// Called whenever the editor's own chrome (template dropdown, mode
  /// selector) is shown/hidden, so the parent screen can hide its
  /// priority/status row in sync while Guided (wizard or bare stepper) is
  /// active.
  final ValueChanged<bool> onChromeVisibleChanged;

  /// Existing note text to load. Empty for a fresh draft.
  final String initialText;

  /// Template to author with. When null the template is detected from
  /// [initialText] (used when opening an existing note).
  final NoteTemplate? initialTemplate;

  /// Preferred mode to open in. Falls back to [NoteEditorMode.raw] when
  /// [NoteEditorMode.guided] is requested for text that can't be guided
  /// (freeform template or non-conforming content).
  final NoteEditorMode initialMode;

  /// Autofocus the first field, so a fresh capture needs zero taps before
  /// typing — preserving the app's instant-capture invariant.
  final bool autofocus;

  /// Whether the template picker and View/Guided/Raw mode toggle are shown.
  /// For a freshly-mounted editor, false pins the mode to
  /// [NoteEditorMode.raw] regardless of [initialMode], and Guided/Preview
  /// are unreachable — casual capture needs neither. Toggling this off
  /// while already mid-Guided does not itself force an immediate mode
  /// change (the open mode stays until the next mode transition, which
  /// then resolves to raw) — a transient, self-healing state, not a hole
  /// in the gating.
  final bool advancedMode;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}
