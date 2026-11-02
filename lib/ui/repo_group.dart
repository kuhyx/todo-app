/// Display-only grouping of the notes list: every note sharing a `repo`
/// collapses into one [RepoEntry]; notes without a repo stay [NoteEntry]s.
///
/// Storage is untouched -- each note keeps its own done_check and closes
/// individually. Grouping runs on the already filtered/sorted list, so a
/// group only counts notes that passed the active filters.
library;

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';

/// One row of the notes list.
sealed class ListEntry {
  const ListEntry();
}

/// A plain note shown as its own row.
final class NoteEntry extends ListEntry {
  /// Wraps [note].
  const NoteEntry(this.note);

  /// The note this row stands for.
  final Note note;
}

/// All notes of one repo, shown as a single row.
final class RepoEntry extends ListEntry {
  /// Groups [notes], which all carry [repo].
  const RepoEntry(this.repo, this.notes);

  /// The full `owner/name` repo.
  final String repo;

  /// Group members in list order.
  final List<Note> notes;

  /// Repo name without its owner.
  String get name => repo.split('/').last;
}

/// Collapses [notes] (already filtered and sorted) into rows. A repo's row
/// takes the position of its first note.
List<ListEntry> groupByRepo(List<Note> notes) {
  final groups = <String, List<Note>>{};
  final entries = <ListEntry>[];
  for (final n in notes) {
    final repo = n.repo;
    if (repo == null) {
      entries.add(NoteEntry(n));
    } else if (groups[repo] case final members?) {
      members.add(n);
    } else {
      final members = groups[repo] = [n];
      entries.add(RepoEntry(repo, members));
    }
  }
  return entries;
}

/// One plain-text block for [notes]: title, body and `id: <id8>` per task,
/// tasks separated by a blank line.
String repoClipboardText(List<Note> notes) {
  return notes.map(_block).join('\n\n');
}

String _block(Note n) {
  final body = n.text.split('\n').skip(1).join('\n').trim();
  final id = n.id.length <= 8 ? n.id : n.id.substring(0, 8);
  return [noteTitle(n.text), if (body.isNotEmpty) body, 'id: $id'].join('\n');
}
