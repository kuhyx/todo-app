import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' hide GitHubClient;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/github_client.dart';
import 'package:todo/sync/sync_service.dart';

GitHubClient _github(MockClient mock) =>
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
  test('sync pulls and merges another device, then pushes its own', () async {
    // Build a second device's note log and serialise it the way it is stored
    // in the repo (a crdt_sync Log JSON, base64 in the API response).
    final other = await NoteRepository.openInMemory(nodeId: 'otherNode');
    await other.upsert(_note('x', 'from other device'));
    final otherJson = logToJson(other.exportLog());
    await other.close();
    final fileResponse = jsonEncode({
      'content': base64.encode(utf8.encode(otherJson)),
    });

    const otherFile = 'otherNode.json';
    final listResponse = jsonEncode([
      {
        'type': 'file',
        'name': otherFile,
        'path': 'todo-sync/notes/$otherFile',
        'sha': 'sha-other',
      },
    ]);

    var putCount = 0;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        putCount++;
        return http.Response('{}', 200);
      }
      if (req.url.path.endsWith('/contents/todo-sync/notes')) {
        return http.Response(listResponse, 200); // directory listing
      }
      return http.Response(fileResponse, 200); // the other device's file
    });

    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(mock));

    expect(result.mergedDevices, 1);
    expect(result.pushed, isTrue);
    expect(result.toString(), contains('mergedDevices: 1'));
    expect(putCount, 1); // pushed our own log
    final texts = (await local.listNotes()).map((n) => n.text);
    expect(texts, contains('from other device'));
  });

  test('sync with no remote files still pushes own log', () async {
    var putCount = 0;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        putCount++;
        return http.Response('{}', 200);
      }
      return http.Response('', 404); // empty/missing notes dir
    });

    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(mock));
    expect(result.mergedDevices, 0);
    expect(result.pushed, isTrue);
    expect(putCount, 1);
  });

  test('sync updates its own already-present log file', () async {
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    // The remote listing already contains *this* device's log file. The sync
    // must recognise it (by node id), skip merging itself, remember the sha,
    // and PUT an update rather than treating it as a peer device.
    final ownFile = '${local.nodeId}.json';
    final listResponse = jsonEncode([
      {
        'type': 'file',
        'name': ownFile,
        'path': 'todo-sync/notes/$ownFile',
        'sha': 'own-sha-123',
      },
    ]);

    String? putSha;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        putSha = body['sha'] as String?;
        return http.Response('{}', 200);
      }
      return http.Response(listResponse, 200);
    });

    final result = await const SyncService().sync(local, _github(mock));
    expect(result.mergedDevices, 0); // own file is not a peer to merge
    expect(result.pushed, isTrue);
    expect(putSha, 'own-sha-123'); // updated in place using the remembered sha
  });

  test('a corrupt or wrong-shape peer file is skipped, not fatal', () async {
    String file(String content) =>
        jsonEncode({'content': base64.encode(utf8.encode(content))});
    final listResponse = jsonEncode([
      {
        'type': 'file',
        'name': 'bad1.json',
        'path': 'todo-sync/notes/bad1.json',
        'sha': 's1',
      },
      {
        'type': 'file',
        'name': 'bad2.json',
        'path': 'todo-sync/notes/bad2.json',
        'sha': 's2',
      },
    ]);

    var putCount = 0;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        putCount++;
        return http.Response('{}', 200);
      }
      if (req.url.path.endsWith('/contents/todo-sync/notes')) {
        return http.Response(listResponse, 200);
      }
      if (req.url.path.endsWith('bad1.json')) {
        return http.Response(file('{not json'), 200); // FormatException
      }
      return http.Response(file('[]'), 200); // valid JSON, wrong shape
    });

    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, _github(mock));
    expect(result.mergedDevices, 0); // both bad files skipped
    expect(putCount, 1); // still pushed our own log
  });
}
