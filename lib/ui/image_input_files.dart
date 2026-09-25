/// Which of a paste's or drop's files are images: split out of the web-only
/// listener so the decision is unit-testable on the VM.
library;

/// Indices of the files whose MIME type is an image, and how many were not.
///
/// Order is preserved: files dropped together are attached in the order the
/// browser lists them.
({List<int> images, int rejected}) partitionImageFiles(List<String> mimeTypes) {
  final images = <int>[
    for (var i = 0; i < mimeTypes.length; i++)
      if (mimeTypes[i].toLowerCase().startsWith('image/')) i,
  ];
  return (images: images, rejected: mimeTypes.length - images.length);
}
