import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// NUL separates the arguments inside `/proc/<pid>/cmdline`.
final String _argumentSeparator = String.fromCharCode(0);

/// What the launcher should do when the fixed wrapper port is already bound.
///
/// The port cannot move — the browser keys `localStorage` (the GitHub token)
/// and IndexedDB (the notes) by origin, so falling back to a free port would
/// silently present an empty, logged-out app. The only options are therefore to
/// take the port back, share the server that already owns it, or refuse.
sealed class PortAction {
  /// Allows subclasses to be const.
  const PortAction();
}

/// The port came free between the failed bind and the probe: just bind again.
final class BindNow extends PortAction {
  /// Creates the retry action.
  const BindNow();
}

/// A todo wrapper is serving and a browser window is still attached to it.
///
/// Reaping here would pull the server out from under a window the user is
/// looking at, so the launcher joins the running instance instead.
final class AttachToExisting extends PortAction {
  /// Creates the attach action for the wrapper running as [pid].
  const AttachToExisting(this.pid);

  /// Process id of the wrapper already serving the port.
  final int pid;
}

/// A todo wrapper is serving with no window attached — a leftover from an
/// earlier session, safe to terminate so the current build can take over.
final class ReapThenBind extends PortAction {
  /// Creates the reap action for the stale wrapper running as [pid].
  const ReapThenBind(this.pid);

  /// Process id of the stale wrapper holding the port.
  final int pid;
}

/// The port is held by something this launcher must not kill.
final class AbortWithOwner extends PortAction {
  /// Creates the abort action, describing the owner for the error message.
  const AbortWithOwner(this.description);

  /// Human-readable description of the owning process.
  final String description;
}

/// Identifying details of a running process, as read from `/proc`.
class ProcessDescription {
  /// Creates a description from an executable path and an argument vector.
  const ProcessDescription({required this.exeTarget, required this.cmdline});

  /// Target of `/proc/<pid>/exe`; empty when it could not be read.
  ///
  /// Carries a ` (deleted)` suffix when the binary was replaced underneath the
  /// running process — exactly what an upgrade leaves behind.
  final String exeTarget;

  /// Argument vector, already split on the NUL separators `/proc` uses.
  final List<String> cmdline;
}

/// Read-only view of the host that [PortGuard] reasons about.
///
/// Injectable so the decision logic can be tested without live processes.
abstract interface class SystemProbe {
  /// Process id listening on [port], or null when it cannot be determined.
  Future<int?> listenerPid(int port);

  /// Describes [pid], or null when the process is gone.
  Future<ProcessDescription?> describe(int pid);

  /// Argument vectors of every process readable by this user.
  Future<List<List<String>>> processCmdlines();

  /// Whether [port] currently refuses a loopback bind.
  Future<bool> portInUse(int port);

  /// Sends [signal] to [pid]; returns whether the signal was delivered.
  bool signal(int pid, ProcessSignal signal);
}

/// Extracts the process id listening on [port] from `ss -tlnp` output.
///
/// Returns null when no line matches or the owning pid is hidden, which `ss`
/// does for sockets belonging to other users.
int? parseListenerPid(String ssOutput, int port) {
  for (final line in const LineSplitter().convert(ssOutput)) {
    final fields = line
        .split(RegExp(r'\s+'))
        .where((f) => f.isNotEmpty)
        .toList();
    if (fields.length < 4) continue;
    // Field 3 is `Local Address:Port`. Matching on the port alone (rather than
    // the address too) keeps IPv6 and wildcard listeners in scope; a wrong
    // guess is harmless because the caller still has to prove the process is
    // a wrapper of this app before it may kill anything.
    if (!fields[3].endsWith(':$port')) continue;
    final pid = RegExp(r'pid=(\d+)').firstMatch(line)?.group(1);
    if (pid != null) return int.parse(pid);
  }
  return null;
}

/// Whether the process described by [exeTarget] and [cmdline] is a wrapper.
///
/// Matches both the installed AOT binary (`/opt/todo/bin/todo_desktop`, with or
/// without the ` (deleted)` suffix an upgrade leaves) and a development run out
/// of the repo (`dart run bin/todo_desktop.dart`, as `run.sh` starts it).
bool isTodoWrapper(String exeTarget, List<String> cmdline) {
  final exe = p.basename(exeTarget.replaceAll(' (deleted)', ''));
  if (exe == 'todo_desktop') return true;
  // A plain substring match is deliberate. It is only ever asked about the
  // process holding the wrapper port, which no unrelated program does, so the
  // looser test cannot reach a bystander — whereas a stricter one would refuse
  // to reap a wrapper whose argument vector does not split the way we expect,
  // leaving the user unable to start the app at all.
  return cmdline.join(' ').contains('todo_desktop');
}

/// Whether any process in [cmdlines] is a browser holding [profileDir] open.
///
/// A live window is the one thing that makes reaping the port owner harmful, so
/// this is the discriminator between "stale leftover" and "in use".
///
/// Chrome rewrites its own argument vector into one space-joined string, so
/// `/proc/<pid>/cmdline` for a browser has no NUL separators at all and the
/// flag has to be found inside a token rather than as one. Getting this wrong
/// is asymmetric: a false negative kills the server under a window the user is
/// using, while a false positive merely opens an extra window, so this errs
/// towards detecting attachment.
bool hasWindowAttached(Iterable<List<String>> cmdlines, String profileDir) {
  final flag = '--user-data-dir=$profileDir';
  return cmdlines.any((tokens) {
    final joined = tokens.join(' ');
    final start = joined.indexOf(flag);
    if (start == -1) return false;
    // Require a boundary so a sibling profile (`…/profile2`) cannot match.
    final end = start + flag.length;
    return end == joined.length || joined[end] == ' ';
  });
}

/// Decides how the launcher should react to a busy wrapper port, and carries
/// out the termination when the owner turns out to be stale.
///
/// Fails closed throughout: anything it cannot positively identify as a todo
/// wrapper is reported rather than killed.
class PortGuard {
  /// Creates a guard for the browser profile at [profileDir].
  PortGuard({required this.profileDir, SystemProbe? probe})
    : probe = probe ?? const LinuxSystemProbe();

  /// Browser profile directory whose presence in a command line means a window
  /// is still attached to the running wrapper.
  final String profileDir;

  /// Host probe used to identify the port owner.
  final SystemProbe probe;

  /// Determines what to do about [port] after a bind failed.
  Future<PortAction> resolve(int port) async {
    final pid = await probe.listenerPid(port);
    if (pid == null) {
      // Either the owner released the port, or `ss` hid it because it belongs
      // to another user. Only the former is safe to retry.
      return await probe.portInUse(port)
          ? const AbortWithOwner(
              'an unidentified process (it may belong to another user)',
            )
          : const BindNow();
    }
    final description = await probe.describe(pid);
    // The process exited while we were looking at it.
    if (description == null) return const BindNow();
    if (!isTodoWrapper(description.exeTarget, description.cmdline)) {
      final exe = description.exeTarget.isEmpty
          ? description.cmdline.firstOrNull ?? 'unknown'
          : description.exeTarget;
      return AbortWithOwner('pid $pid ($exe)');
    }
    return hasWindowAttached(await probe.processCmdlines(), profileDir)
        ? AttachToExisting(pid)
        : ReapThenBind(pid);
  }

  /// Terminates [pid] and waits for [port] to come free.
  ///
  /// Escalates from `SIGTERM` to `SIGKILL` rather than waiting indefinitely.
  /// The wrapper needs no graceful shutdown: it holds no unflushed state, since
  /// every `/backup/*` write completes within its request.
  ///
  /// Returns whether [port] was actually released.
  Future<bool> reap(
    int pid,
    int port, {
    Duration termWait = const Duration(seconds: 3),
    Duration killWait = const Duration(seconds: 2),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    probe.signal(pid, ProcessSignal.sigterm);
    if (await _awaitFreePort(port, termWait, pollInterval)) return true;
    probe.signal(pid, ProcessSignal.sigkill);
    return _awaitFreePort(port, killWait, pollInterval);
  }

  Future<bool> _awaitFreePort(
    int port,
    Duration limit,
    Duration pollInterval,
  ) async {
    final deadline = DateTime.now().add(limit);
    do {
      if (!await probe.portInUse(port)) return true;
      await Future<void>.delayed(pollInterval);
    } while (DateTime.now().isBefore(deadline));
    return !await probe.portInUse(port);
  }
}

/// [SystemProbe] backed by `ss` and `/proc`.
///
/// The desktop wrapper only ever runs on Linux — the desktop app is the web
/// build served locally — so reading `/proc` directly is safe here.
class LinuxSystemProbe implements SystemProbe {
  /// Creates the default host probe.
  ///
  /// [ssExecutable] exists so a test can point at a missing binary and exercise
  /// the "no `ss` on PATH" path.
  const LinuxSystemProbe({this.ssExecutable = 'ss'});

  /// Name of the socket-listing tool used to find the port owner.
  final String ssExecutable;

  @override
  Future<int?> listenerPid(int port) async {
    try {
      final result = await Process.run(ssExecutable, ['-tlnp']);
      final out = result.stdout;
      return out is String ? parseListenerPid(out, port) : null;
    } on ProcessException {
      // No `ss` on PATH: report "unknown" and let the caller fail closed.
      return null;
    }
  }

  @override
  Future<ProcessDescription?> describe(int pid) async {
    final cmdline = readCmdline(pid);
    if (cmdline == null) return null;
    String exe;
    try {
      exe = Link('/proc/$pid/exe').targetSync();
    } on FileSystemException {
      // Unreadable for another user's process; the cmdline still identifies it.
      exe = '';
    }
    return ProcessDescription(exeTarget: exe, cmdline: cmdline);
  }

  @override
  Future<List<List<String>>> processCmdlines() async {
    final cmdlines = <List<String>>[];
    for (final entry in Directory('/proc').listSync()) {
      final pid = int.tryParse(p.basename(entry.path));
      if (pid == null) continue;
      final cmdline = readCmdline(pid);
      if (cmdline != null) cmdlines.add(cmdline);
    }
    return cmdlines;
  }

  @override
  Future<bool> portInUse(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return false;
    } on SocketException {
      return true;
    }
  }

  @override
  bool signal(int pid, ProcessSignal signal) => Process.killPid(pid, signal);

  /// Reads `/proc/<pid>/cmdline` as an argument vector.
  ///
  /// Returns null when the process is gone. Kernel threads yield an empty list,
  /// and the trailing separator is dropped so exact-token matching holds.
  static List<String>? readCmdline(int pid) {
    try {
      return File('/proc/$pid/cmdline')
          .readAsStringSync()
          .split(_argumentSeparator)
          .where((token) => token.isNotEmpty)
          .toList();
    } on FileSystemException {
      return null;
    }
  }
}
