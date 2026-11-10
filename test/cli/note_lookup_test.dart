import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/note_lookup.dart';
import 'package:todo/data/note.dart';

import 'cli_harness.dart';

void main() {
  final notes = [
    fixtureNote('abcdefgh', 'Exact'),
    fixtureNote('abcdefgh-2', 'Longer'),
    fixtureNote('12345678-a', 'First\nbody'),
    fixtureNote('12345678-b', 'Second'),
    fixtureNote('99999999-z', 'Only', repo: 'kuhyx/todo'),
  ];

  test('an exact id wins over a longer id sharing it as prefix', () {
    expect(findNote(notes, 'abcdefgh').text, 'Exact');
  });

  test('a unique prefix of at least 8 characters resolves', () {
    expect(findNote(notes, '99999999').text, 'Only');
    expect(findNote(notes, '99999999-').text, 'Only');
  });

  test('an ambiguous prefix names every candidate', () {
    expect(
      () => findNote(notes, '12345678'),
      throwsA(
        isA<NoteLookupError>().having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('2 notes'),
            contains('12345678-a  First'),
            contains('12345678-b  Second'),
          ]),
        ),
      ),
    );
  });

  test('an unknown id is not found', () {
    expect(
      () => findNote(notes, 'ffffffff'),
      throwsA(
        isA<NoteLookupError>().having(
          (e) => e.message,
          'message',
          'no live note with id ffffffff',
        ),
      ),
    );
  });

  test('a short non-exact id is not prefix-matched', () {
    expect(
      () => findNote(notes, 'abc'),
      throwsA(
        isA<NoteLookupError>().having(
          (e) => e.message,
          'message',
          allOf(contains('no live note with id abc'), contains('8 characters')),
        ),
      ),
    );
  });

  test('listLine: 8-char id, status, priority, repo, title, author', () {
    expect(
      listLine(notes[2].copyWith(status: Status.inProgress)),
      '12345678\tin_progress\tmedium\t-\tFirst\tkuhy',
    );
    expect(
      listLine(notes[4]),
      '99999999\ttodo\tmedium\tkuhyx/todo\tOnly\tkuhy',
    );
    expect(listLine(fixtureNote('abc', 'Short')), startsWith('abc\t'));
  });
}
