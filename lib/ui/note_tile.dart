/// One row of the notes list.
///
/// Split out of `notes_list_screen.dart` for file size; public only because
/// Dart privacy is library-scoped.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';

/// One row in the notes list: title, metadata line, and an actions button.
class NoteTile extends StatelessWidget {
  /// Creates a tile for [note].
  const NoteTile({
    required this.note,
    required this.onTap,
    required this.onActions,
    super.key,
  });

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
    // Every note has a status and a priority now, so both are always shown.
    final meta = <String>[
      note.status.label,
      note.priority.label,
      'edited ${_relative(note.updatedAt)}',
    ].join(' · ');
    return ListTile(
      title: Text(
        firstLine.isEmpty ? '(empty)' : firstLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(meta),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Quick actions',
        onPressed: onActions,
      ),
      onTap: onTap,
      onLongPress: onActions,
    );
  }

  /// Compact relative time like "2m ago" for the list subtitle.
  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Bottom sheet for editing one note's priority/status or deleting it.
