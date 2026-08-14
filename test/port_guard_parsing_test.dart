import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/desktop/port_guard.dart';

import 'port_guard_fakes.dart';

/// Real `ss -tlnp` output, including the header row and the run-together
/// `Peer Address:PortProcess` column that iproute2 actually prints.
const _ssOutput = '''
State  Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess
LISTEN 0      4096         0.0.0.0:5355       0.0.0.0:*
LISTEN 0      128        127.0.0.1:8730       0.0.0.0:*    users:(("dart:todo_deskt",pid=61687,fd=7))
LISTEN 0      511        127.0.0.1:9000       0.0.0.0:*    users:(("node",pid=1234,fd=20))
''';

/// A [SystemProbe] whose every answer is scripted by the test.
class FakeProbe implements SystemProbe {
  FakeProbe({
    this.pid,
    this.description,
    this.cmdlines = const [],
    this.inUse = const [true],
    this.freeAfter,
  });

  int? pid;
  ProcessDescription? description;
  List<List<String>> cmdlines;

  /// Answers for successive [portInUse] calls; the last one repeats.
  List<bool> inUse;

  /// When set, the port frees only once this signal has been delivered.
  ///
  /// Keyed on the signal rather than on elapsed time so the escalation test
  /// cannot flake on a slow machine.
  ProcessSignal? freeAfter;

  final List<ProcessSignal> signalsSent = [];
  int portInUseCalls = 0;

  @override
  Future<int?> listenerPid(int port) async => pid;

  @override
  Future<ProcessDescription?> describe(int pid) async => description;

  @override
  Future<List<List<String>>> processCmdlines() async => cmdlines;

  @override
  Future<bool> portInUse(int port) async {
    portInUseCalls++;
    if (freeAfter != null) return !signalsSent.contains(freeAfter);
    return inUse[(portInUseCalls - 1).clamp(0, inUse.length - 1)];
  }

  @override
  bool signal(int pid, ProcessSignal signal) {
    signalsSent.add(signal);
    return true;
  }
}

const _profile = '/home/kuchy/.local/share/todo-desktop/profile';

/// Fast timings so the reap tests do not slow the suite down.
Future<bool> _reap(PortGuard guard, int pid, int port) => guard.reap(
  pid,
  port,
  termWait: const Duration(milliseconds: 60),
  killWait: const Duration(milliseconds: 60),
  pollInterval: const Duration(milliseconds: 5),
);

void main() {
  group('parseListenerPid', () {
    test('finds the pid holding the requested port', () {
      expect(parseListenerPid(_ssOutput, 8730), 61687);
      expect(parseListenerPid(_ssOutput, 9000), 1234);
    });

    test('returns null when no line listens on the port', () {
      expect(parseListenerPid(_ssOutput, 7777), isNull);
    });

    test('returns null when ss hides the owning pid', () {
      // ss omits the users:(...) column for another user's socket.
      const hidden = 'LISTEN 0 128 127.0.0.1:8730 0.0.0.0:*';
      expect(parseListenerPid(hidden, 8730), isNull);
    });

    test('ignores short and empty lines', () {
      expect(parseListenerPid('\nLISTEN 0 128\n', 8730), isNull);
    });

    test('does not match a port that is only a suffix', () {
      const other =
          'LISTEN 0 128 127.0.0.1:18730 0.0.0.0:* '
          'users:(("x",pid=5,fd=7))';
      expect(parseListenerPid(other, 8730), isNull);
    });
  });

  group('isTodoWrapper', () {
    test('accepts the installed binary', () {
      expect(isTodoWrapper('/opt/todo/bin/todo_desktop', []), isTrue);
    });

    test('accepts a binary replaced by an upgrade', () {
      expect(
        isTodoWrapper('/opt/todo/bin/todo_desktop (deleted)', []),
        isTrue,
      );
    });

    test('accepts a development run out of the repo', () {
      expect(
        isTodoWrapper('/usr/lib/dart/bin/dart', [
          'dart',
          'run',
          'bin/todo_desktop.dart',
          '--web-root',
          'build/web',
        ]),
        isTrue,
      );
    });

    test('rejects an unrelated process', () {
      expect(
        isTodoWrapper('/usr/bin/python3.14', [
          'python3',
          '-m',
          'http.server',
          '8730',
        ]),
        isFalse,
      );
    });
  });

  group('hasWindowAttached', () {
    // Chrome rewrites argv into one space-joined string, so this is the shape
    // that actually appears in /proc for a browser window.
    const collapsed = [
      '/opt/thorium-browser/thorium --app=http://localhost:8730 '
          '--user-data-dir=$_profile --class=todo --no-first-run',
    ];

    test('matches a browser whose argv collapsed into one token', () {
      expect(hasWindowAttached([collapsed], _profile), isTrue);
    });

    test('matches a normally separated argument vector', () {
      expect(
        hasWindowAttached(
          [
            ['thorium', '--user-data-dir=$_profile', '--class=todo'],
          ],
          _profile,
        ),
        isTrue,
      );
    });

    test('matches when the flag is the final argument', () {
      expect(
        hasWindowAttached(
          [
            ['thorium', '--user-data-dir=$_profile'],
          ],
          _profile,
        ),
        isTrue,
      );
    });

    test('does not match a sibling profile directory', () {
      expect(
        hasWindowAttached(
          [
            ['thorium', '--user-data-dir=${_profile}2'],
          ],
          _profile,
        ),
        isFalse,
      );
    });

    test('does not match when no process mentions the profile', () {
      expect(
        hasWindowAttached(
          [
            ['bash', '-c', 'sleep 1'],
          ],
          _profile,
        ),
        isFalse,
      );
    });
  });
}
