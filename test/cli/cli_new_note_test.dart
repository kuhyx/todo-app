// `--repo --new-note`: the task gets its own note; an exact title in another
// separate note merges into it. The CLI never talks to the board. ASCII
// titles: FakeRtdb encodes its responses as Latin-1.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_args.dart';

import 'cli_harness.dart';

void main() {
  late CliHarness h;
  setUp(() => h = CliHarness());
  tearDown(() => h.dispose());

  Future<String> add(String text, [List<String> more = const []]) =>
      h.add(text, ['--repo', 'kuhyx/herosi', ...more]);

  test('C1: --new-note opens a second note; a duplicate merges', () async {
    final shared = await add('Old\n\nx');
    final split = await add('Mlody\n\nwhat', ['--new-note']);
    expect(split, isNot(shared));
    final again = await add('Mlody\n\nmore', ['--new-note']);
    expect(again, split);
    expect(h.err.toString(), contains('merged into'));
    expect(h.err.toString(), contains('click Start on the board by hand'));
    expect(await h.run(['--list', '--repo', 'kuhyx/herosi']), 0);
    expect(h.out.toString().trim().split('\n'), hasLength(2));
    expect(await h.run(['--get', split]), 0);
    expect(h.out.toString(), contains('herosi todos: Mlody'));
  });

  test('--new-note needs --repo and an add', () {
    expect(() => CliArgs.parse(['--new-note']), throwsA(isA<UsageError>()));
    expect(
      () => CliArgs.parse(['--list', '--repo', 'a/b', '--new-note']),
      throwsA(isA<UsageError>()),
    );
    expect(CliArgs.parse(['--repo', 'a/b', '--new-note']).newNote, isTrue);
    expect(CliArgs.parse(['--repo', 'a/b']).newNote, isFalse);
  });
}
