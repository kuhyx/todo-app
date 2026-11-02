import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/note_lookup.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:uuid/uuid.dart';

/// One CLI command per method over an open [CliSession]; each returns the
/// exit code. Id arguments are resolved by [findNote].
class CliCommands {
  /// Writes results to the first sink, errors and warnings to the second.
  CliCommands(this.session, this._out, this._err);

  /// The open session the commands act on.
  final CliSession session;

  final StringSink _out;
  final StringSink _err;

  /// Creates a note (a repo task when `--repo` is set) and pushes it.
  Future<int> add(CliArgs args, String text) async {
    final now = DateTime.now();
    final note = Note(
      id: const Uuid().v4(),
      text: text,
      priority: args.priority,
      status: args.status ?? Status.todo,
      createdAt: now,
      updatedAt: now,
      repo: args.opts.repo,
      doneCheck: args.opts.doneCheck,
      by: args.opts.by,
    );
    await session.repository.upsert(note);
    if (!await _push('note')) return 1;
    _out.writeln(note.id);
    return 0;
  }

  /// Prints [listLine] for each note matching the filters in [args].
  Future<int> list(CliArgs args) async {
    _report(await session.sync(push: false));
    final notes = await session.repository.listNotes(
      filter: NoteFilter(
        query: args.opts.query ?? '',
        statuses: {?args.status},
        sources: {?args.opts.repo},
      ),
    );
    notes.map(listLine).forEach(_out.writeln);
    return 0;
  }

  /// Prints one note in full.
  Future<int> get(String ref) async {
    _report(await session.sync(push: false));
    _out.writeln(
      noteDetail(findNote(await session.repository.listNotes(), ref)),
    );
    return 0;
  }

  /// Tombstones a note and pushes the deletion.
  Future<int> delete(String ref) async {
    final note = await _pullAndFind(ref);
    await session.repository.delete(note.id);
    if (!await _push('deletion')) return 1;
    _out.writeln('deleted ${note.id}');
    return 0;
  }

  /// Changes a note's status and pushes it.
  Future<int> setStatus(String ref, Status status) async {
    final note = await _pullAndFind(ref);
    await _save(note.copyWith(status: status));
    if (!await _push('status change')) return 1;
    _out.writeln('${note.id}\t${CliArgs.statusName(status)}');
    return 0;
  }

  /// Marks a note done with [evidence], keeping it, and pushes it.
  Future<int> close(String ref, String evidence) async {
    final note = await _pullAndFind(ref);
    await _save(note.copyWith(status: Status.done, evidence: evidence));
    if (!await _push('close')) return 1;
    _out.writeln('closed ${note.id}');
    return 0;
  }

  Future<Note> _pullAndFind(String ref) async {
    _report(await session.sync(push: true));
    return findNote(await session.repository.listNotes(), ref);
  }

  Future<void> _save(Note note) =>
      session.repository.upsert(note.copyWith(updatedAt: DateTime.now()));

  Future<bool> _push(String what) async {
    if (_report(await session.sync(push: true)).pushed) return true;
    _err.writeln('error: $what saved locally but nothing was pushed');
    return false;
  }

  SyncResult _report(SyncResult result) {
    for (final name in result.skippedFiles) {
      _err.writeln('warning: could not merge peer file $name');
    }
    return result;
  }
}
