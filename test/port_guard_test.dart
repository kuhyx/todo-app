import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/desktop/port_guard.dart';

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

  group('PortGuard.resolve', () {
    test('retries the bind when the port came free', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(inUse: [false]),
      );
      expect(await guard.resolve(8730), isA<BindNow>());
    });

    test('refuses when the owner cannot be identified', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(inUse: [true]),
      );
      final action = await guard.resolve(8730);
      expect(action, isA<AbortWithOwner>());
      expect(
        (action as AbortWithOwner).description,
        contains('unidentified'),
      );
    });

    test('retries when the owner exited mid-probe', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(pid: 42),
      );
      expect(await guard.resolve(8730), isA<BindNow>());
    });

    test('refuses to touch a process that is not a wrapper', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(
          pid: 42,
          description: const ProcessDescription(
            exeTarget: '/usr/bin/python3.14',
            cmdline: ['python3', '-m', 'http.server'],
          ),
        ),
      );
      final action = await guard.resolve(8730);
      expect(action, isA<AbortWithOwner>());
      expect((action as AbortWithOwner).description, contains('42'));
      expect(action.description, contains('python3.14'));
    });

    test('names the command when the executable is unreadable', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(
          pid: 42,
          description: const ProcessDescription(
            exeTarget: '',
            cmdline: ['some-daemon'],
          ),
        ),
      );
      final action = await guard.resolve(8730);
      expect((action as AbortWithOwner).description, contains('some-daemon'));
    });

    test('reports unknown when there is no command either', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(
          pid: 42,
          description: const ProcessDescription(exeTarget: '', cmdline: []),
        ),
      );
      final action = await guard.resolve(8730);
      expect((action as AbortWithOwner).description, contains('unknown'));
    });

    test('attaches when a browser window is still open', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(
          pid: 42,
          description: const ProcessDescription(
            exeTarget: '/opt/todo/bin/todo_desktop',
            cmdline: ['/opt/todo/bin/todo_desktop'],
          ),
          cmdlines: const [
            ['thorium', '--user-data-dir=$_profile'],
          ],
        ),
      );
      final action = await guard.resolve(8730);
      expect(action, isA<AttachToExisting>());
      expect((action as AttachToExisting).pid, 42);
    });

    test('reaps a wrapper with no window attached', () async {
      final guard = PortGuard(
        profileDir: _profile,
        probe: FakeProbe(
          pid: 42,
          description: const ProcessDescription(
            exeTarget: '/opt/todo/bin/todo_desktop',
            cmdline: ['/opt/todo/bin/todo_desktop'],
          ),
        ),
      );
      final action = await guard.resolve(8730);
      expect(action, isA<ReapThenBind>());
      expect((action as ReapThenBind).pid, 42);
    });

    test('defaults to the real host probe', () {
      expect(PortGuard(profileDir: _profile).probe, isA<LinuxSystemProbe>());
    });
  });

  group('PortGuard.reap', () {
    test('stops at SIGTERM when the port comes free', () async {
      final probe = FakeProbe(freeAfter: ProcessSignal.sigterm);
      final guard = PortGuard(profileDir: _profile, probe: probe);
      expect(await _reap(guard, 42, 8730), isTrue);
      expect(probe.signalsSent, [ProcessSignal.sigterm]);
    });

    test('escalates to SIGKILL when SIGTERM is ignored', () async {
      // Busy for the whole SIGTERM wait, free once SIGKILL lands.
      final probe = FakeProbe(freeAfter: ProcessSignal.sigkill);
      final guard = PortGuard(profileDir: _profile, probe: probe);
      expect(await _reap(guard, 42, 8730), isTrue);
      expect(probe.signalsSent, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
    });

    test('reports failure when the port never comes free', () async {
      final probe = FakeProbe(inUse: [true]);
      final guard = PortGuard(profileDir: _profile, probe: probe);
      expect(await _reap(guard, 42, 8730), isFalse);
      expect(probe.signalsSent, [
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
    });
  });

  group('LinuxSystemProbe against the real host', () {
    test('portInUse tracks a real socket', () async {
      const probe = LinuxSystemProbe();
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => socket.close());
      expect(await probe.portInUse(socket.port), isTrue);
      await socket.close();
      expect(await probe.portInUse(socket.port), isFalse);
    });

    test('listenerPid finds this process holding a real port', () async {
      const probe = LinuxSystemProbe();
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => socket.close());
      // Proves the parser works against genuine `ss` output, not a fixture.
      expect(await probe.listenerPid(socket.port), pid);
    });

    test('listenerPid returns null when ss is unavailable', () async {
      const probe = LinuxSystemProbe(ssExecutable: 'ss-does-not-exist');
      expect(await probe.listenerPid(8730), isNull);
    });

    test('describe reads this process', () async {
      const probe = LinuxSystemProbe();
      final description = await probe.describe(pid);
      expect(description, isNotNull);
      expect(description!.cmdline, isNotEmpty);
      expect(description.exeTarget, isNotEmpty);
    });

    test('describe tolerates an unreadable executable link', () async {
      // pid 1 belongs to root: its cmdline is world-readable but /proc/1/exe
      // is not, which is the branch under test.
      const probe = LinuxSystemProbe();
      final description = await probe.describe(1);
      expect(description, isNotNull);
      expect(description!.exeTarget, isEmpty);
    });

    test('describe returns null for a process that does not exist', () async {
      const probe = LinuxSystemProbe();
      expect(await probe.describe(0x7FFFFFFF), isNull);
    });

    test('processCmdlines lists real processes', () async {
      const probe = LinuxSystemProbe();
      final cmdlines = await probe.processCmdlines();
      expect(cmdlines, isNotEmpty);
    });

    test('signal terminates a real child process', () async {
      const probe = LinuxSystemProbe();
      final child = await Process.start('sleep', ['30']);
      expect(probe.signal(child.pid, ProcessSignal.sigterm), isTrue);
      expect(await child.exitCode, isNot(0));
    });
  });
}
