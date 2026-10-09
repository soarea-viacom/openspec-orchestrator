#!/usr/bin/env bash
# Fails when HEAD changes what Atlas installs without exactly one new
# releases.json entry against <base-ref>. Usage: check-release-bump.sh origin/main
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
base="${1:?usage: $0 <base-ref>}"
REL=skills/openspec-orchestrator/releases.json
mb="$(git merge-base "$base" HEAD)"

# releases.json is itself installed, so editing it alone still needs a valid history.
changed="$(git diff --name-only "$mb" HEAD -- skills/openspec-orchestrator agents)"
[ -n "$changed" ] || { echo "no installed files changed; no bump required"; exit 0; }

python3 - "$REL" <(git show "$mb:$REL") <<'EOF'
import json, sys
new = json.load(open(sys.argv[1], encoding="utf-8"))
old = json.load(open(sys.argv[2], encoding="utf-8"))
ver = lambda v: tuple(int(p) for p in v.split("."))
added = [k for k in new if k not in old]
errs = [f"entry {k} was edited or removed" for k in old if new.get(k) != old[k]]
if len(added) != 1:
    errs.append(f"expected exactly one new version, found {len(added)}: {added}")
elif ver(added[0]) <= max(map(ver, old)):
    errs.append(f"new version {added[0]} is not above {'.'.join(map(str, max(map(ver, old))))}")
if errs:
    print("releases.json: " + "; ".join(errs) + " — run atlas bump against main", file=sys.stderr)
    sys.exit(1)
print(f"releases.json bumped to {added[0]}")
EOF
