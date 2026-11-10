// --set-text: replace a note's whole text, keeping every other field.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_mode.dart';
import 'package:todo/cli/cli_session.dart';

import 'cli_harness.dart';
import 'scripted_session.dart';

void main() {
  late CliHarness h;
  setUp(() => h = CliHarness());
  tearDown(() => h.dispose());

  test('--set-text replaces the text and keeps repo and status', () async {
    final id = await h.add('Old title\nold body', ['--repo', 'kuhyx/todo']);
    expect(await h.run(['--set-status', id, 'in_progress']), 0);
    expect(
      await h.run([
        '--set-text',
        id.substring(0, 8),
        '--text',
        'New title\nnew body',
        '--data-dir',
        h.dir('a'),
      ]),
      0,
    );
    expect(h.out.toString().trim(), '$id\ttext');
    expect(await h.run(['--get', id, '--data-dir', h.dir('b')]), 0);
    expect(
      h.out.toString(),
      allOf(
        contains('New title\nnew body'),
        isNot(contains('old body')),
        contains('repo: kuhyx/todo'),
        contains('in_progress'),
      ),
    );
  });

  test('--set-text reads stdin when --text is absent', () async {
    final id = await h.add('Old');
    expect(await h.run(['--set-text', id], stdin: 'From stdin'), 0);
    expect(await h.run(['--get', id, '--data-dir', h.dir('b')]), 0);
    expect(h.out.toString(), contains('From stdin'));
  });

  test('--set-text refuses empty text and changes nothing', () async {
    final id = await h.add('Keep me');
    expect(await h.run(['--set-text', id, '--text', '  ']), 2);
    expect(h.err.toString(), contains('empty note'));
    expect(await h.run(['--get', id]), 0);
    expect(h.out.toString(), contains('Keep me'));
  });

  test('--set-text on a missing id exits 1', () async {
    expect(await h.run(['--set-text', 'ffffffff', '--text', 'x']), 1);
    expect(h.err.toString(), contains('no live note with id ffffffff'));
  });

  test('--set-text fails when the push reports nothing published', () async {
    Future<CliSession> opener(String d, {required String seedCredentials}) =>
        ScriptedSession.create(h.db.client, [true, false], noteId: 'stuck');
    expect(
      await h.run(['--set-text', 'stuck', '--text', 'x'], opener: opener),
      1,
    );
    expect(h.err.toString(), contains('text change saved locally'));
  });

  test('parse: --set-text takes an id and allows --text', () {
    final args = CliArgs.parse(['--set-text', 'abc', '--text', 'T']);
    expect(args.mode, CliMode.setText);
    expect(args.id, 'abc');
    expect(args.text, 'T');
    expect(() => CliArgs.parse(['--set-text']), throwsA(isA<UsageError>()));
    expect(
      () => CliArgs.parse(['--set-text', 'a', '--repo', 'kuhyx/todo']),
      throwsA(isA<UsageError>()),
    );
  });
}
