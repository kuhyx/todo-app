import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake for the `flutter_secure_storage` platform channel so tests
/// never touch the real OS keystore. Install it from a test (or `setUp`) and it
/// auto-removes on tear down.
///
/// Pass [throwing] to simulate a host with no secret service: every call raises
/// a [PlatformException], which exercises the plaintext-fallback paths in
/// [SyncSettings].
void installFakeSecureStorage({
  Map<String, String>? initial,
  bool throwing = false,
}) {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{...?initial};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(channel, (call) async {
    if (throwing) {
      throw PlatformException(code: 'unavailable');
    }
    final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key!] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'containsKey':
        return store.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
      default:
        return null;
    }
  });

  addTearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
}
