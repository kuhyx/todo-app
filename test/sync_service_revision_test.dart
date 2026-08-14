import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';

import 'sync_service_fakes.dart';

void main() {
  group('revision tracking', () {
    late NoteRepository repo;

    setUp(() async {
      repo = await NoteRepository.openInMemory(nodeId: 'me');
    });

    tearDown(() async => repo.close());

    test('skips a peer whose revision has not changed', () async {
      // The saving the free-tier budget depends on: an unchanged ~150 KB peer
      // log must not be downloaded again.
      final peerLog = logToJson(await buildPeerLog());
      final remote = FakeRemote({
        'todo-sync/notes/phone.json': peerLog,
        'todo-sync/revs/phone': revisionOf(peerLog),
      });
      final store = InMemorySyncStateStore();

      await SyncService(stateStore: store).sync(repo, remote);
      remote.reads.clear();
      final second = await SyncService(stateStore: store).sync(repo, remote);

      expect(remote.reads, isNot(contains('todo-sync/notes/phone.json')));
      expect(second.skippedUnchanged, 1);
      expect(second.mergedDevices, 0);
    });

    test('downloads again once the peer publishes a new revision', () async {
      final first = logToJson(await buildPeerLog());
      final remote = FakeRemote({
        'todo-sync/notes/phone.json': first,
        'todo-sync/revs/phone': revisionOf(first),
      });
      final store = InMemorySyncStateStore();
      await SyncService(stateStore: store).sync(repo, remote);
      remote.reads.clear();

      final changed = logToJson(await buildPeerLog(title: 'changed'));
      remote.files['todo-sync/notes/phone.json'] = changed;
      remote.files['todo-sync/revs/phone'] = revisionOf(changed);
      final second = await SyncService(stateStore: store).sync(repo, remote);

      expect(remote.reads, contains('todo-sync/notes/phone.json'));
      expect(second.mergedDevices, 1);
    });

    test('suppresses an unchanged push and publishes a revision', () async {
      final remote = FakeRemote({});
      final store = InMemorySyncStateStore();

      final first = await SyncService(stateStore: store).sync(repo, remote);
      expect(first.pushed, isTrue);
      expect(remote.writes, [
        'todo-sync/notes/me.json',
        'todo-sync/revs/me',
      ]);
      remote.writes.clear();

      final second = await SyncService(stateStore: store).sync(repo, remote);

      expect(second.pushed, isFalse);
      expect(remote.writes, isEmpty);
    });

    test('still syncs on a backend without a bulk-map read', () async {
      // GitHub has no cheap revision map; correctness must not depend on the
      // optimisation being available.
      final peerLog = logToJson(await buildPeerLog());
      final remote = FakeRemoteWithoutBulkRead({
        'todo-sync/notes/phone.json': peerLog,
      });

      final result = await SyncService(
        stateStore: InMemorySyncStateStore(),
      ).sync(repo, remote);

      expect(result.mergedDevices, 1);
      expect(remote.reads, contains('todo-sync/notes/phone.json'));
    });
  });
}
