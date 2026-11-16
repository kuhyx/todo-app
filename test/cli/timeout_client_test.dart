// Every Firebase and token call a CliSession makes is bounded: a request that
// never answers (dead connection, blackholed route) must fail with a
// TimeoutException instead of holding the MCP server's one-at-a-time queue.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/timeout_client.dart';

import 'fake_rtdb.dart';

const _limit = Duration(milliseconds: 150);

http.Client _answering({Stream<List<int>>? body}) =>
    http_testing.MockClient.streaming(
      (request, _) async =>
          http.StreamedResponse(body ?? Stream.value([111, 107]), 200),
    );

void main() {
  test('a fast response passes through untouched', () async {
    final client = TimeoutClient(_answering(), timeout: _limit);
    expect((await client.get(Uri.parse('http://x.test/'))).body, 'ok');
  });

  test('[T-http-timeout] a request that never answers times out', () async {
    final client = TimeoutClient(
      http_testing.MockClient((_) => Completer<http.Response>().future),
      timeout: _limit,
    );
    await expectLater(
      client.get(Uri.parse('http://x.test/')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a body that stalls after the headers times out', () async {
    final stalled = StreamController<List<int>>()..add([1]);
    final client = TimeoutClient(
      _answering(body: stalled.stream),
      timeout: _limit,
    );
    await expectLater(
      client.get(Uri.parse('http://x.test/')),
      throwsA(isA<TimeoutException>()),
    );
    await stalled.close();
  });

  test('a slow but moving body is not cut off', () async {
    final slow = Stream.periodic(
      const Duration(milliseconds: 60),
      (i) => [i],
    ).take(5);
    final client = TimeoutClient(_answering(body: slow), timeout: _limit);
    expect(
      (await client.get(Uri.parse('http://x.test/'))).bodyBytes,
      hasLength(5),
    );
  });

  test(
    '[T-http-timeout] a CliSession sync against a dead network fails',
    () async {
      final tmp = Directory.systemTemp.createTempSync('timeout_client');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final session = await CliSession.open(
        '${tmp.path}/data',
        seedCredentials: writeSeedCredentials(tmp).path,
        httpClient: http_testing.MockClient(
          (_) => Completer<http.Response>().future,
        ),
        requestTimeout: _limit,
      );
      addTearDown(session.close);
      await expectLater(
        session.sync(push: true),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
