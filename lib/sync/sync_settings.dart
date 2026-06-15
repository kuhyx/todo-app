import 'package:shared_preferences/shared_preferences.dart';

/// Locally-stored GitHub sync configuration.
///
/// NOTE: the token is currently stored in plain `SharedPreferences`. That is
/// acceptable for a personal dogfood build, but should move to
/// `flutter_secure_storage` (Android Keystore / libsecret) before this is
/// considered done. Tracked as a follow-up.
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
  static const _kToken = 'sync.token';
  static const _kClientId = 'sync.clientId';

  /// Loads settings, defaulting the repo to `kuhyx/todo-sync` and the client id
  /// to the baked-in [defaultClientId] so first run (and any reinstall) needs
  /// nothing but a single "Connect GitHub" tap.
  static Future<SyncSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncSettings(
      owner: prefs.getString(_kOwner) ?? 'kuhyx',
      repo: prefs.getString(_kRepo) ?? 'todo-sync',
      token: prefs.getString(_kToken) ?? '',
      clientId: prefs.getString(_kClientId) ?? defaultClientId,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOwner, owner);
    await prefs.setString(_kRepo, repo);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kClientId, clientId);
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
