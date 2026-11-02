// One-time: one open note per repo, holding all of that repo's todos.
//
//   dart run bin/merge_repo_notes.dart            # dry run, prints the map
//   dart run bin/merge_repo_notes.dart --apply    # does it and pushes
import 'dart:io';

import 'package:todo/cli/merge_repo_notes.dart';

Future<void> main(List<String> argv) async {
  exitCode = await runMergeRepoNotes(
    argv,
    env: Platform.environment,
    out: stdout,
    err: stderr,
  );
}
