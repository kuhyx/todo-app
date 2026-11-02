/// The notes list's body: phone grid or desktop list of grouped rows.
///
/// Split out of `notes_list_screen.dart` for file size.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/note_tile.dart';
import 'package:todo/ui/notes_grid.dart';
import 'package:todo/ui/repo_group.dart';
import 'package:todo/ui/repo_tiles.dart';

/// Lays [entries] out as a grid below [kNotesGridMaxWidth], else a list.
class NotesListBody extends StatelessWidget {
  /// Creates the body; callbacks get the tapped note or repo group.
  const NotesListBody({
    required this.entries,
    required this.onOpen,
    required this.onActions,
    required this.onOpenRepo,
    super.key,
  });

  /// Rows in display order.
  final List<ListEntry> entries;

  /// Tap on a note.
  final ValueChanged<Note> onOpen;

  /// Long-press (or the actions button) on a note.
  final ValueChanged<Note> onActions;

  /// Tap on a repo group.
  final ValueChanged<RepoEntry> onOpenRepo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < kNotesGridMaxWidth
          ? NotesGrid(
              entries: entries,
              onOpen: onOpen,
              onActions: onActions,
              onOpenRepo: onOpenRepo,
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => switch (entries[i]) {
                NoteEntry(:final note) => NoteTile(
                  key: ValueKey(note.id),
                  note: note,
                  onTap: () => onOpen(note),
                  onActions: () => onActions(note),
                ),
                final RepoEntry repo => RepoListTile(
                  key: ValueKey(repo.repo),
                  entry: repo,
                  onTap: () => onOpenRepo(repo),
                ),
              },
            ),
    );
  }
}
