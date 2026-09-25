/// Settings → Cloud images: the dufs login attached images upload with.
///
/// On the phone that is a password field (the `todo` login's password,
/// printed and put on the PC clipboard by `add_dufs_login.sh`) plus a Test
/// button. The desktop page has no field: its wrapper reads the login from
/// `~/.config/dufs/logins/todo.env`, so the screen only reports whether it
/// found one.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:todo/attachments/image_password_store.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/dufs_image_client.dart';

/// The command that creates the login, shown wherever it is missing.
const kAddLoginCommand =
    '~/src/dufs-cloud/scripts/add_dufs_login.sh todo /todo-images rw';

/// The settings-list entry that opens [CloudImagesScreen].
class CloudImagesTile extends StatelessWidget {
  /// Creates the tile; [httpClient] reaches the Test button (tests).
  const CloudImagesTile({this.httpClient, super.key});

  /// Injected HTTP client for the Test button.
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Cloud images'),
    subtitle: const Text('Where attached images upload (dufs)'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CloudImagesScreen(httpClient: httpClient),
      ),
    ),
  );
}

/// Password + status for image uploads.
class CloudImagesScreen extends StatefulWidget {
  /// Creates the screen; everything injectable is for tests.
  const CloudImagesScreen({
    this.passwords = const ImagePasswordStore(),
    this.httpClient,
    this.showPasswordField = !kIsWeb,
    super.key,
  });

  /// Where the phone keeps the password.
  final ImagePasswordStore passwords;

  /// Injected HTTP client for the Test button.
  final http.Client? httpClient;

  /// Whether this device enters the password itself (not the desktop page).
  final bool showPasswordField;

  @override
  State<CloudImagesScreen> createState() => _CloudImagesScreenState();
}

class _CloudImagesScreenState extends State<CloudImagesScreen> {
  final _password = TextEditingController();
  ImageStoreStatus? _status;
  String? _checkResult;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ImageStoreScope.read(context);
    if (widget.showPasswordField) {
      _password.text = await widget.passwords.read();
    }
    final status = await store.status();
    if (mounted) setState(() => _status = status);
  }

  /// Saves the password, then checks it against dufs.
  Future<void> _saveAndTest() async {
    final password = _password.text.trim();
    setState(() => _checking = true);
    final saved = await widget.passwords.write(password);
    var result = 'Could not save: the keystore is unavailable';
    if (saved) {
      final client = DufsImageClient(
        DufsLogin(user: kDufsImagesUser, password: password),
        httpClient: widget.httpClient,
      );
      final check = await client.check();
      result = switch (check) {
        DufsCheck.ok => 'Saved — dufs accepted the login',
        DufsCheck.rejected => 'Saved, but dufs rejected the password',
        DufsCheck.unreachable => 'Saved — dufs is unreachable right now',
      };
      // Upload what queued up while there was no password, now rather than
      // on the next sync. No note texts: an empty ref set only uploads, it
      // never evicts.
      if (check == DufsCheck.ok && mounted) {
        await ImageStoreScope.read(context).reconcile(const []);
      }
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkResult = result;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud images')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.showPasswordField) ...[
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password for the "todo" dufs login',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _checking ? null : _saveAndTest,
              child: const Text('Save & test'),
            ),
            if (_checkResult case final result?) ...[
              const SizedBox(height: 8),
              Text(result),
            ],
            const SizedBox(height: 16),
          ],
          if (status != null) ...[
            Text(
              status.configured
                  ? 'Login: configured'
                  : 'Login: missing — create it on the PC with',
            ),
            if (!status.configured) const SelectableText(kAddLoginCommand),
            const SizedBox(height: 8),
            Text('Waiting to upload: ${status.pending}'),
          ],
          const SizedBox(height: 16),
          Text(
            'Images are shrunk to 2560px JPEGs without location data before '
            'they leave this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
