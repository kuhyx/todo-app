/// A note's metadata controls: the priority/status row and the generic
/// dropdown behind it.
///
/// Shared by both editing surfaces -- capture and the detail screen -- so the
/// two cannot drift apart. Public only because Dart privacy is library-scoped.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/enum_glyphs.dart';

/// A compact dropdown for picking an enum value (priority/status), headed by
/// a glyph and showing each value as its glyph.
///
/// Generic over the enum type [T] so the same control drives both pickers
/// without duplication; [glyphOf] maps a value to its glyph.
class MetaDropdown<T> extends StatelessWidget {
  /// Creates a dropdown showing [value] out of [values].
  const MetaDropdown({
    required this.heading,
    required this.semanticLabel,
    required this.value,
    required this.values,
    required this.glyphOf,
    required this.onChanged,
    super.key,
  });

  /// Glyph in the control's border in place of a written heading.
  final IconData heading;

  /// Spoken name of the control; never painted.
  final String semanticLabel;

  /// Currently selected value.
  final T value;

  /// Every selectable value.
  final List<T> values;

  /// Maps a value to its glyph.
  final Widget Function(T) glyphOf;

  /// Called with the newly picked value.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        prefixIcon: Icon(heading, semanticLabel: semanticLabel),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final v in values)
              DropdownMenuItem<T>(value: v, child: glyphOf(v)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// A note's priority and status pickers, side by side.
///
/// Lays the row out and nothing else: whether it is visible at all is
/// [NoteFormChromeGate]'s job, not this widget's.
class NoteMetaRow extends StatelessWidget {
  /// Creates the metadata row for the current values.
  const NoteMetaRow({
    required this.priority,
    required this.status,
    required this.onPriorityChanged,
    required this.onStatusChanged,
    super.key,
  });

  /// The note's current priority.
  final Priority priority;

  /// The note's current status.
  final Status status;

  /// Called with a newly picked priority.
  final ValueChanged<Priority> onPriorityChanged;

  /// Called with a newly picked status.
  final ValueChanged<Status> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetaDropdown<Priority>(
            heading: kPriorityHeadingIcon,
            semanticLabel: 'Priority',
            value: priority,
            values: Priority.values,
            glyphOf: (p) => priorityGlyph(context, p),
            onChanged: onPriorityChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetaDropdown<Status>(
            heading: kStatusHeadingIcon,
            semanticLabel: 'Status',
            value: status,
            values: Status.values,
            glyphOf: statusGlyph,
            onChanged: onStatusChanged,
          ),
        ),
      ],
    );
  }
}
