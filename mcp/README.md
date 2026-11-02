# todo MCP server

Repo tasks for any Claude session (local or cloud): `add_task`, `list_tasks`,
`get_task`, `update_task`, `close_task` (refused without evidence),
`search_tasks`. Dart, Streamable HTTP on `127.0.0.1:8735/mcp`; Caddy
publishes it as `https://todo.kuhy.duckdns.org/mcp`.

The server is one more sync node: it reuses `lib/cli` (`CliSession`,
`SyncService`) and writes its own CRDT log at
`todo-sync/notes/<node id>.json` plus `todo-sync/revs/<node id>`.
Code: `lib/mcp/`, entrypoint `mcp/todo_mcp.dart`, tests `test/mcp/`.

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
