// coverage:ignore-file
// Entry point for the desktop wrapper: resolves real paths, starts the server,
// and launches the browser. The serving logic it delegates to is covered by
// test/wrapper_server_test.dart.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo/desktop/wrapper_server.dart';

/// Port must stay fixed: the browser keys `localStorage` (the GitHub token) and
/// IndexedDB (the notes) by origin, so a different port looks like a different
/// app with no token and no notes. Kept in step with lib/sync/desktop_wrapper.
const _port = 8730;

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('HOME is not set; cannot resolve the backlog path.');
    exit(1);
  }

  // Assets sit next to this executable when installed; --web-root overrides for
  // development runs straight out of the repo.
  final webRoot = _argValue(args, '--web-root') ??
      p.join(p.dirname(Platform.resolvedExecutable), 'web');
  if (!Directory(webRoot).existsSync()) {
    stderr.writeln('web assets not found at $webRoot');
    exit(1);
  }

  // Overridable so a verification run cannot point at the real backlog: an
  // app that starts with an empty store would export over it.
  final server = WrapperServer(
    webRoot: webRoot,
    backlogPath:
        _argValue(args, '--backlog-path') ?? p.join(home, 'todo', 'BACKLOG.md'),
    logPath: _argValue(args, '--log-path') ??
        p.join(home, '.local', 'share', 'todo-desktop', 'todo_notes.json'),
  );
  await server.start(_port);
  stdout.writeln('todo desktop serving on http://localhost:$_port');

  if (_argValue(args, '--no-browser') == null) {
    await _launchBrowser(home);
    // The browser owns the session: when its window closes, so does the app.
    await server.stop();
  }
}

/// Launches the app in a Chrome-family browser with a **stable** profile
/// directory, since the token and notes live in that profile.
Future<void> _launchBrowser(String home) async {
  const candidates = [
    '/opt/google/chrome/chrome',
    '/usr/bin/chromium',
    '/usr/bin/google-chrome-stable',
  ];
  final browser = candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => '',
  );
  if (browser.isEmpty) {
    stderr.writeln('No Chrome-family browser found; open '
        'http://localhost:$_port manually.');
    return;
  }
  final profile = p.join(home, '.local', 'share', 'todo-desktop', 'profile');
  final process = await Process.start(browser, [
    '--app=http://localhost:$_port',
    '--user-data-dir=$profile',
    '--no-first-run',
  ]);
  await process.exitCode;
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
