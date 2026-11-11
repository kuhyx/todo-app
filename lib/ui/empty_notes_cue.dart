/// The notes list's empty state as a picture, not a sentence.
library;

import 'package:flutter/material.dart';

/// A large muted glyph: an empty inbox when there are no notes at all, a
/// crossed-out filter when the current filter hides every note (the filter
/// button's badge is the second channel saying a filter is on).
class EmptyNotesCue extends StatelessWidget {
  /// Creates the cue; [filtered] picks the filter variant.
  const EmptyNotesCue({required this.filtered, super.key});

  /// Whether a filter is active (notes may exist but none match).
  final bool filtered;

  @override
  Widget build(BuildContext context) => Icon(
    filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
    size: 64,
    color: Theme.of(context).colorScheme.outline,
    semanticLabel: filtered ? 'No notes match these filters' : 'No notes yet',
  );
}
