import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/sync/sync_settings.dart';

void main() {
  test(
    'load returns the kuhyx/todo-sync defaults on a fresh install',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SyncSettings.load();
      expect(s.owner, 'kuhyx');
      expect(s.repo, 'todo-sync');
      expect(s.token, '');
      expect(s.clientId, '');
    },
  );

  test('save then load round-trips all fields', () async {
    SharedPreferences.setMockInitialValues({});
    await const SyncSettings(
      owner: 'me',
      repo: 'notes',
      token: 'tok',
      clientId: 'cid',
    ).save();

    final s = await SyncSettings.load();
    expect(s.owner, 'me');
    expect(s.repo, 'notes');
    expect(s.token, 'tok');
    expect(s.clientId, 'cid');
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
