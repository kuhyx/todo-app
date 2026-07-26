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
///     the pre-2026-07 twelve-section spec, hand-mangled raw edits) is reported
///     as such so the UI can fall back to a raw editor and show it verbatim —
///     we never force non-conforming text into the guided stepper and never
///     drop a line we couldn't place.
library;

/// One field of a structured template.
class TemplateSection {
  /// Creates a [TemplateSection] from its field/label/helper text.
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
  /// multi-line input for list-shaped sections (must/read first). Purely a
  /// UI hint; the stored format is the same for both.
  final bool inline;

  /// The title section is special: it has no `##` heading and is stored as the
  /// note's `#` title line.
  final bool isTitle;
}

/// A named template: an ordered list of [sections]. A template with no
/// sections is *freeform* (a single plain-text body, no structure).
class NoteTemplate {
  /// Creates a [NoteTemplate] from its id, label, and [sections].
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

  /// The LLM-oriented design-spec template (the default). Every section carries
  /// a self-documenting guidance line so the pasted note tells the LLM how to
  /// read it.
  ///
  /// The section set is deliberately small. It was cut from twelve to seven in
  /// 2026-07 after auditing 514 real sessions: `estimate` was referenced in 1
  /// of 22 note-driven sessions, `ask` changed the agent's asking behaviour not
  /// at all (92% ask rate without it vs 100% with), and `tech` lost to the
  /// agent just opening `pubspec.yaml`. `verify` is the one addition — the
  /// single most repeated correction in the corpus was "test it yourself, on
  /// the phone". See `docs/llm-design-spec-audit.md`.
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
        hint: 'repo + files/paths, or new app: <name> + stack',
        helper:
            'Repo + target files/paths (not terminal dumps), or '
            "'new app: <name>' with the stack and versions. Name the repo "
            'that actually owns the fix, even if it is not the obvious one.',
      ),
      TemplateSection(
        key: 'must',
        label: 'must',
        inline: false,
        hint: '- required behaviour / must not: hard stop',
        helper:
            'Required behaviours the agent does without asking, one per '
            "line. Prefix a hard stop with 'must not:' and an optional "
            "extra with 'optional:'.",
      ),
      TemplateSection(
        key: 'done',
        label: 'done',
        hint: 'a threshold, a guarantee, or a check command',
        helper:
            'Observable success as a threshold, a guarantee, or a command '
            "whose output settles it — not a sentence. 'Feels better' is "
            "not done; '0 dropped frames at 4K' is.",
      ),
      TemplateSection(
        key: 'verify',
        label: 'verify',
        hint: 'phone / desktop, and the exact command',
        helper:
            'Where and how this gets checked: which device, the exact '
            'command, the real deploy path. Blank means desktop, any way '
            'you like.',
      ),
      TemplateSection(
        key: 'refs',
        label: 'read first',
        inline: false,
        hint: 'links/docs/code/screenshots to read before starting',
        helper:
            'Links, docs, code and reference screenshots the agent must '
            'read before starting, one per line. Say whether a screenshot '
            'is the format to copy or the content. Leave blank if none.',
      ),
    ],
  );

  /// Section labels this template used to have and no longer does.
  ///
  /// An unknown `## heading` is normally treated as *content* — the user may
  /// write subheadings inside a value. A retired label is different: it is a
  /// section the template once owned, so folding it into the preceding
  /// section's value and calling the note conforming would let the stepper
  /// silently swallow it on the next save. Seeing one means "this note was
  /// written against an older template" → non-conforming → raw editor.
  static const Set<String> retiredLabels = {
    'tech',
    'ask',
    'nice',
    'never',
    'out',
    'depends',
    'estimate',
    'refs',
  };

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
  /// Creates a [ParsedNote] from its parsed [values] and [conforms] flag.
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
