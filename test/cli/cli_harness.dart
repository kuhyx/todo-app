/// Runs `runCli` against a [FakeRtdb] from a temp HOME. Not a `*_test.dart`.
library;

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_runner.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

import 'fake_rtdb.dart';

class CliHarness {
  CliHarness() {
    final home = Directory('${tmp.path}/home')..createSync();
    Directory('${home.path}/.config/todo').createSync(recursive: true);
    writeSeedCredentials(
      tmp,
    ).copySync('${home.path}/.config/todo/firebase_auth.json');
    env = {'HOME': home.path, 'XDG_DATA_HOME': '${tmp.path}/xdg'};
  }

  final tmp = Directory.systemTemp.createTempSync('cli_harness');
  final db = FakeRtdb();
  late final Map<String, String> env;
  final out = StringBuffer();
  final err = StringBuffer();

  void dispose() => tmp.deleteSync(recursive: true);

  String dir(String name) => '${tmp.path}/$name';

  Future<int> run(
    List<String> argv, {
    SessionOpener? opener,
    String stdin = '',
  }) async {
    out.clear();
    err.clear();
    return runCli(
      argv,
      env: env,
      out: out,
      err: err,
      readStdin: () async => stdin,
      open:
          opener ?? (d, {required seedCredentials}) => open(d, seedCredentials),
    );
  }

  /// A real session over the fake RTDB.
  Future<CliSession> open(String dataDir, String seedCredentials) =>
      CliSession.open(
        dataDir,
        seedCredentials: seedCredentials,
        httpClient: db.client,
      );

  /// Adds a note from node [node] and returns its id.
  Future<String> add(String text, [List<String> extra = const []]) async {
    expect(await run(['--data-dir', dir('a'), '--text', text, ...extra]), 0);
    return out.toString().trim();
  }

  /// Publishes [notes] as device [node]'s log.
  void seedPeer(List<Note> notes, {String node = 'peer'}) {
    db.files['todo-sync/notes/$node~2Ejson'] = logToJson({
      for (final n in notes) n.id: NoteRepository.recordAtNoteTime(n, node),
    });
  }
}

Note fixtureNote(String id, String text, {String? repo}) {
  final at = DateTime.utc(2026, 11);
  return Note(
    id: id,
    text: text,
    priority: Priority.medium,
    status: Status.todo,
    createdAt: at,
    updatedAt: at,
    repo: repo,
  );
}
