import 'dart:async';

import 'package:http/http.dart' as http;

/// An HTTP client whose every request is bounded.
///
/// `package:http` has no timeout of its own, and neither do the Firebase and
/// token clients built on it: one dead connection (after boot, a network
/// blip) made a sync wait forever and wedged the MCP server's serial queue.
/// [timeout] bounds the wait for the response headers and then each gap
/// between body chunks, so a large body that keeps moving is never cut off.
class TimeoutClient extends http.BaseClient {
  /// Wraps [_inner]; each wait fails with a [TimeoutException] after [timeout].
  TimeoutClient(this._inner, {this.timeout = const Duration(seconds: 30)});

  final http.Client _inner;

  /// Longest wait for the headers, and for the next body chunk.
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner
        .send(request)
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            '${request.method} ${request.url.host} got no response',
            timeout,
          ),
        );
    return http.StreamedResponse(
      response.stream.timeout(
        timeout,
        onTimeout: (sink) {
          sink
            ..addError(
              TimeoutException(
                '${request.method} ${request.url.host} body stalled',
                timeout,
              ),
            )
            ..close();
        },
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
