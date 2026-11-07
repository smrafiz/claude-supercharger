#!/usr/bin/env python3
"""A stand-in for the Anthropic Messages API, so the real `claude` binary can run with no
account and no model. Idea from mnema (github.com/mnema-work/mnema, Apache-2.0); code our own.

Usage: stand-in.py <script.json> <requests.jsonl> <port-file>

The script is a JSON list of turns: {"text": "..."} or {"tool": "Bash", "input": {...}}, each
with an optional "lane" (default "hc-main"). A request takes the first unused turn whose lane
word is in its FIRST message: the main session's first message holds the prompt (run.sh puts
hc-main in it), a subagent's holds the prompt the Agent call gave it. Anything else (the
host's "foo" probe, titles, summaries) and a lane past its end gets {"text": "done"}. Every request body is
appended to requests.jsonl, so a case can grep what the host put in front of the model.
"""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT = json.load(open(sys.argv[1], encoding="utf-8"))
LOG = sys.argv[2]
LOCK = threading.Lock()
STATE = {"used": set(), "n": 0}


def next_turn(body):
    msgs = body.get("messages") or []
    first = json.dumps(msgs[0]) if msgs else ""
    with LOCK:
        STATE["n"] += 1
        if body.get("tools"):
            for i, turn in enumerate(SCRIPT):
                if i not in STATE["used"] and turn.get("lane", "hc-main") in first:
                    STATE["used"].add(i)
                    return turn, STATE["n"]
        return {"text": "done"}, STATE["n"]


def blocks(turn, n):
    if "tool" in turn:
        return [{"type": "tool_use", "id": f"toolu_{n:04d}", "name": turn["tool"],
                 "input": turn.get("input", {})}], "tool_use"
    return [{"type": "text", "text": turn["text"]}], "end_turn"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, code, payload, ctype="application/json"):
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send(404, {"type": "error", "error": {"type": "not_found_error", "message": "stand-in"}})

    def do_HEAD(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("content-length") or 0))
        try:
            body = json.loads(raw or b"{}")
        except ValueError:
            body = {}
        path = self.path.split("?")[0]
        with LOCK, open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"path": path, "body": body}) + "\n")
        if path.endswith("/count_tokens"):
            return self._send(200, {"input_tokens": 1})
        if not path.endswith("/v1/messages"):
            return self._send(404, {"type": "error", "error": {"type": "not_found_error", "message": "stand-in"}})
        turn, n = next_turn(body)
        content, stop = blocks(turn, n)
        model = body.get("model", "claude-sonnet-4-5")
        usage = {"input_tokens": 10, "output_tokens": 5}
        if not body.get("stream"):
            return self._send(200, {"id": f"msg_{n:04d}", "type": "message", "role": "assistant",
                                    "model": model, "content": content, "stop_reason": stop,
                                    "stop_sequence": None, "usage": usage})
        events = [("message_start", {"type": "message_start", "message": {
            "id": f"msg_{n:04d}", "type": "message", "role": "assistant", "model": model,
            "content": [], "stop_reason": None, "stop_sequence": None, "usage": usage}})]
        for i, b in enumerate(content):
            if b["type"] == "text":
                events += [("content_block_start", {"type": "content_block_start", "index": i,
                                                    "content_block": {"type": "text", "text": ""}}),
                           ("content_block_delta", {"type": "content_block_delta", "index": i,
                                                    "delta": {"type": "text_delta", "text": b["text"]}})]
            else:
                events += [("content_block_start", {"type": "content_block_start", "index": i,
                                                    "content_block": dict(b, input={})}),
                           ("content_block_delta", {"type": "content_block_delta", "index": i,
                                                    "delta": {"type": "input_json_delta",
                                                              "partial_json": json.dumps(b["input"])}})]
            events.append(("content_block_stop", {"type": "content_block_stop", "index": i}))
        events += [("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop,
                                      "stop_sequence": None}, "usage": {"output_tokens": 5}}),
                   ("message_stop", {"type": "message_stop"})]
        data = "".join(f"event: {e}\ndata: {json.dumps(d)}\n\n" for e, d in events).encode()
        self._send(200, data, "text/event-stream")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[3], "w", encoding="utf-8") as fh:
    fh.write(str(server.server_address[1]))
server.serve_forever()
