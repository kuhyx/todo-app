/// A GitHub stand-in that persists the end-to-end encryption header, which
/// the sync service writes and re-reads; every other request goes to [inner].
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Wraps [inner] so `…/e2e` PUTs are stored and served back on GET.
MockClient e2eMock(Future<http.Response> Function(http.Request) inner) {
  String? header;
  return MockClient((request) async {
    if (request.url.path.endsWith('/e2e.json')) {
      // Firebase REST: the value is a JSON-encoded string.
      if (request.method == 'PUT') {
        header = jsonDecode(request.body) as String;
        return http.Response(request.body, 200);
      }
      return http.Response(jsonEncode(header), 200);
    }
    if (!request.url.path.endsWith('/e2e')) return inner(request);
    if (request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      header = utf8.decode(base64.decode(body['content'] as String));
      return http.Response(jsonEncode({'content': {}, 'sha': 'h'}), 200);
    }
    final text = header;
    if (text == null) return http.Response('', 404);
    return http.Response(
      jsonEncode({'content': base64.encode(utf8.encode(text)), 'sha': 'h'}),
      200,
    );
  });
}
