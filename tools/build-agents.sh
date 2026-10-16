#!/usr/bin/env bash
# Generates agents/<tool>/openspec-<role>-<tier>/AGENT.md from the engine's
# role prompts. The role prompt is the single source; the agent file adds
# only what a prompt cannot carry: the tier's model, effort and the tool
# allowlist. tests/run.sh fails when the two drift, so run this after
# editing scripts/roles/*.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROLES=skills/openspec-orchestrator/scripts/roles
# role:effort:tools:description — checkers get no Edit (they write one
# report file, so they are not readonly either), writers get Edit; nobody
# gets Agent (no nesting: the orchestrator owns dispatch). The description is stated here, not cut
# from the prompt's first line, which carries anchors and punctuation.
TABLE='proposer:high:Read, Write, Edit, Bash, Grep, Glob:Propose — drafts the delta spec, seam list and Guardrails
critic:high:Read, Write, Bash, Grep, Glob:Proposal critic — fresh read of a draft against the request, glossary and ADRs
verifier:high:Read, Write, Bash, Grep, Glob:Verify — grades the committed change against the proposal and its Guardrails
unit-critic:medium:Read, Write, Bash, Grep, Glob:Unit critic — fresh read of one green unit, checks first, then code, then screenshot
worker:medium:Read, Write, Edit, Bash, Grep, Glob:Worker — unit worker, fixer, sweep, merge-conflict agent or split, confined to its file list'
# Copilot takes a priority list, so it carries the fallback too;
# tools/install.sh converts the Codex frontmatter to TOML.
ROLE_SRC="$ROLES"
source skills/openspec-orchestrator/scripts/lib.sh
TOOLS="claude-code cursor copilot codex opencode"
TIER_LIST="mechanical standard deep max"
rm -rf agents
while IFS=: read -r role effort tools desc; do
  for tool in $TOOLS; do
    for tier in $TIER_LIST; do
      m1="$(model_pick "$tool" "$tier" 1)"; m2="$(model_pick "$tool" "$tier" 2)"
      name="openspec-$role-$tier"
      out="agents/$tool/$name/AGENT.md"
      mkdir -p "$(dirname "$out")"
      {
        printf -- '---\nname: %s\ndescription: %s, %s tier. Dispatched by the openspec-orchestrator engine; never invoke directly.\n' "$name" "$desc" "$tier"
        case "$tool" in
          claude-code) printf 'model: %s\ntools: %s\neffort: %s\n' "$m1" "$tools" "$effort" ;;
          cursor) printf 'model: %s\n' "$m1" ;;
          copilot) printf "model: ['%s', '%s']\n" "$m1" "$m2" ;;
          codex) printf 'model: %s\neffort: %s\n' "$m1" "$effort" ;;
          opencode) printf 'mode: subagent\nmodel: %s\n' "$m1" ;;
        esac
        printf -- '---\n'
        cat "$ROLE_SRC/$role.md"
      } > "$out"
    done
  done
done <<<"$TABLE"
echo "wrote $(find agents -name AGENT.md | wc -l | tr -d ' ') agents"
