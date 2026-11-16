import 'dart:async';
import 'dart:io';

/// Answers 503 here because the library can only say 403 for a refusal; it
/// then fails to write its own 403 ("Header already sent", swallowed by the
/// zone guard in `TodoMcpServer.start`) and the request stays refused.
bool answerUnavailable(HttpRequest request) {
  request.response
    ..statusCode = HttpStatus.serviceUnavailable
    ..write('Service Unavailable')
    ..close().ignore();
  return false;
}

/// Closes [request]'s response with 503 once [deadline] passes, unless it was
/// answered first. Safe on any state: a response already closed or a dead
/// socket is ignored.
void guardDeadline(HttpRequest request, Duration deadline) {
  if (request.method == 'GET') return;
  final response = request.response;
  final timer = Timer(deadline, () async {
    try {
      response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('Request timed out');
    } on Object {
      // Headers already sent: just end the stream.
    }
    try {
      await response.close();
    } on Object {
      // The peer is gone; the socket is released either way.
    }
  });
  unawaited(
    response.done
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(timer.cancel),
  );
}
