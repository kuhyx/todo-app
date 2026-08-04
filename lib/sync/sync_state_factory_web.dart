import 'package:crdt_sync/crdt_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key holding the revision cache in `SharedPreferences`.
const kSyncStateKey = 'sync.state';

/// Opens the revision cache on web (the Chrome-wrapper desktop build).
///
/// `SharedPreferences` rather than IndexedDB: the payload is two short hashes
/// per peer, so a key-value entry is the whole requirement, and the note
/// log already owns the IndexedDB store.
Future<SyncStateStore> openSyncStateStore() async => PersistedSyncStateStore(
  _PrefsPersistence(await SharedPreferences.getInstance()),
);

class _PrefsPersistence implements LogPersistence {
  _PrefsPersistence(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> read() async => _prefs.getString(kSyncStateKey);

  @override
  Future<void> write(String text) async =>
      _prefs.setString(kSyncStateKey, text);
}
