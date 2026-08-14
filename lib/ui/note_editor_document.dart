/// The editor's text state: the template, the controllers, and which of the
/// two sources (raw body vs. per-section fields) is currently authoritative.
///
/// Split out of `note_editor.dart` for file size, and it is the honest seam:
/// none of this needs a `BuildContext` or a `setState` — it is the model the
/// widget renders. `_NoteEditorState` still drives every transition and still
/// owns when to rebuild; this class just holds the text and converts between
/// the two sources.
///
/// The two-source design is what keeps non-conforming text safe: text that
/// does not fit the template is never forced through it, it stays verbatim in
/// [body] and the editor shows the raw field instead.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note_template.dart';

/// Holds a note's editable text for one [NoteTemplate].
class NoteEditorDocument {
  /// Creates a document for [template]; call [load] to put text in it.
  NoteEditorDocument(this.template);

  /// Builds the document a freshly-mounted editor should start from.
  ///
  /// With an explicit [template] the text is simply loaded into it. Without
  /// one the template is *detected*: text that cleanly fits the design-spec
  /// template adopts it, and anything else (freeform, legacy, hand-mangled)
  /// stays a raw body under [NoteTemplate.blank], untouched.
  ///
  /// [openingRaw] keeps the raw body authoritative even for conforming text.
  /// Without it, typing into a Raw field would silently update the hidden,
  /// unused section controllers instead of what `onChanged` emits.
  factory NoteEditorDocument.forInitialText(
    String text, {
    required NoteTemplate? template,
    required bool openingRaw,
  }) {
    if (template != null) {
      return NoteEditorDocument(template)
        ..load(template, text, preferGuided: !openingRaw);
    }
    final parsed = parse(NoteTemplate.llmDesignSpec, text);
    if (!parsed.conforms) {
      return NoteEditorDocument(NoteTemplate.blank)
        ..rawSource = true
        ..body.text = text;
    }
    final doc = NoteEditorDocument(NoteTemplate.llmDesignSpec);
    if (openingRaw) {
      doc
        ..rawSource = true
        ..body.text = text;
    } else {
      doc.adoptSections(parsed.values);
    }
    return doc;
  }

  /// The template the text is authored against.
  NoteTemplate template;

  /// Whether the editable content currently lives in [body] (raw source)
  /// rather than the per-section controllers (guided source). Preview keeps
  /// whichever source was last active so [currentText] stays correct.
  bool rawSource = true;

  /// Single field used for the freeform [NoteTemplate.blank] body and for raw
  /// mode of a structured template.
  final TextEditingController body = TextEditingController();

  /// One controller per structured section (keyed by section key).
  final Map<String, TextEditingController> section = {};

  /// Ensures a controller exists for every section of [forTemplate].
  void ensureControllers(NoteTemplate forTemplate) {
    for (final s in forTemplate.sections) {
      section.putIfAbsent(s.key, TextEditingController.new);
    }
  }

  /// Writes [values] into the per-section controllers.
  void fillSections(Map<String, String> values) {
    ensureControllers(template);
    for (final s in template.sections) {
      section[s.key]!.text = values[s.key] ?? '';
    }
  }

  /// Loads [text] into [forTemplate], choosing the guided source when it
  /// conforms (or when [preferGuided] and the text is empty) and the raw body
  /// otherwise.
  void load(
    NoteTemplate forTemplate,
    String text, {
    required bool preferGuided,
  }) {
    template = forTemplate;
    if (forTemplate.isFreeform) {
      rawSource = true;
      body.text = text;
      return;
    }
    final parsed = parse(forTemplate, text);
    if (parsed.conforms || (preferGuided && text.trim().isEmpty)) {
      rawSource = false;
      fillSections(parsed.values);
    } else {
      rawSource = true;
      body.text = text;
    }
  }

  /// Adopts [values] as the guided source, making the section fields
  /// authoritative.
  ///
  /// The raw -> guided direction, once the caller has confirmed the text
  /// still conforms to the template.
  void adoptSections(Map<String, String> values) {
    fillSections(values);
    rawSource = false;
  }

  /// Tries to make the section fields authoritative, for raw -> guided.
  ///
  /// Returns false and changes nothing when the edited raw text no longer
  /// fits the template — the caller keeps the editor in raw and says so,
  /// rather than forcing text through a template it does not match.
  /// Empty text always succeeds: there is nothing to lose.
  bool tryAdoptGuided() {
    if (!rawSource) return true;
    final parsed = parse(template, body.text);
    if (!parsed.conforms && body.text.trim().isNotEmpty) return false;
    adoptSections(parsed.values);
    return true;
  }

  /// Moves the editable content into the raw body, leaving it authoritative.
  ///
  /// Used on guided -> raw so the assembled text is what the user then edits.
  void materialiseToRaw() {
    if (rawSource) return;
    body.text = currentText();
    rawSource = true;
  }

  /// The current note text, assembled from whichever source is active.
  String currentText() {
    if (rawSource) return body.text;
    final values = {
      for (final s in template.sections) s.key: section[s.key]?.text ?? '',
    };
    return assemble(template, values);
  }

  /// Disposes every controller this document owns.
  void dispose() {
    for (final c in section.values) {
      c.dispose();
    }
    body.dispose();
  }
}
