/// Inserting attached-image links into whichever field is being edited.
///
/// A `part` of `note_editor.dart` because it writes the editor's private
/// controllers (`_doc`) and follows its mode (`_mode`, `_currentStep`).
part of 'note_editor.dart';

extension _NoteEditorImages on _NoteEditorState {
  /// Puts [lines] on their own lines at the cursor of the field in view:
  /// the current step's field in Guided, the body in Raw. With no visible
  /// cursor (View mode, or a field never focused) they go at the end.
  void _insertImageLinks(List<String> lines) {
    final TextEditingController target;
    var atEnd = _mode == NoteEditorMode.preview;
    if (_mode == NoteEditorMode.guided && !_doc.rawSource) {
      _doc.ensureControllers(_doc.template);
      final sections = _doc.template.sections;
      target = _doc
          .section[sections[_currentStep.clamp(0, sections.length - 1)].key]!;
    } else if (_doc.rawSource) {
      target = _doc.body;
    } else {
      // View mode over guided sections: the last section is the end.
      _doc.ensureControllers(_doc.template);
      target = _doc.section[_doc.template.sections.last.key]!;
      atEnd = true;
    }
    _insertBlock(target, lines.join('\n'), atEnd: atEnd);
    _retemplateDraft();
    _onStepFieldChanged();
  }
}

/// Replaces [controller]'s selection (or appends, when [atEnd] or there is
/// no selection) with [block], padded with newlines so it sits on its own
/// lines, and leaves the cursor just after it.
void _insertBlock(
  TextEditingController controller,
  String block, {
  required bool atEnd,
}) {
  final text = controller.text;
  final selection = controller.selection;
  final useCursor = !atEnd && selection.isValid;
  final start = useCursor ? selection.start : text.length;
  final end = useCursor ? selection.end : text.length;
  final before = text.substring(0, start);
  final after = text.substring(end);
  final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
  final trail = after.startsWith('\n') ? '' : '\n';
  final inserted = '$lead$block$trail';
  controller.value = TextEditingValue(
    text: '$before$inserted$after',
    selection: TextSelection.collapsed(offset: before.length + inserted.length),
  );
}
