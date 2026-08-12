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

import 'dart:convert';
import 'dart:developer';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:todo/desktop/wrapper_server.dart' show kSyncCredentialsPath;
import 'package:todo/sync/google_sign_in_backend.dart';

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

/// Returns a signed-in Firebase client, or null when not configured.
///
/// Signs in with the stored password only when there is no cached refresh
/// token, so the usual path costs no authentication round trip.
Future<FirebaseRestClient?> openFirebase() async {
  final account = await loadAccount();
  if (account == null) {
    // A stored refresh token IS a signed-in device, even with no account
    // marker beside it. Treating the marker as the source of truth is what
    // made a phone with a live session sync over GitHub and 401 forever --
    // the credential was in the keystore the whole time, unused.
    return _clientFromStoredSession();
  }
  return firebaseClientFor(
    config: kProject.configFor(account.email),
    store: credentialStore(),
    // A Google-provisioned account stores an empty password. Passing '' would
    // make firebaseClientFor treat it as a usable credential and sign in with
    // it, which fails; null correctly means "no password on this device".
    password: account.password.isEmpty ? null : account.password,
    // Deliberately NOT passing googleIdToken here. This path runs from
    // background timers and, in some apps, before runApp -- offering Google
    // would let a non-interactive tick raise the OS account picker with no
    // user action behind it. Interactive sign-in goes through
    // openFirebaseWithGoogle instead.
    expectedUid: kSyncUid,
  );
}

/// Signs in with Google alone, for a device that has no account stored yet.
///
/// This is the one-tap path: [openFirebase] needs an account in the keystore
/// to know which email to use, but a fresh install has none. The Google token
/// carries the identity, so nothing needs to be typed -- and on success the
/// email is written to the keystore so every later launch takes the ordinary
/// path.
///
/// Returns null when the user dismisses the picker or the token is refused;
/// throws [FirebaseAuthError] when Google succeeds but resolves to the wrong
/// uid, which is a misconfiguration worth surfacing rather than swallowing.
///
/// On success the account is written to the keystore using the email
/// **Firebase reports**, not one read from the UI: a fresh install has no
/// email anywhere on the device, so taking it from a text field would persist
/// an empty account and send the next launch down the password path with ''.
Future<FirebaseRestClient?> openFirebaseWithGoogle({
  Future<String?> Function()? tokenFetcher,
  Future<void> Function(FirebaseAccount)? accountSaver,
  http.Client? httpClient,
}) async {
  final token = await (tokenFetcher ?? googleIdToken)();
  if (token == null) return null;
  final auth = FirebaseTokenProvider(
    apiKey: kProject.apiKey,
    store: credentialStore(),
    httpClient: httpClient,
  );
  final email = await auth.signInWithGoogle(
    idToken: token,
    expectedUid: kSyncUid,
  );
  // Saved unconditionally, and deliberately not gated on `email`:
  // `signInWithIdp` omits that field whenever the Google account hides it, and
  // gating the write on it returned a working client while persisting nothing,
  // so the next launch looked unconfigured and fell back to GitHub-only.
  // The session itself is already durable here -- signInWithGoogle stored the
  // refresh token -- and that token, not the address, is the credential.
  // password is empty on purpose: this device has a refresh token and no
  // password to store. loadAccount() treats the account as configured, and
  // openFirebase() re-signs-in with Google rather than with an empty
  // password -- see the googleIdToken argument it passes.
  await (accountSaver ?? saveAccount)(
    FirebaseAccount(email: email ?? '', password: ''),
  );
  return FirebaseRestClient(databaseUrl: kProject.databaseUrl, auth: auth);
}

/// Whether this device can actually authenticate against Firebase.
///
/// True when either half of the state is present: the account marker
/// [loadAccount] reads, or a stored refresh token. The token is the half that
/// matters -- it is what signs requests -- so reporting the marker alone calls
/// a working device "not connected", which is exactly how a phone that was in
/// fact syncing looked broken.
///
/// The marker alone is not enough, though. A revoked refresh token makes the
/// library clear the session, and a marker left behind by the sign-in that
/// created it would still report "Connected" while every sync failed with
/// TOKEN_EXPIRED -- the desktop symptom seen on 2026-08-11. So when a marker
/// exists but the session is gone, the marker is the stale half: drop it.
Future<bool> isFirebaseConfigured() async {
  try {
    final auth = FirebaseTokenProvider(
      apiKey: kProject.apiKey,
      store: credentialStore(),
    );
    if (await auth.hasSession()) return true;
    // storedAccount, not loadAccount: on Android the latter falls back to the
    // desktop wrapper's /sync-account route, which resolves to file:/// and
    // throws "No host specified in URI" -- observed on the phone, where it
    // turned a successful sign-in into "Google sign-in failed".
    if (await storedAccount() == null) return false;
    // A marker with no session behind it cannot sign a single request. Drop
    // just the marker so the settings screen offers a sign-in instead of a
    // dead banner -- not clearAccount(), which also sets the opt-out flag and
    // would stop the desktop wrapper re-provisioning after the next sign-in.
    await _secure.delete(key: kFirebaseAccountKey);
    return false;
  } on Object catch (error, stackTrace) {
    log(
      'session probe failed; reporting this device as not configured',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

/// Returns a client built from the keystore's refresh token alone, or null.
///
/// The recovery path for a device that has a live session but no account
/// marker -- the state a Google sign-in used to leave behind. Costs one
/// keystore read and no network round trip when there is no session, so it is
/// safe on the background-tick path [openFirebase] also serves.
Future<FirebaseRestClient?> _clientFromStoredSession() async {
  try {
    final auth = FirebaseTokenProvider(
      apiKey: kProject.apiKey,
      store: credentialStore(),
    );
    if (!await auth.hasSession()) return null;
    return FirebaseRestClient(databaseUrl: kProject.databaseUrl, auth: auth);
  } on Object catch (error, stackTrace) {
    log(
      'stored-session recovery failed; falling back to the GitHub mirror',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

// coverage:ignore-end
