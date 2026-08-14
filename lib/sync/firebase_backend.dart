/// Wiring for the Firebase backend, during and after the GitHub cutover.
///
/// A barrel over the three files this was split into for size. Import this one
/// and you get the whole backend API, exactly as before the split:
///
/// * `firebase_project.dart` — [kProject], the public project identifiers.
/// * `firebase_account_store.dart` — the account and refresh token, in the OS
///   keystore, plus the desktop wrapper's self-provisioning fallback.
/// * `firebase_client.dart` — opening a signed-in client, and reporting
///   whether this device can authenticate at all.
///
/// Split by what is safe to publish, because this repo is public: the project
/// identifiers already ship inside the APK and are protected by the security
/// rules rather than by secrecy, while the account email and password are
/// entered once per device and kept in the OS keystore, next to the GitHub
/// token this app already stores there.
///
/// Nothing here reads `~/.config/crdt-sync/` — that is the desktop/Python
/// half. On Android there is no such file.
library;

export 'firebase_account_store.dart';
export 'firebase_client.dart';
export 'firebase_project.dart';
