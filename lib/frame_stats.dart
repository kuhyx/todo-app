// coverage:ignore-file
// TEMPORARY diagnostic instrument (desktop interaction-lag investigation).
// Guarded by TODO_FRAME_STATS=1 so it is inert in normal use.
//
// v3 adds an event-loop blocking monitor, which is the decisive instrument.
// Frame gaps are ambiguous in a mostly-static UI: no frame is produced when
// nothing needs drawing, so an idle user looks identical to a stalled isolate.
// A periodic timer, by contrast, is scheduled regardless of drawing -- if it
// fires late, the UI isolate was genuinely blocked, and by exactly how long.
import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Whether the frame-stats instrument is armed for this process.
bool get frameStatsEnabled => Platform.environment['TODO_FRAME_STATS'] == '1';

/// A frame whose own work exceeded this is a hitch worth naming. Set to zero
/// by TODO_FRAME_STATS_ALL=1 so every frame is logged, which is what the
/// raster-cost-vs-window-size sweep needs.
int get _slowFrameUs =>
    Platform.environment['TODO_FRAME_STATS_ALL'] == '1' ? -1 : 8000;

/// How often the event-loop probe is scheduled.
const _probePeriod = Duration(milliseconds: 16);

/// Lateness beyond this means the isolate was blocked long enough to be felt.
const _blockedMs = 24;

final Stopwatch _clock = Stopwatch();
Timer? _probe;

String get _at => (_clock.elapsedMilliseconds / 1000).toStringAsFixed(2);

/// Installs the frame-timing and event-loop instruments.
void installFrameStats() {
  if (!frameStatsEnabled) return;
  _clock.start();
  stdout.writeln(
    '[frame-stats v3] armed; logging slow frames and UI-isolate blocking',
  );
  _installFrameTimings();
  _installEventLoopProbe();
}

void _installFrameTimings() {
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      if (build + raster > _slowFrameUs) {
        stdout.writeln(
          '[FRAME $_at s] total=${((build + raster) / 1000)
              .toStringAsFixed(1)}ms '
          '(build=${(build / 1000).toStringAsFixed(1)} '
          'raster=${(raster / 1000).toStringAsFixed(1)})',
        );
      }
    }
  });
}

/// Schedules a timer every [_probePeriod] and reports how late it actually
/// fired. Lateness is time the UI isolate spent unable to run anything -- e.g.
/// a synchronous JSON serialize of the whole note log.
void _installEventLoopProbe() {
  var expected = _clock.elapsedMicroseconds + _probePeriod.inMicroseconds;
  void tick(Timer _) {
    final now = _clock.elapsedMicroseconds;
    final lateMs = (now - expected) / 1000;
    if (lateMs > _blockedMs) {
      stdout.writeln(
        '[UI-BLOCKED $_at s] event loop stalled '
        '${lateMs.toStringAsFixed(1)}ms',
      );
    }
    expected = now + _probePeriod.inMicroseconds;
  }

  _probe = Timer.periodic(_probePeriod, tick);
}

/// Stops the probe. Only needed if the instrument outlives the app.
void disposeFrameStats() => _probe?.cancel();
