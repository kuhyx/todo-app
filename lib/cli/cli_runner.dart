/// The body of `bin/todo_note.dart`, with every side effect injected.
///
/// Lives in `lib/` so the tests can drive it with a fake RTDB, a temp data
/// dir and in-memory output sinks; the `bin/` entrypoint only wires the real
/// process streams and environment into [runCli].
library;

import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:path/path.dart' as p;
import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_commands.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/note_lookup.dart';

/// Opens a [CliSession]; swapped in tests to point it at a fake backend.
typedef SessionOpener =
    Future<CliSession> Function(
      String dataDir, {
      required String seedCredentials,
    });

/// Reads all of [input] as text, or '' when it is an interactive terminal.
Future<String> readInput(
  Stream<List<int>> input, {
  required bool hasTerminal,
}) async {
  if (hasTerminal) return '';
  return (await input.transform(utf8.decoder).join()).trimRight();
}

/// Runs the CLI for [argv] and returns its exit code.
Future<int> runCli(
  List<String> argv, {
  required Map<String, String> env,
  required StringSink out,
  required StringSink err,
  required Future<String> Function() readStdin,
  SessionOpener open = CliSession.open,
}) async {
  final CliArgs args;
  try {
    args = CliArgs.parse(argv);
  } on UsageError catch (error) {
    err
      ..writeln('error: $error')
      ..writeln(kUsage);
    return 2;
  }
  if (args.mode == CliMode.help) {
    out.writeln(kUsage);
    return 0;
  }
  String? text;
  if (args.mode == CliMode.add) {
    text = args.text ?? await readStdin();
    if (text.trim().isEmpty) {
      err.writeln('error: empty note (pass --text or pipe text on stdin)');
      return 2;
    }
  }

  CliSession? session;
  try {
    session = await open(
      args.dataDir ?? defaultDataDir(env),
      seedCredentials: p.join(
        env['HOME'] ?? '',
        '.config',
        'todo',
        'firebase_auth.json',
      ),
    );
    final cli = CliCommands(session, out, err);
    return switch (args.mode) {
      CliMode.add => await cli.add(args, text!),
      CliMode.list || CliMode.search => await cli.list(args),
      CliMode.get => await cli.get(args.id!),
      CliMode.setStatus => await cli.setStatus(args.id!, args.status!),
      CliMode.close => await cli.close(args.id!, args.opts.evidence!),
      // Only delete is left: help returned above.
      _ => await cli.delete(args.id!),
    };
  } on NoteLookupError catch (error) {
    err.writeln('error: $error');
    return 1;
  } on RemoteSyncError catch (error) {
    err.writeln('error: $error');
    return 1;
  } on IOException catch (error) {
    err.writeln('error: $error');
    return 1;
  } finally {
    await session?.close();
  }
}
