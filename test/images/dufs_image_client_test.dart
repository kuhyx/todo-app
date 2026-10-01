import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/dufs_image_client.dart';

void main() {
  final ref = AttachmentRef.tryParse('n1/a.jpg')!;
  const login = DufsLogin(user: 'todo', password: 'pw', baseUrl: 'https://d');
  final auth = 'Basic ${base64.encode(utf8.encode('todo:pw'))}';

  DufsImageClient client(MockClientHandler handler) =>
      DufsImageClient(login, httpClient: MockClient(handler));

  test('the default login points at kuhy-cloud', () {
    expect(const DufsLogin(user: 'u', password: 'p').baseUrl, kDufsBaseUrl);
  });

  Stream<List<int>> body(List<int> bytes) => Stream.value(bytes);

  test('upload streams the body with basic auth and its length', () async {
    late http.Request seen;
    final ok = await client((r) async {
      seen = r;
      return http.Response('', 201);
    }).upload(ref, body([1, 2]), 2);
    expect(ok, isTrue);
    expect(seen.method, 'PUT');
    expect(seen.url.toString(), 'https://d/todo-images/n1/a.jpg');
    expect(seen.headers['authorization'], auth);
    expect(seen.headers['content-type'], 'image/jpeg');
    expect(seen.bodyBytes, [1, 2]);
  });

  test('upload declares the length up front, so nothing is buffered', () async {
    final capture = _CapturingClient();
    final file = AttachmentRef.tryParse('n1/b.pdf')!;
    await DufsImageClient(
      login,
      httpClient: capture,
    ).upload(file, body([1, 2, 3]), 3);
    expect(capture.seen.contentLength, 3);
    expect(capture.seen.headers['content-type'], 'application/octet-stream');
  });

  test('upload is false on a refusal or a network error', () async {
    expect(
      await client(
        (_) async => http.Response('', 403),
      ).upload(ref, body([1]), 1),
      isFalse,
    );
    expect(
      await client(
        (_) => throw const SocketException('down'),
      ).upload(ref, body([1]), 1),
      isFalse,
    );
  });

  test('openDownload streams the body on 200, null otherwise', () async {
    final stream = await client((r) async {
      expect(r.method, 'GET');
      expect(r.headers['authorization'], auth);
      return http.Response.bytes([7, 8], 200);
    }).openDownload(ref);
    expect(await stream!.expand((chunk) => chunk).toList(), [7, 8]);
    expect(
      await client((_) async => http.Response('', 404)).openDownload(ref),
      isNull,
    );
    expect(
      await client(
        (_) => throw const SocketException('down'),
      ).openDownload(ref),
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

/// Records the request as sent, before any mock flattens it.
class _CapturingClient extends http.BaseClient {
  late http.BaseRequest seen;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen = request;
    await request.finalize().drain<void>();
    return http.StreamedResponse(const Stream.empty(), 201);
  }
}
