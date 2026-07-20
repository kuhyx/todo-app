import 'package:http/http.dart' as http;

/// Talks to the local desktop wrapper that serves the web build.
///
/// The wrapper exists because a browser cannot write to the filesystem, and two
/// things depend on it:
///
/// * `~/todo/BACKLOG.md` — read by the user's tooling and the `todo` MCP
///   server. Without this it would silently go stale after the move to a web
///   build.
/// * an on-disk copy of the note log, so a wiped Chrome profile is not a
///   total-loss event for notes that have not reached GitHub yet.
///
/// Every method is best-effort and swallows failures: the app must remain fully
/// usable when the wrapper is absent, e.g. when the build is opened in a plain
/// browser tab or on mobile.
class DesktopBackupClient {
  /// Creates a client targeting [baseUrl] (the wrapper's origin).
  DesktopBackupClient({required this.baseUrl, http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  /// Origin the wrapper listens on, e.g. `http://localhost:8730`.
  final String baseUrl;

  final http.Client _client;

  /// Writes the Markdown backlog export to disk via the wrapper.
  Future<void> writeBacklog(String markdown) =>
      _post('/backup/backlog', markdown);

  /// Writes the serialised note log to disk via the wrapper.
  Future<void> writeLog(String json) => _post('/backup/log', json);

  /// Reads the wrapper's on-disk copy of the log, or null if unavailable.
  Future<String?> readLog() => _get('/backup/log');

  /// Reads the on-disk Markdown backlog, or null if unavailable.
  Future<String?> readBacklog() => _get('/backup/backlog');

  Future<String?> _get(String path) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl$path'));
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      return response.body;
    } on Exception {
      return null;
    }
  }

  Future<void> _post(String path, String body) async {
    try {
      await _client.post(Uri.parse('$baseUrl$path'), body: body);
    } on Exception {
      // Best-effort by design; see the class docs.
    }
  }
}
