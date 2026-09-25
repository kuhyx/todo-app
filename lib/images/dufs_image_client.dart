/// The three WebDAV calls image sync needs, against kuhy's dufs.
///
/// Deliberately not dufs-cloud's full `DufsClient` (~700 lines with listing,
/// moves, streaming progress and an xml parser): todo only ever puts, gets and
/// checks one folder. dufs creates missing parent folders on PUT (verified
/// against dufs 0.46.0), so there is no MKCOL step.
///
/// Pure Dart: the desktop wrapper imports it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:todo/images/image_ref.dart';

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

/// Upload / download / check for images under [kImagesDir].
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

  /// PUTs [bytes] as [ref]; true on a 2xx.
  Future<bool> upload(ImageRef ref, Uint8List bytes) async {
    try {
      final response = await _http.put(
        _uri(ref.relativePath),
        headers: {..._auth, 'content-type': 'image/jpeg'},
        body: bytes,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    }
  }

  /// GETs [ref]'s bytes, or null when it is missing or unreachable.
  Future<Uint8List?> download(ImageRef ref) async {
    try {
      final response = await _http.get(
        _uri(ref.relativePath),
        headers: _auth,
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
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
