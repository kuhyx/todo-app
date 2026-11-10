/// Which notes of the list are selected, and whether a tap selects.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:todo/data/note.dart';

/// The notes list's multi-select state.
///
/// Holds ids, not notes, so a selection survives the list re-emitting
/// (a bulk status change rebuilds every tile). Selection order is kept, so
/// an assign appends the notes in the order they were picked.
class NoteSelection extends ChangeNotifier {
  final Set<String> _ids = {};
  bool _active = false;
  String? _anchor;

  /// Whether a plain tap selects rather than opens.
  bool get active => _active;

  /// The selected ids, in the order they were picked.
  Set<String> get ids => Set.unmodifiable(_ids);

  /// Whether [id] is selected.
  bool contains(String id) => _ids.contains(id);

  /// Enters selection mode, or leaves it and drops the selection.
  void toggleMode() {
    if (_active) return clear();
    _active = true;
    notifyListeners();
  }

  /// Flips [id] in or out of the selection; enters the mode.
  void toggle(String id) {
    _active = true;
    if (!_ids.remove(id)) _ids.add(id);
    _anchor = id;
    notifyListeners();
  }

  /// Selects every note of [order] from the last toggled one to [id]
  /// (Shift-click); without an anchor in [order] it is a [toggle].
  void extendTo(String id, List<Note> order) {
    final from = order.indexWhere((n) => n.id == _anchor);
    final to = order.indexWhere((n) => n.id == id);
    if (from < 0 || to < 0) return toggle(id);
    final (lo, hi) = from < to ? (from, to) : (to, from);
    _ids.addAll(order.sublist(lo, hi + 1).map((n) => n.id));
    _anchor = id;
    notifyListeners();
  }

  /// Keeps only the selected ids in [keep] (e.g. the notes an assign
  /// refused); an empty result is a [clear].
  void retain(Set<String> keep) {
    _ids.retainWhere(keep.contains);
    if (_ids.isEmpty) return clear();
    notifyListeners();
  }

  /// Drops the selection and leaves the mode.
  void clear() {
    _ids.clear();
    _active = false;
    _anchor = null;
    notifyListeners();
  }

  /// Handles a tap on [note] of the list [order]; false means "open it".
  ///
  /// Shift extends, Ctrl/Cmd toggles even outside the mode (desktop), and in
  /// the mode a plain tap toggles.
  bool handleTap(Note note, List<Note> order) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      extendTo(note.id, order);
    } else if (_active || keys.isControlPressed || keys.isMetaPressed) {
      toggle(note.id);
    } else {
      return false;
    }
    return true;
  }
}
