/// Runs the todo MCP server in-process over real HTTP, backed by a
/// [FakeRtdb] and a temp data dir. Never the real RTDB or ~/.local/share.
///
/// Not named `*_test.dart`: the runner would collect it and fail on the
/// missing `main()`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/mcp/todo_mcp_server.dart';
import 'package:todo/mcp/token_file.dart';

import '../cli/fake_rtdb.dart';

class McpHarness {
  static const token = 'test-token-for-pc';

  final tmp = Directory.systemTemp.createTempSync('mcp_harness');
  final db = FakeRtdb();
  late final File tokens = File('${tmp.path}/tokens');
  late final CliSession session;
  late final TodoMcpServer server;
  final _clients = <McpClient>[];

  Future<void> start() async {
    tokens.writeAsStringSync('${tokenHash(token)} pc\n');
    session = await CliSession.open(
      '${tmp.path}/data',
      seedCredentials: writeSeedCredentials(tmp).path,
      httpClient: db.client,
    );
    server = await TodoMcpServer.start(
      tasks: TaskService(session),
      tokens: tokens,
      port: 0,
    );
  }

  Future<void> dispose() async {
    for (final c in _clients) {
      await c.close();
    }
    await server.close();
    await session.close();
    tmp.deleteSync(recursive: true);
  }

  /// A connected MCP client sending `Authorization: Bearer <bearer>`.
  Future<McpClient> connect({String bearer = token}) async {
    final client = McpClient(
      const Implementation(name: 'contract-test', version: '1.0.0'),
    );
    await client.connect(
      StreamableHttpClientTransport(
        server.uri,
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': {'Authorization': 'Bearer $bearer'},
          },
        ),
      ),
    );
    _clients.add(client);
    return client;
  }

  /// Calls [tool] and returns its text, failing the test on a tool error.
  Future<String> call(
    McpClient client,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final (text, isError) = await _call(client, tool, args);
    expect(isError, isFalse, reason: '$tool failed: $text');
    return text;
  }

  /// Calls [tool], expects it to be refused, and returns the error text.
  Future<String> refused(
    McpClient client,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final (text, isError) = await _call(client, tool, args);
    expect(isError, isTrue, reason: '$tool should be refused: $text');
    return text;
  }

  Future<(String, bool)> _call(
    McpClient client,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final result = await client.callTool(
      CallToolRequest(name: tool, arguments: args),
    );
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join('\n');
    return (text, result.isError);
  }

  /// POSTs a raw `initialize` with the given headers; returns the status.
  Future<int> rawInitialize(Map<String, String> headers) async {
    final http = HttpClient();
    try {
      final req = await http.postUrl(server.uri);
      req.headers
        ..set('content-type', 'application/json')
        ..set('accept', 'application/json, text/event-stream');
      headers.forEach(req.headers.set);
      req.write(
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
        '{"protocolVersion":"2025-06-18","capabilities":{},'
        '"clientInfo":{"name":"raw","version":"1"}}}',
      );
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      http.close(force: true);
    }
  }
}

/// The first full uuid in [text].
String idIn(String text) =>
    RegExp(r'[0-9a-f]{8}-[0-9a-f-]{27}').firstMatch(text)!.group(0)!;
