/// The three WebDAV calls attachment sync needs, against kuhy's dufs.
///
/// Deliberately not dufs-cloud's full `DufsClient` (~700 lines with listing,
/// moves, streaming progress and an xml parser): todo only ever puts, gets and
/// checks one folder. dufs creates missing parent folders on PUT (verified
/// against dufs 0.46.0), so there is no MKCOL step.
///
/// Bodies stream both ways: an attachment can be gigabytes, and neither the
/// phone nor the wrapper may hold one in memory.
///
/// Pure Dart: the desktop wrapper imports it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:todo/images/attachment_ref.dart';

/// A scoped dufs login, e.g. `todo` → `/todo-images`.
class DufsLogin {
  /// Creates a login for [user] with [password] against [baseUrl].
  const DufsLogin({
    required this.user,
    required this.password,
    this.baseUrl = kDufsBaseUrl,
  });

  /// The login name (`add_dufs_login.sh`'s first argument).
  final String user;

  /// Its generated password.
  final String password;

  /// The dufs origin, without a trailing slash.
  final String baseUrl;
}

/// Outcome of [DufsImageClient.check], for the settings screen.
enum DufsCheck {
  /// The login can see its folder.
  ok,

  /// dufs refused the login (401/403).
  rejected,

  /// dufs answered something else, or could not be reached.
  unreachable,
}

/// Upload / download / check for attachments under [kImagesDir].
class DufsImageClient {
  /// Creates a client for [login]; [httpClient] is injectable for tests.
  DufsImageClient(this.login, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// The credentials every request carries.
  final DufsLogin login;

  final http.Client _http;

  Map<String, String> get _auth {
    final pair = utf8.encode('${login.user}:${login.password}');
    return {'authorization': 'Basic ${base64.encode(pair)}'};
  }

  Uri _uri(String relative) =>
      Uri.parse('${login.baseUrl}/$kImagesDir/$relative');

  /// PUTs the [length] bytes of [body] as [ref]; true on a 2xx.
  ///
  /// [body] is only listened to once the connection is up, so a file stream
  /// passed here is never read when dufs is unreachable.
  Future<bool> upload(
    AttachmentRef ref,
    Stream<List<int>> body,
    int length,
  ) async {
    try {
      final request = _StreamBodyRequest('PUT', _uri(ref.relativePath), body)
        ..contentLength = length
        ..headers.addAll({
          ..._auth,
          'content-type': ref.extension == 'jpg'
              ? 'image/jpeg'
              : 'application/octet-stream',
        });
      final response = await _http.send(request);
      await response.stream.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    }
  }

  /// GETs [ref], returning its body as a stream, or null when it is missing
  /// or unreachable. The caller must consume the stream.
  Future<Stream<List<int>>?> openDownload(AttachmentRef ref) async {
    try {
      final request = http.Request('GET', _uri(ref.relativePath))
        ..headers.addAll(_auth);
      final response = await _http.send(request);
      if (response.statusCode == 200) return response.stream;
      await response.stream.drain<void>();
      return null;
    } on Exception {
      return null;
    }
  }

  /// Whether the login can see its folder (PROPFIND, depth 0).
  Future<DufsCheck> check() async {
    try {
      final request = http.Request('PROPFIND', _uri(''))
        ..headers.addAll({..._auth, 'depth': '0'});
      final response = await _http.send(request);
      await response.stream.drain<void>();
      return switch (response.statusCode) {
        207 => DufsCheck.ok,
        401 || 403 => DufsCheck.rejected,
        _ => DufsCheck.unreachable,
      };
    } on Exception {
      return DufsCheck.unreachable;
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _http.close();
}

/// A request whose body is an existing stream, pulled by the client as it
/// sends. Unlike `http.StreamedRequest`, nothing is buffered when the
/// connection fails before the body is wanted.
class _StreamBodyRequest extends http.BaseRequest {
  _StreamBodyRequest(super.method, super.url, this._body);

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
