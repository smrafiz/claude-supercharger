"""The text a tool returned, from any PostToolUse tool_response shape.

One key order for every output scanner, so a shape one of them learns is a shape all
of them read. Shapes captured live (2026-11-19/22):
  Bash      {"stdout", "stderr", "interrupted", ...}
  Read text {"type":"text", "file":{"filePath","content"}}
  Read nb   {"type":"notebook", "file":{"filePath","cells":[{"cellType","source","cell_id"}]}}
  Read img  {"type":"image", "file":{"base64", ...}}   -> "" (pixels, not text)
  WebFetch  {"bytes","code","codeText","result","durationMs","url"}
  MCP       {"output"} / {"content":[blocks]} / anything else -> json.dumps
            (a list of only text/image blocks -> the text blocks; image data dropped)
"""
import json

_TEXT_KEYS = ("stdout", "output", "content")


def _s(v):
    return v if isinstance(v, str) else json.dumps(v)


def _blocks(v):
    """MCP content-block list -> text blocks only (image pixels are not text), else None.

    A list with any non-dict item, or a block type other than text/image, is not
    treated as blocks: it keeps the json.dumps path so nothing else is silenced.
    """
    if not (isinstance(v, list) and v and all(isinstance(b, dict) for b in v)):
        return None
    if any(b.get("type") not in ("text", "image") for b in v):
        return None
    return "\n".join(b["text"] for b in v if b.get("type") == "text" and isinstance(b.get("text"), str))


def tool_text(resp):
    if resp is None:
        return ""
    if isinstance(resp, str):
        return resp
    if not isinstance(resp, dict):
        t = _blocks(resp)
        return json.dumps(resp) if t is None else t
    for k in _TEXT_KEYS:
        if resp.get(k):
            t = _blocks(resp[k])
            return _s(resp[k]) if t is None else t
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
    img = {"type": "image", "source": {"data": "/9j/4AAQ"}}
    assert tool_text([{"type": "text", "text": "t"}, img, {"type": "text", "text": "u"}]) == "t\nu"
    assert tool_text({"content": [img]}) == ""
    assert tool_text([{"type": "x", "text": "t"}]) == '[{"type": "x", "text": "t"}]'
    print("ok")
