import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/ui/images/file_opening.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the URL instead of opening a browser.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<(String, String?)> launched = [];
  bool succeed = true;

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.webOnlyWindowName));
    return succeed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('open_file');
  final calls = <Map<Object?, Object?>>[];

  void answer(int type, String message) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments as Map<Object?, Object?>);
          return jsonEncode({'type': type, 'message': message});
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('a local file goes to the app that handles its type', () async {
    answer(0, 'done');
    expect(
      await openAttachedFile(const LocalImageSource('/c/a.pdf'), 'a.pdf'),
      isNull,
    );
    expect(calls.single['file_path'], '/c/a.pdf');
  });

  test('no handler or a failure says so', () async {
    answer(-1, 'No APP found');
    expect(
      await openAttachedFile(const LocalImageSource('/c/a.xyz'), 'a.xyz'),
      'No app on this phone opens a.xyz',
    );
    answer(-4, 'File opened incorrectly');
    expect(
      await openAttachedFile(const LocalImageSource('/c/a.pdf'), 'a.pdf'),
      'Could not open a.pdf: File opened incorrectly',
    );
  });

  test('the desktop opens the wrapper copy, named, in a new tab', () async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    const source = NetworkImageSource(
      'http://localhost:8730/images/n/u.pdf?r=2',
    );
    expect(await openAttachedFile(source, 'Raport v2.pdf'), isNull);
    final (url, window) = launcher.launched.single;
    expect(Uri.parse(url).queryParameters, {'r': '2', 'name': 'Raport v2.pdf'});
    expect(window, '_blank');
    launcher.succeed = false;
    expect(await openAttachedFile(source, 'a.pdf'), 'Could not open a.pdf');
  });

  test('a file not on this device cannot be opened', () async {
    expect(
      await openAttachedFile(const MissingImageSource(), 'a.pdf'),
      'a.pdf is not on this device yet',
    );
  });
}
