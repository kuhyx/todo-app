// Bearer tokens are checked against sha256 hashes in the tokens file, re-read
// when it changes so revoking a line takes effect without a restart; a read
// error keeps the last good set, and with none loaded the answer is 503. The
// Host check admits loopback and the public proxy name only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'mcp_harness.dart';

void main() {
  late McpHarness h;

  setUp(() async {
    h = McpHarness();
    await h.start();
  });
  tearDown(() => h.dispose());

  const ok = 'Bearer ${McpHarness.token}';

  test('a listed token is admitted', () async {
    expect(await h.rawInitialize({'authorization': ok}), 200);
  });

  test('no token or a wrong token is refused', () async {
    expect(await h.rawInitialize({}), anyOf(401, 403));
    expect(
      await h.rawInitialize({'authorization': 'Bearer nope'}),
      anyOf(401, 403),
    );
  });

  test('removing the line revokes without a restart', () async {
    h.tokens.writeAsStringSync('# revoked\n');
    expect(await h.rawInitialize({'authorization': ok}), anyOf(401, 403));
  });

  test('a vanished tokens file keeps the tokens already loaded', () async {
    expect(await h.rawInitialize({'authorization': ok}), 200);
    h.tokens.deleteSync();
    expect(await h.rawInitialize({'authorization': ok}), 200);
  });

  test('[T-tokens-keep] an unreadable file keeps the loaded tokens', () async {
    expect(await h.rawInitialize({'authorization': ok}), 200);
    h.tokens.writeAsStringSync('# rewritten, then locked\n');
    Process.runSync('chmod', ['000', h.tokens.path]);
    expect(await h.rawInitialize({'authorization': ok}), 200);
  });

  test('[T-tokens-503] no good load yet answers 503, not 403', () async {
    Process.runSync('chmod', ['000', h.tokens.path]);
    expect(await h.rawInitialize({'authorization': ok}), 503);
    expect(await h.rawInitialize({}), 403, reason: 'no bearer: plain refusal');
    Process.runSync('chmod', ['600', h.tokens.path]);
    expect(await h.rawInitialize({'authorization': ok}), 200);
  });

  test('the proxy host is admitted, a foreign host is not', () async {
    expect(
      await h.rawInitialize({
        'authorization': ok,
        'host': 'todo.kuhy.duckdns.org',
        'origin': 'https://todo.kuhy.duckdns.org',
      }),
      200,
    );
    expect(
      await h.rawInitialize({'authorization': ok, 'host': 'evil.example'}),
      anyOf(400, 403),
    );
  });
}
