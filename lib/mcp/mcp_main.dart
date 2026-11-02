import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/mcp/todo_mcp_server.dart';

/// Starts the server from `$HOME` paths and returns its stop function, or
/// null after writing to [err] why it cannot run (no tokens, seed, network).
Future<Future<void> Function()?> startTodoMcp(
  Map<String, String> env,
  StringSink err, {
  http.Client? httpClient,
}) async {
  final home = env['HOME'] ?? '';
  final config = p.join(home, '.config', 'todo-mcp');
  final tokens = File(p.join(config, 'tokens'));
  if (!tokens.existsSync()) {
    err.writeln('error: ${tokens.path} missing; run mcp/mint_token.sh pc');
    return null;
  }
  CliSession? session;
  try {
    session = await CliSession.open(
      env['TODO_MCP_DATA_DIR'] ?? p.join(home, '.local', 'share', 'todo-mcp'),
      seedCredentials: p.join(config, 'firebase_auth.json'),
      seedApp: 'todo-mcp',
      httpClient: httpClient,
    );
    await session.sync(push: true);
    final server = await TodoMcpServer.start(
      tasks: TaskService(session),
      tokens: tokens,
      port: int.tryParse(env['TODO_MCP_PORT'] ?? '') ?? kTodoMcpPort,
    );
    err.writeln('todo-mcp: serving ${server.uri}');
    final open = session;
    return () async {
      await server.close();
      await open.close();
    };
  } on Object catch (e) {
    err.writeln('error: $e');
    await session?.close();
    return null;
  }
}
