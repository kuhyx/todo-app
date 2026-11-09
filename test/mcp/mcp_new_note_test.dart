// add_task new_note over MCP: second note, guard merge, Start on the board.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/mcp/board_client.dart';

import 'mcp_harness.dart';

const _repo = 'kuhyx/herosi';

void main() {
  late McpHarness h;
  late McpClient c;
  var cards = <Map<String, dynamic>>[];
  var up = true;
  final posts = <String>[];
  final board = BoardClient(
    client: MockClient((req) async {
      if (!up) throw http.ClientException('connection refused');
      if (req.method == 'POST') {
        posts.add(req.url.path);
        return http.Response('{"ok":true}', 200);
      }
      if (req.url.path == '/api/board') {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'tasks': cards})),
          200,
        );
      }
      return http.Response('<meta name="todoimpl-csrf" content="t">', 200);
    }),
  );
  List<Map<String, dynamic>> cardsOf(String id, String column) => [
    {
      'id': '${id.substring(0, 8)}-0',
      'title': 'Młody',
      'column': column,
      'actions': [
        {'id': 'start', 'enabled': true},
      ],
    },
  ];

  setUp(() async {
    cards = [];
    up = true;
    posts.clear();
    h = McpHarness(board: board);
    await h.start();
    c = await h.connect();
  });
  tearDown(() => h.dispose());

  Future<String> add(Map<String, dynamic> extra) => h.call(c, 'add_task', {
    'repo': _repo,
    'title': 'Młody',
    'body': 'what',
    'new_note': true,
    ...extra,
  });

  test('C1/C2: new_note opens a second note, a plain add does not', () async {
    final shared = idIn(
      await h.call(c, 'add_task', {'repo': _repo, 'title': 'Old'}),
    );
    final before = await h.call(c, 'get_task', {'id': shared});
    final second = await add({});
    expect(second, startsWith('added '));
    expect(idIn(second), isNot(shared));
    expect(await h.call(c, 'get_task', {'id': shared}), before);
    final listed = await h.call(c, 'list_tasks', {'repo': _repo});
    expect(listed.trim().split('\n'), hasLength(2));
    final plain = await h.call(c, 'add_task', {'repo': _repo, 'title': 'C'});
    expect(idIn(plain), shared);
    expect(posts, isEmpty);
  });

  test('C3/C6: a duplicate merges and Start is POSTed', () async {
    final x = idIn(await add({'done_check': 'true'}));
    cards = cardsOf(x, 'backlog');
    final r = await add({'done_check': 'true'});
    expect(r, startsWith('merged into $x'));
    expect(r, contains('start: ok ${x.substring(0, 8)}-0'));
    expect(posts, ['/api/task/${x.substring(0, 8)}-0/start']);
    final listed = await h.call(c, 'list_tasks', {'repo': _repo});
    expect(listed.trim().split('\n'), hasLength(1));
  });

  test('C6: done_check none or low priority merges without Start', () async {
    final x = idIn(await add({}));
    cards = cardsOf(x, 'backlog');
    final none = await add({});
    expect(none, startsWith('merged into $x'));
    expect(none, contains('start: skipped (done_check is none)'));
    final low = await add({'done_check': 'true', 'body': 'low priority\nx'});
    expect(low, contains('start: skipped (marked low priority)'));
    expect(posts, isEmpty);
  });

  test('C5: a running target is left alone', () async {
    final x = idIn(await add({'done_check': 'true'}));
    final before = await h.call(c, 'get_task', {'id': x});
    cards = cardsOf(x, 'running');
    final r = await add({'done_check': 'true'});
    expect(r, startsWith('added '));
    expect(idIn(r), isNot(x));
    expect(r, contains('not merged into ${x.substring(0, 8)}'));
    expect(await h.call(c, 'get_task', {'id': x}), before);
  });

  test('C7: board down keeps the merge and says click Start', () async {
    final x = idIn(await add({'done_check': 'true'}));
    up = false;
    final r = await add({'done_check': 'true'});
    expect(r, startsWith('merged into $x'));
    expect(r, contains('start: {ok: false, reason: "board unreachable'));
    expect(r, contains('click Start on the board by hand'));
  });

  test('the add_task schema offers new_note', () async {
    final tools = (await c.listTools()).tools;
    final add = tools.singleWhere((t) => t.name == 'add_task');
    expect(jsonEncode(add.inputSchema.toJson()), contains('new_note'));
  });
}
