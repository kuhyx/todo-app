import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locally-stored GitHub sync configuration.
///
/// The GitHub token is kept in the OS keystore (Android Keystore / libsecret)
/// via [flutter_secure_storage]; only the non-secret owner/repo/clientId live
/// in `SharedPreferences`. Older builds stored the token in plaintext prefs;
/// [load]/[save] migrate it transparently and never drop the plaintext copy
/// until a secure write is confirmed (so we degrade to — never below — the old
/// behaviour when no secret service is available).
class SyncSettings {
  const SyncSettings({
    required this.owner,
    required this.repo,
    required this.token,
    this.clientId = '',
  });

  final String owner;
  final String repo;
  final String token;

  /// GitHub OAuth App client id used by the device-flow "Connect" button.
  /// Not a secret (device flow needs no client secret), so it is safe to ship
  /// as a compile-time default and commit to source — see [defaultClientId].
  final String clientId;

  /// The app's own GitHub OAuth App (device-flow enabled) client id, baked in
  /// so "Connect GitHub" works with zero setup — even after a reinstall. A
  /// device-flow client id is a public identifier, not a secret.
  static const defaultClientId = 'Ov23li9tF2R46PqzJgch';

  /// True when enough is set to attempt a sync.
  bool get isConfigured =>
      owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  /// True when device-flow "Connect GitHub" can be offered.
  bool get canUseDeviceFlow => clientId.isNotEmpty;

  static const _kOwner = 'sync.owner';
  static const _kRepo = 'sync.repo';
  // Legacy plaintext location for the token; read-only now and removed once the
  // token has been migrated into secure storage.
  static const _kToken = 'sync.token';
  static const _kClientId = 'sync.clientId';

  /// Key for the token inside the OS keystore.
  static const _secureToken = 'sync.token';

  /// Default options keep us off the deprecated `encryptedSharedPreferences`
  /// path on Android and use libsecret on Linux.
  static const _secure = FlutterSecureStorage();

  /// Loads settings, defaulting the repo to `kuhyx/todo-sync` and the client id
  /// to the baked-in [defaultClientId] so first run (and any reinstall) needs
  /// nothing but a single "Connect GitHub" tap.
  static Future<SyncSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncSettings(
      owner: prefs.getString(_kOwner) ?? 'kuhyx',
      repo: prefs.getString(_kRepo) ?? 'todo-sync',
      token: await _loadToken(prefs),
      clientId: prefs.getString(_kClientId) ?? defaultClientId,
    );
  }

  /// Reads the token, preferring the keystore and falling back to the legacy
  /// plaintext value. A legacy value is migrated into the keystore on read, but
  /// only dropped from prefs once that secure write succeeds.
  static Future<String> _loadToken(SharedPreferences prefs) async {
    String? secure;
    try {
      secure = await _secure.read(key: _secureToken);
    } catch (_) {
      // No secret service available — fall back to the legacy plaintext copy.
      secure = null;
    }
    if (secure != null && secure.isNotEmpty) return secure;

    final legacy = prefs.getString(_kToken) ?? '';
    if (legacy.isNotEmpty && await _writeSecureToken(legacy)) {
      await prefs.remove(_kToken);
    }
    return legacy;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOwner, owner);
    await prefs.setString(_kRepo, repo);
    await prefs.setString(_kClientId, clientId);
    // Confirm-before-delete: only remove the plaintext copy once the keystore
    // write succeeds; otherwise keep persisting it to prefs as before.
    if (await _writeSecureToken(token)) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  /// Writes [token] to the keystore (deleting the entry when empty). Returns
  /// false if the platform secret service is unavailable.
  static Future<bool> _writeSecureToken(String token) async {
    try {
      if (token.isEmpty) {
        await _secure.delete(key: _secureToken);
      } else {
        await _secure.write(key: _secureToken, value: token);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  SyncSettings copyWith({
    String? owner,
    String? repo,
    String? token,
    String? clientId,
  }) {
    return SyncSettings(
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      token: token ?? this.token,
      clientId: clientId ?? this.clientId,
    );
  }
}
