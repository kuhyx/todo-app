import 'dart:async';

import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/note_lookup.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:todo/mcp/board_client.dart';
import 'package:todo/mcp/task_split.dart';
import 'package:todo/sync/sync_service.dart';

/// The six task tools over one persistent sync node; calls run one at a time.
class TaskService {
  /// Serves [_session]'s notes; every call pulls first, writes then push.
  /// [board] is the todoImplementer board `new_note` checks and starts on.
  ///
  /// A call that outlives [callTimeout] (a sync stuck on a dead connection)
  /// fails with a TimeoutException instead of holding every later call, so
  /// the queue never wedges and abandoned requests do not pile up sockets.
  TaskService(
    this._session, {
    this._board,
    this.callTimeout = const Duration(seconds: 60),
    this.readFreshness = const Duration(seconds: 2),
  });

  final CliSession _session;
  final BoardClient? _board;

  /// Longest one call may run before it fails with a TimeoutException.
  final Duration callTimeout;

  /// How long a finished sync still counts for the read calls (list, search,
  /// get). The board reads 15 times per fetch and each sync is a Firebase
  /// round trip of 0.5-1 s, so reads inside the window skip it; every write
  /// still pulls and pushes. [Duration.zero] syncs on every read.
  final Duration readFreshness;
  final Stopwatch _since = Stopwatch();
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body()).timeout(callTimeout);
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<SyncResult> _sync() async {
    final result = await _session.sync(push: true);
    _since
      ..reset()
      ..start();
    return result;
  }

  /// Pulls every peer, unless [read] and a sync ended within [readFreshness].
  Future<List<Note>> _pull({bool read = false}) async {
    final fresh = _since.isRunning && _since.elapsed < readFreshness;
    if (!read || !fresh) {
      final skipped = (await _sync()).skippedFiles;
      if (skipped.isNotEmpty) throw StateError('sync: unmergeable $skipped');
    }
    return await _session.repository.listNotes();
  }

  Future<String> _save(Note note, String verb) async {
    await _session.repository.upsert(note.copyWith(updatedAt: DateTime.now()));
    await _sync();
    return '$verb ${note.id}\n${listLine(note)}';
  }

  Future<Note> _find(_Args a, {bool read = false}) async {
    final id = a.required('id');
    try {
      return findNote(await _pull(read: read), id);
    } on NoteLookupError catch (e) {
      throw FormatException('id: $e');
    }
  }

  /// `add_task`: joins the repo's open note (by: claude), or creates it. A
  /// board Start after a merge runs once the other calls may go again.
  Future<String> add(Map<String, dynamic> args) async {
    final (:reply, :start) = await _serial(() => _add(args));
    return start == null ? reply : '$reply\n${await start()}';
  }

  Future<SplitReply> _add(Map<String, dynamic> args) async {
    final a = _Args(args);
    final repo = a.repo(required: true)!;
    final title = a.required('title');
    await _pull();
    if (a.flag('new_note')) {
      return await addSplit(
        _session.repository,
        _board,
        _save,
        repo: repo,
        title: title,
        body: a.optional('body') ?? '',
        doneCheck: a.optional('done_check'),
        priority: a.priority() ?? Priority.medium,
      );
    }
    final added = await addRepoTask(
      _session.repository,
      repo: repo,
      title: title,
      body: a.optional('body') ?? '',
      doneCheck: a.optional('done_check'),
      priority: a.priority() ?? Priority.medium,
      by: 'claude',
      createdBy: 'claude',
    );
    final verb = added.appended ? 'appended to' : 'added';
    return (reply: await _save(added.note, verb), start: null);
  }

  /// `list_tasks`: repo tasks, open ones unless `status` says otherwise;
  /// `no_repo: true` lists the repo-less notes (ideas) instead.
  Future<String> list(Map<String, dynamic> args) => _serial(() async {
    final a = _Args(args);
    final repo = a.repo();
    final statuses = a.statuses();
    final ideas = a.flag('no_repo');
    await _pull(read: true);
    final notes = await _session.repository.listNotes(
      filter: NoteFilter(statuses: statuses, repo: repo, repoTasksOnly: !ideas),
    );
    return _lines(ideas ? notes.where((n) => n.repo == null).toList() : notes);
  });

  /// `search_tasks`: repo tasks of any status whose text or repo matches.
  Future<String> search(Map<String, dynamic> args) => _serial(() async {
    final query = _Args(args).required('query');
    await _pull(read: true);
    return _lines(
      await _session.repository.listNotes(
        filter: NoteFilter(query: query, repoTasksOnly: true),
      ),
    );
  });

  /// `get_task`: one note in full.
  Future<String> get(Map<String, dynamic> args) =>
      _serial(() async => noteDetail(await _find(_Args(args), read: true)));

  /// `update_task`: changes only the keys given; `done_check: ""` clears it.
  Future<String> update(Map<String, dynamic> args) => _serial(() async {
    final a = _Args(args);
    final note = await _find(a);
    final status = a.status();
    if (status == Status.done) {
      throw const FormatException('status: use close_task with evidence');
    }
    final lines = note.text.split('\n');
    final title = a.has('title') ? a.required('title') : lines.first;
    final body = a.has('body')
        ? (a.optional('body') ?? '')
        : lines.skip(1).join('\n').trimLeft();
    final reopened = status != null && note.status == Status.done;
    return await _save(
      note.copyWith(
        text: body.isEmpty ? title : '$title\n\n$body',
        priority: a.priority(),
        status: status,
        repo: a.repo(),
        doneCheck: a.has('done_check')
            ? (a.optional('done_check') ?? '')
            : null,
        evidence: reopened ? '' : null,
      ),
      'updated',
    );
  });

  /// `close_task`: status done plus evidence; refused without evidence.
  Future<String> close(Map<String, dynamic> args) => _serial(() async {
    final a = _Args(args);
    final evidence = a.required('evidence');
    final note = await _find(a);
    return await _save(
      note.copyWith(status: Status.done, evidence: evidence),
      'closed',
    );
  });

  String _lines(List<Note> notes) =>
      notes.isEmpty ? 'no tasks match' : notes.map(listLine).join('\n');
}

final _repoShape = RegExp(r'^[\w.-]+/[\w.-]+$');
final Map<String, Status> _statuses = {
  for (final s in Status.values) CliArgs.statusName(s): s,
};

// Every refusal is a FormatException whose message starts with the field.
extension type _Args(Map<String, dynamic> _args) {
  bool has(String name) => _args.containsKey(name);

  bool flag(String name) => switch (_args[name]) {
    null || false => false,
    true => true,
    _ => throw FormatException('$name: must be a boolean'),
  };

  String? optional(String name) {
    final value = _args[name];
    if (value == null) return null;
    if (value is! String) throw FormatException('$name: must be a string');
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String required(String name) =>
      optional(name) ?? (throw FormatException('$name: required, not blank'));

  String? repo({bool required = false}) {
    if (!required && !has('repo')) return null;
    final value = optional('repo') ?? '';
    if (!_repoShape.hasMatch(value)) {
      throw FormatException('repo: must look like owner/name, got "$value"');
    }
    return value;
  }

  Priority? priority() =>
      _pick('priority', {for (final p in Priority.values) p.name: p});

  Status? status() => _pick('status', _statuses);

  Set<Status> statuses() => switch (optional('status')) {
    null || 'open' => {Status.todo, Status.inProgress},
    'all' => const {},
    _ => {status()!},
  };

  T? _pick<T>(String name, Map<String, T> choices) {
    final value = optional(name);
    if (value == null) return null;
    return choices[value] ??
        (throw FormatException(
          '$name: must be one of ${choices.keys.join('|')}, got "$value"',
        ));
  }
}
