/// Who filed a note, for notes written before `created_by` existed.
///
/// The `created_at` field's clock names the node that last wrote it. The MCP
/// and the CLI are the only nodes Claude writes through, so a note created
/// there carries one of their node ids; anything else came from kuhy's own
/// devices.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/data/note_record.dart';

const _createdAt = 'created_at';

/// `claude` when [record]'s `created_at` was written by one of [claudeNodes],
/// else `kuhy`.
String classifyCreatedBy(Record record, Set<String> claudeNodes) {
  final node = record.fields[_createdAt]?.$2.nodeId;
  return node != null && claudeNodes.contains(node) ? 'claude' : 'kuhy';
}

/// Live records of [log] with no `created_by` yet, mapped to their value.
Map<String, String> planCreatedByBackfill(Log log, Set<String> claudeNodes) => {
  for (final record in log.values)
    if (!record.deleted &&
        ((record.fields[kCreatedByField]?.$1 as String?) ?? '').isEmpty)
      record.id: classifyCreatedBy(record, claudeNodes),
};

/// [incoming], carrying [existing]'s `created_by` when [incoming] has none.
///
/// A store replaces a record wholesale, so an edit that does not know the
/// field (an import of an old backup) would otherwise drop it locally.
Record keepCreatedBy(Record incoming, Record? existing) {
  final kept = existing?.fields[kCreatedByField];
  if (kept == null || incoming.fields.containsKey(kCreatedByField)) {
    return incoming;
  }
  return Record(
    id: incoming.id,
    fields: {...incoming.fields, kCreatedByField: kept},
    deleted: incoming.deleted,
    deletedHlc: incoming.deletedHlc,
  );
}
