/// Ctrl+V and drag-and-drop of images onto the desktop (web) page.
///
/// Flutter web has no drop target of its own, so this listens on the DOM
/// `document` directly (`package:web`, no native plugin): `dragover` must be
/// cancelled for the page to accept a drop at all, and `drop` must be, or
/// Chrome navigates away to the dropped file. A paste is only taken over when
/// the clipboard carries files; plain-text pastes stay the text field's.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:todo/ui/image_input_files.dart';
import 'package:web/web.dart' as web;

/// Receives pasted or dropped images and the count of non-image files.
typedef ImageInputCallback =
    void Function(List<Uint8List> images, int rejected);

/// Calls [onImages] for images pasted or dropped anywhere on the page while
/// this widget's route is the visible one.
class ImageInputListener extends StatefulWidget {
  /// Wraps [child], listening while mounted.
  const ImageInputListener({
    required this.onImages,
    required this.child,
    super.key,
  });

  /// Receives the image bytes in order, plus the non-image count.
  final ImageInputCallback onImages;

  /// The screen body.
  final Widget child;

  @override
  State<ImageInputListener> createState() => _ImageInputListenerState();
}

class _ImageInputListenerState extends State<ImageInputListener> {
  late final JSFunction _onDragOver = _dragOver.toJS;
  late final JSFunction _onDrop = _drop.toJS;
  late final JSFunction _onPaste = _paste.toJS;

  @override
  void initState() {
    super.initState();
    web.document
      ..addEventListener('dragover', _onDragOver)
      ..addEventListener('drop', _onDrop)
      ..addEventListener('paste', _onPaste);
  }

  @override
  void dispose() {
    web.document
      ..removeEventListener('dragover', _onDragOver)
      ..removeEventListener('drop', _onDrop)
      ..removeEventListener('paste', _onPaste);
    super.dispose();
  }

  // The capture screen stays mounted under a pushed detail screen, and both
  // listen on the same document: only the visible route may take the input,
  // or one drop would attach to two notes.
  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  void _dragOver(web.DragEvent event) {
    final types = event.dataTransfer?.types.toDart ?? const <JSString>[];
    if (_active && types.any((t) => t.toDart == 'Files')) {
      event.preventDefault();
    }
  }

  void _drop(web.DragEvent event) {
    final files = event.dataTransfer?.files;
    if (!_active || files == null || files.length == 0) return;
    event.preventDefault();
    unawaited(_take(files));
  }

  void _paste(web.ClipboardEvent event) {
    final files = event.clipboardData?.files;
    if (!_active || files == null || files.length == 0) return;
    event.preventDefault();
    unawaited(_take(files));
  }

  Future<void> _take(web.FileList list) async {
    final files = [for (var i = 0; i < list.length; i++) list.item(i)!];
    final split = partitionImageFiles([for (final f in files) f.type]);
    final images = <Uint8List>[
      for (final i in split.images)
        (await files[i].arrayBuffer().toDart).toDart.asUint8List(),
    ];
    if (mounted) widget.onImages(images, split.rejected);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
