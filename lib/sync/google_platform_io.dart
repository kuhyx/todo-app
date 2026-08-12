/// Whether the programmatic Google sign-in flow exists on this platform.
///
/// The io half: Android has the Credential Manager flow; Linux desktop does
/// not, and this app's desktop build is the web one anyway.
library;

import 'dart:io';

/// True only on Android, the one platform shipping the programmatic flow.
bool get googleSignInSupported => Platform.isAndroid;
