/// The 📎 button: pick images from the camera or gallery (Android) or from
/// disk (desktop), and hand their bytes on.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Where the phone takes an image from.
enum ImagePickSource {
  /// A new photo.
  camera,

  /// Existing photos, several at once.
  gallery,
}

/// Picks images and returns their bytes; empty when the user cancels.
///
/// Injectable so widget tests never reach a platform picker.
typedef ImagePicking = Future<List<Uint8List>> Function(BuildContext context);

/// The platform picker: a Camera/Gallery sheet on Android, a multi-select
/// file dialog filtered to images on the desktop (web) build.
///
/// [fromPhone] is the platform call behind the sheet, injectable for tests.
Future<List<Uint8List>> pickImages(
  BuildContext context, {
  Future<List<Uint8List>> Function(ImagePickSource) fromPhone = _pickFromPhone,
}) async {
  // The desktop build has no sheet: straight to the file dialog.
  if (kIsWeb) return await _pickFiles(); // coverage:ignore-line
  final source = await showModalBottomSheet<ImagePickSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImagePickSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImagePickSource.gallery),
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
// everything downstream of the returned bytes are covered.
Future<List<Uint8List>> _pickFromPhone(ImagePickSource source) async {
  final picker = ImagePicker();
  final files = switch (source) {
    ImagePickSource.camera => [
      ?await picker.pickImage(source: ImageSource.camera),
    ],
    ImagePickSource.gallery => await picker.pickMultiImage(),
  };
  return [for (final file in files) await file.readAsBytes()];
}

Future<List<Uint8List>> _pickFiles() async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', mimeTypes: ['image/*']),
    ],
  );
  return [for (final file in files) await file.readAsBytes()];
}
// coverage:ignore-end

/// App-bar action that picks images and passes them to [onImages].
class AttachImageButton extends StatelessWidget {
  /// Creates the button; [picking] defaults to [pickImages].
  const AttachImageButton({required this.onImages, this.picking, super.key});

  /// Receives the picked images (never called for a cancelled pick).
  final ValueChanged<List<Uint8List>> onImages;

  /// The picker, injectable for tests.
  final ImagePicking? picking;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Attach image',
      icon: const Icon(Icons.attach_file),
      onPressed: () async {
        final images = await (picking ?? pickImages)(context);
        if (images.isNotEmpty) onImages(images);
      },
    );
  }
}
