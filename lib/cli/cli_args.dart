/// Hand-rolled argument parsing for `bin/todo_note.dart`.
///
/// Deliberately not `package:args`: a handful of flags do not justify a new
/// exact-pinned dependency under the freshness gate.
library;

import 'package:todo/data/note.dart';

/// What the CLI was asked to do.
enum CliMode {
  /// Create a note and push it.
  add,

  /// Print every live note, one per line.
  list,

  /// Print one note in full.
  get,

  /// Tombstone one note and push the deletion.
  delete,

  /// Change one note's status and push it.
  setStatus,

  /// Print usage.
  help,
}

/// Thrown for a malformed command line; maps to exit code 2.
class UsageError implements Exception {
  /// Creates a [UsageError] carrying [message].
  UsageError(this.message);

  /// What was wrong with the arguments.
  final String message;

  @override
  String toString() => message;
}

/// The parsed command line.
class CliArgs {
  /// Creates parsed arguments; see [parse].
  const CliArgs({
    required this.mode,
    this.text,
    this.id,
    this.priority = Priority.medium,
    this.status = Status.todo,
    this.dataDir,
  });

  /// Parses [argv]. Throws [UsageError] on anything it does not understand.
  factory CliArgs.parse(List<String> argv) {
    String? text;
    String? id;
    String? dataDir;
    var priority = Priority.medium;
    var status = Status.todo;
    final modes = <CliMode>{};
    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      String value() {
        if (i + 1 >= argv.length) throw UsageError('$arg needs a value');
        return argv[++i];
      }

      switch (arg) {
        case '-h' || '--help':
          modes.add(CliMode.help);
        case '--text':
          text = value();
        case '--priority':
          priority = _byName(Priority.values, value(), arg);
        case '--status':
          status = _byName(Status.values, value(), arg, _statusName);
        case '--data-dir':
          dataDir = value();
        case '--list':
          modes.add(CliMode.list);
        case '--get':
          modes.add(CliMode.get);
          id = value();
        case '--delete':
          modes.add(CliMode.delete);
          id = value();
        case '--set-status':
          modes.add(CliMode.setStatus);
          id = value();
          status = _byName(Status.values, value(), arg, _statusName);
        default:
          throw UsageError('unknown argument: $arg');
      }
    }
    if (modes.contains(CliMode.help)) return const CliArgs(mode: CliMode.help);
    if (modes.length > 1) {
      throw UsageError(
        '--list, --get, --delete and --set-status are mutually exclusive',
      );
    }
    final mode = modes.isEmpty ? CliMode.add : modes.single;
    if (mode != CliMode.add && text != null) {
      throw UsageError('--text only applies when adding a note');
    }
    return CliArgs(
      mode: mode,
      text: text,
      id: id,
      priority: priority,
      status: status,
      dataDir: dataDir,
    );
  }

  /// The selected mode.
  final CliMode mode;

  /// Note text from `--text`; null means "read stdin" in [CliMode.add].
  final String? text;

  /// Note id for [CliMode.get] / [CliMode.delete] / [CliMode.setStatus].
  final String? id;

  /// Priority of a new note.
  final Priority priority;

  /// Status of a new note, or the target status of [CliMode.setStatus].
  final Status status;

  /// Overrides the default data dir (a second, independent node).
  final String? dataDir;

  /// The command-line spelling of [status] (`in_progress`, not `inProgress`).
  static String statusName(Status status) => _statusName(status);

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

/// Usage text printed by `--help` and after a [UsageError].
const kUsage = r'''
Usage: dart run bin/todo_note.dart [options]

Adds a note to the todo app headlessly: pulls from Firebase RTDB, writes an
ordinary CRDT change as this install's own node, pushes, and prints the id.

  --text <markdown>     note text (first line = title); default: read stdin
  --priority <p>        low|medium|high (default medium)
  --status <s>          todo|in_progress|done|abandoned (default todo)
  --list                pull, then print live notes: id, priority, status, title
  --get <id>            pull, then print one note in full (exit 1 if absent)
  --delete <id>         pull, tombstone the note, push
  --set-status <id> <s> pull, change the note's status (as --status), push
  --data-dir <dir>      local log + node id (default
                        $XDG_DATA_HOME/todo-cli or ~/.local/share/todo-cli)
  -h, --help            this text

--list and --get never push, so a throwaway --data-dir leaves nothing behind.
Exit codes: 0 ok, 1 sync/auth failure or note not found, 2 bad arguments.''';
