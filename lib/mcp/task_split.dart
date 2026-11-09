/// `add_task` with `new_note: true`: the separate note, the guard merge and
/// the board Start that follows a merge, as one reply text.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note_split.dart';
import 'package:todo/mcp/board_client.dart';

/// Saves [note] and returns `<verb> <id>` plus its list line.
typedef SaveNote = Future<String> Function(Note note, String verb);

/// A saved split add: its reply so far, and the board Start still to run.
/// The caller runs [start] after releasing its lock, since the board learns
/// about the merged section by calling this same server (T1865).
typedef SplitReply = ({String reply, Future<String> Function()? start});

/// Adds a separate task, merging into a duplicate's note when it is idle;
/// a merge that may run comes back with the Start to click on the board.
Future<SplitReply> addSplit(
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
    return (
      reply: added.why == null ? reply : '$reply\n${added.why}',
      start: null,
    );
  }
  final reply = await save(added.note, 'merged into');
  final block = startBlock(doneCheck, body);
  if (block != null) {
    return (reply: '$reply\nstart: skipped ($block)', start: null);
  }
  Future<String> start() async {
    final s = board == null
        ? (ok: false, reason: 'no board configured', item: null)
        : await board.start(
            added.note.id,
            title.trim(),
            sections: sectionCount(added.note.text),
          );
    if (s.ok) return 'start: ok ${s.item}';
    return 'start: {ok: false, reason: "${s.reason}"}; '
        'the merge is saved, click Start on the board by hand';
  }

  return (reply: reply, start: start);
}
