import 'package:flutter/material.dart';

import '../data/note_template.dart';
import 'markdown_view.dart';

/// Which view of the note the editor is currently showing.
enum NoteEditorMode {
  /// Read-only rendered Markdown (headings, guidance, bullets).
  preview,

  /// Inline [Stepper], one step per template section.
  guided,

  /// A single text field showing the assembled Markdown verbatim.
  raw,
}

/// A guided editor for a note's text, shared by the capture and detail
/// screens.
///
/// It is a *view* over plain text: it parses [initialText] into template
/// sections and reports the re-assembled text through [onChanged] on every
/// edit. Storage stays plain text, so sync and markdown export are unaffected.
///
/// Modes (see [NoteEditorMode]):
///   * **Preview** — the note rendered as Markdown, read-only.
///   * **Guided** — an inline [Stepper], one step per template section, each
///     with guidance on what to write and why the LLM needs it.
///   * **Raw** — a single text field showing the assembled text verbatim.
///
/// Non-conforming or freeform text never enters the guided stepper (we never
/// force it into the template), so for such text Guided is unavailable and the
/// editable source stays the raw body, preserving the user's content.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    required this.onChanged,
    this.initialText = '',
    this.initialTemplate,
    this.initialMode = NoteEditorMode.guided,
    this.autofocus = false,
    super.key,
  });

  /// Called with the freshly assembled note text on every edit.
  final ValueChanged<String> onChanged;

  /// Existing note text to load. Empty for a fresh draft.
  final String initialText;

  /// Template to author with. When null the template is detected from
  /// [initialText] (used when opening an existing note).
  final NoteTemplate? initialTemplate;

  /// Preferred mode to open in. Falls back to [NoteEditorMode.raw] when
  /// [NoteEditorMode.guided] is requested for text that can't be guided
  /// (freeform template or non-conforming content).
  final NoteEditorMode initialMode;

  /// Autofocus the first field, so a fresh capture needs zero taps before
  /// typing — preserving the app's instant-capture invariant.
  final bool autofocus;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late NoteTemplate _template;
  late NoteEditorMode _mode;

  /// Whether the editable content currently lives in [_body] (raw source)
  /// rather than the per-section controllers (guided source). Preview keeps
  /// whichever source was last active so [_currentText] stays correct.
  late bool _rawSource;

  int _currentStep = 0;

  /// One controller per structured section (keyed by section key).
  final Map<String, TextEditingController> _section = {};

  /// Single field used for the freeform [NoteTemplate.blank] body and for raw
  /// mode of a structured template.
  final TextEditingController _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTemplate;
    if (initial != null) {
      _template = initial;
      _loadSource(initial, widget.initialText, preferGuided: true);
    } else {
      // Detect: does the text cleanly fit the design-spec template?
      final parsed = parse(NoteTemplate.llmDesignSpec, widget.initialText);
      if (parsed.conforms) {
        _template = NoteTemplate.llmDesignSpec;
        _rawSource = false;
        _fillSections(parsed.values);
      } else {
        // Freeform / legacy / hand-mangled — keep it as a raw body, untouched.
        _template = NoteTemplate.blank;
        _rawSource = true;
        _body.text = widget.initialText;
      }
    }
    _mode = _resolveMode(widget.initialMode);
  }

  @override
  void dispose() {
    for (final c in _section.values) {
      c.dispose();
    }
    _body.dispose();
    super.dispose();
  }

  /// Whether the guided stepper can be *opened* right now: a structured
  /// template whose current source still fits the template. Used to decide the
  /// initial mode; the Guided segment itself is offered for any structured
  /// template (a switch that no longer conforms is blocked at switch time).
  bool get _canOpenGuided => !_template.isFreeform && !_rawSource;

  /// Picks the mode to actually display: honours [desired] unless Guided was
  /// asked for when it can't be opened, in which case fall back to Raw.
  NoteEditorMode _resolveMode(NoteEditorMode desired) {
    if (desired == NoteEditorMode.guided && !_canOpenGuided) {
      return NoteEditorMode.raw;
    }
    return desired;
  }

  /// Ensures a controller exists for every section of [template].
  void _ensureControllers(NoteTemplate template) {
    for (final s in template.sections) {
      _section.putIfAbsent(s.key, () => TextEditingController());
    }
  }

  void _fillSections(Map<String, String> values) {
    _ensureControllers(_template);
    for (final s in _template.sections) {
      _section[s.key]!.text = values[s.key] ?? '';
    }
  }

  /// Loads [text] into [template], choosing the guided source when it conforms
  /// (or when [preferGuided] and the text is empty) and the raw body otherwise.
  void _loadSource(
    NoteTemplate template,
    String text, {
    required bool preferGuided,
  }) {
    if (template.isFreeform) {
      _rawSource = true;
      _body.text = text;
      return;
    }
    final parsed = parse(template, text);
    if (parsed.conforms || (preferGuided && text.trim().isEmpty)) {
      _rawSource = false;
      _fillSections(parsed.values);
    } else {
      _rawSource = true;
      _body.text = text;
    }
  }

  /// The current note text, assembled from whichever source is active.
  String _currentText() {
    if (_rawSource) return _body.text;
    final values = {
      for (final s in _template.sections) s.key: _section[s.key]?.text ?? '',
    };
    return assemble(_template, values);
  }

  void _emit() => widget.onChanged(_currentText());

  void _switchTemplate(NoteTemplate next) {
    if (next.id == _template.id) return;
    final text = _currentText();
    setState(() {
      _template = next;
      _currentStep = 0;
      _loadSource(next, text, preferGuided: true);
      _mode = _resolveMode(_mode);
    });
    _emit();
  }

  /// Switches the displayed mode, converting the editable source as needed.
  void _setMode(NoteEditorMode next) {
    if (next == _mode) return;
    setState(() {
      switch (next) {
        case NoteEditorMode.guided:
          if (_rawSource) {
            // raw -> guided: only if the edited text still fits the template.
            final parsed = parse(_template, _body.text);
            if (!parsed.conforms && _body.text.trim().isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Text doesn't match the template — staying in raw",
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            _fillSections(parsed.values);
            _rawSource = false;
          }
          _currentStep = 0;
          _mode = NoteEditorMode.guided;
        case NoteEditorMode.raw:
          if (!_rawSource) {
            // guided -> raw: materialise the assembled text into the body.
            _body.text = _currentText();
            _rawSource = true;
          }
          _mode = NoteEditorMode.raw;
        case NoteEditorMode.preview:
          // Read-only render of the current source; nothing to convert.
          _mode = NoteEditorMode.preview;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _template.id,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Template',
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            for (final t in NoteTemplate.all)
              DropdownMenuItem(value: t.id, child: Text(t.label)),
          ],
          onChanged: (id) {
            if (id == null) return;
            _switchTemplate(NoteTemplate.all.firstWhere((t) => t.id == id));
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<NoteEditorMode>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: NoteEditorMode.preview,
                icon: Icon(Icons.visibility_outlined),
                label: Text('View'),
              ),
              // Guided is offered for any structured template; switching to it
              // is blocked at switch time if the raw text no longer conforms.
              if (!_template.isFreeform)
                const ButtonSegment(
                  value: NoteEditorMode.guided,
                  icon: Icon(Icons.checklist),
                  label: Text('Guided'),
                ),
              const ButtonSegment(
                value: NoteEditorMode.raw,
                icon: Icon(Icons.notes),
                label: Text('Raw'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_mode) {
      case NoteEditorMode.preview:
        return MarkdownView(text: _currentText());
      case NoteEditorMode.raw:
        return _buildRaw(theme);
      case NoteEditorMode.guided:
        return _buildStepper(theme);
    }
  }

  Widget _buildRaw(ThemeData theme) {
    return TextField(
      controller: _body,
      autofocus: widget.autofocus,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      style: theme.textTheme.bodyLarge,
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Write your idea…',
      ),
      onChanged: (_) => _emit(),
    );
  }

  Widget _buildStepper(ThemeData theme) {
    _ensureControllers(_template);
    final sections = _template.sections;
    return SingleChildScrollView(
      child: Stepper(
        currentStep: _currentStep.clamp(0, sections.length - 1),
        physics: const NeverScrollableScrollPhysics(),
        onStepTapped: (i) => setState(() => _currentStep = i),
        onStepContinue: _currentStep < sections.length - 1
            ? () => setState(() => _currentStep++)
            : null,
        onStepCancel: _currentStep > 0
            ? () => setState(() => _currentStep--)
            : null,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (details.onStepContinue != null)
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: const Text('Next'),
                  ),
                if (details.onStepCancel != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          for (var i = 0; i < sections.length; i++)
            _stepFor(theme, sections[i], i),
        ],
      ),
    );
  }

  Step _stepFor(ThemeData theme, TemplateSection section, int index) {
    final controller = _section[section.key]!;
    final hasValue = controller.text.trim().isNotEmpty;
    return Step(
      title: Text(section.isTitle ? 'title' : section.label),
      state: hasValue
          ? StepState.complete
          : (index == _currentStep ? StepState.editing : StepState.indexed),
      isActive: index <= _currentStep,
      content: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.helper,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: widget.autofocus && index == 0,
              maxLines: section.inline ? 1 : null,
              minLines: section.inline ? 1 : 3,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: section.hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              // Rebuild so the step's completion tick reflects the new value.
              onChanged: (_) {
                setState(() {});
                _emit();
              },
            ),
          ],
        ),
      ),
    );
  }
}
