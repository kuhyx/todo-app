import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/note_repository.dart';

/// Barebones list of all stored/synced notes, newest-modified first.
///
/// Deliberately minimal for now (the rich history view with filter/sort by
/// created/modified/alphabetical/priority is deferred). Its job today is to
/// show that synced items actually landed locally.
class NotesListScreen extends StatelessWidget {
  const NotesListScreen({required this.repository, super.key});

  final NoteRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: StreamBuilder<List<Note>>(
        stream: repository.watchNotes(),
        builder: (context, snapshot) {
          final notes = snapshot.data ?? const <Note>[];
          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet'));
          }
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final note = notes[i];
              final firstLine = note.text.split('\n').first;
              return ListTile(
                title: Text(
                  firstLine.isEmpty ? '(empty)' : firstLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('edited ${_relative(note.updatedAt)}'),
              );
            },
          );
        },
      ),
    );
  }

  /// Compact relative time like "2m ago" for the list subtitle.
  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
