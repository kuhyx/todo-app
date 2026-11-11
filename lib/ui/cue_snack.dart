/// Transient feedback as a glyph, not a sentence (kuhy's textgate rule).
///
/// The design system's `showToast`/`showError` paint a message; this paints
/// an icon (plus an optional number) and keeps the old sentence as the
/// spoken label only. Colour is the second channel: errors use the danger
/// hue and stay up longer, as `showError` does.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

const Duration _toastDuration = Duration(seconds: 3);
const Duration _errorDuration = Duration(seconds: 5);

/// Shows [icon] (and [count], if given) in a snack bar; [spoken] is what a
/// screen reader says. Returns quietly when no `ScaffoldMessenger` is above
/// [context] (an async callback outliving its screen).
void showCue(
  BuildContext context,
  IconData icon,
  String spoken, {
  bool error = false,
  int? count,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colors = context.statusColors;
  final fg = error ? colors.onStatus : null;
  // Replace rather than queue: a queued cue describes an action the user
  // has already moved on from.
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Semantics(
          label: spoken,
          excludeSemantics: true,
          // Its own node: otherwise the label merges into the snack bar's.
          container: true,
          child: Row(
            children: [
              Icon(icon, color: fg),
              if (count != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text('$count', style: TextStyle(color: fg)),
              ],
            ],
          ),
        ),
        backgroundColor: error ? colors.danger : null,
        duration: error ? _errorDuration : _toastDuration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
}
