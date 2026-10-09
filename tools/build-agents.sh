#!/usr/bin/env bash
# Generates agents/openspec-<role>/AGENT.md from the engine's role prompts.
# The role prompt is the single source; the agent file adds only what a
# prompt cannot carry: effort and the tool allowlist. tests/run.sh fails
# when the two drift, so run this after editing scripts/roles/*.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROLES=skills/openspec-orchestrator/scripts/roles
# role:effort:tools:description — checkers get no Edit (they write one
# report file), writers get Edit; nobody gets Agent (no nesting: the
# orchestrator owns dispatch). The description is stated here, not cut
# from the prompt's first line, which carries anchors and punctuation.
TABLE='proposer:high:Read, Write, Edit, Bash, Grep, Glob:Propose — drafts the delta spec, seam list and Guardrails
critic:high:Read, Write, Bash, Grep, Glob:Proposal critic — fresh read of a draft against the request, glossary and ADRs
verifier:high:Read, Write, Bash, Grep, Glob:Verify — grades the committed change against the proposal and its Guardrails
unit-critic:medium:Read, Write, Bash, Grep, Glob:Unit critic — fresh read of one green unit, checks first, then code, then screenshot
worker:medium:Read, Write, Edit, Bash, Grep, Glob:Worker — unit worker, fixer, sweep, merge-conflict agent or split, confined to its file list'
while IFS=: read -r role effort tools desc; do
  src="$ROLES/$role.md"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  out="agents/openspec-$role/AGENT.md"
  mkdir -p "$(dirname "$out")"
  {
    printf -- '---\nname: openspec-%s\ndescription: %s. Dispatched by the openspec-orchestrator engine with the tier model on the dispatch; never invoke directly.\ntools: %s\neffort: %s\n---\n' "$role" "$desc" "$tools" "$effort"
    cat "$src"
  } > "$out"
  echo "wrote $out ($effort)"
done <<<"$TABLE"
