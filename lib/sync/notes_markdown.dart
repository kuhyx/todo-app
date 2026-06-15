import 'package:uuid/uuid.dart';

import '../data/note.dart';

/// Serialises notes to (and parses them back from) a single Markdown file.
///
/// The whole document is valid Markdown: each note is preceded by an HTML
/// comment carrying its metadata (id, priority, status, timestamps), which
/// renders invisibly, followed by the note body verbatim. Keeping the `id`
/// lets [NoteRepository.importNotes] re-import a file as a *merge* (by id)
/// rather than creating duplicates — the basis for "never lose ideas"
/// recovery and round-tripping a backup.
class NotesMarkdown {
  // Private ctor: this is a static-only utility class, never instantiated.
  const NotesMarkdown._(); // coverage:ignore-line

  static const _uuid = Uuid();

  /// First line of an exported file; identifies the format/version.
  static const header = '<!-- todo-backlog v1 -->';

  /// Matches a per-note metadata marker at the start of a line. The body is
  /// everything between one marker and the next (or end of file).
  static final _markerPattern = RegExp(
    r'^<!--\s*@note\s+(.*?)\s*-->[ \t]*$',
    multiLine: true,
  );

  /// Matches `key="value"` attribute pairs inside a marker.
  static final _attrPattern = RegExp(r'(\w+)="([^"]*)"');

  /// Renders [notes] to a single Markdown document.
  static String export(List<Note> notes) {
    final buffer = StringBuffer()
      ..writeln(header)
      ..writeln();
    for (final note in notes) {
      buffer
        ..writeln(
          '<!-- @note id="${note.id}" priority="${note.priority.name}" '
          'status="${note.status.name}" '
          'created="${note.createdAt.toIso8601String()}" '
          'updated="${note.updatedAt.toIso8601String()}" -->',
        )
        ..writeln(note.text)
        ..writeln();
    }
    return buffer.toString();
  }

  /// Parses a previously exported (or hand-written) document back into notes.
  ///
  /// Tolerant by design: a missing/blank `id` gets a fresh UUID (treated as
  /// a new note), and unknown/missing priority/status/timestamps fall back
  /// to sensible defaults so a partially hand-edited file never throws.
  static List<Note> parse(String content) {
    final markers = _markerPattern.allMatches(content).toList();
    final notes = <Note>[];
    for (var i = 0; i < markers.length; i++) {
      final marker = markers[i];
      final attrs = _parseAttrs(marker.group(1) ?? '');
      final bodyStart = marker.end;
      final bodyEnd = i + 1 < markers.length
          ? markers[i + 1].start
          : content.length;
      final body = content.substring(bodyStart, bodyEnd).trim();

      final id = attrs['id'];
      notes.add(
        Note(
          id: (id != null && id.isNotEmpty) ? id : _uuid.v4(),
          text: body,
          priority: _enumByName(
            Priority.values,
            attrs['priority'],
            Priority.defaultValue,
          ),
          status: _enumByName(Status.values, attrs['status'], Status.todo),
          createdAt:
              DateTime.tryParse(attrs['created'] ?? '') ?? DateTime.now(),
          updatedAt:
              DateTime.tryParse(attrs['updated'] ?? '') ?? DateTime.now(),
        ),
      );
    }
    return notes;
  }

  /// Extracts `key="value"` pairs from a marker's attribute string.
  static Map<String, String> _parseAttrs(String raw) {
    return {
      for (final m in _attrPattern.allMatches(raw)) m.group(1)!: m.group(2)!,
    };
  }

  /// Resolves an enum value by its [Enum.name], falling back to [fallback].
  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    return values.firstWhere((v) => v.name == name, orElse: () => fallback);
  }
}
