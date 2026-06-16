/// Structured note templates and the pure text <-> sections conversion.
///
/// The whole point of a template is that the user fills it, then copies the
/// note verbatim into an LLM, and the LLM has everything it needs to start
/// work. So this layer is deliberately *pure* (no Flutter, no IO): the UI is
/// just a view over [assemble]/[parse], and the canonical storage stays plain
/// text (CRDT body + markdown export are unchanged).
///
/// The assembled format is Markdown: an `#` title, then one `##` section per
/// *filled* field with a one-line italic guidance under the heading. The
/// guidance is kept in the stored note on purpose — the note is pasted
/// verbatim to an LLM, so the description of what each section means must
/// travel with it.
///
/// Design invariants (see the round-trip tests):
///   * The **template** defines which sections exist; the stored text only
///     carries values. Parsing an unknown/legacy note never invents sections.
///   * `assemble(parse(text))` is idempotent for any text that *conforms* to a
///     template, so opening and closing a structured note never mutates it.
///   * Text that does **not** conform (freeform notes, the old `what —` format,
///     hand-mangled raw edits) is reported as such so the UI can fall back to a
///     raw editor and show it verbatim — we never force non-conforming text
///     into the guided stepper and never drop a line we couldn't place.
library;

/// One field of a structured template.
class TemplateSection {
  const TemplateSection({
    required this.key,
    required this.label,
    required this.helper,
    this.hint = '',
    this.inline = true,
    this.isTitle = false,
  });

  /// Stable identifier for the section (also used as the values-map key).
  final String key;

  /// The Markdown heading written into the stored text (e.g. `## what`), and
  /// shown in the stepper. The title section has no heading of its own.
  final String label;

  /// One-line guidance: *what* to write here and *why* the LLM needs it.
  /// Shown in the stepper and embedded as an italic line under the section's
  /// heading in the stored note.
  final String helper;

  /// Placeholder shown in the empty input.
  final String hint;

  /// Whether the stepper renders a single-line input (title/what/…) versus a
  /// multi-line input for list-shaped sections (must/nice/out/refs). Purely a
  /// UI hint; the stored format is the same for both.
  final bool inline;

  /// The title section is special: it has no `##` heading and is stored as the
  /// note's `#` title line.
  final bool isTitle;
}

/// A named template: an ordered list of [sections]. A template with no
/// sections is *freeform* (a single plain-text body, no structure).
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.label,
    required this.sections,
  });

  /// Stable identifier persisted alongside UI state (e.g. `llm-design-spec`).
  final String id;

  /// Human-readable name shown in the template picker.
  final String label;

  /// Ordered sections. Empty for the freeform [blank] template.
  final List<TemplateSection> sections;

  /// Whether this template has no structure (just a plain-text body).
  bool get isFreeform => sections.isEmpty;

  /// The LLM-oriented design-spec template (the default). Mirrors the user's
  /// backlog format; every section carries a self-documenting guidance line so
  /// the pasted note tells the LLM how to read it.
  static const NoteTemplate llmDesignSpec = NoteTemplate(
    id: 'llm-design-spec',
    label: 'LLM design spec',
    sections: [
      TemplateSection(
        key: 'title',
        label: '',
        isTitle: true,
        hint: 'Imperative title',
        helper: "One-line imperative summary — becomes the note's heading.",
      ),
      TemplateSection(
        key: 'what',
        label: 'what',
        hint: 'The concrete thing, 1–3 sentences',
        helper: 'The concrete thing to build, in 1–3 sentences — the goal.',
      ),
      TemplateSection(
        key: 'where',
        label: 'where',
        hint: 'repo + files/paths, or new app: <name>',
        helper:
            "Repo + target files/paths (not terminal dumps), or "
            "'new app: <name>', and platform(s).",
      ),
      TemplateSection(
        key: 'tech',
        label: 'tech',
        hint: 'language/framework@version, key libraries',
        helper:
            'Tech stack with versions (e.g. Flutter 3.32, Dart 3.8, '
            'sqlite_crdt 0.5). Tells the agent the exact environment.',
      ),
      TemplateSection(
        key: 'must',
        label: 'must',
        inline: false,
        hint: '- required behaviour',
        helper:
            'Required behaviours the agent should do without asking, '
            'one per line — hard requirements.',
      ),
      TemplateSection(
        key: 'ask',
        label: 'ask',
        inline: false,
        hint: '- decision needing your approval before proceeding',
        helper:
            'High-impact decisions where the agent must stop and confirm '
            'with you first (e.g. schema changes, deleting data). '
            'Leave blank if none.',
      ),
      TemplateSection(
        key: 'nice',
        label: 'nice',
        inline: false,
        hint: '- optional behaviour',
        helper:
            'Optional behaviours; skipping them is fine. '
            'Leave blank if none.',
      ),
      TemplateSection(
        key: 'never',
        label: 'never',
        inline: false,
        hint: '- hard stop / explicitly out of scope',
        helper:
            'Hard stops and explicitly out-of-scope items — '
            'agent must not do these. Prevents gold-plating and '
            'dangerous actions. Leave blank if none.',
      ),
      TemplateSection(
        key: 'done',
        label: 'done',
        hint: 'I can X and Y happens',
        helper:
            "Observable success: 'I can X and Y happens' — used to verify "
            'completion.',
      ),
      TemplateSection(
        key: 'depends',
        label: 'depends',
        hint: 'prerequisite tasks/notes',
        helper: 'Prerequisite tasks/notes. Leave blank if none.',
      ),
      TemplateSection(
        key: 'estimate',
        label: 'estimate',
        hint: 'S | M | L',
        helper: 'Rough size: S / M / L.',
      ),
      TemplateSection(
        key: 'refs',
        label: 'refs',
        inline: false,
        hint: 'links/docs the agent should read',
        helper:
            'Links/docs/code the agent should read first, one per line. '
            'Leave blank if none.',
      ),
    ],
  );

  /// An empty, structure-free template.
  static const NoteTemplate blank = NoteTemplate(
    id: 'blank',
    label: 'Blank',
    sections: [],
  );

  /// All selectable templates, default first.
  static const List<NoteTemplate> all = [llmDesignSpec, blank];

  /// The default template applied to new notes.
  static const NoteTemplate defaultTemplate = llmDesignSpec;
}

/// Result of parsing stored text against a template.
class ParsedNote {
  const ParsedNote({required this.values, required this.conforms});

  /// Section-key -> value (trimmed). Sections absent from the text map to ''.
  final Map<String, String> values;

  /// Whether [text] cleanly matched [template]. When false the UI must show
  /// the text in a raw editor rather than the guided stepper.
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
