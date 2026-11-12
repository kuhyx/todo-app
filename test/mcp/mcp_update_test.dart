import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_harness.dart';

void main() {
  late McpHarness h;
  late McpClient c;
  late String id;

  setUp(() async {
    h = McpHarness();
    await h.start();
    c = await h.connect();
    id = idIn(
      await h.call(c, 'add_task', {
        'repo': 'kuhyx/todo',
        'title': 'Old title',
        'body': 'old body',
      }),
    );
  });
  tearDown(() => h.dispose());

  test('title, body, priority and repo change independently', () async {
    await h.call(c, 'update_task', {'id': id, 'title': 'New title'});
    var got = await h.call(c, 'get_task', {'id': id});
    expect(got, endsWith('---\nNew title\n\n## Old title\nold body'));

    await h.call(c, 'update_task', {
      'id': id,
      'body': '',
      'priority': 'low',
      'repo': 'kuhyx/utils',
    });
    got = await h.call(c, 'get_task', {'id': id});
    expect(got, endsWith('---\nNew title'));
    expect(got, contains('priority: low'));
    expect(got, contains('repo: kuhyx/utils'));
  });

  test('done only via close; reopening drops the evidence', () async {
    expect(
      await h.refused(c, 'update_task', {'id': id, 'status': 'done'}),
      startsWith('error: status:'),
    );
    expect(
      await h.refused(c, 'update_task', {'id': id, 'title': ' '}),
      startsWith('error: title:'),
    );
    await h.call(c, 'close_task', {'id': id, 'evidence': 'abc exit 0'});
    expect(
      await h.call(c, 'list_tasks', {'status': 'all'}),
      contains('\tdone\t'),
    );
    expect(await h.call(c, 'list_tasks', {}), 'no tasks match');
    await h.call(c, 'update_task', {'id': id, 'status': 'in_progress'});
    final got = await h.call(c, 'get_task', {'id': id});
    expect(got, contains('status: in_progress'));
    expect(got, isNot(contains('evidence')));
  });

  test('an unmergeable peer log is reported, not hidden', () async {
    h.db.files['todo-sync/notes-e2e/broken~2Ejson'] = 'not a log';
    expect(await h.refused(c, 'list_tasks', {}), contains('unmergeable'));
  });
}
