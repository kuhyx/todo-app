import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/github_client.dart';
import 'package:todo/sync/sync_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('sync pulls and merges another device, then pushes its own', () async {
    final dir = await Directory.systemTemp.createTemp('todo_sync');
    addTearDown(() => dir.delete(recursive: true));

    // Build a second device's changeset and serialise it the way it would
    // be stored in the repo (hlc as a String, base64 in the API response).
    final other = await NoteRepository.open('${dir.path}/other.db');
    await other.upsert(
      Note(
        id: 'x',
        text: 'from other device',
        priority: Priority.medium,
        status: Status.todo,
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 15),
      ),
    );
    final otherJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(await other.getChangeset());
    await other.close();
    final fileResponse = jsonEncode({
      'content': base64.encode(utf8.encode(otherJson)),
    });

    const otherFile = 'otherNode.json';
    final listResponse = jsonEncode([
      {
        'type': 'file',
        'name': otherFile,
        'path': 'todo-sync/changesets/$otherFile',
        'sha': 'sha-other',
      },
    ]);

    var putCount = 0;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        putCount++;
        return http.Response('{}', 200);
      }
      if (req.url.path.endsWith('/contents/todo-sync/changesets')) {
        return http.Response(listResponse, 200); // directory listing
      }
      return http.Response(fileResponse, 200); // the other device's file
    });

    final local = await NoteRepository.open('${dir.path}/local.db');
    addTearDown(local.close);
    final github = GitHubClient(
      owner: 'o',
      repo: 'r',
      token: 't',
      httpClient: mock,
    );

    final result = await const SyncService().sync(local, github);

    expect(result.mergedDevices, 1);
    expect(result.pushed, isTrue);
    expect(result.toString(), contains('mergedDevices: 1'));
    expect(putCount, 1); // pushed our own changeset
    final texts = (await local.listNotes()).map((n) => n.text);
    expect(texts, contains('from other device'));
  });

  test('sync with no remote files still pushes own changeset', () async {
    final dir = await Directory.systemTemp.createTemp('todo_sync_empty');
    addTearDown(() => dir.delete(recursive: true));

    var putCount = 0;
    final mock = MockClient((req) async {
      if (req.method == 'PUT') {
        putCount++;
        return http.Response('{}', 200);
      }
      return http.Response('', 404); // empty/missing changesets dir
    });

    final local = await NoteRepository.open('${dir.path}/local.db');
    addTearDown(local.close);
    final github = GitHubClient(
      owner: 'o',
      repo: 'r',
      token: 't',
      httpClient: mock,
    );

    final result = await const SyncService().sync(local, github);
    expect(result.mergedDevices, 0);
    expect(result.pushed, isTrue);
    expect(putCount, 1);
  });

  test('sync updates its own already-present changeset file', () async {
    final dir = await Directory.systemTemp.createTemp('todo_sync_own');
    addTearDown(() => dir.delete(recursive: true));

    final local = await NoteRepository.open('${dir.path}/local.db');
    addTearDown(local.close);

    // The remote listing already contains *this* device's changeset file.
    // The sync must recognise it (by node id), skip merging itself, remember
    // the sha, and PUT an update rather than treating it as a peer device.
    final ownFile = '${local.nodeId}.json';
    final listResponse = jsonEncode([
      {
        'type': 'file',
        'name': ownFile,
        'path': 'todo-sync/changesets/$ownFile',
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

    final github = GitHubClient(
      owner: 'o',
      repo: 'r',
      token: 't',
      httpClient: mock,
    );

    final result = await const SyncService().sync(local, github);
    expect(result.mergedDevices, 0); // own file is not a peer to merge
    expect(result.pushed, isTrue);
    expect(putSha, 'own-sha-123'); // updated in place using the remembered sha
  });
}
