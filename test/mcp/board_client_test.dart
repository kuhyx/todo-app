// BoardClient: scrape the CSRF meta, find the startable item by title,
// POST start; every failure is a reason, never an exception.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/mcp/board_client.dart';

const _id = 'cccccccc-1111-2222-3333-444444444444';

Map<String, dynamic> _card(
  String id,
  String title, {
  String column = 'backlog',
  bool start = true,
}) => {
  'id': id,
  'title': title,
  'column': column,
  'actions': [
    {'id': 'start', 'enabled': start},
  ],
};

class _Board {
  _Board(this.cards);
  final List<Map<String, dynamic>> cards;
  final posts = <http.Request>[];
  int startStatus = 200;
  int boardStatus = 200;
  String startBody = '{"ok":false,"error":{"message":"nope"}}';
  String page = '<meta name="todoimpl-csrf" content="tok-1">';

  /// Board reads so far; [onRead] may change [cards] between reads.
  int reads = 0;
  void Function(int read)? onRead;
  Duration postDelay = Duration.zero;

  BoardClient client({
    Duration wait = Duration.zero,
    Duration startTimeout = const Duration(seconds: 5),
  }) => BoardClient(
    wait: wait,
    poll: const Duration(milliseconds: 5),
    startTimeout: startTimeout,
    client: MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(req);
        await Future<void>.delayed(postDelay);
        return http.Response(startBody, startStatus);
      }
      if (req.url.path == '/api/board') {
        onRead?.call(++reads);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'tasks': cards})),
          boardStatus,
        );
      }
      return http.Response(page, 200);
    }),
  );
}

void main() {
  test('C6: starts the last startable item with that title', () async {
    final b = _Board([
      _card('cccccccc-0', 'Młody'),
      _card('cccccccc-1', 'Other'),
      _card('cccccccc-2', 'Młody'),
      _card('dddddddd-0', 'Młody'),
    ]);
    final r = await b.client().start(_id, 'Młody');
    expect(r, (ok: true, reason: null, item: 'cccccccc-2'));
    final post = b.posts.single;
    expect(
      post.url.toString(),
      'http://127.0.0.1:8786/api/task/cccccccc-2/start',
    );
    expect(post.headers['X-Todoimpl-Token'], 'tok-1');
    expect(post.headers['Origin'], 'http://127.0.0.1:8786');
    expect(post.body, isEmpty);
  });

  test(
    'C7: no startable item, refusal and missing token are reasons',
    () async {
      final b = _Board([_card('cccccccc-0', 'Młody', start: false)]);
      expect(
        (await b.client().start(_id, 'Młody')).reason,
        'no startable item',
      );
      final refused = _Board([_card('cccccccc-0', 'Młody')])..startStatus = 409;
      final r = await refused.client().start(_id, 'Młody');
      expect(r.ok, isFalse);
      expect(r.reason, 'board refused start: 409 nope');
      final blank = _Board([_card('cccccccc-0', 'Młody')])..page = '<html>';
      expect(
        (await blank.client().start(_id, 'Młody')).reason,
        'no CSRF token on the board page',
      );
    },
  );

  test('C7: a board that is down gives a reason, not a throw', () async {
    final down = BoardClient(
      client: MockClient((_) async => throw http.ClientException('refused')),
    );
    final r = await down.start(_id, 'Młody');
    expect(r.ok, isFalse);
    expect(r.reason, startsWith('board unreachable'));
    expect(await down.running(_id), isFalse);
  });

  test('C5: running is true only for a running item of that note', () async {
    final b = _Board([
      _card('cccccccc-0', 'A'),
      _card('dddddddd-0', 'A', column: 'running'),
    ]);
    expect(await b.client().running(_id), isFalse);
    b.cards.add(_card('cccccccc-1', 'B', column: 'running'));
    expect(await b.client().running(_id), isTrue);
  });

  test('a broken board and a non-JSON refusal are reasons too', () async {
    final b = _Board([_card('cccccccc-0', 'Młody')])..boardStatus = 500;
    expect(
      (await b.client().start(_id, 'Młody')).reason,
      allOf(startsWith('board unreachable'), contains('GET /api/board 500')),
    );
    final raw = _Board([_card('cccccccc-0', 'Młody')])
      ..startStatus = 502
      ..startBody = 'Bad Gateway';
    expect(
      (await raw.client().start(_id, 'Młody')).reason,
      'board refused start: 502 Bad Gateway',
    );
  });

  test('T1863: waits for the board to see a freshly merged section', () async {
    final b = _Board([_card('cccccccc-0', 'Młody')]);
    b.onRead = (n) {
      if (n == 3) b.cards.add(_card('cccccccc-1', 'Młody'));
    };
    final r = await b
        .client(wait: const Duration(seconds: 2))
        .start(_id, 'Młody', sections: 2);
    expect(r, (ok: true, reason: null, item: 'cccccccc-1'));
  });

  test('T1863: a board that never shows the section gives up', () async {
    final b = _Board([_card('cccccccc-0', 'Młody')]);
    final r = await b
        .client(wait: const Duration(milliseconds: 50))
        .start(_id, 'Młody', sections: 2);
    expect(r.ok, isFalse);
    expect(r.reason, 'no startable item');
    expect(b.posts, isEmpty);
  });

  test('T1866: starts the merged item, not a re-startable older one', () async {
    // The board lists by column: a cancelled older item may come last.
    final b = _Board([
      _card('cccccccc-0', 'Młody'),
      _card('cccccccc-2', 'Młody'),
      _card('cccccccc-1', 'Młody', column: 'done'),
    ]);
    final r = await b.client().start(_id, 'Młody', sections: 3);
    expect(r, (ok: true, reason: null, item: 'cccccccc-2'));
    final other = _Board([
      _card('cccccccc-1', 'Młody', column: 'done'),
      _card('cccccccc-0', 'Młody', start: false),
    ]);
    final none = await other.client().start(_id, 'Młody', sections: 1);
    expect(none.reason, 'no startable item');
    expect(other.posts, isEmpty);
  });

  test('T1864: a slow Start that took effect is ok, not unreachable', () async {
    final b = _Board([_card('cccccccc-0', 'Młody')])
      ..postDelay = const Duration(milliseconds: 200);
    b.onRead = (n) {
      // After the POST was sent the card has left backlog (no Start action).
      if (b.posts.isNotEmpty) {
        b.cards[0] = _card(
          'cccccccc-0',
          'Młody',
          column: 'running',
          start: false,
        );
      }
    };
    final r = await b
        .client(startTimeout: const Duration(milliseconds: 50))
        .start(_id, 'Młody');
    expect(r, (ok: true, reason: null, item: 'cccccccc-0'));
  });

  test(
    'T1864: a slow Start that did not take effect is still a reason',
    () async {
      final b = _Board([_card('cccccccc-0', 'Młody')])
        ..postDelay = const Duration(milliseconds: 200);
      final r = await b
          .client(startTimeout: const Duration(milliseconds: 50))
          .start(_id, 'Młody');
      expect(r.ok, isFalse);
      expect(r.reason, startsWith('board unreachable'));
    },
  );

  test('the default client targets the loopback board', () {
    expect(BoardClient().base.toString(), 'http://127.0.0.1:8786');
  });
}
