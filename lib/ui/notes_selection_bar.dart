/// The icon-only action bar shown while notes are selected.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';

/// How long the assign icon shows the refusal block.
const kRefusalFlash = Duration(milliseconds: 1500);

/// Set status, set priority, assign to repo, clear: icons only.
///
/// Menus pass `tooltip: ''` because a tooltip is visible text; the icons
/// carry semantic labels instead.
class NotesSelectionBar extends StatefulWidget {
  /// Creates the bar; every callback acts on the whole selection.
  const NotesSelectionBar({
    required this.onStatus,
    required this.onPriority,
    required this.onAssign,
    required this.onClear,
    super.key,
  });

  /// Sets every selected note's status.
  final ValueChanged<Status> onStatus;

  /// Sets every selected note's priority.
  final ValueChanged<Priority> onPriority;

  /// Runs the assign flow; true when some notes were refused.
  final Future<bool> Function() onAssign;

  /// Drops the selection.
  final VoidCallback onClear;

  @override
  State<NotesSelectionBar> createState() => _NotesSelectionBarState();
}

class _NotesSelectionBarState extends State<NotesSelectionBar> {
  Timer? _flash;

  @override
  void dispose() {
    _flash?.cancel();
    super.dispose();
  }

  Future<void> _assign() async {
    if (!await widget.onAssign() || !mounted) return;
    _flash?.cancel();
    setState(() => _flash = Timer(kRefusalFlash, () => setState(() {})));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final refused = _flash?.isActive ?? false;
    return Material(
      key: const ValueKey('selection-bar'),
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            PopupMenuButton<Status>(
              key: const ValueKey('bulk-status'),
              tooltip: '',
              icon: const Icon(Icons.task_alt, semanticLabel: 'Set status'),
              onSelected: widget.onStatus,
              itemBuilder: (_) => [
                for (final s in Status.values)
                  PopupMenuItem(
                    key: ValueKey('status-${s.name}'),
                    value: s,
                    child: Icon(statusIcon(s), semanticLabel: s.label),
                  ),
              ],
            ),
            PopupMenuButton<Priority>(
              key: const ValueKey('bulk-priority'),
              tooltip: '',
              icon: const Icon(
                Icons.flag_outlined,
                semanticLabel: 'Set priority',
              ),
              onSelected: widget.onPriority,
              itemBuilder: (_) => [
                for (final p in Priority.values.reversed)
                  PopupMenuItem(
                    key: ValueKey('priority-${p.name}'),
                    value: p,
                    child: Icon(
                      Icons.flag,
                      color: priorityColor(p, scheme),
                      semanticLabel: p.label,
                    ),
                  ),
              ],
            ),
            IconButton(
              key: const ValueKey('bulk-assign'),
              onPressed: _assign,
              icon: Icon(
                refused ? Icons.block : Icons.drive_file_move_outline,
                color: refused ? scheme.error : null,
                semanticLabel: 'Assign to repo',
              ),
            ),
            IconButton(
              key: const ValueKey('bulk-clear'),
              onPressed: widget.onClear,
              icon: const Icon(
                Icons.deselect,
                semanticLabel: 'Clear selection',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
