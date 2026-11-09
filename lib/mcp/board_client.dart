/// The todoImplementer board as `add_task new_note` sees it: whether a
/// note has a session running, and a Start click on a merged task. Start
/// goes through the board's own page (CSRF meta tag, same Origin), so the
/// board needs no new endpoint. Failures come back as reasons, never throws:
/// a board that is down must not lose the task that was just saved.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the board listens (loopback only).
final Uri kBoardBase = Uri.parse('http://127.0.0.1:8786');

/// A Start attempt: the item started, or why not.
typedef StartResult = ({bool ok, String? reason, String? item});

final _csrf = RegExp(r'<meta\s+name="todoimpl-csrf"\s+content="([^"]+)"');

/// Talks to the board over [client] at [base].
class BoardClient {
  /// [client] is injectable so tests need no network. [wait] bounds how
  /// long Start waits for the board to see a merged section (its note cache
  /// lags ~10 s, T1863) and to confirm a Start whose reply outran
  /// [startTimeout] (T1864); [poll] is the gap between board reads.
  BoardClient({
    http.Client? client,
    Uri? base,
    this.wait = const Duration(seconds: 30),
    this.poll = const Duration(seconds: 1),
    this.startTimeout = const Duration(seconds: 30),
  }) : _http = client ?? http.Client(),
       base = base ?? kBoardBase;

  final http.Client _http;

  /// The board's origin; also the `Origin` header of a POST.
  final Uri base;

  /// Longest wait for the board to catch up with the note.
  final Duration wait;

  /// Gap between two board reads while waiting.
  final Duration poll;

  /// Longest wait for the reply to a Start POST.
  final Duration startTimeout;

  static const _timeout = Duration(seconds: 10);

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

  /// Clicks Start on the note's last startable item titled [title]. With
  /// [sections], that is the note's last section (`<id8>-<sections - 1>`),
  /// which a merge just added: waits until the board shows it.
  Future<StartResult> start(
    String noteId,
    String title, {
    int? sections,
  }) async {
    try {
      final last = sections == null ? null : _item(noteId, sections - 1);
      bool seen(List<Map<String, dynamic>> cs) =>
          last == null || cs.any((c) => c['id'] == last);
      final cards = await _until(noteId, seen);
      // Exactly the merged item: never an older same-titled one, which the
      // board may list last (it orders by column, T1866).
      final card = seen(cards)
          ? cards.reversed
                .where((c) => last == null || c['id'] == last)
                .where((c) => c['title'] == title && _startable(c))
                .firstOrNull
          : null;
      if (card == null) return _no('no startable item');
      final page = await _http.get(base).timeout(_timeout);
      final token = _csrf.firstMatch(page.body)?.group(1);
      if (token == null) return _no('no CSRF token on the board page');
      final id = card['id']! as String;
      return await _post(noteId, id, token);
    } on Object catch (e) {
      return _no('board unreachable: $e');
    }
  }

  Future<StartResult> _post(String noteId, String id, String token) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            base.resolve('/api/task/$id/start'),
            headers: {'Origin': base.origin, 'X-Todoimpl-Token': token},
          )
          .timeout(startTimeout);
    } on TimeoutException catch (e) {
      // The board may still be starting it: a card that left Start took it.
      final cards = await _until(
        noteId,
        (cs) => cs.any((c) => c['id'] == id && !_startable(c)),
      );
      if (cards.any((c) => c['id'] == id && !_startable(c))) {
        return (ok: true, reason: null, item: id);
      }
      return _no('board unreachable: $e');
    }
    if (res.statusCode == 200) return (ok: true, reason: null, item: id);
    return _no('board refused start: ${res.statusCode} ${_message(res)}');
  }

  /// The note's cards once [done] holds, or the last read after [wait].
  Future<List<Map<String, dynamic>>> _until(
    String noteId,
    bool Function(List<Map<String, dynamic>>) done,
  ) async {
    final deadline = DateTime.now().add(wait);
    var cards = await _cards(noteId);
    while (!done(cards) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(poll);
      cards = await _cards(noteId);
    }
    return cards;
  }

  static String _item(String noteId, int index) =>
      '${noteId.substring(0, 8)}-$index';

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
