import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';

/// Below this width the notes list is a grid; at or above it, the list.
const double kNotesGridMaxWidth = 600;

const _columns = 2;
const double _gap = AppSpacing.sm;
const double _sidePadding = AppSpacing.md - AppSpacing.xs;
const _minTileHeight = 96.0;

double _tileHeightFor(double height) {
  final rows = math.max(1, ((height + _gap) / (_minTileHeight + _gap)).floor());
  return (height + _gap) / rows - _gap;
}

/// Phone notes list: two columns, scrolling only past one screenful.
class NotesGrid extends StatelessWidget {
  /// Creates the grid; [onOpen] and [onActions] get the tapped note.
  const NotesGrid({
    required this.notes,
    required this.onOpen,
    required this.onActions,
    super.key,
  });

  /// Notes in display order.
  final List<Note> notes;

  /// Tap on a tile.
  final ValueChanged<Note> onOpen;

  /// Long-press on a tile.
  final ValueChanged<Note> onActions;

  Widget _tile(Note note) {
    return NoteGridTile(
      key: ValueKey(note.id),
      note: note,
      onTap: () => onOpen(note),
      onActions: () => onActions(note),
    );
  }

  SliverGridDelegate _delegate(double viewportHeight) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _columns,
      mainAxisSpacing: _gap,
      crossAxisSpacing: _gap,
      mainAxisExtent: _tileHeightFor(viewportHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _gap),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) => GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
            gridDelegate: _delegate(box.maxHeight),
            itemCount: notes.length,
            itemBuilder: (context, i) => _tile(notes[i]),
          ),
        ),
      ),
    );
  }
}
