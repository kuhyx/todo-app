import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

/// The default status selection: hide completed/dropped work.
const Set<Status> kDefaultStatuses = {Status.todo, Status.inProgress};

/// The default source selection: plain ideas only, repo tasks hidden.
const Set<String> kDefaultSources = {kIdeasSource};

/// The notes list's unfiltered baseline, which "Clear all" resets to.
const kDefaultNoteFilter = NoteFilter(
  statuses: kDefaultStatuses,
  sources: kDefaultSources,
);

/// Facets the user changed from [kDefaultNoteFilter], for the filter badge.
int userFacetCount(NoteFilter filter) {
  var count = filter.activeCount;
  if (_same(filter.statuses, kDefaultStatuses)) count -= 1;
  if (_same(filter.sources, kDefaultSources)) count -= 1;
  return count;
}

bool _same<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
