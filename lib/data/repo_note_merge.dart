/// One-time migration plan: one open note per repo, oldest id kept.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/repo_note.dart';

/// The rewritten oldest note and the originals to delete.
typedef RepoMerge = ({Note kept, List<Note> removed});

/// A merge for every repo whose open notes are not yet one `<name> todos`
/// note; running it on its own result yields an empty plan. Separate
/// (`new_note`) notes stay out of it.
List<RepoMerge> planRepoMerges(Iterable<Note> notes) {
  final byRepo = <String, List<Note>>{};
  for (final n in notes) {
    final repo = n.repo;
    if (repo != null &&
        kOpenStatuses.contains(n.status) &&
        !isSeparateNote(n)) {
      byRepo.putIfAbsent(repo, () => []).add(n);
    }
  }
  final plan = <RepoMerge>[];
  for (final MapEntry(key: repo, value: group) in byRepo.entries) {
    group.sort(byAge);
    final title = repoNoteTitle(repo);
    if (group.length == 1 && splitNote(group.single.text).title == title) {
      continue;
    }
    plan.add((kept: _merged(title, group), removed: group.sublist(1)));
  }
  return plan;
}

Note _merged(String title, List<Note> group) {
  var doneCheck = group.first.doneCheck;
  var priority = group.first.priority;
  final sections = <String>[];
  for (final (i, n) in group.indexed) {
    final (title: t, :body) = splitNote(n.text);
    // An already-merged note keeps its sections as they are.
    sections.add(t == title ? body : repoSection(t, body));
    if (i > 0) {
      doneCheck = composeDoneCheck(doneCheck, n.doneCheck);
      priority = maxPriority(priority, n.priority);
    }
  }
  return group.first.copyWith(
    text: '$title\n\n${sections.where((s) => s.isNotEmpty).join('\n\n')}',
    doneCheck: doneCheck,
    priority: priority,
  );
}
