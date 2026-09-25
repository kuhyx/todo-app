/// Where a note's image lives, and how a note's text points at it.
///
/// A note never stores image bytes: it carries a plain markdown link
/// `![](https://kuhy-cloud.duckdns.org/todo-images/<noteId>/<uuid>.jpg)`, so the
/// CRDT log, the sync format and every older build stay untouched (an old
/// build just shows the link as text). This file is the single source of truth
/// for that link's shape; everything else goes through it.
///
/// Pure Dart: the desktop wrapper (`bin/todo_desktop.dart`) imports it.
library;

import 'package:uuid/uuid.dart';

/// Public origin of kuhy's dufs server (Caddy → dufs on 127.0.0.1:5000).
const kDufsBaseUrl = 'https://kuhy-cloud.duckdns.org';

/// The dufs folder the `todo` login is scoped to.
const kImagesDir = 'todo-images';

/// Where the same folder sits on kuhy's PC, as written into `BACKLOG.md` so an
/// agent reading the backlog can open the image straight from disk.
const kBacklogImagesRoot = '~/data/cloud/$kImagesDir';

// Segments are restricted to URL- and filesystem-safe characters, which is
// what makes a ref safe to join onto a cache directory without a traversal
// check of its own.
const _segment = '[A-Za-z0-9_-]+';
const _path = '$_segment/$_segment\\.jpg';
const _label = r'!\[[^\]\n]*\]\(';
final _refPath = RegExp('^($_segment)/($_segment\\.jpg)\$');
final _urlLink = RegExp(
  '$_label${RegExp.escape('$kDufsBaseUrl/$kImagesDir/')}($_path)\\)',
);
final _backlogLink = RegExp(
  '($_label)${RegExp.escape('$kBacklogImagesRoot/')}($_path\\))',
);
final _wholeLine = RegExp('^\\s*${_urlLink.pattern}\\s*\$');

/// One image, addressed as `<noteId>/<file>` under [kImagesDir].
///
/// An extension type over that relative path: equality and hashing are the
/// string's, so refs drop straight into sets.
extension type const ImageRef._(String relativePath) {
  /// A new, unique ref for an image being attached to [noteId].
  factory ImageRef.create(String noteId) {
    final ref = ImageRef.tryParse('$noteId/${const Uuid().v4()}.jpg');
    if (ref == null) throw ArgumentError.value(noteId, 'noteId');
    return ref;
  }

  /// Parses `<noteId>/<file>.jpg`, or null when it is not a safe image path.
  static ImageRef? tryParse(String relativePath) =>
      _refPath.hasMatch(relativePath) ? ImageRef._(relativePath) : null;

  /// The note the image was attached to (it names the folder only).
  String get noteId => relativePath.substring(0, relativePath.indexOf('/'));

  /// `<uuid>.jpg`.
  String get file => relativePath.substring(relativePath.indexOf('/') + 1);

  /// The public dufs URL stored in the note.
  String get url => '$kDufsBaseUrl/$kImagesDir/$relativePath';

  /// The markdown line inserted into a note.
  String get markdown => '![]($url)';
}

/// Every image [text] links to, in order, without duplicates.
Set<ImageRef> imageRefsIn(String text) => {
  for (final match in _urlLink.allMatches(text))
    ImageRef.tryParse(match.group(1)!)!,
};

/// The image when [line] is nothing but one image link, else null.
ImageRef? imageRefOfLine(String line) {
  final match = _wholeLine.firstMatch(line);
  return match == null ? null : ImageRef.tryParse(match.group(1)!);
}

/// Rewrites image links to their on-disk path under [kBacklogImagesRoot].
String toBacklogImagePaths(String text) => text.replaceAllMapped(
  _urlLink,
  (m) => m[0]!.replaceFirst('$kDufsBaseUrl/$kImagesDir', kBacklogImagesRoot),
);

/// Exact inverse of [toBacklogImagePaths], so an exported backlog imports
/// back with its links intact.
String fromBacklogImagePaths(String text) => text.replaceAllMapped(
  _backlogLink,
  (m) => '${m[1]}$kDufsBaseUrl/$kImagesDir/${m[2]}',
);
