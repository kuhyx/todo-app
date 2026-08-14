/// The shared Firebase project identifiers.
///
/// Its own file because both halves of the backend (the account store and the
/// client factory) need it, and neither should have to import the other.
///
/// Safe to publish, and this repo is public: [kProject] holds the Web API key
/// and database URL, both public identifiers that already ship inside the APK.
/// The security rules, not their secrecy, are what protect the data. The
/// account credentials live in the OS keystore instead — see
/// `firebase_account_store.dart`.
library;

import 'package:crdt_sync/crdt_sync.dart';

/// The shared `kuhy-syncs` project.
///
/// `databaseUrl` is the **regional** host. The plain `*.firebaseio.com` form
/// answers 404 with a `correctUrl` body rather than an obvious error, which
/// reads like an auth failure and wastes a debugging session.
const kProject = FirebaseProject(
  apiKey: 'AIzaSyCF_sA3xCMehAYXK8eND-rAygb9NXXW_8E',
  databaseUrl:
      'https://kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app',
);
