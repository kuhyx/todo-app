// Standalone end-to-end check of the GitHub OAuth device flow used by the app,
// to isolate whether a failure is in GitHub/OAuth-App config or in the app.
//
// Run: dart run tool/device_flow_check.dart
// It prints a user code, you authorize it in the browser, and it reports
// whether polling yields a token and whether that token can read the sync repo.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _clientId = 'Ov23li9tF2R46PqzJgch';
const _scope = 'repo';
const _owner = 'kuhyx';
const _repo = 'todo-sync';

Future<void> main() async {
  final code = await http.post(
    Uri.parse('https://github.com/login/device/code'),
    headers: {'Accept': 'application/json'},
    body: {'client_id': _clientId, 'scope': _scope},
  );
  if (code.statusCode != 200) {
    stderr.writeln('device/code FAILED ${code.statusCode}: ${code.body}');
    exit(1);
  }
  final dc = jsonDecode(code.body) as Map<String, dynamic>;
  stdout.writeln(
    '>>> Open ${dc['verification_uri']} and enter: ${dc['user_code']}',
  );
  stdout.writeln('Polling for the token...');

  final deviceCode = dc['device_code'] as String;
  var interval = (dc['interval'] as int?) ?? 5;
  final deadline = DateTime.now().add(
    Duration(seconds: (dc['expires_in'] as int?) ?? 900),
  );

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(Duration(seconds: interval));
    final res = await http.post(
      Uri.parse('https://github.com/login/oauth/access_token'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': _clientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = body['access_token'] as String?;
    if (token != null) {
      stdout.writeln('TOKEN OK (length ${token.length})');
      final repo = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'todo-app-sync',
        },
      );
      stdout.writeln('repo $_owner/$_repo access status: ${repo.statusCode}');
      stdout.writeln(
        repo.statusCode == 200
            ? 'CHAIN OK — device flow + token + repo access all work.'
            : 'TOKEN CANNOT READ REPO: ${repo.body}',
      );
      exit(repo.statusCode == 200 ? 0 : 2);
    }
    switch (body['error'] as String?) {
      case 'authorization_pending':
        stdout.write('.');
      case 'slow_down':
        interval = (body['interval'] as int?) ?? interval + 5;
      case final String e:
        stderr.writeln('\nTOKEN ERROR: $e — ${body['error_description']}');
        exit(1);
      case null:
        stderr.writeln('\nUnexpected: ${res.body}');
        exit(1);
    }
  }
  stderr.writeln('\nExpired before authorization.');
  exit(1);
}
