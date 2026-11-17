// coverage:ignore-file
// App bootstrap: opens the platform's note store and calls runApp. Exercised
// end-to-end by running the app, not unit tests.
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show AppErrors, AppErrorsConfig, AppErrorsRouteObserver, installAppErrors;
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/attachments/image_store.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repository_factory.dart';
import 'package:todo/frame_stats.dart';
import 'package:todo/sync/firebase_client.dart' show openFirebase;
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/text_free_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Every error and every wait over 1 s goes to the PC's app-errors ingest,
  // which files a board ticket (kuhyx/utils DOCS-app-errors.md). The release
  // build passes the versionCode and name as dart-defines (release-apk.yml).
  final errors = await installAppErrors(
    const AppErrorsConfig(
      app: 'todo',
      repo: 'kuhyx/todo-app',
      package: 'todo',
      // 0 unless the build passes --dart-define=APP_BUILD.
      // ignore: avoid_redundant_argument_values
      build: int.fromEnvironment('APP_BUILD'),
      version: String.fromEnvironment('APP_VERSION'),
    ),
  );
  installFrameStats();

  // Where the log lives, and whether a legacy sqlite DB needs importing, is
  // platform-specific and resolved by a conditional import: `dart:io` cannot be
  // imported at all in a web compile, and the desktop app is now a web build.
  final repository = await openRepository();
  errors.connect(
    sink: () async => (await openFirebase())?.patchValues,
    deviceId: () async => repository.nodeId,
  );
  final appSettings = ValueNotifier(await AppSettings.load());
  final analytics = AnalyticsService(nodeId: repository.nodeId);
  // App storage + direct dufs on Android; the wrapper's /images on desktop.
  final imageStore = await openImageStore();

  runApp(
    TodoApp(
      repository: repository,
      appSettings: appSettings,
      analytics: analytics,
      imageStore: imageStore,
      errors: errors,
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
    required this.imageStore,
    this.errors,
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

  /// The single, app-wide store for attached images.
  final ImageStore imageStore;

  /// App-wide error reporting; null in widget tests.
  final AppErrors? errors;

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp so pushed routes (note detail) see it too.
    return ImageStoreScope(
      store: imageStore,
      child: MaterialApp(
        title: 'todo',
        localizationsDelegates: kTextFreeLocalizations,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        navigatorObservers: [
          if (errors case final errors?) AppErrorsRouteObserver(errors),
        ],
        home: CaptureScreen(
          repository: repository,
          appSettings: appSettings,
          analytics: analytics,
        ),
      ),
    );
  }
}
