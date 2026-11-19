// list_tasks `no_repo: true` lists the open notes that have no repo (ideas),
// which the board shows in its Yours lane; without it they stay invisible.
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/data/note.dart';

import 'mcp_harness.dart';

void main() {
  late McpHarness h;
  late McpClient c;
  setUp(() async {
    h = McpHarness();
    await h.start();
    c = await h.connect();
  });
  tearDown(() => h.dispose());

  Future<void> idea(String id, String text, Status status) async {
    final now = DateTime.now();
    await h.session.repository.upsert(
      Note(
        id: id,
        text: text,
        status: status,
        priority: Priority.medium,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('no_repo lists only open repo-less notes', () async {
    await idea('11111111-aaaa', 'open idea', Status.todo);
    await idea('22222222-aaaa', 'finished idea', Status.done);
    await h.call(c, 'add_task', {'repo': 'kuhyx/x', 'title': 'repo task'});

    final plain = await h.call(c, 'list_tasks', {});
    expect(plain, isNot(contains('open idea')));
    final ideas = await h.call(c, 'list_tasks', {'no_repo': true});
    expect(ideas.trim().split('\n'), hasLength(1));
    expect(ideas, allOf(contains('11111111'), contains('open idea')));
    expect(ideas, isNot(contains('repo task')));
  });

  test('no_repo with nothing to list says so', () async {
    expect(await h.call(c, 'list_tasks', {'no_repo': true}), 'no tasks match');
  });

  test('no_repo is named in the tool text', () async {
    final tools = (await c.listTools()).tools;
    final list = tools.singleWhere((t) => t.name == 'list_tasks');
    expect(list.description, contains('no_repo'));
  });
}
