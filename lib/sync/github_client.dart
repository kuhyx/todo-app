import 'dart:convert';

import 'package:http/http.dart' as http;

/// A file entry in a GitHub repository directory listing.
class GitHubFile {
  const GitHubFile({required this.name, required this.path, required this.sha});

  final String name;
  final String path;

  /// Git blob SHA; required to update or delete the file.
  final String sha;
}

/// Raised when the GitHub API returns an unexpected status.
class GitHubApiException implements Exception {
  GitHubApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'GitHubApiException($statusCode): $message';
}

/// Minimal GitHub REST client scoped to the Contents API.
///
/// This is the only component that holds the access token, mirroring the
/// "server holds credentials" pattern: the rest of the app deals in notes
/// and changesets, never in raw HTTP or secrets. The token can come from a
/// pasted PAT today or the OAuth device flow later — this class does not
/// care how it was obtained.
class GitHubClient {
  GitHubClient({
    required this.owner,
    required this.repo,
    required String token,
    http.Client? httpClient,
    this.branch = 'main',
  }) // Dart forbids private named params, so this can't be an initializing
    // formal; assign it explicitly.
    // ignore: prefer_initializing_formals
    : _token = token,
       _http = httpClient ?? http.Client();

  final String owner;
  final String repo;
  final String branch;
  final String _token;
  final http.Client _http;

  static const _apiBase = 'https://api.github.com';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'todo-app-sync',
  };

  Uri _contentsUri(String path) =>
      Uri.parse('$_apiBase/repos/$owner/$repo/contents/$path');

  /// Lists the files directly under [dirPath]. Returns an empty list if the
  /// directory does not exist yet (e.g. before the first sync).
  Future<List<GitHubFile>> listDirectory(String dirPath) async {
    final res = await _http.get(
      _contentsUri(dirPath).replace(queryParameters: {'ref': branch}),
      headers: _headers,
    );
    if (res.statusCode == 404) return [];
    _ensureOk(res, 'list $dirPath');
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return [];
    return decoded
        .cast<Map<String, dynamic>>()
        .where((e) => e['type'] == 'file')
        .map(
          (e) => GitHubFile(
            name: e['name'] as String,
            path: e['path'] as String,
            sha: e['sha'] as String,
          ),
        )
        .toList();
  }

  /// Fetches and UTF-8-decodes a file's contents. Returns null if absent.
  Future<String?> getFileText(String path) async {
    final res = await _http.get(
      _contentsUri(path).replace(queryParameters: {'ref': branch}),
      headers: _headers,
    );
    if (res.statusCode == 404) return null;
    _ensureOk(res, 'get $path');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    // GitHub base64-encodes file content, wrapping lines at 60 chars.
    final raw = (json['content'] as String).replaceAll('\n', '');
    return utf8.decode(base64.decode(raw));
  }

  /// Creates or updates [path] with [text]. Pass the current [sha] when
  /// updating an existing file; omit it to create a new one.
  Future<void> putFileText(
    String path,
    String text, {
    String? sha,
    String? message,
  }) async {
    final body = <String, dynamic>{
      'message': message ?? 'sync: update $path',
      'content': base64.encode(utf8.encode(text)),
      'branch': branch,
      'sha': ?sha,
    };
    final res = await _http.put(
      _contentsUri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ensureOk(res, 'put $path');
  }

  /// Deletes the file at [path] (requires its current [sha]).
  Future<void> deleteFile(String path, String sha, {String? message}) async {
    final res = await _http.delete(
      _contentsUri(path),
      headers: _headers,
      body: jsonEncode({
        'message': message ?? 'sync: delete $path',
        'sha': sha,
        'branch': branch,
      }),
    );
    _ensureOk(res, 'delete $path');
  }

  /// Cheap auth/connectivity probe used by the settings "Test connection"
  /// button: succeeds only if the token can read the repo.
  Future<bool> canAccessRepo() async {
    final res = await _http.get(
      Uri.parse('$_apiBase/repos/$owner/$repo'),
      headers: _headers,
    );
    return res.statusCode == 200;
  }

  void close() => _http.close();

  void _ensureOk(http.Response res, String action) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GitHubApiException(
        res.statusCode,
        'Failed to $action: ${res.body}',
      );
    }
  }
}
