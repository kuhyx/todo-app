/// How notes are selected and ordered: the sort modes, the filter, and the
/// pure predicates behind them.
///
/// Split out of `note_repository.dart` for file size; that file re-exports
/// this one, so callers import it as before. Everything here is pure -- it
/// takes notes and a filter and returns a decision -- which is what made it
/// the natural seam.
library;

import 'package:todo/data/note.dart';

/// How the history list should be ordered.
enum NoteSort {
  /// Newest created first.
  createdDesc,

  /// Most recently modified first.
  modifiedDesc,

  /// A-Z by note text.
  alphabetical,

  /// Highest [Priority] first.
  priorityDesc,
}

/// An immutable set of constraints for querying notes.
///
/// All fields combine with logical AND. Empty/null fields impose no
/// constraint. Lives in the data layer so the filtering it drives never leaks
/// into the UI. Construct copies with [copyWith] when toggling one facet.
class NoteFilter {
  /// Creates a [NoteFilter] from its constraint fields.
  const NoteFilter({
    this.query = '',
    this.priorities = const {},
    this.statuses = const {},
    this.createdFrom,
    this.createdTo,
    this.updatedFrom,
    this.updatedTo,
  });

  /// Case-insensitive substring matched against the note body.
  final String query;

  /// Notes must have one of these priorities. Empty means "any priority".
  final Set<Priority> priorities;

  /// Notes must have one of these statuses. Empty means "any status".
  final Set<Status> statuses;

  /// Inclusive lower bound (by calendar day) on the creation date.
  final DateTime? createdFrom;

  /// Inclusive upper bound (by calendar day) on the creation date.
  final DateTime? createdTo;

  /// Inclusive lower bound (by calendar day) on the last-updated date.
  final DateTime? updatedFrom;

  /// Inclusive upper bound (by calendar day) on the last-updated date.
  final DateTime? updatedTo;

  /// True when no constraint is active (the unfiltered, full list).
  bool get isEmpty =>
      query.trim().isEmpty &&
      priorities.isEmpty &&
      statuses.isEmpty &&
      createdFrom == null &&
      createdTo == null &&
      updatedFrom == null &&
      updatedTo == null;

  /// Number of distinct active facets, for an "N filters" badge in the UI.
  int get activeCount {
    var n = 0;
    if (query.trim().isNotEmpty) n++;
    if (priorities.isNotEmpty) n++;
    if (statuses.isNotEmpty) n++;
    if (createdFrom != null || createdTo != null) n++;
    if (updatedFrom != null || updatedTo != null) n++;
    return n;
  }

  /// Returns a copy with selected facets replaced. A `null` argument keeps
  /// the current value; clearing a date is done via the dedicated clear
  /// flags so `null` can mean "unchanged".
  NoteFilter copyWith({
    String? query,
    Set<Priority>? priorities,
    Set<Status>? statuses,
    DateTime? createdFrom,
    DateTime? createdTo,
    DateTime? updatedFrom,
    DateTime? updatedTo,
    bool clearCreated = false,
    bool clearUpdated = false,
  }) {
    return NoteFilter(
      query: query ?? this.query,
      priorities: priorities ?? this.priorities,
      statuses: statuses ?? this.statuses,
      createdFrom: clearCreated ? null : (createdFrom ?? this.createdFrom),
      createdTo: clearCreated ? null : (createdTo ?? this.createdTo),
      updatedFrom: clearUpdated ? null : (updatedFrom ?? this.updatedFrom),
      updatedTo: clearUpdated ? null : (updatedTo ?? this.updatedTo),
    );
  }
}

/// Whether [note] passes every clause of [filter].
///
/// Clauses are AND-combined, and an empty clause matches everything -- an
/// empty priority set means "any priority", not "no priorities".
bool matchesFilter(Note note, NoteFilter filter) {
  final query = filter.query.trim().toLowerCase();
  if (query.isNotEmpty && !note.text.toLowerCase().contains(query)) {
    return false;
  }
  if (filter.priorities.isNotEmpty &&
      !filter.priorities.contains(note.priority)) {
    return false;
  }
  if (filter.statuses.isNotEmpty && !filter.statuses.contains(note.status)) {
    return false;
  }
  if (!_withinDays(note.createdAt, filter.createdFrom, filter.createdTo)) {
    return false;
  }
  if (!_withinDays(note.updatedAt, filter.updatedFrom, filter.updatedTo)) {
    return false;
  }
  return true;
}

/// Inclusive day-granularity range check, matching the old SQL bounds:
/// `from` includes its whole day; `to` includes its whole day.
bool _withinDays(DateTime value, DateTime? from, DateTime? to) {
  if (from != null && value.isBefore(_startOfDay(from))) return false;
  if (to != null &&
      !value.isBefore(_startOfDay(to).add(const Duration(days: 1)))) {
    return false;
  }
  return true;
}

/// The comparator implementing [sort].
Comparator<Note> comparatorFor(NoteSort sort) {
  switch (sort) {
    case NoteSort.createdDesc:
      return (a, b) => b.createdAt.compareTo(a.createdAt);
    case NoteSort.modifiedDesc:
      return (a, b) => b.updatedAt.compareTo(a.updatedAt);
    case NoteSort.alphabetical:
      return (a, b) => a.text.toLowerCase().compareTo(b.text.toLowerCase());
    case NoteSort.priorityDesc:
      return (a, b) {
        final byPriority = b.priority.value.compareTo(a.priority.value);
        return byPriority != 0
            ? byPriority
            : b.updatedAt.compareTo(a.updatedAt);
      };
  }
}

/// Midnight (local) of [t]'s calendar day.
DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
