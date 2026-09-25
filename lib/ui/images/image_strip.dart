import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/images/image_ref.dart';
import 'package:todo/ui/images/image_embed.dart';

/// Height of the thumbnail row under the editor.
const kImageStripHeight = 88.0;

/// A row of thumbnails for every image [text] links to, shown under the
/// editing field so a note's pictures are visible while writing it. The
/// editing modes show the links as text; without this the default (Raw)
/// mode would never show an image at all. Empty when there are none.
class ImageStrip extends StatelessWidget {
  /// Creates the strip for [text].
  const ImageStrip({required this.text, super.key});

  /// The note text being edited.
  final String text;

  @override
  Widget build(BuildContext context) {
    final refs = imageRefsIn(text).toList();
    if (refs.isEmpty) return const SizedBox.shrink();
    // Same centred column as the editor above it (rule 21), so on the wide
    // desktop window the thumbnails sit under the text, not at the far edge.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kProseMaxWidth,
            maxHeight: kImageStripHeight,
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: refs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: kImageStripHeight,
              child: ImageEmbed(ref: refs[i]),
            ),
          ),
        ),
      ),
    );
  }
}
