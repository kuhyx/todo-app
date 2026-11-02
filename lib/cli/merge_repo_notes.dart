/// `bin/merge_repo_notes.dart`: collapse each repo's open notes into one.
/// Dry run unless `--apply`; stdout is the `old_id<TAB>kept_id<TAB>repo` map.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:path/path.dart' as p;
import 'package:todo/cli/cli_runner.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/repo_note_merge.dart';

const _usage = 'usage: merge_repo_notes [--dry-run|--apply] [--data-dir D]';

/// Runs the merge for [argv]; returns the exit code.
Future<int> runMergeRepoNotes(
  List<String> argv, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  SessionOpener open = CliSession.open,
}) async {
  var apply = false;
  String? dataDir;
  for (var i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--apply':
        apply = true;
      case '--dry-run':
        apply = false;
      case '--data-dir' when i + 1 < argv.length:
        dataDir = argv[++i];
      default:
        err.writeln(_usage);
        return 2;
    }
  }
  CliSession? session;
  try {
    session = await open(
      dataDir ?? defaultDataDir(env),
      seedCredentials: p.join(
        env['HOME'] ?? '',
        '.config',
        'todo',
        'firebase_auth.json',
      ),
    );
    await session.sync(push: apply);
    final plan = planRepoMerges(await session.repository.listNotes());
    for (final (:kept, :removed) in plan) {
      if (apply) {
        await session.repository.upsert(
          kept.copyWith(updatedAt: DateTime.now()),
        );
        for (final n in removed) {
          await session.repository.delete(n.id);
        }
      }
      for (final n in removed) {
        out.writeln('${n.id}\t${kept.id}\t${kept.repo}');
      }
    }
    final deleted = plan.fold(0, (sum, m) => sum + m.removed.length);
    err.writeln(
      '${apply ? 'applied' : 'dry run'}: ${plan.length} repos, '
      '$deleted notes deleted',
    );
    if (apply && plan.isNotEmpty && !(await session.sync(push: true)).pushed) {
      err.writeln('error: saved locally but nothing was pushed');
      return 1;
    }
    return 0;
  } on RemoteSyncError catch (error) {
    err.writeln('error: $error');
    return 1;
  } finally {
    await session?.close();
  }
}
