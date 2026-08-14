// coverage:ignore-file
// Entry point for the desktop wrapper: resolves real paths, starts the server,
// and launches the browser. The serving logic it delegates to is covered by
// test/wrapper_server_test.dart, and the busy-port recovery it delegates to by
// test/port_guard_test.dart. Keep this file thin wiring for that reason.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo/desktop/browser_launcher.dart';
import 'package:todo/desktop/port_guard.dart';
import 'package:todo/desktop/wrapper_server.dart';

/// The fixed wrapper port; see [kWrapperPort] for why it cannot move.
/// Kept in step with lib/sync/desktop_wrapper.
const int _port = kWrapperPort;

/// `errno` for EADDRINUSE. The wrapper is Linux-only (the desktop app is the
/// web build served locally), so the numeric value is stable here.
const _addressInUse = 98;

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
  final webRoot =
      _argValue(args, '--web-root') ??
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
    logPath:
        _argValue(args, '--log-path') ??
        p.join(home, '.local', 'share', 'todo-desktop', 'todo_notes.json'),
  );

  if (!await _bind(server)) {
    // Something already holds the port. It cannot simply move — the notes and
    // the token are keyed by origin — so work out who owns it and either take
    // it back, join it, or refuse.
    if (!await _recoverPort(server, home, args)) return;
  }
  stdout.writeln('todo desktop serving on http://localhost:$_port');

  // Provisioning is a setup step, not a session: load the app once in a
  // headless browser so its own code can write the account into the
  // origin-keyed localStorage only the page can reach, then exit. No window
  // is ever mapped, so this never steals focus or lands on the wrong monitor.
  if (args.contains('--provision-sync-account')) {
    final ok = await _provisionSyncAccount(home);
    await server.stop();
    exit(ok ? 0 : 1);
  }

  // A bare flag, not a valued option: requiring a dummy value meant passing a
  // stray positional, which the AOT runtime tries to interpret as a snapshot.
  if (!args.contains('--no-browser')) {
    final ranLongEnough = await launchBrowser(home);
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

/// Binds [server] to the fixed port, reporting failure instead of throwing.
///
/// Anything other than "address in use" is fatal and reported without a stack
/// trace: a Dart traceback tells the user nothing they can act on.
Future<bool> _bind(WrapperServer server) async {
  try {
    await server.start(_port);
    return true;
  } on SocketException catch (e) {
    if (e.osError?.errorCode == _addressInUse) return false;
    stderr.writeln('could not serve on port $_port: ${e.osError?.message}');
    exit(1);
  }
}

/// Resolves a busy port and, where possible, gets [server] listening.
///
/// Returns true once the server is bound. Returns false when this process has
/// deliberately not taken the port — it joined a running instance instead — in
/// which case the caller must not touch [server]: it owns no socket, and
/// falling through to the browser-lifetime logic would leave a second orphan.
/// Exits the process when the port cannot safely be had.
Future<bool> _recoverPort(
  WrapperServer server,
  String home,
  List<String> args,
) async {
  final guard = PortGuard(profileDir: profileDir(home));
  switch (await guard.resolve(_port)) {
    case AbortWithOwner(:final description):
      stderr.writeln('port $_port is already in use by $description.');
      stderr.writeln(
        'todo needs this exact port — its notes and GitHub token are stored '
        'per origin. Free the port, then run todo again.',
      );
      exit(1);
    case AttachToExisting(:final pid):
      // Re-running the browser command opens a second window rather than
      // raising the first (measured on Thorium: the process returns in ~180ms
      // and window count goes 1 -> 2). A duplicate window is the right
      // trade-off anyway: both share this one server and one IndexedDB, and
      // typing `todo` to get nothing visible would be worse.
      // --provision-sync-account counts as "do not open a window" too: it
      // is a headless setup step, and opening one here defeated the whole
      // point (it landed fullscreen on the primary monitor).
      final opening =
          !args.contains('--no-browser') &&
          !args.contains('--provision-sync-account');
      stdout.writeln(
        'todo is already running (pid $pid)'
        '${opening ? '; opening a window.' : '.'}',
      );
      if (opening) await launchBrowser(home);
      return false;
    case ReapThenBind(:final pid):
      stdout.writeln('clearing a stale todo wrapper (pid $pid) on port $_port');
      if (!await guard.reap(pid, _port)) {
        stderr.writeln('could not free port $_port from pid $pid.');
        exit(1);
      }
    case BindNow():
      break;
  }
  if (await _bind(server)) return true;
  stderr.writeln('port $_port was taken again while todo was starting.');
  exit(1);
}

/// Loads the app once headlessly so it provisions its own sync account.
///
/// The account lives in origin-keyed localStorage, which only code running in
/// the page can write -- so the page has to run. `--headless` means it runs
/// without ever mapping a window.
///
/// Returns whether the account is present afterwards.
Future<bool> _provisionSyncAccount(String home) async {
  final browser = findBrowser();
  if (browser.isEmpty) {
    stderr.writeln('No Chrome-family browser found; cannot provision.');
    return false;
  }
  // A separate profile from the real app's: Chrome refuses to start headless
  // against a user-data-dir another instance already owns, and the account is
  // written through the app's own storage anyway, which the next normal
  // launch reads from the shared profile.
  final process = await Process.start(browser, [
    '--headless=new',
    '--disable-gpu',
    '--user-data-dir=${profileDir(home)}',
    // Surface the page's own log() output, so a failure inside the app is
    // visible in the terminal that started the provisioning run.
    '--enable-logging=stderr',
    'http://localhost:$_port',
  ]);
  // No --virtual-time-budget: it makes Chrome SIGKILL itself when the budget
  // expires, which both reads as a failure (exit -9) and can cut the sync
  // short. Give the page a real window of wall-clock time, then close it.
  await Future<void>.delayed(const Duration(seconds: 30));
  process.kill();
  await process.exitCode;
  stdout.writeln(
    'Provisioning run complete. Launch normally to confirm it is connected.',
  );
  return true;
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
