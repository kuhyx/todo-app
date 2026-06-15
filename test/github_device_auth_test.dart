import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/sync/github_device_auth.dart';

/// Builds an auth instance whose polls resolve instantly (no real waiting).
GitHubDeviceAuth authWith(http.Client client) => GitHubDeviceAuth(
  clientId: 'test-client-id',
  httpClient: client,
  delay: (_) => Future<void>.value(),
);

const _device = DeviceCodeResponse(
  deviceCode: 'dev-123',
  userCode: 'WXYZ-1234',
  verificationUri: 'https://github.com/login/device',
  interval: 1,
  expiresIn: 900,
);

void main() {
  test('requestDeviceCode parses the device + user code', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), contains('login/device/code'));
      expect(req.bodyFields['client_id'], 'test-client-id');
      expect(req.bodyFields['scope'], 'repo');
      return http.Response(
        jsonEncode({
          'device_code': 'dev-123',
          'user_code': 'WXYZ-1234',
          'verification_uri': 'https://github.com/login/device',
          'interval': 5,
          'expires_in': 900,
        }),
        200,
      );
    });

    final res = await authWith(client).requestDeviceCode();
    expect(res.deviceCode, 'dev-123');
    expect(res.userCode, 'WXYZ-1234');
    expect(res.verificationUri, 'https://github.com/login/device');
  });

  test('pollForToken returns the token after authorization_pending', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      // Pending on the first two polls, then success.
      if (calls < 3) {
        return http.Response(
          jsonEncode({'error': 'authorization_pending'}),
          200,
        );
      }
      return http.Response(
        jsonEncode({'access_token': 'gho_abc', 'token_type': 'bearer'}),
        200,
      );
    });

    final token = await authWith(client).pollForToken(_device);
    expect(token, 'gho_abc');
    expect(calls, 3);
  });

  test('pollForToken obeys slow_down and still succeeds', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'error': 'slow_down', 'interval': 1}),
          200,
        );
      }
      return http.Response(jsonEncode({'access_token': 'gho_xyz'}), 200);
    });

    final token = await authWith(client).pollForToken(_device);
    expect(token, 'gho_xyz');
  });

  test('pollForToken throws on access_denied', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({'error': 'access_denied', 'error_description': 'no'}),
        200,
      ),
    );

    expect(
      () => authWith(client).pollForToken(_device),
      throwsA(
        isA<DeviceAuthException>().having(
          (e) => e.code,
          'code',
          'access_denied',
        ),
      ),
    );
  });

  test('pollForToken honors slow_down then succeeds', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'error': 'slow_down', 'interval': 0}),
          200,
        );
      }
      return http.Response(jsonEncode({'access_token': 'gho_ok'}), 200);
    });

    expect(await authWith(client).pollForToken(_device), 'gho_ok');
    expect(calls, 2);
  });

  test('pollForToken throws on an unexpected response shape', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'foo': 'bar'}), 200),
    );
    expect(
      () => authWith(client).pollForToken(_device),
      throwsA(isA<DeviceAuthException>()),
    );
  });

  test('pollForToken throws when the device code has expired', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'access_token': 'x'}), 200),
    );
    const expired = DeviceCodeResponse(
      deviceCode: 'd',
      userCode: 'u',
      verificationUri: 'v',
      interval: 1,
      expiresIn: 0, // deadline is now → loop body never runs
    );
    expect(
      () => authWith(client).pollForToken(expired),
      throwsA(
        isA<DeviceAuthException>().having(
          (e) => e.code,
          'code',
          'expired_token',
        ),
      ),
    );
  });

  test('defaults to a real http client and delay when none are injected', () {
    // Omitting httpClient/delay exercises the `?? http.Client()` and
    // `?? Future.delayed` constructor fallbacks; no request is made.
    final auth = GitHubDeviceAuth(clientId: 'c');
    addTearDown(auth.close);
  });
}
