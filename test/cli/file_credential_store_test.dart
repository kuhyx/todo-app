import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/file_credential_store.dart';

import 'fake_rtdb.dart';

void main() {
  late Directory tmp;
  late File own;
  late File seed;
  late FileCredentialStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cred_store_test');
    own = File('${tmp.path}/nested/own.json');
    seed = File('${tmp.path}/seed.json');
    store = FileCredentialStore(file: own, seedFile: seed);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('load is null when neither file exists', () async {
    expect(await store.load(), isNull);
  });

  test('load falls back to the seed, then prefers its own copy', () async {
    writeSeedCredentials(tmp);
    expect((await store.load())!.refreshToken, 'seed-refresh-token');

    await store.save(
      FirebaseCredentials(
        idToken: 'new-id',
        refreshToken: 'new-refresh',
        expiresAt: DateTime.utc(2099),
      ),
    );
    expect((await store.load())!.refreshToken, 'new-refresh');
    // The seed is read-only: saving never touches it.
    expect(
      jsonDecode(seed.readAsStringSync()),
      containsPair('refresh_token', 'seed-refresh-token'),
    );
  });

  test('save writes an owner-only file and leaves no temp file', () async {
    await store.save(
      FirebaseCredentials(
        idToken: 'i',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2099),
      ),
    );
    expect(own.statSync().mode & 0x1ff, 384); // 0600
    expect(own.parent.listSync().map((e) => e.path), [own.path]);
  });

  test('load is null for a non-object document', () async {
    seed.writeAsStringSync('[1, 2]');
    expect(await store.load(), isNull);
  });

  test('clear deletes its own copy and tolerates a missing one', () async {
    await store.clear();
    await store.save(
      FirebaseCredentials(
        idToken: 'i',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2099),
      ),
    );
    await store.clear();
    expect(own.existsSync(), isFalse);
  });
}
