/// The 📎 button: pick photos from the camera or gallery, or any file
/// (Android), or any file from disk (desktop), and hand them on.
library;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

export 'package:file_selector/file_selector.dart' show XFile;

/// Where the phone takes an attachment from.
enum AttachmentPickSource {
  /// A new photo.
  camera,

  /// Existing photos, several at once.
  gallery,

  /// Any files, several at once, from the system file picker.
  file,
}

/// Picks files and returns them; empty when the user cancels.
///
/// Injectable so widget tests never reach a platform picker.
typedef AttachmentPicking = Future<List<XFile>> Function(BuildContext context);

/// The platform picker: a Camera/Gallery/File sheet on Android, an
/// unfiltered multi-select file dialog on the desktop (web) build.
///
/// [fromPhone] is the platform call behind the sheet, injectable for tests.
Future<List<XFile>> pickAttachments(
  BuildContext context, {
  Future<List<XFile>> Function(AttachmentPickSource) fromPhone = _pickFromPhone,
}) async {
  // The desktop build has no sheet: straight to the file dialog.
  if (kIsWeb) return await openFiles(); // coverage:ignore-line
  final source = await showModalBottomSheet<AttachmentPickSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, AttachmentPickSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, AttachmentPickSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('File'),
            onTap: () => Navigator.pop(context, AttachmentPickSource.file),
          ),
        ],
      ),
    ),
  );
  if (source == null) return const [];
  return await fromPhone(source);
}

// coverage:ignore-start
// Thin calls into platform pickers with no test binding; the sheet above and
// everything downstream of the returned files are covered.
//
// "File" uses file_picker, not file_selector: file_selector's Android side
// reads the whole file into memory on the UI thread (an `int`-sized byte
// array, then across the platform channel), so a large pick crashes the app.
// file_picker streams it into the cache directory on a background thread.
Future<List<XFile>> _pickFromPhone(AttachmentPickSource source) async {
  final picker = ImagePicker();
  return switch (source) {
    AttachmentPickSource.camera => [
      ?await picker.pickImage(source: ImageSource.camera),
    ],
    AttachmentPickSource.gallery => await picker.pickMultiImage(),
    AttachmentPickSource.file => [
      for (final file in await FilePicker.pickFiles()) file.xFile,
    ],
  };
}
// coverage:ignore-end

/// App-bar action that picks attachments and passes them to [onFiles].
class AttachButton extends StatelessWidget {
  /// Creates the button; [picking] defaults to [pickAttachments].
  const AttachButton({required this.onFiles, this.picking, super.key});

  /// Receives the picked files (never called for a cancelled pick).
  final ValueChanged<List<XFile>> onFiles;

  /// The picker, injectable for tests.
  final AttachmentPicking? picking;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Attach',
      icon: const Icon(Icons.attach_file),
      onPressed: () async {
        final files = await (picking ?? pickAttachments)(context);
        if (files.isNotEmpty) onFiles(files);
      },
    );
  }
}
