import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/backlog_export.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/github_device_auth.dart';
import 'package:todo/sync/google_sign_in_backend.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings screen for sync configuration and note backup.
///
/// Primary sync path: "Connect Firebase" signs in with the shared sync
/// account, whose password is kept in the OS keystore. GitHub is only the
/// cutover mirror, so its device-flow connection, owner/repo and token
/// fallback all sit under "Advanced (GitHub mirror)" rather than competing
/// with Firebase as a visible choice.
///
/// The Backup section exports/imports all notes as a single Markdown file
/// (see [NotesMarkdown]).
class SettingsScreen extends StatefulWidget {
  /// Creates a [SettingsScreen] pre-filled with [initial] settings.
  const SettingsScreen({
    required this.initial,
    required this.repository,
    required this.appSettings,
    this.analytics,
    this.httpClient,
    this.firebaseFactory,
    this.googleFirebaseFactory,
    this.googleAvailable,
    this.stateStore,
    this.accountLoader,
    this.accountSaver,
    this.accountClearer,
    this.sessionProbe,
    super.key,
  });

  /// The sync settings loaded when this screen was opened.
  final SyncSettings initial;

  /// The store backup export/import reads from and writes to.
  final NoteRepository repository;

  /// App-wide preferences, currently just `advancedMode`. The "Enable
  /// advanced" switch on this screen reads and writes it directly.
  final ValueNotifier<AppSettings> appSettings;

  /// Interaction-only usage analytics. Null in tests that don't exercise it.
  final AnalyticsService? analytics;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Builds the Firebase backend via Google sign-in. Separate from
  /// [firebaseFactory] because it reaches the Google plugin's platform
  /// channel, which `flutter test` has no binding for.
  final Future<FirebaseRestClient?> Function()? googleFirebaseFactory;

  /// Whether to offer the Google button. Defaults to what the platform
  /// actually supports; injected by tests, which run on a host where the
  /// plugin reports unsupported.
  final bool? googleAvailable;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Keystore accessors for the Firebase account. Injected as a group so the
  /// connect/disconnect flows are testable without a platform channel —
  /// `flutter test` has no binding for one, and the real keystore is the only
  /// thing standing between these branches and full coverage.
  final Future<FirebaseAccount?> Function()? accountLoader;

  /// Persists the account. See [accountLoader].
  final Future<void> Function(FirebaseAccount)? accountSaver;

  /// Forgets the account and any cached session. See [accountLoader].
  final Future<void> Function()? accountClearer;

  /// Whether a Firebase session is stored. See [accountLoader].
  ///
  /// Separate from [accountLoader] because the two answer different
  /// questions: the account marker is bookkeeping, the session is the
  /// credential. A device can hold the second without the first, and
  /// reporting only the first is what made a syncing phone read as
  /// "not connected".
  final Future<bool> Function()? sessionProbe;

  /// Optional HTTP client for the GitHub calls (test-connection and device
  /// flow). Injected by tests; production uses each client's default.
  final http.Client? httpClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _owner = TextEditingController(
    text: widget.initial.owner,
  );
  late final TextEditingController _repo = TextEditingController(
    text: widget.initial.repo,
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.initial.token,
  );
  late final TextEditingController _clientId = TextEditingController(
    text: widget.initial.clientId,
  );

  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _testing = false;
  bool _busy = false;
  bool _firebaseConnected = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirebaseAccount());
  }

  /// Reflects a previously-stored account, so a returning user sees the real
  /// state instead of an empty form that looks unconfigured.
  Future<void> _loadFirebaseAccount() async {
    final account = await (widget.accountLoader ?? loadAccount)();
    // The stored session, not the account marker, decides "connected": a
    // Google sign-in leaves a refresh token that authenticates every request
    // even when no marker was written beside it.
    final connected = await (widget.sessionProbe ?? isFirebaseConfigured)();
    if (!mounted) return;
    if (account != null) _email.text = account.email;
    setState(() => _firebaseConnected = connected);
  }

  /// Stores the typed account and signs in immediately, so a typo surfaces
  /// here rather than as a silent background failure on the next sync.
  ///
  /// Without this the app could never reach Firebase at all: `openFirebase()`
  /// reads an account nothing had ever written.
  Future<void> _connectFirebase() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _status = 'Enter the sync account email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Signing in…';
    });
    await (widget.accountSaver ?? saveAccount)(
      FirebaseAccount(email: email, password: password),
    );
    final client = await (widget.firebaseFactory ?? openFirebase)();
    if (!mounted) return;
    if (client == null) {
      await (widget.accountClearer ?? clearAccount)();
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = 'Firebase rejected that account.';
      });
      return;
    }
    _password.clear();
    setState(() {
      _busy = false;
      _firebaseConnected = true;
      _status = 'Connected to Firebase.';
    });
  }

  /// Signs in by picking a Google account -- the one-tap path.
  ///
  /// Distinguishes three outcomes deliberately: a dismissed picker is not an
  /// error and says nothing alarming; a wrong-account sign-in reports *why*,
  /// because it is the failure that would otherwise look like a working sync
  /// that never syncs; anything else is a plain failure.
  Future<void> _connectGoogle() async {
    setState(() {
      _busy = true;
      _status = 'Signing in…';
    });
    try {
      final client =
          await (widget.googleFirebaseFactory ?? openFirebaseWithGoogle)();
      if (!mounted) return;
      if (client == null) {
        setState(() {
          _busy = false;
          _status = 'Google sign-in was cancelled.';
        });
        return;
      }
      // The account is saved by openFirebaseWithGoogle, using the email
      // Firebase reports -- not from _email, which is empty on the fresh
      // install this path exists for. Reflect it so the connected row shows
      // the address instead of a blank.
      //
      // storedAccount, not loadAccount: the latter falls back to the desktop
      // wrapper's /sync-account route when the keystore looks empty, which on
      // Android resolves to file:/// and throws. That threw here mid-sign-in
      // on the phone, leaving the screen stuck on "Signing in..." even though
      // the sign-in had actually succeeded.
      final account = await (widget.accountLoader ?? storedAccount)();
      // Report the persisted state, not the fact that the call returned a
      // client: a non-null client only means sign-in succeeded in that
      // moment, which is how four apps claimed "Connected" and then synced
      // over GitHub after the next restart.
      final connected = await (widget.sessionProbe ?? isFirebaseConfigured)();
      if (!mounted) return;
      if (account != null) _email.text = account.email;
      setState(() {
        _busy = false;
        _firebaseConnected = connected;
        _status = connected
            ? 'Connected to Firebase.'
            : 'Signed in, but this device did not save the session - it will '
                  'sync over GitHub after a restart. Try connecting again.';
      });
    } on FirebaseAuthError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = error.message;
      });
    } on Object catch (error) {
      // Broader than Exception on purpose: a missing platform binding raises
      // an Error, and anything escaping here leaves the button disabled and
      // the screen stuck on "Signing in..." forever -- which is exactly what
      // happened on the phone. Always land in a state the user can retry from.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = 'Google sign-in failed: $error';
      });
    }
  }

  Future<void> _disconnectFirebase() async {
    await (widget.accountClearer ?? clearAccount)();
    if (!mounted) return;
    _email.clear();
    _password.clear();
    setState(() {
      _firebaseConnected = false;
      _status = 'Firebase disconnected.';
    });
  }

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _token.dispose();
    _clientId.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  SyncSettings get _current => SyncSettings(
    owner: _owner.text.trim(),
    repo: _repo.text.trim(),
    token: _token.text.trim(),
    clientId: _clientId.text.trim(),
  );

  /// Runs the OAuth device flow and, on success, fills in the token field.
  Future<void> _connectGitHub() async {
    final clientId = _clientId.text.trim();
    if (clientId.isEmpty) {
      setState(() => _status = 'Enter the OAuth App client id first.');
      return;
    }
    final auth = GitHubDeviceAuth(
      clientId: clientId,
      httpClient: widget.httpClient,
    );
    try {
      final device = await auth.requestDeviceCode();
      if (!mounted) return;
      final token = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeviceCodeDialog(device: device, auth: auth),
      );
      if (token != null && token.isNotEmpty) {
        setState(() {
          _token.text = token;
          _status = 'Connected — syncing…';
        });
        await _current.save();
        await _syncAfterConnect();
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Could not start device flow: $e');
    } finally {
      auth.close();
    }
  }

  /// Runs a sync right after connecting so the user's notes download
  /// immediately and they get clear confirmation it worked.
  Future<void> _syncAfterConnect() async {
    final s = _current;
    try {
      final run = await runSync(
        widget.repository,
        s,
        appSettings: widget.appSettings.value,
        analytics: widget.analytics,
        httpClient: widget.httpClient,
        firebaseFactory: widget.firebaseFactory,
        stateStore: widget.stateStore,
      );
      widget.appSettings.value = widget.appSettings.value.adopt(
        run.appSettings,
      );
      if (mounted) {
        setState(
          () => _status =
              'Connected and synced (merged '
              '${run.syncResult.mergedDevices} device(s)). Your notes are '
              'up to date.',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Connected, but sync failed: $e');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final s = _current;
    final client = GitHubClient(
      owner: s.owner,
      repo: s.repo,
      token: s.token,
      httpClient: widget.httpClient,
    );
    try {
      final ok = await client.canAccessRepo();
      setState(
        () => _status = ok
            ? 'Connected — repo is reachable.'
            : 'Could not access ${s.owner}/${s.repo}. Check token scope.',
      );
    } on Exception catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final s = _current;
    await s.save();
    if (mounted) Navigator.of(context).pop(s);
  }

  /// Persists the "Enable advanced" toggle locally and, when a Firebase
  /// session is available, best-effort mirrors it so the choice follows the
  /// user to their other devices.
  ///
  /// The local write always lands — a signed-in-as-wrong-account device
  /// throwing [FirebaseAuthError] out of `openFirebase()` must not take the
  /// toggle down with it, so opening the client has its own try/catch,
  /// separate from (and preceding) the try that guards the local write and
  /// mirror push.
  Future<void> _setAdvancedMode(bool value) async {
    final analytics = widget.analytics;
    if (analytics != null) {
      unawaited(
        analytics.logEvent(
          AnalyticsEvent(
            name: 'settings_toggle',
            timestamp: DateTime.now(),
            params: {'key': 'advancedMode', 'value': value},
          ),
        ),
      );
    }
    FirebaseRestClient? client;
    try {
      client = await (widget.firebaseFactory ?? openFirebase)();
    } on Exception {
      client = null;
    }
    try {
      final updated = await widget.appSettings.value.withAdvancedMode(
        value: value,
        client: client,
      );
      if (mounted) widget.appSettings.value = updated;
    } finally {
      client?.close();
    }
  }

  /// Exports every note to a single Markdown file. On mobile this opens the
  /// system share sheet; on desktop it writes the canonical `~/todo/
  /// BACKLOG.md` so a future tool/agent has a stable path to read.
  Future<void> _export() async {
    try {
      final notes = await widget.repository.listNotes();
      final markdown = NotesMarkdown.export(notes);

      final outcome = await exportBacklog(markdown, notes.length);
      if (mounted) setState(() => _status = outcome);
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Export failed: $e');
    }
  }

  /// Imports notes from a user-picked Markdown file, merging by id so a
  /// stale backup never clobbers a newer local edit (see
  /// [NoteRepository.importNotes]).
  Future<void> _import() async {
    try {
      const group = XTypeGroup(
        label: 'Markdown',
        extensions: ['md', 'markdown', 'txt'],
        // UTIs/MIME so the picker accepts the file on iOS/Android too.
        uniformTypeIdentifiers: ['net.daringfireball.markdown', 'public.text'],
        mimeTypes: ['text/markdown', 'text/plain'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return; // user cancelled
      final content = await file.readAsString();

      final notes = NotesMarkdown.parse(content);
      final outcome = await widget.repository.importNotes(notes);
      if (mounted) {
        setState(
          () => _status =
              'Imported ${outcome.total}: ${outcome.added} new, '
              '${outcome.updated} updated, ${outcome.skipped} unchanged',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<AppSettings>(
            valueListenable: widget.appSettings,
            builder: (context, settings, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable advanced'),
              subtitle: const Text(
                'Priority/status, templates, view modes, and sync details '
                'in the capture screen',
              ),
              value: settings.advancedMode,
              onChanged: (value) => unawaited(_setAdvancedMode(value)),
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Firebase sync',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _firebaseConnected
                ? 'Connected. Notes go to Firebase first, and still mirror '
                      'to GitHub until every device has moved.'
                : 'Not connected — syncing over GitHub only. Enter the '
                      'shared sync account to move this device over. The '
                      'password is kept in the device keystore, never in the '
                      'app or the repo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Once connected the account is read-only text: an editable email
          // box beside an empty password box reads as "you still have to
          // enter this", making a connected device look unconfigured.
          if (_firebaseConnected)
            Row(
              children: [
                const Icon(Icons.cloud_done, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_email.text)),
                TextButton(
                  onPressed: _busy ? null : _disconnectFirebase,
                  child: const Text('Disconnect'),
                ),
              ],
            )
          else ...[
            // The whole point of this screen after a reinstall: one tap, no
            // typing. The password form is kept but demoted, because on a
            // phone keyboard it is the slow path.
            //
            // Hidden where the platform cannot sign in programmatically --
            // the desktop build is the web build, and Google Identity
            // Services only signs in through its own rendered button there.
            // A visible button that always failed would be worse than none.
            if (widget.googleAvailable ?? googleSignInSupported) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _connectGoogle,
                  icon: const Icon(Icons.account_circle),
                  label: const Text('Sign in with Google'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ExpansionTile(
              // Expanded by default where Google is unavailable: on desktop
              // the password form is the only way in, so hiding it behind a
              // disclosure would look like there is no way to connect.
              initiallyExpanded:
                  !(widget.googleAvailable ?? googleSignInSupported),
              title: const Text('Use the account password instead'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Sync account email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Sync account password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _connectFirebase,
                    icon: const Icon(Icons.cloud_done),
                    label: const Text('Connect Firebase'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Backup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Export all notes to a single Markdown file, or import/merge a '
            'file back (matching ids are merged, never duplicated).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.upload_file),
                label: const Text('Export notes'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.download),
                label: const Text('Import notes'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          // GitHub is the cutover mirror, not a choice competing with
          // Firebase, so its whole setup lives behind one disclosure at the
          // very bottom of the screen — last, not suggested as a normal
          // option.
          ExpansionTile(
            title: const Text('Advanced (GitHub mirror)'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Authorize in your browser — no token to paste. Syncs to '
                  'kuhyx/syncs by default.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _connectGitHub,
                  icon: const Icon(Icons.login),
                  label: const Text('Connect GitHub'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _owner,
                decoration: const InputDecoration(
                  labelText: 'GitHub owner',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _repo,
                decoration: const InputDecoration(
                  labelText: 'Repository name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientId,
                decoration: const InputDecoration(
                  labelText: 'OAuth App client id',
                  helperText:
                      'Leave as the baked-in default unless self-hosting',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Access token (fallback)',
                  helperText: 'Contents: read/write on the sync repo only',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Dialog shown during the device flow: displays the user code, opens the
/// verification page, and polls until authorized — popping the token (or
/// null if cancelled / failed).
class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({required this.device, required this.auth});

  final DeviceCodeResponse device;
  final GitHubDeviceAuth auth;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      final token = await widget.auth.pollForToken(widget.device);
      if (mounted) Navigator.of(context).pop(token);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _openPage() async {
    await Clipboard.setData(ClipboardData(text: widget.device.userCode));
    await launchUrl(
      Uri.parse(widget.device.verificationUri),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Authorize on GitHub'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter this code on GitHub:'),
          const SizedBox(height: 8),
          SelectableText(
            widget.device.userCode,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (_error == null)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Waiting for authorization…')),
              ],
            )
          else
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _openPage,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open GitHub & copy code'),
        ),
      ],
    );
  }
}
