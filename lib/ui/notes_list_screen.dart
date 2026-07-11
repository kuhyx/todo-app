import 'dart:async';

import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/note_repository.dart';
import '../data/note_template.dart';
import 'note_detail_screen.dart';

/// The default status selection: hide completed/dropped work. This is the
/// app's notion of "unfiltered", so it does not count towards the filter
/// badge and is what "Clear all" resets to.
const Set<Status> kDefaultStatuses = {Status.todo, Status.inProgress};

/// Searchable, filterable, sortable list of stored/synced notes.
///
/// The heavy lifting (WHERE/ORDER BY) lives in [NoteRepository]; this screen
/// only owns transient view state ([NoteSort] + [NoteFilter]) and rebuilds
/// the watch stream when that state changes. The stream is memoised so a
/// rebuild (e.g. a search keystroke) does not churn a new DB subscription.
class NotesListScreen extends StatefulWidget {
  const NotesListScreen({required this.repository, super.key});

  final NoteRepository repository;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  /// How long to wait after the last keystroke before re-querying, so we
  /// don't spin up a new subscription on every character typed.
  static const _searchDebounce = Duration(milliseconds: 250);

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  NoteSort _sort = NoteSort.modifiedDesc;

  /// Default view hides completed/dropped work: only To do + In progress.
  /// The user can widen this (or clear it) via the filter sheet.
  NoteFilter _filter = const NoteFilter(statuses: kDefaultStatuses);

  /// Whether [statuses] is exactly the default selection (so the badge can
  /// treat the default view as "unfiltered").
  static bool _statusesAreDefault(Set<Status> statuses) =>
      statuses.length == kDefaultStatuses.length &&
      statuses.containsAll(kDefaultStatuses);

  /// Number of *user-applied* filter facets, for the badge. Excludes the
  /// default status selection so a fresh list shows no badge.
  int get _badgeCount {
    var count = _filter.activeCount;
    if (_statusesAreDefault(_filter.statuses)) count -= 1;
    return count;
  }

  /// Memoised stream; only replaced when [_sort]/[_filter] actually change.
  late Stream<List<Note>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository.watchNotes(sort: _sort, filter: _filter);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Rebuilds the watch stream for the current sort + filter. Call only
  /// from handlers that change those, never from [build].
  void _applyState() {
    setState(() {
      _stream = widget.repository.watchNotes(sort: _sort, filter: _filter);
    });
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
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (edited != null) {
      _filter = edited.copyWith(query: _searchController.text);
      _applyState();
    }
  }

  /// Opens the full note: read it, edit the body, change priority/status.
  Future<void> _openNote(Note note) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            NoteDetailScreen(note: note, repository: widget.repository),
      ),
    );
  }

  /// Opens the per-note quick-actions sheet (priority, status, delete).
  Future<void> _openNoteActions(Note note) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _NoteActionsSheet(
        note: note,
        onChanged: (updated) async {
          await widget.repository.upsert(updated);
        },
        onDelete: () async {
          await widget.repository.delete(note.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgeCount = _badgeCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
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
                return ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _NoteTile(
                    key: ValueKey(notes[i].id),
                    note: notes[i],
                    onTap: () => _openNote(notes[i]),
                    onActions: () => _openNoteActions(notes[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the notes list: first line, then a metadata subtitle.
class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.onTap,
    required this.onActions,
    super.key,
  });

  final Note note;

  /// Open the full note for reading/editing.
  final VoidCallback onTap;

  /// Open the quick-actions sheet (priority/status/delete).
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final firstLine = noteTitle(note.text);
    // Every note has a status and a priority now, so both are always shown.
    final meta = <String>[
      note.status.label,
      note.priority.label,
      'edited ${_relative(note.updatedAt)}',
    ].join(' · ');
    return ListTile(
      title: Text(
        firstLine.isEmpty ? '(empty)' : firstLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(meta),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Quick actions',
        onPressed: onActions,
      ),
      onTap: onTap,
      onLongPress: onActions,
    );
  }

  /// Compact relative time like "2m ago" for the list subtitle.
  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Bottom sheet for editing one note's priority/status or deleting it.
class _NoteActionsSheet extends StatefulWidget {
  const _NoteActionsSheet({
    required this.note,
    required this.onChanged,
    required this.onDelete,
  });

  final Note note;
  final Future<void> Function(Note) onChanged;
  final Future<void> Function() onDelete;

  @override
  State<_NoteActionsSheet> createState() => _NoteActionsSheetState();
}

class _NoteActionsSheetState extends State<_NoteActionsSheet> {
  late Priority _priority = widget.note.priority;
  late Status _status = widget.note.status;

  Future<void> _persist() async {
    await widget.onChanged(
      widget.note.copyWith(
        priority: _priority,
        status: _status,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstLine = noteTitle(widget.note.text);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              firstLine.isEmpty ? '(empty)' : firstLine,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            _EnumChips<Status>(
              label: 'Status',
              values: Status.values,
              selected: {_status},
              labelOf: (s) => s.label,
              onSelected: (s) {
                setState(() => _status = s);
                _persist();
              },
            ),
            const SizedBox(height: 12),
            _EnumChips<Priority>(
              label: 'Priority',
              values: Priority.values,
              selected: {_priority},
              labelOf: (p) => p.label,
              onSelected: (p) {
                setState(() => _priority = p);
                _persist();
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete note'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                await widget.onDelete();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-select chip row for an enum (used for per-note priority/status).
class _EnumChips<T> extends StatelessWidget {
  const _EnumChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: selected.contains(v),
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// The filter editing sheet: priority + status multi-select and Created /
/// Last-updated date ranges (presets + a custom range picker). Edits a
/// working copy and returns it via [Navigator.pop] on "Apply".
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final NoteFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<Priority> _priorities = {...widget.initial.priorities};
  late Set<Status> _statuses = {...widget.initial.statuses};
  late DateTime? _createdFrom = widget.initial.createdFrom;
  late DateTime? _createdTo = widget.initial.createdTo;
  late DateTime? _updatedFrom = widget.initial.updatedFrom;
  late DateTime? _updatedTo = widget.initial.updatedTo;

  void _toggle<T>(Set<T> set, T value) {
    setState(() => set.contains(value) ? set.remove(value) : set.add(value));
  }

  void _clearAll() {
    setState(() {
      _priorities = {};
      // Reset to the default view (hide Done/Abandoned), not an empty set,
      // so "Clear all" matches the app's unfiltered baseline.
      _statuses = {...kDefaultStatuses};
      _createdFrom = null;
      _createdTo = null;
      _updatedFrom = null;
      _updatedTo = null;
    });
  }

  NoteFilter _build() {
    // query is owned by the search box and re-applied by the caller.
    return NoteFilter(
      priorities: _priorities,
      statuses: _statuses,
      createdFrom: _createdFrom,
      createdTo: _createdTo,
      updatedFrom: _updatedFrom,
      updatedTo: _updatedTo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Filters', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MultiChips<Status>(
                label: 'Status',
                values: Status.values,
                selected: _statuses,
                labelOf: (s) => s.label,
                onToggle: (s) => _toggle(_statuses, s),
              ),
              const SizedBox(height: 12),
              _MultiChips<Priority>(
                label: 'Priority',
                values: Priority.values,
                selected: _priorities,
                labelOf: (p) => p.label,
                onToggle: (p) => _toggle(_priorities, p),
              ),
              const SizedBox(height: 12),
              _DateRangeField(
                label: 'Created',
                from: _createdFrom,
                to: _createdTo,
                onChanged: (from, to) => setState(() {
                  _createdFrom = from;
                  _createdTo = to;
                }),
              ),
              const SizedBox(height: 12),
              _DateRangeField(
                label: 'Last updated',
                from: _updatedFrom,
                to: _updatedTo,
                onChanged: (from, to) => setState(() {
                  _updatedFrom = from;
                  _updatedTo = to;
                }),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_build()),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select chip group for an enum (used by the filter sheet).
class _MultiChips<T> extends StatelessWidget {
  const _MultiChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final v in values)
              FilterChip(
                label: Text(labelOf(v)),
                selected: selected.contains(v),
                onSelected: (_) => onToggle(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// A date-range control offering quick presets plus a custom range picker.
///
/// Reports the chosen [from]/[to] (day granularity, both inclusive) back to
/// the parent; `null`/`null` means "any date" for this field.
class _DateRangeField extends StatelessWidget {
  const _DateRangeField({
    required this.label,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final String label;
  final DateTime? from;
  final DateTime? to;

  /// Called with the new (from, to); either may be null to clear.
  final void Function(DateTime? from, DateTime? to) onChanged;

  bool get _hasRange => from != null || to != null;

  /// Sets a preset range of the last [days] days ending today.
  void _applyDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    onChanged(today.subtract(Duration(days: days - 1)), today);
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: (from != null && to != null)
          ? DateTimeRange(start: from!, end: to!)
          : null,
    );
    if (picked != null) onChanged(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const Spacer(),
            if (_hasRange)
              Text(_rangeLabel(), style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Today'),
              onPressed: () => _applyDays(1),
            ),
            ActionChip(
              label: const Text('7 days'),
              onPressed: () => _applyDays(7),
            ),
            ActionChip(
              label: const Text('30 days'),
              onPressed: () => _applyDays(30),
            ),
            ActionChip(
              label: const Text('Custom…'),
              onPressed: () => _pickCustom(context),
            ),
            if (_hasRange)
              ActionChip(
                avatar: const Icon(Icons.clear, size: 16),
                label: const Text('Any'),
                onPressed: () => onChanged(null, null),
              ),
          ],
        ),
      ],
    );
  }

  /// Compact "YYYY-MM-DD → YYYY-MM-DD" (or one-sided) summary of the range.
  String _rangeLabel() {
    String d(DateTime? t) =>
        t == null ? '…' : '${t.year}-${_two(t.month)}-${_two(t.day)}';
    return '${d(from)} → ${d(to)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
