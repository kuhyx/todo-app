import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/note_form.dart';

/// Full-screen view of a single note: read it in full, edit its body through
/// the shared [NoteForm], change its priority/status, or delete it.
///
/// Edits persist immediately (matching the capture screen's autosave), so
/// there is no explicit save button. The template is detected from the note's
/// text, falling back to a raw editor for freeform/legacy notes.
class NoteDetailScreen extends StatefulWidget {
  /// Creates a [NoteDetailScreen] editing [note].
  const NoteDetailScreen({
    required this.note,
    required this.repository,
    required this.appSettings,
    super.key,
  });

  /// The note being viewed/edited.
  final Note note;

  /// The store edits persist to.
  final NoteRepository repository;

  /// Drives whether the metadata row and editor chrome are shown. Required,
  /// not defaulted: this screen silently defaulting it to "advanced" is
  /// exactly what made editing look different from capture.
  final ValueNotifier<AppSettings> appSettings;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late Note _note = widget.note;

  Future<void> _persist(Note next) async {
    setState(() => _note = next);
    await widget.repository.upsert(next);
  }

  Future<void> _onTextChanged(String text) =>
      _persist(_note.copyWith(text: text, updatedAt: DateTime.now()));

  Future<void> _delete() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete note?',
      message: 'This cannot be undone.',
    );
    if (!confirmed) return;
    await widget.repository.delete(_note.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = noteTitle(_note.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? '(empty)' : title),
        actions: [
          IconButton(
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        // The same form capture renders, gated on the same setting, so an
        // edited note and a fresh one cannot look different.
        child: ValueListenableBuilder<AppSettings>(
          valueListenable: widget.appSettings,
          builder: (context, settings, _) => NoteForm(
            advancedMode: settings.advancedMode,
            initialText: _note.text,
            priority: _note.priority,
            status: _note.status,
            onPriorityChanged: (p) => _persist(
              _note.copyWith(priority: p, updatedAt: DateTime.now()),
            ),
            onStatusChanged: (s) =>
                _persist(_note.copyWith(status: s, updatedAt: DateTime.now())),
            onChanged: _onTextChanged,
          ),
        ),
      ),
    );
  }
}
