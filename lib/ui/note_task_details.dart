import 'package:flutter/material.dart';
import 'package:todo/data/note.dart';

/// Read-only repo-task fields of [note]; empty for a plain idea.
class NoteTaskDetails extends StatelessWidget {
  /// Shows the fields [note] has set.
  const NoteTaskDetails({required this.note, super.key});

  /// The note whose task fields are shown.
  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final rows = [
      ('Repo', note.repo),
      ('Done check', note.doneCheck),
      ('By', note.by),
      ('Evidence', note.evidence),
    ].where((row) => row.$2 != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows) ...[
          const SizedBox(height: 12),
          Text(label, style: theme.labelLarge),
          const SizedBox(height: 4),
          Text(value!, style: theme.bodyMedium),
        ],
      ],
    );
  }
}
