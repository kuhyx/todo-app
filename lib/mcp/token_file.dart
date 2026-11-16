import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';

/// sha256 hex of [token] (crdt_sync's `revisionOf` is exactly that).
String tokenHash(String token) => revisionOf(token);

/// What the tokens file says about one `Authorization` header.
enum TokenVerdict {
  /// A listed token: let the request in.
  accepted,

  /// Missing, malformed or unlisted: HTTP 403.
  rejected,

  /// No token set has ever loaded, so nothing can be judged: HTTP 503.
  unavailable,
}

/// The sha256-hashed bearer tokens of [file], loaded once.
///
/// A request costs one `stat`; the file is re-read only when its mtime or
/// size changed. A failed read keeps the last good set (an exhausted fd table
/// once made every valid token read as "no tokens", i.e. 403) and is logged
/// once per distinct error. Until a first good load every well-formed bearer
/// is [TokenVerdict.unavailable], never a refusal.
class TokenStore {
  /// Watches [file]; [log] gets read errors.
  TokenStore(this.file, {required this.log});

  /// The `<sha256> <name>` lines, `#` comments allowed.
  final File file;

  /// Receives read errors, one line each.
  final void Function(String) log;

  Set<String>? _hashes;
  (DateTime, int)? _seen;
  String? _lastError;

  /// Judges [authorization] (an `Authorization` header value or null).
  TokenVerdict verdict(String? authorization) {
    const scheme = 'bearer ';
    if (authorization == null ||
        !authorization.toLowerCase().startsWith(scheme)) {
      return TokenVerdict.rejected;
    }
    final token = authorization.substring(scheme.length).trim();
    if (token.isEmpty) return TokenVerdict.rejected;
    _refresh();
    final hashes = _hashes;
    if (hashes == null) return TokenVerdict.unavailable;
    return hashes.contains(tokenHash(token))
        ? TokenVerdict.accepted
        : TokenVerdict.rejected;
  }

  void _refresh() {
    try {
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        throw FileSystemException('no such file', file.path);
      }
      final key = (stat.modified, stat.size);
      if (key == _seen) return;
      _hashes = _parse(file.readAsStringSync());
      _seen = key;
      _lastError = null;
    } on FileSystemException catch (e) {
      // Keep the last good set; `_seen` stays, so the next request retries.
      final message = '${e.message} ${e.path} ${e.osError?.errorCode}';
      if (message != _lastError) log('tokens: keeping last set: $message');
      _lastError = message;
    }
  }

  static Set<String> _parse(String text) => {
    for (final line in text.split('\n'))
      if (line.trim() case final t when t.isNotEmpty && !t.startsWith('#'))
        t.split(RegExp(r'\s+')).first.toLowerCase(),
  };
}
