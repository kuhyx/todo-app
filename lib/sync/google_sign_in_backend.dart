/// One-tap Google sign-in, kept apart from the rest of the sync wiring.
///
/// Why this is its own file: `crdt_sync` is deliberately pure Dart (only
/// `crypto` and `http`), because the same library runs on Linux desktop and
/// headless under systemd, where Android's AccountManager does not exist. So
/// the platform channel lives in the app, and the library only ever receives
/// a token string through a closure.
///
/// What this buys: on a fresh install the sync account is reached by tapping
/// one account-picker row instead of typing a long password on a phone
/// keyboard. The password path stays as the fallback and as the machine
/// credential for desktop and the Python side.
library;

import 'dart:developer';

import 'package:todo/sync/account_token.dart';
import 'package:todo/sync/google_platform.dart' as platform_gate;

/// The account the security rules pin.
///
/// Not a secret -- it is already in the public `database.rules.json` -- but it
/// is the value that makes a wrong-account sign-in *fail loudly* instead of
/// authenticating fine and then being denied every read and write. See
/// `crdt-sync/tool/link_google.py`, which is what put the Google identity on
/// this uid in the first place.
const kSyncUid = 'OvA2REQyLIhAHOEjzwS1o877rgG3';

/// The project's **Web** OAuth client id, used as the audience for ID
/// tokens.
///
/// Public by design, exactly like [kProject]'s `apiKey`: it ships inside every
/// APK, and the security rules -- not its secrecy -- protect the data.
///
/// A plain const rather than a `--dart-define`, deliberately. As a
/// compile-time environment value it was empty in every build that matters:
/// the phone-deploy skill and CI both run a bare `flutter build apk
/// --release`, so released APKs would have shown a Google button that always
/// reported "cancelled" -- a visible control that can never succeed, which is
/// the exact thing the web platform gate exists to prevent.
///
/// Fill this in from Firebase console -> Project settings -> the `syncs-rest`
/// Web app's OAuth client (type "Web application"). Android must request a
/// token minted for the *web* client; an Android client id here yields a token
/// Firebase rejects with `audience mismatch`.
/// Empty until the Web OAuth client is registered; [googleSignInSupported] is
/// false while it is, so the button stays hidden rather than failing.
const kServerClientId =
    '845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com';

/// Whether this platform can sign in programmatically.
///
/// False on web, where Google Identity Services only signs in through its own
/// rendered button: `authenticate()` throws `UnimplementedError` there. The
/// desktop build of this app *is* the web build, so without this check the
/// "Sign in with Google" button would crash the settings screen on desktop
/// rather than falling back; see `google_platform.dart` for why this is a
/// platform check rather than a question asked of the plugin.
///
/// Also false when no client id is compiled in: a button that cannot possibly
/// succeed is worse than no button, and without this check an unconfigured
/// build reports "cancelled" and sends you debugging the OAuth console for a
/// problem that is really a missing constant.
bool get googleSignInSupported =>
    platform_gate.googleSignInSupported && kServerClientId.isNotEmpty;

/// Returns a Google ID token for the signed-in account, or null.
///
/// Null rather than throwing when the user dismisses the picker: cancelling is
/// an ordinary outcome, and the caller falls back to the password path.
///
/// [signInFn] and [serverClientId] exist for tests, which cannot reach the
/// platform channel `account_token.dart` uses.
Future<String?> googleIdToken({
  Future<String?> Function()? signInFn,
  String serverClientId = kServerClientId,
}) async {
  if (signInFn != null) return await signInFn();
  if (serverClientId.isEmpty) {
    // A build without --dart-define=GOOGLE_SERVER_CLIENT_ID would otherwise
    // fail on the platform side with a far less obvious message.
    log(
      'Google sign-in unavailable: GOOGLE_SERVER_CLIENT_ID was not set at '
      'build time; falling back to the password path',
      level: 900,
    );
    return null;
  }
  return await accountManagerIdToken(serverClientId: serverClientId);
}
