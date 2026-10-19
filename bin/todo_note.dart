// Headless note CLI: add, list, get, re-status or delete a todo note from the PC.
//
//   dart run bin/todo_note.dart --text "Title\n\nbody" --priority high
//   echo "Title" | dart run bin/todo_note.dart
//   dart run bin/todo_note.dart --get <id>
//   dart run bin/todo_note.dart --set-status <id> done
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
