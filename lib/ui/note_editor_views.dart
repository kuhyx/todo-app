/// The [NoteEditor]'s view wiring: the small methods that hand this editor's
/// state to the extracted presentation widgets.
///
/// A `part` of `note_editor.dart` because every method here reads private
/// state (`_doc`, `_mode`, `_currentStep`) that Dart scopes to the library.
part of 'note_editor.dart';

extension _NoteEditorViews on _NoteEditorState {
  /// The pre-guided wizard. Its step state lives in the widget itself; only
  /// the two committed choices come back here.
  Widget _guidedEntryWizard() => NoteEditorWizard(
    initialPriority: widget.priority,
    initialTemplate: NoteTemplate.defaultTemplate,
    onCancel: _cancelWizard,
    onStart: (priority, template) {
      widget.onPriorityChanged(priority);
      _enterGuidedWithTemplate(template);
    },
  );

  /// The raw field, wired to this editor's body controller.
  Widget _rawField() => NoteEditorRawField(
    controller: _doc.body,
    autofocus: widget.autofocus,
    onChanged: () {
      _retemplateDraft();
      _emit();
    },
  );

  Widget _buildBody() {
    switch (_mode) {
      case NoteEditorMode.preview:
        return MarkdownView(text: _doc.currentText());
      case NoteEditorMode.raw:
        return _rawField();
      // coverage:ignore-start
      // Unreachable: build() short-circuits to _buildStepPage before reaching
      // here, so this arm only exists to make the switch exhaustive.
      case NoteEditorMode.guided:
        return _rawField();
      // coverage:ignore-end
    }
  }

  /// Full-screen per-step view returned directly from [build] so the
  /// TextField is a first-level Expanded child of that column -- see
  /// [NoteEditorStepPage], which documents why the flat structure matters.
  Widget _buildStepPage() {
    _doc.ensureControllers(_doc.template);
    final sections = _doc.template.sections;
    final idx = _currentStep.clamp(0, sections.length - 1);
    final section = sections[idx];
    return NoteEditorStepPage(
      section: section,
      controller: _doc.section[section.key]!,
      index: idx,
      total: sections.length,
      autofocus: widget.autofocus,
      onGoToStep: _goToStep,
      onExit: _exitGuided,
      onChanged: _onStepFieldChanged,
    );
  }
}
