import 'dart:convert';
import 'dart:io';

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
    );
    // Port 0 lets the OS pick, so tests never collide with a running app.
    await server.start(0);
    base = 'http://localhost:${server.port}';
  });

  tearDown(() async {
    await server.stop();
    root.deleteSync(recursive: true);
  });

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
}
