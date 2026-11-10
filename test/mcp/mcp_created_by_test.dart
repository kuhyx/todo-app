// add_task stamps created_by claude; every read tool reports it.
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

  test('add_task is stamped claude and list/get/search show it', () async {
    final added = await h.call(c, 'add_task', {
      'repo': 'kuhyx/todo',
      'title': 'Fix gate',
    });
    final id = idIn(added);
    final stored = (await h.session.repository.listNotes()).single;
    expect(stored.createdBy, 'claude');

    expect(
      await h.call(c, 'get_task', {'id': id}),
      contains('created_by: claude'),
    );
    for (final listed in [
      await h.call(c, 'list_tasks', {}),
      await h.call(c, 'search_tasks', {'query': 'gate'}),
    ]) {
      expect(listed.trim(), endsWith('\tclaude'));
    }
  });

  test('a separate new_note task is stamped claude too', () async {
    await h.call(c, 'add_task', {
      'repo': 'kuhyx/todo',
      'title': 'Own note',
      'new_note': true,
    });
    expect((await h.session.repository.listNotes()).single.createdBy, 'claude');
  });

  test('a record without created_by reads as kuhy', () async {
    final at = DateTime.utc(2026, 11);
    await h.session.repository.upsert(
      Note(
        id: 'human-task-0001',
        text: 'Human task',
        priority: Priority.medium,
        status: Status.todo,
        createdAt: at,
        updatedAt: at,
        repo: 'kuhyx/todo',
      ),
    );
    expect(
      await h.call(c, 'get_task', {'id': 'human-task-0001'}),
      contains('created_by: kuhy'),
    );
    expect(
      (await h.call(c, 'list_tasks', {})).trim(),
      endsWith('Human task\tkuhy'),
    );
  });

  test('joining a human-made repo note keeps its author', () async {
    final at = DateTime.utc(2026, 11);
    await h.session.repository.upsert(
      Note(
        id: 'human-task-0001',
        text: 'todo todos',
        priority: Priority.medium,
        status: Status.todo,
        createdAt: at,
        updatedAt: at,
        repo: 'kuhyx/todo',
        createdBy: 'kuhy',
      ),
    );
    await h.call(c, 'add_task', {'repo': 'kuhyx/todo', 'title': 'More'});
    expect((await h.session.repository.listNotes()).single.createdBy, 'kuhy');
  });
}
