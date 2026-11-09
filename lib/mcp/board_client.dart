/// The todoImplementer board as `add_task new_note` sees it: whether a
/// note has a session running, and a Start click on a merged task. Start
/// goes through the board's own page (CSRF meta tag, same Origin), so the
/// board needs no new endpoint. Failures come back as reasons, never throws:
/// a board that is down must not lose the task that was just saved.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the board listens (loopback only).
final Uri kBoardBase = Uri.parse('http://127.0.0.1:8786');

/// A Start attempt: the item started, or why not.
typedef StartResult = ({bool ok, String? reason, String? item});

final _csrf = RegExp(r'<meta\s+name="todoimpl-csrf"\s+content="([^"]+)"');

/// Talks to the board over [client] at [base].
class BoardClient {
  /// [client] is injectable so tests need no network.
  BoardClient({http.Client? client, Uri? base})
    : _http = client ?? http.Client(),
      base = base ?? kBoardBase;

  final http.Client _http;

  /// The board's origin; also the `Origin` header of a POST.
  final Uri base;

  static const _timeout = Duration(seconds: 5);

  Future<List<Map<String, dynamic>>> _cards(String noteId) async {
    final res = await _http.get(base.resolve('/api/board')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('GET /api/board ${res.statusCode}');
    }
    final tasks = _json(res)['tasks'];
    final prefix = '${noteId.substring(0, 8)}-';
    return [
      for (final t in (tasks as List).cast<Map<String, dynamic>>())
        if ((t['id']! as String).startsWith(prefix)) t,
    ];
  }

  /// Whether any item of the note is in the board's Running column; false
  /// when the board cannot be reached.
  Future<bool> running(String noteId) async {
    try {
      return (await _cards(noteId)).any((c) => c['column'] == 'running');
    } on Object {
      return false;
    }
  }

  /// Clicks Start on the note's last startable item titled [title].
  Future<StartResult> start(String noteId, String title) async {
    try {
      final card = (await _cards(noteId)).reversed
          .where((c) => c['title'] == title && _startable(c))
          .firstOrNull;
      if (card == null) return _no('no startable item');
      final page = await _http.get(base).timeout(_timeout);
      final token = _csrf.firstMatch(page.body)?.group(1);
      if (token == null) return _no('no CSRF token on the board page');
      final id = card['id']! as String;
      final res = await _http
          .post(
            base.resolve('/api/task/$id/start'),
            headers: {'Origin': base.origin, 'X-Todoimpl-Token': token},
          )
          .timeout(_timeout);
      if (res.statusCode == 200) return (ok: true, reason: null, item: id);
      return _no('board refused start: ${res.statusCode} ${_message(res)}');
    } on Object catch (e) {
      return _no('board unreachable: $e');
    }
  }

  static bool _startable(Map<String, dynamic> card) => (card['actions'] as List)
      .cast<Map<String, dynamic>>()
      .any((a) => a['id'] == 'start' && a['enabled'] == true);

  static String _message(http.Response res) {
    try {
      final error = _json(res)['error'];
      return (error as Map<String, dynamic>)['message'] as String;
    } on Object {
      return res.body;
    }
  }

  // The board's JSON is UTF-8 whatever the Content-Type says.
  static Map<String, dynamic> _json(http.Response res) =>
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

  static StartResult _no(String reason) =>
      (ok: false, reason: reason, item: null);
}
