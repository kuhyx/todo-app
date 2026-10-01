import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/images/attachment_links.dart';
import 'package:todo/ui/images/file_embed.dart';
import 'package:todo/ui/images/image_embed.dart';

/// Height of the thumbnail row under the editor.
const kAttachmentStripHeight = 88.0;

/// A row of tiles for every attachment [text] links to — thumbnails for
/// images, icon-and-name tiles for files — shown under the editing field so a
/// note's attachments are visible (and files openable) while writing it. The
/// editing modes show the links as text; without this the default (Raw)
/// mode would never show one at all. Empty when there are none.
class AttachmentStrip extends StatelessWidget {
  /// Creates the strip for [text].
  const AttachmentStrip({required this.text, super.key});

  /// The note text being edited.
  final String text;

  @override
  Widget build(BuildContext context) {
    final attachments = attachmentsIn(text);
    if (attachments.isEmpty) return const SizedBox.shrink();
    // Same centred column as the editor above it (rule 21), so on the wide
    // desktop window the thumbnails sit under the text, not at the far edge.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kProseMaxWidth,
            maxHeight: kAttachmentStripHeight,
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: kAttachmentStripHeight,
              child: attachments[i].isImage
                  ? ImageEmbed(ref: attachments[i].ref)
                  : FileEmbed(attachment: attachments[i], compact: true),
            ),
          ),
        ),
      ),
    );
  }
}
