# Copyright (c) 2026 Krzysztof Rudnicki
"""Live check of the todo MCP endpoint: real initialize + list_tasks, or a 401.

    verify_mcp.py <url> --token-file F [--wait S]   # expects a working session
    verify_mcp.py <url> --expect-401   [--wait S]   # expects no-token rejection

Exit 0 on success, 1 with one reason line on stderr. Used by go_live.sh; the
token is read from a file and never printed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

_PROTOCOL = "2025-03-26"
_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}


class VerifyError(Exception):
    """A check failed; the message is the one line shown to kuhy."""


def _post(
    url: str, body: dict[str, object], headers: dict[str, str]
) -> tuple[int, dict[str, str], str]:
    """POST JSON; return (status, lower-cased headers, body), HTTP errors included."""
    request = urllib.request.Request(
        url, data=json.dumps(body).encode(), headers={**_HEADERS, **headers}
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as resp:
            return (
                resp.status,
                {k.lower(): v for k, v in resp.headers.items()},
                resp.read().decode(),
            )
    except urllib.error.HTTPError as err:
        return err.code, {k.lower(): v for k, v in err.headers.items()}, ""


def _json_of(payload: str) -> dict[str, object]:
    """Parse a plain JSON body or the first `data:` line of an SSE body."""
    text = payload.strip()
    if not text.startswith("{"):
        lines = [x[5:].strip() for x in text.splitlines() if x.startswith("data:")]
        text = next((x for x in lines if x.startswith("{")), "")
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        msg = f"unparseable MCP reply: {payload[:80]!r}"
        raise VerifyError(msg) from exc
    return parsed if isinstance(parsed, dict) else {}


def check_session(url: str, token: str) -> str:
    """initialize + notifications/initialized + tools/call list_tasks."""
    auth = {"Authorization": f"Bearer {token}"}
    init = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": _PROTOCOL,
            "capabilities": {},
            "clientInfo": {"name": "go_live", "version": "1"},
        },
    }
    status, headers, payload = _post(url, init, auth)
    if status != 200:
        msg = f"initialize returned HTTP {status}"
        raise VerifyError(msg)
    if "result" not in _json_of(payload):
        msg = "initialize reply has no result"
        raise VerifyError(msg)
    headers_next = dict(auth)
    if "mcp-session-id" in headers:
        headers_next["Mcp-Session-Id"] = headers["mcp-session-id"]
    _post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, headers_next)
    call = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "list_tasks", "arguments": {}},
    }
    status, _, payload = _post(url, call, headers_next)
    if status != 200:
        msg = f"list_tasks returned HTTP {status}"
        raise VerifyError(msg)
    result = _json_of(payload).get("result")
    if not isinstance(result, dict) or result.get("isError"):
        msg = f"list_tasks failed: {str(result)[:120]}"
        raise VerifyError(msg)
    return "list_tasks ok"


def check_rejected(url: str) -> str:
    """A request without a bearer token must be refused (401, or 403 from mcp_dart's auth hook)."""
    status, _, _ = _post(url, {"jsonrpc": "2.0", "id": 1, "method": "ping"}, {})
    if status not in (401, 403):
        msg = f"no-token request returned HTTP {status}, expected 401 or 403"
        raise VerifyError(msg)
    return f"no token -> {status}"


def run(argv: list[str]) -> int:
    """Parse args, retry up to --wait seconds (cold TLS, restart), report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--expect-401", action="store_true")
    parser.add_argument("--wait", type=float, default=0.0)
    args = parser.parse_args(argv)
    if bool(args.token_file) == args.expect_401:
        parser.error("give exactly one of --token-file / --expect-401")
    deadline = time.monotonic() + args.wait
    while True:
        try:
            if args.expect_401:
                print(check_rejected(args.url))
            else:
                token = args.token_file.read_text().strip()
                print(check_session(args.url, token))
        except (VerifyError, OSError) as exc:
            if time.monotonic() >= deadline:
                print(f"{args.url}: {exc}", file=sys.stderr)
                return 1
            time.sleep(2)
        else:
            return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
