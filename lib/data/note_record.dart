/// Note <-> crdt_sync [Record] mapping; re-exported by `note_repository.dart`.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/data/note.dart';

const _text = 'text';
const _priority = 'priority';
const _status = 'status';
const _createdAt = 'created_at';
const _updatedAt = 'updated_at';
const _repo = 'repo';
const _doneCheck = 'done_check';
const _by = 'by';
const _evidence = 'evidence';

/// Record field naming who filed the note (`kuhy` or `claude`).
const kCreatedByField = 'created_by';

/// Record fields for [note], all at [hlc]. Unset task fields are omitted, so
/// an idea's record is exactly the v3 field set (and cannot clear a peer's).
Map<String, Field> noteFields(Note note, Hlc hlc) => {
  _text: (note.text, hlc),
  _priority: (note.priority.value, hlc),
  _status: (note.status.value, hlc),
  _createdAt: (note.createdAt.toIso8601String(), hlc),
  _updatedAt: (note.updatedAt.toIso8601String(), hlc),
  if (note.repo case final v?) _repo: (v, hlc),
  if (note.doneCheck case final v?) _doneCheck: (v, hlc),
  if (note.by case final v?) _by: (v, hlc),
  if (note.evidence case final v?) _evidence: (v, hlc),
  if (note.createdBy case final v?) kCreatedByField: (v, hlc),
};

/// Reads [record] as a [Note], ignoring unknown fields.
Note noteFromRecord(Record record) {
  final fields = record.fields;
  String? str(String name) => fields[name]?.$1 as String?;
  // '' is how a peer clears a task field: omitting it never clears.
  String? task(String name) => switch (str(name)) {
    '' => null,
    final v => v,
  };
  return Note(
    id: record.id,
    text: str(_text) ?? '',
    priority: Priority.fromValue(fields[_priority]?.$1 as int?),
    status: Status.fromValue(fields[_status]?.$1 as int?),
    createdAt: _parseDate(str(_createdAt)),
    updatedAt: _parseDate(str(_updatedAt)),
    repo: task(_repo),
    doneCheck: task(_doneCheck),
    by: task(_by),
    evidence: task(_evidence),
    createdBy: task(kCreatedByField),
  );
}

DateTime _parseDate(String? iso) =>
    iso == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.parse(iso);
