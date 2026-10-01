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

  /// Paths whose GET drops the connection after the first chunk.
  final Set<String> dropMidBody = {};

  /// The HTTP client the image client talks through. Streaming, like the
  /// real one: bodies arrive and leave as streams.
  http.Client httpClient() => MockClient.streaming((request, body) async {
    requests.add('${request.method} ${request.url.path}');
    if (!online) throw const SocketException('offline');
    final key = request.url.path.replaceFirst('/todo-images/', '');
    switch (request.method) {
      case 'PUT':
        files[key] = await body.toBytes();
        return http.StreamedResponse(const Stream.empty(), 201);
      case 'GET':
        final bytes = files[key];
        if (bytes == null) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          dropMidBody.contains(key) ? _dropped(bytes) : Stream.value(bytes),
          200,
        );
      default:
        return http.StreamedResponse(const Stream.empty(), 207);
    }
  });

  Stream<List<int>> _dropped(List<int> bytes) async* {
    yield bytes;
    throw const SocketException('connection dropped');
  }

  /// A client over this fake.
  DufsImageClient client() => DufsImageClient(
    const DufsLogin(user: 'todo', password: 'pw', baseUrl: 'https://d'),
    httpClient: httpClient(),
  );
}
