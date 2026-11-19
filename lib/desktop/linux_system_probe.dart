/// The real-host [SystemProbe]: `ss` for the listener, `/proc` for the rest.
///
/// Split out of `port_guard.dart` for file size, and it is the natural seam:
/// everything here touches the live host, while `port_guard.dart` keeps the
/// pure decision logic that tests drive with a fake probe.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo/desktop/port_guard.dart';

/// NUL separates the arguments inside `/proc/<pid>/cmdline`.
final String _argumentSeparator = String.fromCharCode(0);

/// [SystemProbe] backed by `ss` and `/proc`.
///
/// The desktop wrapper only ever runs on Linux — the desktop app is the web
/// build served locally — so reading `/proc` directly is safe here.
class LinuxSystemProbe implements SystemProbe {
  /// Creates the default host probe.
  ///
  /// [ssExecutable] exists so a test can point at a missing binary and exercise
  /// the "no `ss` on PATH" path. [listProc] lets a test fail the `/proc`
  /// listing on demand.
  const LinuxSystemProbe({this.ssExecutable = 'ss', this.listProc = _listProc});

  /// Name of the socket-listing tool used to find the port owner.
  final String ssExecutable;

  /// Lists `/proc`'s entries.
  final List<FileSystemEntity> Function() listProc;

  /// How many `/proc` listings a process exiting mid-listing may spoil.
  static const _listAttempts = 3;

  static List<FileSystemEntity> _listProc() => Directory('/proc').listSync();

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
    for (final entry in _listProcRetrying()) {
      final pid = int.tryParse(p.basename(entry.path));
      if (pid == null) continue;
      final cmdline = readCmdline(pid);
      if (cmdline != null) cmdlines.add(cmdline);
    }
    return cmdlines;
  }

  /// Dart's listing lstat()s some entries, so a pid that exits between
  /// readdir and that lstat fails the whole listing. A fresh listing no
  /// longer holds that pid; a few failures in a row mean a real error.
  List<FileSystemEntity> _listProcRetrying() {
    for (var attempt = 1; ; attempt++) {
      try {
        return listProc();
      } on PathNotFoundException {
        if (attempt >= _listAttempts) rethrow;
      }
    }
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
