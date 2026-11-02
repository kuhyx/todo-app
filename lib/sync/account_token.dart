import 'dart:developer';

import 'package:flutter/services.dart';

/// Talks to `AccountTokenChannel.kt`: system account chooser, then
/// AccountManager's `audience:server:client_id:` token. No browser.
const kAccountTokenChannel = MethodChannel('dev.kuhy.todo/account_token');

/// A Google ID token for [serverClientId], or null on cancel or failure.
Future<String?> accountManagerIdToken({
  required String serverClientId,
  MethodChannel channel = kAccountTokenChannel,
}) async {
  try {
    return await channel.invokeMethod<String>('idToken', {
      'serverClientId': serverClientId,
    });
  } on PlatformException catch (error, stackTrace) {
    log(
      'AccountManager token failed',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}
