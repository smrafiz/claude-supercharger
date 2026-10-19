"""Model-aware API prices for the cost hooks (budget-cap, subagent-cost, /sc-status).

Each caller kept its own four-number table per FAMILY ('opus' = Opus 4.x/5 rates),
so every newer model was priced as the old one: Opus 5.5 at $5 in / $0.50 cache
read instead of $4 / $0.20, and every 1-hour cache write at the 5-minute rate. With
cache reads the bulk of a long session, the shown cost ran about 2x high.

Rates: platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-18.
Per million tokens: input, 5m cache write, 1h cache write, cache read, output.
"""
import os
import re

# Most specific first; the first pattern found in the model id wins.
_TABLE = [
    (r'fable|mythos',                  (10.00, 12.50, 20.00, 0.25, 50.00)),
    (r'opus-5-5',                      (4.00,  5.00,  8.00,  0.20, 20.00)),
    (r'opus-4(?:-1)?(?:-\d{8}|$)',     (15.00, 18.75, 30.00, 1.50, 75.00)),  # Opus 4 / 4.1
    (r'opus',                          (5.00,  6.25,  10.00, 0.50, 25.00)),  # Opus 4.5-4.8, 5
    (r'sonnet-5-5',                    (2.00,  2.50,  4.00,  0.10, 10.00)),
    (r'sonnet-5',                      (2.00,  2.50,  4.00,  0.20, 10.00)),
    (r'sonnet',                        (3.00,  3.75,  6.00,  0.30, 15.00)),  # Sonnet 4.x
    (r'haiku-5-5',                     (0.10,  0.125, 0.20,  0.01, 0.50)),   # prompts <= 100k
    (r'3-5-haiku|haiku-3',             (0.80,  1.00,  1.60,  0.08, 4.00)),
    (r'haiku',                         (1.00,  1.25,  2.00,  0.10, 5.00)),   # Haiku 4.5
]
_HAIKU_55_LONG = (0.50, 0.625, 1.00, 0.05, 2.50)   # Haiku 5.5, prompts over 100k
_DEFAULT = (3.00, 3.75, 6.00, 0.30, 15.00)          # no model named: Sonnet 4.x, as before
_FAMILIES = ('opus', 'sonnet', 'haiku', 'fable')


def family(model):
    m = (model or '').lower()
    if 'fable' in m or 'mythos' in m:
        return 'fable'
    for f in ('opus', 'haiku', 'sonnet'):
        if f in m:
            return f
    return 'sonnet'


def _override(fam):
    """SUPERCHARGER_PRICE_<FAMILY>="in,cw,cr,out" (v4.2.0, for gateways): wins for the
    whole family. It has no 1h rate, so 1h writes use 2x input, the API's ratio."""
    raw = os.environ.get('SUPERCHARGER_PRICE_' + fam.upper(), '')
    if not raw:
        return None
    try:
        v = tuple(float(x) for x in raw.split(','))
    except ValueError:
        return None
    if len(v) != 4 or any(x < 0 for x in v):
        return None
    return (v[0], v[1], v[0] * 2, v[2], v[3])


def rates(model, prompt_tokens=0, force_family=''):
    """(input, 5m write, 1h write, read, output) per MTok for a model id.
    force_family = SUPERCHARGER_PRICING_MODEL, which names a family, not a model."""
    fam = force_family if force_family in _FAMILIES else family(model)
    ov = _override(fam)
    if ov:
        return ov
    if force_family in _FAMILIES:
        model = force_family
    m = (model or '').lower()
    if not m:
        return _DEFAULT
    for pat, r in _TABLE:
        if re.search(pat, m):
            if pat == r'haiku-5-5' and prompt_tokens > 100_000:
                return _HAIKU_55_LONG
            return r
    return _DEFAULT


def _i(v):
    try:
        return int(v or 0)
    except (TypeError, ValueError):
        return 0


def usage_cost(model, u, force_family=''):
    """USD for one API response's `usage`. Splits cache writes by TTL when the
    `cache_creation` breakdown is present (cache_creation_input_tokens is its sum)."""
    inp = _i(u.get('input_tokens'))
    cw = _i(u.get('cache_creation_input_tokens'))
    cr = _i(u.get('cache_read_input_tokens'))
    out = _i(u.get('output_tokens'))
    cc = u.get('cache_creation') if isinstance(u.get('cache_creation'), dict) else {}
    cw1h = min(cw, _i(cc.get('ephemeral_1h_input_tokens')))
    ip, c5, c1, rp, op = rates(model, inp + cw + cr, force_family)
    return (inp * ip + (cw - cw1h) * c5 + cw1h * c1 + cr * rp + out * op) / 1_000_000


if __name__ == '__main__':
    # Self-check against the published table.
    def near(a, b):
        return abs(a - b) < 1e-9
    M = 1_000_000
    assert near(usage_cost('claude-opus-5-5', {'cache_read_input_tokens': M}), 0.20)
    assert near(usage_cost('claude-opus-5-5', {'cache_creation_input_tokens': M,
                                               'cache_creation': {'ephemeral_1h_input_tokens': M}}), 8.0)
    assert near(usage_cost('claude-opus-5-5', {'cache_creation_input_tokens': M}), 5.0)
    assert near(usage_cost('claude-opus-4-1-20250805', {'input_tokens': M}), 15.0)
    assert near(usage_cost('claude-opus-4-20250514', {'input_tokens': M}), 15.0)
    assert near(usage_cost('claude-opus-4-8', {'input_tokens': M}), 5.0)
    assert near(usage_cost('claude-sonnet-5-5', {'cache_read_input_tokens': M}), 0.10)
    assert near(usage_cost('claude-sonnet-4-6', {'output_tokens': M}), 15.0)
    assert near(usage_cost('claude-fable-5-1', {'cache_read_input_tokens': M}), 0.25)
    assert near(usage_cost('claude-haiku-5-5', {'input_tokens': 1000}), 0.0001)
    assert near(usage_cost('claude-haiku-5-5', {'input_tokens': 200_000}), 0.1)
    assert near(usage_cost('', {'output_tokens': M}), 15.0)
    assert near(usage_cost('claude-opus-5-5', {'output_tokens': M}, force_family='sonnet'), 15.0)
    print('lib_pricing: ok')
