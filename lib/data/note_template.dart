/// Structured note templates: the section types and the template data.
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
/// The conversion itself ([assemble], [parse], [noteTitle], [isBareLink]) lives
/// in `note_template_parser.dart` and is re-exported below, so importing this
/// file still gets the whole template API in one import.
library;

// Imported as well as exported: `export` re-publishes the parser to this
// library's importers but does not bring its names into scope here, and
// NoteTemplate.forDraft calls isBareLink.
import 'package:todo/data/note_template_parser.dart';

export 'note_template_parser.dart';

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

  /// The template a *draft* of [text] should be authored with.
  ///
  /// A bare link gets [blank]: a third of the freeform notes in the backlog are
  /// nothing but a pasted URL, and walking a seven-step spec stepper to file a
  /// link is pure friction. Everything else keeps [defaultTemplate].
  static NoteTemplate forDraft(String text) =>
      isBareLink(text) ? blank : defaultTemplate;
}
