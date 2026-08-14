/// The GitHub/remote fakes and note fixtures shared by the sync_service
/// test files.
///
/// `sync_service_test.dart` was split for the 250-line cap. The underscores
/// came off every name here: Dart privacy is library-scoped, so a `_Fake`
/// declared in one file is invisible to the next.
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it and
/// fail on the missing `main()`.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';

http.Response response(int statusCode, [Object? jsonBody]) =>
    http.Response(jsonEncode(jsonBody ?? {}), statusCode);

http.Response fileWith(String text, {String? sha}) =>
    response(200, {'content': base64.encode(utf8.encode(text)), 'sha': ?sha});

class PutCall {
  PutCall(this.path, this.body);
  final String path;
  final Map<String, dynamic> body;
}

/// Mock GitHub Contents API router matching crdt_sync's client: GET
/// `.../contents/<key>` returns [contentResponses]`[key]` (404 if absent), the
/// bare repo-existence GET always succeeds, and every PUT is recorded.
({http.Client httpClient, List<PutCall> putCalls}) mockGitHub({
  Map<String, http.Response> contentResponses = const {},
}) {
  final putCalls = <PutCall>[];
  final client = http_testing.MockClient((request) async {
    final path = request.url.path;
    if (!path.contains('/contents/')) return response(200); // repo-exists
    final key = path.split('/contents/').last;
    if (request.method == 'PUT') {
      putCalls.add(
        PutCall(key, jsonDecode(request.body) as Map<String, dynamic>),
      );
      return response(200);
    }
    return contentResponses[key] ?? response(404);
  });
  return (httpClient: client, putCalls: putCalls);
}

GitHubClient github(http.Client mock) =>
    GitHubClient(owner: 'o', repo: 'r', token: 't', httpClient: mock);

Note note(String id, String text) => Note(
  id: id,
  text: text,
  priority: Priority.medium,
  status: Status.todo,
  createdAt: DateTime(2026, 6, 15),
  updatedAt: DateTime(2026, 6, 15),
);

/// An in-memory [RemoteStore] that also serves revision maps in one read,
/// standing in for Firebase. Counts reads so tests can assert on *traffic*
/// rather than on the merge result.
class FakeRemote implements RemoteStore, BulkMapReader {
  FakeRemote(this.files);

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
/// Delegates rather than extends: a subclass of [FakeRemote] would inherit
/// `BulkMapReader`, the very capability this fake exists to lack.
class FakeRemoteWithoutBulkRead implements RemoteStore {
  FakeRemoteWithoutBulkRead(Map<String, String> files)
    : _inner = FakeRemote(files);

  final FakeRemote _inner;

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

/// Builds a one-note log as it would arrive from another device.
Future<Log> buildPeerLog({String title = 'from phone'}) async {
  final peer = await NoteRepository.openInMemory(nodeId: 'phone');
  await peer.upsert(note('peer-note', title));
  final log = peer.exportLog();
  await peer.close();
  return log;
}
