/// The notes-list filter sheet and its multi-select chip row.
///
/// Split out of `notes_list_screen.dart` for file size. [FilterSheet] is
/// public only because Dart privacy is library-scoped; it is still an
/// implementation detail of the notes list, pushed by
/// `_NotesListScreenState._openFilters`.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/enum_glyphs.dart';
import 'package:todo/ui/note_date_range_field.dart';
import 'package:todo/ui/notes_list_defaults.dart';

/// The filter editing sheet: priority + status multi-select and Created /
/// Last-updated date ranges (one compact preset menu + custom picker). Edits a
/// working copy and returns it via [Navigator.pop] on "Apply".
class FilterSheet extends StatefulWidget {
  /// Creates the sheet seeded with the currently applied [initial] filter.
  const FilterSheet({required this.initial, super.key});

  /// The filter the sheet opens with; edits are made to a working copy.
  final NoteFilter initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
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
                  const Icon(Icons.filter_list, semanticLabel: 'Filters'),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Icon(Icons.clear, semanticLabel: 'Clear all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GlyphChips<Status>(
                multi: true,
                heading: kStatusHeadingIcon,
                semanticLabel: 'Status',
                values: Status.values,
                selected: _statuses,
                glyphOf: statusGlyph,
                onTap: (s) => _toggle(_statuses, s),
              ),
              const SizedBox(height: 12),
              GlyphChips<Priority>(
                multi: true,
                heading: kPriorityHeadingIcon,
                semanticLabel: 'Priority',
                values: Priority.values,
                selected: _priorities,
                glyphOf: (p) => priorityGlyph(context, p),
                onTap: (p) => _toggle(_priorities, p),
              ),
              const SizedBox(height: 12),
              DateRangeField(
                icon: kCreatedIcon,
                semanticLabel: 'Created',
                from: _createdFrom,
                to: _createdTo,
                onChanged: (from, to) => setState(() {
                  _createdFrom = from;
                  _createdTo = to;
                }),
              ),
              const SizedBox(height: 12),
              DateRangeField(
                icon: kUpdatedIcon,
                semanticLabel: 'Last updated',
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
                child: const Icon(Icons.check, semanticLabel: 'Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A date-range control offering quick presets plus a custom range picker.
///
/// Reports the chosen [from]/[to] (day granularity, both inclusive) back to
/// the parent; `null`/`null` means "any date" for this field.
