import 'package:todo/cli/cli_args.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/note_lookup.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:todo/mcp/board_client.dart';
import 'package:todo/mcp/task_split.dart';

/// The six task tools over one persistent sync node; calls run one at a time.
class TaskService {
  /// Serves [_session]'s notes; every call pulls first, writes then push.
  /// [board] is the todoImplementer board `new_note` checks and starts on.
  TaskService(this._session, {this._board});

  final CliSession _session;
  final BoardClient? _board;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<Note>> _pull() async {
    final skipped = (await _session.sync(push: true)).skippedFiles;
    if (skipped.isNotEmpty) throw StateError('sync: unmergeable $skipped');
    return await _session.repository.listNotes();
  }

  Future<String> _save(Note note, String verb) async {
    await _session.repository.upsert(note.copyWith(updatedAt: DateTime.now()));
    await _session.sync(push: true);
    return '$verb ${note.id}\n${listLine(note)}';
  }

  Future<Note> _find(_Args a) async {
    final id = a.required('id');
    try {
      return findNote(await _pull(), id);
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

  /// `list_tasks`: repo tasks, open ones unless `status` says otherwise.
  Future<String> list(Map<String, dynamic> args) => _serial(() async {
    final a = _Args(args);
    final repo = a.repo();
    final statuses = a.statuses();
    await _pull();
    return _lines(
      await _session.repository.listNotes(
        filter: NoteFilter(statuses: statuses, repo: repo, repoTasksOnly: true),
      ),
    );
  });

  /// `search_tasks`: repo tasks of any status whose text or repo matches.
  Future<String> search(Map<String, dynamic> args) => _serial(() async {
    final query = _Args(args).required('query');
    await _pull();
    return _lines(
      await _session.repository.listNotes(
        filter: NoteFilter(query: query, repoTasksOnly: true),
      ),
    );
  });

  /// `get_task`: one note in full.
  Future<String> get(Map<String, dynamic> args) =>
      _serial(() async => noteDetail(await _find(_Args(args))));

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
