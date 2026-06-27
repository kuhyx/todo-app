import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/note_template.dart';
import 'markdown_view.dart';

/// Which view of the note the editor is currently showing.
enum NoteEditorMode {
  /// Read-only rendered Markdown (headings, guidance, bullets).
  preview,

  /// Full-screen per-step view, one step per template section.
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
///   * **Guided** — a full-screen per-step view, one step per template
///     section, with guidance on what to write and why the LLM needs it.
///   * **Raw** — a single text field showing the assembled text verbatim.
///
/// Non-conforming or freeform text never enters the guided stepper (we never
/// force it into the template), so for such text Guided is unavailable and the
/// editable source stays the raw body, preserving the user's content.
///
/// Entering Guided on an empty draft first runs a two-step wizard (priority,
/// then template) via [onPriorityChanged], since those choices only make
/// sense once, before there's anything to guide. Guided itself — wizard or
/// bare step page — hides the template/mode chrome entirely (just a back arrow
/// to return to Raw); [onChromeVisibleChanged] tells the parent screen to
/// hide its own priority/status row in sync.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    required this.onChanged,
    required this.priority,
    required this.onPriorityChanged,
    required this.onChromeVisibleChanged,
    this.initialText = '',
    this.initialTemplate,
    this.initialMode = NoteEditorMode.guided,
    this.autofocus = false,
    super.key,
  });

  /// Called with the freshly assembled note text on every edit.
  final ValueChanged<String> onChanged;

  /// The note's current priority, shown as the wizard's starting selection.
  final Priority priority;

  /// Called when the priority wizard step is confirmed (Guided "Start").
  final ValueChanged<Priority> onPriorityChanged;

  /// Called whenever the editor's own chrome (template dropdown, mode
  /// selector) is shown/hidden, so the parent screen can hide its
  /// priority/status row in sync while Guided (wizard or bare stepper) is
  /// active.
  final ValueChanged<bool> onChromeVisibleChanged;

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

  /// Whether the priority+template entry wizard is showing in place of the
  /// normal chrome. True only between tapping Guided on an empty draft and
  /// either "Start" (which flips to bare Guided) or "Cancel" (back to Raw).
  bool _enteringGuided = false;

  /// Which wizard step (0: priority, 1: template) is showing.
  int _wizardStep = 0;

  /// Working copies of the wizard's two choices, committed on "Start".
  Priority _wizardPriority = Priority.defaultValue;
  NoteTemplate _wizardTemplate = NoteTemplate.defaultTemplate;

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
      // Only prefer the guided (sections) source for an empty draft when the
      // caller actually wants to open in Guided — an empty Raw draft (the new
      // default) must keep the raw body as its source, or typing into the Raw
      // field would silently update the (hidden, unused) section controllers
      // instead of what's emitted via onChanged.
      _loadSource(
        initial,
        widget.initialText,
        preferGuided: widget.initialMode != NoteEditorMode.raw,
      );
    } else {
      // Detect: does the text cleanly fit the design-spec template?
      final parsed = parse(NoteTemplate.llmDesignSpec, widget.initialText);
      if (parsed.conforms) {
        _template = NoteTemplate.llmDesignSpec;
        // Same Raw/source consistency rule as above: an explicit Raw request
        // must keep the raw body as the source even for conforming text.
        if (widget.initialMode == NoteEditorMode.raw) {
          _rawSource = true;
          _body.text = widget.initialText;
        } else {
          _rawSource = false;
          _fillSections(parsed.values);
        }
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

  void _goToStep(int index) {
    setState(() {
      _currentStep = index.clamp(0, _template.sections.length - 1);
    });
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
          if (_currentText().trim().isEmpty) {
            // Fresh, empty draft: priority and template are meaningful
            // choices only once, so ask for them before showing the stepper.
            _enteringGuided = true;
            _wizardStep = 0;
            _wizardPriority = widget.priority;
            _wizardTemplate = NoteTemplate.defaultTemplate;
          } else {
            // Existing content: priority/template are already settled, so
            // skip straight to the bare stepper rather than re-asking.
            _mode = NoteEditorMode.guided;
          }
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
    widget.onChromeVisibleChanged(
      !_enteringGuided && _mode != NoteEditorMode.guided,
    );
  }

  /// Commits the wizard's template choice and enters the bare stepper.
  /// Distinct from [_switchTemplate]: that short-circuits when the template
  /// is unchanged, which would skip flipping out of the wizard here.
  void _enterGuidedWithTemplate(NoteTemplate template) {
    final text = _currentText();
    setState(() {
      _template = template;
      _currentStep = 0;
      _loadSource(template, text, preferGuided: true);
      _mode = NoteEditorMode.guided;
      _enteringGuided = false;
    });
    _emit();
    widget.onChromeVisibleChanged(false);
  }

  /// Aborts the wizard, returning to Raw with the chrome restored.
  void _cancelWizard() {
    setState(() => _enteringGuided = false);
    widget.onChromeVisibleChanged(true);
  }

  /// Exits the bare stepper back to Raw, restoring the chrome.
  void _exitGuided() {
    setState(() {
      if (!_rawSource) {
        _body.text = _currentText();
        _rawSource = true;
      }
      _mode = NoteEditorMode.raw;
    });
    widget.onChromeVisibleChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_enteringGuided) return _buildGuidedEntryWizard(theme);

    // Guided (the bare stepper) hides the template/mode chrome entirely —
    // that's the point of "Guided": just the stepper, no top-bar noise. A
    // single back arrow is the only way out, restoring the full chrome.
    final bareGuided = _mode == NoteEditorMode.guided;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bareGuided)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Exit guided',
              onPressed: _exitGuided,
            ),
          )
        else ...[
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
                // Guided is offered for any structured template; tapping it
                // on an empty draft opens the wizard (see _setMode), and is
                // blocked at switch time if the raw text no longer conforms.
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
        ],
        const SizedBox(height: 12),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  /// The two-step priority -> template wizard shown before a fresh draft
  /// enters Guided. Replaces the normal chrome entirely (see [build]).
  Widget _buildGuidedEntryWizard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: _cancelWizard,
            ),
            Text(
              'Step ${_wizardStep + 1} of 2',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_wizardStep == 0)
          ..._buildWizardPriorityStep()
        else
          ..._buildWizardTemplateStep(),
      ],
    );
  }

  List<Widget> _buildWizardPriorityStep() {
    return [
      DropdownButtonFormField<Priority>(
        initialValue: _wizardPriority,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Priority',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          for (final p in Priority.values)
            DropdownMenuItem(value: p, child: Text(p.label)),
        ],
        onChanged: (p) {
          if (p != null) setState(() => _wizardPriority = p);
        },
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => setState(() => _wizardStep = 1),
          child: const Text('Next'),
        ),
      ),
    ];
  }

  List<Widget> _buildWizardTemplateStep() {
    final templates = NoteTemplate.all.where((t) => !t.isFreeform).toList();
    return [
      DropdownButtonFormField<String>(
        initialValue: _wizardTemplate.id,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Template',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          for (final t in templates)
            DropdownMenuItem(value: t.id, child: Text(t.label)),
        ],
        onChanged: (id) {
          if (id == null) return;
          setState(
            () => _wizardTemplate = templates.firstWhere((t) => t.id == id),
          );
        },
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => _wizardStep = 0),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              widget.onPriorityChanged(_wizardPriority);
              _enterGuidedWithTemplate(_wizardTemplate);
            },
            child: const Text('Start'),
          ),
        ],
      ),
    ];
  }

  Widget _buildBody(ThemeData theme) {
    switch (_mode) {
      case NoteEditorMode.preview:
        return MarkdownView(text: _currentText());
      case NoteEditorMode.raw:
        return _buildRaw(theme);
      case NoteEditorMode.guided:
        return _buildStepPage(theme);
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

  Widget _buildStepPage(ThemeData theme) {
    _ensureControllers(_template);
    final sections = _template.sections;
    final idx = _currentStep.clamp(0, sections.length - 1);
    final section = sections[idx];
    final total = sections.length;
    final controller = _section[section.key]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress bar + step counter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('${idx + 1} / $total', style: theme.textTheme.labelMedium),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(value: (idx + 1) / total),
              ),
            ],
          ),
        ),
        // Section label + helper + text field
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  section.isTitle ? 'title' : section.label,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  section.helper,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: widget.autofocus && idx == 0,
                  maxLines: section.inline ? 1 : null,
                  minLines: section.inline ? 1 : 6,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: section.hint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _emit();
                  },
                ),
              ],
            ),
          ),
        ),
        // Navigation buttons — below Expanded so they stay above the keyboard
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (idx > 0)
                TextButton(
                  onPressed: () => _goToStep(idx - 1),
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (idx < total - 1)
                FilledButton(
                  onPressed: () => _goToStep(idx + 1),
                  child: const Text('Next'),
                )
              else
                FilledButton(onPressed: _exitGuided, child: const Text('Done')),
            ],
          ),
        ),
      ],
    );
  }
}
