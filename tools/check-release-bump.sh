#!/usr/bin/env bash
# Fails when HEAD changes installed files without exactly one new CHANGELOG.md
# Release against <base-ref>. Usage: check-release-bump.sh origin/main
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
base="${1:?usage: $0 <base-ref>}"
mb="$(git merge-base "$base" HEAD)"

changed="$(git diff --name-only "$mb" HEAD -- skills/openspec-orchestrator agents)"
[ -n "$changed" ] || { echo "no installed files changed; no bump required"; exit 0; }

new="$(git show HEAD:CHANGELOG.md)"
# A base that predates CHANGELOG.md keeps its Releases in releases.json.
if old="$(git show "$mb:CHANGELOG.md" 2>/dev/null)"; then oldkind=md
else old="$(git show "$mb:skills/openspec-orchestrator/releases.json")"; oldkind=json; fi

NEW="$new" OLD="$old" OLDKIND="$oldkind" python3 - <<'PY'
import json, os, re, sys

def parse_md(text):
    out, cur = {}, None
    for line in text.split("\n"):
        m = re.fullmatch(r"## (\d+\.\d+\.\d+)", line.rstrip())
        if m:
            cur = m.group(1); out[cur] = []
        elif line.startswith("## "):
            print(f"CHANGELOG.md: malformed Release heading: {line}", file=sys.stderr)
            sys.exit(1)
        elif cur and line.strip():
            out[cur].append(line.strip())
    return {k: "\n".join(v) for k, v in out.items()}

ver = lambda v: tuple(int(p) for p in v.split("."))
new = parse_md(os.environ["NEW"])
old = json.loads(os.environ["OLD"]) if os.environ["OLDKIND"] == "json" else parse_md(os.environ["OLD"])
added = [k for k in new if k not in old]
errs = [f"Release {k} was edited or removed" for k in old if new.get(k) != old[k]]
top = ".".join(map(str, max(map(ver, old)))) if old else None
if len(added) != 1:
    errs.append(f"expected exactly one new Release, found {len(added)}: {added}")
elif old and ver(added[0]) <= max(map(ver, old)):
    errs.append(f"new Release {added[0]} is not above {top}")
if errs:
    print("CHANGELOG.md: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
print(added[0])
PY
