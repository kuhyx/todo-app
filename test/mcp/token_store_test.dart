// The tokens file is read once and again only when its mtime or size changes.
// A read error keeps the last good set (an exhausted fd table once made every
// valid token read as 403); with no good load yet the answer is "unavailable".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/mcp/token_file.dart';

void main() {
  late Directory tmp;
  late File file;
  late List<String> logged;
  late TokenStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('token_store');
    file = File('${tmp.path}/tokens')
      ..writeAsStringSync('${tokenHash('good')} pc\n# note\n');
    logged = [];
    store = TokenStore(file, log: logged.add);
  });
  tearDown(() {
    if (file.existsSync()) Process.runSync('chmod', ['600', file.path]);
    tmp.deleteSync(recursive: true);
  });

  TokenVerdict check(String token) => store.verdict('Bearer $token');

  /// Rewrites [file] and moves its mtime on, so the change is always seen.
  void rewrite(String text) {
    final before = file.lastModifiedSync();
    file
      ..writeAsStringSync(text)
      ..setLastModifiedSync(before.add(const Duration(seconds: 5)));
  }

  test('a listed token is accepted, others and malformed headers rejected', () {
    expect(check('good'), TokenVerdict.accepted);
    expect(check('bad'), TokenVerdict.rejected);
    expect(store.verdict(null), TokenVerdict.rejected);
    expect(store.verdict('Basic good'), TokenVerdict.rejected);
    expect(store.verdict('Bearer  '), TokenVerdict.rejected);
  });

  test('[T-tokens-mtime] the file is not re-read while its mtime holds', () {
    expect(check('good'), TokenVerdict.accepted);
    final mtime = file.lastModifiedSync();
    // Same length, same mtime: only a re-read could notice the new hash.
    file
      ..writeAsStringSync('${tokenHash('other')} pc\n# note\n')
      ..setLastModifiedSync(mtime);
    expect(check('good'), TokenVerdict.accepted);
    expect(check('other'), TokenVerdict.rejected);
  });

  test('a changed mtime reloads, so deleting a line revokes it', () {
    expect(check('good'), TokenVerdict.accepted);
    rewrite('# revoked\n');
    expect(check('good'), TokenVerdict.rejected);
  });

  test('[T-tokens-keep] an unreadable file after a good load keeps tokens', () {
    expect(check('good'), TokenVerdict.accepted);
    rewrite('${tokenHash('good')} pc\n${tokenHash('new')} pc2\n');
    Process.runSync('chmod', ['000', file.path]);
    expect(check('good'), TokenVerdict.accepted);
    expect(check('new'), TokenVerdict.rejected);
    expect(logged, isNotEmpty);
  });

  test('a vanished file after a good load keeps the last set', () {
    expect(check('good'), TokenVerdict.accepted);
    file.deleteSync();
    expect(check('good'), TokenVerdict.accepted);
  });

  test('the file coming back readable is picked up again', () {
    expect(check('good'), TokenVerdict.accepted);
    rewrite('${tokenHash('new')} pc\n');
    Process.runSync('chmod', ['000', file.path]);
    expect(check('new'), TokenVerdict.rejected);
    Process.runSync('chmod', ['600', file.path]);
    expect(check('new'), TokenVerdict.accepted);
    expect(check('good'), TokenVerdict.rejected);
  });

  test('[T-tokens-503] no good load yet is unavailable, not rejected', () {
    Process.runSync('chmod', ['000', file.path]);
    expect(check('good'), TokenVerdict.unavailable);
    expect(check('bad'), TokenVerdict.unavailable);
    expect(logged, hasLength(1), reason: 'the same error is logged once');
    Process.runSync('chmod', ['600', file.path]);
    expect(check('good'), TokenVerdict.accepted);
  });

  test('a missing file with no good load is unavailable', () {
    file.deleteSync();
    expect(check('good'), TokenVerdict.unavailable);
  });
}
