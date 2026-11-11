/// The Created / Last-updated date-range control used by the filter sheet.
///
/// Split out of `notes_list_screen.dart` for file size. Public only because
/// Dart privacy is library-scoped and the filter sheet now lives in a
/// different file.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Glyph for "created" (a note added), shared by the filter and sort menus.
const IconData kCreatedIcon = Icons.post_add;

/// Glyph for "last updated", shared by the filter and sort menus.
const IconData kUpdatedIcon = Icons.update;

/// A labelled date range shown as one preset menu plus a custom picker.
class DateRangeField extends StatelessWidget {
  /// Creates a labelled date-range control.
  const DateRangeField({
    required this.icon,
    required this.semanticLabel,
    required this.from,
    required this.to,
    required this.onChanged,
    super.key,
  });

  /// Glyph shown in the control's border in place of a written heading.
  final IconData icon;

  /// Spoken name of the control (e.g. 'Created'); never painted.
  final String semanticLabel;

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

  /// Which menu entry describes the current range.
  _Preset get _current {
    if (!_hasRange) return _Preset.any;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final p in _Preset.dayPresets) {
      final days = p.days!;
      if (to == today && from == today.subtract(Duration(days: days - 1))) {
        return p;
      }
    }
    return _Preset.custom;
  }

  void _select(BuildContext context, _Preset preset) {
    switch (preset) {
      case _Preset.any:
        onChanged(null, null);
      case _Preset.custom:
        unawaited(_pickCustom(context));
      case _Preset.today || _Preset.week || _Preset.month:
        _applyDays(preset.days!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    // A popup menu rather than DropdownButton: re-picking "Custom…" while a
    // custom range is shown must still reopen the picker.
    return PopupMenuButton<_Preset>(
      // Empty, not the label: a tooltip is painted on long-press.
      tooltip: '',
      onSelected: (p) => _select(context, p),
      itemBuilder: (_) => [
        for (final p in _Preset.values)
          PopupMenuItem(value: p, child: Text(p.label)),
      ],
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: Icon(icon, semanticLabel: semanticLabel),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          current == _Preset.custom ? _rangeLabel() : current.label,
          style: theme.textTheme.bodyMedium,
        ),
      ),
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

/// Entries of the range menu, in display order.
enum _Preset {
  any('Any', null),
  today('Today', 1),
  week('7 days', 7),
  month('30 days', 30),
  custom('Custom…', null);

  const _Preset(this.label, this.days);

  final String label;
  final int? days;

  static const List<_Preset> dayPresets = [today, week, month];
}
