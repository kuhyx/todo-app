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
}
