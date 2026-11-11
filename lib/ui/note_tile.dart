/// One row of the notes list.
///
/// Split out of `notes_list_screen.dart` for file size; public only because
/// Dart privacy is library-scoped.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/enum_glyphs.dart';
import 'package:todo/ui/note_grid_tile.dart';

/// One row in the notes list: title, metadata line, and an actions button.
class NoteTile extends StatelessWidget {
  /// Creates a tile for [note].
  const NoteTile({
    required this.note,
    required this.onTap,
    required this.onActions,
    this.selected = false,
    super.key,
  });

  /// Whether the row is part of the multi-selection: highlighted + a check.
  final bool selected;

  /// The note this row displays.
  final Note note;

  /// Open the full note for reading/editing.
  /// Called when the row body is tapped (opens the note).
  final VoidCallback onTap;

  /// Open the quick-actions sheet (priority/status/delete).
  /// Called when the trailing actions button is tapped.
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final firstLine = noteTitle(note.text);
    return ListTile(
      selected: selected,
      leading: selected
          ? const Icon(Icons.check_circle, semanticLabel: 'Selected')
          : null,
      title: Text(
        firstLine.isEmpty ? kEmptyTitle : firstLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _meta(context),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, semanticLabel: 'Quick actions'),
        onPressed: onActions,
      ),
      onTap: onTap,
      onLongPress: onActions,
    );
  }

  /// Status and priority glyphs, the edit age, and the repo (content).
  /// Every note has a status and a priority, so both are always shown.
  Widget _meta(BuildContext context) => Row(
    children: [
      statusGlyph(note.status, size: 16),
      const SizedBox(width: 6),
      priorityGlyph(context, note.priority, size: 16),
      const SizedBox(width: 6),
      const Icon(Icons.history, size: 16, semanticLabel: 'Edited'),
      Text(relativeAge(note.updatedAt)),
      if (note.repoName case final repo?) ...[
        const SizedBox(width: 6),
        Flexible(child: Text(repo, overflow: TextOverflow.ellipsis)),
      ],
    ],
  );
}

/// Compact age like "2m" / "3h" / "4d": a number plus a unit symbol.
String relativeAge(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}
