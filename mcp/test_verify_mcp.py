# Copyright (c) 2026 Krzysztof Rudnicki
"""verify_mcp.py against a fake Streamable HTTP server (no live state)."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import verify_mcp


class _Fake(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.headers.get("Authorization") != "Bearer good":
            self.send_response(401)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Mcp-Session-Id", "s1")
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        if "id" in body:
            reply = {"jsonrpc": "2.0", "id": body["id"], "result": {"content": []}}
            self.wfile.write(f"event: message\ndata: {json.dumps(reply)}\n\n".encode())

    def log_message(self, *_args: object) -> None:
        return


def _serve() -> tuple[HTTPServer, str]:
    server = HTTPServer(("127.0.0.1", 0), _Fake)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_port}/mcp"


def test_good_token_passes_and_missing_token_is_401(tmp_path: Path) -> None:
    server, url = _serve()
    token = tmp_path / "t"
    token.write_text("good\n")
    assert verify_mcp.run([url, "--token-file", str(token)]) == 0
    assert verify_mcp.run([url, "--expect-401"]) == 0
    server.shutdown()


def test_bad_token_fails_and_expect_401_fails_when_open(tmp_path: Path) -> None:
    server, url = _serve()
    token = tmp_path / "t"
    token.write_text("bad\n")
    assert verify_mcp.run([url, "--token-file", str(token)]) == 1
    server.shutdown()
