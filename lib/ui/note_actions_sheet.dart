/// The per-note actions sheet shown from the notes list.
///
/// Split out of `notes_list_screen.dart` for file size; public only because
/// Dart privacy is library-scoped.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              firstLine.isEmpty ? '(empty)' : firstLine,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            _EnumChips<Status>(
              label: 'Status',
              values: Status.values,
              selected: {_status},
              labelOf: (s) => s.label,
              onSelected: (s) {
                setState(() => _status = s);
                unawaited(_persist());
              },
            ),
            const SizedBox(height: 12),
            _EnumChips<Priority>(
              label: 'Priority',
              values: Priority.values,
              selected: {_priority},
              labelOf: (p) => p.label,
              onSelected: (p) {
                setState(() => _priority = p);
                unawaited(_persist());
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete note'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                final confirmed = await confirmDestructive(
                  context,
                  title: 'Delete note?',
                  message: 'This cannot be undone.',
                );
                if (!confirmed) return;
                await widget.onDelete();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-select chip row for an enum (used for per-note priority/status).
class _EnumChips<T> extends StatelessWidget {
  const _EnumChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: selected.contains(v),
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    );
  }
}
