import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/mcp/mcp_main.dart';
import 'package:todo/mcp/token_file.dart';

import '../cli/fake_rtdb.dart';

void main() {
  late Directory home;
  late FakeRtdb db;
  late StringBuffer err;
  late Map<String, String> env;

  setUp(() {
    home = Directory.systemTemp.createTempSync('mcp_main');
    db = FakeRtdb();
    err = StringBuffer();
    env = {
      'HOME': home.path,
      'TODO_MCP_PORT': '0',
      'TODO_MCP_DATA_DIR': '${home.path}/data',
    };
  });
  tearDown(() => home.deleteSync(recursive: true));

  Future<Future<void> Function()?> start() =>
      startTodoMcp(env, err, httpClient: db.client);

  void writeTokens() => File('${home.path}/.config/todo-mcp/tokens')
    ..createSync(recursive: true)
    ..writeAsStringSync('${tokenHash('t')} pc\n');

  test('refuses to start without a tokens file', () async {
    expect(await start(), isNull);
    expect(err.toString(), contains('mint_token.sh'));
  });

  test('refuses to start without a seeded session, naming the app', () async {
    writeTokens();
    expect(await start(), isNull);
    expect(err.toString(), contains('--app todo-mcp'));
  });

  test('refuses to start when the first sync fails', () async {
    writeTokens();
    writeSeedCredentials(
      Directory('${home.path}/.config/todo-mcp'),
      name: 'firebase_auth.json',
    );
    db.failWith = 503;
    expect(await start(), isNull);
    expect(err.toString(), startsWith('error:'));
  });

  test('starts, publishes its own node log, and stops', () async {
    writeTokens();
    writeSeedCredentials(
      Directory('${home.path}/.config/todo-mcp'),
      name: 'firebase_auth.json',
    );
    final stop = await start();
    expect(stop, isNotNull);
    expect(err.toString(), contains('serving http://127.0.0.1:'));
    expect(db.files.keys, contains(startsWith('todo-sync/notes/')));
    expect(db.files.keys, contains(startsWith('todo-sync/revs/')));
    await stop!();
  });
}
