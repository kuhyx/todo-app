/// Icon-only confirmation before deleting a note.
///
/// Replaces design_system's `confirmDestructive` here because that dialog
/// paints its title, message and button labels as text. The safety contract
/// is kept: Cancel is autofocused (a reflexive Return keeps the note), Escape
/// and the barrier answer "no", and the confirm glyph wears the error colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks whether to delete a note; true only when the delete glyph is pressed.
Future<bool> confirmDeleteNote(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConfirmDeleteDialog(),
  );
  return confirmed ?? false;
}

class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog();

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
      },
      child: AlertDialog(
        // Spoken when the dialog opens; the old written body.
        semanticLabel: 'This cannot be undone.',
        title: Icon(
          Icons.delete_forever,
          size: 40,
          color: error,
          semanticLabel: 'Delete note?',
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton(
            key: const ValueKey('confirm-cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
          ),
          IconButton(
            key: const ValueKey('confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icon(Icons.delete, color: error, semanticLabel: 'Delete'),
          ),
        ],
      ),
    );
  }
}
