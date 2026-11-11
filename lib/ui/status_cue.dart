/// A screen's latest result as a glyph in place of a status sentence.
library;

import 'package:flutter/material.dart';

/// One result: what to paint, whether it is a failure, and the old
/// sentence, kept as the spoken label only.
class StatusCue {
  /// Creates a cue.
  const StatusCue(this.icon, this.spoken, {this.error = false});

  /// A success: a check glyph in the accent colour.
  const StatusCue.ok(this.spoken) : icon = Icons.check_circle, error = false;

  /// A failure: an error glyph in the danger hue.
  const StatusCue.failed(this.spoken) : icon = Icons.error, error = true;

  /// The glyph painted.
  final IconData icon;

  /// What a screen reader says.
  final String spoken;

  /// Whether this is a failure (danger hue) rather than a success.
  final bool error;
}

/// Paints [cue] as a large glyph; colour is the second channel.
class StatusCueView extends StatelessWidget {
  /// Creates the view.
  const StatusCueView(this.cue, {super.key});

  /// The result shown.
  final StatusCue cue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Icon(
        cue.icon,
        size: 32,
        color: cue.error ? scheme.error : scheme.primary,
        semanticLabel: cue.spoken,
      ),
    );
  }
}
