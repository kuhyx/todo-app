/// Hand-rolled argument parsing for `bin/todo_note.dart`.
///
/// Deliberately not `package:args`: a handful of flags do not justify a new
/// exact-pinned dependency under the freshness gate.
library;

import 'package:todo/cli/cli_mode.dart';
import 'package:todo/data/note.dart';

export 'package:todo/cli/cli_mode.dart';
export 'package:todo/cli/cli_usage.dart';

/// The parsed command line.
class CliArgs {
  /// Creates parsed arguments; see [parse].
  const CliArgs({
    required this.mode,
    this.text,
    this.id,
    this.priority = Priority.medium,
    this.status,
    this.dataDir,
    this.newNote = false,
    this.dryRun = false,
    this.opts = (
      repo: null,
      query: null,
      doneCheck: null,
      by: null,
      evidence: null,
    ),
  });

  /// Parses [argv]. Throws [UsageError] on anything it does not understand.
  factory CliArgs.parse(List<String> argv) {
    final opts = <String, String>{};
    String? id;
    final modes = <CliMode>{};
    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      String value() {
        if (i + 1 >= argv.length) throw UsageError('$arg needs a value');
        return argv[++i];
      }

      switch (arg) {
        case '--new-note':
          opts[arg] = '';
        case '-h' || '--help':
          modes.add(CliMode.help);
        case '--text' || '--priority' || '--status' || '--data-dir':
        case '--repo' || '--done-check' || '--by' || '--evidence':
          opts[arg] = value();
        case '--list':
          modes.add(CliMode.list);
        case '--backfill-created-by':
          modes.add(CliMode.backfill);
        case '--dry-run':
          opts[arg] = 'true';
        case '--search':
          modes.add(CliMode.search);
          opts[arg] = value();
        case '--get' || '--delete' || '--close':
          modes.add(CliMode.values.byName(arg.substring(2)));
          id = value();
        case '--set-status':
          modes.add(CliMode.setStatus);
          id = value();
          opts[arg] = value();
        default:
          throw UsageError('unknown argument: $arg');
      }
    }
    if (modes.contains(CliMode.help)) return const CliArgs(mode: CliMode.help);
    if (modes.length > 1) {
      throw UsageError(
        '--list, --search, --get, --delete, --set-status, --close and '
        '--backfill-created-by are mutually exclusive',
      );
    }
    final mode = modes.isEmpty ? CliMode.add : modes.single;
    _checkScopes(opts.keys, mode);
    final rawStatus = opts['--set-status'] ?? opts['--status'];
    return CliArgs(
      mode: mode,
      text: opts['--text'],
      id: id,
      priority: opts['--priority'] == null
          ? Priority.medium
          : _byName(Priority.values, opts['--priority']!, '--priority'),
      status: rawStatus == null
          ? null
          : _byName(Status.values, rawStatus, '--status', _statusName),
      dataDir: opts['--data-dir'],
      newNote:
          opts.containsKey('--new-note') &&
          (opts['--repo'] != null ||
              (throw UsageError('--new-note needs --repo'))),
      dryRun: opts.containsKey('--dry-run'),
      opts: (
        repo: _repo(opts['--repo']),
        query: _nonBlank(opts['--search'], '--search'),
        doneCheck: _nonBlank(opts['--done-check'], '--done-check'),
        by: opts['--by'] == null ? null : _by(opts['--by']!),
        evidence: _evidence(opts['--evidence'], mode),
      ),
    );
  }

  /// The selected mode.
  final CliMode mode;

  /// Note text from `--text`; null means "read stdin" in [CliMode.add].
  final String? text;

  /// Full id or 8+ character prefix of the note an id mode acts on.
  final String? id;

  /// Priority of a new note.
  final Priority priority;

  /// New note's status, [CliMode.setStatus]'s target, or a list filter.
  final Status? status;

  /// Overrides the default data dir (a second, independent node).
  final String? dataDir;

  /// `--new-note`: the `--repo` task gets its own note.
  final bool newNote;

  /// Whether `--dry-run` was given: report what would change, change nothing.
  final bool dryRun;

  /// `--repo`, `--search`, `--done-check`, `--by` and `--evidence` values.
  final ({
    String? repo,
    String? query,
    String? doneCheck,
    String? by,
    String? evidence,
  })
  opts;

  /// The command-line spelling of [status] (`in_progress`, not `inProgress`).
  static String statusName(Status status) => _statusName(status);

  static const _adding = 'when adding a note';
  static const Map<String, (String, Set<CliMode>)> _scopes = {
    '--text': (_adding, {CliMode.add}),
    '--done-check': (_adding, {CliMode.add}),
    '--by': (_adding, {CliMode.add}),
    '--repo': (
      '$_adding, to --list or to --search',
      {CliMode.add, CliMode.list, CliMode.search},
    ),
    '--evidence': ('to --close', {CliMode.close}),
    '--new-note': (_adding, {CliMode.add}),
    '--dry-run': ('to --backfill-created-by', {CliMode.backfill}),
  };

  static void _checkScopes(Iterable<String> flags, CliMode mode) {
    for (final flag in flags) {
      final scope = _scopes[flag];
      if (scope != null && !scope.$2.contains(mode)) {
        throw UsageError('$flag only applies ${scope.$1}');
      }
    }
  }

  static final _repoShape = RegExp(r'^[\w.-]+/[\w.-]+$');

  static String? _repo(String? raw) {
    if (raw == null || _repoShape.hasMatch(raw)) return raw;
    throw UsageError(
      '--repo must look like owner/name (e.g. kuhyx/todo), got "$raw"',
    );
  }

  static String _by(String raw) {
    if (kNoteAuthors.contains(raw)) return raw;
    throw UsageError(
      '--by must be one of ${kNoteAuthors.join('|')}, got "$raw"',
    );
  }

  static String? _evidence(String? raw, CliMode mode) {
    if (mode == CliMode.close && (raw == null || raw.trim().isEmpty)) {
      throw UsageError(
        '--close needs --evidence <commit sha + done check exit code>: '
        'a task is only closed with proof',
      );
    }
    return raw;
  }

  static String? _nonBlank(String? raw, String flag) {
    if (raw != null && raw.trim().isEmpty) {
      throw UsageError('$flag must not be empty');
    }
    return raw;
  }

  static String _statusName(Enum value) =>
      value == Status.inProgress ? 'in_progress' : value.name;

  static T _byName<T extends Enum>(
    List<T> values,
    String raw,
    String flag, [
    String Function(Enum) nameOf = _plainName,
  ]) {
    for (final v in values) {
      if (nameOf(v) == raw) return v;
    }
    throw UsageError(
      '$flag must be one of ${values.map(nameOf).join('|')}, got "$raw"',
    );
  }

  static String _plainName(Enum value) => value.name;
}
