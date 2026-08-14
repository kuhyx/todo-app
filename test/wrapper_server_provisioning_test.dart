import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_server.dart';

import 'wrapper_server_harness.dart';

void main() {
  final h = WrapperHarness()..install();

  group('sync-account provisioning', () {
    test('is 404 when not enabled', () async {
      // The default, and the whole security posture: a credential route must
      // not be reachable just because the app is running.
      final response = await http.get(Uri.parse('${h.base}$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('serves the account when enabled', () async {
      final origin = await h.enabledOrigin({
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
      final origin = await h.enabledOrigin({});

      final response = await http.get(Uri.parse('$origin$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('is 404 when firebase.json has no usable email', () async {
      final origin = await h.enabledOrigin({
        'firebase.json': '{"apiKey":"x"}',
        'password': 'pw',
      });

      final response = await http.get(Uri.parse('$origin$kSyncAccountPath'));

      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('sync-credentials provisioning', () {
    // Unlike /sync-account, this route needs no CRDT_SYNC_SERVE_ACCOUNT: a
    // normal launch must self-provision with nothing to remember. [h.base]'s
    // h.server was built with no credentials file at the default path, so this
    // exercises the file-absent 404, not a disabled-route 404 -- there is no
    // "disabled" state for this route anymore.
    test(
      'is 404 when no credentials file exists at the default path',
      () async {
        final response = await http.get(
          Uri.parse('${h.base}$kSyncCredentialsPath'),
        );

        expect(response.statusCode, HttpStatus.notFound);
      },
    );

    test('serves once, then 404s for the rest of the process', () async {
      final credentialsDir = Directory(p.join(h.root.path, 'todo-config-once'))
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
        webRoot: p.join(h.root.path, 'web'),
        backlogPath: p.join(h.root.path, 'todo', 'BACKLOG.md'),
        logPath: p.join(h.root.path, 'state', 'todo_notes.json'),
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
        final configDir = Directory(p.join(h.root.path, 'crdt-sync'))
          ..createSync(recursive: true);
        File(
          p.join(configDir.path, 'firebase.json'),
        ).writeAsStringSync('{"email":"seeded@example.com"}');
        final credentialsDir = Directory(p.join(h.root.path, 'todo-config'))
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
          webRoot: p.join(h.root.path, 'web'),
          backlogPath: p.join(h.root.path, 'todo', 'BACKLOG.md'),
          logPath: p.join(h.root.path, 'state', 'todo_notes.json'),
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
        final credentialsDir = Directory(p.join(h.root.path, 'todo-config-2'))
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
          webRoot: p.join(h.root.path, 'web'),
          backlogPath: p.join(h.root.path, 'todo', 'BACKLOG.md'),
          logPath: p.join(h.root.path, 'state', 'todo_notes.json'),
          serveSyncAccount: true,
          syncConfigDir: p.join(h.root.path, 'crdt-sync-absent'),
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
      final origin = await h.enabledOrigin({});

      final response = await http.get(
        Uri.parse('$origin$kSyncCredentialsPath'),
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('is 404 when the credentials file is not valid JSON', () async {
      final origin = await h.enabledOrigin({}, credentialsJson: 'not json');

      final response = await http.get(
        Uri.parse('$origin$kSyncCredentialsPath'),
      );

      expect(response.statusCode, HttpStatus.notFound);
    });

    test(
      'is 404 when the credentials file is missing required fields',
      () async {
        final origin = await h.enabledOrigin(
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
