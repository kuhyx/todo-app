import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_server.dart';

void main() {
  late Directory root;
  late WrapperServer server;
  late String base;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wrapper');
    final webRoot = Directory(p.join(root.path, 'web'))..createSync();
    File(p.join(webRoot.path, 'index.html')).writeAsStringSync('<h1>todo</h1>');
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

  /// Starts a second server with provisioning enabled against [files], and
  /// optionally a `todo`-specific credentials file at [credentialsJson].
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

  test('serves index.html at the root', () async {
    final response = await http.get(Uri.parse('$base/'));
    expect(response.statusCode, 200);
    expect(response.body, contains('todo'));
  });

  test('serves nested assets and 404s unknown paths', () async {
    expect((await http.get(Uri.parse('$base/main.dart.js'))).statusCode, 200);
    expect((await http.get(Uri.parse('$base/nope.js'))).statusCode, 404);
  });

  test('refuses to serve outside the web root', () async {
    // The served directory sits beside the user's files, so traversal must not
    // be able to read them. Sent over a raw socket because http.get normalises
    // `..` away client-side, so the server would never see the attack.
    File(p.join(root.path, 'secret')).writeAsStringSync('do not serve me');

    // Percent-encoded, because both the http client and Dart's HttpServer
    // collapse a literal `..` before any handler sees it; `%2e%2e` survives
    // that and is decoded into the path afterwards.
    final socket = await Socket.connect('localhost', server.port);
    socket.write('GET /%2e%2e/secret HTTP/1.1\r\nHost: localhost\r\n\r\n');
    await socket.flush();
    final response = await utf8.decoder.bind(socket).first;
    await socket.close();

    // Dart's HttpServer decodes and then normalises, so traversal is already
    // collapsed before any handler runs and this comes back 404 rather than
    // 403. What matters is the property, not which code rejected it: the file
    // outside the web root is never served.
    expect(response, isNot(contains('do not serve me')));
    expect(response, anyOf(contains('403'), contains('404')));
  });

  test('a failing write reports a server error rather than crashing', () async {
    // Parent path is a regular file, so creating the directory for the backup
    // throws. The serve loop must survive it and keep answering requests.
    final blocked = Directory(p.join(root.path, 'blocked'))..createSync();
    File(p.join(blocked.path, 'wall')).writeAsStringSync('');
    final wedged = WrapperServer(
      webRoot: p.join(root.path, 'web'),
      backlogPath: p.join(blocked.path, 'wall', 'nested', 'BACKLOG.md'),
      logPath: p.join(root.path, 'state', 'todo_notes.json'),
    );
    await wedged.start(0);
    addTearDown(wedged.stop);

    final response = await http.post(
      Uri.parse('http://localhost:${wedged.port}/backup/backlog'),
      body: 'x',
    );
    expect(response.statusCode, 500);

    // Still alive afterwards.
    final after = await http.get(
      Uri.parse('http://localhost:${wedged.port}/'),
    );
    expect(after.statusCode, 200);
  });

  test('POST then GET round-trips the backlog', () async {
    final posted = await http.post(
      Uri.parse('$base/backup/backlog'),
      body: '# backlog\n\nnote one\n',
    );
    expect(posted.statusCode, 204);

    // Written to the real path, which is what the user's tooling reads.
    final onDisk = File(p.join(root.path, 'todo', 'BACKLOG.md'));
    expect(onDisk.existsSync(), isTrue);
    expect(onDisk.readAsStringSync(), contains('note one'));

    final fetched = await http.get(Uri.parse('$base/backup/backlog'));
    expect(fetched.statusCode, 200);
    expect(fetched.body, contains('note one'));
  });

  test('POST then GET round-trips the note log', () async {
    await http.post(Uri.parse('$base/backup/log'), body: '{"a":1}');
    final fetched = await http.get(Uri.parse('$base/backup/log'));
    expect(fetched.body, '{"a":1}');
  });

  test('GET on a backup that does not exist yet 404s', () async {
    expect((await http.get(Uri.parse('$base/backup/log'))).statusCode, 404);
  });

  test('rejects unsupported methods on a backup path', () async {
    final response = await http.delete(Uri.parse('$base/backup/log'));
    expect(response.statusCode, 405);
  });

  test('labels wasm and js correctly', () async {
    // CanvasKit refuses a .wasm served as anything else, and the app then
    // renders nothing at all.
    final wasm = await http.get(Uri.parse('$base/canvaskit.wasm'));
    expect(wasm.headers['content-type'], contains('application/wasm'));
    final js = await http.get(Uri.parse('$base/main.dart.js'));
    expect(js.headers['content-type'], contains('javascript'));
  });

  test('contentTypeFor covers the asset kinds the build emits', () {
    String kind(String name) => WrapperServer.contentTypeFor(name).mimeType;

    expect(kind('a.html'), 'text/html');
    expect(kind('a.json'), 'application/json');
    expect(kind('a.css'), 'text/css');
    expect(kind('a.png'), 'image/png');
    expect(kind('a.svg'), 'image/svg+xml');
    expect(kind('a.ttf'), 'font/ttf');
    expect(kind('a.otf'), 'font/otf');
    expect(kind('a.woff2'), 'font/woff2');
    expect(kind('a.mjs'), 'text/javascript');
    expect(kind('a.bin'), 'application/octet-stream');
    expect(kind('a.unknown'), 'application/octet-stream');
  });

  group('sync-account provisioning', () {
    test('is 404 when not enabled', () async {
      // The default, and the whole security posture: a credential route must
      // not be reachable just because the app is running.
      final response = await http.get(Uri.parse('$base$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('serves the account when enabled', () async {
      final origin = await enabledOrigin({
        'firebase.json': '{"email":"a@b.c"}',
        'password': 'pw\n',
      });

      final response = await http.get(Uri.parse('$origin$kSyncAccountPath'));
      final account = FirebaseAccount.tryParse(response.body);

      expect(response.statusCode, HttpStatus.ok);
      expect(account?.email, 'a@b.c');
      expect(account?.password, 'pw');
    });

    test('is 404 when the config files are absent', () async {
      final origin = await enabledOrigin({});

      final response = await http.get(Uri.parse('$origin$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('is 404 when firebase.json has no usable email', () async {
      final origin = await enabledOrigin({
        'firebase.json': '{"apiKey":"x"}',
        'password': 'pw',
      });

      final response = await http.get(Uri.parse('$origin$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('sync-credentials provisioning', () {
    // Unlike /sync-account, this route needs no CRDT_SYNC_SERVE_ACCOUNT: a
    // normal launch must self-provision with nothing to remember. [base]'s
    // server was built with no credentials file at the default path, so this
    // exercises the file-absent 404, not a disabled-route 404 -- there is no
    // "disabled" state for this route anymore.
    test(
      'is 404 when no credentials file exists at the default path',
      () async {
        final response = await http.get(
          Uri.parse('$base$kSyncCredentialsPath'),
        );

        expect(response.statusCode, HttpStatus.notFound);
      },
    );

    test('serves once, then 404s for the rest of the process', () async {
      final credentialsDir = Directory(p.join(root.path, 'todo-config-once'))
        ..createSync(recursive: true);
      final credentialsPath = p.join(credentialsDir.path, 'firebase_auth.json');
      File(credentialsPath).writeAsStringSync(
        jsonEncode({
          'id_token': 'id',
          'refresh_token': 'refresh',
          'expires_at': '2026-01-01T00:00:00.000Z',
        }),
      );
      final enabled = WrapperServer(
        webRoot: p.join(root.path, 'web'),
        backlogPath: p.join(root.path, 'todo', 'BACKLOG.md'),
        logPath: p.join(root.path, 'state', 'todo_notes.json'),
        todoCredentialsPath: credentialsPath,
      );
      await enabled.start(0);
      addTearDown(enabled.stop);
      final origin = 'http://localhost:${enabled.port}';

      final first = await http.get(Uri.parse('$origin$kSyncCredentialsPath'));
      final second = await http.get(Uri.parse('$origin$kSyncCredentialsPath'));

      expect(first.statusCode, HttpStatus.ok);
      expect(second.statusCode, HttpStatus.notFound);
    });

    test(
      'serves the seeded credentials, with email from firebase.json',
      () async {
        final configDir = Directory(p.join(root.path, 'crdt-sync'))
          ..createSync(recursive: true);
        File(
          p.join(configDir.path, 'firebase.json'),
        ).writeAsStringSync('{"email":"seeded@example.com"}');
        final credentialsDir = Directory(p.join(root.path, 'todo-config'))
          ..createSync(recursive: true);
        final credentialsPath = p.join(
          credentialsDir.path,
          'firebase_auth.json',
        );
        File(credentialsPath).writeAsStringSync(
          jsonEncode({
            'id_token': 'id',
            'refresh_token': 'refresh',
            'expires_at': '2026-01-01T00:00:00.000Z',
          }),
        );
        final enabled = WrapperServer(
          webRoot: p.join(root.path, 'web'),
          backlogPath: p.join(root.path, 'todo', 'BACKLOG.md'),
          logPath: p.join(root.path, 'state', 'todo_notes.json'),
          serveSyncAccount: true,
          syncConfigDir: configDir.path,
          todoCredentialsPath: credentialsPath,
        );
        await enabled.start(0);
        addTearDown(enabled.stop);

        final response = await http.get(
          Uri.parse('http://localhost:${enabled.port}$kSyncCredentialsPath'),
        );
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.ok);
        expect(body['id_token'], 'id');
        expect(body['refresh_token'], 'refresh');
        expect(body['expires_at'], '2026-01-01T00:00:00.000Z');
        expect(body['email'], 'seeded@example.com');
      },
    );

    test(
      'serves credentials with a null email when firebase.json is absent',
      () async {
        final credentialsDir = Directory(p.join(root.path, 'todo-config-2'))
          ..createSync(recursive: true);
        final credentialsPath = p.join(
          credentialsDir.path,
          'firebase_auth.json',
        );
        File(credentialsPath).writeAsStringSync(
          jsonEncode({
            'id_token': 'id',
            'refresh_token': 'refresh',
            'expires_at': '2026-01-01T00:00:00.000Z',
          }),
        );
        final enabled = WrapperServer(
          webRoot: p.join(root.path, 'web'),
          backlogPath: p.join(root.path, 'todo', 'BACKLOG.md'),
          logPath: p.join(root.path, 'state', 'todo_notes.json'),
          serveSyncAccount: true,
          syncConfigDir: p.join(root.path, 'crdt-sync-absent'),
          todoCredentialsPath: credentialsPath,
        );
        await enabled.start(0);
        addTearDown(enabled.stop);

        final response = await http.get(
          Uri.parse('http://localhost:${enabled.port}$kSyncCredentialsPath'),
        );
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.ok);
        expect(body['email'], isNull);
      },
    );

    test('is 404 when the credentials file is absent', () async {
      final origin = await enabledOrigin({});

      final response = await http.get(
        Uri.parse('$origin$kSyncCredentialsPath'),
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('is 404 when the credentials file is not valid JSON', () async {
      final origin = await enabledOrigin({}, credentialsJson: 'not json');

      final response = await http.get(
        Uri.parse('$origin$kSyncCredentialsPath'),
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test(
      'is 404 when the credentials file is missing required fields',
      () async {
        final origin = await enabledOrigin(
          {},
          credentialsJson: jsonEncode({'id_token': 'id'}),
        );

        final response = await http.get(
          Uri.parse('$origin$kSyncCredentialsPath'),
        );

        expect(response.statusCode, HttpStatus.notFound);
      },
    );
  });
}
