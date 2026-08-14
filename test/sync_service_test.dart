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
  test('pulls and merges another device, then pushes its own', () async {
    final other = await NoteRepository.openInMemory(nodeId: 'otherNode');
    await other.upsert(note('x', 'from other device'));
    final otherLog = logToJson(other.exportLog());
    await other.close();

    final (:httpClient, :putCalls) = mockGitHub(
      contentResponses: {
        'todo-sync/notes': response(200, [
          {'name': 'otherNode.json'},
        ]),
        'todo-sync/notes/otherNode.json': fileWith(otherLog),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, github(httpClient));

    expect(result.mergedDevices, 1);
    expect(result.pushed, isTrue);
    expect(result.toString(), contains('mergedDevices: 1'));
    expect(putCalls.single.path, 'todo-sync/notes/localNode.json');
    final texts = (await local.listNotes()).map((n) => n.text);
    expect(texts, contains('from other device'));
  });

  test('withFirebaseConnected copies every other field unchanged', () {
    // SyncService itself never sets firebaseConnected -- only runSync does,
    // since SyncService is deliberately agnostic to which RemoteStore it was
    // handed. This is the seam that lets runSync attach that fact afterward.
    const original = SyncResult(
      mergedDevices: 2,
      pushed: true,
      skippedFiles: ['bad.json'],
      skippedUnchanged: 3,
    );

    final connected = original.withFirebaseConnected(value: true);

    expect(connected.firebaseConnected, isTrue);
    expect(connected.mergedDevices, original.mergedDevices);
    expect(connected.pushed, original.pushed);
    expect(connected.skippedFiles, original.skippedFiles);
    expect(connected.skippedUnchanged, original.skippedUnchanged);
    expect(connected.toString(), contains('firebaseConnected: true'));
  });

  test('with no remote files, still pushes its own log', () async {
    final (:httpClient, :putCalls) = mockGitHub(
      contentResponses: {'todo-sync/notes': response(200, <Object>[])},
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, github(httpClient));
    expect(result.mergedDevices, 0);
    expect(putCalls, hasLength(1));
  });

  test('updates its own already-present file using its resolved sha', () async {
    final (:httpClient, :putCalls) = mockGitHub(
      contentResponses: {
        'todo-sync/notes': response(200, [
          {'name': 'localNode.json'},
        ]),
        'todo-sync/notes/localNode.json': fileWith('{}', sha: 'own-sha-123'),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, github(httpClient));
    expect(result.mergedDevices, 0); // own file is not a peer to merge
    expect(putCalls.single.body['sha'], 'own-sha-123'); // put reused the sha
  });

  test('a corrupt or wrong-shape peer file is skipped, not fatal', () async {
    final (:httpClient, :putCalls) = mockGitHub(
      contentResponses: {
        'todo-sync/notes': response(200, [
          {'name': 'bad1.json'},
          {'name': 'bad2.json'},
        ]),
        'todo-sync/notes/bad1.json': fileWith('{not json'),
        'todo-sync/notes/bad2.json': fileWith('[]'),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, github(httpClient));
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
    final (:httpClient, :putCalls) = mockGitHub(
      contentResponses: {
        'todo-sync/notes': response(200, [
          {'name': 'gone.json'},
        ]),
      },
    );
    final local = await NoteRepository.openInMemory(nodeId: 'localNode');
    addTearDown(local.close);

    final result = await const SyncService().sync(local, github(httpClient));
    expect(result.mergedDevices, 0);
    expect(result.skippedFiles, ['gone.json']);
    expect(putCalls, hasLength(1)); // the push still happened
  });
}
