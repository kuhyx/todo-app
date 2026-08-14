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

  group('AnalyticsEvent', () {
    test('round-trips through toJson/tryFromJson', () {
      final event = AnalyticsEvent(
        name: 'screen_view',
        timestamp: DateTime(2026, 1, 1, 12),
        params: {'screen': 'capture'},
      );
      final decoded = AnalyticsEvent.tryFromJson(event.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.name, 'screen_view');
      expect(decoded.timestamp, event.timestamp);
      expect(decoded.params, {'screen': 'capture'});
    });

    test('tryFromJson returns null for a non-map value', () {
      expect(AnalyticsEvent.tryFromJson('not a map'), isNull);
      expect(AnalyticsEvent.tryFromJson(null), isNull);
    });

    test('tryFromJson returns null for a missing/invalid name', () {
      expect(
        AnalyticsEvent.tryFromJson({'timestamp': '2026-01-01T00:00:00.000'}),
        isNull,
      );
    });

    test('tryFromJson returns null for an unparsable timestamp', () {
      expect(
        AnalyticsEvent.tryFromJson({'name': 'x', 'timestamp': 'not a date'}),
        isNull,
      );
    });

    test('tryFromJson defaults params to empty when missing/non-map', () {
      final decoded = AnalyticsEvent.tryFromJson({
        'name': 'x',
        'timestamp': DateTime(2026).toIso8601String(),
      });
      expect(decoded!.params, isEmpty);
    });
  });

  group('AnalyticsService.logEvent', () {
    test('appends to an initially empty buffer', () async {
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime.now()),
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('analytics.buffer');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(decoded, hasLength(1));
    });

    test('drops the oldest event once past the cap', () async {
      const service = AnalyticsService(nodeId: 'device-a');
      for (var i = 0; i < AnalyticsService.maxBufferedEvents + 5; i++) {
        await service.logEvent(
          AnalyticsEvent(
            name: 'event_$i',
            timestamp: DateTime.now(),
          ),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('analytics.buffer')!) as List;
      expect(decoded, hasLength(AnalyticsService.maxBufferedEvents));
      // The oldest 5 events were dropped, so event_0..event_4 are gone.
      final names = decoded.map((e) => (e as Map)['name']).toList();
      expect(names, isNot(contains('event_0')));
      expect(
        names,
        contains('event_${AnalyticsService.maxBufferedEvents + 4}'),
      );
    });

    test('ignores a malformed pre-existing buffer entry on read', () async {
      SharedPreferences.setMockInitialValues({
        'analytics.buffer': jsonEncode([
          {'not': 'an event'},
          {
            'name': 'ok_event',
            'timestamp': DateTime(2026).toIso8601String(),
            'params': <String, Object?>{},
          },
        ]),
      });
      const service = AnalyticsService(nodeId: 'device-a');
      await service.logEvent(
        AnalyticsEvent(name: 'new_event', timestamp: DateTime.now()),
      );

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('analytics.buffer')!) as List;
      // The malformed entry was dropped; only the valid + new event remain.
      expect(decoded, hasLength(2));
    });
  });
}
