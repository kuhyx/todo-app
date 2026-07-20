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

  // `dart build cli` emits bundle/bin/<exe> alongside bundle/lib/, so the
  // installed layout is /opt/todo/bin/todo-desktop with the web assets one
  // level up at /opt/todo/web. --web-root overrides for development runs
  // straight out of the repo.
  final webRoot = _argValue(args, '--web-root') ??
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '..', 'web'));
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

  // A bare flag, not a valued option: requiring a dummy value meant passing a
  // stray positional, which the AOT runtime tries to interpret as a snapshot.
  if (!args.contains('--no-browser')) {
    final ranLongEnough = await _launchBrowser(home);
    if (!ranLongEnough) {
      // Chrome exits immediately when it hands the URL to an instance that
      // already owns the profile directory (or when a stale SingletonLock is
      // left behind). Shutting down here would pull the server out from under
      // a window that is still open, so keep serving instead.
      stdout.writeln(
        'Browser returned immediately (handed off to an existing window). '
        'Still serving on http://localhost:$_port — Ctrl-C to stop.',
      );
      return;
    }
    // Otherwise the browser owned the session: its window closed, so we exit.
    await server.stop();
  }
}

/// Launches the app in a Chrome-family browser with a **stable** profile
/// directory, since the token and notes live in that profile.
/// Returns true when the browser ran long enough to have owned the session.
Future<bool> _launchBrowser(String home) async {
  // Ordered by preference, and deliberately broad: this machine runs Thorium
  // behind /opt/google/chrome, and has a policy that uninstalls the `chromium`
  // package, so assuming any single browser is wrong. TODO_BROWSER overrides.
  final candidates = [
    Platform.environment['TODO_BROWSER'] ?? '',
    '/opt/google/chrome/chrome',
    '/opt/thorium-browser/thorium-browser',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/brave',
  ];
  final browser = candidates.firstWhere(
    (path) => path.isNotEmpty && File(path).existsSync(),
    orElse: () => '',
  );
  if (browser.isEmpty) {
    stderr.writeln('No Chrome-family browser found; open '
        'http://localhost:$_port manually.');
    return false;
  }
  // The profile directory must stay stable: the GitHub token (localStorage)
  // and the notes (IndexedDB) live inside it, so a changing path silently
  // logs the user out and hides their notes.
  final profile = p.join(home, '.local', 'share', 'todo-desktop', 'profile');
  final process = await Process.start(browser, [
    '--app=http://localhost:$_port',
    '--user-data-dir=$profile',
    // Sets WM_CLASS, which the .desktop entry matches on via StartupWMClass.
    // Without it the window inherits the browser's class and the taskbar shows
    // a browser icon instead of todo's.
    '--class=todo',
    '--no-first-run',
  ]);

  final started = DateTime.now();
  await process.exitCode;
  return DateTime.now().difference(started) > const Duration(seconds: 5);
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
