/// The headless CLI's Firebase session, kept in a file of its own.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';

/// A file-backed [FirebaseCredentialStore], seeded once from [seedFile].
///
/// [seedFile] is todo's desktop session (`~/.config/todo/firebase_auth.json`,
/// written by `crdt-sync/tool/seed_session.py --app todo`) and is only ever
/// read. Every write goes to [file], a private copy in the CLI's data dir.
/// That split matters: [FirebaseTokenProvider] clears its store when a refresh
/// token is revoked, and a shared file would let one bad CLI run delete the
/// seed the desktop wrapper provisions itself from.
class FileCredentialStore implements FirebaseCredentialStore {
  /// Creates a store that persists to [file], falling back to [seedFile].
  FileCredentialStore({required this.file, required this.seedFile});

  /// The CLI's own copy, written on every token refresh.
  final File file;

  /// The read-only seed used until [file] exists.
  final File seedFile;

  @override
  Future<FirebaseCredentials?> load() async {
    final source = file.existsSync() ? file : seedFile;
    if (!source.existsSync()) return null;
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    return FirebaseCredentials.fromJson(decoded);
  }

  @override
  Future<void> save(FirebaseCredentials credentials) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.$pid.tmp');
    // Owner-only before the token is written, not after: dart:io has no
    // chmod, and a umask-default file would briefly expose a DB credential.
    await tmp.writeAsString('');
    await Process.run('chmod', ['600', tmp.path]);
    await tmp.writeAsString(jsonEncode(credentials.toJson()));
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    if (file.existsSync()) await file.delete();
  }
}
