/// The editor's chrome: the template picker and the View/Guided/Raw toggle.
///
/// Split out of `note_editor.dart` for file size. Stateless and callback-only
/// — every choice it offers is applied by `_NoteEditorState`, which owns the
/// template and mode. Guided hides this chrome entirely, so it is only ever
/// built in Preview and Raw.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_template.dart';
import 'package:todo/ui/note_editor_mode.dart';

/// Template dropdown above a segmented View / Guided / Raw selector.
class NoteEditorChrome extends StatelessWidget {
  /// Creates the chrome for [template] in [mode].
  const NoteEditorChrome({
    required this.template,
    required this.mode,
    required this.onTemplateSelected,
    required this.onModeSelected,
    super.key,
  });

  /// The template currently selected in the dropdown.
  final NoteTemplate template;

  /// The mode the segmented button shows as selected.
  final NoteEditorMode mode;

  /// Called with the template the user picked.
  final ValueChanged<NoteTemplate> onTemplateSelected;

  /// Called with the mode the user picked.
  final ValueChanged<NoteEditorMode> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: template.id,
          decoration: const InputDecoration(
            labelText: 'Template',
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            for (final t in NoteTemplate.all)
              DropdownMenuItem(value: t.id, child: Text(t.label)),
          ],
          onChanged: (id) {
            if (id == null) return;
            onTemplateSelected(
              NoteTemplate.all.firstWhere((t) => t.id == id),
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<NoteEditorMode>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: NoteEditorMode.preview,
                icon: Icon(Icons.visibility_outlined),
                label: Text('View'),
              ),
              // Guided is offered for any structured template; tapping it
              // on an empty draft opens the wizard, and is blocked at
              // switch time if the raw text no longer conforms.
              if (!template.isFreeform)
                const ButtonSegment(
                  value: NoteEditorMode.guided,
                  icon: Icon(Icons.checklist),
                  label: Text('Guided'),
                ),
              const ButtonSegment(
                value: NoteEditorMode.raw,
                icon: Icon(Icons.notes),
                label: Text('Raw'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeSelected(s.first),
          ),
        ),
      ],
    );
  }
}
