/// The one-open-note-per-repo invariant. Single add path for the MCP
/// `add_task` and the CLI `--repo` add; callers persist and push.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:uuid/uuid.dart';

/// Statuses that count as open.
const Set<Status> kOpenStatuses = {Status.todo, Status.inProgress};

/// The repo note's title.
String repoNoteTitle(String repo) => '${repo.split('/').last} todos';

/// A `new_note` task's own note title: `<name> todos: <title>`.
String separateNoteTitle(String repo, String title) =>
    '${repoNoteTitle(repo)}: ${title.trim()}';

/// Whether [note] is a `new_note` note, which the shared add path and the
/// one-time merge leave alone.
bool isSeparateNote(Note note) {
  final repo = note.repo;
  return repo != null &&
      splitNote(note.text).title.startsWith('${repoNoteTitle(repo)}: ');
}

/// Joins two checks with `&&`; either may be absent.
String? composeDoneCheck(String? older, String? newer) {
  final a = (older ?? '').trim();
  final b = (newer ?? '').trim();
  if (a.isEmpty) return b.isEmpty ? null : b;
  return b.isEmpty ? a : '( $a ) && ( $b )';
}

/// A `## title` section.
String repoSection(String title, String body) {
  final text = body.trim();
  return text.isEmpty ? '## $title' : '## $title\n$text';
}

/// The higher priority.
Priority maxPriority(Priority a, Priority b) => a.value >= b.value ? a : b;

/// Title line and rest of a note's text.
({String title, String body}) splitNote(String text) {
  final lines = text.split('\n');
  final first = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (first < 0) return (title: '', body: '');
  return (
    title: lines[first].trim().replaceFirst(RegExp(r'^#+\s*'), ''),
    body: lines.skip(first + 1).join('\n').trim(),
  );
}

/// Oldest first; ties broken by id so the choice is deterministic.
int byAge(Note a, Note b) {
  final c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// The note to save and whether it was appended.
typedef RepoAdd = ({Note note, bool appended});

/// Appends the task to [repo]'s oldest open shared note, or builds that
/// note; separate (`new_note`) notes are never joined.
Future<RepoAdd> addRepoTask(
  NoteRepository repository, {
  required String repo,
  required String title,
  String body = '',
  String? doneCheck,
  Priority priority = Priority.medium,
  String? by,
  String? createdBy,
}) async {
  final section = repoSection(title, body);
  final open = (await repository.listNotes(
    filter: NoteFilter(statuses: kOpenStatuses, repo: repo),
  )).where((n) => !isSeparateNote(n)).toList();
  if (open.isNotEmpty) {
    final existing = (open..sort(byAge)).first;
    return (
      note: existing.copyWith(
        text: '${existing.text}\n\n$section',
        doneCheck: composeDoneCheck(existing.doneCheck, doneCheck),
        priority: maxPriority(existing.priority, priority),
      ),
      appended: true,
    );
  }
  final now = DateTime.now();
  return (
    note: Note(
      id: const Uuid().v4(),
      text: '${repoNoteTitle(repo)}\n\n$section',
      priority: priority,
      status: Status.todo,
      createdAt: now,
      updatedAt: now,
      repo: repo,
      doneCheck: composeDoneCheck(null, doneCheck),
      by: by,
      createdBy: createdBy,
    ),
    appended: false,
  );
}
