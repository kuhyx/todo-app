import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/sync/github_client.dart';

void main() {
  GitHubClient client(MockClient mock) =>
      GitHubClient(owner: 'o', repo: 'r', token: 't', httpClient: mock);

  test('listDirectory returns only files and ignores subdirectories', () async {
    final mock = MockClient((req) async {
      expect(req.headers['Authorization'], contains('t'));
      return http.Response(
        jsonEncode([
          {'type': 'file', 'name': 'a.json', 'path': 'd/a.json', 'sha': 's1'},
          {'type': 'dir', 'name': 'sub', 'path': 'd/sub', 'sha': 's2'},
        ]),
        200,
      );
    });
    final files = await client(mock).listDirectory('d');
    expect(files, hasLength(1));
    expect(files.single.name, 'a.json');
    expect(files.single.sha, 's1');
  });

  test(
    'listDirectory returns empty on 404 (directory not created yet)',
    () async {
      final files = await client(
        MockClient((_) async => http.Response('', 404)),
      ).listDirectory('missing');
      expect(files, isEmpty);
    },
  );

  test('getFileText base64-decodes content; null on 404', () async {
    final encoded = base64.encode(utf8.encode('hello world'));
    final ok = MockClient(
      (_) async => http.Response(jsonEncode({'content': encoded}), 200),
    );
    expect(await client(ok).getFileText('f'), 'hello world');

    final missing = MockClient((_) async => http.Response('', 404));
    expect(await client(missing).getFileText('f'), isNull);
  });

  test(
    'putFileText omits sha when creating, includes it when updating',
    () async {
      String? sentBody;
      final mock = MockClient((req) async {
        sentBody = req.body;
        return http.Response('{}', 201);
      });
      await client(mock).putFileText('f', 'data');
      expect(jsonDecode(sentBody!).containsKey('sha'), isFalse);

      await client(mock).putFileText('f', 'data', sha: 'abc');
      expect(jsonDecode(sentBody!)['sha'], 'abc');
    },
  );

  test('deleteFile sends the sha', () async {
    String? body;
    final mock = MockClient((req) async {
      body = req.body;
      return http.Response('{}', 200);
    });
    await client(mock).deleteFile('f', 'sha123');
    expect(jsonDecode(body!)['sha'], 'sha123');
  });

  test('canAccessRepo reflects the status code', () async {
    expect(
      await client(
        MockClient((_) async => http.Response('{}', 200)),
      ).canAccessRepo(),
      isTrue,
    );
    expect(
      await client(
        MockClient((_) async => http.Response('', 403)),
      ).canAccessRepo(),
      isFalse,
    );
  });

  test('throws GitHubApiException on a non-2xx that is not 404', () async {
    final mock = MockClient((_) async => http.Response('boom', 500));
    expect(
      () => client(mock).getFileText('f'),
      throwsA(isA<GitHubApiException>()),
    );
  });
}
