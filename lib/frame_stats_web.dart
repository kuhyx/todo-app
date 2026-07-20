// coverage:ignore-file
// TEMPORARY diagnostic instrument, web variant. See frame_stats_io.dart.
//
// Armed at build time (`--dart-define=TODO_FRAME_STATS=1`) rather than by an
// environment variable, which a browser does not have. Reports to the devtools
// console.
import 'dart:async';

import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Whether the frame-stats instrument is armed for this build.
const frameStatsEnabled = bool.fromEnvironment('TODO_FRAME_STATS');

const _slowFrameMs = 8;
const _probePeriod = Duration(milliseconds: 16);
const _blockedMs = 24;

final Stopwatch _clock = Stopwatch();
Timer? _probe;
final List<int> _cadenceUs = <int>[];

String get _at => (_clock.elapsedMilliseconds / 1000).toStringAsFixed(2);

/// Installs the frame-timing and event-loop instruments.
void installFrameStats() {
  if (!frameStatsEnabled) return;
  _clock.start();
  debugPrint('[frame-stats web] armed');

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final total = t.buildDuration.inMilliseconds +
          t.rasterDuration.inMilliseconds;
      if (total > _slowFrameMs) {
        debugPrint(
          '[SLOW-FRAME $_at s] total=${total}ms '
          '(build=${t.buildDuration.inMilliseconds} '
          'raster=${t.rasterDuration.inMilliseconds})',
        );
      }
      // Cadence is the headline number for the >=100fps done-condition.
      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      _cadenceUs.add(vsync);
    }
    _reportCadence();
  });

  var expected = _clock.elapsedMicroseconds + _probePeriod.inMicroseconds;
  _probe = Timer.periodic(_probePeriod, (_) {
    final now = _clock.elapsedMicroseconds;
    final lateMs = (now - expected) / 1000;
    if (lateMs > _blockedMs) {
      debugPrint('[UI-BLOCKED $_at s] ${lateMs.toStringAsFixed(1)}ms');
    }
    expected = now + _probePeriod.inMicroseconds;
  });
}

void _reportCadence() {
  if (_cadenceUs.length < 120) return;
  final deltas = <int>[];
  for (var i = 1; i < _cadenceUs.length; i++) {
    deltas.add(_cadenceUs[i] - _cadenceUs[i - 1]);
  }
  deltas.sort();
  final p50 = deltas[deltas.length ~/ 2] / 1000;
  final p95 = deltas[(deltas.length * 95) ~/ 100] / 1000;
  debugPrint(
    '[frame-stats web] cadence p50=${p50.toStringAsFixed(2)}ms '
    'p95=${p95.toStringAsFixed(2)}ms (~${(1000 / p50).toStringAsFixed(1)} fps)',
  );
  _cadenceUs.clear();
}

/// Stops the probe.
void disposeFrameStats() {
  _probe?.cancel();
}
