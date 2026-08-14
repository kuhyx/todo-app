/// The capture screen's metadata controls: the priority/status row and the
/// generic dropdown behind it.
///
/// Split out of `capture_status.dart` for file size. Public only because Dart
/// privacy is library-scoped.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';

/// A compact labelled dropdown for picking an enum value (priority/status).
///
/// Generic over the enum type [T] so the same control drives both pickers
/// without duplication; [labelOf] maps a value to its display string.
class MetaDropdown<T> extends StatelessWidget {
  /// Creates a dropdown showing [value] out of [values].
  const MetaDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    super.key,
  });

  /// Label shown above the control.
  final String label;

  /// Currently selected value.
  final T value;

  /// Every selectable value.
  final List<T> values;

  /// Maps a value to its display string.
  final String Function(T) labelOf;

  /// Called with the newly picked value.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
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
              DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// The draft's priority and status pickers, side by side.
///
/// Hidden together with the editor's own chrome while the bare guided
/// stepper or its entry wizard is up, so the top of the screen stays free of
/// noise -- the screen decides that; this only lays the row out.
class CaptureMetaRow extends StatelessWidget {
  /// Creates the metadata row for the current draft values.
  const CaptureMetaRow({
    required this.priority,
    required this.status,
    required this.onPriorityChanged,
    required this.onStatusChanged,
    super.key,
  });

  /// The draft's current priority.
  final Priority priority;

  /// The draft's current status.
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
            label: 'Priority',
            value: priority,
            values: Priority.values,
            labelOf: (p) => p.label,
            onChanged: onPriorityChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetaDropdown<Status>(
            label: 'Status',
            value: status,
            values: Status.values,
            labelOf: (s) => s.label,
            onChanged: onStatusChanged,
          ),
        ),
      ],
    );
  }
}
