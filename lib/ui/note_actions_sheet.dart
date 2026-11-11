/// The per-note actions sheet shown from the notes list.
///
/// Split out of `notes_list_screen.dart` for file size; public only because
/// Dart privacy is library-scoped.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/confirm_delete.dart';
import 'package:todo/ui/enum_glyphs.dart';
import 'package:todo/ui/note_sheet_details.dart';
import 'package:todo/ui/note_task_details.dart';

/// The per-note bottom sheet: status/priority chips, and delete.
class NoteActionsSheet extends StatefulWidget {
  /// Creates the per-note actions sheet for [note].
  const NoteActionsSheet({
    required this.note,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  /// The note being acted on.
  final Note note;

  /// Called with the edited note whenever a chip changes it.
  final Future<void> Function(Note) onChanged;

  /// Called once the user confirms deletion.
  final Future<void> Function() onDelete;

  @override
  State<NoteActionsSheet> createState() => _NoteActionsSheetState();
}

class _NoteActionsSheetState extends State<NoteActionsSheet> {
  late Priority _priority = widget.note.priority;
  late Status _status = widget.note.status;

  Future<void> _persist() async {
    await widget.onChanged(
      widget.note.copyWith(
        priority: _priority,
        status: _status,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstLine = noteTitle(widget.note.text);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User content; untitled shows nothing, not a placeholder.
              if (firstLine.isNotEmpty)
                Text(
                  firstLine,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              NoteSheetDetails(note: widget.note),
              const SizedBox(height: 16),
              GlyphChips<Status>(
                heading: kStatusHeadingIcon,
                semanticLabel: 'Status',
                values: Status.values,
                selected: {_status},
                glyphOf: statusGlyph,
                onTap: (s) {
                  setState(() => _status = s);
                  unawaited(_persist());
                },
              ),
              const SizedBox(height: 12),
              GlyphChips<Priority>(
                heading: kPriorityHeadingIcon,
                semanticLabel: 'Priority',
                values: Priority.values,
                selected: {_priority},
                glyphOf: (p) => priorityGlyph(context, p),
                onTap: (p) {
                  setState(() => _priority = p);
                  unawaited(_persist());
                },
              ),
              NoteTaskDetails(note: widget.note),
              const SizedBox(height: 16),
              Align(
                child: IconButton.outlined(
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(
                    Icons.delete_outline,
                    semanticLabel: 'Delete note',
                  ),
                  onPressed: () async {
                    if (!await confirmDeleteNote(context)) return;
                    await widget.onDelete();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
