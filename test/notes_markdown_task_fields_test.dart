// BACKLOG.md markers carry the repo-task attributes, escaped so any value
// survives the single-line `<!-- @note ... -->` marker.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/sync/notes_markdown.dart';

Note _note({String? repo, String? doneCheck, String? by, String? evidence}) {
  final at = DateTime.utc(2026, 11, 2, 9);
  return Note(
    id: 'n1',
    text: 'Title\n\nbody',
    priority: Priority.high,
    status: Status.done,
    createdAt: at,
    updatedAt: at,
    repo: repo,
    doneCheck: doneCheck,
    by: by,
    evidence: evidence,
  );
}

void _expectSameTaskFields(Note actual, Note expected) {
  expect(actual.repo, expected.repo);
  expect(actual.doneCheck, expected.doneCheck);
  expect(actual.by, expected.by);
  expect(actual.evidence, expected.evidence);
}

void main() {
  test('a plain idea exports no task attributes (byte-identical marker)', () {
    final out = NotesMarkdown.export([_note()]);
    expect(
      out,
      contains(
        '<!-- @note id="n1" priority="high" status="done" '
        'created="2026-11-02T09:00:00.000Z" '
        'updated="2026-11-02T09:00:00.000Z" -->\n',
      ),
    );
    _expectSameTaskFields(NotesMarkdown.parse(out).single, _note());
  });

  test('task attributes are exported and parsed back', () {
    final task = _note(
      repo: 'kuhyx/todo',
      doneCheck: 'test -f "a b" && echo \'ok\' --> done',
      by: 'claude',
      evidence: 'abc1234 exit 0',
    );
    final out = NotesMarkdown.export([task]);
    expect(out, contains('repo="kuhyx/todo"'));
    expect(out, contains('by="claude"'));
    // The value can never close the comment or the attribute early.
    final marker = out.split('\n').firstWhere((l) => l.contains('@note'));
    expect('-->'.allMatches(marker), hasLength(1));
    final parsed = NotesMarkdown.parse(out).single;
    _expectSameTaskFields(parsed, task);
    expect(parsed.text, task.text);
  });

  test('an empty attribute value reads back as absent', () {
    const doc = '<!-- @note id="x" repo="" evidence="" -->\nbody\n';
    final parsed = NotesMarkdown.parse(doc).single;
    expect(parsed.repo, isNull);
    expect(parsed.evidence, isNull);
  });

  test('property: hostile attribute values round-trip (seeded)', () {
    // Characters that break naive markers: quotes, the comment closer,
    // entity look-alikes (double-decoding), newlines and non-ASCII.
    const alphabet = [
      '"',
      "'",
      '<',
      '>',
      '-',
      '--',
      '-->',
      '&',
      '&quot;',
      '&amp;',
      '&#10;',
      '\n',
      '\r',
      '\t',
      ' ',
      '=',
      'a',
      'Z',
      '0',
      '/',
      r'\',
      'ż',
      '🙂',
    ];
    final random = Random(20261102);
    String value() => [
      for (var i = random.nextInt(12) + 1; i > 0; i--)
        alphabet[random.nextInt(alphabet.length)],
    ].join();
    for (var run = 0; run < 300; run++) {
      final task = _note(
        repo: value(),
        doneCheck: value(),
        by: value(),
        evidence: value(),
      );
      final parsed = NotesMarkdown.parse(NotesMarkdown.export([task]));
      expect(parsed, hasLength(1), reason: 'run $run');
      _expectSameTaskFields(parsed.single, task);
      expect(parsed.single.text, task.text, reason: 'run $run');
    }
  });
}
