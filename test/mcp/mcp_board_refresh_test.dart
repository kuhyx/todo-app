// T1865: the real board learns about notes by calling this MCP server, so a
// merged add_task must not hold the server while it waits for the board.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/mcp/board_client.dart';

import 'mcp_harness.dart';

void main() {
  late McpHarness h;
  late McpClient c;
  late McpClient boardSide;
  String? note;
  var cards = <Map<String, dynamic>>[];
  final posts = <String>[];

  // A board whose every read refreshes its cards from this MCP server, as
  // the real one does; a refresh that cannot get through keeps stale cards.
  Future<List<Map<String, dynamic>>> refresh() async {
    final id = note;
    if (id == null) return cards;
    try {
      final text = await h
          .call(boardSide, 'get_task', {'id': id})
          .timeout(const Duration(milliseconds: 300));
      final n = '\n$text'.split('\n## ').length - 1;
      cards = [
        for (var i = 0; i < n; i++)
          {
            'id': '${id.substring(0, 8)}-$i',
            'title': 'Młody',
            'column': 'backlog',
            'actions': [
              {'id': 'start', 'enabled': true},
            ],
          },
      ];
    } on TimeoutException {
      // Stale, like the real cache when the server does not answer.
    }
    return cards;
  }

  final board = BoardClient(
    wait: const Duration(seconds: 2),
    poll: const Duration(milliseconds: 20),
    client: MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(req.url.path);
        return http.Response('{"ok":true}', 200);
      }
      if (req.url.path == '/api/board') {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'tasks': await refresh()})),
          200,
        );
      }
      return http.Response('<meta name="todoimpl-csrf" content="t">', 200);
    }),
  );

  setUp(() async {
    note = null;
    cards = [];
    posts.clear();
    h = McpHarness(board: board);
    await h.start();
    c = await h.connect();
    boardSide = await h.connect();
  });
  tearDown(() => h.dispose());

  test('T1865: Start after a merge sees the board refreshed', () async {
    final args = {
      'repo': 'kuhyx/herosi',
      'title': 'Młody',
      'body': 'what',
      'new_note': true,
      'done_check': 'true',
    };
    note = idIn(await h.call(c, 'add_task', args));
    final r = await h.call(c, 'add_task', args);
    expect(r, startsWith('merged into $note'));
    expect(r, contains('start: ok ${note!.substring(0, 8)}-1'));
    expect(posts, ['/api/task/${note!.substring(0, 8)}-1/start']);
  });

  test('a merge with no board configured says click Start', () async {
    final bare = McpHarness();
    await bare.start();
    addTearDown(bare.dispose);
    final client = await bare.connect();
    final args = {'repo': 'kuhyx/herosi', 'title': 'A', 'new_note': true};
    final x = idIn(await bare.call(client, 'add_task', args));
    final r = await bare.call(client, 'add_task', {
      ...args,
      'done_check': 'true',
    });
    expect(r, startsWith('merged into $x'));
    expect(r, contains('reason: "no board configured"'));
    expect(r, contains('click Start on the board by hand'));
  });
}
