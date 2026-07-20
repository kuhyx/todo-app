/// Platform entry point for the temporary frame instrument.
///
/// Conditional export because the io version writes to `stdout` and reads
/// `Platform.environment`, neither of which exists in a browser. The web
/// version reports to the devtools console instead and is armed at build time
/// with `--dart-define=TODO_FRAME_STATS=1`.
library;

export 'frame_stats_io.dart'
    if (dart.library.js_interop) 'frame_stats_web.dart';
