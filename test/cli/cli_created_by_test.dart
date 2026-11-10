// created_by through the CLI: stamping, output, and the backfill command.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'cli_harness.dart';

void main() {
  late CliHarness h;
  setUp(() => h = CliHarness());
  tearDown(() => h.dispose());

  test('a CLI add is stamped claude, repo task or idea', () async {
    final idea = await h.add('Plain idea');
    final task = await h.add('Fix gate', ['--repo', 'kuhyx/todo']);
    for (final id in [idea, task]) {
      expect(await h.run(['--get', id, '--data-dir', h.dir('b')]), 0);
      expect(h.out.toString(), contains('created_by: claude'));
    }
    expect(await h.run(['--list']), 0);
    expect(
      h.out.toString().trim().split('\n'),
      everyElement(endsWith('\tclaude')),
    );
  });

  test('a --new-note add is stamped claude', () async {
    final id = await h.add('Own note', ['--repo', 'kuhyx/todo', '--new-note']);
    expect(await h.run(['--get', id, '--data-dir', h.dir('b')]), 0);
    expect(h.out.toString(), contains('created_by: claude'));
  });

  test('a peer note without created_by reads as kuhy', () async {
    h.seedPeer([fixtureNote('peer-note-1', 'From the phone')]);
    expect(await h.run(['--get', 'peer-note-1']), 0);
    expect(h.out.toString(), contains('created_by: kuhy'));
    expect(await h.run(['--list']), 0);
    expect(h.out.toString(), endsWith('From the phone\tkuhy\n'));
  });

  group('--backfill-created-by', () {
    void seed() {
      final mcp = Directory('${h.env['XDG_DATA_HOME']}/todo-mcp')
        ..createSync(recursive: true);
      File('${mcp.path}/node_id').writeAsStringSync('mcp-node\n');
      h.seedPeer([
        fixtureNote('mcp-note-0001', 'Make a text-free', repo: 'kuhyx/a'),
      ], node: 'mcp-node');
      h.seedPeer([fixtureNote('idea-note-0001', 'My idea')], node: 'phone');
    }

    test('--dry-run lists the plan and writes nothing', () async {
      seed();
      expect(await h.run(['--backfill-created-by', '--dry-run']), 0);
      final lines = h.out.toString().trim().split('\n');
      expect(lines, contains('mcp-note\tclaude\tMake a text-free'));
      expect(lines, contains('idea-not\tkuhy\tMy idea'));
      expect(lines.last, 'dry run: claude 1, kuhy 1');
      expect(h.db.methods, isNot(contains('PUT')), reason: 'nothing pushed');
    });

    test('a real run sets it once, pushes it, and is then a no-op', () async {
      seed();
      expect(await h.run(['--backfill-created-by']), 0);
      expect(h.out.toString().trim().split('\n').last, 'set: claude 1, kuhy 1');
      expect(
        await h.run(['--get', 'mcp-note-0001', '--data-dir', h.dir('b')]),
        0,
      );
      expect(h.out.toString(), contains('created_by: claude'));
      expect(
        await h.run(['--get', 'idea-note-0001', '--data-dir', h.dir('b')]),
        0,
      );
      expect(h.out.toString(), contains('created_by: kuhy'));
      expect(await h.run(['--backfill-created-by']), 0);
      expect(h.out.toString().trim(), 'set: claude 0, kuhy 0');
    });

    test('--dry-run is refused without the backfill flag', () async {
      expect(await h.run(['--dry-run']), 2);
      expect(h.err.toString(), contains('--dry-run only applies'));
    });
  });
}
