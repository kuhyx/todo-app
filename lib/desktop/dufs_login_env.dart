/// Reads the dufs login `add_dufs_login.sh` wrote for the desktop wrapper.
///
/// `~/src/dufs-cloud/scripts/add_dufs_login.sh todo /todo-images rw` leaves a
/// 0600 `~/.config/dufs/logins/todo.env` of `KEY=value` lines. The wrapper
/// re-reads it on every reconcile, so creating or rotating the login takes
/// effect without restarting the desktop app.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:todo/images/dufs_image_client.dart';

/// `~/.config/dufs/logins/todo.env` under [home].
String defaultDufsLoginEnvPath(String home) =>
    p.join(home, '.config', 'dufs', 'logins', 'todo.env');

/// The login in [envFile], or null when it is absent or incomplete.
DufsLogin? readDufsLoginEnv(File envFile) {
  if (!envFile.existsSync()) return null;
  final values = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    final eq = line.indexOf('=');
    if (eq <= 0 || line.startsWith('#')) continue;
    values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  final user = values['DUFS_USER'] ?? '';
  final password = values['DUFS_PASSWORD'] ?? '';
  final url = values['DUFS_URL'] ?? '';
  if (user.isEmpty || password.isEmpty || url.isEmpty) return null;
  return DufsLogin(
    user: user,
    password: password,
    baseUrl: url.endsWith('/') ? url.substring(0, url.length - 1) : url,
  );
}
