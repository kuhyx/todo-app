/// Partial logs for the multi-note writes: merged in one store write.
///
/// Each write re-serialises the whole log (over a megabyte on a real
/// device), so a bulk action must be one partial log merged once, never one
/// upsert per note. Merging is per field, so a field left out keeps its value
/// and its clock (`created_by` included).
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_record.dart';

/// Partial records setting [priority] and/or [status] on the live notes of
/// [log] among [ids], all at [hlc].
///
/// Only fields whose value changes are written, plus `updated_at` = [now]
/// (so "last updated" sorting and newer-wins import see the edit). A note
/// with nothing to change, an unknown id and a deleted note are left out.
Log planBulkUpdate(
  Log log,
  Set<String> ids, {
  required Hlc hlc,
  required DateTime now,
  Priority? priority,
  Status? status,
}) {
  final plan = <String, Record>{};
  for (final id in ids) {
    final current = log[id];
    if (current == null || current.deleted) continue;
    final note = noteFromRecord(current);
    final next = note.copyWith(priority: priority, status: status);
    if (next.priority == note.priority && next.status == note.status) continue;
    // Generated against generated, never against the stored text: a peer's
    // `...00Z` (or a web build's millisecond date) would otherwise read as
    // a change and get a fresh clock, erasing the `created_at` node signal.
    final before = noteFields(note, hlc);
    plan[id] = Record(
      id: id,
      fields: {
        for (final MapEntry(:key, :value) in noteFields(
          next.copyWith(updatedAt: now),
          hlc,
        ).entries)
          if (before[key]?.$1 != value.$1) key: value,
      },
    );
  }
  return plan;
}

/// [note] at [hlc] plus a tombstone for each live note of [log] in
/// [removed] (other than [note] itself).
///
/// A merge, not a replace: a field [note] leaves unset keeps its stored
/// value, so this suits notes that only gain content (the repo note an
/// assign appends to), not edits that clear a field.
Log planReplace(Log log, Note note, Iterable<String> removed, Hlc hlc) => {
  for (final id in removed)
    if (log[id] case final r? when !r.deleted && id != note.id)
      id: Record(id: id, fields: const {}, deleted: true, deletedHlc: hlc),
  note.id: Record(id: note.id, fields: noteFields(note, hlc)),
};
