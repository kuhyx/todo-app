import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_image_routes.dart';
import 'package:todo/desktop/wrapper_server.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/image_cache_store.dart';

void main() {
  late Directory root;
  late WrapperServer server;
  late String base;
  late ImageCacheStore store;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wrapper_attach');
    File(p.join(root.path, 'index.html')).writeAsStringSync('<h1>todo</h1>');
    store = ImageCacheStore(Directory(p.join(root.path, 'images')));
    server = WrapperServer(
      webRoot: root.path,
      backlogPath: p.join(root.path, 'BACKLOG.md'),
      logPath: p.join(root.path, 'log.json'),
      todoCredentialsPath: p.join(root.path, 'none.json'),
      images: WrapperImageRoutes(
        store: store,
        loginEnvPath: p.join(root.path, 'none.env'),
        // Identity "re-encode": decodes anything starting like a JPEG.
        prepare: (bytes) async => bytes.first == 0xFF ? bytes : null,
      ),
    );
    await server.start(0);
    base = 'http://localhost:${server.port}';
  });
  tearDown(() async {
    await server.stop();
    root.deleteSync(recursive: true);
  });

  Future<http.Response> attach(
    List<int> body, {
    String note = 'n1',
    String name = 'Raport.pdf',
    Map<String, String> headers = const {},
  }) => http.post(
    Uri.parse('$base/images/attach?note=$note&name=$name'),
    body: body,
    headers: headers,
  );

  Attachment attached(http.Response response) =>
      Attachment.fromJson(jsonDecode(response.body));

  test('attach stores any file byte for byte and answers with it', () async {
    final response = await attach('%PDF-1.7 x'.codeUnits);
    expect(response.statusCode, 200);
    final a = attached(response);
    expect((a.name, a.isImage, a.ref.extension), ('Raport.pdf', false, 'pdf'));
    expect(store.fileFor(a.ref).readAsStringSync(), '%PDF-1.7 x');
    expect(store.isPending(a.ref), isTrue);
  });

  test('attach turns an image into a re-encoded jpg', () async {
    final a = attached(await attach([0xFF, 0xD8, 0xFF, 1], name: 'p.png'));
    expect(a.isImage, isTrue);
    expect(a.ref.extension, 'jpg');
  });

  test('attach refuses an unsafe note and reports a disk failure', () async {
    expect((await attach([1], note: '..')).statusCode, 400);
    expect((await attach([1], note: '')).statusCode, 400);
    File(store.root.path).writeAsStringSync('in the way');
    expect((await attach([1])).statusCode, 500);
  });

  group('serving', () {
    late AttachmentRef pdf;

    setUp(() async {
      pdf = attached(await attach(List.filled(100, 7))).ref;
    });

    test('GET names the file and keeps the browser from sniffing', () async {
      final response = await http.get(
        Uri.parse('$base/images/${pdf.relativePath}?name=Raport%20v2.pdf'),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/pdf');
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['accept-ranges'], 'bytes');
      expect(
        response.headers['content-disposition'],
        "inline; filename*=UTF-8''Raport%20v2.pdf",
      );
      expect(response.bodyBytes, List.filled(100, 7));
    });

    test('a scriptable type is only ever a download', () async {
      final html = attached(await attach([1], name: 'evil.html')).ref;
      final response = await http.get(
        Uri.parse('$base/images/${html.relativePath}'),
      );
      expect(response.headers['content-type'], 'application/octet-stream');
      expect(
        response.headers['content-disposition'],
        startsWith('attachment;'),
      );
    });

    test('HEAD reports the size without a body', () async {
      final response = await http.head(
        Uri.parse('$base/images/${pdf.relativePath}'),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-length'], '100');
      expect(response.bodyBytes, isEmpty);
    });

    test('a range is served partially, a bad one refused', () async {
      final url = Uri.parse('$base/images/${pdf.relativePath}');
      final part = await http.get(url, headers: {'range': 'bytes=10-19'});
      expect(part.statusCode, 206);
      expect(part.headers['content-range'], 'bytes 10-19/100');
      expect(part.bodyBytes, hasLength(10));
      final bad = await http.get(url, headers: {'range': 'bytes=500-'});
      expect(bad.statusCode, 416);
      expect(bad.headers['content-range'], 'bytes */100');
    });

    test('an empty file is served empty', () async {
      final empty = attached(await attach([], name: 'empty.txt')).ref;
      final response = await http.get(
        Uri.parse('$base/images/${empty.relativePath}'),
      );
      expect(response.statusCode, 200);
      expect(response.bodyBytes, isEmpty);
    });

    test('a client leaving mid-download does not stop the server', () async {
      final big = attached(
        await attach(List.filled(16 * 1024 * 1024, 1), name: 'big.bin'),
      ).ref;
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('$base/images/${big.relativePath}'),
      );
      final response = await request.close();
      await response.first;
      client.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await http.get(Uri.parse('$base/'))).statusCode, 200);
    });
  });

  test('writes from another site are refused, the app own allowed', () async {
    final foreign = await attach(
      [1],
      headers: {'origin': 'https://evil.example'},
    );
    expect(foreign.statusCode, 403);
    expect(store.pending(), isEmpty);
    final backup = await http.post(
      Uri.parse('$base/backup/backlog'),
      headers: {'origin': 'https://evil.example'},
      body: 'pwned',
    );
    expect(backup.statusCode, 403);
    expect(File(p.join(root.path, 'BACKLOG.md')).existsSync(), isFalse);
    for (final own in [
      'http://localhost:${server.port}',
      'http://127.0.0.1:${server.port}',
    ]) {
      expect((await attach([1], headers: {'origin': own})).statusCode, 200);
    }
    final read = await http.get(
      Uri.parse('$base/'),
      headers: {'origin': 'https://evil.example'},
    );
    expect(read.statusCode, 200, reason: 'reads stay CORS-protected');
  });

  test('an upload abandoned halfway leaves nothing behind', () async {
    final socket = await Socket.connect('localhost', server.port);
    socket.write(
      'POST /images/attach?note=n1&name=a.bin HTTP/1.1\r\n'
      'Host: localhost\r\nContent-Length: 1000000\r\n\r\nabc',
    );
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    socket.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.root.listSync(recursive: true).whereType<File>(), isEmpty);
    expect((await http.get(Uri.parse('$base/'))).statusCode, 200);
  });

  test('a slow upload does not hold up the page', () async {
    final slow = http.StreamedRequest(
      'POST',
      Uri.parse('$base/images/attach?note=n1&name=slow.bin'),
    )..contentLength = 4;
    final sent = http.Client().send(slow);
    slow.sink.add([1, 2]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final page = await http
        .get(Uri.parse('$base/'))
        .timeout(const Duration(seconds: 5));
    expect(page.statusCode, 200);
    slow.sink.add([3, 4]);
    unawaited(slow.sink.close());
    expect((await sent).statusCode, 200);
  });
}
