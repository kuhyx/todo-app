/// The capture screen's image behaviour: attaching to the draft, and
/// reconciling the device's image store with every note.
///
/// A `part` of `capture_screen.dart` because it reads the private draft and
/// attach controller.
part of 'capture_screen.dart';

extension _CaptureImages on _CaptureScreenState {
  /// Stores [images] under the draft's note (reserving its id) and inserts
  /// their links at the cursor. [rejected] counts dropped non-images.
  Future<void> _attachImages(List<Uint8List> images, {int rejected = 0}) =>
      attachImages(
        context,
        noteId: _draft.reserveId,
        target: _attach,
        images: images,
        rejected: rejected,
      );

  /// Uploads queued images, prefetches every image any note links to, and
  /// evicts what no note links to. Runs after every sync attempt, on resume
  /// and at launch (via the launch sync).
  Future<void> _reconcileImages() async {
    if (!mounted) return;
    final store = ImageStoreScope.read(context);
    final notes = await widget.repository.listNotes();
    await store.reconcile([for (final note in notes) note.text]);
  }
}
