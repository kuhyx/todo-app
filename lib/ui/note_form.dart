/// Composes the note-editing form shared by capture and the detail screen.
///
/// Composition only, no logic of its own: [NoteFormChromeGate] decides
/// visibility, [NoteMetaRow] renders the priority/status row, and [NoteEditor]
/// owns the text. Both surfaces render this so an edited note and a fresh
/// capture cannot look different -- the divergence this replaced was the
/// detail screen defaulting `advancedMode` to true while the app-wide setting
/// defaults to false.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/image_attach.dart';
import 'package:todo/ui/images/image_strip.dart';
import 'package:todo/ui/note_editor.dart';
import 'package:todo/ui/note_form_chrome_gate.dart';
import 'package:todo/ui/note_meta_row.dart';

/// The metadata row above a [NoteEditor], gated on advanced mode, and the
/// attached-image thumbnails below it.
class NoteForm extends StatefulWidget {
  /// Creates the form for the given note values.
  const NoteForm({
    required this.advancedMode,
    required this.priority,
    required this.status,
    required this.onPriorityChanged,
    required this.onStatusChanged,
    required this.onChanged,
    this.initialText = '',
    this.initialTemplate,
    this.autofocus = false,
    this.attachController,
    super.key,
  });

  /// Whether the metadata row and the editor's own chrome may be shown.
  final bool advancedMode;

  /// The note's current priority.
  final Priority priority;

  /// The note's current status.
  final Status status;

  /// Called with a newly picked priority.
  final ValueChanged<Priority> onPriorityChanged;

  /// Called with a newly picked status.
  final ValueChanged<Status> onStatusChanged;

  /// Called with the freshly assembled note text on every edit.
  final ValueChanged<String> onChanged;

  /// Existing note text to load. Empty for a fresh draft.
  final String initialText;

  /// Template to author with. Null detects it from [initialText], which is
  /// what opening an existing note wants.
  final NoteTemplate? initialTemplate;

  /// Autofocus the editor, so a fresh capture needs zero taps before typing.
  final bool autofocus;

  /// Where the screen's attach actions insert image links.
  final ImageAttachController? attachController;

  @override
  State<NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<NoteForm> {
  // The live text, for the thumbnail strip only: a notifier so a keystroke
  // rebuilds the strip, not the editor.
  late final ValueNotifier<String> _text = ValueNotifier(widget.initialText);
  bool _previewing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _text.value = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    return NoteFormChromeGate(
      advancedMode: widget.advancedMode,
      builder:
          (context, {required chromeVisible, required onChromeVisibleChanged}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chromeVisible) ...[
                  NoteMetaRow(
                    priority: widget.priority,
                    status: widget.status,
                    onPriorityChanged: widget.onPriorityChanged,
                    onStatusChanged: widget.onStatusChanged,
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: NoteEditor(
                    initialText: widget.initialText,
                    initialTemplate: widget.initialTemplate,
                    initialMode: NoteEditorMode.raw,
                    advancedMode: widget.advancedMode,
                    priority: widget.priority,
                    onPriorityChanged: widget.onPriorityChanged,
                    onChromeVisibleChanged: onChromeVisibleChanged,
                    autofocus: widget.autofocus,
                    onChanged: _onChanged,
                    attachController: widget.attachController,
                    onModeChanged: (mode) => setState(
                      () => _previewing = mode == NoteEditorMode.preview,
                    ),
                  ),
                ),
                // A sibling of the editor's Expanded, not nested inside it:
                // an extra Column around the expanding field breaks its
                // height in release builds (see NoteEditorRawField).
                if (!_previewing)
                  ValueListenableBuilder<String>(
                    valueListenable: _text,
                    builder: (context, text, _) => ImageStrip(text: text),
                  ),
              ],
            );
          },
    );
  }
}
