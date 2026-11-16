import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/mcp/request_guard.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/mcp/token_file.dart';

/// Loopback port; Caddy proxies todo.kuhy.duckdns.org/mcp here.
const kTodoMcpPort = 8735;

const _publicHost = 'todo.kuhy.duckdns.org';

const _instructions = '''
Tasks for kuhy's repos live in the todo app (not in TODO*.md files, which are
banned). Use this server instead of writing a TODO file.
- At session start in a repo, call list_tasks(repo: "kuhyx/<name>") to see
  its open tasks.
- A repo has ONE open note, "<repo> todos", holding all its tasks as
  "## title" sections. add_task appends to it (or creates it) and returns its id.
- When you find work you will not finish now, call add_task with the repo,
  a one-line title, the body (what / where / done / verify) and a done_check:
  a shell command run from the repo root that exits 0 once the work is done.
  Done checks of appended tasks are joined with &&.
- When a task's work lands, run its done_check; only if it exits 0 call
  close_task with evidence "<commit sha> done_check exit 0". Never close
  without running it.
- Ids accept an 8-character prefix. Errors start with the argument to fix.''';

/// The task tools over Streamable HTTP, behind sha256-hashed bearer tokens.
class TodoMcpServer {
  TodoMcpServer._(this._http);

  final StreamableMcpServer _http;

  /// `http://<host>:<bound port>/mcp`.
  Uri get uri => Uri.parse('http://${_http.host}:${_http.boundPort}/mcp');

  /// Binds [host]:[port] (0 = any free port); [tokens] is loaded once and
  /// re-read when its mtime changes, errors going to [log] (default stderr).
  ///
  /// A POST or DELETE that has no answer after [requestDeadline] is closed
  /// with 503, which also frees its socket when the client already gave up
  /// (Dart's HttpServer never notices a half-closed idle request). Keep it
  /// above [TaskService.callTimeout] so a stuck tool call reports its own
  /// error first. GET streams are long-lived by design and exempt.
  static Future<TodoMcpServer> start({
    required TaskService tasks,
    required File tokens,
    String host = '127.0.0.1',
    int port = kTodoMcpPort,
    Duration requestDeadline = const Duration(seconds: 90),
    void Function(String)? log,
  }) async {
    final out = log ?? (String line) => stderr.writeln(line);
    final store = TokenStore(tokens, log: out);
    final http = StreamableMcpServer(
      serverFactory: (_) => _server(tasks),
      host: host,
      port: port,
      authenticator: (request) {
        if (request is! HttpRequest) return false;
        guardDeadline(request, requestDeadline);
        return switch (store.verdict(
          request.headers.value(HttpHeaders.authorizationHeader),
        )) {
          TokenVerdict.accepted => true,
          TokenVerdict.rejected => false,
          TokenVerdict.unavailable => answerUnavailable(request),
        };
      },
      allowedHosts: const {'localhost', '127.0.0.1', '::1', _publicHost},
    );
    // The library runs each request as an unawaited future in the zone that
    // called start(): without a guard, one failed write (a response we closed
    // first) would be an uncaught error and kill the process.
    await runZonedGuarded(http.start, (error, stack) {
      if (error is StateError && '$error'.contains('Header already sent')) {
        return; // the library answering a request we already answered
      }
      out('todo-mcp: request error: $error');
    });
    return TodoMcpServer._(http);
  }

  /// Stops listening and closes every session.
  Future<void> close() => _http.stop();
}

McpServer _server(TaskService tasks) {
  final server = McpServer(
    const Implementation(name: 'todo', version: '1.0.0'),
    options: const McpServerOptions(instructions: _instructions),
  );
  final id = JsonSchema.string(
    description: 'Task id, or a unique prefix of at least 8 characters.',
  );
  final repo = JsonSchema.string(
    description: 'GitHub repo as owner/name, e.g. kuhyx/todo.',
  );
  final priority = JsonSchema.string(description: 'low | medium | high.');
  final doneCheck = JsonSchema.string(
    description:
        'Shell command run from the repo root; exit 0 means done. '
        'In update_task, "" clears it.',
  );
  void tool(
    String name,
    String description,
    Map<String, JsonSchema> props,
    List<String> required,
    Future<String> Function(Map<String, dynamic>) run,
  ) => server.registerTool(
    name,
    description: description,
    inputSchema: JsonSchema.object(properties: props, required: required),
    callback: (args, _) => _result(() => run(args)),
  );

  tool(
    'add_task',
    "Add a task to the repo's single open note (by: claude): appended as a "
        '"## title" section, or the note is created. Returns "added <full id>" '
        'or "appended to <full id>", then its list line. Use when you find '
        'work you will not finish now. With new_note: true the task gets '
        'its own note ("added"), or, when another separate note of the repo '
        'already has that exact title, "merged into" that note, followed by '
        'a "start:" line for the todoImplementer board.',
    {
      'repo': repo,
      'title': JsonSchema.string(description: 'One-line title.'),
      'body': JsonSchema.string(description: 'Markdown: what/where/verify.'),
      'done_check': doneCheck,
      'priority': priority,
      'new_note': JsonSchema.boolean(
        description: 'Own note instead of joining the shared one.',
      ),
    },
    ['repo', 'title'],
    tasks.add,
  );
  tool(
    'list_tasks',
    'List repo tasks, one line each: 8-char id, status, priority, repo, '
        'title, created_by (kuhy|claude). Default status "open" '
        '(todo + in_progress).',
    {
      'repo': repo,
      'status': JsonSchema.string(
        description: 'open | all | todo | in_progress | done | abandoned.',
      ),
    },
    [],
    tasks.list,
  );
  tool(
    'get_task',
    'One task in full: metadata lines, then --- and the text.',
    {'id': id},
    ['id'],
    tasks.get,
  );
  tool(
    'update_task',
    'Change only the arguments given; others stay as they are. Marking done '
        'is close_task. Returns "updated <id>" and its list line.',
    {
      'id': id,
      'title': JsonSchema.string(description: 'New one-line title.'),
      'body': JsonSchema.string(description: 'New body; "" empties it.'),
      'done_check': doneCheck,
      'priority': priority,
      'status': JsonSchema.string(
        description: 'todo | in_progress | abandoned.',
      ),
      'repo': repo,
    },
    ['id'],
    tasks.update,
  );
  tool(
    'close_task',
    'Mark a task done, keeping it. Refused without evidence. Run the '
        "task's done_check first and close only when it exits 0.",
    {
      'id': id,
      'evidence': JsonSchema.string(
        description:
            'Commit sha and done_check exit code, e.g. "abc1234 exit 0".',
      ),
    },
    ['id', 'evidence'],
    tasks.close,
  );
  tool(
    'search_tasks',
    'Repo tasks of any status whose text or repo contains the query '
        '(case-insensitive), one line each as list_tasks.',
    {'query': JsonSchema.string(description: 'Text to look for.')},
    ['query'],
    tasks.search,
  );
  return server;
}

Future<CallToolResult> _result(Future<String> Function() run) async {
  try {
    return CallToolResult.fromContent([TextContent(text: await run())]);
  } on FormatException catch (e) {
    return _error(e.message);
  } on Object catch (e) {
    return _error('$e');
  }
}

CallToolResult _error(String text) =>
    CallToolResult(content: [TextContent(text: 'error: $text')], isError: true);
