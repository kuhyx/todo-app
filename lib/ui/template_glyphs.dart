/// Glyphs standing for note templates and their sections in the editor.
///
/// The section labels stay in `note_template.dart`: they are the note's own
/// `## heading` format, read by `parse()`, BACKLOG.md and the CLI. Only what
/// the editor paints around them is a glyph; the label and helper are spoken.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_template.dart';

/// The glyph for template [t]: a structured form, or a blank page.
IconData templateIcon(NoteTemplate t) =>
    t.isFreeform ? Icons.note_outlined : Icons.assignment_outlined;

/// [t] as its glyph, spoken as its label.
Widget templateGlyph(NoteTemplate t) =>
    Icon(templateIcon(t), semanticLabel: t.label);

/// The glyph heading a guided step, keyed by the section's stable `key`.
IconData sectionIcon(TemplateSection s) => switch (s.key) {
  'title' => Icons.title,
  'what' => Icons.lightbulb_outline,
  'where' => Icons.place_outlined,
  'must' => Icons.rule,
  'done' => Icons.emoji_events_outlined,
  'verify' => Icons.devices,
  'refs' => Icons.menu_book_outlined,
  _ => Icons.notes,
};
