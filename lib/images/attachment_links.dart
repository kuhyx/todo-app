/// Finding attachment links in a note's text, and rewriting them for
/// `BACKLOG.md`.
///
/// One regex reads both shapes: `![](url)` is an image, `[name](url)` a file.
/// Matching them together (rather than a file regex beside an image regex)
/// is what keeps an image link, which contains `[](url)`, from also counting
/// as a file.
///
/// Pure Dart: the desktop wrapper imports it.
library;

import 'package:todo/images/attachment_ref.dart';

final String _base = RegExp.escape('$kDufsBaseUrl/$kImagesDir/');
const _label = r'\[[^\]\n]*\]\(';
const _link = r'(!?)\[([^\]\n]*)\]\(';
final _anyLink = RegExp('$_link$_base($kAttachmentPathPattern)\\)');
final _wholeLine = RegExp('^\\s*${_anyLink.pattern}\\s*\$');
final _urlLink = RegExp('($_label)$_base($kAttachmentPathPattern\\))');
final _backlogLink = RegExp(
  '($_label)${RegExp.escape('$kBacklogImagesRoot/')}'
  '($kAttachmentPathPattern\\))',
);

Attachment _attachment(RegExpMatch match) => Attachment(
  ref: AttachmentRef.tryParse(match.group(3)!)!,
  name: match.group(2)!,
  isImage: match.group(1)!.isNotEmpty,
);

/// Every attachment [text] links to, in order, each ref once.
List<Attachment> attachmentsIn(String text) {
  final seen = <AttachmentRef>{};
  final found = <Attachment>[];
  for (final match in _anyLink.allMatches(text)) {
    final attachment = _attachment(match);
    if (seen.add(attachment.ref)) found.add(attachment);
  }
  return found;
}

/// Every ref [text] links to, images and files alike.
Set<AttachmentRef> attachmentRefsIn(String text) => {
  for (final attachment in attachmentsIn(text)) attachment.ref,
};

/// The attachment when [line] is nothing but one attachment link, else null.
Attachment? attachmentOfLine(String line) {
  final match = _wholeLine.firstMatch(line);
  return match == null ? null : _attachment(match);
}

/// Rewrites attachment links to their on-disk path under
/// [kBacklogImagesRoot].
String toBacklogAttachmentPaths(String text) => text.replaceAllMapped(
  _urlLink,
  (m) => '${m[1]}$kBacklogImagesRoot/${m[2]}',
);

/// Exact inverse of [toBacklogAttachmentPaths], so an exported backlog
/// imports back with its links intact.
String fromBacklogAttachmentPaths(String text) => text.replaceAllMapped(
  _backlogLink,
  (m) => '${m[1]}$kDufsBaseUrl/$kImagesDir/${m[2]}',
);
