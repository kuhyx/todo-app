/// The pure text <-> sections conversion for [NoteTemplate].
///
/// Split out of `note_template.dart` (which now owns only the template types
/// and the template data) purely for file size; `note_template.dart` re-exports
/// everything here, so callers import that one file as before.
///
/// Design invariants (see the round-trip tests):
///   * The **template** defines which sections exist; the stored text only
///     carries values. Parsing an unknown/legacy note never invents sections.
///   * `assemble(parse(text))` is idempotent for any text that *conforms* to a
///     template, so opening and closing a structured note never mutates it.
///   * Text that does **not** conform (freeform notes, the old `what —` format,
///     the pre-2026-07 twelve-section spec, hand-mangled raw edits) is reported
///     as such so the UI can fall back to a raw editor and show it verbatim —
///     we never force non-conforming text into the guided stepper and never
///     drop a line we couldn't place.
library;

import 'package:todo/data/note_template.dart';

/// Matches a single `http(s)://…` token.
final RegExp _linkPattern = RegExp(r'^https?://\S+$');

/// Whether [text] is nothing but one or more links.
///
/// Deliberately strict: one word of context ("read this https://…") means the
/// note has prose in it and is no longer a bare link.
bool isBareLink(String text) {
  final tokens = text.trim().split(RegExp(r'\s+'))
    ..removeWhere((t) => t.isEmpty);
  if (tokens.isEmpty) return false;
  return tokens.every(_linkPattern.hasMatch);
}

/// Result of parsing stored text against a template.
class ParsedNote {
  /// Creates a [ParsedNote] from its parsed [values] and [conforms] flag.
  const ParsedNote({required this.values, required this.conforms});

  /// Section-key -> value (trimmed). Sections absent from the text map to ''.
  final Map<String, String> values;

  /// Whether the text cleanly matched the template. When false the UI must
  /// show the text in a raw editor rather than the guided stepper.
  final bool conforms;
}

/// Builds the stored note text from section [values], dropping empty sections
/// so the pasted note carries no blank scaffold for the LLM to wade through.
///
/// [template] fixes the section order; [values] is keyed by section key. Each
/// present section becomes a `## label` heading, an italic guidance line, and
/// the value.
String assemble(NoteTemplate template, Map<String, String> values) {
  if (template.isFreeform) return (values['body'] ?? '').trimRight();

  final blocks = <String>[];
  final title = (values['title'] ?? '').trim();
  if (title.isNotEmpty) blocks.add('# $title');

  for (final section in template.sections) {
    if (section.isTitle) continue;
    final value = (values[section.key] ?? '').trim();
    if (value.isEmpty) continue; // drop empty sections
    blocks.add('## ${section.label}\n_${section.helper}_\n\n$value');
  }
  return blocks.join('\n\n');
}

/// Parses stored [text] into section values for the given [template].
///
/// Freeform templates always conform: the whole text is the `body` value.
/// For structured templates the text conforms only if it uses the Markdown
/// section headings, those headings are known and in template order without
/// repeats, and nothing but the `#` title sits before the first section.
/// Anything else (freeform, the old `what —` format) is reported as
/// non-conforming so the caller can show it raw, untouched.
ParsedNote parse(NoteTemplate template, String text) {
  if (template.isFreeform) {
    return ParsedNote(values: {'body': text}, conforms: true);
  }

  // Index of each non-title section in template order, used to detect
  // out-of-order or duplicate headings.
  final order = <String, int>{};
  var oi = 0;
  for (final s in template.sections) {
    if (!s.isTitle) order[s.key] = oi++;
  }

  final values = <String, String>{for (final s in template.sections) s.key: ''};
  final lines = text.split('\n');

  final titleLines = <String>[];
  String? currentKey; // open section accumulating its block lines
  final blocks = <String, List<String>>{};
  var lastOrder = -1;
  var sawSection = false;
  var conforms = true;

  for (final line in lines) {
    final heading = _matchHeading(line, template);
    if (heading != null) {
      sawSection = true;
      final idx = order[heading.key]!;
      if (idx <= lastOrder) conforms = false; // out of order / duplicate
      lastOrder = idx;
      currentKey = heading.key;
      blocks[heading.key] = <String>[];
      continue;
    }
    // A heading the template retired means the note predates the current
    // section set. Keep the line as content (we never drop one) but refuse to
    // call the note conforming, so the UI shows it raw instead of letting the
    // stepper fold the retired section into its neighbour on the next save.
    if (_isRetiredHeading(line)) conforms = false;
    if (currentKey != null) {
      blocks[currentKey]!.add(line);
      continue;
    }
    // Still before the first section: only the `#` title and blanks belong.
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
      titleLines.add(trimmed.substring(2).trim());
    } else {
      conforms = false; // stray content before the first section
    }
  }

  values['title'] = titleLines.join('\n').trim();
  for (final entry in blocks.entries) {
    values[entry.key] = _stripGuidance(entry.value).trim();
  }

  // A structured note with no recognised section headings is really freeform.
  if (!sawSection) conforms = false;

  return ParsedNote(values: values, conforms: conforms);
}

/// The note's display title: the `#` heading text without its `#` marker, or
/// the first non-empty line for freeform notes.
String noteTitle(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
  }
  return '';
}

/// Returns the section whose `## label` heading is on [line], or null. Only
/// known section labels are treated as headings, so a `## subheading` the user
/// wrote inside a value is preserved as content rather than splitting the note.
TemplateSection? _matchHeading(String line, NoteTemplate template) {
  if (!line.startsWith('## ')) return null;
  final label = line.substring(3).trim();
  for (final s in template.sections) {
    if (!s.isTitle && s.label == label) return s;
  }
  return null;
}

/// Whether [line] is a `## heading` naming a section the template retired.
bool _isRetiredHeading(String line) {
  if (!line.startsWith('## ')) return false;
  return NoteTemplate.retiredLabels.contains(line.substring(3).trim());
}

/// Drops the leading blank lines and the single italic guidance line (if any)
/// from a section's block, leaving just the user's value.
String _stripGuidance(List<String> lines) {
  final out = List<String>.from(lines);
  var i = 0;
  while (i < out.length && out[i].trim().isEmpty) {
    i++;
  }
  if (i < out.length) {
    final t = out[i].trim();
    if (t.length >= 2 && t.startsWith('_') && t.endsWith('_')) {
      out.removeAt(i);
    }
  }
  return out.join('\n');
}
