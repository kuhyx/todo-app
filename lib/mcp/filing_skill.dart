import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// The MCP Skills extension (revision 2026-07-28). mcp_dart 2.4.4 has no
/// typed API for it, so this file wires its two methods by hand: a
/// capability under `extensions`, `skills/list` + `skills/get`, and the
/// SKILL.md served as a plain resource the client reads and hash-checks.
const kSkillsExtensionId = 'io.modelcontextprotocol/skills';

/// The skill's name; Claude Code lists it as `todo:filing-tasks`.
const kFilingSkillName = 'filing-tasks';

/// SKILL.md's address. The last directory segment must equal the name.
const kFilingSkillUri = 'skill://todo/$kFilingSkillName/SKILL.md';

const _description =
    "File, track and close a task in kuhy's todo app: the add_task fields, "
    'the "MANUAL WORK REQUIRED: " title, the "Todo: <id8>" commit trailer '
    'and closing with evidence. Use when asked to file, add or note a '
    'task, when you find work you will not finish now, and before you '
    "call a task's work done.";

// Kept in step with the copies in ~/.claude/CLAUDE.md and the
// md-file-conventions skill: `claude -p` board workers never load MCP
// skills, so those copies stay the source for them.
const _body = '''
# Filing tasks in the todo app

Tasks for kuhy's repos live in the todo app, never in TODO*.md files.

## add_task fields

- `repo`: `kuhyx/<origin repo name>`, e.g. `kuhyx/todo-app`.
- `title`: one line naming the work.
- `body`: markdown with what / where / done / verify.
- `done_check`: a shell command run from the repo root, offline, under
  60 s, that exits 0 once the work is done. Its exit code settles it.
- `priority`: low | medium | high (default medium).
- `new_note: true` only when the task needs its own note; by default it
  joins the repo's single open note as a `## title` section.

## Work only kuhy can do

A task that needs kuhy's manual work has a title that starts with
`MANUAL WORK REQUIRED: <what>`, in exactly those capitals.

## Closing a task

- Name the task in the commit that lands its work with a trailer line
  `Todo: <id8>` (its 8-character id prefix). The post-commit hook runs
  the task's done_check and closes it only on exit 0.
- A task still open after that commit, or one with `Check: manual`:
  run its done_check yourself and only if it exits 0 call `close_task`
  with evidence `"<commit sha> done_check exit 0"`.
- Never leave finished work's task open, and never close without
  running its done_check.
''';

/// SKILL.md: frontmatter (JSON-quoted, which is valid YAML) then [_body].
final String filingSkillMd = [
  '---',
  'name: ${jsonEncode(kFilingSkillName)}',
  'description: ${jsonEncode(_description)}',
  '---',
  _body,
].join('\n');

/// The skill's `skills/list` entry; its one file carries size and digest.
Map<String, dynamic> filingSkillEntry() {
  final bytes = utf8.encode(filingSkillMd);
  return {
    'uri': kFilingSkillUri,
    'frontmatter': {'name': kFilingSkillName, 'description': _description},
    'resources': [
      {
        'uri': kFilingSkillUri,
        'size': bytes.length,
        'digest': 'sha256:${revisionOf(filingSkillMd)}',
      },
    ],
  };
}

/// Publishes the filing skill on [server]; call before it connects.
void registerFilingSkill(McpServer server) {
  final low = server.server
    ..registerCapabilities(
      const ServerCapabilities(extensions: {kSkillsExtensionId: {}}),
    );
  server.registerResource(
    kFilingSkillName,
    kFilingSkillUri,
    (description: _description, mimeType: 'text/markdown'),
    (uri, _) => ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: kFilingSkillUri,
          mimeType: 'text/markdown',
          text: filingSkillMd,
        ),
      ],
    ),
  );
  void method(String name, Map<String, dynamic> Function(Object?) answer) =>
      low.setRequestHandler<JsonRpcRequest>(
        name,
        (request, _) async => _Json(answer(request.params?['uri'])),
        (id, params, meta) =>
            JsonRpcRequest(id: id, method: name, params: params, meta: meta),
      );
  method(
    'skills/list',
    (_) => {
      'skills': [filingSkillEntry()],
    },
  );
  method('skills/get', (uri) {
    if (uri == kFilingSkillUri) return {'skill': filingSkillEntry()};
    throw McpError(ErrorCode.resourceNotFound.value, 'no skill at $uri');
  });
}

/// A result whose JSON is already built.
class _Json implements BaseResultData {
  const _Json(this.json);

  final Map<String, dynamic> json;

  @override
  Map<String, dynamic>? get meta => null;

  @override
  Map<String, dynamic> toJson() => json;
}
