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

  group('scheduleExport', () {
    test('zero debounce writes the exported markdown immediately', () {
      String? written;
      final backup = LocalBackup(
        reader: () async => null,
        writer: (md) async => written = md,
        debounce: Duration.zero,
      );

      backup.scheduleExport([note('a', '# A')]);
      expect(written, isNotNull);
      expect(written, contains('# A'));
      backup.dispose();
    });

    test('debounced writes coalesce to the latest snapshot', () {
      fakeAsync((async) {
        final writes = <String>[];
        final backup = LocalBackup(
          reader: () async => null,
          writer: (md) async => writes.add(md),
          debounce: const Duration(seconds: 2),
        );

        backup.scheduleExport([note('a', '# first')]);
        async.elapse(const Duration(seconds: 1)); // not yet
        backup.scheduleExport([note('a', '# second')]); // resets the timer
        expect(writes, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(writes, hasLength(1));
        expect(writes.single, contains('# second'));
        backup.dispose();
      });
    });

    test('dispose cancels a pending write', () {
      fakeAsync((async) {
        var calls = 0;
        final backup = LocalBackup(
          reader: () async => null,
          writer: (_) async => calls++,
          debounce: const Duration(seconds: 2),
        );

        backup.scheduleExport([note('a', '# x')]);
        backup.dispose();
        async.elapse(const Duration(seconds: 5));

        expect(calls, 0); // timer was cancelled
      });
    });
  });

  group('recover', () {
    test('parses a backup file into notes', () async {
      final markdown = NotesMarkdown.export([note('a', '# Recovered')]);
      final backup = LocalBackup(
        reader: () async => markdown,
        writer: (_) async {},
      );

      final recovered = await backup.recover();
      expect(recovered, hasLength(1));
      expect(recovered.single.text, contains('# Recovered'));
    });

    test('returns empty when there is no backup file', () async {
      final backup = LocalBackup(
        reader: () async => null,
        writer: (_) async {},
      );
      expect(await backup.recover(), isEmpty);
    });

    test('returns empty when the backup file is blank', () async {
      final backup = LocalBackup(
        reader: () async => '   \n  ',
        writer: (_) async {},
      );
      expect(await backup.recover(), isEmpty);
    });
  });
}
