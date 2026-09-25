import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_image_routes.dart';
import 'package:todo/desktop/wrapper_server.dart';
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_ref.dart';

import '../images/fake_dufs.dart';

void main() {
  late Directory root;
  late WrapperServer server;
  late String base;
  late FakeDufs dufs;
  late ImageCacheStore store;
  const rel = 'n1/0815ff8a-203e-4f54-9cc5-8a58b27982ec.jpg';

  File envFile() => File(p.join(root.path, 'dufs', 'todo.env'));

  void writeLogin() {
    envFile()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'DUFS_URL=https://d\nDUFS_USER=todo\nDUFS_PASSWORD=pw\n',
      );
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wrapper_images');
    dufs = FakeDufs();
    store = ImageCacheStore(Directory(p.join(root.path, 'images')));
    server = WrapperServer(
      webRoot: root.path,
      backlogPath: p.join(root.path, 'BACKLOG.md'),
      logPath: p.join(root.path, 'log.json'),
      todoCredentialsPath: p.join(root.path, 'none.json'),
      images: WrapperImageRoutes(
        store: store,
        loginEnvPath: envFile().path,
        httpClient: dufs.httpClient,
        // Identity "re-encode" that still refuses non-images, so the
        // routes are tested without decoding real photos.
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

  Future<http.Response> reconcile(Object body) =>
      http.post(Uri.parse('$base/images/reconcile'), body: jsonEncode(body));

  test('the default routes live under the given home', () {
    final routes = defaultWrapperImageRoutes('/h');
    expect(routes.store.root.path, '/h/.local/share/todo-desktop/images');
    expect(routes.loginEnvPath, '/h/.config/dufs/logins/todo.env');
  });

  test('POST stores and queues an image, GET serves it', () async {
    final post = await http.post(
      Uri.parse('$base/images/$rel'),
      body: Uint8List.fromList([0xFF, 1, 2]),
    );
    expect(post.statusCode, 204);
    expect(store.isPending(ImageRef.tryParse(rel)!), isTrue);
    final get = await http.get(Uri.parse('$base/images/$rel'));
    expect(get.statusCode, 200);
    expect(get.headers['content-type'], 'image/jpeg');
    expect(get.headers['cache-control'], contains('max-age'));
    expect(get.bodyBytes, [0xFF, 1, 2]);
  });

  test('non-images are refused with 415 and nothing is stored', () async {
    final post = await http.post(
      Uri.parse('$base/images/$rel'),
      body: Uint8List.fromList([1, 2]),
    );
    expect(post.statusCode, 415);
    expect(store.pending(), isEmpty);
  });

  test('oversized uploads are refused with 413', () async {
    final big = Uint8List(kMaxImageUploadBytes + 1)..[0] = 0xFF;
    final post = await http.post(Uri.parse('$base/images/$rel'), body: big);
    expect(post.statusCode, 413);
  });

  test('unknown image, bad path and bad method', () async {
    expect((await http.get(Uri.parse('$base/images/$rel'))).statusCode, 404);
    expect(
      (await http.get(Uri.parse('$base/images/n1/x.png'))).statusCode,
      404,
    );
    expect((await http.delete(Uri.parse('$base/images/$rel'))).statusCode, 405);
    expect(
      (await http.get(Uri.parse('$base/images/reconcile'))).statusCode,
      404,
    );
  });

  test('status reports login and queue', () async {
    Future<Map<String, dynamic>> status() async =>
        jsonDecode((await http.get(Uri.parse('$base/images/status'))).body)
            as Map<String, dynamic>;
    expect(await status(), {'configured': false, 'pending': 0});
    writeLogin();
    await http.post(
      Uri.parse('$base/images/$rel'),
      body: Uint8List.fromList([0xFF]),
    );
    expect(await status(), {'configured': true, 'pending': 1});
  });

  test('reconcile uploads with the env login and prefetches', () async {
    writeLogin();
    await http.post(
      Uri.parse('$base/images/$rel'),
      body: Uint8List.fromList([0xFF, 9]),
    );
    dufs.files['n2/b.jpg'] = [5];
    final response = await reconcile({
      'refs': [rel, 'n2/b.jpg', '../bad.jpg'],
    });
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {
      'uploaded': 1,
      'downloaded': 1,
      'evicted': 0,
      'pending': 0,
      'missing': 0,
    });
    expect(dufs.files[rel], [0xFF, 9]);
  });

  test('reconcile without a login only reports', () async {
    final response = await reconcile({'refs': <String>[]});
    expect(jsonDecode(response.body)['uploaded'], 0);
    expect(dufs.requests, isEmpty);
  });

  test('reconcile rejects malformed bodies', () async {
    for (final body in ['not json', '[]', '{"refs": [1]}', '{}']) {
      final response = await http.post(
        Uri.parse('$base/images/reconcile'),
        body: body,
      );
      expect(response.statusCode, 400, reason: body);
    }
  });

  test('jpg is served with an image content type', () {
    expect(WrapperServer.contentTypeFor('a.JPG').mimeType, 'image/jpeg');
    expect(WrapperServer.contentTypeFor('a.jpeg').mimeType, 'image/jpeg');
  });
}
