/// The selection bar's assign flow: pick a repo, move the notes into it.
///
/// Data-layer only ([assignToRepo]); the UI never reaches the board, so an
/// assign never starts a task.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_assign.dart';
import 'package:todo/ui/note_selection.dart';
import 'package:todo/ui/repo_picker_sheet.dart';

/// Asks for a repo and assigns the selected plain notes to it, in
/// selection order. True when some notes were refused (already in a repo);
/// those stay selected, the moved ones leave the selection.
Future<bool> assignSelection(
  BuildContext context,
  NoteRepository repository,
  NoteSelection selection,
) async {
  final all = await repository.listNotes();
  final repos = {for (final n in all) ?n.repo}.toList()..sort();
  if (!context.mounted) return false;
  final repo = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RepoPickerSheet(repos: repos),
  );
  if (repo == null) return false;
  final byId = {for (final n in all) n.id: n};
  final chosen = [for (final id in selection.ids) ?byId[id]];
  final refused = await assignToRepo(repository, chosen, repo);
  selection.retain({for (final n in refused) n.id});
  return refused.isNotEmpty;
}
