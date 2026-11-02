import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_args.dart';
import 'package:todo/data/note.dart';

void expectUsage(List<String> argv, String fragment) {
  expect(
    () => CliArgs.parse(argv),
    throwsA(
      isA<UsageError>().having((e) => e.message, 'message', contains(fragment)),
    ),
  );
}

void main() {
  test('add reads the task fields', () {
    final args = CliArgs.parse([
      '--repo',
      'kuhyx/todo',
      '--done-check',
      'flutter test',
      '--by',
      'claude',
    ]);
    expect(args.mode, CliMode.add);
    expect(args.opts.repo, 'kuhyx/todo');
    expect(args.opts.doneCheck, 'flutter test');
    expect(args.opts.by, 'claude');
    expect(args.status, isNull);
  });

  test('list and search take --repo and --status as filters', () {
    final list = CliArgs.parse(['--list', '--repo', 'kuhyx/a.b-c_d']);
    expect(list.mode, CliMode.list);
    expect(list.opts.repo, 'kuhyx/a.b-c_d');
    expect(list.status, isNull);
    final search = CliArgs.parse(['--search', 'gate', '--status', 'done']);
    expect(search.mode, CliMode.search);
    expect(search.opts.query, 'gate');
    expect(search.status, Status.done);
  });

  test('close takes an id and evidence', () {
    final args = CliArgs.parse(['--close', 'abcdefgh', '--evidence', 'x 0']);
    expect(args.mode, CliMode.close);
    expect(args.id, 'abcdefgh');
    expect(args.opts.evidence, 'x 0');
  });

  test('close is refused without evidence', () {
    expectUsage(['--close', 'abcdefgh'], '--close needs --evidence');
    expectUsage(['--close', 'a', '--evidence', '  '], '--close needs');
  });

  test('task flags are refused outside their modes', () {
    expectUsage(['--evidence', 'e'], '--evidence only applies to --close');
    expectUsage(['--list', '--by', 'kuhy'], '--by only applies when adding');
    expectUsage(['--list', '--done-check', 'x'], 'only applies when adding');
    expectUsage(['--get', 'a', '--repo', 'kuhyx/x'], '--repo only applies');
    expectUsage(['--list', '--close', 'a'], 'mutually exclusive');
    expectUsage(['--search', 'q', '--list'], 'mutually exclusive');
  });

  test('values are validated', () {
    expectUsage(['--by', 'bob'], '--by must be one of claude|kuhy');
    expectUsage(['--repo', 'todo'], '--repo must look like owner/name');
    expectUsage(['--repo', 'kuhyx/to do'], 'owner/name');
    expectUsage(['--done-check', ' '], '--done-check must not be empty');
    expectUsage(['--search', ''], '--search must not be empty');
  });
}
