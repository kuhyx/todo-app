/// Decides whether a note form's chrome (the priority/status row) is visible.
///
/// This is the one piece of state capture and the detail screen used to keep
/// separately, in copy-pasted form -- which is how the two drifted apart. It
/// lives here so both surfaces resolve visibility by the same rule.
library;

import 'package:flutter/material.dart';

/// Holds the editor's chrome-visibility signal and resolves it against
/// advanced mode.
///
/// Decides visibility and nothing else: it neither builds the metadata row nor
/// the editor. [builder] receives the resolved answer plus the callback to
/// hand to `NoteEditor.onChromeVisibleChanged`.
class NoteFormChromeGate extends StatefulWidget {
  /// Creates a gate resolving visibility against [advancedMode].
  const NoteFormChromeGate({
    required this.advancedMode,
    required this.builder,
    super.key,
  });

  /// When false the chrome is never shown, whatever the editor reports --
  /// casual capture needs neither the metadata row nor the mode toggle.
  final bool advancedMode;

  /// Built with the resolved visibility and the editor's visibility callback.
  final Widget Function(
    BuildContext context, {
    required bool chromeVisible,
    required ValueChanged<bool> onChromeVisibleChanged,
  })
  builder;

  @override
  State<NoteFormChromeGate> createState() => _NoteFormChromeGateState();
}

class _NoteFormChromeGateState extends State<NoteFormChromeGate> {
  /// What the editor last reported. Starts true because a freshly mounted
  /// editor shows its chrome until Guided (wizard or bare stepper) takes over.
  bool _editorChromeVisible = true;

  void _setEditorChromeVisible(bool visible) {
    if (visible == _editorChromeVisible) return;
    setState(() => _editorChromeVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      chromeVisible: widget.advancedMode && _editorChromeVisible,
      onChromeVisibleChanged: _setEditorChromeVisible,
    );
  }
}
