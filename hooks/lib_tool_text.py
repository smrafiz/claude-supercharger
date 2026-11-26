"""The text a tool returned, from any PostToolUse tool_response shape.

One key order for every output scanner, so a shape one of them learns is a shape all
of them read. Shapes captured live (2026-11-19/22):
  Bash      {"stdout", "stderr", "interrupted", ...}
  Read text {"type":"text", "file":{"filePath","content"}}
  Read nb   {"type":"notebook", "file":{"filePath","cells":[{"cellType","source","cell_id"}]}}
  Read img  {"type":"image", "file":{"base64", ...}}   -> "" (pixels, not text)
  WebFetch  {"bytes","code","codeText","result","durationMs","url"}
  MCP       {"output"} / {"content":[blocks]} / anything else -> json.dumps
            (image blocks keep their keys but base64 data/source.data is emptied first)
"""
import json

_TEXT_KEYS = ("stdout", "output", "content")


def _img(b):
    """Copy of an image block with its base64 payload blanked; others pass through."""
    if not (isinstance(b, dict) and b.get("type") == "image"):
        return b
    b = dict(b)
    if isinstance(b.get("data"), str):
        b["data"] = ""
    if isinstance(b.get("source"), dict) and isinstance(b["source"].get("data"), str):
        b["source"] = dict(b["source"], data="")
    return b


def _strip_images(v):
    """json.dumps input with MCP image pixels emptied (they are not text); never mutates v."""
    return [_img(b) for b in v] if isinstance(v, list) else _img(v)


def _s(v):
    return v if isinstance(v, str) else json.dumps(_strip_images(v))


def tool_text(resp):
    if resp is None:
        return ""
    if isinstance(resp, str):
        return resp
    if not isinstance(resp, dict):
        return _s(resp)
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
    return _s(resp)


if __name__ == "__main__":
    assert tool_text({"stdout": "a", "output": "b"}) == "a"
    assert tool_text({"type": "text", "file": {"content": "x"}}) == "x"
    nb = {"type": "notebook", "file": {"cells": [{"source": "a"}, {"source": ["b", "c"]}]}}
    assert tool_text(nb) == "a\nbc"
    assert tool_text({"type": "image", "file": {"base64": "QUJD"}}) == ""
    assert tool_text({"bytes": 3, "code": 200, "result": "r"}) == "r"
    assert tool_text({"stdout": "", "stderr": ""}) == ""
    assert tool_text({"weird": 1}) == '{"weird": 1}'
    img = {"type": "image", "source": {"data": "/9j/4AAQ"}, "alt": "a"}
    blank = {"type": "image", "source": {"data": ""}, "alt": "a"}
    assert tool_text({"content": [img]}) == json.dumps([blank])
    assert img["source"]["data"] == "/9j/4AAQ"
    assert tool_text(img) == json.dumps(blank)
    for tl in ([{"type": "text", "text": "t"}], ["s", {"type": "text", "text": 1}], [{"type": "x", "data": "d"}]):
        assert tool_text(tl) == json.dumps(tl)
    assert tool_text([{"type": "x", "text": "t"}]) == '[{"type": "x", "text": "t"}]'
    print("ok")
