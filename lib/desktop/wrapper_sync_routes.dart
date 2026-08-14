/// The wrapper's two credential-provisioning routes.
///
/// Split out of `wrapper_server.dart` for file size. Both serve a file from
/// the desktop's own config directory to the web app running in Chrome --
/// the seam that lets a desktop install provision itself instead of the
/// account being retyped per machine.
part of 'wrapper_server.dart';

extension _SyncRoutes on WrapperServer {
  /// Serves the shared sync account so a desktop install can self-provision.
  ///
  /// Off unless CRDT_SYNC_SERVE_ACCOUNT is set: this hands out a credential
  /// with database write access to anything that can reach the port, so it is
  /// something you switch on once to set an install up, not a standing route.
  /// 404 (rather than 403) when disabled, so a probe cannot tell the route
  /// exists.
  ///
  /// The account is read from the same ~/.config/crdt-sync/ pair the Python
  /// daemons already use, so there is one source of truth per machine rather
  /// than a per-app copy.
  Future<void> _syncAccount(HttpRequest request) async {
    if (!serveSyncAccount) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final configFile = File(p.join(syncConfigDir, 'firebase.json'));
    final passwordFile = File(p.join(syncConfigDir, 'password'));
    if (!configFile.existsSync() || !passwordFile.existsSync()) {
      stderr.writeln(
        'Sync account requested but ~/.config/crdt-sync/ is incomplete — '
        'the desktop app will keep asking for credentials.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final email =
        (jsonDecode(await configFile.readAsString())
            as Map<String, dynamic>)['email'];
    if (email is! String || email.isEmpty) {
      stderr.writeln('firebase.json has no usable "email" — not serving it.');
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'email': email,
        'password': (await passwordFile.readAsString()).trim(),
      }),
    );
  }

  /// Serves `todo`'s own seeded Firebase session, so a fresh desktop install
  /// can authenticate without ever seeing a password field and without a
  /// human setting an env var first.
  ///
  /// Reachable by default (unlike [_syncAccount], which stays behind
  /// [serveSyncAccount]/[kSyncAccountEnvVar]) but only until the first
  /// successful serve: this hands out a credential with database write
  /// access to anything that can reach the port, shared with five other
  /// apps, so the window it is actually reachable in must be as small as
  /// "until the app finishes booting", not "for as long as the wrapper
  /// runs". 404 (not 403) both when already served and when disabled, so a
  /// probe cannot tell which case it hit.
  ///
  /// Consumed once by `loadAccount()`'s wrapper fallback and written
  /// straight into the keystore; never a standing source the app re-reads on
  /// every launch. That matters here specifically: `seed_session.py` may
  /// later rotate this file's refresh token for an unrelated app's re-seed
  /// run, and Firebase invalidates the previous token when it does --
  /// serving a stale token to a device that already adopted the live one
  /// would just hand back a token neither side can use.
  Future<void> _syncCredentials(HttpRequest request) async {
    if (_todoCredentialsServed) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final credentialsFile = File(todoCredentialsPath);
    if (!credentialsFile.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final Map<String, dynamic> credentials;
    try {
      credentials =
          jsonDecode(await credentialsFile.readAsString())
              as Map<String, dynamic>;
    } on FormatException {
      stderr.writeln(
        '$todoCredentialsPath is not valid JSON — not serving it.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    if (credentials['id_token'] is! String ||
        credentials['refresh_token'] is! String ||
        credentials['expires_at'] is! String) {
      stderr.writeln(
        '$todoCredentialsPath is missing id_token/refresh_token/expires_at '
        '— not serving it.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    // The email is a display nicety (so Settings shows an address instead of
    // a blank), not a credential -- read from the shared config, not from
    // todoCredentialsPath, which has no email field of its own.
    String? email;
    final configFile = File(p.join(syncConfigDir, 'firebase.json'));
    if (configFile.existsSync()) {
      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final configEmail = config['email'];
      if (configEmail is String && configEmail.isNotEmpty) {
        email = configEmail;
      }
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({...credentials, 'email': email}));
    // After, not before writing the response: a request that fails partway
    // through must remain retryable rather than burning the one serve.
    _todoCredentialsServed = true;
  }
}
