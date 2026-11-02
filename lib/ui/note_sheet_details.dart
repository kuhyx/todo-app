import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/images/attachment_links.dart';

/// [text] without the line that serves as the title.
String noteBodyOf(String text) {
  final lines = text.split('\n');
  final title = lines.indexWhere(
    (l) => l.trim().isNotEmpty && attachmentOfLine(l.trim()) == null,
  );
  if (title < 0) return text.trim();
  return [...lines.take(title), ...lines.skip(title + 1)].join('\n').trim();
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${t.year}-${two(t.month)}-${two(t.day)}';
  return '$date ${two(t.hour)}:${two(t.minute)}';
}

/// What a grid tile leaves out: the note body and its two dates.
class NoteSheetDetails extends StatelessWidget {
  /// Shows the body and the dates of [note].
  const NoteSheetDetails({required this.note, super.key});

  /// The note being shown.
  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = noteBodyOf(note.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(body, style: theme.bodyMedium),
        ],
        const SizedBox(height: 12),
        Text(
          'Edited ${_stamp(note.updatedAt)}'
          ' · Created ${_stamp(note.createdAt)}',
          style: theme.bodySmall,
        ),
      ],
    );
  }
}
