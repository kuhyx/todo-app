import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/pull_only_store.dart';

import 'fake_rtdb.dart';

void main() {
  test('reads pass through and writes are dropped', () async {
    final tmp = Directory.systemTemp.createTempSync('pull_only_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final db = FakeRtdb()
      ..files['todo-sync/notes/a~2Ejson'] = 'log-a'
      ..files['todo-sync/revs/a'] = 'rev-a';
    final inner = FirebaseRestClient(
      databaseUrl: 'https://example.test/',
      auth: FirebaseTokenProvider(
        apiKey: 'k',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'rt',
            expiresAt: DateTime.utc(2099),
          ),
        ),
      ),
      httpClient: db.client,
    );
    final store = PullOnlyStore(inner);

    expect(await store.listDirectory('todo-sync/notes'), ['a.json']);
    expect(await store.getFileText('todo-sync/notes/a.json'), 'log-a');
    expect(await store.getStringMap('todo-sync/revs'), {'a': 'rev-a'});
    expect(await store.canAccessRemote(), isTrue);

    final before = db.methods.length;
    await store.putFileText('todo-sync/notes/b.json', 'x', message: 'm');
    await store.deleteFile('todo-sync/notes/a.json');
    expect(db.methods.length, before);
    expect(db.files.keys, hasLength(2));
    store.close();
  });
}
