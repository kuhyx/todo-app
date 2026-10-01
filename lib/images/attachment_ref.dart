/// Where a note's attachment lives on dufs.
///
/// A note never stores attachment bytes: it carries a plain markdown link to
/// `https://kuhy-cloud.duckdns.org/todo-images/<noteId>/<uuid>.<ext>` — an
/// image as `![](…)`, any other file as `[name](…)` — so the CRDT log, the
/// sync format and every older build stay untouched (an old build just shows
/// the link as text). This file owns the stored path's shape;
/// `attachment_links.dart` owns the links that point at it.
///
/// Pure Dart: the desktop wrapper (`bin/todo_desktop.dart`) imports it.
library;

import 'package:uuid/uuid.dart';

/// Public origin of kuhy's dufs server (Caddy → dufs on 127.0.0.1:5000).
const kDufsBaseUrl = 'https://kuhy-cloud.duckdns.org';

/// The dufs folder the `todo` login is scoped to. Named for images, which
/// came first; it holds every kind of attachment.
const kImagesDir = 'todo-images';

/// Where the same folder sits on kuhy's PC, as written into `BACKLOG.md` so an
/// agent reading the backlog can open the attachment straight from disk.
const kBacklogImagesRoot = '~/data/cloud/$kImagesDir';

/// Extension given to a file whose name has none usable.
const kUnknownExtension = 'bin';

// Segments are restricted to URL- and filesystem-safe characters, which is
// what makes a ref safe to join onto a cache directory without a traversal
// check of its own. The single, dot-free extension also keeps the cache's
// `.pending` and `.tmp` companions from ever parsing as refs.
const _segment = '[A-Za-z0-9_-]+';
const _extension = '[a-z0-9]{1,10}';

/// The pattern of a stored path, `<noteId>/<uuid>.<ext>`, for link regexes.
const kAttachmentPathPattern = '$_segment/$_segment\\.$_extension';

final _refPath = RegExp('^$kAttachmentPathPattern\$');
final _usableExtension = RegExp('^$_extension\$');
final _noteId = RegExp('^$_segment\$');

/// Whether [noteId] can name an attachment folder.
bool isSafeNoteId(String noteId) => _noteId.hasMatch(noteId);

/// One stored attachment, addressed as `<noteId>/<file>` under [kImagesDir].
///
/// An extension type over that relative path: equality and hashing are the
/// string's, so refs drop straight into sets.
extension type const AttachmentRef._(String relativePath) {
  /// A new, unique ref for an image being attached to [noteId]. Images are
  /// always stored re-encoded, hence always `.jpg`.
  factory AttachmentRef.create(String noteId) => _fresh(noteId, 'jpg');

  /// A new, unique ref for the file [fileName] being attached to [noteId],
  /// keeping its extension when that is short and plain, else
  /// [kUnknownExtension].
  factory AttachmentRef.forFile(String noteId, String fileName) =>
      _fresh(noteId, extensionOf(fileName));

  static AttachmentRef _fresh(String noteId, String extension) {
    final ref = tryParse('$noteId/${const Uuid().v4()}.$extension');
    if (ref == null) throw ArgumentError.value(noteId, 'noteId');
    return ref;
  }

  /// Parses `<noteId>/<file>.<ext>`, or null when it is not a safe path.
  static AttachmentRef? tryParse(String relativePath) =>
      _refPath.hasMatch(relativePath) ? AttachmentRef._(relativePath) : null;

  /// The note the attachment was added to (it names the folder only).
  String get noteId => relativePath.substring(0, relativePath.indexOf('/'));

  /// `<uuid>.<ext>`.
  String get file => relativePath.substring(relativePath.indexOf('/') + 1);

  /// The lower-case extension, without its dot.
  String get extension =>
      relativePath.substring(relativePath.lastIndexOf('.') + 1);

  /// The public dufs URL stored in the note.
  String get url => '$kDufsBaseUrl/$kImagesDir/$relativePath';

  /// The markdown line that shows this as an inline image.
  String get imageMarkdown => '![]($url)';

  /// The markdown line that links this as the file [name].
  String fileMarkdown(String name) => '[${linkLabel(name)}]($url)';
}

/// [fileName]'s extension, lower-cased, when it is 1–10 letters or digits;
/// otherwise [kUnknownExtension].
String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return kUnknownExtension;
  final extension = fileName.substring(dot + 1).toLowerCase();
  return _usableExtension.hasMatch(extension) ? extension : kUnknownExtension;
}

/// [name] made safe as a markdown link label: brackets would end the label
/// early and a line break would split the link, so both are replaced.
String linkLabel(String name) {
  final label = name
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();
  return label.isEmpty ? 'file' : label;
}

/// An attachment as inserted into a note: the stored ref, the name it was
/// picked under, and whether it is shown as an image.
class Attachment {
  /// Creates an attachment.
  const Attachment({
    required this.ref,
    required this.name,
    required this.isImage,
  });

  /// Where it is stored.
  final AttachmentRef ref;

  /// The file name it was picked or dropped under.
  final String name;

  /// True for a re-encoded image (`![](…)`), false for a plain file.
  final bool isImage;

  /// The line inserted into the note.
  String get markdown => isImage ? ref.imageMarkdown : ref.fileMarkdown(name);

  /// JSON form, the desktop wrapper's answer to an attach.
  Map<String, Object> toJson() => {
    'ref': ref.relativePath,
    'name': name,
    'image': isImage,
  };

  /// Parses [toJson]'s output; throws [FormatException] on anything else.
  static Attachment fromJson(Object? json) {
    if (json case {
      'ref': final String path,
      'name': final String name,
      'image': final bool isImage,
    }) {
      if (AttachmentRef.tryParse(path) case final ref?) {
        return Attachment(ref: ref, name: name, isImage: isImage);
      }
    }
    throw FormatException('Not an attachment: $json');
  }
}
