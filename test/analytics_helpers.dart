/// The fake FirebaseRestClient used by the analytics tests.
///
/// Shared by the files `analytics_service_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';

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
