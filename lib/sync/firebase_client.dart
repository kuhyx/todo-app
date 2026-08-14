/// Opening a signed-in Firebase client, and reporting whether one is possible.
///
/// Split out of `firebase_backend.dart` for file size; that file re-exports
/// this one, so callers import it as before. The credentials these read live
/// in the OS keystore — see `firebase_account_store.dart`.
library;

import 'dart:developer';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;
import 'package:todo/sync/firebase_account_store.dart';
import 'package:todo/sync/firebase_project.dart';
import 'package:todo/sync/google_sign_in_backend.dart';

// Reaches the OS keystore through a platform channel, which `flutter test`
// has no binding for; see the note in firebase_account_store.dart.
// coverage:ignore-start

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
    // dead banner.
    await clearAccountMarkerOnly();
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
