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

| What | Where |
|---|---|
| Firebase seed (read once) | `~/.config/todo-mcp/firebase_auth.json` |
| Bearer token hashes | `~/.config/todo-mcp/tokens` (`<sha256> <env>`) |
| Log, node id, session copy (0600) | `~/.local/share/todo-mcp/` |
| Binary | `~/.local/lib/todo-mcp/todo_mcp` |

## One-time setup

```bash
python3 ~/src/utils/crdt-sync/tool/seed_session.py --app todo-mcp
mcp/mint_token.sh pc        # prints the token once; export it as TODO_MCP_TOKEN
mcp/install.sh              # build + install the unit
systemctl --user enable --now todo-mcp.service
```

Deploy a new build: `mcp/install.sh` (restarts a running unit).
Revoke a token: delete its line in `tokens`; no restart needed.
