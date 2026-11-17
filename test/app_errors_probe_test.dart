// Proves the shared app-errors reporter end to end inside the test runner:
// one uncaught error and one wait over a second each become exactly one
// uploaded entry, and both carry the build. The sink writes to a file in
// place of RTDB so the probe needs no network.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FlutterExceptionHandler? savedFlutter;
  late ErrorCallback? savedAsync;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    savedFlutter = FlutterError.onError;
    savedAsync = PlatformDispatcher.instance.onError;
    dir = Directory.systemTemp.createTempSync('app_errors_probe');
  });

  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedAsync;
    AppErrors.instance = null;
    dir.deleteSync(recursive: true);
  });

  testWidgets('one error and one 2 s wait upload with the build', (t) async {
    // The deliberate error must not fail the test, so the handler the
    // reporter chains to is a no-op.
    FlutterError.onError = (_) {};
    final errors = await installAppErrors(
      const AppErrorsConfig(
        app: 'todo',
        repo: 'kuhyx/todo-app',
        package: 'todo',
        build: 4242,
        version: '1.2.3',
      ),
    );
    final out = File('${dir.path}/sink.jsonl');
    final uploader = errors.connect(
      sink: () async =>
          (path, values) async => out.writeAsStringSync(
            '${jsonEncode({'path': path, 'values': values})}\n',
            mode: FileMode.append,
          ),
      deviceId: () async => 'probe-device',
      startDelay: Duration.zero,
    );

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('probe boom')),
    );

    await t.pumpWidget(
      const WaitWatch(operation: 'probe.wait', child: SizedBox()),
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pumpWidget(const SizedBox());

    await t.runAsync(uploader.flush);
    uploader.dispose();

    final entries = [
      for (final line in out.readAsLinesSync())
        for (final v
            in ((jsonDecode(line) as Map)['values'] as Map).values.cast<Map>())
          v,
    ];
    final kinds = entries.map((e) => e['kind']).toList()..sort();
    expect(kinds, ['perf.slow', 'uncaught.flutter']);
    expect(entries.map((e) => e['build']).toSet(), {4242});
    expect(entries.map((e) => e['repo']).toSet(), {'kuhyx/todo-app'});
    final slow = entries.firstWhere((e) => e['kind'] == 'perf.slow');
    expect(slow['operation'], 'probe.wait');
    expect(slow['durationMs'] as int, greaterThanOrEqualTo(2000));
  });
}
