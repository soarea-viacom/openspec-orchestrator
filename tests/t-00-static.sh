#!/usr/bin/env bash
# Static checks: syntax, dead code, role prompts and agents, generated files, install, docs.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# syntax first: a parse error would make every check below fail for the
# same reason, so stop here instead of drowning it in noise.
check "run-change parses" bash -n $SKILL/scripts/run-change
check "lib.sh parses" bash -n $SKILL/scripts/lib.sh
for f in tests/run.sh tests/lib.sh tests/t-*.sh; do check "$f parses" bash -n "$f"; done
[ "$fails" -eq 0 ] || { echo "syntax errors — not running behavior tests"; exit 1; }

# dead-code pass (the bash stand-in for knip): every function defined in the
# engine must be referenced somewhere other than its own definition.
dead=""
for fn in $(grep -ohE '^[a-z_]+\(\)' $SKILL/scripts/lib.sh $SKILL/scripts/run-change | tr -d '()'); do
  if [ "$(grep -hE "\b$fn\b" $SKILL/scripts/lib.sh $SKILL/scripts/run-change tests/*.sh | grep -cvE "^$fn\(\)")" -eq 0 ]; then
    dead="$dead $fn"
  fi
done
check "no engine function without a caller${dead:+ (dead:$dead)}" test -z "$dead"

# engine role prompts: $SKILL/scripts/roles/<role>.md. The anchor assignment lives
# only here and in the spec; nothing at runtime reads it.
check "$SKILL/scripts/roles holds exactly the five role files" test "$(LC_ALL=C ls $SKILL/scripts/roles 2>/dev/null | tr '\n' ' ')" = "critic.md proposer.md unit-critic.md verifier.md worker.md "
ANCHORS='seam|fresh read|generator/checker split|smallest tier that can be wrong safely|turns, not tokens|the engine records, the worker never asserts'
ROLE_ANCHORS='proposer:seam|generator/checker split|smallest tier that can be wrong safely|turns, not tokens
critic:fresh read|generator/checker split|seam|turns, not tokens
worker:seam|the engine records, the worker never asserts|turns, not tokens
unit-critic:fresh read|generator/checker split|the engine records, the worker never asserts|turns, not tokens
verifier:fresh read|generator/checker split|seam|the engine records, the worker never asserts|turns, not tokens'
ROLE_INVARIANTS='proposer:--store <slug>
proposer:seams "<seam>=<file>,<file>;<seam>=<file>"
proposer:openspec/CONTEXT.md
proposer:openspec/adr/
proposer:never edit
proposer:implied baseline
critic:implied baseline
verifier:implied baseline
critic:never the generator'"'"'s transcript
critic:openspec/CONTEXT.md
critic:openspec/adr/
critic:names the ADR it supersedes
critic:non-canonical term
verifier:never the generator'"'"'s transcript
worker:`git add -- <files>`, never `-A`
worker:unit iterate
worker:advisor request --unit <u>
worker:fail_reason spec
unit-critic:never the generator'"'"'s transcript
unit-critic:screenshot'
anchor_n() { # anchor_n <anchor> <text> -> occurrences; seam as a whole word, not the <seam> placeholder
  if [ "$1" = seam ]; then printf '%s\n' "$2" | sed 's/<seam>//g' | { grep -ow seam || true; } | wc -l | tr -d ' '
  else printf '%s\n' "$2" | { grep -oF -- "$1" || true; } | wc -l | tr -d ' '; fi
}
check "anchor count: seam skips the <seam> placeholder" test "$(anchor_n seam 'set seams "<seam>=a" per seam')" = 1
while IFS=: read -r role assigned; do
  f="$SKILL/scripts/roles/$role.md"
  text=""; [ -f "$f" ] && text="$(cat "$f")"
  first="$(printf '%s\n' "$text" | sed -n 1p)"; last="$(printf '%s\n' "$text" | sed -n '$p')"
  check "role prompt $role: at most 20 lines, no heading" bash -c "[ -f '$f' ] && [ \$(wc -l < '$f') -le 20 ] && ! grep -q '^#' '$f'"
  IFS='|' read -ra all <<<"$ANCHORS"
  for a in "${all[@]}"; do
    case "|$assigned|" in
      *"|$a|"*) check "role prompt $role: '$a' twice, once on line 1 and once on the last line" \
        test "$(anchor_n "$a" "$text") $(anchor_n "$a" "$first") $(anchor_n "$a" "$last")" = "2 1 1" ;;
      *) check "role prompt $role: no '$a'" test "$(anchor_n "$a" "$text")" = 0 ;;
    esac
  done
done <<<"$ROLE_ANCHORS"
while IFS=: read -r role s; do
  check "role prompt $role quotes: $s" grep -qF -- "$s" "$SKILL/scripts/roles/$role.md"
done <<<"$ROLE_INVARIANTS"

# role agents: agents/openspec-<role>/AGENT.md = frontmatter + the role prompt verbatim
AGENT_EFFORT='proposer:high
critic:high
verifier:high
unit-critic:medium
worker:medium'
while IFS=: read -r role eff; do
  af="agents/openspec-$role/AGENT.md"
  check "agent file exists for $role" test -f "$af"
  check "agent $role names itself openspec-$role" grep -qx "name: openspec-$role" "$af"
  check "agent $role runs at effort $eff" grep -qx "effort: $eff" "$af"
  check "agent $role body is the role prompt verbatim" bash -c "diff <(awk 'c>=2{print} /^---$/{c++}' '$af') '$SKILL/scripts/roles/$role.md'"
  check_fails "agent $role grants no Agent tool" grep -E '^tools:.*\bAgent\b' "$af"
done <<<"$AGENT_EFFORT"
for role in critic verifier unit-critic; do
  check_fails "checker agent $role has no Edit tool" grep -E '^tools:.*\bEdit\b' agents/openspec-$role/AGENT.md
done
check "catalog lists the five role agents" bash -c "[ \$(python3 -c \"import json;print(sum(not k.endswith(('-claude-code','-cursor','-copilot','-codex','-opencode')) for k in json.load(open('atlas-catalog.json'))['agents']))\") -eq 5 ]"

for tool in claude-code cursor copilot codex opencode; do
  for tier in mechanical standard deep max; do
    check "catalogue: $tool $tier has a default and a different fallback" bash -c "source $SKILL/scripts/lib.sh && a=\$(model_pick $tool $tier 1) && b=\$(model_pick $tool $tier 2) && [ -n \"\$a\" ] && [ \"\$a\" != \"\$b\" ]"
  done
done

# per-tool agents: generated, 20 per tool, model pinned to the catalogue default
h_before="$(find agents atlas-catalog.json -type f | sort | xargs shasum | shasum)"
./tools/build-agents.sh >/dev/null
check "build-agents.sh output is committed (no drift)" test "$h_before" = "$(find agents atlas-catalog.json -type f | sort | xargs shasum | shasum)"
for tool in claude-code cursor copilot codex opencode; do
  check "$tool ships 20 per-tier agents" test "$(find agents/$tool -name AGENT.md | wc -l | tr -d ' ')" = 20
done
check "claude-code critic-max pins the max default" grep -qx "model: $(bash -c "source $SKILL/scripts/lib.sh; model_pick claude-code max 1")" agents/claude-code/openspec-critic-max/AGENT.md
check "copilot agents carry a two-item model list" grep -qE "^model: \['[^']+', '[^']+'\]$" agents/copilot/openspec-worker-standard/AGENT.md
check "cursor checker agents are readonly" grep -qx "readonly: true" agents/cursor/openspec-verifier-deep/AGENT.md
check "catalog lists 100 per-tool agents" bash -c "[ \$(python3 -c \"import json;print(sum(k.endswith(('-claude-code','-cursor','-copilot','-codex','-opencode')) for k in json.load(open('atlas-catalog.json'))['agents']))\") -eq 100 ]"

# standalone install: one home, linked into each tool's dirs
IH="$TMP/install-home"
for tool in claude-code cursor copilot codex opencode; do
  check "install.sh --tool $tool succeeds" env HOME="$IH" XDG_DATA_HOME= CLAUDE_CONFIG_DIR= tools/install.sh --tool $tool
done
check "claude-code agent links into the home" test -L "$IH/.claude/agents/openspec-critic-max"
check "cursor agent is a flat .md link" test -L "$IH/.cursor/agents/openspec-critic-max.md"
check "copilot agent is a .agent.md link" test -L "$IH/.copilot/agents/openspec-critic-max.agent.md"
check "opencode uses ~/.config/opencode" test -L "$IH/.config/opencode/agents/openspec-critic-max.md"
check "skill dir links into the home" test -L "$IH/.codex/skills/openspec-orchestrator"
check "codex agents are TOML with model and effort keys" python3 -c "import tomllib,sys; d=tomllib.load(open('$IH/.codex/agents/openspec-verifier-deep.toml','rb')); sys.exit(0 if d['model']=='gpt-6-astra' and d['model_reasoning_effort']=='high' and d['developer_instructions'].startswith('You are') else 1)"
ih1="$(cd "$IH" && find . | sort | shasum)"
env HOME="$IH" XDG_DATA_HOME= tools/install.sh --tool codex >/dev/null
check "install.sh rerun changes nothing" test "$ih1" = "$(cd "$IH" && find . | sort | shasum)"
echo mine > "$IH/.cursor/agents/openspec-mine.md"
env HOME="$IH" XDG_DATA_HOME= tools/install.sh --tool cursor --uninstall
check "uninstall removes its own links" test ! -e "$IH/.cursor/agents/openspec-critic-max.md"
check "uninstall leaves files it did not install" test -f "$IH/.cursor/agents/openspec-mine.md"
check "no doc names Claude Code's Agent tool or subagent_type" bash -c "cd $SKILL && ! grep -rnE 'Agent tool|Agent call|subagent_type|Skill tool' SKILL.md AUTONOMOUS-ORCHESTRATION.md CONTEXT.md scripts/lib.sh scripts/roles ../../agents"

# =====================================================================
# docs: style-split rule and role-prompt vocabulary documented where an
# editor would look (AUTONOMOUS-ORCHESTRATION.md, CONTEXT.md, config.yaml,
# SKILL.md) — see specs/role-prompts/spec.md "Style split documented"
# =====================================================================
hr_line="$(grep -n '^## Hard rule: written for agents' $SKILL/AUTONOMOUS-ORCHESTRATION.md | sed -n 1p | cut -d: -f1)"
ro_line="$(grep -n '^### Role overlays' $SKILL/AUTONOMOUS-ORCHESTRATION.md | sed -n 1p | cut -d: -f1)"
fr_line="$(grep -n '^### Fix rounds' $SKILL/AUTONOMOUS-ORCHESTRATION.md | sed -n 1p | cut -d: -f1)"
hr_hit=""; ro_hit=""
for n in $(grep -n 'scripts/roles' $SKILL/AUTONOMOUS-ORCHESTRATION.md | cut -d: -f1); do
  [ -n "$hr_line" ] && [ "$n" -gt "$hr_line" ] && hr_hit=1
  [ -n "$ro_line" ] && [ -n "$fr_line" ] && [ "$n" -gt "$ro_line" ] && [ "$n" -lt "$fr_line" ] && ro_hit=1
done
check "$SKILL/AUTONOMOUS-ORCHESTRATION.md names scripts/roles in the Hard rule section" test -n "$hr_hit"
check "$SKILL/AUTONOMOUS-ORCHESTRATION.md names scripts/roles in the Role overlays section" test -n "$ro_hit"

check "$SKILL/CONTEXT.md defines Role prompt" bash -c "grep -qE -- '\*\*Role prompt\*\*' $SKILL/CONTEXT.md"
check "$SKILL/CONTEXT.md defines Anchor" bash -c "grep -qE -- '\*\*Anchor\*\*' $SKILL/CONTEXT.md"
anchor_start="$(grep -n -- '\*\*Anchor\*\*' $SKILL/CONTEXT.md | sed -n 1p | cut -d: -f1)"
anchor_tmp="$TMP/anchor_entry.txt"
awk -v s="${anchor_start:-0}" 'NR==s{print;started=1;next} started{ if (/^- \*\*/) exit; print }' $SKILL/CONTEXT.md > "$anchor_tmp"
while IFS= read -r lit; do
  check "$SKILL/CONTEXT.md Anchor entry names '$lit'" grep -qF -- "$lit" "$anchor_tmp"
done <<'EOF_ANCHORS'
seam
fresh read
generator/checker split
smallest tier that can be wrong safely
turns, not tokens
the engine records, the worker never asserts
EOF_ANCHORS

ctx_line="$(grep -n '^context:' openspec/config.yaml | sed -n 1p | cut -d: -f1)"
next_key_line="$(awk -v s="${ctx_line:-0}" 'NR>s && /^[a-zA-Z_]+:/{print NR; exit}' openspec/config.yaml)"
cfg_hit="$(grep -n 'scripts/roles/<role>.md' openspec/config.yaml | sed -n 1p | cut -d: -f1)"
check "openspec/config.yaml names scripts/roles/<role>.md inside the context: block" \
  bash -c "[ -n '${cfg_hit:-}' ] && [ -n '${ctx_line:-}' ] && [ -n '${next_key_line:-}' ] && [ '$cfg_hit' -gt '$ctx_line' ] && [ '$cfg_hit' -lt '$next_key_line' ]"

check "SKILL.md names at least one prompt: line" bash -c "[ \$(grep -c 'prompt:' $SKILL/SKILL.md) -ge 1 ]"

# docs: grill mode replaces /sdd:explore as the only pre-change mode —
# see specs/grill-mode/spec.md
for f in $SKILL/SKILL.md README.md atlas-catalog.json; do
  check "$f has no /sdd:explore" bash -c "[ \$(grep -c '/sdd:explore' $f) -eq 0 ]"
done
check "SKILL.md has exactly one '## Grill mode' heading" bash -c "[ \$(grep -c '^## Grill mode$' $SKILL/SKILL.md) -eq 1 ]"
check "SKILL.md has no grill-with-docs" bash -c "[ \$(grep -c 'grill-with-docs' $SKILL/SKILL.md) -eq 0 ]"

gm_start="$({ grep -n '^## Grill mode$' $SKILL/SKILL.md || true; } | sed -n 1p | cut -d: -f1)"
gm_tmp="$TMP/grill_mode_section.txt"
awk -v s="${gm_start:-0}" 'NR==s{print;started=1;next} started{ if (/^## /) exit; print }' $SKILL/SKILL.md > "$gm_tmp"
while IFS= read -r lit; do
  check "SKILL.md Grill mode section names '$lit'" grep -qF -- "$lit" "$gm_tmp"
done <<'EOF_GRILL'
Step 0
two or three approaches
grilling
domain-modeling
<root>/openspec/CONTEXT.md
<root>/openspec/adr/
docs/adr/
git status --porcelain
no message
uncommitted
sharpened request
Gate 0
EOF_GRILL

ao_start="$({ grep -n '^## Autonomous only$' $SKILL/SKILL.md || true; } | sed -n 1p | cut -d: -f1)"
ao_tmp="$TMP/autonomous_only_section.txt"
awk -v s="${ao_start:-0}" 'NR==s{print;started=1;next} started{ if (/^## /) exit; print }' $SKILL/SKILL.md > "$ao_tmp"
check "SKILL.md Autonomous only section names grill mode" grep -qF -- "grill mode" "$ao_tmp"

gr_start="$({ grep -n '^## Guardrails$' $SKILL/SKILL.md || true; } | sed -n 1p | cut -d: -f1)"
gr_tmp="$TMP/guardrails_section.txt"
awk -v s="${gr_start:-0}" 'NR>=s{print}' $SKILL/SKILL.md > "$gr_tmp"
check "SKILL.md Guardrails section names Project glossary" grep -qF -- "Project glossary" "$gr_tmp"
check "SKILL.md Guardrails section names grill mode" grep -qF -- "grill mode" "$gr_tmp"

skill_desc="$(sed -n 's/^description: //p' $SKILL/SKILL.md | sed -n 1p)"
catalog_desc="$(sed -n 's/.*"description": "\(.*\)",$/\1/p' atlas-catalog.json | sed -n 1p)"
check "SKILL.md and atlas-catalog.json descriptions are identical" test "$skill_desc" = "$catalog_desc"
case "$skill_desc" in
  *"grill mode"*) echo "ok   SKILL.md description names grill mode" ;;
  *) echo "FAIL SKILL.md description names grill mode"; fails=$((fails+1)) ;;
esac

desc_full="$({ grep '^description: ' $SKILL/SKILL.md || true; } | sed -n 1p)"
colon_count="$(printf '%s\n' "$desc_full" | { grep -o ': ' || true; } | wc -l | tr -d ' ')"
hash_count="$(printf '%s\n' "$desc_full" | { grep -o ' #' || true; } | wc -l | tr -d ' ')"
check "SKILL.md description: line has exactly one ': '" test "$colon_count" = 1
check "SKILL.md description: line has no ' #'" test "$hash_count" = 0

check "CONTEXT.md defines Project glossary" grep -qF -- '**Project glossary**' $SKILL/CONTEXT.md
check "CONTEXT.md defines Implied baseline" grep -qF -- '**Implied baseline**' $SKILL/CONTEXT.md
check "SKILL.md grill section never asks the obvious" grep -qF -- 'Never ask the obvious' $SKILL/SKILL.md
check "AUTONOMOUS-ORCHESTRATION.md fidelity standard names the implied baseline" bash -c "grep -A4 -- '- \*\*Fidelity\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md | grep -q 'implied baseline'"
check "CONTEXT.md defines Grill mode" grep -qF -- '**Grill mode**' $SKILL/CONTEXT.md
cic_start="$({ grep -n -- '\*\*Checker input contract\*\*' $SKILL/CONTEXT.md || true; } | sed -n 1p | cut -d: -f1)"
cic_tmp="$TMP/checker_input_contract.txt"
awk -v s="${cic_start:-0}" 'NR==s{print;started=1;next} started{ if (/^- \*\*/) exit; print }' $SKILL/CONTEXT.md > "$cic_tmp"
check "CONTEXT.md Checker input contract entry names Project glossary" grep -qF -- "Project glossary" "$cic_tmp"

ctx2_line="$(grep -n '^context:' openspec/config.yaml | sed -n 1p | cut -d: -f1)"
ctx2_next="$(awk -v s="${ctx2_line:-0}" 'NR>s && /^[a-zA-Z_]+:/{print NR; exit}' openspec/config.yaml)"
ctx2_hit="$({ grep -n 'openspec/CONTEXT.md' openspec/config.yaml || true; } | sed -n 1p | cut -d: -f1)"
check "openspec/config.yaml names openspec/CONTEXT.md inside the context: block" \
  bash -c "[ -n '${ctx2_hit:-}' ] && [ -n '${ctx2_line:-}' ] && [ -n '${ctx2_next:-}' ] && [ '$ctx2_hit' -gt '$ctx2_line' ] && [ '$ctx2_hit' -lt '$ctx2_next' ]"

check "README names /openspec-orchestrator grill" grep -qF -- "/openspec-orchestrator grill" README.md
readme_ctx_row="$({ grep -F '[`CONTEXT.md`]' README.md || true; } | sed -n 1p)"
case "$readme_ctx_row" in
  *"openspec/CONTEXT.md"*) echo "ok   README CONTEXT.md layout row names openspec/CONTEXT.md" ;;
  *) echo "FAIL README CONTEXT.md layout row names openspec/CONTEXT.md"; fails=$((fails+1)) ;;
esac

crit_start="$({ grep -n -- '\*\*Critique\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md || true; } | sed -n 1p | cut -d: -f1)"
crit_end="$({ grep -n -- 'The critic writes a \*\*critique report\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md || true; } | sed -n 1p | cut -d: -f1)"
crit_tmp="$TMP/critique_contract.txt"
awk -v s="${crit_start:-0}" -v e="${crit_end:-0}" 'NR>=s && NR<=e' $SKILL/AUTONOMOUS-ORCHESTRATION.md > "$crit_tmp"
check "AUTONOMOUS-ORCHESTRATION.md Critique input contract names openspec/CONTEXT.md" grep -qF -- "openspec/CONTEXT.md" "$crit_tmp"
check "AUTONOMOUS-ORCHESTRATION.md Critique input contract names openspec/adr/" grep -qF -- "openspec/adr/" "$crit_tmp"

finish
