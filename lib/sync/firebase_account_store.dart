/// Where the per-device Firebase account and session live: the OS keystore.
///
/// Split out of `firebase_backend.dart` for file size; that file re-exports
/// this one, so callers import it as before.
///
/// Nothing here reads `~/.config/crdt-sync/` directly — that is the
/// desktop/Python half, reached over the local wrapper's HTTP routes. On
/// Android there is no such file.
library;

import 'dart:convert';
import 'dart:developer';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:todo/desktop/wrapper_server.dart' show kSyncCredentialsPath;

/// Same options the GitHub token uses: off Android's deprecated
/// `encryptedSharedPreferences` path, and libsecret on Linux.
const _secure = FlutterSecureStorage();

// Everything below reaches the OS keystore through a platform channel, which
// `flutter test` has no binding for -- the same reason `main.dart` and
// `openRepository()` are excluded. The logic these wrap (parsing, the
// public/private split, sign-in) lives in `crdt_sync` and is covered there at
// 100%; what is left here is the two-line adapter.
// coverage:ignore-start

/// The keystore-backed home for the Firebase refresh token.
SecureCredentialStore credentialStore() => SecureCredentialStore(
  read: (key) => _secure.read(key: key),
  write: (key, value) => _secure.write(key: key, value: value),
  delete: (key) => _secure.delete(key: key),
);

/// Reads the per-device account, or null when sync has not been set up.
///
/// Falls back to the local wrapper when the store is empty, so a desktop
/// install can provision itself instead of the account being retyped per
/// machine. Tries the seeded Firebase session first (`/sync-credentials`,
/// `~/.config/todo/firebase_auth.json` via `seed_session.py --app todo`) --
/// the only thing that actually authenticates, since the shared account's
/// password grant is retired fleet-wide (see `link_google.py`/
/// `seed_session.py` in `~/utils/crdt-sync`) -- then the legacy
/// email/password route (`/sync-account`, `~/.config/crdt-sync/`) as a
/// fallback for a machine that has not been re-seeded yet. Whichever
/// succeeds is written to the store on first success, so the route is
/// consulted once rather than being load-bearing forever.
///
/// [httpClient] is injectable for tests; production opens and closes its own
/// per attempted route.
Future<FirebaseAccount?> loadAccount({http.Client? httpClient}) async {
  try {
    final stored = FirebaseAccount.tryParse(
      await _secure.read(key: kFirebaseAccountKey),
    );
    if (stored != null) return stored;
    // Disconnect must stick: without this the next launch would silently
    // re-adopt the account and the button would look broken.
    if (await _secure.read(key: kSyncAccountOptOutKey) != null) return null;
    final seeded = await _adoptCredentialsFromWrapper(
      Uri.base,
      client: httpClient,
    );
    if (seeded != null) return seeded;
    final provisioned = await accountFromWrapper(Uri.base, client: httpClient);
    if (provisioned != null) await saveAccount(provisioned);
    return provisioned;
    // Broader than Exception on purpose: an Android build has no wrapper, so
    // `Uri.base` is `file:///` and accountFromWrapper raises an ArgumentError
    // ("No host specified in URI") -- an Error, which `on Exception` does not
    // catch. That escaped openFirebase() and killed the whole sync tick, so a
    // signed-in phone pulled nothing at all.
  } on Object catch (error, stackTrace) {
    // Still "not configured" rather than crashing the settings screen -- but
    // never silent: this hid *why* provisioning failed, which is
    // indistinguishable from "no account set" until you say so.
    log(
      'loadAccount failed; treating this device as not configured',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Fetches `todo`'s seeded session from the wrapper's `/sync-credentials`
/// route and adopts it: stores the refresh token in [credentialStore] and
/// writes an account marker so the Settings screen shows an address instead
/// of a blank. Returns the marker on success, null on any failure (route
/// disabled, file absent, malformed body, no wrapper at all) -- the caller's
/// fallback is simply "not configured".
///
/// [client] is injectable for tests; production opens and closes its own.
Future<FirebaseAccount?> _adoptCredentialsFromWrapper(
  Uri base, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(base.resolve(kSyncCredentialsPath));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) return null;
    if (body['id_token'] is! String ||
        body['refresh_token'] is! String ||
        body['expires_at'] is! String) {
      return null;
    }
    await credentialStore().save(FirebaseCredentials.fromJson(body));
    final email = body['email'];
    final account = FirebaseAccount(
      email: email is String ? email : '',
      password: '',
    );
    await saveAccount(account);
    return account;
  } on Exception {
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Reads the account from the keystore only, with no wrapper fallback.
///
/// [loadAccount] falls back to the desktop wrapper's `/sync-account` route
/// when the keystore is empty, which on Android resolves to `file:///` and
/// throws `No host specified in URI`. Callers that only want to read back an
/// account they just wrote — where a fallback would be wrong anyway — use
/// this instead.
Future<FirebaseAccount?> storedAccount() async =>
    FirebaseAccount.tryParse(await _secure.read(key: kFirebaseAccountKey));

/// Stores the per-device account. Keystore only — never prefs, never source.
Future<void> saveAccount(FirebaseAccount account) =>
    _secure.write(key: kFirebaseAccountKey, value: account.toJsonString());

/// Forgets the account and any cached session.
Future<void> clearAccount() async {
  await _secure.delete(key: kFirebaseAccountKey);
  // Suppress wrapper re-provisioning; see loadAccount().
  await _secure.write(key: kSyncAccountOptOutKey, value: 'true');
  await credentialStore().clear();
}

/// Drops the account marker alone, leaving the opt-out flag unset.
///
/// Used when a marker is found with no session behind it: not
/// [clearAccount], which also sets the opt-out flag and would stop the
/// desktop wrapper re-provisioning after the next sign-in.
Future<void> clearAccountMarkerOnly() =>
    _secure.delete(key: kFirebaseAccountKey);

// coverage:ignore-end
