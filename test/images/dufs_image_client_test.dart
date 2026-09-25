import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/images/dufs_image_client.dart';
import 'package:todo/images/image_ref.dart';

void main() {
  final ref = ImageRef.tryParse('n1/a.jpg')!;
  const login = DufsLogin(user: 'todo', password: 'pw', baseUrl: 'https://d');
  final auth = 'Basic ${base64.encode(utf8.encode('todo:pw'))}';

  DufsImageClient client(MockClientHandler handler) =>
      DufsImageClient(login, httpClient: MockClient(handler));

  test('the default login points at kuhy-cloud', () {
    expect(const DufsLogin(user: 'u', password: 'p').baseUrl, kDufsBaseUrl);
  });

  test('upload PUTs the bytes with basic auth; true on 2xx', () async {
    late http.Request seen;
    final ok = await client((r) async {
      seen = r;
      return http.Response('', 201);
    }).upload(ref, Uint8List.fromList([1, 2]));
    expect(ok, isTrue);
    expect(seen.method, 'PUT');
    expect(seen.url.toString(), 'https://d/todo-images/n1/a.jpg');
    expect(seen.headers['authorization'], auth);
    expect(seen.headers['content-type'], 'image/jpeg');
    expect(seen.bodyBytes, [1, 2]);
  });

  test('upload is false on a refusal or a network error', () async {
    expect(
      await client(
        (_) async => http.Response('', 403),
      ).upload(ref, Uint8List(1)),
      isFalse,
    );
    expect(
      await client(
        (_) => throw const SocketException('down'),
      ).upload(ref, Uint8List(1)),
      isFalse,
    );
  });

  test('download returns bytes on 200, null otherwise', () async {
    expect(
      await client((r) async {
        expect(r.headers['authorization'], auth);
        return http.Response.bytes([7, 8], 200);
      }).download(ref),
      [7, 8],
    );
    expect(
      await client((_) async => http.Response('', 404)).download(ref),
      isNull,
    );
    expect(
      await client((_) => throw const SocketException('down')).download(ref),
      isNull,
    );
  });

  test('check maps PROPFIND answers', () async {
    Future<DufsCheck> answer(int code) => client((r) async {
      expect(r.method, 'PROPFIND');
      expect(r.headers['depth'], '0');
      expect(r.url.toString(), 'https://d/todo-images/');
      return http.Response('', code);
    }).check();
    expect(await answer(207), DufsCheck.ok);
    expect(await answer(401), DufsCheck.rejected);
    expect(await answer(403), DufsCheck.rejected);
    expect(await answer(502), DufsCheck.unreachable);
    expect(
      await client((_) => throw const SocketException('down')).check(),
      DufsCheck.unreachable,
    );
  });

  test('a default http client is created when none is given', () {
    DufsImageClient(login).close();
  });

  test('close closes the http client', () {
    var closed = false;
    final inner = _ClosingClient(() => closed = true);
    DufsImageClient(login, httpClient: inner).close();
    expect(closed, isTrue);
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
