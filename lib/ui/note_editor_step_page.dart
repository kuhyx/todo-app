/// The guided stepper's full-screen per-step view.
///
/// Split out of `note_editor.dart` for file size. Stateless on purpose: the
/// controllers, the current step and the template all stay owned by
/// `_NoteEditorState`, and are passed in — this widget only lays them out.
///
/// Returned directly from the editor's `build` so the [TextField] is a
/// first-level [Expanded] child of THIS column, the same depth as the raw
/// editor's. Nesting it inside a second Column broke the flutter constraint
/// chain in release builds (the inner Expanded got 0 height), so the flat
/// structure here is load-bearing rather than incidental.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_template.dart';

/// One step of the guided editor: label, guidance, input, and navigation.
class NoteEditorStepPage extends StatelessWidget {
  /// Creates the step view for [section], step [index] of [total].
  const NoteEditorStepPage({
    required this.section,
    required this.controller,
    required this.index,
    required this.total,
    required this.autofocus,
    required this.onChanged,
    required this.onGoToStep,
    required this.onExit,
    super.key,
  });

  /// The template section this step edits.
  final TemplateSection section;

  /// Controller for this section's text, owned by the editor.
  final TextEditingController controller;

  /// Zero-based index of this step, already clamped to the section range.
  final int index;

  /// How many steps the template has in total.
  final int total;

  /// Whether the input should take focus on first build.
  final bool autofocus;

  /// Called on every keystroke so the editor can re-emit the assembled text.
  final VoidCallback onChanged;

  /// Called with the step index to move to.
  final ValueChanged<int> onGoToStep;

  /// Called by the back arrow and by "Done" on the last step.
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Back arrow — only exit from guided mode.
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Exit guided',
            onPressed: onExit,
          ),
        ),
        // Progress bar + step counter.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text('${index + 1} / $total', style: theme.textTheme.labelMedium),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(value: (index + 1) / total),
              ),
            ],
          ),
        ),
        // Section label + helper text.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.isTitle ? 'title' : section.label,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                section.helper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        // TextField fills all remaining space — directly in this Column's
        // Expanded, same as the raw editor, so expands:true works correctly.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TextField(
              controller: controller,
              autofocus: autofocus && index == 0,
              expands: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: section.hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        // Navigation buttons — sibling of Expanded so keyboard pushes them up.
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (index > 0)
                TextButton(
                  onPressed: () => onGoToStep(index - 1),
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (index < total - 1)
                FilledButton(
                  onPressed: () => onGoToStep(index + 1),
                  child: const Text('Next'),
                )
              else
                FilledButton(onPressed: onExit, child: const Text('Done')),
            ],
          ),
        ),
      ],
    );
  }
}
