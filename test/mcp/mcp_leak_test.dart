// Abandoned requests must not leak sockets. Dart's HttpServer never notices a
// client that hung up on a request still being worked on, so 1010 sockets sat
// in CLOSE-WAIT and the process ran out of fds (2026-11-16). The server now
// answers 503 and closes any request still open at its deadline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/mcp/todo_mcp_server.dart';
import 'package:todo/mcp/token_file.dart';
import 'package:todo/sync/sync_service.dart';

/// A session whose sync never returns: every tool call wedges.
class _Wedged extends CliSession {
  _Wedged(NoteRepository repo, FirebaseRestClient firebase)
    : super('unused', repo, firebase);

  @override
  Future<SyncResult> sync({required bool push}) =>
      Completer<SyncResult>().future;
}

int _openFds() => Directory('/proc/self/fd').listSync().length;

const _init =
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
    '{"protocolVersion":"2025-06-18","capabilities":{},'
    '"clientInfo":{"name":"leak","version":"1"}}}';
const _ready = '{"jsonrpc":"2.0","method":"notifications/initialized"}';
const _call =
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":'
    '{"name":"list_tasks","arguments":{}}}';

void main() {
  late Directory tmp;
  late TodoMcpServer server;
  late List<String> logged;

  Future<void> start({required Duration callTimeout}) async {
    tmp = Directory.systemTemp.createTempSync('mcp_leak');
    final firebase = FirebaseRestClient(
      databaseUrl: 'https://example.test',
      auth: FirebaseTokenProvider(
        apiKey: 'k',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'rt',
            expiresAt: DateTime.utc(2099),
          ),
        ),
      ),
      httpClient: http.Client(),
    );
    final tokens = File('${tmp.path}/tokens')
      ..writeAsStringSync('${tokenHash('t')} pc\n');
    logged = [];
    server = await TodoMcpServer.start(
      tasks: TaskService(
        _Wedged(await NoteRepository.openInMemory(), firebase),
        callTimeout: callTimeout,
      ),
      tokens: tokens,
      port: 0,
      requestDeadline: const Duration(milliseconds: 400),
      log: logged.add,
    );
  }

  tearDown(() async {
    await server.close();
    tmp.deleteSync(recursive: true);
  });

  /// POSTs [body] with the bearer token and returns status and session id.
  Future<(int, String?)> post(String body, {String? session}) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(server.uri);
      req.headers
        ..set('content-type', 'application/json')
        ..set('accept', 'application/json, text/event-stream')
        ..set('authorization', 'Bearer t');
      if (session != null) req.headers.set('mcp-session-id', session);
      req.write(body);
      final res = await req.close();
      await res.drain<void>();
      return (res.statusCode, res.headers.value('mcp-session-id'));
    } finally {
      client.close(force: true);
    }
  }

  /// Opens a ready session and returns its id.
  Future<String> open() async {
    final (status, session) = await post(_init);
    expect(status, 200);
    expect((await post(_ready, session: session)).$1, 202);
    return session!;
  }

  /// Sends a tools/call, then hangs up before any answer.
  Future<void> callAndAbort(String session) async {
    final client = HttpClient();
    final req = await client.postUrl(server.uri);
    req.headers
      ..set('content-type', 'application/json')
      ..set('accept', 'application/json, text/event-stream')
      ..set('authorization', 'Bearer t')
      ..set('mcp-session-id', session);
    req.add(utf8.encode(_call));
    unawaited(req.close().then<void>((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    client.close(force: true);
  }

  Future<void> expectFdsBackTo(int baseline) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (_openFds() > baseline && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(_openFds(), lessThanOrEqualTo(baseline));
  }

  test('[T-fd-leak] aborted requests against a wedged call free their '
      'sockets', () async {
    await start(callTimeout: const Duration(hours: 1));
    final session = await open();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final baseline = _openFds();

    for (var i = 0; i < 12; i++) {
      await callAndAbort(session);
    }

    await expectFdsBackTo(baseline);
    // The server still answers afterwards.
    expect((await post(_init)).$1, 200);
  });

  test('[T-fd-leak] the late tool error after the deadline cannot crash '
      'the server', () async {
    await start(callTimeout: const Duration(milliseconds: 900));
    await callAndAbort(await open());
    // Deadline (400 ms) closes the response; the call errors at 900 ms and
    // tries to write into it.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    expect((await post(_init)).$1, 200);
  });

  test('a call that finishes before the deadline is untouched', () async {
    await start(callTimeout: const Duration(milliseconds: 100));
    final (status, _) = await post(_call, session: await open());
    expect(status, 200, reason: 'tool error is a normal 200 result');
  });
}
