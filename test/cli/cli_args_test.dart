import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_args.dart';
import 'package:todo/data/note.dart';

void main() {
  group('CliArgs.parse', () {
    test('no arguments means add with defaults', () {
      final args = CliArgs.parse([]);
      expect(args.mode, CliMode.add);
      expect(args.text, isNull);
      expect(args.priority, Priority.medium);
      expect(args.status, Status.todo);
      expect(args.dataDir, isNull);
    });

    test('reads every add option', () {
      final args = CliArgs.parse([
        '--text',
        'Title',
        '--priority',
        'high',
        '--status',
        'in_progress',
        '--data-dir',
        '/tmp/x',
      ]);
      expect(args.mode, CliMode.add);
      expect(args.text, 'Title');
      expect(args.priority, Priority.high);
      expect(args.status, Status.inProgress);
      expect(args.dataDir, '/tmp/x');
    });

    test('accepts plain status names', () {
      expect(CliArgs.parse(['--status', 'done']).status, Status.done);
    });

    test('selects list, get and delete', () {
      expect(CliArgs.parse(['--list']).mode, CliMode.list);
      final get = CliArgs.parse(['--get', 'abc']);
      expect(get.mode, CliMode.get);
      expect(get.id, 'abc');
      final del = CliArgs.parse(['--delete', 'xyz']);
      expect(del.mode, CliMode.delete);
      expect(del.id, 'xyz');
    });

    test('selects set-status with its id and status', () {
      final set = CliArgs.parse(['--set-status', 'xyz', 'in_progress']);
      expect(set.mode, CliMode.setStatus);
      expect(set.id, 'xyz');
      expect(set.status, Status.inProgress);
    });

    test('help wins over everything else', () {
      expect(CliArgs.parse(['--list', '-h']).mode, CliMode.help);
      expect(CliArgs.parse(['--help']).mode, CliMode.help);
    });

    test('rejects malformed command lines', () {
      void expectUsage(List<String> argv, String fragment) {
        expect(
          () => CliArgs.parse(argv),
          throwsA(
            isA<UsageError>().having(
              (e) => e.toString(),
              'message',
              contains(fragment),
            ),
          ),
        );
      }

      expectUsage(['--text'], '--text needs a value');
      expectUsage(['--bogus'], 'unknown argument: --bogus');
      expectUsage(['--priority', 'urgent'], 'low|medium|high');
      expectUsage(['--status', 'inProgress'], 'todo|in_progress|done');
      expectUsage(['--list', '--get', 'a'], 'mutually exclusive');
      expectUsage(['--list', '--text', 'x'], 'only applies when adding');
      expectUsage(['--set-status', 'a'], '--set-status needs a value');
      expectUsage(['--set-status', 'a', 'finished'], 'todo|in_progress|done');
      expectUsage([
        '--list',
        '--set-status',
        'a',
        'done',
      ], 'mutually exclusive');
    });
  });

  test('statusName spells inProgress with an underscore', () {
    expect(CliArgs.statusName(Status.inProgress), 'in_progress');
    expect(CliArgs.statusName(Status.abandoned), 'abandoned');
  });
}
