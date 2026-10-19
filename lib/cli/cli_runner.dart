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
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:uuid/uuid.dart';

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
    final cli = _Cli(session, out, err);
    return switch (args.mode) {
      CliMode.add => await cli.add(args, text!),
      CliMode.list => await cli.list(),
      CliMode.get => await cli.get(args.id!),
      CliMode.setStatus => await cli.setStatus(args.id!, args.status),
      // Only delete is left: help returned above.
      _ => await cli.delete(args.id!),
    };
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

class _Cli {
  _Cli(this.session, this.out, this.err);

  final CliSession session;
  final StringSink out;
  final StringSink err;

  Future<int> add(CliArgs args, String text) async {
    final now = DateTime.now();
    final note = Note(
      id: const Uuid().v4(),
      text: text,
      priority: args.priority,
      status: args.status,
      createdAt: now,
      updatedAt: now,
    );
    await session.repository.upsert(note);
    final result = _report(await session.sync(push: true));
    if (!result.pushed) {
      err.writeln('error: note saved locally but nothing was pushed');
      return 1;
    }
    out.writeln(note.id);
    return 0;
  }

  Future<int> list() async {
    _report(await session.sync(push: false));
    for (final note in await session.repository.listNotes()) {
      out.writeln(
        [
          note.id,
          note.priority.name,
          CliArgs.statusName(note.status),
          note.text.split('\n').first,
        ].join('\t'),
      );
    }
    return 0;
  }

  Future<int> get(String id) async {
    _report(await session.sync(push: false));
    final note = await _find(id);
    if (note == null) {
      err.writeln('error: no live note with id $id');
      return 1;
    }
    out
      ..writeln('id: ${note.id}')
      ..writeln('priority: ${note.priority.name}')
      ..writeln('status: ${CliArgs.statusName(note.status)}')
      ..writeln('created: ${note.createdAt.toIso8601String()}')
      ..writeln('updated: ${note.updatedAt.toIso8601String()}')
      ..writeln('---')
      ..writeln(note.text);
    return 0;
  }

  Future<int> delete(String id) async {
    // Pull first: the note may have been created on another device, and a
    // tombstone for an id this node has never seen would only be noise.
    _report(await session.sync(push: true));
    if (await _find(id) == null) {
      err.writeln('error: no live note with id $id');
      return 1;
    }
    await session.repository.delete(id);
    if (!_report(await session.sync(push: true)).pushed) {
      err.writeln('error: deletion saved locally but nothing was pushed');
      return 1;
    }
    out.writeln('deleted $id');
    return 0;
  }

  Future<int> setStatus(String id, Status status) async {
    // Pull first, as in [delete]: the note usually lives on another device.
    _report(await session.sync(push: true));
    final note = await _find(id);
    if (note == null) {
      err.writeln('error: no live note with id $id');
      return 1;
    }
    await session.repository.upsert(
      note.copyWith(status: status, updatedAt: DateTime.now()),
    );
    if (!_report(await session.sync(push: true)).pushed) {
      err.writeln('error: status change saved locally but nothing was pushed');
      return 1;
    }
    out.writeln('$id\t${CliArgs.statusName(status)}');
    return 0;
  }

  Future<Note?> _find(String id) async {
    final notes = await session.repository.listNotes();
    return notes.where((n) => n.id == id).firstOrNull;
  }

  /// Surfaces peers that could not be merged instead of dropping them
  /// silently.
  SyncResult _report(SyncResult result) {
    for (final name in result.skippedFiles) {
      err.writeln('warning: could not merge peer file $name');
    }
    return result;
  }
}
