import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';

http.Response _response(int statusCode, [Object? jsonBody]) =>
    http.Response(jsonEncode(jsonBody ?? {}), statusCode);

http.Response _fileWith(String text, {String? sha}) =>
    _response(200, {'content': base64.encode(utf8.encode(text)), 'sha': ?sha});

class _PutCall {
  _PutCall(this.path, this.body);
  final String path;
  final Map<String, dynamic> body;
}

/// Mock GitHub Contents API router matching crdt_sync's client: GET
/// `.../contents/<key>` returns [contentResponses]`[key]` (404 if absent), the
/// bare repo-existence GET always succeeds, and every PUT is recorded.
({http.Client httpClient, List<_PutCall> putCalls}) _mockGitHub({
  Map<String, http.Response> contentResponses = const {},
}) {
  final putCalls = <_PutCall>[];
  final client = http_testing.MockClient((request) async {
    final path = request.url.path;
    if (!path.contains('/contents/')) return _response(200); // repo-exists
    final key = path.split('/contents/').last;
    if (request.method == 'PUT') {
      putCalls.add(
        _PutCall(key, jsonDecode(request.body) as Map<String, dynamic>),
      );
      return _response(200);
    }
    return contentResponses[key] ?? _response(404);
  });
  return (httpClient: client, putCalls: putCalls);
}

GitHubClient _github(http.Client mock) =>
    GitHubClient(owner: 'o', repo: 'r', token: 't', httpClient: mock);

Note _note(String id, String text) => Note(
  id: id,
  text: text,
  priority: Priority.medium,
  status: Status.todo,
  createdAt: DateTime(2026, 6, 15),
  updatedAt: DateTime(2026, 6, 15),
);

void main() {
  _revisionTrackingTests();
  test('pulls and merges another device, then pushes its own', () async {
    final other = await NoteRepository.openInMemory(nodeId: 'otherNode');
    await other.upsert(_note('x', 'from other device'));
    final otherLog = logToJson(other.exportLog());
    await other.close();

    final (:httpClient, :putCalls) = _mockGitHub(
      contentResponses: {
        'todo-sync/notes': _response(200, [
          {'name': 'otherNode.json'},
        ]),
        'todo-sync/notes/otherNode.json': _fileWith(otherLog),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(httpClient));

    expect(result.mergedDevices, 1);
    expect(result.pushed, isTrue);
    expect(result.toString(), contains('mergedDevices: 1'));
    expect(putCalls.single.path, 'todo-sync/notes/localNode.json');
    final texts = (await local.listNotes()).map((n) => n.text);
    expect(texts, contains('from other device'));
  });

  test('with no remote files, still pushes its own log', () async {
    final (:httpClient, :putCalls) = _mockGitHub(
      contentResponses: {'todo-sync/notes': _response(200, <Object>[])},
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(httpClient));
    expect(result.mergedDevices, 0);
    expect(putCalls, hasLength(1));
  });

  test('updates its own already-present file using its resolved sha', () async {
    final (:httpClient, :putCalls) = _mockGitHub(
      contentResponses: {
        'todo-sync/notes': _response(200, [
          {'name': 'localNode.json'},
        ]),
        'todo-sync/notes/localNode.json': _fileWith('{}', sha: 'own-sha-123'),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(httpClient));
    expect(result.mergedDevices, 0); // own file is not a peer to merge
    expect(putCalls.single.body['sha'], 'own-sha-123'); // put reused the sha
  });

  test('a corrupt or wrong-shape peer file is skipped, not fatal', () async {
    final (:httpClient, :putCalls) = _mockGitHub(
      contentResponses: {
        'todo-sync/notes': _response(200, [
          {'name': 'bad1.json'},
          {'name': 'bad2.json'},
        ]),
        'todo-sync/notes/bad1.json': _fileWith('{not json'),
        'todo-sync/notes/bad2.json': _fileWith('[]'),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(httpClient));
    expect(result.mergedDevices, 0); // both bad files skipped
    expect(putCalls, hasLength(1));
    // The skips are reported, not silent: that's how a peer device dropping
    // out of the merge becomes visible in the UI.
    expect(result.skippedFiles, ['bad1.json', 'bad2.json']);
    expect(result.toString(), contains('bad1.json'));
  });

  test('a listed-but-unfetchable peer file is reported as skipped', () async {
    // The file appears in the directory listing but its GET 404s (deleted
    // between list and fetch, or contents unavailable).
    final (:httpClient, :putCalls) = _mockGitHub(
      contentResponses: {
        'todo-sync/notes': _response(200, [
          {'name': 'gone.json'},
        ]),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(httpClient));
    expect(result.mergedDevices, 0);
    expect(result.skippedFiles, ['gone.json']);
    expect(putCalls, hasLength(1)); // the push still happened
  });
}

/// An in-memory [RemoteStore] that also serves revision maps in one read,
/// standing in for Firebase. Counts reads so tests can assert on *traffic*
/// rather than on the merge result.
class _FakeRemote implements RemoteStore, BulkMapReader {
  _FakeRemote(this.files);

  final Map<String, String> files;
  final List<String> reads = [];
  final List<String> writes = [];

  @override
  Future<List<String>> listDirectory(String path) async => files.keys
      .where((k) => k.startsWith('$path/'))
      .map((k) => k.substring(path.length + 1).split('/').first)
      .toSet()
      .toList();

  @override
  Future<String?> getFileText(String path) async {
    reads.add(path);
    return files[path];
  }

  @override
  Future<void> putFileText(
    String path,
    String text, {
    required String message,
  }) async {
    writes.add(path);
    files[path] = text;
  }

  @override
  Future<Map<String, String>> getStringMap(String path) async => {
    for (final e in files.entries)
      if (e.key.startsWith('$path/')) e.key.substring(path.length + 1): e.value,
  };

  @override
  Future<void> deleteFile(String path, {String message = ''}) async =>
      files.remove(path);

  @override
  Future<bool> canAccessRemote() async => true;

  @override
  void close() {}
}

/// A [RemoteStore] with no bulk-map read, standing in for GitHub.
///
/// Delegates rather than extends: a subclass of [_FakeRemote] would inherit
/// `BulkMapReader`, the very capability this fake exists to lack.
class _FakeRemoteWithoutBulkRead implements RemoteStore {
  _FakeRemoteWithoutBulkRead(Map<String, String> files)
    : _inner = _FakeRemote(files);

  final _FakeRemote _inner;

  List<String> get reads => _inner.reads;

  @override
  Future<List<String>> listDirectory(String path) => _inner.listDirectory(path);

  @override
  Future<String?> getFileText(String path) => _inner.getFileText(path);

  @override
  Future<void> putFileText(
    String path,
    String text, {
    required String message,
  }) => _inner.putFileText(path, text, message: message);

  @override
  Future<void> deleteFile(String path, {String message = ''}) =>
      _inner.deleteFile(path, message: message);

  @override
  Future<bool> canAccessRemote() => _inner.canAccessRemote();

  @override
  void close() => _inner.close();
}

void _revisionTrackingTests() {
  group('revision tracking', () {
    late NoteRepository repo;

    setUp(() async {
      repo = await NoteRepository.openInMemory(nodeId: 'me');
    });

    tearDown(() async => repo.close());

    test('skips a peer whose revision has not changed', () async {
      // The saving the free-tier budget depends on: an unchanged ~150 KB peer
      // log must not be downloaded again.
      final peerLog = logToJson(await _peerLog());
      final remote = _FakeRemote({
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
      final first = logToJson(await _peerLog());
      final remote = _FakeRemote({
        'todo-sync/notes/phone.json': first,
        'todo-sync/revs/phone': revisionOf(first),
      });
      final store = InMemorySyncStateStore();
      await SyncService(stateStore: store).sync(repo, remote);
      remote.reads.clear();

      final changed = logToJson(await _peerLog(title: 'changed'));
      remote.files['todo-sync/notes/phone.json'] = changed;
      remote.files['todo-sync/revs/phone'] = revisionOf(changed);
      final second = await SyncService(stateStore: store).sync(repo, remote);

      expect(remote.reads, contains('todo-sync/notes/phone.json'));
      expect(second.mergedDevices, 1);
    });

    test('suppresses an unchanged push and publishes a revision', () async {
      final remote = _FakeRemote({});
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
      final peerLog = logToJson(await _peerLog());
      final remote = _FakeRemoteWithoutBulkRead({
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

/// Builds a one-note log as it would arrive from another device.
Future<Log> _peerLog({String title = 'from phone'}) async {
  final peer = await NoteRepository.openInMemory(nodeId: 'phone');
  await peer.upsert(_note('peer-note', title));
  final log = peer.exportLog();
  await peer.close();
  return log;
}
