/// Runs [work] inline: a browser has no isolates for it.
Future<R> offThread<R>(R Function() work) async => work();
