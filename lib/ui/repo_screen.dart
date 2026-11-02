/// A repo's tasks on one screen, with a copy-all action.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/note_tile.dart';
import 'package:todo/ui/notes_list_navigation.dart';
import 'package:todo/ui/repo_group.dart';

/// Lists the tasks of [repo] that pass the list's active [filter].
///
/// Display only: each task is still its own note, opened with the usual
/// detail screen. The copy action puts every listed task (title, body and
/// `id: <id8>`) on the clipboard as one plain-text block.
class RepoScreen extends StatefulWidget {
  /// Creates the screen for [repo], narrowed by the list's [filter]/[sort].
  const RepoScreen({
    required this.repo,
    required this.filter,
    required this.sort,
    required this.repository,
    required this.appSettings,
    super.key,
  });

  /// The full `owner/name` repo.
  final String repo;

  /// The notes list's active filter; the repo is added on top.
  final NoteFilter filter;

  /// The notes list's sort order.
  final NoteSort sort;

  /// The store the tasks live in.
  final NoteRepository repository;

  /// Passed on to the note detail screen.
  final ValueNotifier<AppSettings> appSettings;

  @override
  State<RepoScreen> createState() => _RepoScreenState();
}

class _RepoScreenState extends State<RepoScreen> {
  late final Stream<List<Note>> _stream = widget.repository.watchNotes(
    sort: widget.sort,
    filter: widget.filter.copyWith(repo: widget.repo),
  );
  List<Note> _notes = const [];
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: repoClipboardText(_notes)));
    await HapticFeedback.lightImpact();
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repo.split('/').last),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: Icon(_copied ? Icons.check : Icons.copy_all),
            onPressed: _copy,
          ),
        ],
      ),
      body: StreamBuilder<List<Note>>(
        stream: _stream,
        builder: (context, snapshot) {
          _notes = snapshot.data ?? const <Note>[];
          return ListView.separated(
            itemCount: _notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = _notes[i];
              return NoteTile(
                key: ValueKey(n.id),
                note: n,
                showRepo: false,
                onTap: () =>
                    openNote(context, n, widget.repository, widget.appSettings),
                onActions: () => openNoteActions(context, n, widget.repository),
              );
            },
          );
        },
      ),
    );
  }
}
