/// The pull half must not scale with peers one after another.
///
/// The board reported a 3.9 s sync on the Pixel (todo:0c575b891b): eight
/// peers of about 2 MB each were fetched, decrypted, parsed and merged in
/// series, each merge rewriting the whole local store.
@TestOn('vm')
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';

import 'sync_service_fakes.dart';

/// A [FakeRemote] whose every call waits [delay] and tracks how many of
/// them are in flight at once.
class _SlowRemote extends FakeRemote {
  _SlowRemote(super.files);

  static const delay = Duration(milliseconds: 50);
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<T> _slow<T>(Future<T> Function() run) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await Future<void>.delayed(delay);
      return await run();
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<String?> getFileText(String path) =>
      _slow(() => super.getFileText(path));

  @override
  Future<List<String>> listDirectory(String path) =>
      _slow(() => super.listDirectory(path));

  @override
  Future<Map<String, String>> getStringMap(String path) =>
      _slow(() => super.getStringMap(path));
}

/// A [FakeRemote] that cannot decrypt [undecryptable].
class _LockedPeerRemote extends FakeRemote {
  _LockedPeerRemote(super.files, this.undecryptable);

  final String undecryptable;

  @override
  Future<String?> getFileText(String path) async {
    if (path.endsWith(undecryptable)) throw E2eDecryptError('wrong key');
    return super.getFileText(path);
  }
}

/// Counts writes to the local store.
class _CountingPersistence extends MemoryPersistence {
  int writes = 0;

  @override
  Future<void> write(String text) {
    writes++;
    return super.write(text);
  }
}

Future<Map<String, String>> _peers(int count) async {
  final files = <String, String>{};
  for (var i = 0; i < count; i++) {
    final text = logToJson(await buildPeerLog(title: 'peer $i'));
    files['todo-sync/notes/peer$i.json'] = text;
    files['todo-sync/revs/peer$i'] = revisionOf(text);
  }
  return files;
}

void main() {
  test('fetches changed peers and the revision map concurrently', () async {
    final remote = _SlowRemote(await _peers(4));
    final repo = await NoteRepository.openInMemory(nodeId: 'me');
    addTearDown(repo.close);

    final result = await SyncService(
      stateStore: InMemorySyncStateStore(),
    ).sync(repo, remote);

    expect(result.mergedDevices, 4);
    expect(remote.maxInFlight, greaterThanOrEqualTo(4));
  });

  test('merges every changed peer with one local store write', () async {
    final remote = FakeRemote(await _peers(3));
    final persistence = _CountingPersistence();
    final repo = await NoteRepository.openWith(
      persistence: persistence,
      nodeId: 'me',
    );
    addTearDown(repo.close);
    persistence.writes = 0;

    final result = await SyncService(
      stateStore: InMemorySyncStateStore(),
    ).sync(repo, remote);

    expect(result.mergedDevices, 3);
    expect(persistence.writes, 1);
    expect(await repo.listNotes(), hasLength(1)); // same id on every peer
  });

  test('still skips an undecodable peer and merges the rest', () async {
    final files = await _peers(2);
    files['todo-sync/notes/bad.json'] = '{not json';
    final repo = await NoteRepository.openInMemory(nodeId: 'me');
    addTearDown(repo.close);

    final result = await SyncService(
      stateStore: InMemorySyncStateStore(),
    ).sync(repo, FakeRemote(files));

    expect(result.mergedDevices, 2);
    expect(result.skippedFiles, ['bad.json']);
  });

  test('skips a peer it cannot decrypt and merges the rest', () async {
    final repo = await NoteRepository.openInMemory(nodeId: 'me');
    addTearDown(repo.close);

    final result = await SyncService(
      stateStore: InMemorySyncStateStore(),
    ).sync(repo, _LockedPeerRemote(await _peers(2), 'peer1.json'));

    expect(result.mergedDevices, 1);
    expect(result.skippedFiles, ['peer1.json']);
  });

  test('a phone-sized peer log decodes on a background isolate', () async {
    // Over the inline threshold, so this runs the isolate path end to end.
    final big = logToJson(await buildPeerLog(title: 'x' * 100000));
    final repo = await NoteRepository.openInMemory(nodeId: 'me');
    addTearDown(repo.close);

    final result = await SyncService().sync(
      repo,
      FakeRemote({'todo-sync/notes/big.json': big}),
    );

    expect(result.mergedDevices, 1);
    expect((await repo.listNotes()).single.text, 'x' * 100000);
  });
}
