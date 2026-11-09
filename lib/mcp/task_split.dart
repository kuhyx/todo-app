/// `add_task` with `new_note: true`: the separate note, the guard merge and
/// the board Start that follows a merge, as one reply text.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note_split.dart';
import 'package:todo/mcp/board_client.dart';

/// Saves [note] and returns `<verb> <id>` plus its list line.
typedef SaveNote = Future<String> Function(Note note, String verb);

/// Adds a separate task, merging into a duplicate's note when it is idle,
/// and clicks Start on the board after a merge that may run.
Future<String> addSplit(
  NoteRepository repository,
  BoardClient? board,
  SaveNote save, {
  required String repo,
  required String title,
  required String body,
  required String? doneCheck,
  required Priority priority,
}) async {
  final added = await addSeparateTask(
    repository,
    repo: repo,
    title: title,
    body: body,
    doneCheck: doneCheck,
    priority: priority,
    by: 'claude',
    busy: board == null ? null : (n) => board.running(n.id),
  );
  if (added.kind != SplitKind.merged) {
    final reply = await save(added.note, 'added');
    return added.why == null ? reply : '$reply\n${added.why}';
  }
  final reply = await save(added.note, 'merged into');
  final block = startBlock(doneCheck, body);
  if (block != null) return '$reply\nstart: skipped ($block)';
  final start = board == null
      ? (ok: false, reason: 'no board configured', item: null)
      : await board.start(
          added.note.id,
          title.trim(),
          sections: sectionCount(added.note.text),
        );
  if (start.ok) return '$reply\nstart: ok ${start.item}';
  return '$reply\nstart: {ok: false, reason: "${start.reason}"}; '
      'the merge is saved, click Start on the board by hand';
}
