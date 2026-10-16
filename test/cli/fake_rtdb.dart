/// An in-memory Firebase Realtime Database speaking the REST dialect that
/// `FirebaseRestClient` uses, plus a seed-credentials helper.
///
/// Not named `*_test.dart`: the runner would collect it and fail on the
/// missing `main()`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// The fake database: text blobs keyed by their (still key-escaped) path.
class FakeRtdb {
  /// Every stored leaf, e.g. `todo-sync/notes/<node>~2Ejson` -> log JSON.
  final Map<String, String> files = {};

  /// Methods of every request seen, in order (`GET`, `PUT`, ...).
  final List<String> methods = [];

  /// When set, every request answers with this status and an empty body.
  int? failWith;

  /// The client to hand to the code under test.
  late final http.Client client = http_testing.MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    methods.add(request.method);
    final status = failWith;
    if (status != null) return http.Response('denied', status);
    final path = request.url.path.replaceFirst(RegExp('^/'), '');
    final key = path.endsWith('.json')
        ? path.substring(0, path.length - '.json'.length)
        : path;
    switch (request.method) {
      case 'PUT':
        files[key] = jsonDecode(request.body) as String;
        return http.Response('null', 200);
      case 'DELETE':
        files.remove(key);
        return http.Response('null', 200);
      default:
        return http.Response(_read(key, request.url.queryParameters), 200);
    }
  }

  String _read(String key, Map<String, String> query) {
    final children = <String, String>{
      for (final entry in files.entries)
        if (key.isEmpty || entry.key.startsWith('$key/'))
          entry.key.substring(key.isEmpty ? 0 : key.length + 1): entry.value,
    };
    if (query['shallow'] == 'true') {
      return children.isEmpty
          ? 'null'
          : jsonEncode({for (final k in children.keys) k: true});
    }
    final leaf = files[key];
    if (leaf != null) return jsonEncode(leaf);
    return children.isEmpty ? 'null' : jsonEncode(children);
  }
}

/// Writes a Firebase session that does not expire during a test run.
File writeSeedCredentials(Directory dir, {String name = 'seed.json'}) {
  return File('${dir.path}/$name')..writeAsStringSync(
    jsonEncode({
      'id_token': 'seed-id-token',
      'refresh_token': 'seed-refresh-token',
      'expires_at': '2099-01-01T00:00:00Z',
    }),
  );
}
