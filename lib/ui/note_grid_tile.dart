/// One compact tile of the notes grid: title plus priority and status cues.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';

/// A note as a grid cell. It fills whatever cell it is given.
class NoteGridTile extends StatelessWidget {
  /// Creates a tile for [note].
  const NoteGridTile({
    required this.note,
    required this.onTap,
    required this.onActions,
    super.key,
  });

  /// The note this tile displays.
  final Note note;

  /// Open the full note.
  final VoidCallback onTap;

  /// Open the per-note sheet (body, dates, priority/status, delete).
  final VoidCallback onActions;

  /// Danger for high, the accent for medium, muted for low.
  Color accentFor(ColorScheme scheme) => switch (note.priority) {
    Priority.high => scheme.error,
    Priority.medium => scheme.primary,
    Priority.low => scheme.outline,
  };

  static IconData _statusIcon(Status s) => switch (s) {
    Status.todo => Icons.radio_button_unchecked,
    Status.inProgress => Icons.timelapse,
    Status.done => Icons.check_circle_outline,
    Status.abandoned => Icons.cancel_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = noteTitle(note.text);
    final cue = theme.textTheme.labelSmall;
    final closed =
        note.status == Status.done || note.status == Status.abandoned;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onActions,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentFor(scheme), width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expanded: a big text scale shortens the title, never overflows.
              Expanded(
                child: Text(
                  title.isEmpty ? '(empty)' : title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: closed ? scheme.onSurfaceVariant : null,
                    decoration: closed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (note.repoName case final repo?)
                Text(
                  repo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cue?.copyWith(color: scheme.onSurfaceVariant),
                ),
              Row(
                children: [
                  Icon(
                    _statusIcon(note.status),
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      note.status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cue,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    note.priority.label,
                    maxLines: 1,
                    style: cue?.copyWith(color: accentFor(scheme)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
