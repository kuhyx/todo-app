import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/note_repository.dart';
import '../data/note_template.dart';
import 'note_editor.dart';

/// Full-screen view of a single note: read it in full, edit its body through
/// the guided [NoteEditor], change its priority/status, or delete it.
///
/// Edits persist immediately (matching the capture screen's autosave), so
/// there is no explicit save button. The template is detected from the note's
/// text, falling back to a raw editor for freeform/legacy notes.
class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({
    required this.note,
    required this.repository,
    super.key,
  });

  final Note note;
  final NoteRepository repository;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late Note _note = widget.note;

  /// Hides the Priority/Status row while the editor's own bare-guided chrome
  /// (template/mode selectors) is also hidden, so the two stay in lockstep.
  bool _chromeVisible = true;

  Future<void> _persist(Note next) async {
    setState(() => _note = next);
    await widget.repository.upsert(next);
  }

  Future<void> _onTextChanged(String text) =>
      _persist(_note.copyWith(text: text, updatedAt: DateTime.now()));

  Future<void> _delete() async {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_chromeVisible) ...[
              Row(
                children: [
                  Expanded(
                    child: _MetaDropdown<Priority>(
                      label: 'Priority',
                      value: _note.priority,
                      values: Priority.values,
                      labelOf: (p) => p.label,
                      onChanged: (p) => _persist(
                        _note.copyWith(priority: p, updatedAt: DateTime.now()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetaDropdown<Status>(
                      label: 'Status',
                      value: _note.status,
                      values: Status.values,
                      labelOf: (s) => s.label,
                      onChanged: (s) => _persist(
                        _note.copyWith(status: s, updatedAt: DateTime.now()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: NoteEditor(
                initialText: _note.text,
                initialMode: NoteEditorMode.raw,
                priority: _note.priority,
                onPriorityChanged: (p) => _persist(
                  _note.copyWith(priority: p, updatedAt: DateTime.now()),
                ),
                onChromeVisibleChanged: (visible) =>
                    setState(() => _chromeVisible = visible),
                onChanged: _onTextChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact labelled dropdown for picking an enum value (priority/status).
class _MetaDropdown<T> extends StatelessWidget {
  const _MetaDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
