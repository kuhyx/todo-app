import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor_chrome.dart';
import 'package:todo/ui/note_editor_document.dart';
import 'package:todo/ui/note_editor_mode.dart';
import 'package:todo/ui/note_editor_raw_field.dart';
import 'package:todo/ui/note_editor_step_page.dart';
import 'package:todo/ui/note_editor_wizard.dart';

export 'package:todo/ui/note_editor_mode.dart';

part 'note_editor_views.dart';
part 'note_editor_widget.dart';

class _NoteEditorState extends State<NoteEditor> {
  late final NoteEditorDocument _doc;
  late NoteEditorMode _mode;

  int _currentStep = 0;

  /// Whether the priority+template entry wizard is showing in place of the
  /// normal chrome. True only between tapping Guided on an empty draft and
  /// either "Start" (which flips to bare Guided) or "Cancel" (back to Raw).
  bool _enteringGuided = false;

  /// Set once the user picks a template themselves, which stops
  /// [_retemplateDraft] from overriding that choice as they keep typing.
  bool _templatePickedByUser = false;

  @override
  void initState() {
    super.initState();
    _doc = NoteEditorDocument.forInitialText(
      widget.initialText,
      template: widget.initialTemplate,
      openingRaw: widget.initialMode == NoteEditorMode.raw,
    );
    _mode = _resolveMode(widget.initialMode);
  }

  @override
  void dispose() {
    _doc.dispose();
    super.dispose();
  }

  /// Whether the guided stepper can be *opened* right now: a structured
  /// template whose current source still fits the template. Used to decide the
  /// initial mode; the Guided segment itself is offered for any structured
  /// template (a switch that no longer conforms is blocked at switch time).
  bool get _canOpenGuided => !_doc.template.isFreeform && !_doc.rawSource;

  /// Picks the mode to actually display: honours [desired] unless Guided was
  /// asked for when it can't be opened (falls back to Raw), or
  /// [NoteEditor.advancedMode] is off (Preview/Guided are unreachable
  /// without their chrome, so Raw is the only mode shown).
  NoteEditorMode _resolveMode(NoteEditorMode desired) {
    if (!widget.advancedMode) return NoteEditorMode.raw;
    if (desired == NoteEditorMode.guided && !_canOpenGuided) {
      return NoteEditorMode.raw;
    }
    return desired;
  }

  void _goToStep(int index) {
    setState(() {
      _currentStep = index.clamp(0, _doc.template.sections.length - 1);
    });
  }

  void _emit() => widget.onChanged(_doc.currentText());

  /// Re-picks the draft's template from what has been typed so far, unless the
  /// user has chosen one explicitly.
  ///
  /// Only ever runs while the raw body *is* the source, so there are no section
  /// values to convert and the switch is lossless in both directions: paste a
  /// link and Guided drops away, write a sentence under it and the spec
  /// template comes back.
  void _retemplateDraft() {
    if (_templatePickedByUser || !_doc.rawSource) return;
    final next = NoteTemplate.forDraft(_doc.body.text);
    if (next.id == _doc.template.id) return;
    setState(() {
      _doc.template = next;
      _currentStep = 0;
      _mode = _resolveMode(_mode);
    });
  }

  void _switchTemplate(NoteTemplate next) {
    if (next.id == _doc.template.id) return;
    final text = _doc.currentText();
    setState(() {
      _doc.template = next;
      _currentStep = 0;
      _doc.load(next, text, preferGuided: true);
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
          // raw -> guided: only if the edited text still fits the template.
          if (!_doc.tryAdoptGuided()) {
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
          _currentStep = 0;
          if (_doc.currentText().trim().isEmpty) {
            // Fresh, empty draft: priority and template are meaningful
            // choices only once, so ask for them before showing the stepper.
            _enteringGuided = true;
          } else {
            // Existing content: priority/template are already settled, so
            // skip straight to the bare stepper rather than re-asking.
            _mode = NoteEditorMode.guided;
          }
        case NoteEditorMode.raw:
          // guided -> raw: materialise the assembled text into the body.
          _doc.materialiseToRaw();
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
    final text = _doc.currentText();
    // Choosing a template in the wizard is as explicit as using the dropdown.
    _templatePickedByUser = true;
    setState(() {
      _doc.template = template;
      _currentStep = 0;
      _doc.load(template, text, preferGuided: true);
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

  @override
  Widget build(BuildContext context) {
    if (_enteringGuided) return _guidedEntryWizard();

    // Guided hides the template/mode chrome entirely. Return the flat step
    // page directly so the TextField sits in THIS column's Expanded — same
    // depth as _buildRaw, avoiding the nested-Column/Expanded layout issue
    // that silently collapses the inner flex space in release builds.
    if (_mode == NoteEditorMode.guided) return _buildStepPage();

    // Advanced mode off: the template picker and mode toggle are hidden and
    // _resolveMode() has already pinned _mode to raw, so skip straight to
    // the body directly (not wrapped in another Expanded — the parent
    // screen already wraps this whole widget in one, same as the guided
    // branch above).
    if (!widget.advancedMode) return _buildBody();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoteEditorChrome(
          template: _doc.template,
          mode: _mode,
          onTemplateSelected: (next) {
            _templatePickedByUser = true;
            _switchTemplate(next);
          },
          onModeSelected: _setMode,
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody()),
      ],
    );
  }

  /// Exits the bare stepper back to Raw, restoring the chrome.
  void _exitGuided() {
    setState(() {
      _doc.materialiseToRaw();
      _mode = NoteEditorMode.raw;
    });
    widget.onChromeVisibleChanged(true);
  }

  /// Rebuilds after a guided step edit, then re-emits the assembled text.
  void _onStepFieldChanged() {
    setState(() {});
    _emit();
  }
}
