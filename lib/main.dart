// coverage:ignore-file
// App bootstrap: opens the platform's note store and calls runApp. Exercised
// end-to-end by running the app, not unit tests.
import 'package:flutter/material.dart';

import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repository_factory.dart';
import 'package:todo/frame_stats.dart';
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameStats();

  // Where the log lives, and whether a legacy sqlite DB needs importing, is
  // platform-specific and resolved by a conditional import: `dart:io` cannot be
  // imported at all in a web compile, and the desktop app is now a web build.
  final repository = await openRepository();
  final appSettings = ValueNotifier(await AppSettings.load());
  final analytics = AnalyticsService(nodeId: repository.nodeId);

  runApp(
    TodoApp(
      repository: repository,
      appSettings: appSettings,
      analytics: analytics,
    ),
  );
}

/// Root widget. Holds the single [NoteRepository] instance and hands it
/// to the screens that need it.
class TodoApp extends StatelessWidget {
  /// Creates a [TodoApp] wrapping the given [repository], [appSettings] and
  /// [analytics].
  const TodoApp({
    required this.repository,
    required this.appSettings,
    required this.analytics,
    super.key,
  });

  /// The single, app-wide note store, injected into every screen.
  final NoteRepository repository;

  /// The single, app-wide preferences notifier (currently just
  /// `advancedMode`), injected into every screen that reads or changes it.
  final ValueNotifier<AppSettings> appSettings;

  /// The single, app-wide analytics logger, injected into every screen that
  /// reports interaction events.
  final AnalyticsService analytics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'todo',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: CaptureScreen(
        repository: repository,
        appSettings: appSettings,
        analytics: analytics,
      ),
    );
  }
}
