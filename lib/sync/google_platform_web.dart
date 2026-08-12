/// Whether the programmatic Google sign-in flow exists on this platform.
///
/// The web half: Google Identity Services signs in only through its own
/// rendered button, so `authenticate()` throws `UnimplementedError` here.
library;

/// Always false: the web plugin has no programmatic sign-in.
bool get googleSignInSupported => false;
