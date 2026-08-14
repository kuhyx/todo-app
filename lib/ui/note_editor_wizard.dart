/// The two-step wizard shown before the guided stepper on an empty draft.
///
/// Split out of `note_editor.dart` for file size. It owns its own step index
/// and pending choices — the editor only cares about the two values that come
/// back out, so keeping that state here rather than in `_NoteEditorState` is
/// both smaller and better scoped.
///
/// Priority and template are asked once, up front, because those choices only
/// make sense before there is anything to guide.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';

/// Asks for a priority, then a template, then hands both back via [onStart].
class NoteEditorWizard extends StatefulWidget {
  /// Creates the wizard seeded with [initialPriority] and [initialTemplate].
  const NoteEditorWizard({
    required this.initialPriority,
    required this.initialTemplate,
    required this.onStart,
    required this.onCancel,
    super.key,
  });

  /// Priority the first step opens on.
  final Priority initialPriority;

  /// Template the second step opens on.
  final NoteTemplate initialTemplate;

  /// Called with both choices when the user presses "Start".
  final void Function(Priority priority, NoteTemplate template) onStart;

  /// Called when the user dismisses the wizard.
  final VoidCallback onCancel;

  @override
  State<NoteEditorWizard> createState() => _NoteEditorWizardState();
}

class _NoteEditorWizardState extends State<NoteEditorWizard> {
  late int _step = 0;
  late Priority _priority = widget.initialPriority;
  late NoteTemplate _template = widget.initialTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: widget.onCancel,
            ),
            Text('Step ${_step + 1} of 2', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        if (_step == 0) ..._priorityStep() else ..._templateStep(),
      ],
    );
  }

  List<Widget> _priorityStep() {
    return [
      DropdownButtonFormField<Priority>(
        initialValue: _priority,
        decoration: const InputDecoration(
          labelText: 'Priority',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          for (final p in Priority.values)
            DropdownMenuItem(value: p, child: Text(p.label)),
        ],
        onChanged: (p) {
          if (p != null) setState(() => _priority = p);
        },
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('Next'),
        ),
      ),
    ];
  }

  List<Widget> _templateStep() {
    final templates = NoteTemplate.all.where((t) => !t.isFreeform).toList();
    return [
      DropdownButtonFormField<String>(
        initialValue: _template.id,
        decoration: const InputDecoration(
          labelText: 'Template',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          for (final t in templates)
            DropdownMenuItem(value: t.id, child: Text(t.label)),
        ],
        onChanged: (id) {
          if (id == null) return;
          setState(() => _template = templates.firstWhere((t) => t.id == id));
        },
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => widget.onStart(_priority, _template),
            child: const Text('Start'),
          ),
        ],
      ),
    ];
  }
}
