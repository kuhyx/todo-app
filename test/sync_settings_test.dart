import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/sync/sync_settings.dart';

import 'fake_secure_storage.dart';

void main() {
  // installFakeSecureStorage touches the test binary messenger, which needs the
  // binding up first (widget tests get this for free via testWidgets).
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'load returns the kuhyx/todo-sync defaults on a fresh install',
    () async {
      SharedPreferences.setMockInitialValues({});
      installFakeSecureStorage();
      final s = await SyncSettings.load();
      expect(s.owner, 'kuhyx');
      expect(s.repo, 'todo-sync');
      expect(s.token, '');
      // Client id defaults to the baked-in OAuth App id (one-tap connect).
      expect(s.clientId, SyncSettings.defaultClientId);
    },
  );

  test('save stores the token in the keystore, not in prefs', () async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
    await const SyncSettings(
      owner: 'me',
      repo: 'notes',
      token: 'tok',
      clientId: 'cid',
    ).save();

    // Token must not linger in plaintext prefs once secured.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sync.token'), isNull);

    final s = await SyncSettings.load();
    expect(s.owner, 'me');
    expect(s.repo, 'notes');
    expect(s.token, 'tok');
    expect(s.clientId, 'cid');
  });

  test('load reads the token straight from the keystore', () async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage(initial: {'sync.token': 'fromKeystore'});
    final s = await SyncSettings.load();
    expect(s.token, 'fromKeystore');
  });

  test('load migrates a legacy plaintext token into the keystore', () async {
    SharedPreferences.setMockInitialValues({'sync.token': 'legacy'});
    installFakeSecureStorage();

    final s = await SyncSettings.load();
    expect(s.token, 'legacy');

    // The plaintext copy is dropped once the secure write succeeds, and the
    // value now resolves from the keystore on the next load.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sync.token'), isNull);
    final again = await SyncSettings.load();
    expect(again.token, 'legacy');
  });

  test(
    'load keeps the plaintext token when no secret service is available',
    () async {
      SharedPreferences.setMockInitialValues({'sync.token': 'plain'});
      installFakeSecureStorage(throwing: true);

      final s = await SyncSettings.load();
      expect(s.token, 'plain');
      // Never drop the only copy when the keystore write can't be confirmed.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync.token'), 'plain');
    },
  );

  test('save falls back to plaintext prefs when the keystore fails', () async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage(throwing: true);
    await const SyncSettings(owner: 'o', repo: 'r', token: 'tok').save();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sync.token'), 'tok');
  });

  test('save with an empty token clears the keystore entry', () async {
    // Seed a keystore token, then save an empty token: it must be deleted and
    // no plaintext copy written.
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage(initial: {'sync.token': 'old'});
    await const SyncSettings(owner: 'o', repo: 'r', token: '').save();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sync.token'), isNull);
    final s = await SyncSettings.load();
    expect(s.token, '');
  });

  test('isConfigured requires owner, repo and token', () {
    expect(
      const SyncSettings(owner: 'o', repo: 'r', token: 't').isConfigured,
      isTrue,
    );
    expect(
      const SyncSettings(owner: 'o', repo: 'r', token: '').isConfigured,
      isFalse,
    );
  });

  test('canUseDeviceFlow needs a client id', () {
    expect(
      const SyncSettings(
        owner: '',
        repo: '',
        token: '',
        clientId: 'c',
      ).canUseDeviceFlow,
      isTrue,
    );
    expect(
      const SyncSettings(owner: '', repo: '', token: '').canUseDeviceFlow,
      isFalse,
    );
  });

  test('copyWith overrides only the given fields', () {
    const base = SyncSettings(owner: 'o', repo: 'r', token: 't', clientId: 'c');
    final next = base.copyWith(token: 'new');
    expect(next.owner, 'o');
    expect(next.repo, 'r');
    expect(next.token, 'new');
    expect(next.clientId, 'c');

    // No-arg copy exercises the `?? this.x` fallback on every field.
    final clone = base.copyWith();
    expect(clone.owner, 'o');
    expect(clone.repo, 'r');
    expect(clone.token, 't');
    expect(clone.clientId, 'c');
  });
}
