/// The temp web root, the served instance, and enabledOrigin.
///
/// Shared by the files `wrapper_server_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_server.dart';

/// One test's temp web root and the [WrapperServer] serving it.
///
/// A class rather than bare `setUp`/`late` globals because [enabledOrigin]
/// needs the temp root, and a top-level function cannot close over a `late`
/// that `setUp` assigns. [install] wires the lifecycle; each test file calls
/// it once at the top of its `main()`.
class WrapperHarness {
  /// Temp directory holding the web root, the state dir, and the configs.
  late Directory root;

  /// The server under test, listening on an OS-assigned port.
  late WrapperServer server;

  /// Origin of [server], e.g. `http://localhost:41234`.
  late String base;

  /// Registers the setUp/tearDown pair that owns this harness.
  void install() {
    setUp(() async {
      root = await Directory.systemTemp.createTemp('wrapper');
      final webRoot = Directory(p.join(root.path, 'web'))..createSync();
      File(
        p.join(webRoot.path, 'index.html'),
      ).writeAsStringSync('<h1>todo</h1>');
      File(p.join(webRoot.path, 'main.dart.js')).writeAsStringSync('console;');
      File(p.join(webRoot.path, 'canvaskit.wasm')).writeAsStringSync('binary');

      server = WrapperServer(
        webRoot: webRoot.path,
        backlogPath: p.join(root.path, 'todo', 'BACKLOG.md'),
        logPath: p.join(root.path, 'state', 'todo_notes.json'),
        // Without this, the default falls back to the real
        // $HOME/.config/todo/firebase_auth.json -- on a machine that has
        // actually signed in (a real desktop session), that file exists, so
        // the "no credentials file exists" test below observes 200 instead
        // of 404. Point it at this test's own throwaway root instead.
        todoCredentialsPath: p.join(
          root.path,
          'todo-config',
          'firebase_auth.json',
        ),
      );
      // Port 0 lets the OS pick, so tests never collide with a running app.
      await server.start(0);
      base = 'http://localhost:${server.port}';
    });

    tearDown(() async {
      await server.stop();
      root.deleteSync(recursive: true);
    });
  }

  Future<String> enabledOrigin(
    Map<String, String> files, {
    String? credentialsJson,
  }) async {
    final configDir = Directory(p.join(root.path, 'crdt-sync'))
      ..createSync(recursive: true);
    files.forEach((name, contents) {
      File(p.join(configDir.path, name)).writeAsStringSync(contents);
    });
    String? credentialsPath;
    if (credentialsJson != null) {
      final credentialsDir = Directory(p.join(root.path, 'todo-config'))
        ..createSync(recursive: true);
      credentialsPath = p.join(credentialsDir.path, 'firebase_auth.json');
      File(credentialsPath).writeAsStringSync(credentialsJson);
    }
    final enabled = WrapperServer(
      webRoot: p.join(root.path, 'web'),
      backlogPath: p.join(root.path, 'todo', 'BACKLOG.md'),
      logPath: p.join(root.path, 'state', 'todo_notes.json'),
      serveSyncAccount: true,
      syncConfigDir: configDir.path,
      todoCredentialsPath:
          credentialsPath ?? p.join(root.path, 'todo-config', 'absent.json'),
    );
    await enabled.start(0);
    addTearDown(enabled.stop);
    return 'http://localhost:${enabled.port}';
  }
}
