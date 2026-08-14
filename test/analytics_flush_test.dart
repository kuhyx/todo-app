/// Tests for the interaction-only analytics buffer and Firebase flush.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';

import 'analytics_helpers.dart';

FirebaseRestClient _fakeClient(
  Future<http.Response> Function(http.Request request) handler,
) => FirebaseRestClient(
  databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
  auth: FirebaseTokenProvider(
    apiKey: 'AIzaKey',
    store: InMemoryCredentialStore(
      FirebaseCredentials(
        idToken: 'id',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    ),
  ),
  httpClient: http_testing.MockClient(handler),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AnalyticsService.flush', () {
    test('does nothing when client is null', () async {
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime.now()),
      );

      await service.flush(null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('analytics.buffer'), isNotNull);
    });

    test('does nothing when the buffer is empty', () async {
      final requests = <String>[];
      final client = _fakeClient((request) async {
        requests.add(request.method);
        return http.Response('{}', 200);
      });
      const service = AnalyticsService(nodeId: 'device-a');

      await service.flush(client);

      expect(requests, isEmpty);
    });

    test('pushes the buffer as one batch and clears it on success', () async {
      String? putPath;
      String? putBody;
      final client = _fakeClient((request) async {
        if (request.method == 'PUT') {
          putPath = request.url.path;
          putBody = request.body;
        }
        return http.Response(request.body, 200);
      });
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime(2026)),
      );
      await service.logEvent(
        AnalyticsEvent(name: 'note_created', timestamp: DateTime(2026)),
      );

      await service.flush(client);

      expect(putPath, startsWith('/analytics/device-a/'));
      final decodedBody = jsonDecode(jsonDecode(putBody!) as String) as List;
      expect(decodedBody, hasLength(2));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('analytics.buffer'), isNull);
    });

    test('leaves the buffer untouched on a push failure', () async {
      final client = _fakeClient((_) async => http.Response('error', 500));
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime.now()),
      );

      await service.flush(client);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('analytics.buffer')!) as List;
      expect(decoded, hasLength(1));
    });

    test('keeps an event logged after the batch was already claimed', () async {
      // The HTTP handler runs mid-`putFileText`, strictly after flush() has
      // already claimed (cleared) the buffer — so writing here lands in a
      // buffer this flush() call no longer owns, unlike writing to prefs
      // before calling flush() (which would just become part of the claimed
      // batch itself).
      final client = _fakeClient((request) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'analytics.buffer',
          jsonEncode([
            AnalyticsEvent(
              name: 'mid_flush_event',
              timestamp: DateTime.now(),
            ).toJson(),
          ]),
        );
        return http.Response(request.body, 200);
      });
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime.now()),
      );

      await service.flush(client);

      final prefs = await SharedPreferences.getInstance();
      final remaining =
          jsonDecode(prefs.getString('analytics.buffer')!) as List;
      expect(remaining, hasLength(1));
      expect((remaining.single as Map)['name'], 'mid_flush_event');
    });

    test(
      'restores the claimed batch ahead of events logged mid-flush on '
      'failure',
      () async {
        // The HTTP handler runs mid-`putFileText`, strictly after flush()
        // has already claimed (cleared) the buffer, so writing here is a
        // genuine race rather than something that could instead land before
        // or after `flush()` depending on scheduling.
        final client = _fakeClient((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'analytics.buffer',
            jsonEncode([
              AnalyticsEvent(
                name: 'mid_flush_event',
                timestamp: DateTime(2026),
              ).toJson(),
            ]),
          );
          return http.Response('error', 500);
        });
        const service = AnalyticsService(nodeId: 'device-a');
        await service.logEvent(
          AnalyticsEvent(name: 'app_open', timestamp: DateTime(2026)),
        );

        await service.flush(client);

        final prefs = await SharedPreferences.getInstance();
        final remaining =
            jsonDecode(prefs.getString('analytics.buffer')!) as List;
        expect(remaining, hasLength(2));
        expect((remaining[0] as Map)['name'], 'app_open');
        expect((remaining[1] as Map)['name'], 'mid_flush_event');
      },
    );

    test(
      'a RemoteSyncError from an expired session restores the buffer',
      () async {
        final client = FirebaseRestClient(
          databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
          auth: FirebaseTokenProvider(
            apiKey: 'AIzaKey',
            store: InMemoryCredentialStore(null),
          ),
        );
        const service = AnalyticsService(nodeId: 'device-a');
        await service.logEvent(
          AnalyticsEvent(name: 'app_open', timestamp: DateTime(2026)),
        );

        await service.flush(client);

        final prefs = await SharedPreferences.getInstance();
        final decoded =
            jsonDecode(prefs.getString('analytics.buffer')!) as List;
        expect(decoded, hasLength(1));
      },
    );
  });
}
