#!/usr/bin/env bash
# Generates agents/openspec-<role>/AGENT.md from the engine's role prompts.
# The role prompt is the single source; the agent file adds only what a
# prompt cannot carry: effort and the tool allowlist. tests/run.sh fails
# when the two drift, so run this after editing scripts/roles/*.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROLES=skills/openspec-orchestrator/scripts/roles
# role:effort:tools — checkers get no Edit (they write one report file),
# writers get Edit; nobody gets Agent (no nesting: the orchestrator owns dispatch).
TABLE='proposer:high:Read, Write, Edit, Bash, Grep, Glob
critic:high:Read, Write, Bash, Grep, Glob
verifier:high:Read, Write, Bash, Grep, Glob
unit-critic:medium:Read, Write, Bash, Grep, Glob
worker:medium:Read, Write, Edit, Bash, Grep, Glob'
while IFS=: read -r role effort tools; do
  src="$ROLES/$role.md"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  desc="$(sed -n 1p "$src" | sed -E 's/^You are ([^:]+):.*/\1/')"
  out="agents/openspec-$role/AGENT.md"
  mkdir -p "$(dirname "$out")"
  {
    printf -- '---\nname: openspec-%s\ndescription: %s. Dispatched by the openspec-orchestrator engine with the tier model on the Agent call; never invoke directly.\ntools: %s\neffort: %s\n---\n' "$role" "$desc" "$tools" "$effort"
    cat "$src"
  } > "$out"
  echo "wrote $out ($effort)"
done <<<"$TABLE"
