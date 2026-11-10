import 'dart:async';

import 'package:flutter/material.dart';

import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/note_selection.dart';
import 'package:todo/ui/notes_assign_flow.dart';
import 'package:todo/ui/notes_filter_sheet.dart';
import 'package:todo/ui/notes_list_body.dart';
import 'package:todo/ui/notes_list_defaults.dart';
import 'package:todo/ui/notes_list_navigation.dart';
import 'package:todo/ui/notes_selection_bar.dart';

export 'package:todo/ui/notes_list_defaults.dart';

part 'notes_list_screen_select.dart';

/// Searchable, filterable, sortable list of stored/synced notes.
///
/// The heavy lifting (WHERE/ORDER BY) lives in [NoteRepository]; this screen
/// only owns transient view state ([NoteSort] + [NoteFilter]) and rebuilds
/// the watch stream when that state changes. The stream is memoised so a
/// rebuild (e.g. a search keystroke) does not churn a new DB subscription.
class NotesListScreen extends StatefulWidget {
  /// Creates a [NotesListScreen] backed by [repository].
  const NotesListScreen({
    required this.repository,
    required this.appSettings,
    super.key,
  });

  /// The store this screen searches/filters/sorts.
  final NoteRepository repository;

  /// Passed through to the detail screen so an opened note is edited with the
  /// same chrome capture uses.
  final ValueNotifier<AppSettings> appSettings;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  /// How long to wait after the last keystroke before re-querying, so we
  /// don't spin up a new subscription on every character typed.
  static const _searchDebounce = Duration(milliseconds: 250);

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  NoteSort _sort = NoteSort.priorityDesc;

  /// Default view: open notes (no Done/Abandoned), ideas and repo tasks alike.
  NoteFilter _filter = kDefaultNoteFilter;

  /// Memoised stream; only replaced when [_sort]/[_filter] actually change.
  late Stream<List<Note>> _stream;

  /// Multi-select; any change rebuilds the screen (tiles + bottom bar).
  late final _selection = NoteSelection()..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    _stream = _watch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _selection.dispose();
    super.dispose();
  }

  /// Rebuilds the watch stream for the current sort + filter. Call only
  /// from handlers that change those, never from [build].
  void _applyState() {
    setState(() => _stream = _watch());
  }

  /// The query for the current sort + filter, minus Claude-made notes unless
  /// this device's eye toggle is on.
  Stream<List<Note>> _watch() => widget.repository.watchNotes(
    sort: _sort,
    filter: _filter.copyWith(
      hideClaude: !widget.appSettings.value.showClaudeNotes,
    ),
  );

  Future<void> _toggleClaudeNotes() async {
    final settings = widget.appSettings.value;
    final next = await settings.withShowClaudeNotes(
      value: !settings.showClaudeNotes,
    );
    if (!mounted) return;
    widget.appSettings.value = next;
    _applyState();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      _filter = _filter.copyWith(query: value);
      _applyState();
    });
  }

  void _setSort(NoteSort sort) {
    if (sort == _sort) return;
    _sort = sort;
    _applyState();
  }

  /// Opens the filter sheet and adopts the edited filter (text query is
  /// owned by the search box, so it is preserved across the round-trip).
  Future<void> _openFilters() async {
    final edited = await showModalBottomSheet<NoteFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _filter),
    );
    if (edited != null) {
      _filter = edited.copyWith(query: _searchController.text);
      _applyState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final badgeCount = userFacetCount(_filter);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          _selectButton(),
          // Eye, no label: open = Claude-made notes shown, slashed = hidden.
          IconButton(
            icon: Icon(
              widget.appSettings.value.showClaudeNotes
                  ? Icons.visibility
                  : Icons.visibility_off,
              semanticLabel: 'Claude notes',
            ),
            onPressed: _toggleClaudeNotes,
          ),
          PopupMenuButton<NoteSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: _setSort,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: NoteSort.modifiedDesc,
                child: Text('Last updated'),
              ),
              PopupMenuItem(
                value: NoteSort.createdDesc,
                child: Text('Newest created'),
              ),
              PopupMenuItem(
                value: NoteSort.alphabetical,
                child: Text('Alphabetical'),
              ),
              PopupMenuItem(
                value: NoteSort.priorityDesc,
                child: Text('Priority'),
              ),
            ],
          ),
          // Filter icon with a badge counting user-applied facets. The
          // trailing padding + inward offset keep the badge from being
          // clipped at the screen edge.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: badgeCount > 0,
              label: Text('$badgeCount'),
              offset: const Offset(-8, 4),
              child: IconButton(
                tooltip: 'Filter',
                icon: const Icon(Icons.filter_list),
                onPressed: _openFilters,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: _stream,
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <Note>[];
                if (notes.isEmpty) {
                  return Center(
                    child: Text(
                      _filter.isEmpty
                          ? 'No notes yet'
                          : 'No notes match these filters',
                    ),
                  );
                }
                return NotesListBody(
                  notes: notes,
                  onOpen: (n) => _tap(n, notes),
                  onActions: _longPress,
                  isSelected: _selection.contains,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectionBar(),
    );
  }
}

/// One row in the notes list: first line, then a metadata subtitle.
