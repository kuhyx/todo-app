/// One compact tile of the notes grid: title plus priority and status cues.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/enum_glyphs.dart';

/// Danger for high, the accent for medium, muted for low.
Color priorityColor(Priority p, ColorScheme scheme) => switch (p) {
  Priority.high => scheme.error,
  Priority.medium => scheme.primary,
  Priority.low => scheme.outline,
};

/// Painted in place of an empty note's title: a mark, not a word.
const String kEmptyTitle = '…';

/// The glyph standing for [s] wherever a status is shown without words.
IconData statusIcon(Status s) => switch (s) {
  Status.todo => Icons.radio_button_unchecked,
  Status.inProgress => Icons.timelapse,
  Status.done => Icons.check_circle_outline,
  Status.abandoned => Icons.cancel_outlined,
};

/// A note as a grid cell. It fills whatever cell it is given.
class NoteGridTile extends StatelessWidget {
  /// Creates a tile for [note].
  const NoteGridTile({
    required this.note,
    required this.onTap,
    required this.onActions,
    this.selected = false,
    super.key,
  });

  /// Whether the note is part of the multi-selection: a tint and a check.
  final bool selected;

  /// The note this tile displays.
  final Note note;

  /// Open the full note.
  final VoidCallback onTap;

  /// Open the per-note sheet (body, dates, priority/status, delete).
  final VoidCallback onActions;

  /// Danger for high, the accent for medium, muted for low.
  Color accentFor(ColorScheme scheme) => priorityColor(note.priority, scheme);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = noteTitle(note.text);
    final cue = theme.textTheme.labelSmall;
    final closed =
        note.status == Status.done || note.status == Status.abandoned;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? kEmptyTitle : title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: closed ? scheme.onSurfaceVariant : null,
                          decoration: closed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: scheme.primary,
                        semanticLabel: 'Selected',
                      ),
                  ],
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
                  // Shape + the tile's accent border carry status/priority;
                  // the enum words survive only as spoken labels.
                  Icon(
                    statusIcon(note.status),
                    size: 14,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: note.status.label,
                  ),
                  const Spacer(),
                  Icon(
                    priorityIcon(note.priority),
                    size: 14,
                    color: accentFor(scheme),
                    semanticLabel: note.priority.label,
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
