import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';

/// sha256 hex of [token] (crdt_sync's `revisionOf` is exactly that).
String tokenHash(String token) => revisionOf(token);

Set<String> _hashes(File tokens) {
  final String text;
  try {
    text = tokens.readAsStringSync();
  } on FileSystemException {
    return const {};
  }
  return {
    for (final line in text.split('\n'))
      if (line.trim() case final t when t.isNotEmpty && !t.startsWith('#'))
        t.split(RegExp(r'\s+')).first.toLowerCase(),
  };
}

/// Whether [authorization] bears a token hashed in [tokens], read per call.
bool tokenAccepted(File tokens, String? authorization) {
  const scheme = 'bearer ';
  if (authorization == null ||
      !authorization.toLowerCase().startsWith(scheme)) {
    return false;
  }
  final token = authorization.substring(scheme.length).trim();
  return token.isNotEmpty && _hashes(tokens).contains(tokenHash(token));
}
