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
  });
}
