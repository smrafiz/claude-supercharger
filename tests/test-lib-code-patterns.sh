#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== lib_code_patterns.scan_content Tests ==="

# Drive the shared module directly through python; each case prints PASS/FAIL.
OUT=$(HOOKS_DIR="$REPO_DIR/hooks" python3 <<'PY'
import os, sys
sys.path.insert(0, os.environ["HOOKS_DIR"])
import lib_code_patterns as L

def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)

check("empty content -> no hits", L.scan_content("") == [])
check("clean code -> no hits", L.scan_content("def add(a,b):\n return a+b") == [])
check("eval flagged", any("eval()" in h for h in L.scan_content("eval(userInput)")))
check("pickle flagged", any("pickle" in h for h in L.scan_content("pickle.loads(data)")))
check("php unserialize flagged", any("unserialize" in h for h in L.scan_content("$x = unserialize($d);")))
check("results de-duplicated", len(L.scan_content("eval(a)\neval(b)\neval(c)")) == 1)
check("Math.random gated: benign non-secret", L.scan_content("const j = Math.random()*100;") == [])
check("Math.random gated: near token -> flagged", any("cryptographically" in h for h in L.scan_content("const token = Math.random();")))
check("python random gated: near secret -> flagged", any("secrets module" in h for h in L.scan_content("otp = random.randint(0,9)")))
# v2.23.26 insecure-transport (TLS disabled)
check("node rejectUnauthorized:false flagged", any("rejectUnauthorized" in h for h in L.scan_content("{ rejectUnauthorized: false }")))
check("py verify=False flagged", any("verify=False" in h for h in L.scan_content("requests.get(u, verify=False)")))
check("go InsecureSkipVerify flagged", any("InsecureSkipVerify" in h for h in L.scan_content("tls.Config{InsecureSkipVerify: true}")))
check("php CURLOPT verifypeer 0 flagged", any("CURLOPT" in h for h in L.scan_content("curl_setopt($c, CURLOPT_SSL_VERIFYPEER, 0);")))
check("py unverified ssl ctx flagged", any("unverified" in h for h in L.scan_content("ssl._create_unverified_context()")))
check("TLS: no FP on verify=True", not any("TLS" in h for h in L.scan_content("requests.get(u, verify=True)")))
# JWT / torch.load / CORS (kintsugi-harness scenarios)
has = lambda s, w: any(w in h for h in L.scan_content(s))
check("jwt verify_signature False flagged", has('claims = jwt.decode(token, options={"verify_signature": False})', "JWT"))
check("jwt alg none flagged", has("jwt.decode(t, key, algorithms=['none'])", "JWT"))
check("jwt: no FP on RS256 verify", not has('claims = jwt.decode(token, public_key, algorithms=["RS256"])', "JWT"))
check("torch.load bare flagged", has('ckpt = torch.load("weights.pt")', "torch.load"))
check("torch.load: no FP with weights_only=True", not has('ckpt = torch.load("w.pt", map_location="cpu", weights_only=True)', "torch.load"))
check("torch.load: no FP multi-line weights_only=True", not has('ckpt = torch.load(\n    open(p, "rb"),\n    weights_only=True,\n)', "torch.load"))
check("fastapi cors * + credentials flagged", has('app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True)', "CORS"))
check("express cors origin:true + credentials flagged", has("app.use(cors({ credentials: true, origin: true }))", "CORS"))
check("cors: no FP on listed origin + credentials", not has('app.add_middleware(CORSMiddleware, allow_origins=["https://app.example.com"], allow_credentials=True)', "CORS"))
check("cors: no FP on * without credentials", not has('app.add_middleware(CORSMiddleware, allow_origins=["*"])', "CORS"))
PY
)
while IFS= read -r line; do
  [ -z "$line" ] && continue
  begin_test "${line#* }"
  case "$line" in PASS*) pass ;; *) fail "$line" ;; esac
done <<< "$OUT"

report
