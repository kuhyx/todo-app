/// Glyphs for the Priority and Status enums, and the chip row that picks
/// them, so every picker shows the same shape + colour for the same value.
///
/// The enum's `label` survives only as the spoken (semantics) label.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';

/// Shape channel for a priority: up for high, level for medium, down for low.
/// Colour ([priorityColor]) is the second channel.
IconData priorityIcon(Priority p) => switch (p) {
  Priority.high => Icons.keyboard_double_arrow_up,
  Priority.medium => Icons.drag_handle,
  Priority.low => Icons.keyboard_double_arrow_down,
};

/// Heading glyph standing for "status" (matches the bulk-status button).
const IconData kStatusHeadingIcon = Icons.task_alt;

/// Heading glyph standing for "priority" (matches the bulk-priority button).
const IconData kPriorityHeadingIcon = Icons.flag_outlined;

/// [s] as its glyph, spoken as its label.
Widget statusGlyph(Status s, {double? size}) =>
    Icon(statusIcon(s), size: size, semanticLabel: s.label);

/// [p] as its tinted glyph, spoken as its label.
Widget priorityGlyph(BuildContext context, Priority p, {double? size}) => Icon(
  priorityIcon(p),
  size: size,
  color: priorityColor(p, Theme.of(context).colorScheme),
  semanticLabel: p.label,
);

/// A heading glyph followed by one chip per value, each chip a glyph.
///
/// [multi] switches between FilterChips (toggle many) and ChoiceChips (pick
/// one); either way the selected chips are filled and checked.
class GlyphChips<T> extends StatelessWidget {
  /// Creates a chip row for [values].
  const GlyphChips({
    required this.heading,
    required this.semanticLabel,
    required this.values,
    required this.selected,
    required this.glyphOf,
    required this.onTap,
    this.multi = false,
    super.key,
  });

  /// Glyph shown in front of the chips in place of a written heading.
  final IconData heading;

  /// Spoken name of the row (the old written heading).
  final String semanticLabel;

  /// Every value offered.
  final List<T> values;

  /// Values currently selected.
  final Set<T> selected;

  /// Builds the glyph for one value.
  final Widget Function(T) glyphOf;

  /// Called with the tapped value.
  final ValueChanged<T> onTap;

  /// Whether this is a multi-select (filter) row.
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(heading, semanticLabel: semanticLabel),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              for (final v in values)
                if (multi)
                  FilterChip(
                    label: glyphOf(v),
                    selected: selected.contains(v),
                    onSelected: (_) => onTap(v),
                  )
                else
                  ChoiceChip(
                    label: glyphOf(v),
                    selected: selected.contains(v),
                    onSelected: (_) => onTap(v),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
