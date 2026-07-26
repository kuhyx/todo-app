// One-shot migration of exported notes from the pre-2026-07 twelve-section
// `llm-design-spec` template to the audited seven-section one.
//
// Why a file transform and not a database migration: the desktop app is the
// web build, so the notes live in IndexedDB inside the fixed Chrome profile —
// a CLI tool cannot reach them. The supported path is
// Settings → Export → run this → Settings → Import, which routes through
// [NoteRepository.importNotes] and merges by id.
//
// Folding rules (nothing is dropped silently — everything dropped is reported):
//   tech        -> appended to `where`
//   never / out -> `must`, as `must not: …` lines (a literal "none" is skipped)
//   nice        -> `must`, as `optional: …` lines
//   ask / depends / estimate -> dropped, listed per note in the report
//
// Usage:
//   dart run tool/migrate_backlog.dart BACKLOG.md            # dry run
//   dart run tool/migrate_backlog.dart BACKLOG.md --apply -o out.md
import 'dart:io';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/sync/notes_markdown.dart';

/// Matches a `## label` heading, capturing the label.
final _heading = RegExp(r'^## (.+)$');

/// Splits a legacy note body into `title` plus one entry per `## section`.
///
/// Deliberately independent of [parse]: that function is bound to the *current*
/// template, and the twelve-section one it replaced no longer exists in `lib/`.
Map<String, String> _parseLegacy(String text) {
  final values = <String, String>{};
  final titleLines = <String>[];
  String? current;
  final blocks = <String, List<String>>{};

  for (final line in text.split('\n')) {
    final match = _heading.firstMatch(line);
    if (match != null) {
      current = match.group(1)!.trim();
      blocks.putIfAbsent(current, () => <String>[]);
      continue;
    }
    if (current != null) {
      blocks[current]!.add(line);
      continue;
    }
    final trimmed = line.trim();
    if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
      titleLines.add(trimmed.substring(2).trim());
    }
  }

  values['title'] = titleLines.join('\n').trim();
  for (final entry in blocks.entries) {
    values[entry.key] = _stripGuidance(entry.value);
  }
  return values;
}

/// Drops leading blanks and the italic guidance line from a section block.
String _stripGuidance(List<String> lines) {
  final out = List<String>.from(lines);
  var i = 0;
  while (i < out.length && out[i].trim().isEmpty) {
    i++;
  }
  if (i < out.length) {
    final t = out[i].trim();
    if (t.length >= 2 && t.startsWith('_') && t.endsWith('_')) out.removeAt(i);
  }
  return out.join('\n').trim();
}

/// Folds a retired section's [value] into `must` as `- <prefix>: …` lines.
///
/// Only a section whose every non-empty line is already a bullet becomes one
/// bullet per line. Anything else is prose — several old `nice`/`never`
/// sections hold pasted terminal output — and is kept as a single item with
/// its block indented underneath, rather than being shredded into one bogus
/// bullet per line.
///
/// A placeholder "none" yields nothing: five old notes wrote it instead of
/// leaving the section blank.
List<String> _foldInto(String prefix, String value) {
  final lines = value.split('\n');
  final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
  if (nonEmpty.isEmpty) return const [];
  if (nonEmpty.length == 1 && nonEmpty.first.trim().toLowerCase() == 'none') {
    return const [];
  }

  final bulleted = RegExp(r'^\s*[-*]\s+');
  if (nonEmpty.every(bulleted.hasMatch)) {
    return nonEmpty
        .map((l) => '- $prefix: ${l.replaceFirst(bulleted, '').trim()}')
        .toList();
  }
  return ['- $prefix:', ...lines.map((l) => l.isEmpty ? l : '  $l')];
}

/// What happened to one note, for the report.
class _Outcome {
  _Outcome(this.note, {required this.folded, required this.dropped});

  final Note note;
  final List<String> folded;
  final List<String> dropped;
}

/// Rewrites [note] under the current template, or returns null if its body has
/// no retired sections (freeform notes and already-migrated ones).
_Outcome? _migrate(Note note, DateTime stamp) {
  final old = _parseLegacy(note.text);
  final retired = old.keys.where(NoteTemplate.retiredLabels.contains).toList();
  if (retired.isEmpty) return null;

  final folded = <String>[];
  final dropped = <String>[];

  final where = <String>[
    if ((old['where'] ?? '').isNotEmpty) old['where']!,
  ];
  if ((old['tech'] ?? '').isNotEmpty) {
    where.add(old['tech']!);
    folded.add('tech -> where');
  }

  final must = <String>[
    if ((old['must'] ?? '').trim().isNotEmpty) old['must']!.trim(),
  ];
  for (final entry in [
    ('never', 'must not'),
    ('out', 'must not'),
    ('nice', 'optional'),
  ]) {
    final folded_ = _foldInto(entry.$2, old[entry.$1] ?? '');
    if (folded_.isEmpty) continue;
    must.addAll(folded_);
    folded.add('${entry.$1} -> must');
  }

  for (final key in ['ask', 'depends', 'estimate']) {
    if ((old[key] ?? '').isNotEmpty) dropped.add(key);
  }

  final text = assemble(NoteTemplate.llmDesignSpec, {
    'title': old['title'] ?? '',
    'what': old['what'] ?? '',
    'where': where.join('\n'),
    'must': must.join('\n'),
    'done': old['done'] ?? '',
    // `verify` is new: nothing in a legacy note maps to it.
    'verify': '',
    'refs': old['refs'] ?? '',
  });

  // Gate, not a warning: a note that does not conform would open in the raw
  // editor, which is exactly what the migration exists to avoid.
  if (!parse(NoteTemplate.llmDesignSpec, text).conforms) {
    throw StateError('migrated note ${note.id} does not conform');
  }
  // Nothing may vanish except the sections we deliberately drop. Compare the
  // surviving source lines against the result.
  final kept = {...old.keys}..removeAll(['ask', 'depends', 'estimate']);
  for (final key in kept) {
    for (final line in (old[key] ?? '').split('\n')) {
      final needle = line.trim().replaceFirst(RegExp(r'^[-*]\s*'), '').trim();
      if (needle.isEmpty || needle.toLowerCase() == 'none') continue;
      if (!text.contains(needle)) {
        throw StateError('note ${note.id}: lost a line from "$key": $needle');
      }
    }
  }

  return _Outcome(
    // The bumped timestamp is what makes the import win. `importNotes` stamps
    // the CRDT record at the note's own edit time precisely so a re-import does
    // not beat other devices just by being recent — so without this the phone
    // would silently keep the old text.
    note.copyWith(text: text, updatedAt: stamp),
    folded: folded,
    dropped: dropped,
  );
}

void main(List<String> args) {
  final apply = args.contains('--apply');
  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/migrate_backlog.dart <BACKLOG.md> '
      '[--apply] [-o <out.md>]',
    );
    exitCode = 2;
    return;
  }

  final input = File(positional.first);
  if (!input.existsSync()) {
    stderr.writeln('error: ${input.path} does not exist');
    exitCode = 2;
    return;
  }

  final oi = args.indexOf('-o');
  final outPath = oi >= 0 && oi + 1 < args.length
      ? args[oi + 1]
      : '${input.path}.migrated.md';

  final notes = NotesMarkdown.parse(input.readAsStringSync());
  final stamp = DateTime.now();

  final result = <Note>[];
  final outcomes = <_Outcome>[];
  for (final note in notes) {
    final outcome = _migrate(note, stamp);
    if (outcome == null) {
      result.add(note); // untouched: freeform, or already on the new template
      continue;
    }
    result.add(outcome.note);
    outcomes.add(outcome);
  }

  stdout
    ..writeln('${notes.length} notes read from ${input.path}')
    ..writeln('${outcomes.length} carry retired sections and were rewritten')
    ..writeln('${notes.length - outcomes.length} left untouched\n');
  for (final o in outcomes) {
    final id = o.note.id.substring(0, 8);
    stdout.writeln('  $id  ${noteTitle(o.note.text)}');
    if (o.folded.isNotEmpty) {
      stdout.writeln('        folded : ${o.folded.join(', ')}');
    }
    if (o.dropped.isNotEmpty) {
      stdout.writeln('        DROPPED: ${o.dropped.join(', ')}');
    }
  }

  if (!apply) {
    stdout.writeln('\ndry run — nothing written. Re-run with --apply.');
    return;
  }
  File(outPath).writeAsStringSync(NotesMarkdown.export(result));
  stdout.writeln('\nwrote $outPath — import it via Settings -> Import notes.');
}
