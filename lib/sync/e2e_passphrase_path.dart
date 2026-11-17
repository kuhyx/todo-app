/// Path of the wrapper's one-shot passphrase route.
///
/// Kept apart from `e2e_passphrase_source.dart` (which needs Flutter) so the
/// dart-only desktop wrapper can import it; `dart build cli` fails on any
/// transitive `dart:ui`.
library;

/// The route the wrapper serves the passphrase on, once.
const kSyncE2ePassphrasePath = '/sync-e2e-passphrase';
