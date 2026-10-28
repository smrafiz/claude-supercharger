#!/usr/bin/env bash
# Disk, partition and power spellings from wintermeyer/heinzel's guard test corpus
# (.claude/hooks/guard-taboos-test.sh, re-audited 2026-10-27). Each DENY case passed
# safety.sh before this file existed; each ALLOW case is a read-only or routine form.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== heinzel disk/power spellings ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
D = '/dev/'
cases = [
    # a disk written without dd
    ("tee onto a disk", "tee " + D + "sda < disk.img", "DENY"),
    ("tee with a second target", "tee /tmp/copy " + D + "sdb < img", "DENY"),
    ("redirect onto a disk", "dd if=disk.img > " + D + "nvme0n1", "DENY"),
    ("cp onto a disk", "cp image.iso " + D + "sdb", "DENY"),
    ("download onto a disk", "curl -fsS -o " + D + "sdb https://example.com/img", "DENY"),
    ("python opens a disk", "python3 -c \"open('" + D + "sda','wb').write(b'0')\"", "DENY"),
    # partition and disk tools
    ("sgdisk -e", "sgdisk -e " + D + "sda", "DENY"),
    ("sgdisk --replicate", "sgdisk --replicate=" + D + "sdb " + D + "sda", "DENY"),
    ("parted toggle", "parted " + D + "sda toggle 1 boot", "DENY"),
    ("gpt destroy", "gpt destroy " + D + "da0", "DENY"),
    ("growpart", "growpart " + D + "sda 1", "DENY"),
    ("nvme write-zeroes", "nvme write-zeroes " + D + "nvme0n1", "DENY"),
    ("badblocks -w, flag first", "badblocks -w " + D + "sda", "DENY"),
    ("sfdisk --delete", "sfdisk --delete " + D + "sda", "DENY"),
    # power
    ("systemctl poweroff", "systemctl power" + "off", "DENY"),
    ("telinit 0", "tel" + "init 0", "DENY"),
    # still allowed
    ("cp FROM a disk", "cp " + D + "sda backup.img", "ALLOW"),
    ("redirect to /dev/null", "make test > " + D + "null 2>&1", "ALLOW"),
    ("tee a log", "npm test | tee build.log", "ALLOW"),
    ("parted print", "parted " + D + "sda print", "ALLOW"),
    ("sgdisk -p", "sgdisk -p " + D + "sda", "ALLOW"),
    ("badblocks read-only", "badblocks -sv " + D + "sda", "ALLOW"),
    ("shutdown -c cancels", "shut" + "down -c", "ALLOW"),
    ("visudo -c checks syntax", "vi" + "sudo -c", "ALLOW"),
    ("systemctl status", "systemctl status nginx", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  st=$(mktemp -d)
  out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/safety.sh" < "$TMP/p$i.json" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) got=DENY ;; *'"permissionDecision":"ask"'*) got=ASK ;; *) got=ALLOW ;; esac
  begin_test "heinzel: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

rm -rf "$TMP"
report
