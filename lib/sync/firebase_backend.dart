/// Wiring for the Firebase backend, during and after the GitHub cutover.
///
/// Split by what is safe to publish, because this repo is public:
///
/// * [kProject] holds the Web API key and database URL. Both are public
///   identifiers that already ship inside the APK; the security rules, not
///   their secrecy, are what protect the data.
/// * The account email and password are entered once per device and kept in
///   the OS keystore, next to the GitHub token this app already stores there.
///
/// Nothing here reads `~/.config/crdt-sync/` — that is the desktop/Python
/// half. On Android there is no such file.
library;

import 'dart:developer';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The shared `kuhy-syncs` project.
///
/// `databaseUrl` is the **regional** host. The plain `*.firebaseio.com` form
/// answers 404 with a `correctUrl` body rather than an obvious error, which
/// reads like an auth failure and wastes a debugging session.
const kProject = FirebaseProject(
  apiKey: 'AIzaSyCF_sA3xCMehAYXK8eND-rAygb9NXXW_8E',
  databaseUrl:
      'https://kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app',
);

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
/// install can provision itself from `~/.config/crdt-sync/` instead of the
/// account being retyped per machine. The fetched account is written to the
/// store on first success, so the route is consulted once rather than being
/// load-bearing forever.
Future<FirebaseAccount?> loadAccount() async {
  try {
    final stored = FirebaseAccount.tryParse(
      await _secure.read(key: kFirebaseAccountKey),
    );
    if (stored != null) return stored;
    // Disconnect must stick: without this the next launch would silently
    // re-adopt the account and the button would look broken.
    if (await _secure.read(key: kSyncAccountOptOutKey) != null) return null;
    final provisioned = await accountFromWrapper(Uri.base);
    if (provisioned != null) await saveAccount(provisioned);
    return provisioned;
  } on Exception catch (error, stackTrace) {
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

/// Returns a signed-in Firebase client, or null when not configured.
///
/// Signs in with the stored password only when there is no cached refresh
/// token, so the usual path costs no authentication round trip.
Future<FirebaseRestClient?> openFirebase() async {
  final account = await loadAccount();
  if (account == null) return null;
  return firebaseClientFor(
    config: kProject.configFor(account.email),
    store: credentialStore(),
    password: account.password,
  );
}

// coverage:ignore-end
