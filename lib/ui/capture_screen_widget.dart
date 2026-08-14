/// The [CaptureScreen] widget's public surface: its parameters and their
/// contracts. The state that drives them lives in `capture_screen.dart`.
///
/// A `part` rather than a separate library because `createState` returns a
/// private class, so the widget and its State cannot be split across
/// libraries.
part of 'capture_screen.dart';

/// The landing screen: an always-focused text box for jotting an idea.
///
/// Per the product goal "no interruptions, immediate", text is persisted
/// to local storage on *every* keystroke. A note row is created lazily on
/// the first character typed, then updated in place. The "new note" action
/// finalises the current idea and clears the field for the next one.
class CaptureScreen extends StatefulWidget {
  /// Creates a [CaptureScreen] backed by [repository].
  const CaptureScreen({
    required this.repository,
    required this.appSettings,
    this.analytics,
    this.httpClient,
    this.localBackup,
    this.firebaseFactory,
    this.stateStore,
    super.key,
  });

  /// The store the captured note is persisted to on every keystroke.
  final NoteRepository repository;

  /// App-wide preferences, currently just `advancedMode`: whether the
  /// priority/status row and the routine save/sync status line are shown.
  /// A sync failure is always surfaced regardless of this flag.
  final ValueNotifier<AppSettings> appSettings;

  /// Interaction-only usage analytics (taps, navigation, sync outcomes —
  /// never note text). Null in tests that don't exercise it, so the prefs
  /// round-trip `logEvent` does on every call never has to be awaited by a
  /// test that didn't ask for it.
  final AnalyticsService? analytics;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Injectable HTTP client for the sync path. Production leaves this null
  /// (the GitHubClient creates its own); tests pass a mock so the configured
  /// sync flow can be exercised without real network access.
  final http.Client? httpClient;

  /// Injectable local-disk backup. Production leaves this null (a platform
  /// file-backed instance is created); tests pass a fake with in-memory IO.
  final LocalBackup? localBackup;

  /// How long focus must stay lost before a background sync fires. Public so
  /// tests can pump exactly past it.
  static const autoSyncDebounce = Duration(seconds: 5);

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}
