/// Where todo gets the shared crdt-sync passphrase its E2E key comes from.
///
/// The keystore first. On the desktop (a web build behind the local
/// wrapper) an empty keystore adopts the wrapper's one-shot
/// `/sync-e2e-passphrase` route, which serves `~/.config/crdt-sync/password`,
/// so the desktop app never asks. Android has no wrapper (`Uri.base` is
/// `file:///`) and is unlocked through the settings lock tile instead.
library;

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey, kSecureStorage, saveE2ePassphrase;
import 'package:http/http.dart' as http;

/// Path of the wrapper's one-shot passphrase route.
const kSyncE2ePassphrasePath = '/sync-e2e-passphrase';

/// Returns the passphrase, adopting the wrapper's once; null when none.
Future<String?> readE2ePassphrase({Uri? base, http.Client? client}) async {
  final stored = await kSecureStorage.read(key: kE2ePassphraseKey);
  if (stored != null && stored.isNotEmpty) return stored;
  final origin = base ?? Uri.base;
  if (origin.scheme != 'http' && origin.scheme != 'https') return null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(
      origin.resolve(kSyncE2ePassphrasePath),
    );
    final text = response.body.trim();
    if (response.statusCode != 200 || text.isEmpty) return null;
    await saveE2ePassphrase(text);
    return text;
  } on Object {
    // No wrapper, or it already served: this device is simply locked.
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}
