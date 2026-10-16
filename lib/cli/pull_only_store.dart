/// A read-only view of a [RemoteStore], for the CLI's verification modes.
library;

import 'package:crdt_sync/crdt_sync.dart';

/// Delegates every read to [inner] and silently drops every write.
///
/// Lets `--list` / `--get` run the app's own [SyncService] merge path without
/// publishing anything. Without it, each throwaway data dir (a fresh node id)
/// would leave a permanent full-log peer file in RTDB that every device then
/// downloads on every sync.
class PullOnlyStore implements RemoteStore, BulkMapReader {
  /// Wraps [inner], which must also be able to read revision maps.
  PullOnlyStore(this.inner);

  /// The real backend reads go to.
  final FirebaseRestClient inner;

  @override
  Future<List<String>> listDirectory(String path) => inner.listDirectory(path);

  @override
  Future<String?> getFileText(String path) => inner.getFileText(path);

  @override
  Future<Map<String, String>> getStringMap(String path) =>
      inner.getStringMap(path);

  @override
  Future<void> putFileText(
    String path,
    String text, {
    required String message,
  }) async {}

  @override
  Future<void> deleteFile(String path, {String message = ''}) async {}

  @override
  Future<bool> canAccessRemote() => inner.canAccessRemote();

  @override
  void close() => inner.close();
}
