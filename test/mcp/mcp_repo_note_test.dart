// add_task keeps ONE open note per repo: the second call appends.
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_harness.dart';

const _repo = 'kuhyx/home-guard';

void main() {
  late McpHarness h;
  late McpClient c;
  setUp(() async {
    h = McpHarness();
    await h.start();
    c = await h.connect();
  });
  tearDown(() => h.dispose());

  test('the second add_task appends and returns the same id', () async {
    final first = await h.call(c, 'add_task', {
      'repo': _repo,
      'title': 'Fix A',
      'body': 'what: a',
      'done_check': 'ca',
      'priority': 'low',
    });
    final second = await h.call(c, 'add_task', {
      'repo': _repo,
      'title': 'Fix B',
      'body': 'what: b',
      'done_check': 'cb',
      'priority': 'high',
    });
    expect(first, startsWith('added '));
    expect(second, startsWith('appended to '));
    expect(idIn(second), idIn(first));

    final got = await h.call(c, 'get_task', {'id': idIn(first)});
    expect(
      got,
      allOf(
        contains('home-guard todos'),
        contains('## Fix A\nwhat: a'),
        contains('## Fix B\nwhat: b'),
        contains('done_check: ( ca ) && ( cb )'),
        contains('priority: high'),
      ),
    );
    final listed = await h.call(c, 'list_tasks', {'repo': _repo});
    expect(listed.trim().split('\n'), hasLength(1));
  });

  test('after the note is closed, the next add starts a new one', () async {
    final first = idIn(
      await h.call(c, 'add_task', {'repo': _repo, 'title': 'Fix A'}),
    );
    await h.call(c, 'close_task', {'id': first, 'evidence': 'smoke test'});
    final next = await h.call(c, 'add_task', {'repo': _repo, 'title': 'B'});
    expect(next, startsWith('added '));
    expect(idIn(next), isNot(first));
  });

  test('the tool text tells agents about the single note', () async {
    final tools = (await c.listTools()).tools;
    final add = tools.singleWhere((t) => t.name == 'add_task');
    expect(add.description, contains('appended'));
  });
}
