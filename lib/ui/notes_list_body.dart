/// The notes list's body: phone grid or desktop list of notes.
///
/// Split out of `notes_list_screen.dart` for file size.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/note_tile.dart';
import 'package:todo/ui/notes_grid.dart';

/// Lays [notes] out as a grid below [kNotesGridMaxWidth], else a list.
class NotesListBody extends StatelessWidget {
  /// Creates the body; callbacks get the tapped note.
  const NotesListBody({
    required this.notes,
    required this.onOpen,
    required this.onActions,
    required this.isSelected,
    super.key,
  });

  /// Whether the note with this id is in the multi-selection.
  final bool Function(String id) isSelected;

  /// Notes in display order.
  final List<Note> notes;

  /// Tap on a note.
  final ValueChanged<Note> onOpen;

  /// Long-press (or the actions button) on a note.
  final ValueChanged<Note> onActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < kNotesGridMaxWidth
          ? NotesGrid(
              notes: notes,
              onOpen: onOpen,
              onActions: onActions,
              isSelected: isSelected,
            )
          : ListView.separated(
              itemCount: notes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => NoteTile(
                key: ValueKey(notes[i].id),
                note: notes[i],
                selected: isSelected(notes[i].id),
                onTap: () => onOpen(notes[i]),
                onActions: () => onActions(notes[i]),
              ),
            ),
    );
  }
}
