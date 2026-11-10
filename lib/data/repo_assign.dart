/// Assigning plain notes to a repo from the UI: each becomes a `## title`
/// section of the repo's one open note ([addRepoTask]), and the original goes.
///
/// Only the data layer: nothing here talks to the board or starts a task.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';

final _repoShape = RegExp(r'^[\w.-]+/[\w.-]+$');
final _heading = RegExp(r'^(#+)(\s.*)$');

/// Whether [value] looks like `owner/name`.
bool isRepoName(String value) => _repoShape.hasMatch(value.trim());

/// [body] with every heading outside code fences pushed below `##`.
///
/// A repo note splits into tasks at `##` headings, so a template note's own
/// `## what` / `## must` would otherwise turn into tasks of their own.
String demoteHeadings(String body) {
  var fenced = false;
  final out = <String>[];
  for (final line in body.split('\n')) {
    if (line.trimLeft().startsWith('```')) fenced = !fenced;
    final m = fenced ? null : _heading.firstMatch(line);
    if (m == null) {
      out.add(line);
      continue;
    }
    final level = m.group(1)!.length;
    out.add('${'#' * (level < 2 ? 3 : level + 1)}${m.group(2)}');
  }
  return out.join('\n');
}

/// Moves the plain [notes] into [repo]'s open note in one write, creating
/// that note when the repo has none; returns the notes refused because
/// they already belong to a repo (left untouched).
Future<List<Note>> assignToRepo(
  NoteRepository repository,
  List<Note> notes,
  String repo,
) async {
  final refused = [
    for (final n in notes)
      if (n.repo != null) n,
  ];
  final plain = [
    for (final n in notes)
      if (n.repo == null) n,
  ];
  if (plain.isEmpty) return refused;
  final first = splitNote(plain.first.text);
  var target = (await addRepoTask(
    repository,
    repo: repo,
    title: first.title,
    body: demoteHeadings(first.body),
    priority: plain.first.priority,
    createdBy: 'kuhy',
  )).note;
  for (final n in plain.skip(1)) {
    final (:title, :body) = splitNote(n.text);
    target = target.copyWith(
      text: '${target.text}\n\n${repoSection(title, demoteHeadings(body))}',
      priority: maxPriority(target.priority, n.priority),
    );
  }
  await repository.saveReplacing(
    target.copyWith(updatedAt: DateTime.now()),
    plain.map((n) => n.id),
  );
  return refused;
}
