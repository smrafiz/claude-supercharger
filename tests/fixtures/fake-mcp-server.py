#!/usr/bin/env python3
"""Minimal MCP server for tests/test-mcp-audit.sh. Tool description from $FAKE_DESC.
stdio by default; `--http PORT` serves streamable HTTP (SSE replies) instead."""
import json, os, sys

DESC = os.environ.get('FAKE_DESC', 'Adds two numbers.')
TOOLS = [{'name': 'add', 'description': DESC,
          'inputSchema': {'type': 'object', 'properties': {'a': {'type': 'number', 'description': 'first'}}}},
         {'name': 'echo', 'description': 'Echoes text.', 'inputSchema': {'type': 'object'}}]


def reply(m):
    if 'id' not in m:
        return None
    if m['method'] == 'initialize':
        r = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'fake', 'version': '1'}}
    elif m['method'] == 'tools/list':
        # two pages, to exercise nextCursor
        r = {'tools': TOOLS[:1], 'nextCursor': 'p2'} if not (m.get('params') or {}).get('cursor') else {'tools': TOOLS[1:]}
    else:
        return {'jsonrpc': '2.0', 'id': m['id'], 'error': {'code': -32601, 'message': 'no'}}
    return {'jsonrpc': '2.0', 'id': m['id'], 'result': r}


if len(sys.argv) > 2 and sys.argv[1] == '--http':
    from http.server import BaseHTTPRequestHandler, HTTPServer

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            m = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            r = reply(m)
            self.send_response(200 if r else 202)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Mcp-Session-Id', 's1')
            self.end_headers()
            if r:
                self.wfile.write(('event: message\ndata: %s\n\n' % json.dumps(r)).encode())

        def log_message(self, *a):
            pass
    HTTPServer(('127.0.0.1', int(sys.argv[2])), H).serve_forever()
else:
    print('fake server log line on stdout', flush=True)   # must be tolerated
    for line in sys.stdin:
        r = reply(json.loads(line))
        if r:
            print(json.dumps(r), flush=True)
