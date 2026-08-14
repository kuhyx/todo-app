/// The pumpMirror harness and the fake url_launcher.
///
/// Shared by the files `github_mirror_screen_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/github_mirror_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fake_note_repository.dart';
import 'fake_secure_storage.dart';

/// Stub launcher that records the URL instead of opening it, so `_openPage`
/// can be exercised without a real platform channel.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  String? launched;

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched = url;
    return true;
  }
}

Future<FakeNoteRepository> pumpMirror(
  WidgetTester tester, {
  SyncSettings initial = const SyncSettings(
    owner: 'kuhyx',
    repo: 'syncs',
    token: 't',
  ),
  http.Client? httpClient,
  FakeNoteRepository? repository,
  Future<FirebaseRestClient?> Function()? firebaseFactory,
  ValueNotifier<AppSettings>? appSettings,
}) async {
  SharedPreferences.setMockInitialValues({});
  installFakeSecureStorage();
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = repository ?? FakeNoteRepository();
  addTearDown(repo.close);
  await tester.pumpWidget(
    MaterialApp(
      home: GitHubMirrorScreen(
        initial: initial,
        repository: repo,
        appSettings:
            appSettings ??
            ValueNotifier(const AppSettings(advancedMode: false)),
        httpClient: httpClient,
        firebaseFactory: firebaseFactory ?? () async => null,
        stateStore: InMemorySyncStateStore(),
      ),
    ),
  );
  await tester.pump();
  return repo;
}
