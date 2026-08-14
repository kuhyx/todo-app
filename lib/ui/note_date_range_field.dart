/// The Created / Last-updated date-range control used by the filter sheet.
///
/// Split out of `notes_list_screen.dart` for file size. Public only because
/// Dart privacy is library-scoped and the filter sheet now lives in a
/// different file.
library;

import 'package:flutter/material.dart';

/// A labelled date range shown as presets plus a custom-range picker.
class DateRangeField extends StatelessWidget {
  /// Creates a labelled date-range control.
  const DateRangeField({
    required this.label,
    required this.from,
    required this.to,
    required this.onChanged,
    super.key,
  });

  /// Heading shown above the control (e.g. 'Created').
  final String label;

  /// Start of the selected range, or null when unbounded.
  final DateTime? from;

  /// End of the selected range, or null when unbounded.
  final DateTime? to;

  /// Called with the new (from, to); either may be null to clear.
  final void Function(DateTime? from, DateTime? to) onChanged;

  bool get _hasRange => from != null || to != null;

  /// Sets a preset range of the last [days] days ending today.
  void _applyDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    onChanged(today.subtract(Duration(days: days - 1)), today);
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: (from != null && to != null)
          ? DateTimeRange(start: from!, end: to!)
          : null,
    );
    if (picked != null) onChanged(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const Spacer(),
            if (_hasRange)
              Text(_rangeLabel(), style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Today'),
              onPressed: () => _applyDays(1),
            ),
            ActionChip(
              label: const Text('7 days'),
              onPressed: () => _applyDays(7),
            ),
            ActionChip(
              label: const Text('30 days'),
              onPressed: () => _applyDays(30),
            ),
            ActionChip(
              label: const Text('Custom…'),
              onPressed: () => _pickCustom(context),
            ),
            if (_hasRange)
              ActionChip(
                avatar: const Icon(Icons.clear, size: 16),
                label: const Text('Any'),
                onPressed: () => onChanged(null, null),
              ),
          ],
        ),
      ],
    );
  }

  /// Compact "YYYY-MM-DD → YYYY-MM-DD" (or one-sided) summary of the range.
  String _rangeLabel() {
    String d(DateTime? t) =>
        t == null ? '…' : '${t.year}-${_two(t.month)}-${_two(t.day)}';
    return '${d(from)} → ${d(to)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
