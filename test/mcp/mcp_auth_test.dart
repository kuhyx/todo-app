// Bearer tokens are checked against sha256 hashes in the tokens file, re-read
// per request so revoking a line takes effect without a restart; the Host
// check admits loopback and the public proxy name only.
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

  test('a missing tokens file admits nobody', () async {
    h.tokens.deleteSync();
    expect(await h.rawInitialize({'authorization': ok}), anyOf(401, 403));
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
