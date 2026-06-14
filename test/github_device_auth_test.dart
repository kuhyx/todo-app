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
        return http.Response(jsonEncode({'error': 'authorization_pending'}), 200);
      }
      return http.Response(
          jsonEncode({'access_token': 'gho_abc', 'token_type': 'bearer'}), 200);
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
            jsonEncode({'error': 'slow_down', 'interval': 1}), 200);
      }
      return http.Response(jsonEncode({'access_token': 'gho_xyz'}), 200);
    });

    final token = await authWith(client).pollForToken(_device);
    expect(token, 'gho_xyz');
  });

  test('pollForToken throws on access_denied', () async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({'error': 'access_denied', 'error_description': 'no'}), 200));

    expect(
      () => authWith(client).pollForToken(_device),
      throwsA(isA<DeviceAuthException>()
          .having((e) => e.code, 'code', 'access_denied')),
    );
  });
}
