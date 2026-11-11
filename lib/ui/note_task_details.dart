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
    // A glyph per field in place of its written name (kept spoken only);
    // the values are content and stay as typed.
    final rows = [
      (Icons.folder_outlined, 'Repo', note.repo),
      (Icons.fact_check_outlined, 'Done check', note.doneCheck),
      (Icons.person_outline, 'By', note.by),
      (Icons.verified_outlined, 'Evidence', note.evidence),
    ].where((row) => row.$3 != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, label, value) in rows) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, semanticLabel: label),
              const SizedBox(width: 8),
              Expanded(child: Text(value!, style: theme.bodyMedium)),
            ],
          ),
        ],
      ],
    );
  }
}
