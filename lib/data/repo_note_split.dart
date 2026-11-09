/// `new_note`: a repo task in its own open note, `<name> todos: <title>`,
/// so it can close on its own done_check. A title that already heads an open
/// section of another separate note of the repo merges into that note
/// instead (it keeps its id); the shared `<name> todos` note never counts.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:uuid/uuid.dart';

/// How a separate add landed.
enum SplitKind {
  /// A new separate note.
  added,

  /// Appended to the separate note that already had the title.
  merged,

  /// A new separate note because the duplicate's note was busy.
  fellBack,
}

/// The note to save, how it landed, and why it fell back.
typedef SplitAdd = ({Note note, SplitKind kind, String? why});

final _heading = RegExp(r'^##\s+(\[x\]\s+)?(.*)$');

/// Every `## title` heading of [text] outside code fences, open or done.
Iterable<RegExpMatch> _sections(String text) sync* {
  var fenced = false;
  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('```')) fenced = !fenced;
    final m = fenced ? null : _heading.firstMatch(line);
    if (m != null) yield m;
  }
}

/// The open `## title` headings of [text], outside code fences.
Iterable<String> openSections(String text) => _sections(
  text,
).where((m) => m.group(1) == null).map((m) => m.group(2)!.trim());

/// How many board items [text] splits into: one per section, done or not.
int sectionCount(String text) => _sections(text).length;

/// The separate open note of [repo] with an open section titled [title].
Note? duplicateTarget(Iterable<Note> open, String repo, String title) {
  final hits =
      open
          .where((n) => n.repo == repo && isSeparateNote(n))
          .where((n) => openSections(n.text).contains(title.trim()))
          .toList()
        ..sort(byAge);
  return hits.isEmpty ? null : hits.first;
}

/// Why a merged task must not be started, or null when it may be.
String? startBlock(String? doneCheck, String body) {
  final check = (doneCheck ?? '').trim().toLowerCase();
  if (check.isEmpty || check == 'none') return 'done_check is none';
  final first = body
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  return first.trim().toLowerCase().startsWith('low priority')
      ? 'marked low priority'
      : null;
}

/// Adds the task as its own note, or merges it into the duplicate's note
/// unless [busy] says a board session is working on it.
Future<SplitAdd> addSeparateTask(
  NoteRepository repository, {
  required String repo,
  required String title,
  String body = '',
  String? doneCheck,
  Priority priority = Priority.medium,
  String? by,
  Future<bool> Function(Note note)? busy,
}) async {
  final section = repoSection(title, body);
  final open = await repository.listNotes(
    filter: NoteFilter(statuses: kOpenStatuses, repo: repo),
  );
  final target = duplicateTarget(open, repo, title);
  String? why;
  if (target != null) {
    if (busy == null || !await busy(target)) {
      return (
        note: target.copyWith(
          text: '${target.text}\n\n$section',
          doneCheck: composeDoneCheck(target.doneCheck, doneCheck),
          priority: maxPriority(target.priority, priority),
        ),
        kind: SplitKind.merged,
        why: null,
      );
    }
    why =
        'not merged into ${target.id.substring(0, 8)}: '
        'a board session is running on it';
  }
  final now = DateTime.now();
  return (
    note: Note(
      id: const Uuid().v4(),
      text: '${separateNoteTitle(repo, title)}\n\n$section',
      priority: priority,
      status: Status.todo,
      createdAt: now,
      updatedAt: now,
      repo: repo,
      doneCheck: composeDoneCheck(null, doneCheck),
      by: by,
    ),
    kind: why == null ? SplitKind.added : SplitKind.fellBack,
    why: why,
  );
}
