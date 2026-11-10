import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/note_lookup.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:todo/data/repo_note_split.dart';
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

  /// Creates a note and pushes it. A `--repo` add joins the repo's open note.
  Future<int> add(CliArgs args, String text) async {
    final repo = args.opts.repo;
    final status = args.status ?? Status.todo;
    if (repo != null && kOpenStatuses.contains(status)) {
      return await _addRepoTask(args, repo, text);
    }
    final now = DateTime.now();
    final note = Note(
      id: const Uuid().v4(),
      text: text,
      priority: args.priority,
      status: status,
      createdAt: now,
      updatedAt: now,
      repo: repo,
      doneCheck: args.opts.doneCheck,
      by: args.opts.by,
      createdBy: 'claude',
    );
    await session.repository.upsert(note);
    if (!await _push('note')) return 1;
    _out.writeln(note.id);
    return 0;
  }

  Future<int> _addRepoTask(CliArgs args, String repo, String text) async {
    _report(await session.sync(push: true));
    final (:title, :body) = splitNote(text);
    if (args.newNote) return await _addSeparate(args, repo, title, body);
    final added = await addRepoTask(
      session.repository,
      repo: repo,
      title: title,
      body: body,
      doneCheck: args.opts.doneCheck,
      priority: args.priority,
      by: args.opts.by,
      createdBy: 'claude',
    );
    await _save(added.note);
    if (!await _push('note')) return 1;
    if (added.appended) _err.writeln('appended to the open note for $repo');
    _out.writeln(added.note.id);
    return 0;
  }

  Future<int> _addSeparate(
    CliArgs args,
    String repo,
    String title,
    String body,
  ) async {
    final added = await addSeparateTask(
      session.repository,
      repo: repo,
      title: title,
      body: body,
      doneCheck: args.opts.doneCheck,
      priority: args.priority,
      by: args.opts.by,
      createdBy: 'claude',
    );
    await _save(added.note);
    if (!await _push('note')) return 1;
    if (added.kind == SplitKind.merged) {
      _err.writeln(
        'merged into the separate note with that title; '
        'click Start on the board by hand',
      );
    }
    _out.writeln(added.note.id);
    return 0;
  }

  /// Prints [listLine] for each note matching the filters in [args].
  Future<int> list(CliArgs args) async {
    _report(await session.sync(push: false));
    final notes = await session.repository.listNotes(
      filter: NoteFilter(
        query: args.opts.query ?? '',
        statuses: {?args.status},
        repo: args.opts.repo,
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

  /// Replaces a note's whole text (title is its first line) and pushes it.
  Future<int> setText(String ref, String text) async {
    final note = await _pullAndFind(ref);
    await _save(note.copyWith(text: text));
    if (!await _push('text change')) return 1;
    _out.writeln('${note.id}\ttext');
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

  /// Sets `created_by` where unset (see [NoteRepository.backfillCreatedBy]).
  /// Prints one `<id>\t<value>\t<title>` line per note, then the totals. With
  /// [dryRun] nothing is written or pushed, and peers are only read.
  Future<int> backfillCreatedBy(
    Set<String> claudeNodes, {
    required bool dryRun,
  }) async {
    _report(await session.sync(push: !dryRun));
    final plan = await session.repository.backfillCreatedBy(
      claudeNodes,
      dryRun: dryRun,
    );
    final titles = {
      for (final n in await session.repository.listNotes()) n.id: n,
    };
    for (final MapEntry(:key, :value) in plan.entries) {
      final note = titles[key];
      final title = note == null ? '' : note.text.split('\n').first;
      _out.writeln(
        '${key.substring(0, key.length.clamp(0, 8))}\t$value\t$title',
      );
    }
    final claude = plan.values.where((v) => v == 'claude').length;
    final kuhy = plan.length - claude;
    _out.writeln('${dryRun ? 'dry run' : 'set'}: claude $claude, kuhy $kuhy');
    if (dryRun || plan.isEmpty) return 0;
    return await _push('backfill') ? 0 : 1;
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
