/// An in-memory dufs for image-sync tests: a map of `todo-images/...` paths
/// to bytes behind a MockClient, with an [online] switch.
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/images/dufs_image_client.dart';

/// Fake server state plus a client factory over it.
class FakeDufs {
  /// Stored files, keyed by the path after `/todo-images/`.
  final Map<String, List<int>> files = {};

  /// When false every request fails like a dropped connection.
  bool online = true;

  /// Every request's `METHOD path`, in order.
  final List<String> requests = [];

  /// The HTTP client the image client talks through.
  http.Client httpClient() => MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    if (!online) throw const SocketException('offline');
    final key = request.url.path.replaceFirst('/todo-images/', '');
    switch (request.method) {
      case 'PUT':
        files[key] = request.bodyBytes;
        return http.Response('', 201);
      case 'GET':
        final bytes = files[key];
        return bytes == null
            ? http.Response('', 404)
            : http.Response.bytes(bytes, 200);
      default:
        return http.Response('', 207);
    }
  });

  /// A client over this fake.
  DufsImageClient client() => DufsImageClient(
    const DufsLogin(user: 'todo', password: 'pw', baseUrl: 'https://d'),
    httpClient: httpClient(),
  );
}
