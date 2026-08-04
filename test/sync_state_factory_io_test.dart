/// Tests for the file-backed revision cache.
///
/// The cache is what keeps a sync tick from re-downloading every peer's whole
/// log when nothing has changed, so "does it actually survive a restart" is
/// the behaviour worth pinning.
@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/sync/sync_state_factory_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('todo_state_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('persists revisions across a restart', () async {
    // A fresh store instance stands in for the next app launch: an
    // in-memory cache would forget every peer and re-download everything.
    await openSyncStateStoreIn(dir.path).save(
      const SyncState(pushedRev: 'mine', peerRevs: {'phone': 'theirs'}),
    );

    final reloaded = await openSyncStateStoreIn(dir.path).load();

    expect(reloaded.pushedRev, 'mine');
    expect(reloaded.peerRevs, {'phone': 'theirs'});
  });

  test('writes beside the log it describes', () async {
    await openSyncStateStoreIn(
      dir.path,
    ).save(const SyncState(pushedRev: 'x'));

    expect(File(p.join(dir.path, kSyncStateFileName)).existsSync(), isTrue);
  });

  test('reports nothing remembered before the first sync', () async {
    final state = await openSyncStateStoreIn(dir.path).load();

    expect(state.pushedRev, isNull);
    expect(state.peerRevs, isEmpty);
  });
}
