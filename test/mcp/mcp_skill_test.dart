// The task-filing skill over the MCP Skills extension (2026-07-28): the
// entry, the file list and the SKILL.md read must pass the same checks
// Claude Code runs before it lists `todo:<name>` and loads it.
import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_harness.dart';

const _ext = 'io.modelcontextprotocol/skills';
final _name = RegExp(r'^(?=.{1,64}$)[a-z0-9]+(?:-[a-z0-9]+)*$');

class _Raw implements BaseResultData {
  _Raw(this.json);

  final Map<String, dynamic> json;

  @override
  Map<String, dynamic>? get meta => null;

  @override
  Map<String, dynamic> toJson() => json;
}

void main() {
  late McpHarness h;
  late McpClient c;

  setUp(() async {
    h = McpHarness();
    await h.start();
    c = await h.connect();
  });
  tearDown(() => h.dispose());

  Future<Map<String, dynamic>> send(String method, Map<String, dynamic> p) => c
      .request(JsonRpcRequest(id: 0, method: method, params: p), _Raw.new)
      .then((r) => r.json);

  test('declares the extension on 2026-07-28', () {
    expect(c.getProtocolVersion(), '2026-07-28');
    expect(c.getServerCapabilities()?.extensions?[_ext], isNotNull);
  });

  test('lists one valid entry and serves its SKILL.md', () async {
    final list = await send('skills/list', {});
    final skills = list['skills'] as List<dynamic>;
    expect(skills, hasLength(1));
    final entry = skills.single as Map<String, dynamic>;
    final uri = entry['uri'] as String;
    expect(uri, endsWith('/SKILL.md'));
    final root = uri.substring(0, uri.length - '/SKILL.md'.length);
    final last = root.substring(root.lastIndexOf('/') + 1);
    final front = entry['frontmatter'] as Map<String, dynamic>;
    expect(front['name'], last);
    expect(_name.hasMatch(last), isTrue, reason: last);
    expect(front['description'], isA<String>());
    expect(uri, isNot(contains(r'$')));

    final files = (entry['resources'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final md = files.singleWhere((f) => f['uri'] == uri);

    final got = await send('skills/get', {'uri': uri});
    expect(got['skill'], entry);

    final read = await c.readResource(ReadResourceRequest(uri: uri));
    expect(read.contents, hasLength(1));
    final content = read.contents.single as TextResourceContents;
    expect(content.uri, uri);
    final bytes = utf8.encode(content.text);
    expect(md['size'], bytes.length);
    expect(md['digest'], 'sha256:${revisionOf(content.text)}');

    // The frontmatter in the file parses to exactly the listed one.
    final text = content.text;
    expect(text, startsWith('---\n'));
    final end = text.indexOf('\n---\n', 4);
    final lines = text.substring(4, end).split('\n');
    final parsed = {
      for (final l in lines)
        l.substring(0, l.indexOf(':')): jsonDecode(
          l.substring(l.indexOf(':') + 1).trim(),
        ),
    };
    expect(parsed, front);

    final body = text.substring(end + 5);
    for (final rule in [
      'add_task',
      'done_check',
      'MANUAL WORK REQUIRED: ',
      'Todo: <id8>',
      'close_task',
    ]) {
      expect(body, contains(rule));
    }
  });

  test('skills/get on an unknown uri is an error', () async {
    await expectLater(
      send('skills/get', {'uri': 'skill://todo/nope/SKILL.md'}),
      throwsA(isA<McpError>()),
    );
  });
}
