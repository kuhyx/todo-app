/// The raw-mode editing field: the assembled note text, verbatim.
///
/// Split out of `note_editor.dart` for file size. Stateless; the controller
/// stays owned by `_NoteEditorState`.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// A full-height plain-text field for the note's assembled Markdown.
class NoteEditorRawField extends StatelessWidget {
  /// Creates the raw field over [controller].
  const NoteEditorRawField({
    required this.controller,
    required this.autofocus,
    required this.onChanged,
    super.key,
  });

  /// Controller holding the raw body text.
  final TextEditingController controller;

  /// Whether the field takes focus on first build.
  final bool autofocus;

  /// Called on every keystroke.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    // Caps the editing column at ~70 chars (rule 21) on the desktop's
    // arbitrarily wide Chrome `--app` window. Center/ConstrainedBox only,
    // no extra Column — nesting a second Column here previously broke the
    // expands:true constraint chain in release builds (see
    // NoteEditorStepPage, which documents the same hazard).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Write your idea…',
          ),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}
