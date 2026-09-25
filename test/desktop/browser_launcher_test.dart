import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/desktop/browser_launcher.dart';

void main() {
  group('browserArgs', () {
    final args = browserArgs('/h');

    test('opens the wrapper as an app window in the fixed profile', () {
      expect(args, contains('--app=http://localhost:$kWrapperPort'));
      expect(
        args,
        contains('--user-data-dir=/h/.local/share/todo-desktop/profile'),
      );
      expect(args, contains('--class=todo'));
    });

    test('keeps Chrome off the keyring, whose lock blanks the window', () {
      expect(args, contains('--password-store=basic'));
    });
  });

  group('findBrowser', () {
    test('an override that exists wins', () {
      expect(findBrowser(override: '/x/b', exists: (_) => true), '/x/b');
    });

    test('falls through to the first installed candidate', () {
      expect(
        findBrowser(
          override: '',
          exists: (p) => p == '/usr/bin/google-chrome-stable',
        ),
        '/usr/bin/google-chrome-stable',
      );
    });

    test("returns '' when nothing is installed", () {
      expect(findBrowser(override: '', exists: (_) => false), '');
    });

    test(r'defaults to $TODO_BROWSER and real files', () {
      expect(findBrowser(), isA<String>());
    });
  });

  group('launchBrowser', () {
    test('defaults to the browser findBrowser picks', () async {
      final expected = findBrowser();
      String? exe;
      await launchBrowser(
        '/h',
        start: (e, _) {
          exe = e;
          return Process.start('true', []);
        },
      );
      expect(exe, expected.isEmpty ? isNull : expected);
    });

    test('without a browser it reports false and starts nothing', () async {
      var started = false;
      final ok = await launchBrowser(
        '/h',
        browser: '',
        start: (_, _) async {
          started = true;
          return Process.start('true', []);
        },
      );
      expect(ok, isFalse);
      expect(started, isFalse);
    });

    test(
      'starts the browser with browserArgs; a quick exit is false',
      () async {
        String? exe;
        List<String>? passed;
        final ok = await launchBrowser(
          '/h',
          browser: '/x/chrome',
          start: (e, a) {
            exe = e;
            passed = a;
            return Process.start('true', []);
          },
        );
        expect(exe, '/x/chrome');
        expect(passed, browserArgs('/h'));
        expect(ok, isFalse, reason: 'ran under 5 s: did not own the session');
      },
    );
  });
}
