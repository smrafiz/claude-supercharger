"""The text a tool returned, from any PostToolUse tool_response shape.

One key order for every output scanner, so a shape one of them learns is a shape all
of them read. Shapes captured live (2026-11-19/22):
  Bash      {"stdout", "stderr", "interrupted", ...}
  Read text {"type":"text", "file":{"filePath","content"}}
  Read nb   {"type":"notebook", "file":{"filePath","cells":[{"cellType","source","cell_id"}]}}
  Read img  {"type":"image", "file":{"base64", ...}}   -> "" (pixels, not text)
  WebFetch  {"bytes","code","codeText","result","durationMs","url"}
  MCP       {"output"} / {"content":[blocks]} / anything else -> json.dumps
"""
import json

_TEXT_KEYS = ("stdout", "output", "content")


def _s(v):
    return v if isinstance(v, str) else json.dumps(v)


def tool_text(resp):
    if resp is None:
        return ""
    if isinstance(resp, str):
        return resp
    if not isinstance(resp, dict):
        return json.dumps(resp)
    for k in _TEXT_KEYS:
        if resp.get(k):
            return _s(resp[k])
    f = resp.get("file")
    if isinstance(f, dict):
        if f.get("content"):
            return _s(f["content"])
        cells = f.get("cells")
        if isinstance(cells, list):
            out = []
            for c in cells:
                src = c.get("source") if isinstance(c, dict) else None
                if isinstance(src, list):
                    src = "".join(x for x in src if isinstance(x, str))
                if isinstance(src, str) and src:
                    out.append(src)
            return "\n".join(out)
        if "base64" in f or resp.get("type") == "image":
            return ""
    if resp.get("result"):
        return _s(resp["result"])
    # A known text key that is present but empty (a Bash call that printed nothing)
    # is an answer: there is no text. Only an unknown shape is dumped whole.
    if any(k in resp for k in _TEXT_KEYS + ("result", "file")):
        return ""
    return json.dumps(resp)


if __name__ == "__main__":
    assert tool_text({"stdout": "a", "output": "b"}) == "a"
    assert tool_text({"type": "text", "file": {"content": "x"}}) == "x"
    nb = {"type": "notebook", "file": {"cells": [{"source": "a"}, {"source": ["b", "c"]}]}}
    assert tool_text(nb) == "a\nbc"
    assert tool_text({"type": "image", "file": {"base64": "QUJD"}}) == ""
    assert tool_text({"bytes": 3, "code": 200, "result": "r"}) == "r"
    assert tool_text({"stdout": "", "stderr": ""}) == ""
    assert tool_text({"weird": 1}) == '{"weird": 1}'
    assert tool_text([{"type": "text", "text": "t"}]) == '[{"type": "text", "text": "t"}]'
    print("ok")
