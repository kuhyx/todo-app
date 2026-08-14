/// Finding and launching the Chrome window the desktop app runs in.
///
/// Split out of `bin/todo_desktop.dart` for file size. The profile directory
/// is fixed on purpose: the GitHub token (localStorage) and the notes
/// (IndexedDB) are keyed by origin and live in that profile, so a moving
/// profile dir would silently log the user out and hide their notes.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Port must stay fixed: the browser keys `localStorage` (the GitHub token)
/// and IndexedDB (the notes) by origin, so a different port looks like a
/// different app with no token and no notes.
const kWrapperPort = 8730;

/// Browser profile directory for the desktop app.
///
/// Must stay stable: the GitHub token (localStorage) and the notes (IndexedDB)
/// live inside it, so a changing path silently logs the user out and hides
/// their notes. It doubles as the marker for "a window is still attached".
String profileDir(String home) =>
    p.join(home, '.local', 'share', 'todo-desktop', 'profile');

/// Returns the first Chrome-family browser on this machine, or ''.
String findBrowser() {
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
  return candidates.firstWhere(
    (path) => path.isNotEmpty && File(path).existsSync(),
    orElse: () => '',
  );
}

/// Launches the app in a Chrome-family browser with a **stable** profile
/// directory, since the token and notes live in that profile.
///
/// Returns true when the browser ran long enough to have owned the session.
Future<bool> launchBrowser(String home) async {
  final browser = findBrowser();
  if (browser.isEmpty) {
    stderr.writeln(
      'No Chrome-family browser found; open '
      'http://localhost:$kWrapperPort manually.',
    );
    return false;
  }
  final process = await Process.start(browser, [
    '--app=http://localhost:$kWrapperPort',
    '--user-data-dir=${profileDir(home)}',
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
