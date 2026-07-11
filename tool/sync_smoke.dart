// Headless end-to-end proof of the sync engine against a REAL GitHub repo.
//
// Simulates two devices (A and B), each creating a note offline, then syncs
// them through the repo and asserts both devices converge to both notes.
// Cleans up its throwaway log files afterwards so the real `notes/` directory
// is never touched.
//
// Run:  GH_TOKEN=$(gh auth token) dart run tool/sync_smoke.dart
import 'dart:io';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/github_client.dart';
import 'package:todo/sync/sync_service.dart';

Future<void> main() async {
  final token = Platform.environment['GH_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('Set GH_TOKEN (e.g. GH_TOKEN=\$(gh auth token)).');
    exit(2);
  }

  // Throwaway directory so we never pollute the real `notes/`.
  const service = SyncService(notesDir: 'todo-sync/notes_smoketest');
  GitHubClient client() =>
      GitHubClient(owner: 'kuhyx', repo: 'syncs', token: token);

  final deviceA = await NoteRepository.openInMemory();
  final deviceB = await NoteRepository.openInMemory();
  final stamp = DateTime.now().toIso8601String();

  await _insert(deviceA, 'Idea from device A @ $stamp');
  await _insert(deviceB, 'Idea from device B @ $stamp');

  stdout.writeln('Device A nodeId: ${deviceA.nodeId}');
  stdout.writeln('Device B nodeId: ${deviceB.nodeId}');

  // Sync order: A pushes, B pulls A + pushes, A pulls B. Both converge.
  final ghA = client();
  final ghB = client();
  stdout.writeln('A.sync(): ${await service.sync(deviceA, ghA)}');
  stdout.writeln('B.sync(): ${await service.sync(deviceB, ghB)}');
  stdout.writeln('A.sync(): ${await service.sync(deviceA, ghA)}');

  final aNotes = (await deviceA.listNotes()).map((n) => n.text).toSet();
  final bNotes = (await deviceB.listNotes()).map((n) => n.text).toSet();
  stdout.writeln('\nDevice A sees: $aNotes');
  stdout.writeln('Device B sees: $bNotes');

  final expected = {
    'Idea from device A @ $stamp',
    'Idea from device B @ $stamp',
  };
  final converged =
      aNotes.containsAll(expected) && bNotes.containsAll(expected);

  // Cleanup: remove the throwaway log files.
  final cleanup = client();
  for (final f in await cleanup.listDirectory('todo-sync/notes_smoketest')) {
    await cleanup.deleteFile(f.path, f.sha, message: 'smoke test cleanup');
  }
  stdout.writeln('Cleaned up throwaway log files.');

  ghA.close();
  ghB.close();
  cleanup.close();
  await deviceA.close();
  await deviceB.close();

  if (converged) {
    stdout.writeln(
      '\n✅ PASS: both devices converged to both notes via GitHub.',
    );
    exit(0);
  } else {
    stdout.writeln('\n❌ FAIL: devices did not converge. Expected $expected.');
    exit(1);
  }
}

Future<void> _insert(NoteRepository repo, String text) async {
  final now = DateTime.now();
  await repo.upsert(
    Note(
      id: '${now.microsecondsSinceEpoch}-${text.hashCode}',
      text: text,
      priority: Priority.medium,
      status: Status.todo,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
