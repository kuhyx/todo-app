import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo/cli/cli_session.dart' show CliSession;

/// Default data dir: `$XDG_DATA_HOME/todo-cli`, else `~/.local/share/todo-cli`.
String defaultDataDir(Map<String, String> env) {
  final xdg = env['XDG_DATA_HOME'] ?? '';
  final base = xdg.isNotEmpty
      ? xdg
      : p.join(env['HOME'] ?? '', '.local', 'share');
  return p.join(base, 'todo-cli');
}

/// Node ids of the installs Claude files notes through: the MCP server and
/// the CLI under the same data root as [defaultDataDir]. Missing ones are
/// skipped.
Set<String> claudeNodeIds(Map<String, String> env) {
  final cli = defaultDataDir(env);
  return {
    for (final dir in [cli, p.join(p.dirname(cli), 'todo-mcp')])
      if (File(p.join(dir, CliSession.nodeIdFileName)) case final f
          when f.existsSync())
        f.readAsStringSync().trim(),
  }..remove('');
}
