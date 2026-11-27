# todo MCP server

Repo tasks for any Claude session (local or cloud): `add_task`, `list_tasks`,
`get_task`, `update_task`, `close_task` (refused without evidence),
`search_tasks`. Dart, Streamable HTTP on `127.0.0.1:8735/mcp`; Caddy
publishes it as `https://todo.kuhy.duckdns.org/mcp`.

The server is one more sync node: it reuses `lib/cli` (`CliSession`,
`SyncService`) and writes its own CRDT log at
`todo-sync/notes/<node id>.json` plus `todo-sync/revs/<node id>`.
Code: `lib/mcp/`, entrypoint `mcp/todo_mcp.dart`, tests `test/mcp/`.

Output shapes: `list_tasks` and `search_tasks` print one tab-separated line per
task (`id8 status priority repo title created_by`); `get_task` prints
`key: value` lines (including `created_by`) then `---` and the text.
`created_by` is `claude` for notes filed through `add_task` or the CLI and
`kuhy` for everything else (a missing value reads as `kuhy`).

The server also publishes one skill through the MCP Skills extension
(`io.modelcontextprotocol/skills`, revision 2026-07-28): `filing-tasks`,
which Claude Code lists as `todo:filing-tasks`. It holds the `add_task` field
rules, the `MANUAL WORK REQUIRED:` title rule, the `Todo: <id8>` commit trailer
and the close-the-task rule. mcp_dart 2.4.4 has no Skills API, so
`lib/mcp/filing_skill.dart` registers the capability, `skills/list`,
`skills/get` and the SKILL.md resource itself; the entry's sha256 and size are
computed from the served text. Claude Code 2.1.332 only asks for MCP skills
when its remote flag `tengu_wiggly_crystal` is on; it was off for kuhy's
account on 2026-11-27, so `/skills` does not list `todo:filing-tasks` yet. `claude -p` board workers never load MCP skills, so
`~/.claude/CLAUDE.md` and the `md-file-conventions` skill keep their copies.

| What | Where |
|---|---|
| Firebase seed (read once) | `~/.config/todo-mcp/firebase_auth.json` |
| Bearer token hashes | `~/.config/todo-mcp/tokens` (`<sha256> <env>`) |
| Log, node id, session copy (0600) | `~/.local/share/todo-mcp/` |
| Binary | `~/.local/lib/todo-mcp/todo_mcp` |

Reads (`list_tasks`, `search_tasks`, `get_task`) reuse a Firebase sync that finished within
the last 2 s (`TaskService.readFreshness`); every write pulls and pushes. One board fetch
makes about 15 calls, each used to be a 0.5-1 s sync.

## One-time setup

```bash
python3 ~/src/utils/crdt-sync/tool/seed_session.py --app todo-mcp
mcp/mint_token.sh pc        # prints the token once; export it as TODO_MCP_TOKEN
mcp/install.sh              # build + install the unit
systemctl --user enable --now todo-mcp.service
```

Deploy a new build: `mcp/install.sh` (restarts a running unit).
Revoke a token: delete its line in `tokens`; no restart needed. The file is
loaded once and re-read when its mtime or size changes; a read error (or a
deleted file) keeps the last good set, and before any good load the answer is
503, not 403. A POST open for 90 s gets 503 and its socket closed; sync HTTP
calls time out after 30 s; the unit sets `LimitNOFILE=65536`.
