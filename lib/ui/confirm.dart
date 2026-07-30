/// Confirmation for destructive actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the user to confirm a destructive action, returning true if they do.
///
/// Exists because "delete note" had no confirmation and no undo on either
/// path: the actions sheet and the detail screen both deleted immediately.
/// With a pointer that is merely risky — you have to travel to the control and
/// press it. With a keyboard it is one Tab away from a Return you were about
/// to press anyway, and the note is gone with nothing to recover it.
///
/// Defaults are chosen so the *safe* option is what a reflexive keypress hits:
/// Cancel is autofocused, and Escape dismisses. The destructive button is
/// styled with the error color but is deliberately not the default action.
///
/// Returns false when dismissed by Escape, by the barrier, or by Cancel.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Escape dismisses as "no". Flutter's own barrier handles this on most
      // platforms, but the desktop surface here is a Chrome `--app` window
      // where that cannot be assumed, and a confirmation the keyboard cannot
      // back out of is worse than no confirmation at all.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
      },
      child: AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            // Autofocused so the reflexive Return presses Cancel, not Delete.
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
