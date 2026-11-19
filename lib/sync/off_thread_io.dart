import 'dart:isolate';

/// Runs [work] on a short-lived isolate and returns its result.
///
/// The result comes back through `Isolate.exit`, so a large parsed log is
/// handed over rather than copied.
Future<R> offThread<R>(R Function() work) => Isolate.run(work);
