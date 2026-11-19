/// Pulls the peers whose logs changed, all at once and off the UI thread.
///
/// Split out of `sync_service.dart` for file size. A peer's log is about
/// 2 MB; pulling eight of them one after another, each parsed on the UI
/// isolate, kept the phone's sync spinner up for 3.9 s (todo:0c575b891b).
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/sync/off_thread.dart';

/// One peer file's pull result: its decoded [log] and revision, or a null
/// [log] when the file vanished, failed decryption or did not parse.
typedef PulledPeer = ({String name, String peer, Log? log, String? rev});

/// Fetches [names] (file names under [dir]) concurrently.
///
/// [knownRevs] holds each peer's published revision; a peer without one gets
/// its revision computed from the downloaded text. Any failure other than an
/// [E2eDecryptError] fails the pull, exactly as a sequential loop would.
Future<List<PulledPeer>> pullPeers(
  RemoteStore remote,
  String dir,
  List<String> names,
  Map<String, String> knownRevs,
) => Future.wait([
  for (final name in names) _pull(remote, dir, name, knownRevs[peerOf(name)]),
], eagerError: true);

/// Peer id of a `<peer>.json` file name.
String peerOf(String name) =>
    name.endsWith('.json') ? name.substring(0, name.length - 5) : name;

Future<PulledPeer> _pull(
  RemoteStore remote,
  String dir,
  String name,
  String? knownRev,
) async {
  final peer = peerOf(name);
  final String? text;
  try {
    text = await remote.getFileText('$dir/$name');
  } on E2eDecryptError {
    // Wrong key, tampered blob or a newer format: skipped and reported,
    // never merged and never fatal.
    return (name: name, peer: peer, log: null, rev: null);
  }
  if (text == null) return (name: name, peer: peer, log: null, rev: null);
  final (log, rev) = await _decodeOffThread(text, knownRev);
  return (name: name, peer: peer, log: log, rev: rev);
}

/// Below this many characters a log parses faster than an isolate starts.
const int _offThreadMinLength = 64 * 1024;

/// Kept separate so the isolate closure captures only [text] and [knownRev].
Future<(Log?, String)> _decodeOffThread(String text, String? knownRev) async {
  (Log?, String) decode() => (decodeLog(text), knownRev ?? revisionOf(text));
  return text.length < _offThreadMinLength ? decode() : await offThread(decode);
}

/// Parses a remote note log, returning `null` for a corrupt or wrong-shape
/// payload so one bad device file never aborts the whole sync.
Log? decodeLog(String text) {
  try {
    return logFromJson(text);
  } on FormatException {
    return null;
  }
  // crdt_sync's logFromJson throws a raw TypeError (not a custom
  // exception) for a wrong-shape JSON payload from an untrusted peer
  // file; must be caught too so one bad device file never aborts the
  // whole sync (see doc comment above).
  // ignore: avoid_catching_errors
  on TypeError {
    return null;
  }
}
