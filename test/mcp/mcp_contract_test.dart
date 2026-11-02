// Spec B / Q6 contract: over real Streamable HTTP, add -> list -> update
// (explicit clear of done_check) -> close with evidence, refused without;
// the result is visible to `todo_note.dart --list --repo` after a sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/cli/cli_runner.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/sync/notes_markdown.dart';

import '../cli/fake_rtdb.dart';
import 'mcp_harness.dart';

const _repo = 'kuhyx/todo';

void main() {
  late McpHarness h;
  late McpClient c;

  setUp(() async {
    h = McpHarness();
    await h.start();
    c = await h.connect();
  });
  tearDown(() => h.dispose());

  Future<String> addTask() async => idIn(
    await h.call(c, 'add_task', {
      'repo': _repo,
      'title': 'Fix the "quoted" thing',
      'body': 'what: details',
      'done_check': 'grep -q "ok" f',
      'priority': 'high',
    }),
  );

  test('add, list, update clearing done_check, close with evidence', () async {
    final id = await addTask();
    final prefix = id.substring(0, 8);

    final listed = await h.call(c, 'list_tasks', {'repo': _repo});
    expect(listed, contains(prefix));
    expect(listed, contains('Fix the "quoted" thing'));
    expect(listed, isNot(contains('&quot;')));

    var got = await h.call(c, 'get_task', {'id': prefix});
    expect(got, contains('done_check: grep -q "ok" f'));
    expect(got, contains('by: claude'));

    await h.call(c, 'update_task', {'id': prefix, 'done_check': ''});
    got = await h.call(c, 'get_task', {'id': prefix});
    expect(got, isNot(contains('done_check')));

    for (final args in [
      {'id': prefix},
      {'id': prefix, 'evidence': '  '},
    ]) {
      expect(await h.refused(c, 'close_task', args), contains('evidence'));
    }
    await h.call(c, 'close_task', {
      'id': prefix,
      'evidence': 'abc1234 "done_check" exit 0',
    });
    got = await h.call(c, 'get_task', {'id': id});
    expect(got, contains('status: done'));
    expect(got, contains('evidence: abc1234 "done_check" exit 0'));

    // Another node (the CLI) sees the closed task, done_check cleared.
    final out = StringBuffer();
    final code = await runCli(
      ['--list', '--repo', _repo, '--data-dir', '${h.tmp.path}/cli'],
      env: {'HOME': h.tmp.path},
      out: out,
      err: StringBuffer(),
      readStdin: () async => '',
      open: (d, {required seedCredentials}) => CliSession.open(
        d,
        seedCredentials: writeSeedCredentials(h.tmp).path,
        httpClient: h.db.client,
      ),
    );
    expect(code, 0);
    expect(out.toString(), contains('$prefix\tdone\thigh\t$_repo'));

    // BACKLOG.md escapes `"` as &quot;; parsing decodes it back.
    final notes = await h.session.repository.listNotes();
    final md = NotesMarkdown.export(notes);
    expect(md, contains('&quot;'));
    final back = NotesMarkdown.parse(md).single;
    expect(back.evidence, 'abc1234 "done_check" exit 0');
    expect(back.doneCheck, isNull);
  });

  test('errors name the field to fix', () async {
    final id = await addTask();
    expect(
      await h.refused(c, 'update_task', {'id': id, 'priority': 'urgent'}),
      contains('priority'),
    );
    expect(
      await h.refused(c, 'add_task', {'repo': 'no-slash', 'title': 't'}),
      contains('repo'),
    );
    expect(
      await h.refused(c, 'add_task', {'repo': _repo, 'title': ' '}),
      contains('title'),
    );
    expect(await h.refused(c, 'get_task', {'id': 'abc'}), contains('id'));
    expect(
      await h.refused(c, 'list_tasks', {'status': 'finished'}),
      contains('status'),
    );
  });

  test('search finds tasks by text; instructions say when to use', () async {
    final id = await addTask();
    expect(
      await h.call(c, 'search_tasks', {'query': 'QUOTED'}),
      contains(id.substring(0, 8)),
    );
    final how = c.getInstructions()!;
    for (final tool in ['add_task', 'list_tasks', 'close_task']) {
      expect(how, contains(tool));
    }
  });
}
