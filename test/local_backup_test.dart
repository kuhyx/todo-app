import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/notes_markdown.dart';

void main() {
  Note note(String id, String text) => Note(
    id: id,
    text: text,
    priority: Priority.medium,
    status: Status.todo,
    createdAt: DateTime(2026, 6, 15),
    updatedAt: DateTime(2026, 6, 15),
  );

  group('schedule', () {
    test('zero debounce fetches and writes the markdown immediately', () {
      fakeAsync((async) {
        String? written;
        final backup = LocalBackup(
          fetch: () async => [note('a', '# A')],
          reader: () async => null,
          writer: (md) async => written = md,
          debounce: Duration.zero,
        );

        backup.schedule();
        async.flushMicrotasks(); // drain the async fetch + write
        expect(written, isNotNull);
        expect(written, contains('# A'));
        backup.dispose();
      });
    });

    test('a burst of schedules fetches once, at the latest snapshot', () {
      fakeAsync((async) {
        var fetches = 0;
        var current = [note('a', '# first')];
        final writes = <String>[];
        final backup = LocalBackup(
          fetch: () async {
            fetches++;
            return current;
          },
          reader: () async => null,
          writer: (md) async => writes.add(md),
          debounce: const Duration(seconds: 2),
        );

        backup.schedule();
        async.elapse(const Duration(seconds: 1)); // not yet
        current = [note('a', '# second')]; // pulled lazily at fire time
        backup.schedule(); // resets the timer
        expect(fetches, 0); // nothing pulled while typing
        expect(writes, isEmpty);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(fetches, 1); // two schedules → a single export
        expect(writes, hasLength(1));
        expect(writes.single, contains('# second'));
        backup.dispose();
      });
    });

    test('dispose cancels a pending write', () {
      fakeAsync((async) {
        var calls = 0;
        final backup = LocalBackup(
          fetch: () async => [note('a', '# x')],
          reader: () async => null,
          writer: (_) async => calls++,
          debounce: const Duration(seconds: 2),
        );

        backup.schedule();
        backup.dispose();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(calls, 0); // timer was cancelled before it could fetch/write
      });
    });
  });

  group('recover', () {
    test('parses a backup file into notes', () async {
      final markdown = NotesMarkdown.export([note('a', '# Recovered')]);
      final backup = LocalBackup(
        fetch: () async => const <Note>[],
        reader: () async => markdown,
        writer: (_) async {},
      );

      final recovered = await backup.recover();
      expect(recovered, hasLength(1));
      expect(recovered.single.text, contains('# Recovered'));
    });

    test('returns empty when there is no backup file', () async {
      final backup = LocalBackup(
        fetch: () async => const <Note>[],
        reader: () async => null,
        writer: (_) async {},
      );
      expect(await backup.recover(), isEmpty);
    });

    test('returns empty when the backup file is blank', () async {
      final backup = LocalBackup(
        fetch: () async => const <Note>[],
        reader: () async => '   \n  ',
        writer: (_) async {},
      );
      expect(await backup.recover(), isEmpty);
    });
  });
}
