/// One attached non-image file as it appears in a note: an icon for its
/// type, its name and size. Tapping opens it (see `file_opening.dart`).
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/ui/images/file_opening.dart';
import 'package:todo/ui/images/image_embed.dart';

/// Opens an attached file; returns why it could not, or null.
typedef FileOpening = Future<String?> Function(ImageSource source, String name);

/// Renders the file [attachment] from the nearest [ImageStoreScope].
class FileEmbed extends StatefulWidget {
  /// Creates an embed: a full-width row inline, or a square tile when
  /// [compact] (the strip under the editor). [opening] is injectable.
  const FileEmbed({
    required this.attachment,
    this.compact = false,
    this.opening = openAttachedFile,
    super.key,
  });

  /// The file to show.
  final Attachment attachment;

  /// Square tile instead of a row.
  final bool compact;

  /// What a tap does.
  final FileOpening opening;

  @override
  State<FileEmbed> createState() => _FileEmbedState();
}

class _FileEmbedState extends State<FileEmbed> {
  late Future<int?> _size;

  // Re-asked whenever the store notifies (a download may have landed), not
  // on every rebuild: on desktop each ask is a request to the wrapper.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _size = ImageStoreScope.of(context).sizeOf(widget.attachment.ref);
  }

  Future<void> _open(ImageSource source) async {
    final failure = await widget.opening(source, widget.attachment.name);
    if (failure != null && mounted) showError(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    final store = ImageStoreScope.of(context);
    final attachment = widget.attachment;
    final theme = Theme.of(context);
    return FutureBuilder<int?>(
      future: _size,
      builder: (context, snapshot) {
        final size = snapshot.data;
        final detail = size == null ? kImageNotDownloaded : formatBytes(size);
        final icon = Icon(fileIconFor(attachment.ref.extension));
        final name = Text(
          attachment.name,
          maxLines: widget.compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: widget.compact ? TextAlign.center : TextAlign.start,
          style: widget.compact ? theme.textTheme.bodySmall : null,
        );
        final pending = store.isPending(attachment.ref)
            ? const Tooltip(
                message: kImageWaitingToUpload,
                child: Icon(Icons.cloud_upload_outlined, size: 18),
              )
            : null;
        final content = widget.compact
            ? Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(height: AppSpacing.xs),
                        name,
                      ],
                    ),
                  ),
                  if (pending != null)
                    Positioned(right: 0, top: 0, child: pending),
                ],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        Text(detail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  ?pending,
                ],
              );
        return Semantics(
          label: 'Attached file ${attachment.name}, $detail',
          button: size != null,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: size == null
                  ? null
                  : () => _open(store.sourceFor(attachment.ref)),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [bytes] as a short human size: `512 B`, `1.2 KB`, `34 MB`, `2.1 GB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// The icon for a file with [extension].
IconData fileIconFor(String extension) => switch (extension) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'mp4' ||
  'm4v' ||
  'webm' ||
  'mov' ||
  'mkv' ||
  'avi' ||
  'ogv' => Icons.movie_outlined,
  'mp3' ||
  'm4a' ||
  'ogg' ||
  'oga' ||
  'opus' ||
  'wav' ||
  'flac' ||
  'aac' => Icons.audiotrack_outlined,
  'txt' || 'md' || 'log' || 'csv' || 'json' => Icons.description_outlined,
  'zip' || 'tar' || 'gz' || '7z' || 'rar' || 'xz' => Icons.folder_zip_outlined,
  'png' ||
  'gif' ||
  'webp' ||
  'bmp' ||
  'svg' ||
  'psd' ||
  'heic' ||
  'tif' => Icons.image_outlined,
  _ => Icons.insert_drive_file_outlined,
};
