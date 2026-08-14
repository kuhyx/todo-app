/// The [GitHubMirrorScreen] widget's public surface.
///
/// A `part` rather than a separate library because `createState` returns a
/// private class, so the widget and its State cannot be split apart.
part of 'github_mirror_screen.dart';

/// The GitHub mirror screen: cutover-only sync transport, not a peer of
/// Firebase.
///
/// Kept app-local rather than folded into the shared `sync_settings_ui`
/// package because connecting here also triggers an actual note sync via
/// [runSync] -- unlike the shared package's Firebase/Backup sections, which
/// only save settings. See `lib/ui/settings_screen.dart` for the "Enable
/// advanced" toggle and the link to this screen and to the shared Sync
/// settings screen.
class GitHubMirrorScreen extends StatefulWidget {
  /// Creates a [GitHubMirrorScreen] pre-filled with [initial] settings.
  const GitHubMirrorScreen({
    required this.initial,
    required this.repository,
    required this.appSettings,
    this.analytics,
    this.httpClient,
    this.firebaseFactory,
    this.stateStore,
    super.key,
  });

  /// The sync settings loaded when this screen was opened.
  final SyncSettings initial;

  /// The store a post-connect sync reads from and writes to.
  final NoteRepository repository;

  /// App-wide preferences, reconciled after a post-connect sync.
  final ValueNotifier<AppSettings> appSettings;

  /// Interaction-only usage analytics. Null in tests that don't exercise it.
  final AnalyticsService? analytics;

  /// Optional HTTP client for the GitHub calls (test-connection and device
  /// flow). Injected by tests; production uses each client's default.
  final http.Client? httpClient;

  /// Builds the Firebase backend for the post-connect sync. Injected so
  /// tests can supply a fake.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  @override
  State<GitHubMirrorScreen> createState() => _GitHubMirrorScreenState();
}
