// Headless note CLI: add, list, search, get, close or delete notes from the PC.
//
//   dart run bin/todo_note.dart --text "Title" --repo kuhyx/todo --by claude
//   dart run bin/todo_note.dart --list --repo kuhyx/todo
//   dart run bin/todo_note.dart --close <id> --evidence "<sha> exit 0"
//
// See `kUsage` in lib/cli/cli_args.dart for every flag. All behaviour lives
// in lib/cli/cli_runner.dart, where the tests reach it.
import 'dart:io';

import 'package:todo/cli/cli_runner.dart';

Future<void> main(List<String> argv) async {
  exitCode = await runCli(
    argv,
    env: Platform.environment,
    out: stdout,
    err: stderr,
    readStdin: () => readInput(stdin, hasTerminal: stdin.hasTerminal),
  );
}
