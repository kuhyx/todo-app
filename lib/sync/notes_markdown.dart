import 'package:todo/data/note.dart';
import 'package:todo/images/attachment_links.dart';
import 'package:uuid/uuid.dart';

/// Serialises notes to (and parses them back from) a single Markdown file.
///
/// The whole document is valid Markdown: each note is preceded by an HTML
/// comment carrying its metadata (id, priority, status, timestamps), which
/// renders invisibly, followed by the note body verbatim. Keeping the `id`
/// lets [NoteRepository.importNotes] re-import a file as a *merge* (by id)
/// rather than creating duplicates — the basis for "never lose ideas"
/// recovery and round-tripping a backup.
///
/// Attached-image links are written as their on-disk path on kuhy's PC
/// (`~/data/cloud/todo-images/…`) so an agent reading `BACKLOG.md` can open
/// the picture directly; [parse] turns them back into the dufs URL, so a
/// backup still round-trips exactly.
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
          'updated="${note.updatedAt.toIso8601String()}"'
          '${_taskAttrs(note)} -->',
        )
        ..writeln(toBacklogAttachmentPaths(note.text))
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
      final body = fromBacklogAttachmentPaths(
        content.substring(bodyStart, bodyEnd).trim(),
      );

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
          repo: attrs['repo'],
          doneCheck: attrs['done_check'],
          by: attrs['by'],
          evidence: attrs['evidence'],
          createdBy: attrs['created_by'],
        ),
      );
    }
    return notes;
  }

  /// Extracts `key="value"` pairs; an empty value counts as absent.
  static Map<String, String> _parseAttrs(String raw) {
    return {
      for (final m in _attrPattern.allMatches(raw))
        if (m.group(2)!.isNotEmpty) m.group(1)!: _unescape(m.group(2)!),
    };
  }

  /// Set task fields only, so an idea's marker is unchanged from v3.
  static String _taskAttrs(Note note) => [
    for (final (name, value) in [
      ('repo', note.repo),
      ('done_check', note.doneCheck),
      ('by', note.by),
      ('evidence', note.evidence),
      ('created_by', note.createdBy),
    ])
      if (value != null) ' $name="${_escape(value)}"',
  ].join();

  // Entities keep a value on one line, inside its quotes and the comment.
  static const _entities = {
    '&': '&amp;',
    '"': '&quot;',
    '<': '&lt;',
    '>': '&gt;',
    '\n': '&#10;',
    '\r': '&#13;',
  };
  static final _escapable = RegExp('[&"<>\n\r]');
  static final _entity = RegExp('&(amp|quot|lt|gt|#10|#13);');
  static final Map<String, String> _decode = {
    for (final e in _entities.entries) e.value: e.key,
  };

  static String _escape(String v) =>
      v.replaceAllMapped(_escapable, (m) => _entities[m[0]]!);

  static String _unescape(String v) =>
      v.replaceAllMapped(_entity, (m) => _decode[m[0]]!);

  /// Resolves an enum value by its [Enum.name], falling back to [fallback].
  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    return values.firstWhere((v) => v.name == name, orElse: () => fallback);
  }
}
