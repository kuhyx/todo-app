/// Navigation out of the notes list: the detail screen and the actions sheet.
///
/// Split out of `notes_list_screen.dart` for file size. Plain functions rather
/// than methods because neither needs the screen's state -- they only need a
/// context, the note, and the store.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/note_actions_sheet.dart';
import 'package:todo/ui/note_detail_screen.dart';

/// Opens the full note: read it, edit the body, change priority/status.
Future<void> openNote(
  BuildContext context,
  Note note,
  NoteRepository repository,
  ValueNotifier<AppSettings> appSettings,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NoteDetailScreen(
        note: note,
        repository: repository,
        appSettings: appSettings,
      ),
    ),
  );
}

/// Opens the per-note quick-actions sheet (priority, status, delete).
Future<void> openNoteActions(
  BuildContext context,
  Note note,
  NoteRepository repository,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Scroll-controlled so the sheet can exceed the default 9/16 of the
    // viewport. On a 768px-tall screen that default is only ~432px, and this
    // sheet's content grows with the note title and its chip rows -- an
    // unscrollable sheet would clip the Delete action out of reach.
    isScrollControlled: true,
    builder: (_) => NoteActionsSheet(
      note: note,
      onChanged: (updated) async {
        await repository.upsert(updated);
      },
      onDelete: () async {
        await repository.delete(note.id);
      },
    ),
  );
}
