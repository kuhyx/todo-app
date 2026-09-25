/// Turning picked, pasted or dropped image bytes into links in the open note.
///
/// Shared by the capture and detail screens: each owns one
/// [ImageAttachController], hands it to its [NoteEditor] (which binds the
/// insert-at-cursor), and routes every image source through [attachImages].
library;

import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/image_ref.dart';

/// Lets a screen insert lines into whichever editor is currently mounted.
class ImageAttachController {
  void Function(List<String> lines)? _insert;

  /// Called by the editor on mount with its insert-at-cursor function;
  /// returns the call that undoes it (a no-op once another editor bound).
  VoidCallback bind(void Function(List<String> lines) insert) {
    _insert = insert;
    return () {
      if (identical(_insert, insert)) _insert = null;
    };
  }

  /// Inserts [lines] at the editor's cursor; false when no editor is bound.
  bool insert(List<String> lines) {
    final insert = _insert;
    if (insert == null || lines.isEmpty) return false;
    insert(lines);
    return true;
  }
}

/// Stores each of [images] for the note [noteId] names and inserts their
/// links, in order, through [target].
///
/// [noteId] is a callback because the capture screen's draft only gets an id
/// once there is something to save; asking for it is what reserves one.
/// Reserving writes nothing, so a rejected paste still never creates an
/// empty note. [rejected] counts inputs already known
/// not to be images (e.g. a dropped PDF), so one message covers both.
Future<void> attachImages(
  BuildContext context, {
  required String Function() noteId,
  required ImageAttachController target,
  required List<Uint8List> images,
  int rejected = 0,
}) async {
  final store = ImageStoreScope.read(context);
  final refs = <ImageRef>[];
  var notImages = rejected;
  String? failure;
  for (final bytes in images) {
    try {
      final ref = await store.attach(noteId(), bytes);
      if (ref == null) {
        notImages++;
      } else {
        refs.add(ref);
      }
    } on ImageStoreException catch (e) {
      failure = e.message;
      break;
    }
  }
  target.insert([for (final ref in refs) ref.markdown]);
  if (!context.mounted) return;
  if (failure != null) {
    showError(context, failure);
  } else if (notImages > 0) {
    showError(
      context,
      notImages == 1 ? 'Not an image' : '$notImages files were not images',
    );
  }
}
