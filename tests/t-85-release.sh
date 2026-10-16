#!/usr/bin/env bash
# CHANGELOG.md shape and tools/check-release-bump.sh, driven through temp git repos.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_CL=$'# Changelog\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst.\n'

# mkrel <name> <base-changelog|-> <branch-changelog|-> <touch: y=skill file, a=agents file, n=other>
# base/branch "-" means no CHANGELOG.md on that side
mkrel() {
  local r="$TMP/$1"
  mkdir -p "$r/tools" "$r/skills/openspec-orchestrator"
  git init -q -b main "$r"
  cp tools/check-release-bump.sh "$r/tools/"
  echo v1 > "$r/skills/openspec-orchestrator/f"
  [ "$2" = "-" ] || printf '%s' "$2" > "$r/CHANGELOG.md"
  [ "${BASE_REL:-}" = "" ] || { printf '%s' "$BASE_REL" > "$r/skills/openspec-orchestrator/releases.json"; }
  git -C "$r" add -A && git -C "$r" commit -qm base
  git -C "$r" checkout -qb work
  if [ "$3" = "-" ]; then git -C "$r" rm -q --cached CHANGELOG.md 2>/dev/null || true; rm -f "$r/CHANGELOG.md"
  else printf '%s' "$3" > "$r/CHANGELOG.md"; fi
  case "$4" in
    y) echo v2 > "$r/skills/openspec-orchestrator/f" ;;
    a) mkdir -p "$r/agents/x"; echo v2 > "$r/agents/x/AGENT.md" ;;
    *) echo x > "$r/other" ;;
  esac
  [ -z "${BRANCH_RM_REL:-}" ] || git -C "$r" rm -q skills/openspec-orchestrator/releases.json
  git -C "$r" add -A && git -C "$r" commit -qm work
  echo "$r"
}
bump() { (cd "$1" && tools/check-release-bump.sh main); }

r="$(mkrel one "$BASE_CL" $'# Changelog\n\n## 1.2.0\n\nThird.\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst.\n' y)"
check_line "one new Release passes and prints it" "1.2.0" bump "$r"
check_out "one new Release exits 0 with message" "1.2.0" bump "$r"

r="$(mkrel none "$BASE_CL" "$BASE_CL" y)"
check_fails "no new Release fails" bump "$r"
check_err "no new Release says exactly one was expected" "expected exactly one new Release, found 0" bump "$r"
check_err "no new Release names CHANGELOG.md" "CHANGELOG.md" bump "$r"
check_not "no legacy bump hint in errors" "atl""as" bump "$r"

r="$(mkrel two "$BASE_CL" $'# Changelog\n\n## 1.3.0\n\nFourth.\n\n## 1.2.0\n\nThird.\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst.\n' y)"
check_fails "two new Releases fail" bump "$r"
check_err "two new Releases say exactly one" "exactly one" bump "$r"

r="$(mkrel below "$BASE_CL" $'# Changelog\n\n## 1.1.0\n\nSecond.\n\n## 1.0.1\n\nPatch.\n\n## 1.0.0\n\nFirst.\n' y)"
check_fails "Release not above the newest fails" bump "$r"
check_err "not-above names both versions" "1.0.1 is not above 1.1.0" bump "$r"

r="$(mkrel edited "$BASE_CL" $'# Changelog\n\n## 1.2.0\n\nThird.\n\n## 1.1.0\n\nSecond, edited.\n\n## 1.0.0\n\nFirst.\n' y)"
check_fails "edited earlier Release fails" bump "$r"
check_err "edited Release names the version" "1.1.0" bump "$r"

r="$(mkrel agentsonly "$BASE_CL" "$BASE_CL" a)"
check_fails "agents-only change without a Release fails" bump "$r"
check_err "agents-only change says exactly one was expected" "found 0" bump "$r"

r="$(mkrel badheading "$BASE_CL" $'# Changelog\n\n## 1.2.0 (2026-10-16)\n\nThird.\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst.\n' y)"
check_fails "malformed heading fails" bump "$r"
check_err "malformed heading is named" "## 1.2.0 (2026-10-16)" bump "$r"

r="$(mkrel noninstalled "$BASE_CL" "$BASE_CL" n)"
check_out "change outside installed files needs no Release" "no bump required" bump "$r"

BASE_REL='{"1.0.0": "First."}'
r="$(BRANCH_RM_REL=1 mkrel fallback - $'# Changelog\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst.\n' y)"
check_line "base with releases.json only: verbatim passes" "1.1.0" bump "$r"
r="$(BRANCH_RM_REL=1 mkrel fallbackalt - $'# Changelog\n\n## 1.1.0\n\nSecond.\n\n## 1.0.0\n\nFirst, altered.\n' y)"
check_fails "base with releases.json only: altered text fails" bump "$r"
BASE_REL=

# static: the real CHANGELOG.md
check "CHANGELOG.md line 1 is # Changelog" test "$(head -n1 CHANGELOG.md)" = "# Changelog"
check "CHANGELOG.md has a 3.0.0 heading" grep -qx '## 3.0.0' CHANGELOG.md
check "CHANGELOG.md has at least 22 headings, descending, one undated paragraph each" python3 -I - <<'PY'
import re, sys
t = open("CHANGELOG.md", encoding="utf-8").read().split("\n")
assert t[0] == "# Changelog"
heads = [i for i, l in enumerate(t) if l.startswith("## ")]
assert len(heads) >= 22, len(heads)
vers = []
for n, i in enumerate(heads):
    m = re.fullmatch(r"## (\d+)\.(\d+)\.(\d+)", t[i]); assert m, t[i]
    vers.append(tuple(map(int, m.groups())))
    end = heads[n + 1] if n + 1 < len(heads) else len(t)
    body = [l for l in t[i + 1:end] if l.strip()]
    assert len(body) == 1, (t[i], len(body))
assert all(a > b for a, b in zip(vers, vers[1:]))
PY
sec3() { awk '/^## 3\.0\.0$/{f=1;next} /^## /{f=0} f' CHANGELOG.md; }
check_out "3.0.0 names the opencode reinstall" "tools/install.sh --tool opencode" sec3
check_out "3.0.0 names the old link suffix" "-opencode.md" sec3

check "releases.json is gone" test ! -e skills/openspec-orchestrator/releases.json
check "nothing under the skill names releases.json" test -z "$(grep -rl releases.json skills/openspec-orchestrator || true)"
check "ci.yml runs the release check on pull requests" grep -qF 'tools/check-release-bump.sh "origin/${{ github.base_ref }}"' .github/workflows/ci.yml
check "ci.yml guards the step to pull_request" grep -qF "github.event_name == 'pull_request'" .github/workflows/ci.yml

finish
