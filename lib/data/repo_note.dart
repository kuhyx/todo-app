/// The one-open-note-per-repo invariant. Single add path for the MCP
/// `add_task` and the CLI `--repo` add; callers persist and push.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/note_template.dart';
import 'package:uuid/uuid.dart';

/// Statuses that count as open.
const Set<Status> kOpenStatuses = {Status.todo, Status.inProgress};

/// The repo note's title.
String repoNoteTitle(String repo) => '${repo.split('/').last} todos';

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
({String title, String body}) splitNote(String text) =>
    (title: noteTitle(text), body: text.split('\n').skip(1).join('\n').trim());

/// Oldest first; ties broken by id so the choice is deterministic.
int byAge(Note a, Note b) {
  final c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// The note to save and whether it was appended.
typedef RepoAdd = ({Note note, bool appended});

/// Appends the task to [repo]'s oldest open note, or builds that note.
Future<RepoAdd> addRepoTask(
  NoteRepository repository, {
  required String repo,
  required String title,
  String body = '',
  String? doneCheck,
  Priority priority = Priority.medium,
  String? by,
}) async {
  final section = repoSection(title, body);
  final open = await repository.listNotes(
    filter: NoteFilter(statuses: kOpenStatuses, repo: repo),
  );
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
    ),
    appended: false,
  );
}
