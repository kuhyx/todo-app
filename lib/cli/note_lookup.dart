import 'package:todo/cli/cli_args.dart';
import 'package:todo/data/note.dart';

const _minPrefix = 8;

/// No note, or more than one, matches an id argument; [message] says which.
class NoteLookupError extends FormatException {
  NoteLookupError._(super.message);

  @override
  String toString() => message;
}

/// The note with id [ref], else the only one whose id starts with [ref].
Note findNote(Iterable<Note> notes, String ref) {
  final exact = notes.where((n) => n.id == ref).firstOrNull;
  if (exact != null) return exact;
  if (ref.length < _minPrefix) {
    throw NoteLookupError._(
      'no live note with id $ref (an id prefix needs at least '
      '$_minPrefix characters)',
    );
  }
  final matches = notes.where((n) => n.id.startsWith(ref)).toList();
  if (matches.isEmpty) throw NoteLookupError._('no live note with id $ref');
  if (matches.length > 1) {
    throw NoteLookupError._(
      'id prefix $ref matches ${matches.length} notes; give more of the id:\n'
      '${matches.map((n) => '  ${n.id}  ${_title(n)}').join('\n')}',
    );
  }
  return matches.single;
}

/// `<8-char id>\t<status>\t<priority>\t<repo or ->\t<title>`.
String listLine(Note note) => [
  if (note.id.length <= _minPrefix)
    note.id
  else
    note.id.substring(0, _minPrefix),
  CliArgs.statusName(note.status),
  note.priority.name,
  note.repo ?? '-',
  _title(note),
].join('\t');

String _title(Note note) => note.text.split('\n').first;
