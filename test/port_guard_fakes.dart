/// The FakeProbe and the ss/proc fixtures.
///
/// Shared by the files `port_guard_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

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
